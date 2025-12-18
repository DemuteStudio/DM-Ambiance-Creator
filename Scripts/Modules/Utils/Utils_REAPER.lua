--[[
@version 1.5
@noindex
DM Ambiance Creator - REAPER API Utilities Module
Extracted from DM_Ambiance_Utils.lua for better modularity

This module contains all REAPER API wrapper functions for track management,
volume control, routing, and media item manipulation.
--]]

local Utils_REAPER = {}
local Constants = require("DM_Ambiance_Constants")

-- Module globals (set by initModule)
local globals = {}

-- Dependencies
local Utils_Math = nil
local Utils_Core = nil
local Utils_String = nil

-- Local state for queues
local fadeUpdateQueue = {}
local randomizationUpdateQueue = {}

function Utils_REAPER.initModule(g)
    if not g then
        error("Utils_REAPER.initModule: globals parameter is required")
    end
    globals = g

    -- Load dependencies
    Utils_Math = require("Utils.Utils_Math")
    Utils_Core = require("Utils.Utils_Core")
    Utils_String = require("Utils.Utils_String")
end

-- ============================================================================
-- TRACK FINDING AND MANAGEMENT
-- ============================================================================

-- Search for a track by its name (generic function)
-- @param name string: The name of the track to find
-- @return MediaTrack|nil, number: The track object and its index, or nil and -1 if not found
function Utils_REAPER.findTrackByName(name)
    if not name or name == "" then
        return nil, -1
    end

    local trackCount = reaper.CountTracks(0)
    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local success, trackName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
            if success and trackName == name then
                return track, i
            end
        end
    end
    return nil, -1
end

-- Search for a track group by its name and return the track and its index if found
-- @param name string: The name of the group to find
-- @return MediaTrack|nil, number: The track object and its index, or nil and -1 if not found
function Utils_REAPER.findGroupByName(name)
    -- Use the generic function
    return Utils_REAPER.findTrackByName(name)
end

-- Search for a container group by name within a parent group, considering folder depth
function Utils_REAPER.findContainerGroup(parentGroupIdx, containerName)
    if not parentGroupIdx or not containerName then
        return nil, nil
    end

    local groupCount = reaper.CountTracks(0)
    local folderDepth = 1 -- Start at depth 1 (inside a folder)

    -- Trim and normalize the container name for comparison
    local containerNameTrimmed = string.gsub(containerName, "^%s*(.-)%s*$", "%1")

    for i = parentGroupIdx + 1, groupCount - 1 do
        local childGroup = reaper.GetTrack(0, i)
        local _, name = reaper.GetSetMediaTrackInfo_String(childGroup, "P_NAME", "", false)

        -- Trim whitespace from track name
        local trackNameTrimmed = string.gsub(name, "^%s*(.-)%s*$", "%1")

        -- Case-sensitive exact match (more reliable than case-insensitive)
        if trackNameTrimmed == containerNameTrimmed then
            return childGroup, i
        end

        -- Update folder depth according to the folder status of this track
        local depth = reaper.GetMediaTrackInfo_Value(childGroup, "I_FOLDERDEPTH")
        folderDepth = folderDepth + depth

        -- Stop searching if we exit the parent folder
        if folderDepth <= 0 then
            break
        end
    end

    -- Container not found in this group
    return nil, nil
end

-- Remove all media items from a given track group
function Utils_REAPER.clearGroupItems(group)
    if not group then return false end
    local itemCount = reaper.GetTrackNumMediaItems(group)
    for i = itemCount-1, 0, -1 do
        local item = reaper.GetTrackMediaItem(group, i)
        reaper.DeleteTrackMediaItem(group, item)
    end
    return true
end

-- Helper function to get all containers in a group with their information
function Utils_REAPER.getAllContainersInGroup(parentGroupIdx)
    if not parentGroupIdx then
        return {}
    end

    local containers = {}
    local groupCount = reaper.CountTracks(0)
    local folderDepth = 1  -- We start inside the parent folder
    local currentLevel = 1  -- Track nesting level (1 = direct children of parent)

    -- Start scanning from the track right after the parent
    for i = parentGroupIdx + 1, groupCount - 1 do
        local track = reaper.GetTrack(0, i)
        if not track then break end

        local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")

        -- Only add tracks at level 1 (direct children of the parent group)
        -- This excludes multi-channel child tracks (level 2)
        if currentLevel == 1 then
            table.insert(containers, {
                track = track,
                index = i,
                name = name,
                originalDepth = depth
            })
        end

        -- Update the nesting level for the next track
        if depth == 1 then
            currentLevel = currentLevel + 1  -- Entering a sub-folder (going deeper)
        elseif depth == -1 then
            currentLevel = currentLevel - 1  -- Exiting a folder (going up)
        end

        -- Update folder depth
        folderDepth = folderDepth + depth

        -- Stop if we exit the parent folder
        if folderDepth <= 0 then
            break
        end
    end

    return containers
end

-- Helper function to fix folder structure for a specific group
-- @param parentGroupIdx number: Index of the parent group track
-- @return boolean: true if successful, false otherwise
function Utils_REAPER.fixGroupFolderStructure(parentGroupIdx)
    if not parentGroupIdx or parentGroupIdx < 0 then
        return false
    end

    -- Get fresh container list after any track insertions/deletions
    local containers = Utils_REAPER.getAllContainersInGroup(parentGroupIdx)

    if #containers == 0 then
        return false
    end

    -- Set proper folder depths for containers
    -- Multi-channel containers (depth = 1) manage their own children
    for i = 1, #containers do
        local container = containers[i]

        -- Check if this container is a multi-channel folder (depth = 1)
        if container.originalDepth == 1 then
            -- Don't modify multi-channel folders - they're already configured
            -- Their children handle the folder structure
        else
            -- Normal container without children
            if i == #containers then
                -- Last non-multi-channel container closes the parent group
                reaper.SetMediaTrackInfo_Value(container.track, "I_FOLDERDEPTH", Constants.TRACKS.FOLDER_END_DEPTH)
            else
                -- Normal container in the middle
                reaper.SetMediaTrackInfo_Value(container.track, "I_FOLDERDEPTH", Constants.TRACKS.NORMAL_TRACK_DEPTH)
            end
        end
    end

    -- Note: If the last container is multi-channel, generateGroups() handles closing the parent folder

    -- Ensure the parent group has the correct folder start depth
    local parentTrack = reaper.GetTrack(0, parentGroupIdx)
    if parentTrack then
        reaper.SetMediaTrackInfo_Value(parentTrack, "I_FOLDERDEPTH", Constants.TRACKS.FOLDER_START_DEPTH)
    end

    return true
end

