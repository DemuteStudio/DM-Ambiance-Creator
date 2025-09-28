--[[
@version 1.5
@noindex
--]]

local Utils = {}
local globals = {}
local Constants = require("DM_Ambiance_Constants")

-- Initialize the module with global references from the main script
function Utils.initModule(g)
    if not g then
        error("Utils.initModule: globals parameter is required")
    end
    globals = g
end

-- Display a help marker "(?)" with a tooltip containing the provided description
function Utils.HelpMarker(desc)
    if not desc or desc == "" then
        error("Utils.HelpMarker: description parameter is required")
    end
    
    globals.imgui.SameLine(globals.ctx)
    globals.imgui.TextDisabled(globals.ctx, '(?)')
    if globals.imgui.BeginItemTooltip(globals.ctx) then
        globals.imgui.PushTextWrapPos(globals.ctx, globals.imgui.GetFontSize(globals.ctx) * Constants.UI.HELP_MARKER_TEXT_WRAP)
        globals.imgui.Text(globals.ctx, desc)
        globals.imgui.PopTextWrapPos(globals.ctx)
        globals.imgui.EndTooltip(globals.ctx)
    end
end

-- Search for a track group by its name and return the track and its index if found
-- @param name string: The name of the group to find
-- @return MediaTrack|nil, number: The track object and its index, or nil and -1 if not found
function Utils.findGroupByName(name)
    if not name or name == "" then
        return nil, -1
    end
    
    local trackCount = reaper.CountTracks(0)
    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local success, groupName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
            if success and groupName == name then
                return track, i
            end
        end
    end
    return nil, -1
end

-- Search for a container group by name within a parent group, considering folder depth
function Utils.findContainerGroup(parentGroupIdx, containerName)
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
function Utils.clearGroupItems(group)
    if not group then return false end
    local itemCount = reaper.GetTrackNumMediaItems(group)
    for i = itemCount-1, 0, -1 do
        local item = reaper.GetTrackMediaItem(group, i)
        reaper.DeleteTrackMediaItem(group, item)
    end
    return true
end

-- Helper function to get all containers in a group with their information
function Utils.getAllContainersInGroup(parentGroupIdx)
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
function Utils.fixGroupFolderStructure(parentGroupIdx)
    if not parentGroupIdx or parentGroupIdx < 0 then
        return false
    end

    -- Get fresh container list after any track insertions/deletions
    local containers = Utils.getAllContainersInGroup(parentGroupIdx)

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
function Utils.validateAndRepairGroupStructure(parentGroupIdx)
    if not parentGroupIdx or parentGroupIdx < 0 then
        return false
    end
    
    local containers = Utils.getAllContainersInGroup(parentGroupIdx)
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
        return Utils.fixGroupFolderStructure(parentGroupIdx)
    end
    
    return true
end

-- Clear items from a group within the time selection, preserving items outside the selection
-- @param containerGroup MediaTrack: The track containing items to clear
-- @param crossfadeMargin number: Crossfade margin in seconds (optional)
function Utils.clearGroupItemsInTimeSelection(containerGroup, crossfadeMargin)
    if not containerGroup then
        error("Utils.clearGroupItemsInTimeSelection: containerGroup parameter is required")
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

-- Reorganize REAPER tracks after group reordering via drag and drop
function Utils.reorganizeTracksAfterGroupReorder()
    
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    -- Get all current tracks with their group associations
    local tracksToStore = {}
    
    -- Map tracks to their groups and store all their data
    for groupIndex, group in ipairs(globals.groups) do
        
        local groupTrack, groupTrackIdx = Utils.findGroupByName(group.name)
        if groupTrack and groupTrackIdx >= 0 then
            -- Store the parent group track data
            tracksToStore[groupIndex] = {
                groupName = group.name,
                containers = {}
            }
            
            -- Get all container tracks in this group
            local containers = Utils.getAllContainersInGroup(groupTrackIdx)
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
        local groupTrack, groupTrackIdx = Utils.findGroupByName(group.name)
        if groupTrack then
            -- Add all tracks in this group to deletion list
            table.insert(tracksToDelete, groupTrack)
            local containers = Utils.getAllContainersInGroup(groupTrackIdx)
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
function Utils.reorganizeTracksAfterContainerMove(sourceGroupIndex, targetGroupIndex, containerName)
    -- If moving within the same group, no track reorganization needed
    if sourceGroupIndex == targetGroupIndex then
        return
    end
    
    -- For moves between different groups, we need to rebuild the entire track structure
    -- to maintain proper folder hierarchy. Use the same approach as group reordering.
    Utils.reorganizeTracksAfterGroupReorder()
end

