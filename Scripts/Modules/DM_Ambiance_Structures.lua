--[[
@version 1.5
@noindex
--]]


local Structures = {}
local globals = {}
local Constants = require("DM_Ambiance_Constants")

function Structures.initModule(g)
    if not g then
        error("Structures.initModule: globals parameter is required")
    end
    globals = g
end

-- Group structure with randomization parameters
-- @param name string: Group name (optional, defaults to "New Group")
-- @return table: Group structure
function Structures.createGroup(name)
    return {
        name = name or "New Group",
        containers = {},
        expanded = true,
        -- Randomization parameters using constants
        pitchRange = {min = Constants.DEFAULTS.PITCH_RANGE_MIN, max = Constants.DEFAULTS.PITCH_RANGE_MAX},
        volumeRange = {min = Constants.DEFAULTS.VOLUME_RANGE_MIN, max = Constants.DEFAULTS.VOLUME_RANGE_MAX},
        panRange = {min = Constants.DEFAULTS.PAN_RANGE_MIN, max = Constants.DEFAULTS.PAN_RANGE_MAX},
        randomizePitch = true,
        randomizeVolume = true,
        randomizePan = true,
        triggerRate = Constants.DEFAULTS.TRIGGER_RATE,
        triggerDrift = Constants.DEFAULTS.TRIGGER_DRIFT,
        intervalMode = Constants.TRIGGER_MODES.ABSOLUTE,
        trackVolume = Constants.DEFAULTS.CONTAINER_VOLUME_DEFAULT, -- Group track volume in dB
        -- Chunk Mode parameters
        chunkDuration = Constants.DEFAULTS.CHUNK_DURATION,
        chunkSilence = Constants.DEFAULTS.CHUNK_SILENCE,
        chunkDurationVariation = Constants.DEFAULTS.CHUNK_DURATION_VARIATION,
        chunkSilenceVariation = Constants.DEFAULTS.CHUNK_SILENCE_VARIATION,
        -- Fade parameters
        fadeInEnabled = Constants.DEFAULTS.FADE_IN_ENABLED,
        fadeOutEnabled = Constants.DEFAULTS.FADE_OUT_ENABLED,
        fadeInDuration = Constants.DEFAULTS.FADE_IN_DURATION,
        fadeOutDuration = Constants.DEFAULTS.FADE_OUT_DURATION,
        fadeInUsePercentage = Constants.DEFAULTS.FADE_IN_USE_PERCENTAGE,
        fadeOutUsePercentage = Constants.DEFAULTS.FADE_OUT_USE_PERCENTAGE,
        fadeInShape = Constants.DEFAULTS.FADE_IN_SHAPE,
        fadeOutShape = Constants.DEFAULTS.FADE_OUT_SHAPE,
        fadeInCurve = Constants.DEFAULTS.FADE_IN_CURVE,
        fadeOutCurve = Constants.DEFAULTS.FADE_OUT_CURVE,
        -- Link modes for randomization parameters
        pitchLinkMode = "mirror", -- "unlink", "link", "mirror"
        volumeLinkMode = "mirror",
        panLinkMode = "mirror",
        -- Link modes for fade parameters  
        fadeLinkMode = "link"
    }
end

