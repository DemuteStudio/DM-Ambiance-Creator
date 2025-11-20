--[[
@version 1.0
@noindex
--]]
-- DM_Ambiance_UI_SliderEnhanced.lua
-- Enhanced slider wrappers with unified keyboard shortcuts
--
-- Features:
-- - CTRL+Click: Manual input (native ImGui behavior, preserved)
-- - Right-click: Reset to default value
-- - CTRL+Drag: Preserved for LinkedSliders (no conflict)
-- - Automatic undo/redo integration
-- - onChange callback: Called during drag (immediate value updates)
-- - onChangeComplete callback: Called when slider released (auto-regeneration)

local SliderEnhanced = {}
local globals = {}

--- Initialize module with globals table
function SliderEnhanced.initModule(g)
    globals = g

    -- Initialize tracking table for auto-regeneration
    if not globals.sliderTracking then
        globals.sliderTracking = {}
    end
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

--- Helper: Handle auto-regeneration tracking and callbacks
--- Similar to LinkedSliders.handleAutoRegenTracking()
local function handleAutoRegenTracking(config, rv, newValue, wasReset)
    local ctx = globals.ctx
    local imgui = globals.imgui
    local trackingKey = config.id

    -- Store original value when slider becomes active
    if imgui.IsItemActive(ctx) and not globals.sliderTracking[trackingKey] then
        globals.sliderTracking[trackingKey] = config.value
    end

    -- Call onChange callback during drag (immediate updates)
    if rv and config.onChange then
        config.onChange(newValue, wasReset)
    end

    -- Call onChangeComplete when slider is released AND value changed
    if imgui.IsItemDeactivatedAfterEdit(ctx) and globals.sliderTracking[trackingKey] then
        local originalValue = globals.sliderTracking[trackingKey]
        local valueChanged = math.abs(originalValue - newValue) > 0.0001

        if valueChanged and config.onChangeComplete then
            config.onChangeComplete(originalValue, newValue)
        end

        -- Cleanup tracking
        globals.sliderTracking[trackingKey] = nil
    end
end

--- Enhanced SliderDouble with shortcuts
-- @param config table {id, value, min, max, defaultValue, format, width, onChange, onChangeComplete}
-- @return changed boolean, newValue number, wasReset boolean
function SliderEnhanced.SliderDouble(config)
    local ctx = globals.ctx
    local imgui = globals.imgui
    local id = config.id or "##slider"
    local value = config.value or 0
    local minValue = config.min or 0
    local maxValue = config.max or 100
    local defaultValue = config.defaultValue or value
    local format = config.format or "%.1f"
    local width = config.width

    -- Set width if specified
    if width then
        imgui.PushItemWidth(ctx, width)
    end

    -- Render slider via UndoWrapper (CTRL+Click = native ImGui manual input)
    local rv, newValue = globals.UndoWrappers.SliderDouble(ctx, id, value, minValue, maxValue, format)

    if width then
        imgui.PopItemWidth(ctx)
    end

    -- Check for right-click to reset to default
    local wasReset = false
    if shouldResetToDefault() then
        newValue = defaultValue
        rv = true
        wasReset = true
    end

    -- Handle auto-regeneration tracking and callbacks
    handleAutoRegenTracking(config, rv, newValue, wasReset)

    return rv, newValue, wasReset
end

--- Enhanced SliderInt with shortcuts
-- @param config table {id, value, min, max, defaultValue, format, width, onChange, onChangeComplete}
-- @return changed boolean, newValue integer, wasReset boolean
function SliderEnhanced.SliderInt(config)
    local ctx = globals.ctx
    local imgui = globals.imgui
    local id = config.id or "##slider"
    local value = config.value or 0
    local minValue = config.min or 0
    local maxValue = config.max or 100
    local defaultValue = config.defaultValue or value
    local format = config.format or "%d"
    local width = config.width

    -- Set width if specified
    if width then
        imgui.PushItemWidth(ctx, width)
    end

    -- Render slider via UndoWrapper (CTRL+Click = native ImGui manual input)
    local rv, newValue = globals.UndoWrappers.SliderInt(ctx, id, value, minValue, maxValue, format)

    if width then
        imgui.PopItemWidth(ctx)
    end

    -- Check for right-click to reset to default
    local wasReset = false
    if shouldResetToDefault() then
        newValue = defaultValue
        rv = true
        wasReset = true
    end

    -- Handle auto-regeneration tracking and callbacks
    handleAutoRegenTracking(config, rv, newValue, wasReset)

    return rv, newValue, wasReset
end

--- Enhanced DragDouble with shortcuts
-- @param config table {id, value, speed, min, max, defaultValue, format, width, onChange, onChangeComplete}
-- @return changed boolean, newValue number, wasReset boolean
function SliderEnhanced.DragDouble(config)
    local ctx = globals.ctx
    local imgui = globals.imgui
    local id = config.id or "##drag"
    local value = config.value or 0
    local speed = config.speed or 1.0
    local minValue = config.min or 0
    local maxValue = config.max or 100
    local defaultValue = config.defaultValue or value
    local format = config.format or "%.1f"
    local width = config.width

    -- Set width if specified
    if width then
        imgui.PushItemWidth(ctx, width)
    end

    -- Render drag via UndoWrapper (CTRL+Click = native ImGui manual input)
    local rv, newValue = globals.UndoWrappers.DragDouble(ctx, id, value, speed, minValue, maxValue, format)

    if width then
        imgui.PopItemWidth(ctx)
    end

    -- Check for right-click to reset to default
    local wasReset = false
    if shouldResetToDefault() then
        newValue = defaultValue
        rv = true
        wasReset = true
    end

    -- Handle auto-regeneration tracking and callbacks
    handleAutoRegenTracking(config, rv, newValue, wasReset)

    return rv, newValue, wasReset
end

--- Enhanced DragInt with shortcuts
-- @param config table {id, value, speed, min, max, defaultValue, format, width, onChange, onChangeComplete}
-- @return changed boolean, newValue integer, wasReset boolean
function SliderEnhanced.DragInt(config)
    local ctx = globals.ctx
    local imgui = globals.imgui
    local id = config.id or "##drag"
    local value = config.value or 0
    local speed = config.speed or 1.0
    local minValue = config.min or 0
    local maxValue = config.max or 100
    local defaultValue = config.defaultValue or value
    local format = config.format or "%d"
    local width = config.width

    -- Set width if specified
    if width then
        imgui.PushItemWidth(ctx, width)
    end

    -- Render drag via UndoWrapper (CTRL+Click = native ImGui manual input)
    local rv, newValue = globals.UndoWrappers.DragInt(ctx, id, value, speed, minValue, maxValue, format)

    if width then
        imgui.PopItemWidth(ctx)
    end

    -- Check for right-click to reset to default
    local wasReset = false
    if shouldResetToDefault() then
        newValue = defaultValue
        rv = true
        wasReset = true
    end

    -- Handle auto-regeneration tracking and callbacks
    handleAutoRegenTracking(config, rv, newValue, wasReset)

    return rv, newValue, wasReset
end

return SliderEnhanced
