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

-- Map a channel label (L, R, C, LS, RS, etc.) to a channel number
-- Handles both ITU/Dolby and SMPTE variants, and different output formats (4.0, 5.0, 7.0)
function Generation.labelToChannelNumber(label, config, channelVariant)
    -- Determine output format
    local numChannels = config and config.channels or 2

    local labelToChannel = {}

    if numChannels == 4 then
        -- 4.0 Quad: L R LS RS (no center)
        labelToChannel = {
            ["L"] = 1, ["R"] = 2, ["LS"] = 3, ["RS"] = 4
        }
    elseif numChannels == 5 then
        -- 5.0 Surround
        if config.hasVariants and channelVariant == 1 then
            -- SMPTE: L C R LS RS
            labelToChannel = {
                ["L"] = 1, ["C"] = 2, ["R"] = 3, ["LS"] = 4, ["RS"] = 5
            }
        else
            -- ITU/Dolby: L R C LS RS
            labelToChannel = {
                ["L"] = 1, ["R"] = 2, ["C"] = 3, ["LS"] = 4, ["RS"] = 5
            }
        end
    elseif numChannels == 7 then
        -- 7.0 Surround
        if config.hasVariants and channelVariant == 1 then
            -- SMPTE: L C R LS RS LB RB
            labelToChannel = {
                ["L"] = 1, ["C"] = 2, ["R"] = 3, ["LS"] = 4, ["RS"] = 5, ["LB"] = 6, ["RB"] = 7
            }
        else
            -- ITU/Dolby: L R C LS RS LB RB
            labelToChannel = {
                ["L"] = 1, ["R"] = 2, ["C"] = 3, ["LS"] = 4, ["RS"] = 5, ["LB"] = 6, ["RB"] = 7
            }
        end
    else
        -- Default stereo or unknown: L R
        labelToChannel = {
            ["L"] = 1, ["R"] = 2
        }
    end

    return labelToChannel[label]
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

    -- STEP 1: Analyze items and determine track structure
    local itemsAnalysis = Generation.analyzeContainerItems(container)
    local trackStructure = Generation.determineTrackStructure(container, itemsAnalysis)

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

    -- STEP 2: Handle configuration changes
    Generation.detectAndHandleConfigurationChanges(container)

    -- Get the active configuration (with variant if applicable)
    local activeConfig = config
    if config.hasVariants then
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
            local channelNum = Generation.labelToChannelNumber(label, config, container.channelVariant) or i
            maxChannel = math.max(maxChannel, channelNum)
        end
        requiredChannels = math.max(requiredChannels, maxChannel)
    else
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
            if container.customRouting then
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
                local channelNum = Generation.labelToChannelNumber(label, config, container.channelVariant)

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

