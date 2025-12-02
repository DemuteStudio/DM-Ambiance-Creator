--[[
@version 1.5
@noindex
DM Ambiance Creator - Core Utilities Module
Extracted from DM_Ambiance_Utils.lua for better modularity

This module contains essential utilities (deepCopy, UUID, table helpers, path navigation).
--]]

local Utils_Core = {}

-- Module globals (set by initModule)
local globals = {}

-- Initialize the module with global references from the main script
function Utils_Core.initModule(g)
    if not g then
        error("Utils_Core.initModule: globals parameter is required")
    end
    globals = g
end

-- Generate a simple UUID for stable container identification
-- Format: timestamp-random (e.g., "1704123456-a3f9")
-- @return string: UUID string
function Utils_Core.generateUUID()
    local timestamp = os.time()
    local random = math.random(0, 0xFFFF)
    return string.format("%d-%04x", timestamp, random)
end

-- Deep copy function to create independent copies of tables
-- Recursively copies all nested tables and preserves metatables
-- @param orig any: The value to copy (table, number, string, boolean, etc.)
-- @return any: A deep copy of the original value
function Utils_Core.deepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[Utils_Core.deepCopy(orig_key)] = Utils_Core.deepCopy(orig_value)
        end
        setmetatable(copy, Utils_Core.deepCopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

-- Alias for deepCopy (for consistency with other codebases)
Utils_Core.copyTable = Utils_Core.deepCopy

-- ===================================================================
-- PATH-BASED NAVIGATION FOR RECURSIVE FOLDER STRUCTURE
-- ===================================================================

-- Get an item from globals.items using a path array
-- Path format: {1, 2, 3} means items[1].children[2].containers[3]
-- @param path table: Array of indices
-- @return any, string: Item and its type, or nil if not found
function Utils_Core.getItemFromPath(path)
    if not path or #path == 0 then
        return nil, nil
    end

    local current = globals.items
    local currentType = nil

    for i = 1, #path do
        local index = path[i]

        if not current or not current[index] then
            return nil, nil
        end

        local item = current[index]

        if i == #path then
            -- Last element in path - return the item and its type
            currentType = item.type
            return item, currentType
        end

        -- Navigate deeper based on item type
        if item.type == "folder" then
            current = item.children
        elseif item.type == "group" then
            current = item.containers
        else
            -- Reached a container or unknown type - can't navigate further
            return nil, nil
        end
    end

    return nil, nil
end

-- Get the parent item from a path
-- @param path table: Array of indices
-- @return any, string, table: Parent item, parent type, parent path
function Utils_Core.getParentFromPath(path)
    if not path or #path <= 1 then
        return nil, nil, nil
    end

    local parentPath = {}
    for i = 1, #path - 1 do
        parentPath[i] = path[i]
    end

    local parent, parentType = Utils_Core.getItemFromPath(parentPath)
    return parent, parentType, parentPath
end

-- Compare two paths for equality
-- @param p1 table: First path
-- @param p2 table: Second path
-- @return boolean: true if paths are equal
function Utils_Core.pathsEqual(p1, p2)
    if not p1 or not p2 then
        return p1 == p2
    end

    if #p1 ~= #p2 then
        return false
    end

    for i = 1, #p1 do
        if p1[i] ~= p2[i] then
            return false
        end
    end

    return true
end

-- Deep copy a path
-- @param path table: Path to copy
-- @return table: Copied path
function Utils_Core.copyPath(path)
    if not path then
        return nil
    end

    local copy = {}
    for i = 1, #path do
        copy[i] = path[i]
    end
    return copy
end

-- Remove an item at a given path and return it
-- @param path table: Path to the item to remove
-- @return any: The removed item, or nil if not found
function Utils_Core.removeItemAtPath(path)
    if not path or #path == 0 then
        return nil
    end

    local parent, parentType, parentPath = Utils_Core.getParentFromPath(path)
    local index = path[#path]

    if not parent then
        -- Removing from root level
        local item = globals.items[index]
        table.remove(globals.items, index)
        return item
    end

    -- Remove from parent's children or containers
    local collection = nil
    if parentType == "folder" then
        collection = parent.children
    elseif parentType == "group" then
        collection = parent.containers
    end

    if collection and collection[index] then
        local item = collection[index]
        table.remove(collection, index)
        return item
    end

    return nil
end

-- Insert an item at a given path (after the item at that path)
-- @param path table: Path where to insert (inserts after this position)
-- @param item any: Item to insert
-- @return boolean: true if successful
function Utils_Core.insertItemAtPath(path, item)
    if not path or #path == 0 then
        -- Insert at root level
        table.insert(globals.items, item)
        return true
    end

    local parent, parentType, parentPath = Utils_Core.getParentFromPath(path)
    local index = path[#path]

    if not parent then
        -- Insert at root level
        table.insert(globals.items, index + 1, item)
        return true
    end

    -- Insert into parent's children or containers
    local collection = nil
    if parentType == "folder" then
        collection = parent.children
    elseif parentType == "group" then
        collection = parent.containers
    end

    if collection then
        table.insert(collection, index + 1, item)
        return true
    end

    return false
end

-- Get the collection (array) that contains the item at a path
-- @param path table: Path to the item
-- @return table, number: The collection and the index within it
function Utils_Core.getCollectionFromPath(path)
    if not path or #path == 0 then
        return nil, nil
    end

    if #path == 1 then
        -- Top-level item
        return globals.items, path[1]
    end

    local parent, parentType = Utils_Core.getParentFromPath(path)
    local index = path[#path]

    if not parent then
        return nil, nil
    end

    if parentType == "folder" then
        return parent.children, index
    elseif parentType == "group" then
        return parent.containers, index
    end

    return nil, nil
end

return Utils_Core
