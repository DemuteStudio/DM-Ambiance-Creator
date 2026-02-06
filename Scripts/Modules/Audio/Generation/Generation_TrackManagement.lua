--[[
@version 1.0
@noindex
DM Ambiance Creator - Generation Track Management Module
Track creation, folder structure, and GUID management for generation.
--]]

local Generation_TrackManagement = {}
local globals = {}

function Generation_TrackManagement.initModule(g)
    globals = g
end

-- Create multi-channel tracks for a container
-- @param containerTrack userdata: The container track
-- @param container table: The container configuration
-- @param isLastInGroup boolean: Whether this is the last container in group
-- @return table: Array of channel tracks
function Generation_TrackManagement.createMultiChannelTracks(containerTrack, container, isLastInGroup)
    -- STEP 1: Analyze items and determine track structure FIRST
    -- This is needed to check if stereo containers need child tracks (e.g., mono split)
    local itemsAnalysis = globals.Generation.analyzeContainerItems(container)
    local trackStructure = globals.Generation.determineTrackStructure(container, itemsAnalysis)

    -- If only 1 track needed, return container track without creating children
    if trackStructure.numTracks == 1 then
        -- Set container track channel count to match requirements
        local requiredChannels = trackStructure.trackChannels
        if requiredChannels % 2 == 1 then
            requiredChannels = requiredChannels + 1
        end
        reaper.SetMediaTrackInfo_Value(containerTrack, "I_NCHAN", requiredChannels)
        return {containerTrack}
    end

    -- Get channel config (may be nil for stereo with mono split)
    local config = globals.Constants.CHANNEL_CONFIGS[container.channelMode]

    -- For non-stereo modes, validate config
    if container.channelMode and container.channelMode > 0 then
        if not config or config.channels == 0 then
            return {containerTrack}
        end
    end

    -- STEP 2: Handle configuration changes
    globals.Generation.detectAndHandleConfigurationChanges(container)

    -- Get the active configuration (with variant if applicable)
    local activeConfig = config
    if config and config.hasVariants then
        activeConfig = config.variants[container.channelVariant or 0]
    end

    local channelTracks = {}
    local numTracksToCreate = trackStructure.numTracks

    -- NEW ARCHITECTURE: Use trackStructure to determine required channels on parent
    -- The parent track must have enough channels to receive all child sends
    local requiredChannels = trackStructure.numTracks -- At minimum, need as many channels as tracks

    -- If we have labels, calculate the maximum channel number needed
    if trackStructure.trackLabels then
        local maxChannel = 0
        for i, label in ipairs(trackStructure.trackLabels) do
            local channelNum = globals.Generation.labelToChannelNumber(label, config, container.channelVariant) or i
            maxChannel = math.max(maxChannel, channelNum)
        end
        requiredChannels = math.max(requiredChannels, maxChannel)
    elseif config then
        -- Fallback: use config channels if available
        requiredChannels = config.totalChannels or config.channels or numTracksToCreate
    end

    -- If using custom routing, ensure we have enough channels for the highest channel
    if container.customRouting then
        local maxCustomChannel = 0
        for _, ch in ipairs(container.customRouting) do
            maxCustomChannel = math.max(maxCustomChannel, ch)
        end
        requiredChannels = math.max(requiredChannels, maxCustomChannel)
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
    for i = numTracksToCreate, 1, -1 do
        -- Always insert immediately after the container
        -- This ensures they're children
        reaper.InsertTrackAtIndex(containerIdx + 1, false)
    end

    -- Now configure each track
    for i = 1, numTracksToCreate do
        -- Get the track at the correct position (container + i)
        local channelTrack = reaper.GetTrack(0, containerIdx + i)

        -- Name the track
        local channelLabel = trackStructure.trackLabels and trackStructure.trackLabels[i] or ("Channel " .. i)
        local trackName = container.name .. " - " .. channelLabel
        reaper.GetSetMediaTrackInfo_String(channelTrack, "P_NAME", trackName, true)

        -- Determine track channel count based on track structure
        local trackChannelCount = trackStructure.trackChannels or 1
        reaper.SetMediaTrackInfo_Value(channelTrack, "I_NCHAN", trackChannelCount)

        -- Disable master send
        reaper.SetMediaTrackInfo_Value(channelTrack, "B_MAINSEND", 0)

        -- Create send to parent track
        local sendIdx = reaper.CreateTrackSend(channelTrack, containerTrack)
        if sendIdx >= 0 then
            -- Route to single channel (0-based)
            -- Use custom routing if available (for conflict resolution)

            -- Validate and clean customRouting if corrupted
            if container.customRouting and config then
                local expectedChannels = config.channels
                local customChannels = #container.customRouting

                -- Check if customRouting has the right number of entries
                if customChannels ~= expectedChannels then
                    -- reaper.ShowConsoleMsg(string.format("WARNING: Corrupted customRouting detected for %s - expected %d channels, got %d. Clearing customRouting.\n",
                    --     container.name or "unknown", expectedChannels, customChannels))
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
                        -- reaper.ShowConsoleMsg(string.format("WARNING: Invalid entries in customRouting for %s. Clearing customRouting.\n",
                        --     container.name or "unknown"))
                        container.customRouting = nil
                    end
                end
            end

            -- NEW ARCHITECTURE: Use trackStructure to determine routing
            local destChannel = 0 -- Default to channel 1 (0-based)

            if container.customRouting and container.customRouting[i] then
                -- Use custom routing if available (from conflict resolution)
                destChannel = container.customRouting[i] - 1

            elseif trackChannelCount == 2 and trackStructure.trackType == "stereo" then
                -- STEREO PAIRS: Route based on track position
                -- Track 1 → stereo pair 0 (channels 1-2)
                -- Track 2 → stereo pair 2 (channels 3-4)
                -- Track 3 → stereo pair 4 (channels 5-6)
                destChannel = (i - 1) * 2  -- 0-based: (track1→0, track2→2, track3→4)

            elseif trackStructure.trackLabels and trackStructure.trackLabels[i] then
                -- MONO TRACKS: Use trackStructure labels to determine proper channel routing
                local label = trackStructure.trackLabels[i]
                local channelNum = globals.Generation.labelToChannelNumber(label, config, container.channelVariant)

                if channelNum then
                    destChannel = channelNum - 1
                else
                    -- Label not found in mapping, use sequential
                    destChannel = i - 1
                end
            else
                -- Fallback: sequential routing (track 1 → ch 1, track 2 → ch 2, etc.)
                destChannel = i - 1
            end

            -- Determine source and destination channel configuration based on track type
            local srcChannels, dstChannels

            if trackChannelCount == 2 and trackStructure.trackType == "stereo" then
                -- STEREO → STEREO routing
                -- srcChannels: 0 = stereo (channels 1-2 from source)
                -- dstChannels: destChannel already calculated as stereo pair position (0, 2, 4, etc.)
                srcChannels = 0  -- Stereo from source
                dstChannels = destChannel  -- Stereo pair starting at destChannel (0-based)
            else
                -- MONO → MONO routing
                -- For mono tracks routing to single channels
                -- srcChannels: 1024 = mono mode (bit 10 set, channel 1)
                -- dstChannels: 1024 + channel number for mono routing
                srcChannels = 1024
                dstChannels = 1024 + destChannel
            end

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
        if i == numTracksToCreate then
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
            if i == numTracksToCreate then
                reaper.SetMediaTrackInfo_Value(channelTrack, "I_FOLDERDEPTH", -1)
            else
                reaper.SetMediaTrackInfo_Value(channelTrack, "I_FOLDERDEPTH", 0)
            end
        end
    end

    -- Force update to ensure proper folder structure
    reaper.UpdateArrange()
    reaper.TrackList_AdjustWindows(false)

    -- Additional refresh to ensure hierarchy is visible (suppressed during export)
    if not globals.suppressViewRefresh then
        reaper.Main_OnCommand(40031, 0) -- View: Zoom out project
        reaper.Main_OnCommand(40295, 0) -- View: Zoom to project
    end

    -- Store GUIDs for future reference
    Generation_TrackManagement.storeTrackGUIDs(container, containerTrack, channelTracks)

    return channelTracks
