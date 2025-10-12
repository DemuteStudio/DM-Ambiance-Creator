--[[
@version 1.3
@noindex
--]]

-- DM_Ambiance_UI_Core: Shared UI utilities and styling functions
-- This module provides common functionality used across all UI submodules

local Core = {}
local globals = {}

-- Initialize the module with global variables from the main script
function Core.initModule(g)
    globals = g

    -- Initialize selection variables for two-panel layout
    globals.selectedGroupIndex = nil
    globals.selectedContainerIndex = nil

    -- Initialize structure for multi-selection
    globals.selectedContainers = {} -- Format: {[groupIndex_containerIndex] = true}
    globals.inMultiSelectMode = false

    -- Initialize variables for Shift multi-selection
    globals.shiftAnchorGroupIndex = nil
    globals.shiftAnchorContainerIndex = nil

    -- Initialize splitter state
    globals.splitterDragging = false
    globals.leftPanelWidth = nil  -- Will be loaded from settings

    -- Detect default font size from ImGui
    globals.defaultFontSize = globals.imgui.GetFontSize(globals.ctx) or 13
end

-- Helper function to scale a size value
function Core.scaleSize(size)
    local uiScale = globals.Settings.getSetting("uiScale") or 1.0
    return size * uiScale
end

-- Wrapper for Button with automatic scaling
function Core.Button(ctx, label, width, height)
    local scaledWidth = width and Core.scaleSize(width) or width
    local scaledHeight = height and Core.scaleSize(height) or height
    return globals.imgui.Button(ctx, label, scaledWidth, scaledHeight)
end

-- Update UI scale (called when scale changes)
function Core.updateScale(scale)
    local ctx = globals.ctx
    local imgui = globals.imgui

    -- Only update if scale actually changed
    if globals.currentScale == scale then
        return
    end

    local oldScale = globals.currentScale or 1.0
    globals.currentScale = scale

    -- Detach old font if exists
    if globals.scaledFont then
        imgui.Detach(ctx, globals.scaledFont)
        globals.scaledFont = nil
    end

    -- Create scaled font using detected default font size
    local baseFontSize = globals.defaultFontSize or 13
    local scaledSize = math.floor(baseFontSize * scale + 0.5) -- Round to nearest integer

    globals.scaledFont = imgui.CreateFont('sans-serif', scaledSize)
    imgui.Attach(ctx, globals.scaledFont)

    -- Scale waveform heights proportionally when scale changes
    if globals.waveformHeights then
        local scaleFactor = scale / oldScale
        for key, height in pairs(globals.waveformHeights) do
            globals.waveformHeights[key] = height * scaleFactor
        end
    end
end

