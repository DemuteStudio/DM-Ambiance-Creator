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

    -- Get current time for throttling
    local currentTime = reaper.time_precise()

    -- Reset throttle map if enough time has passed (0.1 second minimum between regenerations)
    if currentTime - lastFrameTime > 0.1 then
        regeneratedThisFrame = {}
        lastFrameTime = currentTime
    end

    -- Iterate through all groups
    for groupIndex, group in ipairs(globals.groups) do
        local groupKey = "group_" .. groupIndex

        -- Check if the group exists in the REAPER project (prerequisite for regeneration)
        local existingGroup = globals.Utils.findGroupByName(group.name)

        if existingGroup then
            -- Group exists in project, proceed with regeneration checks

            -- Check if entire group needs regeneration
            if group.needsRegeneration and not regeneratedThisFrame[groupKey] then
                -- Regenerate entire group
                globals.Generation.generateSingleGroup(groupIndex)
                -- Mark as regenerated
                regeneratedThisFrame[groupKey] = true
                -- Clear the flag
                group.needsRegeneration = false

                -- Also clear all container flags in this group since they were all regenerated
                for containerIndex, container in ipairs(group.containers) do
                    container.needsRegeneration = false
                    regeneratedThisFrame["container_" .. groupIndex .. "_" .. containerIndex] = true
                end
            else
                -- Group doesn't need regen, check individual containers
                for containerIndex, container in ipairs(group.containers) do
                    local containerKey = "container_" .. groupIndex .. "_" .. containerIndex

                    if container.needsRegeneration and not regeneratedThisFrame[containerKey] then
                        -- Regenerate only this container
                        globals.Generation.generateSingleContainer(groupIndex, containerIndex)
                        -- Mark as regenerated
                        regeneratedThisFrame[containerKey] = true
                        -- Clear the flag
                        container.needsRegeneration = false
                    end
                end
            end
        else
            -- Group doesn't exist in project yet, clear all regeneration flags without generating
            if group.needsRegeneration then
                group.needsRegeneration = false
            end
            for containerIndex, container in ipairs(group.containers) do
                if container.needsRegeneration then
                    container.needsRegeneration = false
                end
            end
        end
    end
end

return RegenManager
