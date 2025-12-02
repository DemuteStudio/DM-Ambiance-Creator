--[[
@version 1.0
@noindex
DM Ambiance Creator - Generation Core Module
Main generation orchestration and group/container generation.
--]]

local Generation_Core = {}
local globals = {}

-- Dependencies (set by aggregator)
local Generation_TrackManagement = nil
local Generation_MultiChannel = nil
local Generation_ItemPlacement = nil
local Generation_Modes = nil
local Utils = nil

function Generation_Core.initModule(g)
    globals = g
    Utils = globals.Utils
end

function Generation_Core.setDependencies(trackMgmt, multiChannel, itemPlacement, modes)
    Generation_TrackManagement = trackMgmt
    Generation_MultiChannel = multiChannel
    Generation_ItemPlacement = itemPlacement
    Generation_Modes = modes
end

-- Helper function to recursively collect item names (groups and folders)
-- @param items table: Array of items (folders/groups)
-- @param nameMap table: Map to store names (modified in-place)
local function collectItemNames(items, nameMap)
    for _, item in ipairs(items) do
        nameMap[item.name] = true
        if item.type == "folder" and item.children then
            collectItemNames(item.children, nameMap)
        end
    end
end

-- Helper function to recursively collect all groups from items structure
-- @param items table: Array of items (folders/groups)
-- @param groups table: Array to collect groups into (modified in-place)
local function collectAllGroups(items, groups)
    for _, item in ipairs(items) do
        if item.type == "group" then
            table.insert(groups, item)
        elseif item.type == "folder" and item.children then
            collectAllGroups(item.children, groups)
        end
    end
end

-- Helper function to process items recursively (folders and groups)
local function processItems(items, generateFolderTracks, currentDepth, xfadeshape)
    if not items or #items == 0 then
        return 0
    end

    local tracksCreatedAtThisLevel = 0

    for i, item in ipairs(items) do
        if item.type == "folder" then
            -- Process folder item
            local folderTrack = nil
            local folderStartIdx = nil

            if generateFolderTracks then
                -- Create folder track in REAPER
                folderStartIdx = reaper.GetNumTracks()
                reaper.InsertTrackAtIndex(folderStartIdx, true)
                folderTrack = reaper.GetTrack(0, folderStartIdx)
                reaper.GetSetMediaTrackInfo_String(folderTrack, "P_NAME", item.name, true)

                -- Store the track GUID for later reference
                item.trackGUID = reaper.GetTrackGUID(folderTrack)

                -- Set as folder start
                reaper.SetMediaTrackInfo_Value(folderTrack, "I_FOLDERDEPTH", 1)

                -- Apply folder properties
                local folderVolumeDB = item.trackVolume or 0.0
                local linearVolume = Utils.dbToLinear(folderVolumeDB)
                reaper.SetMediaTrackInfo_Value(folderTrack, "D_VOL", linearVolume)

                -- Apply solo/mute states (if present)
                if item.solo then
                    reaper.SetMediaTrackInfo_Value(folderTrack, "I_SOLO", item.solo and 1 or 0)
                end
                if item.mute then
                    reaper.SetMediaTrackInfo_Value(folderTrack, "B_MUTE", item.mute and 1 or 0)
                end

                tracksCreatedAtThisLevel = tracksCreatedAtThisLevel + 1
            end

            -- Recursively process folder children
            if item.children and #item.children > 0 then
                local childTracksCreated = processItems(item.children, generateFolderTracks, currentDepth + 1, xfadeshape)
                tracksCreatedAtThisLevel = tracksCreatedAtThisLevel + childTracksCreated
            end

            if generateFolderTracks and folderTrack then
                -- Close the folder by setting I_FOLDERDEPTH = -1 on the last child track
                local currentTrackCount = reaper.GetNumTracks()
                if currentTrackCount > folderStartIdx + 1 then
                    -- There are child tracks, close folder on last child
                    local lastChildTrack = reaper.GetTrack(0, currentTrackCount - 1)
                    local currentDepth = reaper.GetMediaTrackInfo_Value(lastChildTrack, "I_FOLDERDEPTH")
                    -- If the last child is already closing a folder, we need to decrement further
                    reaper.SetMediaTrackInfo_Value(lastChildTrack, "I_FOLDERDEPTH", currentDepth - 1)
                else
                    -- No children were created, delete the empty folder track
                    reaper.DeleteTrack(folderTrack)
                    tracksCreatedAtThisLevel = tracksCreatedAtThisLevel - 1
                end
            end

        elseif item.type == "group" then
            -- Process group item (existing logic from generateGroups)
            local group = item
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
                Generation_ItemPlacement.placeItemsForContainer(group, container, containerGroup, xfadeshape)
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
                local k = parentGroupIdx + 1
                while k < reaper.CountTracks(0) and depth > 0 do
                    lastTrackIdx = k
                    local track = reaper.GetTrack(0, k)
                    local trackDepth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
                    depth = depth + trackDepth
                    k = k + 1
                end

                -- Get the actual last track and ensure it closes the parent group
                if lastTrackIdx > parentGroupIdx then
                    local lastTrack = reaper.GetTrack(0, lastTrackIdx)
                    -- This track should close both its container and the parent group
                    -- Since Reaper doesn't support -2, we use -1 which should close the outermost open folder
                    reaper.SetMediaTrackInfo_Value(lastTrack, "I_FOLDERDEPTH", -1)
                end
            end

            tracksCreatedAtThisLevel = tracksCreatedAtThisLevel + (reaper.GetNumTracks() - parentGroupIdx)
        end
    end

    return tracksCreatedAtThisLevel