-- Open the preset folder in the system file explorer
function Utils.openPresetsFolder(type, groupName)
    local path = globals.Presets.getPresetsPath(type, groupName)
    if reaper.GetOS():match("Win") then
        os.execute('start "" "' .. path .. '"')
    elseif reaper.GetOS():match("OSX") then
        os.execute('open "' .. path .. '"')
    else -- Linux
        os.execute('xdg-open "' .. path .. '"')
    end
end

-- Open any folder in the system file explorer
function Utils.openFolder(path)
    if not path or path == "" then
        return
    end
    local OS = reaper.GetOS()
    local command
    if OS:match("^Win") then
        command = 'explorer "'
    elseif OS:match("^macOS") or OS:match("^OSX") then
        command = 'open "'
    else -- Linux
        command = 'xdg-open "'
    end
    os.execute(command .. path .. '"')
end

-- Open a popup safely (prevents multiple flashes or duplicate popups)
function Utils.safeOpenPopup(popupName)
    -- Initialize activePopups if it doesn't exist
    if not globals.activePopups then
        globals.activePopups = {}
    end
    
    -- Only open if not already active and if we're in a valid ImGui context
    if not globals.activePopups[popupName] then
        local success = pcall(function()
            globals.imgui.OpenPopup(globals.ctx, popupName)
        end)
        
        if success then
            globals.activePopups[popupName] = { 
                active = true, 
                timeOpened = reaper.time_precise() 
            }
        end
    end
end

-- Close a popup safely and remove it from the active popups list
function Utils.safeClosePopup(popupName)
    -- Use pcall to prevent crashes
    pcall(function()
        globals.imgui.CloseCurrentPopup(globals.ctx)
    end)
    
    -- Clean up the popup tracking
    if globals.activePopups then
        globals.activePopups[popupName] = nil
    end
end

-- Check if the media directory is configured and accessible in the settings
function Utils.isMediaDirectoryConfigured()
    -- Ensure the Settings module is properly initialized
    if not globals.Settings then
        return false
    end
    
    local mediaDir = globals.Settings.getSetting("mediaItemDirectory")
    return mediaDir ~= nil and mediaDir ~= "" and globals.Settings.directoryExists(mediaDir)
end

-- Display a warning popup if the media directory is not configured
function Utils.showDirectoryWarningPopup(popupTitle)
    local ctx = globals.ctx
    local imgui = globals.imgui
    local title = popupTitle or "Warning: Media Directory Not Configured"
    
    -- Use safe popup management to avoid flashing issues
    Utils.safeOpenPopup(title)
    
    -- Use pcall to protect against errors in popup rendering
    local success = pcall(function()
        if imgui.BeginPopupModal(ctx, title, nil, imgui.WindowFlags_AlwaysAutoResize) then
            imgui.TextColored(ctx, 0xFF8000FF, "No media directory has been configured in the settings.")
            imgui.TextWrapped(ctx, "You need to configure a media directory before saving presets to ensure proper media file management.")
            
            imgui.Separator(ctx)
            
            if imgui.Button(ctx, "Configure Now", 150, 0) then
                -- Open the settings window
                globals.showSettingsWindow = true
                Utils.safeClosePopup(title)
                globals.showMediaDirWarning = false  -- Reset the state
            end
            
            imgui.SameLine(ctx)
            
            if imgui.Button(ctx, "Cancel", 120, 0) then
                Utils.safeClosePopup(title)
                globals.showMediaDirWarning = false  -- Reset the state
            end
            
            imgui.EndPopup(ctx)
        end
    end)
    
    -- If popup rendering fails, reset the warning flag
    if not success then
        globals.showMediaDirWarning = false
        if globals.activePopups then
            globals.activePopups[title] = nil
        end
    end
end

-- Check if a time selection exists in the project and update globals accordingly
function Utils.checkTimeSelection()
    local start, ending = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    if start ~= ending then
        globals.timeSelectionValid = true
        globals.startTime = start
        globals.endTime = ending
        globals.timeSelectionLength = ending - start
        return true
    else
        globals.timeSelectionValid = false
        return false
    end
end

-- Generate a random value between min and max
function Utils.randomInRange(min, max)
    return min + math.random() * (max - min)
end

-- Format a time value in seconds as HH:MM:SS
function Utils.formatTime(seconds)
    seconds = tonumber(seconds) or 0
    
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    
    return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

-- Create crossfades between two overlapping media items with the given fade shape
-- @param item1 MediaItem: First media item
-- @param item2 MediaItem: Second media item  
-- @param fadeShape number: Fade shape (optional, uses default if not provided)
-- @return boolean: true if crossfade was created, false otherwise
function Utils.createCrossfade(item1, item2, fadeShape)
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

