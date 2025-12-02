--[[
@version 1.0
@noindex
DM Ambiance Creator - Waveform Areas Module
Area/zone management for waveform regions (creation, editing, detection).
--]]

local Waveform_Areas = {}
local globals = {}

function Waveform_Areas.initModule(g)
    globals = g
end

-- Get all areas for an item
function Waveform_Areas.getAreas(itemKey)
    if not itemKey then return {} end
    return globals.waveformAreas[itemKey] or {}
end

-- Clear all areas for an item
function Waveform_Areas.clearAreas(itemKey)
    if itemKey and globals.waveformAreas[itemKey] then
        globals.waveformAreas[itemKey] = nil
    end
end

-- Delete a specific area
function Waveform_Areas.deleteArea(itemKey, areaIndex)
    if itemKey and globals.waveformAreas[itemKey] and globals.waveformAreas[itemKey][areaIndex] then
        table.remove(globals.waveformAreas[itemKey], areaIndex)

        -- Clean up empty area lists
        if #globals.waveformAreas[itemKey] == 0 then
            globals.waveformAreas[itemKey] = nil
        end
    end
end

-- Rename an area
function Waveform_Areas.renameArea(itemKey, areaIndex, newName)
    if itemKey and globals.waveformAreas[itemKey] and globals.waveformAreas[itemKey][areaIndex] then
        globals.waveformAreas[itemKey][areaIndex].name = newName
    end
end

-- Export areas to a table (for saving)
function Waveform_Areas.exportAreas(itemKey)
    if not itemKey or not globals.waveformAreas[itemKey] then
        return nil
    end

    local export = {}
    for i, area in ipairs(globals.waveformAreas[itemKey]) do
        table.insert(export, {
            startPos = area.startPos,
            endPos = area.endPos,
            name = area.name
        })
    end

    return export
end

-- Import areas from a table (for loading)
function Waveform_Areas.importAreas(itemKey, areas)
    if not itemKey or not areas then return false end

    globals.waveformAreas[itemKey] = {}

    for i, area in ipairs(areas) do
        table.insert(globals.waveformAreas[itemKey], {
            startPos = area.startPos,
            endPos = area.endPos,
            name = area.name or string.format("Area %d", i)
        })
    end

    return true
end

-- Get area at position (for click detection)
function Waveform_Areas.getAreaAtPosition(itemKey, position, length)
    if not itemKey or not globals.waveformAreas[itemKey] then
        return nil
    end

    for i, area in ipairs(globals.waveformAreas[itemKey]) do
        if position >= area.startPos and position <= area.endPos then
            return area, i
        end
    end

    return nil
end

-- Check if any waveform manipulation is currently active
function Waveform_Areas.isWaveformBeingManipulated()
    if not globals.waveformAreaDrag then
        return false
    end

    return globals.waveformAreaDrag.isDragging or
           globals.waveformAreaDrag.isResizing or
           globals.waveformAreaDrag.isMoving
end


-- Check if mouse is potentially about to interact with waveform
function Waveform_Areas.isMouseAboutToInteractWithWaveform()
    if not globals.ctx or not globals.imgui then
        return false
    end

    -- Check if any waveform manipulation is already active
    if Waveform_Areas.isWaveformBeingManipulated() then
        return true
    end

    -- Check for modifier keys that would trigger waveform interactions
    local keyMods = globals.imgui.GetKeyMods(globals.ctx)
    local shiftPressed = (keyMods & globals.imgui.Mod_Shift) ~= 0
    local ctrlPressed = (keyMods & globals.imgui.Mod_Ctrl) ~= 0

    -- If Shift is pressed (for creating areas) or Ctrl is pressed (for deleting)
    -- and mouse is down, we should prevent window movement
    if (shiftPressed or ctrlPressed) and globals.imgui.IsMouseDown(globals.ctx, 0) then
        return true
    end

    -- Check if mouse is hovering over any waveform area
    if globals.waveformBounds then
        local mouse_x, mouse_y = globals.imgui.GetMousePos(globals.ctx)
        for itemKey, bounds in pairs(globals.waveformBounds) do
            if bounds and mouse_x >= bounds.x and mouse_x <= bounds.x + bounds.width and
               mouse_y >= bounds.y and mouse_y <= bounds.y + bounds.height then
                -- Mouse is over a waveform, check for potential interactions
                if shiftPressed or ctrlPressed or globals.imgui.IsMouseDown(globals.ctx, 0) then
                    return true
                end
            end
        end
    end

    return false
