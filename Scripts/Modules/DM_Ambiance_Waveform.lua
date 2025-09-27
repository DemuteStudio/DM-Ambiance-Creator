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
    local useLogScale = options.useLogScale ~= false  -- Use logarithmic scaling for quiet sounds (default true)
    local amplifyQuiet = options.amplifyQuiet or 3.0  -- Amplification factor for quiet sounds

    local cacheKey = filePath .. "_" .. width

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
    local samplerate = reaper.GetMediaSourceSampleRate(source) or 44100
    local totalLength = reaper.GetMediaSourceLength(source, false) or 1
    local numChannels = reaper.GetMediaSourceNumChannels(source) or 1

    -- Use startOffset and displayLength from options if provided
    local startOffset = options.startOffset or 0
    local length = options.displayLength or (totalLength - startOffset)

    -- Ensure we don't exceed file boundaries
    length = math.min(length, totalLength - startOffset)

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

    -- Set the item to match the edited portion
    reaper.SetMediaItemInfo_Value(tempItem, "D_POSITION", 0)
    reaper.SetMediaItemInfo_Value(tempItem, "D_LENGTH", totalLength)  -- Use full length to ensure peaks are available

    local tempTake = reaper.AddTakeToMediaItem(tempItem)
    if not tempTake then
        reaper.DeleteTrackMediaItem(tempTrack, tempItem)
        reaper.PCM_Source_Destroy(source)
        return Waveform.createPlaceholderWaveform(width)
    end

    -- Set source (REAPER takes ownership after this)
    reaper.SetMediaItemTake_Source(tempTake, source)

    -- Build peaks
    reaper.SetMediaItemSelected(tempItem, true)
    reaper.Main_OnCommand(40047, 0) -- Build peaks for selected items
    reaper.UpdateItemInProject(tempItem)

    -- Small delay to let peaks build
    local startTime = reaper.time_precise()
    while reaper.time_precise() - startTime < 0.05 do
        -- wait
    end

    -- Read actual channel count instead of forcing mono
    local n_channels = numChannels  -- Use actual channel count

    -- Calculate how many samples we actually need for the edited portion
    local totalEditedSamples = samplerate * length  -- Total samples in edited portion

    -- Calculate optimal number of samples to request
    -- For short clips, request fewer samples and stretch them
    -- For long clips, request more samples and compress them
    local samplesNeeded

    if totalEditedSamples < width * 100 then
        -- Short clip: request fewer samples (minimum 50 for quality)
        samplesNeeded = math.max(50, math.min(width / 4, totalEditedSamples / 100))
    else
        -- Normal/long clip: request proportional to width
        samplesNeeded = width
    end

    -- Ensure reasonable bounds
    samplesNeeded = math.floor(math.max(50, math.min(samplesNeeded, 2000)))

    local bufsize = samplesNeeded * 2 * n_channels  -- 2 values (max/min) per sample per channel
    local buf = reaper.new_array(bufsize)
    buf.clear()

    -- Calculate samples per peak based on EDITED portion only
    local peakrate = math.max(1, totalEditedSamples / samplesNeeded)

    -- Debug to verify we're getting the right portion (commented for production)
    -- reaper.ShowConsoleMsg(string.format("  Edited duration: %.3fs, Total samples: %d, Samples needed: %d, Peakrate: %.2f\n",
    --     length, totalEditedSamples, samplesNeeded, peakrate))

    local retval = reaper.GetMediaItemTake_Peaks(
        tempTake,
        peakrate,        -- samples per peak
        startOffset,     -- start time (use the offset from options)
        n_channels,      -- Use actual channel count
        samplesNeeded,   -- number of samples we want
        0,               -- want_extra_type (0 = min/max peaks)
        buf
    )

    -- Extract the actual number of samples returned
    local spl_cnt = retval % 1048576  -- Lower 20 bits

    -- Debug output (commented for production)
    -- reaper.ShowConsoleMsg(string.format("[Waveform] File: %s\n", filePath or "nil"))
    -- reaper.ShowConsoleMsg(string.format("  Length: %.2fs, Samplerate: %d, Channels: %d\n", length, samplerate, n_channels))
    -- reaper.ShowConsoleMsg(string.format("  Width: %d, Requested: %d, Returned: %d, Peakrate: %.2f\n",
    --     width, samplesNeeded, spl_cnt, peakrate))

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
            local actualSamples = math.min(spl_cnt, samplesNeeded)

            -- Debug output for edited portion (commented for production)
            -- reaper.ShowConsoleMsg(string.format("  Buffer size: %d, Using samples: %d\n",
            --     #peaks_table, actualSamples))
            -- reaper.ShowConsoleMsg(string.format("  Waveform width: %d pixels\n", width))

            -- IMPORTANT: Data is organized in BLOCKS, not interleaved per sample!
            -- First block: ALL maximums (interleaved by channel)
            -- Second block: ALL minimums (interleaved by channel)

            local max_block_start = 1  -- Lua arrays start at 1
            local min_block_start = (actualSamples * n_channels) + 1

            for i = 1, actualSamples do
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

                        -- Debug first and last samples (commented for production)
                        -- if i <= 3 or i >= actualSamples - 2 then
                        --     reaper.ShowConsoleMsg(string.format("  Sample %d, Ch %d: max=%.4f, min=%.4f\n",
                        --         i, ch, maxVal, minVal))
                        -- end
                    else
                        -- Fill with zeros if we run out of data
                        peaks.channels[ch].max[i] = 0
                        peaks.channels[ch].min[i] = 0
                        peaks.channels[ch].rms[i] = 0
                    end
                end
            end

            -- No padding needed - we're now using interpolation to stretch/compress
            -- The drawing code will handle mapping fewer samples to more pixels

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
            local retval_mono = reaper.GetMediaItemTake_Peaks(
                tempTake,
                peakrate,
                startOffset,     -- Use the same startOffset
                1,               -- Force mono
                samplesNeeded,
                0,
                buf
            )

            local spl_cnt_mono = retval_mono % 1048576
            if spl_cnt_mono > 0 then
                local peaks_table = buf.table()
                if peaks_table and #peaks_table > 0 then
                    -- For mono: first half is max values, second half is min values
                    local max_offset = 1  -- Lua arrays start at 1
                    local min_offset = spl_cnt_mono + 1

                    -- Read mono data and duplicate to all channels
                    local samplesToRead = math.min(spl_cnt_mono, samplesNeeded)
                    for i = 1, samplesToRead do
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
                    if samplesToRead ~= width then
                        for ch = 1, n_channels do
                            local interpolated = {min = {}, max = {}, rms = {}}

                            for pixelIdx = 1, width do
                                local samplePos = ((pixelIdx - 1) / (width - 1)) * (samplesToRead - 1) + 1
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
                                else
                                    interpolated.max[pixelIdx] = peaks.channels[ch].max[samplesToRead] or 0
                                    interpolated.min[pixelIdx] = peaks.channels[ch].min[samplesToRead] or 0
                                    interpolated.rms[pixelIdx] = peaks.channels[ch].rms[samplesToRead] or 0
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

            -- Set backward compatibility
            local numSamplesUsed = math.min(spl_cnt_mono, samplesNeeded)
            for i = 1, numSamplesUsed do
                peaks.max[i] = peaks.channels[1] and peaks.channels[1].max[i] or 0
                peaks.min[i] = peaks.channels[1] and peaks.channels[1].min[i] or 0
                peaks.rms[i] = peaks.channels[1] and peaks.channels[1].rms[i] or 0
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

    -- Draw each channel
    local peaks = waveformData.peaks
    local channelColors = {
        0x00FF00FF,  -- Green for channel 1 (or mono)
        0x00FFFFFF,  -- Cyan for channel 2
        0xFF8800FF,  -- Orange for channel 3
        0xFF00FFFF,  -- Magenta for channel 4
        0xFFFF00FF,  -- Yellow for channel 5
        0x8888FFFF,  -- Light blue for channel 6
        0xFF8888FF,  -- Light red for channel 7
        0xFFFFFFFF,  -- White for channel 8
    }

    local rmsColors = {
        0x008800FF,  -- Dark green for channel 1 RMS
        0x008888FF,  -- Dark cyan for channel 2 RMS
        0x884400FF,  -- Dark orange for channel 3 RMS
        0x880088FF,  -- Dark magenta for channel 4 RMS
        0x888800FF,  -- Dark yellow for channel 5 RMS
        0x444488FF,  -- Dark light blue for channel 6 RMS
        0x884444FF,  -- Dark light red for channel 7 RMS
        0x888888FF,  -- Gray for channel 8 RMS
    }

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
            local numSamples = #channelPeaks.max
            local channelDrawHeight = channelHeight - channelSpacing

            -- Draw using polyline for smoother waveform
            local polyline_max = {}
            local polyline_min = {}
            local point_count = 0

            for pixel = 1, width do
                local x = pos_x + pixel - 1

                -- Map pixel position to sample position with stretching/compression
                local samplePos
                if width > 1 then
                    samplePos = ((pixel - 1) / (width - 1)) * (numSamples - 1) + 1
                else
                    samplePos = 1  -- Single pixel case
                end
                local sampleIndex = math.floor(samplePos)
                local fraction = samplePos - sampleIndex

                local maxVal = 0
                local minVal = 0

                if sampleIndex < numSamples then
                    -- Linear interpolation for smooth stretching
                    local max1 = channelPeaks.max[sampleIndex] or 0
                    local max2 = channelPeaks.max[math.min(sampleIndex + 1, numSamples)] or 0
                    local min1 = channelPeaks.min[sampleIndex] or 0
                    local min2 = channelPeaks.min[math.min(sampleIndex + 1, numSamples)] or 0

                    maxVal = max1 + (max2 - max1) * fraction
                    minVal = min1 + (min2 - min1) * fraction
                elseif sampleIndex == numSamples then
                    maxVal = channelPeaks.max[numSamples] or 0
                    minVal = channelPeaks.min[numSamples] or 0
                else
                    -- Beyond available data
                    maxVal = 0
                    minVal = 0
                end

                -- Draw vertical line from min to max
                local topY = centerY - (maxVal * channelDrawHeight / 2)
                local bottomY = centerY - (minVal * channelDrawHeight / 2)

                imgui.DrawList_AddLine(draw_list,
                    x, topY,
                    x, bottomY,
                    channelColors[ch] or channelColors[1],
                    1
                )

                -- Draw RMS with interpolation
                if sampleIndex < numSamples then
                    local rms1 = channelPeaks.rms[sampleIndex] or 0
                    local rms2 = channelPeaks.rms[math.min(sampleIndex + 1, numSamples)] or 0
                    local rmsVal = rms1 + (rms2 - rms1) * fraction

                    if math.abs(rmsVal) > 0.01 then
                        imgui.DrawList_AddLine(draw_list,
                            x, centerY - (rmsVal * channelDrawHeight / 2),
                            x, centerY + (rmsVal * channelDrawHeight / 2),
                            rmsColors[ch] or rmsColors[1],
                            1
                        )
                    end
                elseif sampleIndex == numSamples then
                    local rmsVal = channelPeaks.rms[numSamples] or 0
                    if math.abs(rmsVal) > 0.01 then
                        imgui.DrawList_AddLine(draw_list,
                            x, centerY - (rmsVal * channelDrawHeight / 2),
                            x, centerY + (rmsVal * channelDrawHeight / 2),
                            rmsColors[ch] or rmsColors[1],
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

    -- Draw playback position if playing
    if globals.audioPreview.isPlaying and globals.audioPreview.currentFile == filePath then
        local position = globals.audioPreview.position
        local startOffset = waveformData.startOffset or 0
        if position and type(position) == "number" and waveformData.length and waveformData.length > 0 then
            -- Calculate relative position within the displayed portion
            local relativePos = position - startOffset
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

    -- Draw border
    imgui.DrawList_AddRect(draw_list,
        pos_x, pos_y,
        pos_x + width, pos_y + height,
        0x606060FF,
        0, 0, 1
    )

    -- Reserve space
    imgui.Dummy(ctx, width, height)

    return waveformData
end

-- Clear cache for a specific file
function Waveform.clearFileCache(filePath)
    if filePath and filePath ~= "" then
        for key, _ in pairs(globals.waveformCache) do
            if key:sub(1, #filePath) == filePath then
                globals.waveformCache[key] = nil
            end
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
function Waveform.startPlayback(filePath, startOffset, length)
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

        reaper.CF_Preview_SetValue(preview, 'D_VOLUME', globals.audioPreview.volume or 0.7)
        reaper.CF_Preview_SetValue(preview, 'D_POSITION', startOffset or 0)
        reaper.CF_Preview_SetValue(preview, 'B_LOOP', 0)

        reaper.CF_Preview_Play(preview)

        globals.audioPreview.isPlaying = true
        globals.audioPreview.currentFile = filePath
        globals.audioPreview.startTime = reaper.time_precise()
        globals.audioPreview.position = startOffset or 0
        globals.audioPreview.startOffset = startOffset or 0

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
        globals.audioPreview.currentFile = nil
        globals.audioPreview.position = 0
    end
end

-- Update playback position
function Waveform.updatePlaybackPosition()
    if globals.audioPreview.isPlaying and globals.audioPreview.cfPreview then
        local pos = reaper.CF_Preview_GetValue(globals.audioPreview.cfPreview, 'D_POSITION')
        if pos and type(pos) == "number" then
            globals.audioPreview.position = pos
        else
            local currentTime = reaper.time_precise()
            local elapsed = currentTime - globals.audioPreview.startTime
            globals.audioPreview.position = (globals.audioPreview.startOffset or 0) + elapsed
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

-- Cleanup on exit
function Waveform.cleanup()
    Waveform.stopPlayback()
end

return Waveform