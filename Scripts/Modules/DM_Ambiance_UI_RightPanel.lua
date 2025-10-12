--[[
@version 1.5
@noindex
--]]

local RightPanel = {}
local globals = {}
local imgui = nil  -- Will be initialized from globals

-- Initialize the module with global variables from the main script
function RightPanel.initModule(g)
    if not g then
        error("RightPanel.initModule: globals parameter is required")
    end
    globals = g
    imgui = globals.imgui  -- Get imgui reference from globals
end

-- Render the right panel
-- Handles three modes:
-- 1. Multi-selection mode: Show multi-selection panel
-- 2. Container selected: Show container settings
-- 3. Group selected (no container): Show group settings
-- 4. Nothing selected: Show help text
function RightPanel.render(width)
    -- Early exit if no containers are selected (empty table check)
    if globals.selectedContainers == {} then
        return
    end

    -- MULTI-SELECTION MODE
    if globals.inMultiSelectMode then
        globals.UI_MultiSelection.drawMultiSelectionPanel(width)
        return
    end

    -- SINGLE SELECTION MODE
    if globals.selectedGroupIndex and globals.selectedContainerIndex then
        -- Container is selected: display container settings
        globals.UI_Container.displayContainerSettings(
            globals.selectedGroupIndex,
            globals.selectedContainerIndex,
            width
        )
    elseif globals.selectedGroupIndex then
        -- Only group is selected: display group settings
        globals.UI_Group.displayGroupSettings(
            globals.selectedGroupIndex,
            width
        )
    else
        -- Nothing is selected: show help text
        imgui.TextColored(
            globals.ctx,
            0xFFAA00FF,
            "Select a group or container to view and edit its settings."
        )
    end
end

return RightPanel
