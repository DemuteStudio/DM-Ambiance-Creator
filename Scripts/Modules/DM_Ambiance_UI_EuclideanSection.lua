--[[
@version 1.5
@noindex
--]]

--[[
  DM_Ambiance_UI_EuclideanSection.lua

  Euclidean rhythm visualization and pattern management UI components.

  Extracted from the monolithic DM_Ambiance_UI.lua as part of UI refactoring.
  Handles:
  - Circle visualization with multi-layer euclidean rhythms
  - Pattern preset browser modal
  - Saved patterns list management (save/override/delete/load)
--]]

local EuclideanSection = {}
local globals = {}
local imgui  -- Cached reference to imgui module

-- ============================================================================
-- MODULE INITIALIZATION
-- ============================================================================

function EuclideanSection.initModule(g)
    globals = g
    imgui = globals.imgui  -- Cache imgui reference for performance
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--- Get color for a euclidean layer (delegates to EuclideanUI module)
-- @param layerIndex number Layer index (1-based)
-- @param alpha number Optional alpha override (0.0-1.0)
-- @return number ImGui color (0xRRGGBBAA)
local function getEuclideanLayerColor(layerIndex, alpha)
    return globals.EuclideanUI.getLayerColor(layerIndex, alpha)
end

-- ============================================================================
-- EUCLIDEAN PREVIEW VISUALIZATION
-- ============================================================================

