--[[
@version 1.1
@noindex
DM Ambiance Creator - Export Engine Module
Handles export orchestration, region creation, and export execution.
Migrated from Export_Core.lua (performExport, parseRegionPattern, shallowCopy).
--]]

local M = {}
local globals = {}
local Settings = nil
local Placement = nil

function M.initModule(g)
    if not g then
        error("Export_Engine.initModule: globals parameter is required")
    end
    globals = g
end

function M.setDependencies(settings, placement)
    Settings = settings
    Placement = placement
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

-- Main export function - exports Areas from containers using Generation Engine
-- Delegates to Export_Placement for item placement with correct multichannel support
function M.performExport()
    local containers = Settings.collectAllContainers()
    local enabledContainers = {}

    -- Filter enabled containers
    for _, c in ipairs(containers) do
        if Settings.isContainerEnabled(c.key) then
            table.insert(enabledContainers, c)
        end
    end

    if #enabledContainers == 0 then
        reaper.ShowMessageBox("No containers are enabled for export.", "Export", 0)
        return false, "No containers enabled"
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    local totalItemsExported = 0
    local containerExportIndex = 0

    for _, containerInfo in ipairs(enabledContainers) do
        containerExportIndex = containerExportIndex + 1
        local params = Settings.getEffectiveParams(containerInfo.key)

        -- Get target tracks for this container
        local targetTracks = Placement.resolveTargetTracks(containerInfo, params)
        if #targetTracks == 0 then goto continue end

        -- Get track structure (delegates to Generation engine)
        local trackStructure = Placement.resolveTrackStructure(containerInfo)

        -- Get pool of items to export (stub for now, full implementation in Story 2.1)
        local pool = Placement.resolvePool(containerInfo, params.maxPoolItems)

        -- Place items on tracks using Placement module
        -- This includes the critical multichannel fix using realTrackIdx from trackStructure
        local placedItems = Placement.placeContainerItems(
            pool,
            targetTracks,
            trackStructure,
            params,
            containerInfo
        )

        totalItemsExported = totalItemsExported + #placedItems

        -- Create region for this container if enabled
        if params.createRegions and #placedItems > 0 then
            -- Calculate region bounds from placed items
            local regionStartPos = nil
            local regionEndPos = nil
            for _, placed in ipairs(placedItems) do
                local itemEnd = placed.position + placed.length
                if regionStartPos == nil or placed.position < regionStartPos then
                    regionStartPos = placed.position
                end
                if regionEndPos == nil or itemEnd > regionEndPos then
                    regionEndPos = itemEnd
                end
            end

            if regionStartPos and regionEndPos then
                local regionName = parseRegionPattern(params.regionPattern, containerInfo, containerExportIndex)
                reaper.AddProjectMarker2(0, true, regionStartPos, regionEndPos, regionName, -1, 0)
            end
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

-- Stub: Generate preview of export (full implementation in Story 1.3)
function M.generatePreview(settings)
    return {}
end

-- Stub: Estimate duration of export (full implementation in Story 1.3)
function M.estimateDuration(poolSize, params, container)
    return 0
end

return M
