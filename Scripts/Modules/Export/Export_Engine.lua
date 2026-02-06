--[[
@version 1.4
@noindex
DM Ambiance Creator - Export Engine Module
Handles export orchestration, region creation, and export execution.
Migrated from Export_Core.lua (performExport, parseRegionPattern, shallowCopy).
v1.2: Added instanceCount to PreviewEntry, optimized pool size calculation, fixed trackType default.
v1.3: Story 2.1 - Added validateMaxPoolItems() call before resolvePool(), empty pool handling.
v1.4: Code review fixes - math.randomseed moved here (once per export), validateMaxPoolItems uses containerInfo, empty pool warning.
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

    -- Seed random ONCE at export start for consistent randomness across all containers
    -- (os.time() has 1-second resolution, so seeding per-container could cause duplicates)
    math.randomseed(os.time())

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

        -- Validate and clamp maxPoolItems to actual pool size (AC #3, #4)
        -- Pass full containerInfo to account for waveformAreas in pool size calculation
        local validatedMax = Settings.validateMaxPoolItems(containerInfo, params.maxPoolItems)

        -- Get pool of PoolEntry objects (item + area pre-resolved)
        local pool = Placement.resolvePool(containerInfo, validatedMax)

        -- Handle empty pool gracefully with warning
        if #pool == 0 then
            reaper.ShowConsoleMsg("[Export] Warning: Skipping container '"
                .. (containerInfo.container.name or "Unknown")
                .. "' - no items in pool\n")
            goto continue
        end

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

-- Generate preview of export showing per-container summary
-- @return table: Array of PreviewEntry objects
function M.generatePreview()
    local previewEntries = {}

    local containers = Settings.collectAllContainers()

    for _, containerInfo in ipairs(containers) do
        if not Settings.isContainerEnabled(containerInfo.key) then
            goto nextContainer
        end

        local params = Settings.getEffectiveParams(containerInfo.key)
        local container = containerInfo.container

        -- Get total pool size (use optimized version since we have containerInfo)
        local poolTotal = Settings.calculatePoolSizeFromInfo
            and Settings.calculatePoolSizeFromInfo(containerInfo)
            or Settings.getPoolSize(containerInfo.key)

        -- Calculate poolSelected based on maxPoolItems
        local poolSelected
        if params.maxPoolItems > 0 and params.maxPoolItems < poolTotal then
            poolSelected = params.maxPoolItems
        else
            poolSelected = poolTotal
        end

        -- Resolve loop mode
        local loopModeResolved = Settings.resolveLoopMode(container, params)
        local loopModeAuto = (params.loopMode == "auto" and loopModeResolved)

        -- Resolve track structure (may error if Generation not available)
        -- Default to mono for single track (consistent with trackCount=1)
        local trackCount = 1
        local trackType = "mono"
        if Placement and globals.Generation then
            local ok, trackStructure = pcall(Placement.resolveTrackStructure, containerInfo)
            if ok and trackStructure then
                trackCount = trackStructure.numTracks or 1
                trackType = trackStructure.trackType or "stereo"
            end
        end

        -- Estimate duration
        local estimatedDuration = M.estimateDuration(poolSelected, params, container)

        -- Build PreviewEntry (includes instanceCount per Architecture 3.4)
        table.insert(previewEntries, {
            name = containerInfo.displayName,
            poolTotal = poolTotal,
            poolSelected = poolSelected,
            loopMode = loopModeResolved,
            loopModeAuto = loopModeAuto,
            trackCount = trackCount,
            trackType = trackType,
            estimatedDuration = estimatedDuration,
            instanceCount = params.instanceAmount or 1,
        })

        ::nextContainer::
    end

    return previewEntries
end

-- Estimate total duration of export for a container
-- @param poolSize number: Number of items/areas that will be exported
-- @param params table: Export params with instanceAmount, spacing
-- @param container table: Container object with items for avg length calculation
-- @return number: Estimated duration in seconds
function M.estimateDuration(poolSize, params, container)
    if poolSize == 0 then return 0 end

    -- Calculate average item length from container items or use default
    local avgItemLength = 5.0  -- Default: 5 seconds
    if container and container.items and #container.items > 0 then
        local totalLength = 0
        local itemCount = 0
        for _, item in ipairs(container.items) do
            if item.length and item.length > 0 then
                totalLength = totalLength + item.length
                itemCount = itemCount + 1
            end
        end
        if itemCount > 0 then
            avgItemLength = totalLength / itemCount
        end
    end

    -- Calculate total items: poolSize * instanceAmount
    local totalItems = poolSize * (params.instanceAmount or 1)

    -- Calculate duration: (totalItems * avgItemLength) + ((totalItems - 1) * spacing)
    local spacing = params.spacing or 0
    local duration = (totalItems * avgItemLength)
    if totalItems > 1 then
        duration = duration + ((totalItems - 1) * spacing)
    end

    -- If loop mode is enabled, check if loopDuration is specified
    local loopMode = params.loopMode or "auto"
    if loopMode == "on" or (loopMode == "auto" and container and container.triggerRate and container.triggerRate < 0) then
        -- For loop mode, return estimated duration based on items
        -- (loopDuration from params could override this in future Story 3.2)
        if params.loopDuration and params.loopDuration > 0 then
            return params.loopDuration
        end
    end

    return duration
end

return M