-- Unpacks a 32-bit color into individual RGBA components (0-1)
-- @param color number|string: Color value to unpack
-- @return number, number, number, number: r, g, b, a values (0-1)
function Utils.unpackColor(color)
    -- Convert string to number if necessary
    if type(color) == "string" then
        color = tonumber(color)
    end
    
    -- Check that the color is a number
    if type(color) ~= "number" then
        -- Default value in case of error (opaque white)
        local defaultColor = Constants.COLORS.DEFAULT_WHITE
        local r = ((defaultColor >> 24) & 0xFF) / 255
        local g = ((defaultColor >> 16) & 0xFF) / 255
        local b = ((defaultColor >> 8) & 0xFF) / 255
        local a = (defaultColor & 0xFF) / 255
        return r, g, b, a
    end
    
    local r = ((color >> 24) & 0xFF) / 255
    local g = ((color >> 16) & 0xFF) / 255
    local b = ((color >> 8) & 0xFF) / 255
    local a = (color & 0xFF) / 255
    
    return r, g, b, a
end

-- Packs RGBA components (0-1) into a 32-bit color
-- @param r number: Red component (0-1)
-- @param g number: Green component (0-1)
-- @param b number: Blue component (0-1)
-- @param a number: Alpha component (0-1, optional, defaults to 1)
-- @return number: 32-bit color value
function Utils.packColor(r, g, b, a)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        error("Utils.packColor: r, g, b parameters must be numbers")
    end
    
    -- Clamp values to valid range
    r = math.max(0, math.min(1, r))
    g = math.max(0, math.min(1, g))
    b = math.max(0, math.min(1, b))
    a = math.max(0, math.min(1, a or 1))
    
    r = math.floor(r * 255)
    g = math.floor(g * 255)
    b = math.floor(b * 255)
    a = math.floor(a * 255)
    
    return (r << 24) | (g << 16) | (b << 8) | a
end

-- Utility function to brighten or darken a color
-- @param color number: Color value to modify
-- @param amount number: Amount to brighten (positive) or darken (negative)
-- @return number: Modified color value
function Utils.brightenColor(color, amount)
    if type(amount) ~= "number" then
        error("Utils.brightenColor: amount parameter must be a number")
    end
    
    local r, g, b, a = Utils.unpackColor(color)
    
    r = math.max(0, math.min(1, r + amount))
    g = math.max(0, math.min(1, g + amount))
    b = math.max(0, math.min(1, b + amount))
    
    return Utils.packColor(r, g, b, a)
end

-- Convert decibel value to linear volume factor
-- @param volumeDB number: Volume in decibels
-- @return number: Linear volume factor
function Utils.dbToLinear(volumeDB)
    if type(volumeDB) ~= "number" then
        error("Utils.dbToLinear: volumeDB parameter must be a number")
    end
    
    -- Special case for -inf dB (mute)
    if volumeDB <= Constants.AUDIO.VOLUME_RANGE_DB_MIN then
        return 0.0
    end
    
    return 10 ^ (volumeDB / 20)
end

-- Convert linear volume factor to decibel value  
-- @param linearVolume number: Linear volume factor
-- @return number: Volume in decibels
function Utils.linearToDb(linearVolume)
    if type(linearVolume) ~= "number" or linearVolume < 0 then
        error("Utils.linearToDb: linearVolume parameter must be a non-negative number")
    end
    
    -- Special case for mute
    if linearVolume <= 0 then
        return Constants.AUDIO.VOLUME_RANGE_DB_MIN
    end
    
    return 20 * (math.log(linearVolume) / math.log(10))
end

-- Convert normalized slider value (0-1) to dB with 0dB at center
-- @param normalizedValue number: Value from 0.0 to 1.0
-- @return number: Volume in dB
function Utils.normalizedToDbRelative(normalizedValue)
    if type(normalizedValue) ~= "number" or normalizedValue < 0 or normalizedValue > 1 then
        error("Utils.normalizedToDbRelative: normalizedValue must be between 0 and 1")
    end
    
    if normalizedValue < 0.5 then
        -- Left half: -144dB to 0dB with audio taper curve (convex, not concave)
        local ratio = normalizedValue / 0.5  -- 0 to 1 for left half
        
        -- Use audio taper curve for natural mixing console feel
        -- This provides better resolution in the mixing range (-40dB to 0dB)
        if ratio < 0.001 then
            -- Very close to zero, return minimum
            return Constants.AUDIO.VOLUME_RANGE_DB_MIN
        else
            -- Use exponential curve for natural audio taper
            -- This creates a convex curve that matches professional mixing consoles
            -- At ratio 0.5 (position 0.25), this gives approximately -20dB
            local dB = 60 * (math.log(ratio) / math.log(10))
            -- Clamp to minimum
            return math.max(dB, Constants.AUDIO.VOLUME_RANGE_DB_MIN)
        end
    else
        -- Right half: 0dB to +24dB (linear)
        local ratio = (normalizedValue - 0.5) / 0.5
        return Constants.AUDIO.VOLUME_RANGE_DB_MAX * ratio
    end
