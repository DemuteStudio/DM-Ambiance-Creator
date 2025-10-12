--[[
@version 1.3
@noindex
--]]

local MainWindow = {}
local globals = {}

-- Initialize the module with global variables
function MainWindow.initModule(g)
    globals = g
end

-- Helper function references (these will be provided by other modules)
local drawLeftPanel
local drawRightPanel
local getLeftPanelWidth
local handlePopups
local isContainerSelected
local toggleContainerSelection
local clearContainerSelections
local selectContainerRange

-- Set helper function references from other modules
function MainWindow.setHelperFunctions(helpers)
    drawLeftPanel = helpers.drawLeftPanel
    drawRightPanel = helpers.drawRightPanel
    getLeftPanelWidth = helpers.getLeftPanelWidth
    handlePopups = helpers.handlePopups
    isContainerSelected = helpers.isContainerSelected
    toggleContainerSelection = helpers.toggleContainerSelection
    clearContainerSelections = helpers.clearContainerSelections
    selectContainerRange = helpers.selectContainerRange
end

-- Handle Delete key press for groups and containers
local function handleDeleteKey()
    -- Capture state before deletion
    globals.History.captureState("Delete items")

    -- Check if we're in multi-selection mode
    if globals.inMultiSelectMode and next(globals.selectedContainers) then
        -- Build list of containers to delete (sorted in reverse to maintain indices)
        local toDelete = {}
        for key, _ in pairs(globals.selectedContainers) do
            local groupIdx, containerIdx = key:match("(%d+)_(%d+)")
            if groupIdx and containerIdx then
                table.insert(toDelete, {
                    groupIndex = tonumber(groupIdx),
                    containerIndex = tonumber(containerIdx)
                })
            end
        end

        -- Sort in reverse order (highest indices first)
        table.sort(toDelete, function(a, b)
            if a.groupIndex == b.groupIndex then
                return a.containerIndex > b.containerIndex
            end
            return a.groupIndex > b.groupIndex
        end)

        -- Delete containers
        for _, item in ipairs(toDelete) do
            local group = globals.groups[item.groupIndex]
            if group and group.containers[item.containerIndex] then
                table.remove(group.containers, item.containerIndex)
            end
        end

        -- Clear selections
        globals.selectedContainers = {}
        globals.inMultiSelectMode = false
        globals.selectedContainerIndex = nil

    -- Check if a single container is selected
    elseif globals.selectedGroupIndex and globals.selectedContainerIndex then
        local group = globals.groups[globals.selectedGroupIndex]
        if group and group.containers[globals.selectedContainerIndex] then
            -- Store current indices
            local containerIdx = globals.selectedContainerIndex

            -- Remove the container
            table.remove(group.containers, containerIdx)

            -- Clear selection
            globals.selectedContainerIndex = nil

            -- Clear from multi-selection if present
            local selectionKey = globals.selectedGroupIndex .. "_" .. containerIdx
            if globals.selectedContainers[selectionKey] then
                globals.selectedContainers[selectionKey] = nil
            end

            -- Update selection indices for containers after the deleted one
            for k = containerIdx + 1, #group.containers + 1 do
                local oldKey = globals.selectedGroupIndex .. "_" .. k
                local newKey = globals.selectedGroupIndex .. "_" .. (k-1)
                if globals.selectedContainers[oldKey] then
                    globals.selectedContainers[newKey] = true
                    globals.selectedContainers[oldKey] = nil
                end
            end
        end
    -- Check if only a group is selected (no container selected)
    elseif globals.selectedGroupIndex and not globals.selectedContainerIndex then
        local groupIdx = globals.selectedGroupIndex

        -- Remove the group and all its containers
        table.remove(globals.groups, groupIdx)

        -- Clear selection
        globals.selectedGroupIndex = nil

        -- Clear any selected containers from this group
        for key in pairs(globals.selectedContainers) do
            local t, c = key:match("(%d+)_(%d+)")
            if tonumber(t) == groupIdx then
                globals.selectedContainers[key] = nil
            end
            -- Update indices for groups after the deleted one
            if tonumber(t) > groupIdx then
                local newKey = (tonumber(t) - 1) .. "_" .. c
                globals.selectedContainers[newKey] = globals.selectedContainers[key]
                globals.selectedContainers[key] = nil
            end
        end

        -- Update selected group index if needed
        if globals.selectedGroupIndex and globals.selectedGroupIndex > groupIdx then
            globals.selectedGroupIndex = globals.selectedGroupIndex - 1
        end
    end
end

