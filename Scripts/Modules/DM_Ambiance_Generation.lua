--[[
@version 1.5
@noindex
--]]

local Generation = {}

local globals = {}

local Utils = require("DM_Ambiance_Utils")
local Items = require("DM_Ambiance_Items")

function Generation.initModule(g)
    globals = g
end

-- Function to delete existing groups with same names before generating
function Generation.deleteExistingGroups()
  -- Create a map of group names we're about to create
  local groupNames = {}
  for _, group in ipairs(globals.groups) do
      groupNames[group.name] = true
  end
  
  -- Find all tracks with matching names and their children
  local groupsToDelete = {}
  local groupCount = reaper.CountTracks(0)
  local i = 0
  while i < groupCount do
      local group = reaper.GetTrack(0, i)
      local _, name = reaper.GetSetMediaTrackInfo_String(group, "P_NAME", "", false)
      if groupNames[name] then
          -- Check if this is a folder track
          local depth = reaper.GetMediaTrackInfo_Value(group, "I_FOLDERDEPTH")
          -- Add this track to the delete list
          table.insert(groupsToDelete, group)
          -- If this is a folder track, also find all its children
          if depth == 1 then
              local j = i + 1
              local folderDepth = 1 -- Start with depth 1 (we're inside one folder)
              while j < groupCount and folderDepth > 0 do
                  local childGroup = reaper.GetTrack(0, j)
                  table.insert(groupsToDelete, childGroup)
                  -- Update folder depth based on this group's folder status
                  local childDepth = reaper.GetMediaTrackInfo_Value(childGroup, "I_FOLDERDEPTH")
                  folderDepth = folderDepth + childDepth
                  j = j + 1
              end
              -- Skip the children we've already processed
              i = j - 1
          end
      end
      i = i + 1
  end
  
  -- Delete tracks in reverse order to avoid index issues
  for i = #groupsToDelete, 1, -1 do
      reaper.DeleteTrack(groupsToDelete[i])
  end
end

-- Create multi-channel track structure for a container
-- @param containerTrack userdata: The container track that will become a folder
-- @param container table: The container configuration
-- @param isLastInGroup boolean: Whether this is the last container in the group (optional)
-- @return table: Array of channel tracks (including the container if in default mode)
function Generation.createMultiChannelTracks(containerTrack, container, isLastInGroup)
    if not container.channelMode or container.channelMode == 0 then
        -- Default mode, no child tracks, generate on container
        return {containerTrack}
    end

    local config = globals.Constants.CHANNEL_CONFIGS[container.channelMode]
    if not config or config.channels == 0 then
        return {containerTrack}
    end

    -- Get the active configuration (with variant if applicable)
    local activeConfig = config
    if config.hasVariants then
        activeConfig = config.variants[container.channelVariant or 0]
        -- Debug: print what we got
        if activeConfig then
            reaper.ShowConsoleMsg(string.format("DEBUG: Using variant %d for %s - routing: %s\n",
                container.channelVariant or 0,
                container.name or "unknown",
                table.concat(activeConfig.routing or {}, ", ")))
        else
            reaper.ShowConsoleMsg(string.format("DEBUG: No variant found for %s, variant: %d\n",
                container.name or "unknown",
                container.channelVariant or 0))
        end
    end

    local channelTracks = {}

    -- Update container track to handle multi-channel
    local requiredChannels = config.totalChannels or config.channels
    -- If using custom routing, ensure we have enough channels for the highest channel
    if container.customRouting then
        requiredChannels = math.max(requiredChannels, math.max(table.unpack(container.customRouting)))
    end

    -- REAPER constraint: channel counts must be even numbers
    -- Round up to next even number if odd
    if requiredChannels % 2 == 1 then
        requiredChannels = requiredChannels + 1
    end

    -- Set container track channel count
    reaper.SetMediaTrackInfo_Value(containerTrack, "I_NCHAN", requiredChannels)

    -- Ensure parent tracks have enough channels for proper routing
    globals.Utils.ensureParentHasEnoughChannels(containerTrack, requiredChannels)

    -- Use the passed parameter or fallback to container property
    if isLastInGroup == nil then
        isLastInGroup = container.isLastInGroup or false
    end

    -- Container track becomes a folder
    reaper.SetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH", 1)

    -- Get container track index
    local containerIdx = reaper.GetMediaTrackInfo_Value(containerTrack, "IP_TRACKNUMBER") - 1

    -- Create all child tracks first, then configure them
    -- This ensures the indices remain stable during configuration

    -- Create child tracks in REVERSE order
    -- Always insert at containerIdx + 1, which pushes previous tracks down
    -- This results in the correct final order
    for i = config.channels, 1, -1 do
        -- Always insert immediately after the container
        -- This ensures they're children
        reaper.InsertTrackAtIndex(containerIdx + 1, false)
    end

    -- Now configure each track
    for i = 1, config.channels do
        -- Get the track at the correct position (container + i)
        local channelTrack = reaper.GetTrack(0, containerIdx + i)

        -- Name the track
        local channelLabel = activeConfig.labels[i]
        local trackName = container.name .. " - " .. channelLabel
        reaper.GetSetMediaTrackInfo_String(channelTrack, "P_NAME", trackName, true)

        -- Set track to mono (1 channel)
        reaper.SetMediaTrackInfo_Value(channelTrack, "I_NCHAN", 1)

        -- Disable master send
        reaper.SetMediaTrackInfo_Value(channelTrack, "B_MAINSEND", 0)

        -- Create send to parent track
        local sendIdx = reaper.CreateTrackSend(channelTrack, containerTrack)
        if sendIdx >= 0 then
            -- Route to single channel (0-based)
            -- Use custom routing if available (for conflict resolution)

            -- Validate and clean customRouting if corrupted
            if container.customRouting then
                local expectedChannels = config.channels
                local customChannels = #container.customRouting

                -- Check if customRouting has the right number of entries
                if customChannels ~= expectedChannels then
                    reaper.ShowConsoleMsg(string.format("WARNING: Corrupted customRouting detected for %s - expected %d channels, got %d. Clearing customRouting.\n",
                        container.name or "unknown", expectedChannels, customChannels))
                    container.customRouting = nil
                end

                -- Check if customRouting has missing or invalid channels
                if container.customRouting then
                    local hasInvalidEntries = false
                    for j = 1, expectedChannels do
                        if not container.customRouting[j] or container.customRouting[j] <= 0 then
                            hasInvalidEntries = true
                            break
                        end
                    end

                    if hasInvalidEntries then
                        reaper.ShowConsoleMsg(string.format("WARNING: Invalid entries in customRouting for %s. Clearing customRouting.\n",
                            container.name or "unknown"))
                        container.customRouting = nil
                    end
                end
            end

            -- Debug: check both routing sources (only for first track to avoid spam)
            if i == 1 then
                if container.customRouting then
                    reaper.ShowConsoleMsg(string.format("DEBUG: Found customRouting: %s\n",
                        table.concat(container.customRouting, ", ")))
                else
                    reaper.ShowConsoleMsg("DEBUG: No customRouting found\n")
                end
                if activeConfig.routing then
                    reaper.ShowConsoleMsg(string.format("DEBUG: activeConfig.routing: %s\n",
                        table.concat(activeConfig.routing, ", ")))
                else
                    reaper.ShowConsoleMsg("DEBUG: No activeConfig.routing found\n")
                end
            end

            local routing = container.customRouting or activeConfig.routing
            local destChannel = 0 -- Default to channel 1 (0-based)

            -- Debug: print routing info
            reaper.ShowConsoleMsg(string.format("DEBUG: Track %d (%s): routing table = %s\n",
                i, channelLabel,
                routing and table.concat(routing, ", ") or "nil"))

            if routing and routing[i] then
                destChannel = routing[i] - 1
                reaper.ShowConsoleMsg(string.format("DEBUG: Track %d (%s): routing[%d] = %d -> destChannel = %d\n",
                    i, channelLabel, i, routing[i], destChannel))
            else
                -- Fallback: use channel index as destination
                destChannel = i - 1
                reaper.ShowConsoleMsg(string.format("DEBUG: Track %d (%s): No routing entry, using fallback destChannel = %d\n",
                    i, channelLabel, destChannel))
            end

            -- For mono to mono routing in Reaper:
            -- Source: 1024 = mono mode (bit 10 set, channel 1)
            local srcChannels = 1024

            -- Destination: 1024 + channel number for mono routing
            local dstChannels = 1024 + destChannel

            reaper.ShowConsoleMsg(string.format("DEBUG: Track %d (%s): Final send -> channel %d (REAPER: %d)\n",
                i, channelLabel, destChannel + 1, dstChannels))

            reaper.SetTrackSendInfo_Value(channelTrack, 0, sendIdx, "I_SRCCHAN", srcChannels)
            reaper.SetTrackSendInfo_Value(channelTrack, 0, sendIdx, "I_DSTCHAN", dstChannels)
            reaper.SetTrackSendInfo_Value(channelTrack, 0, sendIdx, "D_VOL", 1.0)  -- Unity gain
        end

        -- Apply channel-specific volume
        if container.channelVolumes and container.channelVolumes[i] then
            local linearVol = globals.Utils.dbToLinear(container.channelVolumes[i])
            reaper.SetMediaTrackInfo_Value(channelTrack, "D_VOL", linearVol)
        end

        -- Set folder depth (last track closes folder)
        if i == config.channels then
            reaper.SetMediaTrackInfo_Value(channelTrack, "I_FOLDERDEPTH", -1)
        else
            reaper.SetMediaTrackInfo_Value(channelTrack, "I_FOLDERDEPTH", 0)
        end

        table.insert(channelTracks, channelTrack)

        -- Verify track was created correctly
        local parent = reaper.GetParentTrack(channelTrack)
        if parent ~= containerTrack then
            -- Force proper folder structure by reapplying folder depth
            -- This happens if the tracks are not properly nested
            reaper.SetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH", 1)
            if i == config.channels then
                reaper.SetMediaTrackInfo_Value(channelTrack, "I_FOLDERDEPTH", -1)
            else
                reaper.SetMediaTrackInfo_Value(channelTrack, "I_FOLDERDEPTH", 0)
            end
        end
    end

    -- Force update to ensure proper folder structure
    reaper.UpdateArrange()
    reaper.TrackList_AdjustWindows(false)

    -- Additional refresh to ensure hierarchy is visible
    reaper.Main_OnCommand(40031, 0) -- View: Zoom out project
    reaper.Main_OnCommand(40295, 0) -- View: Zoom to project

    -- Store GUIDs for future reference
    Generation.storeTrackGUIDs(container, containerTrack, channelTracks)
    
    return channelTracks
end

-- Get existing channel tracks for a container
-- @param containerTrack userdata: The container track
-- @return table: Array of tracks (channel tracks if multi-channel, or just the container)
function Generation.getExistingChannelTracks(containerTrack)
    local tracks = {}
    local containerIdx = reaper.GetMediaTrackInfo_Value(containerTrack, "IP_TRACKNUMBER") - 1
    local folderDepth = reaper.GetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH")

    if folderDepth == 1 then
        -- Container is a folder, get ONLY direct children (not sub-folders)
        local i = containerIdx + 1
        local depth = 1
        local currentLevel = 1  -- Track nesting level

        while i < reaper.CountTracks(0) and depth > 0 do
            local track = reaper.GetTrack(0, i)
            local childDepth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")

            -- Only add direct children (at level 1)
            if currentLevel == 1 then
                table.insert(tracks, track)
            end

            -- Update depth tracking
            depth = depth + childDepth

            -- Update level for next track
            if childDepth == 1 then
                currentLevel = currentLevel + 1  -- Entering a sub-folder
            elseif childDepth == -1 then
                currentLevel = currentLevel - 1  -- Exiting a folder
            end

            i = i + 1
        end
    else
        -- Single track (default mode)
        table.insert(tracks, containerTrack)
    end

    return tracks
end

-- Get track GUID
-- @param track userdata: The track
-- @return string: The track GUID
function Generation.getTrackGUID(track)
    if not track then return nil end
    return reaper.GetTrackGUID(track)
end

-- Find track by GUID
-- @param guid string: The track GUID
-- @return userdata: The track or nil if not found
function Generation.findTrackByGUID(guid)
    if not guid then return nil end
    
    local trackCount = reaper.CountTracks(0)
    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        if reaper.GetTrackGUID(track) == guid then
            return track
        end
    end
    return nil
end

-- Store track GUIDs in container structure
-- @param container table: The container
-- @param containerTrack userdata: The container track
-- @param channelTracks table: Array of channel tracks
function Generation.storeTrackGUIDs(container, containerTrack, channelTracks)
    -- Store container track GUID
    container.trackGUID = Generation.getTrackGUID(containerTrack)
    
    -- Store channel track GUIDs
    container.channelTrackGUIDs = {}
    for _, track in ipairs(channelTracks) do
        table.insert(container.channelTrackGUIDs, Generation.getTrackGUID(track))
    end
end

-- Find existing tracks by stored GUIDs
-- @param container table: The container with stored GUIDs
-- @return containerTrack, channelTracks: The found tracks or nil
function Generation.findTracksByGUIDs(container)
    if not container.trackGUID then
        return nil, {}
    end
    
    -- Find container track
    local containerTrack = Generation.findTrackByGUID(container.trackGUID)
    if not containerTrack then
        return nil, {}
    end
    
    -- Find channel tracks
    local channelTracks = {}
    if container.channelTrackGUIDs then
        for _, guid in ipairs(container.channelTrackGUIDs) do
            local track = Generation.findTrackByGUID(guid)
            if track then
                table.insert(channelTracks, track)
            else
                -- Missing track, structure is broken
                return containerTrack, {}
            end
        end
    end
    
    return containerTrack, channelTracks
end

-- Restore folder structure for found tracks
-- @param containerTrack userdata: The container track
-- @param channelTracks table: Array of channel tracks
function Generation.restoreFolderStructure(containerTrack, channelTracks)
    if #channelTracks == 0 then
        return
    end
    
    -- Set container as folder
    reaper.SetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH", 1)
    
    -- Set middle tracks as normal
    for i = 1, #channelTracks - 1 do
        reaper.SetMediaTrackInfo_Value(channelTracks[i], "I_FOLDERDEPTH", 0)
    end
    
    -- Last track closes folder
    reaper.SetMediaTrackInfo_Value(channelTracks[#channelTracks], "I_FOLDERDEPTH", -1)
end

-- Check if container is last in group and adjust folder closing
-- @param containerTrack userdata: The container track
-- @param channelTracks table: Array of channel tracks
-- @param isLastInGroup boolean: Whether this is the last container in group
function Generation.adjustFolderClosing(containerTrack, channelTracks, isLastInGroup)
    if #channelTracks == 0 then
        -- No channel tracks, container itself should close if last
        if isLastInGroup then
            reaper.SetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH", -1)
        else
            reaper.SetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH", 0)
        end
    else
        -- Has channel tracks (multichannel)
        -- Container is a folder
        reaper.SetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH", 1)
        
        -- Middle tracks are normal
        for i = 1, #channelTracks - 1 do
            reaper.SetMediaTrackInfo_Value(channelTracks[i], "I_FOLDERDEPTH", 0)
        end
        
        -- Last track must close both container and possibly group
        if isLastInGroup then
            -- Need to close both container and group
            -- Set to -1 which should close all open folders up to this point
            reaper.SetMediaTrackInfo_Value(channelTracks[#channelTracks], "I_FOLDERDEPTH", -1)
        else
            -- Just close the container
            reaper.SetMediaTrackInfo_Value(channelTracks[#channelTracks], "I_FOLDERDEPTH", -1)
        end
    end
end

-- Function to validate multi-channel track structure
-- @param containerTrack userdata: The container track
-- @param expectedChannels number: Expected number of channel tracks
-- @return boolean: True if structure is valid
function Generation.validateMultiChannelStructure(containerTrack, expectedChannels)
    local folderDepth = reaper.GetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH")
    
    -- Container must be a folder
    if folderDepth ~= 1 then
        return false
    end
    
    -- Get existing tracks
    local tracks = Generation.getExistingChannelTracks(containerTrack)
    
    -- Check count
    if #tracks ~= expectedChannels then
        return false
    end
    
    -- Verify parent-child relationship
    for _, track in ipairs(tracks) do
        local parent = reaper.GetParentTrack(track)
        if parent ~= containerTrack then
            return false
        end
    end
    
    return true
end

-- Find channel tracks by name pattern when folder structure is lost
-- @param containerTrack userdata: The container track
-- @param container table: The container configuration
-- @return table: Array of channel tracks if found, empty otherwise
function Generation.findChannelTracksByName(containerTrack, container)
    local tracks = {}
    local containerName = container.name
    local containerIdx = reaper.GetMediaTrackInfo_Value(containerTrack, "IP_TRACKNUMBER") - 1
    
    -- Look for tracks immediately after the container
    local expectedChannels = globals.Constants.CHANNEL_CONFIGS[container.channelMode].channels
    local config = globals.Constants.CHANNEL_CONFIGS[container.channelMode]
    local activeConfig = config
    if config.hasVariants then
        activeConfig = config.variants[container.channelVariant or 0]
    end
    
    -- Check the next N tracks for matching names
    for i = 1, expectedChannels do
        local trackIdx = containerIdx + i
        if trackIdx < reaper.CountTracks(0) then
            local track = reaper.GetTrack(0, trackIdx)
            local _, trackName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
            
            -- Check if name matches pattern "ContainerName - ChannelLabel"
            local expectedName = containerName .. " - " .. activeConfig.labels[i]
            if trackName == expectedName then
                table.insert(tracks, track)
            else
                -- Structure is broken, return empty
                return {}
            end
        else
            -- Not enough tracks
            return {}
        end
    end
    
    -- If we found all expected tracks, restore folder structure
    if #tracks == expectedChannels then
        -- Restore container as folder
        reaper.SetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH", 1)
        -- Set middle tracks as normal
        for i = 1, #tracks - 1 do
            reaper.SetMediaTrackInfo_Value(tracks[i], "I_FOLDERDEPTH", 0)
        end
        -- Set last track to close folder
        reaper.SetMediaTrackInfo_Value(tracks[#tracks], "I_FOLDERDEPTH", -1)
    end
    
    return tracks
end

-- Clear all items from channel tracks
-- @param tracks table: Array of tracks to clear
function Generation.clearChannelTracks(tracks)
    for _, track in ipairs(tracks) do
        while reaper.CountTrackMediaItems(track) > 0 do
            local item = reaper.GetTrackMediaItem(track, 0)
            reaper.DeleteTrackMediaItem(track, item)
        end
    end
end

-- Get tracks for container in a unified way
-- @param container table: The container configuration
-- @param containerTrack userdata: The container track
-- @return table: Array of tracks to process (channel tracks if multichannel, container track if not)
function Generation.getTracksForContainer(container, containerTrack)
    if container.channelMode and container.channelMode > 0 then
        -- Multi-channel mode: get child tracks
        return Generation.getExistingChannelTracks(containerTrack)
    else
        -- Default mode: just the container track
        return {containerTrack}
    end
end

-- Clear items from container (unified function for both modes)
-- @param container table: The container configuration
-- @param containerTrack userdata: The container track
function Generation.clearContainerItems(container, containerTrack)
    local tracks = Generation.getTracksForContainer(container, containerTrack)
    for _, track in ipairs(tracks) do
        while reaper.CountTrackMediaItems(track) > 0 do
            local item = reaper.GetTrackMediaItem(track, 0)
            reaper.DeleteTrackMediaItem(track, item)
        end
    end
end

-- Delete all child tracks of a container (for mode changes)
-- @param containerTrack userdata: The container track
function Generation.deleteContainerChildTracks(containerTrack)
    local containerIdx = reaper.GetMediaTrackInfo_Value(containerTrack, "IP_TRACKNUMBER") - 1
    local folderDepth = reaper.GetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH")

    if folderDepth == 1 then
        -- Container is a folder, delete all children
        local tracksToDelete = {}
        local i = containerIdx + 1
        local depth = 1

        while i < reaper.CountTracks(0) and depth > 0 do
            local track = reaper.GetTrack(0, i)
            table.insert(tracksToDelete, track)
            local childDepth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            depth = depth + childDepth
            i = i + 1
        end

        -- Delete in reverse order
        for j = #tracksToDelete, 1, -1 do
            reaper.DeleteTrack(tracksToDelete[j])
        end

        -- Reset container to non-folder
        reaper.SetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH", 0)
    end
end

-- Function to place items for a container with inheritance support
function Generation.placeItemsForContainer(group, container, containerGroup, xfadeshape)
    -- Get effective parameters considering inheritance from parent group
    local effectiveParams = globals.Structures.getEffectiveContainerParams(group, container)

    -- Find group and container indices for area functionality
    local groupIndex = nil
    local containerIndex = nil
    for gi, g in ipairs(globals.groups) do
        for ci, c in ipairs(g.containers) do
            if c == container then
                groupIndex = gi
                containerIndex = ci
                break
            end
        end
        if groupIndex then break end
    end

    -- Handle multi-channel setup with simplified detection
    local shouldBeMultiChannel = container.channelMode and container.channelMode > 0
    local hasChildTracks = reaper.GetMediaTrackInfo_Value(containerGroup, "I_FOLDERDEPTH") == 1
    local isLastInGroup = (containerIndex == #group.containers)
    local channelTracks = {}

    -- Check if current structure matches expected mode
    if shouldBeMultiChannel == hasChildTracks then
        -- Structure matches, use existing tracks
        channelTracks = Generation.getExistingChannelTracks(containerGroup)

        -- For multi-channel, verify we have the correct number of channels
        if shouldBeMultiChannel then
            local expectedChannels = globals.Constants.CHANNEL_CONFIGS[container.channelMode].channels

            if #channelTracks ~= expectedChannels then
                -- Incorrect number of channels, recreate structure
                Generation.deleteContainerChildTracks(containerGroup)
                channelTracks = Generation.createMultiChannelTracks(containerGroup, container, isLastInGroup)
            else
                -- Correct structure, clear items from channel tracks
                Generation.clearChannelTracks(channelTracks)
                -- Store/update GUIDs for next time
                Generation.storeTrackGUIDs(container, containerGroup, channelTracks)
            end
        else
            -- Single track mode, clear items from container
            while reaper.CountTrackMediaItems(containerGroup) > 0 do
                local item = reaper.GetTrackMediaItem(containerGroup, 0)
                reaper.DeleteTrackMediaItem(containerGroup, item)
            end
            -- Store GUID for non-multichannel container
            container.trackGUID = Generation.getTrackGUID(containerGroup)
        end
    else
        -- Structure doesn't match, recreate it
        if hasChildTracks then
            -- Remove existing child tracks
            Generation.deleteContainerChildTracks(containerGroup)
        end

        if shouldBeMultiChannel then
            -- Create multi-channel structure
            channelTracks = Generation.createMultiChannelTracks(containerGroup, container, isLastInGroup)
        else
            -- Use single track
            channelTracks = {containerGroup}
            -- Store GUID for non-multichannel container
            container.trackGUID = Generation.getTrackGUID(containerGroup)
        end
    end

    local skippedItems = 0
    local minRequiredLength = 0
    local containerName = container.name or "Unnamed Container"

    if effectiveParams.items and #effectiveParams.items > 0 then
        -- Calculate interval based on the selected mode
        local interval = effectiveParams.triggerRate -- Default (Absolute mode)

        if effectiveParams.intervalMode == 1 then
            -- Relative mode: Interval is a percentage of time selection length
            interval = (globals.timeSelectionLength * effectiveParams.triggerRate) / 100
        elseif effectiveParams.intervalMode == 2 then
            -- Coverage mode: Calculate interval based on average item length and desired coverage
            local totalItemLength = 0
            local itemCount = #effectiveParams.items

            if itemCount > 0 then
                for _, item in ipairs(effectiveParams.items) do
                    totalItemLength = totalItemLength + item.length
                end

                local averageItemLength = totalItemLength / itemCount
                local desiredCoverage = effectiveParams.triggerRate / 100 -- Convert percentage to ratio
                local totalNumberOfItems = (globals.timeSelectionLength * desiredCoverage) / averageItemLength

                if totalNumberOfItems > 0 then
                    interval = globals.timeSelectionLength / totalNumberOfItems
                else
                    interval = globals.timeSelectionLength -- Fallback
                end
            end
        elseif effectiveParams.intervalMode == 3 then
            -- Chunk mode: Generate chunks with sound periods followed by silence periods
            -- For multi-channel, generate on each track
            if container.channelMode and container.channelMode > 0 then
                for _, channelTrack in ipairs(channelTracks) do
                    Generation.placeItemsChunkMode(effectiveParams, channelTrack, xfadeshape)
                end
                return
            else
                return Generation.placeItemsChunkMode(effectiveParams, containerGroup, xfadeshape)
            end
        end

        -- Generate items on each channel track independently
        for _, targetTrack in ipairs(channelTracks) do
            -- Reset for each track
            local lastItemRef = nil
            local isFirstItem = true
            local lastItemEnd = globals.startTime

            while lastItemEnd < globals.endTime do
                -- Select a random item from the container
                local randomItemIndex = math.random(1, #effectiveParams.items)
                local originalItemData = effectiveParams.items[randomItemIndex]

                -- Select area if available, or use full item
                local itemData = Utils.selectRandomAreaOrFullItem(originalItemData)
            
            -- Vérification pour les intervalles négatifs
            if interval < 0 then
                local requiredLength = math.abs(interval)
                if itemData.length < requiredLength then
                    -- Item trop court, on le skip
                    skippedItems = skippedItems + 1
                    if minRequiredLength == 0 or requiredLength > minRequiredLength then
                        minRequiredLength = requiredLength
                    end
                    
                    -- Avancer légèrement pour éviter une boucle infinie
                    lastItemEnd = lastItemEnd + 0.1
                    goto continue_loop -- Skip cet item et passer au suivant
                end
            end

            local position
            local maxDrift
            local drift
            
            -- Placement spécial pour le premier item avec intervalle > 0
            if isFirstItem and interval > 0 then
                -- Placer directement entre startTime et startTime+interval
                position = globals.startTime + math.random() * interval
                isFirstItem = false
            else
                -- Calcul standard de position pour les items suivants
                if effectiveParams.intervalMode == 0 and interval < 0 then
                    -- Negative spacing creates overlap with the last item
                    maxDrift = math.abs(interval) * (effectiveParams.triggerDrift / 100)
                    drift = Utils.randomInRange(-maxDrift/2, maxDrift/2)
                    position = lastItemEnd + interval + drift
                else
                    -- Regular spacing from the end of the last item
                    maxDrift = interval * (effectiveParams.triggerDrift / 100)
                    drift = Utils.randomInRange(-maxDrift/2, maxDrift/2)
                    position = lastItemEnd + interval + drift
                end
                
                -- Ensure no item starts before time selection
                if position < globals.startTime then
                    position = globals.startTime
                end
            end

            -- Stop if the item would start beyond the end of the time selection
            if position >= globals.endTime then
                break
            end

            -- Create and configure the new item on current track
            local newItem = reaper.AddMediaItemToTrack(targetTrack)
            local newTake = reaper.AddTakeToMediaItem(newItem)

            -- Configure the item
            local PCM_source = reaper.PCM_Source_CreateFromFile(itemData.filePath)
            reaper.SetMediaItemTake_Source(newTake, PCM_source)
            reaper.SetMediaItemTakeInfo_Value(newTake, "D_STARTOFFS", itemData.startOffset)

            -- Trim item so it never exceeds the selection end
            local maxLen = globals.endTime - position
            local actualLen = math.min(itemData.length, maxLen)

            reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", position)
            reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH", actualLen)
            reaper.GetSetMediaItemTakeInfo_String(newTake, "P_NAME", itemData.name, true)

            -- Apply randomizations using effective parameters
            if effectiveParams.randomizePitch then
                local randomPitch = itemData.originalPitch + Utils.randomInRange(effectiveParams.pitchRange.min, effectiveParams.pitchRange.max)
                reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", randomPitch)
            else
                reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", itemData.originalPitch)
            end

            if effectiveParams.randomizeVolume then
                local randomVolume = itemData.originalVolume * 10^(Utils.randomInRange(effectiveParams.volumeRange.min, effectiveParams.volumeRange.max) / 20)
                reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", randomVolume)
            else
                reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", itemData.originalVolume)
            end

            -- Apply pan randomization only for stereo containers (channelMode = 0 or nil)
            if effectiveParams.randomizePan and (not effectiveParams.channelMode or effectiveParams.channelMode == 0) then
                local randomPan = itemData.originalPan + Utils.randomInRange(effectiveParams.panRange.min, effectiveParams.panRange.max) / 100
                randomPan = math.max(-1, math.min(1, randomPan))
                -- Use envelope instead of directly modifying the property
                Items.createTakePanEnvelope(newTake, randomPan)
            end

            -- Apply fade in if enabled
            if effectiveParams.fadeInEnabled then
                local fadeInDuration = effectiveParams.fadeInDuration or 0.1
                -- Convert percentage to seconds if using percentage mode
                if effectiveParams.fadeInUsePercentage then
                    fadeInDuration = (fadeInDuration / 100) * actualLen
                end
                -- Ensure fade doesn't exceed item length
                fadeInDuration = math.min(fadeInDuration, actualLen)

                reaper.SetMediaItemInfo_Value(newItem, "D_FADEINLEN", fadeInDuration)
                reaper.SetMediaItemInfo_Value(newItem, "C_FADEINSHAPE", effectiveParams.fadeInShape or 0)
                reaper.SetMediaItemInfo_Value(newItem, "D_FADEINDIR", effectiveParams.fadeInCurve or 0.0)
            end

            -- Apply fade out if enabled
            if effectiveParams.fadeOutEnabled then
                local fadeOutDuration = effectiveParams.fadeOutDuration or 0.1
                -- Convert percentage to seconds if using percentage mode
                if effectiveParams.fadeOutUsePercentage then
                    fadeOutDuration = (fadeOutDuration / 100) * actualLen
                end
                -- Ensure fade doesn't exceed item length
                fadeOutDuration = math.min(fadeOutDuration, actualLen)

                reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTLEN", fadeOutDuration)
                reaper.SetMediaItemInfo_Value(newItem, "C_FADEOUTSHAPE", effectiveParams.fadeOutShape or 0)
                reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTDIR", effectiveParams.fadeOutCurve or 0.0)
            end

            -- Create crossfade if items overlap (negative triggerRate)
            if lastItemRef and position < lastItemEnd then
                Utils.createCrossfade(lastItemRef, newItem, xfadeshape)
            end

            -- Update references for next iteration
            lastItemEnd = position + actualLen
            lastItemRef = newItem
            ::continue_loop::
            end  -- End of while loop for current track
        end  -- End of for loop for each channel track

        -- Message d'erreur pour les items skippés
        if skippedItems > 0 then
            local message = string.format(
                "Warning: %d item(s) were skipped in container '%s'\n" ..
                "Reason: Item length insufficient for negative interval of %.2f seconds\n" ..
                "Minimum required item length: %.2f seconds",
                skippedItems,
                containerName,
                math.abs(interval),
                minRequiredLength
            )
            
            reaper.ShowConsoleMsg(message .. "\n")
        end
    end

    -- Create crossfades with existing items if they exist
    if globals.crossfadeItems and globals.crossfadeItems[containerGroup] then
        local crossfadeData = globals.crossfadeItems[containerGroup]
        
        -- Create crossfades with items at the start of the time selection
        for _, startItem in ipairs(crossfadeData.startItems) do
            local startItemEnd = reaper.GetMediaItemInfo_Value(startItem, "D_POSITION") + 
                                reaper.GetMediaItemInfo_Value(startItem, "D_LENGTH")
            
            -- Find new items that overlap with this start item
            local containerItemCount = reaper.GetTrackNumMediaItems(containerGroup)
            for i = 0, containerItemCount - 1 do
                local newItem = reaper.GetTrackMediaItem(containerGroup, i)
                local newItemStart = reaper.GetMediaItemInfo_Value(newItem, "D_POSITION")
                
                -- Check if the new item overlaps with the start item
                if newItemStart < startItemEnd and newItemStart >= globals.startTime then
                    Utils.createCrossfade(startItem, newItem, xfadeshape)
                    break -- One crossfade per start item is enough
                end
            end
        end
        
        -- Create crossfades with items at the end of the time selection
        for _, endItem in ipairs(crossfadeData.endItems) do
            local endItemStart = reaper.GetMediaItemInfo_Value(endItem, "D_POSITION")
            
            -- Find new items that overlap with this end item
            local containerItemCount = reaper.GetTrackNumMediaItems(containerGroup)
            for i = containerItemCount - 1, 0, -1 do -- Start from the end
                local newItem = reaper.GetTrackMediaItem(containerGroup, i)
                local newItemStart = reaper.GetMediaItemInfo_Value(newItem, "D_POSITION")
                local newItemEnd = newItemStart + reaper.GetMediaItemInfo_Value(newItem, "D_LENGTH")
                
                -- Check if the new item overlaps with the end item
                if newItemEnd > endItemStart and newItemEnd <= globals.endTime then
                    Utils.createCrossfade(newItem, endItem, xfadeshape)
                    break -- One crossfade per end item is enough
                end
            end
        end
        
        -- Clean up the crossfade data after use
        globals.crossfadeItems[containerGroup] = nil
    end

end



-- Update all functions that call placeItemsForContainer to pass group parameter

-- Function to generate groups and place items
function Generation.generateGroups()
    if not globals.timeSelectionValid then
        reaper.MB("Please create a time selection before generating groups!", "Error", 0)
        return
    end

    reaper.Main_OnCommand(40289, 0) -- "Item: Unselect all items"
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    -- Get default crossfade shape from REAPER preferences
    local xfadeshape = reaper.SNM_GetIntConfigVar("defxfadeshape", 0)

    if globals.keepExistingTracks then
        -- Use regeneration logic for existing tracks (keep existing)
        for i, group in ipairs(globals.groups) do
            Generation.generateSingleGroup(i)
        end
    else
        -- Original behavior: delete and recreate tracks (clear all)
        Generation.deleteExistingGroups()
        
        for i, group in ipairs(globals.groups) do
            -- Create a parent group
            local parentGroupIdx = reaper.GetNumTracks()
            reaper.InsertTrackAtIndex(parentGroupIdx, true)
            local parentGroup = reaper.GetTrack(0, parentGroupIdx)
            reaper.GetSetMediaTrackInfo_String(parentGroup, "P_NAME", group.name, true)
            
            -- Set the group as parent (folder start)
            reaper.SetMediaTrackInfo_Value(parentGroup, "I_FOLDERDEPTH", 1)
            
            -- Apply group track volume
            local groupVolumeDB = group.trackVolume or 0.0
            local linearVolume = Utils.dbToLinear(groupVolumeDB)
            reaper.SetMediaTrackInfo_Value(parentGroup, "D_VOL", linearVolume)
            
            local containerCount = #group.containers
            
            for j, container in ipairs(group.containers) do
                -- Create a group for each container
                local containerGroupIdx = reaper.GetNumTracks()
                reaper.InsertTrackAtIndex(containerGroupIdx, true)
                local containerGroup = reaper.GetTrack(0, containerGroupIdx)
                reaper.GetSetMediaTrackInfo_String(containerGroup, "P_NAME", container.name, true)

                -- Check if this is a multi-channel container
                local isMultiChannel = container.channelMode and container.channelMode > 0

                -- Set folder state based on position and channel mode
                local folderState = 0 -- Default: normal group in a folder
                if not isMultiChannel then
                    -- Only set folder state for non-multi-channel containers
                    if j == containerCount then
                        -- If it's the last container, mark as folder end
                        folderState = -1
                    end
                    reaper.SetMediaTrackInfo_Value(containerGroup, "I_FOLDERDEPTH", folderState)
                else
                    -- For multi-channel containers, don't set folder depth here
                    -- Let createMultiChannelTracks handle it
                    -- But we need to pass info about whether it's the last container
                    container.isLastInGroup = (j == containerCount)
                end

                -- Apply container track volume
                local volumeDB = container.trackVolume or 0.0
                local linearVolume = Utils.dbToLinear(volumeDB)
                reaper.SetMediaTrackInfo_Value(containerGroup, "D_VOL", linearVolume)

                -- Place items on the timeline according to the chosen mode
                Generation.placeItemsForContainer(group, container, containerGroup, xfadeshape)
            end

            -- After all containers are created, ensure proper folder closure
            -- If the last container was multi-channel, we need to close the parent group
            local lastContainer = group.containers[#group.containers]
            if lastContainer and lastContainer.channelMode and lastContainer.channelMode > 0 then
                -- The last container is multi-channel, its children need to close the parent group too
                -- Find the last track in the entire group
                local parentGroupIdx = reaper.GetMediaTrackInfo_Value(parentGroup, "IP_TRACKNUMBER") - 1
                local depth = 1
                local lastTrackIdx = parentGroupIdx

                -- Find the last track in this group's hierarchy
                local i = parentGroupIdx + 1
                while i < reaper.CountTracks(0) and depth > 0 do
                    lastTrackIdx = i
                    local track = reaper.GetTrack(0, i)
                    local trackDepth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
                    depth = depth + trackDepth
                    i = i + 1
                end

                -- Get the actual last track and ensure it closes the parent group
                if lastTrackIdx > parentGroupIdx then
                    local lastTrack = reaper.GetTrack(0, lastTrackIdx)
                    -- This track should close both its container and the parent group
                    -- Since Reaper doesn't support -2, we use -1 which should close the outermost open folder
                    reaper.SetMediaTrackInfo_Value(lastTrack, "I_FOLDERDEPTH", -1)
                end
            end
        end
    end

    -- Ensure Master track has enough channels for all multi-channel groups
    local maxChannels = 2  -- Minimum stereo
    for i, group in ipairs(globals.groups) do
        for j, container in ipairs(group.containers) do
            if container.channelMode and container.channelMode > 0 then
                local config = globals.Constants.CHANNEL_CONFIGS[container.channelMode]
                if config then
                    local requiredChannels = config.totalChannels or config.channels
                    maxChannels = math.max(maxChannels, requiredChannels)
                end
            end
        end
    end

    -- Update Master track if necessary
    local masterTrack = reaper.GetMasterTrack(0)
    if masterTrack then
        local currentMasterChannels = reaper.GetMediaTrackInfo_Value(masterTrack, "I_NCHAN")
        if currentMasterChannels < maxChannels then
            reaper.SetMediaTrackInfo_Value(masterTrack, "I_NCHAN", maxChannels)
        end
    end

    -- Check for routing conflicts after generating all groups
    Generation.checkAndResolveConflicts()

    -- Clear regeneration flags for all groups and containers
    for _, group in ipairs(globals.groups) do
        group.needsRegeneration = false
        for _, container in ipairs(group.containers) do
            container.needsRegeneration = false
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()

    if globals.keepExistingTracks then
        reaper.Undo_EndBlock("Regenerate all groups", -1)
    else
        reaper.Undo_EndBlock("Generate groups and place items", -1)
    end
end


function Generation.generateSingleGroup(groupIndex)
    if not globals.timeSelectionValid then
        reaper.MB("Please create a time selection before regenerating!", "Error", 0)
        return
    end

    local group = globals.groups[groupIndex]
    if not group then return end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    reaper.Main_OnCommand(40289, 0) -- "Item: Unselect all items"

    -- Get default crossfade shape from REAPER preferences
    local xfadeshape = reaper.SNM_GetIntConfigVar("defxfadeshape", 0)

    -- Find the existing group by its name
    local existingGroup, existingGroupIdx = Utils.findGroupByName(group.name)

    if existingGroup then
        -- Group exists, apply volume to existing group track
        local groupVolumeDB = group.trackVolume or 0.0
        local linearVolume = Utils.dbToLinear(groupVolumeDB)
        reaper.SetMediaTrackInfo_Value(existingGroup, "D_VOL", linearVolume)
        
        -- Find all container groups within this folder
        local containerGroups = {}
        local containerNameMap = {}
        local groupCount = reaper.CountTracks(0)
        local folderDepth = 1 -- Start with depth 1 (inside a folder)

        for i = existingGroupIdx + 1, groupCount - 1 do
            local childGroup = reaper.GetTrack(0, i)
            local depth = reaper.GetMediaTrackInfo_Value(childGroup, "I_FOLDERDEPTH")
            local _, containerName = reaper.GetSetMediaTrackInfo_String(childGroup, "P_NAME", "", false)

            -- Add this group to our container list
            table.insert(containerGroups, childGroup)
            containerNameMap[containerName] = #containerGroups -- Store index by name

            -- Update folder depth
            folderDepth = folderDepth + depth

            -- If we reach the end of the folder, stop searching
            if folderDepth <= 0 then break end
        end

        -- Process each container in the structure
        for j, container in ipairs(group.containers) do
            local containerGroup = nil
            local containerIndex = containerNameMap[container.name]
            
            if containerIndex then
                -- Container exists, use it
                containerGroup = containerGroups[containerIndex]
                -- Items will be cleared by placeItemsForContainer
            else
                -- Container doesn't exist, create it
                local insertPosition = existingGroupIdx + #containerGroups + 1
                reaper.InsertTrackAtIndex(insertPosition, true)
                containerGroup = reaper.GetTrack(0, insertPosition)
                reaper.GetSetMediaTrackInfo_String(containerGroup, "P_NAME", container.name, true)
                
                -- Set appropriate folder depth
                local folderState = 0 -- Default: normal track in folder
                -- Check if this should be the last container (folder end)
                local isLastContainer = (j == #group.containers) and (#containerGroups == 0)
                if isLastContainer then
                    folderState = -1
                end
                reaper.SetMediaTrackInfo_Value(containerGroup, "I_FOLDERDEPTH", folderState)
                
                -- Apply container track volume
                local volumeDB = container.trackVolume or 0.0
                local linearVolume = Utils.dbToLinear(volumeDB)
                reaper.SetMediaTrackInfo_Value(containerGroup, "D_VOL", linearVolume)
                
                -- Add to our tracking
                table.insert(containerGroups, containerGroup)
                containerNameMap[container.name] = #containerGroups
            end

            -- Generate items for this container
            Generation.placeItemsForContainer(group, container, containerGroup, xfadeshape)
        end

        -- Ensure the group folder is properly closed
        -- Find the last track in the group hierarchy
        local lastTrackInGroup = nil
        local i = existingGroupIdx + 1
        local depth = 1
        
        while i < reaper.CountTracks(0) and depth > 0 do
            local track = reaper.GetTrack(0, i)
            lastTrackInGroup = track
            local trackDepth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            depth = depth + trackDepth
            i = i + 1
        end
        
        -- If we found the last track, ensure it closes the group
        if lastTrackInGroup then
            local currentDepth = reaper.GetMediaTrackInfo_Value(lastTrackInGroup, "I_FOLDERDEPTH")
            if currentDepth >= 0 then
                -- Track doesn't close folder, fix it
                reaper.SetMediaTrackInfo_Value(lastTrackInGroup, "I_FOLDERDEPTH", -1)
            end
        end

    else
        -- Group doesn't exist, create it with all containers
        local parentGroupIdx = reaper.GetNumTracks()
        reaper.InsertTrackAtIndex(parentGroupIdx, true)
        local parentGroup = reaper.GetTrack(0, parentGroupIdx)
        reaper.GetSetMediaTrackInfo_String(parentGroup, "P_NAME", group.name, true)

        -- Set the group as parent (folder start)
        reaper.SetMediaTrackInfo_Value(parentGroup, "I_FOLDERDEPTH", 1)
        
        -- Apply group track volume
        local groupVolumeDB = group.trackVolume or 0.0
        local linearVolume = Utils.dbToLinear(groupVolumeDB)
        reaper.SetMediaTrackInfo_Value(parentGroup, "D_VOL", linearVolume)

        local containerCount = #group.containers

        for j, container in ipairs(group.containers) do
            -- Create a group for each container
            local containerGroupIdx = reaper.GetNumTracks()
            reaper.InsertTrackAtIndex(containerGroupIdx, true)
            local containerGroup = reaper.GetTrack(0, containerGroupIdx)
            reaper.GetSetMediaTrackInfo_String(containerGroup, "P_NAME", container.name, true)

            -- Set folder state based on position
            local folderState = 0 -- Default: normal group in a folder
            if j == containerCount then
                -- If it's the last container, mark as folder end
                folderState = -1
            end
            reaper.SetMediaTrackInfo_Value(containerGroup, "I_FOLDERDEPTH", folderState)

            -- Apply container track volume
            local volumeDB = container.trackVolume or 0.0
            local linearVolume = Utils.dbToLinear(volumeDB)
            reaper.SetMediaTrackInfo_Value(containerGroup, "D_VOL", linearVolume)

            -- Place items on the timeline according to the chosen mode
            Generation.placeItemsForContainer(group, container, containerGroup, xfadeshape)
        end
    end

    -- Check for routing conflicts after generating single group
    Generation.checkAndResolveConflicts()

    -- Clear regeneration flag for the group and all its containers
    group.needsRegeneration = false
    for _, container in ipairs(group.containers) do
        container.needsRegeneration = false
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Regenerate group '" .. group.name .. "'", -1)
end




-- Function to regenerate a single container
function Generation.generateSingleContainer(groupIndex, containerIndex)
    if not globals.timeSelectionValid then
        reaper.MB("Please create a time selection before regenerating!", "Error", 0)
        return
    end

    local group = globals.groups[groupIndex]
    local container = group.containers[containerIndex]
    if not group or not container then return end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    -- Deselect all items in the project
    reaper.Main_OnCommand(40289, 0) -- "Item: Unselect all items"

    -- Get default crossfade shape from REAPER preferences
    local xfadeshape = reaper.SNM_GetIntConfigVar("defxfadeshape", 0)

    -- Find or create the parent group
    local parentGroup, parentGroupIdx = Utils.findGroupByName(group.name)

    if not parentGroup then
        -- Parent group doesn't exist, create it first
        parentGroupIdx = reaper.GetNumTracks()
        reaper.InsertTrackAtIndex(parentGroupIdx, true)
        parentGroup = reaper.GetTrack(0, parentGroupIdx)
        reaper.GetSetMediaTrackInfo_String(parentGroup, "P_NAME", group.name, true)
        reaper.SetMediaTrackInfo_Value(parentGroup, "I_FOLDERDEPTH", 1)
    end

    -- Try to find container by GUID first
    local containerGroup, containerGroupIdx = nil, nil
    
    if container.trackGUID then
        containerGroup = Generation.findTrackByGUID(container.trackGUID)
        if containerGroup then
            containerGroupIdx = reaper.GetMediaTrackInfo_Value(containerGroup, "IP_TRACKNUMBER") - 1
        end
    end
    
    -- If not found by GUID, search by name
    if not containerGroup then
        containerGroup, containerGroupIdx = Utils.findContainerGroup(parentGroupIdx, container.name)
    end

    if containerGroup then
        -- Container exists, check if channel mode structure has changed
        local shouldBeMultiChannel = container.channelMode and container.channelMode > 0
        local hasChildTracks = reaper.GetMediaTrackInfo_Value(containerGroup, "I_FOLDERDEPTH") == 1

        -- If structure doesn't match the expected mode, clean it completely
        if shouldBeMultiChannel ~= hasChildTracks then
            if hasChildTracks then
                -- Current structure has child tracks but should be single track
                Generation.deleteContainerChildTracks(containerGroup)
            else
                -- Current structure is single track but should have child tracks
                -- Clear items from container to prepare for multi-channel structure
                while reaper.CountTrackMediaItems(containerGroup) > 0 do
                    local item = reaper.GetTrackMediaItem(containerGroup, 0)
                    reaper.DeleteTrackMediaItem(containerGroup, item)
                end
            end
        else
            -- Structure matches, just clear items appropriately
            if globals.keepExistingTracks then
                -- Check if container is supposed to be multi-channel
                local isMultiChannel = container.channelMode and container.channelMode > 0

                if isMultiChannel then
                    -- Multi-channel: clear items from channel tracks
                    local channelTracks = Generation.getExistingChannelTracks(containerGroup)
                    Generation.clearChannelTracks(channelTracks)
                else
                    -- Default mode: clear items from container itself
                    while reaper.CountTrackMediaItems(containerGroup) > 0 do
                        local item = reaper.GetTrackMediaItem(containerGroup, 0)
                        reaper.DeleteTrackMediaItem(containerGroup, item)
                    end
                end
            else
                -- Delete all items from container and its children
                Utils.clearGroupItems(containerGroup)
            end
        end

        -- Apply container track volume
        local volumeDB = container.trackVolume or 0.0
        local linearVolume = Utils.dbToLinear(volumeDB)
        reaper.SetMediaTrackInfo_Value(containerGroup, "D_VOL", linearVolume)

        -- Regenerate items for this container (will handle multi-channel internally)
        Generation.placeItemsForContainer(group, container, containerGroup, xfadeshape)

    else
        -- Container doesn't exist, create it within the parent group
        
        -- Get current containers in the group before modification
        local existingContainers = Utils.getAllContainersInGroup(parentGroupIdx)
        
        -- Calculate insertion position
        local insertPosition = parentGroupIdx + 1
        if #existingContainers > 0 then
            -- If there are existing containers, we need to insert before the last one
            -- and then fix the folder structure so the last one keeps the -1 depth
            local lastContainer = existingContainers[#existingContainers]
            insertPosition = lastContainer.index  -- Insert before the last container
        end
        
        -- Insert the new container track
        reaper.InsertTrackAtIndex(insertPosition, true)
        containerGroup = reaper.GetTrack(0, insertPosition)
        reaper.GetSetMediaTrackInfo_String(containerGroup, "P_NAME", container.name, true)
        
        -- Set initial folder depth as normal track in folder
        reaper.SetMediaTrackInfo_Value(containerGroup, "I_FOLDERDEPTH", 0)
        
        -- Apply container track volume
        local volumeDB = container.trackVolume or 0.0
        local linearVolume = Utils.dbToLinear(volumeDB)
        reaper.SetMediaTrackInfo_Value(containerGroup, "D_VOL", linearVolume)
        
        -- Generate items for this new container
        Generation.placeItemsForContainer(group, container, containerGroup, xfadeshape)
        
        -- CRITICAL: After insertion, indices have changed, so we need to get the updated parent index
        local updatedParentGroup, updatedParentGroupIdx = Utils.findGroupByName(group.name)
        if updatedParentGroup then
            -- Fix the folder structure for the entire group with updated indices
            Utils.fixGroupFolderStructure(updatedParentGroupIdx)
        end
    end

    -- Validate and repair folder structure if needed (safety check)
    -- Get fresh parent group reference in case indices changed
    local finalParentGroup, finalParentGroupIdx = Utils.findGroupByName(group.name)
    if finalParentGroup then
        Utils.validateAndRepairGroupStructure(finalParentGroupIdx)
    end

    -- Check for routing conflicts after generating single container
    Generation.checkAndResolveConflicts()

    -- Clear regeneration flag for the container
    container.needsRegeneration = false

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Regenerate container '" .. container.name .. "' in group '" .. group.name .. "'", -1)
end

-- Enhanced function to fix folder structure of a group (replaces the existing one)
function Generation.fixGroupFolderStructure(parentGroupIdx)
    -- Use the new utility function for consistency
    return Utils.fixGroupFolderStructure(parentGroupIdx)
end

-- Enhanced function to fix folder structure of a group (replaces the existing one)
function Generation.fixGroupFolderStructure(parentGroupIdx)
    -- Use the new utility function for consistency
    return Utils.fixGroupFolderStructure(parentGroupIdx)
end

-- Helper function to debug folder structure (useful for troubleshooting)
function Generation.debugFolderStructure(groupName)
    local parentGroup, parentGroupIdx = Utils.findGroupByName(groupName)
    if not parentGroup then
        reaper.ShowConsoleMsg("Group '" .. groupName .. "' not found\n")
        return
    end
    
    reaper.ShowConsoleMsg("=== Folder Structure for '" .. groupName .. "' ===\n")
    reaper.ShowConsoleMsg("Parent track index: " .. parentGroupIdx .. "\n")
    
    local containers = Utils.getAllContainersInGroup(parentGroupIdx)
    for i, container in ipairs(containers) do
        reaper.ShowConsoleMsg("  Container " .. i .. ": '" .. container.name .. "' (index: " .. container.index .. ", depth: " .. container.originalDepth .. ")\n")
    end
    reaper.ShowConsoleMsg("========================\n")
end

-- Function to place items using Chunk Mode
-- Creates structured patterns of sound chunks separated by silence periods
function Generation.placeItemsChunkMode(effectiveParams, containerGroup, xfadeshape)
    if not effectiveParams.items or #effectiveParams.items == 0 then
        return
    end
    
    local chunkDuration = effectiveParams.chunkDuration
    local silenceDuration = effectiveParams.chunkSilence
    local chunkDurationVariation = effectiveParams.chunkDurationVariation / 100 -- Convert to ratio
    local chunkSilenceVariation = effectiveParams.chunkSilenceVariation / 100 -- Convert to ratio
    
    local lastItemRef = nil
    local currentTime = globals.startTime
    
    -- Process chunks until we reach the end of the time selection
    while currentTime < globals.endTime do
        -- Calculate actual chunk duration with variation (corrected formula)
        local actualChunkDuration = chunkDuration
        if chunkDurationVariation > 0 then
            local variation = Utils.randomInRange(-chunkDurationVariation, chunkDurationVariation)
            actualChunkDuration = chunkDuration * (1 + variation)
            actualChunkDuration = math.max(0.1, actualChunkDuration)
        end
        
        -- Calculate actual silence duration with variation (separate control)
        local actualSilenceDuration = silenceDuration
        if chunkSilenceVariation > 0 then
            local variation = Utils.randomInRange(-chunkSilenceVariation, chunkSilenceVariation)
            actualSilenceDuration = silenceDuration * (1 + variation)
            actualSilenceDuration = math.max(0, actualSilenceDuration)
        end
        
        local chunkEnd = math.min(currentTime + actualChunkDuration, globals.endTime)
        
        -- Generate items within this chunk period
        if chunkEnd > currentTime then
            lastItemRef = Generation.generateItemsInTimeRange(effectiveParams, containerGroup, currentTime, chunkEnd, lastItemRef, xfadeshape)
        end
        
        -- Progress using the actual durations that were calculated
        currentTime = currentTime + actualChunkDuration + actualSilenceDuration
        
        -- Break if we've gone beyond the time selection
        if currentTime >= globals.endTime then
            break
        end
    end
end

-- Helper function to generate items within a specific time range for chunk mode
function Generation.generateItemsInTimeRange(effectiveParams, containerGroup, rangeStart, rangeEnd, lastItemRef, xfadeshape)
    local rangeLength = rangeEnd - rangeStart
    if rangeLength <= 0 then
        return lastItemRef
    end
    
    -- Use the trigger rate as interval within chunks
    local interval = effectiveParams.triggerRate
    local currentTime = rangeStart
    local isFirstItem = true
    local itemCount = 0
    local maxItemsPerChunk = 1000 -- Protection contre boucle infinie
    
    while currentTime < rangeEnd and itemCount < maxItemsPerChunk do
        itemCount = itemCount + 1
        -- Select a random item from the container
        local randomItemIndex = math.random(1, #effectiveParams.items)
        local originalItemData = effectiveParams.items[randomItemIndex]

        -- Select area if available, or use full item
        local itemData = Utils.selectRandomAreaOrFullItem(originalItemData)
        
        -- Vérification pour les intervalles négatifs (overlap)
        if interval < 0 then
            local requiredLength = math.abs(interval)
            if itemData.length < requiredLength then
                -- Item trop court pour supporter l'overlap, skip et avancer minimalement
                currentTime = currentTime + 0.1
                goto continue_loop
            end
        end
        
        local position
        local maxDrift
        local drift
        
        -- Placement pour le premier item
        if isFirstItem then
            if interval > 0 then
                -- Placer directement entre rangeStart et rangeStart+interval
                local maxStartOffset = math.min(interval, rangeLength)
                position = rangeStart + math.random() * maxStartOffset
            else
                -- Pour intervalle négatif, placer le premier item au début du chunk
                position = rangeStart
            end
            isFirstItem = false
        else
            -- Calcul standard de position pour les items suivants (même logique que mode Absolute)
            maxDrift = math.abs(interval) * (effectiveParams.triggerDrift / 100)
            drift = Utils.randomInRange(-maxDrift/2, maxDrift/2)
            position = currentTime + interval + drift
            
            -- Ensure position stays within chunk bounds
            position = math.max(rangeStart, math.min(position, rangeEnd))
        end
        
        -- Stop if position would exceed chunk end
        if position >= rangeEnd then
            break
        end
        
        -- Calculate item length, ensuring it doesn't exceed chunk boundary
        local maxLength = rangeEnd - position
        local actualLength = math.min(itemData.length, maxLength)
        
        if actualLength <= 0 then
            break
        end
        
        -- Create and configure the new item
        local newItem = reaper.AddMediaItemToTrack(containerGroup)
        local newTake = reaper.AddTakeToMediaItem(newItem)
        
        -- Configure the item
        local PCM_source = reaper.PCM_Source_CreateFromFile(itemData.filePath)
        reaper.SetMediaItemTake_Source(newTake, PCM_source)
        reaper.SetMediaItemTakeInfo_Value(newTake, "D_STARTOFFS", itemData.startOffset)
        
        reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", position)
        reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH", actualLength)
        reaper.GetSetMediaItemTakeInfo_String(newTake, "P_NAME", itemData.name, true)

        -- Apply randomizations using effective parameters
        if effectiveParams.randomizePitch then
            local randomPitch = itemData.originalPitch + Utils.randomInRange(effectiveParams.pitchRange.min, effectiveParams.pitchRange.max)
            reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", randomPitch)
        else
            reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", itemData.originalPitch)
        end

        if effectiveParams.randomizeVolume then
            local randomVolume = itemData.originalVolume * 10^(Utils.randomInRange(effectiveParams.volumeRange.min, effectiveParams.volumeRange.max) / 20)
            reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", randomVolume)
        else
            reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", itemData.originalVolume)
        end

        -- Apply pan randomization only for stereo containers (channelMode = 0 or nil)
        if effectiveParams.randomizePan and (not effectiveParams.channelMode or effectiveParams.channelMode == 0) then
            local randomPan = itemData.originalPan + Utils.randomInRange(effectiveParams.panRange.min, effectiveParams.panRange.max) / 100
            randomPan = math.max(-1, math.min(1, randomPan))
            -- Use envelope instead of directly modifying the property
            require("DM_Ambiance_Items").createTakePanEnvelope(newTake, randomPan)
        end
        
        -- Apply fade in if enabled
        if effectiveParams.fadeInEnabled then
            local fadeInDuration = effectiveParams.fadeInDuration or 0.1
            -- Convert percentage to seconds if using percentage mode
            if effectiveParams.fadeInUsePercentage then
                fadeInDuration = (fadeInDuration / 100) * actualLength
            end
            -- Ensure fade doesn't exceed item length
            fadeInDuration = math.min(fadeInDuration, actualLength)
            
            reaper.SetMediaItemInfo_Value(newItem, "D_FADEINLEN", fadeInDuration)
            reaper.SetMediaItemInfo_Value(newItem, "C_FADEINSHAPE", effectiveParams.fadeInShape or 0)
            reaper.SetMediaItemInfo_Value(newItem, "D_FADEINDIR", effectiveParams.fadeInCurve or 0.0)
        end
        
        -- Apply fade out if enabled
        if effectiveParams.fadeOutEnabled then
            local fadeOutDuration = effectiveParams.fadeOutDuration or 0.1
            -- Convert percentage to seconds if using percentage mode
            if effectiveParams.fadeOutUsePercentage then
                fadeOutDuration = (fadeOutDuration / 100) * actualLength
            end
            -- Ensure fade doesn't exceed item length
            fadeOutDuration = math.min(fadeOutDuration, actualLength)
            
            reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTLEN", fadeOutDuration)
            reaper.SetMediaItemInfo_Value(newItem, "C_FADEOUTSHAPE", effectiveParams.fadeOutShape or 0)
            reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTDIR", effectiveParams.fadeOutCurve or 0.0)
        end

        -- Create crossfade if items overlap
        if lastItemRef and position < (reaper.GetMediaItemInfo_Value(lastItemRef, "D_POSITION") + reaper.GetMediaItemInfo_Value(lastItemRef, "D_LENGTH")) then
            Utils.createCrossfade(lastItemRef, newItem, xfadeshape)
        end

        lastItemRef = newItem
        
        -- Calculer la prochaine position (fin de l'item actuel)
        -- L'interval sera appliqué au prochain calcul de position
        currentTime = position + actualLength
        
        -- Protection contre progression insuffisante
        if currentTime <= position then
            currentTime = position + 0.1 -- Progression minimale
        end
        
        ::continue_loop::
    end
    
    return lastItemRef
end

-- Apply routing fixes to resolve conflicts
-- @param suggestions table: Array of routing suggestions
function Generation.applyRoutingFixes(suggestions)
    for _, suggestion in ipairs(suggestions) do
        local container = suggestion.container

        -- Update the container's channel configuration with custom routing
        container.customRouting = suggestion.newRouting

        -- Find and update the actual tracks if they exist
        local group = nil
        for _, g in ipairs(globals.groups) do
            if g.name == suggestion.groupName then
                group = g
                break
            end
        end

        if group then
            local groupTrack, groupTrackIdx = Utils.findGroupByName(group.name)
            if groupTrack then
                local containerTrack, containerTrackIdx = Utils.findContainerGroup(
                    groupTrackIdx,
                    container.name
                )

                if containerTrack then
                    -- Update the routing of existing channel tracks
                    local channelTracks = Generation.getExistingChannelTracks(containerTrack)
                    for i, channelTrack in ipairs(channelTracks) do
                        if i <= #suggestion.newRouting then
                            -- Update the send routing to new channel
                            local sendCount = reaper.GetTrackNumSends(channelTrack, 0)
                            for s = 0, sendCount - 1 do
                                local destTrack = reaper.GetTrackSendInfo_Value(channelTrack, 0, s, "P_DESTTRACK")
                                if destTrack == containerTrack then
                                    local newDestChannel = suggestion.newRouting[i] - 1
                                    local dstChannels = 1024 + newDestChannel  -- Mono routing format
                                    reaper.SetTrackSendInfo_Value(channelTrack, 0, s, "I_DSTCHAN", dstChannels)

                                    -- Update track name with new channel label if needed
                                    local channelLabel = suggestion.labels[i]
                                    local trackName = container.name .. " - " .. channelLabel
                                    reaper.GetSetMediaTrackInfo_String(channelTrack, "P_NAME", trackName, true)
                                end
                            end
                        end
                    end

                    -- Update container and parent track channel count if needed
                    local maxChannel = math.max(table.unpack(suggestion.newRouting))
                    reaper.SetMediaTrackInfo_Value(containerTrack, "I_NCHAN", maxChannel)
                    Utils.ensureParentHasEnoughChannels(containerTrack, maxChannel)
                end
            end
        end
    end

    reaper.UpdateArrange()
end

-- Centralized routing validation and issue resolution
-- Call this from any generation function
function Generation.checkAndResolveConflicts()
    -- Use the new RoutingValidator module for comprehensive validation
    if not globals.RoutingValidator then
        return  -- Module not initialized
    end

    -- Validate entire project routing using the new robust system
    local issues = globals.RoutingValidator.validateProjectRouting()

    -- Handle issues based on auto-fix setting
    if issues and #issues > 0 then
        if globals.autoFixRouting then
            -- Auto-fix mode: apply fixes automatically
            local suggestions = globals.RoutingValidator.generateFixSuggestions(issues, globals.RoutingValidator.getProjectTrackCache())
            local success = globals.RoutingValidator.autoFixRouting(issues, suggestions)

            -- If auto-fix succeeded, re-validate to ensure everything is fixed
            if success then
                local remainingIssues = globals.RoutingValidator.validateProjectRouting()
                if remainingIssues and #remainingIssues > 0 then
                    -- Some issues couldn't be auto-fixed, show modal
                    globals.RoutingValidator.showValidationModal(remainingIssues)
                end
            else
                -- Auto-fix failed, show modal for manual resolution
                globals.RoutingValidator.showValidationModal(issues)
            end
        else
            -- Manual mode: show validation modal for user review
            globals.RoutingValidator.showValidationModal(issues)
        end
    end
end

return Generation
