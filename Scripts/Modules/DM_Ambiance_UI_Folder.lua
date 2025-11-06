--[[
@version 1.0
@noindex
--]]

-- UI module for displaying folder details panel
local UI_Folder = {}
local globals = {}

function UI_Folder.initModule(g)
    if not g then
        error("UI_Folder.initModule: globals parameter is required")
    end
    globals = g
end

-- Draw the folder details panel
-- @param folder table: The folder structure to display
-- @param folderPath table: Path to the folder in the items hierarchy
function UI_Folder.drawFolderPanel(folder, folderPath)
    if not folder then
        return
    end

    local ctx = globals.ctx
    local imgui = globals.imgui
    local Constants = globals.Constants

    -- Sync folder volume, name, mute, and solo from track
    if folderPath then
        globals.Utils.syncFolderVolumeFromTrack(folderPath)
        globals.Utils.syncFolderNameFromTrack(folderPath)
        globals.Utils.syncFolderMuteFromTrack(folderPath)
        globals.Utils.syncFolderSoloFromTrack(folderPath)
    end

    -- Title
    imgui.Text(ctx, "Folder Settings")
    imgui.Separator(ctx)
    imgui.Spacing(ctx)

    -- Name input
    imgui.Text(ctx, "Name:")
    imgui.SameLine(ctx)
    local nameChanged, newName = imgui.InputText(ctx, "##FolderName", folder.name, imgui.InputTextFlags_None)
    if nameChanged then
        folder.name = newName
        -- Update track name in REAPER in real-time
        if folderPath then
            globals.Utils.setFolderTrackName(folderPath, newName)
        end
    end

    imgui.Separator(ctx)
    imgui.Text(ctx, "Folder Volume")
    imgui.SameLine(ctx)
    globals.Utils.HelpMarker("Controls the volume of the folder's track in Reaper. Affects all items in this folder.")

    -- Ensure trackVolume is initialized
    if folder.trackVolume == nil then
        folder.trackVolume = Constants.DEFAULTS.CONTAINER_VOLUME_DEFAULT
    end

    -- Initialize mute/solo states if not set
    if folder.isMuted == nil then folder.isMuted = false end
    if folder.isSoloed == nil then folder.isSoloed = false end

    -- Solo button (square, same size as mute)
    local buttonSize = 20
    local soloColorPushed = 0
    if folder.isSoloed then
        imgui.PushStyleColor(ctx, imgui.Col_Button, 0xFFAA00FF)
        imgui.PushStyleColor(ctx, imgui.Col_ButtonHovered, 0xFFCC00FF)
        imgui.PushStyleColor(ctx, imgui.Col_ButtonActive, 0xFF8800FF)
        soloColorPushed = 3
    end
    if imgui.Button(ctx, "S##FolderSolo", buttonSize, buttonSize) then
        folder.isSoloed = not folder.isSoloed
        -- If soloing, unmute automatically
        if folder.isSoloed and folder.isMuted then
            folder.isMuted = false
            if folderPath then
                globals.Utils.setFolderTrackMute(folderPath, false)
            end
        end
        -- Apply solo to REAPER track in real-time
        if folderPath then
            globals.Utils.setFolderTrackSolo(folderPath, folder.isSoloed)
        end
    end
    if soloColorPushed > 0 then
        imgui.PopStyleColor(ctx, soloColorPushed)
    end
    if imgui.IsItemHovered(ctx) then
        imgui.SetTooltip(ctx, "Solo folder track")
    end

    -- Mute button (square, same size as solo)
    imgui.SameLine(ctx, 0, 4)
    local muteColorPushed = 0
    if folder.isMuted then
        imgui.PushStyleColor(ctx, imgui.Col_Button, 0xFF0000FF)
        imgui.PushStyleColor(ctx, imgui.Col_ButtonHovered, 0xFF3333FF)
        imgui.PushStyleColor(ctx, imgui.Col_ButtonActive, 0xCC0000FF)
        muteColorPushed = 3
    end
    if imgui.Button(ctx, "M##FolderMute", buttonSize, buttonSize) then
        folder.isMuted = not folder.isMuted
        -- If muting, unsolo automatically
        if folder.isMuted and folder.isSoloed then
            folder.isSoloed = false
            if folderPath then
                globals.Utils.setFolderTrackSolo(folderPath, false)
            end
        end
        -- Apply mute to REAPER track in real-time
        if folderPath then
            globals.Utils.setFolderTrackMute(folderPath, folder.isMuted)
        end
    end
    if muteColorPushed > 0 then
        imgui.PopStyleColor(ctx, muteColorPushed)
    end
    if imgui.IsItemHovered(ctx) then
        imgui.SetTooltip(ctx, "Mute folder track")
    end

    -- Convert current dB to normalized
    local normalizedVolume = globals.Utils.dbToNormalizedRelative(folder.trackVolume)

    -- Volume knob
    imgui.SameLine(ctx, 0, 8)
    local defaultNormalizedVolume = globals.Utils.dbToNormalizedRelative(Constants.DEFAULTS.CONTAINER_VOLUME_DEFAULT)
    local rv, newNormalizedVolume = globals.Knob.Knob({
        id = "##FolderTrackVolume",
        label = "",
        value = normalizedVolume,
        min = 0.0,
        max = 1.0,
        default = defaultNormalizedVolume,
        size = 50,
        format = "%.2f",
        showLabel = false
    })
    if rv then
        local newVolumeDB = globals.Utils.normalizedToDbRelative(newNormalizedVolume)
        folder.trackVolume = newVolumeDB
        -- Apply volume to REAPER track in real-time
        if folderPath then
            globals.Utils.setFolderTrackVolume(folderPath, newVolumeDB)
        end
    end

    -- Manual dB input field
    imgui.SameLine(ctx, 0, 8)
    imgui.PushItemWidth(ctx, 85)
    local displayValue = folder.trackVolume <= -144 and -144 or folder.trackVolume
    local rv2, manualDB = globals.UndoWrappers.InputDouble(
        ctx,
        "##FolderVolumeInput",
        displayValue,
        0, 0,  -- step, step_fast (not used)
        "%.1f dB"
    )
    if rv2 then
        -- Clamp to valid range
        manualDB = math.max(Constants.AUDIO.VOLUME_RANGE_DB_MIN,
                           math.min(Constants.AUDIO.VOLUME_RANGE_DB_MAX, manualDB))
        folder.trackVolume = manualDB
        -- Apply volume to REAPER track in real-time
        if folderPath then
            globals.Utils.setFolderTrackVolume(folderPath, manualDB)
        end
    end
    imgui.PopItemWidth(ctx)

    imgui.Spacing(ctx)
    imgui.Separator(ctx)
    imgui.Spacing(ctx)

    -- Folder info
    local numGroups = folder.children and #folder.children or 0
    imgui.TextDisabled(ctx, string.format("Contains %d item(s)", numGroups))
end

return UI_Folder
