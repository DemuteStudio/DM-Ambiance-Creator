--[[
@version 1.3
@noindex
--]]

local LeftPanel = {}
local globals = {}
local Constants = require("DM_Ambiance_Constants")

-- Initialize the module with global variables from the main script
function LeftPanel.initModule(g)
    if not g then
        error("LeftPanel.initModule: globals parameter is required")
    end
    globals = g
end

-- Check if a container is selected
-- @param groupIndex number: Group index
-- @param containerIndex number: Container index
-- @return boolean: True if container is selected
local function isContainerSelected(groupIndex, containerIndex)
    return globals.selectedContainers[groupIndex .. "_" .. containerIndex] == true
end

-- Clear all container selections and reset multi-select mode
local function clearContainerSelections()
    globals.selectedContainers = {}
    globals.inMultiSelectMode = false
    -- Also clear the shift anchor when clearing selections
    globals.shiftAnchorGroupIndex = nil
    globals.shiftAnchorContainerIndex = nil
end

-- Toggle the selection state of a container
-- @param groupIndex number: Group index
-- @param containerIndex number: Container index
local function toggleContainerSelection(groupIndex, containerIndex)
    local key = groupIndex .. "_" .. containerIndex
    local isShiftPressed = (globals.imgui.GetKeyMods(globals.ctx) & globals.imgui.Mod_Shift ~= 0)

    -- If Shift is pressed and an anchor exists, select a range
    if isShiftPressed and globals.shiftAnchorGroupIndex and globals.shiftAnchorContainerIndex then
        selectContainerRange(globals.shiftAnchorGroupIndex, globals.shiftAnchorContainerIndex, groupIndex, containerIndex)
    else
        -- Without Shift, clear previous selections unless Ctrl is pressed
        if not (globals.imgui.GetKeyMods(globals.ctx) & globals.imgui.Mod_Ctrl ~= 0) then
            clearContainerSelections()
        end

        -- Toggle the current container selection
        if globals.selectedContainers[key] then
            globals.selectedContainers[key] = nil
        else
            globals.selectedContainers[key] = true
        end

        -- Update anchor for future Shift selections
        globals.shiftAnchorGroupIndex = groupIndex
        globals.shiftAnchorContainerIndex = containerIndex
    end

    -- Update main selection and multi-select mode
    globals.selectedGroupIndex = groupIndex
    globals.selectedContainerIndex = containerIndex
    globals.inMultiSelectMode = globals.UI_Groups.getSelectedContainersCount() > 1
end

-- Select a range of containers between two points (supports cross-group selection)
-- @param startGroupIndex number: Starting group index
-- @param startContainerIndex number: Starting container index
-- @param endGroupIndex number: Ending group index
-- @param endContainerIndex number: Ending container index
local function selectContainerRange(startGroupIndex, startContainerIndex, endGroupIndex, endContainerIndex)
    -- Clear selection if not in multi-select mode
    if not (globals.imgui.GetKeyMods(globals.ctx) & globals.imgui.Mod_Ctrl ~= 0) then
        clearContainerSelections()
    end

    -- Range selection within the same group
    if startGroupIndex == endGroupIndex then
        local group = globals.groups[startGroupIndex]
        local startIdx = math.min(startContainerIndex, endContainerIndex)
        local endIdx = math.max(startContainerIndex, endContainerIndex)
        for i = startIdx, endIdx do
            if i <= #group.containers then
                globals.selectedContainers[startGroupIndex .. "_" .. i] = true
            end
        end
        return
    end

    -- Range selection across groups
    local startGroup = math.min(startGroupIndex, endGroupIndex)
    local endGroup = math.max(startGroupIndex, endGroupIndex)
    local firstContainerIdx, lastContainerIdx
    if startGroupIndex < endGroupIndex then
        firstContainerIdx, lastContainerIdx = startContainerIndex, endContainerIndex
    else
        firstContainerIdx, lastContainerIdx = endContainerIndex, startContainerIndex
    end

    for t = startGroup, endGroup do
        if globals.groups[t] then
            if t == startGroup then
                for c = firstContainerIdx, #globals.groups[t].containers do
                    globals.selectedContainers[t .. "_" .. c] = true
                end
            elseif t == endGroup then
                for c = 1, lastContainerIdx do
                    globals.selectedContainers[t .. "_" .. c] = true
                end
            else
                for c = 1, #globals.groups[t].containers do
                    globals.selectedContainers[t .. "_" .. c] = true
                end
            end
        end
    end

    globals.inMultiSelectMode = globals.UI_Groups.getSelectedContainersCount() > 1
end

-- Draw the left panel containing the list of groups and containers
-- @param width number: Panel width
function LeftPanel.render(width)
    if not width or width <= 0 then
        error("LeftPanel.render: valid width parameter is required")
    end

    local availHeight = globals.imgui.GetWindowHeight(globals.ctx)
    if availHeight < 100 then -- Minimum height check
        globals.imgui.TextColored(globals.ctx, 0xFF0000FF, "Window too small")
        return
    end

    -- Delegate to UI_Groups for the actual group/container rendering
    globals.UI_Groups.drawGroupsPanel(
        width,
        isContainerSelected,
        toggleContainerSelection,
        clearContainerSelections,
        selectContainerRange
    )
end

-- Get the left panel width (with resizing support)
-- @param windowWidth number: Current window width
-- @return number: Left panel width
function LeftPanel.getWidth(windowWidth)
    -- Load saved width from settings or use default
    if globals.leftPanelWidth == nil then
        local savedWidth = globals.Settings.getSetting("leftPanelWidth")
        if savedWidth then
            globals.leftPanelWidth = savedWidth
        else
            globals.leftPanelWidth = windowWidth * Constants.UI.LEFT_PANEL_DEFAULT_WIDTH
        end
    end

    -- Ensure minimum width and adjust for window size
    local minWidth = Constants.UI.MIN_LEFT_PANEL_WIDTH
    local maxWidth = windowWidth - 200  -- Leave at least 200px for right panel
    globals.leftPanelWidth = math.max(minWidth, math.min(globals.leftPanelWidth, maxWidth))

    return globals.leftPanelWidth
end

-- Export helper functions for testing/debugging (optional)
LeftPanel._private = {
    isContainerSelected = isContainerSelected,
    clearContainerSelections = clearContainerSelections,
    toggleContainerSelection = toggleContainerSelection,
    selectContainerRange = selectContainerRange
}

return LeftPanel