-- Helper function to validate and repair folder structures if needed
-- @param parentGroupIdx number: Index of the parent group track
-- @return boolean: true if successful, false otherwise
function Utils_REAPER.validateAndRepairGroupStructure(parentGroupIdx)
    if not parentGroupIdx or parentGroupIdx < 0 then
        return false
    end

    local containers = Utils_REAPER.getAllContainersInGroup(parentGroupIdx)
    local needsRepair = false

    -- Check if the structure is correct
    for i = 1, #containers do
        local container = containers[i]
        local expectedDepth = (i == #containers) and Constants.TRACKS.FOLDER_END_DEPTH or Constants.TRACKS.NORMAL_TRACK_DEPTH

        if container.originalDepth ~= expectedDepth then
            needsRepair = true
            break
        end
    end

    -- Repair if needed
    if needsRepair then
        return Utils_REAPER.fixGroupFolderStructure(parentGroupIdx)
    end

    return true
end

-- Clear items from a group within the time selection, preserving items outside the selection
-- @param containerGroup MediaTrack: The track containing items to clear
-- @param crossfadeMargin number: Crossfade margin in seconds (optional)
function Utils_REAPER.clearGroupItemsInTimeSelection(containerGroup, crossfadeMargin)
    if not containerGroup then
        error("Utils_REAPER.clearGroupItemsInTimeSelection: containerGroup parameter is required")
    end

    if not globals.timeSelectionValid then
        return
    end

    -- Default crossfade margin parameter (in seconds)
    crossfadeMargin = crossfadeMargin or globals.Settings.getSetting("crossfadeMargin") or Constants.AUDIO.DEFAULT_CROSSFADE_MARGIN

    local itemCount = reaper.CountTrackMediaItems(containerGroup)
    local itemsToProcess = {}

    -- Store references to items that will be preserved for crossfades
    globals.crossfadeItems = globals.crossfadeItems or {}
    globals.crossfadeItems[containerGroup] = { startItems = {}, endItems = {} }

    -- Collect all items that need processing
    for i = 0, itemCount - 1 do
        local item = reaper.GetTrackMediaItem(containerGroup, i)
        local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local itemEnd = itemStart + itemLength

        -- Check intersection with time selection
        if itemEnd > globals.startTime and itemStart < globals.endTime then
            table.insert(itemsToProcess, {
                item = item,
                start = itemStart,
                length = itemLength,
                ending = itemEnd
            })
        end
    end

    -- Process items in reverse order to avoid index issues
    for i = #itemsToProcess, 1, -1 do
        local itemData = itemsToProcess[i]
        local item = itemData.item
        local itemStart = itemData.start
        local itemLength = itemData.length
        local itemEnd = itemData.ending

        if itemStart >= globals.startTime and itemEnd <= globals.endTime then
            -- Item is completely within time selection - delete it
            reaper.DeleteTrackMediaItem(containerGroup, item)

        elseif itemStart < globals.startTime and itemEnd > globals.endTime then
            -- Item spans the entire time selection - split into two parts with overlap
            local splitStart = globals.startTime + crossfadeMargin  -- Cut later
            local splitEnd = globals.endTime - crossfadeMargin      -- Cut earlier

            -- Ensure we don't go beyond the original item boundaries
            splitStart = math.max(splitStart, itemStart)
            splitEnd = math.min(splitEnd, itemEnd)

            if splitStart < splitEnd then
                local splitItem1 = reaper.SplitMediaItem(item, splitStart)
                if splitItem1 then
                    local splitItem2 = reaper.SplitMediaItem(splitItem1, splitEnd)
                    -- Delete the middle part
                    reaper.DeleteTrackMediaItem(containerGroup, splitItem1)
                    -- Store references for crossfading
                    table.insert(globals.crossfadeItems[containerGroup].startItems, item)
                    if splitItem2 then
                        table.insert(globals.crossfadeItems[containerGroup].endItems, splitItem2)
                    end
                end
            end

        elseif itemStart < globals.startTime and itemEnd <= globals.endTime then
            -- Item starts before and ends within selection
            local splitPoint = globals.startTime + crossfadeMargin  -- Cut later
            splitPoint = math.max(splitPoint, itemStart)
            splitPoint = math.min(splitPoint, itemEnd)

            if splitPoint > itemStart and splitPoint < itemEnd then
                local splitItem = reaper.SplitMediaItem(item, splitPoint)
                if splitItem then
                    reaper.DeleteTrackMediaItem(containerGroup, splitItem)
                    -- Store reference for crossfading
                    table.insert(globals.crossfadeItems[containerGroup].startItems, item)
                end
            elseif splitPoint >= itemEnd then
                -- If the split point is after the end of the item, delete the entire item
                reaper.DeleteTrackMediaItem(containerGroup, item)
            end

        elseif itemStart >= globals.startTime and itemEnd > globals.endTime then
            -- Item starts within and ends after selection
            local splitPoint = globals.endTime - crossfadeMargin  -- Cut earlier
            splitPoint = math.min(splitPoint, itemEnd)
            splitPoint = math.max(splitPoint, itemStart)

            if splitPoint < itemEnd and splitPoint > itemStart then
                local splitItem = reaper.SplitMediaItem(item, splitPoint)
                reaper.DeleteTrackMediaItem(containerGroup, item)
                if splitItem then
                    -- Store reference for crossfading
                    table.insert(globals.crossfadeItems[containerGroup].endItems, splitItem)
                end
            elseif splitPoint <= itemStart then
                -- If the split point is before the start of the item, delete the entire item
                reaper.DeleteTrackMediaItem(containerGroup, item)
            end
        end
    end
end

-- ============================================================================
-- TRACK REORGANIZATION
-- ============================================================================

-- Reorganize REAPER tracks after group reordering via drag and drop
function Utils_REAPER.reorganizeTracksAfterGroupReorder()

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    -- Get all current tracks with their group associations
    local tracksToStore = {}

    -- Map tracks to their groups and store all their data
    for groupIndex, group in ipairs(globals.groups) do

        local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
        if groupTrack and groupTrackIdx >= 0 then
            -- Store the parent group track data
            tracksToStore[groupIndex] = {
                groupName = group.name,
                containers = {}
            }

            -- Get all container tracks in this group
            local containers = Utils_REAPER.getAllContainersInGroup(groupTrackIdx)
            for _, container in ipairs(containers) do
                local containerData = {
                    name = container.name,
                    mediaItems = {}
                }

                -- Store all media items from this container
                local itemCount = reaper.CountTrackMediaItems(container.track)
                for i = 0, itemCount - 1 do
                    local item = reaper.GetTrackMediaItem(container.track, i)
                    local itemData = {
                        position = reaper.GetMediaItemInfo_Value(item, "D_POSITION"),
                        length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
                        take = reaper.GetActiveTake(item)
                    }
                    if itemData.take then
                        local source = reaper.GetMediaItemTake_Source(itemData.take)
                        itemData.sourceFile = reaper.GetMediaSourceFileName(source, "")
                        itemData.takeName = reaper.GetTakeName(itemData.take)
                        itemData.startOffset = reaper.GetMediaItemTakeInfo_Value(itemData.take, "D_STARTOFFS")
                        itemData.pitch = reaper.GetMediaItemTakeInfo_Value(itemData.take, "D_PITCH")
                        itemData.volume = reaper.GetMediaItemTakeInfo_Value(itemData.take, "D_VOL")
                        itemData.pan = reaper.GetMediaItemTakeInfo_Value(itemData.take, "D_PAN")
                    end
                    table.insert(containerData.mediaItems, itemData)
                end

                table.insert(tracksToStore[groupIndex].containers, containerData)
            end
        end
    end

    -- Delete all tracks that belong to our groups
    local tracksToDelete = {}
    for groupIndex, group in ipairs(globals.groups) do
        local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
        if groupTrack then
            -- Add all tracks in this group to deletion list
            table.insert(tracksToDelete, groupTrack)
            local containers = Utils_REAPER.getAllContainersInGroup(groupTrackIdx)
            for _, container in ipairs(containers) do
                table.insert(tracksToDelete, container.track)
            end
        end
    end

    -- Delete tracks in reverse order to maintain indices
    table.sort(tracksToDelete, function(a, b)
        local indexA = reaper.GetMediaTrackInfo_Value(a, "IP_TRACKNUMBER") - 1
        local indexB = reaper.GetMediaTrackInfo_Value(b, "IP_TRACKNUMBER") - 1
        return indexA > indexB
    end)

    for _, track in ipairs(tracksToDelete) do
        reaper.DeleteTrack(track)
    end

    -- Recreate tracks in the new order
    for groupIndex, group in ipairs(globals.groups) do
        local storedData = tracksToStore[groupIndex]
        if storedData then
            -- Create parent group track
            local parentGroupIdx = reaper.GetNumTracks()
            reaper.InsertTrackAtIndex(parentGroupIdx, true)
            local parentGroup = reaper.GetTrack(0, parentGroupIdx)
            reaper.GetSetMediaTrackInfo_String(parentGroup, "P_NAME", group.name, true)
            reaper.SetMediaTrackInfo_Value(parentGroup, "I_FOLDERDEPTH", 1)

            -- Create container tracks
            local containerCount = #group.containers
            for j, container in ipairs(group.containers) do
                local containerGroupIdx = reaper.GetNumTracks()
                reaper.InsertTrackAtIndex(containerGroupIdx, true)
                local containerGroup = reaper.GetTrack(0, containerGroupIdx)
                reaper.GetSetMediaTrackInfo_String(containerGroup, "P_NAME", container.name, true)

                -- Set folder state based on position
                local folderState = 0 -- Default: normal track in a folder
                if j == containerCount then
                    -- If it's the last container, mark as folder end
                    folderState = -1
                end
                reaper.SetMediaTrackInfo_Value(containerGroup, "I_FOLDERDEPTH", folderState)

                -- Restore media items if we have stored data for this container
                if storedData.containers[j] then
                    local containerData = storedData.containers[j]
                    for _, itemData in ipairs(containerData.mediaItems) do
                        if itemData.sourceFile and itemData.sourceFile ~= "" then
                            local newItem = reaper.AddMediaItemToTrack(containerGroup)
                            local newTake = reaper.AddTakeToMediaItem(newItem)

                            local pcmSource = reaper.PCM_Source_CreateFromFile(itemData.sourceFile)
                            reaper.SetMediaItemTake_Source(newTake, pcmSource)

                            reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", itemData.position)
                            reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH", itemData.length)
                            reaper.GetSetMediaItemTakeInfo_String(newTake, "P_NAME", itemData.takeName, true)
                            reaper.SetMediaItemTakeInfo_Value(newTake, "D_STARTOFFS", itemData.startOffset)
                            reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", itemData.pitch)
                            reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", itemData.volume)
                            reaper.SetMediaItemTakeInfo_Value(newTake, "D_PAN", itemData.pan)
                        end
                    end
                end
            end
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Reorganize groups after drag and drop", -1)
end

-- Reorganize REAPER tracks after moving a container between groups
function Utils_REAPER.reorganizeTracksAfterContainerMove(sourceGroupIndex, targetGroupIndex, containerName)
    -- If moving within the same group, no track reorganization needed
    if sourceGroupIndex == targetGroupIndex then
        return
    end

    -- For moves between different groups, we need to rebuild the entire track structure
    -- to maintain proper folder hierarchy. Use the same approach as group reordering.
    Utils_REAPER.reorganizeTracksAfterGroupReorder()
end

-- ============================================================================
-- CROSSFADES
-- ============================================================================

-- Create crossfades between two overlapping media items with the given fade shape
-- @param item1 MediaItem: First media item
-- @param item2 MediaItem: Second media item
-- @param fadeShape number: Fade shape (optional, uses default if not provided)
-- @return boolean: true if crossfade was created, false otherwise
function Utils_REAPER.createCrossfade(item1, item2, fadeShape)
    if not item1 or not item2 then
        return false
    end

    fadeShape = fadeShape or Constants.AUDIO.DEFAULT_FADE_SHAPE

    local item1End = reaper.GetMediaItemInfo_Value(item1, "D_POSITION") + reaper.GetMediaItemInfo_Value(item1, "D_LENGTH")
    local item2Start = reaper.GetMediaItemInfo_Value(item2, "D_POSITION")

    if item2Start < item1End then
        local overlapLength = item1End - item2Start
        -- Set fade out for the first item
        reaper.SetMediaItemInfo_Value(item1, "D_FADEOUTLEN", overlapLength)
        reaper.SetMediaItemInfo_Value(item1, "C_FADEOUTSHAPE", fadeShape)
        -- Set fade in for the second item
        reaper.SetMediaItemInfo_Value(item2, "D_FADEINLEN", overlapLength)
        reaper.SetMediaItemInfo_Value(item2, "C_FADEINSHAPE", fadeShape)
        return true
    end
    return false
end

-- Apply crossfades to all overlapping items on a track using REAPER's built-in action
-- This is a unified approach that works for all generation modes
-- @param track MediaTrack: The track to apply crossfades to
-- @return number: Number of items processed
function Utils_REAPER.applyCrossfadesToTrack(track)
    if not track then return 0 end

    local itemCount = reaper.CountTrackMediaItems(track)
    if itemCount < 2 then return itemCount end  -- Need at least 2 items for crossfades

    -- Unselect all items
    reaper.SelectAllMediaItems(0, false)

    -- Select all items on this track
    for i = 0, itemCount - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        reaper.SetMediaItemSelected(item, true)
    end

    -- Apply crossfades to overlapping items (REAPER action 41059)
    reaper.Main_OnCommand(41059, 0)

    -- Unselect all items after
    reaper.SelectAllMediaItems(0, false)

    return itemCount
end

-- ============================================================================
-- VOLUME CONTROL (TRACK-LEVEL)
-- ============================================================================

-- Set the volume of a container's track in Reaper
-- @param groupPath table: Path to the group containing the container
-- @param containerIndex number: Index of the container within the group
-- @param volumeDB number: Volume in decibels
-- @return boolean: true if successful, false otherwise
function Utils_REAPER.setContainerTrackVolume(groupPath, containerIndex, volumeDB)
    if not groupPath or type(groupPath) ~= "table" then
        error("Utils_REAPER.setContainerTrackVolume: valid groupPath is required")
    end

    if not containerIndex or containerIndex < 1 then
        error("Utils_REAPER.setContainerTrackVolume: valid containerIndex is required")
    end

    if type(volumeDB) ~= "number" then
        error("Utils_REAPER.setContainerTrackVolume: volumeDB must be a number")
    end

    -- Get the group using path-based system
    local group = globals.Structures.getItemFromPath(groupPath)
    if not group or group.type ~= "group" then
        return false
    end

    -- Get the container from the group
    local container = globals.Structures.getContainerFromGroup(groupPath, containerIndex)
    if not container then
        return false
    end

    -- Find the group track
    local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return false
    end

    -- Find the container track within the group
    local containerTrack, containerTrackIdx = Utils_REAPER.findContainerGroup(groupTrackIdx, container.name)
    if not containerTrack then
        return false
    end

    -- Convert dB to linear factor and apply to track
    local linearVolume = Utils_Math.dbToLinear(volumeDB)
    reaper.SetMediaTrackInfo_Value(containerTrack, "D_VOL", linearVolume)

    -- Update arrange view to reflect changes
    reaper.UpdateArrange()

    return true
end

-- Get the current volume of a container's track from Reaper
-- @param groupIndex number|table: Index of the group or path to the group
-- @param containerIndex number: Index of the container within the group
-- @return number|nil: Volume in decibels, or nil if track not found
function Utils_REAPER.getContainerTrackVolume(groupIndex, containerIndex)
    if not groupIndex or not containerIndex then
        return nil
    end

    -- Handle both path-based and index-based systems
    local group, container
    if type(groupIndex) == "table" then
        -- New path-based system
        group = Utils_Core.getItemFromPath(groupIndex)
        if not group or not group.containers or not group.containers[containerIndex] then
            return nil
        end
        container = group.containers[containerIndex]
    else
        -- Legacy index-based system
        if groupIndex < 1 or containerIndex < 1 then
            return nil
        end
        if not globals.groups[groupIndex] or not globals.groups[groupIndex].containers[containerIndex] then
            return nil
        end
        group = globals.groups[groupIndex]
        container = group.containers[containerIndex]
    end

    -- Find the group track
    local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return nil
    end

    -- Find the container track within the group
    local containerTrack, containerTrackIdx = Utils_REAPER.findContainerGroup(groupTrackIdx, container.name)
    if not containerTrack then
        return nil
    end

    -- Get linear volume and convert to dB
    local linearVolume = reaper.GetMediaTrackInfo_Value(containerTrack, "D_VOL")
    return Utils_Math.linearToDb(linearVolume)
end

-- Set the volume of a specific channel track within a multichannel container
-- @param groupPath table: Path to the group containing the container
-- @param containerIndex number: Index of the container within the group
-- @param channelIndex number: Index of the channel within the container (1-based)
-- @param volumeDB number: Volume in decibels
-- @return boolean: true if successful, false otherwise
function Utils_REAPER.setChannelTrackVolume(groupPath, containerIndex, channelIndex, volumeDB)
    if not groupPath or type(groupPath) ~= "table" then
        error("Utils_REAPER.setChannelTrackVolume: valid groupPath is required")
    end

    if not containerIndex or containerIndex < 1 then
        error("Utils_REAPER.setChannelTrackVolume: valid containerIndex is required")
    end

    if not channelIndex or channelIndex < 1 then
        error("Utils_REAPER.setChannelTrackVolume: valid channelIndex is required")
    end

    if type(volumeDB) ~= "number" then
        error("Utils_REAPER.setChannelTrackVolume: volumeDB must be a number")
    end

    -- Get the group using path-based system
    local group = globals.Structures.getItemFromPath(groupPath)
    if not group or group.type ~= "group" then
        return false
    end

    -- Get the container from the group
    local container = globals.Structures.getContainerFromGroup(groupPath, containerIndex)
    if not container then
        return false
    end

    -- Only apply if container is in multichannel mode
    if not container.channelMode or container.channelMode == 0 then
        return false
    end

    -- Find the group track
    local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return false
    end

    -- Find the container track within the group
    local containerTrack, containerTrackIdx = Utils_REAPER.findContainerGroup(groupTrackIdx, container.name)
    if not containerTrack then
        return false
    end

    -- Get the number of tracks in the project
    local trackCount = reaper.CountTracks(0)

    -- Find the channel track (it should be a child of the container track)
    local foundChannelCount = 0
    for i = containerTrackIdx + 1, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            -- Check if this track is a child of the container track
            local parent = reaper.GetParentTrack(track)
            if parent == containerTrack then
                foundChannelCount = foundChannelCount + 1
                if foundChannelCount == channelIndex then
                    -- Found the target channel track
                    -- Convert dB to linear factor and apply to track
                    local linearVolume = Utils_Math.dbToLinear(volumeDB)
                    reaper.SetMediaTrackInfo_Value(track, "D_VOL", linearVolume)

                    -- Update arrange view to reflect changes
                    reaper.UpdateArrange()
                    return true
                end
            else
                -- We've gone past the container's children
                break
            end
        end
    end

    return false
end

-- Get the volume of a specific channel track within a multichannel container
-- @param groupIndex number: Index of the group containing the container
-- @param containerIndex number: Index of the container within the group
-- @param channelIndex number: Index of the channel within the container (1-based)
-- @return number|nil: Volume in decibels, or nil if track not found
function Utils_REAPER.getChannelTrackVolume(groupIndex, containerIndex, channelIndex)
    if not groupIndex or not containerIndex or not channelIndex then
        return nil
    end

    -- Handle both path-based and index-based systems
    local group, container
    if type(groupIndex) == "table" then
        -- New path-based system
        group = Utils_Core.getItemFromPath(groupIndex)
        if not group or not group.containers or not group.containers[containerIndex] then
            return nil
        end
        container = group.containers[containerIndex]
    else
        -- Legacy index-based system
        if groupIndex < 1 or containerIndex < 1 or channelIndex < 1 then
            return nil
        end
        if not globals.groups[groupIndex] or not globals.groups[groupIndex].containers[containerIndex] then
            return nil
        end
        group = globals.groups[groupIndex]
        container = group.containers[containerIndex]
    end

    -- Only apply if container is in multichannel mode
    if not container.channelMode or container.channelMode == 0 then
        return nil
    end

    -- Find the group track
    local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return nil
    end

    -- Find the container track within the group
    local containerTrack, containerTrackIdx = Utils_REAPER.findContainerGroup(groupTrackIdx, container.name)
    if not containerTrack then
        return nil
    end

    -- Get the number of tracks in the project
    local trackCount = reaper.CountTracks(0)

    -- Find the channel track (it should be a child of the container track)
    local foundChannelCount = 0
    for i = containerTrackIdx + 1, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            -- Check if this track is a child of the container track
            local parent = reaper.GetParentTrack(track)
            if parent == containerTrack then
                foundChannelCount = foundChannelCount + 1
                if foundChannelCount == channelIndex then
                    -- Found the target channel track
                    local linearVolume = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
                    return Utils_Math.linearToDb(linearVolume)
                end
            else
                -- We've gone past the container's children
                break
            end
        end
    end

    return nil
end

-- Sync channel volumes from Reaper tracks to container data
-- @param groupIndex number: Index of the group containing the container
-- @param containerIndex number: Index of the container within the group
function Utils_REAPER.syncChannelVolumesFromTracks(groupIndex, containerIndex)
    if not groupIndex or not containerIndex then
        return
    end

    -- Handle both path-based and index-based systems
    local group, container
    if type(groupIndex) == "table" then
        -- New path-based system
        group = Utils_Core.getItemFromPath(groupIndex)
        if not group or not group.containers or not group.containers[containerIndex] then
            return
        end
        container = group.containers[containerIndex]
    else
        -- Legacy index-based system
        if groupIndex < 1 or containerIndex < 1 then
            return
        end
        if not globals.groups[groupIndex] or not globals.groups[groupIndex].containers[containerIndex] then
            return
        end
        container = globals.groups[groupIndex].containers[containerIndex]
    end

    -- Only sync if container is in multichannel mode
    if not container.channelMode or container.channelMode == 0 then
        return
    end

    local config = globals.Constants.CHANNEL_CONFIGS[container.channelMode]
    if not config then
        return
    end

    -- Sync each channel's volume
    for i = 1, config.channels do
        local volumeDB = Utils_REAPER.getChannelTrackVolume(groupIndex, containerIndex, i)
        if volumeDB then
            container.channelVolumes[i] = volumeDB
        end
    end
end

-- Set the volume of a group's track in Reaper
-- @param groupIndex number|table: Index of the group or path to the group
-- @param volumeDB number: Volume in decibels
-- @return boolean: true if successful, false otherwise
function Utils_REAPER.setGroupTrackVolume(groupIndex, volumeDB)
    if not groupIndex then
        error("Utils_REAPER.setGroupTrackVolume: valid groupIndex is required")
    end

    if type(volumeDB) ~= "number" then
        error("Utils_REAPER.setGroupTrackVolume: volumeDB must be a number")
    end

    -- Handle both path-based and index-based systems
    local group
    if type(groupIndex) == "table" then
        -- New path-based system
        group = Utils_Core.getItemFromPath(groupIndex)
        if not group then
            return false
        end
    else
        -- Legacy index-based system
        if groupIndex < 1 then
            error("Utils_REAPER.setGroupTrackVolume: valid groupIndex is required")
        end
        if not globals.groups[groupIndex] then
            return false
        end
        group = globals.groups[groupIndex]
    end

    -- Find the group track
    local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return false
    end

    -- Convert dB to linear factor and apply to track
    local linearVolume = Utils_Math.dbToLinear(volumeDB)
    reaper.SetMediaTrackInfo_Value(groupTrack, "D_VOL", linearVolume)

    -- Update arrange view to reflect changes
    reaper.UpdateArrange()

    return true
end

-- Get the current volume of a group's track from Reaper
-- @param groupIndex number: Index of the group
-- @return number|nil: Volume in decibels, or nil if track not found
function Utils_REAPER.getGroupTrackVolume(groupIndex)
    if not groupIndex then
        return nil
    end

    -- Handle both path-based and index-based systems
    local group
    if type(groupIndex) == "table" then
        -- New path-based system
        group = Utils_Core.getItemFromPath(groupIndex)
        if not group then
            return nil
        end
    else
        -- Legacy index-based system
        if groupIndex < 1 then
            return nil
        end
        if not globals.groups[groupIndex] then
            return nil
        end
        group = globals.groups[groupIndex]
    end

    -- Find the group track
    local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return nil
    end

    -- Get linear volume and convert to dB
    local linearVolume = reaper.GetMediaTrackInfo_Value(groupTrack, "D_VOL")
    return Utils_Math.linearToDb(linearVolume)
end

-- ============================================================================
-- MUTE/SOLO CONTROL (CONTAINERS & GROUPS)
-- ============================================================================

-- Get the current mute state of a container's track from Reaper
-- @param groupPath table: Path to the group
-- @param containerIndex number: Index of the container within the group
-- @return boolean|nil: Mute state, or nil if track not found
function Utils_REAPER.getContainerTrackMute(groupPath, containerIndex)
    if not groupPath or not containerIndex then
        return nil
    end

    local group = Utils_Core.getItemFromPath(groupPath)
    if not group or not group.containers or not group.containers[containerIndex] then
        return nil
    end

    local container = group.containers[containerIndex]

    -- Find the group track
    local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return nil
    end

    -- Find the container track within the group
    local containerTrack = Utils_REAPER.findContainerGroup(groupTrackIdx, container.name)
    if not containerTrack then
        return nil
    end

    -- Get mute state from REAPER (returns 1 for muted, 0 for unmuted)
    local muteValue = reaper.GetMediaTrackInfo_Value(containerTrack, "B_MUTE")
    return muteValue == 1
end

-- Get the current solo state of a container's track from Reaper
-- @param groupPath table: Path to the group
-- @param containerIndex number: Index of the container within the group
-- @return boolean|nil: Solo state, or nil if track not found
function Utils_REAPER.getContainerTrackSolo(groupPath, containerIndex)
    if not groupPath or not containerIndex then
        return nil
    end

    local group = Utils_Core.getItemFromPath(groupPath)
    if not group or not group.containers or not group.containers[containerIndex] then
        return nil
    end

    local container = group.containers[containerIndex]

    -- Find the group track
    local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return nil
    end

    -- Find the container track within the group
    local containerTrack = Utils_REAPER.findContainerGroup(groupTrackIdx, container.name)
    if not containerTrack then
        return nil
    end

    -- Get solo state from REAPER (returns non-zero for soloed)
    local soloValue = reaper.GetMediaTrackInfo_Value(containerTrack, "I_SOLO")
    return soloValue ~= 0
end

-- Set the mute state of a container's track in Reaper
-- @param groupPath table: Path to the group
-- @param containerIndex number: Index of the container
-- @param isMuted boolean: true to mute, false to unmute
-- @return boolean: true if successful, false otherwise
function Utils_REAPER.setContainerTrackMute(groupPath, containerIndex, isMuted)
    if not groupPath or type(groupPath) ~= "table" or not containerIndex or containerIndex < 1 then
        return false
    end

    local group = globals.Structures.getItemFromPath(groupPath)
    if not group or group.type ~= "group" then
        return false
    end

    local container = globals.Structures.getContainerFromGroup(groupPath, containerIndex)
    if not container then
        return false
    end

    local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return false
    end

    local containerTrack, containerTrackIdx = Utils_REAPER.findContainerGroup(groupTrackIdx, container.name)
    if not containerTrack then
        return false
    end

    reaper.SetMediaTrackInfo_Value(containerTrack, "B_MUTE", isMuted and 1 or 0)
    reaper.UpdateArrange()
    return true
end

-- Set the solo state of a container's track in Reaper
-- @param groupPath table: Path to the group
-- @param containerIndex number: Index of the container
-- @param isSoloed boolean: true to solo, false to unsolo
-- @return boolean: true if successful, false otherwise
function Utils_REAPER.setContainerTrackSolo(groupPath, containerIndex, isSoloed)
    if not groupPath or type(groupPath) ~= "table" or not containerIndex or containerIndex < 1 then
        return false
    end

    local group = globals.Structures.getItemFromPath(groupPath)
    if not group or group.type ~= "group" then
        return false
    end

    local container = globals.Structures.getContainerFromGroup(groupPath, containerIndex)
    if not container then
        return false
    end

    local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return false
    end

    local containerTrack, containerTrackIdx = Utils_REAPER.findContainerGroup(groupTrackIdx, container.name)
    if not containerTrack then
        return false
    end

    reaper.SetMediaTrackInfo_Value(containerTrack, "I_SOLO", isSoloed and 1 or 0)
    reaper.UpdateArrange()
    return true
end

-- Get the current mute state of a group's track from Reaper
-- @param groupPath table: Path to the group
-- @return boolean|nil: Mute state, or nil if track not found
function Utils_REAPER.getGroupTrackMute(groupPath)
    if not groupPath then
        return nil
    end

    local group = Utils_Core.getItemFromPath(groupPath)
    if not group or group.type ~= "group" then
        return nil
    end

    -- Find the group track
    local groupTrack = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return nil
    end

    -- Get mute state from REAPER (returns 1 for muted, 0 for unmuted)
    local muteValue = reaper.GetMediaTrackInfo_Value(groupTrack, "B_MUTE")
    return muteValue == 1
end

-- Get the current solo state of a group's track from Reaper
-- @param groupPath table: Path to the group
-- @return boolean|nil: Solo state, or nil if track not found
function Utils_REAPER.getGroupTrackSolo(groupPath)
    if not groupPath then
        return nil
    end

    local group = Utils_Core.getItemFromPath(groupPath)
    if not group or group.type ~= "group" then
        return nil
    end

    -- Find the group track
    local groupTrack = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return nil
    end

    -- Get solo state from REAPER (returns non-zero for soloed)
    local soloValue = reaper.GetMediaTrackInfo_Value(groupTrack, "I_SOLO")
    return soloValue ~= 0
end

-- Set the mute state of a group's track in Reaper
-- @param groupIndex number|table: Index of the group or path to the group
-- @param isMuted boolean: true to mute, false to unmute
-- @return boolean: true if successful, false otherwise
function Utils_REAPER.setGroupTrackMute(groupIndex, isMuted)
    if not groupIndex then
        return false
    end

    -- Handle both path-based and index-based systems
    local group
    if type(groupIndex) == "table" then
        -- New path-based system
        group = Utils_Core.getItemFromPath(groupIndex)
        if not group then
            return false
        end
    else
        -- Legacy index-based system
        if groupIndex < 1 then
            return false
        end
        group = globals.groups[groupIndex]
        if not group then
            return false
        end
    end

    local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return false
    end

    reaper.SetMediaTrackInfo_Value(groupTrack, "B_MUTE", isMuted and 1 or 0)
    reaper.UpdateArrange()
    return true
end

-- Set the solo state of a group's track in Reaper
-- @param groupIndex number|table: Index of the group or path to the group
-- @param isSoloed boolean: true to solo, false to unsolo
-- @return boolean: true if successful, false otherwise
function Utils_REAPER.setGroupTrackSolo(groupIndex, isSoloed)
    if not groupIndex then
        return false
    end

    -- Handle both path-based and index-based systems
    local group
    if type(groupIndex) == "table" then
        -- New path-based system
        group = Utils_Core.getItemFromPath(groupIndex)
        if not group then
            return false
        end
    else
        -- Legacy index-based system
        if groupIndex < 1 then
            return false
        end
        group = globals.groups[groupIndex]
        if not group then
            return false
        end
    end

    local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return false
    end

    reaper.SetMediaTrackInfo_Value(groupTrack, "I_SOLO", isSoloed and 1 or 0)
    reaper.UpdateArrange()
    return true
end

-- ============================================================================
-- TRACK NAMING (CONTAINERS & GROUPS)
-- ============================================================================

-- Get the current name of a container's track from Reaper
-- @param groupPath table: Path to the group
-- @param containerIndex number: Index of the container within the group
-- @return string|nil: Track name, or nil if track not found
function Utils_REAPER.getContainerTrackName(groupPath, containerIndex)
    if not groupPath or not containerIndex then
        return nil
    end

    local group = Utils_Core.getItemFromPath(groupPath)
    if not group or not group.containers or not group.containers[containerIndex] then
        return nil
    end

    local container = group.containers[containerIndex]

    -- Find the group track
    local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return nil
    end

    -- Find the container track within the group
    local containerTrack = Utils_REAPER.findContainerGroup(groupTrackIdx, container.name)
    if not containerTrack then
        return nil
    end

    -- Get track name from REAPER
    local success, trackName = reaper.GetSetMediaTrackInfo_String(containerTrack, "P_NAME", "", false)
    if success then
        return trackName
    end
    return nil
end

-- Set the name of a container's track in Reaper
-- @param groupPath table: Path to the group
-- @param containerIndex number: Index of the container
-- @param newName string: New name for the container
-- @return boolean: true if successful, false otherwise
function Utils_REAPER.setContainerTrackName(groupPath, containerIndex, newName)
    if not groupPath or type(groupPath) ~= "table" or not containerIndex or containerIndex < 1 then
        return false
    end

    if not newName or newName == "" then
        return false
    end

    local group = globals.Structures.getItemFromPath(groupPath)
    if not group or group.type ~= "group" then
        return false
    end

    local container = globals.Structures.getContainerFromGroup(groupPath, containerIndex)
    if not container then
        return false
    end

    local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return false
    end

    local containerTrack, containerTrackIdx = Utils_REAPER.findContainerGroup(groupTrackIdx, container.name)
    if not containerTrack then
        return false
    end

    -- Update track name in REAPER
    reaper.GetSetMediaTrackInfo_String(containerTrack, "P_NAME", newName, true)
    reaper.UpdateArrange()
    return true
end

-- Get the current name of a group's track from Reaper
-- @param groupPath table: Path to the group
-- @return string|nil: Track name, or nil if track not found
function Utils_REAPER.getGroupTrackName(groupPath)
    if not groupPath then
        return nil
    end

    local group = Utils_Core.getItemFromPath(groupPath)
    if not group or group.type ~= "group" then
        return nil
    end

    -- Find the group track
    local groupTrack = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return nil
    end

    -- Get track name from REAPER
    local success, trackName = reaper.GetSetMediaTrackInfo_String(groupTrack, "P_NAME", "", false)
    if success then
        return trackName
    end
    return nil
end

-- Set the name of a group's track in Reaper
-- @param groupPath table: Path to the group in the items hierarchy
-- @param newName string: New name for the group
-- @return boolean: true if successful, false otherwise
function Utils_REAPER.setGroupTrackName(groupPath, newName)
    if not groupPath then
        return false
    end

    if not newName or newName == "" then
        return false
    end

    -- Handle both path-based and index-based systems
    local group
    if type(groupPath) == "table" then
        -- New path-based system
        group = Utils_Core.getItemFromPath(groupPath)
        if not group then
            return false
        end
    else
        -- Legacy index-based system
        if groupPath < 1 then
            return false
        end
        if not globals.groups[groupPath] then
            return false
        end
        group = globals.groups[groupPath]
    end

    -- Find the group track
    local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return false
    end

    -- Update track name in REAPER
    reaper.GetSetMediaTrackInfo_String(groupTrack, "P_NAME", newName, true)
    reaper.UpdateArrange()
    return true
end

-- ============================================================================
-- SYNC FUNCTIONS (REAPER → DATA STRUCTURE)
-- ============================================================================

-- Sync container volume from Reaper track to container data
-- @param groupIndex number|table: Index of the group or path to the group
-- @param containerIndex number: Index of the container within the group
function Utils_REAPER.syncContainerVolumeFromTrack(groupIndex, containerIndex)
    local volumeDB = Utils_REAPER.getContainerTrackVolume(groupIndex, containerIndex)
    if volumeDB then
        if type(groupIndex) == "table" then
            -- New path-based system
            local group = Utils_Core.getItemFromPath(groupIndex)
            if group and group.containers and group.containers[containerIndex] then
                group.containers[containerIndex].trackVolume = volumeDB
            end
        else
            -- Legacy index-based system
            if globals.groups[groupIndex] and globals.groups[groupIndex].containers[containerIndex] then
                globals.groups[groupIndex].containers[containerIndex].trackVolume = volumeDB
            end
        end
    end
end

-- Sync container name from Reaper track to container data
-- @param groupPath table: Path to the group
-- @param containerIndex number: Index of the container within the group
function Utils_REAPER.syncContainerNameFromTrack(groupPath, containerIndex)
    local trackName = Utils_REAPER.getContainerTrackName(groupPath, containerIndex)
    if trackName then
        local group = Utils_Core.getItemFromPath(groupPath)
        if group and group.containers and group.containers[containerIndex] then
            group.containers[containerIndex].name = trackName
        end
    end
end

-- Sync container mute from Reaper track to container data
-- @param groupPath table: Path to the group
-- @param containerIndex number: Index of the container within the group
function Utils_REAPER.syncContainerMuteFromTrack(groupPath, containerIndex)
    local isMuted = Utils_REAPER.getContainerTrackMute(groupPath, containerIndex)
    if isMuted ~= nil then
        local group = Utils_Core.getItemFromPath(groupPath)
        if group and group.containers and group.containers[containerIndex] then
            group.containers[containerIndex].isMuted = isMuted
        end
    end
end

-- Sync container solo from Reaper track to container data
-- @param groupPath table: Path to the group
-- @param containerIndex number: Index of the container within the group
function Utils_REAPER.syncContainerSoloFromTrack(groupPath, containerIndex)
    local isSoloed = Utils_REAPER.getContainerTrackSolo(groupPath, containerIndex)
    if isSoloed ~= nil then
        local group = Utils_Core.getItemFromPath(groupPath)
        if group and group.containers and group.containers[containerIndex] then
            group.containers[containerIndex].isSoloed = isSoloed
        end
    end
end

-- Sync group volume from Reaper track to group data
-- @param groupPath table: Path to the group
function Utils_REAPER.syncGroupVolumeFromTrack(groupPath)
    local volumeDB = Utils_REAPER.getGroupTrackVolume(groupPath)
    if volumeDB then
        local group = globals.Structures.getItemFromPath(groupPath)
        if group and group.type == "group" then
            group.trackVolume = volumeDB
        end
    end
end

-- Sync group name from Reaper track to group data
-- @param groupPath table: Path to the group
function Utils_REAPER.syncGroupNameFromTrack(groupPath)
    local trackName = Utils_REAPER.getGroupTrackName(groupPath)
    if trackName then
        local group = Utils_Core.getItemFromPath(groupPath)
        if group and group.type == "group" then
            group.name = trackName
        end
    end
end

-- Sync group mute from Reaper track to group data
-- @param groupPath table: Path to the group
function Utils_REAPER.syncGroupMuteFromTrack(groupPath)
    local isMuted = Utils_REAPER.getGroupTrackMute(groupPath)
    if isMuted ~= nil then
        local group = Utils_Core.getItemFromPath(groupPath)
        if group and group.type == "group" then
            group.isMuted = isMuted
        end
    end
end

-- Sync group solo from Reaper track to group data
-- @param groupPath table: Path to the group
function Utils_REAPER.syncGroupSoloFromTrack(groupPath)
    local isSoloed = Utils_REAPER.getGroupTrackSolo(groupPath)
    if isSoloed ~= nil then
        local group = Utils_Core.getItemFromPath(groupPath)
        if group and group.type == "group" then
            group.isSoloed = isSoloed
        end
    end
end

-- ============================================================================
-- FOLDER TRACK CONTROLS (for new globals.items structure with folders)
-- ============================================================================

-- Get the current volume of a folder's track from Reaper
-- @param folderPath table: Path to the folder in the items hierarchy
-- @return number|nil: Volume in decibels, or nil if track not found
function Utils_REAPER.getFolderTrackVolume(folderPath)
    if not folderPath then
        return nil
    end

    local folder = Utils_Core.getItemFromPath(folderPath)
    if not folder or folder.type ~= "folder" then
        return nil
    end

    -- Try GUID first
    local folderTrack = nil
    if folder.trackGUID and globals.Generation then
        folderTrack = globals.Generation.findTrackByGUID(folder.trackGUID)
    end

    -- Fallback to name search
    if not folderTrack then
        folderTrack = Utils_REAPER.findTrackByName(folder.name)
    end

    if not folderTrack then
        return nil
    end

    -- Get linear volume and convert to dB
    local linearVolume = reaper.GetMediaTrackInfo_Value(folderTrack, "D_VOL")
    return Utils_Math.linearToDb(linearVolume)
end

-- Set the volume of a folder's track in Reaper
-- @param folderPath table: Path to the folder in the items hierarchy
-- @param volumeDB number: Volume in decibels
-- @return boolean: true if successful, false otherwise
function Utils_REAPER.setFolderTrackVolume(folderPath, volumeDB)
    if not folderPath or type(folderPath) ~= "table" then
        return false
    end

    if type(volumeDB) ~= "number" then
        return false
    end

    -- Get the folder from the path
    local folder = Utils_Core.getItemFromPath(folderPath)
    if not folder or folder.type ~= "folder" then
        return false
    end

    -- Find the folder track (try GUID first, then fallback to name)
    local folderTrack = nil
    if folder.trackGUID and globals.Generation then
        folderTrack = globals.Generation.findTrackByGUID(folder.trackGUID)
    end
    if not folderTrack then
        folderTrack = Utils_REAPER.findTrackByName(folder.name)
    end
    if not folderTrack then
        return false
    end

    -- Convert dB to linear factor and apply to track
    local linearVolume = Utils_Math.dbToLinear(volumeDB)
    reaper.SetMediaTrackInfo_Value(folderTrack, "D_VOL", linearVolume)

    -- Update arrange view to reflect changes
    reaper.UpdateArrange()

    return true
end

-- Set the mute state of a folder's track in Reaper
-- @param folderPath table: Path to the folder in the items hierarchy
-- @param isMuted boolean: true to mute, false to unmute
-- @return boolean: true if successful, false otherwise
function Utils_REAPER.setFolderTrackMute(folderPath, isMuted)
    if not folderPath or type(folderPath) ~= "table" then
        return false
    end

    -- Get the folder from the path
    local folder = Utils_Core.getItemFromPath(folderPath)
    if not folder or folder.type ~= "folder" then
        return false
    end

    -- Find the folder track (try GUID first, then fallback to name)
    local folderTrack = nil
    if folder.trackGUID and globals.Generation then
        folderTrack = globals.Generation.findTrackByGUID(folder.trackGUID)
    end
    if not folderTrack then
        folderTrack = Utils_REAPER.findTrackByName(folder.name)
    end
    if not folderTrack then
        return false
    end

    reaper.SetMediaTrackInfo_Value(folderTrack, "B_MUTE", isMuted and 1 or 0)
    reaper.UpdateArrange()
    return true
end

-- Set the solo state of a folder's track in Reaper
-- @param folderPath table: Path to the folder in the items hierarchy
-- @param isSoloed boolean: true to solo, false to unsolo
-- @return boolean: true if successful, false otherwise
function Utils_REAPER.setFolderTrackSolo(folderPath, isSoloed)
    if not folderPath or type(folderPath) ~= "table" then
        return false
    end

    -- Get the folder from the path
    local folder = Utils_Core.getItemFromPath(folderPath)
    if not folder or folder.type ~= "folder" then
        return false
    end

    -- Find the folder track (try GUID first, then fallback to name)
    local folderTrack = nil
    if folder.trackGUID and globals.Generation then
        folderTrack = globals.Generation.findTrackByGUID(folder.trackGUID)
    end
    if not folderTrack then
        folderTrack = Utils_REAPER.findTrackByName(folder.name)
    end
    if not folderTrack then
        return false
    end

    reaper.SetMediaTrackInfo_Value(folderTrack, "I_SOLO", isSoloed and 1 or 0)
    reaper.UpdateArrange()
    return true
end

-- Set the name of a folder's track in Reaper
-- @param folderPath table: Path to the folder in the items hierarchy
-- @param newName string: New name for the folder
-- @return boolean: true if successful, false otherwise
function Utils_REAPER.setFolderTrackName(folderPath, newName)
    if not folderPath or type(folderPath) ~= "table" then
        return false
    end

    if not newName or newName == "" then
        return false
    end

    -- Get the folder from the path
    local folder = Utils_Core.getItemFromPath(folderPath)
    if not folder or folder.type ~= "folder" then
        return false
    end

    -- Find the folder track (try GUID first, then fallback to name)
    local folderTrack = nil
    if folder.trackGUID and globals.Generation then
        folderTrack = globals.Generation.findTrackByGUID(folder.trackGUID)
    end
    if not folderTrack then
        folderTrack = Utils_REAPER.findTrackByName(folder.name)
    end
    if not folderTrack then
        return false
    end

    -- Update track name in REAPER
    reaper.GetSetMediaTrackInfo_String(folderTrack, "P_NAME", newName, true)
    reaper.UpdateArrange()
    return true
end

-- Get the current mute state of a folder's track from Reaper
-- @param folderPath table: Path to the folder in the items hierarchy
-- @return boolean|nil: Mute state, or nil if track not found
function Utils_REAPER.getFolderTrackMute(folderPath)
    if not folderPath then
        return nil
    end

    local folder = Utils_Core.getItemFromPath(folderPath)
    if not folder or folder.type ~= "folder" then
        return nil
    end

    -- Try GUID first
    local folderTrack = nil
    if folder.trackGUID and globals.Generation then
        folderTrack = globals.Generation.findTrackByGUID(folder.trackGUID)
    end

    -- Fallback to name search
    if not folderTrack then
        folderTrack = Utils_REAPER.findTrackByName(folder.name)
    end

    if not folderTrack then
        return nil
    end

    -- Get mute state from REAPER (returns 1 for muted, 0 for unmuted)
    local muteValue = reaper.GetMediaTrackInfo_Value(folderTrack, "B_MUTE")
    return muteValue == 1
end

-- Get the current solo state of a folder's track from Reaper
-- @param folderPath table: Path to the folder in the items hierarchy
-- @return boolean|nil: Solo state, or nil if track not found
function Utils_REAPER.getFolderTrackSolo(folderPath)
    if not folderPath then
        return nil
    end

    local folder = Utils_Core.getItemFromPath(folderPath)
    if not folder or folder.type ~= "folder" then
        return nil
    end

    -- Try GUID first
    local folderTrack = nil
    if folder.trackGUID and globals.Generation then
        folderTrack = globals.Generation.findTrackByGUID(folder.trackGUID)
    end

    -- Fallback to name search
    if not folderTrack then
        folderTrack = Utils_REAPER.findTrackByName(folder.name)
    end

    if not folderTrack then
        return nil
    end

    -- Get solo state from REAPER (returns non-zero for soloed)
    local soloValue = reaper.GetMediaTrackInfo_Value(folderTrack, "I_SOLO")
    return soloValue ~= 0
end

-- Get the current name of a folder's track from Reaper
-- @param folderPath table: Path to the folder in the items hierarchy
-- @return string|nil: Track name, or nil if track not found
function Utils_REAPER.getFolderTrackName(folderPath)
    if not folderPath then
        return nil
    end

    local folder = Utils_Core.getItemFromPath(folderPath)
    if not folder or folder.type ~= "folder" then
        return nil
    end

    -- Try GUID first
    local folderTrack = nil
    if folder.trackGUID and globals.Generation then
        folderTrack = globals.Generation.findTrackByGUID(folder.trackGUID)
    end

    -- Fallback to name search
    if not folderTrack then
        folderTrack = Utils_REAPER.findTrackByName(folder.name)
    end

    if not folderTrack then
        return nil
    end

    -- Get track name from REAPER
    local success, trackName = reaper.GetSetMediaTrackInfo_String(folderTrack, "P_NAME", "", false)
    if success then
        return trackName
    end
    return nil
end

-- Sync folder volume from Reaper track to folder data
-- @param folderPath table: Path to the folder
function Utils_REAPER.syncFolderVolumeFromTrack(folderPath)
    local volumeDB = Utils_REAPER.getFolderTrackVolume(folderPath)
    if volumeDB then
        local folder = Utils_Core.getItemFromPath(folderPath)
        if folder and folder.type == "folder" then
            folder.trackVolume = volumeDB
        end
    end
end

-- Sync folder name from Reaper track to folder data
-- @param folderPath table: Path to the folder
function Utils_REAPER.syncFolderNameFromTrack(folderPath)
    local trackName = Utils_REAPER.getFolderTrackName(folderPath)
    if trackName then
        local folder = Utils_Core.getItemFromPath(folderPath)
        if folder and folder.type == "folder" then
            folder.name = trackName
        end
    end
end

-- Sync folder mute from Reaper track to folder data
-- @param folderPath table: Path to the folder
function Utils_REAPER.syncFolderMuteFromTrack(folderPath)
    local isMuted = Utils_REAPER.getFolderTrackMute(folderPath)
    if isMuted ~= nil then
        local folder = Utils_Core.getItemFromPath(folderPath)
        if folder and folder.type == "folder" then
            folder.isMuted = isMuted
        end
    end
end

-- Sync folder solo from Reaper track to folder data
-- @param folderPath table: Path to the folder
function Utils_REAPER.syncFolderSoloFromTrack(folderPath)
    local isSoloed = Utils_REAPER.getFolderTrackSolo(folderPath)
    if isSoloed ~= nil then
        local folder = Utils_Core.getItemFromPath(folderPath)
        if folder and folder.type == "folder" then
            folder.isSoloed = isSoloed
        end
    end
end

-- ============================================================================
-- VOLUME INITIALIZATION
-- ============================================================================

-- Initialize trackVolume property for all existing containers and groups that don't have it
-- This ensures backward compatibility with existing projects
function Utils_REAPER.initializeContainerVolumes()
    if not globals.groups then
        return
    end

    for groupIndex, group in ipairs(globals.groups) do
        -- Initialize group trackVolume if it doesn't exist
        if group.trackVolume == nil then
            group.trackVolume = Constants.DEFAULTS.CONTAINER_VOLUME_DEFAULT
        end

        if group.containers then
            for containerIndex, container in ipairs(group.containers) do
                -- Initialize container trackVolume if it doesn't exist
                if container.trackVolume == nil then
                    container.trackVolume = Constants.DEFAULTS.CONTAINER_VOLUME_DEFAULT
                end
            end
        end
    end
end

-- ============================================================================
-- FADE MANAGEMENT (QUEUED UPDATES)
-- ============================================================================

-- Add a fade update request to the queue
-- @param groupPath table: Path to the group
-- @param containerIndex number: Index of the container (nil for group-wide update)
-- @param modifiedFade string: Which fade was modified ("fadeIn", "fadeOut", or nil for both)
function Utils_REAPER.queueFadeUpdate(groupPath, containerIndex, modifiedFade)
    local key = Utils_String.pathToString(groupPath) .. "_" .. (containerIndex or "all")
    fadeUpdateQueue[key] = {
        groupPath = groupPath,
        containerIndex = containerIndex,
        modifiedFade = modifiedFade,
        timestamp = os.clock()
    }
end

-- Process all queued fade updates (call this after ImGui frame)
function Utils_REAPER.processQueuedFadeUpdates()
    for key, update in pairs(fadeUpdateQueue) do
        if update.containerIndex then
            Utils_REAPER.applyFadeSettingsToContainerItems(update.groupPath, update.containerIndex, update.modifiedFade)
        else
            Utils_REAPER.applyFadeSettingsToGroupItems(update.groupPath, update.modifiedFade)
        end
    end
    -- Clear the queue
    fadeUpdateQueue = {}
end

-- Apply fade settings to all media items in a specific container in real-time
-- @param groupPath table: Path to the group
-- @param containerIndex number: Index of the container
-- @param modifiedFade string: Which fade was modified ("fadeIn", "fadeOut", or nil for both)
function Utils_REAPER.applyFadeSettingsToContainerItems(groupPath, containerIndex, modifiedFade)
    -- Get the group using path-based system
    local group = globals.Structures.getItemFromPath(groupPath)
    if not group or group.type ~= "group" then
        return
    end

    -- Get the container from the group
    local container = globals.Structures.getContainerFromGroup(groupPath, containerIndex)
    if not container then
        return
    end

    -- Find the group track first
    local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack or not groupTrackIdx then
        return -- Group track not found
    end

    -- Find the container track within the group
    local containerTrack, containerTrackIdx = Utils_REAPER.findContainerGroup(groupTrackIdx, container.name)
    if not containerTrack then
        return -- Container track not found
    end

    -- Get effective parameters (handles parent inheritance)
    local Structures = require("DM_Ambiance_Structures")
    local effectiveParams = Structures.getEffectiveContainerParams(group, container)

    -- Determine which tracks to process based on channel mode
    local tracksToProcess = {}
    if container.channelMode and container.channelMode > 0 then
        -- Multi-channel mode: get child tracks where items are actually placed
        local Generation = require("DM_Ambiance_Generation")
        tracksToProcess = Generation.getExistingChannelTracks(containerTrack)
    else
        -- Default mode: items are on the container track itself
        tracksToProcess = {containerTrack}
    end

    -- Check if we have any tracks to process
    local totalItemCount = 0
    for _, track in ipairs(tracksToProcess) do
        totalItemCount = totalItemCount + reaper.CountTrackMediaItems(track)
    end

    if totalItemCount == 0 then
        return -- No items to update
    end

    -- Begin undo block for batch operation
    reaper.Undo_BeginBlock()

    -- Process items on all relevant tracks
    for _, track in ipairs(tracksToProcess) do
        local itemCount = reaper.CountTrackMediaItems(track)
        for i = 0, itemCount - 1 do
            local item = reaper.GetTrackMediaItem(track, i)
            if item then
            local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

            -- Calculate desired fade durations
            local desiredFadeInDuration = 0
            local desiredFadeOutDuration = 0

            -- Calculate fade in duration
            if effectiveParams.fadeInEnabled then
                local duration = effectiveParams.fadeInDuration or 0.1
                if effectiveParams.fadeInUsePercentage then
                    desiredFadeInDuration = (duration / 100.0) * itemLength
                else
                    desiredFadeInDuration = duration
                end
                desiredFadeInDuration = math.max(0, desiredFadeInDuration)
            end

            -- Calculate fade out duration
            if effectiveParams.fadeOutEnabled then
                local duration = effectiveParams.fadeOutDuration or 0.1
                if effectiveParams.fadeOutUsePercentage then
                    desiredFadeOutDuration = (duration / 100.0) * itemLength
                else
                    desiredFadeOutDuration = duration
                end
                desiredFadeOutDuration = math.max(0, desiredFadeOutDuration)
            end

            -- Apply "push" logic if fades overlap
            local finalFadeInDuration = desiredFadeInDuration
            local finalFadeOutDuration = desiredFadeOutDuration

            if (desiredFadeInDuration + desiredFadeOutDuration) > itemLength then
                if modifiedFade == "fadeIn" then
                    -- Fade in is being modified, let it "push" the fade out
                    finalFadeInDuration = math.min(desiredFadeInDuration, itemLength)
                    finalFadeOutDuration = math.max(0, itemLength - finalFadeInDuration)
                elseif modifiedFade == "fadeOut" then
                    -- Fade out is being modified, let it "push" the fade in
                    finalFadeOutDuration = math.min(desiredFadeOutDuration, itemLength)
                    finalFadeInDuration = math.max(0, itemLength - finalFadeOutDuration)
                else
                    -- No specific fade being modified, limit both to item length
                    finalFadeInDuration = math.min(desiredFadeInDuration, itemLength)
                    finalFadeOutDuration = math.min(desiredFadeOutDuration, itemLength - finalFadeInDuration)
                end
            end

            -- Apply fade in
            if effectiveParams.fadeInEnabled then
                reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", finalFadeInDuration)
                reaper.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", effectiveParams.fadeInShape or 0)
                reaper.SetMediaItemInfo_Value(item, "D_FADEINDIR", effectiveParams.fadeInCurve or 0.0)
            else
                reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0)
            end

            -- Apply fade out
            if effectiveParams.fadeOutEnabled then
                reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", finalFadeOutDuration)
                reaper.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", effectiveParams.fadeOutShape or 0)
                reaper.SetMediaItemInfo_Value(item, "D_FADEOUTDIR", effectiveParams.fadeOutCurve or 0.0)
            else
                reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0)
                end
            end
        end
    end

    reaper.Undo_EndBlock("Apply Fade Settings to Container Items", -1)
    reaper.UpdateArrange()
