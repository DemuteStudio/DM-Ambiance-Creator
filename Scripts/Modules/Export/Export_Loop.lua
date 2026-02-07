--[[
@version 1.2
@noindex
DM Ambiance Creator - Export Loop Module
Handles zero-crossing detection and seamless loop creation via split/swap processing.
For Story 3.2: Zero-Crossing Loop Processing (Split/Swap)
v1.1: Code review fixes - MIDI check, locked item check, position clamp warning, track newItems for region bounds.
v1.2 (2026-02-07): Story 5.3 - Added effectiveInterval parameter to processLoop() and splitAndSwap().
      Maintains consistent overlap between moved right part and first item after split/swap.
      Fixes bug where overlap was ignored, causing adjacent placement (0s gap) instead of configured overlap.
      Handles edge case where right part is shorter than target overlap with warning.
--]]

local M = {}
local globals = {}
local Settings = nil

function M.initModule(g)
    if not g then
        error("Export_Loop.initModule: globals parameter is required")
    end
    globals = g
end

function M.setDependencies(settings)
    Settings = settings
end

-- Find the nearest zero-crossing point to a target time within an item
-- Uses AudioAccessor API to read samples and find sign changes
-- @param item MediaItem: REAPER media item
-- @param targetTime number: Target time in seconds (project timeline position)
-- @return number: Time of nearest zero-crossing (or targetTime as fallback)
-- @return boolean: True if zero-crossing found, false if fallback used
function M.findNearestZeroCrossing(item, targetTime)
    -- Get the active take from item
    local take = reaper.GetActiveTake(item)
    if not take then
        reaper.ShowConsoleMsg("[Export_Loop] Warning: No active take on item, using center point\n")
        return targetTime, false
    end

    -- Check if take is MIDI (zero-crossing only works on audio)
    if reaper.TakeIsMIDI(take) then
        reaper.ShowConsoleMsg("[Export_Loop] Warning: MIDI item detected, zero-crossing not applicable, using center point\n")
        return targetTime, false
    end

    -- Get source and sample rate
    local source = reaper.GetMediaItemTake_Source(take)
    if not source then
        reaper.ShowConsoleMsg("[Export_Loop] Warning: No source on take, using center point\n")
        return targetTime, false
    end

    local sampleRate = reaper.GetMediaSourceSampleRate(source)
    if sampleRate <= 0 then
        sampleRate = 44100 -- Fallback sample rate
    end

    -- Get item position and length for bounds checking
    local itemPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local itemLen = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local itemEnd = itemPos + itemLen

    -- Get search window from constants
    local Constants = globals.Constants
    local searchWindow = Constants and Constants.EXPORT and Constants.EXPORT.LOOP_ZERO_CROSSING_WINDOW or 0.05

    -- Handle short items: reduce search window proportionally to avoid exceeding item bounds (AC #5)
    if itemLen < (searchWindow * 4) then -- Item shorter than 200ms
        searchWindow = itemLen / 4 -- Use 1/4 of item length as window
    end

    -- Calculate search bounds (relative to item start for audio accessor)
    -- targetTime is in project time, convert to take time
    local takeOffset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
    local targetTakeTime = (targetTime - itemPos) + takeOffset

    local searchStart = targetTakeTime - searchWindow
    local searchEnd = targetTakeTime + searchWindow

    -- Clamp to item bounds (in take time)
    if searchStart < takeOffset then searchStart = takeOffset end
    if searchEnd > takeOffset + itemLen then searchEnd = takeOffset + itemLen end

    -- Create audio accessor
    local accessor = reaper.CreateTakeAudioAccessor(take)
    if not accessor then
        reaper.ShowConsoleMsg("[Export_Loop] Warning: Could not create audio accessor, using center point\n")
        return targetTime, false
    end

    -- Calculate samples to read
    local numSamples = math.floor((searchEnd - searchStart) * sampleRate)
    if numSamples <= 1 then
        reaper.DestroyAudioAccessor(accessor)
        return targetTime, false
    end

    -- Create buffer and read samples (mono channel for zero-crossing detection)
    local buffer = reaper.new_array(numSamples)
    local numChannels = 1 -- Read mono for simplicity

    reaper.GetAudioAccessorSamples(accessor, sampleRate, numChannels, searchStart, numSamples, buffer)

    -- Find zero-crossing closest to center
    local centerSample = math.floor(numSamples / 2)
    local bestIdx = nil
    local bestDistance = math.huge

    for i = 1, numSamples - 1 do
        local val = buffer[i]
        local nextVal = buffer[i + 1]
        -- Sign change = zero crossing (positive to negative or negative to positive)
        if (val >= 0 and nextVal < 0) or (val <= 0 and nextVal > 0) then
            local distFromCenter = math.abs(i - centerSample)
            if distFromCenter < bestDistance then
                bestDistance = distFromCenter
                bestIdx = i
            end
        end
    end

    -- Cleanup accessor
    reaper.DestroyAudioAccessor(accessor)

    -- Calculate result time
    if bestIdx then
        -- Convert sample index back to project time
        local zeroCrossingTakeTime = searchStart + (bestIdx / sampleRate)
        local zeroCrossingProjectTime = itemPos + (zeroCrossingTakeTime - takeOffset)
        return zeroCrossingProjectTime, true
    else
        -- No zero-crossing found, use target time as fallback (AC #3)
        reaper.ShowConsoleMsg("[Export_Loop] Warning: No zero-crossing found within search window, using center point\n")
        return targetTime, false
    end
end

-- Split an item at a specified point and move the right portion before the first item
-- Story 5.3: Added effectiveInterval parameter to maintain consistent overlap
-- @param lastItem MediaItem: The last item to split
-- @param firstItem MediaItem: The first item (right part moves before this)
-- @param splitPoint number: Project time position to split at
-- @param effectiveInterval number|nil: Interval between items (negative for overlap, e.g., -1.5).
--        If provided, the moved right part will overlap with firstItem by abs(effectiveInterval).
--        Formula: newPosition = firstItemPos - rightPartLen - effectiveInterval
--        With effectiveInterval = -1.5: newPosition = firstItemPos - rightPartLen + 1.5
-- @return table: { success = bool, rightPart = MediaItem or nil, rightPartPos = number or nil, warning = string or nil }
function M.splitAndSwap(lastItem, firstItem, splitPoint, effectiveInterval)
    -- Check if item is locked
    local isLocked = reaper.GetMediaItemInfo_Value(lastItem, "C_LOCK")
    if isLocked and isLocked ~= 0 then
        return {
            success = false,
            rightPart = nil,
            rightPartPos = nil,
            warning = "Cannot split locked item"
        }
    end

    -- Get first item position for calculating new position
    local firstItemPos = reaper.GetMediaItemInfo_Value(firstItem, "D_POSITION")

    -- Split the last item at the zero-crossing point
    local rightPart = reaper.SplitMediaItem(lastItem, splitPoint)
    if not rightPart then
        return {
            success = false,
            rightPart = nil,
            rightPartPos = nil,
            warning = "SplitMediaItem failed - split point may be out of bounds"
        }
    end

    -- Get the length of the right part
    local rightPartLen = reaper.GetMediaItemInfo_Value(rightPart, "D_LENGTH")

    -- Story 5.3: Calculate new position with effectiveInterval for consistent overlap
    -- Formula: newPosition = firstItemPos - rightPartLen - effectiveInterval
    -- With effectiveInterval = -1.5 (overlap):
    --   newPosition = firstItemPos - rightPartLen - (-1.5)
    --   newPosition = firstItemPos - rightPartLen + 1.5
    -- This creates 1.5s overlap between rightPart and firstItem
    --
    -- AC#3: Total loop duration preservation
    -- The overlap extends INTO the firstItem but doesn't extend the overall timeline.
    -- If this moves the right part before the container start, Export_Engine will
    -- shift all items forward to maintain the configured start position (see Export_Engine lines 186-216).
    local overlapTarget = math.abs(effectiveInterval or 0)
    local newPosition
    local warning = nil

    -- Edge case: right part shorter than overlap amount (AC #6)
    if effectiveInterval and effectiveInterval < 0 and rightPartLen < overlapTarget then
        -- Maximum possible overlap is limited by right part length
        newPosition = firstItemPos - rightPartLen
        warning = string.format(
            "Loop overlap reduced to %.2fs (target: %.2fs) due to short split",
            rightPartLen, overlapTarget
        )
    else
        -- Apply configured overlap (or default adjacent placement if effectiveInterval is nil)
        -- Note: effectiveInterval should never be explicitly 0 in practice (either negative for overlap,
        -- positive for gap, or nil for adjacent placement)
        local interval = effectiveInterval ~= nil and effectiveInterval or 0
        newPosition = firstItemPos - rightPartLen - interval
    end

    -- Prevent negative positions with warning
    if newPosition < 0 then
        if warning then
            warning = warning .. "; Position clamped to 0 (would have been " .. string.format("%.3f", newPosition) .. "s)"
        else
            warning = "Right part position clamped to 0 (would have been " .. string.format("%.3f", newPosition) .. "s)"
        end
        newPosition = 0
    end

    -- Move right portion to new position
    reaper.SetMediaItemPosition(rightPart, newPosition, false)

    return {
        success = true,
        rightPart = rightPart,
        rightPartPos = newPosition,
        warning = warning
    }
end

-- Process loop for all placed items, applying split/swap per track
-- Code Review M1: Added targetDuration parameter to explicitly validate AC#8
--   (split/swap only applied to tracks where last item reaches/exceeds targetDuration)
-- Story 5.3: Added effectiveInterval parameter for consistent overlap after split/swap
-- @param placedItems table: Array of PlacedItem { item, track, position, length, trackIdx }
-- @param targetTracks table: Array of REAPER tracks (for validation)
-- @param targetDuration number|nil: Target loop duration in seconds (nil = apply to all tracks)
-- @param effectiveInterval number|nil: Interval between items (negative for overlap). Used to
--        maintain consistent overlap when positioning the moved right part after split/swap.
-- @return table: { success = bool, warnings = table, errors = table, newItems = table }
--         newItems contains { item = MediaItem, position = number, length = number, trackIdx = number } for each rightPart created
function M.processLoop(placedItems, targetTracks, targetDuration, effectiveInterval)
    local result = {
        success = true,
        warnings = {},
        errors = {},
        newItems = {} -- Track new items created by split/swap for region bounds calculation
    }

    -- Handle empty placedItems gracefully
    if not placedItems or #placedItems == 0 then
        return result -- Nothing to process, success
    end

    -- Group placed items by trackIdx (AC #2)
    local itemsByTrack = {}
    for _, placed in ipairs(placedItems) do
        local trackIdx = placed.trackIdx
        if not itemsByTrack[trackIdx] then
            itemsByTrack[trackIdx] = {}
        end
        table.insert(itemsByTrack[trackIdx], placed)
    end

    -- Process each track independently
    for trackIdx, trackItems in pairs(itemsByTrack) do
        -- Check if track has at least 2 items (AC #4)
        if #trackItems < 2 then
            table.insert(result.warnings, "Track " .. trackIdx .. ": Need at least 2 items for meaningful loop (found " .. #trackItems .. ")")
            goto nextTrack
        end

        -- Sort items by position
        table.sort(trackItems, function(a, b)
            return a.position < b.position
        end)

        -- Get first and last items
        local firstPlaced = trackItems[1]
        local lastPlaced = trackItems[#trackItems]

        -- Code Review M1: AC#8 explicit validation
        -- Split/swap only applied to tracks where last item reaches/exceeds targetDuration
        if targetDuration then
            local lastItemEnd = lastPlaced.position + lastPlaced.length
            local firstItemStart = firstPlaced.position
            local trackDuration = lastItemEnd - firstItemStart

            if trackDuration < targetDuration then
                table.insert(result.warnings, string.format(
                    "Track %d: Last item ends before targetDuration (%.2fs < %.2fs), skipping split/swap per AC#8",
                    trackIdx, trackDuration, targetDuration
                ))
                goto nextTrack
            end
        end

        -- Verify items are valid
        if not reaper.ValidatePtr(firstPlaced.item, "MediaItem*") then
            table.insert(result.errors, "Track " .. trackIdx .. ": First item is invalid")
            result.success = false
            goto nextTrack
        end
        if not reaper.ValidatePtr(lastPlaced.item, "MediaItem*") then
            table.insert(result.errors, "Track " .. trackIdx .. ": Last item is invalid")
            result.success = false
            goto nextTrack
        end

        -- Calculate center of last item (AC #1)
        local lastItemPos = reaper.GetMediaItemInfo_Value(lastPlaced.item, "D_POSITION")
        local lastItemLen = reaper.GetMediaItemInfo_Value(lastPlaced.item, "D_LENGTH")
        local centerTime = lastItemPos + (lastItemLen / 2)

        -- Find nearest zero-crossing to center
        local zeroCrossingTime, foundZeroCrossing = M.findNearestZeroCrossing(lastPlaced.item, centerTime)
        if not foundZeroCrossing then
            table.insert(result.warnings, "Track " .. trackIdx .. ": Using center point (no zero-crossing found)")
        end

        -- Perform split and swap (Story 5.3: pass effectiveInterval for overlap consistency)
        local swapResult = M.splitAndSwap(lastPlaced.item, firstPlaced.item, zeroCrossingTime, effectiveInterval)
        if not swapResult.success then
            table.insert(result.errors, "Track " .. trackIdx .. ": " .. (swapResult.warning or "Split/swap failed"))
            result.success = false
        else
            -- Track the new item created for region bounds calculation
            if swapResult.rightPart then
                local rightPartLen = reaper.GetMediaItemInfo_Value(swapResult.rightPart, "D_LENGTH")
                table.insert(result.newItems, {
                    item = swapResult.rightPart,
                    position = swapResult.rightPartPos,
                    length = rightPartLen,
                    trackIdx = trackIdx
                })
            end
            if swapResult.warning then
                table.insert(result.warnings, "Track " .. trackIdx .. ": " .. swapResult.warning)
            end
        end

        ::nextTrack::
    end

    return result
end

return M
