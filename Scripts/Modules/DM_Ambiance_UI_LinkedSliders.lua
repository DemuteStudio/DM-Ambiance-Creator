-- DM_Ambiance_UI_LinkedSliders.lua
-- Reusable linked sliders component with link/unlink/mirror modes
-- Provides a generic UI pattern for multiple synchronized sliders
--
-- Usage example:
--[[
    globals.LinkedSliders.draw({
        id = "densityRange",
        sliders = {
            {value = obj.noiseThreshold, min = 0, max = 100, format = "%.1f%%"},
            {value = obj.noiseDensity, min = 0, max = 100, format = "%.1f%%"}
        },
        linkMode = obj.densityLinkMode,
        width = 200,
        label = "Density",
        helpText = "Density range for item placement.",  -- Custom help (optional)
        sliderLabels = {"Min Density", "Max Density"},   -- Slider descriptions (optional)
        onChange = function(values)
            callbacks.setNoiseThreshold(values[1])
            callbacks.setNoiseDensity(values[2])
        end,
        onChangeComplete = function()                    -- Called when slider released (optional)
            triggerRegeneration()
        end,
        onLinkModeChange = function(newMode)
            obj.densityLinkMode = newMode
        end
    })

    -- The help marker will automatically show:
    -- 1. Custom helpText
    -- 2. Slider labels with positions (left/right)
    -- 3. Generic link mode documentation (always appended)
    -- 4. Keyboard shortcuts (Shift/Alt)
]]

local LinkedSliders = {}
local globals = {}

function LinkedSliders.initModule(g)
    globals = g
end

--- Cycle through link modes
--- @param currentMode string: Current link mode
--- @return string: Next link mode
local function cycleLinkMode(currentMode)
    if currentMode == "unlink" then
        return "link"
    elseif currentMode == "link" then
        return "mirror"
    else
        return "unlink"
    end
end

--- Apply link mode logic to slider values
--- @param oldSliders table: Array of original slider configs
--- @param newValues table: Array of new values from sliders
--- @param changedIndex number: Index of slider that changed
--- @param linkMode string: Link mode to apply
--- @return table: Final values after applying link logic
local function applyLinkLogic(oldSliders, newValues, changedIndex, linkMode)
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
        -- Calculate center point from all slider values
        local centerSum = 0
        for i = 1, numSliders do
            centerSum = centerSum + oldSliders[i].value
        end
        local center = centerSum / numSliders

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

--- Create a set of linked sliders with customizable behavior
--- @param config table: Configuration table with the following fields:
---   - id string: Unique identifier for this slider set
---   - sliders table: Array of slider definitions, each with:
---       * value number: Current value
---       * min number: Minimum value
---       * max number: Maximum value
---       * format string: Display format (e.g., "%.1f%%", "%.2f")
---       * label string: Optional label for individual slider
---   - linkMode string: Current link mode ("unlink", "link", "mirror")
---   - width number: Total width for all sliders
---   - label string: Main label for the slider set
---   - helpText string: Optional custom help text (prepended to generic link mode help)
---   - sliderLabels table: Optional array of labels for individual sliders (e.g., {"Min", "Max"})
---   - onChange function(values table): Callback with new values array
---   - onChangeComplete function(): Optional callback when slider is released
---   - onLinkModeChange function(newMode string): Callback when link mode changes
--- @return boolean: true if any value changed
function LinkedSliders.draw(config)
    -- Validate config
    if not config.id then
        error("LinkedSliders.draw: config.id is required")
    end
    if not config.sliders or #config.sliders < 2 then
        error("LinkedSliders.draw: config.sliders must contain at least 2 sliders")
    end
    if not config.onChange then
        error("LinkedSliders.draw: config.onChange callback is required")
    end

    local numSliders = #config.sliders
    local linkMode = config.linkMode or "unlink"
    local totalWidth = config.width or 200

    -- Link mode button
    if globals.Icons.createLinkModeButton(globals.ctx, "link_" .. config.id, linkMode, "Link mode: " .. linkMode) then
        local newMode = cycleLinkMode(linkMode)
        if config.onLinkModeChange then
            config.onLinkModeChange(newMode)
        end
        if globals.History then
            globals.History.captureState("Change link mode: " .. config.id)
        end
    end

    imgui.SameLine(globals.ctx)

    -- Calculate individual slider width
    local spacing = 4
    local sliderWidth = (totalWidth - (spacing * (numSliders - 1))) / numSliders

    -- Track which slider changed and if any is active
    local changedIndex = nil
    local newValues = {}
    local anyChanged = false
    local anyActive = false

    -- Draw all sliders
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

        -- Check if this slider is currently being dragged
        if imgui.IsItemActive(globals.ctx) then
            anyActive = true
        end

        newValues[i] = newValue
    end

    -- Apply link mode logic if any slider changed
    if anyChanged then
        local effectiveMode = linkMode

        -- Keyboard overrides for temporary mode changes (priority order: Shift > Alt > Ctrl)
        -- Shift: force unlink mode (independent adjustment)
        if imgui.IsKeyDown(globals.ctx, imgui.Mod_Shift) then
            effectiveMode = "unlink"
        -- Alt: force mirror mode (symmetric adjustment)
        elseif imgui.IsKeyDown(globals.ctx, imgui.Mod_Alt) then
            effectiveMode = "mirror"
        -- Ctrl: force link mode (maintain range)
        elseif imgui.IsKeyDown(globals.ctx, imgui.Mod_Ctrl) then
            effectiveMode = "link"
        end

        local finalValues = applyLinkLogic(
            config.sliders,
            newValues,
            changedIndex,
            effectiveMode
        )

        -- Clamp all values to their respective ranges
        for i, slider in ipairs(config.sliders) do
            finalValues[i] = math.max(slider.min, math.min(slider.max, finalValues[i]))
        end

        -- Always update values during drag
        config.onChange(finalValues)
    end

    -- Track state for auto-regen on release
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

    -- Label and help marker
    if config.label then
        imgui.SameLine(globals.ctx)
        imgui.Text(globals.ctx, config.label)
    end

    -- Build complete help text (custom + generic)
    if config.helpText or config.sliderLabels then
        imgui.SameLine(globals.ctx)

        local fullHelpText = ""

        -- Custom help text (specific to this instance)
        if config.helpText then
            fullHelpText = config.helpText
        end

        -- Add slider labels if provided
        if config.sliderLabels then
            if fullHelpText ~= "" then
                fullHelpText = fullHelpText .. "\n\n"
            end
            for i, label in ipairs(config.sliderLabels) do
                local sliderNum = i == 1 and "left" or (i == #config.sliderLabels and "right" or tostring(i))
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

        globals.Utils.HelpMarker(fullHelpText)
    end

    return anyChanged
end

return LinkedSliders