end

-- Apply fade settings to all containers in a group in real-time
-- @param groupPath table: Path to the group
-- @param modifiedFade string: Which fade was modified ("fadeIn", "fadeOut", or nil for both)
function Utils_REAPER.applyFadeSettingsToGroupItems(groupPath, modifiedFade)
    -- Get the group using path-based system
    local group = globals.Structures.getItemFromPath(groupPath)
    if not group or group.type ~= "group" then
        return
    end

    if not group.containers then
        return
    end

    -- Apply fade settings to all containers in this group
    for containerIndex, container in ipairs(group.containers) do
        Utils_REAPER.applyFadeSettingsToContainerItems(groupPath, containerIndex, modifiedFade)
    end
end

-- ============================================================================
-- RANDOMIZATION (QUEUED UPDATES)
-- ============================================================================

-- Add a randomization update request to the queue
-- @param groupPath table: Path to the group
-- @param containerIndex number: Index of the container (nil for group-wide update)
-- @param modifiedParam string: Which parameter was modified ("pitch", "volume", "pan", or nil for all)
function Utils_REAPER.queueRandomizationUpdate(groupPath, containerIndex, modifiedParam)
    local key = Utils_String.pathToString(groupPath) .. "_" .. (containerIndex or "all") .. "_randomization"
    randomizationUpdateQueue[key] = {
        groupPath = groupPath,
        containerIndex = containerIndex,
        modifiedParam = modifiedParam,
        timestamp = os.clock()
    }