end

-- Convert dB value to normalized slider position (0-1)
-- @param volumeDB number: Volume in decibels
-- @return number: Normalized value from 0.0 to 1.0
function Utils.dbToNormalizedRelative(volumeDB)
    if type(volumeDB) ~= "number" then
        error("Utils.dbToNormalizedRelative: volumeDB must be a number")
    end
    
    if volumeDB <= Constants.AUDIO.VOLUME_RANGE_DB_MIN then
        return 0.0
    elseif volumeDB <= 0 then
        -- Map -144dB to 0dB → 0.0 to 0.5 with inverse audio taper curve
        -- Use the inverse of the exponential curve for consistency
        -- 10^(dB/60) gives us the ratio for our audio taper
        local ratio = 10^(volumeDB / 60)
        -- Clamp ratio to valid range [0, 1]
        ratio = math.max(0, math.min(1, ratio))
        return ratio * 0.5
    else
        -- Map 0dB to +24dB → 0.5 to 1.0
        local ratio = volumeDB / Constants.AUDIO.VOLUME_RANGE_DB_MAX
        return 0.5 + (ratio * 0.5)
    end
end

-- Set the volume of a container's track in Reaper
-- @param groupIndex number: Index of the group containing the container
-- @param containerIndex number: Index of the container within the group
-- @param volumeDB number: Volume in decibels
-- @return boolean: true if successful, false otherwise
function Utils.setContainerTrackVolume(groupIndex, containerIndex, volumeDB)
    if not groupIndex or groupIndex < 1 then
        error("Utils.setContainerTrackVolume: valid groupIndex is required")
    end
    
    if not containerIndex or containerIndex < 1 then
        error("Utils.setContainerTrackVolume: valid containerIndex is required")
    end
    
    if type(volumeDB) ~= "number" then
        error("Utils.setContainerTrackVolume: volumeDB must be a number")
    end
    
    -- Validate that the group and container exist
    if not globals.groups[groupIndex] or not globals.groups[groupIndex].containers[containerIndex] then
        return false
    end
    
    local group = globals.groups[groupIndex]
    local container = group.containers[containerIndex]
    
    -- Find the group track
    local groupTrack, groupTrackIdx = Utils.findGroupByName(group.name)
    if not groupTrack then
        return false
    end
    
    -- Find the container track within the group
    local containerTrack, containerTrackIdx = Utils.findContainerGroup(groupTrackIdx, container.name)
    if not containerTrack then
        return false
    end
    
    -- Convert dB to linear factor and apply to track
    local linearVolume = Utils.dbToLinear(volumeDB)
    reaper.SetMediaTrackInfo_Value(containerTrack, "D_VOL", linearVolume)
    
    -- Update arrange view to reflect changes
    reaper.UpdateArrange()
    
    return true
end

-- Set the volume of a specific channel track within a multichannel container
-- @param groupIndex number: Index of the group containing the container
-- @param containerIndex number: Index of the container within the group
-- @param channelIndex number: Index of the channel within the container (1-based)
-- @param volumeDB number: Volume in decibels
-- @return boolean: true if successful, false otherwise
function Utils.setChannelTrackVolume(groupIndex, containerIndex, channelIndex, volumeDB)
    if not groupIndex or groupIndex < 1 then
        error("Utils.setChannelTrackVolume: valid groupIndex is required")
    end
    
    if not containerIndex or containerIndex < 1 then
        error("Utils.setChannelTrackVolume: valid containerIndex is required")
    end
    
    if not channelIndex or channelIndex < 1 then
        error("Utils.setChannelTrackVolume: valid channelIndex is required")
    end
    
    if type(volumeDB) ~= "number" then
        error("Utils.setChannelTrackVolume: volumeDB must be a number")
    end
    
    -- Validate that the group and container exist
    if not globals.groups[groupIndex] or not globals.groups[groupIndex].containers[containerIndex] then
        return false
    end
    
    local group = globals.groups[groupIndex]
    local container = group.containers[containerIndex]
    
    -- Only apply if container is in multichannel mode
    if not container.channelMode or container.channelMode == 0 then
        return false
    end
    
    -- Find the group track
    local groupTrack, groupTrackIdx = Utils.findGroupByName(group.name)
    if not groupTrack then
        return false
    end
    
    -- Find the container track within the group
    local containerTrack, containerTrackIdx = Utils.findContainerGroup(groupTrackIdx, container.name)
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
                    local linearVolume = Utils.dbToLinear(volumeDB)
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
function Utils.getChannelTrackVolume(groupIndex, containerIndex, channelIndex)
    if not groupIndex or groupIndex < 1 or not containerIndex or containerIndex < 1 or not channelIndex or channelIndex < 1 then
        return nil
    end
    
    -- Validate that the group and container exist
    if not globals.groups[groupIndex] or not globals.groups[groupIndex].containers[containerIndex] then
        return nil
    end
    
    local group = globals.groups[groupIndex]
    local container = group.containers[containerIndex]
    
    -- Only apply if container is in multichannel mode
    if not container.channelMode or container.channelMode == 0 then
        return nil
    end
    
    -- Find the group track
    local groupTrack, groupTrackIdx = Utils.findGroupByName(group.name)
    if not groupTrack then
        return nil
    end
    
    -- Find the container track within the group
    local containerTrack, containerTrackIdx = Utils.findContainerGroup(groupTrackIdx, container.name)
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
                    return Utils.linearToDb(linearVolume)
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
function Utils.syncChannelVolumesFromTracks(groupIndex, containerIndex)
    if not groupIndex or groupIndex < 1 or not containerIndex or containerIndex < 1 then
        return
    end
    
    -- Validate that the group and container exist
    if not globals.groups[groupIndex] or not globals.groups[groupIndex].containers[containerIndex] then
        return
    end
    
    local container = globals.groups[groupIndex].containers[containerIndex]
    
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
        local volumeDB = Utils.getChannelTrackVolume(groupIndex, containerIndex, i)
        if volumeDB then
            container.channelVolumes[i] = volumeDB
        end
    end
