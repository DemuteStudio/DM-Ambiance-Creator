-- DM_Ambiance_UI_LinkedSliders.lua
-- Reusable linked sliders component with link/unlink/mirror modes
-- Provides a generic UI pattern for multiple synchronized sliders
--
-- Architecture: Separated logic from presentation
-- - Pure logic functions: Can be used standalone or by any UI layout
-- - UI components: drawHorizontal() and drawVertical() both use shared logic
--
-- Usage example (horizontal layout):
--[[
    globals.LinkedSliders.drawHorizontal({
        id = "densityRange",
        sliders = {
            {value = obj.noiseThreshold, min = 0, max = 100, format = "%.1f%%"},
            {value = obj.noiseDensity, min = 0, max = 100, format = "%.1f%%"}
        },
        linkMode = obj.densityLinkMode,
        width = 200,
        label = "Density",
        helpText = "Density range for item placement.",
        sliderLabels = {"Min Density", "Max Density"},
        onChange = function(values)
            callbacks.setNoiseThreshold(values[1])
            callbacks.setNoiseDensity(values[2])
        end,
        onChangeComplete = function()
            triggerRegeneration()
        end,
        onLinkModeChange = function(newMode)
            obj.densityLinkMode = newMode
        end
    })
--]]
--
-- Usage example (vertical layout with custom widgets):
--[[
    globals.LinkedSliders.drawVertical({
        id = "fadeRange",
        sliders = {
            {value = obj.fadeInDuration, min = 0, max = 10, format = "%.2fs"},
            {value = obj.fadeOutDuration, min = 0, max = 10, format = "%.2fs"}
        },
        linkMode = obj.fadeLinkMode,
        width = 200,
        helpText = "Fade in/out durations.",
        sliderLabels = {"Fade In", "Fade Out"},
        onChange = function(values)
            callbacks.setFadeIn(values[1])
            callbacks.setFadeOut(values[2])
        end,
        onChangeComplete = function()
            triggerRegeneration()
        end,
        onLinkModeChange = function(newMode)
            obj.fadeLinkMode = newMode
        end,
        renderSliderRow = function(sliderIndex, sliderValue)
            -- Custom rendering for each slider row
            imgui.Text(globals.ctx, sliderIndex == 1 and "Fade In:" or "Fade Out:")
            imgui.SameLine(globals.ctx)
            -- Slider rendered here by component
            -- Return widgets to render AFTER slider
            return function()
                imgui.SameLine(globals.ctx)
                imgui.Checkbox(globals.ctx, "Enabled##fade" .. sliderIndex, obj.fadeEnabled[sliderIndex])
            end
        end
    })
--]]

local LinkedSliders = {}
local globals = {}

function LinkedSliders.initModule(g)
    globals = g
end

--============================================================================
-- PURE LOGIC FUNCTIONS (No UI - Can be used standalone)
--============================================================================

--- Cycle through link modes
--- @param currentMode string: Current link mode ("unlink", "link", "mirror")
--- @return string: Next link mode in cycle
function LinkedSliders.cycleLinkMode(currentMode)
    if currentMode == "unlink" then
        return "link"
    elseif currentMode == "link" then
        return "mirror"
    else
        return "unlink"
    end
end

