--[[
@version 1.0
@noindex
--]]

local Waveform = {}
local globals = {}

-- Initialize the module with global variables from the main script
function Waveform.initModule(g)
    if not g then
        error("Waveform.initModule: globals parameter is required")
    end
    globals = g
    
    -- Initialize waveform-related globals
    globals.selectedItemIndex = {}  -- Per container: {[groupIndex_containerIndex] = itemIndex}
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

-- Generate .reapeaks file for external audio file
function Waveform.generateReapeaksFile(filePath)
    reaper.ShowConsoleMsg("[Waveform] Generating .reapeaks file for: " .. filePath .. "\n")
    
    -- Create PCM source from file
    local source = reaper.PCM_Source_CreateFromFile(filePath)
    if not source then
        reaper.ShowConsoleMsg("[Waveform] Failed to create source for peak generation\n")
        return false
    end
    
    -- Build peaks using REAPER's built-in function
    -- This creates the .reapeaks file in the same directory as the audio file
    local retval = reaper.PCM_Source_BuildPeaks(source, 0)  -- mode 0 = build now
    
    if retval == 0 then
        reaper.ShowConsoleMsg("[Waveform] Successfully built peaks file\n")
        reaper.PCM_Source_Destroy(source)
        return true
    else
        reaper.ShowConsoleMsg("[Waveform] Failed to build peaks file\n")
        reaper.PCM_Source_Destroy(source)
        return false
    end
end