end

-- Get the current volume of a container's track from Reaper
-- @param groupIndex number: Index of the group containing the container
-- @param containerIndex number: Index of the container within the group
-- @return number|nil: Volume in decibels, or nil if track not found
function Utils.getContainerTrackVolume(groupIndex, containerIndex)
    if not groupIndex or groupIndex < 1 or not containerIndex or containerIndex < 1 then
        return nil
    end
    
    -- Validate that the group and container exist
    if not globals.groups[groupIndex] or not globals.groups[groupIndex].containers[containerIndex] then
        return nil
    end
    
    local group = globals.groups[groupIndex]
    local container = group.containers[containerIndex]
    
    -- Find the group track
    local groupTrack, groupTrackIdx = Utils.findGroupByName(group.name)
    if not groupTrack then
        return nil
    end
    
    -- Find the container track within the group
    local containerTrack, containerTrackIdx = Utils.findContainerGroup(groupTrackIdx, container.name)
    if not containerTrack then
        return nil
    end
    
    -- Get linear volume and convert to dB
    local linearVolume = reaper.GetMediaTrackInfo_Value(containerTrack, "D_VOL")
    return Utils.linearToDb(linearVolume)
end

-- Set the volume of a group's track in Reaper
-- @param groupIndex number: Index of the group
-- @param volumeDB number: Volume in decibels
-- @return boolean: true if successful, false otherwise
function Utils.setGroupTrackVolume(groupIndex, volumeDB)
    if not groupIndex or groupIndex < 1 then
        error("Utils.setGroupTrackVolume: valid groupIndex is required")
    end
    
    if type(volumeDB) ~= "number" then
        error("Utils.setGroupTrackVolume: volumeDB must be a number")
    end
    
    -- Validate that the group exists
    if not globals.groups[groupIndex] then
        return false
    end
    
    local group = globals.groups[groupIndex]
    
    -- Find the group track
    local groupTrack, groupTrackIdx = Utils.findGroupByName(group.name)
    if not groupTrack then
        return false
    end
    
    -- Convert dB to linear factor and apply to track
    local linearVolume = Utils.dbToLinear(volumeDB)
    reaper.SetMediaTrackInfo_Value(groupTrack, "D_VOL", linearVolume)
    
    -- Update arrange view to reflect changes
    reaper.UpdateArrange()
    
    return true
end

-- Get the current volume of a group's track from Reaper
-- @param groupIndex number: Index of the group
-- @return number|nil: Volume in decibels, or nil if track not found
function Utils.getGroupTrackVolume(groupIndex)
    if not groupIndex or groupIndex < 1 then
        return nil
    end
    
    -- Validate that the group exists
    if not globals.groups[groupIndex] then
        return nil
    end
    
    local group = globals.groups[groupIndex]
    
    -- Find the group track
    local groupTrack, groupTrackIdx = Utils.findGroupByName(group.name)
    if not groupTrack then
        return nil
    end
    
    -- Get linear volume and convert to dB
    local linearVolume = reaper.GetMediaTrackInfo_Value(groupTrack, "D_VOL")
    return Utils.linearToDb(linearVolume)
end

-- Sync container volume from Reaper track to container data
-- @param groupIndex number: Index of the group containing the container
-- @param containerIndex number: Index of the container within the group
function Utils.syncContainerVolumeFromTrack(groupIndex, containerIndex)
    local volumeDB = Utils.getContainerTrackVolume(groupIndex, containerIndex)
    if volumeDB then
        globals.groups[groupIndex].containers[containerIndex].trackVolume = volumeDB
    end