-- Push custom style variables for UI
function Core.PushStyle()
    local ctx = globals.ctx
    local imgui = globals.imgui
    local settings = globals.Settings
    local utils = globals.Utils

    -- Update UI scale if changed
    local uiScale = settings.getSetting("uiScale") or 1.0
    Core.updateScale(uiScale)

    -- Push scaled font
    if globals.scaledFont then
        imgui.PushFont(ctx, globals.scaledFont)
    end

    -- Item Spacing (scaled)
    local itemSpacing = settings.getSetting("itemSpacing") * uiScale
    imgui.PushStyleVar(ctx, imgui.StyleVar_ItemSpacing, itemSpacing, itemSpacing)

    -- Frame padding (scaled)
    imgui.PushStyleVar(ctx, imgui.StyleVar_FramePadding, 4 * uiScale, 3 * uiScale)

    -- Window padding (scaled)
    imgui.PushStyleVar(ctx, imgui.StyleVar_WindowPadding, 8 * uiScale, 8 * uiScale)

    -- Round Style for buttons and frames (scaled)
    local rounding = settings.getSetting("uiRounding") * uiScale

    -- Apply the user-defined rounding value
    imgui.PushStyleVar(ctx, imgui.StyleVar_DisabledAlpha, 0.68)
    imgui.PushStyleVar(ctx, imgui.StyleVar_FrameRounding, rounding)
    imgui.PushStyleVar(ctx, imgui.StyleVar_GrabRounding, rounding)
    imgui.PushStyleVar(ctx, imgui.StyleVar_GrabMinSize, 10 * uiScale)

    -- Colors
    local buttonColor = settings.getSetting("buttonColor")
    local backgroundColor = settings.getSetting("backgroundColor")
    local textColor = settings.getSetting("textColor")
    local waveformColor = settings.getSetting("waveformColor")

    -- Apply button colors
    imgui.PushStyleColor(ctx, imgui.Col_Button, buttonColor)
    imgui.PushStyleColor(ctx, imgui.Col_ButtonHovered, utils.brightenColor(buttonColor, 0.1))
    imgui.PushStyleColor(ctx, imgui.Col_ButtonActive, utils.brightenColor(buttonColor, -0.1))
    -- Apply scroll bars
    imgui.PushStyleColor(ctx, imgui.Col_ScrollbarGrab, buttonColor)
    imgui.PushStyleColor(ctx, imgui.Col_ScrollbarGrabHovered, utils.brightenColor(buttonColor, 0.1))
    imgui.PushStyleColor(ctx, imgui.Col_ScrollbarGrabActive, utils.brightenColor(buttonColor, -0.1))
    -- Apply sliders
    imgui.PushStyleColor(ctx, imgui.Col_SliderGrab, buttonColor)
    imgui.PushStyleColor(ctx, imgui.Col_SliderGrabActive, buttonColor)
    -- Apply check marks
    imgui.PushStyleColor(ctx, imgui.Col_CheckMark, buttonColor)

    -- Apply background colors
    imgui.PushStyleColor(ctx, imgui.Col_Header, utils.brightenColor(backgroundColor, 0.1))
    imgui.PushStyleColor(ctx, imgui.Col_HeaderActive, utils.brightenColor(backgroundColor, 0.2))
    imgui.PushStyleColor(ctx, imgui.Col_HeaderHovered, utils.brightenColor(backgroundColor, 0.15))
    imgui.PushStyleColor(ctx, imgui.Col_TitleBgActive, utils.brightenColor(backgroundColor, -0.01))
    imgui.PushStyleColor(ctx, imgui.Col_WindowBg, backgroundColor)
    imgui.PushStyleColor(ctx, imgui.Col_PopupBg, utils.brightenColor(backgroundColor, 0.05))
    imgui.PushStyleColor(ctx, imgui.Col_FrameBg, utils.brightenColor(backgroundColor, 0.1))
    imgui.PushStyleColor(ctx, imgui.Col_FrameBgHovered, utils.brightenColor(backgroundColor, 0.15))
    imgui.PushStyleColor(ctx, imgui.Col_FrameBgActive, utils.brightenColor(backgroundColor, 0.2))

    -- Apply text colors
    imgui.PushStyleColor(ctx, imgui.Col_Text, textColor)
    imgui.PushStyleColor(ctx, imgui.Col_CheckMark, textColor)
end

-- Pop custom style variables
function Core.PopStyle()
    local ctx = globals.ctx
    local imgui = globals.imgui

    -- Pop font if we pushed one
    if globals.scaledFont then
        imgui.PopFont(ctx)
    end

    -- Pop style colors (20 colors pushed)
    imgui.PopStyleColor(ctx, 20)

    -- Pop style vars (7 vars: ItemSpacing, FramePadding, WindowPadding, DisabledAlpha, FrameRounding, GrabRounding, GrabMinSize)
    imgui.PopStyleVar(ctx, 7)
end

-- Clear all container selections and reset selection state
function Core.clearContainerSelections()
    globals.selectedContainers = {}
    globals.inMultiSelectMode = false
    -- Also clear the shift anchor when clearing selections
    globals.shiftAnchorGroupIndex = nil
    globals.shiftAnchorContainerIndex = nil
end

-- Check if a container is selected
function Core.isContainerSelected(groupIndex, containerIndex)
    return globals.selectedContainers[groupIndex .. "_" .. containerIndex] == true
end

