--[[
@version 1.0
@noindex
--]]

-- Reusable volume controls widget (Solo/Mute/Knob/dB input)
-- Used for containers, groups, and folders
local VolumeControls = {}
local globals = {}

function VolumeControls.initModule(g)
    if not g then
        error("VolumeControls.initModule: globals parameter is required")
    end
    globals = g
end

--- Draw volume controls: Solo button, Mute button, Volume knob, and dB input
-- @param config table: {
--   id: unique ID for the widgets
--   item: the item (container/group/folder) with trackVolume, isMuted, isSoloed
--   onVolumeChange: callback(newVolumeDB) - called when volume changes
--   onMuteChange: callback(isMuted) - called when mute changes
--   onSoloChange: callback(isSoloed) - called when solo changes
-- }
function VolumeControls.draw(config)
    local ctx = globals.ctx
    local imgui = globals.imgui
    local Constants = globals.Constants

    local id = config.id
    local item = config.item
    local onVolumeChange = config.onVolumeChange
    local onMuteChange = config.onMuteChange
    local onSoloChange = config.onSoloChange

    -- Ensure trackVolume is initialized
    if item.trackVolume == nil then
        item.trackVolume = Constants.DEFAULTS.CONTAINER_VOLUME_DEFAULT
    end

    -- Initialize mute/solo states if not set
    if item.isMuted == nil then item.isMuted = false end
    if item.isSoloed == nil then item.isSoloed = false end

    -- Solo button (square, same size as mute)
    local buttonSize = 20
    local soloColorPushed = 0
    if item.isSoloed then
        imgui.PushStyleColor(ctx, imgui.Col_Button, 0xFFAA00FF)
        imgui.PushStyleColor(ctx, imgui.Col_ButtonHovered, 0xFFCC00FF)
        imgui.PushStyleColor(ctx, imgui.Col_ButtonActive, 0xFF8800FF)
        soloColorPushed = 3
    end
    if imgui.Button(ctx, "S##" .. id .. "_Solo", buttonSize, buttonSize) then
        item.isSoloed = not item.isSoloed
        if onSoloChange then
            onSoloChange(item.isSoloed)
        end
    end
    if soloColorPushed > 0 then
        imgui.PopStyleColor(ctx, soloColorPushed)
    end
    if imgui.IsItemHovered(ctx) then
        imgui.SetTooltip(ctx, "Solo track")
    end

    -- Mute button (square, same size as solo)
    imgui.SameLine(ctx, 0, 4)
    local muteColorPushed = 0
    if item.isMuted then
        imgui.PushStyleColor(ctx, imgui.Col_Button, 0xFF0000FF)
        imgui.PushStyleColor(ctx, imgui.Col_ButtonHovered, 0xFF3333FF)
        imgui.PushStyleColor(ctx, imgui.Col_ButtonActive, 0xCC0000FF)
        muteColorPushed = 3
    end
    if imgui.Button(ctx, "M##" .. id .. "_Mute", buttonSize, buttonSize) then
        item.isMuted = not item.isMuted
        if onMuteChange then
            onMuteChange(item.isMuted)
        end
    end
    if muteColorPushed > 0 then
        imgui.PopStyleColor(ctx, muteColorPushed)
    end
    if imgui.IsItemHovered(ctx) then
        imgui.SetTooltip(ctx, "Mute track")
    end

    -- Convert current dB to normalized
    local normalizedVolume = globals.Utils.dbToNormalizedRelative(item.trackVolume)

    -- Volume knob
    imgui.SameLine(ctx, 0, 8)
    local defaultNormalizedVolume = globals.Utils.dbToNormalizedRelative(Constants.DEFAULTS.CONTAINER_VOLUME_DEFAULT)
    local rv, newNormalizedVolume = globals.Knob.Knob({
        id = "##" .. id .. "_VolumeKnob",
        label = "",
        value = normalizedVolume,
        min = 0.0,
        max = 1.0,
        defaultValue = defaultNormalizedVolume,
        size = 50,
        format = "%.2f",
        showLabel = false
    })
    if rv then
        local newVolumeDB = globals.Utils.normalizedToDbRelative(newNormalizedVolume)
        item.trackVolume = newVolumeDB
        if onVolumeChange then
            onVolumeChange(newVolumeDB)
        end
    end

    -- Manual dB input field
    imgui.SameLine(ctx, 0, 8)
    imgui.PushItemWidth(ctx, 85)
    local displayValue = item.trackVolume <= -144 and -144 or item.trackVolume
    local rv2, manualDB = globals.UndoWrappers.InputDouble(
        ctx,
        "##" .. id .. "_VolumeInput",
        displayValue,
        0, 0,  -- step, step_fast (not used)
        "%.1f dB"
    )
    if rv2 then
        -- Clamp to valid range
        manualDB = math.max(Constants.AUDIO.VOLUME_RANGE_DB_MIN,
                           math.min(Constants.AUDIO.VOLUME_RANGE_DB_MAX, manualDB))
        item.trackVolume = manualDB
        if onVolumeChange then
            onVolumeChange(manualDB)
        end
    end
    imgui.PopItemWidth(ctx)
end

return VolumeControls
