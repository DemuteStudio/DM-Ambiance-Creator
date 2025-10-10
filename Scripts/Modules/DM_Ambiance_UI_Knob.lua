-- DM_Ambiance_UI_Knob.lua
-- Rotary knob widget with keyboard shortcuts integration
--
-- Features:
-- - Vertical drag to change value
-- - Right-click: Reset to default value
-- - CTRL+Click: Manual input (TODO: implement input dialog)
-- - Automatic undo/redo integration
-- - Visual feedback (hover, active states)

local Knob = {}
local globals = {}

-- Animation state storage (per widget ID)
local animationStates = {}

--- Initialize module with globals table
function Knob.initModule(g)
    globals = g
end

--- Smooth interpolation for hover animation
-- @param current number Current animation value (0-1)
-- @param target number Target value (0 or 1)
-- @param speed number Animation speed (higher = faster)
-- @return number New animation value
local function smoothLerp(current, target, speed)
    local delta = target - current
    return current + delta * speed
end

--- Helper: Check if right-click to reset to default
local function shouldResetToDefault()
    local ctx = globals.ctx
    local imgui = globals.imgui

    -- Right-click when hovered (not during active drag)
    if imgui.IsItemHovered(ctx) and not imgui.IsItemActive(ctx) then
        if imgui.IsMouseClicked(ctx, 1) then  -- Right mouse button
            return true
        end
    end

    return false
end