-- Get cached waveform data or generate new one
function Waveform.getWaveformData(filePath, width)
    -- Validate inputs
    if not filePath or filePath == "" then
        -- Return a simple placeholder waveform
        reaper.ShowConsoleMsg("[Waveform] No file path provided\n")
        return Waveform.createPlaceholderWaveform(width)
    end
    
    width = math.floor(tonumber(width) or 400)
    if width <= 0 then width = 400 end
    
    local cacheKey = filePath .. "_" .. width
    
    -- Check cache first
    if globals.waveformCache[cacheKey] then
        -- Check if cached data is a placeholder (invalid data)
        if globals.waveformCache[cacheKey].isPlaceholder then
            reaper.ShowConsoleMsg("[Waveform] Cached data is placeholder, regenerating for: " .. filePath .. "\n")
            globals.waveformCache[cacheKey] = nil
        else
            reaper.ShowConsoleMsg("[Waveform] Using cached data for: " .. filePath .. "\n")
            return globals.waveformCache[cacheKey]
        end
    end
    
    reaper.ShowConsoleMsg("[Waveform] Generating new waveform for: " .. filePath .. "\n")
    
    -- Skip reading .reapeaks directly - it's too complex
    -- Instead, always use PCM_Source_GetPeaks which will use the .reapeaks if available
    reaper.ShowConsoleMsg("[Waveform] Using PCM_Source_GetPeaks (will use .reapeaks if available)\n")
    
    -- Check if file exists
    local file = io.open(filePath, "r")
    if not file then
        -- File doesn't exist, return placeholder waveform
        reaper.ShowConsoleMsg("[Waveform] File not found: " .. filePath .. "\n")
        return Waveform.createPlaceholderWaveform(width)
    end
    file:close()
    reaper.ShowConsoleMsg("[Waveform] File exists, proceeding with peak generation\n")
    
    -- Generate waveform data using PCM_Source_GetPeaks
    local source = reaper.PCM_Source_CreateFromFile(filePath)
    if not source then
        -- Could not create source, return placeholder
        reaper.ShowConsoleMsg("[Waveform] Failed to create PCM_Source from file\n")
        return Waveform.createPlaceholderWaveform(width)
    end
    
    -- Declare variables upfront for linter clarity
    local samplerate, length, numChannels
    
    -- Get source info
    samplerate = reaper.GetMediaSourceSampleRate(source)
    length = reaper.GetMediaSourceLength(source, false)
    numChannels = reaper.GetMediaSourceNumChannels(source)
    
    reaper.ShowConsoleMsg(string.format("[Waveform] Source info - Rate: %.0f, Length: %.2f, Channels: %d\n", 
        samplerate or 0, length or 0, numChannels or 0))
    
    -- Validate source info
    if not samplerate or samplerate <= 0 then samplerate = 44100 end
    if not length or length <= 0 then length = 1 end
    if not numChannels or numChannels <= 0 then numChannels = 1 end
    
    -- Ensure width is valid
    width = math.floor(width)
    if width <= 0 then width = 400 end
    
    -- Create peaks array
    local peaks = {
        min = {},
        max = {},
        rms = {}
    }
    
    -- First, ensure the .reapeaks file exists
    local peaksFilePath = filePath .. ".reapeaks"
    local peaksFileExists = io.open(peaksFilePath, "rb")
    if not peaksFileExists then
        reaper.ShowConsoleMsg("[Waveform] Building .reapeaks file first...\n")
        -- Build peaks directly on this source
        reaper.PCM_Source_BuildPeaks(source, 0)
    else
        peaksFileExists:close()
        reaper.ShowConsoleMsg("[Waveform] .reapeaks file exists\n")
        -- Even if file exists, ensure peaks are loaded in source
        reaper.PCM_Source_BuildPeaks(source, 2)  -- mode 2 = build if not built
    end
    
    -- Try using PCM_Source_GetPeaks if available (it will use the .reapeaks)
    if reaper.PCM_Source_GetPeaks then
        reaper.ShowConsoleMsg("[Waveform] Using PCM_Source_GetPeaks\n")
        
        -- Create buffer for peaks - need more space for proper format
        local bufSize = width * 2 * numChannels  -- min/max pairs per channel
        local buf = reaper.new_array(bufSize)
        buf.clear()
        
        -- Calculate samples per peak
        local samplesPerPeak = (samplerate * length) / width
        reaper.ShowConsoleMsg(string.format("[Waveform] Samples per peak: %.2f\n", samplesPerPeak))
        
        -- Get peaks directly from source
        local retval = reaper.PCM_Source_GetPeaks(
            source,           -- PCM_source
            samplesPerPeak,   -- peakrate (samples per peak)
            0,                -- starttime
            numChannels,      -- numchannels
            width,            -- numsamplesperchannel  
            0,                -- want_extra_type (0 = normal peaks)
            buf               -- buffer
        )
        
        reaper.ShowConsoleMsg(string.format("[Waveform] PCM_Source_GetPeaks returned: %d\n", retval or 0))
        
        -- Decode the return value (same format as GetMediaItemTake_Peaks)
        -- Lower 20 bits = sample count
        local spl_cnt = retval % 1048576
        reaper.ShowConsoleMsg(string.format("[Waveform] Decoded sample count: %d\n", spl_cnt))
        
        if spl_cnt > 0 then
            local peaks_table = buf.table()
            reaper.ShowConsoleMsg(string.format("[Waveform] Buffer size: %d\n", peaks_table and #peaks_table or 0))
            
            if peaks_table and #peaks_table > 0 then
                -- Log first few values for debugging
                reaper.ShowConsoleMsg("[Waveform] First 10 buffer values: ")
                for i = 1, math.min(10, #peaks_table) do
                    reaper.ShowConsoleMsg(string.format("%.4f ", peaks_table[i]))
                end
                reaper.ShowConsoleMsg("\n")
                
                -- Try accessing buffer directly if table is empty
                if peaks_table[1] == 0 and peaks_table[2] == 0 then
                    reaper.ShowConsoleMsg("[Waveform] Buffer seems empty, trying direct access\n")
                    -- Try to access the buffer differently
                    for i = 0, math.min(10, bufSize-1) do
                        local val = buf[i]
                        if val and val ~= 0 then
                            reaper.ShowConsoleMsg(string.format("[Waveform] buf[%d] = %.4f\n", i, val))
                        end
                    end
                end
                
                -- Parse the peaks data (format depends on function)
                -- PCM_Source_GetPeaks might return data differently than GetMediaItemTake_Peaks
                local samples_to_read = math.min(spl_cnt, width)
                
                for i = 1, samples_to_read do
                    -- Try different indexing - PCM_Source_GetPeaks might use different format
                    local idx = (i - 1) * 2 + 1
                    if idx + 1 <= #peaks_table then
                        -- Try both min/max and max/min order
                        local val1 = peaks_table[idx] or 0
                        local val2 = peaks_table[idx + 1] or 0
                        
                        -- Ensure proper min/max assignment
                        if val1 < val2 then
                            peaks.min[i] = val1
                            peaks.max[i] = val2
                        else
                            peaks.min[i] = val2
                            peaks.max[i] = val1
                        end
                        
                        peaks.rms[i] = (math.abs(peaks.max[i]) + math.abs(peaks.min[i])) / 2 * 0.7
                    else
                        peaks.max[i] = 0
                        peaks.min[i] = 0
                        peaks.rms[i] = 0
                    end
                end
                
                -- Check if we got valid data
                local hasData = false
                for i = 1, math.min(10, width) do
                    if math.abs(peaks.max[i]) > 0.001 or math.abs(peaks.min[i]) > 0.001 then
                        hasData = true
                        break
                    end
                end
                
                reaper.ShowConsoleMsg(string.format("[Waveform] Has valid peak data: %s\n", tostring(hasData)))
                
                reaper.PCM_Source_Destroy(source)
                
                local waveformData = {
                    peaks = peaks,
                    length = length,
                    numChannels = numChannels,
                    samplerate = samplerate,
                    isPlaceholder = false
                }
                
                globals.waveformCache[cacheKey] = waveformData
                reaper.ShowConsoleMsg("[Waveform] Successfully generated peaks with PCM_Source_GetPeaks\n")
                return waveformData
            end  -- End of if peaks_table and #peaks_table > 0
        else
            reaper.ShowConsoleMsg("[Waveform] No peak data in buffer\n")
        end  -- End of if peaks_table
    else
        reaper.ShowConsoleMsg("[Waveform] PCM_Source_GetPeaks returned no samples\n")
    end  -- End of if spl_cnt > 0
    end  -- End of if reaper.PCM_Source_GetPeaks
    
    -- Fallback: Calculate samples per pixel for fallback method
    local totalSamples = samplerate * length
    local samplesPerPixel = math.max(1, math.floor(totalSamples / width))
    
    -- Use temporary item to get waveform peaks
    -- Find or create a track for temporary use
    local tempTrack = nil
    local trackCount = reaper.CountTracks(0)
    
    if trackCount > 0 then
        tempTrack = reaper.GetTrack(0, 0)
    end
    
    if not tempTrack then
        reaper.InsertTrackAtIndex(0, false)
        tempTrack = reaper.GetTrack(0, 0)
    end
    
    if not tempTrack then
        reaper.ShowConsoleMsg("[Waveform] Failed to create/find temp track\n")
        reaper.PCM_Source_Destroy(source)
        return Waveform.createPlaceholderWaveform(width)
    end
    
    local tempItem = reaper.AddMediaItemToTrack(tempTrack)
    if not tempItem then
        -- Destroy source and return placeholder data
        reaper.ShowConsoleMsg("[Waveform] Failed to create temp item\n")
        reaper.PCM_Source_Destroy(source)
        return Waveform.createPlaceholderWaveform(width)
    end
    
    -- Position the item at time 0 for consistency
    reaper.SetMediaItemInfo_Value(tempItem, "D_POSITION", 0)
    reaper.SetMediaItemInfo_Value(tempItem, "D_LENGTH", length)
    
    local tempTake = reaper.AddTakeToMediaItem(tempItem)
    if not tempTake then
        reaper.DeleteTrackMediaItem(tempTrack, tempItem)
        -- Source is still owned by us at this point, so we must destroy it
        if source and type(source) == "userdata" then
            local success = pcall(function() reaper.PCM_Source_Destroy(source) end)
            if not success then
                -- Source might already be invalid, continue anyway
            end
        end
        return Waveform.createPlaceholderWaveform(width)
    end
    
    -- Set the source for the take
    reaper.SetMediaItemTake_Source(tempTake, source)
    -- IMPORTANT: After SetMediaItemTake_Source, REAPER owns the source
    -- We should NOT call PCM_Source_Destroy on it anymore
    
    -- Select the item to build peaks
    reaper.SetMediaItemSelected(tempItem, true)
    
    -- Build peaks for the item - try multiple methods
    reaper.Main_OnCommand(40047, 0) -- Build peaks for selected items
    reaper.Main_OnCommand(40048, 0) -- Build missing peaks
    
    -- Update arrange view to ensure item is ready  
    reaper.UpdateArrange()
    reaper.UpdateItemInProject(tempItem)
    
    -- Wait a bit for peaks to build
    local startTime = reaper.time_precise()
    while reaper.time_precise() - startTime < 0.1 do
        -- Small delay to let peaks build
    end
    
    -- Get peaks using REAPER's built-in peak functions
    local n_chans = math.floor(numChannels)
    local want_extra_type = 0 -- 0 for peaks, 1 for spectral data
    
    -- Validate channel count
    if n_chans <= 0 then n_chans = 1 end
    
    -- Calculate buffer size for peaks (2 values per sample per channel: min and max)
    local bufferSize = math.floor(width * 2 * n_chans)
    if bufferSize <= 0 then bufferSize = 800 end
    
    reaper.ShowConsoleMsg(string.format("[Waveform] Channels: %d, Width: %d, BufferSize: %d\n", n_chans, width, bufferSize))
    
    -- Try to create buffer, with error handling
    local buf
    local success, err = pcall(function()
        buf = reaper.new_array(bufferSize)
    end)
    
    if not success or not buf then
        -- Fallback if buffer creation fails
        reaper.ShowConsoleMsg("[Waveform] Buffer creation failed, using fallback\n")
        buf = reaper.new_array(800)  -- Use a safe default size
        n_chans = 1
        width = 400
    end
    
    -- Get peak samples
    -- Make sure buffer is initialized
    buf.clear()
    
    -- Force update to build peaks
    reaper.UpdateItemInProject(tempItem)
    
    -- Calculate the peak rate (samples per peak point)
    -- GetMediaItemTake_Peaks wants the number of source samples per output sample
    local peakrate = totalSamples / width
    
    reaper.ShowConsoleMsg(string.format("[Waveform] PeakRate: %.2f, SampleRate: %.0f, TotalSamples: %.0f, Width: %d\n", 
        peakrate, samplerate, totalSamples, width))
    
    -- Call GetMediaItemTake_Peaks
    local retval = reaper.GetMediaItemTake_Peaks(
        tempTake,
        peakrate,
        0,        -- starttime
        n_chans,  -- numchannels  
        width,    -- numsamplesperchannel
        want_extra_type,
        buf
    )
    
    -- Extract sample count and check if successful
    -- Use math operations for compatibility (bit operations need Lua 5.3+)
    local spl_cnt = retval % 1048576  -- Lower 20 bits (0xfffff + 1)
    local ext_type = math.floor(retval / 16777216) % 2  -- Bit 24
    local out_mode = math.floor(retval / 1048576) % 16  -- Bits 20-23
    
    reaper.ShowConsoleMsg(string.format("[Waveform] GetMediaItemTake_Peaks retval: %d, spl_cnt: %d\n", retval, spl_cnt))
    
    if spl_cnt > 0 then
        -- Process the peak data - try direct buffer access
        reaper.ShowConsoleMsg(string.format("[Waveform] Processing %d samples\n", spl_cnt))
        
        -- Access buffer directly instead of using table()
        local hasData = false
        for i = 1, width do
            local idx = (i - 1) * 2
            local min_val = buf[idx] or 0
            local max_val = buf[idx + 1] or 0
            
            -- Store peaks
            peaks.min[i] = min_val
            peaks.max[i] = max_val
            peaks.rms[i] = (math.abs(min_val) + math.abs(max_val)) / 2 * 0.7
            
            if math.abs(min_val) > 0.001 or math.abs(max_val) > 0.001 then
                hasData = true
            end
        end
        
        reaper.ShowConsoleMsg(string.format("[Waveform] Direct buffer access - has data: %s\n", tostring(hasData)))
        
        -- If direct access didn't work, try table method
        if not hasData then
            local peaks_table = buf.table()
            
            reaper.ShowConsoleMsg(string.format("[Waveform] Trying table method - size: %d\n", peaks_table and #peaks_table or 0))
            
            if peaks_table and #peaks_table > 0 then
            -- GetMediaItemTake_Peaks returns data differently than expected
            -- For mono: [max1, min1, max2, min2, ...]
            -- For stereo: More complex interleaving
            
            -- Simplified approach for mono/stereo
            local samples_to_read = math.min(spl_cnt, width)
            
            -- Log first few raw values for debugging  
            reaper.ShowConsoleMsg("[Waveform] First 10 raw buffer values: ")
            for i = 1, math.min(10, #peaks_table) do
                reaper.ShowConsoleMsg(string.format("%.6f ", peaks_table[i]))
            end
            reaper.ShowConsoleMsg("\n")
            
            -- Try direct buffer access if table is empty
            if #peaks_table > 0 and peaks_table[1] == 0 and peaks_table[2] == 0 then
                reaper.ShowConsoleMsg("[Waveform] Table values are zero, trying direct buffer access\n")
                -- Access buffer elements directly
                for i = 0, math.min(20, bufferSize - 1) do
                    local val = buf[i]
                    if val ~= 0 then
                        reaper.ShowConsoleMsg(string.format("[Waveform] Found non-zero at buf[%d] = %.6f\n", i, val))
                    end
                end
            end
            
            if n_chans == 1 then
                -- Mono: pairs of max/min values
                for i = 1, samples_to_read do
                    local idx = (i - 1) * 2 + 1
                    if idx <= #peaks_table and (idx + 1) <= #peaks_table then
                        peaks.max[i] = peaks_table[idx] or 0
                        peaks.min[i] = peaks_table[idx + 1] or 0
                    else
                        peaks.max[i] = 0
                        peaks.min[i] = 0
                    end
                    peaks.rms[i] = (math.abs(peaks.min[i]) + math.abs(peaks.max[i])) / 2 * 0.7
                end
            else
                -- Stereo or multi-channel: try simple averaging
                for i = 1, samples_to_read do
                    local idx = (i - 1) * 2 * n_chans + 1
                    local max_val = 0
                    local min_val = 0
                    
                    -- Average across channels
                    for ch = 0, n_chans - 1 do
                        local max_idx = idx + ch * 2
                        local min_idx = max_idx + 1
                        if max_idx <= #peaks_table and min_idx <= #peaks_table then
                            max_val = max_val + (peaks_table[max_idx] or 0)
                            min_val = min_val + (peaks_table[min_idx] or 0)
                        end
                    end
                    
                    peaks.max[i] = max_val / n_chans
                    peaks.min[i] = min_val / n_chans
                    peaks.rms[i] = (math.abs(peaks.min[i]) + math.abs(peaks.max[i])) / 2 * 0.7
                end
            end
            
            -- If we have fewer samples than display width, we need to ensure proper indexing
            -- Store the actual number of valid samples
            local actualSamples = samples_to_read
            
            -- Find the maximum peak value to determine normalization
            local maxPeak = 0
            local hasValidData = false
            local validSampleCount = 0
            
            for i = 1, samples_to_read do
                if peaks.max[i] and peaks.min[i] then
                    local absMax = math.abs(peaks.max[i])
                    local absMin = math.abs(peaks.min[i])
                    
                    -- Check if we have any non-zero data
                    if absMax > 0.0001 or absMin > 0.0001 then
                        hasValidData = true
                        validSampleCount = validSampleCount + 1
                    end
                    
                    maxPeak = math.max(maxPeak, absMax, absMin)
                end
            end
            
            reaper.ShowConsoleMsg(string.format("[Waveform] HasValidData: %s, MaxPeak: %.6f, ValidSamples: %d/%d\n", 
                tostring(hasValidData), maxPeak, validSampleCount, samples_to_read))
            
            -- If we have valid data but it's too small, normalize aggressively
            if hasValidData then
                -- If peaks are extremely small (less than 0.01), they're probably in the wrong scale
                if maxPeak < 0.01 then
                    -- This might be dB values or very quiet audio
                    -- Convert assuming values might be in dB (where -60dB = 0.001)
                    for i = 1, actualSamples do
                        if peaks.max[i] and peaks.max[i] ~= 0 then
                            peaks.max[i] = math.pow(10, peaks.max[i] / 20) 
                        end
                        if peaks.min[i] and peaks.min[i] ~= 0 then
                            peaks.min[i] = math.pow(10, peaks.min[i] / 20)
                        end
                    end
                    
                    -- Recalculate max peak after conversion
                    maxPeak = 0
                    for i = 1, actualSamples do
                        if peaks.max[i] and peaks.min[i] then
                            maxPeak = math.max(maxPeak, math.abs(peaks.max[i]), math.abs(peaks.min[i]))
                        end
                    end
                end
                
                -- Always normalize to use full available height
                if maxPeak > 0 then
                    -- Normalize to 90% of full scale for better visibility
                    local normalizeAmount = 0.9 / maxPeak
                    
                    for i = 1, samples_to_read do
                        peaks.max[i] = peaks.max[i] * normalizeAmount
                        peaks.min[i] = peaks.min[i] * normalizeAmount
                        peaks.rms[i] = math.abs(peaks.max[i] - peaks.min[i]) * 0.35
                    end
                end
            else
                -- No valid data, don't create test waveform - leave empty to debug
                reaper.ShowConsoleMsg("[Waveform] WARNING: No valid peak data found!\n")
                -- for i = 1, width do
                --     local t = (i / width) * math.pi * 4
                --     peaks.max[i] = math.sin(t) * 0.5
                --     peaks.min[i] = -math.sin(t) * 0.5
                --     peaks.rms[i] = math.abs(math.sin(t)) * 0.35
                -- end
            end
            
            retval = 1  -- Mark as successful
        else
            -- No valid peak data
            retval = 0
        end
    else
        retval = 0
    end
    
    -- If peaks retrieval failed completely (no data at all)
    if retval == 0 or (peaks.max[1] == 0 and peaks.max[2] == 0) then
        reaper.ShowConsoleMsg("[Waveform] Peak retrieval failed, generating simple waveform\n")
        -- Generate a simple waveform based on file properties
        math.randomseed(math.floor(samplerate + length * 1000))
        
        for i = 1, width do
            -- Create a simple waveform with some variation
            local t = (i / width) * math.pi * 8
            local envelope = math.sin((i / width) * math.pi) -- Fade in/out
            local noise = (math.random() - 0.5) * 0.3
            
            local val = (math.sin(t) * 0.4 + noise) * envelope
            
            peaks.max[i] = math.abs(val)
            peaks.min[i] = -math.abs(val)
            peaks.rms[i] = math.abs(val) * 0.7
        end
        
        reaper.ShowConsoleMsg("[Waveform] Generated fallback waveform\n")
    end
    
    -- Final check: ensure we have valid peak data
    local numPeaks = #peaks.max
    if numPeaks == 0 then
        -- No peaks at all, create minimal placeholder
        for i = 1, 10 do
            peaks.min[i] = 0
            peaks.max[i] = 0
            peaks.rms[i] = 0
        end
    end
    
    -- Clean up temporary item (this will also destroy the source automatically)
    if tempTrack and tempItem then
        reaper.DeleteTrackMediaItem(tempTrack, tempItem)
    end
    
    -- Source is automatically destroyed when the item is deleted
    -- No need to call PCM_Source_Destroy here
    
    -- Check if we actually got valid data
    local hasAnyData = false
    for i = 1, #peaks.max do
        if peaks.max[i] and (math.abs(peaks.max[i]) > 0.0001 or math.abs(peaks.min[i] or 0) > 0.0001) then
            hasAnyData = true
            break
        end
    end
    
    local waveformData = {
        peaks = peaks,
        length = length,
        numChannels = numChannels,
        samplerate = samplerate,
        isPlaceholder = not hasAnyData  -- Mark as placeholder if no valid data
    }
    
    -- Only cache if we have valid data
    if hasAnyData then
        globals.waveformCache[cacheKey] = waveformData
        reaper.ShowConsoleMsg("[Waveform] Cached valid waveform data\n")
    else
        reaper.ShowConsoleMsg("[Waveform] Not caching - no valid data found\n")
    end
    
    return waveformData
end

-- Draw waveform using ImGui DrawList
function Waveform.drawWaveform(filePath, width, height)
    local ctx = globals.ctx
    local imgui = globals.imgui
    
    -- Validate inputs
    width = math.floor(tonumber(width) or 400)
    height = math.floor(tonumber(height) or 100)
    if width <= 0 then width = 400 end
    if height <= 0 then height = 100 end
    
    -- Get waveform data
    local waveformData = Waveform.getWaveformData(filePath, width)
    if not waveformData then
        imgui.Text(ctx, "Unable to load waveform")
        return nil
    end
    
    -- Get drawing position
    local draw_list = imgui.GetWindowDrawList(ctx)
    local pos_x, pos_y = imgui.GetCursorScreenPos(ctx)
    
    -- Draw background
    imgui.DrawList_AddRectFilled(draw_list,
        pos_x, pos_y,
        pos_x + width, pos_y + height,
        0x1A1A1AFF
    )
    
    -- Draw waveform
    local centerY = pos_y + height / 2
    local peaks = waveformData.peaks
    
    -- Draw zero line
    imgui.DrawList_AddLine(draw_list,
        pos_x, centerY,
        pos_x + width, centerY,
        0x404040FF,
        1
    )
    
    -- Draw waveform peaks
    if peaks and peaks.max and #peaks.max > 0 then
        local numSamples = #peaks.max
        -- Scale the samples to fit the display width
        for pixel = 1, width do
            -- Map pixel position to sample index with proper scaling
            -- pixel goes from 1 to width, we need to map to 1 to numSamples
            local sampleProgress = (pixel - 1) / width
            local sampleIndex = math.floor(sampleProgress * numSamples) + 1
            sampleIndex = math.max(1, math.min(sampleIndex, numSamples))
            
            local x = pos_x + pixel - 1
            
            -- Get values safely
            local minVal = peaks.min[sampleIndex] or 0
            local maxVal = peaks.max[sampleIndex] or 0
            local rmsVal = peaks.rms[sampleIndex] or 0
            
            local minY = centerY - (minVal * height / 2)
            local maxY = centerY - (maxVal * height / 2)
            
            -- Draw peak line
            imgui.DrawList_AddLine(draw_list,
                x, minY,
                x, maxY,
                0x00FF00FF,
                1
            )
            
            -- Draw RMS (darker green)
            imgui.DrawList_AddLine(draw_list,
                x, centerY - (rmsVal * height / 2),
                x, centerY + (rmsVal * height / 2),
                0x008800FF,
                1
            )
        end
    end
    
    -- Draw playback position if playing
    if globals.audioPreview.isPlaying and globals.audioPreview.currentFile == filePath then
        local position = globals.audioPreview.position
        if position and type(position) == "number" and waveformData.length and waveformData.length > 0 then
            local playPos = (position / waveformData.length) * width
            imgui.DrawList_AddLine(draw_list,
                pos_x + playPos, pos_y,
                pos_x + playPos, pos_y + height,
                0xFFFFFFFF,
                2
            )
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

-- Create temporary preview track for audio playback
function Waveform.getOrCreatePreviewTrack()
    local trackName = "AMBIANCE_PREVIEW_TRACK"
    
    -- Look for existing preview track
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local _, name = reaper.GetTrackName(track)
        if name == trackName then
            return track
        end
    end
    
    -- Create new preview track at the end
    local trackIndex = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(trackIndex, false)
    local track = reaper.GetTrack(0, trackIndex)
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", trackName, true)
    
    -- Set track to not be visible in mixer and arrange
    reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
    reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
    
    -- Set volume
    reaper.SetMediaTrackInfo_Value(track, "D_VOL", globals.audioPreview.volume)
    
    return track
end

-- Start audio playback using CF_Preview API for isolated playback
function Waveform.startPlayback(filePath, startOffset, length)
    -- Validate inputs
    if not filePath or filePath == "" then
        return false
    end
    
    -- Stop current playback if any
    Waveform.stopPlayback()
    
    -- Check if file exists before trying to play
    local file = io.open(filePath, "r")
    if not file then
        -- File doesn't exist
        return false
    end
    file:close()
    
    -- Check if CF_Preview API is available (from SWS extension)
    if reaper.CF_CreatePreview then
        -- Use CF_Preview API for isolated playback
        local source = reaper.PCM_Source_CreateFromFile(filePath)
        if not source then
            return false
        end
        
        -- Create the preview
        local preview = reaper.CF_CreatePreview(source)
        if not preview then
            reaper.PCM_Source_Destroy(source)
            return false
        end
        
        -- Store preview references for later cleanup
        globals.audioPreview.cfPreview = preview
        globals.audioPreview.cfSource = source
        
        -- Configure preview settings
        reaper.CF_Preview_SetValue(preview, 'D_VOLUME', globals.audioPreview.volume or 0.7)
        reaper.CF_Preview_SetValue(preview, 'D_POSITION', startOffset or 0)
        reaper.CF_Preview_SetValue(preview, 'B_LOOP', 0)  -- No loop
        
        -- Play the preview
        reaper.CF_Preview_Play(preview)
        
        -- Update preview state
        globals.audioPreview.isPlaying = true
        globals.audioPreview.currentFile = filePath
        globals.audioPreview.startTime = reaper.time_precise()
        globals.audioPreview.position = startOffset or 0
        globals.audioPreview.startOffset = startOffset or 0
        
        return true
    else
        -- Fallback: Use solo track method if SWS is not available
        return Waveform.startPlaybackFallback(filePath, startOffset, length)
    end
end

-- Fallback playback method if SWS extension is not available
function Waveform.startPlaybackFallback(filePath, startOffset, length)
    -- Get or create preview track
    local track = Waveform.getOrCreatePreviewTrack()
    if not track then
        return false
    end
    
    -- Solo the preview track to isolate playback
    -- First unsolo all tracks
    for i = 0, reaper.CountTracks(0) - 1 do
        local t = reaper.GetTrack(0, i)
        reaper.SetMediaTrackInfo_Value(t, "I_SOLO", 0)
    end
    -- Solo only the preview track
    reaper.SetMediaTrackInfo_Value(track, "I_SOLO", 2)  -- Solo in place
    
    -- Clear existing items on preview track
    local itemCount = reaper.CountTrackMediaItems(track)
    for i = itemCount - 1, 0, -1 do
        local item = reaper.GetTrackMediaItem(track, i)
        reaper.DeleteTrackMediaItem(track, item)
    end
    
    -- Create new media item
    local cursorPos = reaper.GetCursorPosition()
    local item = reaper.AddMediaItemToTrack(track)
    if not item then
        return false
    end
    
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", cursorPos)
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", length or 1)
    
    -- Add take with the audio file
    local take = reaper.AddTakeToMediaItem(item)
    if not take then
        reaper.DeleteTrackMediaItem(track, item)
        return false
    end
    
    local source = reaper.PCM_Source_CreateFromFile(filePath)
    if source then
        reaper.SetMediaItemTake_Source(take, source)
        reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", startOffset or 0)
        
        -- Update preview state
        globals.audioPreview.isPlaying = true
        globals.audioPreview.currentFile = filePath
        globals.audioPreview.startTime = reaper.time_precise()
        globals.audioPreview.position = 0
        
        -- Start playback from cursor position
        reaper.SetEditCurPos(cursorPos, false, false)
        reaper.OnPlayButton()
        
        return true
    else
        -- Could not create source, clean up
        reaper.DeleteTrackMediaItem(track, item)
        return false
    end
end

-- Stop audio playback
function Waveform.stopPlayback()
    if globals.audioPreview.isPlaying then
        -- Check if using CF_Preview API
        if globals.audioPreview.cfPreview then
            -- CF_Preview_Stop both stops and destroys the preview
            reaper.CF_Preview_Stop(globals.audioPreview.cfPreview)
            
            -- Destroy source
            if globals.audioPreview.cfSource then
                reaper.PCM_Source_Destroy(globals.audioPreview.cfSource)
            end
            
            globals.audioPreview.cfPreview = nil
            globals.audioPreview.cfSource = nil
        else
            -- Fallback method: stop transport and clear preview track
            reaper.OnStopButton()
            
            -- Unsolo all tracks
            for i = 0, reaper.CountTracks(0) - 1 do
                local t = reaper.GetTrack(0, i)
                reaper.SetMediaTrackInfo_Value(t, "I_SOLO", 0)
            end
            
            -- Clear preview track items
            local track = Waveform.getOrCreatePreviewTrack()
            if track then
                local itemCount = reaper.CountTrackMediaItems(track)
                for i = itemCount - 1, 0, -1 do
                    local item = reaper.GetTrackMediaItem(track, i)
                    reaper.DeleteTrackMediaItem(track, item)
                end
            end
        end
        
        -- Reset preview state
        globals.audioPreview.isPlaying = false
        globals.audioPreview.currentFile = nil
        globals.audioPreview.position = 0
    end
end

-- Update playback position
function Waveform.updatePlaybackPosition()
    if globals.audioPreview.isPlaying then
        if globals.audioPreview.cfPreview then
            -- Get position from CF_Preview (use D_POSITION for current playback position)
            local pos = reaper.CF_Preview_GetValue(globals.audioPreview.cfPreview, 'D_POSITION')
            if pos and type(pos) == "number" then
                globals.audioPreview.position = pos
            else
                -- If position is not available, estimate from time elapsed
                local currentTime = reaper.time_precise()
                local elapsed = currentTime - globals.audioPreview.startTime
                globals.audioPreview.position = (globals.audioPreview.startOffset or 0) + elapsed
            end
            
            -- Check if still playing (B_PLAY returns 1 for playing, 0 for stopped)
            local isPlaying = reaper.CF_Preview_GetValue(globals.audioPreview.cfPreview, 'B_PLAY')
            if isPlaying and isPlaying == 0 then
                -- Playback ended
                Waveform.stopPlayback()
            end
        else
            -- Fallback: calculate position based on time
            local currentTime = reaper.time_precise()
            globals.audioPreview.position = currentTime - globals.audioPreview.startTime
            
            -- Check if we should stop (reached end of item)
            local waveformData = globals.waveformCache[globals.audioPreview.currentFile .. "_400"]
            if waveformData and globals.audioPreview.position >= waveformData.length then
                Waveform.stopPlayback()
            end
        end
    end
end

-- Set preview volume
function Waveform.setPreviewVolume(volume)
    globals.audioPreview.volume = volume
    
    -- Update CF_Preview volume if active
    if globals.audioPreview.cfPreview then
        reaper.CF_Preview_SetValue(globals.audioPreview.cfPreview, 'D_VOLUME', volume)
    end
    
    -- Also update track volume for fallback method
    local track = Waveform.getOrCreatePreviewTrack()
    if track then
        reaper.SetMediaTrackInfo_Value(track, "D_VOL", volume)
    end
end

-- Force regeneration of .reapeaks file
function Waveform.regeneratePeaksFile(filePath)
    if not filePath or filePath == "" then
        reaper.ShowConsoleMsg("[Waveform] No file path provided for peak regeneration\n")
        return false
    end
    
    -- Delete existing .reapeaks file
    local peaksFilePath = filePath .. ".reapeaks"
    os.remove(peaksFilePath)
    reaper.ShowConsoleMsg("[Waveform] Deleted existing peaks file: " .. peaksFilePath .. "\n")
    
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
    
    reaper.ShowConsoleMsg(string.format("[Waveform] Generated peaks for %d files\n", generated))
    return generated
end

-- Clear waveform cache (useful for debugging)
function Waveform.clearCache()
    globals.waveformCache = {}
    reaper.ShowConsoleMsg("[Waveform] Cache cleared\n")
end

-- Clear cache for a specific file
function Waveform.clearFileCache(filePath)
    if filePath and filePath ~= "" then
        -- Clear all width variations for this file
        for key, _ in pairs(globals.waveformCache) do
            if key:sub(1, #filePath) == filePath then
                globals.waveformCache[key] = nil
                reaper.ShowConsoleMsg("[Waveform] Cache cleared for: " .. filePath .. "\n")
            end
        end
    end
end

-- Clean up preview track on script exit
function Waveform.cleanup()
    Waveform.stopPlayback()
    
    -- Remove preview track if it exists
    local trackName = "AMBIANCE_PREVIEW_TRACK"
    for i = reaper.CountTracks(0) - 1, 0, -1 do
        local track = reaper.GetTrack(0, i)
        local _, name = reaper.GetTrackName(track)
        if name == trackName then
            reaper.DeleteTrack(track)
            break
        end
    end
end

return Waveform