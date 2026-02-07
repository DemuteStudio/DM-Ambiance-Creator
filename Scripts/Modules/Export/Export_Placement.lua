--[[
@version 1.12
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
v1.7: Story 4.3 - Added missing source file detection with reaper.file_exists() check.
      Throws error with file path if source file is missing for pcall isolation in Export_Engine.
v1.8: Code review fixes - Nil filePath now throws error instead of silent skip, error() uses level 0
      for cleaner UI display without file:line prefix.
v1.9: Story 4.4 - Fixed effectiveInterval logic to properly support auto-mode semantics.
      loopInterval=0 means auto-mode (use container.triggerRate), non-zero overrides all containers.
v1.10: Story 5.1 - Export now creates proper track hierarchy (folder + channel tracks) for multichannel
       containers. Uses Generation_TrackManagement.createMultiChannelTracks() for consistency.
       Handles GUID fallback when tracks don't exist. Stores GUIDs after track creation.
v1.11: Code review fixes - Removed dead needsTrackHierarchy(), suppressed Generation view/state
       side effects during export, eliminated redundant analysis via trackStructure passthrough,
       consistent "Export -" naming for multichannel folders, defensive checks for Generation API.
v1.12: Story 5.2 - Multichannel export mode: Flatten restricts to first child track,
       Preserve distributes via Round-Robin/Random/All Tracks matching Generation engine.
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

-- Helper: Create a new track for export (simple flat track)
-- Used only for stereo containers that don't need hierarchy
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

-- Helper: Create track hierarchy for multichannel containers
-- Uses Generation engine's createMultiChannelTracks for consistency with generation
-- @param containerInfo table: Container info from collectAllContainers
-- @param trackStructure table: Pre-computed track structure from resolveTrackStructure
-- @return table: Array of channel tracks (or single track for stereo)
function M.createExportTrackHierarchy(containerInfo, trackStructure)
    local container = containerInfo.container

    -- Check if Generation module is available (all required sub-functions)
    if not globals.Generation
       or not globals.Generation.createMultiChannelTracks
       or not globals.Generation.analyzeContainerItems
       or not globals.Generation.determineTrackStructure then
        -- Fallback to simple track creation
        local track = M.createExportTrack(containerInfo)
        return {track}
    end

    -- For single track (stereo with stereo items), create simple track
    if trackStructure.numTracks == 1 then
        local track = M.createExportTrack(containerInfo)
        -- Set channel count to match requirements
        local requiredChannels = trackStructure.trackChannels or 2
        if requiredChannels % 2 == 1 then
            requiredChannels = requiredChannels + 1
        end
        reaper.SetMediaTrackInfo_Value(track, "I_NCHAN", requiredChannels)

        -- Store GUID for future exports
        container.trackGUID = reaper.GetTrackGUID(track)
        container.channelTrackGUIDs = nil

        return {track}
    end

    -- Create folder track for multichannel container
    local trackCount = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(trackCount, false)
    local folderTrack = reaper.GetTrack(0, trackCount)

    -- Name the folder track (consistent "Export - " prefix with stereo tracks)
    reaper.GetSetMediaTrackInfo_String(folderTrack, "P_NAME",
        "Export - " .. (container.name or "Container"), true)

    -- Suppress Generation-specific side effects during export:
    -- 1. View zoom commands (inappropriate during export)
    -- 2. Container state mutation (previousChannelMode tracking)
    local savedPreviousChannelMode = container.previousChannelMode
    globals.suppressViewRefresh = true

    -- Use Generation's createMultiChannelTracks to create the hierarchy
    -- This handles all the complexity: track structure analysis, routing, folder depth
    local channelTracks = globals.Generation.createMultiChannelTracks(folderTrack, container, false)

    globals.suppressViewRefresh = nil
    container.previousChannelMode = savedPreviousChannelMode

    -- GUIDs are already stored by createMultiChannelTracks via storeTrackGUIDs

    return channelTracks
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
-- Story 5.1: Creates proper track hierarchy using Generation engine for consistency
-- @param containerInfo table: Container info from collectAllContainers
-- @param trackStructure table: Pre-computed track structure from resolveTrackStructure
-- @param params table: Export params with exportMethod
-- @return table: Array of target tracks
function M.resolveTargetTracks(containerInfo, trackStructure, params)
    local tracks = {}
    local container = containerInfo.container
    local groupName = containerInfo.group and containerInfo.group.name or ""
    local containerName = container.name or ""

    if params.exportMethod == 1 then  -- New Track
        -- Story 5.1: Use track hierarchy creation for proper multichannel support
        -- This delegates to Generation engine for consistent track structure
        tracks = M.createExportTrackHierarchy(containerInfo, trackStructure)

    else  -- Current Track (exportMethod == 0)
        local foundValidTracks = false

        -- Strategy 1: Try channelTrackGUIDs for multi-channel
        if container.channelTrackGUIDs and #container.channelTrackGUIDs > 0 then
            local allTracksFound = true
            local guidTracks = {}

            for _, guid in ipairs(container.channelTrackGUIDs) do
                local track = reaper.BR_GetMediaTrackByGUID(0, guid)
                if track then
                    table.insert(guidTracks, track)
                else
                    -- At least one GUID points to non-existent track
                    allTracksFound = false
                    break
                end
            end

            if allTracksFound and #guidTracks > 0 then
                tracks = guidTracks
                foundValidTracks = true
            end
            -- Story 5.1 AC#3: If GUIDs point to non-existent tracks, fall through to create hierarchy
        end

        -- Strategy 2: Try trackGUID for single track or folder
        if not foundValidTracks and container.trackGUID then
            local track = reaper.BR_GetMediaTrackByGUID(0, container.trackGUID)
            if track then
                -- Check if it's a folder track with children
                local folderDepth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
                if folderDepth == 1 then
                    -- It's a folder, get child tracks
                    tracks = M.getChildTracks(track)
                    if #tracks > 0 then
                        foundValidTracks = true
                    end
                end

                -- If no children found or it's not a folder, use the track itself
                if #tracks == 0 then
                    table.insert(tracks, track)
                    foundValidTracks = true
                end
            end
            -- Story 5.1 AC#3: If trackGUID points to non-existent track, fall through
        end

        -- Strategy 3: Fallback to name search
        if not foundValidTracks then
            local track = M.findTrackByName(groupName, containerName)
            if track then
                -- Check if it's a folder track with children
                local folderDepth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
                if folderDepth == 1 then
                    -- It's a folder, get child tracks
                    tracks = M.getChildTracks(track)
                    if #tracks > 0 then
                        foundValidTracks = true
                    end
                end

                -- If no children found or it's not a folder, use the track itself
                if #tracks == 0 then
                    table.insert(tracks, track)
                    foundValidTracks = true
                end
            end
        end

        -- Strategy 4: Ultimate fallback - create proper track hierarchy
        -- Story 5.1 AC#3: Creates hierarchy instead of simple flat tracks
        if not foundValidTracks then
            tracks = M.createExportTrackHierarchy(containerInfo, trackStructure)
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
--
-- ARCHITECTURE NOTE: This function is called ONCE per container by Export_Engine.performExport().
-- This design enables Story 4.4's AC5 (batch export with loopInterval=0): each container's
-- effectiveInterval is calculated independently based on its own triggerRate when in auto-mode.
-- Do NOT refactor Export_Engine to batch multiple containers in a single call without updating
-- the effectiveInterval logic accordingly.
--
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

    -- Story 5.2: Multichannel export mode handling
    -- Flatten: restrict to first child track only, skip channel extraction
    -- Preserve: distribute items across child tracks per distribution mode
    local Constants = globals.Constants
    local EXPORT = Constants and Constants.EXPORT or {}
    local multichannelMode = params.multichannelExportMode
        or EXPORT.MULTICHANNEL_EXPORT_MODE_DEFAULT or "flatten"
    local isFlattenMode = (multichannelMode == (EXPORT.MULTICHANNEL_EXPORT_MODE_FLATTEN or "flatten"))
    local isPreserveMode = (multichannelMode == (EXPORT.MULTICHANNEL_EXPORT_MODE_PRESERVE or "preserve"))

    -- Apply flatten mode: use only the first target track, no channel extraction
    local effectiveTargetTracks = targetTracks
    local effectiveTrackStructure = trackStructure
    if isFlattenMode and #targetTracks > 1 then
        effectiveTargetTracks = {targetTracks[1]}
        -- Override trackStructure to skip channel extraction (AC #2: place items as-is)
        effectiveTrackStructure = {}
        for k, v in pairs(trackStructure) do
            effectiveTrackStructure[k] = v
        end
        effectiveTrackStructure.channelSelectionMode = "none"
        effectiveTrackStructure.needsChannelSelection = false
        -- Map trackIndices to just the first track's real index
        if trackStructure.trackIndices then
            effectiveTrackStructure.trackIndices = {trackStructure.trackIndices[1]}
        end
    end

    -- Detect loop mode and configure placement behavior
    local isLoopMode = Settings and Settings.resolveLoopMode(containerInfo.container, params) or false
    local container = containerInfo.container
    -- Story 4.4: Loop Interval auto-mode semantics
    -- loopInterval=0 (auto-mode): each container uses its own triggerRate for overlap
    -- loopInterval!=0 (explicit): all containers use the specified loopInterval value
    local effectiveInterval
    if isLoopMode then
        if (params.loopInterval or 0) ~= 0 then
            -- Explicit override: all containers use the specified loopInterval
            effectiveInterval = params.loopInterval
        elseif container.triggerRate and container.triggerRate < 0 then
            -- Auto-mode: container has negative triggerRate (overlap), use it
            effectiveInterval = container.triggerRate
        else
            -- Auto-mode: container has non-negative triggerRate (no overlap requested)
            effectiveInterval = 0
        end
    else
        effectiveInterval = params.spacing or 0  -- Non-loop mode uses spacing
    end
    local targetDuration = isLoopMode and (params.loopDuration or 30) or math.huge

    -- Story 5.2: Preserve mode distribution state
    -- Determines whether items should be distributed across tracks (Round-Robin/Random)
    -- vs placed on all tracks (Smart Routing) or handled as All Tracks (mode 2)
    local preserveDistribution = false
    local distributionCounter = 0
    local distributionMode = container.itemDistributionMode or 0
    local isAllTracksMode = false

    if isPreserveMode and #effectiveTargetTracks > 1 then
        if effectiveTrackStructure.useSmartRouting then
            -- Smart Routing: same item on all tracks with channel extraction (AC #3.5)
            preserveDistribution = false
        elseif effectiveTrackStructure.useDistribution then
            if distributionMode == 2 then
                -- All Tracks mode: handled separately with track-outer/pool-inner loop (Task 4)
                isAllTracksMode = true
            else
                -- Round-Robin (0) or Random (1): distribute per-item
                preserveDistribution = true
            end
        end
    end

    -- Helper: place a single pool entry at current position on specified tracks
    -- @param poolEntry table: PoolEntry object
    -- @param overrideTracks table|nil: If provided, place only on these tracks (for distribution)
    -- @param overrideTrackIndices table|nil: If provided, use these real track indices
    local function placePoolEntry(poolEntry, overrideTracks, overrideTrackIndices)
        -- Story 4.3 fix: Nil filePath should throw error, not silently skip
        if not poolEntry.item.filePath then
            error("Item has no file path configured")
        end

        -- Story 4.3: Check if source file exists before attempting placement
        local filePath = poolEntry.item.filePath
        if not reaper.file_exists(filePath) then
            -- Use error level 0 to suppress file:line prefix for cleaner UI display
            error("Missing source file: " .. filePath, 0)
        end

        local itemData = M.buildItemData(poolEntry.item, poolEntry.area)
        local itemPos = M.calculatePosition(currentPos, params)
        local actualLen = 0
        local anyItemCreated = false

        -- Story 5.2: Use override tracks if provided (Preserve distribution),
        -- otherwise use all effective target tracks (Flatten or Smart Routing)
        local placementTracks = overrideTracks or effectiveTargetTracks
        local placementIndices = overrideTrackIndices or (effectiveTrackStructure.trackIndices)

        for tIdx, track in ipairs(placementTracks) do
            local realTrackIdx = placementIndices and placementIndices[tIdx] or tIdx

            local newItem, length = globals.Generation.placeSingleItem(
                track,
                itemData,
                itemPos,
                genParams,
                effectiveTrackStructure,
                realTrackIdx,
                effectiveTrackStructure.channelSelectionMode,
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

    -- Story 5.2: Helper to resolve distribution target for a single pool entry
    -- Returns the single-element track/index tables for Round-Robin or Random modes
    local function getDistributionTarget()
        local targetIdx
        if distributionMode == 0 then
            -- Round-Robin (AC #5): cycle through tracks sequentially
            distributionCounter = distributionCounter + 1
            targetIdx = ((distributionCounter - 1) % #effectiveTargetTracks) + 1
        else
            -- Random (AC #6): pick random track per pool entry
            targetIdx = math.random(1, #effectiveTargetTracks)
        end
        local track = effectiveTargetTracks[targetIdx]
        local realIdx = effectiveTrackStructure.trackIndices
            and effectiveTrackStructure.trackIndices[targetIdx] or targetIdx
        return {track}, {realIdx}
    end

    -- Main placement logic
    -- Story 5.2: All Tracks mode (mode 2) uses a completely different loop structure:
    -- iterate tracks OUTER, pool INNER — each track gets its own independent sequence
    if isAllTracksMode then
        -- AC #7: All Tracks Preserve mode — each track generates independently
        -- Each track gets its own shuffled copy of the pool so sequences differ
        for tIdx, track in ipairs(effectiveTargetTracks) do
            local realIdx = effectiveTrackStructure.trackIndices
                and effectiveTrackStructure.trackIndices[tIdx] or tIdx
            local trackPos = startPos
            local trackTracks = {track}
            local trackIndices = {realIdx}

            -- Shuffle an independent copy of the pool for this track
            -- This ensures each track gets a different item sequence
            local trackPool = {}
            for i, entry in ipairs(pool) do trackPool[i] = entry end
            M.shuffleArray(trackPool)

            if isLoopMode then
                -- Loop mode: cycle through shuffled pool until targetDuration
                local poolIndex = 1
                local itemsPlaced = 0
                local maxIter = EXPORT.LOOP_MAX_ITERATIONS or 10000

                while (trackPos - startPos) < targetDuration and itemsPlaced < maxIter do
                    local poolEntry = trackPool[poolIndex]
                    if not poolEntry then break end

                    for instance = 1, params.instanceAmount do
                        if (trackPos - startPos) >= targetDuration then break end
                        -- Temporarily set currentPos for this track's placement
                        currentPos = trackPos
                        placePoolEntry(poolEntry, trackTracks, trackIndices)
                        trackPos = currentPos  -- Capture advanced position
                        itemsPlaced = itemsPlaced + 1
                    end

                    poolIndex = poolIndex + 1
                    if poolIndex > #trackPool then
                        poolIndex = 1
                    end
                end
            else
                -- Standard mode: iterate once through shuffled pool per track
                for _, poolEntry in ipairs(trackPool) do
                    for instance = 1, params.instanceAmount do
                        currentPos = trackPos
                        placePoolEntry(poolEntry, trackTracks, trackIndices)
                        trackPos = currentPos
                    end
                end
            end

            -- Track the furthest position across all tracks
            if trackPos > currentPos then
                currentPos = trackPos
            end
        end

    elseif isLoopMode then
        -- Loop mode: cycle through pool until loopDuration is reached
        -- NOTE: Items may extend past loopDuration - this is intentional.
        -- Story 3.2 (loop processing) handles trimming via zero-crossing split/swap.
        local poolIndex = 1
        local itemsPlaced = 0
        local maxIterations = EXPORT.LOOP_MAX_ITERATIONS or 10000

        while (currentPos - startPos) < targetDuration and itemsPlaced < maxIterations do
            local poolEntry = pool[poolIndex]
            if not poolEntry then break end

            -- Story 5.2: Resolve distribution target for Preserve Round-Robin/Random
            local distTracks, distIndices
            if preserveDistribution then
                distTracks, distIndices = getDistributionTarget()
            end

            -- Place for each instance requested
            for instance = 1, params.instanceAmount do
                if (currentPos - startPos) >= targetDuration then break end
                placePoolEntry(poolEntry, distTracks, distIndices)
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
            -- Story 5.2: Resolve distribution target for Preserve Round-Robin/Random
            local distTracks, distIndices
            if preserveDistribution then
                distTracks, distIndices = getDistributionTarget()
            end

            for instance = 1, params.instanceAmount do
                placePoolEntry(poolEntry, distTracks, distIndices)
            end
        end
    end

    return placedItems, currentPos
end

return M
