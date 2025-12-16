--[[
@version 1.0
@noindex
--]]

-- RegenManager - Centralized regeneration system
-- Handles all automatic regeneration of groups and containers based on needsRegeneration flags

local RegenManager = {}
local globals = {}

-- Throttling: track what was regenerated this frame to avoid duplicates
local regeneratedThisFrame = {}
local lastFrameTime = 0

-- Helper function to recursively collect all groups from items structure
-- @param items table: Array of items (folders/groups)
-- @param groups table: Array to collect groups into (modified in-place)
local function collectAllGroups(items, groups)
    for _, item in ipairs(items) do
        if item.type == "group" then
            table.insert(groups, item)
        elseif item.type == "folder" and item.children then
            collectAllGroups(item.children, groups)
        end
    end
end

-- Helper function to find the path to a group in the items structure
-- @param items table: Array of items to search
-- @param targetGroup table: The group object to find
-- @param currentPath table: Current path being built (for recursion)
-- @return table|nil: Path array (indices) to the group, or nil if not found
local function findGroupPath(items, targetGroup, currentPath)
    for i, item in ipairs(items) do
        local newPath = {}
        for _, v in ipairs(currentPath) do table.insert(newPath, v) end
        table.insert(newPath, i)

        if item == targetGroup then
            return newPath
        end

        if item.type == "folder" and item.children then
            local path = findGroupPath(item.children, targetGroup, newPath)
            if path then
                return path
            end
        end
    end
    return nil
end

-- Initialize the module with global variables
function RegenManager.initModule(g)
    globals = g
end

-- Check all groups and containers for regeneration needs and execute
-- This should be called once per frame in the main loop
function RegenManager.checkAndRegenerate()
    if not globals.timeSelectionValid then
        -- No time selection, skip regeneration
        return
    end

    -- Collect all groups from globals.items (recursive for folders)
    local allGroups = {}
    if globals.items then
        collectAllGroups(globals.items, allGroups)
    end

    -- Get current time for throttling
    local currentTime = reaper.time_precise()

    -- Reset throttle map if enough time has passed (0.025 second minimum between regenerations)
    if currentTime - lastFrameTime > 0.025 then
        regeneratedThisFrame = {}
        lastFrameTime = currentTime
    end

    -- Iterate through all groups
    for groupIndex, group in ipairs(allGroups) do
        -- Create unique key using group object address (since index in flat array isn't stable)
        local groupKey = "group_" .. tostring(group)

        -- Check if entire group needs regeneration
        if group.needsRegeneration and not regeneratedThisFrame[groupKey] then
            -- Find path to this group in globals.items
            local groupPath = findGroupPath(globals.items or {}, group, {})
            if groupPath then
                -- Regenerate entire group using path (new system)
                globals.Generation.generateSingleGroupByPath(groupPath)
                -- Mark as regenerated
                regeneratedThisFrame[groupKey] = true
                -- Clear the flag
                group.needsRegeneration = false

                -- Also clear all container flags in this group since they were all regenerated
                for containerIndex, container in ipairs(group.containers) do
                    container.needsRegeneration = false
                    local containerKey = "container_" .. tostring(group) .. "_" .. containerIndex
                    regeneratedThisFrame[containerKey] = true
                end
            end
        else
            -- Group doesn't need regen, check individual containers
            for containerIndex, container in ipairs(group.containers) do
                local containerKey = "container_" .. tostring(group) .. "_" .. containerIndex

                if container.needsRegeneration and not regeneratedThisFrame[containerKey] then
                    -- Find path to this group in globals.items
                    local groupPath = findGroupPath(globals.items or {}, group, {})
                    if groupPath then
                        -- Regenerate only this container using path
                        globals.Generation.generateSingleContainerByPath(groupPath, containerIndex)
                        -- Mark as regenerated
                        regeneratedThisFrame[containerKey] = true
                        -- Clear the flag
                        container.needsRegeneration = false
                    end
                end
            end
        end
    end
end

return RegenManager
