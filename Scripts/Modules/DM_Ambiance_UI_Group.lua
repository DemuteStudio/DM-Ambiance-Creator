--[[
@version 1.5
@noindex
--]]

local UI_Group = {}
local globals = {}
local Constants = require("DM_Ambiance_Constants")

-- Initialize the module with global variables from the main script
function UI_Group.initModule(g)
    if not g then
        error("UI_Group.initModule: globals parameter is required")
    end
    globals = g
end

-- Function to display group randomization settings in the right panel
function UI_Group.displayGroupSettings(groupIndex, width)
    local group = globals.groups[groupIndex]
    local groupId = "group" .. groupIndex
    
    -- Sync group volume from track
    globals.Utils.syncGroupVolumeFromTrack(groupIndex)
    
    -- Panel title showing which group is being edited
    imgui.Text(globals.ctx, "Group Settings: " .. group.name)
    imgui.Separator(globals.ctx)
    
    -- Group name input field
    local groupName = group.name
    imgui.PushItemWidth(globals.ctx, width * 0.5)
    local rv, newGroupName = imgui.InputText(globals.ctx, "Name##detail_" .. groupId, groupName)
    if rv and newGroupName ~= groupName then
        globals.History.captureState("Rename group")
        group.name = newGroupName
    end
    
    -- Group track volume slider
    imgui.Text(globals.ctx, "Track Volume")
    imgui.SameLine(globals.ctx)
    globals.Utils.HelpMarker("Controls the volume of the group's track in Reaper. Affects all containers in this group.")
    
    imgui.PushItemWidth(globals.ctx, width * 0.6)
    
    -- Ensure trackVolume is initialized
    if group.trackVolume == nil then
        group.trackVolume = Constants.DEFAULTS.CONTAINER_VOLUME_DEFAULT
    end
    
    -- Convert current dB to normalized
    local normalizedVolume = globals.Utils.dbToNormalizedRelative(group.trackVolume)
    
    local rv, newNormalizedVolume = imgui.SliderDouble(
        globals.ctx, 
        "##GroupTrackVolume_" .. groupId, 
        normalizedVolume, 
        0.0,  -- Min normalized
        1.0,  -- Max normalized
        ""    -- No format, we'll display custom text
    )
    if rv then 
        local newVolumeDB = globals.Utils.normalizedToDbRelative(newNormalizedVolume)
        group.trackVolume = newVolumeDB
        -- Apply volume to track in real-time
        globals.Utils.setGroupTrackVolume(groupIndex, newVolumeDB)
    end
    
    -- Manual dB input field
    imgui.SameLine(globals.ctx)
    imgui.PushItemWidth(globals.ctx, 65)
    local displayValue = group.trackVolume <= -144 and -144 or group.trackVolume
    local rv2, manualDB = imgui.InputDouble(
        globals.ctx,
        "##GroupTrackVolumeInput_" .. groupId,
        displayValue,
        0, 0,  -- step, step_fast (not used)
        "%.1f dB"
    )
    if rv2 then
        -- Clamp to valid range
        manualDB = math.max(Constants.AUDIO.VOLUME_RANGE_DB_MIN, 
                           math.min(Constants.AUDIO.VOLUME_RANGE_DB_MAX, manualDB))
        group.trackVolume = manualDB
        globals.Utils.setGroupTrackVolume(groupIndex, manualDB)
    end
    imgui.PopItemWidth(globals.ctx)
    
    -- Group preset controls
    globals.UI_Groups.drawGroupPresetControls(groupIndex)
    
    -- TRIGGER SETTINGS SECTION
    globals.UI.displayTriggerSettings(group, groupId, width, true, groupIndex, nil)
end

return UI_Group
