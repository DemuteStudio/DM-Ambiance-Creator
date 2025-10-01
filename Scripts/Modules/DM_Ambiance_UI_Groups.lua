--[[
@version 1.3
@noindex
--]]

local UI_Groups = {}
local globals = {}
local Constants = require("DM_Ambiance_Constants")

-- Initialize the module with global variables from the main script
function UI_Groups.initModule(g)
    if not g then
        error("UI_Groups.initModule: globals parameter is required")
    end
    globals = g
end

-- Display group preset controls (load/save) for a specific group
-- @param i number: Group index
function UI_Groups.drawGroupPresetControls(i)
    if not i or i < 1 then
        error("UI_Groups.drawGroupPresetControls: valid group index is required")
    end
    local groupId = "group" .. i

    -- Initialize selected preset index for this group if not already set
    if not globals.selectedGroupPresetIndex[i] then
        globals.selectedGroupPresetIndex[i] = -1
    end

    -- Get the list of available group presets
    local groupPresetList = globals.Presets.listPresets("Groups")

    -- Prepare items for the preset dropdown (ImGui Combo expects a null-separated string)
    local groupPresetItems = ""
    for _, name in ipairs(groupPresetList) do
        groupPresetItems = groupPresetItems .. name .. "\0"
    end

    -- Group preset dropdown selector
    imgui.PushItemWidth(globals.ctx, Constants.UI.PRESET_SELECTOR_WIDTH)
    local rv, newSelectedGroupIndex = globals.UndoWrappers.Combo(
        globals.ctx,
        "##GroupPresetSelector" .. groupId,
        globals.selectedGroupPresetIndex[i],
        groupPresetItems
    )
    if rv then
        globals.selectedGroupPresetIndex[i] = newSelectedGroupIndex
    end

    -- Load preset button
    imgui.SameLine(globals.ctx)
    if globals.Icons.createDownloadButton(globals.ctx, "loadGroup" .. groupId, "Load group preset")
        and globals.selectedGroupPresetIndex[i] >= 0
        and globals.selectedGroupPresetIndex[i] < #groupPresetList then
        local presetName = groupPresetList[globals.selectedGroupPresetIndex[i] + 1]
        globals.Presets.loadGroupPreset(presetName, i)
    end

    -- Save preset button
    imgui.SameLine(globals.ctx)
    if globals.Icons.createUploadButton(globals.ctx, "saveGroup" .. groupId, "Save group preset") then
        -- Check if a media directory is configured before allowing save
        if not globals.Utils.isMediaDirectoryConfigured() then
            -- Set flag to show the warning popup
            globals.showMediaDirWarning = true
        else
            -- Continue with the normal save popup
            globals.newGroupPresetName = globals.groups[i].name
            globals.currentSaveGroupIndex = i
            globals.Utils.safeOpenPopup("Save Group Preset##" .. groupId)
        end
    end

    -- Popup dialog for saving the group as a preset
    if imgui.BeginPopupModal(globals.ctx, "Save Group Preset##" .. groupId, nil, imgui.WindowFlags_AlwaysAutoResize) then
        imgui.Text(globals.ctx, "Group preset name:")
        local rv, value = imgui.InputText(globals.ctx, "##GroupPresetName" .. groupId, globals.newGroupPresetName)
        if rv then globals.newGroupPresetName = value end
        if imgui.Button(globals.ctx, "Save", Constants.UI.BUTTON_WIDTH_STANDARD, 0) and globals.newGroupPresetName ~= "" then
            if globals.Presets.saveGroupPreset(globals.newGroupPresetName, globals.currentSaveGroupIndex) then
                globals.Utils.safeClosePopup("Save Group Preset##" .. groupId)
            end
        end
        imgui.SameLine(globals.ctx)
        if imgui.Button(globals.ctx, "Cancel", Constants.UI.BUTTON_WIDTH_STANDARD, 0) then
            globals.Utils.safeClosePopup("Save Group Preset##" .. groupId)
        end
        imgui.EndPopup(globals.ctx)
    end
end