end

-- Process all queued randomization updates (call this after ImGui frame)
function Utils_REAPER.processQueuedRandomizationUpdates()
    for key, update in pairs(randomizationUpdateQueue) do
        if update.containerIndex then
            Utils_REAPER.applyRandomizationSettingsToContainerItems(update.groupPath, update.containerIndex, update.modifiedParam)
        else
            Utils_REAPER.applyRandomizationSettingsToGroupItems(update.groupPath, update.modifiedParam)
        end
    end
    -- Clear the queue
    randomizationUpdateQueue = {}
end

-- Apply randomization settings to all media items in a specific container in real-time
-- @param groupPath table: Path to the group
-- @param containerIndex number: Index of the container
-- @param modifiedParam string: Which parameter was modified ("pitch", "volume", "pan", or nil for all)
function Utils_REAPER.applyRandomizationSettingsToContainerItems(groupPath, containerIndex, modifiedParam)
    -- Get the group using path-based system
    local group = globals.Structures.getItemFromPath(groupPath)
    if not group or group.type ~= "group" then
        return
    end

    -- Get the container from the group
    local container = globals.Structures.getContainerFromGroup(groupPath, containerIndex)
    if not container then
        return
    end

    local effectiveParams = globals.Structures.getEffectiveContainerParams(group, container)

    -- Find the container track
    local groupTrack, groupTrackIdx = Utils_REAPER.findGroupByName(group.name)
    if not groupTrack then
        return
    end

    local containerTrack, containerTrackIdx = Utils_REAPER.findContainerGroup(groupTrackIdx, container.name)
    if not containerTrack then
        return
    end

    -- Determine which tracks to process based on channel mode
    local tracksToProcess = {}
    if container.channelMode and container.channelMode > 0 then
        -- Multi-channel mode: get child tracks where items are actually placed
        local Generation = require("DM_Ambiance_Generation")
        tracksToProcess = Generation.getExistingChannelTracks(containerTrack)
    else
        -- Default mode: items are on the container track itself
        tracksToProcess = {containerTrack}
    end

    -- Count total items across all tracks
    local totalItemCount = 0
    for _, track in ipairs(tracksToProcess) do
        totalItemCount = totalItemCount + reaper.GetTrackNumMediaItems(track)
    end

    if totalItemCount == 0 then
        return
    end

    -- Begin undo block for batch operation
    reaper.Undo_BeginBlock()

    -- If we're dealing with pan randomization, handle envelope creation/removal in batch
    if (modifiedParam == "pan" or modifiedParam == nil) then
        -- Save current selection
        local numSelectedItems = reaper.CountSelectedMediaItems(0)
        local originalSelection = {}
        for i = 0, numSelectedItems - 1 do
            originalSelection[i + 1] = reaper.GetSelectedMediaItem(0, i)
        end

        -- Select ALL items across all tracks (container + children)
        reaper.SelectAllMediaItems(0, false)
        local allContainerItems = {}
        for _, track in ipairs(tracksToProcess) do
            local trackItemCount = reaper.GetTrackNumMediaItems(track)
            for i = 0, trackItemCount - 1 do
                local item = reaper.GetTrackMediaItem(track, i)
                if item then
                    reaper.SetMediaItemSelected(item, true)
                    table.insert(allContainerItems, item)
                end
            end
        end

        if #allContainerItems > 0 then
            if effectiveParams.randomizePan then
                -- Check if ANY item needs envelope creation
                local needsCreation = false
                for _, item in ipairs(allContainerItems) do
                    local take = reaper.GetActiveTake(item)
                    if take then
                        local env = reaper.GetTakeEnvelopeByName(take, "Pan")
                        if not env then
                            needsCreation = true
                            break
                        end
                    end
                end

                -- If any item needs envelope creation, toggle ON for all
                if needsCreation then
                    reaper.Main_OnCommand(40694, 0)  -- Create/toggle take pan envelopes for all selected items
                    reaper.UpdateArrange()
                    reaper.UpdateTimeline()
                end
            else
                -- Check if ANY item has an envelope to remove
                local hasEnvelopes = false
                for _, item in ipairs(allContainerItems) do
                    local take = reaper.GetActiveTake(item)
                    if take then
                        local env = reaper.GetTakeEnvelopeByName(take, "Pan")
                        if env then
                            hasEnvelopes = true
                            break
                        end
                    end
                end

                -- If any item has envelope, toggle OFF for all
                if hasEnvelopes then
                    reaper.Main_OnCommand(40694, 0)  -- Toggle OFF take pan envelopes for all selected items
                    reaper.UpdateArrange()
                    reaper.UpdateTimeline()
                end
            end
        end

        -- Restore original selection
        reaper.SelectAllMediaItems(0, false)
        for _, item in ipairs(originalSelection) do
            reaper.SetMediaItemSelected(item, true)
        end
    end

    -- Now apply individual randomization values across all tracks
    for _, track in ipairs(tracksToProcess) do
        local trackItemCount = reaper.GetTrackNumMediaItems(track)
        for i = 0, trackItemCount - 1 do
            local item = reaper.GetTrackMediaItem(track, i)
            if item then
                local take = reaper.GetActiveTake(item)
                if take then
                    -- Get original values from item data
                    local itemData = nil
                    local retval, takeName = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
                    if not retval then
                        takeName = "unknown"
                    end

                    for _, containerData in ipairs(container.items) do
                        if takeName == containerData.name then
                            itemData = containerData
                            break
                        end
                    end

                    if itemData then
                        Utils_REAPER.applyRandomizationToItem(item, take, itemData, effectiveParams, modifiedParam)
                    end
                end
            end
        end
    end

    reaper.Undo_EndBlock("Apply Randomization Settings to Container Items", -1)
    reaper.UpdateArrange()
