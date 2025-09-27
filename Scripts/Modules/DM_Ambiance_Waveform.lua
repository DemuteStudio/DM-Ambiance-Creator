--[[
@version 1.0
@noindex
--]]

local Waveform = {}
local globals = {}

-- Helper function for soft clipping (replaces math.tanh which may not be available)
local function softClip(value, limit)
    limit = limit or 1.0
    if value > limit then
        return limit
    elseif value < -limit then
        return -limit
    else
        -- Smooth transition near limits
        local absVal = math.abs(value)
        if absVal > limit * 0.9 then
            local x = (absVal - limit * 0.9) / (limit * 0.1)
            local factor = 1 - (x * x * 0.1)  -- Quadratic smoothing
            return (value / absVal) * (limit * 0.9 + (limit * 0.1) * factor)
        end
        return value
    end
end

-- Initialize the module with global variables from the main script
function Waveform.initModule(g)
    if not g then
        error("Waveform.initModule: globals parameter is required")
    end
    globals = g

    -- Initialize waveform-related globals
    globals.waveformCache = {}      -- Cache waveform data: {[filePath] = {peaks, length}}
    globals.audioPreview = {         -- Audio preview state
        isPlaying = false,
        currentFile = nil,
        startTime = 0,
        position = 0,
        volume = 0.7
    }

    -- Initialize waveform areas/regions
    globals.waveformAreas = {}       -- Store areas/regions: {[filePath] = {areas}}
    globals.waveformAreaDrag = {     -- Track area creation/editing state
        isDragging = false,
        isResizing = false,
        startX = 0,
        endX = 0,
        resizeEdge = nil,            -- 'left' or 'right'
        resizeAreaIndex = nil,
        currentFile = nil
    }
end

-- Create a placeholder waveform when file is not available
function Waveform.createPlaceholderWaveform(width)
    width = math.floor(tonumber(width) or 400)
    if width <= 0 then width = 400 end

    local peaks = {
        min = {},
        max = {},
        rms = {}
    }

    -- Create a simple flat line
    for i = 1, width do
        peaks.min[i] = 0
        peaks.max[i] = 0
        peaks.rms[i] = 0
    end

    return {
        peaks = peaks,
        length = 1,
        numChannels = 1,
        samplerate = 44100,
        isPlaceholder = true
    }
end