-- Handle copy operation (Ctrl+C)
local function handleCopy()
    if globals.inMultiSelectMode and next(globals.selectedContainers) then
        -- Multi-selection copy: copy all selected containers
        local containers = {}
        for key in pairs(globals.selectedContainers) do
            local groupIdx, containerIdx = key:match("(%d+)_(%d+)")
            if groupIdx and containerIdx then
                groupIdx = tonumber(groupIdx)
                containerIdx = tonumber(containerIdx)
                if globals.groups[groupIdx] and globals.groups[groupIdx].containers[containerIdx] then
                    table.insert(containers, globals.Utils.deepCopy(globals.groups[groupIdx].containers[containerIdx]))
                end
            end
        end

        if #containers > 0 then
            globals.clipboard = {
                type = "containers",
                data = containers,
                source = nil
            }
        end
    elseif globals.selectedContainerIndex then
        -- Single container copy
        local container = globals.groups[globals.selectedGroupIndex].containers[globals.selectedContainerIndex]
        globals.clipboard = {
            type = "container",
            data = globals.Utils.deepCopy(container),
            source = {groupIndex = globals.selectedGroupIndex, containerIndex = globals.selectedContainerIndex}
        }
    elseif globals.selectedGroupIndex then
        -- Group copy
        local group = globals.groups[globals.selectedGroupIndex]
        globals.clipboard = {
            type = "group",
            data = globals.Utils.deepCopy(group),
            source = {groupIndex = globals.selectedGroupIndex}
        }
    end
end

