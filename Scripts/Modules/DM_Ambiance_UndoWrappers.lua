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
    -- Capture state BEFORE editing (when widget becomes active)
    if globals.imgui.IsItemActivated(ctx) then
        if globals.History then
            globals.History.captureState("Edit text: " .. label)
            reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE edit for: " .. label .. "\n")
        end
    end

    local rv, newText = globals.imgui.InputText(ctx, label, text)

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
    -- Capture state BEFORE editing (when widget becomes active)
    if globals.imgui.IsItemActivated(ctx) then
        if globals.History then
            globals.History.captureState("Edit slider: " .. label)
            reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE edit for: " .. label .. "\n")
        end
    end

    local rv, newValue = globals.imgui.SliderDouble(ctx, label, value, min, max, format)

    return rv, newValue
end

-- Wrapper for SliderInt with automatic undo
function UndoWrappers.SliderInt(ctx, label, value, min, max, format)
    if globals.imgui.IsItemActivated(ctx) then
        if globals.History then
            globals.History.captureState("Edit slider: " .. label)
            reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE edit for: " .. label .. "\n")
        end
    end

    local rv, newValue = globals.imgui.SliderInt(ctx, label, value, min, max, format)

    return rv, newValue
end

-- Wrapper for InputDouble with automatic undo
function UndoWrappers.InputDouble(ctx, label, value, step, step_fast, format)
    if globals.imgui.IsItemActivated(ctx) then
        if globals.History then
            globals.History.captureState("Edit input: " .. label)
            reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE edit for: " .. label .. "\n")
        end
    end

    local rv, newValue = globals.imgui.InputDouble(ctx, label, value, step, step_fast, format)

    return rv, newValue
end

-- Wrapper for InputInt with automatic undo
function UndoWrappers.InputInt(ctx, label, value, step, step_fast)
    if globals.imgui.IsItemActivated(ctx) then
        if globals.History then
            globals.History.captureState("Edit input: " .. label)
            reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE edit for: " .. label .. "\n")
        end
    end

    local rv, newValue = globals.imgui.InputInt(ctx, label, value, step, step_fast)

    return rv, newValue
end

-- Wrapper for Checkbox with automatic undo
function UndoWrappers.Checkbox(ctx, label, value)
    local rv, newValue = globals.imgui.Checkbox(ctx, label, value)

    -- Capture BEFORE the value is applied to globals.groups
    -- When rv is true, the checkbox was clicked, but the calling code hasn't applied
    -- the new value yet (that happens in the "if rv then" block after this returns)
    -- So globals.groups still contains the OLD value - perfect for undo!
    if rv and globals.History then
        globals.History.captureState("Toggle checkbox: " .. label)
        reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE checkbox toggle for: " .. label .. "\n")
    end

    return rv, newValue
end

-- Wrapper for Combo with automatic undo
function UndoWrappers.Combo(ctx, label, current_item, items, popup_max_height_in_items)
    local rv, newItem = globals.imgui.Combo(ctx, label, current_item, items, popup_max_height_in_items)

    -- Capture BEFORE the value is applied to globals.groups
    -- When rv is true, the combo selection changed, but the calling code hasn't applied
    -- the new value yet (that happens in the "if rv then" block after this returns)
    -- So globals.groups still contains the OLD value - perfect for undo!
    if rv and globals.History then
        globals.History.captureState("Change combo: " .. label)
        reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE combo change for: " .. label .. "\n")
    end

    return rv, newItem
end

-- Wrapper for DragDouble with automatic undo
function UndoWrappers.DragDouble(ctx, label, value, v_speed, v_min, v_max, format)
    if globals.imgui.IsItemActivated(ctx) then
        if globals.History then
            globals.History.captureState("Drag value: " .. label)
            reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE edit for: " .. label .. "\n")
        end
    end

    local rv, newValue = globals.imgui.DragDouble(ctx, label, value, v_speed, v_min, v_max, format)

    return rv, newValue
end

-- Wrapper for DragInt with automatic undo
function UndoWrappers.DragInt(ctx, label, value, v_speed, v_min, v_max, format)
    if globals.imgui.IsItemActivated(ctx) then
        if globals.History then
            globals.History.captureState("Drag value: " .. label)
            reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE edit for: " .. label .. "\n")
        end
    end

    local rv, newValue = globals.imgui.DragInt(ctx, label, value, v_speed, v_min, v_max, format)

    return rv, newValue
end

-- Wrapper for ColorEdit4 with automatic undo
function UndoWrappers.ColorEdit4(ctx, label, col, flags)
    if globals.imgui.IsItemActivated(ctx) then
        if globals.History then
            globals.History.captureState("Edit color: " .. label)
            reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE edit for: " .. label .. "\n")
        end
    end

    local rv, r, g, b, a = globals.imgui.ColorEdit4(ctx, label, col, flags)

    return rv, r, g, b, a
end

return UndoWrappers
