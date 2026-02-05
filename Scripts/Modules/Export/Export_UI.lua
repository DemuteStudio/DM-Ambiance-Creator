--[[
@version 1.1
@noindex
DM Ambiance Creator - Export UI Module
Handles the Export modal window rendering with multi-selection and new widgets.
--]]

local Export_UI = {}
local globals = {}
local Export_Settings = nil
local Export_Engine = nil

-- UI State
local shouldOpenModal = false
local lastClickedKey = nil  -- For Shift+Click range selection

function Export_UI.initModule(g)
    if not g then
        error("Export_UI.initModule: globals parameter is required")
    end
    globals = g
end

function Export_UI.setDependencies(settings, engine)
    Export_Settings = settings
    Export_Engine = engine
end

-- Open the export modal
function Export_UI.openModal()
    -- Reset and initialize settings
    Export_Settings.resetSettings()
    Export_Settings.initializeEnabledContainers()
    lastClickedKey = nil
    shouldOpenModal = true
end

-- Render the export modal (call every frame from UI_Preset)
function Export_UI.renderModal()
    local ctx = globals.ctx
    local imgui = globals.imgui

    if not ctx or not imgui then return end

    -- Open popup when requested
    if shouldOpenModal then
        imgui.OpenPopup(ctx, "Export Items")
        shouldOpenModal = false
    end

    -- Set modal size (increased for Preview section)
    imgui.SetNextWindowSize(ctx, 750, 620, imgui.Cond_FirstUseEver)

    local popupOpen, popupVisible = imgui.BeginPopupModal(ctx, "Export Items", true, imgui.WindowFlags_NoCollapse)

    if popupVisible then
        local windowWidth, windowHeight = imgui.GetWindowSize(ctx)
        local leftPanelWidth = 260
        local rightPanelWidth = windowWidth - leftPanelWidth - 30
        local contentHeight = windowHeight - 130  -- Leave room for export method + buttons

        -- Get global params (needed in multiple sections)
        local globalParams = Export_Settings.getGlobalParams()
        local Constants = globals.Constants
        local EXPORT = Constants and Constants.EXPORT or {}

        -- Left Panel: Container List with Checkboxes and Multi-Selection
        if imgui.BeginChild(ctx, "ContainerList", leftPanelWidth, contentHeight, imgui.ChildFlags_Border) then
            imgui.TextColored(ctx, 0xFFAA00FF, "Containers")
            imgui.SameLine(ctx)
            imgui.TextDisabled(ctx, "(Ctrl/Shift+Click)")
            imgui.Separator(ctx)
            imgui.Spacing(ctx)

            local containers = Export_Settings.collectAllContainers()

            if #containers == 0 then
                imgui.TextDisabled(ctx, "No containers found")
            else
                for _, c in ipairs(containers) do
                    local enabled = Export_Settings.isContainerEnabled(c.key)
                    local isSelected = Export_Settings.isContainerSelected(c.key)

                    -- Checkbox for enable/disable export
                    local changedEnable, newEnabled = imgui.Checkbox(ctx, "##enable_" .. c.key, enabled)
                    if changedEnable then
                        Export_Settings.setContainerEnabled(c.key, newEnabled)
                    end

                    imgui.SameLine(ctx)

                    -- Selectable for container name (multi-selection)
                    local flags = 0
                    if imgui.Selectable(ctx, c.displayName .. "##sel_" .. c.key, isSelected, flags) then
                        local ctrl = imgui.IsKeyDown(ctx, imgui.Mod_Ctrl)
                        local shift = imgui.IsKeyDown(ctx, imgui.Mod_Shift)

                        if shift and lastClickedKey then
                            -- Shift+Click: Range selection
                            Export_Settings.selectContainerRange(lastClickedKey, c.key)
                        elseif ctrl then
                            -- Ctrl+Click: Toggle selection
                            Export_Settings.toggleContainerSelected(c.key)
                        else
                            -- Normal click: Single selection
                            Export_Settings.clearContainerSelection()
                            Export_Settings.setContainerSelected(c.key, true)
                        end
                        lastClickedKey = c.key
                    end
                end
            end
        end
        imgui.EndChild(ctx)

        imgui.SameLine(ctx)

        -- Right Panel: Parameters
        if imgui.BeginChild(ctx, "Parameters", rightPanelWidth, contentHeight, imgui.ChildFlags_Border) then
            -- Global Parameters Section
            imgui.TextColored(ctx, 0xFFAA00FF, "Global Export Parameters")
            imgui.Separator(ctx)
            imgui.Spacing(ctx)

            -- Instance Amount (DragInt)
            imgui.Text(ctx, "Instance Amount:")
            imgui.SameLine(ctx, 150)
            imgui.PushItemWidth(ctx, 120)
            local minInstances = EXPORT.INSTANCE_MIN or 1
            local maxInstances = EXPORT.INSTANCE_MAX or 100
            local changedAmount, newAmount = imgui.DragInt(ctx, "##InstanceAmount",
                globalParams.instanceAmount, 0.1, minInstances, maxInstances)
            if changedAmount then
                Export_Settings.setGlobalParam("instanceAmount", newAmount)
            end
            imgui.PopItemWidth(ctx)

            -- Spacing (DragDouble)
            imgui.Text(ctx, "Spacing (seconds):")
            imgui.SameLine(ctx, 150)
            imgui.PushItemWidth(ctx, 120)
            local minSpacing = EXPORT.SPACING_MIN or 0
            local maxSpacing = EXPORT.SPACING_MAX or 60
            local changedSpacing, newSpacing = imgui.DragDouble(ctx, "##Spacing",
                globalParams.spacing, 0.01, minSpacing, maxSpacing, "%.2f")
            if changedSpacing then
                Export_Settings.setGlobalParam("spacing", newSpacing)
            end
            imgui.PopItemWidth(ctx)

            -- Max Pool Items (DragInt)
            imgui.Text(ctx, "Max Pool Items:")
            imgui.SameLine(ctx, 150)
            imgui.PushItemWidth(ctx, 120)
            local changedMaxPool, newMaxPool = imgui.DragInt(ctx, "##MaxPoolItems",
                globalParams.maxPoolItems, 0.1, 0, 999)
            if changedMaxPool then
                Export_Settings.setGlobalParam("maxPoolItems", newMaxPool)
            end
            imgui.PopItemWidth(ctx)

            -- Display pool info: "All (X)" when 0, or "X / Y available" when > 0
            imgui.SameLine(ctx)
            local totalPool = 0
            local selectedKeys = Export_Settings.getSelectedContainerKeys()
            if #selectedKeys == 1 then
                totalPool = Export_Settings.getPoolSize(selectedKeys[1])
            elseif #selectedKeys == 0 then
                -- Show total from all enabled containers
                local containers = Export_Settings.collectAllContainers()
                for _, c in ipairs(containers) do
                    if Export_Settings.isContainerEnabled(c.key) then
                        totalPool = totalPool + Export_Settings.getPoolSize(c.key)
                    end
                end
            end
            if totalPool > 0 then
                local poolText
                if globalParams.maxPoolItems == 0 or globalParams.maxPoolItems >= totalPool then
                    poolText = string.format("All (%d)", totalPool)
                else
                    poolText = string.format("%d / %d available", globalParams.maxPoolItems, totalPool)
                end
                imgui.TextDisabled(ctx, poolText)
            end

            -- Loop Mode (Combo)
            imgui.Text(ctx, "Loop Mode:")
            imgui.SameLine(ctx, 150)
            imgui.PushItemWidth(ctx, 120)
            local loopModeOptions = "Auto\0On\0Off\0"
            local loopModeValueToIndex = { ["auto"] = 0, ["on"] = 1, ["off"] = 2 }
            local loopModeIndexToValue = { [0] = "auto", [1] = "on", [2] = "off" }
            local currentLoopIndex = loopModeValueToIndex[globalParams.loopMode] or 0
            local changedLoopMode, newLoopIndex = imgui.Combo(ctx, "##LoopMode",
                currentLoopIndex, loopModeOptions)
            if changedLoopMode then
                local newLoopValue = loopModeIndexToValue[newLoopIndex] or "auto"
                Export_Settings.setGlobalParam("loopMode", newLoopValue)
            end
            imgui.PopItemWidth(ctx)

            imgui.Spacing(ctx)

            -- Align to whole seconds
            local changedAlign, newAlign = imgui.Checkbox(ctx, "Align to whole seconds",
                globalParams.alignToSeconds)
            if changedAlign then
                Export_Settings.setGlobalParam("alignToSeconds", newAlign)
            end

            imgui.Spacing(ctx)
            imgui.Separator(ctx)
            imgui.Spacing(ctx)

            -- Preserve checkboxes
            imgui.Text(ctx, "Preserve Properties:")
            imgui.Spacing(ctx)

            local changed1, newPan = imgui.Checkbox(ctx, "Preserve Pan", globalParams.preservePan)
            if changed1 then Export_Settings.setGlobalParam("preservePan", newPan) end

            local changed2, newVol = imgui.Checkbox(ctx, "Preserve Volume", globalParams.preserveVolume)
            if changed2 then Export_Settings.setGlobalParam("preserveVolume", newVol) end

            local changed3, newPitch = imgui.Checkbox(ctx, "Preserve Pitch/Stretch", globalParams.preservePitch)
            if changed3 then Export_Settings.setGlobalParam("preservePitch", newPitch) end

            imgui.Spacing(ctx)
            imgui.Separator(ctx)
            imgui.Spacing(ctx)

            -- Region Creation Section
            imgui.Text(ctx, "Region Creation:")
            imgui.Spacing(ctx)

            local changedCreateRegions, newCreateRegions = imgui.Checkbox(ctx,
                "Create regions for exported items", globalParams.createRegions)
            if changedCreateRegions then
                Export_Settings.setGlobalParam("createRegions", newCreateRegions)
            end

            if globalParams.createRegions then
                imgui.Indent(ctx, 15)
                imgui.Text(ctx, "Pattern:")
                imgui.SameLine(ctx, 80)
                imgui.PushItemWidth(ctx, 200)
                local changedPattern, newPattern = imgui.InputText(ctx, "##RegionPattern",
                    globalParams.regionPattern, imgui.InputTextFlags_None)
                if changedPattern then
                    Export_Settings.setGlobalParam("regionPattern", newPattern)
                end
                imgui.PopItemWidth(ctx)
                imgui.TextDisabled(ctx, "Tags: $container, $group, $index")
                imgui.Unindent(ctx, 15)
            end

            imgui.Spacing(ctx)

            -- Container Override Section
            imgui.Separator(ctx)
            imgui.Spacing(ctx)
            imgui.TextColored(ctx, 0x00AAFFFF, "Container Override")
            imgui.Spacing(ctx)

            local selectedCount = Export_Settings.getSelectedContainerCount()

            if selectedCount == 0 then
                imgui.TextDisabled(ctx, "Select container(s) to set overrides")
            elseif selectedCount == 1 then
                -- Single selection: show container name
                local selectedKeys = Export_Settings.getSelectedContainerKeys()
                local selectedKey = selectedKeys[1]

                -- Find container display name
                local containers = Export_Settings.collectAllContainers()
                local selectedName = ""
                for _, c in ipairs(containers) do
                    if c.key == selectedKey then
                        selectedName = c.displayName
                        break
                    end
                end

                imgui.Text(ctx, "Selected: " .. selectedName)
                imgui.Spacing(ctx)

                -- Get or create override
                local override = Export_Settings.getContainerOverride(selectedKey)
                if not override then
                    override = {
                        enabled = false,
                        params = {
                            instanceAmount = globalParams.instanceAmount,
                            spacing = globalParams.spacing,
                            alignToSeconds = globalParams.alignToSeconds,
                            exportMethod = globalParams.exportMethod,
                            preservePan = globalParams.preservePan,
                            preserveVolume = globalParams.preserveVolume,
                            preservePitch = globalParams.preservePitch,
                            createRegions = globalParams.createRegions,
                            regionPattern = globalParams.regionPattern,
                            maxPoolItems = globalParams.maxPoolItems,
                            loopMode = globalParams.loopMode,
                        }
                    }
                end

                local changedOverride, enableOverride = imgui.Checkbox(ctx, "Enable Override##container", override.enabled)
                if changedOverride then
                    override.enabled = enableOverride
                    Export_Settings.setContainerOverride(selectedKey, override)
                end

                if override.enabled then
                    Export_UI.renderOverrideParams(ctx, imgui, selectedKey, override, EXPORT)
                else
                    imgui.TextDisabled(ctx, "Using global parameters")
                end
            else
                -- Multi-selection
                imgui.TextColored(ctx, 0xFFAA00FF, string.format("%d containers selected", selectedCount))
                imgui.Text(ctx, "Changes apply to all selected")
                imgui.Spacing(ctx)

                -- Check if all selected have overrides enabled
                local allOverridesEnabled = true
                local selectedKeys = Export_Settings.getSelectedContainerKeys()
                for _, key in ipairs(selectedKeys) do
                    local override = Export_Settings.getContainerOverride(key)
                    if not override or not override.enabled then
                        allOverridesEnabled = false
                        break
                    end
                end

                -- Enable override checkbox for all selected
                local changedBatchOverride, enableBatchOverride = imgui.Checkbox(ctx,
                    "Enable Override for all##batch", allOverridesEnabled)
                if changedBatchOverride then
                    for _, key in ipairs(selectedKeys) do
                        local override = Export_Settings.getContainerOverride(key)
                        if not override then
                            override = {
                                enabled = enableBatchOverride,
                                params = {
                                    instanceAmount = globalParams.instanceAmount,
                                    spacing = globalParams.spacing,
                                    alignToSeconds = globalParams.alignToSeconds,
                                    exportMethod = globalParams.exportMethod,
                                    preservePan = globalParams.preservePan,
                                    preserveVolume = globalParams.preserveVolume,
                                    preservePitch = globalParams.preservePitch,
                                    createRegions = globalParams.createRegions,
                                    regionPattern = globalParams.regionPattern,
                                    maxPoolItems = globalParams.maxPoolItems,
                                    loopMode = globalParams.loopMode,
                                }
                            }
                        else
                            override.enabled = enableBatchOverride
                        end
                        Export_Settings.setContainerOverride(key, override)
                    end
                end

                if allOverridesEnabled then
                    imgui.Spacing(ctx)
                    imgui.TextDisabled(ctx, "Editing applies to all selected:")
                    imgui.Spacing(ctx)

                    -- Get first selected container's override as reference
                    local refOverride = Export_Settings.getContainerOverride(selectedKeys[1])
                    if refOverride then
                        Export_UI.renderBatchOverrideParams(ctx, imgui, selectedKeys, refOverride, EXPORT)
                    end
                end
            end

            -- Preview Section
            imgui.Spacing(ctx)
            imgui.Separator(ctx)
            imgui.Spacing(ctx)
            imgui.TextColored(ctx, 0x00AAFFFF, "Preview")
            imgui.Spacing(ctx)

            if imgui.BeginChild(ctx, "PreviewList", -1, 120, imgui.ChildFlags_Border) then
                -- Defensive nil-check for Export_Engine
                local previewEntries = Export_Engine and Export_Engine.generatePreview
                    and Export_Engine.generatePreview() or {}

                if #previewEntries == 0 then
                    imgui.TextDisabled(ctx, "No enabled containers")
                else
                    for _, entry in ipairs(previewEntries) do
                        -- Format pool display: "6/12" or "8/8"
                        local poolDisplay = string.format("%d/%d", entry.poolSelected, entry.poolTotal)

                        -- Format loop indicator: checkmark or X, with "(auto)" suffix
                        local loopIndicator
                        if entry.loopMode then
                            loopIndicator = "Loop \226\156\147"  -- ✓
                            if entry.loopModeAuto then
                                loopIndicator = loopIndicator .. " (auto)"
                            end
                        else
                            loopIndicator = "Loop \226\156\151"  -- ✗
                        end

                        -- Format track info: "1trk" for mono, "2trk" for stereo
                        local trackInfo = string.format("%dtrk", entry.trackCount)

                        -- Format duration: "~12s" rounded to nearest second
                        local durationDisplay = string.format("~%ds", math.floor(entry.estimatedDuration + 0.5))

                        -- Render row with proper spacing
                        -- Name (truncated if needed)
                        local displayName = entry.name
                        if #displayName > 20 then
                            displayName = displayName:sub(1, 17) .. "..."
                        end
                        imgui.Text(ctx, displayName)
                        imgui.SameLine(ctx, 160)
                        imgui.TextDisabled(ctx, poolDisplay)
                        imgui.SameLine(ctx, 200)
                        if entry.loopMode then
                            imgui.TextColored(ctx, 0x88FF88FF, loopIndicator)
                        else
                            imgui.TextDisabled(ctx, loopIndicator)
                        end
                        imgui.SameLine(ctx, 300)
                        imgui.TextDisabled(ctx, trackInfo)
                        imgui.SameLine(ctx, 340)
                        imgui.TextDisabled(ctx, durationDisplay)
                    end
                end
            end
            imgui.EndChild(ctx)
        end
        imgui.EndChild(ctx)

        -- Export Method Section (between panels and buttons)
        imgui.Separator(ctx)
        imgui.Spacing(ctx)

        imgui.Text(ctx, "Export Method:")
        imgui.SameLine(ctx)
        imgui.PushItemWidth(ctx, 200)
        local methods = "Current Track\0New Track\0"
        local changedMethod, newMethod = imgui.Combo(ctx, "##ExportMethod",
            globalParams.exportMethod, methods)
        if changedMethod then
            Export_Settings.setGlobalParam("exportMethod", newMethod)
        end
        imgui.PopItemWidth(ctx)

        imgui.SameLine(ctx)

        -- Show enabled count
        local enabledCount = Export_Settings.getEnabledContainerCount()
        local totalCount = #Export_Settings.collectAllContainers()
        imgui.Text(ctx, string.format("| Enabled: %d/%d", enabledCount, totalCount))

        imgui.Spacing(ctx)
        imgui.Separator(ctx)
        imgui.Spacing(ctx)

        -- Footer buttons
        local buttonWidth = 120
        local buttonSpacing = 10
        local totalButtonWidth = buttonWidth * 2 + buttonSpacing
        local startX = (windowWidth - totalButtonWidth) / 2

        imgui.SetCursorPosX(ctx, startX)

        -- Export button
        imgui.PushStyleColor(ctx, imgui.Col_Button, 0x0088AAFF)
        imgui.PushStyleColor(ctx, imgui.Col_ButtonHovered, 0x00AACCFF)
        imgui.PushStyleColor(ctx, imgui.Col_ButtonActive, 0x006688FF)
        if imgui.Button(ctx, "Export", buttonWidth, 30) then
            local success, message = Export_Engine.performExport()
            if success then
                imgui.CloseCurrentPopup(ctx)
            end
        end
        imgui.PopStyleColor(ctx, 3)

        imgui.SameLine(ctx)

        -- Cancel button
        if imgui.Button(ctx, "Cancel", buttonWidth, 30) then
            imgui.CloseCurrentPopup(ctx)
        end

        imgui.EndPopup(ctx)
    end
