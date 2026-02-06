--[[
@version 1.13
@noindex
DM Ambiance Creator - Export Engine Module
Handles export orchestration, region creation, and export execution.
Migrated from Export_Core.lua (performExport, parseRegionPattern, shallowCopy).
v1.2: Added instanceCount to PreviewEntry, optimized pool size calculation, fixed trackType default.
v1.3: Story 2.1 - Added validateMaxPoolItems() call before resolvePool(), empty pool handling.
v1.4: Code review fixes - math.randomseed moved here (once per export), validateMaxPoolItems uses containerInfo, empty pool warning.
v1.5: Story 3.1 - Added loopDuration to PreviewEntry, updated estimateDuration for loop mode.
      Code review fix: estimateDuration now uses Settings.resolveLoopMode for consistency.
v1.6: Story 3.2 - Integrated Export_Loop for zero-crossing loop processing (split/swap).
v1.7: Code review fixes - Region bounds now include loop-created items, totalItemsExported counts split items.
v1.8: Story 4.1 - Sequential container placement for batch export. Each container starts after
      previous container ends, preventing overlap. Uses globalParams.spacing for container spacing.
v1.9: Code review fixes - containerSpacing from global params, Loop module warning in loop mode.
v1.10: Bug fix - Reposition loop container items after split/swap to prevent overlap with previous container.
v1.11: Bug fix - Read actual item bounds from REAPER after loop processing for accurate spacing and regions.
v1.12: Bug fix - Calculate actual endPosition for ALL containers (not just loops) to ensure consistent spacing.
v1.13: Story 4.1 fix - Apply crossfades to overlapping items after placement using Utils.applyCrossfadesToTrack.
--]]

local M = {}
local globals = {}
local Settings = nil
local Placement = nil
local Loop = nil

function M.initModule(g)
    if not g then
        error("Export_Engine.initModule: globals parameter is required")
    end
    globals = g
end

