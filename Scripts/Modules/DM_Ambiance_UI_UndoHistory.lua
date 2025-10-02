--[[
@version 1.0
@noindex
@description Undo History UI window (similar to REAPER's Undo History)
--]]

local UI_UndoHistory = {}
local globals = {}

function UI_UndoHistory.initModule(g)
    if not g then
        error("UI_UndoHistory.initModule: globals parameter is required")
    end
    globals = g
end

-- Show the Undo History window
function UI_UndoHistory.showWindow()
    local imgui = globals.imgui
    local ctx = globals.ctx

    -- Window flags
    local windowFlags = imgui.WindowFlags_None

    -- Begin window
    imgui.SetNextWindowSize(ctx, 600, 400, imgui.Cond_FirstUseEver)
    local visible, open = imgui.Begin(ctx, "Undo History", true, windowFlags)

    if visible then
        local historyStack = globals.History.getHistoryStack()
        local currentIndex = globals.History.getCurrentIndex()
        local memoryUsage = globals.History.getMemoryUsage()

        -- Header with memory usage
        imgui.Text(ctx, string.format("Undo History Memory Usage: %.3f MB", memoryUsage / (1024 * 1024)))
        imgui.Separator(ctx)

        -- Table with columns: Description and Time
        if imgui.BeginTable(ctx, "UndoHistoryTable", 2, imgui.TableFlags_Borders | imgui.TableFlags_RowBg | imgui.TableFlags_ScrollY) then
            -- Setup columns
            imgui.TableSetupColumn(ctx, "Description", imgui.TableColumnFlags_WidthStretch)
            imgui.TableSetupColumn(ctx, "Time", imgui.TableColumnFlags_WidthFixed, 150)
            imgui.TableSetupScrollFreeze(ctx, 0, 1) -- Freeze header row
            imgui.TableHeadersRow(ctx)

            -- Display history entries
            for i = #historyStack, 1, -1 do
                local entry = historyStack[i]
                imgui.TableNextRow(ctx)

                -- Highlight current position
                local isCurrent = (i == currentIndex)
                if isCurrent then
                    imgui.TableSetBgColor(ctx, imgui.TableBgTarget_RowBg0, 0x3366FFFF)
                end

                -- Description column (make it selectable for double-click detection)
                imgui.TableSetColumnIndex(ctx, 0)
                local displayText = entry.description or "Unnamed action"
                if i == currentIndex then
                    displayText = "● " .. displayText  -- Marker for current state
                end

                -- Use Selectable to detect clicks
                local clicked = imgui.Selectable(ctx, displayText .. "##row" .. i, isCurrent, imgui.SelectableFlags_SpanAllColumns)

                -- Detect double-click to jump to this state
                if imgui.IsItemHovered(ctx) and imgui.IsMouseDoubleClicked(ctx, 0) then
                    globals.History.jumpToState(i)
                end

                -- Show tooltip on hover
                if imgui.IsItemHovered(ctx) and not isCurrent then
                    imgui.SetTooltip(ctx, "Double-click to jump to this state")
                end

                -- Time column
                imgui.TableSetColumnIndex(ctx, 1)
                -- Convert to integer for os.date (os.date expects integer timestamp)
                local timeStr = os.date("%d/%m/%Y %H:%M:%S", math.floor(entry.timestamp))
                imgui.Text(ctx, timeStr)
            end

            imgui.EndTable(ctx)
        end

        imgui.Separator(ctx)

        -- Controls
        if imgui.Button(ctx, "Clear History") then
            globals.History.clear()
        end
        imgui.SameLine(ctx)
        imgui.Text(ctx, string.format("Current: %d / %d", currentIndex, #historyStack))

        imgui.End(ctx)
    end

    return open
end

return UI_UndoHistory
