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
-- Handles four modes:
-- 1. Multi-selection mode: Show multi-selection panel
-- 2. Container selected: Show container settings
-- 3. Group selected (no container): Show group settings
-- 4. Folder selected: Show folder settings
-- 5. Nothing selected: Show help text
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
    -- Use path-based selection system only
    if not globals.selectedPath then
        -- Nothing selected
        imgui.TextColored(
            globals.ctx,
            0xFFAA00FF,
            "Select a group or container to view and edit its settings."
        )
        return
    end

    if globals.selectedContainerIndex and globals.selectedContainerIndex > 0 then
        -- Container is selected: display container settings
        globals.UI_Container.displayContainerSettings(
            globals.selectedPath,
            globals.selectedContainerIndex,
            width
        )
    elseif globals.selectedType == "folder" then
        -- Folder is selected: display folder settings
        if globals.UI_Folder then
            local folder = globals.Structures.getItemFromPath(globals.selectedPath)
            if folder then
                globals.UI_Folder.drawFolderPanel(folder)
            end
        end
    elseif globals.selectedType == "group" then
        -- Group is selected: display group settings
        globals.UI_Group.displayGroupSettings(
            globals.selectedPath,
            width
        )
    else
        -- Shouldn't happen, but fallback to help text
        imgui.TextColored(
            globals.ctx,
            0xFFAA00FF,
            "Select a group or container to view and edit its settings."
        )
    end
end

return RightPanel
