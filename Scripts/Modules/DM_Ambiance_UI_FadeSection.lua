--[[
@version 1.4
@noindex
--]]

-- Fade Settings Section UI Module
-- Extracted from monolithic DM_Ambiance_UI.lua
-- Handles fade in/out controls with link mode support

local FadeSection = {}
local globals = {}

--- Initialize the module with globals table
function FadeSection.initModule(g)
    globals = g
end

--- Utility function to cycle through fade link modes
--- Fades support all three modes: unlink, link, and mirror
local function cycleFadeLinkMode(currentMode)
    return globals.LinkedSliders.cycleLinkMode(currentMode)
end

--- Draw the fade settings section for groups or containers
--- @param obj table: The data object (group or container) containing fade parameters
--- @param objId string: Unique identifier for ImGui widget IDs
--- @param width number: Available width for the section
--- @param titlePrefix string: Prefix for the section title (e.g., "Container " or "Group ")
--- @param groupIndex number: Index of the group (required for fade updates)
--- @param containerIndex number|nil: Index of the container (nil for group-level)
function FadeSection.drawFadeSettingsSection(obj, objId, width, titlePrefix, groupIndex, containerIndex)
    local Constants = require("DM_Ambiance_Constants")

    -- Ensure all fade properties are properly initialized with defaults
    -- Only initialize if nil (not if false) to allow unchecking
    if obj.fadeInEnabled == nil then
        obj.fadeInEnabled = Constants.GENERATION_DEFAULTS.FADE_IN_ENABLED
    end
    if obj.fadeOutEnabled == nil then
        obj.fadeOutEnabled = Constants.GENERATION_DEFAULTS.FADE_OUT_ENABLED
    end
    obj.fadeInShape = obj.fadeInShape or Constants.GENERATION_DEFAULTS.FADE_IN_SHAPE
    obj.fadeOutShape = obj.fadeOutShape or Constants.GENERATION_DEFAULTS.FADE_OUT_SHAPE
    obj.fadeInCurve = obj.fadeInCurve or Constants.GENERATION_DEFAULTS.FADE_IN_CURVE
    obj.fadeOutCurve = obj.fadeOutCurve or Constants.GENERATION_DEFAULTS.FADE_OUT_CURVE
    -- Use == nil check for boolean values to allow false values
    if obj.fadeInUsePercentage == nil then
        obj.fadeInUsePercentage = Constants.GENERATION_DEFAULTS.FADE_IN_USE_PERCENTAGE
    end
    if obj.fadeOutUsePercentage == nil then
        obj.fadeOutUsePercentage = Constants.GENERATION_DEFAULTS.FADE_OUT_USE_PERCENTAGE
    end
    obj.fadeInDuration = obj.fadeInDuration or Constants.GENERATION_DEFAULTS.FADE_IN_DURATION
    obj.fadeOutDuration = obj.fadeOutDuration or Constants.GENERATION_DEFAULTS.FADE_OUT_DURATION

    -- Section separator and title
    globals.imgui.Separator(globals.ctx)
    globals.imgui.BeginGroup(globals.ctx)
    globals.imgui.Text(globals.ctx, titlePrefix .. "Fade Settings")

    -- Link mode button for fades
    globals.imgui.SameLine(globals.ctx)
    -- Ensure link mode is initialized
    if not obj.fadeLinkMode then obj.fadeLinkMode = "link" end
    if globals.Icons.createLinkModeButton(globals.ctx, "fadeLink" .. objId, obj.fadeLinkMode, "Fade link mode: " .. obj.fadeLinkMode) then
        obj.fadeLinkMode = cycleFadeLinkMode(obj.fadeLinkMode)
        -- Capture AFTER mode change
        if globals.History then
            globals.History.captureState("Change fade link mode")
        end
    end
    globals.imgui.EndGroup(globals.ctx)

    -- Layout parameters for dynamic width (matching other sections)
    local checkboxWidth = 20
    local labelWidth = 75       -- "Fade In:" / "Fade Out:"
    local unitButtonWidth = 45  -- "sec" / "%"
    local spacing = 4

    -- Calculate available space for sliders
    local totalControlWidth = width - checkboxWidth - labelWidth - 10

    -- Allocate space for duration slider, shape dropdown, and curve slider
    local shapeDropdownWidth = 120
    local curveSliderWidth = 80
    local shapeLabelWidth = 50   -- "Shape:"
    local curveLabelWidth = 50   -- "Curve:"

    -- Duration slider gets remaining space
    local durationSliderWidth = totalControlWidth - unitButtonWidth - shapeDropdownWidth - curveSliderWidth - shapeLabelWidth - curveLabelWidth - (spacing * 6)

    -- Helper function to draw fade controls with column-based alignment
    local function drawFadeControls(fadeType, enabled, duration, shape, curve)
        local suffix = fadeType .. objId
        local isIn = fadeType == "In"

        globals.imgui.BeginGroup(globals.ctx)

        -- Checkbox
        local rv, newEnabled = globals.UndoWrappers.Checkbox(globals.ctx, "##Enable" .. suffix, enabled or false)
        if rv then
            if isIn then obj.fadeInEnabled = newEnabled
            else obj.fadeOutEnabled = newEnabled end
            -- Queue fade update to avoid ImGui conflicts
            local modifiedFade = isIn and "fadeIn" or "fadeOut"
            if groupIndex and containerIndex then
                globals.Utils.queueFadeUpdate(groupIndex, containerIndex, modifiedFade)
            elseif groupIndex then
                globals.Utils.queueFadeUpdate(groupIndex, nil, modifiedFade)
            end
        end

        -- Label (with fixed width for alignment)
        globals.imgui.SameLine(globals.ctx)
        globals.imgui.BeginGroup(globals.ctx)
        globals.imgui.AlignTextToFramePadding(globals.ctx)
        globals.imgui.Text(globals.ctx, "Fade " .. fadeType .. ":")
        globals.imgui.SameLine(globals.ctx, labelWidth)  -- Force position after label
        globals.imgui.Dummy(globals.ctx, 0, 0)  -- Invisible spacer to maintain width
        globals.imgui.EndGroup(globals.ctx)

        -- Unit button (read current value from obj directly)
        globals.imgui.SameLine(globals.ctx)
        globals.imgui.BeginDisabled(globals.ctx, not enabled)
        -- Use explicit if to handle boolean false correctly (can't use 'or' operator with booleans)
        local usePercentage
        if isIn then
            usePercentage = obj.fadeInUsePercentage
        else
            usePercentage = obj.fadeOutUsePercentage
        end
        local unitText = usePercentage and "%" or "sec"
        if globals.imgui.Button(globals.ctx, unitText .. "##Unit" .. suffix, unitButtonWidth, 0) then
            if isIn then obj.fadeInUsePercentage = not obj.fadeInUsePercentage
            else obj.fadeOutUsePercentage = not obj.fadeOutUsePercentage end
            -- Queue fade update to avoid ImGui conflicts
            local modifiedFade = isIn and "fadeIn" or "fadeOut"
            if groupIndex and containerIndex then
                globals.Utils.queueFadeUpdate(groupIndex, containerIndex, modifiedFade)
            elseif groupIndex then
                globals.Utils.queueFadeUpdate(groupIndex, nil, modifiedFade)
            end
            -- Capture AFTER value change (simple buttons don't need deferred capture)
            if globals.History then
                globals.History.captureState("Toggle " .. (isIn and "fade in" or "fade out") .. " unit mode")
            end
        end

        -- Duration slider
        globals.imgui.SameLine(globals.ctx)
        local maxVal = usePercentage and 100 or 10
        local format = usePercentage and "%.0f%%" or "%.2f"
        local defaultDuration = isIn and Constants.GENERATION_DEFAULTS.FADE_IN_DURATION or Constants.GENERATION_DEFAULTS.FADE_OUT_DURATION
        local rv, newDuration = globals.SliderEnhanced.SliderDouble({
            id = "##Duration" .. suffix,
            value = duration or 0.1,
            min = 0,
            max = maxVal,
            defaultValue = defaultDuration,
            format = format,
            width = durationSliderWidth
        })
        if rv then
            -- Apply link mode logic using LinkedSliders logic functions
            local effectiveMode = globals.LinkedSliders.checkKeyboardOverrides(obj.fadeLinkMode or "link")

            -- Build sliders config for link mode logic
            local fadeSliders = {
                {value = obj.fadeInDuration or 0.1},
                {value = obj.fadeOutDuration or 0.1}
            }
            local changedIndex = isIn and 1 or 2
            local newValues = {isIn and newDuration or obj.fadeInDuration, isIn and obj.fadeOutDuration or newDuration}

            -- Apply link mode logic
            local finalValues = globals.LinkedSliders.applyLinkModeLogic(fadeSliders, newValues, changedIndex, effectiveMode)

            -- Clamp to valid range
            finalValues[1] = math.max(0, math.min(maxVal, finalValues[1]))
            finalValues[2] = math.max(0, math.min(maxVal, finalValues[2]))

            -- Update both fade durations
            obj.fadeInDuration = finalValues[1]
            obj.fadeOutDuration = finalValues[2]

            -- Queue fade update to avoid ImGui conflicts
            local modifiedFade = isIn and "fadeIn" or "fadeOut"
            if groupIndex and containerIndex then
                globals.Utils.queueFadeUpdate(groupIndex, containerIndex, modifiedFade)
            elseif groupIndex then
                globals.Utils.queueFadeUpdate(groupIndex, nil, modifiedFade)
            end
        end

        -- Interactive Fade Widget (replaces shape dropdown and curve slider)
        globals.imgui.SameLine(globals.ctx)
        -- For fade out, invert the curve value for display to match REAPER's behavior
        local displayCurve = (not isIn) and -(curve or 0.0) or (curve or 0.0)
        local shapeChanged, newShape, curveChanged, newCurve = globals.FadeWidget.FadeWidget({
            id = "##FadeWidget" .. suffix,
            fadeType = fadeType,
            shape = shape or 0,
            curve = displayCurve,
            size = 48
        })

        if shapeChanged then
            if isIn then obj.fadeInShape = newShape
            else obj.fadeOutShape = newShape end
            -- Queue fade update to avoid ImGui conflicts
            local modifiedFade = isIn and "fadeIn" or "fadeOut"
            if groupIndex and containerIndex then
                globals.Utils.queueFadeUpdate(groupIndex, containerIndex, modifiedFade)
            elseif groupIndex then
                globals.Utils.queueFadeUpdate(groupIndex, nil, modifiedFade)
            end
        end

        if curveChanged then
            -- For fade out, invert the curve value to match REAPER's behavior
            local finalCurve = (not isIn) and -newCurve or newCurve
            if isIn then obj.fadeInCurve = finalCurve
            else obj.fadeOutCurve = finalCurve end
            -- Queue fade update to avoid ImGui conflicts
            local modifiedFade = isIn and "fadeIn" or "fadeOut"
            if groupIndex and containerIndex then
                globals.Utils.queueFadeUpdate(groupIndex, containerIndex, modifiedFade)
            elseif groupIndex then
                globals.Utils.queueFadeUpdate(groupIndex, nil, modifiedFade)
            end
        end

        globals.imgui.EndDisabled(globals.ctx)
        globals.imgui.EndGroup(globals.ctx)
    end

    -- Draw Fade In controls
    drawFadeControls("In",
        obj.fadeInEnabled,
        obj.fadeInDuration,
        obj.fadeInShape,
        obj.fadeInCurve)

    -- Draw Fade Out controls
    drawFadeControls("Out",
        obj.fadeOutEnabled,
        obj.fadeOutDuration,
        obj.fadeOutShape,
        obj.fadeOutCurve)
end

return FadeSection