end

-- Apply randomization settings to all containers in a group in real-time
-- @param groupPath table: Path to the group
-- @param modifiedParam string: Which parameter was modified ("pitch", "volume", "pan", or nil for all)
function Utils_REAPER.applyRandomizationSettingsToGroupItems(groupPath, modifiedParam)
    -- Get the group using path-based system
    local group = globals.Structures.getItemFromPath(groupPath)
    if not group or group.type ~= "group" then
        return
    end

    if not group.containers then
        return
    end

    -- Apply randomization settings to all containers in this group
    for containerIndex, container in ipairs(group.containers) do
        Utils_REAPER.applyRandomizationSettingsToContainerItems(groupPath, containerIndex, modifiedParam)
    end
end

-- Apply randomization to a single item based on current and previous settings
-- @param item MediaItem: The media item
-- @param take MediaItemTake: The media item take
-- @param itemData table: Original item data with originalPitch, originalVolume, originalPan
-- @param effectiveParams table: Current effective parameters
-- @param modifiedParam string: Which parameter was modified
function Utils_REAPER.applyRandomizationToItem(item, take, itemData, effectiveParams, modifiedParam)
    -- Current values from the item
    local currentPitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH")
    local currentVolume = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")

    -- Check if pan envelope exists (indicates randomized pan)
    local panEnv = reaper.GetTakeEnvelopeByName(take, "Pan")
    local currentPan = 0
    if panEnv then
        -- Get pan value from envelope (first point)
        local retval, time, value, shape, tension, selected = reaper.GetEnvelopePoint(panEnv, 0)
        if retval then
            currentPan = value
        end
    end

    -- Apply pitch randomization
    if modifiedParam == "pitch" or modifiedParam == nil then
        if effectiveParams.randomizePitch then
            -- Check if current pitch is different from original (indicating it was randomized)
            local isPitchRandomized = math.abs(currentPitch - itemData.originalPitch) > 0.001

            local randomPitch = itemData.originalPitch + Utils_Math.randomInRange(effectiveParams.pitchRange.min, effectiveParams.pitchRange.max)

            if effectiveParams.pitchMode == Constants.PITCH_MODES.STRETCH then
                -- Use time stretch (D_PLAYRATE)
                local playrate = Utils_Math.semitonesToPlayrate(randomPitch)
                reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", playrate)
                reaper.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 0)  -- Disable preserve pitch to allow pitch change
                -- Reset D_PITCH to 0 to avoid conflicts
                reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", 0)
            else
                -- Use standard pitch shift (D_PITCH)
                reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", randomPitch)
                -- Reset D_PLAYRATE to 1.0 to avoid conflicts
                reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", 1.0)
                reaper.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 0)
            end
        else
            -- Randomization disabled, return to original value
            if effectiveParams.pitchMode == Constants.PITCH_MODES.STRETCH then
                local playrate = Utils_Math.semitonesToPlayrate(itemData.originalPitch)
                reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", playrate)
                reaper.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 0)
                reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", 0)
            else
                reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", itemData.originalPitch)
                reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", 1.0)
                reaper.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 0)
            end
        end
    end

    -- Apply volume randomization
    if modifiedParam == "volume" or modifiedParam == nil then
        if effectiveParams.randomizeVolume then
            -- Check if current volume is different from original (indicating it was randomized)
            local isVolumeRandomized = math.abs(currentVolume - itemData.originalVolume) > 0.001

            if isVolumeRandomized then
                -- For now, apply new randomization (proportional logic would need old range)
                local randomVolume = itemData.originalVolume * 10^(Utils_Math.randomInRange(effectiveParams.volumeRange.min, effectiveParams.volumeRange.max) / 20)
                reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", randomVolume)
            else
                -- Generate new random value
                local randomVolume = itemData.originalVolume * 10^(Utils_Math.randomInRange(effectiveParams.volumeRange.min, effectiveParams.volumeRange.max) / 20)
                reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", randomVolume)
            end
        else
            -- Randomization disabled, return to original value
            reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", itemData.originalVolume)
        end
    end

    -- Apply pan randomization
    if modifiedParam == "pan" or modifiedParam == nil then
        if effectiveParams.randomizePan then
            local randomPan = itemData.originalPan - Utils_Math.randomInRange(effectiveParams.panRange.min, effectiveParams.panRange.max) / 100
            randomPan = math.max(-1, math.min(1, randomPan))

            -- The envelope should already exist from batch creation, just update values
            if panEnv then
                -- Update existing envelope (preserves all points, just changes values)
                globals.Items.updateTakePanEnvelope(take, randomPan)
            else
                -- If envelope doesn't exist (shouldn't happen with batch creation), try to create it
                globals.Items.createTakePanEnvelope(take, randomPan)
            end
        else
            -- Randomization disabled, clear pan envelope to return to original
            if panEnv then
                -- Clear all envelope points to effectively disable the envelope
                local numPoints = reaper.CountEnvelopePoints(panEnv)
                for i = numPoints - 1, 0, -1 do
                    reaper.DeleteEnvelopePointEx(panEnv, -1, i)
                end
                -- Set the take pan back to original value
                reaper.SetMediaItemTakeInfo_Value(take, "D_PAN", itemData.originalPan or 0)
            end
        end
    end
