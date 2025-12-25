--[[
@version 1.4
@noindex
DM Ambiance Creator - Export Core Module
Handles export data structures, settings state, and export logic using the Generation engine.
--]]

local Export_Core = {}
local globals = {}

-- Export settings state
local exportSettings = {
    globalParams = {
        instanceAmount = 1,
        spacing = 1.0,
        alignToSeconds = true,
        exportMethod = 0,  -- 0 = current track, 1 = new track
        preservePan = true,
        preserveVolume = true,
        preservePitch = true,
        createRegions = false,
        regionPattern = "$container",
    },
    containerOverrides = {},   -- {[containerKey] = {enabled, params}}
    enabledContainers = {},    -- {[containerKey] = true/false}
    selectedContainerKeys = {}, -- {[containerKey] = true} for multi-selection in UI
}

-- Cache for container list (to support range selection)
local containerListCache = {}

function Export_Core.initModule(g)
    if not g then
        error("Export_Core.initModule: globals parameter is required")
    end
    globals = g
end

-- Reset export settings to defaults
function Export_Core.resetSettings()
    local Constants = globals.Constants
    local EXPORT = Constants and Constants.EXPORT or {}

    exportSettings.globalParams = {
        instanceAmount = EXPORT.INSTANCE_DEFAULT or 1,
        spacing = EXPORT.SPACING_DEFAULT or 1.0,
        alignToSeconds = EXPORT.ALIGN_TO_SECONDS_DEFAULT ~= false,
        exportMethod = EXPORT.METHOD_DEFAULT or 0,
        preservePan = EXPORT.PRESERVE_PAN_DEFAULT ~= false,
        preserveVolume = EXPORT.PRESERVE_VOLUME_DEFAULT ~= false,
        preservePitch = EXPORT.PRESERVE_PITCH_DEFAULT ~= false,
        createRegions = EXPORT.CREATE_REGIONS_DEFAULT or false,
        regionPattern = EXPORT.REGION_PATTERN_DEFAULT or "$container",
    }
    exportSettings.containerOverrides = {}
    exportSettings.enabledContainers = {}
    exportSettings.selectedContainerKeys = {}
    containerListCache = {}
end

-- Collect all containers from globals.items (recursive)
function Export_Core.collectAllContainers()
    local containers = {}

    local function collectFromItems(items, parentPath)
        for i, item in ipairs(items) do
            local currentPath = {}
            for _, p in ipairs(parentPath) do
                table.insert(currentPath, p)
            end
            table.insert(currentPath, i)

            if item.type == "folder" and item.children then
                collectFromItems(item.children, currentPath)
            elseif item.type == "group" and item.containers then
                for ci, container in ipairs(item.containers) do
                    local key = globals.Utils and globals.Utils.makeContainerKey
                        and globals.Utils.makeContainerKey(currentPath, ci)
                        or (table.concat(currentPath, "_") .. "::" .. ci)
                    table.insert(containers, {
                        path = currentPath,
                        containerIndex = ci,
                        container = container,
                        group = item,
                        key = key,
                        displayName = item.name .. " / " .. container.name,
                    })
                end
            end
        end
    end

    if globals.items then
        collectFromItems(globals.items, {})
    end

    -- Update cache for range selection
    containerListCache = containers

    return containers
end

-- Initialize enabled containers (all enabled by default)
function Export_Core.initializeEnabledContainers()
    local containers = Export_Core.collectAllContainers()
    exportSettings.enabledContainers = {}
    for _, c in ipairs(containers) do
        exportSettings.enabledContainers[c.key] = true
    end
end

-- Getters/setters for global params
function Export_Core.getGlobalParams()
    return exportSettings.globalParams
end

function Export_Core.setGlobalParam(param, value)
    exportSettings.globalParams[param] = value
end

-- Container enabled state (checkbox in list)
function Export_Core.isContainerEnabled(containerKey)
    return exportSettings.enabledContainers[containerKey] ~= false
end

function Export_Core.setContainerEnabled(containerKey, enabled)
    exportSettings.enabledContainers[containerKey] = enabled
end

-- Container selection state (for multi-selection override editing)
function Export_Core.isContainerSelected(containerKey)
    return exportSettings.selectedContainerKeys[containerKey] == true
end

function Export_Core.setContainerSelected(containerKey, selected)
    if selected then
        exportSettings.selectedContainerKeys[containerKey] = true
    else
        exportSettings.selectedContainerKeys[containerKey] = nil
    end
end

function Export_Core.toggleContainerSelected(containerKey)
    if exportSettings.selectedContainerKeys[containerKey] then
        exportSettings.selectedContainerKeys[containerKey] = nil
    else
        exportSettings.selectedContainerKeys[containerKey] = true
    end
end

function Export_Core.clearContainerSelection()
    exportSettings.selectedContainerKeys = {}
end

