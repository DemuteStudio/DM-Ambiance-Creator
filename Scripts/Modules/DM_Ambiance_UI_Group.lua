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
function UI_Group.displayGroupSettings(groupPath, width)
    -- Get group using path-based system
    local group = globals.Structures.getItemFromPath(groupPath)
    if not group then
        return -- Group not found
    end

    local groupId = "group" .. globals.Utils.pathToString(groupPath)

    -- Sync group volume, name, mute, and solo from track
    globals.Utils.syncGroupVolumeFromTrack(groupPath)
    globals.Utils.syncGroupNameFromTrack(groupPath)
    globals.Utils.syncGroupMuteFromTrack(groupPath)
    globals.Utils.syncGroupSoloFromTrack(groupPath)

    -- Panel title showing which group is being edited
    imgui.Text(globals.ctx, "Group Settings: " .. group.name)
    imgui.Separator(globals.ctx)
    
    -- Group name input field
    imgui.PushItemWidth(globals.ctx, width * 0.5)
    local rv, newGroupName = globals.UndoWrappers.InputText(globals.ctx, "Name##detail_" .. groupId, group.name)
    if rv then
        group.name = newGroupName
        -- Update track name in REAPER in real-time
        globals.Utils.setGroupTrackName(groupPath, newGroupName)
    end
    
    -- Group track volume slider
    imgui.Text(globals.ctx, "Group Volume")
    imgui.SameLine(globals.ctx)
    globals.Utils.HelpMarker("Controls the volume of the group's track in Reaper. Affects all containers in this group.")

    -- Use the shared VolumeControls widget
    globals.UI_VolumeControls.draw({
        id = "Group_" .. groupId,
        item = group,
        onVolumeChange = function(newVolumeDB)
            globals.Utils.setGroupTrackVolume(groupPath, newVolumeDB)
        end,
        onMuteChange = function(isMuted)
            if isMuted and group.isSoloed then
                group.isSoloed = false
                globals.Utils.setGroupTrackSolo(groupPath, false)
            end
            globals.Utils.setGroupTrackMute(groupPath, isMuted)
        end,
        onSoloChange = function(isSoloed)
            if isSoloed and group.isMuted then
                group.isMuted = false
                globals.Utils.setGroupTrackMute(groupPath, false)
            end
            globals.Utils.setGroupTrackSolo(groupPath, isSoloed)
        end
    })
    
    -- Group preset controls
    globals.UI_Groups.drawGroupPresetControls(groupPath)

    -- TRIGGER SETTINGS SECTION
    globals.UI.displayTriggerSettings(group, groupId, width, true, groupPath, nil)
end

return UI_Group