end

-- Sync group volume from Reaper track to group data
-- @param groupIndex number: Index of the group
function Utils.syncGroupVolumeFromTrack(groupIndex)
    local volumeDB = Utils.getGroupTrackVolume(groupIndex)
    if volumeDB then
        globals.groups[groupIndex].trackVolume = volumeDB
    end
end

-- Initialize trackVolume property for all existing containers and groups that don't have it
-- This ensures backward compatibility with existing projects
function Utils.initializeContainerVolumes()
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

-- Queue system for deferred fade applications to avoid ImGui conflicts
local fadeUpdateQueue = {}

-- Add a fade update request to the queue
-- @param groupIndex number: Index of the group
-- @param containerIndex number: Index of the container (nil for group-wide update)
-- @param modifiedFade string: Which fade was modified ("fadeIn", "fadeOut", or nil for both)
function Utils.queueFadeUpdate(groupIndex, containerIndex, modifiedFade)
    local key = groupIndex .. "_" .. (containerIndex or "all")
    fadeUpdateQueue[key] = {
        groupIndex = groupIndex,
        containerIndex = containerIndex,
        modifiedFade = modifiedFade,
        timestamp = os.clock()
    }
end

-- Process all queued fade updates (call this after ImGui frame)
function Utils.processQueuedFadeUpdates()
    for key, update in pairs(fadeUpdateQueue) do
        if update.containerIndex then
            Utils.applyFadeSettingsToContainerItems(update.groupIndex, update.containerIndex, update.modifiedFade)
        else
            Utils.applyFadeSettingsToGroupItems(update.groupIndex, update.modifiedFade)
        end
    end
    -- Clear the queue
    fadeUpdateQueue = {}
end

-- Apply fade settings to all media items in a specific container in real-time
-- @param groupIndex number: Index of the group
-- @param containerIndex number: Index of the container
-- @param modifiedFade string: Which fade was modified ("fadeIn", "fadeOut", or nil for both)
function Utils.applyFadeSettingsToContainerItems(groupIndex, containerIndex, modifiedFade)
    if not globals.groups or not globals.groups[groupIndex] then
        return
    end
    
    local group = globals.groups[groupIndex]
    if not group.containers or not group.containers[containerIndex] then
        return
    end
    
    local container = group.containers[containerIndex]
    
    -- Find the group track first
    local groupTrack, groupTrackIdx = Utils.findGroupByName(group.name)
    if not groupTrack or not groupTrackIdx then
        return -- Group track not found
    end
    
    -- Find the container track within the group
    local containerTrack, containerTrackIdx = Utils.findContainerGroup(groupTrackIdx, container.name)
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
-- @param groupIndex number: Index of the group
-- @param modifiedFade string: Which fade was modified ("fadeIn", "fadeOut", or nil for both)
function Utils.applyFadeSettingsToGroupItems(groupIndex, modifiedFade)
    if not globals.groups or not globals.groups[groupIndex] then
        return
    end
    
    local group = globals.groups[groupIndex]
    if not group.containers then
        return
    end
    
    -- Apply fade settings to all containers in this group
    for containerIndex, container in ipairs(group.containers) do
        Utils.applyFadeSettingsToContainerItems(groupIndex, containerIndex, modifiedFade)
    end
end

-- Apply randomization settings to all media items in a specific container in real-time
-- @param groupIndex number: Index of the group
-- @param containerIndex number: Index of the container
-- @param modifiedParam string: Which parameter was modified ("pitch", "volume", "pan", or nil for all)
function Utils.applyRandomizationSettingsToContainerItems(groupIndex, containerIndex, modifiedParam)
    if not globals.groups or not globals.groups[groupIndex] then
        return
    end
    
    local group = globals.groups[groupIndex]
    if not group.containers or not group.containers[containerIndex] then
        return
    end
    
    local container = group.containers[containerIndex]
    local effectiveParams = globals.Structures.getEffectiveContainerParams(group, container)
    
    -- Find the container track
    local groupTrack, groupTrackIdx = Utils.findGroupByName(group.name)
    if not groupTrack then
        return
    end
    
    local containerTrack, containerTrackIdx = Utils.findContainerGroup(groupTrackIdx, container.name)
    if not containerTrack then
        return
    end
    
    local itemCount = reaper.GetTrackNumMediaItems(containerTrack)
    if itemCount == 0 then
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
        
        -- Select ALL items in the container
        reaper.SelectAllMediaItems(0, false)
        local allContainerItems = {}
        for i = 0, itemCount - 1 do
            local item = reaper.GetTrackMediaItem(containerTrack, i)
            if item then
                reaper.SetMediaItemSelected(item, true)
                allContainerItems[i + 1] = item
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
    
    -- Now apply individual randomization values
    for i = 0, itemCount - 1 do
        local item = reaper.GetTrackMediaItem(containerTrack, i)
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
                    Utils.applyRandomizationToItem(item, take, itemData, effectiveParams, modifiedParam)
                end
            end
        end
    end
    
    reaper.Undo_EndBlock("Apply Randomization Settings to Container Items", -1)
    reaper.UpdateArrange()