end

-- Get existing channel tracks for a container
-- @param containerTrack userdata: The container track
-- @return table: Array of tracks (channel tracks if multi-channel, or just the container)
function Generation_TrackManagement.getExistingChannelTracks(containerTrack)
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
function Generation_TrackManagement.getTrackGUID(track)
    if not track then return nil end
    return reaper.GetTrackGUID(track)
end

-- Find track by GUID
-- @param guid string: The track GUID
-- @return userdata: The track or nil if not found
function Generation_TrackManagement.findTrackByGUID(guid)
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
function Generation_TrackManagement.storeTrackGUIDs(container, containerTrack, channelTracks)
    -- Store container track GUID
    container.trackGUID = Generation_TrackManagement.getTrackGUID(containerTrack)

    -- Store channel track GUIDs
    container.channelTrackGUIDs = {}
    for _, track in ipairs(channelTracks) do
        table.insert(container.channelTrackGUIDs, Generation_TrackManagement.getTrackGUID(track))
    end
end

-- Find existing tracks by stored GUIDs
-- @param container table: The container with stored GUIDs
-- @return containerTrack, channelTracks: The found tracks or nil
function Generation_TrackManagement.findTracksByGUIDs(container)
    if not container.trackGUID then
        return nil, {}
    end

    -- Find container track
    local containerTrack = Generation_TrackManagement.findTrackByGUID(container.trackGUID)
    if not containerTrack then
        return nil, {}
    end

    -- Find channel tracks
    local channelTracks = {}
    if container.channelTrackGUIDs then
        for _, guid in ipairs(container.channelTrackGUIDs) do
            local track = Generation_TrackManagement.findTrackByGUID(guid)
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
function Generation_TrackManagement.restoreFolderStructure(containerTrack, channelTracks)
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
function Generation_TrackManagement.adjustFolderClosing(containerTrack, channelTracks, isLastInGroup)
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
function Generation_TrackManagement.validateMultiChannelStructure(containerTrack, expectedChannels)
    local folderDepth = reaper.GetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH")

    -- Container must be a folder
    if folderDepth ~= 1 then
        return false
    end

    -- Get existing tracks
    local tracks = Generation_TrackManagement.getExistingChannelTracks(containerTrack)

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
function Generation_TrackManagement.findChannelTracksByName(containerTrack, container)
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
function Generation_TrackManagement.clearChannelTracks(tracks)
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
function Generation_TrackManagement.getTracksForContainer(container, containerTrack)
    if container.channelMode and container.channelMode > 0 then
        -- Multi-channel mode: get child tracks
        return Generation_TrackManagement.getExistingChannelTracks(containerTrack)
    else
        -- Default mode: just the container track
        return {containerTrack}
    end
