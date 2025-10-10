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

--- Initialize module with globals table
function FadeWidget.initModule(g)
    globals = g
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
        -- S-curve with adjustable steepness
        local steepness = 1 + math.abs(curve) * 3
        return 1 / (1 + math.exp(-steepness * (x - 0.5)))
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

    -- Apply UI scaling
    local size = globals.UI and globals.UI.scaleSize(baseSize) or baseSize

    local shapeChanged = false
    local curveChanged = false
    local newShape = shape
    local newCurve = curve

    -- Calculate vertical centering offset to align with other widgets
    local frame_padding_y = imgui.GetStyleVar(ctx, imgui.StyleVar_FramePadding)
    local text_height = imgui.GetTextLineHeight(ctx)
    local widget_height = text_height + (frame_padding_y * 2)
    local vertical_offset = (widget_height - size) * 0.5

    -- Get draw list and cursor position
    local draw_list = imgui.GetWindowDrawList(ctx)
    local cursor_x, cursor_y = imgui.GetCursorScreenPos(ctx)

    -- Apply vertical offset for drawing (but keep button at original position for ImGui layout)
    local draw_y = cursor_y + vertical_offset

    -- Create invisible button for interaction
    imgui.InvisibleButton(ctx, id, size, size)
    local is_active = imgui.IsItemActive(ctx)
    local is_hovered = imgui.IsItemHovered(ctx)

    -- Handle left-click drag to adjust curve (only for shapes that support curve)
    local supportsCurve = (shape == Constants.FADE_SHAPES.LINEAR or
                          shape == Constants.FADE_SHAPES.BEZIER or
                          shape == Constants.FADE_SHAPES.S_CURVE)

    if supportsCurve and is_active then
        local mouse_delta_x, mouse_delta_y = imgui.GetMouseDelta(ctx)
        -- Vertical drag adjusts curve (drag down = positive curve, drag up = negative curve)
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

    -- Draw background (square) - use draw_y for vertical positioning
    imgui.DrawList_AddRectFilled(draw_list, cursor_x, draw_y, cursor_x + size, draw_y + size, col_bg, 2)
    imgui.DrawList_AddRect(draw_list, cursor_x, draw_y, cursor_x + size, draw_y + size, col_border, 2, nil, 1)

    -- Draw fade curve
    local padding = 4
    local curve_start_x = cursor_x + padding
    local curve_end_x = cursor_x + size - padding
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

    -- Draw curve value if applicable (centered in widget) - use draw_y
    if supportsCurve then
        local curveText = string.format("%.1f", curve)
        local curve_text_size_x, curve_text_size_y = imgui.CalcTextSize(ctx, curveText)
        local text_x = cursor_x + (size - curve_text_size_x) * 0.5
        local text_y = draw_y + (size - curve_text_size_y) * 0.5
        imgui.DrawList_AddText(draw_list, text_x, text_y, col_text, curveText)
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