-- Helper function to draw a list item (group or container) with buttons aligned to the right
-- Uses Selectable for full-width clickable area, manual arrow for expansion
-- @param params table: Configuration table with the following keys:
--   - id: string - Unique ID for the item
--   - text: string - Display text
--   - isSelected: boolean - Whether the item is selected
--   - hasArrow: boolean - Whether to show expand/collapse arrow
--   - isOpen: boolean - Whether the item is expanded (only used if hasArrow = true)
--   - availableWidth: number - Total available width for the row
--   - dragSource: table - Drag source config {type, data, preview, onStart} (optional)
--   - dropTarget: table - Drop target config {accept[], onDrop} (optional)
--   - onSelect: function - Callback when item is clicked
--   - onToggle: function - Callback when arrow is clicked (only if hasArrow = true)
--   - buttons: table - Array of button configs {icon, id, tooltip, onClick}
-- @return boolean - Whether the item was clicked
local function drawListItemWithButtons(params)
    local imgui = globals.imgui
    local ctx = globals.ctx

    -- Calculate button area width
    local buttonWidth = 16
    local buttonSpacing = 5
    local numButtons = #params.buttons
    local totalButtonWidth = numButtons * (buttonWidth + buttonSpacing)
    local scrollbarMargin = 30

    -- Full width for the selectable (minus scrollbar)
    local selectableWidth = params.availableWidth - scrollbarMargin

    -- Draw expansion arrow if needed (manual, not TreeNode)
    local arrowWidth = 0
    if params.hasArrow then
        local arrowIcon = params.isOpen and "▼" or "▶"
        imgui.Text(ctx, arrowIcon)

        -- Check if arrow was clicked
        local arrowClicked = imgui.IsItemClicked(ctx)
        if arrowClicked and params.onToggle then
            params.onToggle()
        end

        imgui.SameLine(ctx, 0, 5)
        arrowWidth = 20
    end

    -- Draw Selectable with full width
    -- Use "text##id" format to have unique ID but display the name
    local selectableLabel = params.text .. "##" .. params.id
    local clicked = imgui.Selectable(
        ctx,
        selectableLabel,
        params.isSelected,
        imgui.SelectableFlags_None,
        selectableWidth - arrowWidth - totalButtonWidth,
        0
    )

    -- DRAG SOURCE: Must be IMMEDIATELY after Selectable (ImGui requirement)
    if params.dragSource then
        if imgui.BeginDragDropSource(ctx, imgui.DragDropFlags_None) then
            imgui.SetDragDropPayload(ctx, params.dragSource.type, params.dragSource.data)

            -- Handle preview as string or function
            local previewText = params.dragSource.preview
            if type(previewText) == "function" then
                previewText = previewText()
            end
            imgui.Text(ctx, previewText)

            -- Initialize drag state
            if params.dragSource.onStart then
                params.dragSource.onStart()
            end

            imgui.EndDragDropSource(ctx)
        end
    end

    -- DROP TARGET: Show insertion line indicator with smart positioning
    if params.dropTarget then
        -- Disable DragDropTarget highlight (yellow border)
        imgui.PushStyleColor(ctx, imgui.Col_DragDropTarget, 0x00000000) -- Transparent

        if imgui.BeginDragDropTarget(ctx) then
            local min_x, min_y = imgui.GetItemRectMin(ctx)
            local max_x, max_y = imgui.GetItemRectMax(ctx)
            local drawList = imgui.GetWindowDrawList(ctx)
            local _, mouseY = imgui.GetMousePos(ctx)

            -- Light gray color for insertion line (1px)
            local lineColor = 0xB0B0B0FF -- Lighter gray

            -- Calculate relative mouse position (0.0 = top, 1.0 = bottom)
            local itemHeight = max_y - min_y
            local relativeY = (mouseY - min_y) / itemHeight

            -- Smart positioning:
            -- Top 25%: insert BEFORE
            -- Bottom 25%: insert AFTER
            -- Middle 50%: insert INTO (for groups only)
            local dropPosition = "middle" -- "before", "after", "middle"

            if relativeY < 0.25 then
                dropPosition = "before"
            elseif relativeY > 0.75 then
                dropPosition = "after"
            else
                -- Middle zone: only valid for groups to drop INTO
                dropPosition = params.allowDropInto and "middle" or (relativeY < 0.5 and "before" or "after")
            end

            -- Draw insertion line (NOT in middle zone)
            if dropPosition == "before" then
                imgui.DrawList_AddLine(drawList, min_x, min_y, max_x, min_y, lineColor, 1)
            elseif dropPosition == "after" then
                imgui.DrawList_AddLine(drawList, min_x, max_y, max_x, max_y, lineColor, 1)
            end
            -- Middle zone: no line (visual clarity that item will go INTO)

            -- Try to accept each specified payload type
            for _, acceptType in ipairs(params.dropTarget.accept) do
                local payload = imgui.AcceptDragDropPayload(ctx, acceptType)
                if payload then
                    -- Only process if we don't already have a pending operation
                    local hasPendingOp = globals.pendingGroupMove or globals.pendingContainerMove or globals.pendingContainerReorder or globals.pendingContainerMultiMove
                    if not hasPendingOp and params.dropTarget.onDrop then
                        params.dropTarget.onDrop(acceptType, dropPosition)
                    end
                end
            end
            imgui.EndDragDropTarget(ctx)
        end

        imgui.PopStyleColor(ctx, 1) -- Pop DragDropTarget color
    end

    -- Handle selection clicks (simple click, not double click)
    if clicked and params.onSelect then
        params.onSelect()
    end

    -- Draw buttons aligned to the right
    for i, button in ipairs(params.buttons) do
        imgui.SameLine(ctx, 0, buttonSpacing)

        -- For first button, position it at the right edge
        if i == 1 then
            local currentX = imgui.GetCursorPosX(ctx)
            local contentAvail = imgui.GetContentRegionAvail(ctx)
            -- Reserve space for scrollbar (16px) + safety margin (8px)
            local scrollbarReserve = 24
            local rightX = currentX + contentAvail - totalButtonWidth - scrollbarReserve
            imgui.SetCursorPosX(ctx, rightX)
        end

        -- Draw the appropriate button based on icon type
        if button.icon == "+" then
            if globals.Icons.createAddButton(ctx, button.id, button.tooltip) then
                button.onClick()
            end
        elseif button.icon == "X" then
            if globals.Icons.createDeleteButton(ctx, button.id, button.tooltip) then
                button.onClick()
            end
        elseif button.icon == "↻" then
            if globals.Icons.createRegenButton(ctx, button.id, button.tooltip) then
                button.onClick()
            end
        end
    end

    return clicked
end