end

-- Clear items from container (unified function for both modes)
-- @param container table: The container configuration
-- @param containerTrack userdata: The container track
function Generation_TrackManagement.clearContainerItems(container, containerTrack)
    local tracks = Generation_TrackManagement.getTracksForContainer(container, containerTrack)
    for _, track in ipairs(tracks) do
        while reaper.CountTrackMediaItems(track) > 0 do
            local item = reaper.GetTrackMediaItem(track, 0)
            reaper.DeleteTrackMediaItem(track, item)
        end
    end
end

-- Delete all child tracks of a container (for mode changes)
-- @param containerTrack userdata: The container track
function Generation_TrackManagement.deleteContainerChildTracks(containerTrack)
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

-- Enhanced function to fix folder structure of a group
-- @param parentGroupIdx number: The group index
function Generation_TrackManagement.fixGroupFolderStructure(parentGroupIdx)
    -- Use the new utility function for consistency
    return globals.Utils.fixGroupFolderStructure(parentGroupIdx)
end

-- Helper function to debug folder structure (useful for troubleshooting)
-- @param groupName string: The group name
function Generation_TrackManagement.debugFolderStructure(groupName)
    local parentGroup, parentGroupIdx = globals.Utils.findGroupByName(groupName)
    if not parentGroup then
        -- reaper.ShowConsoleMsg("Group '" .. groupName .. "' not found\n")
        return
    end

    -- reaper.ShowConsoleMsg("=== Folder Structure for '" .. groupName .. "' ===\n")
    -- reaper.ShowConsoleMsg("Parent track index: " .. parentGroupIdx .. "\n")

    local containers = globals.Utils.getAllContainersInGroup(parentGroupIdx)
    for i, container in ipairs(containers) do
        -- reaper.ShowConsoleMsg("  Container " .. i .. ": '" .. container.name .. "' (index: " .. container.index .. ", depth: " .. container.originalDepth .. ")\n")
    end
    -- reaper.ShowConsoleMsg("========================\n")
