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
    imgui.PushItemWidth(globals.ctx, width * 0.5)
    local rv, newGroupName = globals.UndoWrappers.InputText(globals.ctx, "Name##detail_" .. groupId, group.name)
    if rv then
        group.name = newGroupName
    end
    
    -- Group track volume slider
    imgui.Text(globals.ctx, "Group Volume")
    imgui.SameLine(globals.ctx)
    globals.Utils.HelpMarker("Controls the volume of the group's track in Reaper. Affects all containers in this group.")

    -- Ensure trackVolume is initialized
    if group.trackVolume == nil then
        group.trackVolume = Constants.DEFAULTS.CONTAINER_VOLUME_DEFAULT
    end

    -- Initialize mute/solo states if not set
    if group.isMuted == nil then group.isMuted = false end
    if group.isSoloed == nil then group.isSoloed = false end

    -- Solo button (square, same size as mute)
    local buttonSize = 20
    local soloColorPushed = 0
    if group.isSoloed then
        imgui.PushStyleColor(globals.ctx, imgui.Col_Button, 0xFFAA00FF) -- Yellow/orange when active
        imgui.PushStyleColor(globals.ctx, imgui.Col_ButtonHovered, 0xFFAA00FF) -- Same color on hover (no hover effect)
        soloColorPushed = 2
    end
    if imgui.Button(globals.ctx, "S##GroupSolo_" .. groupId, buttonSize, buttonSize) then
        group.isSoloed = not group.isSoloed
        if group.isSoloed and group.isMuted then
            group.isMuted = false
            globals.Utils.setGroupTrackMute(groupIndex, false)
        end
        globals.Utils.setGroupTrackSolo(groupIndex, group.isSoloed)
    end
    if soloColorPushed > 0 then
        imgui.PopStyleColor(globals.ctx, soloColorPushed)
    end

    -- Mute button (square, red when active)
    imgui.SameLine(globals.ctx, 0, 4)
    local muteColorPushed = 0
    if group.isMuted then
        imgui.PushStyleColor(globals.ctx, imgui.Col_Button, 0xFF0000FF) -- Red when active
        imgui.PushStyleColor(globals.ctx, imgui.Col_ButtonHovered, 0xFF0000FF) -- Same color on hover (no hover effect)
        muteColorPushed = 2
    end
    if imgui.Button(globals.ctx, "M##GroupMute_" .. groupId, buttonSize, buttonSize) then
        group.isMuted = not group.isMuted
        if group.isMuted and group.isSoloed then
            group.isSoloed = false
            globals.Utils.setGroupTrackSolo(groupIndex, false)
        end
        globals.Utils.setGroupTrackMute(groupIndex, group.isMuted)
    end
    if muteColorPushed > 0 then
        imgui.PopStyleColor(globals.ctx, muteColorPushed)
    end

    -- Volume slider (half width)
    imgui.SameLine(globals.ctx, 0, 8)

    -- Convert current dB to normalized
    local normalizedVolume = globals.Utils.dbToNormalizedRelative(group.trackVolume)
    local defaultNormalizedVolume = globals.Utils.dbToNormalizedRelative(globals.Constants.DEFAULTS.CONTAINER_VOLUME_DEFAULT)

    local rv, newNormalizedVolume = globals.SliderEnhanced.SliderDouble({
        id = "##GroupTrackVolume_" .. groupId,
        value = normalizedVolume,
        min = 0.0,
        max = 1.0,
        defaultValue = defaultNormalizedVolume,
        format = "",
        width = width * 0.3
    })
    if rv then
        local newVolumeDB = globals.Utils.normalizedToDbRelative(newNormalizedVolume)
        group.trackVolume = newVolumeDB
        -- Apply volume to track in real-time
        globals.Utils.setGroupTrackVolume(groupIndex, newVolumeDB)
    end

    -- Manual dB input field
    imgui.SameLine(globals.ctx, 0, 8)
    imgui.PushItemWidth(globals.ctx, 65)
    local displayValue = group.trackVolume <= -144 and -144 or group.trackVolume
    local rv2, manualDB = globals.UndoWrappers.InputDouble(
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