function M.setDependencies(settings, placement, loop)
    Settings = settings
    Placement = placement
    Loop = loop
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

    -- Story 4.1: Track cumulative position for sequential container placement
    -- Each container starts after the previous one ends (plus spacing)
    local currentExportPosition = reaper.GetCursorPosition()
    -- Use global spacing param for container spacing (allows user control via UI)
    local globalParams = Settings.getGlobalParams()
    local containerSpacing = globalParams.spacing or 1.0

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
        -- Story 4.1: Pass currentExportPosition for sequential placement
        local placedItems, endPosition = Placement.placeContainerItems(
            pool,
            targetTracks,
            trackStructure,
            params,
            containerInfo,
            currentExportPosition
        )

        -- Process loop if in loop mode (Story 3.2: zero-crossing split/swap)
        local isLoopMode = Settings.resolveLoopMode(containerInfo.container, params)
        local loopNewItems = {} -- Track new items created by loop processing
        -- Warn if loop mode enabled but Loop module not available
        if isLoopMode and not Loop then
            reaper.ShowConsoleMsg("[Export] Warning: Loop mode enabled for '"
                .. (containerInfo.container.name or "Unknown")
                .. "' but Export_Loop module not loaded. Loop processing skipped.\n")
        end
        if isLoopMode and Loop and #placedItems > 1 then
            local loopResult = Loop.processLoop(placedItems, targetTracks)
            if loopResult.warnings then
                for _, warn in ipairs(loopResult.warnings) do
                    reaper.ShowConsoleMsg("[Export] Warning: " .. warn .. "\n")
                end
            end
            if loopResult.errors then
                for _, err in ipairs(loopResult.errors) do
                    reaper.ShowConsoleMsg("[Export] Error: " .. err .. "\n")
                end
            end
            -- Capture new items created by split/swap for region bounds calculation
            if loopResult.newItems then
                loopNewItems = loopResult.newItems
            end

            -- v1.10: Reposition all items if loop processing moved items before container start
            -- This prevents overlap with the previous container
            if #loopNewItems > 0 then
                -- Find minimum position among all items (original + loop-created)
                local minPosition = currentExportPosition
                for _, newItem in ipairs(loopNewItems) do
                    if newItem.position < minPosition then
                        minPosition = newItem.position
                    end
                end

                -- If items were placed before container start, shift everything right
                if minPosition < currentExportPosition then
                    local shiftAmount = currentExportPosition - minPosition

                    -- Shift original placed items
                    for _, placed in ipairs(placedItems) do
                        if reaper.ValidatePtr(placed.item, "MediaItem*") then
                            local currentPos = reaper.GetMediaItemInfo_Value(placed.item, "D_POSITION")
                            reaper.SetMediaItemPosition(placed.item, currentPos + shiftAmount, false)
                            placed.position = placed.position + shiftAmount
                        end
                    end

                    -- Shift loop-created items
                    for _, newItem in ipairs(loopNewItems) do
                        if reaper.ValidatePtr(newItem.item, "MediaItem*") then
                            local currentPos = reaper.GetMediaItemInfo_Value(newItem.item, "D_POSITION")
                            reaper.SetMediaItemPosition(newItem.item, currentPos + shiftAmount, false)
                            newItem.position = newItem.position + shiftAmount
                        end
                    end

                    -- Update endPosition to account for the shift
                    endPosition = endPosition + shiftAmount
                end
            end

        end

        -- Count includes original items plus any new items from loop split
        totalItemsExported = totalItemsExported + #placedItems + #loopNewItems

        -- v1.12: Calculate actual endPosition for ALL containers (not just loops)
        -- placeContainerItems returns currentPos which includes item spacing, but we need actual item bounds
        -- This ensures consistent spacing between containers regardless of type (normal vs loop)
        if #placedItems > 0 then
            local actualEndPosition = currentExportPosition
            for _, placed in ipairs(placedItems) do
                if reaper.ValidatePtr(placed.item, "MediaItem*") then
                    local itemPos = reaper.GetMediaItemInfo_Value(placed.item, "D_POSITION")
                    local itemLen = reaper.GetMediaItemInfo_Value(placed.item, "D_LENGTH")
                    local itemEnd = itemPos + itemLen
                    if itemEnd > actualEndPosition then
                        actualEndPosition = itemEnd
                    end
                    -- Update cached values for region calculation
                    placed.position = itemPos
                    placed.length = itemLen
                end
            end
            -- Include loop-created items in end position calculation
            for _, newItem in ipairs(loopNewItems) do
                if reaper.ValidatePtr(newItem.item, "MediaItem*") then
                    local itemPos = reaper.GetMediaItemInfo_Value(newItem.item, "D_POSITION")
                    local itemLen = reaper.GetMediaItemInfo_Value(newItem.item, "D_LENGTH")
                    local itemEnd = itemPos + itemLen
                    if itemEnd > actualEndPosition then
                        actualEndPosition = itemEnd
                    end
                    -- Update cached values for region calculation
                    newItem.position = itemPos
                    newItem.length = itemLen
                end
            end
            endPosition = actualEndPosition
        end

        -- v1.13: Apply crossfades to overlapping items on each target track
        -- This matches the behavior of the generator which calls Utils.applyCrossfadesToTrack
        if globals.Utils and globals.Utils.applyCrossfadesToTrack then
            for _, track in ipairs(targetTracks) do
                globals.Utils.applyCrossfadesToTrack(track)
            end
        end

        -- Create region for this container if enabled
        if params.createRegions and #placedItems > 0 then
            -- Calculate region bounds from placed items AND loop-created items
            local regionStartPos = nil
            local regionEndPos = nil

            -- Include original placed items
            for _, placed in ipairs(placedItems) do
                local itemEnd = placed.position + placed.length
                if regionStartPos == nil or placed.position < regionStartPos then
                    regionStartPos = placed.position
                end
                if regionEndPos == nil or itemEnd > regionEndPos then
                    regionEndPos = itemEnd
                end
            end

            -- Include new items created by loop processing (split rightParts moved to start)
            for _, newItem in ipairs(loopNewItems) do
                local itemEnd = newItem.position + newItem.length
                if regionStartPos == nil or newItem.position < regionStartPos then
                    regionStartPos = newItem.position
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

        -- Story 4.1: Update position for next container (sequential placement)
        -- Use endPosition from placeContainerItems, add spacing between containers
        if #placedItems > 0 and endPosition then
            currentExportPosition = endPosition + containerSpacing
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
            loopDuration = loopModeResolved and (params.loopDuration or 30) or nil,
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

    -- If loop mode is enabled, return loopDuration as the estimated duration
    -- Use resolveLoopMode for consistency with actual export behavior
    local isLoopMode = Settings and Settings.resolveLoopMode
        and Settings.resolveLoopMode(container, params)
        or false
    if isLoopMode then
        -- For loop mode, loopDuration defines the target duration
        if params.loopDuration and params.loopDuration > 0 then
            return params.loopDuration
        end
    end

    return duration
end

return M