-- LEGACY FUNCTIONS REMOVED:
-- - detectContainerFormat() → Replaced by analyzeContainerItems() + determineTrackStructure()
-- - calculateTrackMultiplier() → Replaced by new system with determineTargetTracks()

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

    -- Analyze items and determine track structure
    local itemsAnalysis = Generation.analyzeContainerItems(container)
    local trackStructure = Generation.determineTrackStructure(container, itemsAnalysis)

    local hasChildTracks = reaper.GetMediaTrackInfo_Value(containerGroup, "I_FOLDERDEPTH") == 1
    local isLastInGroup = (containerIndex == #group.containers)
    local channelTracks = {}

    -- Get existing track structure
    local existingTracks = Generation.getExistingChannelTracks(containerGroup)
    local numExistingTracks = #existingTracks

    -- Check if structure needs to be recreated
    local needsRecreate = false

    if trackStructure.numTracks == 1 and hasChildTracks then
        -- Need single track but have children
        needsRecreate = true
    elseif trackStructure.numTracks > 1 and not hasChildTracks then
        -- Need multiple tracks but don't have children
        needsRecreate = true
    elseif trackStructure.numTracks > 1 and numExistingTracks ~= trackStructure.numTracks then
        -- Wrong number of child tracks
        needsRecreate = true
    end

    if needsRecreate then
        -- Clear existing structure
        if hasChildTracks then
            Generation.deleteContainerChildTracks(containerGroup)
        else
            -- Clear items from single track
            while reaper.CountTrackMediaItems(containerGroup) > 0 do
                local item = reaper.GetTrackMediaItem(containerGroup, 0)
                reaper.DeleteTrackMediaItem(containerGroup, item)
            end
        end

        -- Create new structure
        channelTracks = Generation.createMultiChannelTracks(containerGroup, container, isLastInGroup)
    else
        -- Structure is correct, just clear items
        if hasChildTracks then
            Generation.clearChannelTracks(existingTracks)
        else
            while reaper.CountTrackMediaItems(containerGroup) > 0 do
                local item = reaper.GetTrackMediaItem(containerGroup, 0)
                reaper.DeleteTrackMediaItem(containerGroup, item)
            end
        end
        channelTracks = existingTracks

        -- Store/update GUIDs
        if trackStructure.numTracks > 1 then
            Generation.storeTrackGUIDs(container, containerGroup, channelTracks)
        else
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

        -- Generate items considering channel count matching
        -- For multichannel containers, we need to intelligently distribute items
        local isMultiChannel = container.channelMode and container.channelMode > 0

        -- Analyze items and determine track structure for placement logic
        local itemsAnalysis = Generation.analyzeContainerItems(container)
        local trackStructure = Generation.determineTrackStructure(container, itemsAnalysis)

        -- SPECIAL CASE: Independent generation for "All Tracks" mode
        -- Must be checked BEFORE entering the main loop
        local distributionMode = container.itemDistributionMode or 0
        if trackStructure.useDistribution and distributionMode == 2 then
            -- All Tracks mode - generate independently for each track
            local needsChannelSelection = trackStructure.needsChannelSelection
            local channelSelectionMode = trackStructure.channelSelectionMode or container.channelSelectionMode or "none"

            for trackIdx, targetTrack in ipairs(channelTracks) do
                Generation.generateIndependentTrack(targetTrack, trackIdx, container, effectiveParams, channelTracks, trackStructure, needsChannelSelection, channelSelectionMode)
            end

            -- Exit completely - independent generation is done
            return
        end

        -- Reset for generation
        local lastItemRef = nil
        local isFirstItem = true
        local lastItemEnd = globals.startTime

        while lastItemEnd < globals.endTime do
            -- Select a random item from the container
            local randomItemIndex = math.random(1, #effectiveParams.items)
            local originalItemData = effectiveParams.items[randomItemIndex]

            -- Select area if available, or use full item
            local itemData = Utils.selectRandomAreaOrFullItem(originalItemData)

            -- Determine which tracks to place this item on
            local targetTracks = {channelTracks[1]} -- Default
            local itemChannels = itemData.numChannels or 2
            local needsChannelSelection = trackStructure.needsChannelSelection
            -- Use the mode from trackStructure if it was overridden by auto-optimization
            local channelSelectionMode = trackStructure.channelSelectionMode or container.channelSelectionMode or "none"

            -- Check for custom routing matrix first
            local useCustomRouting = false
            if container.customItemRouting and container.customItemRouting[randomItemIndex] then
                local customRouting = container.customItemRouting[randomItemIndex]
                if customRouting.routingMatrix and not customRouting.isAutoRouting then
                    -- Use custom routing: place item on specified tracks
                    useCustomRouting = true
                    targetTracks = {}
                    local uniqueTracks = {}
                    for srcCh, destCh in pairs(customRouting.routingMatrix) do
                        if destCh > 0 and channelTracks[destCh] and not uniqueTracks[destCh] then
                            table.insert(targetTracks, channelTracks[destCh])
                            uniqueTracks[destCh] = true
                        end
                    end
                    if #targetTracks == 0 then
                        targetTracks = {channelTracks[1]}
                    end
                end
            end

            -- If no custom routing, use automatic distribution
            local distributionMode = container.itemDistributionMode or 0

            if not useCustomRouting then
                if trackStructure.numTracks == 1 then
                    -- Single track: place item there
                    targetTracks = {channelTracks[1]}
                elseif trackStructure.useSmartRouting then
                    -- Smart routing: place on all tracks (each will extract different channel)
                    targetTracks = channelTracks
                elseif trackStructure.useDistribution then
                    -- Mono items or items that need distribution: distribute across tracks

                    if distributionMode == 0 then
                        -- Round-robin
                        if not container.distributionCounter then
                            container.distributionCounter = 0
                        end
                        container.distributionCounter = container.distributionCounter + 1
                        local targetChannel = ((container.distributionCounter - 1) % #channelTracks) + 1
                        targetTracks = {channelTracks[targetChannel]}
                    elseif distributionMode == 1 then
                        -- Random
                        local targetChannel = math.random(1, #channelTracks)
                        targetTracks = {channelTracks[targetChannel]}
                    -- distributionMode == 2 (All tracks) is handled BEFORE the main loop
                    end
                else
                    -- All other cases: use all tracks or first track
                    targetTracks = channelTracks
                end
            end
            
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

            -- Place the item on all target tracks determined by channel routing
            for trackIdx, targetTrack in ipairs(targetTracks) do
                -- Create and configure the new item on current track
                local newItem = reaper.AddMediaItemToTrack(targetTrack)
                local newTake = reaper.AddTakeToMediaItem(newItem)

                -- Configure the item
                local PCM_source = reaper.PCM_Source_CreateFromFile(itemData.filePath)
                reaper.SetMediaItemTake_Source(newTake, PCM_source)
                reaper.SetMediaItemTakeInfo_Value(newTake, "D_STARTOFFS", itemData.startOffset)

                -- Apply channel selection if needed
                if needsChannelSelection then
                    Generation.applyChannelSelection(newItem, container, itemChannels, channelSelectionMode, trackStructure, trackIdx)
                end

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

                -- Apply pan randomization for stereo items
                -- Enable for: stereo containers, OR stereo items on stereo tracks
                local canUsePan = false
                if not effectiveParams.channelMode or effectiveParams.channelMode == 0 then
                    -- Stereo container
                    canUsePan = true
                elseif trackStructure.trackType == "stereo" and trackStructure.trackChannels == 2 then
                    -- Stereo items on stereo tracks in multichannel
                    canUsePan = true
                end

                if effectiveParams.randomizePan and canUsePan then
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
                -- Only for the first target track to avoid duplicate crossfades
                if trackIdx == 1 and lastItemRef and position < lastItemEnd then
                    Utils.createCrossfade(lastItemRef, newItem, xfadeshape)
                end

                -- Update references for next iteration (only from first track)
                if trackIdx == 1 then
                    lastItemEnd = position + actualLen
                    lastItemRef = newItem
                end
            end  -- End of for loop for target tracks

            ::continue_loop::
        end  -- End of while loop

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
            
            -- reaper.ShowConsoleMsg(message .. "\n")
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

    -- MEGATHINK FIX: Complete project stabilization after generation
    -- reaper.ShowConsoleMsg("INFO: Starting project stabilization after generation...\n")

    -- Small delay to ensure all track operations are complete
    reaper.UpdateArrange()

    -- CRITICAL: Always force stabilization after generation, especially when regenerating
    -- This ensures deleted containers don't leave groups/master with excessive channels
    if not globals.skipRoutingValidation then
        if globals.keepExistingTracks then
            -- Force full stabilization when regenerating (container deletion case)
            Generation.stabilizeProjectConfiguration(false)  -- Full mode, not light
        else
            -- Normal generation - use light stabilization
            Generation.stabilizeProjectConfiguration(true)   -- Light mode
        end
    else
        -- Clear the skip flag for next time
        globals.skipRoutingValidation = false
    end

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

    -- CRITICAL: Force full stabilization after single group regeneration
    -- This handles the case where containers were deleted from the tool
    if not globals.skipRoutingValidation then
        Generation.stabilizeProjectConfiguration(false)  -- Full stabilization
    end

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
        -- reaper.ShowConsoleMsg("Group '" .. groupName .. "' not found\n")
        return
    end
    
    -- reaper.ShowConsoleMsg("=== Folder Structure for '" .. groupName .. "' ===\n")
    -- reaper.ShowConsoleMsg("Parent track index: " .. parentGroupIdx .. "\n")
    
    local containers = Utils.getAllContainersInGroup(parentGroupIdx)
    for i, container in ipairs(containers) do
        -- reaper.ShowConsoleMsg("  Container " .. i .. ": '" .. container.name .. "' (index: " .. container.index .. ", depth: " .. container.originalDepth .. ")\n")
    end
    -- reaper.ShowConsoleMsg("========================\n")
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

-- ===================================================================
-- CHANNEL OPTIMIZATION AND RECALCULATION
-- ===================================================================

-- Recalculate channel requirements bottom-up: children define parent needs
-- CRITICAL: Now uses REAL track counts, not theoretical configuration
-- ENHANCED: Detects orphaned tracks (tracks without corresponding containers)
function Generation.recalculateChannelRequirements()
    if not globals.groups or #globals.groups == 0 then
        return
    end

    -- STEP 0: Detect orphaned container tracks (tracks without matching tool containers)
    Generation.detectOrphanedContainerTracks()

    -- reaper.ShowConsoleMsg("INFO: Starting bottom-up channel recalculation (REAL tracks)...\n")

    -- Phase 1: Calculate actual requirements for each container based on REAL tracks
    local containerRequirements = {}

    for _, group in ipairs(globals.groups) do
        for _, container in ipairs(group.containers) do
            if container.channelMode and container.channelMode > 0 then
                -- Get the REAL number of child tracks
                local realChildCount = Generation.getExistingChildTrackCount(container)

                if realChildCount and realChildCount > 0 then
                    -- Use REAL count, not theoretical config
                    local requiredChannels = realChildCount

                    -- Apply REAPER even constraint
                    if requiredChannels % 2 == 1 then
                        requiredChannels = requiredChannels + 1
                    end

                    containerRequirements[container.name] = {
                        logicalChannels = realChildCount,  -- REAL count
                        physicalChannels = requiredChannels,
                        container = container,
                        group = group
                    }

                    -- reaper.ShowConsoleMsg(string.format("INFO: Container '%s' has %d REAL tracks → requires %d physical channels\n",
                    --     container.name, realChildCount, requiredChannels))
                else
                    -- Fallback to theoretical if no tracks exist yet
                    local config = globals.Constants.CHANNEL_CONFIGS[container.channelMode]
                    if config then
                        local requiredChannels = config.channels
                        if requiredChannels % 2 == 1 then
                            requiredChannels = requiredChannels + 1
                        end

                        containerRequirements[container.name] = {
                            logicalChannels = config.channels,
                            physicalChannels = requiredChannels,
                            container = container,
                            group = group
                        }

                        -- reaper.ShowConsoleMsg(string.format("INFO: Container '%s' (no tracks yet) → requires %d channels (theoretical)\n",
                        --     container.name, requiredChannels))
                    end
                end
            end
        end
    end

    -- Phase 2: Calculate requirements for each group (MAX of real container channels)
    local groupRequirements = {}

    for _, group in ipairs(globals.groups) do
        local maxChannels = 2  -- Minimum stereo
        local containerCount = 0

        for _, container in ipairs(group.containers) do
            local req = containerRequirements[container.name]
            if req then
                -- Use the REAL physical channels (based on actual tracks)
                maxChannels = math.max(maxChannels, req.physicalChannels)
                containerCount = containerCount + 1
                -- reaper.ShowConsoleMsg(string.format("    Container '%s' contributes %d physical channels\n",
                --     container.name, req.physicalChannels))
            end
        end

        groupRequirements[group.name] = {
            requiredChannels = maxChannels,
            containerCount = containerCount,
            group = group
        }

        -- reaper.ShowConsoleMsg(string.format("INFO: Group '%s' MAX requirement: %d channels for %d containers\n",
        --     group.name, maxChannels, containerCount))
    end

    -- Phase 3: Calculate master track requirement (maximum of all REAL group channels)
    local masterRequirement = 2  -- Minimum stereo

    for groupName, req in pairs(groupRequirements) do
        local oldMaster = masterRequirement
        masterRequirement = math.max(masterRequirement, req.requiredChannels)
        if req.requiredChannels > oldMaster then
            -- reaper.ShowConsoleMsg(string.format("    Group '%s' increases master requirement: %d → %d channels\n",
            --     groupName, oldMaster, masterRequirement))
        end
    end

    -- reaper.ShowConsoleMsg(string.format("INFO: Master track FINAL requirement: %d channels (based on REAL group usage)\n", masterRequirement))

    -- Phase 4: Apply the calculated requirements to actual tracks
    Generation.applyChannelRequirements(containerRequirements, groupRequirements, masterRequirement)

    -- reaper.ShowConsoleMsg("INFO: Bottom-up channel recalculation completed.\n")
end

-- Apply calculated channel requirements to actual REAPER tracks
function Generation.applyChannelRequirements(containerReqs, groupReqs, masterReq)
    reaper.Undo_BeginBlock()

    -- ULTRATHINK FIX: Update container tracks using robust finder
    for containerName, req in pairs(containerReqs) do
        local containerTrack = Generation.findContainerTrackRobust(req.container)
        if containerTrack then
            local currentChannels = reaper.GetMediaTrackInfo_Value(containerTrack, "I_NCHAN")
            if currentChannels ~= req.physicalChannels then
                -- reaper.ShowConsoleMsg(string.format("APPLY: Updating container '%s' from %d to %d channels\n",
                --     containerName, currentChannels, req.physicalChannels))

                -- Apply change with verification
                reaper.SetMediaTrackInfo_Value(containerTrack, "I_NCHAN", req.physicalChannels)

                -- MEGATHINK: Verify the change actually took effect
                local verifyChannels = reaper.GetMediaTrackInfo_Value(containerTrack, "I_NCHAN")
                if verifyChannels == req.physicalChannels then
                    -- reaper.ShowConsoleMsg(string.format("✅ APPLY SUCCESS: Container '%s' confirmed at %d channels\n",
                    --     containerName, verifyChannels))
                else
                    -- reaper.ShowConsoleMsg(string.format("❌ APPLY FAILED: Container '%s' still at %d channels (expected %d)\n",
                    --     containerName, verifyChannels, req.physicalChannels))

                    -- Force multiple attempts with UI refresh
                    for attempt = 1, 3 do
                        -- reaper.ShowConsoleMsg(string.format("MEGATHINK: Retry attempt %d for container '%s'\n", attempt, containerName))
                        reaper.SetMediaTrackInfo_Value(containerTrack, "I_NCHAN", req.physicalChannels)
                        reaper.UpdateArrange()
                        reaper.TrackList_AdjustWindows(false)
                        local retryCheck = reaper.GetMediaTrackInfo_Value(containerTrack, "I_NCHAN")
                        if retryCheck == req.physicalChannels then
                            -- reaper.ShowConsoleMsg(string.format("✅ SUCCESS on retry %d\n", attempt))
                            break
                        end
                    end
                end
            else
                -- reaper.ShowConsoleMsg(string.format("APPLY: Container '%s' already has %d channels\n",
                --     containerName, currentChannels))
            end
        else
            -- reaper.ShowConsoleMsg(string.format("APPLY: FAILED to find container track '%s'\n", containerName))
        end
    end

    -- ULTRATHINK FIX: Update group tracks using robust search
    for groupName, req in pairs(groupReqs) do
        local groupTrack = Generation.findGroupTrackRobust(groupName)
        if groupTrack then
            local currentChannels = reaper.GetMediaTrackInfo_Value(groupTrack, "I_NCHAN")
            if currentChannels ~= req.requiredChannels then
                -- reaper.ShowConsoleMsg(string.format("APPLY: Updating group '%s' from %d to %d channels\n",
                --     groupName, currentChannels, req.requiredChannels))
                reaper.SetMediaTrackInfo_Value(groupTrack, "I_NCHAN", req.requiredChannels)
            else
                -- reaper.ShowConsoleMsg(string.format("APPLY: Group '%s' already has %d channels\n",
                --     groupName, currentChannels))
            end
        else
            -- reaper.ShowConsoleMsg(string.format("APPLY: FAILED to find group track '%s'\n", groupName))
        end
    end

    -- Update master track
    local masterTrack = reaper.GetMasterTrack(0)
    if masterTrack then
        local currentChannels = reaper.GetMediaTrackInfo_Value(masterTrack, "I_NCHAN")
        if currentChannels ~= masterReq then
            -- reaper.ShowConsoleMsg(string.format("APPLY: Updating master track from %d to %d channels\n",
            --     currentChannels, masterReq))
            reaper.SetMediaTrackInfo_Value(masterTrack, "I_NCHAN", masterReq)
        else
            -- reaper.ShowConsoleMsg(string.format("APPLY: Master track already has %d channels\n", currentChannels))
        end
    end

    reaper.Undo_EndBlock("Optimize Project Channel Count", -1)
end

-- Robust group track finder
function Generation.findGroupTrackRobust(groupName)
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
function Generation.findContainerTrack(groupName, containerName)
    local groupTrack = Generation.findGroupTrack(groupName)
    if not groupTrack then return nil end

    local groupIdx = reaper.GetMediaTrackInfo_Value(groupTrack, "IP_TRACKNUMBER") - 1
    return globals.Utils.findContainerGroup(groupIdx, containerName)
end

-- Find group track by name
function Generation.findGroupTrack(groupName)
    local groupTrack, _ = globals.Utils.findGroupByName(groupName)
    return groupTrack
end

-- Handle configuration downgrades (e.g., 5.0 → 4.0)
function Generation.handleConfigurationDowngrade(container, oldChannelCount, newChannelCount)
    if newChannelCount >= oldChannelCount then
        return  -- Not a downgrade
    end

    -- reaper.ShowConsoleMsg(string.format("INFO: Handling downgrade for '%s': %d→%d channels\n",
    --     container.name or "unknown", oldChannelCount, newChannelCount))

    -- Find the container track
    local containerTrack = nil
    for _, group in ipairs(globals.groups or {}) do
        if group.containers then
            for _, cont in ipairs(group.containers) do
                if cont == container then
                    containerTrack = Generation.findContainerTrack(group.name, container.name)
                    break
                end
            end
        end
        if containerTrack then break end
    end

    if not containerTrack then
        -- reaper.ShowConsoleMsg(string.format("WARNING: Could not find track for container '%s'\n", container.name))
        return
    end

    -- Remove excess child tracks
    Generation.removeExcessChildTracks(containerTrack, oldChannelCount, newChannelCount)

    -- CRITICAL: Update container.channelMode to reflect the new configuration
    local newChannelMode = Generation.detectChannelModeFromTrackCount(newChannelCount)
    if newChannelMode then
        local oldChannelMode = container.channelMode
        container.channelMode = newChannelMode
        -- reaper.ShowConsoleMsg(string.format("INFO: Updated channelMode for '%s': %d → %d\n",
        --     container.name, oldChannelMode, newChannelMode))
    end

    -- Clear corrupted customRouting
    if container.customRouting then
        -- reaper.ShowConsoleMsg(string.format("INFO: Clearing customRouting for '%s' due to downgrade\n", container.name))
        container.customRouting = nil
    end

    -- Force regeneration to apply new routing
    container.needsRegeneration = true

    -- reaper.ShowConsoleMsg(string.format("INFO: Downgrade handling completed for '%s'\n", container.name))
end

-- Detect channelMode from track count (inverse of config lookup)
function Generation.detectChannelModeFromTrackCount(trackCount)
    -- Map track count to channelMode
    local trackCountToMode = {
        [2] = 0,  -- Default (Stereo)
        [4] = 1,  -- 4.0 Quad
        [5] = 2,  -- 5.0
        [7] = 3   -- 7.0
    }

    local newMode = trackCountToMode[trackCount]
    if newMode then
        -- reaper.ShowConsoleMsg(string.format("INFO: Detected channelMode %d for %d tracks\n", newMode, trackCount))
        return newMode
    else
        -- reaper.ShowConsoleMsg(string.format("WARNING: No channelMode mapping for %d tracks, keeping current\n", trackCount))
        return nil
    end
end

-- Remove excess child tracks during downgrade (FOLDER STRUCTURE SAFE)
function Generation.removeExcessChildTracks(containerTrack, oldChannelCount, newChannelCount)
    if not containerTrack then return end

    local tracksToRemove = oldChannelCount - newChannelCount
    if tracksToRemove <= 0 then return end

    -- reaper.ShowConsoleMsg(string.format("INFO: Safely removing %d excess child tracks (folder aware)\n", tracksToRemove))

    -- STEP 1: Find all direct children of the container
    local childTracks = {}
    local totalTracks = reaper.CountTracks(0)

    for i = 0, totalTracks - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local parent = reaper.GetParentTrack(track)
            if parent == containerTrack then
                table.insert(childTracks, {
                    track = track,
                    index = i,
                    depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
                })
            end
        end
    end

    -- reaper.ShowConsoleMsg(string.format("INFO: Found %d child tracks before removal\n", #childTracks))

    if #childTracks ~= oldChannelCount then
        -- reaper.ShowConsoleMsg(string.format("WARNING: Expected %d children, found %d\n", oldChannelCount, #childTracks))
    end

    -- STEP 2: Determine which tracks to keep and which to remove
    local tracksToKeep = newChannelCount
    local tracksToDelete = {}

    -- Remove from the end (last tracks first)
    for i = #childTracks, tracksToKeep + 1, -1 do
        table.insert(tracksToDelete, childTracks[i])
    end

    -- reaper.ShowConsoleMsg(string.format("INFO: Will remove %d tracks, keep %d tracks\n", #tracksToDelete, tracksToKeep))

    -- STEP 3: CRITICAL - Adjust folder structure BEFORE removing tracks
    if tracksToKeep > 0 and #childTracks >= tracksToKeep then
        local newLastChild = childTracks[tracksToKeep]
        -- reaper.ShowConsoleMsg(string.format("INFO: Setting new last child (index %d) to I_FOLDERDEPTH = -1\n",
        --     newLastChild.index))
        reaper.SetMediaTrackInfo_Value(newLastChild.track, "I_FOLDERDEPTH", -1)
    end

    -- STEP 4: Remove tracks in reverse order to avoid index shifts
    for i = #tracksToDelete, 1, -1 do
        local trackInfo = tracksToDelete[i]
        -- reaper.ShowConsoleMsg(string.format("INFO: Removing child track at index %d (depth was %d)\n",
        --     trackInfo.index, trackInfo.depth))
        reaper.DeleteTrack(trackInfo.track)
    end

    -- STEP 5: Validate folder structure after removal
    Generation.validateFolderStructure(containerTrack, newChannelCount)
end

-- Validate that folder structure is correct after track removal
function Generation.validateFolderStructure(containerTrack, expectedChildren)
    local containerDepth = reaper.GetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH")

    if containerDepth ~= 1 then
        -- reaper.ShowConsoleMsg(string.format("WARNING: Container lost folder status (depth = %d, should be 1)\n", containerDepth))
        reaper.SetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH", 1)
    end

    -- Count remaining children
    local actualChildren = 0
    local totalTracks = reaper.CountTracks(0)
    local lastChild = nil

    for i = 0, totalTracks - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local parent = reaper.GetParentTrack(track)
            if parent == containerTrack then
                actualChildren = actualChildren + 1
                lastChild = track
            end
        end
    end

    -- reaper.ShowConsoleMsg(string.format("VALIDATE: Expected %d children, found %d children\n",
    --     expectedChildren, actualChildren))

    -- Ensure last child closes the folder
    if lastChild then
        local lastDepth = reaper.GetMediaTrackInfo_Value(lastChild, "I_FOLDERDEPTH")
        if lastDepth ~= -1 then
            -- reaper.ShowConsoleMsg("VALIDATE: Correcting last child folder depth to -1\n")
            reaper.SetMediaTrackInfo_Value(lastChild, "I_FOLDERDEPTH", -1)
        end
    end

    if actualChildren == expectedChildren then
        -- reaper.ShowConsoleMsg("VALIDATE: ✅ Folder structure is correct\n")
    else
        -- reaper.ShowConsoleMsg("VALIDATE: ❌ Folder structure mismatch\n")
    end
end

-- Detect configuration changes and handle them appropriately
function Generation.detectAndHandleConfigurationChanges(container)
    if not container.channelMode then
        return  -- No configuration
    end

    -- ULTRATHINK FIX: Store and compare previous channelMode
    local currentChannelMode = container.channelMode
    local previousChannelMode = container.previousChannelMode

    -- Store current as previous for next time
    container.previousChannelMode = currentChannelMode

    if currentChannelMode == 0 then
        return  -- No multi-channel configuration
    end

    local config = globals.Constants.CHANNEL_CONFIGS[currentChannelMode]
    if not config then return end

    local newChannelCount = config.channels

    -- Get real track count
    local realTrackCount = Generation.getExistingChildTrackCount(container)

    -- reaper.ShowConsoleMsg(string.format("DEBUG: Container '%s' - channelMode: %s→%d, config channels: %d, real tracks: %s\n",
    --     container.name or "unknown",
    --     previousChannelMode and tostring(previousChannelMode) or "nil",
    --     currentChannelMode,
    --     newChannelCount,
    --     realTrackCount and tostring(realTrackCount) or "nil"))

    -- Detect changes based on previousChannelMode
    if previousChannelMode and previousChannelMode ~= currentChannelMode then
        -- User changed channelMode in UI
        local previousConfig = globals.Constants.CHANNEL_CONFIGS[previousChannelMode]
        if previousConfig then
            local oldChannelCount = previousConfig.channels

            if oldChannelCount > newChannelCount then
                -- TRUE DOWNGRADE DETECTED
                -- reaper.ShowConsoleMsg(string.format("INFO: TRUE DOWNGRADE: %s changed %d.0→%d.0 (%d→%d channels)\n",
                --     container.name or "unknown", oldChannelCount, newChannelCount, oldChannelCount, newChannelCount))

                Generation.propagateConfigurationDowngrade(oldChannelCount, newChannelCount, currentChannelMode)

                -- MEGATHINK FIX: Force complete stabilization after downgrade
                -- reaper.ShowConsoleMsg("INFO: Starting complete project stabilization after downgrade...\n")
                reaper.UpdateArrange()

                -- Clear skip flag before stabilization
                globals.skipRoutingValidation = false

                -- Run fix-point stabilization until convergence
                Generation.stabilizeProjectConfiguration()

            elseif oldChannelCount < newChannelCount then
                -- TRUE UPGRADE DETECTED
                -- reaper.ShowConsoleMsg(string.format("INFO: TRUE UPGRADE: %s changed %d.0→%d.0 (%d→%d channels)\n",
                --     container.name or "unknown", oldChannelCount, newChannelCount, oldChannelCount, newChannelCount))
                -- Normal creation will handle upgrades
            end
        end
    else
        -- No channelMode change, check for track count mismatch
        if realTrackCount and realTrackCount ~= newChannelCount then
            -- reaper.ShowConsoleMsg(string.format("INFO: Track mismatch for '%s': has %d tracks but should have %d\n",
            --     container.name or "unknown", realTrackCount, newChannelCount))
        end
    end
end

-- Propagate configuration downgrades to ALL containers of the same type
function Generation.propagateConfigurationDowngrade(oldChannelCount, newChannelCount, channelModeType)
    local affectedContainers = {}

    -- Find ALL containers with the same channel mode
    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if container.channelMode == channelModeType then
                local currentChildCount = Generation.getExistingChildTrackCount(container)
                if currentChildCount and currentChildCount == oldChannelCount then
                    table.insert(affectedContainers, {
                        container = container,
                        group = group,
                        currentChildCount = currentChildCount
                    })
                end
            end
        end
    end

    -- reaper.ShowConsoleMsg(string.format("INFO: Found %d containers to downgrade\n", #affectedContainers))

    -- Apply downgrade to ALL affected containers
    for _, info in ipairs(affectedContainers) do
        Generation.handleConfigurationDowngrade(info.container, oldChannelCount, newChannelCount)
        -- reaper.ShowConsoleMsg(string.format("INFO: Downgraded container '%s' in group '%s'\n",
        --     info.container.name or "unknown", info.group.name or "unknown"))
    end

    -- CRITICAL: Set a flag to prevent RoutingValidator from "fixing" during this operation
    globals.skipRoutingValidation = true

    -- Clear RoutingValidator cache to force fresh validation next time
    if globals.RoutingValidator and globals.RoutingValidator.clearValidation then
        globals.RoutingValidator.clearValidation()
    end

    -- reaper.ShowConsoleMsg(string.format("INFO: Propagation complete. %d containers processed.\n", #affectedContainers))

    -- REGRESSION FIX: Clear skip flag immediately after propagation
    -- This allows validation to detect other containers with bad routing
    globals.skipRoutingValidation = false
    -- reaper.ShowConsoleMsg("INFO: Propagation finished - validation re-enabled to catch other issues\n")
end

-- Get the current number of child tracks for a container
function Generation.getExistingChildTrackCount(container)
    -- ULTRATHINK FIX: Use more robust track finding
    local containerTrack = Generation.findContainerTrackRobust(container)

    if not containerTrack then
        -- reaper.ShowConsoleMsg(string.format("DEBUG: Could not find container track for '%s'\n", container.name or "unknown"))
        return nil
    end

    -- Count direct children using REAPER's direct parent-child relationship
    local childCount = 0
    local totalTracks = reaper.CountTracks(0)

    for i = 0, totalTracks - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local parent = reaper.GetParentTrack(track)
            if parent == containerTrack then
                childCount = childCount + 1
            end
        end
    end

    -- reaper.ShowConsoleMsg(string.format("DEBUG: Container '%s' has %d direct children\n",
    --     container.name or "unknown", childCount))

    return childCount
end

-- Robust container track finder that actually works
function Generation.findContainerTrackRobust(container)
    local containerName = container.name
    if not containerName then return nil end

    -- Method 1: Use stored GUID if available
    if container.trackGUID then
        local track = reaper.BR_GetMediaTrackByGUID(0, container.trackGUID)
        if track then
            -- reaper.ShowConsoleMsg(string.format("DEBUG: Found container '%s' by GUID\n", containerName))
            return track
        end
    end

    -- Method 2: Search by name across all tracks
    local totalTracks = reaper.CountTracks(0)
    for i = 0, totalTracks - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local _, trackName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
            if trackName == containerName then
                -- reaper.ShowConsoleMsg(string.format("DEBUG: Found container '%s' by name at index %d\n",
                --     containerName, i))
                return track
            end
        end
    end

    -- reaper.ShowConsoleMsg(string.format("DEBUG: FAILED to find container track '%s'\n", containerName))
    return nil
end

-- ===================================================================
-- FIX-POINT STABILIZATION SYSTEM
-- ===================================================================

-- Stabilize project configuration until convergence (Fix-Point approach)
function Generation.stabilizeProjectConfiguration(lightMode)
    local maxIterations = lightMode and 2 or 5  -- Light mode: fewer iterations
    local iteration = 0
    local hasChanges = true

    -- reaper.ShowConsoleMsg(string.format("INFO: Starting %s fix-point stabilization...\n", lightMode and "light" or "full"))

    while hasChanges and iteration < maxIterations do
        iteration = iteration + 1
        -- reaper.ShowConsoleMsg(string.format("INFO: Stabilization iteration %d/%d\n", iteration, maxIterations))

        -- Capture project state before changes
        local startState = Generation.captureProjectState()

        -- Recalculate channel requirements bottom-up
        -- reaper.ShowConsoleMsg("  → Recalculating channel requirements...\n")
        Generation.recalculateChannelRequirements()

        -- Capture project state after changes
        local endState = Generation.captureProjectState()

        -- Check if anything changed
        hasChanges = not Generation.compareProjectStates(startState, endState)

        if hasChanges then
            -- reaper.ShowConsoleMsg(string.format("  → Changes detected, continuing iteration %d\n", iteration + 1))
        else
            -- reaper.ShowConsoleMsg("  → No changes detected, system is stable!\n")
        end

        -- Force update REAPER display between iterations
        reaper.UpdateArrange()
    end

    if iteration >= maxIterations and hasChanges then
        -- reaper.ShowConsoleMsg("WARNING: Stabilization reached max iterations, may not be fully stable\n")
    else
        -- reaper.ShowConsoleMsg(string.format("SUCCESS: Project stabilized after %d iterations\n", iteration))
    end

    -- CRITICAL: Validate and resolve routing conflicts AFTER stabilization is complete
    -- This ensures fixes are not overwritten by recalculation iterations
    Generation.checkAndResolveConflicts()

    return not hasChanges  -- Return true if fully stabilized
end

-- Detect orphaned container tracks that no longer have corresponding containers in the tool
-- This is critical for handling cases where containers were deleted from the tool
function Generation.detectOrphanedContainerTracks()
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

-- Capture current project state for comparison
function Generation.captureProjectState()
    local state = {
        containerChannels = {},
        groupChannels = {},
        masterChannels = 0
    }

    -- Capture all container track channel counts
    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if container.name then
                local containerTrack = Generation.findContainerTrackRobust(container)
                if containerTrack then
                    state.containerChannels[container.name] = reaper.GetMediaTrackInfo_Value(containerTrack, "I_NCHAN")
                end
            end
        end

        -- Capture group track channel count
        if group.name then
            local groupTrack = Generation.findGroupTrackRobust(group.name)
            if groupTrack then
                state.groupChannels[group.name] = reaper.GetMediaTrackInfo_Value(groupTrack, "I_NCHAN")
            end
        end
    end

    -- Capture master track channels
    local masterTrack = reaper.GetMasterTrack(0)
    if masterTrack then
        state.masterChannels = reaper.GetMediaTrackInfo_Value(masterTrack, "I_NCHAN")
    end

    return state
end

-- Compare two project states to detect changes
function Generation.compareProjectStates(state1, state2)
    if not state1 or not state2 then return false end

    -- Compare master channels
    if state1.masterChannels ~= state2.masterChannels then
        -- reaper.ShowConsoleMsg(string.format("  State change: Master %d → %d\n",
        --     state1.masterChannels, state2.masterChannels))
        return false
    end

    -- Compare container channels
    for name, channels1 in pairs(state1.containerChannels) do
        local channels2 = state2.containerChannels[name]
        if channels1 ~= channels2 then
            -- reaper.ShowConsoleMsg(string.format("  State change: Container '%s' %d → %d\n",
            --     name, channels1, channels2 or 0))
            return false
        end
    end

    -- Compare group channels
    for name, channels1 in pairs(state1.groupChannels) do
        local channels2 = state2.groupChannels[name]
        if channels1 ~= channels2 then
            -- reaper.ShowConsoleMsg(string.format("  State change: Group '%s' %d → %d\n",
            --     name, channels1, channels2 or 0))
            return false
        end
    end

    return true  -- No changes detected
end

-- Centralized routing validation and issue resolution
-- Call this from any generation function
function Generation.checkAndResolveConflicts()
    -- Use the new RoutingValidator module for comprehensive validation
    if not globals.RoutingValidator then
        return  -- Module not initialized
    end

    -- CRITICAL: Clear cache before validation to ensure fresh scan after generation
    globals.RoutingValidator.clearCache()

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
                globals.RoutingValidator.clearCache()  -- Force fresh scan
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

-- ═══════════════════════════════════════════════════════════════════════════════
-- INDEPENDENT TRACK GENERATION (for "All Tracks" distribution mode)
-- ═══════════════════════════════════════════════════════════════════════════════

-- Apply randomization (pitch, volume, pan) to an item
function Generation.applyRandomization(newItem, newTake, effectiveParams, itemData, trackStructure)
    -- Apply pitch randomization
    if effectiveParams.randomizePitch then
        local randomPitch = itemData.originalPitch + Utils.randomInRange(effectiveParams.pitchRange.min, effectiveParams.pitchRange.max)
        reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", randomPitch)
    else
        reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", itemData.originalPitch)
    end

    -- Apply volume randomization
    if effectiveParams.randomizeVolume then
        local randomVolume = itemData.originalVolume * 10^(Utils.randomInRange(effectiveParams.volumeRange.min, effectiveParams.volumeRange.max) / 20)
        reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", randomVolume)
    else
        reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", itemData.originalVolume)
    end

    -- Apply pan randomization (only for stereo contexts)
    local canUsePan = false
    if not effectiveParams.channelMode or effectiveParams.channelMode == 0 then
        -- Stereo container
        canUsePan = true
    elseif trackStructure and trackStructure.trackType == "stereo" and trackStructure.trackChannels == 2 then
        -- Stereo items on stereo tracks in multichannel
        canUsePan = true
    end

    if effectiveParams.randomizePan and canUsePan then
        local randomPan = itemData.originalPan + Utils.randomInRange(effectiveParams.panRange.min, effectiveParams.panRange.max) / 100
        randomPan = math.max(-1, math.min(1, randomPan))
        -- Use envelope instead of directly modifying the property
        Items.createTakePanEnvelope(newTake, randomPan)
    end
end

-- Apply fade in/out to an item
function Generation.applyFades(newItem, effectiveParams, actualLen)
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
end

-- Calculate interval based on the selected mode
function Generation.calculateInterval(effectiveParams)
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
    end

    return interval
end

-- Generate items independently for a single track in "All Tracks" mode
-- Each track gets its own timeline with independent intervals, drift, and randomization
function Generation.generateIndependentTrack(targetTrack, trackIdx, container, effectiveParams, channelTracks, trackStructure, needsChannelSelection, channelSelectionMode)
    if not container.items or #container.items == 0 then
        return
    end

    local interval = Generation.calculateInterval(effectiveParams)
    local lastItemEnd = globals.startTime
    local isFirstItem = true
    local itemCount = 0
    local maxItems = 10000  -- Safety limit to prevent infinite loops

    -- Independent generation loop for this track
    while lastItemEnd < globals.endTime and itemCount < maxItems do
        itemCount = itemCount + 1
        -- Select a random item from the container
        local randomItemIndex = math.random(1, #effectiveParams.items)
        local originalItemData = effectiveParams.items[randomItemIndex]

        -- Select area if available, or use full item
        local itemData = Utils.selectRandomAreaOrFullItem(originalItemData)
        local itemChannels = itemData.numChannels or 2

        -- Vérification pour les intervalles négatifs
        if interval < 0 then
            local requiredLength = math.abs(interval)
            if itemData.length < requiredLength then
                -- Item trop court, avancer légèrement
                lastItemEnd = lastItemEnd + 0.1
                goto continue_independent_loop
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

        -- Create and configure the new item on this track
        local newItem = reaper.AddMediaItemToTrack(targetTrack)
        local newTake = reaper.AddTakeToMediaItem(newItem)

        -- Configure the item
        local PCM_source = reaper.PCM_Source_CreateFromFile(itemData.filePath)
        reaper.SetMediaItemTake_Source(newTake, PCM_source)
        reaper.SetMediaItemTakeInfo_Value(newTake, "D_STARTOFFS", itemData.startOffset)

        -- Apply channel selection if needed
        if needsChannelSelection then
            Generation.applyChannelSelection(newItem, container, itemChannels, channelSelectionMode, trackStructure, trackIdx)
        end

        -- Trim item so it never exceeds the selection end
        local maxLen = globals.endTime - position
        local actualLen = math.min(itemData.length, maxLen)

        reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", position)
        reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH", actualLen)
        reaper.GetSetMediaItemTakeInfo_String(newTake, "P_NAME", itemData.name, true)

        -- Apply randomization (pitch, volume, pan)
        Generation.applyRandomization(newItem, newTake, effectiveParams, itemData, trackStructure)

        -- Apply fades if enabled
        if effectiveParams.fadeInEnabled or effectiveParams.fadeOutEnabled then
            Generation.applyFades(newItem, effectiveParams, actualLen)
        end

        -- Update end time for next item
        lastItemEnd = position + actualLen

        -- Safety: ensure minimum progression to prevent infinite loops
        if actualLen <= 0 then
            lastItemEnd = lastItemEnd + 0.01
        end

        -- Recalculate interval for next iteration
        interval = Generation.calculateInterval(effectiveParams)

        ::continue_independent_loop::
    end

    -- Debug warning if we hit the safety limit
    if itemCount >= maxItems then
        reaper.ShowConsoleMsg("WARNING: Independent track generation hit safety limit of " .. maxItems .. " items\n")
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- NEW MULTICHANNEL SYSTEM - Analysis, Decision & Execution Functions
-- ═══════════════════════════════════════════════════════════════════════════════

-- Apply channel selection (downmix/split) to an item via REAPER actions
-- @param item userdata: The media item to apply channel selection to
-- @param container table: Container configuration
-- @param itemChannels number: Number of channels in the item
-- @param channelSelectionMode string: "none", "stereo", or "mono"
-- @param trackStructure table: Track structure (optional, for auto-forced values)
-- @param trackIdx number: Track index (1-based) for smart routing
function Generation.applyChannelSelection(item, container, itemChannels, channelSelectionMode, trackStructure, trackIdx)
    if not item or not container then return end

    -- Select the item for applying actions
    reaper.SelectAllMediaItems(0, false)
    reaper.SetMediaItemSelected(item, true)

    if channelSelectionMode == "stereo" then
        -- Stereo pair selection
        -- Priority: trackStructure value (auto-forced) > container value (user choice)
        local stereoPairSelection = (trackStructure and trackStructure.stereoPairSelection) or container.stereoPairSelection or 0

        -- Apply stereo downmix action based on pair index
        if stereoPairSelection == 0 then
            reaper.Main_OnCommand(41450, 0) -- Channels 1-2 (L/R)
        elseif stereoPairSelection == 1 then
            reaper.Main_OnCommand(41452, 0) -- Channels 3-4 (LS/RS or C/LFE)
        elseif stereoPairSelection == 2 then
            reaper.Main_OnCommand(41454, 0) -- Channels 5-6
        elseif stereoPairSelection == 3 then
            reaper.Main_OnCommand(41456, 0) -- Channels 7-8
        end

    elseif channelSelectionMode == "mono" then
        -- Mono channel selection
        -- Priority: trackStructure value (auto-forced) > container value (user choice)
        local monoChannelSelection = (trackStructure and trackStructure.monoChannelSelection) or container.monoChannelSelection or itemChannels

        -- Special case: Smart routing for surround items with known center position
        if trackStructure and trackStructure.useSmartRouting then
            -- Smart routing: Extract specific channel based on track index and source variant
            -- For 5.0: L R C LS RS (ITU) or L C R LS RS (SMPTE)
            -- For 7.0: L R C LS RS LB RB (ITU) or L C R LS RS LB RB (SMPTE)
            -- Target: 4 tracks = L, R, LS, RS (skip center)

            local sourceChannelVariant = trackStructure.sourceChannelVariant or container.sourceChannelVariant or 0
            local sourceChannel = 0  -- 0-based channel index

            if itemChannels == 5 then
                -- 5.0 surround
                if sourceChannelVariant == 0 then
                    -- ITU/Dolby: L(0) R(1) C(2) LS(3) RS(4)
                    local channelMap = {0, 1, 3, 4}  -- L, R, LS, RS (skip C at index 2)
                    sourceChannel = channelMap[trackIdx] or 0
                else
                    -- SMPTE: L(0) C(1) R(2) LS(3) RS(4)
                    local channelMap = {0, 2, 3, 4}  -- L, R, LS, RS (skip C at index 1)
                    sourceChannel = channelMap[trackIdx] or 0
                end
            elseif itemChannels == 7 then
                -- 7.0 surround
                if sourceChannelVariant == 0 then
                    -- ITU/Dolby: L(0) R(1) C(2) LS(3) RS(4) LB(5) RB(6)
                    local channelMap = {0, 1, 3, 4}  -- L, R, LS, RS (skip C, LB, RB)
                    sourceChannel = channelMap[trackIdx] or 0
                else
                    -- SMPTE: L(0) C(1) R(2) LS(3) RS(4) LB(5) RB(6)
                    local channelMap = {0, 2, 3, 4}  -- L, R, LS, RS (skip C, LB, RB)
                    sourceChannel = channelMap[trackIdx] or 0
                end
            end

            -- Apply mono channel selection action based on source channel (0-based)
            if sourceChannel == 0 then
                reaper.Main_OnCommand(40179, 0) -- Mono channel 1 (left)
            elseif sourceChannel == 1 then
                reaper.Main_OnCommand(40180, 0) -- Mono channel 2 (right)
            elseif sourceChannel == 2 then
                reaper.Main_OnCommand(41388, 0) -- Mono channel 3
            elseif sourceChannel == 3 then
                reaper.Main_OnCommand(41389, 0) -- Mono channel 4
            elseif sourceChannel == 4 then
                reaper.Main_OnCommand(41390, 0) -- Mono channel 5
            elseif sourceChannel == 5 then
                reaper.Main_OnCommand(41391, 0) -- Mono channel 6
            elseif sourceChannel == 6 then
                reaper.Main_OnCommand(41392, 0) -- Mono channel 7
            elseif sourceChannel == 7 then
                reaper.Main_OnCommand(41393, 0) -- Mono channel 8
            end
        else
            -- Normal mono channel selection
            -- Check if random mode (index >= itemChannels means Random)
            local selectedChannel = monoChannelSelection
            if selectedChannel >= itemChannels then
                -- Random: choose random channel (0-based)
                selectedChannel = math.random(0, itemChannels - 1)
            end

            -- Apply mono channel selection action based on channel index (0-based)
            if selectedChannel == 0 then
                reaper.Main_OnCommand(40179, 0) -- Mono channel 1 (left)
            elseif selectedChannel == 1 then
                reaper.Main_OnCommand(40180, 0) -- Mono channel 2 (right)
            elseif selectedChannel == 2 then
                reaper.Main_OnCommand(41388, 0) -- Mono channel 3
            elseif selectedChannel == 3 then
                reaper.Main_OnCommand(41389, 0) -- Mono channel 4
            elseif selectedChannel == 4 then
                reaper.Main_OnCommand(41390, 0) -- Mono channel 5
            elseif selectedChannel == 5 then
                reaper.Main_OnCommand(41391, 0) -- Mono channel 6
            elseif selectedChannel == 6 then
                reaper.Main_OnCommand(41392, 0) -- Mono channel 7
            elseif selectedChannel == 7 then
                reaper.Main_OnCommand(41393, 0) -- Mono channel 8
            end
        end
    end

    -- Deselect the item
    reaper.SetMediaItemSelected(item, false)
end

-- Get output channel count from channel mode
-- @param channelMode number: Channel mode (0=Stereo, 1=Quad, 2=5.0, 3=7.0)
-- @return number: Number of output channels
function Generation.getOutputChannelCount(channelMode)
    if not channelMode or channelMode == 0 then
        return 2  -- Stereo
    end

    local config = globals.Constants.CHANNEL_CONFIGS[channelMode]
    if not config then
        return 2  -- Fallback to stereo
    end

    return config.channels or 2
end

-- Analyze container items to understand channel configuration
-- Pure function with no side effects
-- @param container table: The container to analyze
-- @return table: Analysis result with channel information
function Generation.analyzeContainerItems(container)
    -- Default result for empty container
    if not container.items or #container.items == 0 then
        return {
            isEmpty = true,
            isHomogeneous = true,
            dominantChannelCount = 2,
            uniqueChannelCounts = {},
            totalItems = 0
        }
    end

    -- Count channel occurrences
    local channelCounts = {}
    for _, item in ipairs(container.items) do
        local ch = item.numChannels or 2
        channelCounts[ch] = (channelCounts[ch] or 0) + 1
    end

    -- Get unique channel counts
    local uniqueChannels = {}
    for ch, _ in pairs(channelCounts) do
        table.insert(uniqueChannels, ch)
    end

    -- Sort for consistency
    table.sort(uniqueChannels)

    -- Find dominant channel count (most frequent)
    local dominantChannel = uniqueChannels[1]
    local maxCount = 0
    for ch, count in pairs(channelCounts) do
        if count > maxCount then
            maxCount = count
            dominantChannel = ch
        end
    end

    return {
        isEmpty = false,
        isHomogeneous = (#uniqueChannels == 1),
        dominantChannelCount = dominantChannel,
        uniqueChannelCounts = uniqueChannels,
        totalItems = #container.items,
        channelCounts = channelCounts
    }
end

-- Generate stereo pair labels based on item channels
-- @param itemChannels number: Number of channels in items
-- @param numPairs number: Number of stereo pairs to generate
-- @return table: Array of label strings
function Generation.generateStereoPairLabels(itemChannels, numPairs)
    local labels = {}

    if itemChannels == 4 and numPairs == 2 then
        return {"L+R", "LS+RS"}
    elseif itemChannels == 6 and numPairs == 3 then
        return {"L+R", "C+LFE", "LS+RS"}
    elseif itemChannels == 8 and numPairs == 4 then
        return {"L+R", "C+LFE", "LS+RS", "LB+RB"}
    else
        -- Generic labels
        for i = 1, numPairs do
            local ch1 = (i-1)*2 + 1
            local ch2 = i*2
            labels[i] = "Ch" .. ch1 .. "+" .. ch2
        end
    end

    return labels
end

-- Auto-optimization logic when channelSelectionMode = "none"
-- @param container table: Container configuration
-- @param itemsAnalysis table: Result from analyzeContainerItems
-- @param outputChannels number: Target output channel count
-- @return table: Track structure description
function Generation.determineAutoOptimization(container, itemsAnalysis, outputChannels)
    local itemCh = itemsAnalysis.dominantChannelCount

    -- ──────────────────────────────────────────────────────────
    -- CAS A : Stereo items (2ch) dans Quad/5.0/7.0
    -- ──────────────────────────────────────────────────────────
    if itemCh == 2 and outputChannels >= 4 then
        if outputChannels == 4 then
            return {
                strategy = "auto-stereo-pairs-quad",
                numTracks = 2,
                trackType = "stereo",
                trackChannels = 2,
                trackLabels = {"L+R", "LS+RS"},
                needsChannelSelection = false,
                useDistribution = true
            }
        else  -- 5.0 or 7.0
            return {
                strategy = "auto-stereo-pairs-surround",
                numTracks = 2,
                trackType = "stereo",
                trackChannels = 2,
                trackLabels = {"L+R", "LS+RS"},
                needsChannelSelection = false,
                useDistribution = true
            }
        end
    end

    -- ──────────────────────────────────────────────────────────
    -- CAS B : 4.0 items dans 5.0/7.0
    -- ──────────────────────────────────────────────────────────
    if itemCh == 4 and outputChannels >= 5 then
        return {
            strategy = "auto-4ch-in-surround",
            numTracks = 4,
            trackType = "mono",
            trackChannels = 1,
            trackLabels = {"L", "R", "LS", "RS"},
            needsChannelSelection = false,
            needsRouting = true,
            routingMap = {1, 2, 4, 5},  -- Skip center (channel 3)
        }
    end

    -- ──────────────────────────────────────────────────────────
    -- CAS C : Items > Output → Auto downmix intelligent
    -- ──────────────────────────────────────────────────────────
    if itemCh > outputChannels then
        -- Cas spécial : 5.0/7.0 items avec source variant connu → Smart routing vers 4.0/Stereo
        if (itemCh == 5 or itemCh == 7) and container.sourceChannelVariant ~= nil then
            -- L'utilisateur a spécifié où est le center, on peut faire du routing intelligent
            if outputChannels == 4 then
                -- 5.0/7.0 → 4.0 : Map L/R/LS/RS (skip center)
                return {
                    strategy = "surround-to-quad-skip-center",
                    numTracks = 4,
                    trackType = "mono",
                    trackChannels = 1,
                    trackLabels = {"L", "R", "LS", "RS"},
                    needsChannelSelection = true,
                    channelSelectionMode = "mono",
                    useSmartRouting = true,
                    sourceChannelVariant = container.sourceChannelVariant,
                    warning = string.format(
                        "Items have %d channels, mapping to 4.0 (skipping center channel).",
                        itemCh
                    )
                }
            elseif outputChannels == 2 then
                -- 5.0/7.0 → Stereo : Downmix L/R only (skip center + surrounds)
                return {
                    strategy = "surround-to-stereo-front-only",
                    numTracks = 1,
                    trackType = "stereo",
                    trackChannels = 2,
                    needsChannelSelection = true,
                    channelSelectionMode = "stereo",
                    stereoPairSelection = 0,  -- Force Ch1-2 (L/R front)
                    warning = string.format(
                        "Items have %d channels, using front L/R only (skipping center and surrounds).",
                        itemCh
                    )
                }
            end
        end

        -- Cas spécial : 4.0 items → Stereo/4.0 (pairs)
        if itemCh == 4 and outputChannels == 2 then
            -- 4.0 → Stereo : Downmix automatique vers Ch1-2
            return {
                strategy = "auto-downmix-stereo",
                numTracks = 1,
                trackType = "stereo",
                trackChannels = 2,
                needsChannelSelection = true,
                channelSelectionMode = "stereo",
                stereoPairSelection = 0,  -- Force Ch1-2 (L/R)
                itemsGoDirectly = true,
                warning = "Items have 4 channels but output is stereo. Auto-downmixing to channels 1-2 (L/R)."
            }
        end

        -- Cas spécial : Items pairs (6, 8) → Stereo
        if outputChannels == 2 and itemCh % 2 == 0 then
            -- Items avec channels pairs → Downmix stereo automatique vers Ch1-2
            return {
                strategy = "auto-downmix-stereo",
                numTracks = 1,
                trackType = "stereo",
                trackChannels = 2,
                needsChannelSelection = true,
                channelSelectionMode = "stereo",
                stereoPairSelection = 0,  -- Force Ch1-2 (L/R)
                itemsGoDirectly = true,
                warning = string.format(
                    "Items have %d channels but output is stereo. Auto-downmixing to channels 1-2 (L/R).",
                    itemCh
                )
            }
        end

        -- Cas général : 5.0/7.0 sans variant connu → Downmix mono avec warning
        if (itemCh == 5 or itemCh == 7) and container.sourceChannelVariant == nil then
            local targetChannels = outputChannels == 2 and "stereo" or (outputChannels .. ".0")
            return {
                strategy = "surround-unknown-format",
                numTracks = 1,
                trackType = "multi",
                trackChannels = outputChannels,
                needsChannelSelection = true,
                channelSelectionMode = "mono",
                monoChannelSelection = 0,  -- Force channel 1
                warning = string.format(
                    "Items have %d channels but output is %s. Using channel 1 only.\n" ..
                    "To enable smart routing (skip center), specify the source format below.",
                    itemCh, targetChannels
                ),
                needsSourceVariant = true  -- Flag to show source format dropdown
            }
        end

        -- Cas général : Downmix vers channel 1
        return {
            strategy = "auto-downmix-to-first",
            numTracks = 1,
            trackType = "multi",
            trackChannels = outputChannels,
            needsChannelSelection = true,
            channelSelectionMode = "mono",
            monoChannelSelection = 0,  -- Force channel 1
            warning = string.format(
                "Items have %d channels but output is %d channels. Using channel 1 only. " ..
                "Consider using 'Channel Selection: Mono' or 'Channel Selection: Stereo' for more control.",
                itemCh, outputChannels
            )
        }
    end

    -- ──────────────────────────────────────────────────────────
    -- CAS D : Autres cas → Structure multi-channel standard
    -- ──────────────────────────────────────────────────────────
    return {
        strategy = "auto-default",
        numTracks = outputChannels,
        trackType = "mono",
        trackChannels = 1,
        needsChannelSelection = (itemCh > 1),
        channelSelectionMode = "mono",
        monoChannelSelection = 0,  -- Channel 1
        useDistribution = true
    }
end

-- Determine track structure based on container configuration and items
-- Pure function that applies decision rules
-- @param container table: Container configuration
-- @param itemsAnalysis table: Result from analyzeContainerItems
-- @return table: Track structure description
function Generation.determineTrackStructure(container, itemsAnalysis)
    local outputChannels = Generation.getOutputChannelCount(container.channelMode)
    local itemCh = itemsAnalysis.dominantChannelCount

    -- ═══════════════════════════════════════════════════════════
    -- RÈGLE 0 : Items mixtes → FORCE MONO
    -- ═══════════════════════════════════════════════════════════
    if not itemsAnalysis.isHomogeneous then
        return {
            strategy = "mixed-items-forced-mono",
            numTracks = outputChannels,
            trackType = "mono",
            trackChannels = 1,
            needsChannelSelection = true,
            channelSelectionMode = "mono",
            useDistribution = true,
            warning = "Mixed channel items detected - forcing mono channel selection"
        }
    end

    -- ═══════════════════════════════════════════════════════════
    -- RÈGLE 1 : Container vide → Structure par défaut
    -- ═══════════════════════════════════════════════════════════
    if itemsAnalysis.isEmpty then
        return {
            strategy = "empty-default",
            numTracks = 1,
            trackType = "multi",
            trackChannels = outputChannels,
            needsChannelSelection = false
        }
    end

    -- ═══════════════════════════════════════════════════════════
    -- RÈGLE 2 : Match parfait → Passthrough (1 track)
    -- ═══════════════════════════════════════════════════════════
    if itemCh == outputChannels then
        return {
            strategy = "perfect-match-passthrough",
            numTracks = 1,
            trackType = "multi",
            trackChannels = outputChannels,
            needsChannelSelection = false,
            itemsGoDirectly = true
        }
    end

    -- ═══════════════════════════════════════════════════════════
    -- RÈGLE 3 : Items MONO → Distribution sur N tracks mono
    -- ═══════════════════════════════════════════════════════════
    if itemCh == 1 then
        return {
            strategy = "mono-distribution",
            numTracks = outputChannels,
            trackType = "mono",
            trackChannels = 1,
            needsChannelSelection = false,
            useDistribution = true
        }
    end

    -- ═══════════════════════════════════════════════════════════
    -- À partir d'ici : itemCh > 1 et itemCh != outputChannels
    -- → Besoin de Channel Selection (downmix/split)
    -- ═══════════════════════════════════════════════════════════

    local channelSelectionMode = container.channelSelectionMode or "none"

    -- ═══════════════════════════════════════════════════════════
    -- RÈGLE 4 : Channel Selection = STEREO
    -- ═══════════════════════════════════════════════════════════
    if channelSelectionMode == "stereo" then
        -- Vérifier que les items ont un nombre pair de channels
        if itemCh % 2 ~= 0 then
            return {
                strategy = "invalid-stereo-fallback-mono",
                numTracks = outputChannels,
                trackType = "mono",
                trackChannels = 1,
                needsChannelSelection = true,
                channelSelectionMode = "mono",
                useDistribution = true,
                warning = "Cannot split odd-channel items into stereo pairs - using mono"
            }
        end

        local numStereoPairs = itemCh / 2

        -- Cas : Container Stereo avec items multi-channel pairs
        if outputChannels == 2 then
            return {
                strategy = "stereo-pair-selection",
                numTracks = 1,
                trackType = "stereo",
                trackChannels = 2,
                needsChannelSelection = true,
                channelSelectionMode = "stereo",
                availableStereoPairs = numStereoPairs,
            }
        end

        -- Cas : Container Quad/5.0/7.0 avec items stereo
        if itemCh == 2 and outputChannels >= 4 then
            if outputChannels == 4 then
                return {
                    strategy = "stereo-pairs-quad",
                    numTracks = 2,
                    trackType = "stereo",
                    trackChannels = 2,
                    trackLabels = {"L+R", "LS+RS"},
                    needsChannelSelection = false,
                    useDistribution = true
                }
            elseif outputChannels >= 5 then
                return {
                    strategy = "stereo-pairs-surround",
                    numTracks = 2,
                    trackType = "stereo",
                    trackChannels = 2,
                    trackLabels = {"L+R", "LS+RS"},
                    needsChannelSelection = false,
                    useDistribution = true
                }
            end
        end

        -- Cas : Container multi avec items 4ch+
        if outputChannels >= 4 and numStereoPairs >= 2 then
            local targetPairs = math.min(numStereoPairs, math.floor(outputChannels / 2))
            return {
                strategy = "split-stereo-pairs",
                numTracks = targetPairs,
                trackType = "stereo",
                trackChannels = 2,
                needsChannelSelection = true,
                channelSelectionMode = "split-stereo",
                trackLabels = Generation.generateStereoPairLabels(itemCh, targetPairs),
            }
        end

        -- Fallback
        return Generation.determineAutoOptimization(container, itemsAnalysis, outputChannels)
    end

    -- ═══════════════════════════════════════════════════════════
    -- RÈGLE 5 : Channel Selection = MONO
    -- ═══════════════════════════════════════════════════════════
    if channelSelectionMode == "mono" then
        return {
            strategy = "split-to-mono",
            numTracks = outputChannels,
            trackType = "mono",
            trackChannels = 1,
            needsChannelSelection = true,
            channelSelectionMode = "mono",
            useDistribution = true,
        }
    end

    -- ═══════════════════════════════════════════════════════════
    -- RÈGLE 6 : Channel Selection = NONE (Auto-optimization)
    -- ═══════════════════════════════════════════════════════════
    return Generation.determineAutoOptimization(container, itemsAnalysis, outputChannels)
end

return Generation
