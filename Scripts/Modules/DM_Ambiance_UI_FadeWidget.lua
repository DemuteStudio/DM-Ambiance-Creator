-- DM_Ambiance_UI_FadeWidget.lua
-- Interactive fade widget combining visualization, shape selection, and curve adjustment
--
-- Features:
-- - Visual representation of fade curve
-- - Left-click + drag: Adjust curve value
-- - Right-click: Open shape selection popup
-- - Compact all-in-one design

local FadeWidget = {}
local globals = {}

-- Animation state storage (per widget ID)
local animationStates = {}

--- Initialize module with globals table
function FadeWidget.initModule(g)
    globals = g
end

--- Smooth interpolation for hover animation with ease-out
-- @param current number Current animation value (0-1)
-- @param target number Target value (0 or 1)
-- @param speed number Animation speed (higher = faster)
-- @return number New animation value
local function smoothLerp(current, target, speed)
    local delta = target - current

    -- Higher speed for snappier animation that doesn't slow down too much at the end
    local adjustedSpeed = 0.45

    if math.abs(delta) < 0.001 then
        return target  -- Snap to target when very close
    end

    return current + delta * adjustedSpeed
end

--- Helper: Calculate fade curve Y position for given X
-- Approximates the fade shape visually
local function calculateFadeCurve(x, shape, curve)
    local Constants = globals.Constants

    if shape == Constants.FADE_SHAPES.LINEAR then
        -- Linear with curve adjustment (power curve)
        if curve == 0 then
            return x
        elseif curve > 0 then
            -- Exponential (fast end)
            return x ^ (1 + curve * 2)
        else
            -- Logarithmic (fast start)
            return 1 - (1 - x) ^ (1 - curve * 2)
        end
    elseif shape == Constants.FADE_SHAPES.FAST_START then
        -- Logarithmic
        return 1 - (1 - x) ^ 2
    elseif shape == Constants.FADE_SHAPES.FAST_END then
        -- Exponential
        return x ^ 2
    elseif shape == Constants.FADE_SHAPES.FAST_START_END then
        -- Fast both ends (S-curve variant)
        if x < 0.5 then
            return 2 * (x ^ 2)
        else
            return 1 - 2 * ((1 - x) ^ 2)
        end
    elseif shape == Constants.FADE_SHAPES.SLOW_START_END then
        -- Slow both ends (inverse S-curve)
        return x * x * (3 - 2 * x)  -- Smoothstep
    elseif shape == Constants.FADE_SHAPES.BEZIER then
        -- Bezier curve with adjustable curve parameter
        local t = x
        local tension = curve  -- -1 to 1
        -- Cubic bezier approximation
        return t * t * (3 - 2 * t + tension * t * (1 - t))
    elseif shape == Constants.FADE_SHAPES.S_CURVE then
        -- S-curve with adjustable center bias
        -- Positive curve = push center up (more volume in middle)
        -- Negative curve = pull center down (less volume in middle)

        -- Adjust both steepness and center based on curve parameter
        -- Higher absolute curve value = much steeper S-curve
        local base_steepness = 4 + math.abs(curve) * 15  -- Range from 4 to 19
        local center_offset = -curve * 0.2  -- Adjust center position (inverted to match REAPER)

        local sigmoid = function(t)
            return 1 / (1 + math.exp(-base_steepness * (t - (0.5 - center_offset))))
        end

        -- Normalize to 0-1 range
        local y0 = sigmoid(0)
        local y1 = sigmoid(1)
        local raw_y = sigmoid(x)
        return (raw_y - y0) / (y1 - y0)
    end

    return x  -- Fallback to linear
end