-- Toggle the selection state of a container
function Core.toggleContainerSelection(groupIndex, containerIndex)
    local key = groupIndex .. "_" .. containerIndex
    local isShiftPressed = (globals.imgui.GetKeyMods(globals.ctx) & globals.imgui.Mod_Shift ~= 0)

    -- If Shift is pressed and an anchor exists, select a range
    if isShiftPressed and globals.shiftAnchorGroupIndex and globals.shiftAnchorContainerIndex then
        Core.selectContainerRange(globals.shiftAnchorGroupIndex, globals.shiftAnchorContainerIndex, groupIndex, containerIndex)
    else
        -- Without Shift, clear previous selections unless Ctrl is pressed
        if not (globals.imgui.GetKeyMods(globals.ctx) & globals.imgui.Mod_Ctrl ~= 0) then
            Core.clearContainerSelections()
        end

        -- Toggle the current container selection
        if globals.selectedContainers[key] then
            globals.selectedContainers[key] = nil
        else
            globals.selectedContainers[key] = true
        end

        -- Update anchor for future Shift selections
        globals.shiftAnchorGroupIndex = groupIndex
        globals.shiftAnchorContainerIndex = containerIndex
    end

    -- Update main selection and multi-select mode
    globals.selectedGroupIndex = groupIndex
    globals.selectedContainerIndex = containerIndex
    globals.inMultiSelectMode = globals.UI_Groups.getSelectedContainersCount() > 1
end

-- Select a range of containers between two points (supports cross-group selection)
function Core.selectContainerRange(startGroupIndex, startContainerIndex, endGroupIndex, endContainerIndex)
    -- Clear selection if not in multi-select mode
    if not (globals.imgui.GetKeyMods(globals.ctx) & globals.imgui.Mod_Ctrl ~= 0) then
        Core.clearContainerSelections()
    end

    -- Range selection within the same group
    if startGroupIndex == endGroupIndex then
        local group = globals.groups[startGroupIndex]
        local startIdx = math.min(startContainerIndex, endContainerIndex)
        local endIdx = math.max(startContainerIndex, endContainerIndex)
        for i = startIdx, endIdx do
            if i <= #group.containers then
                globals.selectedContainers[startGroupIndex .. "_" .. i] = true
            end
        end
        return
    end

    -- Range selection across groups
    local startGroup = math.min(startGroupIndex, endGroupIndex)
    local endGroup = math.max(startGroupIndex, endGroupIndex)
    local firstContainerIdx, lastContainerIdx
    if startGroupIndex < endGroupIndex then
        firstContainerIdx, lastContainerIdx = startContainerIndex, endContainerIndex
    else
        firstContainerIdx, lastContainerIdx = endContainerIndex, startContainerIndex
    end

    for t = startGroup, endGroup do
        if globals.groups[t] then
            if t == startGroup then
                for c = firstContainerIdx, #globals.groups[t].containers do
                    globals.selectedContainers[t .. "_" .. c] = true
                end
            elseif t == endGroup then
                for c = 1, lastContainerIdx do
                    globals.selectedContainers[t .. "_" .. c] = true
                end
            else
                for c = 1, #globals.groups[t].containers do
                    globals.selectedContainers[t .. "_" .. c] = true
                end
            end
        end
    end

    globals.inMultiSelectMode = globals.UI_Groups.getSelectedContainersCount() > 1
end

-- Utility function to cycle through link modes
function Core.cycleLinkMode(currentMode)
    if currentMode == "unlink" then
        return "link"
    elseif currentMode == "link" then
        return "mirror"
    else -- currentMode == "mirror"
        return "unlink"
    end
end

-- Utility function to cycle through fade link modes
-- Fades support all three modes: unlink, link, and mirror
function Core.cycleFadeLinkMode(currentMode)
    return globals.LinkedSliders.cycleLinkMode(currentMode)
end