-- Create a drop zone with insertion line for groups (only during drag)
local function createGroupInsertionLine(insertIndex)
    -- Only show drop zones during an active drag
    if not globals.draggedItem or globals.draggedItem.type ~= "GROUP" then
        return
    end
    
    local dropZoneHeight = Constants.UI.GROUP_DROP_ZONE_HEIGHT
    local dropZoneWidth = -1 -- Full width
    
    -- Get button color from settings and create variations
    local buttonColor = globals.Settings.getSetting("buttonColor")
    local backgroundColorTransparent = buttonColor
    local borderColor = globals.Utils.brightenColor(buttonColor, 0.2) -- Brighter border
    local insertionLineColor = globals.Utils.brightenColor(buttonColor, 0.4) -- Even brighter insertion line
    
    -- Create an interactive invisible button for the drop zone
    imgui.InvisibleButton(globals.ctx, "##group_dropzone_" .. insertIndex, dropZoneWidth, dropZoneHeight)
    
    -- Always draw the drop zone outline when visible
    local min_x, min_y = imgui.GetItemRectMin(globals.ctx)
    local max_x, max_y = imgui.GetItemRectMax(globals.ctx)
    local drawList = imgui.GetWindowDrawList(globals.ctx)
    
    -- Draw background and border for the drop zone using button color
    imgui.DrawList_AddRectFilled(drawList, min_x, min_y, max_x, max_y, backgroundColorTransparent)
    imgui.DrawList_AddRect(drawList, min_x, min_y, max_x, max_y, borderColor, 0, 0, 1)
    
    if imgui.BeginDragDropTarget(globals.ctx) then
        -- Draw insertion line when hovering with valid payload
        local lineY = min_y + dropZoneHeight / 2
        -- Draw insertion line using brightened button color
        imgui.DrawList_AddLine(drawList, min_x, lineY, max_x, lineY, insertionLineColor, 4)
        
        -- Accept group drops
        if imgui.AcceptDragDropPayload(globals.ctx, "DND_GROUP") then
            if globals.draggedItem and globals.draggedItem.type == "GROUP" then
                local sourceGroupIndex = globals.draggedItem.index
                if sourceGroupIndex and sourceGroupIndex ~= insertIndex then
                    globals.pendingGroupMove = {
                        sourceIndex = sourceGroupIndex,
                        targetIndex = insertIndex
                    }
                end
            end
        end
        imgui.EndDragDropTarget(globals.ctx)
    end
end

-- Create a drop zone with insertion line for containers (only during drag)
local function createContainerInsertionLine(groupIndex, insertIndex)
    -- Only show drop zones during an active container drag
    if not globals.draggedItem or globals.draggedItem.type ~= "CONTAINER" then
        return
    end
    
    local dropZoneHeight = Constants.UI.CONTAINER_DROP_ZONE_HEIGHT
    local dropZoneWidth = -1 -- Full width
    
    -- Get button color from settings and create variations
    local buttonColor = globals.Settings.getSetting("buttonColor")
    local backgroundColorTransparent = buttonColor
    local borderColor = globals.Utils.brightenColor(buttonColor, 0.1) -- Slightly brighter border
    local insertionLineColor = globals.Utils.brightenColor(buttonColor, 0.3) -- Brighter insertion line
    
    -- Indent to match containers
    imgui.Indent(globals.ctx, Constants.UI.CONTAINER_INDENT)
    
    -- Create an interactive invisible button for the drop zone
    imgui.InvisibleButton(globals.ctx, "##container_dropzone_" .. groupIndex .. "_" .. insertIndex, dropZoneWidth, dropZoneHeight)
    
    -- Always draw the drop zone outline when visible
    local min_x, min_y = imgui.GetItemRectMin(globals.ctx)
    local max_x, max_y = imgui.GetItemRectMax(globals.ctx)
    local drawList = imgui.GetWindowDrawList(globals.ctx)
    
    -- Draw background and border for the drop zone using button color
    imgui.DrawList_AddRectFilled(drawList, min_x, min_y, max_x, max_y, backgroundColorTransparent)
    imgui.DrawList_AddRect(drawList, min_x, min_y, max_x, max_y, borderColor, 0, 0, 1)
    
    if imgui.BeginDragDropTarget(globals.ctx) then
        -- Draw insertion line when hovering with valid payload
        local lineY = min_y + dropZoneHeight / 2
        imgui.DrawList_AddLine(drawList, min_x, lineY, max_x, lineY, insertionLineColor, 3)
        
        -- Accept container drops
        if imgui.AcceptDragDropPayload(globals.ctx, "DND_CONTAINER") then
            if globals.draggedItem and globals.draggedItem.type == "CONTAINER" then
                local sourceGroupIndex = globals.draggedItem.groupIndex
                local sourceContainerIndex = globals.draggedItem.containerIndex
                
                if sourceGroupIndex and sourceContainerIndex then
                    if sourceGroupIndex == groupIndex then
                        -- Moving within same group
                        if sourceContainerIndex ~= insertIndex and sourceContainerIndex ~= insertIndex - 1 then
                            globals.pendingContainerReorder = {
                                groupIndex = groupIndex,
                                sourceIndex = sourceContainerIndex,
                                targetIndex = insertIndex
                            }
                        end
                    else
                        -- Moving between groups
                        globals.pendingContainerMove = {
                            sourceGroupIndex = sourceGroupIndex,
                            sourceContainerIndex = sourceContainerIndex,
                            targetGroupIndex = groupIndex,
                            targetContainerIndex = insertIndex
                        }
                    end
                end
            end
        end
        imgui.EndDragDropTarget(globals.ctx)
    end
    
    imgui.Unindent(globals.ctx, Constants.UI.CONTAINER_INDENT)