--- Interactive Fade Widget
-- @param config table {id, fadeType, shape, curve, width, height, onShapeChange, onCurveChange}
-- @return shapeChanged boolean, newShape number, curveChanged boolean, newCurve number
function FadeWidget.FadeWidget(config)
    local ctx = globals.ctx
    local imgui = globals.imgui
    local Constants = globals.Constants

    -- Parse config
    local id = config.id or "##fadewidget"
    local fadeType = config.fadeType or "In"  -- "In" or "Out"
    local shape = config.shape or Constants.FADE_SHAPES.LINEAR
    local curve = config.curve or 0.0
    local baseSize = config.size or 48  -- Square widget, default size

    -- Initialize animation state for this widget if it doesn't exist
    if not animationStates[id] then
        animationStates[id] = 0.0  -- Start at small size (0 = small, 1 = full)
    end

    local shapeChanged = false
    local curveChanged = false
    local newShape = shape
    local newCurve = curve

    -- Calculate slider-sized dimensions
    local frame_padding_y = imgui.GetStyleVar(ctx, imgui.StyleVar_FramePadding)
    local text_height = imgui.GetTextLineHeight(ctx)
    local slider_height = text_height + (frame_padding_y * 2)

    -- Get draw list and cursor position
    local draw_list = imgui.GetWindowDrawList(ctx)
    local cursor_x, cursor_y = imgui.GetCursorScreenPos(ctx)

    -- Use current animation state to determine size for this frame
    local currentAnimState = animationStates[id]
    local animatedSize = slider_height + (baseSize - slider_height) * currentAnimState
    local size = globals.UI and globals.UI.scaleSize(animatedSize) or animatedSize

    -- Create invisible button with current animated size
    imgui.InvisibleButton(ctx, id, size, size)
    local is_active = imgui.IsItemActive(ctx)
    local is_hovered = imgui.IsItemHovered(ctx)

    -- Update animation for NEXT frame based on hover/active state
    local target = (is_hovered or is_active) and 1.0 or 0.0
    animationStates[id] = smoothLerp(animationStates[id], target, 0.35)

    -- Calculate drawing position (centered in hitbox)
    local draw_x = cursor_x
    local draw_y = cursor_y

    -- Handle left-click drag to adjust curve (only for shapes that support curve)
    local supportsCurve = (shape == Constants.FADE_SHAPES.LINEAR or
                          shape == Constants.FADE_SHAPES.BEZIER or
                          shape == Constants.FADE_SHAPES.S_CURVE)

    if supportsCurve and is_active then
        local mouse_delta_x, mouse_delta_y = imgui.GetMouseDelta(ctx)
        -- Vertical drag adjusts curve (drag up = positive delta = curve goes up)
        local delta = mouse_delta_y * 0.005
        newCurve = curve + delta
        newCurve = math.max(-1.0, math.min(1.0, newCurve))
        curveChanged = (newCurve ~= curve)
    end

    -- Handle right-click for shape selection
    if imgui.IsItemHovered(ctx) and imgui.IsMouseClicked(ctx, 1) then
        imgui.OpenPopup(ctx, "FadeShapePopup" .. id)
    end

    -- Colors
    local col_bg = is_hovered and 0x333333FF or 0x2A2A2AFF
    local col_border = is_active and 0x888888FF or 0x555555FF
    local buttonColor = globals.Settings and globals.Settings.getSetting("buttonColor") or 0x15856DFF
    local col_curve = buttonColor
    local col_text = 0xD5D5D5FF

    -- Function to draw the fade widget
    local function drawFadeWidget()
        -- Draw background (square) - use draw_x and draw_y for positioning
        imgui.DrawList_AddRectFilled(draw_list, draw_x, draw_y, draw_x + size, draw_y + size, col_bg, 2)
        imgui.DrawList_AddRect(draw_list, draw_x, draw_y, draw_x + size, draw_y + size, col_border, 2, nil, 1)

        -- Draw fade curve
        local padding = 4
        local curve_start_x = draw_x + padding
        local curve_end_x = draw_x + size - padding
        local curve_start_y = draw_y + size - padding
        local curve_end_y = draw_y + padding
        local curve_width = curve_end_x - curve_start_x
        local curve_height = curve_start_y - curve_end_y

        -- Draw curve as series of line segments
        local segments = 30
        for i = 0, segments - 1 do
            local t1 = i / segments
            local t2 = (i + 1) / segments

            -- For fade out, mirror horizontally (start from right)
            local x1, y1, x2, y2
            if fadeType == "Out" then
                -- Fade out: curve goes from right (full) to left (zero)
                x1 = 1 - t1
                y1 = calculateFadeCurve(t1, shape, curve)
                x2 = 1 - t2
                y2 = calculateFadeCurve(t2, shape, curve)
            else
                -- Fade in: curve goes from left (zero) to right (full)
                x1 = t1
                y1 = calculateFadeCurve(t1, shape, curve)
                x2 = t2
                y2 = calculateFadeCurve(t2, shape, curve)
            end

            local screen_x1 = curve_start_x + x1 * curve_width
            local screen_y1 = curve_start_y - y1 * curve_height
            local screen_x2 = curve_start_x + x2 * curve_width
            local screen_y2 = curve_start_y - y2 * curve_height

            imgui.DrawList_AddLine(draw_list, screen_x1, screen_y1, screen_x2, screen_y2, col_curve, 2)
        end
    end

    -- If animated, defer drawing to render on top; otherwise draw immediately
    if animationStates[id] > 0.01 and globals.deferredWidgetDraws then
        table.insert(globals.deferredWidgetDraws, drawFadeWidget)
    else
        drawFadeWidget()
    end

    -- Shape selection popup
    local shapeNames = {"Linear", "Fast Start", "Fast End", "Fast S/E", "Slow S/E", "Bezier", "S-Curve"}

    if imgui.BeginPopup(ctx, "FadeShapePopup" .. id) then
        imgui.Text(ctx, "Select Fade Shape:")
        imgui.Separator(ctx)

        for i = 0, 6 do
            local name = shapeNames[i + 1]
            if imgui.Selectable(ctx, name, shape == i) then
                newShape = i
                shapeChanged = true
                imgui.CloseCurrentPopup(ctx)
            end
        end

        imgui.EndPopup(ctx)
    end

    return shapeChanged, newShape, curveChanged, newCurve
end

return FadeWidget