-- Apply linked slider changes
-- Keyboard shortcuts: Shift = unlink, Ctrl = link, Alt = mirror
function Core.applyLinkedSliderChange(obj, paramType, newMin, newMax, linkMode)
    -- Keyboard overrides for temporary mode changes (priority: Shift > Alt > Ctrl)
    if globals.imgui.IsKeyDown(globals.ctx, globals.imgui.Mod_Shift) then
        linkMode = "unlink"
    elseif globals.imgui.IsKeyDown(globals.ctx, globals.imgui.Mod_Alt) then
        linkMode = "mirror"
    elseif globals.imgui.IsKeyDown(globals.ctx, globals.imgui.Mod_Ctrl) then
        linkMode = "link"
    end

    if linkMode == "unlink" then
        -- Independent sliders - just apply the new values
        return newMin, newMax
    elseif linkMode == "link" then
        -- Linked sliders - maintain relative distance
        local currentMin = obj[paramType .. "Range"].min
        local currentMax = obj[paramType .. "Range"].max
        local currentRange = currentMax - currentMin

        -- Calculate which slider moved and apply the same relative change to both
        local minDiff = newMin - currentMin
        local maxDiff = newMax - currentMax

        if math.abs(minDiff) > math.abs(maxDiff) then
            -- Min slider moved more, adjust max to maintain relative distance
            return newMin, newMin + currentRange
        else
            -- Max slider moved more, adjust min to maintain relative distance
            return newMax - currentRange, newMax
        end
    elseif linkMode == "mirror" then
        -- Mirror sliders - move opposite amounts from center
        local currentMin = obj[paramType .. "Range"].min
        local currentMax = obj[paramType .. "Range"].max
        local center = (currentMin + currentMax) / 2

        -- Calculate which slider moved and mirror the change
        local minDiff = newMin - currentMin
        local maxDiff = newMax - currentMax

        if math.abs(minDiff) > math.abs(maxDiff) then
            -- Min slider moved, mirror the change to max
            local newMinFromCenter = newMin - center
            return newMin, center - newMinFromCenter
        else
            -- Max slider moved, mirror the change to min
            local newMaxFromCenter = newMax - center
            return center - newMaxFromCenter, newMax
        end
    end

    return newMin, newMax
end

--- Helper to draw a slider row with automatic variation controls using table layout
-- This provides consistent alignment without pixel-perfect positioning
function Core.drawSliderWithVariation(params)
    local sliderId = params.sliderId
    local sliderValue = params.sliderValue
    local sliderMin = params.sliderMin
    local sliderMax = params.sliderMax
    local sliderFormat = params.sliderFormat or "%.1f"
    local sliderLabel = params.sliderLabel
    local helpText = params.helpText
    local trackingKey = params.trackingKey
    local callbacks = params.callbacks
    local autoRegenCallback = params.autoRegenCallback
    local checkAutoRegen = params.checkAutoRegen
    local defaultValue = params.defaultValue or sliderValue  -- Default to current value if not specified

    -- Variation params (optional)
    local variationEnabled = params.variationEnabled ~= false  -- default true
    local variationValue = params.variationValue
    local variationDirection = params.variationDirection
    local variationLabel = params.variationLabel or "Var"
    local variationCallbacks = params.variationCallbacks or {}
    local defaultVariation = params.defaultVariation or 0  -- Variation default is typically 0

    local sliderWidth = params.sliderWidth or -1  -- -1 means fill available space
    local imgui = globals.imgui

    imgui.TableNextRow(globals.ctx)

    -- Column 1: Slider
    imgui.TableSetColumnIndex(globals.ctx, 0)
    if sliderWidth > 0 then
        imgui.PushItemWidth(globals.ctx, sliderWidth)
    else
        imgui.PushItemWidth(globals.ctx, -1)  -- Fill column width
    end

    globals.SliderEnhanced.SliderDouble({
        id = sliderId,
        value = sliderValue,
        min = sliderMin,
        max = sliderMax,
        defaultValue = defaultValue,
        format = sliderFormat,
        onChange = function(newValue, wasReset)
            if callbacks.setValue then
                callbacks.setValue(newValue)
            end
        end,
        onChangeComplete = function(oldValue, newValue)
            if checkAutoRegen then
                checkAutoRegen(trackingKey, oldValue, newValue)
            end
        end
    })

    imgui.PopItemWidth(globals.ctx)

    -- Column 2: Label with help marker
    imgui.TableSetColumnIndex(globals.ctx, 1)
    imgui.Text(globals.ctx, sliderLabel)
    if helpText then
        imgui.SameLine(globals.ctx)
        globals.Utils.HelpMarker(helpText)
    end

    -- Column 3: Variation controls (if enabled)
    if variationEnabled and variationValue ~= nil then
        imgui.TableSetColumnIndex(globals.ctx, 2)

        -- Direction button (using icon button)
        local dirChanged, newDirection = globals.Icons.createVariationDirectionButton(
            globals.ctx,
            trackingKey .. "_dir",
            variationDirection
        )
        if dirChanged and variationCallbacks.setDirection then
            variationCallbacks.setDirection(newDirection)
        end

        imgui.SameLine(globals.ctx, 0, 2)

        -- Variation knob
        local varKey = trackingKey .. "_var"
        local rvVar, newVar, wasResetVar = globals.Knob.Knob({
            id = "##" .. varKey,
            label = "",
            value = variationValue,
            min = 0,
            max = 100,
            defaultValue = defaultVariation,
            size = 24,
            format = "%d",
            showLabel = false
        })

        -- Auto-regen tracking (skip if this was a reset)
        if not wasResetVar then
            if imgui.IsItemActive(globals.ctx) and autoRegenCallback and not globals.autoRegenTracking[varKey] then
                globals.autoRegenTracking[varKey] = variationValue
            end
        end

        if rvVar and variationCallbacks.setValue then variationCallbacks.setValue(math.floor(newVar + 0.5)) end

        -- Only check auto-regen if NOT a reset
        if not wasResetVar then
            if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and autoRegenCallback and globals.autoRegenTracking[varKey] then
                if checkAutoRegen then
                    checkAutoRegen(varKey, varKey, globals.autoRegenTracking[varKey], variationValue)
                end
                globals.autoRegenTracking[varKey] = nil
            end
        end

        imgui.SameLine(globals.ctx, 0, 2)
        imgui.Text(globals.ctx, string.format("%s %d%%", variationLabel, variationValue))
    end
