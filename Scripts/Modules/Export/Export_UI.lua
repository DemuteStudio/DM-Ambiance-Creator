--[[
@version 1.1
@noindex
DM Ambiance Creator - Export UI Module
Handles the Export modal window rendering with multi-selection and new widgets.
--]]

local Export_UI = {}
local globals = {}
local Export_Core = nil

-- UI State
local shouldOpenModal = false
local lastClickedKey = nil  -- For Shift+Click range selection

function Export_UI.initModule(g)
    if not g then
        error("Export_UI.initModule: globals parameter is required")
    end
    globals = g
end

function Export_UI.setDependencies(core)
    Export_Core = core
end

-- Open the export modal
function Export_UI.openModal()
    -- Reset and initialize settings
    Export_Core.resetSettings()
    Export_Core.initializeEnabledContainers()
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

    -- Set modal size
    imgui.SetNextWindowSize(ctx, 750, 520, imgui.Cond_FirstUseEver)

    local popupOpen, popupVisible = imgui.BeginPopupModal(ctx, "Export Items", true, imgui.WindowFlags_NoCollapse)

    if popupVisible then
        local windowWidth, windowHeight = imgui.GetWindowSize(ctx)
        local leftPanelWidth = 260
        local rightPanelWidth = windowWidth - leftPanelWidth - 30
        local contentHeight = windowHeight - 130  -- Leave room for export method + buttons

        -- Get global params (needed in multiple sections)
        local globalParams = Export_Core.getGlobalParams()
        local Constants = globals.Constants
        local EXPORT = Constants and Constants.EXPORT or {}

        -- Left Panel: Container List with Checkboxes and Multi-Selection
        if imgui.BeginChild(ctx, "ContainerList", leftPanelWidth, contentHeight, imgui.ChildFlags_Border) then
            imgui.TextColored(ctx, 0xFFAA00FF, "Containers")
            imgui.SameLine(ctx)
            imgui.TextDisabled(ctx, "(Ctrl/Shift+Click)")
            imgui.Separator(ctx)
            imgui.Spacing(ctx)

            local containers = Export_Core.collectAllContainers()

            if #containers == 0 then
                imgui.TextDisabled(ctx, "No containers found")
            else
                for _, c in ipairs(containers) do
                    local enabled = Export_Core.isContainerEnabled(c.key)
                    local isSelected = Export_Core.isContainerSelected(c.key)

                    -- Checkbox for enable/disable export
                    local changedEnable, newEnabled = imgui.Checkbox(ctx, "##enable_" .. c.key, enabled)
                    if changedEnable then
                        Export_Core.setContainerEnabled(c.key, newEnabled)
                    end

                    imgui.SameLine(ctx)

                    -- Selectable for container name (multi-selection)
                    local flags = 0
                    if imgui.Selectable(ctx, c.displayName .. "##sel_" .. c.key, isSelected, flags) then
                        local ctrl = imgui.IsKeyDown(ctx, imgui.Mod_Ctrl)
                        local shift = imgui.IsKeyDown(ctx, imgui.Mod_Shift)

                        if shift and lastClickedKey then
                            -- Shift+Click: Range selection
                            Export_Core.selectContainerRange(lastClickedKey, c.key)
                        elseif ctrl then
                            -- Ctrl+Click: Toggle selection
                            Export_Core.toggleContainerSelected(c.key)
                        else
                            -- Normal click: Single selection
                            Export_Core.clearContainerSelection()
                            Export_Core.setContainerSelected(c.key, true)
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
                Export_Core.setGlobalParam("instanceAmount", newAmount)
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
                Export_Core.setGlobalParam("spacing", newSpacing)
            end
            imgui.PopItemWidth(ctx)

            imgui.Spacing(ctx)

            -- Align to whole seconds
            local changedAlign, newAlign = imgui.Checkbox(ctx, "Align to whole seconds",
                globalParams.alignToSeconds)
            if changedAlign then
                Export_Core.setGlobalParam("alignToSeconds", newAlign)
            end

            imgui.Spacing(ctx)
            imgui.Separator(ctx)
            imgui.Spacing(ctx)

            -- Preserve checkboxes
            imgui.Text(ctx, "Preserve Properties:")
            imgui.Spacing(ctx)

            local changed1, newPan = imgui.Checkbox(ctx, "Preserve Pan", globalParams.preservePan)
            if changed1 then Export_Core.setGlobalParam("preservePan", newPan) end

            local changed2, newVol = imgui.Checkbox(ctx, "Preserve Volume", globalParams.preserveVolume)
            if changed2 then Export_Core.setGlobalParam("preserveVolume", newVol) end

            local changed3, newPitch = imgui.Checkbox(ctx, "Preserve Pitch/Stretch", globalParams.preservePitch)
            if changed3 then Export_Core.setGlobalParam("preservePitch", newPitch) end

            imgui.Spacing(ctx)
            imgui.Spacing(ctx)

            -- Container Override Section
            imgui.Separator(ctx)
            imgui.Spacing(ctx)
            imgui.TextColored(ctx, 0x00AAFFFF, "Container Override")
            imgui.Spacing(ctx)

            local selectedCount = Export_Core.getSelectedContainerCount()

            if selectedCount == 0 then
                imgui.TextDisabled(ctx, "Select container(s) to set overrides")
            elseif selectedCount == 1 then
                -- Single selection: show container name
                local selectedKeys = Export_Core.getSelectedContainerKeys()
                local selectedKey = selectedKeys[1]

                -- Find container display name
                local containers = Export_Core.collectAllContainers()
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
                local override = Export_Core.getContainerOverride(selectedKey)
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
                        }
                    }
                end

                local changedOverride, enableOverride = imgui.Checkbox(ctx, "Enable Override##container", override.enabled)
                if changedOverride then
                    override.enabled = enableOverride
                    Export_Core.setContainerOverride(selectedKey, override)
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
                local selectedKeys = Export_Core.getSelectedContainerKeys()
                for _, key in ipairs(selectedKeys) do
                    local override = Export_Core.getContainerOverride(key)
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
                        local override = Export_Core.getContainerOverride(key)
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
                                }
                            }
                        else
                            override.enabled = enableBatchOverride
                        end
                        Export_Core.setContainerOverride(key, override)
                    end
                end

                if allOverridesEnabled then
                    imgui.Spacing(ctx)
                    imgui.TextDisabled(ctx, "Editing applies to all selected:")
                    imgui.Spacing(ctx)

                    -- Get first selected container's override as reference
                    local refOverride = Export_Core.getContainerOverride(selectedKeys[1])
                    if refOverride then
                        Export_UI.renderBatchOverrideParams(ctx, imgui, selectedKeys, refOverride, EXPORT)
                    end
                end
            end
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
            Export_Core.setGlobalParam("exportMethod", newMethod)
        end
        imgui.PopItemWidth(ctx)

        imgui.SameLine(ctx)

        -- Show enabled count
        local enabledCount = Export_Core.getEnabledContainerCount()
        local totalCount = #Export_Core.collectAllContainers()
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
            local success, message = Export_Core.performExport()
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
        Export_Core.setContainerOverride(containerKey, override)
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
        Export_Core.setContainerOverride(containerKey, override)
    end
    imgui.PopItemWidth(ctx)

    -- Override Align to seconds
    local changedAlignOvr, newAlignOvr = imgui.Checkbox(ctx, "Align to seconds##override",
        override.params.alignToSeconds)
    if changedAlignOvr then
        override.params.alignToSeconds = newAlignOvr
        Export_Core.setContainerOverride(containerKey, override)
    end

    imgui.Spacing(ctx)

    -- Override Preserve checkboxes
    local c1, p1 = imgui.Checkbox(ctx, "Preserve Pan##override", override.params.preservePan)
    if c1 then
        override.params.preservePan = p1
        Export_Core.setContainerOverride(containerKey, override)
    end

    local c2, p2 = imgui.Checkbox(ctx, "Preserve Volume##override", override.params.preserveVolume)
    if c2 then
        override.params.preserveVolume = p2
        Export_Core.setContainerOverride(containerKey, override)
    end

    local c3, p3 = imgui.Checkbox(ctx, "Preserve Pitch##override", override.params.preservePitch)
    if c3 then
        override.params.preservePitch = p3
        Export_Core.setContainerOverride(containerKey, override)
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
        Export_Core.applyParamToSelected("instanceAmount", newAmt)
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
        Export_Core.applyParamToSelected("spacing", newSpc)
    end
    imgui.PopItemWidth(ctx)

    -- Batch Align to seconds
    local changedAlignBatch, newAlignBatch = imgui.Checkbox(ctx, "Align to seconds##batch",
        refOverride.params.alignToSeconds)
    if changedAlignBatch then
        Export_Core.applyParamToSelected("alignToSeconds", newAlignBatch)
    end

    imgui.Spacing(ctx)

    -- Batch Preserve checkboxes
    local c1, p1 = imgui.Checkbox(ctx, "Preserve Pan##batch", refOverride.params.preservePan)
    if c1 then
        Export_Core.applyParamToSelected("preservePan", p1)
    end

    local c2, p2 = imgui.Checkbox(ctx, "Preserve Volume##batch", refOverride.params.preserveVolume)
    if c2 then
        Export_Core.applyParamToSelected("preserveVolume", p2)
    end

    local c3, p3 = imgui.Checkbox(ctx, "Preserve Pitch##batch", refOverride.params.preservePitch)
    if c3 then
        Export_Core.applyParamToSelected("preservePitch", p3)
    end

    imgui.Unindent(ctx, 15)
end

return Export_UI
