--[[
@version 1.3
@noindex
--]]

local UI_Generation = {}
local globals = {}
local Utils = require("DM_Ambiance_Utils")
local Items = require("DM_Ambiance_Items")

-- Initialize the module with global variables from the main script
function UI_Generation.initModule(g)
    globals = g
end

-- Function to draw the main generation button with styling
function UI_Generation.drawMainGenerationButton()
    -- Apply styling for the main generation button
    imgui.PushStyleColor(globals.ctx, imgui.Col_Button, 0xFF4CAF50) -- Green button
    imgui.PushStyleColor(globals.ctx, imgui.Col_ButtonHovered, 0xFF66BB6A) -- Lighter green when hovered
    imgui.PushStyleColor(globals.ctx, imgui.Col_ButtonActive, 0xFF43A047) -- Darker green when clicked
    
    local buttonPressed = imgui.Button(globals.ctx, "Create Ambiance", 150, 30)
    
    -- Pop styling colors to return to default
    imgui.PopStyleColor(globals.ctx, 3)
    
    -- Execute generation if button was pressed
    if buttonPressed then
        globals.Generation.generateGroups()
    end
    
    return buttonPressed
end

function UI_Generation.drawKeepExistingTracksButton()
    local changed, newValue = imgui.Checkbox(globals.ctx, "Keep existing tracks", globals.keepExistingTracks)
    
    if changed then
        globals.keepExistingTracks = newValue
    end

    Utils.HelpMarker("Determines clearing behavior before generation:\n" ..
                    "- Enabled (Keep):\n" ..
                    "Preserve tracks and content outside time selection, only replace content within selection\n\n" ..
                    "- Disabled (Clear All):\n" ..
                    "Clear all existing tracks and content from tracks before generating new content")

    return changed
end

-- Function to display time selection information
function UI_Generation.drawTimeSelectionInfo()
    if globals.Utils.checkTimeSelection() then
        imgui.Text(globals.ctx, "Time Selection: " .. globals.Utils.formatTime(globals.startTime) .. 
                                       " - " .. globals.Utils.formatTime(globals.endTime) .. 
                                       " | Length: " .. globals.Utils.formatTime(globals.endTime - globals.startTime))
    else
        imgui.TextColored(globals.ctx, 0xFF0000FF, "No time selection! Please create one.")
    end
end

-- Function to draw regenerate button for a group
function UI_Generation.drawGroupRegenerateButton(groupIndex)
    local groupId = "group" .. groupIndex
    if globals.Icons.createRegenButton(globals.ctx, groupId, "Regenerate group") then
        globals.Generation.generateSingleGroup(groupIndex)
        return true
    end
    return false
end

-- Function to draw regenerate button for a container
function UI_Generation.drawContainerRegenerateButton(groupIndex, containerIndex)
    local groupId = "group" .. groupIndex
    local containerId = groupId .. "_container" .. containerIndex
    if globals.Icons.createRegenButton(globals.ctx, containerId, "Regenerate container") then
        globals.Generation.generateSingleContainer(groupIndex, containerIndex)
        return true
    end
    return false
end

-- Function to draw regenerate button for multiple selected containers
function UI_Generation.drawMultiRegenerateButton(width)
    -- Get list of all selected containers
    local selectedContainers = {}
    for key in pairs(globals.selectedContainers) do
        local t, c = key:match("(%d+)_(%d+)")
        table.insert(selectedContainers, {groupIndex = tonumber(t), containerIndex = tonumber(c)})
    end
    
    if imgui.Button(globals.ctx, "Regenerate All", width * 0.5, 30) then
        for _, c in ipairs(selectedContainers) do
            globals.Generation.generateSingleContainer(c.groupIndex, c.containerIndex)
        end
        return true
    end
    return false
end

-- Function to display UI controls for global generation settings
function UI_Generation.drawGlobalGenerationSettings()
    if not imgui.CollapsingHeader(globals.ctx, "Generation Settings") then
        return
    end
    
    imgui.Indent(globals.ctx, 10)
    
    -- Global cross-fade settings
    local rv, newCrossfadeEnabled = imgui.Checkbox(globals.ctx, "Enable automatic crossfades", globals.enableCrossfades)
    if rv then globals.enableCrossfades = newCrossfadeEnabled end
    
    if globals.enableCrossfades then
        imgui.PushItemWidth(globals.ctx, 200)
        local crossfadeShapes = "Linear\0Slow start/end\0Fast start\0Fast end\0Sharp\0\0"
        local rv, newShape = imgui.Combo(globals.ctx, "Crossfade shape", globals.crossfadeShape, crossfadeShapes)
        if rv then globals.crossfadeShape = newShape end
    end
    
    -- Random seed control
    imgui.Separator(globals.ctx)
    local rv, newUseSeed = imgui.Checkbox(globals.ctx, "Use fixed seed", globals.useRandomSeed)
    if rv then globals.useRandomSeed = newUseSeed end
    
    if globals.useRandomSeed then
        imgui.PushItemWidth(globals.ctx, 200)
        local rv, newSeed = imgui.InputInt(globals.ctx, "Random seed", globals.randomSeed)
        if rv then globals.randomSeed = newSeed end
    end
    
    imgui.Unindent(globals.ctx, 10)
end

return UI_Generation
