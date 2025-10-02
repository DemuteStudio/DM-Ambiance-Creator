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

-- Track which widgets have already captured state during current edit session
local hasCaptured = {}

function UndoWrappers.initModule(g)
    if not g then
        error("UndoWrappers.initModule: globals parameter is required")
    end
    globals = g
end

-- No longer needed - History module has its own deepCopy

-- Wrapper for InputText with automatic undo
-- @param ctx ImGui context
-- @param label Widget label
-- @param text Current text value
-- @return changed (boolean), new text value (string)
function UndoWrappers.InputText(ctx, label, text)
    local rv, newText = globals.imgui.InputText(ctx, label, text)

    -- Capture AFTER editing is complete
    if globals.imgui.IsItemDeactivatedAfterEdit(ctx) and globals.History then
        if not hasCaptured[label] then
            hasCaptured[label] = true
            globals.pendingHistoryCapture = {
                label = label,
                description = "Edit text: " .. label
            }
        end
    end

    -- Execute pending capture (one frame later)
    if globals.pendingHistoryCapture and globals.pendingHistoryCapture.label == label then
        if not globals.imgui.IsItemActive(ctx) then
            globals.History.captureState(globals.pendingHistoryCapture.description)
            globals.pendingHistoryCapture = nil
            hasCaptured[label] = nil
        end
    end

    return rv, newText
end

-- Helper function for deferred capture pattern (defined before use)
local function setupDeferredCapture(ctx, label, description)
    if globals.imgui.IsItemDeactivatedAfterEdit(ctx) and globals.History then
        if not hasCaptured[label] then
            hasCaptured[label] = true
            globals.pendingHistoryCapture = { label = label, description = description }
        end
    end
    if globals.pendingHistoryCapture and globals.pendingHistoryCapture.label == label then
        if not globals.imgui.IsItemActive(ctx) then
            globals.History.captureState(globals.pendingHistoryCapture.description)
            globals.pendingHistoryCapture = nil
            hasCaptured[label] = nil
        end
    end
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
    setupDeferredCapture(ctx, label, "Edit slider: " .. label)
    return rv, newValue
end

-- Wrapper for SliderInt with automatic undo
function UndoWrappers.SliderInt(ctx, label, value, min, max, format)
    local rv, newValue = globals.imgui.SliderInt(ctx, label, value, min, max, format)
    setupDeferredCapture(ctx, label, "Edit slider: " .. label)
    return rv, newValue
end

-- Wrapper for InputDouble with automatic undo
function UndoWrappers.InputDouble(ctx, label, value, step, step_fast, format)
    local rv, newValue = globals.imgui.InputDouble(ctx, label, value, step, step_fast, format)
    setupDeferredCapture(ctx, label, "Edit input: " .. label)
    return rv, newValue
end

-- Wrapper for InputInt with automatic undo
function UndoWrappers.InputInt(ctx, label, value, step, step_fast)
    local rv, newValue = globals.imgui.InputInt(ctx, label, value, step, step_fast)
    setupDeferredCapture(ctx, label, "Edit input: " .. label)
    return rv, newValue
end

-- Wrapper for Checkbox with automatic undo
function UndoWrappers.Checkbox(ctx, label, value)
    local rv, newValue = globals.imgui.Checkbox(ctx, label, value)

    -- For instant widgets, we still need to defer one frame to let UI code apply the value
    if rv and globals.History then
        if not hasCaptured[label] then
            hasCaptured[label] = true
            globals.pendingHistoryCapture = {
                label = label,
                description = "Toggle checkbox: " .. label
            }
        end
    end

    -- Execute pending capture (one frame later)
    if globals.pendingHistoryCapture and globals.pendingHistoryCapture.label == label then
        if not rv then  -- Checkbox not being clicked this frame
            globals.History.captureState(globals.pendingHistoryCapture.description)
            globals.pendingHistoryCapture = nil
            hasCaptured[label] = nil
        end
    end

    return rv, newValue
end

-- Wrapper for Combo with automatic undo
function UndoWrappers.Combo(ctx, label, current_item, items, popup_max_height_in_items)
    local rv, newItem = globals.imgui.Combo(ctx, label, current_item, items, popup_max_height_in_items)

    -- For instant widgets, we still need to defer one frame to let UI code apply the value
    if rv and globals.History then
        if not hasCaptured[label] then
            hasCaptured[label] = true
            globals.pendingHistoryCapture = {
                label = label,
                description = "Change combo: " .. label
            }
        end
    end

    -- Execute pending capture (one frame later)
    if globals.pendingHistoryCapture and globals.pendingHistoryCapture.label == label then
        if not rv then  -- Combo not being changed this frame
            globals.History.captureState(globals.pendingHistoryCapture.description)
            globals.pendingHistoryCapture = nil
            hasCaptured[label] = nil
        end
    end

    return rv, newItem
end

-- Wrapper for DragFloatRange2 with automatic undo (used for randomization ranges)
-- @param ctx ImGui context
-- @param label Widget label
-- @param v_current_min Current minimum value
-- @param v_current_max Current maximum value
-- @param v_speed Drag speed
-- @param v_min Minimum allowed value
-- @param v_max Maximum allowed value
-- @param format Display format (optional)
-- @param format_max Display format for max (optional)
-- @param flags ImGui slider flags (optional)
-- @return changed (boolean), new min (number), new max (number)
function UndoWrappers.DragFloatRange2(ctx, label, v_current_min, v_current_max, v_speed, v_min, v_max, format, format_max, flags)
    local rv, newMin, newMax = globals.imgui.DragFloatRange2(ctx, label, v_current_min, v_current_max, v_speed, v_min, v_max, format, format_max, flags)
    setupDeferredCapture(ctx, label, "Edit range: " .. label)
    return rv, newMin, newMax
end

-- Wrapper for DragDouble with automatic undo
function UndoWrappers.DragDouble(ctx, label, value, v_speed, v_min, v_max, format)
    local rv, newValue = globals.imgui.DragDouble(ctx, label, value, v_speed, v_min, v_max, format)
    setupDeferredCapture(ctx, label, "Drag value: " .. label)
    return rv, newValue
end

-- Wrapper for DragInt with automatic undo
function UndoWrappers.DragInt(ctx, label, value, v_speed, v_min, v_max, format)
    local rv, newValue = globals.imgui.DragInt(ctx, label, value, v_speed, v_min, v_max, format)
    setupDeferredCapture(ctx, label, "Drag value: " .. label)
    return rv, newValue
end

-- Wrapper for ColorEdit4 with automatic undo
function UndoWrappers.ColorEdit4(ctx, label, col, flags)
    local rv, r, g, b, a = globals.imgui.ColorEdit4(ctx, label, col, flags)
    setupDeferredCapture(ctx, label, "Edit color: " .. label)
    return rv, r, g, b, a
end

return UndoWrappers