end

-- Create a drop zone on group header for moving containers to the end of the group (only during container drag)
local function createGroupDropZone(groupIndex)
    -- Only show group drop zones during container drag
    if not globals.draggedItem or globals.draggedItem.type ~= "CONTAINER" then
        return
    end
    
    if imgui.BeginDragDropTarget(globals.ctx) then
        -- Get button color from settings and create variations
        local buttonColor = globals.Settings.getSetting("buttonColor")
        local highlightColor = buttonColor
        local borderColor = globals.Utils.brightenColor(buttonColor, 0.3) -- Bright border
        
        -- Highlight the entire group with enhanced visuals using button color
        local min_x, min_y = imgui.GetItemRectMin(globals.ctx)
        local max_x, max_y = imgui.GetItemRectMax(globals.ctx)
        local drawList = imgui.GetWindowDrawList(globals.ctx)
        imgui.DrawList_AddRectFilled(drawList, min_x, min_y, max_x, max_y, highlightColor)
        imgui.DrawList_AddRect(drawList, min_x, min_y, max_x, max_y, borderColor, 0, 0, 2)
        
        -- Accept container drops (add to end of group)
        if imgui.AcceptDragDropPayload(globals.ctx, "DND_CONTAINER") then
            if globals.draggedItem and globals.draggedItem.type == "CONTAINER" then
                local sourceGroupIndex = globals.draggedItem.groupIndex
                local sourceContainerIndex = globals.draggedItem.containerIndex
                
                if sourceGroupIndex and sourceContainerIndex and sourceGroupIndex ~= groupIndex then
                    globals.pendingContainerMove = {
                        sourceGroupIndex = sourceGroupIndex,
                        sourceContainerIndex = sourceContainerIndex,
                        targetGroupIndex = groupIndex,
                        targetContainerIndex = #globals.groups[groupIndex].containers + 1
                    }
                end
            end
        end
        imgui.EndDragDropTarget(globals.ctx)
    end
end