--- Draw euclidean rhythm preview circles with multi-layer support
-- Visualizes euclidean patterns as circular rhythms with colored dots.
-- Supports two modes:
-- 1. Auto-Bind Mode (groups): Multiple concentric circles, one per bound container
-- 2. Manual Mode: Single circle with all layers combined
--
-- @param dataObj table Container or group object with euclidean parameters
-- @param size number Diameter of the preview area in pixels
-- @param isGroup boolean True if dataObj is a group, false if container
function EuclideanSection.drawEuclideanPreview(dataObj, size, isGroup)
    -- Determine if we're in auto-bind mode
    local isAutoBind = isGroup and (dataObj.euclideanAutoBindContainers or false)

    -- Get layers data based on mode
    local layers = {}
    local layerNames = {}  -- Container names for auto-bind mode
    local selectedIndex = 1

    if isAutoBind then
        -- AUTO-BIND MODE: Combine parent binding + container's own layers for each container
        if dataObj.euclideanBindingOrder then
            for i, uuid in ipairs(dataObj.euclideanBindingOrder) do
                if dataObj.euclideanLayerBindings and dataObj.euclideanLayerBindings[uuid] then
                    -- Find container by UUID
                    local container = nil
                    local containerName = "???"
                    if dataObj.containers then
                        for _, c in ipairs(dataObj.containers) do
                            if c.id == uuid then
                                container = c
                                containerName = c.name
                                break
                            end
                        end
                    end

                    -- Build combined layer list for this container
                    local containerLayers = {}

                    -- Start with parent binding layers (now an array)
                    local parentBindingLayers = dataObj.euclideanLayerBindings[uuid]
                    if parentBindingLayers then
                        for _, bindingLayer in ipairs(parentBindingLayers) do
                            table.insert(containerLayers, {
                                pulses = bindingLayer.pulses,
                                steps = bindingLayer.steps,
                                rotation = bindingLayer.rotation,
                            })
                        end
                    end

                    -- NOTE: Do NOT add container.euclideanLayers here even if in Override mode
                    -- When a container is in Override + Euclidean, its layers are synchronized
                    -- with the parent binding layers (see setEuclideanLayer* callbacks).
                    -- So the parent binding already contains the container's layers.

                    -- Store as array of layers (each circle = multiple layers combined)
                    table.insert(layers, containerLayers)
                    table.insert(layerNames, containerName)
                end
            end
        end
        selectedIndex = dataObj.euclideanSelectedBindingIndex or 1
    else
        -- MANUAL MODE: Combine all layers into a single circle (like Auto-Bind mode)
        layers = {}
        local sourceLayers = dataObj.euclideanLayers
        if not sourceLayers or #sourceLayers == 0 then
            sourceLayers = {{pulses = 8, steps = 16, rotation = 0}}
        end

        -- Combine all layers into a single array (same as Auto-Bind containers)
        local combinedLayers = {}
        for _, layer in ipairs(sourceLayers) do
            table.insert(combinedLayers, {
                pulses = layer.pulses,
                steps = layer.steps,
                rotation = layer.rotation,
            })
        end
        table.insert(layers, combinedLayers)  -- Single circle with all layers combined

        selectedIndex = 1  -- Only one circle to select
    end

    local layerCount = #layers

    local drawList = imgui.GetWindowDrawList(globals.ctx)
    local cursorX, cursorY = imgui.GetCursorScreenPos(globals.ctx)

    -- Background
    local bgColor = 0x202020FF
    imgui.DrawList_AddRectFilled(drawList, cursorX, cursorY, cursorX + size, cursorY + size, bgColor)

    -- Border
    local borderColor = 0x666666FF
    imgui.DrawList_AddRect(drawList, cursorX, cursorY, cursorX + size, cursorY + size, borderColor)

    -- Calculate circle layout
    local padding = 10
    local centerX = cursorX + size / 2
    local centerY = cursorY + size / 2
    local maxRadius = (size / 2) - padding

    -- Colors for empty dots and guide circle
    local emptyColor = 0x666666FF
    local guideColor = 0x444444FF
    local selectedGuideColor = 0x777777FF

    -- Draw layers
    -- Both modes now use the same structure: each element in 'layers' is a circle with combined patterns
    -- Auto-Bind mode: concentric circles (one per container, largest to smallest, outer to inner)
    -- Manual mode: single circle with all layers combined
    local drawOrder = 1
    local drawStep = 1
    local drawEnd = layerCount

    for layerIdx = drawOrder, drawEnd, drawStep do
        -- Each element in 'layers' is now an array of patterns to combine
        local layerPatterns = layers[layerIdx]

        -- Calculate radius based on mode
        local currentRadius
        if isAutoBind then
            -- Auto-Bind: Concentric circles (each layer gets smaller radius)
            local radiusRatio = 1.0 - ((layerIdx - 1) * 0.16)  -- Each layer 16% smaller
            currentRadius = maxRadius * radiusRatio
        else
            -- Manual: Single circle at full radius (all layers combined)
            currentRadius = maxRadius
        end

        -- Combine all patterns for this circle using the utility function
        local combinedPattern, circleSteps = globals.Utils.combineEuclideanLayers(layerPatterns)

        -- For drawing, we need to know the step count
        -- Use the combined LCM steps for the grid
        local steps = circleSteps

        -- Draw circle guide segments (avoiding dots)
        local isLayerSelected = (layerIdx == selectedIndex)
        local currentGuideColor = isLayerSelected and selectedGuideColor or guideColor

        -- Apply transparency to non-selected layer guides
        if not isLayerSelected then
            -- Extract RGB and replace alpha with 40% opacity (format: 0xRRGGBBAA)
            currentGuideColor = (currentGuideColor & 0xFFFFFF00) | 0x66
        end

        local segmentCount = steps * 2  -- More segments for smoother circle
        for seg = 1, segmentCount do
            local angle1 = (2 * math.pi * (seg - 1) / segmentCount) - (math.pi / 2)
            local angle2 = (2 * math.pi * seg / segmentCount) - (math.pi / 2)

            -- Check if this segment is near a dot
            local nearDot = false
            for i = 1, steps do
                local dotAngle = (2 * math.pi * (i - 1) / steps) - (math.pi / 2)
                local midAngle = (angle1 + angle2) / 2
                local angleDiff = math.abs(dotAngle - midAngle)
                if angleDiff < (math.pi / steps * 0.4) then  -- Near a dot position
                    nearDot = true
                    break
                end
            end

            -- Only draw segment if not near a dot
            if not nearDot then
                local x1 = centerX + currentRadius * math.cos(angle1)
                local y1 = centerY + currentRadius * math.sin(angle1)
                local x2 = centerX + currentRadius * math.cos(angle2)
                local y2 = centerY + currentRadius * math.sin(angle2)
                imgui.DrawList_AddLine(drawList, x1, y1, x2, y2, currentGuideColor, 1.5)
            end
        end

        -- Draw dots around the circle
        -- NEW: Draw all positions that belong to at least one layer (hits AND silences)
        local dotRadius = math.min(5.5, maxRadius / 8)

        -- Build a map of which positions exist in which layers and whether they're hits
        local gridPositions = {}  -- {[gridPos] = {[layerIdx] = isHit}}

        for subLayerIdx, layer in ipairs(layerPatterns) do
            -- Generate pattern with rotation (single source of truth)
            local layerPattern = globals.Utils.euclideanRhythmWithRotation(
                layer.pulses,
                layer.steps,
                layer.rotation
            )

            -- Map ALL positions of this layer to the LCM grid (both hits and silences)
            local layerSteps = layer.steps
            for stepIdx = 1, layerSteps do
                -- Calculate position on LCM grid
                -- Note: rotation already applied to layerPattern above, so don't add it here
                local gridPos = ((stepIdx - 1) * (circleSteps / layerSteps)) + 1  -- +1 for 1-based indexing
                gridPos = math.floor(gridPos + 0.5) % circleSteps
                if gridPos == 0 then gridPos = circleSteps end

                -- Record this position for this layer (hit or silence)
                if not gridPositions[gridPos] then
                    gridPositions[gridPos] = {}
                end
                gridPositions[gridPos][subLayerIdx] = layerPattern[stepIdx] or false
            end
        end

        -- Draw dots at all positions that belong to at least one layer
        for gridPos, layerStates in pairs(gridPositions) do
            local angle = (2 * math.pi * (gridPos - 1) / steps) - (math.pi / 2)
            local x = centerX + currentRadius * math.cos(angle)
            local y = centerY + currentRadius * math.sin(angle)

            -- Separate layers into hits and silences
            local hitLayers = {}
            local silenceLayers = {}
            for subLayerIdx, isHit in pairs(layerStates) do
                if isHit then
                    table.insert(hitLayers, subLayerIdx)
                else
                    table.insert(silenceLayers, subLayerIdx)
                end
            end

            -- Draw background
            local layerBgColor = bgColor
            if not isLayerSelected then
                layerBgColor = (bgColor & 0xFFFFFF00) | 0x66
            end
            imgui.DrawList_AddCircleFilled(drawList, x, y, dotRadius, layerBgColor)

            -- Draw hits FIRST (filled circles)
            if #hitLayers > 0 then
                if #hitLayers == 1 then
                    -- Single hit: full colored circle
                    local subLayerColor = getEuclideanLayerColor(hitLayers[1])
                    if not isLayerSelected then
                        subLayerColor = getEuclideanLayerColor(hitLayers[1], 0.4)
                    end
                    imgui.DrawList_AddCircleFilled(drawList, x, y, dotRadius, subLayerColor)
                else
                    -- Multiple hits: divide into pie segments
                    local segmentAngle = (2 * math.pi) / #hitLayers
                    for i, subLayerIdx in ipairs(hitLayers) do
                        local subLayerColor = getEuclideanLayerColor(subLayerIdx)
                        if not isLayerSelected then
                            subLayerColor = getEuclideanLayerColor(subLayerIdx, 0.4)
                        end
                        local startAngle = (i - 1) * segmentAngle - (math.pi / 2)
                        local endAngle = i * segmentAngle - (math.pi / 2)

                        -- Draw pie segment
                        imgui.DrawList_PathArcTo(drawList, x, y, dotRadius, startAngle, endAngle, 16)
                        imgui.DrawList_PathLineTo(drawList, x, y)
                        imgui.DrawList_PathFillConvex(drawList, subLayerColor)
                    end
                end
            end

            -- Draw silences ON TOP (outlines visible over fills)
            if #silenceLayers > 0 then
                if #silenceLayers == 1 then
                    -- Single silence: full colored outline
                    local subLayerColor = getEuclideanLayerColor(silenceLayers[1])
                    if not isLayerSelected then
                        subLayerColor = getEuclideanLayerColor(silenceLayers[1], 0.4)
                    end
                    imgui.DrawList_AddCircle(drawList, x, y, dotRadius, subLayerColor, 0, 2.0)
                else
                    -- Multiple silences: divide outline into colored arcs
                    local segmentAngle = (2 * math.pi) / #silenceLayers
                    for i, subLayerIdx in ipairs(silenceLayers) do
                        local subLayerColor = getEuclideanLayerColor(subLayerIdx)
                        if not isLayerSelected then
                            subLayerColor = getEuclideanLayerColor(subLayerIdx, 0.4)
                        end
                        local startAngle = (i - 1) * segmentAngle - (math.pi / 2)
                        local endAngle = i * segmentAngle - (math.pi / 2)

                        -- Draw colored arc segment
                        imgui.DrawList_PathArcTo(drawList, x, y, dotRadius, startAngle, endAngle, 16)
                        imgui.DrawList_PathStroke(drawList, subLayerColor, 0, 2.0)
                    end
                end
            end
        end

        -- Labels removed for cleaner preview
    end

    -- Reserve space for the preview
    imgui.Dummy(globals.ctx, size, size)
