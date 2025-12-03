--[[
@version 1.0
@noindex
@description Euclidean rhythm mode controls for TriggerSection
Extracted from DM_Ambiance_UI_TriggerSection.lua
--]]

local TriggerSection_Euclidean = {}
local globals = {}

function TriggerSection_Euclidean.initModule(g)
    globals = g
end

-- Helper function: Get Euclidean layer color
local function getEuclideanLayerColor(layerIndex, alpha)
    return globals.EuclideanUI.getLayerColor(layerIndex, alpha)
end

-- Draw euclidean rhythm mode specific controls
-- @param dataObj table: Container or group object with euclidean parameters
-- @param callbacks table: Callback functions for parameter changes
-- @param trackingKey string: Unique key for tracking state
-- @param width number: Available width for controls
-- @param isGroup boolean: Whether this is a group (vs container)
-- @param groupPath string: Path to the group
-- @param containerIndex number: Container index (if not a group)
-- @param UI table: Reference to main UI module for helpers
function TriggerSection_Euclidean.draw(dataObj, callbacks, trackingKey, width, isGroup, groupPath, containerIndex, UI)
    local imgui = globals.imgui

    local labelWidth = 150
    local padding = 10
    local controlWidth = width - labelWidth - padding - 10

    imgui.Spacing(globals.ctx)
    imgui.Separator(globals.ctx)
    imgui.Spacing(globals.ctx)

    -- Check if this is a container whose parent is in auto-bind mode
    local isChildOfAutobindGroup = false
    if not isGroup and containerIndex and groupPath then
        local group = globals.Structures.getGroupByPath(groupPath)
        if group then
            local container = globals.Structures.getContainerFromGroup(groupPath, containerIndex)
            if container and container.overrideParent and container.intervalMode == 5 and group.euclideanAutoBindContainers then
                isChildOfAutobindGroup = true
            end
        end
    end

    -- Helper function for auto-regeneration (simplified)
    local function checkAutoRegen()
        if not globals.timeSelectionValid then
            return
        end

        if isGroup then
            -- For groups in Euclidean AutoBind mode, mark only the selected container
            if dataObj.euclideanAutoBindContainers then
                local selectedBindingIndex = dataObj.euclideanSelectedBindingIndex or 1
                local bindingOrder = dataObj.euclideanBindingOrder or {}
                local selectedUUID = bindingOrder[selectedBindingIndex]

                if selectedUUID and groupPath then
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        for _, container in ipairs(group.containers) do
                            if container.id == selectedUUID then
                                container.needsRegeneration = true
                                return
                            end
                        end
                    end
                end
            end
            dataObj.needsRegeneration = true
        else
            dataObj.needsRegeneration = true
        end
    end

    -- Mode selection (Tempo-Based / Fit-to-Selection)
    TriggerSection_Euclidean.drawModeSelection(dataObj, callbacks, trackingKey, isChildOfAutobindGroup, checkAutoRegen)

    imgui.Spacing(globals.ctx)

    -- Auto-bind to Containers checkbox (only for groups)
    if isGroup then
        TriggerSection_Euclidean.drawAutoBindCheckbox(dataObj, callbacks, trackingKey, checkAutoRegen)
        imgui.Spacing(globals.ctx)
    end

    -- Layer selection UI
    TriggerSection_Euclidean.drawLayerSelection(dataObj, callbacks, isGroup, groupPath, containerIndex)

    -- Warning if selected container is in Override mode
    TriggerSection_Euclidean.drawOverrideWarning(dataObj, isGroup, groupPath)

    imgui.Spacing(globals.ctx)

    -- Tempo controls (only for Tempo-Based mode)
    if (dataObj.euclideanMode or 0) == 0 then
        TriggerSection_Euclidean.drawTempoControls(dataObj, callbacks, trackingKey, controlWidth, padding, isChildOfAutobindGroup, checkAutoRegen)
    end

    -- Euclidean parameters layout
    TriggerSection_Euclidean.drawEuclideanParameters(dataObj, callbacks, trackingKey, isGroup, checkAutoRegen, UI)