end

-- Function to delete existing groups with same names before generating
function Generation_Core.deleteExistingGroups()
  -- Create a map of all item names (groups and folders) we're about to create
  local itemNames = {}

  -- Support both old globals.groups and new globals.items structure
  if globals.items and #globals.items > 0 then
      collectItemNames(globals.items, itemNames)
  elseif globals.groups and #globals.groups > 0 then
      for _, group in ipairs(globals.groups) do
          itemNames[group.name] = true
      end
  end

  -- Find all tracks with matching names and their children
  local groupsToDelete = {}
  local groupCount = reaper.CountTracks(0)
  local i = 0
  while i < groupCount do
      local group = reaper.GetTrack(0, i)
      local _, name = reaper.GetSetMediaTrackInfo_String(group, "P_NAME", "", false)
      if itemNames[name] then
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

-- Function to generate groups and place items
function Generation_Core.generateGroups()
    if not globals.timeSelectionValid then
        reaper.MB("Please create a time selection before generating groups!", "Error", 0)
        return
    end

    reaper.Main_OnCommand(40289, 0) -- "Item: Unselect all items"
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    -- Get default crossfade shape from REAPER preferences
    local xfadeshape = reaper.SNM_GetIntConfigVar("defxfadeshape", 0)

    -- Determine data source: new globals.items or legacy globals.groups
    local itemsSource = (globals.items and #globals.items > 0) and globals.items or nil
    local groupsSource = (not itemsSource and globals.groups and #globals.groups > 0) and globals.groups or nil

    if globals.keepExistingTracks then
        -- Use regeneration logic for existing tracks (keep existing)
        -- Use new items structure or fall back to legacy groups
        if itemsSource then
            -- TODO: Implement true regeneration for new items structure with folders
            -- For now, silently fall back to recreate mode (delete and regenerate)
            -- NOTE: We don't modify globals.keepExistingTracks to preserve user's checkbox state
            Generation_Core.deleteExistingGroups()
            local generateFolderTracks = globals.Settings and globals.Settings.getSetting("generateFolderTracks")
            if generateFolderTracks == nil then
                generateFolderTracks = true
            end
            processItems(itemsSource, generateFolderTracks, 0, xfadeshape)
        elseif groupsSource then
            -- Legacy regeneration for old globals.groups
            for i, group in ipairs(groupsSource) do
                Generation_Core.generateSingleGroup(i)
            end
        end
    else
        -- Original behavior: delete and recreate tracks (clear all)
        Generation_Core.deleteExistingGroups()

        -- NEW APPROACH: Use processItems for recursive folder/group generation
        if itemsSource then
            -- Get generateFolderTracks setting
            local generateFolderTracks = globals.Settings and globals.Settings.getSetting("generateFolderTracks")
            if generateFolderTracks == nil then
                generateFolderTracks = true  -- Default to true if setting not found
            end

            -- Process items recursively
            processItems(itemsSource, generateFolderTracks, 0, xfadeshape)

        elseif groupsSource then
            -- LEGACY APPROACH: Use old globals.groups logic
            for i, group in ipairs(groupsSource) do
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
                    Generation_ItemPlacement.placeItemsForContainer(group, container, containerGroup, xfadeshape)
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
                    local k = parentGroupIdx + 1
                    while k < reaper.CountTracks(0) and depth > 0 do
                        lastTrackIdx = k
                        local track = reaper.GetTrack(0, k)
                        local trackDepth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
                        depth = depth + trackDepth
                        k = k + 1
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
    end

    -- Collect all groups from either source for master track channel calculation
    local allGroups = {}
    if itemsSource then
        collectAllGroups(itemsSource, allGroups)
    elseif groupsSource then
        allGroups = groupsSource
    end

    -- Ensure Master track has enough channels for all multi-channel groups
    local maxChannels = 2  -- Minimum stereo
    for _, group in ipairs(allGroups) do
        if group.containers then
            for _, container in ipairs(group.containers) do
                if container.channelMode and container.channelMode > 0 then
                    local config = globals.Constants.CHANNEL_CONFIGS[container.channelMode]
                    if config then
                        local requiredChannels = config.totalChannels or config.channels
                        maxChannels = math.max(maxChannels, requiredChannels)
                    end
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

    -- NOTE: Routing validation is handled in stabilizeProjectConfiguration() below
    -- Don't call checkAndResolveConflicts() here to avoid duplicate validation
    -- on issues that will be auto-corrected by recalculateChannelRequirements()

    -- Clear regeneration flags for all groups and containers
    for _, group in ipairs(allGroups) do
        group.needsRegeneration = false
        if group.containers then
            for _, container in ipairs(group.containers) do
                container.needsRegeneration = false
            end
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
            Generation_MultiChannel.stabilizeProjectConfiguration(false)  -- Full mode, not light
        else
            -- Normal generation - use light stabilization
            Generation_MultiChannel.stabilizeProjectConfiguration(true)   -- Light mode
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


function Generation_Core.generateSingleGroup(groupIndex)
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
            Generation_ItemPlacement.placeItemsForContainer(group, container, containerGroup, xfadeshape)
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
            Generation_ItemPlacement.placeItemsForContainer(group, container, containerGroup, xfadeshape)
        end
    end

    -- CRITICAL: Force full stabilization after single group regeneration
    -- This handles the case where containers were deleted from the tool
    if not globals.skipRoutingValidation then
        Generation_MultiChannel.stabilizeProjectConfiguration(false)  -- Full stabilization
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


-- Function to regenerate a single group by path (for new globals.items structure with folders)
-- @param groupPath table: Path to the group in the items hierarchy
function Generation_Core.generateSingleGroupByPath(groupPath)
    if not globals.timeSelectionValid then
        reaper.MB("Please create a time selection before regenerating!", "Error", 0)
        return
    end

    -- Get the group from the path
    local group, groupType = globals.Utils.getItemFromPath(groupPath)
    if not group or groupType ~= "group" then
        reaper.ShowConsoleMsg("Error: Could not find group at path\n")
        return
    end

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
            Generation_ItemPlacement.placeItemsForContainer(group, container, containerGroup, xfadeshape)
        end
    else
        -- Group doesn't exist in REAPER, create it from scratch

        -- Check if this group has a parent folder
        local parent, parentType, parentPath = globals.Utils.getParentFromPath(groupPath)
        local insertIdx = reaper.GetNumTracks() -- Default: insert at end

        if parent and parentType == "folder" then
            -- Find the parent folder track to insert after it
            local folderTrack = nil
            if parent.trackGUID and globals.Generation then
                folderTrack = Generation_TrackManagement.findTrackByGUID(parent.trackGUID)
            end
            if not folderTrack then
                folderTrack = globals.Utils.findTrackByName(parent.name)
            end

            if folderTrack then
                -- Find the index of the folder track
                local folderIdx = -1
                for i = 0, reaper.CountTracks(0) - 1 do
                    if reaper.GetTrack(0, i) == folderTrack then
                        folderIdx = i
                        break
                    end
                end

                if folderIdx >= 0 then
                    -- Insert right after the folder track
                    insertIdx = folderIdx + 1
                end
            end
        end

        reaper.InsertTrackAtIndex(insertIdx, true)
        local parentGroup = reaper.GetTrack(0, insertIdx)
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

            -- Generate items for this container
            Generation_ItemPlacement.placeItemsForContainer(group, container, containerGroup, xfadeshape)
        end

        -- After all containers are created, ensure proper folder closure
        -- If the last container was multi-channel, we need to close the parent group
        local lastContainer = group.containers[#group.containers]
        if lastContainer and lastContainer.channelMode and lastContainer.channelMode > 0 then
            -- Find channel tracks for last container
            local lastContainerTrack = reaper.GetTrack(0, reaper.GetNumTracks() - 1)
            local channelTracks = Generation_MultiChannel.getExistingChannelTracks(lastContainerTrack)

            if #channelTracks > 0 then
                -- Last channel track should close the parent group
                local lastTrackIdx = reaper.GetNumTracks() - 1
                if lastTrackIdx > insertIdx then
                    local lastTrack = reaper.GetTrack(0, lastTrackIdx)
                    -- This track should close both its container and the parent group
                    reaper.SetMediaTrackInfo_Value(lastTrack, "I_FOLDERDEPTH", -1)
                end
            end
        end
    end

    -- CRITICAL: Force full stabilization after single group regeneration
    -- This handles the case where containers were deleted from the tool
    if not globals.skipRoutingValidation then
        Generation_MultiChannel.stabilizeProjectConfiguration(false)  -- Full stabilization
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
function Generation_Core.generateSingleContainer(groupIndex, containerIndex)
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

        -- Check if this group has a parent folder
        local parent, parentType, parentPath = globals.Utils.getParentFromPath(groupPath)
        parentGroupIdx = reaper.GetNumTracks() -- Default: insert at end

        if parent and parentType == "folder" then
            -- Find the parent folder track to insert after it
            local folderTrack = nil
            if parent.trackGUID and globals.Generation then
                folderTrack = Generation_TrackManagement.findTrackByGUID(parent.trackGUID)
            end
            if not folderTrack then
                folderTrack = globals.Utils.findTrackByName(parent.name)
            end

            if folderTrack then
                -- Find the index of the folder track
                local folderIdx = -1
                for i = 0, reaper.CountTracks(0) - 1 do
                    if reaper.GetTrack(0, i) == folderTrack then
                        folderIdx = i
                        break
                    end
                end

                if folderIdx >= 0 then
                    -- Insert right after the folder track
                    parentGroupIdx = folderIdx + 1
                end
            end
        end

        reaper.InsertTrackAtIndex(parentGroupIdx, true)
        parentGroup = reaper.GetTrack(0, parentGroupIdx)
        reaper.GetSetMediaTrackInfo_String(parentGroup, "P_NAME", group.name, true)
        reaper.SetMediaTrackInfo_Value(parentGroup, "I_FOLDERDEPTH", 1)
    end

    -- Try to find container by GUID first
    local containerGroup, containerGroupIdx = nil, nil

    if container.trackGUID then
        containerGroup = Generation_TrackManagement.findTrackByGUID(container.trackGUID)
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
                Generation_MultiChannel.deleteContainerChildTracks(containerGroup)
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
                    local channelTracks = Generation_MultiChannel.getExistingChannelTracks(containerGroup)
                    Generation_MultiChannel.clearChannelTracks(channelTracks)
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
        Generation_ItemPlacement.placeItemsForContainer(group, container, containerGroup, xfadeshape)

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
        Generation_ItemPlacement.placeItemsForContainer(group, container, containerGroup, xfadeshape)

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
    Generation_MultiChannel.checkAndResolveConflicts()

    -- Clear regeneration flag for the container
    container.needsRegeneration = false

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Regenerate container '" .. container.name .. "' in group '" .. group.name .. "'", -1)
end


-- Function to regenerate a single container by path (for new globals.items structure with folders)
-- @param groupPath table: Path to the group in the items hierarchy
-- @param containerIndex number: Index of the container within the group
function Generation_Core.generateSingleContainerByPath(groupPath, containerIndex)
    if not globals.timeSelectionValid then
        reaper.MB("Please create a time selection before regenerating!", "Error", 0)
        return
    end

    -- Get the group from the path
    local group, groupType = globals.Utils.getItemFromPath(groupPath)
    if not group or groupType ~= "group" then
        reaper.ShowConsoleMsg("Error: Could not find group at path\n")
        return
    end

    local container = group.containers[containerIndex]
    if not container then
        reaper.ShowConsoleMsg("Error: Could not find container at index " .. containerIndex .. "\n")
        return
    end

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

        -- Check if this group has a parent folder
        local parent, parentType, parentPath = globals.Utils.getParentFromPath(groupPath)
        parentGroupIdx = reaper.GetNumTracks() -- Default: insert at end

        if parent and parentType == "folder" then
            -- Find the parent folder track to insert after it
            local folderTrack = nil
            if parent.trackGUID and globals.Generation then
                folderTrack = Generation_TrackManagement.findTrackByGUID(parent.trackGUID)
            end
            if not folderTrack then
                folderTrack = globals.Utils.findTrackByName(parent.name)
            end

            if folderTrack then
                -- Find the index of the folder track
                local folderIdx = -1
                for i = 0, reaper.CountTracks(0) - 1 do
                    if reaper.GetTrack(0, i) == folderTrack then
                        folderIdx = i
                        break
                    end
                end

                if folderIdx >= 0 then
                    -- Insert right after the folder track
                    parentGroupIdx = folderIdx + 1
                end
            end
        end

        reaper.InsertTrackAtIndex(parentGroupIdx, true)
        parentGroup = reaper.GetTrack(0, parentGroupIdx)
        reaper.GetSetMediaTrackInfo_String(parentGroup, "P_NAME", group.name, true)
        reaper.SetMediaTrackInfo_Value(parentGroup, "I_FOLDERDEPTH", 1)
    end

    -- Try to find container by GUID first
    local containerGroup, containerGroupIdx = nil, nil

    if container.trackGUID then
        containerGroup = Generation_TrackManagement.findTrackByGUID(container.trackGUID)
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
                Generation_MultiChannel.deleteContainerChildTracks(containerGroup)
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
                    local channelTracks = Generation_MultiChannel.getExistingChannelTracks(containerGroup)
                    Generation_MultiChannel.clearChannelTracks(channelTracks)
                else
                    -- Default mode: clear items from container itself
                    while reaper.CountTrackMediaItems(containerGroup) > 0 do
                        local item = reaper.GetTrackMediaItem(containerGroup, 0)
                        reaper.DeleteTrackMediaItem(containerGroup, item)
                    end
                end
            end
        end

        -- Apply container track volume
        local volumeDB = container.trackVolume or 0.0
        local linearVolume = Utils.dbToLinear(volumeDB)
        reaper.SetMediaTrackInfo_Value(containerGroup, "D_VOL", linearVolume)

        -- Generate items for this container
        Generation_ItemPlacement.placeItemsForContainer(group, container, containerGroup, xfadeshape)
    else
        -- Container doesn't exist, create it
        -- Find the correct insertion position (after parent group and existing containers)
        local insertPosition = parentGroupIdx + 1

        -- Count existing containers to insert after them
        local existingContainerCount = 0
        for i = parentGroupIdx + 1, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, i)
            local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            if depth == -1 then break end -- End of group folder
            existingContainerCount = existingContainerCount + 1
        end

        insertPosition = parentGroupIdx + existingContainerCount + 1

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
        Generation_ItemPlacement.placeItemsForContainer(group, container, containerGroup, xfadeshape)

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

    -- Clear regeneration flag for the container
    container.needsRegeneration = false

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Regenerate container '" .. container.name .. "' in group '" .. group.name .. "'", -1)
end

return Generation_Core