end

-- ============================================================================
-- CHANNEL ROUTING AND OPTIMIZATION
-- ============================================================================

-- Update container track routing for multi-channel configuration
-- @param containerTrack userdata: The container track to configure
-- @param channelMode number: The channel mode (from Constants.CHANNEL_MODES)
function Utils_REAPER.updateContainerRouting(containerTrack, channelMode)
    if not containerTrack then
        return
    end

    if channelMode == nil or channelMode == 0 then
        -- Default stereo mode
        reaper.SetMediaTrackInfo_Value(containerTrack, "I_NCHAN", 2)
    else
        local config = globals.Constants.CHANNEL_CONFIGS[channelMode]
        if config then
            -- Use totalChannels if defined, otherwise use channels
            local requiredChannels = config.totalChannels or config.channels
            reaper.SetMediaTrackInfo_Value(containerTrack, "I_NCHAN", requiredChannels)
        end
    end
end

-- Ensure parent tracks have enough channels for multi-channel routing
-- Recursively updates parent tracks up to the Master if necessary
-- @param childTrack userdata: The child track requiring channels
-- @param requiredChannels number: Minimum number of channels needed
function Utils_REAPER.ensureParentHasEnoughChannels(childTrack, requiredChannels)
    if not childTrack or not requiredChannels then
        return
    end

    -- REAPER constraint: channel counts must be even numbers
    -- Round up to next even number if odd
    if requiredChannels % 2 == 1 then
        requiredChannels = requiredChannels + 1
    end

    local parentTrack = reaper.GetParentTrack(childTrack)
    if parentTrack then
        local parentChannels = reaper.GetMediaTrackInfo_Value(parentTrack, "I_NCHAN")
        if parentChannels < requiredChannels then
            reaper.SetMediaTrackInfo_Value(parentTrack, "I_NCHAN", requiredChannels)
            -- Recursively update grand-parents if necessary
            Utils_REAPER.ensureParentHasEnoughChannels(parentTrack, requiredChannels)
        end
    else
        -- No parent track means we might be at a top-level track
        -- Check if we need to update the Master track
        local masterTrack = reaper.GetMasterTrack(0)
        if masterTrack then
            local masterChannels = reaper.GetMediaTrackInfo_Value(masterTrack, "I_NCHAN")
            -- Ensure Master has at least the required channels (minimum 2 for stereo)
            local neededChannels = math.max(2, requiredChannels)
            -- Apply even number constraint to master as well
            if neededChannels % 2 == 1 then
                neededChannels = neededChannels + 1
            end
            if masterChannels < neededChannels then
                reaper.SetMediaTrackInfo_Value(masterTrack, "I_NCHAN", neededChannels)
            end
        end
    end
