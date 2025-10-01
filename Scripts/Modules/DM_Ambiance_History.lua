--[[
@version 1.0
@noindex
@description History management module for Undo/Redo functionality
--]]

local History = {}
local globals = {}

-- History stacks
local historyStack = {}      -- Array of historical states
local historyIndex = 0        -- Current position in history (0 = no history)
local maxHistorySize = 50     -- Maximum number of undo states to keep

-- Initialize the module with global variables from the main script
function History.initModule(g)
    if not g then
        error("History.initModule: globals parameter is required")
    end
    globals = g

    -- Reset history on initialization
    historyStack = {}
    historyIndex = 0
end

-- Deep copy function to create independent state snapshots
local function deepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepCopy(orig_key)] = deepCopy(orig_value)
        end
        setmetatable(copy, deepCopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-- Capture the current state and add it to the history stack
-- @param description string: Optional description of the action (for debugging)
function History.captureState(description)
    -- Create a deep copy of the current groups state
    local snapshot = {
        groups = deepCopy(globals.groups),
        timestamp = reaper.time_precise(),
        description = description or "Unnamed action"
    }

    -- If we're not at the end of history, remove all states after current position
    -- (this happens when user does: action -> undo -> new action)
    if historyIndex < #historyStack then
        for i = #historyStack, historyIndex + 1, -1 do
            table.remove(historyStack, i)
        end
    end

    -- Add the new snapshot to history
    table.insert(historyStack, snapshot)
    historyIndex = #historyStack

    -- Enforce maximum history size (remove oldest entries)
    while #historyStack > maxHistorySize do
        table.remove(historyStack, 1)
        historyIndex = historyIndex - 1
    end

    -- Debug logging (can be enabled for debugging)
    -- reaper.ShowConsoleMsg(string.format("[History] Captured: %s (Index: %d, Stack: %d)\n",
    --     description or "Unnamed", historyIndex, #historyStack))
end

-- Restore a state from history
local function restoreState(snapshot)
    if not snapshot or not snapshot.groups then
        return false
    end

    -- Save current selection before restoring
    local savedSelectedGroupIndex = globals.selectedGroupIndex
    local savedSelectedContainerIndex = globals.selectedContainerIndex
    local savedSelectedContainers = {}
    for k, v in pairs(globals.selectedContainers) do
        savedSelectedContainers[k] = v
    end

    -- Restore the groups state
    globals.groups = deepCopy(snapshot.groups)

    -- Apply track volumes to REAPER tracks after restoration
    if globals.Utils then
        for groupIndex, group in ipairs(globals.groups) do
            -- Apply group track volume if it exists
            if group.trackVolume then
                globals.Utils.setGroupTrackVolume(groupIndex, group.trackVolume)
            end

            -- Apply container track volumes if they exist
            if group.containers then
                for containerIndex, container in ipairs(group.containers) do
                    if container.trackVolume then
                        globals.Utils.setContainerTrackVolume(groupIndex, containerIndex, container.trackVolume)
                    end
                end
            end
        end
    end

    -- Restore selection if indices are still valid
    if savedSelectedGroupIndex and savedSelectedGroupIndex <= #globals.groups then
        globals.selectedGroupIndex = savedSelectedGroupIndex

        -- Check if container index is still valid
        if savedSelectedContainerIndex and
           globals.groups[savedSelectedGroupIndex] and
           savedSelectedContainerIndex <= #globals.groups[savedSelectedGroupIndex].containers then
            globals.selectedContainerIndex = savedSelectedContainerIndex
        else
            globals.selectedContainerIndex = nil
        end
    else
        globals.selectedGroupIndex = nil
        globals.selectedContainerIndex = nil
    end

    -- Restore multi-selection (validate each entry)
    globals.selectedContainers = {}
    for key, value in pairs(savedSelectedContainers) do
        local groupIdx, containerIdx = key:match("(%d+)_(%d+)")
        if groupIdx and containerIdx then
            groupIdx = tonumber(groupIdx)
            containerIdx = tonumber(containerIdx)
            -- Only restore if indices are still valid
            if groupIdx <= #globals.groups and
               globals.groups[groupIdx] and
               containerIdx <= #globals.groups[groupIdx].containers then
                globals.selectedContainers[key] = value
            end
        end
    end

    -- Update multi-select mode based on restored selection
    globals.inMultiSelectMode = false
    for _ in pairs(globals.selectedContainers) do
        globals.inMultiSelectMode = true
        break
    end

    -- Debug logging (can be enabled for debugging)
    -- reaper.ShowConsoleMsg(string.format("[History] Restored: %s\n", snapshot.description or "Unnamed"))

    return true
end

-- Undo the last action
-- @return boolean: true if undo was successful, false if no undo available
function History.undo()
    if not History.canUndo() then
        return false
    end

    -- Move back in history
    historyIndex = historyIndex - 1

    -- Restore the state at this position
    local snapshot = historyStack[historyIndex]
    return restoreState(snapshot)
end

-- Redo the previously undone action
-- @return boolean: true if redo was successful, false if no redo available
function History.redo()
    if not History.canRedo() then
        return false
    end

    -- Move forward in history
    historyIndex = historyIndex + 1

    -- Restore the state at this position
    local snapshot = historyStack[historyIndex]
    return restoreState(snapshot)
end

-- Check if undo is available
-- @return boolean: true if there are states to undo
function History.canUndo()
    return historyIndex > 1  -- We need at least 2 states to undo (current + previous)
end

-- Check if redo is available
-- @return boolean: true if there are states to redo
function History.canRedo()
    return historyIndex < #historyStack
end

-- Get current history information (for debugging/UI)
-- @return table: {index, stackSize, canUndo, canRedo}
function History.getInfo()
    return {
        index = historyIndex,
        stackSize = #historyStack,
        canUndo = History.canUndo(),
        canRedo = History.canRedo(),
        currentDescription = historyStack[historyIndex] and historyStack[historyIndex].description or "None"
    }
end

-- Clear all history (useful when loading presets)
function History.clear()
    historyStack = {}
    historyIndex = 0
    -- reaper.ShowConsoleMsg("[History] Cleared all history\n")
end

-- Set maximum history size
-- @param size number: Maximum number of undo states (default: 50)
function History.setMaxSize(size)
    if size and size > 0 then
        maxHistorySize = size

        -- Trim history if new size is smaller
        while #historyStack > maxHistorySize do
            table.remove(historyStack, 1)
            historyIndex = math.max(0, historyIndex - 1)
        end
    end
end

return History