end

-- ============================================================================
-- PATTERN PRESET BROWSER MODAL
-- ============================================================================

--- Draw the Euclidean Pattern Preset Browser as a non-modal window
-- Displays categorized list of euclidean rhythm presets from Constants.
-- User can click to select and apply a pattern to the current layer.
-- Context stored in globals.euclideanPatternModalContext contains:
-- - callbacks: {setPulses, setSteps, setRotation}
-- - layerIdx: Index of the layer to modify
function EuclideanSection.drawEuclideanPatternPresetBrowser()
    -- Check if modal should be opened (button was clicked)
    if globals.euclideanPatternModalOpen then
        -- Center on main window on first open
        local modalWidth, modalHeight = 750, 550
        if globals.mainWindowPos and globals.mainWindowSize then
            local mainWinX, mainWinY = globals.mainWindowPos[1], globals.mainWindowPos[2]
            local mainWinWidth, mainWinHeight = globals.mainWindowSize[1], globals.mainWindowSize[2]
            local centerX = mainWinX + (mainWinWidth - modalWidth) * 0.5
            local centerY = mainWinY + (mainWinHeight - modalHeight) * 0.5
            imgui.SetNextWindowPos(globals.ctx, centerX, centerY, imgui.Cond_Appearing)
        end
        -- Set minimum size, window will auto-resize to content
        imgui.SetNextWindowSize(globals.ctx, 750, 550, imgui.Cond_Appearing)
        globals.euclideanPatternModalOpen = false
        globals.euclideanPatternBrowserOpen = true
    end

    -- Only render if flag is set
    if not globals.euclideanPatternBrowserOpen then
        return
    end

    -- Window flags (non-modal, always on top, auto-resize to content)
    local windowFlags = imgui.WindowFlags_NoCollapse | imgui.WindowFlags_TopMost | imgui.WindowFlags_AlwaysAutoResize

    local visible, open = imgui.Begin(globals.ctx, "Euclidean Pattern Presets", true, windowFlags)
    if visible then
        imgui.Text(globals.ctx, "Select a rhythmic pattern to apply to the current layer")
        imgui.Separator(globals.ctx)
        imgui.Spacing(globals.ctx)

        -- Table with columns: Name, Pattern, Description
        local tableFlags = imgui.TableFlags_Borders |
                          imgui.TableFlags_RowBg |
                          imgui.TableFlags_ScrollY |
                          imgui.TableFlags_SizingFixedFit

        if imgui.BeginTable(globals.ctx, "##eucPatternTable", 3, tableFlags, 0, 450) then
            -- Setup columns
            imgui.TableSetupColumn(globals.ctx, "Name", imgui.TableColumnFlags_WidthFixed, 180)
            imgui.TableSetupColumn(globals.ctx, "Pattern", imgui.TableColumnFlags_WidthFixed, 100)
            imgui.TableSetupColumn(globals.ctx, "Description", imgui.TableColumnFlags_WidthStretch)
            imgui.TableSetupScrollFreeze(globals.ctx, 0, 1)  -- Freeze header row
            imgui.TableHeadersRow(globals.ctx)

            -- Iterate through categories and patterns
            for _, category in ipairs(globals.Constants.EUCLIDEAN_PATTERNS) do
                -- Category header
                imgui.TableNextRow(globals.ctx)
                imgui.TableSetColumnIndex(globals.ctx, 0)
                imgui.PushStyleColor(globals.ctx, imgui.Col_Text, 0xFFFFAA00)  -- Yellow/orange
                imgui.Text(globals.ctx, category.category)
                imgui.PopStyleColor(globals.ctx)

                -- Patterns in category
                for idx, pattern in ipairs(category.patterns) do
                    imgui.TableNextRow(globals.ctx)

                    -- Column 1: Name (clickable)
                    imgui.TableSetColumnIndex(globals.ctx, 0)
                    local isSelected = false
                    if imgui.Selectable(globals.ctx, pattern.name .. "##pat" .. category.category .. idx, isSelected, imgui.SelectableFlags_SpanAllColumns) then
                        -- Pattern selected, apply to layer using stored context
                        if globals.euclideanPatternModalContext then
                            local ctx = globals.euclideanPatternModalContext
                            local callbacks = ctx.callbacks
                            local layerIdx = ctx.layerIdx

                            -- Apply pattern parameters
                            if callbacks.setPulses then
                                callbacks.setPulses(layerIdx, pattern.pulses)
                            end
                            if callbacks.setSteps then
                                callbacks.setSteps(layerIdx, pattern.steps)
                            end
                            -- Reset rotation to 0 when loading preset
                            if callbacks.setRotation then
                                callbacks.setRotation(layerIdx, 0)
                            end
                        end
                        -- Close window after selection
                        globals.euclideanPatternBrowserOpen = false
                    end

                    -- Column 2: Pattern notation
                    imgui.TableSetColumnIndex(globals.ctx, 1)
                    imgui.TextDisabled(globals.ctx, "E(" .. pattern.pulses .. "," .. pattern.steps .. ")")

                    -- Column 3: Description
                    imgui.TableSetColumnIndex(globals.ctx, 2)
                    imgui.TextWrapped(globals.ctx, pattern.description)
                end
            end

            imgui.EndTable(globals.ctx)
        end

        imgui.Spacing(globals.ctx)
        imgui.Separator(globals.ctx)

        -- Close button
        if imgui.Button(globals.ctx, "Close", 120, 0) then
            globals.euclideanPatternBrowserOpen = false
        end
    end

    -- CRITICAL: Always call End() after Begin(), regardless of visibility
    imgui.End(globals.ctx)

    -- Handle window close via X button
    if not open then
        globals.euclideanPatternBrowserOpen = false
    end