end

-- Apply randomization settings to all containers in a group in real-time
-- @param groupIndex number: Index of the group
-- @param modifiedParam string: Which parameter was modified ("pitch", "volume", "pan", or nil for all)
function Utils.applyRandomizationSettingsToGroupItems(groupIndex, modifiedParam)
    if not globals.groups or not globals.groups[groupIndex] then
        return
    end
    
    local group = globals.groups[groupIndex]
    if not group.containers then
        return
    end
    
    -- Apply randomization settings to all containers in this group
    for containerIndex, container in ipairs(group.containers) do
        Utils.applyRandomizationSettingsToContainerItems(groupIndex, containerIndex, modifiedParam)
    end
end

-- Apply randomization to a single item based on current and previous settings
-- @param item MediaItem: The media item
-- @param take MediaItemTake: The media item take
-- @param itemData table: Original item data with originalPitch, originalVolume, originalPan
-- @param effectiveParams table: Current effective parameters
-- @param modifiedParam string: Which parameter was modified
function Utils.applyRandomizationToItem(item, take, itemData, effectiveParams, modifiedParam)
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
            
            local randomPitch = itemData.originalPitch + Utils.randomInRange(effectiveParams.pitchRange.min, effectiveParams.pitchRange.max)
            reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", randomPitch)
        else
            -- Randomization disabled, return to original value
            reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", itemData.originalPitch)
        end
    end
    
    -- Apply volume randomization
    if modifiedParam == "volume" or modifiedParam == nil then
        if effectiveParams.randomizeVolume then
            -- Check if current volume is different from original (indicating it was randomized)
            local isVolumeRandomized = math.abs(currentVolume - itemData.originalVolume) > 0.001
            
            if isVolumeRandomized then
                -- For now, apply new randomization (proportional logic would need old range)
                local randomVolume = itemData.originalVolume * 10^(Utils.randomInRange(effectiveParams.volumeRange.min, effectiveParams.volumeRange.max) / 20)
                reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", randomVolume)
            else
                -- Generate new random value
                local randomVolume = itemData.originalVolume * 10^(Utils.randomInRange(effectiveParams.volumeRange.min, effectiveParams.volumeRange.max) / 20)
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
            local randomPan = itemData.originalPan + Utils.randomInRange(effectiveParams.panRange.min, effectiveParams.panRange.max) / 100
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

-- Calculate proportional value when randomization range changes
-- @param currentValue number: Current value on the item
-- @param oldMin number: Previous minimum range value
-- @param oldMax number: Previous maximum range value  
-- @param newMin number: New minimum range value
-- @param newMax number: New maximum range value
-- @param defaultValue number: Default value (used when current value equals default)
-- @return number: New proportional value
function Utils.calculateProportionalValue(currentValue, oldMin, oldMax, newMin, newMax, defaultValue)
    -- If current value is at default, keep it at default
    if math.abs(currentValue - defaultValue) < 0.001 then
        return defaultValue
    end
    
    -- Calculate the relative position in the old range
    local oldRange = oldMax - oldMin
    if oldRange == 0 then
        return defaultValue -- Avoid division by zero
    end
    
    local relativePosition = (currentValue - defaultValue) / oldRange
    
    -- Apply this relative position to the new range
    local newRange = newMax - newMin
    local newValue = defaultValue + (relativePosition * newRange)
    
    return newValue
end

-- Queue system for randomization parameter updates
local randomizationUpdateQueue = {}

-- Add a randomization update request to the queue
-- @param groupIndex number: Index of the group
-- @param containerIndex number: Index of the container (nil for group-wide update)
-- @param modifiedParam string: Which parameter was modified ("pitch", "volume", "pan", or nil for all)
function Utils.queueRandomizationUpdate(groupIndex, containerIndex, modifiedParam)
    local key = groupIndex .. "_" .. (containerIndex or "all") .. "_randomization"
    randomizationUpdateQueue[key] = {
        groupIndex = groupIndex,
        containerIndex = containerIndex,
        modifiedParam = modifiedParam,
        timestamp = os.clock()
    }
end

-- Process all queued randomization updates (call this after ImGui frame)
function Utils.processQueuedRandomizationUpdates()
    for key, update in pairs(randomizationUpdateQueue) do
        if update.containerIndex then
            Utils.applyRandomizationSettingsToContainerItems(update.groupIndex, update.containerIndex, update.modifiedParam)
        else
            Utils.applyRandomizationSettingsToGroupItems(update.groupIndex, update.modifiedParam)
        end
    end
    -- Clear the queue
    randomizationUpdateQueue = {}