-- Get waveform data with automatic .reapeaks generation if needed
function Waveform.getWaveformData(filePath, width, options)
    -- Validate inputs
    if not filePath or filePath == "" then
        return Waveform.createPlaceholderWaveform(width)
    end

    width = math.floor(tonumber(width) or 400)
    if width <= 0 then width = 400 end

    options = options or {}

    -- REDIRECT TO NEW FUNCTION FOR EDITED ITEMS
    if options.startOffset and options.displayLength then
        return Waveform.getWaveformDataForEditedItem(filePath, width, options)
    end

    local useLogScale = options.useLogScale ~= false  -- Use logarithmic scaling for quiet sounds (default true)
    local amplifyQuiet = options.amplifyQuiet or 3.0  -- Amplification factor for quiet sounds

    -- Include startOffset and displayLength in cache key to handle edited portions correctly
    local cacheKey = string.format("%s_%d_%.3f_%.3f",
        filePath,
        width,
        options.startOffset or 0,
        options.displayLength or -1)

    -- Check cache first - but verify peaks exist too
    if globals.waveformCache[cacheKey] and not globals.waveformCache[cacheKey].isPlaceholder then
        -- Also verify the peaks data is not empty
        local peaks = globals.waveformCache[cacheKey].peaks
        if peaks and peaks.max and #peaks.max > 0 then
            local hasData = false
            for i = 1, math.min(10, #peaks.max) do
                if math.abs(peaks.max[i] or 0) > 0.001 then
                    hasData = true
                    break
                end
            end
            if hasData then
                return globals.waveformCache[cacheKey]
            end
        end
        -- Cache exists but is empty, clear it
        globals.waveformCache[cacheKey] = nil
    end

    -- Check if file exists
    local file = io.open(filePath, "r")
    if not file then
        return Waveform.createPlaceholderWaveform(width)
    end
    file:close()

    -- Create PCM source
    local source = reaper.PCM_Source_CreateFromFile(filePath)
    if not source then
        return Waveform.createPlaceholderWaveform(width)
    end

    -- Get source info
    local samplerate = math.floor(reaper.GetMediaSourceSampleRate(source) or 44100)
    local totalLength = reaper.GetMediaSourceLength(source, false) or 1
    local numChannels = math.floor(reaper.GetMediaSourceNumChannels(source) or 1)

    -- Use startOffset and displayLength from options for the EDITED portion
    local startOffset = options.startOffset or 0
    local length = options.displayLength or (totalLength - startOffset)

    -- Ensure we don't exceed file boundaries
    length = math.min(length, totalLength - startOffset)

    -- Debug: Confirm we're using the right portion (commented for production)
    -- reaper.ShowConsoleMsg(string.format("\n[Waveform] Processing edited item:\n"))
    -- reaper.ShowConsoleMsg(string.format("  File: %s\n", filePath))
    -- reaper.ShowConsoleMsg(string.format("  Total file length: %.3fs\n", totalLength))
    -- reaper.ShowConsoleMsg(string.format("  Item start offset: %.3fs\n", startOffset))
    -- reaper.ShowConsoleMsg(string.format("  Item length: %.3fs\n", length))
    -- reaper.ShowConsoleMsg(string.format("  Item end position: %.3fs\n", startOffset + length))

    -- Validate offset doesn't exceed file length
    if startOffset >= totalLength then
        startOffset = 0
        length = math.min(length, totalLength)
    end

    -- Ensure .reapeaks file exists
    local peaksFilePath = filePath .. ".reapeaks"
    local peaksFileExists = io.open(peaksFilePath, "rb")
    local needsRebuild = false

    if not peaksFileExists then
        needsRebuild = true
    else
        -- Check if file is too small (likely corrupted)
        local fileSize = peaksFileExists:seek("end")
        peaksFileExists:close()
        if fileSize < 100 then  -- .reapeaks files should be bigger than 100 bytes
            os.remove(peaksFilePath)
            needsRebuild = true
        end
    end

    if needsRebuild then
        -- Build peaks file
        reaper.PCM_Source_BuildPeaks(source, 0)  -- mode 0 = build now
    end

    -- Create peaks array
    local peaks = {
        min = {},
        max = {},
        rms = {}
    }

    -- Use temporary item to get peaks (most reliable method)
    local tempTrack = reaper.GetTrack(0, 0) or (function()
        reaper.InsertTrackAtIndex(0, false)
        return reaper.GetTrack(0, 0)
    end)()

    if not tempTrack then
        reaper.PCM_Source_Destroy(source)
        return Waveform.createPlaceholderWaveform(width)
    end

    -- Create temporary item
    local tempItem = reaper.AddMediaItemToTrack(tempTrack)
    if not tempItem then
        reaper.PCM_Source_Destroy(source)
        return Waveform.createPlaceholderWaveform(width)
    end

    -- Set the item to match the EDITED portion
    reaper.SetMediaItemInfo_Value(tempItem, "D_POSITION", 0)
    reaper.SetMediaItemInfo_Value(tempItem, "D_LENGTH", length)  -- Use edited length

    local tempTake = reaper.AddTakeToMediaItem(tempItem)
    if not tempTake then
        reaper.DeleteTrackMediaItem(tempTrack, tempItem)
        reaper.PCM_Source_Destroy(source)
        return Waveform.createPlaceholderWaveform(width)
    end

    -- Set source (REAPER takes ownership after this)
    reaper.SetMediaItemTake_Source(tempTake, source)

    -- CRITICAL: Set the take's offset to match where the edited portion starts in the source
    reaper.SetMediaItemTakeInfo_Value(tempTake, "D_STARTOFFS", startOffset)

    -- Apply changes to item
    reaper.UpdateItemInProject(tempItem)

    -- Build peaks for the edited portion
    reaper.SetMediaItemSelected(tempItem, true)
    reaper.Main_OnCommand(40047, 0) -- Build peaks for selected items

    -- Small delay to let peaks build
    local startTime = reaper.time_precise()
    while reaper.time_precise() - startTime < 0.05 do
        -- wait
    end

    -- Read actual channel count instead of forcing mono
    local n_channels = numChannels  -- Use actual channel count

    -- Calculate how many samples we actually need for the edited portion
    local totalEditedSamples = math.floor(samplerate * length)  -- Total samples in edited portion

    -- Request exactly the width number of samples for 1:1 mapping
    local samplesNeeded = math.floor(width)

    -- Ensure reasonable bounds
    samplesNeeded = math.floor(math.max(50, math.min(samplesNeeded, 2000)))

    -- Calculate the number of samples we can actually get from the edited portion
    local samplesToRequest = samplesNeeded

    -- Calculate peakrate based on what we need
    local peakrate = math.max(1, totalEditedSamples / samplesToRequest)

    -- If we're asking for more samples than available in the edited portion, adjust
    if peakrate < 1 then
        samplesToRequest = totalEditedSamples
        peakrate = 1
    end

    -- Calculate the EXACT maximum samples for the edited portion
    local maxSamplesForEditedPortion = math.floor(length * samplerate / peakrate)

    -- Calculate the exact number of samples that represent our edited portion
    local exactSamplesForEditedLength = math.floor(length * samplerate / peakrate)

    -- Make sure we never request more than what's available in the edited portion
    samplesToRequest = math.min(samplesToRequest, maxSamplesForEditedPortion)

    -- Create a slightly larger buffer to accommodate any rounding
    local bufsize = (samplesToRequest + 10) * 2 * n_channels  -- 2 values (max/min) per sample per channel
    local buf = reaper.new_array(bufsize)
    buf.clear()

    -- Debug to verify we're getting the right portion (commented for production)
    -- reaper.ShowConsoleMsg(string.format("  Getting peaks: rate=%.2f, requesting %d samples\n", peakrate, samplesToRequest))

    local retval = reaper.GetMediaItemTake_Peaks(
        tempTake,
        peakrate,        -- samples per peak
        0,               -- start time (0 because take already has offset)
        n_channels,      -- Use actual channel count
        samplesToRequest,   -- number of samples we want (limited by edited duration)
        0,               -- want_extra_type (0 = min/max peaks)
        buf
    )

    -- Extract the actual number of samples returned
    local spl_cnt = retval % 1048576  -- Lower 20 bits

    -- Debug: Check how many samples we got (commented for production)
    -- reaper.ShowConsoleMsg(string.format("  Samples returned: %d\n", spl_cnt))

    -- CRITICAL: Strictly limit samples to the edited portion
    -- Never process more samples than what represents the edited length
    if spl_cnt > maxSamplesForEditedPortion then
        -- reaper.ShowConsoleMsg(string.format("  WARNING: Got %d samples but edited portion should only have %d\n",
        --     spl_cnt, maxSamplesForEditedPortion))
        spl_cnt = maxSamplesForEditedPortion
    end

    -- Also limit to what we requested
    if spl_cnt > samplesToRequest then
        spl_cnt = samplesToRequest
    end

    -- IMPORTANT: Ensure we stop exactly at the edited portion end
    if spl_cnt > exactSamplesForEditedLength then
        spl_cnt = exactSamplesForEditedLength
    end

    -- Initialize channel-specific peak arrays
    peaks.channels = {}
    for ch = 1, n_channels do
        peaks.channels[ch] = {
            min = {},
            max = {},
            rms = {}
        }
    end

    if spl_cnt > 0 then
        -- Convert buffer to table
        local peaks_table = buf.table()

        if peaks_table and #peaks_table > 0 then
            -- Limit to the samples that represent the edited portion
            -- CRUCIAL: Use the exact number of samples we got, capped at the edited portion length
            local actualSamples = math.min(spl_cnt, exactSamplesForEditedLength or maxSamplesForEditedPortion)
            -- reaper.ShowConsoleMsg(string.format("  Using %d samples for display\n", actualSamples))

            -- Debug output for edited portion (commented for production)
            -- reaper.ShowConsoleMsg(string.format("  Buffer size: %d, Using samples: %d\n",
            --     #peaks_table, actualSamples))
            -- reaper.ShowConsoleMsg(string.format("  Waveform width: %d pixels\n", width))

            -- IMPORTANT: Data is organized in BLOCKS, not interleaved per sample!
            -- First block: ALL maximums (interleaved by channel)
            -- Second block: ALL minimums (interleaved by channel)

            local max_block_start = 1  -- Lua arrays start at 1
            local min_block_start = (spl_cnt * n_channels) + 1  -- Use spl_cnt for actual buffer structure

            -- CRITICAL: Never read more samples than what represents the edited portion
            local samplesToRead = math.min(actualSamples, spl_cnt)
            for i = 1, samplesToRead do
                for ch = 1, n_channels do
                    -- Maximum values are in the first block
                    local max_idx = max_block_start + ((i - 1) * n_channels) + (ch - 1)
                    -- Minimum values are in the second block
                    local min_idx = min_block_start + ((i - 1) * n_channels) + (ch - 1)

                    if max_idx <= #peaks_table and min_idx <= #peaks_table then
                        local maxVal = peaks_table[max_idx] or 0
                        local minVal = peaks_table[min_idx] or 0

                        peaks.channels[ch].max[i] = maxVal
                        peaks.channels[ch].min[i] = minVal
                        peaks.channels[ch].rms[i] = (math.abs(maxVal) + math.abs(minVal)) / 2 * 0.7

                        -- Debug first samples to verify we have the right data (commented for production)
                        -- if i <= 5 and ch == 1 then
                        --     reaper.ShowConsoleMsg(string.format("  Peak[%d]: max=%.4f, min=%.4f\n",
                        --         i, maxVal, minVal))
                        -- end
                    else
                        -- Fill with zeros if we run out of data
                        peaks.channels[ch].max[i] = 0
                        peaks.channels[ch].min[i] = 0
                        peaks.channels[ch].rms[i] = 0
                    end
                end
            end

            -- Interpolate/stretch to display width if needed
            if samplesToRead ~= width then
                -- reaper.ShowConsoleMsg(string.format("  Interpolating from %d samples to %d pixels\n", samplesToRead, width))
                for ch = 1, n_channels do
                    local interpolated = {min = {}, max = {}, rms = {}}

                    for pixelIdx = 1, width do
                        if samplesToRead > 0 then
                            -- Map pixel to sample position proportionally - stretch the available data
                            local samplePos
                            if width > 1 and samplesToRead > 1 then
                                samplePos = ((pixelIdx - 1) / (width - 1)) * (samplesToRead - 1) + 1
                            else
                                samplePos = 1
                            end
                            local sampleIdx = math.floor(samplePos)
                            local fraction = samplePos - sampleIdx

                            if sampleIdx < samplesToRead then
                                local maxVal1 = peaks.channels[ch].max[sampleIdx] or 0
                                local maxVal2 = peaks.channels[ch].max[math.min(sampleIdx + 1, samplesToRead)] or 0
                                local minVal1 = peaks.channels[ch].min[sampleIdx] or 0
                                local minVal2 = peaks.channels[ch].min[math.min(sampleIdx + 1, samplesToRead)] or 0
                                local rmsVal1 = peaks.channels[ch].rms[sampleIdx] or 0
                                local rmsVal2 = peaks.channels[ch].rms[math.min(sampleIdx + 1, samplesToRead)] or 0

                                -- Linear interpolation
                                interpolated.max[pixelIdx] = maxVal1 + (maxVal2 - maxVal1) * fraction
                                interpolated.min[pixelIdx] = minVal1 + (minVal2 - minVal1) * fraction
                                interpolated.rms[pixelIdx] = rmsVal1 + (rmsVal2 - rmsVal1) * fraction
                            elseif sampleIdx == samplesToRead then
                                -- Last sample - use it as is
                                interpolated.max[pixelIdx] = peaks.channels[ch].max[samplesToRead] or 0
                                interpolated.min[pixelIdx] = peaks.channels[ch].min[samplesToRead] or 0
                                interpolated.rms[pixelIdx] = peaks.channels[ch].rms[samplesToRead] or 0
                            else
                                -- This shouldn't happen with correct stretching, but keep last valid sample
                                interpolated.max[pixelIdx] = peaks.channels[ch].max[samplesToRead] or 0
                                interpolated.min[pixelIdx] = peaks.channels[ch].min[samplesToRead] or 0
                                interpolated.rms[pixelIdx] = peaks.channels[ch].rms[samplesToRead] or 0
                            end
                        else
                            -- No data at all - fill with silence
                            interpolated.max[pixelIdx] = 0
                            interpolated.min[pixelIdx] = 0
                            interpolated.rms[pixelIdx] = 0
                        end
                    end

                    peaks.channels[ch] = interpolated
                end
            end

            -- Keep backward compatibility: store first channel in root peaks object
            if n_channels > 0 and peaks.channels[1] then
                peaks.max = peaks.channels[1].max
                peaks.min = peaks.channels[1].min
                peaks.rms = peaks.channels[1].rms
            end

            -- Apply adaptive normalization per channel
            for ch = 1, n_channels do
                local maxPeak = 0
                local validSamples = 0

                -- Find the maximum peak value in this channel
                local numSamples = peaks.channels[ch].max and #peaks.channels[ch].max or 0
                for i = 1, numSamples do
                    if peaks.channels[ch] and peaks.channels[ch].max and peaks.channels[ch].max[i] then
                        local absMax = math.abs(peaks.channels[ch].max[i])
                        local absMin = math.abs(peaks.channels[ch].min[i] or 0)
                        maxPeak = math.max(maxPeak, absMax, absMin)
                        if absMax > 0.001 or absMin > 0.001 then
                            validSamples = validSamples + 1
                        end
                    end
                end

                -- Only normalize if we have valid data
                if maxPeak > 0.001 and validSamples > 10 then
                    local normFactor = 1.0

                    if maxPeak < 0.05 then
                        -- Very quiet sound - amplify significantly
                        normFactor = 0.4 / maxPeak
                    elseif maxPeak < 0.1 then
                        -- Quiet sound - moderate amplification
                        normFactor = 0.5 / maxPeak
                    elseif maxPeak < 0.3 then
                        -- Moderate level - slight boost
                        normFactor = 0.6 / maxPeak
                    elseif maxPeak < 0.7 then
                        -- Good level - minor adjustment
                        normFactor = 0.8 / maxPeak
                    else
                        -- Already loud - no amplification
                        normFactor = 1.0
                    end

                    -- Apply amplification factor from options
                    if amplifyQuiet and amplifyQuiet > 1.0 and maxPeak < 0.3 then
                        normFactor = normFactor * (1.0 + (amplifyQuiet - 1.0) * (0.3 - maxPeak) / 0.3)
                    end

                    -- Apply logarithmic scaling if enabled and needed
                    if useLogScale and normFactor > 1.5 then
                        normFactor = 1.0 + math.sqrt(normFactor - 1.0)
                    end

                    -- Limit maximum amplification
                    normFactor = math.min(normFactor, 8.0)

                    -- Apply normalization to all samples
                    for i = 1, numSamples do
                        if peaks.channels[ch].max[i] then
                            local maxVal = peaks.channels[ch].max[i] * normFactor
                            local minVal = peaks.channels[ch].min[i] * normFactor
                            local rmsVal = peaks.channels[ch].rms[i] * normFactor

                            -- Apply soft clipping to prevent overflow
                            peaks.channels[ch].max[i] = softClip(maxVal, 0.95)
                            peaks.channels[ch].min[i] = softClip(minVal, 0.95)
                            peaks.channels[ch].rms[i] = softClip(rmsVal, 0.95)
                        end
                    end
                end
            end

            -- Update backward compatibility peaks
            if n_channels > 0 and peaks.channels[1] then
                peaks.max = peaks.channels[1].max
                peaks.min = peaks.channels[1].min
                peaks.rms = peaks.channels[1].rms
            end
        else
            -- No data in buffer - try single channel fallback
            -- Request mono peaks as fallback
            buf.clear()
            -- Resize buffer for mono (1 channel, 2 values per sample)
            local bufsize_mono = samplesToRequest * 2  -- 2 values (max/min) per sample for mono
            buf.resize(bufsize_mono)

            local retval_mono = reaper.GetMediaItemTake_Peaks(
                tempTake,
                peakrate,
                0,               -- start time (0 because take already has offset)
                1,               -- Force mono
                samplesToRequest,   -- Use limited samples
                0,
                buf
            )

            local spl_cnt_mono = retval_mono % 1048576

            -- Apply same strict limits as for multi-channel
            if spl_cnt_mono > maxSamplesForEditedPortion then
                spl_cnt_mono = maxSamplesForEditedPortion
            end
            if spl_cnt_mono > samplesToRequest then
                spl_cnt_mono = samplesToRequest
            end
            -- IMPORTANT: Ensure we stop exactly at the edited portion end
            if spl_cnt_mono > exactSamplesForEditedLength then
                spl_cnt_mono = exactSamplesForEditedLength
            end

            if spl_cnt_mono > 0 then
                local peaks_table = buf.table()
                if peaks_table and #peaks_table > 0 then
                    -- For mono: first half is max values, second half is min values
                    local max_offset = 1  -- Lua arrays start at 1
                    local min_offset = spl_cnt_mono + 1

                    -- Read mono data and duplicate to all channels
                    local samplesToReadMono = math.min(spl_cnt_mono, exactSamplesForEditedLength)
                    for i = 1, samplesToReadMono do
                        local maxVal = peaks_table[max_offset + (i - 1)] or 0
                        local minVal = peaks_table[min_offset + (i - 1)] or 0
                        local rmsVal = (math.abs(maxVal) + math.abs(minVal)) / 2 * 0.7

                        -- Apply to all channels
                        for ch = 1, n_channels do
                            peaks.channels[ch].max[i] = maxVal
                            peaks.channels[ch].min[i] = minVal
                            peaks.channels[ch].rms[i] = rmsVal
                        end
                    end

                    -- Interpolate to display width if needed
                    if samplesToReadMono ~= width then
                        for ch = 1, n_channels do
                            local interpolated = {min = {}, max = {}, rms = {}}

                            for pixelIdx = 1, width do
                                local samplePos
                                if width > 1 and samplesToReadMono > 1 then
                                    samplePos = ((pixelIdx - 1) / (width - 1)) * (samplesToReadMono - 1) + 1
                                else
                                    samplePos = 1
                                end
                                local sampleIdx = math.floor(samplePos)
                                local fraction = samplePos - sampleIdx

                                if sampleIdx < samplesToReadMono then
                                    local maxVal1 = peaks.channels[ch].max[sampleIdx] or 0
                                    local maxVal2 = peaks.channels[ch].max[math.min(sampleIdx + 1, samplesToReadMono)] or 0
                                    local minVal1 = peaks.channels[ch].min[sampleIdx] or 0
                                    local minVal2 = peaks.channels[ch].min[math.min(sampleIdx + 1, samplesToReadMono)] or 0
                                    local rmsVal1 = peaks.channels[ch].rms[sampleIdx] or 0
                                    local rmsVal2 = peaks.channels[ch].rms[math.min(sampleIdx + 1, samplesToReadMono)] or 0

                                    -- Linear interpolation
                                    interpolated.max[pixelIdx] = maxVal1 + (maxVal2 - maxVal1) * fraction
                                    interpolated.min[pixelIdx] = minVal1 + (minVal2 - minVal1) * fraction
                                    interpolated.rms[pixelIdx] = rmsVal1 + (rmsVal2 - rmsVal1) * fraction
                                elseif sampleIdx == samplesToReadMono then
                                    -- Last sample - use it as is
                                    interpolated.max[pixelIdx] = peaks.channels[ch].max[samplesToReadMono] or 0
                                    interpolated.min[pixelIdx] = peaks.channels[ch].min[samplesToReadMono] or 0
                                    interpolated.rms[pixelIdx] = peaks.channels[ch].rms[samplesToReadMono] or 0
                                else
                                    -- This shouldn't happen with correct stretching, but keep last valid sample
                                    interpolated.max[pixelIdx] = peaks.channels[ch].max[samplesToReadMono] or 0
                                    interpolated.min[pixelIdx] = peaks.channels[ch].min[samplesToReadMono] or 0
                                    interpolated.rms[pixelIdx] = peaks.channels[ch].rms[samplesToReadMono] or 0
                                end
                            end

                            peaks.channels[ch] = interpolated
                        end
                    end
                end
            else
                -- Complete failure - fill with minimal data
                for ch = 1, n_channels do
                    peaks.channels[ch] = peaks.channels[ch] or {min = {}, max = {}, rms = {}}
                    -- Just create one sample of silence
                    peaks.channels[ch].max[1] = 0
                    peaks.channels[ch].min[1] = 0
                    peaks.channels[ch].rms[1] = 0
                end
            end

            -- Set backward compatibility - use the interpolated data to fill width
            if peaks.channels and peaks.channels[1] then
                peaks.max = peaks.channels[1].max
                peaks.min = peaks.channels[1].min
                peaks.rms = peaks.channels[1].rms
            end
        end
    else
        -- No data returned, fill with minimal silence
        for ch = 1, n_channels do
            peaks.channels[ch] = {min = {}, max = {}, rms = {}}
            for i = 1, 1 do  -- Just one sample
                peaks.channels[ch].max[i] = 0
                peaks.channels[ch].min[i] = 0
                peaks.channels[ch].rms[i] = 0
            end
        end
        -- Minimal fallback data
        peaks.max[1] = 0
        peaks.min[1] = 0
        peaks.rms[1] = 0
    end

    -- Clean up
    reaper.DeleteTrackMediaItem(tempTrack, tempItem)

    -- Check if we got ANY data (even silence is valid)
    local hasValidData = false
    if n_channels > 0 and peaks.channels then
        for ch = 1, n_channels do
            if peaks.channels[ch] and peaks.channels[ch].max and #peaks.channels[ch].max > 0 then
                hasValidData = true
                break
            end
        end
    end

    -- If no data at all, try to rebuild peaks
    if not hasValidData then
        -- reaper.ShowConsoleMsg("[Waveform] ERROR: No peak data received, rebuilding peaks...\n")

        -- Delete existing .reapeaks file which might be corrupted
        local peaksFilePath = filePath .. ".reapeaks"
        os.remove(peaksFilePath)

        -- Clear cache
        globals.waveformCache[cacheKey] = nil

        -- Return placeholder for now - the next call will rebuild
        return Waveform.createPlaceholderWaveform(width)
    end

    -- Create waveform data
    local waveformData = {
        peaks = peaks,
        length = length,
        numChannels = numChannels,
        samplerate = samplerate,
        startOffset = startOffset,
        isPlaceholder = false
    }

    -- Cache it only if we have valid data
    globals.waveformCache[cacheKey] = waveformData

    return waveformData
end

-- Draw waveform using ImGui DrawList
function Waveform.drawWaveform(filePath, width, height, options)
    local ctx = globals.ctx
    local imgui = globals.imgui

    -- Validate inputs
    width = math.floor(tonumber(width) or 400)
    height = math.floor(tonumber(height) or 100)
    if width <= 0 then width = 400 end
    if height <= 0 then height = 100 end

    options = options or {}

    -- Get waveform data with options
    local waveformData = Waveform.getWaveformData(filePath, width, options)
    if not waveformData then
        imgui.Text(ctx, "Unable to load waveform")
        return nil
    end

    -- Get drawing position
    local draw_list = imgui.GetWindowDrawList(ctx)
    local pos_x, pos_y = imgui.GetCursorScreenPos(ctx)

    -- Calculate channel layout
    local numChannels = waveformData.numChannels or 1
    local displayChannels = math.min(numChannels, 8)  -- Limit to 8 channels for display
    local channelHeight = height / displayChannels
    local channelSpacing = 2  -- Pixels between channels

    -- Draw background
    imgui.DrawList_AddRectFilled(draw_list,
        pos_x, pos_y,
        pos_x + width, pos_y + height,
        0x1A1A1AFF
    )

    -- Push clipping rectangle to prevent waveform from drawing outside bounds when zoomed
    imgui.DrawList_PushClipRect(draw_list, pos_x, pos_y, pos_x + width, pos_y + height, true)

    -- Draw each channel
    local peaks = waveformData.peaks

    -- Single color for all waveform elements
    local waveformColor = globals.Settings.getSetting("waveformColor") -- Bright cyan for both peaks and RMS

    for ch = 1, displayChannels do
        local channelY = pos_y + (ch - 1) * channelHeight
        local centerY = channelY + channelHeight / 2 - channelSpacing / 2

        -- Draw zero line for this channel
        imgui.DrawList_AddLine(draw_list,
            pos_x, centerY,
            pos_x + width, centerY,
            0x404040FF,
            1
        )

        -- Get channel data
        local channelPeaks = nil
        if peaks.channels and peaks.channels[ch] then
            channelPeaks = peaks.channels[ch]
        elseif ch == 1 then
            -- Fallback for backward compatibility
            channelPeaks = peaks
        end

            -- Draw waveform peaks for this channel
        if channelPeaks and channelPeaks.max and #channelPeaks.max > 0 then
            local channelDrawHeight = channelHeight - channelSpacing

            -- Draw waveform
            for pixel = 1, width do
                local x = pos_x + pixel - 1

                -- Direct 1:1 mapping since data is already interpolated to width
                local sampleIndex = pixel
                local maxVal = channelPeaks.max[sampleIndex] or 0
                local minVal = channelPeaks.min[sampleIndex] or 0

                -- Draw vertical line from min to max (only if showPeaks is enabled)
                local verticalZoom = options.verticalZoom or globals.waveformVerticalZoom or 1.0
                local topY = centerY - (maxVal * channelDrawHeight / 2 * verticalZoom)
                local bottomY = centerY - (minVal * channelDrawHeight / 2 * verticalZoom)

                if options.showPeaks ~= false then
                    imgui.DrawList_AddLine(draw_list,
                        x, topY,
                        x, bottomY,
                        waveformColor,
                        1
                    )
                end

                -- Draw RMS (only if showRMS is enabled)
                if options.showRMS ~= false then
                    local rmsVal = channelPeaks.rms[sampleIndex] or 0
                    if math.abs(rmsVal) > 0.01 then
                        imgui.DrawList_AddLine(draw_list,
                            x, centerY - (rmsVal * channelDrawHeight / 2 * verticalZoom),
                            x, centerY + (rmsVal * channelDrawHeight / 2 * verticalZoom),
                            waveformColor,
                            1
                        )
                    end
                end
            end
        end

        -- Draw separator between channels
        if ch < displayChannels then
            local separatorY = channelY + channelHeight - 1
            imgui.DrawList_AddLine(draw_list,
                pos_x, separatorY,
                pos_x + width, separatorY,
                0x303030FF,
                1
            )
        end
    end

    -- Draw playback position if playing (the moving white bar)
    if globals.audioPreview.isPlaying and globals.audioPreview.currentFile == filePath then
        local position = globals.audioPreview.position
        local startOffset = waveformData.startOffset or 0

        if position and type(position) == "number" and waveformData.length and waveformData.length > 0 then
            -- Calculate the relative position in the edited item
            local relativePos = position - startOffset

            -- Draw the playback position (white bar)
            local playPos = (relativePos / waveformData.length) * width

            -- Only draw if within visible range
            if playPos >= 0 and playPos <= width then
                imgui.DrawList_AddLine(draw_list,
                    pos_x + playPos, pos_y,
                    pos_x + playPos, pos_y + height,
                    0xFFFFFFFF,
                    2
                )
            end
        end
    end

    -- Pop clipping rectangle
    imgui.DrawList_PopClipRect(draw_list)

    -- Draw waveform areas/regions before the border
    if globals.waveformAreas[filePath] then
        for i, area in ipairs(globals.waveformAreas[filePath]) do
            local areaStartX = pos_x + (area.startPos / waveformData.length) * width
            local areaEndX = pos_x + (area.endPos / waveformData.length) * width
            local areaWidth = areaEndX - areaStartX

            -- Draw quasi-transparent area with very subtle gradient effect
            imgui.DrawList_AddRectFilled(draw_list,
                areaStartX, pos_y,
                areaEndX, pos_y + height,
                0x15856D50  -- Quasi-transparent blue (5% opacity)
            )

            -- Draw very subtle gradient overlay (barely visible darker at edges)
            imgui.DrawList_AddRectFilled(draw_list,
                areaStartX, pos_y,
                areaStartX + 3, pos_y + height,
                0x15856D50  -- Very slightly darker blue
            )
            imgui.DrawList_AddRectFilled(draw_list,
                areaEndX - 3, pos_y,
                areaEndX, pos_y + height,
                0x15856D50  -- Very slightly darker blue
            )

            -- Draw area borders (more subtle)
            imgui.DrawList_AddLine(draw_list,
                areaStartX, pos_y,
                areaStartX, pos_y + height,
                0x40FFFFFF, 1  -- Subtle white border left
            )
            imgui.DrawList_AddLine(draw_list,
                areaEndX, pos_y,
                areaEndX, pos_y + height,
                0x40FFFFFF, 1  -- Subtle white border right
            )

            -- Draw area name label if there's enough space
            if areaWidth > 40 then
                local areaName = area.name or string.format("Area %d", i)
                local textX = areaStartX + 5
                local textY = pos_y + 5

                -- Draw text background for better readability
                local textWidth = imgui.CalcTextSize(ctx, areaName)
                imgui.DrawList_AddRectFilled(draw_list,
                    textX - 2, textY - 1,
                    math.min(textX + textWidth + 2, areaEndX - 2), textY + 14,
                    0x80000000  -- Semi-transparent black background
                )

                -- Draw area name
                imgui.DrawList_AddText(draw_list, textX, textY, 0xFFFFFFFF, areaName)
            end

            -- Draw resize handles (subtle, only visible on hover)
            local handleWidth = 4
            local handleHeight = 20
            local handleColor = 0x40FFFFFF  -- Very subtle semi-transparent white

            -- Check if mouse is near handles for highlighting
            local mouse_x, mouse_y = imgui.GetMousePos(ctx)
            local relative_x = mouse_x - pos_x
            local leftHandleHover = math.abs(relative_x - (areaStartX - pos_x)) < 5
            local rightHandleHover = math.abs(relative_x - (areaEndX - pos_x)) < 5

            -- Left handle
            local leftHandleColor = leftHandleHover and 0xA0FFFFFF or handleColor
            imgui.DrawList_AddRectFilled(draw_list,
                areaStartX - handleWidth/2, pos_y + height/2 - handleHeight/2,
                areaStartX + handleWidth/2, pos_y + height/2 + handleHeight/2,
                leftHandleColor
            )
            -- Add subtle grip lines on handle when hovering
            if leftHandleHover then
                imgui.DrawList_AddLine(draw_list,
                    areaStartX, pos_y + height/2 - 5,
                    areaStartX, pos_y + height/2 + 5,
                    0x60000000, 1
                )
            end

            -- Right handle
            local rightHandleColor = rightHandleHover and 0xA0FFFFFF or handleColor
            imgui.DrawList_AddRectFilled(draw_list,
                areaEndX - handleWidth/2, pos_y + height/2 - handleHeight/2,
                areaEndX + handleWidth/2, pos_y + height/2 + handleHeight/2,
                rightHandleColor
            )
            -- Add subtle grip lines on handle when hovering
            if rightHandleHover then
                imgui.DrawList_AddLine(draw_list,
                    areaEndX, pos_y + height/2 - 5,
                    areaEndX, pos_y + height/2 + 5,
                    0x60000000, 1
                )
            end
        end
    end

    -- Draw area being created
    if globals.waveformAreaDrag.isDragging and globals.waveformAreaDrag.currentFile == filePath then
        local dragStartX = math.min(globals.waveformAreaDrag.startX, globals.waveformAreaDrag.endX)
        local dragEndX = math.max(globals.waveformAreaDrag.startX, globals.waveformAreaDrag.endX)

        imgui.DrawList_AddRectFilled(draw_list,
            dragStartX, pos_y,
            dragEndX, pos_y + height,
            0x0C80FF80  -- Quasi-transparent green for new area (5% opacity)
        )

        imgui.DrawList_AddRect(draw_list,
            dragStartX, pos_y,
            dragEndX, pos_y + height,
            0x40FF80FF, -- Subtle green border
            0, 0, 1
        )
    end

    -- Draw border
    imgui.DrawList_AddRect(draw_list,
        pos_x, pos_y,
        pos_x + width, pos_y + height,
        0x606060FF,
        0, 0, 1
    )

    -- Reserve space
    imgui.Dummy(ctx, width, height)

    -- Check for interactions
    if imgui.IsItemHovered(ctx) then
        -- Check for vertical zoom with Ctrl+MouseWheel
        local wheel = imgui.GetMouseWheel(ctx)
        local ctrlPressed = (imgui.GetKeyMods(ctx) & imgui.Mod_Ctrl) ~= 0
        if ctrlPressed and wheel ~= 0 then
            options.verticalZoom = options.verticalZoom or globals.waveformVerticalZoom or 1.0
            options.verticalZoom = math.max(0.1, math.min(5.0, options.verticalZoom + wheel * 0.1))
            -- Store zoom level in globals for persistence
            globals.waveformVerticalZoom = options.verticalZoom
        end

        -- Check for Ctrl+Click to delete area
        local ctrlPressed = (imgui.GetKeyMods(ctx) & imgui.Mod_Ctrl) ~= 0
        if ctrlPressed and imgui.IsMouseClicked(ctx, 0) and not globals.waveformAreaDrag.isResizing then
            -- Check if clicking on an area to delete it
            local clickPos = (relative_x / width) * waveformData.length
            local clickedArea, clickedAreaIndex = Waveform.getAreaAtPosition(filePath, clickPos, waveformData.length)

            if clickedArea then
                -- Delete the area with Ctrl+Click
                Waveform.deleteArea(filePath, clickedAreaIndex)
            end
        -- Check for double-click to reset position
        elseif imgui.IsMouseDoubleClicked(ctx, 0) then  -- Double left click
            -- Clear the saved position
            if globals.audioPreview then
                globals.audioPreview.clickedPosition = nil
                globals.audioPreview.playbackStartPosition = nil
                -- Don't clear currentFile here - it will be set when playing
            end

            -- Start playback from beginning if onWaveformClick is defined
            if options.onWaveformClick then
                options.onWaveformClick(0, waveformData)  -- Start from beginning
            end
        elseif imgui.IsMouseClicked(ctx, 0) and not ctrlPressed then  -- Single left click (without Ctrl)
            -- Get mouse position relative to waveform
            local mouse_x, mouse_y = imgui.GetMousePos(ctx)
            local relative_x = mouse_x - pos_x

            -- Calculate position in the audio file
            if relative_x >= 0 and relative_x <= width then
                local clickRatio = relative_x / width
                local clickPosition = clickRatio * waveformData.length

                -- Store click information for starting playback
                if options.onWaveformClick then
                    options.onWaveformClick(clickPosition, waveformData)
                end
            end
        end

        -- Check for area resize hover
        local mouse_x, mouse_y = imgui.GetMousePos(ctx)
        local relative_x = mouse_x - pos_x
        local hoverOnHandle = false

        if globals.waveformAreas[filePath] and not globals.waveformAreaDrag.isDragging then
            for i, area in ipairs(globals.waveformAreas[filePath]) do
                local areaStartX = (area.startPos / waveformData.length) * width
                local areaEndX = (area.endPos / waveformData.length) * width

                -- Check if hovering on left edge
                if math.abs(relative_x - areaStartX) < 5 then
                    imgui.SetMouseCursor(ctx, imgui.MouseCursor_ResizeEW)
                    hoverOnHandle = true

                    -- Check for left drag to resize
                    if imgui.IsMouseClicked(ctx, 0) then
                        globals.waveformAreaDrag.isResizing = true
                        globals.waveformAreaDrag.resizeEdge = 'left'
                        globals.waveformAreaDrag.resizeAreaIndex = i
                        globals.waveformAreaDrag.currentFile = filePath
                    end
                    break
                -- Check if hovering on right edge
                elseif math.abs(relative_x - areaEndX) < 5 then
                    imgui.SetMouseCursor(ctx, imgui.MouseCursor_ResizeEW)
                    hoverOnHandle = true

                    -- Check for left drag to resize
                    if imgui.IsMouseClicked(ctx, 0) then
                        globals.waveformAreaDrag.isResizing = true
                        globals.waveformAreaDrag.resizeEdge = 'right'
                        globals.waveformAreaDrag.resizeAreaIndex = i
                        globals.waveformAreaDrag.currentFile = filePath
                    end
                    break
                end
            end
        end

        -- Handle area resizing
        if globals.waveformAreaDrag.isResizing and globals.waveformAreaDrag.currentFile == filePath then
            if imgui.IsMouseDragging(ctx, 0) then
                local area = globals.waveformAreas[filePath][globals.waveformAreaDrag.resizeAreaIndex]
                if area then
                    local newPos = math.max(0, math.min(1, relative_x / width)) * waveformData.length

                    if globals.waveformAreaDrag.resizeEdge == 'left' then
                        area.startPos = math.min(newPos, area.endPos - 0.01)  -- Minimum area size
                    else
                        area.endPos = math.max(newPos, area.startPos + 0.01)
                    end
                end
            elseif imgui.IsMouseReleased(ctx, 0) then
                globals.waveformAreaDrag.isResizing = false
                globals.waveformAreaDrag.resizeEdge = nil
                globals.waveformAreaDrag.resizeAreaIndex = nil
            end
        end

        -- Check for right-click drag to create new area or show context menu
        if imgui.IsMouseClicked(ctx, 2) and not globals.waveformAreaDrag.isResizing then  -- Right click
            -- Check if we're clicking on an existing area
            local clickPos = (relative_x / width) * waveformData.length
            local clickedArea, clickedAreaIndex = Waveform.getAreaAtPosition(filePath, clickPos, waveformData.length)

            if clickedArea then
                -- Open context menu for existing area
                imgui.OpenPopup(ctx, string.format("##AreaContextMenu_%s_%d", filePath, clickedAreaIndex))
                globals.contextMenuArea = {area = clickedArea, index = clickedAreaIndex, file = filePath}
            else
                -- Start dragging to create new area
                globals.waveformAreaDrag.isDragging = true
                globals.waveformAreaDrag.startX = mouse_x
                globals.waveformAreaDrag.endX = mouse_x
                globals.waveformAreaDrag.currentFile = filePath
            end
        end

        if globals.waveformAreaDrag.isDragging and globals.waveformAreaDrag.currentFile == filePath then
            if imgui.IsMouseDragging(ctx, 2) then  -- Right drag
                globals.waveformAreaDrag.endX = mouse_x
            elseif imgui.IsMouseReleased(ctx, 2) then  -- Right release
                -- Create the new area
                local startX = math.min(globals.waveformAreaDrag.startX, globals.waveformAreaDrag.endX) - pos_x
                local endX = math.max(globals.waveformAreaDrag.startX, globals.waveformAreaDrag.endX) - pos_x

                -- Convert to time positions
                local startPos = math.max(0, math.min(1, startX / width)) * waveformData.length
                local endPos = math.max(0, math.min(1, endX / width)) * waveformData.length

                -- Only create area if it has meaningful size
                if math.abs(endPos - startPos) > 0.01 then
                    if not globals.waveformAreas[filePath] then
                        globals.waveformAreas[filePath] = {}
                    end

                    table.insert(globals.waveformAreas[filePath], {
                        startPos = startPos,
                        endPos = endPos,
                        name = string.format("Area %d", #globals.waveformAreas[filePath] + 1)
                    })
                end

                -- Reset drag state
                globals.waveformAreaDrag.isDragging = false
                globals.waveformAreaDrag.startX = 0
                globals.waveformAreaDrag.endX = 0
                globals.waveformAreaDrag.currentFile = nil
            end
        end

        -- Show appropriate cursor
        if not hoverOnHandle and not globals.waveformAreaDrag.isDragging and not globals.waveformAreaDrag.isResizing then
            imgui.SetMouseCursor(ctx, imgui.MouseCursor_Hand)
        end
    else
        -- Reset drag state if mouse left the waveform area
        if globals.waveformAreaDrag.isDragging and imgui.IsMouseReleased(ctx, 2) then
            globals.waveformAreaDrag.isDragging = false
            globals.waveformAreaDrag.currentFile = nil
        end
        if globals.waveformAreaDrag.isResizing and imgui.IsMouseReleased(ctx, 0) then
            globals.waveformAreaDrag.isResizing = false
            globals.waveformAreaDrag.resizeAreaIndex = nil
            globals.waveformAreaDrag.currentFile = nil
        end
    end

    -- Handle area context menu
    if globals.contextMenuArea and globals.contextMenuArea.file == filePath then
        local menuOpen = imgui.BeginPopup(ctx, string.format("##AreaContextMenu_%s_%d",
                                          globals.contextMenuArea.file,
                                          globals.contextMenuArea.index))
        if menuOpen then
            local area = globals.contextMenuArea.area
            local areaIndex = globals.contextMenuArea.index

            -- Display area info
            imgui.Text(ctx, area.name or string.format("Area %d", areaIndex))
            imgui.Separator(ctx)
            imgui.Text(ctx, string.format("Start: %.2fs", area.startPos))
            imgui.Text(ctx, string.format("End: %.2fs", area.endPos))
            imgui.Text(ctx, string.format("Duration: %.2fs", area.endPos - area.startPos))
            imgui.Separator(ctx)

            -- Rename area
            if imgui.Selectable(ctx, "Rename") then
                -- Set up for rename (would need an input dialog)
                globals.renameAreaDialog = {
                    file = filePath,
                    index = areaIndex,
                    currentName = area.name or string.format("Area %d", areaIndex),
                    show = true
                }
                imgui.CloseCurrentPopup(ctx)
            end

            -- Play area
            if imgui.Selectable(ctx, "Play Area") then
                -- Start playback from area start
                if options.onWaveformClick then
                    options.onWaveformClick(area.startPos, waveformData)
                end
                imgui.CloseCurrentPopup(ctx)
            end

            imgui.Separator(ctx)

            -- Delete area
            if imgui.Selectable(ctx, "Delete") then
                Waveform.deleteArea(filePath, areaIndex)
                imgui.CloseCurrentPopup(ctx)
            end

            -- Clear all areas
            if imgui.Selectable(ctx, "Clear All Areas") then
                Waveform.clearAreas(filePath)
                imgui.CloseCurrentPopup(ctx)
            end

            imgui.EndPopup(ctx)
        else
            -- Clear context menu data when popup is closed
            if not menuOpen then
                globals.contextMenuArea = nil
            end
        end
    end

    -- Draw click position marker (where playback will start) - this stays fixed even after stopping
    -- Only show if this is the file that has the saved position
    if globals.audioPreview and globals.audioPreview.clickedPosition and
       globals.audioPreview.currentFile == filePath then
        local clickPos = globals.audioPreview.clickedPosition
        if clickPos and type(clickPos) == "number" and waveformData.length and waveformData.length > 0 then
            -- Calculate position within the waveform
            local markerPos = (clickPos / waveformData.length) * width

            -- Draw marker line (this is the starting point)
            if markerPos >= 0 and markerPos <= width then
                -- Draw a slightly thicker line with a glow effect
                -- First draw a wider semi-transparent line for glow
                imgui.DrawList_AddLine(draw_list,
                    pos_x + markerPos - 1, pos_y,
                    pos_x + markerPos - 1, pos_y + height,
                    0x44FF8888,  -- Semi-transparent red
                    1
                )
                imgui.DrawList_AddLine(draw_list,
                    pos_x + markerPos + 1, pos_y,
                    pos_x + markerPos + 1, pos_y + height,
                    0x44FF8888,  -- Semi-transparent red
                    1
                )
                -- Then draw the main marker
                imgui.DrawList_AddLine(draw_list,
                    pos_x + markerPos, pos_y,
                    pos_x + markerPos, pos_y + height,
                    0xFF8888FF,  -- Light red color for click marker
                    2  -- Make it slightly thicker
                )
            end
        end
    end

    -- Handle rename dialog
    if globals.renameAreaDialog and globals.renameAreaDialog.show and globals.renameAreaDialog.file == filePath then
        imgui.OpenPopup(ctx, "Rename Area")

        local flags = imgui.WindowFlags_AlwaysAutoResize | imgui.WindowFlags_NoSavedSettings

        if imgui.BeginPopupModal(ctx, "Rename Area", nil, flags) then
            -- Initialize input buffer if not exists
            if not globals.renameAreaDialog.buffer then
                globals.renameAreaDialog.buffer = globals.renameAreaDialog.currentName
            end

            imgui.Text(ctx, "Enter new name for area:")

            local changed, newName = imgui.InputText(ctx, "##AreaName",
                                                     globals.renameAreaDialog.buffer)
            if changed then
                globals.renameAreaDialog.buffer = newName
            end

            imgui.Spacing(ctx)

            -- OK button
            if imgui.Button(ctx, "OK", 100, 0) or imgui.IsKeyPressed(ctx, imgui.Key_Enter) then
                Waveform.renameArea(globals.renameAreaDialog.file,
                                   globals.renameAreaDialog.index,
                                   globals.renameAreaDialog.buffer)
                globals.renameAreaDialog = nil
                imgui.CloseCurrentPopup(ctx)
            end

            imgui.SameLine(ctx)

            -- Cancel button
            if imgui.Button(ctx, "Cancel", 100, 0) or imgui.IsKeyPressed(ctx, imgui.Key_Escape) then
                globals.renameAreaDialog = nil
                imgui.CloseCurrentPopup(ctx)
            end

            imgui.EndPopup(ctx)
        end
    end

    return waveformData
end

-- New dedicated function for edited items - reads audio samples directly for precise control
function Waveform.getWaveformDataForEditedItem(filePath, width, options)
    -- 1. VALIDATION
    if not filePath or filePath == "" then
        return Waveform.createPlaceholderWaveform(width)
    end

    width = math.floor(width or 400)
    if width <= 0 then width = 400 end

    local startOffset = options.startOffset or 0
    local displayLength = options.displayLength or 1

    -- Check cache first
    local cacheKey = string.format("%s_EDITED_%d_%.3f_%.3f",
        filePath, width, startOffset, displayLength)

    if globals.waveformCache[cacheKey] and not globals.waveformCache[cacheKey].isPlaceholder then
        return globals.waveformCache[cacheKey]
    end

    -- Check file exists
    local file = io.open(filePath, "r")
    if not file then
        return Waveform.createPlaceholderWaveform(width)
    end
    file:close()

    -- 2. CREATE SOURCE
    local source = reaper.PCM_Source_CreateFromFile(filePath)
    if not source then
        return Waveform.createPlaceholderWaveform(width)
    end

    local samplerate = reaper.GetMediaSourceSampleRate(source)
    local numChannels = math.floor(reaper.GetMediaSourceNumChannels(source) or 1)
    local totalLength = reaper.GetMediaSourceLength(source, false)

    -- Verify bounds
    if startOffset >= totalLength then
        reaper.PCM_Source_Destroy(source)
        return Waveform.createPlaceholderWaveform(width)
    end

    displayLength = math.min(displayLength, totalLength - startOffset)

    -- 3. CREATE TEMPORARY ITEM FOR ACCESSOR
    local tempTrack = reaper.GetTrack(0, 0)
    if not tempTrack then
        reaper.InsertTrackAtIndex(0, false)
        tempTrack = reaper.GetTrack(0, 0)
    end

    if not tempTrack then
        reaper.PCM_Source_Destroy(source)
        return Waveform.createPlaceholderWaveform(width)
    end

    local tempItem = reaper.AddMediaItemToTrack(tempTrack)
    if not tempItem then
        reaper.PCM_Source_Destroy(source)
        return Waveform.createPlaceholderWaveform(width)
    end

    reaper.SetMediaItemInfo_Value(tempItem, "D_POSITION", 0)
    reaper.SetMediaItemInfo_Value(tempItem, "D_LENGTH", displayLength)

    local tempTake = reaper.AddTakeToMediaItem(tempItem)
    if not tempTake then
        reaper.DeleteTrackMediaItem(tempTrack, tempItem)
        reaper.PCM_Source_Destroy(source)
        return Waveform.createPlaceholderWaveform(width)
    end

    -- Set source (REAPER takes ownership)
    reaper.SetMediaItemTake_Source(tempTake, source)

    -- CRUCIAL: Set the offset to read from the correct position
    reaper.SetMediaItemTakeInfo_Value(tempTake, "D_STARTOFFS", startOffset)
    reaper.UpdateItemInProject(tempItem)

    -- 4. CREATE AUDIO ACCESSOR
    local accessor = reaper.CreateTakeAudioAccessor(tempTake)
    if not accessor then
        reaper.DeleteTrackMediaItem(tempTrack, tempItem)
        return Waveform.createPlaceholderWaveform(width)
    end

    -- 5. CALCULATE SAMPLES TO READ
    local totalSamples = math.floor(displayLength * samplerate)
    local samplesPerPixel = math.max(1, math.floor(totalSamples / width))

    -- If we have fewer samples than pixels, we'll stretch the data
    if totalSamples < width then
        samplesPerPixel = 1
    end

    -- 6. INITIALIZE PEAKS STRUCTURE
    local peaks = {
        min = {},
        max = {},
        rms = {},
        channels = {}
    }

    -- Initialize channels
    for ch = 1, numChannels do
        peaks.channels[ch] = {min = {}, max = {}, rms = {}}
    end

    -- 7. READ SAMPLES BLOCK BY BLOCK
    local bufferSize = samplesPerPixel * numChannels
    local audioBuffer = reaper.new_array(bufferSize * 2) -- Extra space for safety

    -- Process exactly 'width' pixels
    for pixelIdx = 1, width do
        -- Calculate position for this pixel
        local startSample = (pixelIdx - 1) * samplesPerPixel

        if startSample >= totalSamples then
            -- Beyond the edited portion - fill with silence
            for ch = 1, numChannels do
                peaks.channels[ch].min[pixelIdx] = 0
                peaks.channels[ch].max[pixelIdx] = 0
                peaks.channels[ch].rms[pixelIdx] = 0
            end
        else
            -- Number of samples to read for this block
            local samplesToRead = math.min(samplesPerPixel, totalSamples - startSample)

            -- Clear buffer before reading
            audioBuffer.clear()

            -- READ AUDIO SAMPLES DIRECTLY
            -- Note: GetAudioAccessorSamples expects time in seconds
            local startTime = startSample / samplerate
            local ret = reaper.GetAudioAccessorSamples(
                accessor,
                samplerate,
                numChannels,
                startTime,
                samplesToRead,
                audioBuffer
            )

            -- Convert buffer to table
            local samples = audioBuffer.table(1, samplesToRead * numChannels)

            -- Calculate min/max/rms for each channel
            for ch = 1, numChannels do
                local minVal = 0
                local maxVal = 0
                local sumSquares = 0
                local count = 0

                -- Process samples for this channel
                for s = 0, samplesToRead - 1 do
                    -- Audio data is interleaved: ch1, ch2, ch1, ch2, ...
                    local idx = s * numChannels + ch
                    local value = samples[idx] or 0

                    minVal = math.min(minVal, value)
                    maxVal = math.max(maxVal, value)
                    sumSquares = sumSquares + (value * value)
                    count = count + 1
                end

                -- Store peaks for this pixel
                peaks.channels[ch].min[pixelIdx] = minVal
                peaks.channels[ch].max[pixelIdx] = maxVal

                -- Calculate RMS (Root Mean Square)
                if count > 0 then
                    peaks.channels[ch].rms[pixelIdx] = math.sqrt(sumSquares / count) * 0.7
                else
                    peaks.channels[ch].rms[pixelIdx] = 0
                end
            end
        end
    end

    -- 8. HANDLE STRETCHING IF NEEDED
    -- If we have fewer samples than width, stretch the data
    if totalSamples < width and totalSamples > 0 then
        local actualPixels = math.ceil(totalSamples / samplesPerPixel)

        if actualPixels < width then
            -- We need to interpolate/stretch
            for ch = 1, numChannels do
                local stretchedChannel = {min = {}, max = {}, rms = {}}

                for pixelIdx = 1, width do
                    -- Map this pixel to the source data
                    local sourcePos = ((pixelIdx - 1) / (width - 1)) * (actualPixels - 1) + 1
                    local sourceIdx = math.floor(sourcePos)
                    local fraction = sourcePos - sourceIdx

                    if sourceIdx < actualPixels then
                        local idx1 = sourceIdx
                        local idx2 = math.min(sourceIdx + 1, actualPixels)

                        -- Linear interpolation
                        stretchedChannel.min[pixelIdx] =
                            peaks.channels[ch].min[idx1] * (1 - fraction) +
                            peaks.channels[ch].min[idx2] * fraction
                        stretchedChannel.max[pixelIdx] =
                            peaks.channels[ch].max[idx1] * (1 - fraction) +
                            peaks.channels[ch].max[idx2] * fraction
                        stretchedChannel.rms[pixelIdx] =
                            peaks.channels[ch].rms[idx1] * (1 - fraction) +
                            peaks.channels[ch].rms[idx2] * fraction
                    else
                        -- Use last value
                        stretchedChannel.min[pixelIdx] = peaks.channels[ch].min[actualPixels] or 0
                        stretchedChannel.max[pixelIdx] = peaks.channels[ch].max[actualPixels] or 0
                        stretchedChannel.rms[pixelIdx] = peaks.channels[ch].rms[actualPixels] or 0
                    end
                end

                peaks.channels[ch] = stretchedChannel
            end
        end
    end

    -- 9. APPLY NORMALIZATION (optional)
    if options.amplifyQuiet then
        for ch = 1, numChannels do
            local maxPeak = 0

            -- Find max peak
            for i = 1, width do
                maxPeak = math.max(maxPeak,
                    math.abs(peaks.channels[ch].max[i] or 0),
                    math.abs(peaks.channels[ch].min[i] or 0))
            end

            -- Apply amplification if needed
            if maxPeak > 0.001 and maxPeak < 0.5 then
                local factor = math.min(0.7 / maxPeak, options.amplifyQuiet or 3.0)

                for i = 1, width do
                    peaks.channels[ch].min[i] = peaks.channels[ch].min[i] * factor
                    peaks.channels[ch].max[i] = peaks.channels[ch].max[i] * factor
                    peaks.channels[ch].rms[i] = peaks.channels[ch].rms[i] * factor
                end
            end
        end
    end

    -- 10. BACKWARD COMPATIBILITY
    if numChannels > 0 then
        peaks.min = peaks.channels[1].min
        peaks.max = peaks.channels[1].max
        peaks.rms = peaks.channels[1].rms
    end

    -- 11. CLEANUP
    reaper.DestroyAudioAccessor(accessor)
    reaper.DeleteTrackMediaItem(tempTrack, tempItem)

    -- 12. PREPARE RETURN DATA
    local waveformData = {
        peaks = peaks,
        length = displayLength,
        numChannels = numChannels,
        samplerate = samplerate,
        startOffset = startOffset,
        isPlaceholder = false
    }

    -- Store in cache
    globals.waveformCache[cacheKey] = waveformData

    return waveformData
end

-- Clear cache for a specific file (all variations with different offsets/lengths)
function Waveform.clearFileCache(filePath)
    if filePath and filePath ~= "" then
        local toRemove = {}
        for key, _ in pairs(globals.waveformCache) do
            -- Check if the key contains the filepath
            -- This clears both regular and EDITED cache entries
            if string.find(key, filePath, 1, true) then
                table.insert(toRemove, key)
            end
        end
        -- Remove all matching entries
        for _, key in ipairs(toRemove) do
            globals.waveformCache[key] = nil
        end
    end
end

-- Clear all cache
function Waveform.clearCache()
    globals.waveformCache = {}
end

-- Generate .reapeaks file for external audio file
function Waveform.generateReapeaksFile(filePath)
    if not filePath or filePath == "" then
        return false
    end

    -- Create PCM source from file
    local source = reaper.PCM_Source_CreateFromFile(filePath)
    if not source then
        return false
    end

    -- Build peaks using REAPER's built-in function
    local retval = reaper.PCM_Source_BuildPeaks(source, 0)  -- mode 0 = build now

    if retval == 0 then
        reaper.PCM_Source_Destroy(source)
        return true
    else
        reaper.PCM_Source_Destroy(source)
        return false
    end
end

-- Force regeneration of .reapeaks file
function Waveform.regeneratePeaksFile(filePath)
    if not filePath or filePath == "" then
        return false
    end

    -- Delete existing .reapeaks file
    local peaksFilePath = filePath .. ".reapeaks"
    os.remove(peaksFilePath)

    -- Clear cache for this file
    Waveform.clearFileCache(filePath)

    -- Generate new peaks file
    return Waveform.generateReapeaksFile(filePath)
end

-- Generate peaks for all items in a container
function Waveform.generatePeaksForContainer(container)
    if not container or not container.items then
        return 0
    end

    local generated = 0
    for _, item in ipairs(container.items) do
        if item.filePath and item.filePath ~= "" then
            local peaksFile = item.filePath .. ".reapeaks"
            local exists = io.open(peaksFile, "rb")
            if exists then
                exists:close()
            else
                -- Peaks don't exist, generate them
                if Waveform.generateReapeaksFile(item.filePath) then
                    generated = generated + 1
                end
            end
        end
    end

    return generated
end

-- Simple audio playback (start)
-- @param filePath: path to audio file
-- @param startOffset: offset in the original file where the edited item starts
-- @param length: length of the edited item
-- @param relativePosition: optional position relative to the edited item (0 to length)
function Waveform.startPlayback(filePath, startOffset, length, relativePosition)
    if not filePath or filePath == "" then
        return false
    end

    Waveform.stopPlayback()

    local file = io.open(filePath, "r")
    if not file then
        return false
    end
    file:close()

    -- Check if SWS extension is available for isolated playback
    if reaper.CF_CreatePreview then
        local source = reaper.PCM_Source_CreateFromFile(filePath)
        if not source then
            return false
        end

        local preview = reaper.CF_CreatePreview(source)
        if not preview then
            reaper.PCM_Source_Destroy(source)
            return false
        end

        globals.audioPreview.cfPreview = preview
        globals.audioPreview.cfSource = source

        -- Calculate actual start position
        local actualStartPos = startOffset or 0
        if relativePosition and relativePosition > 0 then
            actualStartPos = actualStartPos + relativePosition
            -- Ensure we don't exceed the item bounds
            if length and actualStartPos > (startOffset or 0) + length then
                actualStartPos = (startOffset or 0) + length
            end
        end

        reaper.CF_Preview_SetValue(preview, 'D_VOLUME', globals.audioPreview.volume or 0.7)
        reaper.CF_Preview_SetValue(preview, 'D_POSITION', actualStartPos)
        reaper.CF_Preview_SetValue(preview, 'B_LOOP', 0)

        reaper.CF_Preview_Play(preview)

        globals.audioPreview.isPlaying = true
        globals.audioPreview.currentFile = filePath
        globals.audioPreview.startTime = reaper.time_precise()
        globals.audioPreview.position = actualStartPos  -- This is the absolute position in the file
        globals.audioPreview.startOffset = startOffset or 0
        globals.audioPreview.playbackLength = length or nil
        globals.audioPreview.clickedPosition = relativePosition  -- Store for visual feedback (relative to item)
        globals.audioPreview.playbackStartPosition = actualStartPos  -- Store where playback actually started (absolute)

        return true
    end

    return false
end

-- Stop audio playback
function Waveform.stopPlayback()
    if globals.audioPreview.isPlaying then
        if globals.audioPreview.cfPreview then
            reaper.CF_Preview_Stop(globals.audioPreview.cfPreview)

            if globals.audioPreview.cfSource then
                reaper.PCM_Source_Destroy(globals.audioPreview.cfSource)
            end

            globals.audioPreview.cfPreview = nil
            globals.audioPreview.cfSource = nil
        end

        globals.audioPreview.isPlaying = false
        -- KEEP currentFile so the marker stays visible for the correct file
        -- globals.audioPreview.currentFile = nil  -- DON'T clear this or the marker will disappear
        globals.audioPreview.position = globals.audioPreview.startOffset or 0  -- Reset to start instead of 0
        -- KEEP clickedPosition so the marker stays visible and we can resume from there
        -- globals.audioPreview.clickedPosition = nil  -- DON'T clear the click marker
        globals.audioPreview.playbackStartPosition = nil  -- Clear the start position
    end
end

-- Update playback position
function Waveform.updatePlaybackPosition()
    if globals.audioPreview.isPlaying and globals.audioPreview.cfPreview then
        local pos = reaper.CF_Preview_GetValue(globals.audioPreview.cfPreview, 'D_POSITION')
        if pos and type(pos) == "number" then
            globals.audioPreview.position = pos

            -- Check if we've reached the end of the edited portion
            if globals.audioPreview.playbackLength then
                local endPosition = (globals.audioPreview.startOffset or 0) + globals.audioPreview.playbackLength
                if pos >= endPosition then
                    -- Stop and reset to start
                    Waveform.stopPlayback()
                    return
                end
            end
        else
            -- Fallback: calculate position based on elapsed time
            local currentTime = reaper.time_precise()
            local elapsed = currentTime - globals.audioPreview.startTime

            -- Use playbackStartPosition if we started from a clicked position
            -- This ensures the visual position starts at the clicked point
            if globals.audioPreview.playbackStartPosition then
                globals.audioPreview.position = globals.audioPreview.playbackStartPosition + elapsed
            else
                globals.audioPreview.position = (globals.audioPreview.startOffset or 0) + elapsed
            end

            -- Check elapsed time
            if globals.audioPreview.playbackLength then
                -- Calculate remaining time based on where we started
                local effectiveLength = globals.audioPreview.playbackLength
                if globals.audioPreview.clickedPosition then
                    effectiveLength = globals.audioPreview.playbackLength - globals.audioPreview.clickedPosition
                end

                if elapsed >= effectiveLength then
                    Waveform.stopPlayback()
                    return
                end
            end
        end

        local isPlaying = reaper.CF_Preview_GetValue(globals.audioPreview.cfPreview, 'B_PLAY')
        if isPlaying and isPlaying == 0 then
            Waveform.stopPlayback()
        end
    end
end

-- Set preview volume
function Waveform.setPreviewVolume(volume)
    globals.audioPreview.volume = volume

    if globals.audioPreview.cfPreview then
        reaper.CF_Preview_SetValue(globals.audioPreview.cfPreview, 'D_VOLUME', volume)
    end
end

-- Clear saved playback position (marker)
function Waveform.clearSavedPosition()
    if globals.audioPreview then
        globals.audioPreview.clickedPosition = nil
        globals.audioPreview.playbackStartPosition = nil
    end
end

-- Reset position for a specific file
function Waveform.resetPositionForFile(filePath)
    if globals.audioPreview and globals.audioPreview.currentFile == filePath then
        globals.audioPreview.clickedPosition = nil
        globals.audioPreview.playbackStartPosition = nil
        globals.audioPreview.currentFile = nil
    end
end

-- Cleanup on exit
function Waveform.cleanup()
    Waveform.stopPlayback()
end

-- Area management functions

-- Get all areas for a file
function Waveform.getAreas(filePath)
    if not filePath then return {} end
    return globals.waveformAreas[filePath] or {}
end

-- Clear all areas for a file
function Waveform.clearAreas(filePath)
    if filePath and globals.waveformAreas[filePath] then
        globals.waveformAreas[filePath] = nil
    end
end

-- Delete a specific area
function Waveform.deleteArea(filePath, areaIndex)
    if filePath and globals.waveformAreas[filePath] and globals.waveformAreas[filePath][areaIndex] then
        table.remove(globals.waveformAreas[filePath], areaIndex)

        -- Clean up empty area lists
        if #globals.waveformAreas[filePath] == 0 then
            globals.waveformAreas[filePath] = nil
        end
    end
end

-- Rename an area
function Waveform.renameArea(filePath, areaIndex, newName)
    if filePath and globals.waveformAreas[filePath] and globals.waveformAreas[filePath][areaIndex] then
        globals.waveformAreas[filePath][areaIndex].name = newName
    end
end

-- Export areas to a table (for saving)
function Waveform.exportAreas(filePath)
    if not filePath or not globals.waveformAreas[filePath] then
        return nil
    end

    local export = {}
    for i, area in ipairs(globals.waveformAreas[filePath]) do
        table.insert(export, {
            startPos = area.startPos,
            endPos = area.endPos,
            name = area.name
        })
    end

    return export
end

-- Import areas from a table (for loading)
function Waveform.importAreas(filePath, areas)
    if not filePath or not areas then return false end

    globals.waveformAreas[filePath] = {}

    for i, area in ipairs(areas) do
        table.insert(globals.waveformAreas[filePath], {
            startPos = area.startPos,
            endPos = area.endPos,
            name = area.name or string.format("Area %d", i)
        })
    end

    return true
end

-- Get area at position (for click detection)
function Waveform.getAreaAtPosition(filePath, position, length)
    if not filePath or not globals.waveformAreas[filePath] then
        return nil
    end

    for i, area in ipairs(globals.waveformAreas[filePath]) do
        if position >= area.startPos and position <= area.endPos then
            return area, i
        end
    end

    return nil
end

return Waveform