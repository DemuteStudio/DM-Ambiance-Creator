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

-- Track which widgets are currently being edited to avoid duplicate captures
local activeWidgets = {}

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
    -- Check BEFORE calling the widget
    local shouldCapture = not activeWidgets[label]

    local rv, newText = globals.imgui.InputText(ctx, label, text)

    -- Capture when value FIRST changes (rv is true for the first time this session)
    if rv and shouldCapture and globals.History then
        globals.History.captureState("Edit text: " .. label)
        reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE first change for: " .. label .. "\n")
        activeWidgets[label] = true
    end

    -- Clear tracking when widget is deactivated
    if globals.imgui.IsItemDeactivated(ctx) then
        activeWidgets[label] = nil
        reaper.ShowConsoleMsg("[UndoWrappers] Deactivated: " .. label .. "\n")
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
    -- Capture state BEFORE the widget returns a changed value for the first time
    -- At this point globals.groups still has the OLD value because the calling code
    -- hasn't executed "if rv then container.value = newValue" yet
    local shouldCapture = not activeWidgets[label]

    local rv, newValue = globals.imgui.SliderDouble(ctx, label, value, min, max, format)

    -- Capture when value FIRST changes (rv is true for the first time this session)
    if rv and shouldCapture and globals.History then
        globals.History.captureState("Edit slider: " .. label)
        reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE first change for: " .. label .. "\n")
        activeWidgets[label] = true
    end

    -- Clear tracking when widget is deactivated (user releases it)
    if globals.imgui.IsItemDeactivated(ctx) then
        activeWidgets[label] = nil
        reaper.ShowConsoleMsg("[UndoWrappers] Deactivated: " .. label .. "\n")
    end

    return rv, newValue
end

-- Wrapper for SliderInt with automatic undo
function UndoWrappers.SliderInt(ctx, label, value, min, max, format)
    -- Check BEFORE calling the widget
    local shouldCapture = not activeWidgets[label]

    local rv, newValue = globals.imgui.SliderInt(ctx, label, value, min, max, format)

    -- Capture when value FIRST changes (rv is true for the first time this session)
    if rv and shouldCapture and globals.History then
        globals.History.captureState("Edit slider: " .. label)
        reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE first change for: " .. label .. "\n")
        activeWidgets[label] = true
    end

    -- Clear tracking when widget is deactivated
    if globals.imgui.IsItemDeactivated(ctx) then
        activeWidgets[label] = nil
        reaper.ShowConsoleMsg("[UndoWrappers] Deactivated: " .. label .. "\n")
    end

    return rv, newValue
end

-- Wrapper for InputDouble with automatic undo
function UndoWrappers.InputDouble(ctx, label, value, step, step_fast, format)
    -- Check BEFORE calling the widget
    local shouldCapture = not activeWidgets[label]

    local rv, newValue = globals.imgui.InputDouble(ctx, label, value, step, step_fast, format)

    -- Capture when value FIRST changes (rv is true for the first time this session)
    if rv and shouldCapture and globals.History then
        globals.History.captureState("Edit input: " .. label)
        reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE first change for: " .. label .. "\n")
        activeWidgets[label] = true
    end

    -- Clear tracking when widget is deactivated
    if globals.imgui.IsItemDeactivated(ctx) then
        activeWidgets[label] = nil
        reaper.ShowConsoleMsg("[UndoWrappers] Deactivated: " .. label .. "\n")
    end

    return rv, newValue
end

-- Wrapper for InputInt with automatic undo
function UndoWrappers.InputInt(ctx, label, value, step, step_fast)
    -- Check BEFORE calling the widget
    local shouldCapture = not activeWidgets[label]

    local rv, newValue = globals.imgui.InputInt(ctx, label, value, step, step_fast)

    -- Capture when value FIRST changes (rv is true for the first time this session)
    if rv and shouldCapture and globals.History then
        globals.History.captureState("Edit input: " .. label)
        reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE first change for: " .. label .. "\n")
        activeWidgets[label] = true
    end

    -- Clear tracking when widget is deactivated
    if globals.imgui.IsItemDeactivated(ctx) then
        activeWidgets[label] = nil
        reaper.ShowConsoleMsg("[UndoWrappers] Deactivated: " .. label .. "\n")
    end

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
    -- Check BEFORE calling the widget
    local shouldCapture = not activeWidgets[label]

    local rv, newValue = globals.imgui.DragDouble(ctx, label, value, v_speed, v_min, v_max, format)

    -- Capture when value FIRST changes (rv is true for the first time this session)
    if rv and shouldCapture and globals.History then
        globals.History.captureState("Drag value: " .. label)
        reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE first change for: " .. label .. "\n")
        activeWidgets[label] = true
    end

    -- Clear tracking when widget is deactivated
    if globals.imgui.IsItemDeactivated(ctx) then
        activeWidgets[label] = nil
        reaper.ShowConsoleMsg("[UndoWrappers] Deactivated: " .. label .. "\n")
    end

    return rv, newValue
end

-- Wrapper for DragInt with automatic undo
function UndoWrappers.DragInt(ctx, label, value, v_speed, v_min, v_max, format)
    -- Check BEFORE calling the widget
    local shouldCapture = not activeWidgets[label]

    local rv, newValue = globals.imgui.DragInt(ctx, label, value, v_speed, v_min, v_max, format)

    -- Capture when value FIRST changes (rv is true for the first time this session)
    if rv and shouldCapture and globals.History then
        globals.History.captureState("Drag value: " .. label)
        reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE first change for: " .. label .. "\n")
        activeWidgets[label] = true
    end

    -- Clear tracking when widget is deactivated
    if globals.imgui.IsItemDeactivated(ctx) then
        activeWidgets[label] = nil
        reaper.ShowConsoleMsg("[UndoWrappers] Deactivated: " .. label .. "\n")
    end

    return rv, newValue
end

-- Wrapper for ColorEdit4 with automatic undo
function UndoWrappers.ColorEdit4(ctx, label, col, flags)
    -- Check BEFORE calling the widget
    local shouldCapture = not activeWidgets[label]

    local rv, r, g, b, a = globals.imgui.ColorEdit4(ctx, label, col, flags)

    -- Capture when value FIRST changes (rv is true for the first time this session)
    if rv and shouldCapture and globals.History then
        globals.History.captureState("Edit color: " .. label)
        reaper.ShowConsoleMsg("[UndoWrappers] Captured BEFORE first change for: " .. label .. "\n")
        activeWidgets[label] = true
    end

    -- Clear tracking when widget is deactivated
    if globals.imgui.IsItemDeactivated(ctx) then
        activeWidgets[label] = nil
        reaper.ShowConsoleMsg("[UndoWrappers] Deactivated: " .. label .. "\n")
    end

    return rv, r, g, b, a
end

return UndoWrappers
