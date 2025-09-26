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
function Waveform.getWaveformData(filePath, width)
    -- Validate inputs
    if not filePath or filePath == "" then
        return Waveform.createPlaceholderWaveform(width)
    end

    width = math.floor(tonumber(width) or 400)
    if width <= 0 then width = 400 end

    local cacheKey = filePath .. "_" .. width

    -- Check cache first
    if globals.waveformCache[cacheKey] and not globals.waveformCache[cacheKey].isPlaceholder then
        return globals.waveformCache[cacheKey]
    end

    -- Check if file exists
    local file = io.open(filePath, "r")
    if not file then
        reaper.ShowConsoleMsg("[Waveform] File not found: " .. filePath .. "\n")
        return Waveform.createPlaceholderWaveform(width)
    end
    file:close()
    reaper.ShowConsoleMsg("[Waveform] File exists, proceeding...\n")

    -- Create PCM source
    local source = reaper.PCM_Source_CreateFromFile(filePath)
    if not source then
        reaper.ShowConsoleMsg("[Waveform] Failed to create PCM source\n")
        return Waveform.createPlaceholderWaveform(width)
    end

    -- Get source info
    local samplerate = reaper.GetMediaSourceSampleRate(source) or 44100
    local length = reaper.GetMediaSourceLength(source, false) or 1
    local numChannels = reaper.GetMediaSourceNumChannels(source) or 1
    reaper.ShowConsoleMsg(string.format("[Waveform] Source info - rate: %.0f, length: %.2f, channels: %d\n",
        samplerate, length, numChannels))

    -- Ensure .reapeaks file exists
    local peaksFilePath = filePath .. ".reapeaks"
    local peaksFileExists = io.open(peaksFilePath, "rb")
    if not peaksFileExists then
        -- Build peaks file
        reaper.PCM_Source_BuildPeaks(source, 0)  -- mode 0 = build now
    else
        peaksFileExists:close()
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

    reaper.SetMediaItemInfo_Value(tempItem, "D_POSITION", 0)
    reaper.SetMediaItemInfo_Value(tempItem, "D_LENGTH", length)

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

    -- Get peaks
    local buf = reaper.new_array(width * 2)
    buf.clear()

    local peakrate = (samplerate * length) / width
    reaper.ShowConsoleMsg(string.format("[Waveform] Getting peaks - rate: %.2f, width: %d\n", peakrate, width))

    local retval = reaper.GetMediaItemTake_Peaks(
        tempTake,
        peakrate,
        0,
        1,  -- mono for simplicity
        width,
        0,
        buf
    )

    -- Extract peaks
    local spl_cnt = retval % 1048576
    reaper.ShowConsoleMsg(string.format("[Waveform] GetMediaItemTake_Peaks returned: %d, samples: %d\n", retval, spl_cnt))

    if spl_cnt > 0 then
        local peaks_table = buf.table()
        if peaks_table and #peaks_table > 0 then
            reaper.ShowConsoleMsg(string.format("[Waveform] Got %d peak values\n", #peaks_table))

            -- Check first few values
            local hasNonZero = false
            for i = 1, math.min(10, #peaks_table) do
                if math.abs(peaks_table[i]) > 0.0001 then
                    hasNonZero = true
                    break
                end
            end
            reaper.ShowConsoleMsg(string.format("[Waveform] Has non-zero peaks: %s\n", tostring(hasNonZero)))

            for i = 1, math.min(width, spl_cnt) do
                local idx = (i - 1) * 2 + 1
                if idx + 1 <= #peaks_table then
                    peaks.max[i] = peaks_table[idx] or 0
                    peaks.min[i] = peaks_table[idx + 1] or 0
                    peaks.rms[i] = (math.abs(peaks.max[i]) + math.abs(peaks.min[i])) / 2 * 0.7
                else
                    peaks.max[i] = 0
                    peaks.min[i] = 0
                    peaks.rms[i] = 0
                end
            end

            -- Normalize if peaks are too small
            local maxPeak = 0
            for i = 1, math.min(width, spl_cnt) do
                maxPeak = math.max(maxPeak, math.abs(peaks.max[i]), math.abs(peaks.min[i]))
            end

            if maxPeak > 0 and maxPeak < 0.1 then
                local normFactor = 0.8 / maxPeak
                reaper.ShowConsoleMsg(string.format("[Waveform] Normalizing peaks by factor: %.2f\n", normFactor))
                for i = 1, math.min(width, spl_cnt) do
                    peaks.max[i] = peaks.max[i] * normFactor
                    peaks.min[i] = peaks.min[i] * normFactor
                    peaks.rms[i] = peaks.rms[i] * normFactor
                end
            end
        else
            reaper.ShowConsoleMsg("[Waveform] No peaks table or empty\n")
        end
    else
        reaper.ShowConsoleMsg("[Waveform] No samples returned from GetMediaItemTake_Peaks\n")
    end

    -- Clean up
    reaper.DeleteTrackMediaItem(tempTrack, tempItem)

    -- Check if we got any valid data
    local hasData = false
    for i = 1, #peaks.max do
        if peaks.max[i] and math.abs(peaks.max[i]) > 0.0001 then
            hasData = true
            break
        end
    end

    -- If no data, create a simple test waveform
    if not hasData then
        reaper.ShowConsoleMsg("[Waveform] No valid peak data, creating test waveform\n")
        for i = 1, width do
            local t = (i / width) * math.pi * 4
            peaks.max[i] = math.sin(t) * 0.5
            peaks.min[i] = -math.sin(t) * 0.5
            peaks.rms[i] = math.abs(math.sin(t)) * 0.35
        end
    end

    -- Create waveform data
    local waveformData = {
        peaks = peaks,
        length = length,
        numChannels = numChannels,
        samplerate = samplerate,
        isPlaceholder = false
    }

    -- Cache it
    globals.waveformCache[cacheKey] = waveformData

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
        for pixel = 1, width do
            local sampleIndex = math.floor(((pixel - 1) / width) * numSamples) + 1
            sampleIndex = math.max(1, math.min(sampleIndex, numSamples))

            local x = pos_x + pixel - 1
            local minVal = peaks.min[sampleIndex] or 0
            local maxVal = peaks.max[sampleIndex] or 0
            local rmsVal = peaks.rms[sampleIndex] or 0

            -- Draw peak line (max is positive, min is negative typically)
            local topY = centerY - (maxVal * height / 2)
            local bottomY = centerY - (minVal * height / 2)

            imgui.DrawList_AddLine(draw_list,
                x, topY,
                x, bottomY,
                0x00FF00FF,
                1
            )

            -- Draw RMS (darker green)
            if rmsVal > 0 then
                imgui.DrawList_AddLine(draw_list,
                    x, centerY - (rmsVal * height / 2),
                    x, centerY + (rmsVal * height / 2),
                    0x008800FF,
                    1
                )
            end
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