-- Handle paste operation (Ctrl+V)
local function handlePaste()
    if not globals.clipboard.data then
        return
    end

    globals.History.captureState("Paste " .. globals.clipboard.type)

    if globals.clipboard.type == "group" then
        -- Paste group
        local groupCopy = globals.Utils.deepCopy(globals.clipboard.data)
        groupCopy.name = groupCopy.name .. " (Copy)"

        -- Generate new UUIDs for all containers in the group
        for _, container in ipairs(groupCopy.containers) do
            container.id = globals.Utils.generateUUID()
            container.channelTrackGUIDs = {}
        end

        -- Insert after currently selected group or at end
        local insertIndex = globals.selectedGroupIndex and (globals.selectedGroupIndex + 1) or (#globals.groups + 1)
        table.insert(globals.groups, insertIndex, groupCopy)
        globals.selectedGroupIndex = insertIndex
        globals.selectedContainerIndex = nil
        clearContainerSelections()

    elseif globals.clipboard.type == "container" then
        -- Paste single container into selected group
        if not globals.selectedGroupIndex then
            return
        end

        local containerCopy = globals.Utils.deepCopy(globals.clipboard.data)
        containerCopy.id = globals.Utils.generateUUID()
        containerCopy.name = containerCopy.name .. " (Copy)"
        containerCopy.channelTrackGUIDs = {}

        -- Insert after currently selected container or at end
        local insertIndex = globals.selectedContainerIndex and (globals.selectedContainerIndex + 1) or (#globals.groups[globals.selectedGroupIndex].containers + 1)
        table.insert(globals.groups[globals.selectedGroupIndex].containers, insertIndex, containerCopy)
        globals.selectedContainerIndex = insertIndex
        clearContainerSelections()

    elseif globals.clipboard.type == "containers" then
        -- Paste multiple containers into selected group
        if not globals.selectedGroupIndex then
            return
        end

        local insertIndex = globals.selectedContainerIndex and (globals.selectedContainerIndex + 1) or (#globals.groups[globals.selectedGroupIndex].containers + 1)

        for i, container in ipairs(globals.clipboard.data) do
            local containerCopy = globals.Utils.deepCopy(container)
            containerCopy.id = globals.Utils.generateUUID()
            containerCopy.name = containerCopy.name .. " (Copy)"
            containerCopy.channelTrackGUIDs = {}
            table.insert(globals.groups[globals.selectedGroupIndex].containers, insertIndex + i - 1, containerCopy)
        end

        clearContainerSelections()
    end
end

-- Handle duplicate operation (Ctrl+D)
local function handleDuplicate()
    handleCopy()
    handlePaste()
end

-- Handle keyboard shortcuts (Undo/Redo/Delete/Copy/Paste)
local function handleKeyboardShortcuts()
    local ctrlPressed = (globals.imgui.GetKeyMods(globals.ctx) & globals.imgui.Mod_Ctrl ~= 0)
    local shiftPressed = (globals.imgui.GetKeyMods(globals.ctx) & globals.imgui.Mod_Shift ~= 0)

    -- Ctrl+Z: Undo (works everywhere)
    if ctrlPressed and not shiftPressed and globals.imgui.IsKeyPressed(globals.ctx, globals.imgui.Key_Z) then
        globals.History.undo()
    end

    -- Ctrl+Y or Ctrl+Shift+Z: Redo (works everywhere)
    if (ctrlPressed and globals.imgui.IsKeyPressed(globals.ctx, globals.imgui.Key_Y)) or
       (ctrlPressed and shiftPressed and globals.imgui.IsKeyPressed(globals.ctx, globals.imgui.Key_Z)) then
        globals.History.redo()
    end

    -- Ctrl+C: Copy
    if ctrlPressed and globals.imgui.IsKeyPressed(globals.ctx, globals.imgui.Key_C) then
        handleCopy()
    end

    -- Ctrl+V: Paste
    if ctrlPressed and globals.imgui.IsKeyPressed(globals.ctx, globals.imgui.Key_V) then
        handlePaste()
    end

    -- Ctrl+D: Duplicate
    if ctrlPressed and globals.imgui.IsKeyPressed(globals.ctx, globals.imgui.Key_D) then
        handleDuplicate()
    end

    -- Delete key: Delete selected items
    if globals.imgui.IsKeyPressed(globals.ctx, globals.imgui.Key_Delete) then
        handleDeleteKey()
    end
end

-- Render the top section (preset controls and generation buttons)
local function renderTopSection()
    local UI_Preset = globals.UI_Preset or require("DM_Ambiance_UI_Preset")
    local UI_Generation = globals.UI_Generation or require("DM_Ambiance_UI_Generation")
    local Utils = globals.Utils or require("DM_Ambiance_Utils")

    -- Top section: preset controls and generation button
    UI_Preset.drawPresetControls()

    -- Settings button positioned at the far right
    local settingsButtonWidth = 14  -- Icon size
    local windowWidth = globals.imgui.GetWindowWidth(globals.ctx)
    local cursorX = globals.imgui.GetCursorPosX(globals.ctx)
    local spacing = globals.imgui.GetStyleVar(globals.ctx, globals.imgui.StyleVar_ItemSpacing)
    globals.imgui.SameLine(globals.ctx)
    globals.imgui.SetCursorPosX(globals.ctx, windowWidth - settingsButtonWidth - spacing - 10)
    if globals.Icons.createSettingsButton(globals.ctx, "main", "Open settings") then
        globals.showSettingsWindow = true
    end

    -- Generation buttons or time selection info
    if globals.Utils.checkTimeSelection() then
        UI_Generation.drawMainGenerationButton()
        globals.imgui.SameLine(globals.ctx)
        UI_Generation.drawKeepExistingTracksButton()
    else
        UI_Generation.drawTimeSelectionInfo()
    end

    globals.imgui.Separator(globals.ctx)
end

-- Render the resizable splitter between panels
local function renderPanelSplitter(windowWidth)
    local Constants = require("DM_Ambiance_Constants")

    -- Splitter between panels
    globals.imgui.SameLine(globals.ctx)

    -- Style the splitter to look like a separator
    local separatorColor = globals.imgui.GetStyleColor(globals.ctx, globals.imgui.Col_Separator)
    globals.imgui.PushStyleColor(globals.ctx, globals.imgui.Col_Button, separatorColor)
    globals.imgui.PushStyleColor(globals.ctx, globals.imgui.Col_ButtonHovered, separatorColor)
    globals.imgui.PushStyleColor(globals.ctx, globals.imgui.Col_ButtonActive, separatorColor)

    globals.imgui.Button(globals.ctx, "##vsplitter", 2, -1)

    globals.imgui.PopStyleColor(globals.ctx, 3)

    -- Check if splitter is being dragged
    if globals.imgui.IsItemActive(globals.ctx) then
        local deltaX, deltaY = globals.imgui.GetMouseDragDelta(globals.ctx, 0)
        if deltaX ~= 0 then
            globals.leftPanelWidth = globals.leftPanelWidth + deltaX
            globals.imgui.ResetMouseDragDelta(globals.ctx, 0)

            -- Clamp width
            local minWidth = Constants.UI.MIN_LEFT_PANEL_WIDTH
            local maxWidth = windowWidth - 200
            globals.leftPanelWidth = math.max(minWidth, math.min(globals.leftPanelWidth, maxWidth))
        end
    end

    -- Save when drag is released
    if globals.imgui.IsItemDeactivated(globals.ctx) and globals.leftPanelWidth then
        globals.Settings.setSetting("leftPanelWidth", globals.leftPanelWidth)
        globals.Settings.saveSettings()  -- Write to file
    end

    -- Change cursor on hover
    if globals.imgui.IsItemHovered(globals.ctx) then
        globals.imgui.SetMouseCursor(globals.ctx, globals.imgui.MouseCursor_ResizeEW)
    end
end

-- Render the two-panel layout (left and right panels)
local function renderTwoPanelLayout()
    local Constants = require("DM_Ambiance_Constants")
    local windowWidth = globals.imgui.GetWindowWidth(globals.ctx)

    -- Get the left panel width
    local leftPanelWidth = getLeftPanelWidth(windowWidth)

    -- Left panel: groups and containers
    local leftVisible = globals.imgui.BeginChild(globals.ctx, "LeftPanel", leftPanelWidth, 0, imgui.WindowFlags_None)
    if leftVisible then
        drawLeftPanel(leftPanelWidth)
    end
    -- CRITICAL: Always call EndChild after BeginChild, regardless of visibility
    globals.imgui.EndChild(globals.ctx)

    -- Splitter between panels
    renderPanelSplitter(windowWidth)

    -- Right panel: container or group details
    globals.imgui.SameLine(globals.ctx)
    local rightMargin = 15  -- Right margin for balanced UI
    local rightPanelWidth = windowWidth - leftPanelWidth - Constants.UI.SPLITTER_WIDTH - 20 - rightMargin
    local rightVisible = globals.imgui.BeginChild(globals.ctx, "RightPanel", rightPanelWidth, 0, imgui.WindowFlags_None)
    if rightVisible then
        drawRightPanel(rightPanelWidth)
    end
    -- CRITICAL: Always call EndChild after BeginChild, regardless of visibility
    globals.imgui.EndChild(globals.ctx)
end

-- Render external windows and popups (outside main window)
local function renderExternalWindows()
    local UI = globals.UI or require("DM_Ambiance_UI")
    local UI_Container = globals.UI_Container or require("DM_Ambiance_UI_Container")
    local Utils = globals.Utils or require("DM_Ambiance_Utils")

    -- Render Euclidean pattern preset browser modal (must be outside main window)
    UI.drawEuclideanPatternPresetBrowser()

    -- Handle settings window with the same pattern
    if globals.showSettingsWindow then
        globals.showSettingsWindow = globals.Settings.showSettingsWindow(true)
    end

    -- Show the media directory warning popup if needed
    if globals.showMediaDirWarning then
        Utils.showDirectoryWarningPopup()
    end

    -- Handle routing matrix popup
    if globals.routingPopupItemIndex then
        UI_Container.showRoutingMatrixPopup(globals.routingPopupGroupIndex, globals.routingPopupContainerIndex, "routing")
    end

    -- Handle other popups
    handlePopups()
end

-- Process post-frame operations
local function processPostFrameOperations()
    -- Process any queued fade updates after ImGui frame is complete
    globals.Utils.processQueuedFadeUpdates()

    -- Process any queued randomization updates after ImGui frame is complete
    globals.Utils.processQueuedRandomizationUpdates()
end

-- Main window rendering function
function MainWindow.ShowMainWindow(open)
    local windowFlags = imgui.WindowFlags_None

    -- Lock window movement during waveform manipulations or when about to interact
    if globals.Waveform and (globals.Waveform.isWaveformBeingManipulated() or
                            globals.Waveform.isMouseAboutToInteractWithWaveform()) then
        windowFlags = windowFlags | imgui.WindowFlags_NoMove
    end

    local visible, open = globals.imgui.Begin(globals.ctx, 'Ambiance Creator', open, windowFlags)

    -- CRITICAL: Only call End() if Begin() returned true (visible)
    if visible then
        -- Store main window position and size for modal centering
        globals.mainWindowPos = {imgui.GetWindowPos(globals.ctx)}
        globals.mainWindowSize = {imgui.GetWindowSize(globals.ctx)}

        -- Initialize deferred widget drawing list for animated widgets
        if not globals.deferredWidgetDraws then
            globals.deferredWidgetDraws = {}
        end
        globals.deferredWidgetDraws = {}  -- Clear previous frame

        -- Handle keyboard shortcuts
        handleKeyboardShortcuts()

        -- Render top section (preset controls, generation buttons)
        renderTopSection()

        -- Render two-panel layout (left and right panels)
        renderTwoPanelLayout()

        -- Execute deferred widget draws (animated widgets drawn last = on top)
        if globals.deferredWidgetDraws then
            for _, drawFunc in ipairs(globals.deferredWidgetDraws) do
                drawFunc()
            end
        end

        -- CRITICAL: Only call End() if Begin() returned true
        globals.imgui.End(globals.ctx)
    end

    -- Render external windows and popups (outside main window)
    renderExternalWindows()

    -- Process post-frame operations
    processPostFrameOperations()

    return open
end

return MainWindow
