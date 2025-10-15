--[[
@version 1.4
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

-- Helper function to draw a list item (folder, group, or container) with buttons aligned to the right
-- Uses Selectable for full-width clickable area, manual arrow for expansion
-- @param params table: Configuration table with the following keys:
--   - id: string - Unique ID for the item
--   - text: string - Display text
--   - icon: string - Icon to display before text (optional)
--   - isSelected: boolean - Whether the item is selected
--   - hasArrow: boolean - Whether to show expand/collapse arrow
--   - isOpen: boolean - Whether the item is expanded (only used if hasArrow = true)
--   - availableWidth: number - Total available width for the row
--   - dragSource: table - Drag source config {type, data, preview, onStart} (optional)
--   - dropTarget: table - Drop target config {accept[], onDrop} (optional)
--   - onSelect: function - Callback when item is clicked
--   - onToggle: function - Callback when arrow is clicked (only if hasArrow = true)
--   - buttons: table - Array of button configs {icon, id, tooltip, onClick}
--   - contextMenu: table - Array of context menu items {label, onClick, separator, enabled}
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

    -- Draw icon if provided
    local iconWidth = 0
    if params.icon then
        imgui.Text(ctx, params.icon)
        imgui.SameLine(ctx, 0, 5)
        iconWidth = 20
    end

    -- Draw Selectable with full width
    -- Use "text##id" format to have unique ID but display the name
    local selectableLabel = params.text .. "##" .. params.id
    local clicked = imgui.Selectable(
        ctx,
        selectableLabel,
        params.isSelected,
        imgui.SelectableFlags_None,
        selectableWidth - arrowWidth - iconWidth - totalButtonWidth,
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
            -- Middle 50%: insert INTO (for folders/groups only)
            local dropPosition = "middle" -- "before", "after", "middle"

            if relativeY < 0.25 then
                dropPosition = "before"
            elseif relativeY > 0.75 then
                dropPosition = "after"
            else
                -- Middle zone: only valid for folders/groups to drop INTO
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
                    local hasPendingOp = globals.pendingGroupMove or globals.pendingContainerMove or globals.pendingContainerReorder or globals.pendingContainerMultiMove or globals.pendingFolderMove
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

    -- Right-click context menu
    if params.contextMenu then
        if imgui.BeginPopupContextItem(ctx, "##contextMenu_" .. params.id) then
            for _, menuItem in ipairs(params.contextMenu) do
                -- Check if item should be enabled/disabled
                local enabled = true
                if menuItem.enabled ~= nil then
                    enabled = type(menuItem.enabled) == "function" and menuItem.enabled() or menuItem.enabled
                end

                if menuItem.separator then
                    imgui.Separator(ctx)
                else
                    if enabled then
                        if imgui.Selectable(ctx, menuItem.label) then
                            if menuItem.onClick then
                                menuItem.onClick()
                            end
                        end
                    else
                        imgui.BeginDisabled(ctx)
                        imgui.Selectable(ctx, menuItem.label, false)
                        imgui.EndDisabled(ctx)
                    end
                end
            end
            imgui.EndPopup(ctx)
        end
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

-- Recursive function to render folders, groups, and containers
-- @param items table: Array of items (folders or groups) to render
-- @param parentPath table: Path to the parent (array of indices)
-- @param indentLevel number: Current indentation level
-- @param availableWidth number: Available width for rendering
-- @param isContainerSelected function: Callback to check if container is selected
-- @param toggleContainerSelection function: Callback to toggle container selection
-- @param clearContainerSelections function: Callback to clear all container selections
-- @param selectContainerRange function: Callback to select container range
local function renderItems(items, parentPath, indentLevel, availableWidth, isContainerSelected, toggleContainerSelection, clearContainerSelections, selectContainerRange)
    if not items or #items == 0 then
        return
    end

    indentLevel = indentLevel or 0
    parentPath = parentPath or {}

    local ctrlPressed = imgui.GetKeyMods(globals.ctx) & imgui.Mod_Ctrl ~= 0
    local itemToDelete = nil

    for i, item in ipairs(items) do
        local currentPath = globals.Utils.copyTable(parentPath)
        table.insert(currentPath, i)
        local pathStr = globals.Utils.pathToString(currentPath)
        local itemId = item.type .. pathStr

        if item.type == "folder" then
            -- RENDER FOLDER
            local isSelected = globals.Utils.pathsEqual(globals.selectedPath, currentPath) and globals.selectedType == "folder"
            local isOpen = item.expanded or false

            -- Draw folder using the helper function
            drawListItemWithButtons({
                id = itemId,
                icon = "📁",
                text = item.name,
                isSelected = isSelected,
                hasArrow = true,
                isOpen = isOpen,
                availableWidth = availableWidth,

                -- Drag source: folders can be dragged
                dragSource = {
                    type = "DND_FOLDER",
                    data = pathStr,
                    preview = "📁 " .. item.name,
                    onStart = function()
                        globals.draggedItem = {
                            type = "FOLDER",
                            path = currentPath,
                            name = item.name
                        }
                    end
                },

                -- Drop target: folders accept folders, groups, and containers
                dropTarget = {
                    accept = {"DND_FOLDER", "DND_GROUP", "DND_CONTAINER"},
                    allowDropInto = true,
                    onDrop = function(payloadType, dropPosition)
                        if payloadType == "DND_FOLDER" then
                            -- Folder dropped on folder
                            if globals.draggedItem and globals.draggedItem.type == "FOLDER" then
                                local sourcePath = globals.draggedItem.path
                                local targetPath = currentPath

                                -- Prevent dropping folder into itself or its descendants
                                if globals.Utils.isPathAncestor(sourcePath, targetPath) then
                                    return
                                end

                                -- Determine final target path based on drop position
                                if dropPosition == "before" then
                                    -- Insert before this folder (same level)
                                    targetPath = globals.Utils.copyTable(parentPath)
                                    table.insert(targetPath, i)
                                elseif dropPosition == "after" then
                                    -- Insert after this folder (same level)
                                    targetPath = globals.Utils.copyTable(parentPath)
                                    table.insert(targetPath, i + 1)
                                else -- "middle"
                                    -- Drop INTO this folder
                                    targetPath = globals.Utils.copyTable(currentPath)
                                    table.insert(targetPath, #item.children + 1)
                                end

                                globals.pendingFolderMove = {
                                    sourcePath = sourcePath,
                                    targetPath = targetPath,
                                    moveType = "folder"
                                }
                            end
                        elseif payloadType == "DND_GROUP" then
                            -- Group dropped on folder
                            if globals.draggedItem and globals.draggedItem.type == "GROUP" then
                                local sourcePath = globals.draggedItem.path
                                local targetPath

                                if dropPosition == "before" then
                                    targetPath = globals.Utils.copyTable(parentPath)
                                    table.insert(targetPath, i)
                                elseif dropPosition == "after" then
                                    targetPath = globals.Utils.copyTable(parentPath)
                                    table.insert(targetPath, i + 1)
                                else -- "middle"
                                    targetPath = globals.Utils.copyTable(currentPath)
                                    table.insert(targetPath, #item.children + 1)
                                end

                                globals.pendingFolderMove = {
                                    sourcePath = sourcePath,
                                    targetPath = targetPath,
                                    moveType = "group"
                                }
                            end
                        elseif payloadType == "DND_CONTAINER" then
                            -- Container dropped on folder (not allowed - folders can't contain containers directly)
                            -- Containers can only be inside groups
                            -- Do nothing or show error
                        end
                    end
                },

                onSelect = function()
                    globals.selectedPath = currentPath
                    globals.selectedType = "folder"
                    globals.selectedContainerIndex = nil
                    if not ctrlPressed then
                        clearContainerSelections()
                    end
                end,

                onToggle = function()
                    item.expanded = not item.expanded
                end,

                buttons = {
                    {icon = "+", id = itemId .. "_addGroup", tooltip = "Add group", onClick = function()
                        table.insert(item.children, globals.Structures.createGroup())
                        item.expanded = true
                        globals.History.captureState("Add group to folder")
                    end},
                    {icon = "+", id = itemId .. "_addFolder", tooltip = "Add folder", onClick = function()
                        table.insert(item.children, globals.Structures.createFolder())
                        item.expanded = true
                        globals.History.captureState("Add subfolder")
                    end},
                    {icon = "X", id = itemId, tooltip = "Delete folder", onClick = function()
                        itemToDelete = i
                    end}
                },

                contextMenu = {
                    {label = "Copy (Ctrl+C)", onClick = function()
                        globals.clipboard = {
                            type = "folder",
                            data = globals.Utils.deepCopy(item),
                            source = {path = currentPath}
                        }
                    end},
                    {label = "Paste (Ctrl+V)", onClick = function()
                        if not globals.clipboard.data then return end
                        globals.History.captureState("Paste " .. globals.clipboard.type)

                        if globals.clipboard.type == "folder" or globals.clipboard.type == "group" then
                            local itemCopy = globals.Utils.deepCopy(globals.clipboard.data)
                            itemCopy.name = itemCopy.name .. " (Copy)"
                            table.insert(item.children, itemCopy)
                        end
                    end, enabled = function() return globals.clipboard.data ~= nil end},
                    {label = "Duplicate (Ctrl+D)", onClick = function()
                        globals.History.captureState("Duplicate folder")
                        local folderCopy = globals.Utils.deepCopy(item)
                        folderCopy.name = item.name .. " (Copy)"
                        table.insert(items, i + 1, folderCopy)
                    end},
                    {separator = true},
                    {label = "Delete (Del)", onClick = function()
                        itemToDelete = i
                    end}
                }
            })

            -- If folder is expanded, render its children recursively
            if item.expanded then
                imgui.Indent(globals.ctx, Constants.UI.CONTAINER_INDENT)
                renderItems(item.children, currentPath, indentLevel + 1, availableWidth - Constants.UI.CONTAINER_INDENT, isContainerSelected, toggleContainerSelection, clearContainerSelections, selectContainerRange)
                imgui.Unindent(globals.ctx, Constants.UI.CONTAINER_INDENT)
            end

        elseif item.type == "group" then
            -- RENDER GROUP
            local isSelected = globals.Utils.pathsEqual(globals.selectedPath, currentPath) and globals.selectedType == "group" and not globals.selectedContainerIndex
            local isOpen = item.expanded or false

            -- Prepare display name with regeneration indicator
            local groupDisplayName = item.name
            if item.needsRegeneration then
                groupDisplayName = "• " .. item.name
            end

            -- Draw group using the helper function
            drawListItemWithButtons({
                id = itemId,
                text = groupDisplayName,
                isSelected = isSelected,
                hasArrow = true,
                isOpen = isOpen,
                availableWidth = availableWidth,

                -- Drag source: groups can be dragged
                dragSource = {
                    type = "DND_GROUP",
                    data = pathStr,
                    preview = "📦 " .. item.name,
                    onStart = function()
                        globals.draggedItem = {
                            type = "GROUP",
                            path = currentPath,
                            name = item.name
                        }
                    end
                },

                -- Drop target: groups accept groups and containers
                dropTarget = {
                    accept = {"DND_GROUP", "DND_CONTAINER"},
                    allowDropInto = true, -- Groups can receive containers INTO them
                    onDrop = function(payloadType, dropPosition)
                        if payloadType == "DND_CONTAINER" then
                            -- Container dropped on group
                            if globals.draggedItem and (globals.draggedItem.type == "CONTAINER" or globals.draggedItem.type == "CONTAINER_MULTI") then
                                local targetContainerIndex
                                if dropPosition == "before" then
                                    -- Insert before this group (at parent level - not valid for containers)
                                    -- Treat as beginning of group instead
                                    targetContainerIndex = 1
                                elseif dropPosition == "after" then
                                    -- Insert after this group (at parent level - not valid for containers)
                                    -- Treat as end of group instead
                                    targetContainerIndex = #item.containers + 1
                                else -- "middle"
                                    -- Drop INTO the group (end of group)
                                    targetContainerIndex = #item.containers + 1
                                end

                                if globals.draggedItem.type == "CONTAINER_MULTI" then
                                    -- Multi-container move to group
                                    globals.pendingContainerMultiMove = {
                                        containers = globals.draggedItem.containers,
                                        targetPath = currentPath,
                                        targetContainerIndex = targetContainerIndex
                                    }
                                else
                                    -- Single container move
                                    globals.pendingContainerMove = {
                                        sourcePath = globals.draggedItem.path,
                                        sourceContainerIndex = globals.draggedItem.containerIndex,
                                        targetPath = currentPath,
                                        targetContainerIndex = targetContainerIndex
                                    }
                                end
                            end
                        elseif payloadType == "DND_GROUP" then
                            -- Group dropped on group (reorder at same level)
                            if globals.draggedItem and globals.draggedItem.type == "GROUP" then
                                local sourcePath = globals.draggedItem.path
                                local targetPath

                                if dropPosition == "before" then
                                    targetPath = globals.Utils.copyTable(parentPath)
                                    table.insert(targetPath, i)
                                elseif dropPosition == "after" then
                                    targetPath = globals.Utils.copyTable(parentPath)
                                    table.insert(targetPath, i + 1)
                                else -- "middle" - treat as "after" for groups
                                    targetPath = globals.Utils.copyTable(parentPath)
                                    table.insert(targetPath, i + 1)
                                end

                                globals.pendingFolderMove = {
                                    sourcePath = sourcePath,
                                    targetPath = targetPath,
                                    moveType = "group"
                                }
                            end
                        end
                    end
                },

                onSelect = function()
                    globals.selectedPath = currentPath
                    globals.selectedType = "group"
                    globals.selectedContainerIndex = nil
                    if not ctrlPressed then
                        clearContainerSelections()
                    end
                end,

                onToggle = function()
                    item.expanded = not item.expanded
                end,

                buttons = {
                    {icon = "+", id = itemId, tooltip = "Add container", onClick = function()
                        table.insert(item.containers, globals.Structures.createContainer())
                        clearContainerSelections()
                        local newContainerIndex = #item.containers
                        toggleContainerSelection(currentPath, newContainerIndex)
                        globals.selectedPath = currentPath
                        globals.selectedType = "group"
                        globals.selectedContainerIndex = newContainerIndex
                        globals.inMultiSelectMode = false
                        globals.shiftAnchorPath = currentPath
                        globals.shiftAnchorContainerIndex = newContainerIndex
                        item.expanded = true
                        globals.Structures.syncEuclideanBindings(item)
                        globals.History.captureState("Add container")
                    end},
                    {icon = "X", id = itemId, tooltip = "Delete group", onClick = function()
                        itemToDelete = i
                    end},
                    {icon = "↻", id = itemId, tooltip = "Regenerate group", onClick = function()
                        globals.Generation.generateSingleGroupByPath(currentPath)
                    end}
                },

                contextMenu = {
                    {label = "Copy (Ctrl+C)", onClick = function()
                        globals.clipboard = {
                            type = "group",
                            data = globals.Utils.deepCopy(item),
                            source = {path = currentPath}
                        }
                    end},
                    {label = "Paste (Ctrl+V)", onClick = function()
                        if not globals.clipboard.data then return end
                        globals.History.captureState("Paste " .. globals.clipboard.type)

                        if globals.clipboard.type == "group" then
                            local groupCopy = globals.Utils.deepCopy(globals.clipboard.data)
                            groupCopy.name = groupCopy.name .. " (Copy)"
                            for _, container in ipairs(groupCopy.containers) do
                                container.id = globals.Utils.generateUUID()
                                container.channelTrackGUIDs = {}
                            end
                            table.insert(items, i + 1, groupCopy)
                        end
                    end, enabled = function() return globals.clipboard.data ~= nil end},
                    {label = "Duplicate (Ctrl+D)", onClick = function()
                        globals.History.captureState("Duplicate group")
                        local groupCopy = globals.Utils.deepCopy(item)
                        groupCopy.name = item.name .. " (Copy)"
                        for _, container in ipairs(groupCopy.containers) do
                            container.id = globals.Utils.generateUUID()
                            container.channelTrackGUIDs = {}
                        end
                        table.insert(items, i + 1, groupCopy)
                    end},
                    {separator = true},
                    {label = "Delete (Del)", onClick = function()
                        itemToDelete = i
                    end}
                }
            })

            -- If group is expanded, render its containers
            if item.expanded then
                local containerToDelete = nil

                for j, container in ipairs(item.containers) do
                    local containerId = itemId .. "_container" .. j
                    local isSelected = isContainerSelected(currentPath, j)

                    -- Prepare display name with regeneration indicator
                    local containerDisplayName = container.name
                    if container.needsRegeneration then
                        containerDisplayName = "• " .. container.name
                    end

                    -- Indent containers visually
                    imgui.Indent(globals.ctx, Constants.UI.CONTAINER_INDENT)

                    -- Get actual available width after indentation
                    local containerAvailWidth = imgui.GetContentRegionAvail(globals.ctx)

                    -- Check if this container should be highlighted (temporary highlight from layer button click)
                    local isHighlighted = false
                    if globals.highlightedContainerUUID and container.id == globals.highlightedContainerUUID then
                        local now = reaper.time_precise()
                        if not globals.highlightStartTime then
                            globals.highlightStartTime = now
                        end
                        local elapsed = now - globals.highlightStartTime
                        if elapsed < 1.0 then
                            isHighlighted = true
                        else
                            globals.highlightedContainerUUID = nil
                            globals.highlightStartTime = nil
                        end
                    end

                    -- Draw container using the helper function
                    drawListItemWithButtons({
                        id = containerId,
                        text = containerDisplayName,
                        isSelected = isSelected or isHighlighted,
                        hasArrow = false,
                        isOpen = false,
                        availableWidth = containerAvailWidth,

                        -- Drag source: containers can be dragged
                        dragSource = {
                            type = "DND_CONTAINER",
                            data = pathStr .. "_" .. j,
                            preview = function()
                                if globals.inMultiSelectMode and isSelected then
                                    local count = UI_Groups.getSelectedContainersCount()
                                    return "📦 " .. count .. " containers"
                                else
                                    return "📦 " .. container.name
                                end
                            end,
                            onStart = function()
                                if globals.inMultiSelectMode and isSelected then
                                    local selectedContainers = {}
                                    for key, _ in pairs(globals.selectedContainers) do
                                        local path, cIdx = globals.Utils.parseContainerKey(key)
                                        if path and cIdx then
                                            table.insert(selectedContainers, {
                                                path = path,
                                                containerIndex = cIdx
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
                                        path = currentPath,
                                        containerIndex = j,
                                        name = container.name
                                    }
                                end
                            end
                        },

                        -- Drop target: containers accept other containers
                        dropTarget = {
                            accept = {"DND_CONTAINER"},
                            allowDropInto = false,
                            onDrop = function(payloadType, dropPosition)
                                if globals.draggedItem and (globals.draggedItem.type == "CONTAINER" or globals.draggedItem.type == "CONTAINER_MULTI") then
                                    local targetIndex
                                    if dropPosition == "before" then
                                        targetIndex = j
                                    else -- "after"
                                        targetIndex = j + 1
                                    end

                                    if globals.draggedItem.type == "CONTAINER_MULTI" then
                                        globals.pendingContainerMultiMove = {
                                            containers = globals.draggedItem.containers,
                                            targetPath = currentPath,
                                            targetContainerIndex = targetIndex
                                        }
                                    else
                                        globals.pendingContainerMove = {
                                            sourcePath = globals.draggedItem.path,
                                            sourceContainerIndex = globals.draggedItem.containerIndex,
                                            targetPath = currentPath,
                                            targetContainerIndex = targetIndex
                                        }
                                    end
                                end
                            end
                        },

                        onSelect = function()
                            local shiftPressed = imgui.GetKeyMods(globals.ctx) & imgui.Mod_Shift ~= 0
                            if ctrlPressed then
                                toggleContainerSelection(currentPath, j)
                                globals.inMultiSelectMode = UI_Groups.getSelectedContainersCount() > 1
                                globals.shiftAnchorPath = currentPath
                                globals.shiftAnchorContainerIndex = j
                                -- Update selection state for UI panel rendering
                                globals.selectedPath = currentPath
                                globals.selectedType = "group"
                                globals.selectedContainerIndex = j
                            elseif shiftPressed and globals.shiftAnchorPath then
                                selectContainerRange(globals.shiftAnchorPath, globals.shiftAnchorContainerIndex, currentPath, j)
                                -- Range selection sets multi-select mode
                                globals.selectedPath = currentPath
                                globals.selectedType = "group"
                                globals.selectedContainerIndex = j
                            else
                                clearContainerSelections()
                                if globals.Waveform then
                                    globals.Waveform.stopPlayback()
                                end
                                toggleContainerSelection(currentPath, j)
                                globals.inMultiSelectMode = false
                                globals.shiftAnchorPath = currentPath
                                globals.shiftAnchorContainerIndex = j
                                -- Update selection state for UI panel rendering
                                globals.selectedPath = currentPath
                                globals.selectedType = "group"
                                globals.selectedContainerIndex = j
                            end
                        end,

                        buttons = {
                            {icon = "X", id = containerId, tooltip = "Delete container", onClick = function()
                                containerToDelete = j
                            end},
                            {icon = "↻", id = containerId, tooltip = "Regenerate container", onClick = function()
                                globals.Generation.generateSingleContainerByPath(currentPath, j)
                            end}
                        },

                        contextMenu = {
                            {label = "Copy (Ctrl+C)", onClick = function()
                                if globals.inMultiSelectMode and isSelected then
                                    local containers = {}
                                    for key in pairs(globals.selectedContainers) do
                                        local path, containerIdx = globals.Utils.parseContainerKey(key)
                                        if path and containerIdx then
                                            local group = globals.Utils.getItemFromPath(path)
                                            if group and group.containers then
                                                local cont = group.containers[containerIdx]
                                                if cont then
                                                    table.insert(containers, globals.Utils.deepCopy(cont))
                                                end
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
                                else
                                    globals.clipboard = {
                                        type = "container",
                                        data = globals.Utils.deepCopy(container),
                                        source = {path = currentPath, containerIndex = j}
                                    }
                                end
                            end},
                            {label = "Paste (Ctrl+V)", onClick = function()
                                if not globals.clipboard.data then return end
                                globals.History.captureState("Paste " .. globals.clipboard.type)

                                if globals.clipboard.type == "container" then
                                    local containerCopy = globals.Utils.deepCopy(globals.clipboard.data)
                                    containerCopy.id = globals.Utils.generateUUID()
                                    containerCopy.name = containerCopy.name .. " (Copy)"
                                    containerCopy.channelTrackGUIDs = {}
                                    table.insert(item.containers, j + 1, containerCopy)
                                    clearContainerSelections()
                                    toggleContainerSelection(currentPath, j + 1)
                                elseif globals.clipboard.type == "containers" then
                                    local insertIndex = j + 1
                                    for idx, cont in ipairs(globals.clipboard.data) do
                                        local containerCopy = globals.Utils.deepCopy(cont)
                                        containerCopy.id = globals.Utils.generateUUID()
                                        containerCopy.name = containerCopy.name .. " (Copy)"
                                        containerCopy.channelTrackGUIDs = {}
                                        table.insert(item.containers, insertIndex + idx - 1, containerCopy)
                                    end
                                    clearContainerSelections()
                                end
                            end, enabled = function() return globals.clipboard.data ~= nil end},
                            {label = "Duplicate (Ctrl+D)", onClick = function()
                                globals.History.captureState("Duplicate container")
                                if globals.inMultiSelectMode and isSelected then
                                    local containersToDuplicate = {}
                                    for key in pairs(globals.selectedContainers) do
                                        local path, containerIdx = globals.Utils.parseContainerKey(key)
                                        if path and containerIdx then
                                            table.insert(containersToDuplicate, {
                                                path = path,
                                                containerIndex = containerIdx
                                            })
                                        end
                                    end
                                    table.sort(containersToDuplicate, function(a, b)
                                        if #a.path == #b.path then
                                            for k = 1, #a.path do
                                                if a.path[k] ~= b.path[k] then
                                                    return a.path[k] > b.path[k]
                                                end
                                            end
                                            return a.containerIndex > b.containerIndex
                                        end
                                        return #a.path > #b.path
                                    end)
                                    for _, entry in ipairs(containersToDuplicate) do
                                        local group = globals.Utils.getItemFromPath(entry.path)
                                        if group and group.containers then
                                            local cont = group.containers[entry.containerIndex]
                                            if cont then
                                                local containerCopy = globals.Utils.deepCopy(cont)
                                                containerCopy.id = globals.Utils.generateUUID()
                                                containerCopy.name = cont.name .. " (Copy)"
                                                containerCopy.channelTrackGUIDs = {}
                                                table.insert(group.containers, entry.containerIndex + 1, containerCopy)
                                            end
                                        end
                                    end
                                    clearContainerSelections()
                                else
                                    local containerCopy = globals.Utils.deepCopy(container)
                                    containerCopy.id = globals.Utils.generateUUID()
                                    containerCopy.name = container.name .. " (Copy)"
                                    containerCopy.channelTrackGUIDs = {}
                                    table.insert(item.containers, j + 1, containerCopy)
                                    clearContainerSelections()
                                    toggleContainerSelection(currentPath, j + 1)
                                end
                            end},
                            {separator = true},
                            {label = "Delete (Del)", onClick = function()
                                containerToDelete = j
                            end}
                        }
                    })

                    imgui.Unindent(globals.ctx, Constants.UI.CONTAINER_INDENT)
                end

                -- Delete the marked container if any
                if containerToDelete then
                    local containerKey = globals.Utils.makeContainerKey(currentPath, containerToDelete)
                    globals.selectedContainers[containerKey] = nil
                    table.remove(item.containers, containerToDelete)

                    if globals.Utils.pathsEqual(globals.selectedPath, currentPath) and globals.selectedContainerIndex == containerToDelete then
                        globals.selectedContainerIndex = nil
                    elseif globals.Utils.pathsEqual(globals.selectedPath, currentPath) and globals.selectedContainerIndex and globals.selectedContainerIndex > containerToDelete then
                        globals.selectedContainerIndex = globals.selectedContainerIndex - 1
                    end

                    -- Update selection indices for containers after the deleted one
                    for k = containerToDelete + 1, #item.containers + 1 do
                        local oldKey = globals.Utils.makeContainerKey(currentPath, k)
                        if globals.selectedContainers[oldKey] then
                            globals.selectedContainers[globals.Utils.makeContainerKey(currentPath, k-1)] = true
                            globals.selectedContainers[oldKey] = nil
                        end
                    end

                    globals.Structures.syncEuclideanBindings(item)
                    globals.History.captureState("Delete container")
                end
            end
        end
    end

    -- Delete the marked item (folder or group) if any
    if itemToDelete then
        -- Remove any selected containers from this item if it's a group
        local deletedItem = items[itemToDelete]
        if deletedItem.type == "group" then
            local pathToDelete = globals.Utils.copyTable(parentPath)
            table.insert(pathToDelete, itemToDelete)
            local pathStr = globals.Utils.pathToString(pathToDelete)

            for key in pairs(globals.selectedContainers) do
                if key:sub(1, #pathStr) == pathStr then
                    globals.selectedContainers[key] = nil
                end
            end
        end

        table.remove(items, itemToDelete)

        -- Update selection if necessary
        local deletedPath = globals.Utils.copyTable(parentPath)
        table.insert(deletedPath, itemToDelete)
        if globals.Utils.pathsEqual(globals.selectedPath, deletedPath) then
            globals.selectedPath = nil
            globals.selectedType = nil
            globals.selectedContainerIndex = nil
        end

        globals.History.captureState("Delete " .. (deletedItem.type or "item"))
    end
end

-- Draw the left panel containing the list of folders, groups, and their containers
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

    -- Add Group and Add Folder buttons at top level
    if imgui.Button(globals.ctx, "Add Group") then
        table.insert(globals.items, globals.Structures.createGroup())
        local newPath = {#globals.items}
        globals.selectedPath = newPath
        globals.selectedType = "group"
        globals.selectedContainerIndex = nil
        clearContainerSelections()
        globals.inMultiSelectMode = false
        globals.shiftAnchorPath = newPath
        globals.shiftAnchorContainerIndex = nil
        globals.History.captureState("Add group")
    end

    imgui.SameLine(globals.ctx)
    if imgui.Button(globals.ctx, "Add Folder") then
        table.insert(globals.items, globals.Structures.createFolder())
        local newPath = {#globals.items}
        globals.selectedPath = newPath
        globals.selectedType = "folder"
        globals.selectedContainerIndex = nil
        clearContainerSelections()
        globals.inMultiSelectMode = false
        globals.History.captureState("Add folder")
    end

    -- Help marker for drag and drop
    imgui.SameLine(globals.ctx)
    globals.Utils.HelpMarker("Drag and drop:\n" ..
        "- Drag folders/groups to reorder or nest them\n" ..
        "- Drag containers to move them within/between groups\n" ..
        "- Drop on folder/group headers to add items inside\n" ..
        "- Use Ctrl+Click and Shift+Click for multi-selection")

    imgui.Separator(globals.ctx)

    -- Render all items recursively
    renderItems(globals.items, {}, 0, width, isContainerSelected, toggleContainerSelection, clearContainerSelections, selectContainerRange)

    -- Update the multi-select mode flag
    globals.inMultiSelectMode = UI_Groups.getSelectedContainersCount() > 1

    -- Process pending folder/group moves
    if globals.pendingFolderMove then
        globals.History.captureState("Move " .. globals.pendingFolderMove.moveType)
        UI_Groups.moveItem(globals.pendingFolderMove.sourcePath, globals.pendingFolderMove.targetPath)
        globals.pendingFolderMove = nil
        globals.draggedItem = nil
    end

    -- Process pending container moves
    if globals.pendingContainerMultiMove then
        globals.History.captureState("Move multiple containers")
        UI_Groups.moveMultipleContainersToGroup(
            globals.pendingContainerMultiMove.containers,
            globals.pendingContainerMultiMove.targetPath,
            globals.pendingContainerMultiMove.targetContainerIndex
        )
        globals.pendingContainerMultiMove = nil
        globals.draggedItem = nil
    end

    if globals.pendingContainerMove then
        globals.History.captureState("Move container")
        UI_Groups.moveContainerToGroup(
            globals.pendingContainerMove.sourcePath,
            globals.pendingContainerMove.sourceContainerIndex,
            globals.pendingContainerMove.targetPath,
            globals.pendingContainerMove.targetContainerIndex
        )
        globals.pendingContainerMove = nil
        globals.draggedItem = nil
    end

    -- Clean up drag state if no drag is active
    if globals.draggedItem and not imgui.IsMouseDown(globals.ctx, imgui.MouseButton_Left) and
       not globals.pendingFolderMove and not globals.pendingContainerMove and not globals.pendingContainerMultiMove then
        globals.draggedItem = nil
    end
end

-- Move an item (folder or group) from source path to target path
-- @param sourcePath table: Path array to source item
-- @param targetPath table: Path array to target location
function UI_Groups.moveItem(sourcePath, targetPath)
    if not sourcePath or #sourcePath == 0 or not targetPath or #targetPath == 0 then
        return
    end

    -- Prevent moving item into itself or its descendants
    if globals.Utils.isPathAncestor(sourcePath, targetPath) then
        return
    end

    -- Extract the item from source
    local sourceParent = globals.items
    local sourceIndex = sourcePath[1]

    for i = 1, #sourcePath - 1 do
        local item = sourceParent[sourcePath[i]]
        if not item then return end
        sourceParent = item.children or item.containers
        sourceIndex = sourcePath[i + 1]
    end

    local movingItem = sourceParent[sourceIndex]
    if not movingItem then return end

    table.remove(sourceParent, sourceIndex)

    -- Insert at target
    local targetParent = globals.items
    local targetIndex = targetPath[#targetPath]

    for i = 1, #targetPath - 1 do
        local item = targetParent[targetPath[i]]
        if not item then
            -- Target path invalid, restore item
            table.insert(sourceParent, sourceIndex, movingItem)
            return
        end
        targetParent = item.children or item.containers
    end

    targetIndex = math.max(1, math.min(targetIndex, #targetParent + 1))
    table.insert(targetParent, targetIndex, movingItem)

    -- Update selection
    if globals.Utils.pathsEqual(globals.selectedPath, sourcePath) then
        globals.selectedPath = targetPath
    end

    clearContainerSelections()
end

-- Move a container from one group to another
-- @param sourcePath table: Path to source group
-- @param sourceContainerIndex number: Container index in source group
-- @param targetPath table: Path to target group
-- @param targetContainerIndex number: Target position in target group
function UI_Groups.moveContainerToGroup(sourcePath, sourceContainerIndex, targetPath, targetContainerIndex)
    local sourceGroup = globals.Utils.getItemFromPath(sourcePath)
    local targetGroup = globals.Utils.getItemFromPath(targetPath)

    if not sourceGroup or not sourceGroup.containers or not targetGroup or not targetGroup.containers then
        return
    end

    if sourceContainerIndex < 1 or sourceContainerIndex > #sourceGroup.containers then
        return
    end

    local movingContainer = sourceGroup.containers[sourceContainerIndex]
    table.remove(sourceGroup.containers, sourceContainerIndex)

    local insertIndex = targetContainerIndex or (#targetGroup.containers + 1)
    insertIndex = math.max(1, math.min(insertIndex, #targetGroup.containers + 1))
    table.insert(targetGroup.containers, insertIndex, movingContainer)

    -- Update selections
    local sourceKey = globals.Utils.makeContainerKey(sourcePath, sourceContainerIndex)
    if globals.selectedContainers[sourceKey] then
        globals.selectedContainers[sourceKey] = nil
        globals.selectedContainers[globals.Utils.makeContainerKey(targetPath, insertIndex)] = true
    end

    if globals.Utils.pathsEqual(globals.selectedPath, sourcePath) and globals.selectedContainerIndex == sourceContainerIndex then
        globals.selectedPath = targetPath
        globals.selectedContainerIndex = insertIndex
    end

    globals.Structures.syncEuclideanBindings(sourceGroup)
    globals.Structures.syncEuclideanBindings(targetGroup)

    globals.Utils.reorganizeTracksAfterContainerMove(sourcePath, targetPath, movingContainer.name)
end

-- Move multiple containers to a target group
-- @param containers table: Array of {path, containerIndex}
-- @param targetPath table: Path to target group
-- @param targetContainerIndex number: Target position
function UI_Groups.moveMultipleContainersToGroup(containers, targetPath, targetContainerIndex)
    if not containers or #containers == 0 then return end

    -- Sort containers for safe removal (reverse order)
    table.sort(containers, function(a, b)
        if #a.path == #b.path then
            for i = 1, #a.path do
                if a.path[i] ~= b.path[i] then
                    return a.path[i] > b.path[i]
                end
            end
            return a.containerIndex > b.containerIndex
        end
        return #a.path > #b.path
    end)

    -- Extract all containers first
    local movedContainers = {}
    for _, item in ipairs(containers) do
        local group = globals.Utils.getItemFromPath(item.path)
        if group and group.containers and item.containerIndex >= 1 and item.containerIndex <= #group.containers then
            local container = group.containers[item.containerIndex]
            table.insert(movedContainers, 1, container)
            table.remove(group.containers, item.containerIndex)
        end
    end

    -- Insert all containers at target position
    local targetGroup = globals.Utils.getItemFromPath(targetPath)
    if targetGroup and targetGroup.containers then
        local insertIndex = math.max(1, math.min(targetContainerIndex, #targetGroup.containers + 1))
        for _, container in ipairs(movedContainers) do
            table.insert(targetGroup.containers, insertIndex, container)
            insertIndex = insertIndex + 1
        end
    end

    -- Clear selection
    globals.selectedContainers = {}
    globals.inMultiSelectMode = false
    globals.selectedContainerIndex = nil

    -- Sync euclidean bindings for all affected groups
    local affectedGroups = {}
    for _, item in ipairs(containers) do
        local pathStr = globals.Utils.pathToString(item.path)
        affectedGroups[pathStr] = item.path
    end
    affectedGroups[globals.Utils.pathToString(targetPath)] = targetPath

    for _, path in pairs(affectedGroups) do
        local group = globals.Utils.getItemFromPath(path)
        if group then
            globals.Structures.syncEuclideanBindings(group)
        end
    end

    -- Trigger track reorganization
    for _, item in ipairs(containers) do
        globals.Utils.reorganizeTracksAfterContainerMove(item.path, targetPath, "multiple containers")
        break
    end
end

-- Return the number of selected containers
function UI_Groups.getSelectedContainersCount()
    local count = 0
    for _ in pairs(globals.selectedContainers) do
        count = count + 1
    end
    return count
end

-- Display group preset controls (load/save) for a specific group path
-- @param groupPath table: Path array to the group
function UI_Groups.drawGroupPresetControls(groupPath)
    if not groupPath or #groupPath == 0 then
        error("UI_Groups.drawGroupPresetControls: valid group path is required")
    end

    local pathStr = globals.Utils.pathToString(groupPath)
    local groupId = "group" .. pathStr

    -- Initialize selected preset index for this group if not already set
    if not globals.selectedGroupPresetIndex[pathStr] then
        globals.selectedGroupPresetIndex[pathStr] = -1
    end

    -- Initialize search query for this group if not already set
    if not globals.groupPresetSearchQuery then
        globals.groupPresetSearchQuery = {}
    end
    if not globals.groupPresetSearchQuery[pathStr] then
        globals.groupPresetSearchQuery[pathStr] = ""
    end

    -- Get the list of available group presets
    local groupPresetList = globals.Presets.listPresets("Groups")

    -- Use searchable combo box
    local changed, newIndex, newSearchQuery = globals.Utils.searchableCombo(
        "##GroupPresetSelector" .. groupId,
        globals.selectedGroupPresetIndex[pathStr],
        groupPresetList,
        globals.groupPresetSearchQuery[pathStr],
        Constants.UI.PRESET_SELECTOR_WIDTH
    )

    if changed then
        globals.selectedGroupPresetIndex[pathStr] = newIndex
    end

    globals.groupPresetSearchQuery[pathStr] = newSearchQuery

    -- Load preset button
    imgui.SameLine(globals.ctx)
    if globals.Icons.createDownloadButton(globals.ctx, "loadGroup" .. groupId, "Load group preset")
        and globals.selectedGroupPresetIndex[pathStr] >= 0
        and globals.selectedGroupPresetIndex[pathStr] < #groupPresetList then
        local presetName = groupPresetList[globals.selectedGroupPresetIndex[pathStr] + 1]
        globals.Presets.loadGroupPresetByPath(presetName, groupPath)
    end

    -- Save preset button
    imgui.SameLine(globals.ctx)
    if globals.Icons.createUploadButton(globals.ctx, "saveGroup" .. groupId, "Save group preset") then
        if not globals.Utils.isMediaDirectoryConfigured() then
            globals.showMediaDirWarning = true
        else
            local group = globals.Utils.getItemFromPath(groupPath)
            if group then
                globals.newGroupPresetName = group.name
                globals.currentSaveGroupPath = groupPath
                globals.Utils.safeOpenPopup("Save Group Preset##" .. groupId)
            end
        end
    end

    -- Popup dialog for saving the group as a preset
    if imgui.BeginPopupModal(globals.ctx, "Save Group Preset##" .. groupId, nil, imgui.WindowFlags_AlwaysAutoResize) then
        imgui.Text(globals.ctx, "Group preset name:")
        local rv, value = imgui.InputText(globals.ctx, "##GroupPresetName" .. groupId, globals.newGroupPresetName)
        if rv then globals.newGroupPresetName = value end
        if imgui.Button(globals.ctx, "Save", Constants.UI.BUTTON_WIDTH_STANDARD, 0) and globals.newGroupPresetName ~= "" then
            if globals.Presets.saveGroupPresetByPath(globals.newGroupPresetName, globals.currentSaveGroupPath) then
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

return UI_Groups