end

-- Draw mode selection (Tempo-Based / Fit-to-Selection)
function TriggerSection_Euclidean.drawModeSelection(dataObj, callbacks, trackingKey, isChildOfAutobindGroup, checkAutoRegen)
    local imgui = globals.imgui

    imgui.BeginGroup(globals.ctx)
    if isChildOfAutobindGroup then
        imgui.BeginDisabled(globals.ctx)
    end
    local euclideanMode = dataObj.euclideanMode or 0
    local modeChanged = false
    if imgui.RadioButton(globals.ctx, "Tempo-Based##eucMode", euclideanMode == 0) then
        callbacks.setEuclideanMode(0)
        modeChanged = true
    end
    imgui.SameLine(globals.ctx)
    if imgui.RadioButton(globals.ctx, "Fit-to-Selection##eucMode", euclideanMode == 1) then
        callbacks.setEuclideanMode(1)
        modeChanged = true
    end
    if modeChanged and checkAutoRegen then
        checkAutoRegen("euclideanMode", trackingKey .. "_eucMode", not euclideanMode, euclideanMode)
    end
    if isChildOfAutobindGroup then
        imgui.EndDisabled(globals.ctx)
    end
    imgui.EndGroup(globals.ctx)
    if isChildOfAutobindGroup and imgui.IsItemHovered(globals.ctx, imgui.HoveredFlags_AllowWhenDisabled) then
        imgui.SetTooltip(globals.ctx, "This parameter is controlled by the parent group in Auto-bind mode")
    end
end

-- Draw auto-bind checkbox (only for groups)
function TriggerSection_Euclidean.drawAutoBindCheckbox(dataObj, callbacks, trackingKey, checkAutoRegen)
    local imgui = globals.imgui

    local autoBind = dataObj.euclideanAutoBindContainers or false
    local rv, newValue = imgui.Checkbox(globals.ctx, "Auto-bind to Containers##eucAutoBind", autoBind)
    imgui.SameLine(globals.ctx)
    globals.Utils.HelpMarker("When enabled, each container gets its own euclidean pattern. Layer buttons show container names.")
    if rv then
        callbacks.setEuclideanAutoBindContainers(newValue)
        if checkAutoRegen then
            checkAutoRegen("euclideanAutoBindContainers", trackingKey .. "_eucAutoBind", autoBind, newValue)
        end
    end
end