function Export_Core.selectContainerRange(fromKey, toKey)
    -- Find indices in cached container list
    local fromIdx, toIdx = nil, nil
    for i, c in ipairs(containerListCache) do
        if c.key == fromKey then fromIdx = i end
        if c.key == toKey then toIdx = i end
    end

    if fromIdx and toIdx then
        local startIdx = math.min(fromIdx, toIdx)
        local endIdx = math.max(fromIdx, toIdx)
        for i = startIdx, endIdx do
            local c = containerListCache[i]
            if c then
                exportSettings.selectedContainerKeys[c.key] = true
            end
        end
    end
end

function Export_Core.getSelectedContainerCount()
    local count = 0
    for _ in pairs(exportSettings.selectedContainerKeys) do
        count = count + 1
    end
    return count
end

function Export_Core.getSelectedContainerKeys()
    local keys = {}
    for key in pairs(exportSettings.selectedContainerKeys) do
        table.insert(keys, key)
    end
    return keys
end

-- Apply a param to all selected containers (for multi-selection editing)
function Export_Core.applyParamToSelected(param, value)
    for key in pairs(exportSettings.selectedContainerKeys) do
        local override = exportSettings.containerOverrides[key]
        if override and override.enabled then
            override.params[param] = value
            exportSettings.containerOverrides[key] = override
        end
    end
end

-- Container overrides
function Export_Core.getContainerOverride(containerKey)
    return exportSettings.containerOverrides[containerKey]
end

function Export_Core.setContainerOverride(containerKey, override)
    exportSettings.containerOverrides[containerKey] = override
end

function Export_Core.hasContainerOverride(containerKey)
    return exportSettings.containerOverrides[containerKey] ~= nil
end

-- Get effective params for a container (global or override)
function Export_Core.getEffectiveParams(containerKey)
    local override = exportSettings.containerOverrides[containerKey]
    if override and override.enabled then
        return override.params
    end
    return exportSettings.globalParams
end

-- Count enabled containers
function Export_Core.getEnabledContainerCount()
    local count = 0
    for _, enabled in pairs(exportSettings.enabledContainers) do
        if enabled then
            count = count + 1
        end
    end
    return count
end

-- Helper: Round to next whole second
function Export_Core.roundToNextSecond(position)
    return math.ceil(position)
end

-- Helper: Parse region name pattern and replace tags
-- @param pattern string: The pattern string with tags (e.g., "sfx_$container")
-- @param containerInfo table: Container information with container, group
-- @param containerIndex number: 1-based index of container in export list
-- @return string: The parsed region name
local function parseRegionPattern(pattern, containerInfo, containerIndex)
    local result = pattern
    result = result:gsub("%$container", containerInfo.container.name or "Container")
    result = result:gsub("%$group", containerInfo.group.name or "Group")
    result = result:gsub("%$index", tostring(containerIndex))
    return result
end

-- Helper: Make item key for waveformAreas lookup
local function makeItemKey(path, containerIndex, itemIndex)
    if globals.Structures and globals.Structures.makeItemKey then
        return globals.Structures.makeItemKey(path, containerIndex, itemIndex)
    end
    -- Fallback (replicate Structures logic with comma)
    local pathStr = table.concat(path, ",")
    return pathStr .. "::" .. containerIndex .. "::" .. itemIndex
end

-- Helper: Create a new track for export
local function createExportTrack(containerInfo, channelIndex)
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
local function findTrackByName(groupName, containerName)
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
local function getChildTracks(folderTrack)
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
local function getTargetTracks(containerInfo, params)
    local tracks = {}
    local container = containerInfo.container
    local groupName = containerInfo.group and containerInfo.group.name or ""
    local containerName = container.name or ""

    if params.exportMethod == 1 then  -- New Track
        -- Create new track(s) based on container configuration
        if container.channelMode and container.channelMode > 0 then
            local config = globals.Constants and globals.Constants.CHANNEL_CONFIGS[container.channelMode]
            local numCh = config and config.channels or 0
            
            -- Important: Check if container actually uses split tracks or passthrough
            -- For export, we generally want to replicate the structure or force separate tracks if we want clean stems
            if numCh > 0 then
                -- Multi-channel: create one track per channel
                for i = 1, numCh do
                    local track = createExportTrack(containerInfo, i)
                    table.insert(tracks, track)
                end
            else
                table.insert(tracks, createExportTrack(containerInfo))
            end
        else
            -- Single track
            table.insert(tracks, createExportTrack(containerInfo))
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
                    tracks = getChildTracks(track)
                end

                -- If no children found or it's not a folder, use the track itself
                if #tracks == 0 then
                    table.insert(tracks, track)
                end
            end
        end

        -- Strategy 3: Fallback to name search
        if #tracks == 0 then
            local track = findTrackByName(groupName, containerName)
            if track then
                -- Check if it's a folder track with children
                local folderDepth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
                if folderDepth == 1 then
                    -- It's a folder, get child tracks
                    tracks = getChildTracks(track)
                end

                -- If no children found or it's not a folder, use the track itself
                if #tracks == 0 then
                    table.insert(tracks, track)
                end
            end
        end

        -- Strategy 4: Ultimate fallback - create new track
        if #tracks == 0 then
            table.insert(tracks, createExportTrack(containerInfo))
        end
    end

    return tracks
end

