--[[
@version 1.0
@noindex
@description Automatic undo wrappers for ImGui widgets
@about
    This module provides wrapper functions for ImGui widgets that automatically
    capture state for undo/redo when the widget is activated (before editing).
--]]

local UndoWrappers = {}
local globals = {}

function UndoWrappers.initModule(g)
    if not g then
        error("UndoWrappers.initModule: globals parameter is required")
    end
    globals = g
end

-- Wrapper for InputText with automatic undo
-- @param ctx ImGui context
-- @param label Widget label
-- @param text Current text value
-- @return changed (boolean), new text value (string)
function UndoWrappers.InputText(ctx, label, text)
    local rv, newText = globals.imgui.InputText(ctx, label, text)

    -- Capture state when widget is first activated (before any changes)
    if globals.imgui.IsItemActivated(ctx) and globals.History then
        globals.History.captureState("Edit text: " .. label)
    end

    return rv, newText
end

-- Wrapper for SliderDouble with automatic undo
-- @param ctx ImGui context
-- @param label Widget label
-- @param value Current value
-- @param min Minimum value
-- @param max Maximum value
-- @param format Display format (optional)
-- @return changed (boolean), new value (number)
function UndoWrappers.SliderDouble(ctx, label, value, min, max, format)
    local rv, newValue = globals.imgui.SliderDouble(ctx, label, value, min, max, format)

    -- Capture state when widget is first activated (before any changes)
    if globals.imgui.IsItemActivated(ctx) and globals.History then
        globals.History.captureState("Edit slider: " .. label)
    end

    return rv, newValue
end

-- Wrapper for SliderInt with automatic undo
function UndoWrappers.SliderInt(ctx, label, value, min, max, format)
    local rv, newValue = globals.imgui.SliderInt(ctx, label, value, min, max, format)

    -- Capture state when widget is first activated (before any changes)
    if globals.imgui.IsItemActivated(ctx) and globals.History then
        globals.History.captureState("Edit slider: " .. label)
    end

    return rv, newValue
end

-- Wrapper for InputDouble with automatic undo
function UndoWrappers.InputDouble(ctx, label, value, step, step_fast, format)
    local rv, newValue = globals.imgui.InputDouble(ctx, label, value, step, step_fast, format)

    -- Capture state when widget is first activated (before any changes)
    if globals.imgui.IsItemActivated(ctx) and globals.History then
        globals.History.captureState("Edit input: " .. label)
    end

    return rv, newValue
end

-- Wrapper for InputInt with automatic undo
function UndoWrappers.InputInt(ctx, label, value, step, step_fast)
    local rv, newValue = globals.imgui.InputInt(ctx, label, value, step, step_fast)

    -- Capture state when widget is first activated (before any changes)
    if globals.imgui.IsItemActivated(ctx) and globals.History then
        globals.History.captureState("Edit input: " .. label)
    end

    return rv, newValue
end

-- Wrapper for Checkbox with automatic undo
function UndoWrappers.Checkbox(ctx, label, value)
    local rv, newValue = globals.imgui.Checkbox(ctx, label, value)

    -- Capture when checkbox is clicked (before value is applied)
    if rv and globals.History then
        globals.History.captureState("Toggle checkbox: " .. label)
    end

    return rv, newValue
end

-- Wrapper for Combo with automatic undo
function UndoWrappers.Combo(ctx, label, current_item, items, popup_max_height_in_items)
    local rv, newItem = globals.imgui.Combo(ctx, label, current_item, items, popup_max_height_in_items)

    -- Capture when combo selection changes (before value is applied)
    if rv and globals.History then
        globals.History.captureState("Change combo: " .. label)
    end

    return rv, newItem
end

-- Wrapper for DragDouble with automatic undo
function UndoWrappers.DragDouble(ctx, label, value, v_speed, v_min, v_max, format)
    local rv, newValue = globals.imgui.DragDouble(ctx, label, value, v_speed, v_min, v_max, format)

    -- Capture state when widget is first activated (before any changes)
    if globals.imgui.IsItemActivated(ctx) and globals.History then
        globals.History.captureState("Drag value: " .. label)
    end

    return rv, newValue
end

-- Wrapper for DragInt with automatic undo
function UndoWrappers.DragInt(ctx, label, value, v_speed, v_min, v_max, format)
    local rv, newValue = globals.imgui.DragInt(ctx, label, value, v_speed, v_min, v_max, format)

    -- Capture state when widget is first activated (before any changes)
    if globals.imgui.IsItemActivated(ctx) and globals.History then
        globals.History.captureState("Drag value: " .. label)
    end

    return rv, newValue
end

-- Wrapper for ColorEdit4 with automatic undo
function UndoWrappers.ColorEdit4(ctx, label, col, flags)
    local rv, r, g, b, a = globals.imgui.ColorEdit4(ctx, label, col, flags)

    -- Capture state when widget is first activated (before any changes)
    if globals.imgui.IsItemActivated(ctx) and globals.History then
        globals.History.captureState("Edit color: " .. label)
    end

    return rv, r, g, b, a
end

return UndoWrappers