end

-- Optimize the entire project's channel count by removing unused channels
function Utils_REAPER.optimizeProjectChannelCount()
    if not globals.groups or #globals.groups == 0 then
        return
    end

    reaper.Undo_BeginBlock()

    -- Calculate actual channel usage for the entire project
    local actualUsage = Utils_REAPER.calculateActualChannelUsage()

    -- Apply optimizations
    Utils_REAPER.applyChannelOptimizations(actualUsage)

    reaper.Undo_EndBlock("Optimize Project Channel Count", -1)
end

-- Calculate actual channel usage across the project
function Utils_REAPER.calculateActualChannelUsage()
    local usage = {
        containers = {},
        groups = {},
        master = 2  -- Minimum stereo
    }

    -- Analyze each container's actual routing requirements
    for _, group in ipairs(globals.groups) do
        local groupMaxChannels = 2

        for _, container in ipairs(group.containers) do
            if container.channelMode and container.channelMode > 0 then
                local config = globals.Constants.CHANNEL_CONFIGS[container.channelMode]
                if config then
                    local requiredChannels = config.channels

                    -- Apply REAPER even constraint
                    if requiredChannels % 2 == 1 then
                        requiredChannels = requiredChannels + 1
                    end

                    usage.containers[container.name] = {
                        required = requiredChannels,
                        logical = config.channels,
                        container = container,
                        group = group
                    }

                    groupMaxChannels = math.max(groupMaxChannels, requiredChannels)
                end
            end
        end

        usage.groups[group.name] = {
            required = groupMaxChannels,
            group = group
        }

        usage.master = math.max(usage.master, groupMaxChannels)
    end

    return usage