end

-- Render override parameters for single selection
function Export_UI.renderOverrideParams(ctx, imgui, containerKey, override, EXPORT)
    imgui.Indent(ctx, 15)
    imgui.Spacing(ctx)

    -- Override Instance Amount
    imgui.Text(ctx, "Instances:")
    imgui.SameLine(ctx, 100)
    imgui.PushItemWidth(ctx, 100)
    local changedAmt, newAmt = imgui.DragInt(ctx, "##OverrideAmount",
        override.params.instanceAmount, 0.1,
        EXPORT.INSTANCE_MIN or 1, EXPORT.INSTANCE_MAX or 100)
    if changedAmt then
        override.params.instanceAmount = newAmt
        Export_Settings.setContainerOverride(containerKey, override)
    end
    imgui.PopItemWidth(ctx)

    -- Override Spacing
    imgui.Text(ctx, "Spacing:")
    imgui.SameLine(ctx, 100)
    imgui.PushItemWidth(ctx, 100)
    local changedSpc, newSpc = imgui.DragDouble(ctx, "##OverrideSpacing",
        override.params.spacing, 0.01,
        EXPORT.SPACING_MIN or 0, EXPORT.SPACING_MAX or 60, "%.2f")
    if changedSpc then
        override.params.spacing = newSpc
        Export_Settings.setContainerOverride(containerKey, override)
    end
    imgui.PopItemWidth(ctx)

    -- Override Max Pool Items
    imgui.Text(ctx, "Max Pool:")
    imgui.SameLine(ctx, 100)
    imgui.PushItemWidth(ctx, 100)
    local changedMaxPoolOvr, newMaxPoolOvr = imgui.DragInt(ctx, "##OverrideMaxPool",
        override.params.maxPoolItems or 0, 0.1, 0, 999)
    if changedMaxPoolOvr then
        override.params.maxPoolItems = newMaxPoolOvr
        Export_Settings.setContainerOverride(containerKey, override)
    end
    imgui.PopItemWidth(ctx)

    -- Override Loop Mode
    imgui.Text(ctx, "Loop Mode:")
    imgui.SameLine(ctx, 100)
    imgui.PushItemWidth(ctx, 100)
    local loopModeOptions = "Auto\0On\0Off\0"
    local loopModeValueToIndex = { ["auto"] = 0, ["on"] = 1, ["off"] = 2 }
    local loopModeIndexToValue = { [0] = "auto", [1] = "on", [2] = "off" }
    local currentLoopIdx = loopModeValueToIndex[override.params.loopMode or "auto"] or 0
    local changedLoopOvr, newLoopIdx = imgui.Combo(ctx, "##OverrideLoopMode",
        currentLoopIdx, loopModeOptions)
    if changedLoopOvr then
        override.params.loopMode = loopModeIndexToValue[newLoopIdx] or "auto"
        Export_Settings.setContainerOverride(containerKey, override)
    end
    imgui.PopItemWidth(ctx)

    -- Override Align to seconds
    local changedAlignOvr, newAlignOvr = imgui.Checkbox(ctx, "Align to seconds##override",
        override.params.alignToSeconds)
    if changedAlignOvr then
        override.params.alignToSeconds = newAlignOvr
        Export_Settings.setContainerOverride(containerKey, override)
    end

    imgui.Spacing(ctx)

    -- Override Preserve checkboxes
    local c1, p1 = imgui.Checkbox(ctx, "Preserve Pan##override", override.params.preservePan)
    if c1 then
        override.params.preservePan = p1
        Export_Settings.setContainerOverride(containerKey, override)
    end

    local c2, p2 = imgui.Checkbox(ctx, "Preserve Volume##override", override.params.preserveVolume)
    if c2 then
        override.params.preserveVolume = p2
        Export_Settings.setContainerOverride(containerKey, override)
    end

    local c3, p3 = imgui.Checkbox(ctx, "Preserve Pitch##override", override.params.preservePitch)
    if c3 then
        override.params.preservePitch = p3
        Export_Settings.setContainerOverride(containerKey, override)
    end

    imgui.Unindent(ctx, 15)