--- Apply link mode logic to slider values
--- @param oldSliders table: Array of original slider configs with .value field
--- @param newValues table: Array of new values from sliders
--- @param changedIndex number: Index of slider that changed (1-based)
--- @param linkMode string: Link mode to apply ("unlink", "link", "mirror")
--- @return table: Final values after applying link logic (not clamped)
function LinkedSliders.applyLinkModeLogic(oldSliders, newValues, changedIndex, linkMode)
    local numSliders = #oldSliders

    if linkMode == "unlink" then
        -- Independent: just return new values
        return newValues

    elseif linkMode == "link" then
        -- Link mode: maintain relative distances between all sliders
        -- When one slider moves, shift all others by the same amount
        local changedDiff = newValues[changedIndex] - oldSliders[changedIndex].value
        local result = {}

        for i = 1, numSliders do
            result[i] = oldSliders[i].value + changedDiff
        end

        return result

    elseif linkMode == "mirror" then
        -- Mirror mode: move sliders symmetrically from center
        -- When one slider moves, others move in opposite direction by same amount
        local changedDiff = newValues[changedIndex] - oldSliders[changedIndex].value
        local result = {}

        for i = 1, numSliders do
            if i == changedIndex then
                result[i] = newValues[i]
            else
                -- Mirror the change: if changed slider went up, others go down by same amount
                result[i] = oldSliders[i].value - changedDiff
            end
        end

        return result
    end

    -- Fallback: unlink behavior
    return newValues
end

--- Check keyboard modifiers and return effective link mode
--- @param currentLinkMode string: Current link mode
--- @return string: Effective link mode after keyboard overrides
function LinkedSliders.checkKeyboardOverrides(currentLinkMode)
    -- Keyboard overrides (priority: Shift > Alt > Ctrl)
    -- Shift: force unlink (independent adjustment)
    if imgui.IsKeyDown(globals.ctx, imgui.Mod_Shift) then
        return "unlink"
    -- Alt: force mirror (symmetric adjustment)
    elseif imgui.IsKeyDown(globals.ctx, imgui.Mod_Alt) then
        return "mirror"
    -- Ctrl: force link (maintain range)
    elseif imgui.IsKeyDown(globals.ctx, imgui.Mod_Ctrl) then
        return "link"
    end
    return currentLinkMode
end