-- Container structure with override parent flag
-- @param name string: Container name (optional, defaults to "New Container")
-- @return table: Container structure
function Structures.createContainer(name)
    return {
        name = name or "New Container",
        items = {},
        expanded = true,
        pitchRange = {min = Constants.DEFAULTS.PITCH_RANGE_MIN, max = Constants.DEFAULTS.PITCH_RANGE_MAX},
        volumeRange = {min = Constants.DEFAULTS.VOLUME_RANGE_MIN, max = Constants.DEFAULTS.VOLUME_RANGE_MAX},
        panRange = {min = Constants.DEFAULTS.PAN_RANGE_MIN, max = Constants.DEFAULTS.PAN_RANGE_MAX},
        randomizePitch = true,
        randomizeVolume = true,
        randomizePan = true,
        triggerRate = Constants.DEFAULTS.TRIGGER_RATE, -- Can be negative for overlaps
        triggerDrift = Constants.DEFAULTS.TRIGGER_DRIFT,
        intervalMode = Constants.TRIGGER_MODES.ABSOLUTE,
        overrideParent = false, -- Flag to override parent group settings
        trackVolume = Constants.DEFAULTS.CONTAINER_VOLUME_DEFAULT, -- Container track volume in dB
        -- Chunk Mode parameters
        chunkDuration = Constants.DEFAULTS.CHUNK_DURATION,
        chunkSilence = Constants.DEFAULTS.CHUNK_SILENCE,
        chunkDurationVariation = Constants.DEFAULTS.CHUNK_DURATION_VARIATION,
        chunkSilenceVariation = Constants.DEFAULTS.CHUNK_SILENCE_VARIATION,
        -- Fade parameters
        fadeInEnabled = Constants.DEFAULTS.FADE_IN_ENABLED,
        fadeOutEnabled = Constants.DEFAULTS.FADE_OUT_ENABLED,
        fadeInDuration = Constants.DEFAULTS.FADE_IN_DURATION,
        fadeOutDuration = Constants.DEFAULTS.FADE_OUT_DURATION,
        fadeInUsePercentage = Constants.DEFAULTS.FADE_IN_USE_PERCENTAGE,
        fadeOutUsePercentage = Constants.DEFAULTS.FADE_OUT_USE_PERCENTAGE,
        fadeInShape = Constants.DEFAULTS.FADE_IN_SHAPE,
        fadeOutShape = Constants.DEFAULTS.FADE_OUT_SHAPE,
        fadeInCurve = Constants.DEFAULTS.FADE_IN_CURVE,
        fadeOutCurve = Constants.DEFAULTS.FADE_OUT_CURVE,
        -- Link modes for randomization parameters
        pitchLinkMode = "mirror", -- "unlink", "link", "mirror"
        volumeLinkMode = "mirror",
        panLinkMode = "mirror",
        -- Link modes for fade parameters  
        fadeLinkMode = "link"
    }
end

-- Function to get effective container parameters, considering parent inheritance
function Structures.getEffectiveContainerParams(group, container)
    -- If container is set to override parent settings, return its own parameters
    if container.overrideParent then
        return container
    end
    
    -- Create a new table with inherited parameters
    local effectiveParams = {}
    
    -- Copy all container properties first (without modifying references)
    for k, v in pairs(container) do
        if type(v) ~= "table" then
            effectiveParams[k] = v
        else
            -- Deep copy for tables (like ranges)
            effectiveParams[k] = {}
            for tk, tv in pairs(v) do
                effectiveParams[k][tk] = tv
            end
        end
    end
    
    -- Override with parent group randomization settings
    effectiveParams.randomizePitch = group.randomizePitch
    effectiveParams.randomizeVolume = group.randomizeVolume
    effectiveParams.randomizePan = group.randomizePan
    
    -- Copy parent range values (creating new tables to avoid reference issues)
    effectiveParams.pitchRange = {min = group.pitchRange.min, max = group.pitchRange.max}
    effectiveParams.volumeRange = {min = group.volumeRange.min, max = group.volumeRange.max}
    effectiveParams.panRange = {min = group.panRange.min, max = group.panRange.max}
    
    -- Inherit trigger settings
    effectiveParams.useRepetition = group.useRepetition
    effectiveParams.triggerRate = group.triggerRate
    effectiveParams.triggerDrift = group.triggerDrift
    effectiveParams.intervalMode = group.intervalMode
    
    -- Inherit chunk mode settings
    effectiveParams.chunkDuration = group.chunkDuration
    effectiveParams.chunkSilence = group.chunkSilence
    effectiveParams.chunkDurationVariation = group.chunkDurationVariation
    effectiveParams.chunkSilenceVariation = group.chunkSilenceVariation
    
    -- Inherit fade settings
    effectiveParams.fadeInEnabled = group.fadeInEnabled
    effectiveParams.fadeOutEnabled = group.fadeOutEnabled
    effectiveParams.fadeInDuration = group.fadeInDuration
    effectiveParams.fadeOutDuration = group.fadeOutDuration
    effectiveParams.fadeInUsePercentage = group.fadeInUsePercentage
    effectiveParams.fadeOutUsePercentage = group.fadeOutUsePercentage
    effectiveParams.fadeInShape = group.fadeInShape
    effectiveParams.fadeOutShape = group.fadeOutShape
    effectiveParams.fadeInCurve = group.fadeInCurve
    effectiveParams.fadeOutCurve = group.fadeOutCurve
    
    -- Inherit link modes
    effectiveParams.pitchLinkMode = group.pitchLinkMode or "mirror"
    effectiveParams.volumeLinkMode = group.volumeLinkMode or "mirror"
    effectiveParams.panLinkMode = group.panLinkMode or "mirror"
    effectiveParams.fadeLinkMode = group.fadeLinkMode or "link"
    
    return effectiveParams
end

return Structures