--- Rotary Knob Widget
-- @param config table {id, label, value, min, max, defaultValue, size, format, showLabel}
-- @return changed boolean, newValue number, wasReset boolean
function Knob.Knob(config)
    local ctx = globals.ctx
    local imgui = globals.imgui

    -- Parse config
    local id = config.id or "##knob"
    local label = config.label or ""
    local value = config.value or 0
    local minValue = config.min or 0
    local maxValue = config.max or 1
    local defaultValue = config.defaultValue or ((minValue + maxValue) / 2)
    local baseSize = config.size or 24  -- Base size before scaling
    local format = config.format or "%.2f"
    local showLabel = config.showLabel ~= false  -- Default true

    -- Initialize animation state for this widget if it doesn't exist
    if not animationStates[id] then
        animationStates[id] = 0.0  -- Start at small size (0 = small, 1 = full)
    end

    local changed = false
    local newValue = value
    local wasReset = false

    -- Get initial cursor position
    local draw_list = imgui.GetWindowDrawList(ctx)
    local cursor_x, cursor_y = imgui.GetCursorScreenPos(ctx)

    -- Calculate slider-sized hitbox for interaction (to match slider height)
    local frame_padding_y = imgui.GetStyleVar(ctx, imgui.StyleVar_FramePadding)
    local text_height = imgui.GetTextLineHeight(ctx)
    local slider_height = text_height + (frame_padding_y * 2)

    -- Update animation state FIRST to check current hover
    -- We need to check hover against the CURRENT animated size, not future size
    local target = animationStates[id] > 0.5 and 1.0 or 0.0  -- Temporarily use previous state
    animationStates[id] = smoothLerp(animationStates[id], target, 0.35)  -- Faster animation (was 0.2)

    -- Interpolate size: small (slider height) to large (full baseSize)
    local animatedSize = slider_height + (baseSize - slider_height) * animationStates[id]
    local size = globals.UI and globals.UI.scaleSize(animatedSize) or animatedSize
    local hitbox_size = size  -- Hitbox matches current animated size

    -- Create invisible button with ANIMATED size (grows/shrinks with widget)
    imgui.InvisibleButton(ctx, id, hitbox_size, hitbox_size)
    local is_active = imgui.IsItemActive(ctx)
    local is_hovered = imgui.IsItemHovered(ctx)

    -- NOW update animation based on actual hover state OR active drag
    -- Keep widget expanded while dragging even if mouse moves outside
    target = (is_hovered or is_active) and 1.0 or 0.0
    animationStates[id] = smoothLerp(animationStates[id], target, 0.35)

    -- Recalculate size with updated animation
    animatedSize = slider_height + (baseSize - slider_height) * animationStates[id]
    size = globals.UI and globals.UI.scaleSize(animatedSize) or animatedSize
    local radius = size * 0.5

    -- Calculate where to draw the circle (centered in hitbox)
    local center_x = cursor_x + radius
    local center_y = cursor_y + radius

    -- Handle mouse drag
    if is_active then
        local mouse_delta_x, mouse_delta_y = imgui.GetMouseDelta(ctx)
        local delta = -mouse_delta_y * 0.005 -- Vertical drag sensitivity
        newValue = value + delta * (maxValue - minValue)
        newValue = math.max(minValue, math.min(maxValue, newValue))
        changed = (newValue ~= value)
    end

    -- Check for right-click reset
    if shouldResetToDefault() then
        newValue = defaultValue
        changed = true
        wasReset = true
    end

    -- Normalize value to 0-1 range for drawing
    local normalized = (newValue - minValue) / (maxValue - minValue)

    -- Calculate angle (start at 7 o'clock, end at 5 o'clock)
    -- This gives a 270-degree range of motion
    local angle_min = math.pi * 0.75   -- 135 degrees (7 o'clock position)
    local angle_max = math.pi * 2.25   -- 405 degrees (5 o'clock position)
    local angle = angle_min + (angle_max - angle_min) * normalized

    -- Colors (using RGBA hex format: 0xRRGGBBAA)
    -- Get button color from settings for consistency
    local buttonColor = globals.Settings and globals.Settings.getSetting("buttonColor") or 0x15856DFF

    local col_bg = is_hovered and 0x444444FF or 0x333333FF
    local col_track = 0x666666FF
    local col_fill = buttonColor  -- Use button color for fill arc
    local col_indicator = buttonColor  -- Use button color for indicator line and center dot

    -- Draw indicator line and center dot (if enabled in settings)
    local showIndicator = globals.Settings and globals.Settings.getSetting("showKnobIndicator")
    if showIndicator == nil then showIndicator = true end  -- Default to true if setting not found

    -- Function to draw the knob
    local function drawKnob()
        -- Draw background circle
        imgui.DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, col_bg)

        -- Draw track arc (background)
        imgui.DrawList_PathArcTo(draw_list, center_x, center_y, radius - 3, angle_min, angle_max, 32)
        imgui.DrawList_PathStroke(draw_list, col_track, nil, 2)

        -- Draw value arc (filled portion)
        if normalized > 0 then
            imgui.DrawList_PathArcTo(draw_list, center_x, center_y, radius - 3, angle_min, angle, 32)
            imgui.DrawList_PathStroke(draw_list, col_fill, nil, 3)
        end

        if showIndicator then
            -- Draw indicator line from center to edge
            local indicator_length = radius - 8
            local indicator_x = center_x + math.cos(angle) * indicator_length
            local indicator_y = center_y + math.sin(angle) * indicator_length
            imgui.DrawList_AddLine(draw_list, center_x, center_y, indicator_x, indicator_y, col_indicator, 2)

            -- Draw center dot
            imgui.DrawList_AddCircleFilled(draw_list, center_x, center_y, 3, col_indicator)
        end
    end

    -- If animated, defer drawing to render on top; otherwise draw immediately
    if animationStates[id] > 0.01 and globals.deferredWidgetDraws then
        table.insert(globals.deferredWidgetDraws, drawKnob)
    else
        drawKnob()
    end

    -- Draw label and value below knob
    if showLabel then
        local label_text = string.format("%s: " .. format, label, newValue)
        local text_size_x, text_size_y = imgui.CalcTextSize(ctx, label_text)
        imgui.SetCursorScreenPos(ctx, cursor_x + (size - text_size_x) * 0.5, cursor_y + size + 4)
        imgui.Text(ctx, label_text)

        -- Advance cursor to below text for next widget
        imgui.SetCursorScreenPos(ctx, cursor_x, cursor_y + size + text_size_y + 8)
    else
        -- Cursor is already advanced by InvisibleButton, no need to move it
    end

    return changed, newValue, wasReset
end

--- Wrapped Knob with Undo/Redo support
-- Uses the same API as SliderEnhanced for consistency
-- @param config table {id, label, value, min, max, defaultValue, size, format, showLabel, onChange}
-- @return changed boolean, newValue number, wasReset boolean
function Knob.KnobWithUndo(config)
    local changed, newValue, wasReset = Knob.Knob(config)

    -- If changed and onChange callback provided, trigger it
    if changed and config.onChange then
        config.onChange(newValue, wasReset)
    end

    return changed, newValue, wasReset
end

return Knob