end

-- Find group track robustly by name
-- @param groupName string: The group name
-- @return userdata: The group track or nil
function Generation_TrackManagement.findGroupTrackRobust(groupName)
    if not groupName then return nil end

    -- Search by name across all tracks
    local totalTracks = reaper.CountTracks(0)
    for i = 0, totalTracks - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local _, trackName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
            if trackName == groupName then
                -- reaper.ShowConsoleMsg(string.format("DEBUG: Found group '%s' at index %d\n", groupName, i))
                return track
            end
        end
    end

    -- reaper.ShowConsoleMsg(string.format("DEBUG: FAILED to find group track '%s'\n", groupName))
    return nil
end

-- Find container track by group and container name
-- @param groupName string: The group name
-- @param containerName string: The container name
-- @return userdata: The container track or nil
function Generation_TrackManagement.findContainerTrack(groupName, containerName)
    local groupTrack = Generation_TrackManagement.findGroupTrack(groupName)
    if not groupTrack then return nil end

    local groupIdx = reaper.GetMediaTrackInfo_Value(groupTrack, "IP_TRACKNUMBER") - 1
    return globals.Utils.findContainerGroup(groupIdx, containerName)
end

-- Find group track by name
-- @param groupName string: The group name
-- @return userdata: The group track or nil
function Generation_TrackManagement.findGroupTrack(groupName)
    local groupTrack, _ = globals.Utils.findGroupByName(groupName)
    return groupTrack
end

-- Detect orphaned container tracks
function Generation_TrackManagement.detectOrphanedContainerTracks()
    -- Build a set of all container names that should exist
    local validContainerNames = {}
    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if container.name then
                validContainerNames[container.name] = true
            end
        end
    end

    -- Scan all tracks to find container tracks that aren't in our tool
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local _, trackName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

            -- Check if this looks like a container track
            local hasChildren = false
            local parentTrack = reaper.GetParentTrack(track)
            if parentTrack then
                -- Check if any tracks are children of this track
                for j = 0, reaper.CountTracks(0) - 1 do
                    local childTrack = reaper.GetTrack(0, j)
                    if reaper.GetParentTrack(childTrack) == track then
                        hasChildren = true
                        break
                    end
                end
            end

            -- If track has children but no corresponding container in tool, it's orphaned
            if hasChildren and trackName and trackName ~= "" and not validContainerNames[trackName] then
                -- This is an orphaned container track - it should be ignored in calculations
                -- Mark it somehow or just skip it in getExistingChildTrackCount
                if not globals.orphanedContainers then
                    globals.orphanedContainers = {}
                end
                globals.orphanedContainers[trackName] = track
            end
        end
    end
end

return Generation_TrackManagement