-- Draw layer selection UI
function TriggerSection_Euclidean.drawLayerSelection(dataObj, callbacks, isGroup, groupPath, containerIndex)
    local imgui = globals.imgui

    imgui.BeginGroup(globals.ctx)

    local isAutoBind = isGroup and (dataObj.euclideanAutoBindContainers or false)
    local selectedIndex = 1
    local itemCount = 0
    local itemList = {}

    if isAutoBind then
        -- Auto-bind mode: show container names
        if dataObj.euclideanBindingOrder then
            for _, uuid in ipairs(dataObj.euclideanBindingOrder) do
                local containerName = "???"
                if dataObj.containers then
                    for _, container in ipairs(dataObj.containers) do
                        if container.id == uuid then
                            containerName = container.name
                            break
                        end
                    end
                end
                table.insert(itemList, {
                    uuid = uuid,
                    name = containerName,
                    layerData = dataObj.euclideanLayerBindings[uuid]
                })
            end
        end
        itemCount = #itemList
        selectedIndex = dataObj.euclideanSelectedBindingIndex or 1
    else
        -- Manual mode: show layer numbers
        if not dataObj.euclideanLayers or #dataObj.euclideanLayers == 0 then
            dataObj.euclideanLayers = {{pulses = 8, steps = 16, rotation = 0}}
        end
        for i, layerData in ipairs(dataObj.euclideanLayers) do
            table.insert(itemList, {
                index = i,
                layerData = layerData
            })
        end
        itemCount = #itemList
        selectedIndex = dataObj.euclideanSelectedLayer or 1
    end

    -- Layer/Container buttons
    for i, item in ipairs(itemList) do
        local isSelected = (i == selectedIndex)

        -- Check if this container is in Override Parent mode
        local isOverrideParent = false
        if isAutoBind and isGroup and groupPath and item.uuid then
            local group = globals.Structures.getGroupByPath(groupPath)
            if group then
                for _, container in ipairs(group.containers) do
                    if container.id == item.uuid and container.overrideParent and container.intervalMode == 5 then
                        isOverrideParent = true
                        break
                    end
                end
            end
        end

        -- Apply button color based on state
        local colorPushed = 0
        if isOverrideParent then
            imgui.PushStyleColor(globals.ctx, imgui.Col_Button, 0xFFAA00FF)
            imgui.PushStyleColor(globals.ctx, imgui.Col_Text, 0x000000FF)
            colorPushed = 2
        elseif isSelected then
            imgui.PushStyleColor(globals.ctx, imgui.Col_Button, 0x00AA77FF)
            colorPushed = 1
        end

        local buttonLabel = ""
        local buttonWidth = 30
        if isAutoBind then
            buttonLabel = item.name .. "##eucBinding" .. i
            buttonWidth = 0
        else
            buttonLabel = tostring(i) .. "##eucLayer" .. i
            buttonWidth = 30

            local layerColor = getEuclideanLayerColor(i)
            imgui.ColorButton(globals.ctx, "##layerColor" .. i, layerColor, imgui.ColorEditFlags_NoTooltip, 12, 12)
            imgui.SameLine(globals.ctx, 0, 2)
        end

        if imgui.Button(globals.ctx, buttonLabel, buttonWidth, 0) then
            if isAutoBind then
                callbacks.setEuclideanSelectedBindingIndex(i)
                callbacks.setHighlightedContainerUUID(item.uuid)
            else
                callbacks.setEuclideanSelectedLayer(i)
            end
        end

        if colorPushed > 0 then
            imgui.PopStyleColor(globals.ctx, colorPushed)
        end

        if isOverrideParent and imgui.IsItemHovered(globals.ctx) then
            imgui.SetTooltip(globals.ctx, "⚠ This container is in Override Parent mode.\nChanges sync bidirectionally with its own euclidean settings.")
        end

        imgui.SameLine(globals.ctx)
    end

    -- "+" and "-" buttons for layer management
    if not isAutoBind then
        if imgui.Button(globals.ctx, "+##eucAddLayer", 30, 0) then
            callbacks.addEuclideanLayer()
        end
        if imgui.IsItemHovered(globals.ctx) then
            imgui.SetTooltip(globals.ctx, "Add a new Euclidean layer")
        end

        if itemCount > 1 then
            imgui.SameLine(globals.ctx)
            if imgui.Button(globals.ctx, "-##eucRemoveLayer", 30, 0) then
                callbacks.removeEuclideanLayer(selectedIndex)
            end
            if imgui.IsItemHovered(globals.ctx) then
                imgui.SetTooltip(globals.ctx, "Remove current layer")
            end
        end
    else
        if imgui.Button(globals.ctx, "+##eucAddBindingLayer", 30, 0) then
            callbacks.addEuclideanBindingLayer(selectedIndex)
        end
        if imgui.IsItemHovered(globals.ctx) then
            imgui.SetTooltip(globals.ctx, "Add layer to selected container")
        end

        local bindingLayerCount = 0
        if dataObj.euclideanBindingOrder and dataObj.euclideanBindingOrder[selectedIndex] then
            local uuid = dataObj.euclideanBindingOrder[selectedIndex]
            if dataObj.euclideanLayerBindings and dataObj.euclideanLayerBindings[uuid] then
                bindingLayerCount = #dataObj.euclideanLayerBindings[uuid]
            end
        end

        if bindingLayerCount > 1 then
            imgui.SameLine(globals.ctx)
            if imgui.Button(globals.ctx, "-##eucRemoveBindingLayer", 30, 0) then
                callbacks.removeEuclideanBindingLayer(selectedIndex)
            end
            if imgui.IsItemHovered(globals.ctx) then
                imgui.SetTooltip(globals.ctx, "Remove selected layer from container")
            end
        end
    end

    imgui.EndGroup(globals.ctx)
