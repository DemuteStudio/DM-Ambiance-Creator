--[[
@version 1.6
@noindex
DM Ambiance Creator - Export Placement Module
Handles track resolution, item placement helpers, and export track management.
Migrated from Export_Core.lua (makeItemKey, createExportTrack, findTrackByName, getChildTracks, getTargetTracks).
v1.2: Story 2.1 - Full resolvePool() implementation with PoolEntry format and Fisher-Yates shuffle.
      placeContainerItems() updated to use PoolEntry objects directly.
v1.3: Story 3.1 - Added loop mode support with loopInterval and loopDuration in placeContainerItems.
      Code review fix: Use LOOP_MAX_ITERATIONS constant, added loop overshoot documentation.
v1.4: Story 4.1 - Added startPosition parameter and endPosition return for sequential container placement.
      Enables batch export without overlap between containers.
v1.5: Code review fixes - startPosition validation, improved return value documentation.
v1.6: Story 4.1 fix - In autoloop mode, use container.triggerRate for overlap instead of export loopInterval.
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

-- Fisher-Yates shuffle (in-place, returns same array)
-- @param arr table: Array to shuffle
-- @return table: The same array, shuffled in place
function M.shuffleArray(arr)
    local n = #arr
    for i = n, 2, -1 do
        local j = math.random(1, i)
        arr[i], arr[j] = arr[j], arr[i]
    end
    return arr
end

-- Resolve pool subset for export with random selection
-- Returns array of PoolEntry objects: { item, area, itemIdx, itemKey }
-- @param containerInfo table: Container info from collectAllContainers
-- @param maxPoolItems number: Maximum items to return (0 = all)
-- @return table: Array of PoolEntry objects
function M.resolvePool(containerInfo, maxPoolItems)
    -- Defensive nil-check for containerInfo
    if not containerInfo or not containerInfo.container then
        return {}
    end

    local allEntries = {}

    -- Iterate all items in container
    for itemIdx, item in ipairs(containerInfo.container.items or {}) do
        local itemKey = M.makeItemKey(containerInfo.path, containerInfo.containerIndex, itemIdx)
        local areas = globals.waveformAreas and globals.waveformAreas[itemKey]

        if areas and #areas > 0 then
            -- Create entry for each waveform area
            for _, area in ipairs(areas) do
                table.insert(allEntries, {
                    item = item,
                    area = area,
                    itemIdx = itemIdx,
                    itemKey = itemKey
                })
            end
        else
            -- No waveform areas: treat full item as single area
            table.insert(allEntries, {
                item = item,
                area = {
                    startPos = 0,
                    endPos = item.length or 10,
                    name = item.name or "Full"
                },
                itemIdx = itemIdx,
                itemKey = itemKey
            })
        end
    end

    -- Return all entries if maxPoolItems is 0 or >= total entries
    if maxPoolItems == 0 or maxPoolItems >= #allEntries then
        return allEntries
    end

    -- Random subset selection using Fisher-Yates shuffle
    -- NOTE: math.randomseed() is called once in Export_Engine.performExport()
    local shuffled = M.shuffleArray(allEntries)
    local subset = {}
    for i = 1, maxPoolItems do
        subset[i] = shuffled[i]
    end
    return subset
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
-- In loop mode: uses loopInterval instead of spacing, continues until loopDuration reached
-- @param pool table: Array of PoolEntry objects from resolvePool { item, area, itemIdx, itemKey }
-- @param targetTracks table: Array of REAPER tracks from resolveTargetTracks
-- @param trackStructure table: Track structure from resolveTrackStructure
-- @param params table: Effective export params
-- @param containerInfo table: Container info with path, container, group
-- @param startPosition number|nil: Optional start position in seconds (defaults to cursor if nil).
--        If provided, must be >= 0. Used by Export_Engine for sequential container placement.
-- @return table: Array of PlacedItem records {item, track, position, length, trackIdx}
-- @return number: End position (in seconds) after all items placed. Used by Export_Engine to
--        calculate next container's start position for sequential batch export.
function M.placeContainerItems(pool, targetTracks, trackStructure, params, containerInfo, startPosition)
    local placedItems = {}
    -- Validate and resolve start position (must be >= 0 if provided)
    local startPos = startPosition or reaper.GetCursorPosition()
    if startPos < 0 then
        startPos = 0 -- Clamp negative positions to timeline start
    end
    local currentPos = startPos
    local genParams = M.buildGenParams(params, containerInfo)

    -- Detect loop mode and configure placement behavior
    local isLoopMode = Settings and Settings.resolveLoopMode(containerInfo.container, params) or false
    local container = containerInfo.container
    -- v1.6: In autoloop mode (negative triggerRate), use container's triggerRate for overlap
    -- This ensures the same overlap behavior as the generator when container has negative interval
    local effectiveInterval
    if isLoopMode then
        -- Check if container has negative triggerRate (overlap) - use it if so
        if container.triggerRate and container.triggerRate < 0 then
            effectiveInterval = container.triggerRate  -- Use container's overlap value
        else
            effectiveInterval = params.loopInterval or 0  -- Use export settings loopInterval
        end
    else
        effectiveInterval = params.spacing or 0  -- Non-loop mode uses spacing
    end
    local targetDuration = isLoopMode and (params.loopDuration or 30) or math.huge

    -- Helper: place a single pool entry at current position
    local function placePoolEntry(poolEntry)
        if not poolEntry.item.filePath then return false, 0 end

        local itemData = M.buildItemData(poolEntry.item, poolEntry.area)
        local itemPos = M.calculatePosition(currentPos, params)
        local actualLen = 0
        local anyItemCreated = false

        -- Place item on target tracks (handles multi-channel)
        for tIdx, track in ipairs(targetTracks) do
            local realTrackIdx = trackStructure.trackIndices
                and trackStructure.trackIndices[tIdx] or tIdx

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
            -- Advance position by item length plus interval
            -- For loop mode with negative interval (overlap), ensure we don't go backwards
            local newPos = itemPos + actualLen + effectiveInterval
            -- Clamp to prevent negative progress (overlap cannot exceed item length)
            if newPos <= currentPos then
                newPos = currentPos + 0.001 -- Minimal forward progress
            end
            currentPos = newPos
            -- Optionally align after interval
            if params.alignToSeconds and effectiveInterval > 0 then
                currentPos = math.ceil(currentPos)
            end
        end

        return anyItemCreated, actualLen
    end

    -- Main placement logic
    if isLoopMode then
        -- Loop mode: cycle through pool until loopDuration is reached
        -- NOTE: Items may extend past loopDuration - this is intentional.
        -- Story 3.2 (loop processing) handles trimming via zero-crossing split/swap.
        local poolIndex = 1
        local itemsPlaced = 0
        local Constants = globals.Constants
        local maxIterations = Constants and Constants.EXPORT and Constants.EXPORT.LOOP_MAX_ITERATIONS or 10000

        while (currentPos - startPos) < targetDuration and itemsPlaced < maxIterations do
            local poolEntry = pool[poolIndex]
            if not poolEntry then break end

            -- Place for each instance requested
            for instance = 1, params.instanceAmount do
                if (currentPos - startPos) >= targetDuration then break end
                placePoolEntry(poolEntry)
                itemsPlaced = itemsPlaced + 1
            end

            -- Cycle through pool
            poolIndex = poolIndex + 1
            if poolIndex > #pool then
                poolIndex = 1 -- Loop back to start of pool
            end
        end
    else
        -- Standard mode: iterate once through pool
        for _, poolEntry in ipairs(pool) do
            for instance = 1, params.instanceAmount do
                placePoolEntry(poolEntry)
            end
        end
    end

    return placedItems, currentPos
end

return M