end

-- Get color for a specific euclidean layer index (delegates to EuclideanUI module)
-- @param layerIndex number: Layer index (1-based)
-- @param alpha number: Optional alpha value (0.0-1.0), if nil uses color's original alpha
-- @return number: Color in 0xRRGGBBAA format
function Core.getEuclideanLayerColor(layerIndex, alpha)
    return globals.EuclideanUI.getLayerColor(layerIndex, alpha)
end

-- Handle popups and force close if a popup is stuck for too long
function Core.handlePopups()
    for name, popup in pairs(globals.activePopups or {}) do
        if popup.active and reaper.time_precise() - popup.timeOpened > 5 then
            globals.imgui.CloseCurrentPopup(globals.ctx)
            globals.activePopups[name] = nil
        end
    end
end

-- Detect and fix ImGui imbalance (safety net to prevent crashes)
function Core.detectAndFixImGuiImbalance()
    -- Get ImGui context state (if accessible)
    -- This is a safety net to prevent crashes
    local success = pcall(function()
        -- Try to detect if we're in an inconsistent state
        -- by checking if any operation causes an error
        local testVar = globals.imgui.GetWindowWidth(globals.ctx)
    end)

    if not success then
        -- If there's an issue, reset some flags that might help
        globals.showMediaDirWarning = false
        globals.activePopups = {}

        -- Force close any open popups
        pcall(function()
            globals.imgui.CloseCurrentPopup(globals.ctx)
        end)
    end
end

-- Get the left panel width (with resizing support)
function Core.getLeftPanelWidth(windowWidth)
    local Constants = require("DM_Ambiance_Constants")

    -- Load saved width from settings or use default
    if globals.leftPanelWidth == nil then
        local savedWidth = globals.Settings.getSetting("leftPanelWidth")
        if savedWidth then
            globals.leftPanelWidth = savedWidth
        else
            globals.leftPanelWidth = windowWidth * Constants.UI.LEFT_PANEL_DEFAULT_WIDTH
        end
    end

    -- Ensure minimum width and adjust for window size
    local minWidth = Constants.UI.MIN_LEFT_PANEL_WIDTH
    local maxWidth = windowWidth - 200  -- Leave at least 200px for right panel
    globals.leftPanelWidth = math.max(minWidth, math.min(globals.leftPanelWidth, maxWidth))

    return globals.leftPanelWidth
end

return Core