--- Build complete help text with custom text + slider labels + generic link mode documentation
--- @param customText string: Optional custom help text
--- @param sliderLabels table: Optional array of slider label descriptions
--- @return string: Complete help text
function LinkedSliders.buildHelpText(customText, sliderLabels)
    local fullHelpText = ""

    -- Custom help text (specific to this instance)
    if customText then
        fullHelpText = customText
    end

    -- Add slider labels if provided
    if sliderLabels then
        if fullHelpText ~= "" then
            fullHelpText = fullHelpText .. "\n\n"
        end
        for i, label in ipairs(sliderLabels) do
            local sliderNum = i == 1 and "left" or (i == #sliderLabels and "right" or tostring(i))
            fullHelpText = fullHelpText .. "• " .. label .. " (" .. sliderNum .. " slider)\n"
        end
    end

    -- Generic link mode documentation (always appended)
    if fullHelpText ~= "" then
        fullHelpText = fullHelpText .. "\n"
    end
    fullHelpText = fullHelpText ..
        "Link modes:\n" ..
        "• Unlink: Adjust sliders independently\n" ..
        "• Link: Maintain range width (default)\n" ..
        "• Mirror: Move symmetrically from center\n\n" ..
        "Keyboard shortcuts:\n" ..
        "• Hold Shift: Temporarily unlink (independent)\n" ..
        "• Hold Ctrl: Temporarily link (maintain range)\n" ..
        "• Hold Alt: Temporarily mirror (symmetric)"

    return fullHelpText
end

--============================================================================
-- SHARED HELPER FUNCTIONS (Used by both layouts)
--============================================================================

--- Validate configuration
--- @param config table: Configuration to validate
local function validateConfig(config)
    if not config.id then
        error("LinkedSliders: config.id is required")
    end
    if not config.sliders or #config.sliders < 2 then
        error("LinkedSliders: config.sliders must contain at least 2 sliders")
    end
    if not config.onChange then
        error("LinkedSliders: config.onChange callback is required")
    end
end

--- Process slider value changes with link mode logic
--- @param config table: Configuration table
--- @param changedIndex number: Index of slider that changed
--- @param newValues table: New values from sliders
--- @return table: Final values after applying link mode and clamping
local function processSliderChanges(config, changedIndex, newValues)
    local effectiveMode = LinkedSliders.checkKeyboardOverrides(config.linkMode or "unlink")

    local finalValues = LinkedSliders.applyLinkModeLogic(
        config.sliders,
        newValues,
        changedIndex,
        effectiveMode
    )

    -- Clamp all values to their respective ranges
    for i, slider in ipairs(config.sliders) do
        finalValues[i] = math.max(slider.min, math.min(slider.max, finalValues[i]))
    end

    return finalValues
end

--- Track slider state for auto-regen on release
--- @param config table: Configuration table
--- @param anyActive boolean: True if any slider is currently active
--- @param anyChanged boolean: True if any value changed this frame
local function handleAutoRegenTracking(config, anyActive, anyChanged)
    if not globals.linkedSlidersTracking then
        globals.linkedSlidersTracking = {}
    end

    local trackingKey = config.id

    -- Start tracking when slider becomes active
    if anyActive and not globals.linkedSlidersTracking[trackingKey] then
        globals.linkedSlidersTracking[trackingKey] = {
            originalValues = {}
        }
        for i, slider in ipairs(config.sliders) do
            globals.linkedSlidersTracking[trackingKey].originalValues[i] = slider.value
        end
    end

    -- Trigger onChangeComplete when slider is released
    if not anyActive and globals.linkedSlidersTracking[trackingKey] then
        -- Check if values actually changed
        local hasChanged = false
        for i, slider in ipairs(config.sliders) do
            if math.abs(slider.value - globals.linkedSlidersTracking[trackingKey].originalValues[i]) > 0.001 then
                hasChanged = true
                break
            end
        end

        if hasChanged and config.onChangeComplete then
            config.onChangeComplete()
        end

        globals.linkedSlidersTracking[trackingKey] = nil
    end
end

--- Render link mode button
--- @param config table: Configuration table
local function renderLinkButton(config)
    local linkMode = config.linkMode or "unlink"

    if globals.Icons.createLinkModeButton(globals.ctx, "link_" .. config.id, linkMode, "Link mode: " .. linkMode) then
        local newMode = LinkedSliders.cycleLinkMode(linkMode)
        if config.onLinkModeChange then
            config.onLinkModeChange(newMode)
        end
        if globals.History then
            globals.History.captureState("Change link mode: " .. config.id)
        end
    end
end

--- Render help marker with complete help text
--- @param config table: Configuration table
local function renderHelpMarker(config)
    if config.helpText or config.sliderLabels then
        local fullHelpText = LinkedSliders.buildHelpText(config.helpText, config.sliderLabels)
        globals.Utils.HelpMarker(fullHelpText)
    end
end

--============================================================================
-- UI COMPONENTS
--============================================================================

--- Draw sliders horizontally in a single row
--- All sliders on same line with link button and optional label/help marker
--- @param config table: Configuration (see usage example at top of file)
--- @return boolean: true if any value changed
function LinkedSliders.drawHorizontal(config)
    validateConfig(config)

    local numSliders = #config.sliders
    local totalWidth = config.width or 200

    -- Link mode button
    renderLinkButton(config)
    imgui.SameLine(globals.ctx)

    -- Calculate individual slider width
    local spacing = 4
    local sliderWidth = (totalWidth - (spacing * (numSliders - 1))) / numSliders

    -- Track which slider changed and if any is active
    local changedIndex = nil
    local newValues = {}
    local anyChanged = false
    local anyActive = false

    -- Draw all sliders horizontally
    for i, slider in ipairs(config.sliders) do
        if i > 1 then
            imgui.SameLine(globals.ctx)
        end

        imgui.PushItemWidth(globals.ctx, sliderWidth)
        local rv, newValue = globals.UndoWrappers.SliderDouble(
            globals.ctx,
            "##" .. config.id .. "_slider" .. i,
            slider.value,
            slider.min,
            slider.max,
            slider.format or "%.1f"
        )
        imgui.PopItemWidth(globals.ctx)

        if rv then
            changedIndex = i
            anyChanged = true
        end

        if imgui.IsItemActive(globals.ctx) then
            anyActive = true
        end

        newValues[i] = newValue
    end

    -- Apply link mode logic if any slider changed
    if anyChanged then
        local finalValues = processSliderChanges(config, changedIndex, newValues)
        config.onChange(finalValues)
    end

    -- Track state for auto-regen on release
    handleAutoRegenTracking(config, anyActive, anyChanged)

    -- Label and help marker
    if config.label then
        imgui.SameLine(globals.ctx)
        imgui.Text(globals.ctx, config.label)
    end

    if config.helpText or config.sliderLabels then
        imgui.SameLine(globals.ctx)
        renderHelpMarker(config)
    end

    return anyChanged
end

--- Draw sliders vertically in separate rows
--- Each slider on its own line, allowing custom widgets beside each
--- @param config table: Configuration (see usage example at top of file)
---   Additional config fields for vertical layout:
---   - renderSliderRow: function(sliderIndex, sliderValue) -> function or nil
---       Called before each slider, receives slider index and current value
---       Return a function to be called AFTER the slider (for widgets beside slider)
---       Or return nil to render slider with default layout
---   - showLinkButtonInline: boolean - If true, show link button on first slider row (default: false)
--- @return boolean: true if any value changed
function LinkedSliders.drawVertical(config)
    validateConfig(config)

    local numSliders = #config.sliders
    local sliderWidth = config.width or 200

    -- Link button (either inline on first row or on separate line)
    if not config.showLinkButtonInline then
        renderLinkButton(config)
        if config.label then
            imgui.SameLine(globals.ctx)
            imgui.Text(globals.ctx, config.label)
        end
        if config.helpText or config.sliderLabels then
            imgui.SameLine(globals.ctx)
            renderHelpMarker(config)
        end
    end

    -- Track which slider changed and if any is active
    local changedIndex = nil
    local newValues = {}
    local anyChanged = false
    local anyActive = false

    -- Draw sliders vertically (each on its own line)
    for i, slider in ipairs(config.sliders) do
        -- Call custom row renderer if provided
        local postSliderCallback = nil
        if config.renderSliderRow then
            postSliderCallback = config.renderSliderRow(i, slider.value)
        end

        -- Link button inline on first row if requested
        if i == 1 and config.showLinkButtonInline then
            renderLinkButton(config)
            imgui.SameLine(globals.ctx)
        end

        -- Render slider
        imgui.PushItemWidth(globals.ctx, sliderWidth)
        local rv, newValue = globals.UndoWrappers.SliderDouble(
            globals.ctx,
            "##" .. config.id .. "_slider" .. i,
            slider.value,
            slider.min,
            slider.max,
            slider.format or "%.1f"
        )
        imgui.PopItemWidth(globals.ctx)

        if rv then
            changedIndex = i
            anyChanged = true
        end

        if imgui.IsItemActive(globals.ctx) then
            anyActive = true
        end

        newValues[i] = newValue

        -- Call post-slider callback (for custom widgets)
        if postSliderCallback then
            postSliderCallback()
        end

        -- Help marker and label on first row if inline mode
        if i == 1 and config.showLinkButtonInline then
            if config.label then
                imgui.SameLine(globals.ctx)
                imgui.Text(globals.ctx, config.label)
            end
            if config.helpText or config.sliderLabels then
                imgui.SameLine(globals.ctx)
                renderHelpMarker(config)
            end
        end
    end

    -- Apply link mode logic if any slider changed
    if anyChanged then
        local finalValues = processSliderChanges(config, changedIndex, newValues)
        config.onChange(finalValues)
    end

    -- Track state for auto-regen on release
    handleAutoRegenTracking(config, anyActive, anyChanged)

    return anyChanged
end

--- Backward compatibility alias
--- @param config table: Configuration
--- @return boolean: true if any value changed
function LinkedSliders.draw(config)
    return LinkedSliders.drawHorizontal(config)
end

return LinkedSliders