end

-- Draw override warning for selected container
function TriggerSection_Euclidean.drawOverrideWarning(dataObj, isGroup, groupPath)
    local imgui = globals.imgui
    local isAutoBind = isGroup and (dataObj.euclideanAutoBindContainers or false)

    if isAutoBind and isGroup and groupPath then
        local selectedIndex = dataObj.euclideanSelectedBindingIndex or 1
        local bindingOrder = dataObj.euclideanBindingOrder or {}
        local uuid = bindingOrder[selectedIndex]
        if uuid then
            local group = globals.Structures.getGroupByPath(groupPath)
            if group then
                for _, container in ipairs(group.containers) do
                    if container.id == uuid and container.overrideParent then
                        imgui.Spacing(globals.ctx)
                        imgui.PushStyleColor(globals.ctx, imgui.Col_Text, 0xFFAA00FF)
                        imgui.TextWrapped(globals.ctx, "⚠ This container is in Override Parent mode. Changes here will sync with the container's own settings.")
                        imgui.PopStyleColor(globals.ctx)
                        break
                    end
                end
            end
        end
    end
end

-- Draw tempo controls
function TriggerSection_Euclidean.drawTempoControls(dataObj, callbacks, trackingKey, controlWidth, padding, isChildOfAutobindGroup, checkAutoRegen)
    local imgui = globals.imgui

    -- Use Project Tempo checkbox
    imgui.BeginGroup(globals.ctx)
    if isChildOfAutobindGroup then
        imgui.BeginDisabled(globals.ctx)
    end
    local useProjectTempo = dataObj.euclideanUseProjectTempo or false
    local rv, newValue = imgui.Checkbox(globals.ctx, "Use Project Tempo##eucUseProjectTempo", useProjectTempo)
    if rv then
        callbacks.setEuclideanUseProjectTempo(newValue)
        if checkAutoRegen then
            checkAutoRegen("euclideanUseProjectTempo", trackingKey .. "_eucUseProjectTempo", useProjectTempo, newValue)
        end
    end
    if isChildOfAutobindGroup then
        imgui.EndDisabled(globals.ctx)
    end
    imgui.EndGroup(globals.ctx)

    if imgui.IsItemHovered(globals.ctx, isChildOfAutobindGroup and imgui.HoveredFlags_AllowWhenDisabled or 0) then
        if isChildOfAutobindGroup then
            imgui.SetTooltip(globals.ctx, "This parameter is controlled by the parent group in Auto-bind mode")
        else
            imgui.SetTooltip(globals.ctx, "Use REAPER's project tempo (supports tempo changes)")
        end
    end

    imgui.Spacing(globals.ctx)

    -- Tempo slider (only if not using project tempo)
    if not (dataObj.euclideanUseProjectTempo or false) then
        imgui.BeginGroup(globals.ctx)
        if isChildOfAutobindGroup then
            imgui.BeginDisabled(globals.ctx)
        end
        globals.SliderEnhanced.SliderDouble({
            id = "##EuclideanTempo",
            value = dataObj.euclideanTempo or 120,
            min = 20,
            max = 300,
            defaultValue = globals.Constants.DEFAULTS.EUCLIDEAN_TEMPO,
            format = "%.0f BPM",
            width = controlWidth,
            onChange = function(newValue)
                callbacks.setEuclideanTempo(newValue)
            end,
            onChangeComplete = function(oldValue, newValue)
                checkAutoRegen("euclideanTempo", oldValue, newValue)
            end
        })
        if isChildOfAutobindGroup then
            imgui.EndDisabled(globals.ctx)
        end

        imgui.EndGroup(globals.ctx)

        imgui.SameLine(globals.ctx, controlWidth + padding)
        imgui.Text(globals.ctx, "Tempo")
        imgui.SameLine(globals.ctx)
        if isChildOfAutobindGroup then
            globals.Utils.HelpMarker("This parameter is controlled by the parent group in Auto-bind mode")
        else
            globals.Utils.HelpMarker("BPM for the Euclidean pattern")
        end
    end