end

-- Update container track routing for multi-channel configuration
-- @param containerTrack userdata: The container track to configure
-- @param channelMode number: The channel mode (from Constants.CHANNEL_MODES)
function Utils.updateContainerRouting(containerTrack, channelMode)
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
function Utils.ensureParentHasEnoughChannels(childTrack, requiredChannels)
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
            Utils.ensureParentHasEnoughChannels(parentTrack, requiredChannels)
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

-- ===================================================================
-- GLOBAL CHANNEL OPTIMIZATION
-- ===================================================================

-- Optimize the entire project's channel count by removing unused channels
function Utils.optimizeProjectChannelCount()
    if not globals.groups or #globals.groups == 0 then
        return
    end

    -- reaper.ShowConsoleMsg("INFO: Starting global channel optimization...\n")
    reaper.Undo_BeginBlock()

    -- Calculate actual channel usage for the entire project
    local actualUsage = Utils.calculateActualChannelUsage()

    -- Apply optimizations
    Utils.applyChannelOptimizations(actualUsage)

    reaper.Undo_EndBlock("Optimize Project Channel Count", -1)
    -- reaper.ShowConsoleMsg("INFO: Global channel optimization completed.\n")
end

-- Calculate actual channel usage across the project
function Utils.calculateActualChannelUsage()
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
function Utils.applyChannelOptimizations(usage)
    local trackCount = reaper.CountTracks(0)

    -- Optimize container tracks
    for containerName, info in pairs(usage.containers) do
        local containerTrack = Utils.findContainerTrackByName(containerName, info.group.name)
        if containerTrack then
            local currentChannels = reaper.GetMediaTrackInfo_Value(containerTrack, "I_NCHAN")
            if currentChannels > info.required then
                -- reaper.ShowConsoleMsg(string.format("INFO: Optimizing container '%s': %d → %d channels\n",
                --     containerName, currentChannels, info.required))
                reaper.SetMediaTrackInfo_Value(containerTrack, "I_NCHAN", info.required)
            end
        end
    end

    -- Optimize group tracks
    for groupName, info in pairs(usage.groups) do
        local groupTrack = Utils.findGroupTrackByName(groupName)
        if groupTrack then
            local currentChannels = reaper.GetMediaTrackInfo_Value(groupTrack, "I_NCHAN")
            if currentChannels > info.required then
                -- reaper.ShowConsoleMsg(string.format("INFO: Optimizing group '%s': %d → %d channels\n",
                --     groupName, currentChannels, info.required))
                reaper.SetMediaTrackInfo_Value(groupTrack, "I_NCHAN", info.required)
            end
        end
    end

    -- Optimize master track
    local masterTrack = reaper.GetMasterTrack(0)
    if masterTrack then
        local currentChannels = reaper.GetMediaTrackInfo_Value(masterTrack, "I_NCHAN")
        if currentChannels > usage.master then
            -- reaper.ShowConsoleMsg(string.format("INFO: Optimizing master track: %d → %d channels\n",
            --     currentChannels, usage.master))
            reaper.SetMediaTrackInfo_Value(masterTrack, "I_NCHAN", usage.master)
        end
    end
end

-- Find container track by name and group name
function Utils.findContainerTrackByName(containerName, groupName)
    local groupTrack, groupIdx = Utils.findGroupByName(groupName)
    if not groupTrack then return nil end

    return Utils.findContainerGroup(groupIdx, containerName)
end

-- Find group track by name
function Utils.findGroupTrackByName(groupName)
    local groupTrack, _ = Utils.findGroupByName(groupName)
    return groupTrack
end

-- Detect routing conflicts between containers
-- @return table: conflict info or nil if no conflicts
function Utils.detectRoutingConflicts()
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
function Utils.suggestRoutingFix(conflictInfo)
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

-- Generate a unique itemKey for identifying items and their areas
-- @param groupIndex number: The group index (1-based)
-- @param containerIndex number: The container index (1-based)
-- @param itemIndex number: The item index (1-based)
-- @return string: The unique item key
function Utils.generateItemKey(groupIndex, containerIndex, itemIndex)
    return string.format("g%d_c%d_i%d", groupIndex, containerIndex, itemIndex)
end

-- Get areas for a specific item
-- @param itemKey string: The unique item key
-- @return table: Array of areas or empty table if none exist
function Utils.getItemAreas(itemKey)
    if not itemKey or not globals.waveformAreas or not globals.waveformAreas[itemKey] then
        return {}
    end
    return globals.waveformAreas[itemKey]
end

-- Select a random area from an item, or return the full item if no areas exist
-- @param itemData table: The original item data
-- @return table: Modified item data with area-specific startOffset and length
function Utils.selectRandomAreaOrFullItem(itemData)
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

return Utils