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

--- Initialize module with globals table
function Knob.initModule(g)
    globals = g
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
    local size = config.size or 50
    local format = config.format or "%.2f"
    local showLabel = config.showLabel ~= false  -- Default true

    local radius = size * 0.5
    local changed = false
    local newValue = value
    local wasReset = false

    -- Get draw list and position
    local draw_list = imgui.GetWindowDrawList(ctx)
    local pos_x, pos_y = imgui.GetCursorScreenPos(ctx)
    local center_x = pos_x + radius
    local center_y = pos_y + radius

    -- Create invisible button for interaction
    imgui.InvisibleButton(ctx, id, size, size)
    local is_active = imgui.IsItemActive(ctx)
    local is_hovered = imgui.IsItemHovered(ctx)

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
    local col_bg = is_hovered and 0x444444FF or 0x333333FF
    local col_track = 0x666666FF
    local col_fill = is_active and 0x00AAFFFF or 0x0088FFFF
    local col_knob = 0xEEEEEEFF

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

    -- Draw indicator line from center to edge
    local indicator_length = radius - 8
    local indicator_x = center_x + math.cos(angle) * indicator_length
    local indicator_y = center_y + math.sin(angle) * indicator_length
    imgui.DrawList_AddLine(draw_list, center_x, center_y, indicator_x, indicator_y, col_knob, 2)

    -- Draw center dot
    imgui.DrawList_AddCircleFilled(draw_list, center_x, center_y, 3, col_knob)

    -- Draw label and value below knob
    if showLabel then
        local label_text = string.format("%s: " .. format, label, newValue)
        local text_size_x, text_size_y = imgui.CalcTextSize(ctx, label_text)
        imgui.SetCursorScreenPos(ctx, pos_x + (size - text_size_x) * 0.5, pos_y + size + 4)
        imgui.Text(ctx, label_text)

        -- Advance cursor to below text for next widget
        imgui.SetCursorScreenPos(ctx, pos_x, pos_y + size + text_size_y + 8)
    else
        -- Just advance cursor past the knob
        imgui.SetCursorScreenPos(ctx, pos_x, pos_y + size + 4)
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
