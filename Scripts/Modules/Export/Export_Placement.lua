--[[
@version 1.13
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
v1.13 (2026-02-07): Story 5.3 - placeContainerItems() now returns effectiveInterval as third return value.
       Enables Export_Loop to maintain consistent overlap after split/swap for seamless loops.
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

-- Place a single pool entry at specified position on given tracks
-- Replaces closure to eliminate upvalue mutation (Code Review H2)
-- @param poolEntry table: PoolEntry object { item, area, itemIdx, itemKey }
-- @param placementTracks table: Tracks to place on
-- @param placementIndices table: Real track indices for channel extraction
-- @param currentPos number: Timeline position in seconds
-- @param params table: Export params with alignToSeconds
-- @param genParams table: Generation params for placeSingleItem
-- @param effectiveTrackStructure table: Track structure with channel selection mode
-- @param effectiveInterval number: Interval between items
-- @param placedItems table: Output array to append PlacedItem records
-- @return number: New position after placement (or currentPos if nothing placed)
local function placeSinglePoolEntry(poolEntry, placementTracks, placementIndices, currentPos, params, genParams, effectiveTrackStructure, effectiveInterval, placedItems)
    -- Story 4.3 fix: Nil filePath should throw error, not silently skip
    if not poolEntry.item.filePath then
        error("Item has no file path configured")
    end

    -- Story 4.3: Check if source file exists before attempting placement
    local filePath = poolEntry.item.filePath
    if not reaper.file_exists(filePath) then
        error("Missing source file: " .. filePath, 0)
    end

    local itemData = M.buildItemData(poolEntry.item, poolEntry.area)
    -- Story 5.4: Don't align to seconds in loop mode with overlap (negative interval)
    local itemPos
    if effectiveInterval < 0 then
        itemPos = currentPos  -- Preserve precise positioning for overlaps
    else
        itemPos = M.calculatePosition(currentPos, params)
    end
    local actualLen = 0
    local anyItemCreated = false

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
        local newPos = itemPos + actualLen + effectiveInterval
        -- Clamp to prevent negative progress (overlap cannot exceed item length)
        if newPos <= currentPos then
            newPos = currentPos + 0.001
        end
        -- Optionally align after interval
        if params.alignToSeconds and effectiveInterval > 0 then
            newPos = math.ceil(newPos)
        end
        return newPos
    end

    return currentPos
end

-- Resolve distribution target tracks for Round-Robin or Random modes
-- Replaces closure to eliminate shared upvalue (Code Review H2)
-- @param distributionMode number: 0 = Round-Robin, 1 = Random
-- @param distributionCounter number: Current counter for Round-Robin (passed by reference via return)
-- @param effectiveTargetTracks table: Array of tracks to distribute across
-- @param effectiveTrackStructure table: Track structure with trackIndices
-- @return table: Single-element array with target track
-- @return table: Single-element array with real track index
-- @return number: Updated distribution counter (for Round-Robin)
local function getDistributionTargetTracks(distributionMode, distributionCounter, effectiveTargetTracks, effectiveTrackStructure)
    local targetIdx
    local newCounter = distributionCounter

    if distributionMode == 0 then
        -- Round-Robin: cycle through tracks sequentially
        newCounter = newCounter + 1
        targetIdx = ((newCounter - 1) % #effectiveTargetTracks) + 1
    else
        -- Random: pick random track per pool entry
        targetIdx = math.random(1, #effectiveTargetTracks)
    end

    local track = effectiveTargetTracks[targetIdx]
    local realIdx = effectiveTrackStructure.trackIndices
        and effectiveTrackStructure.trackIndices[targetIdx] or targetIdx

    return {track}, {realIdx}, newCounter
end

-- Place items in All Tracks mode (distributionMode == 2)
-- Each track gets independent sequence from shuffled pool
-- Code Review H1: Extracted to reduce placeContainerItems complexity
-- @return table: placedItems array
-- @return number: Final position (furthest across all tracks)
local function placeItemsAllTracksMode(pool, effectiveTargetTracks, effectiveTrackStructure, startPos, params, genParams, effectiveInterval, isLoopMode, targetDuration, placedItems)
    local Constants = globals.Constants
    local EXPORT = Constants and Constants.EXPORT or {}
    local furthestPos = startPos

    for tIdx, track in ipairs(effectiveTargetTracks) do
        local realIdx = effectiveTrackStructure.trackIndices
            and effectiveTrackStructure.trackIndices[tIdx] or tIdx
        local trackPos = startPos
        local trackTracks = {track}
        local trackIndices = {realIdx}

        -- Shuffle independent copy of pool for this track
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
                    trackPos = placeSinglePoolEntry(poolEntry, trackTracks, trackIndices, trackPos, params, genParams, effectiveTrackStructure, effectiveInterval, placedItems)
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
                    trackPos = placeSinglePoolEntry(poolEntry, trackTracks, trackIndices, trackPos, params, genParams, effectiveTrackStructure, effectiveInterval, placedItems)
                end
            end
        end

        -- Track furthest position across all tracks
        if trackPos > furthestPos then
            furthestPos = trackPos
        end
    end

    return placedItems, furthestPos
end

-- Place items in Loop mode (non-All Tracks)
-- Cycles through pool until targetDuration reached
-- Code Review H1: Extracted to reduce placeContainerItems complexity
-- @return table: placedItems array
-- @return number: Final position
local function placeItemsLoopMode(pool, effectiveTargetTracks, effectiveTrackStructure, startPos, params, genParams, effectiveInterval, targetDuration, preserveDistribution, distributionMode, distributionCounter, placedItems)
    local Constants = globals.Constants
    local EXPORT = Constants and Constants.EXPORT or {}
    local currentPos = startPos
    local poolIndex = 1
    local itemsPlaced = 0
    local maxIterations = EXPORT.LOOP_MAX_ITERATIONS or 10000

    while (currentPos - startPos) < targetDuration and itemsPlaced < maxIterations do
        local poolEntry = pool[poolIndex]
        if not poolEntry then break end

        -- Place for each instance requested
        -- Code Review M3: Advance distribution counter PER INSTANCE (not per pool entry)
        for instance = 1, params.instanceAmount do
            if (currentPos - startPos) >= targetDuration then break end

            -- Resolve distribution target for Preserve Round-Robin/Random
            local distTracks, distIndices
            if preserveDistribution then
                distTracks, distIndices, distributionCounter = getDistributionTargetTracks(distributionMode, distributionCounter, effectiveTargetTracks, effectiveTrackStructure)
            else
                distTracks = effectiveTargetTracks
                distIndices = effectiveTrackStructure.trackIndices
            end

            currentPos = placeSinglePoolEntry(poolEntry, distTracks, distIndices, currentPos, params, genParams, effectiveTrackStructure, effectiveInterval, placedItems)
            itemsPlaced = itemsPlaced + 1
        end

        -- Cycle through pool
        poolIndex = poolIndex + 1
        if poolIndex > #pool then
            poolIndex = 1
        end
    end

    return placedItems, currentPos
end

-- Place items in Standard mode (non-loop, non-All Tracks)
-- Single pass through pool with optional distribution
-- Code Review H1: Extracted to reduce placeContainerItems complexity
-- Code Review M3: Distribution counter now advances per instance (matching Generation engine)
-- @return table: placedItems array
-- @return number: Final position
local function placeItemsStandardMode(pool, effectiveTargetTracks, effectiveTrackStructure, startPos, params, genParams, effectiveInterval, preserveDistribution, distributionMode, distributionCounter, placedItems)
    local currentPos = startPos

    for _, poolEntry in ipairs(pool) do
        -- Place for each instance requested
        -- Code Review M3: Advance distribution counter PER INSTANCE (not per pool entry)
        for instance = 1, params.instanceAmount do
            -- Resolve distribution target for Preserve Round-Robin/Random
            local distTracks, distIndices
            if preserveDistribution then
                distTracks, distIndices, distributionCounter = getDistributionTargetTracks(distributionMode, distributionCounter, effectiveTargetTracks, effectiveTrackStructure)
            else
                distTracks = effectiveTargetTracks
                distIndices = effectiveTrackStructure.trackIndices
            end

            currentPos = placeSinglePoolEntry(poolEntry, distTracks, distIndices, currentPos, params, genParams, effectiveTrackStructure, effectiveInterval, placedItems)
        end
    end

    return placedItems, currentPos
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
-- Code Review H1: Refactored from 281 lines to ~60 lines by extracting helpers
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
-- @return number: effectiveInterval used for item spacing (negative for overlap). Used by
--        Export_Loop for maintaining consistent overlap after split/swap (Story 5.3).
function M.placeContainerItems(pool, targetTracks, trackStructure, params, containerInfo, startPosition)
    local placedItems = {}
    local startPos = startPosition or reaper.GetCursorPosition()
    if startPos < 0 then
        startPos = 0
    end

    local genParams = M.buildGenParams(params, containerInfo)
    local container = containerInfo.container
    local Constants = globals.Constants
    local EXPORT = Constants and Constants.EXPORT or {}

    -- Story 5.2: Multichannel export mode handling
    local multichannelMode = params.multichannelExportMode
        or EXPORT.MULTICHANNEL_EXPORT_MODE_DEFAULT or "flatten"
    local isFlattenMode = (multichannelMode == (EXPORT.MULTICHANNEL_EXPORT_MODE_FLATTEN or "flatten"))
    local isPreserveMode = (multichannelMode == (EXPORT.MULTICHANNEL_EXPORT_MODE_PRESERVE or "preserve"))

    -- Code Review L2: Defensive guard for invalid mode
    if not isFlattenMode and not isPreserveMode then
        error(string.format("Invalid multichannelExportMode: %s (must be 'flatten' or 'preserve')", tostring(multichannelMode)), 0)
    end

    -- Apply flatten mode: restrict to first track, disable channel extraction
    local effectiveTargetTracks = targetTracks
    local effectiveTrackStructure = trackStructure
    if isFlattenMode and #targetTracks > 1 then
        effectiveTargetTracks = {targetTracks[1]}
        effectiveTrackStructure = {}
        for k, v in pairs(trackStructure) do
            effectiveTrackStructure[k] = v
        end
        effectiveTrackStructure.channelSelectionMode = "none"
        effectiveTrackStructure.needsChannelSelection = false
        if trackStructure.trackIndices then
            effectiveTrackStructure.trackIndices = {trackStructure.trackIndices[1]}
        end
    end

    -- Resolve loop mode and effective interval
    local isLoopMode = Settings and Settings.resolveLoopMode(container, params) or false
    local effectiveInterval
    if isLoopMode then
        if (params.loopInterval or 0) ~= 0 then
            effectiveInterval = params.loopInterval
        elseif container.triggerRate and container.triggerRate < 0 then
            effectiveInterval = container.triggerRate
        else
            effectiveInterval = 0
        end
    else
        -- Standard mode: respect container interval
        -- Story 5.4: Use container.triggerRate if defined (ABSOLUTE mode only)
        local intervalMode = container.intervalMode or Constants.TRIGGER_MODES.ABSOLUTE
        if container.triggerRate
            and container.triggerRate > 0
            and intervalMode == Constants.TRIGGER_MODES.ABSOLUTE then
            -- Use container's configured interval (positive absolute mode)
            effectiveInterval = container.triggerRate
        else
            -- Fallback to global spacing for:
            -- - No triggerRate defined
            -- - triggerRate is 0
            -- - Non-ABSOLUTE modes (RELATIVE, COVERAGE, CHUNK)
            effectiveInterval = params.spacing or 0
        end
    end
    local targetDuration = isLoopMode and (params.loopDuration or 30) or math.huge

    -- Story 5.2: Determine distribution mode and flags
    local preserveDistribution = false
    local distributionCounter = 0
    local distributionMode = container.itemDistributionMode or 0
    local isAllTracksMode = false

    if isPreserveMode and #effectiveTargetTracks > 1 then
        if effectiveTrackStructure.useSmartRouting then
            preserveDistribution = false
        elseif effectiveTrackStructure.useDistribution then
            if distributionMode == 2 then
                isAllTracksMode = true
            else
                preserveDistribution = true
            end
        end
    end

    -- Route to appropriate placement strategy
    local finalPos
    if isAllTracksMode then
        placedItems, finalPos = placeItemsAllTracksMode(pool, effectiveTargetTracks, effectiveTrackStructure, startPos, params, genParams, effectiveInterval, isLoopMode, targetDuration, placedItems)
    elseif isLoopMode then
        placedItems, finalPos = placeItemsLoopMode(pool, effectiveTargetTracks, effectiveTrackStructure, startPos, params, genParams, effectiveInterval, targetDuration, preserveDistribution, distributionMode, distributionCounter, placedItems)
    else
        placedItems, finalPos = placeItemsStandardMode(pool, effectiveTargetTracks, effectiveTrackStructure, startPos, params, genParams, effectiveInterval, preserveDistribution, distributionMode, distributionCounter, placedItems)
    end

    return placedItems, finalPos, effectiveInterval
end

return M