end

-- Convert dB to linear amplitude
local function dbToLinear(db)
    return 10 ^ (db / 20)
end

-- Auto-detect areas based on gate parameters
function Waveform_Areas.autoDetectAreas(item, itemKey)
    if not item or not item.filePath or item.filePath == "" then
        return false
    end

    -- Check if file exists
    local file = io.open(item.filePath, "r")
    if not file then
        return false
    end
    file:close()

    -- Get gate parameters with defaults
    local openThresholdDb = item.gateOpenThreshold or -20
    local closeThresholdDb = item.gateCloseThreshold or -30
    local minLengthMs = item.gateMinLength or 100
    local startOffsetMs = item.gateStartOffset or 0
    local endOffsetMs = item.gateEndOffset or 0

    -- Convert parameters
    local openThreshold = dbToLinear(openThresholdDb)
    local closeThreshold = dbToLinear(closeThresholdDb)
    local minLength = minLengthMs / 1000.0  -- Convert to seconds
    local startOffset = startOffsetMs / 1000.0
    local endOffset = endOffsetMs / 1000.0

    -- Create PCM source
    local source = reaper.PCM_Source_CreateFromFile(item.filePath)
    if not source then
        return false
    end

    local samplerate = reaper.GetMediaSourceSampleRate(source)
    local numChannels = math.floor(reaper.GetMediaSourceNumChannels(source) or 1)
    local totalLength = reaper.GetMediaSourceLength(source, false)

    -- Calculate the portion to analyze
    local analyzeStart = item.startOffset or 0
    local analyzeLength = item.length or (totalLength - analyzeStart)
    analyzeLength = math.min(analyzeLength, totalLength - analyzeStart)

    -- Create temporary item for audio accessor
    local tempTrack = reaper.GetTrack(0, 0)
    if not tempTrack then
        reaper.InsertTrackAtIndex(0, false)
        tempTrack = reaper.GetTrack(0, 0)
    end

    if not tempTrack then
        reaper.PCM_Source_Destroy(source)
        return false
    end

    local tempItem = reaper.AddMediaItemToTrack(tempTrack)
    if not tempItem then
        reaper.PCM_Source_Destroy(source)
        return false
    end

    reaper.SetMediaItemInfo_Value(tempItem, "D_POSITION", 0)
    reaper.SetMediaItemInfo_Value(tempItem, "D_LENGTH", analyzeLength)

    local tempTake = reaper.AddTakeToMediaItem(tempItem)
    if not tempTake then
        reaper.DeleteTrackMediaItem(tempTrack, tempItem)
        reaper.PCM_Source_Destroy(source)
        return false
    end

    reaper.SetMediaItemTake_Source(tempTake, source)
    reaper.SetMediaItemTakeInfo_Value(tempTake, "D_STARTOFFS", analyzeStart)
    reaper.UpdateItemInProject(tempItem)

    -- Create audio accessor
    local accessor = reaper.CreateTakeAudioAccessor(tempTake)
    if not accessor then
        reaper.DeleteTrackMediaItem(tempTrack, tempItem)
        return false
    end

    -- Analysis parameters
    local windowSize = math.max(1, math.floor(samplerate * 0.01))  -- 10ms window for RMS
    local hopSize = math.max(1, math.floor(samplerate * 0.005))    -- 5ms hop for smoother detection
    local totalSamples = math.floor(analyzeLength * samplerate)

    -- Audio buffer
    local bufferSize = windowSize * numChannels
    local audioBuffer = reaper.new_array(bufferSize * 2)

    -- Gate state
    local gateOpen = false
    local areaStartTime = 0
    local gateOpenTime = 0
    local belowThresholdCount = 0  -- Count consecutive samples below close threshold
    local belowThresholdRequired = 3  -- Require N consecutive samples below threshold to close
    local areas = {}

    -- Process audio in chunks
    for samplePos = 0, totalSamples - windowSize, hopSize do
        local currentTime = samplePos / samplerate

        -- Clear buffer
        audioBuffer.clear()

        -- Read audio samples
        local startTime = currentTime
        local ret = reaper.GetAudioAccessorSamples(
            accessor,
            samplerate,
            numChannels,
            startTime,
            windowSize,
            audioBuffer
        )

        -- Convert buffer to table
        local samples = audioBuffer.table(1, windowSize * numChannels)

        if samples and #samples > 0 then
            -- Calculate RMS level across all channels
            local sumSquares = 0
            local sampleCount = 0

            for s = 0, windowSize - 1 do
                for ch = 1, numChannels do
                    local idx = s * numChannels + ch
                    if samples[idx] then
                        local value = samples[idx]
                        sumSquares = sumSquares + (value * value)
                        sampleCount = sampleCount + 1
                    end
                end
            end

            local rmsLevel = 0
            if sampleCount > 0 then
                rmsLevel = math.sqrt(sumSquares / sampleCount)
            end

            -- Gate logic
            if not gateOpen then
                -- Gate is closed, check for opening
                if rmsLevel > openThreshold then
                    gateOpen = true
                    -- Start offset: positive values make the start earlier (subtract from current time)
                    areaStartTime = math.max(0, currentTime - (startOffset / 1000.0))
                    gateOpenTime = currentTime  -- Remember when gate actually opened for length calculation
                    belowThresholdCount = 0  -- Reset close counter
                end
            else
                -- Gate is open, check for closing
                local actualGateLength = currentTime - gateOpenTime  -- Time since gate opened

                -- Only check for closing if minimum length has been reached
                if actualGateLength >= minLength then
                    if rmsLevel < closeThreshold then
                        belowThresholdCount = belowThresholdCount + 1

                        -- Close gate only after consecutive samples below threshold
                        if belowThresholdCount >= belowThresholdRequired then
                            local areaEndTime = math.min(analyzeLength, currentTime + (endOffset / 1000.0))

                            -- Create new area
                            if areaEndTime > areaStartTime then
                                table.insert(areas, {
                                    startPos = areaStartTime,
                                    endPos = areaEndTime,
                                    name = string.format("Variation %d", #areas + 1)
                                })
                            end

                            gateOpen = false
                            belowThresholdCount = 0
                        end
                    else
                        -- Reset counter if signal goes back above threshold
                        belowThresholdCount = 0
                    end
                end
            end
        end

        -- Limit number of areas to prevent UI issues
        if #areas >= 100 then
            break
        end
    end

    -- Handle case where gate is still open at the end
    if gateOpen then
        local actualGateLength = analyzeLength - gateOpenTime
        if actualGateLength >= minLength then
            local areaEndTime = math.min(analyzeLength, analyzeLength + (endOffset / 1000.0))
            if areaEndTime > areaStartTime then
                table.insert(areas, {
                    startPos = areaStartTime,
                    endPos = areaEndTime,
                    name = string.format("Variation %d", #areas + 1)
                })
            end
        end
    end

    -- Cleanup
    reaper.DestroyAudioAccessor(accessor)
    reaper.DeleteTrackMediaItem(tempTrack, tempItem)

    -- Merge areas that are too close together (< 50ms apart)
    local mergedAreas = {}
    local mergeThreshold = 0.05  -- 50ms

    for i, area in ipairs(areas) do
        local merged = false

        for j, prevArea in ipairs(mergedAreas) do
            if area.startPos - prevArea.endPos < mergeThreshold then
                -- Merge with previous area
                prevArea.endPos = area.endPos
                merged = true
                break
            end
        end

        if not merged then
            table.insert(mergedAreas, {
                startPos = area.startPos,
                endPos = area.endPos,
                name = area.name
            })
        end
    end

    -- Store detected areas
    if itemKey then
        globals.waveformAreas[itemKey] = mergedAreas
        -- Also store in item for persistence
        item.areas = mergedAreas
    end

    return true, #mergedAreas
end

-- Split audio item into equal-sized areas
function Waveform_Areas.splitCountAreas(item, itemKey, count)
    if not item or not item.filePath or item.filePath == "" then
        return false, 0
    end

    -- Check if file exists
    local file = io.open(item.filePath, "r")
    if not file then
        return false, 0
    end
    file:close()

    -- Validate count
    if not count or count < 1 then
        return false, 0
    end

    -- Get the length to divide
    local totalLength = item.length or 0
    if totalLength <= 0 then
        -- Try to get length from the audio file
        local source = reaper.PCM_Source_CreateFromFile(item.filePath)
        if source then
            totalLength = reaper.GetMediaSourceLength(source, false)
            reaper.PCM_Source_Destroy(source)
        end

        if totalLength <= 0 then
            return false, 0
        end
    end

    -- Calculate area length
    local areaLength = totalLength / count
    local areas = {}

    -- Create equal-sized areas
    for i = 0, count - 1 do
        local startPos = i * areaLength
        local endPos = (i + 1) * areaLength

        -- Ensure the last area doesn't exceed the total length
        if i == count - 1 then
            endPos = totalLength
        end

        table.insert(areas, {
            startPos = startPos,
            endPos = endPos,
            name = string.format("Area %d", i + 1)
        })
    end

    -- Store areas
    if not globals.waveformAreas then
        globals.waveformAreas = {}
    end
    globals.waveformAreas[itemKey] = areas

    -- Also store in item for persistence
    item.areas = areas

    return true, #areas
end

-- Split audio item into fixed-duration areas
function Waveform_Areas.splitTimeAreas(item, itemKey, duration)
    if not item or not item.filePath or item.filePath == "" then
        return false, 0
    end

    -- Check if file exists
    local file = io.open(item.filePath, "r")
    if not file then
        return false, 0
    end
    file:close()

    -- Validate duration
    if not duration or duration <= 0 then
        return false, 0
    end

    -- Get the total length
    local totalLength = item.length or 0
    if totalLength <= 0 then
        -- Try to get length from the audio file
        local source = reaper.PCM_Source_CreateFromFile(item.filePath)
        if source then
            totalLength = reaper.GetMediaSourceLength(source, false)
            reaper.PCM_Source_Destroy(source)
        end

        if totalLength <= 0 then
            return false, 0
        end
    end

    -- Calculate how many complete areas we can fit
    local numCompleteAreas = math.floor(totalLength / duration)
    if numCompleteAreas == 0 then
        return false, 0 -- Duration is longer than the file
    end

    local areas = {}

    -- Create fixed-duration areas
    for i = 0, numCompleteAreas - 1 do
        local startPos = i * duration
        local endPos = startPos + duration

        table.insert(areas, {
            startPos = startPos,
            endPos = endPos,
            name = string.format("Area %d", i + 1)
        })
    end

    -- Store areas
    if not globals.waveformAreas then
        globals.waveformAreas = {}
    end
    globals.waveformAreas[itemKey] = areas

    -- Also store in item for persistence
    item.areas = areas

    return true, #areas
end

-- Process debounced gate detection requests
function Waveform_Areas.processGateDetectionDebounce()
    if not globals.gateDetectionDebounce then
        return
    end

    local currentTime = reaper.time_precise()
    local debounceDelay = 0.3  -- 300ms delay after last change

    for itemKey, debounceData in pairs(globals.gateDetectionDebounce) do
        if currentTime - debounceData.timestamp >= debounceDelay then
            -- Check if parameters have actually changed since last detection
            local item = debounceData.item
            local shouldDetect = false

            -- Check if this is the first detection for this item
            if not item.lastGateParams then
                shouldDetect = true
            else
                -- Compare with last detection parameters
                local lastParams = item.lastGateParams
                local currentParams = debounceData.params

                if lastParams.openThreshold ~= currentParams.openThreshold or
                   lastParams.closeThreshold ~= currentParams.closeThreshold or
                   lastParams.minLength ~= currentParams.minLength or
                   lastParams.startOffset ~= currentParams.startOffset or
                   lastParams.endOffset ~= currentParams.endOffset then
                    shouldDetect = true
                end
            end

            if shouldDetect then
                -- Perform the detection
                local success, numAreas = Waveform_Areas.autoDetectAreas(item, itemKey)

                if success then
                    -- Store the parameters used for this detection
                    item.lastGateParams = {
                        openThreshold = debounceData.params.openThreshold,
                        closeThreshold = debounceData.params.closeThreshold,
                        minLength = debounceData.params.minLength,
                        startOffset = debounceData.params.startOffset,
                        endOffset = debounceData.params.endOffset
                    }
                end
            end

            -- Remove from debounce queue
            globals.gateDetectionDebounce[itemKey] = nil
        end
    end
end

return Waveform_Areas