end

-- Draw euclidean parameters with preview
function TriggerSection_Euclidean.drawEuclideanParameters(dataObj, callbacks, trackingKey, isGroup, checkAutoRegen, UI)
    local imgui = globals.imgui

    local isAutoBind = isGroup and (dataObj.euclideanAutoBindContainers or false)
    local previewSize = UI.scaleSize(154)

    -- Left side: Preview
    UI.drawEuclideanPreview(dataObj, previewSize, isGroup)

    imgui.SameLine(globals.ctx)

    -- Right side: Scrollable container for layers
    local availWidth = imgui.GetContentRegionAvail(globals.ctx)
    local contentHeight = previewSize

    -- Calculate total content width for all layers
    local layerCount
    if not isAutoBind then
        layerCount = #dataObj.euclideanLayers
    else
        local selectedBindingIndex = dataObj.euclideanSelectedBindingIndex or 1
        local bindingOrder = dataObj.euclideanBindingOrder or {}
        local uuid = bindingOrder[selectedBindingIndex]
        local bindingLayers = {}
        if uuid and dataObj.euclideanLayerBindings and dataObj.euclideanLayerBindings[uuid] then
            bindingLayers = dataObj.euclideanLayerBindings[uuid]
        end
        layerCount = math.max(#bindingLayers, 1)
    end

    local layerWidth = 180
    local spacing = imgui.GetStyleVar(globals.ctx, imgui.StyleVar_ItemSpacing)
    local totalWidth = (layerWidth * layerCount) + (spacing * math.max(0, layerCount - 1))

    imgui.SetNextWindowContentSize(globals.ctx, totalWidth, 0)

    local windowFlags = imgui.WindowFlags_HorizontalScrollbar
    local euclideanScrollVisible = imgui.BeginChild(globals.ctx, "EuclideanLayersScroll_" .. trackingKey, availWidth, contentHeight, 0, windowFlags)

    if euclideanScrollVisible then
        if not isAutoBind then
            -- MANUAL MODE
            local adaptedCallbacks = globals.EuclideanUI.createManualModeCallbacks(callbacks)
            globals.EuclideanUI.renderLayerColumns(
                dataObj.euclideanLayers,
                trackingKey,
                adaptedCallbacks,
                checkAutoRegen,
                "manual_",
                contentHeight
            )
        else
            -- AUTO-BIND MODE
            local selectedBindingIndex = dataObj.euclideanSelectedBindingIndex or 1
            local bindingOrder = dataObj.euclideanBindingOrder or {}
            local uuid = bindingOrder[selectedBindingIndex]

            local bindingLayers = {}
            if uuid and dataObj.euclideanLayerBindings and dataObj.euclideanLayerBindings[uuid] then
                bindingLayers = dataObj.euclideanLayerBindings[uuid]
            end

            local numLayers = #bindingLayers
            if numLayers == 0 then
                bindingLayers = {{pulses = 8, steps = 16, rotation = 0}}
            end

            local adaptedCallbacks = globals.EuclideanUI.createAutoBindModeCallbacks(callbacks, selectedBindingIndex)
            local itemIdentifier = uuid or ("binding_" .. selectedBindingIndex)
            globals.EuclideanUI.renderLayerColumns(
                bindingLayers,
                trackingKey .. "_" .. itemIdentifier,
                adaptedCallbacks,
                checkAutoRegen,
                "bind" .. selectedBindingIndex .. "_",
                contentHeight
            )
        end

        imgui.EndChild(globals.ctx)
    end
end

return TriggerSection_Euclidean