end

-- ============================================================================
-- SAVED PATTERNS LIST
-- ============================================================================

--- Draw saved euclidean patterns list with Save/Override/Delete buttons
-- Displays a list of saved patterns for the current object (group or container).
-- Allows user to:
-- - Save current pattern (all layers)
-- - Load saved pattern (replaces all layers)
-- - Override existing pattern with current values
-- - Delete saved pattern
--
-- @param dataObj table Group or container object with euclideanSavedPatterns array
-- @param callbacks table Callback functions (not used in this function, kept for API compatibility)
-- @param isGroup boolean True if dataObj is a group
-- @param groupIndex number Index of the group (unused but kept for API compatibility)
-- @param containerIndex number Index of the container (unused but kept for API compatibility)
-- @param height number Total height in pixels for the saved patterns section
function EuclideanSection.drawEuclideanSavedPatternsList(dataObj, callbacks, isGroup, groupIndex, containerIndex, height)
    if not dataObj then return end

    -- Initialize saved patterns array if needed
    if not dataObj.euclideanSavedPatterns then
        dataObj.euclideanSavedPatterns = {}
    end

    local savedPatterns = dataObj.euclideanSavedPatterns
    local listWidth = 280  -- Increased width for multi-layer pattern names

    imgui.BeginGroup(globals.ctx)

    -- Get current layers data (ALL layers, not just selected one)
    local currentLayers = {}
    local isAutoBind = isGroup and (dataObj.euclideanAutoBindContainers or false)

    if isAutoBind then
        local selectedIndex = dataObj.euclideanSelectedBindingIndex or 1
        if dataObj.euclideanBindingOrder and dataObj.euclideanBindingOrder[selectedIndex] then
            local uuid = dataObj.euclideanBindingOrder[selectedIndex]
            local bindingLayers = dataObj.euclideanLayerBindings and dataObj.euclideanLayerBindings[uuid]
            if bindingLayers and #bindingLayers > 0 then
                -- Get ALL layers for this binding
                for i, layer in ipairs(bindingLayers) do
                    table.insert(currentLayers, {
                        pulses = layer.pulses or 8,
                        steps = layer.steps or 16,
                        rotation = layer.rotation or 0
                    })
                end
            end
        end
    else
        if dataObj.euclideanLayers and #dataObj.euclideanLayers > 0 then
            -- Get ALL layers
            for i, layer in ipairs(dataObj.euclideanLayers) do
                table.insert(currentLayers, {
                    pulses = layer.pulses or 8,
                    steps = layer.steps or 16,
                    rotation = layer.rotation or 0
                })
            end
        end
    end

    -- Save button
    if imgui.Button(globals.ctx, "Save Pattern##eucSave", listWidth, 0) then
        if #currentLayers > 0 then
            local patternName = globals.Presets.saveEuclideanPattern(dataObj, currentLayers)
        end
    end
    if imgui.IsItemHovered(globals.ctx) then
        local tooltipText = "Save current pattern ("
        for i, layer in ipairs(currentLayers) do
            if i > 1 then tooltipText = tooltipText .. " | " end
            tooltipText = tooltipText .. layer.pulses .. "-" .. layer.steps .. "-" .. layer.rotation
        end
        tooltipText = tooltipText .. ")"
        imgui.SetTooltip(globals.ctx, tooltipText)
    end

    imgui.Spacing(globals.ctx)

    -- Saved patterns list in a scrollable child window
    local listHeight = height - 35  -- Reserve space for Save button and spacing
    if imgui.BeginChild(globals.ctx, "##eucSavedPatternsList", listWidth, listHeight) then
        if #savedPatterns == 0 then
            imgui.TextDisabled(globals.ctx, "No saved patterns")
        else
            for i, pattern in ipairs(savedPatterns) do
                -- Calculate available width and reserve space for override + delete buttons
                local availWidth = imgui.GetContentRegionAvail(globals.ctx)
                local buttonWidth = 105  -- Width for both buttons + spacing
                local selectableWidth = availWidth - buttonWidth

                -- Draw selectable with limited width
                local isSelected = false
                if imgui.Selectable(globals.ctx, pattern.name .. "##saved" .. i, isSelected, 0, selectableWidth, 0) then
                    -- Load pattern on click (supports multi-layer)
                    local patternData = globals.Presets.loadEuclideanPattern(dataObj, pattern.name)
                    if patternData and patternData.layers then
                        if isAutoBind then
                            local selectedIndex = dataObj.euclideanSelectedBindingIndex or 1
                            local uuid = dataObj.euclideanBindingOrder[selectedIndex]

                            -- Replace ALL layers in the binding
                            if uuid and dataObj.euclideanLayerBindings then
                                dataObj.euclideanLayerBindings[uuid] = {}
                                for layerIdx, layer in ipairs(patternData.layers) do
                                    table.insert(dataObj.euclideanLayerBindings[uuid], {
                                        pulses = layer.pulses,
                                        steps = layer.steps,
                                        rotation = layer.rotation
                                    })
                                end
                                -- Reset selected layer to first
                                if not dataObj.euclideanSelectedLayerPerBinding then
                                    dataObj.euclideanSelectedLayerPerBinding = {}
                                end
                                dataObj.euclideanSelectedLayerPerBinding[uuid] = 1
                                dataObj.needsRegeneration = true
                            end
                        else
                            -- Replace ALL layers in container/group
                            dataObj.euclideanLayers = {}
                            for layerIdx, layer in ipairs(patternData.layers) do
                                table.insert(dataObj.euclideanLayers, {
                                    pulses = layer.pulses,
                                    steps = layer.steps,
                                    rotation = layer.rotation
                                })
                            end
                            dataObj.euclideanSelectedLayer = 1
                            dataObj.needsRegeneration = true
                        end
                    end
                end

                -- Position override button
                imgui.SameLine(globals.ctx, 0, 0)
                local windowWidth = imgui.GetWindowWidth(globals.ctx)
                imgui.SetCursorPosX(globals.ctx, windowWidth - buttonWidth - 5)

                if imgui.Button(globals.ctx, "Override##ovr" .. i, 65, 0) then
                    if #currentLayers > 0 then
                        globals.Presets.overrideEuclideanPattern(dataObj, pattern.name, currentLayers)
                    end
                end
                if imgui.IsItemHovered(globals.ctx) then
                    imgui.SetTooltip(globals.ctx, "Replace '" .. pattern.name .. "' with current pattern")
                end

                -- Position delete button
                imgui.SameLine(globals.ctx, 0, 2)
                if imgui.SmallButton(globals.ctx, "X##del" .. i) then
                    globals.Presets.deleteEuclideanPattern(dataObj, pattern.name)
                end
                if imgui.IsItemHovered(globals.ctx) then
                    imgui.SetTooltip(globals.ctx, "Delete '" .. pattern.name .. "'")
                end
            end
        end
    end
    -- CRITICAL: Always call EndChild after BeginChild, regardless of visibility
    imgui.EndChild(globals.ctx)

    imgui.EndGroup(globals.ctx)
end

-- ============================================================================
-- MODULE EXPORT
-- ============================================================================

return EuclideanSection