-- Shallow copy of a table
local function shallowCopy(t)
    local t2 = {}
    for k, v in pairs(t) do
        t2[k] = v
    end
    return t2
end

-- Main export function - exports Areas from containers using Generation Engine
function Export_Core.performExport()
    local containers = Export_Core.collectAllContainers()
    local enabledContainers = {}

    -- Filter enabled containers
    for _, c in ipairs(containers) do
        if Export_Core.isContainerEnabled(c.key) then
            table.insert(enabledContainers, c)
        end
    end

    if #enabledContainers == 0 then
        reaper.ShowMessageBox("No containers are enabled for export.", "Export", 0)
        return false, "No containers enabled"
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    local currentPos = reaper.GetCursorPosition()
    local totalItemsExported = 0
    local xfadeshape = reaper.SNM_GetIntConfigVar("defxfadeshape", 0)
    local containerExportIndex = 0

    for _, containerInfo in ipairs(enabledContainers) do
        containerExportIndex = containerExportIndex + 1
        local regionStartPos = nil
        local regionEndPos = nil
        local params = Export_Core.getEffectiveParams(containerInfo.key)
        local container = containerInfo.container
        local group = containerInfo.group

        -- Prepare Generation Parameters (Override randomization based on settings)
        local genParams = shallowCopy(container)
        
        -- Override randomization flags
        -- If preserve is TRUE, we allow the container's randomization (or keep it as is)
        -- If preserve is FALSE, we force randomization to FALSE (flatten)
        -- Wait, logical check: "Preserve Pitch" unchecked usually means "Don't apply random pitch, just plain". 
        -- Actually, user intent: "Preserve" means "Keep the variation". Unchecked means "Remove variation".
        genParams.randomizePitch = container.randomizePitch and params.preservePitch
        genParams.randomizeVolume = container.randomizeVolume and params.preserveVolume
        genParams.randomizePan = container.randomizePan and params.preservePan

        -- Get target tracks
        local targetTracks = getTargetTracks(containerInfo, params)
        if #targetTracks == 0 then goto continue end

        -- Analyze Track Structure for Channel Selection
        local itemsAnalysis = globals.Generation.analyzeContainerItems(container)
        local trackStructure = globals.Generation.determineTrackStructure(container, itemsAnalysis)

        -- Iterate items in container
        for itemIdx, item in ipairs(container.items or {}) do
            if not item.filePath then goto nextItem end

            -- Get Areas for this item
            local itemKey = makeItemKey(containerInfo.path, containerInfo.containerIndex, itemIdx)
            local areas = item.areas
            if (not areas or #areas == 0) and globals.waveformAreas then
                areas = globals.waveformAreas[itemKey]
            end
            if not areas or #areas == 0 then
                areas = {{ startPos = 0, endPos = item.length or 10, name = item.name or "Full" }}
            end

            -- For each Area
            for _, area in ipairs(areas) do
                -- Construct Item Data for Generation
                local itemData = {
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

                -- For each instance requested
                for instance = 1, params.instanceAmount do
                    -- Calculate aligned position
                    local itemPos = currentPos
                    if params.alignToSeconds then
                        itemPos = Export_Core.roundToNextSecond(currentPos)
                    end

                    local actualLen = 0
                    local anyItemCreated = false

                    -- Place item on target tracks
                    -- If we have multiple target tracks (Multi-channel), we place on each
                    for tIdx, track in ipairs(targetTracks) do
                        -- Use placeSingleItem from Generation Engine
                        -- This handles channel selection, routing, randomization, and fades consistently
                        -- Pass ignoreBounds=true to ignore project time selection limits
                        local newItem, length = globals.Generation.placeSingleItem(
                            track,
                            itemData,
                            itemPos,
                            genParams,
                            trackStructure,
                            tIdx, -- trackIdx (real index for channel extraction)
                            trackStructure.channelSelectionMode,
                            true -- ignoreBounds
                        )
                        
                        if newItem then
                            anyItemCreated = true
                            actualLen = math.max(actualLen, length)
                        end
                    end

                    if anyItemCreated then
                        totalItemsExported = totalItemsExported + 1
                        -- Track region bounds
                        local itemEnd = itemPos + actualLen
                        if regionStartPos == nil then
                            regionStartPos = itemPos
                        end
                        regionEndPos = math.max(regionEndPos or itemEnd, itemEnd)
                        -- Advance position
                        currentPos = itemPos + actualLen + params.spacing
                        if params.alignToSeconds and params.spacing > 0 then
                            currentPos = Export_Core.roundToNextSecond(currentPos)
                        end
                    end
                end
            end

            ::nextItem::
        end

        -- Create region for this container if enabled
        if params.createRegions and regionStartPos and regionEndPos then
            local regionName = parseRegionPattern(params.regionPattern, containerInfo, containerExportIndex)
            reaper.AddProjectMarker2(0, true, regionStartPos, regionEndPos, regionName, -1, 0)
        end

        ::continue::
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Export Ambiance Areas", -1)

    local message = string.format("Exported %d items", totalItemsExported)
    reaper.ShowMessageBox(message, "Export Complete", 0)

    return true, message
end

return Export_Core