-- Function to reorder groups
function UI_Groups.reorderGroups(sourceIndex, targetIndex)
    if sourceIndex == targetIndex or sourceIndex < 1 or targetIndex < 1 or
       sourceIndex > #globals.groups or targetIndex > #globals.groups + 1 then
        return
    end
    
    local movingGroup = globals.groups[sourceIndex]
    table.remove(globals.groups, sourceIndex)
    
    -- Adjust target index
    local insertIndex = targetIndex
    if sourceIndex < targetIndex then
        insertIndex = targetIndex - 1
    end
    insertIndex = math.max(1, math.min(insertIndex, #globals.groups + 1))
    
    table.insert(globals.groups, insertIndex, movingGroup)
    
    -- Update selections
    if globals.selectedGroupIndex == sourceIndex then
        globals.selectedGroupIndex = insertIndex
    end
    globals.selectedContainers = {}
    globals.inMultiSelectMode = false
    
    globals.Utils.reorganizeTracksAfterGroupReorder()
end

-- Function to move a container between groups
function UI_Groups.moveContainerToGroup(sourceGroupIndex, sourceContainerIndex, targetGroupIndex, targetContainerIndex)
    if sourceGroupIndex < 1 or targetGroupIndex < 1 or
       sourceGroupIndex > #globals.groups or targetGroupIndex > #globals.groups or
       sourceContainerIndex < 1 or sourceContainerIndex > #globals.groups[sourceGroupIndex].containers then
        return
    end
    
    local movingContainer = globals.groups[sourceGroupIndex].containers[sourceContainerIndex]
    table.remove(globals.groups[sourceGroupIndex].containers, sourceContainerIndex)
    
    -- Insert at target position
    local insertIndex = targetContainerIndex or (#globals.groups[targetGroupIndex].containers + 1)
    insertIndex = math.max(1, math.min(insertIndex, #globals.groups[targetGroupIndex].containers + 1))
    table.insert(globals.groups[targetGroupIndex].containers, insertIndex, movingContainer)
    
    -- Update selections
    local key = sourceGroupIndex .. "_" .. sourceContainerIndex
    if globals.selectedContainers[key] then
        globals.selectedContainers[key] = nil
        globals.selectedContainers[targetGroupIndex .. "_" .. insertIndex] = true
    end
    
    if globals.selectedGroupIndex == sourceGroupIndex and globals.selectedContainerIndex == sourceContainerIndex then
        globals.selectedGroupIndex = targetGroupIndex
        globals.selectedContainerIndex = insertIndex
    end
    
    globals.Utils.reorganizeTracksAfterContainerMove(sourceGroupIndex, targetGroupIndex, movingContainer.name)
end

-- Function to move multiple containers to a target group
function UI_Groups.moveMultipleContainersToGroup(containers, targetGroupIndex, targetContainerIndex)
    if not containers or #containers == 0 then return end

    -- Sort containers by groupIndex then containerIndex (descending) to remove from back to front
    table.sort(containers, function(a, b)
        if a.groupIndex == b.groupIndex then
            return a.containerIndex > b.containerIndex
        end
        return a.groupIndex > b.groupIndex
    end)

    -- Extract all containers first
    local movedContainers = {}
    for _, item in ipairs(containers) do
        if item.groupIndex >= 1 and item.groupIndex <= #globals.groups and
           item.containerIndex >= 1 and item.containerIndex <= #globals.groups[item.groupIndex].containers then
            local container = globals.groups[item.groupIndex].containers[item.containerIndex]
            table.insert(movedContainers, 1, container) -- Insert at front to maintain order
            table.remove(globals.groups[item.groupIndex].containers, item.containerIndex)
        end
    end

    -- Insert all containers at target position
    if targetGroupIndex >= 1 and targetGroupIndex <= #globals.groups then
        local insertIndex = math.max(1, math.min(targetContainerIndex, #globals.groups[targetGroupIndex].containers + 1))
        for _, container in ipairs(movedContainers) do
            table.insert(globals.groups[targetGroupIndex].containers, insertIndex, container)
            insertIndex = insertIndex + 1
        end
    end

    -- Clear selection and reorganize tracks
    globals.selectedContainers = {}
    globals.inMultiSelectMode = false
    globals.selectedContainerIndex = nil

    -- Trigger track reorganization
    for _, item in ipairs(containers) do
        globals.Utils.reorganizeTracksAfterContainerMove(item.groupIndex, targetGroupIndex, "multiple containers")
        break -- Only need to call once
    end
end

-- Function to reorder containers within the same group
function UI_Groups.reorderContainers(groupIndex, sourceIndex, targetIndex)
    if sourceIndex == targetIndex or sourceIndex < 1 or targetIndex < 1 or
       groupIndex < 1 or groupIndex > #globals.groups or
       sourceIndex > #globals.groups[groupIndex].containers then
        return
    end
    
    local movingContainer = globals.groups[groupIndex].containers[sourceIndex]
    table.remove(globals.groups[groupIndex].containers, sourceIndex)
    
    -- Adjust target index
    local insertIndex = targetIndex
    if sourceIndex < targetIndex then
        insertIndex = targetIndex - 1
    end
    insertIndex = math.max(1, math.min(insertIndex, #globals.groups[groupIndex].containers + 1))
    
    table.insert(globals.groups[groupIndex].containers, insertIndex, movingContainer)
    
    -- Update selections
    local oldKey = groupIndex .. "_" .. sourceIndex
    if globals.selectedContainers[oldKey] then
        globals.selectedContainers[oldKey] = nil
        globals.selectedContainers[groupIndex .. "_" .. insertIndex] = true
    end
    
    if globals.selectedGroupIndex == groupIndex and globals.selectedContainerIndex == sourceIndex then
        globals.selectedContainerIndex = insertIndex
    end
    
    -- No need to reorganize tracks for reordering within same group
end

-- Draw the left panel containing the list of groups and their containers
-- @param width number: Panel width
-- @param isContainerSelected function: Function to check if container is selected
-- @param toggleContainerSelection function: Function to toggle container selection
-- @param clearContainerSelections function: Function to clear all selections
-- @param selectContainerRange function: Function to select container range
function UI_Groups.drawGroupsPanel(width, isContainerSelected, toggleContainerSelection, clearContainerSelections, selectContainerRange)
    if not width or width <= 0 then
        error("UI_Groups.drawGroupsPanel: valid width parameter is required")
    end
    
    if not isContainerSelected or not toggleContainerSelection or not clearContainerSelections or not selectContainerRange then
        error("UI_Groups.drawGroupsPanel: all callback functions are required")
    end
    -- Basic check for minimal window size
    local availableHeight = imgui.GetWindowHeight(globals.ctx)
    local availableWidth = imgui.GetWindowWidth(globals.ctx)
    if availableHeight < Constants.UI.MIN_WINDOW_HEIGHT or availableWidth < Constants.UI.MIN_WINDOW_WIDTH then
        imgui.TextColored(globals.ctx, Constants.COLORS.ERROR_RED, "Window too small")
        return
    end

    -- Panel title
    imgui.Text(globals.ctx, "Groups & Containers")

    -- Multi-selection info and clear selection button
    local selectedCount = UI_Groups.getSelectedContainersCount()
    if selectedCount > 1 then
        imgui.SameLine(globals.ctx)
        imgui.TextColored(globals.ctx, Constants.COLORS.SUCCESS_GREEN, "(" .. selectedCount .. " selected)")
        imgui.SameLine(globals.ctx)
        if imgui.Button(globals.ctx, "Clear Selection") then
            clearContainerSelections()
        end
    end

    -- Add group button
    if imgui.Button(globals.ctx, "Add Group") then
        globals.History.captureState("Add group")
        table.insert(globals.groups, globals.Structures.createGroup())
        local newGroupIndex = #globals.groups
        globals.selectedGroupIndex = newGroupIndex
        globals.selectedContainerIndex = nil
        clearContainerSelections()
        globals.inMultiSelectMode = false
        globals.shiftAnchorGroupIndex = newGroupIndex
        globals.shiftAnchorContainerIndex = nil
    end

    -- Help marker for drag and drop
    imgui.SameLine(globals.ctx)
    globals.Utils.HelpMarker("Drag and drop:\n" ..
        "- Drag groups to reorder them\n" ..
        "- Drag containers to move them within/between groups\n" ..
        "- Drop containers on group headers to add them to the end\n" ..
        "- Use Ctrl+Click and Shift+Click for multi-selection")

    imgui.Separator(globals.ctx)

    -- Detect if Ctrl is pressed for multi-selection
    local ctrlPressed = imgui.GetKeyMods(globals.ctx) & imgui.Mod_Ctrl ~= 0
    local groupToDelete = nil

    -- Loop through groups
    for i, group in ipairs(globals.groups) do
        local groupId = "group" .. i
        local isSelected = (globals.selectedGroupIndex == i and globals.selectedContainerIndex == nil)
        local isOpen = group.expanded or false

        -- Prepare display name with regeneration indicator
        local groupDisplayName = group.name
        if group.needsRegeneration then
            groupDisplayName = "• " .. group.name
        end

        -- Draw group using the helper function
        local groupClicked = drawListItemWithButtons({
            id = groupId,
            text = groupDisplayName,
            isSelected = isSelected,
            hasArrow = true,
            isOpen = isOpen,
            availableWidth = width,

            -- Drag source: groups can be dragged
            dragSource = {
                type = "DND_GROUP",
                data = string.format("GROUP:%d", i),
                preview = "📁 " .. group.name,
                onStart = function()
                    globals.draggedItem = {
                        type = "GROUP",
                        index = i,
                        name = group.name
                    }
                end
            },

            -- Drop target: groups accept both groups and containers
            dropTarget = {
                accept = {"DND_GROUP", "DND_CONTAINER"},
                allowDropInto = true, -- Groups can receive items INTO them
                onDrop = function(payloadType, dropPosition)
                    if payloadType == "DND_CONTAINER" then
                        -- Drop container(s)
                        if globals.draggedItem and (globals.draggedItem.type == "CONTAINER" or globals.draggedItem.type == "CONTAINER_MULTI") then
                            local targetContainerIndex
                            if dropPosition == "before" then
                                -- Insert before this group (beginning of group)
                                targetContainerIndex = 1
                            elseif dropPosition == "after" then
                                -- Insert after this group (end of group)
                                targetContainerIndex = #globals.groups[i].containers + 1
                            else -- "middle"
                                -- Drop INTO the group (end of group)
                                targetContainerIndex = #globals.groups[i].containers + 1
                            end

                            if globals.draggedItem.type == "CONTAINER_MULTI" then
                                -- Multi-container move to group
                                globals.pendingContainerMultiMove = {
                                    containers = globals.draggedItem.containers,
                                    targetGroupIndex = i,
                                    targetContainerIndex = targetContainerIndex
                                }
                            else
                                -- Single container move
                                local sourceGroupIndex = globals.draggedItem.groupIndex
                                local sourceContainerIndex = globals.draggedItem.containerIndex

                                if sourceGroupIndex ~= i or (sourceGroupIndex == i and sourceContainerIndex ~= targetContainerIndex and sourceContainerIndex ~= targetContainerIndex - 1) then
                                    if sourceGroupIndex == i then
                                        globals.pendingContainerReorder = {
                                            groupIndex = i,
                                            sourceIndex = sourceContainerIndex,
                                            targetIndex = targetContainerIndex
                                        }
                                    else
                                        globals.pendingContainerMove = {
                                            sourceGroupIndex = sourceGroupIndex,
                                            sourceContainerIndex = sourceContainerIndex,
                                            targetGroupIndex = i,
                                            targetContainerIndex = targetContainerIndex
                                        }
                                    end
                                end
                            end
                        end
                    elseif payloadType == "DND_GROUP" then
                        -- Reorder groups
                        if globals.draggedItem and globals.draggedItem.type == "GROUP" then
                            local sourceIndex = globals.draggedItem.index
                            local targetIndex

                            if dropPosition == "before" then
                                targetIndex = i
                            elseif dropPosition == "after" then
                                targetIndex = i + 1
                            else -- "middle" - treat as "after" for groups
                                targetIndex = i + 1
                            end

                            if sourceIndex ~= targetIndex and sourceIndex ~= targetIndex - 1 then
                                globals.pendingGroupMove = {
                                    sourceIndex = sourceIndex,
                                    targetIndex = targetIndex
                                }
                            end
                        end
                    end
                end
            },

            onSelect = function()
                globals.selectedGroupIndex = i
                globals.selectedContainerIndex = nil
                if not ctrlPressed then
                    clearContainerSelections()
                end
            end,

            onToggle = function()
                group.expanded = not group.expanded
            end,

            buttons = {
                {icon = "+", id = groupId, tooltip = "Add container", onClick = function()
                    globals.History.captureState("Add container")
                    table.insert(group.containers, globals.Structures.createContainer())
                    clearContainerSelections()
                    local newContainerIndex = #group.containers
                    toggleContainerSelection(i, newContainerIndex)
                    globals.selectedGroupIndex = i
                    globals.selectedContainerIndex = newContainerIndex
                    globals.inMultiSelectMode = false
                    globals.shiftAnchorGroupIndex = i
                    globals.shiftAnchorContainerIndex = newContainerIndex
                    -- Ensure the group is expanded to show the new container
                    group.expanded = true
                end},
                {icon = "X", id = groupId, tooltip = "Delete group", onClick = function()
                    groupToDelete = i
                end},
                {icon = "↻", id = groupId, tooltip = "Regenerate group", onClick = function()
                    globals.Generation.generateSingleGroup(i)
                end}
            }
        })

        -- If the group is open, display its content
        if group.expanded then
            local containerToDelete = nil

            -- Loop through containers in this group
            for j, container in ipairs(group.containers) do
                local containerId = groupId .. "_container" .. j
                local isSelected = isContainerSelected(i, j)

                -- Prepare display name with regeneration indicator
                local containerDisplayName = container.name
                if container.needsRegeneration then
                    containerDisplayName = "• " .. container.name
                end

                -- Indent containers visually
                imgui.Indent(globals.ctx, Constants.UI.CONTAINER_INDENT)

                -- Get actual available width after indentation
                local containerAvailWidth = imgui.GetContentRegionAvail(globals.ctx)

                -- Draw container using the helper function
                local containerClicked = drawListItemWithButtons({
                    id = containerId,
                    text = containerDisplayName,
                    isSelected = isSelected,
                    hasArrow = false, -- Containers don't have expansion arrow
                    isOpen = false,
                    availableWidth = containerAvailWidth,

                    -- Drag source: containers can be dragged
                    dragSource = {
                        type = "DND_CONTAINER",
                        data = string.format("CONTAINER:%d:%d", i, j),
                        preview = function()
                            -- If multi-select is active and this container is selected, show count
                            if globals.inMultiSelectMode and isSelected then
                                local count = UI_Groups.getSelectedContainersCount()
                                return "📦 " .. count .. " containers"
                            else
                                return "📦 " .. container.name
                            end
                        end,
                        onStart = function()
                            -- If dragging a selected container in multi-select mode, store all selected
                            if globals.inMultiSelectMode and isSelected then
                                local selectedContainers = {}
                                for key, _ in pairs(globals.selectedContainers) do
                                    local gIdx, cIdx = key:match("(%d+)_(%d+)")
                                    if gIdx and cIdx then
                                        table.insert(selectedContainers, {
                                            groupIndex = tonumber(gIdx),
                                            containerIndex = tonumber(cIdx)
                                        })
                                    end
                                end
                                globals.draggedItem = {
                                    type = "CONTAINER_MULTI",
                                    containers = selectedContainers,
                                    count = #selectedContainers
                                }
                            else
                                globals.draggedItem = {
                                    type = "CONTAINER",
                                    groupIndex = i,
                                    containerIndex = j,
                                    name = container.name
                                }
                            end
                        end
                    },

                    -- Drop target: containers accept both containers AND groups
                    -- Groups dropped on containers will be placed after the parent group
                    dropTarget = {
                        accept = {"DND_CONTAINER", "DND_GROUP"},
                        allowDropInto = false, -- Containers don't accept items INTO them
                        onDrop = function(payloadType, dropPosition)
                            if payloadType == "DND_GROUP" then
                                -- Group dropped on a container - treat as dropping after the parent group
                                if globals.draggedItem and globals.draggedItem.type == "GROUP" then
                                    local sourceIndex = globals.draggedItem.index
                                    local targetIndex = i + 1 -- Always drop after parent group

                                    if sourceIndex ~= targetIndex and sourceIndex ~= targetIndex - 1 then
                                        local hasPendingOp = globals.pendingGroupMove or globals.pendingContainerMove or globals.pendingContainerReorder or globals.pendingContainerMultiMove
                                        if not hasPendingOp then
                                            globals.pendingGroupMove = {
                                                sourceIndex = sourceIndex,
                                                targetIndex = targetIndex
                                            }
                                        end
                                    end
                                end
                            elseif globals.draggedItem and (globals.draggedItem.type == "CONTAINER" or globals.draggedItem.type == "CONTAINER_MULTI") then
                                -- Calculate target index based on drop position
                                local targetIndex
                                if dropPosition == "before" then
                                    targetIndex = j
                                else -- "after" (middle is treated as after for containers)
                                    targetIndex = j + 1
                                end

                                if globals.draggedItem.type == "CONTAINER_MULTI" then
                                    -- Multi-container move
                                    globals.pendingContainerMultiMove = {
                                        containers = globals.draggedItem.containers,
                                        targetGroupIndex = i,
                                        targetContainerIndex = targetIndex
                                    }
                                else
                                    -- Single container move
                                    local sourceGroupIndex = globals.draggedItem.groupIndex
                                    local sourceContainerIndex = globals.draggedItem.containerIndex

                                    if sourceGroupIndex == i then
                                        -- Reorder within same group
                                        -- Don't reorder if dropping at same position
                                        local isSamePosition = (dropPosition == "before" and sourceContainerIndex == targetIndex) or
                                                              (dropPosition == "after" and sourceContainerIndex == targetIndex - 1)

                                        if not isSamePosition then
                                            globals.pendingContainerReorder = {
                                                groupIndex = i,
                                                sourceIndex = sourceContainerIndex,
                                                targetIndex = targetIndex
                                            }
                                        end
                                    else
                                        -- Move between groups
                                        globals.pendingContainerMove = {
                                            sourceGroupIndex = sourceGroupIndex,
                                            sourceContainerIndex = sourceContainerIndex,
                                            targetGroupIndex = i,
                                            targetContainerIndex = targetIndex
                                        }
                                    end
                                end
                            end
                        end
                    },

                    onSelect = function()
                        local shiftPressed = imgui.GetKeyMods(globals.ctx) & imgui.Mod_Shift ~= 0
                        if ctrlPressed then
                            toggleContainerSelection(i, j)
                            globals.inMultiSelectMode = UI_Groups.getSelectedContainersCount() > 1
                            globals.shiftAnchorGroupIndex = i
                            globals.shiftAnchorContainerIndex = j
                        elseif shiftPressed and globals.shiftAnchorGroupIndex then
                            selectContainerRange(globals.shiftAnchorGroupIndex, globals.shiftAnchorContainerIndex, i, j)
                        else
                            clearContainerSelections()
                            -- Stop any playing audio when selecting a different container
                            if globals.Waveform then
                                globals.Waveform.stopPlayback()
                            end
                            toggleContainerSelection(i, j)
                            globals.inMultiSelectMode = false
                            globals.shiftAnchorGroupIndex = i
                            globals.shiftAnchorContainerIndex = j
                        end
                    end,

                    buttons = {
                        {icon = "X", id = containerId, tooltip = "Delete container", onClick = function()
                            containerToDelete = j
                        end},
                        {icon = "↻", id = containerId, tooltip = "Regenerate container", onClick = function()
                            globals.Generation.generateSingleContainer(i, j)
                        end}
                    }
                })

                imgui.Unindent(globals.ctx, Constants.UI.CONTAINER_INDENT)
            end

            -- Delete the marked container if any
            if containerToDelete then
                globals.History.captureState("Delete container")
                globals.selectedContainers[i .. "_" .. containerToDelete] = nil
                table.remove(group.containers, containerToDelete)
                if globals.selectedGroupIndex == i and globals.selectedContainerIndex == containerToDelete then
                    globals.selectedContainerIndex = nil
                elseif globals.selectedGroupIndex == i and globals.selectedContainerIndex and globals.selectedContainerIndex > containerToDelete then
                    globals.selectedContainerIndex = globals.selectedContainerIndex - 1
                end
                -- Update selection indices for containers after the deleted one
                for k = containerToDelete + 1, #group.containers + 1 do
                    if globals.selectedContainers[i .. "_" .. k] then
                        globals.selectedContainers[i .. "_" .. (k-1)] = true
                        globals.selectedContainers[i .. "_" .. k] = nil
                    end
                end
            end
        end
    end

    -- Delete the marked group if any
    if groupToDelete then
        globals.History.captureState("Delete group")
        -- Remove any selected containers from this group
        for key in pairs(globals.selectedContainers) do
            local t, c = key:match("(%d+)_(%d+)")
            if tonumber(t) == groupToDelete then
                globals.selectedContainers[key] = nil
            end
        end
        table.remove(globals.groups, groupToDelete)
        -- Update primary selection if necessary
        if globals.selectedGroupIndex == groupToDelete then
            globals.selectedGroupIndex = nil
            globals.selectedContainerIndex = nil
        elseif globals.selectedGroupIndex and globals.selectedGroupIndex > groupToDelete then
            globals.selectedGroupIndex = globals.selectedGroupIndex - 1
        end
        -- Update multi-selection references for groups after the deleted one
        for key in pairs(globals.selectedContainers) do
            local t, c = key:match("(%d+)_(%d+)")
            if tonumber(t) > groupToDelete then
                globals.selectedContainers[(tonumber(t)-1) .. "_" .. c] = true
                globals.selectedContainers[key] = nil
            end
        end
    end

    -- Update the multi-select mode flag
    globals.inMultiSelectMode = UI_Groups.getSelectedContainersCount() > 1
    
    -- Process any pending moves after rendering is complete
    if globals.pendingGroupMove then
        globals.History.captureState("Reorder group")
        UI_Groups.reorderGroups(globals.pendingGroupMove.sourceIndex, globals.pendingGroupMove.targetIndex)
        globals.pendingGroupMove = nil
        globals.draggedItem = nil -- Clear drag state after successful move
    end

    if globals.pendingContainerMultiMove then
        globals.History.captureState("Move multiple containers")
        UI_Groups.moveMultipleContainersToGroup(
            globals.pendingContainerMultiMove.containers,
            globals.pendingContainerMultiMove.targetGroupIndex,
            globals.pendingContainerMultiMove.targetContainerIndex
        )
        globals.pendingContainerMultiMove = nil
        globals.draggedItem = nil -- Clear drag state after successful move
    end

    if globals.pendingContainerMove then
        globals.History.captureState("Move container")
        UI_Groups.moveContainerToGroup(
            globals.pendingContainerMove.sourceGroupIndex,
            globals.pendingContainerMove.sourceContainerIndex,
            globals.pendingContainerMove.targetGroupIndex,
            globals.pendingContainerMove.targetContainerIndex
        )
        globals.pendingContainerMove = nil
        globals.draggedItem = nil -- Clear drag state after successful move
    end

    if globals.pendingContainerReorder then
        globals.History.captureState("Reorder container")
        UI_Groups.reorderContainers(
            globals.pendingContainerReorder.groupIndex,
            globals.pendingContainerReorder.sourceIndex,
            globals.pendingContainerReorder.targetIndex
        )
        globals.pendingContainerReorder = nil
        globals.draggedItem = nil -- Clear drag state after successful move
    end
    
    -- Clean up drag state if no drag is active and no pending operations (fixes persistent drop zones)
    if globals.draggedItem and not imgui.IsMouseDown(globals.ctx, imgui.MouseButton_Left) and
       not globals.pendingGroupMove and not globals.pendingContainerMove and not globals.pendingContainerReorder and not globals.pendingContainerMultiMove then
        globals.draggedItem = nil
    end
end

-- Return the number of selected containers across all groups
function UI_Groups.getSelectedContainersCount()
    local count = 0
    for _ in pairs(globals.selectedContainers) do
        count = count + 1
    end
    return count
end

return UI_Groups