end

-- Render override parameters for multi-selection (batch editing)
function Export_UI.renderBatchOverrideParams(ctx, imgui, selectedKeys, refOverride, EXPORT)
    imgui.Indent(ctx, 15)

    -- Batch Instance Amount
    imgui.Text(ctx, "Instances:")
    imgui.SameLine(ctx, 100)
    imgui.PushItemWidth(ctx, 100)
    local changedAmt, newAmt = imgui.DragInt(ctx, "##BatchAmount",
        refOverride.params.instanceAmount, 0.1,
        EXPORT.INSTANCE_MIN or 1, EXPORT.INSTANCE_MAX or 100)
    if changedAmt then
        Export_Settings.applyParamToSelected("instanceAmount", newAmt)
    end
    imgui.PopItemWidth(ctx)

    -- Batch Spacing
    imgui.Text(ctx, "Spacing:")
    imgui.SameLine(ctx, 100)
    imgui.PushItemWidth(ctx, 100)
    local changedSpc, newSpc = imgui.DragDouble(ctx, "##BatchSpacing",
        refOverride.params.spacing, 0.01,
        EXPORT.SPACING_MIN or 0, EXPORT.SPACING_MAX or 60, "%.2f")
    if changedSpc then
        Export_Settings.applyParamToSelected("spacing", newSpc)
    end
    imgui.PopItemWidth(ctx)

    -- Batch Max Pool Items
    imgui.Text(ctx, "Max Pool:")
    imgui.SameLine(ctx, 100)
    imgui.PushItemWidth(ctx, 100)
    local changedMaxPoolBatch, newMaxPoolBatch = imgui.DragInt(ctx, "##BatchMaxPool",
        refOverride.params.maxPoolItems or 0, 0.1, 0, 999)
    if changedMaxPoolBatch then
        Export_Settings.applyParamToSelected("maxPoolItems", newMaxPoolBatch)
    end
    imgui.PopItemWidth(ctx)

    -- Batch Loop Mode
    imgui.Text(ctx, "Loop Mode:")
    imgui.SameLine(ctx, 100)
    imgui.PushItemWidth(ctx, 100)
    local loopModeOptions = "Auto\0On\0Off\0"
    local loopModeValueToIndex = { ["auto"] = 0, ["on"] = 1, ["off"] = 2 }
    local loopModeIndexToValue = { [0] = "auto", [1] = "on", [2] = "off" }
    local currentLoopIdxBatch = loopModeValueToIndex[refOverride.params.loopMode or "auto"] or 0
    local changedLoopBatch, newLoopIdxBatch = imgui.Combo(ctx, "##BatchLoopMode",
        currentLoopIdxBatch, loopModeOptions)
    if changedLoopBatch then
        Export_Settings.applyParamToSelected("loopMode", loopModeIndexToValue[newLoopIdxBatch] or "auto")
    end
    imgui.PopItemWidth(ctx)

    -- Batch Align to seconds
    local changedAlignBatch, newAlignBatch = imgui.Checkbox(ctx, "Align to seconds##batch",
        refOverride.params.alignToSeconds)
    if changedAlignBatch then
        Export_Settings.applyParamToSelected("alignToSeconds", newAlignBatch)
    end

    imgui.Spacing(ctx)

    -- Batch Preserve checkboxes
    local c1, p1 = imgui.Checkbox(ctx, "Preserve Pan##batch", refOverride.params.preservePan)
    if c1 then
        Export_Settings.applyParamToSelected("preservePan", p1)
    end

    local c2, p2 = imgui.Checkbox(ctx, "Preserve Volume##batch", refOverride.params.preserveVolume)
    if c2 then
        Export_Settings.applyParamToSelected("preserveVolume", p2)
    end

    local c3, p3 = imgui.Checkbox(ctx, "Preserve Pitch##batch", refOverride.params.preservePitch)
    if c3 then
        Export_Settings.applyParamToSelected("preservePitch", p3)
    end

    imgui.Unindent(ctx, 15)
end

return Export_UI
