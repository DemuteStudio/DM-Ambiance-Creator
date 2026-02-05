--[[
@version 1.1
@noindex
DM Ambiance Creator - Export Placement Module
Handles track resolution, item placement helpers, and export track management.
Migrated from Export_Core.lua (makeItemKey, createExportTrack, findTrackByName, getChildTracks, getTargetTracks).
--]]

local M = {}
local globals = {}
local Settings = nil

function M.initModule(g)
    if not g then
        error("Export_Placement.initModule: globals parameter is required")
    end
    globals = g
end

function M.setDependencies(settings)
    Settings = settings
end

-- Helper: Make item key for waveformAreas lookup
function M.makeItemKey(path, containerIndex, itemIndex)
    if globals.Structures and globals.Structures.makeItemKey then
        return globals.Structures.makeItemKey(path, containerIndex, itemIndex)
    end
    -- Fallback (replicate Structures logic with comma)
    local pathStr = table.concat(path, ",")
    return pathStr .. "::" .. containerIndex .. "::" .. itemIndex
end

-- Helper: Create a new track for export
function M.createExportTrack(containerInfo, channelIndex)
    local trackCount = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(trackCount, false)
    local newTrack = reaper.GetTrack(0, trackCount)

    local trackName = "Export - " .. containerInfo.container.name
    if channelIndex then
        local label = ""
        local mode = containerInfo.container.channelMode or 0
        local config = globals.Constants and globals.Constants.CHANNEL_CONFIGS[mode]
        if config and config.labels then
            label = " (" .. (config.labels[channelIndex] or channelIndex) .. ")"
        else
            label = " (Ch " .. channelIndex .. ")"
        end
        trackName = trackName .. label
    end
    reaper.GetSetMediaTrackInfo_String(newTrack, "P_NAME", trackName, true)

    return newTrack
end

-- Helper: Find track by name (fallback when GUID unavailable)
function M.findTrackByName(groupName, containerName)
    local trackCount = reaper.CountTracks(0)
    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        local _, trackName = reaper.GetTrackName(track)
        -- Match "ContainerName" or "GroupName - ContainerName"
        if trackName == containerName or
           trackName == (groupName .. " - " .. containerName) then
            return track
        end
    end
    return nil
end

-- Helper: Get child tracks of a folder track
function M.getChildTracks(folderTrack)
    local children = {}
    if not folderTrack then return children end

    local folderIdx = reaper.GetMediaTrackInfo_Value(folderTrack, "IP_TRACKNUMBER") - 1
    local trackCount = reaper.CountTracks(0)
    local depth = 1

    for i = folderIdx + 1, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        local trackDepth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")

        -- Stop when we exit the folder (depth goes back to same level or higher)
        if depth <= 0 then break end

        local parent = reaper.GetParentTrack(track)
        if parent == folderTrack then
            table.insert(children, track)
        end

        depth = depth + trackDepth
    end

    return children
end

-- Helper: Get target tracks for export (handles multi-channel)
-- Renamed from getTargetTracks for architecture compliance
function M.resolveTargetTracks(containerInfo, params)
    local tracks = {}
    local container = containerInfo.container
    local groupName = containerInfo.group and containerInfo.group.name or ""
    local containerName = container.name or ""

    if params.exportMethod == 1 then  -- New Track
        -- Create new track(s) based on container configuration
        if container.channelMode and container.channelMode > 0 then
            local config = globals.Constants and globals.Constants.CHANNEL_CONFIGS[container.channelMode]
            local numCh = config and config.channels or 0

            if numCh > 0 then
                -- Multi-channel: create one track per channel
                for i = 1, numCh do
                    local track = M.createExportTrack(containerInfo, i)
                    table.insert(tracks, track)
                end
            else
                table.insert(tracks, M.createExportTrack(containerInfo))
            end
        else
            -- Single track
            table.insert(tracks, M.createExportTrack(containerInfo))
        end
    else  -- Current Track (exportMethod == 0)
        -- Strategy 1: Try channelTrackGUIDs for multi-channel
        if container.channelTrackGUIDs and #container.channelTrackGUIDs > 0 then
            for _, guid in ipairs(container.channelTrackGUIDs) do
                local track = reaper.BR_GetMediaTrackByGUID(0, guid)
                if track then
                    table.insert(tracks, track)
                end
            end
        end

        -- Strategy 2: Try trackGUID for single track or folder
        if #tracks == 0 and container.trackGUID then
            local track = reaper.BR_GetMediaTrackByGUID(0, container.trackGUID)
            if track then
                -- Check if it's a folder track with children
                local folderDepth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
                if folderDepth == 1 then
                    -- It's a folder, get child tracks
                    tracks = M.getChildTracks(track)
                end

                -- If no children found or it's not a folder, use the track itself
                if #tracks == 0 then
                    table.insert(tracks, track)
                end
            end
        end

        -- Strategy 3: Fallback to name search
        if #tracks == 0 then
            local track = M.findTrackByName(groupName, containerName)
            if track then
                -- Check if it's a folder track with children
                local folderDepth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
                if folderDepth == 1 then
                    -- It's a folder, get child tracks
                    tracks = M.getChildTracks(track)
                end

                -- If no children found or it's not a folder, use the track itself
                if #tracks == 0 then
                    table.insert(tracks, track)
                end
            end
        end

        -- Strategy 4: Ultimate fallback - create new track
        if #tracks == 0 then
            table.insert(tracks, M.createExportTrack(containerInfo))
        end
    end

    return tracks
end

-- Stub: Resolve pool subset for export (full random subset in Story 2.1)
-- For now returns all items
function M.resolvePool(containerInfo, maxPoolItems)
    return containerInfo.container.items or {}
end