end

-- Apply channel optimizations based on calculated usage
function Utils_REAPER.applyChannelOptimizations(usage)
    local trackCount = reaper.CountTracks(0)

    -- Optimize container tracks
    for containerName, info in pairs(usage.containers) do
        local containerTrack = Utils_REAPER.findContainerTrackByName(containerName, info.group.name)
        if containerTrack then
            local currentChannels = reaper.GetMediaTrackInfo_Value(containerTrack, "I_NCHAN")
            if currentChannels > info.required then
                reaper.SetMediaTrackInfo_Value(containerTrack, "I_NCHAN", info.required)
            end
        end
    end

    -- Optimize group tracks
    for groupName, info in pairs(usage.groups) do
        local groupTrack = Utils_REAPER.findGroupTrackByName(groupName)
        if groupTrack then
            local currentChannels = reaper.GetMediaTrackInfo_Value(groupTrack, "I_NCHAN")
            if currentChannels > info.required then
                reaper.SetMediaTrackInfo_Value(groupTrack, "I_NCHAN", info.required)
            end
        end
    end

    -- Optimize master track
    local masterTrack = reaper.GetMasterTrack(0)
    if masterTrack then
        local currentChannels = reaper.GetMediaTrackInfo_Value(masterTrack, "I_NCHAN")
        if currentChannels > usage.master then
            reaper.SetMediaTrackInfo_Value(masterTrack, "I_NCHAN", usage.master)
        end
    end
end

-- Find container track by name and group name
function Utils_REAPER.findContainerTrackByName(containerName, groupName)
    local groupTrack, groupIdx = Utils_REAPER.findGroupByName(groupName)
    if not groupTrack then return nil end

    return Utils_REAPER.findContainerGroup(groupIdx, containerName)
end

-- Find group track by name
function Utils_REAPER.findGroupTrackByName(groupName)
    local groupTrack, _ = Utils_REAPER.findGroupByName(groupName)
    return groupTrack
end

-- ============================================================================
-- ROUTING CONFLICT DETECTION
-- ============================================================================

-- Detect routing conflicts between containers
-- @return table: conflict info or nil if no conflicts
function Utils_REAPER.detectRoutingConflicts()
    local channelUsage = {}  -- Track which channels are used for what
    local conflicts = {}
    local containers = {}  -- Store all containers with their routing

    -- Collect all containers with multi-channel routing
    for i, group in ipairs(globals.groups) do
        for j, container in ipairs(group.containers) do
            if container.channelMode and container.channelMode > 0 then
                local config = globals.Constants.CHANNEL_CONFIGS[container.channelMode]

                if config then
                    local activeConfig = config
                    if config.hasVariants then
                        activeConfig = config.variants[container.channelVariant or 0]
                        activeConfig.channels = config.channels  -- Copy channels count from parent config
                    end

                    table.insert(containers, {
                        group = group,
                        container = container,
                        config = activeConfig,
                        channels = config.channels,  -- Store the actual channel count
                        groupName = group.name,
                        containerName = container.name
                    })

                    -- Track channel usage
                    for idx, channelNum in ipairs(activeConfig.routing) do
                        local label = activeConfig.labels[idx]

                        if not channelUsage[channelNum] then
                            channelUsage[channelNum] = {}
                        end

                        -- Check for conflicts
                        local existingUsage = channelUsage[channelNum]
                        for _, usage in ipairs(existingUsage) do
                            if usage.label ~= label then
                                -- Conflict detected!
                                table.insert(conflicts, {
                                    channel = channelNum,
                                    container1 = usage.containerInfo,
                                    container2 = {
                                        group = group,
                                        container = container,
                                        groupName = group.name,
                                        containerName = container.name,
                                        label = label
                                    }
                                })
                            end
                        end

                        table.insert(channelUsage[channelNum], {
                            label = label,
                            containerInfo = {
                                group = group,
                                container = container,
                                groupName = group.name,
                                containerName = container.name,
                                label = label
                            }
                        })
                    end
                end
            end
        end
    end

    if #conflicts > 0 then
        return {conflicts = conflicts, containers = containers}
    end
    return nil
end

-- Suggest alternative routing to avoid conflicts
-- @param conflictInfo table: The conflict information
-- @return table: Suggested routing changes
function Utils_REAPER.suggestRoutingFix(conflictInfo)
    local suggestions = {}
    local usedChannels = {}

    -- First, mark all channels used by larger configurations
    for _, containerInfo in ipairs(conflictInfo.containers) do
        local config = containerInfo.config
        local channels = containerInfo.channels or config.channels or 2  -- Use stored channels or fallback
        if channels >= 5 then  -- Prioritize larger configs (5.0, 7.0)
            for _, channel in ipairs(config.routing) do
                usedChannels[channel] = true
            end
        end
    end

    -- Then find alternative routing for smaller configs
    for _, containerInfo in ipairs(conflictInfo.containers) do
        local config = containerInfo.config
        local channels = containerInfo.channels or config.channels or 2  -- Use stored channels or fallback

        if channels == 4 then  -- Quad needs rerouting
            local newRouting = {}
            local channelOffset = 0

            -- Find free channels
            for i = 1, channels do
                local originalChannel = config.routing[i]

                if i <= 2 then
                    -- Keep L/R on channels 1/2
                    newRouting[i] = originalChannel
                else
                    -- Find next free channel for surrounds
                    local newChannel = 5 + channelOffset
                    while usedChannels[newChannel] and newChannel <= 8 do
                        channelOffset = channelOffset + 1
                        newChannel = 5 + channelOffset
                    end

                    -- If we run out of channels in the 5-8 range, try higher
                    if newChannel > 8 then
                        newChannel = 9
                        while usedChannels[newChannel] and newChannel <= 16 do
                            newChannel = newChannel + 1
                        end
                    end

                    newRouting[i] = newChannel
                    usedChannels[newChannel] = true
                    channelOffset = channelOffset + 1
                end
            end

            -- Only suggest rerouting if it's different from the original
            local needsRerouting = false
            for i = 1, #config.routing do
                if config.routing[i] ~= newRouting[i] then
                    needsRerouting = true
                    break
                end
            end

            if needsRerouting then
                table.insert(suggestions, {
                    container = containerInfo.container,
                    containerName = containerInfo.containerName,
                    groupName = containerInfo.groupName,
                    originalRouting = config.routing,
                    newRouting = newRouting,
                    labels = config.labels,
                    reason = "Conflicts with 5.0/7.0 center and surround channel routing"
                })
            end
        end
    end

    return suggestions
end

-- ============================================================================
-- ITEM AREAS (WAVEFORM ZONES)
-- ============================================================================

-- Get areas for a specific item
-- @param itemKey string: The unique item key
-- @return table: Array of areas or empty table if none exist
function Utils_REAPER.getItemAreas(itemKey)
    if not itemKey or not globals.waveformAreas or not globals.waveformAreas[itemKey] then
        return {}
    end
    return globals.waveformAreas[itemKey]
end

-- Select a random area from an item, or return the full item if no areas exist
-- @param itemData table: The original item data
-- @return table: Modified item data with area-specific startOffset and length
function Utils_REAPER.selectRandomAreaOrFullItem(itemData)
    local areas = itemData.areas or {}

    if #areas == 0 then
        -- No areas defined, return original item
        return itemData
    end

    -- Select a random area
    local randomAreaIndex = math.random(1, #areas)
    local selectedArea = areas[randomAreaIndex]

    -- Create a copy of the item data with area-specific modifications
    local areaItemData = {}
    for k, v in pairs(itemData) do
        areaItemData[k] = v
    end

    -- Adjust startOffset and length to match the selected area
    -- Areas store positions in seconds relative to the audio file
    local areaStartTime = selectedArea.startPos
    local areaEndTime = selectedArea.endPos
    local areaLength = areaEndTime - areaStartTime

    -- Set the start offset to the area's start position
    areaItemData.startOffset = areaStartTime
    areaItemData.length = areaLength
    areaItemData.originalLength = itemData.length  -- Store original length for reference
    areaItemData.selectedArea = selectedArea  -- Store which area was selected

    return areaItemData
end

return Utils_REAPER
