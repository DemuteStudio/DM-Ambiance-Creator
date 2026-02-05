--[[
@version 1.0
@noindex
DM Ambiance Creator - Export Settings Module
Handles export settings state management, container collection, and parameter resolution.
Migrated from Export_Core.lua with new v2 fields (maxPoolItems, loopMode).
--]]

local M = {}
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
        maxPoolItems = 0,      -- 0 = export all items, >0 = random subset
        loopMode = "auto",     -- "auto" | "on" | "off"
    },
    containerOverrides = {},   -- {[containerKey] = {enabled, params}}
    enabledContainers = {},    -- {[containerKey] = true/false}
    selectedContainerKeys = {}, -- {[containerKey] = true} for multi-selection in UI
}

-- Cache for container list (to support range selection)
local containerListCache = {}

function M.initModule(g)
    if not g then
        error("Export_Settings.initModule: globals parameter is required")
    end
    globals = g
end

-- Reset export settings to defaults
function M.resetSettings()
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
        maxPoolItems = EXPORT.MAX_POOL_ITEMS_DEFAULT or 0,
        loopMode = EXPORT.LOOP_MODE_DEFAULT or "auto",
    }
    exportSettings.containerOverrides = {}
    exportSettings.enabledContainers = {}
    exportSettings.selectedContainerKeys = {}
    containerListCache = {}
end

-- Collect all containers from globals.items (recursive)
function M.collectAllContainers()
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
function M.initializeEnabledContainers()
    local containers = M.collectAllContainers()
    exportSettings.enabledContainers = {}
    for _, c in ipairs(containers) do
        exportSettings.enabledContainers[c.key] = true
    end
end

-- Getters/setters for global params
function M.getGlobalParams()
    return exportSettings.globalParams
end

function M.setGlobalParam(param, value)
    local Constants = globals.Constants
    local EXPORT = Constants and Constants.EXPORT or {}

    -- Validate and clamp numeric parameters
    if param == "instanceAmount" then
        local min = EXPORT.INSTANCE_MIN or 1
        local max = EXPORT.INSTANCE_MAX or 100
        value = math.max(min, math.min(max, value))
    elseif param == "spacing" then
        local min = EXPORT.SPACING_MIN or 0
        local max = EXPORT.SPACING_MAX or 60
        value = math.max(min, math.min(max, value))
    elseif param == "maxPoolItems" then
        value = math.max(0, value)  -- Clamped to pool size at export time
    elseif param == "loopMode" then
        -- Validate loopMode is one of the allowed values
        local validModes = {
            [EXPORT.LOOP_MODE_AUTO or "auto"] = true,
            [EXPORT.LOOP_MODE_ON or "on"] = true,
            [EXPORT.LOOP_MODE_OFF or "off"] = true,
        }
        if not validModes[value] then
            value = EXPORT.LOOP_MODE_DEFAULT or "auto"
        end
    end

    exportSettings.globalParams[param] = value
end

-- Container enabled state (checkbox in list)
function M.isContainerEnabled(containerKey)
    return exportSettings.enabledContainers[containerKey] ~= false
end

function M.setContainerEnabled(containerKey, enabled)
    exportSettings.enabledContainers[containerKey] = enabled
end

-- Container selection state (for multi-selection override editing)
function M.isContainerSelected(containerKey)
    return exportSettings.selectedContainerKeys[containerKey] == true
end

function M.setContainerSelected(containerKey, selected)
    if selected then
        exportSettings.selectedContainerKeys[containerKey] = true
    else
        exportSettings.selectedContainerKeys[containerKey] = nil
    end
end

function M.toggleContainerSelected(containerKey)
    if exportSettings.selectedContainerKeys[containerKey] then
        exportSettings.selectedContainerKeys[containerKey] = nil
    else
        exportSettings.selectedContainerKeys[containerKey] = true
    end
end

function M.clearContainerSelection()
    exportSettings.selectedContainerKeys = {}
end

function M.selectContainerRange(fromKey, toKey)
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

function M.getSelectedContainerCount()
    local count = 0
    for _ in pairs(exportSettings.selectedContainerKeys) do
        count = count + 1
    end
    return count
end

function M.getSelectedContainerKeys()
    local keys = {}
    for key in pairs(exportSettings.selectedContainerKeys) do
        table.insert(keys, key)
    end
    return keys
end

-- Apply a param to all selected containers (for multi-selection editing)
function M.applyParamToSelected(param, value)
    for key in pairs(exportSettings.selectedContainerKeys) do
        local override = exportSettings.containerOverrides[key]
        if override and override.enabled then
            override.params[param] = value
            exportSettings.containerOverrides[key] = override
        end
    end
end

-- Container overrides
function M.getContainerOverride(containerKey)
    return exportSettings.containerOverrides[containerKey]
end

function M.setContainerOverride(containerKey, override)
    exportSettings.containerOverrides[containerKey] = override
end

function M.hasContainerOverride(containerKey)
    return exportSettings.containerOverrides[containerKey] ~= nil
end

-- Get effective params for a container (global or override)
function M.getEffectiveParams(containerKey)
    local override = exportSettings.containerOverrides[containerKey]
    if override and override.enabled then
        return override.params
    end
    return exportSettings.globalParams
end

-- Count enabled containers
function M.getEnabledContainerCount()
    local count = 0
    for _, enabled in pairs(exportSettings.enabledContainers) do
        if enabled then
            count = count + 1
        end
    end
    return count
end

-- Helper: Round to next whole second
function M.roundToNextSecond(position)
    return math.ceil(position)
end

-- NEW v2: Resolve loop mode for a container
-- Returns boolean: true if item should loop, false otherwise
function M.resolveLoopMode(container, params)
    local Constants = globals.Constants
    if params.loopMode == Constants.EXPORT.LOOP_MODE_ON then return true end
    if params.loopMode == Constants.EXPORT.LOOP_MODE_OFF then return false end
    -- "auto": check if container has negative interval in absolute mode
    return container.triggerRate < 0
        and container.intervalMode == Constants.TRIGGER_MODES.ABSOLUTE
end

-- NEW v2: Validate maxPoolItems against actual container pool size
-- Returns clamped value: math.min(maxItems, #container.items) when maxItems > 0, else #container.items
function M.validateMaxPoolItems(container, maxItems)
    if maxItems > 0 then
        return math.min(maxItems, #container.items)
    end
    return #container.items
end

-- NEW v2: Get pool size for a container (total exportable entries: items x areas)
function M.getPoolSize(containerKey)
    local containers = M.collectAllContainers()
    for _, c in ipairs(containers) do
        if c.key == containerKey then
            local container = c.container
            local totalEntries = 0
            for itemIdx, item in ipairs(container.items or {}) do
                local areas = item.areas
                if (not areas or #areas == 0) and globals.waveformAreas then
                    local itemKey = globals.Structures and globals.Structures.makeItemKey
                        and globals.Structures.makeItemKey(c.path, c.containerIndex, itemIdx)
                        or nil
                    if itemKey then
                        areas = globals.waveformAreas[itemKey]
                    end
                end
                if areas and #areas > 0 then
                    totalEntries = totalEntries + #areas
                else
                    totalEntries = totalEntries + 1  -- At least one entry per item
                end
            end
            return totalEntries
        end
    end
    return 0
end

return M