-- Build ItemData object for placeSingleItem
-- @param item table: Source item from container
-- @param area table: Area within the item (startPos, endPos, name)
-- @return table: ItemData object compatible with Generation.placeSingleItem
function M.buildItemData(item, area)
    return {
        filePath = item.filePath,
        name = area.name or item.name or "Exported",
        startOffset = area.startPos,
        length = area.endPos - area.startPos,
        originalPitch = item.originalPitch or 0,
        originalVolume = item.originalVolume or 1.0,
        originalPan = item.originalPan or 0,
        gainDB = item.gainDB or 0.0,
        numChannels = item.numChannels or 2
    }
end

-- Build genParams object for placeSingleItem
-- Copies container settings but overrides randomization based on preserve flags
-- @param params table: Effective params from Settings.getEffectiveParams
-- @param containerInfo table: Container info with container and group
-- @return table: genParams object compatible with Generation.placeSingleItem
function M.buildGenParams(params, containerInfo)
    local container = containerInfo.container
    local genParams = {}

    -- Copy all container properties
    for k, v in pairs(container) do
        genParams[k] = v
    end

    -- Override randomization flags based on preserve settings
    -- If preserve is TRUE, we allow the container's randomization
    -- If preserve is FALSE, we force randomization to FALSE (flatten)
    genParams.randomizePitch = container.randomizePitch and params.preservePitch
    genParams.randomizeVolume = container.randomizeVolume and params.preserveVolume
    genParams.randomizePan = container.randomizePan and params.preservePan

    return genParams
end

-- Calculate timeline position for item placement
-- Handles alignToSeconds rounding
-- @param currentPos number: Current timeline position in seconds
-- @param params table: Export params with alignToSeconds flag
-- @return number: Calculated position (potentially aligned to next whole second)
function M.calculatePosition(currentPos, params)
    if params.alignToSeconds then
        return math.ceil(currentPos)
    end
    return currentPos
end

-- Resolve track structure by delegating to Generation engine
-- This ensures export uses the same channel mapping logic as generation
-- @param containerInfo table: Container info from collectAllContainers
-- @return table: trackStructure object from Generation_Modes.determineTrackStructure()
function M.resolveTrackStructure(containerInfo)
    if not globals.Generation then
        error("Export_Placement.resolveTrackStructure: globals.Generation not initialized. Ensure Generation module is loaded before Export.")
    end

    local container = containerInfo.container

    -- Analyze items for channel structure
    local itemsAnalysis = globals.Generation.analyzeContainerItems(container)

    -- Determine track structure based on container mode and item analysis
    local trackStructure = globals.Generation.determineTrackStructure(container, itemsAnalysis)

    return trackStructure
end

-- Place container items on target tracks with correct multichannel channel distribution
-- CRITICAL: Uses real track indices from trackStructure for correct channel extraction
-- @param pool table: Array of items to export (from resolvePool or container.items)
-- @param targetTracks table: Array of REAPER tracks from resolveTargetTracks
-- @param trackStructure table: Track structure from resolveTrackStructure
-- @param params table: Effective export params
-- @param containerInfo table: Container info with path, container, group
-- @return table: Array of PlacedItem records {item, track, position, length, trackIdx}
function M.placeContainerItems(pool, targetTracks, trackStructure, params, containerInfo)
    local placedItems = {}
    local currentPos = reaper.GetCursorPosition()
    local genParams = M.buildGenParams(params, containerInfo)

    -- Iterate items in pool
    for itemIdx, item in ipairs(pool) do
        if not item.filePath then goto nextItem end

        -- Get Areas for this item
        local itemKey = M.makeItemKey(containerInfo.path, containerInfo.containerIndex, itemIdx)
        local areas = item.areas
        if (not areas or #areas == 0) and globals.waveformAreas then
            areas = globals.waveformAreas[itemKey]
        end
        if not areas or #areas == 0 then
            areas = {{ startPos = 0, endPos = item.length or 10, name = item.name or "Full" }}
        end

        -- For each Area
        for _, area in ipairs(areas) do
            local itemData = M.buildItemData(item, area)

            -- For each instance requested
            for instance = 1, params.instanceAmount do
                -- Calculate aligned position
                local itemPos = M.calculatePosition(currentPos, params)
                local actualLen = 0
                local anyItemCreated = false

                -- Place item on target tracks (handles multi-channel)
                for tIdx, track in ipairs(targetTracks) do
                    -- CRITICAL FIX: Use real track index from trackStructure, not loop counter
                    -- This ensures correct channel extraction for multichannel configurations
                    local realTrackIdx = trackStructure.trackIndices
                        and trackStructure.trackIndices[tIdx] or tIdx

                    -- Use placeSingleItem from Generation Engine
                    -- Pass ignoreBounds=true to ignore project time selection limits
                    local newItem, length = globals.Generation.placeSingleItem(
                        track,
                        itemData,
                        itemPos,
                        genParams,
                        trackStructure,
                        realTrackIdx,
                        trackStructure.channelSelectionMode,
                        true -- ignoreBounds
                    )

                    if newItem then
                        anyItemCreated = true
                        actualLen = math.max(actualLen, length)
                        -- Record placed item
                        table.insert(placedItems, {
                            item = newItem,
                            track = track,
                            position = itemPos,
                            length = length,
                            trackIdx = realTrackIdx
                        })
                    end
                end

                if anyItemCreated then
                    -- Advance position by item length plus spacing
                    currentPos = itemPos + actualLen + params.spacing
                    -- Optionally align again after spacing
                    if params.alignToSeconds and params.spacing > 0 then
                        currentPos = math.ceil(currentPos)
                    end
                end
            end
        end

        ::nextItem::
    end

    return placedItems
end

return M
