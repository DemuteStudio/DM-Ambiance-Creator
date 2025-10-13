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
        pitchMode = Constants.DEFAULTS.PITCH_MODE,
        pitchRange = {min = Constants.DEFAULTS.PITCH_RANGE_MIN, max = Constants.DEFAULTS.PITCH_RANGE_MAX},
        volumeRange = {min = Constants.DEFAULTS.VOLUME_RANGE_MIN, max = Constants.DEFAULTS.VOLUME_RANGE_MAX},
        panRange = {min = Constants.DEFAULTS.PAN_RANGE_MIN, max = Constants.DEFAULTS.PAN_RANGE_MAX},
        randomizePitch = true,
        randomizeVolume = true,
        randomizePan = true,
        triggerRate = Constants.DEFAULTS.TRIGGER_RATE,
        triggerDrift = Constants.DEFAULTS.TRIGGER_DRIFT,
        triggerDriftDirection = Constants.DEFAULTS.TRIGGER_DRIFT_DIRECTION,
        intervalMode = Constants.TRIGGER_MODES.ABSOLUTE,
        trackVolume = Constants.DEFAULTS.CONTAINER_VOLUME_DEFAULT, -- Group track volume in dB
        -- Chunk Mode parameters
        chunkDuration = Constants.DEFAULTS.CHUNK_DURATION,
        chunkSilence = Constants.DEFAULTS.CHUNK_SILENCE,
        chunkDurationVariation = Constants.DEFAULTS.CHUNK_DURATION_VARIATION,
        chunkDurationVarDirection = Constants.DEFAULTS.CHUNK_DURATION_VAR_DIRECTION,
        chunkSilenceVariation = Constants.DEFAULTS.CHUNK_SILENCE_VARIATION,
        chunkSilenceVarDirection = Constants.DEFAULTS.CHUNK_SILENCE_VAR_DIRECTION,
        -- Noise Mode parameters
        noiseSeed = math.random(Constants.DEFAULTS.NOISE_SEED_MIN, Constants.DEFAULTS.NOISE_SEED_MAX),
        noiseAlgorithm = Constants.DEFAULTS.NOISE_ALGORITHM,
        noiseFrequency = Constants.DEFAULTS.NOISE_FREQUENCY,
        noiseAmplitude = Constants.DEFAULTS.NOISE_AMPLITUDE,
        noiseOctaves = Constants.DEFAULTS.NOISE_OCTAVES,
        noisePersistence = Constants.DEFAULTS.NOISE_PERSISTENCE,
        noiseLacunarity = Constants.DEFAULTS.NOISE_LACUNARITY,
        noiseDensity = Constants.DEFAULTS.NOISE_DENSITY,
        noiseThreshold = Constants.DEFAULTS.NOISE_THRESHOLD,
        densityLinkMode = "link", -- "unlink", "link", "mirror"
        -- Euclidean Mode parameters
        euclideanMode = Constants.DEFAULTS.EUCLIDEAN_MODE,
        euclideanTempo = Constants.DEFAULTS.EUCLIDEAN_TEMPO,
        euclideanUseProjectTempo = Constants.DEFAULTS.EUCLIDEAN_USE_PROJECT_TEMPO,
        euclideanSelectedLayer = Constants.DEFAULTS.EUCLIDEAN_SELECTED_LAYER,
        euclideanLayers = {
            {
                pulses = Constants.DEFAULTS.EUCLIDEAN_PULSES,
                steps = Constants.DEFAULTS.EUCLIDEAN_STEPS,
                rotation = Constants.DEFAULTS.EUCLIDEAN_ROTATION,
            }
        },
        -- Euclidean Layer Bindings (for groups only)
        euclideanAutoBindContainers = false,  -- If true, bind layers to child containers by UUID
        euclideanLayerBindings = {},  -- {[containerUUID] = {{pulses, steps, rotation}, {pulses, steps, rotation}, ...}}
        euclideanBindingOrder = {},  -- Array of containerUUIDs in display order
        euclideanSelectedBindingIndex = Constants.DEFAULTS.EUCLIDEAN_SELECTED_BINDING_INDEX,  -- Selected binding index (auto-bind mode)
        euclideanSelectedLayerPerBinding = {},  -- {[containerUUID] = layerIndex} - Track selected layer per binding
        -- Euclidean Saved Patterns (for both groups and containers)
        euclideanSavedPatterns = {},  -- Array of {name, pulses, steps, rotation}
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
        fadeLinkMode = "link",
        -- Regeneration tracking
        needsRegeneration = false
    }
end

-- Container structure with override parent flag
-- @param name string: Container name (optional, defaults to "New Container")
-- @return table: Container structure
function Structures.createContainer(name)
    -- Generate UUID using Utils (will be available after initModule)
    local Utils = require("DM_Ambiance_Utils")

    return {
        id = Utils.generateUUID(),  -- Stable identifier for layer binding
        name = name or "New Container",
        items = {},
        expanded = true,
        pitchMode = Constants.DEFAULTS.PITCH_MODE,
        pitchRange = {min = Constants.DEFAULTS.PITCH_RANGE_MIN, max = Constants.DEFAULTS.PITCH_RANGE_MAX},
        volumeRange = {min = Constants.DEFAULTS.VOLUME_RANGE_MIN, max = Constants.DEFAULTS.VOLUME_RANGE_MAX},
        panRange = {min = Constants.DEFAULTS.PAN_RANGE_MIN, max = Constants.DEFAULTS.PAN_RANGE_MAX},
        randomizePitch = true,
        randomizeVolume = true,
        randomizePan = true,
        triggerRate = Constants.DEFAULTS.TRIGGER_RATE, -- Can be negative for overlaps
        triggerDrift = Constants.DEFAULTS.TRIGGER_DRIFT,
        triggerDriftDirection = Constants.DEFAULTS.TRIGGER_DRIFT_DIRECTION,
        intervalMode = Constants.TRIGGER_MODES.ABSOLUTE,
        overrideParent = false, -- Flag to override parent group settings
        trackVolume = Constants.DEFAULTS.CONTAINER_VOLUME_DEFAULT, -- Container track volume in dB
        -- Multi-channel support
        channelMode = Constants.CHANNEL_MODES.DEFAULT,  -- Default to stereo
        channelVariant = 0,  -- Channel variant (0=ITU/Dolby, 1=SMPTE) for OUTPUT
        sourceChannelVariant = nil,  -- Source format for items (nil=unknown, 0=ITU, 1=SMPTE) - for smart routing
        channelVolumes = {},  -- Volume per channel in dB
        -- Item routing and distribution
        itemDistributionMode = 0,  -- 0=Round-robin, 1=Random, 2=All tracks (for mono items)
        channelSelectionMode = "none",  -- "none" (auto), "stereo" (stereo pairs), "mono" (mono split)
        stereoPairSelection = 0,  -- DEPRECATED: Use stereoPairMapping instead
        stereoPairMapping = nil,  -- NEW: Per-track stereo pair selection: {[trackIdx] = pairIdx or "random"}
        monoChannelSelection = 0,  -- Which mono channel to select (0=Ch1, 1=Ch2, ..., or index>=itemChannels for Random)
        customItemRouting = {},  -- Custom routing per item: {[itemIndex] = {routingMatrix = {[srcCh]=destCh}, isAutoRouting = true}}
        -- Legacy support (will be migrated)
        downmixMode = nil,  -- OLD: Will be converted to channelSelectionMode
        downmixChannel = nil,  -- OLD: Will be converted to stereoPairSelection or monoChannelSelection
        -- Chunk Mode parameters
        chunkDuration = Constants.DEFAULTS.CHUNK_DURATION,
        chunkSilence = Constants.DEFAULTS.CHUNK_SILENCE,
        chunkDurationVariation = Constants.DEFAULTS.CHUNK_DURATION_VARIATION,
        chunkDurationVarDirection = Constants.DEFAULTS.CHUNK_DURATION_VAR_DIRECTION,
        chunkSilenceVariation = Constants.DEFAULTS.CHUNK_SILENCE_VARIATION,
        chunkSilenceVarDirection = Constants.DEFAULTS.CHUNK_SILENCE_VAR_DIRECTION,
        -- Noise Mode parameters
        noiseSeed = math.random(Constants.DEFAULTS.NOISE_SEED_MIN, Constants.DEFAULTS.NOISE_SEED_MAX),
        noiseAlgorithm = Constants.DEFAULTS.NOISE_ALGORITHM,
        noiseFrequency = Constants.DEFAULTS.NOISE_FREQUENCY,
        noiseAmplitude = Constants.DEFAULTS.NOISE_AMPLITUDE,
        noiseOctaves = Constants.DEFAULTS.NOISE_OCTAVES,
        noisePersistence = Constants.DEFAULTS.NOISE_PERSISTENCE,
        noiseLacunarity = Constants.DEFAULTS.NOISE_LACUNARITY,
        noiseDensity = Constants.DEFAULTS.NOISE_DENSITY,
        noiseThreshold = Constants.DEFAULTS.NOISE_THRESHOLD,
        densityLinkMode = "link", -- "unlink", "link", "mirror"
        -- Euclidean Mode parameters
        euclideanMode = Constants.DEFAULTS.EUCLIDEAN_MODE,
        euclideanTempo = Constants.DEFAULTS.EUCLIDEAN_TEMPO,
        euclideanUseProjectTempo = Constants.DEFAULTS.EUCLIDEAN_USE_PROJECT_TEMPO,
        euclideanSelectedLayer = Constants.DEFAULTS.EUCLIDEAN_SELECTED_LAYER,
        euclideanLayers = {
            {
                pulses = Constants.DEFAULTS.EUCLIDEAN_PULSES,
                steps = Constants.DEFAULTS.EUCLIDEAN_STEPS,
                rotation = Constants.DEFAULTS.EUCLIDEAN_ROTATION,
            }
        },
        -- Euclidean Saved Patterns (for containers only)
        euclideanSavedPatterns = {},  -- Array of {name, pulses, steps, rotation}
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
        fadeLinkMode = "link",
        -- Regeneration tracking
        needsRegeneration = false
    }
end

-- Generate default stereo pair mapping for a container
-- @param numTracks number: Number of stereo tracks to create
-- @return table: Default mapping {[trackIdx] = pairIdx}
function Structures.getDefaultStereoPairMapping(numTracks)
    local mapping = {}
    for i = 1, numTracks do
        mapping[i] = i - 1  -- Track 1 → pair 0 (Ch1-2), Track 2 → pair 1 (Ch3-4), etc.
    end
    return mapping
end

-- Initialize stereoPairMapping if needed
-- @param container table: Container to initialize
-- @param numTracks number: Number of stereo tracks
function Structures.ensureStereoPairMapping(container, numTracks)
    if not container.stereoPairMapping or type(container.stereoPairMapping) ~= "table" then
        container.stereoPairMapping = Structures.getDefaultStereoPairMapping(numTracks)
    else
        -- Ensure all track indices exist with valid defaults
        for i = 1, numTracks do
            if container.stereoPairMapping[i] == nil then
                container.stereoPairMapping[i] = i - 1  -- Default to logical pair
            end
        end
    end
end

-- Function to get effective container parameters, considering parent inheritance
function Structures.getEffectiveContainerParams(group, container)
    -- If container is set to override parent settings, return its own parameters
    if container.overrideParent then
        -- Create a copy to avoid modifying the original container
        local containerParams = {}
        for k, v in pairs(container) do
            if type(v) ~= "table" then
                containerParams[k] = v
            else
                -- Deep copy for tables (like ranges)
                containerParams[k] = {}
                for tk, tv in pairs(v) do
                    containerParams[k][tk] = tv
                end
            end
        end

        -- Force disable pan randomization for multichannel containers (channelMode > 0)
        -- This ensures old presets don't apply pan in multichannel mode
        if containerParams.channelMode and containerParams.channelMode > 0 then
            containerParams.randomizePan = false
        end

        return containerParams
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
    effectiveParams.pitchMode = group.pitchMode
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
    effectiveParams.triggerDriftDirection = group.triggerDriftDirection
    effectiveParams.intervalMode = group.intervalMode

    -- Inherit chunk mode settings
    effectiveParams.chunkDuration = group.chunkDuration
    effectiveParams.chunkSilence = group.chunkSilence
    effectiveParams.chunkDurationVariation = group.chunkDurationVariation
    effectiveParams.chunkDurationVarDirection = group.chunkDurationVarDirection
    effectiveParams.chunkSilenceVariation = group.chunkSilenceVariation
    effectiveParams.chunkSilenceVarDirection = group.chunkSilenceVarDirection
    
    -- Inherit fade settings with proper boolean handling
    -- Ensure fadeEnabled values are never nil (fixes checkbox persistence issue)
    if container.fadeInEnabled ~= nil then
        effectiveParams.fadeInEnabled = container.fadeInEnabled
    elseif group.fadeInEnabled ~= nil then
        effectiveParams.fadeInEnabled = group.fadeInEnabled
    else
        effectiveParams.fadeInEnabled = false  -- Default to false if both are nil
    end
    
    if container.fadeOutEnabled ~= nil then
        effectiveParams.fadeOutEnabled = container.fadeOutEnabled
    elseif group.fadeOutEnabled ~= nil then
        effectiveParams.fadeOutEnabled = group.fadeOutEnabled
    else
        effectiveParams.fadeOutEnabled = false  -- Default to false if both are nil
    end
    
    -- Inherit other fade settings (these can be nil without issues)
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

    -- Inherit noise mode settings
    effectiveParams.noiseSeed = group.noiseSeed
    effectiveParams.noiseFrequency = group.noiseFrequency
    effectiveParams.noiseAmplitude = group.noiseAmplitude
    effectiveParams.noiseOctaves = group.noiseOctaves
    effectiveParams.noisePersistence = group.noisePersistence
    effectiveParams.noiseLacunarity = group.noiseLacunarity
    effectiveParams.noiseDensity = group.noiseDensity
    effectiveParams.noiseThreshold = group.noiseThreshold
    effectiveParams.densityLinkMode = group.densityLinkMode or "link"

    -- Inherit euclidean mode settings
    effectiveParams.euclideanMode = group.euclideanMode
    effectiveParams.euclideanTempo = group.euclideanTempo
    effectiveParams.euclideanUseProjectTempo = group.euclideanUseProjectTempo
    effectiveParams.euclideanSelectedLayer = group.euclideanSelectedLayer

    -- Check if group is in auto-bind mode and container has a specific binding
    local useBinding = false
    if group.euclideanAutoBindContainers and container.id then
        -- Container has UUID and group is in auto-bind mode
        if group.euclideanLayerBindings and group.euclideanLayerBindings[container.id] then
            -- Combine parent binding layers + container's own layers
            useBinding = true
            local combinedLayers = {}

            -- Add all parent binding layers (now an array)
            local parentBindingLayers = group.euclideanLayerBindings[container.id]
            for _, bindingLayer in ipairs(parentBindingLayers) do
                table.insert(combinedLayers, {
                    pulses = bindingLayer.pulses,
                    steps = bindingLayer.steps,
                    rotation = bindingLayer.rotation,
                })
            end

            -- Add container's own euclidean layers (if in Override mode)
            if container.overrideParent and container.euclideanLayers then
                for _, layer in ipairs(container.euclideanLayers) do
                    table.insert(combinedLayers, {
                        pulses = layer.pulses,
                        steps = layer.steps,
                        rotation = layer.rotation,
                    })
                end
            end

            effectiveParams.euclideanLayers = combinedLayers
        end
    end

    -- If not using binding, inherit layers from group (manual mode)
    if not useBinding then
        effectiveParams.euclideanLayers = {}
        if group.euclideanLayers then
            for i, layer in ipairs(group.euclideanLayers) do
                effectiveParams.euclideanLayers[i] = {
                    pulses = layer.pulses,
                    steps = layer.steps,
                    rotation = layer.rotation,
                }
            end
        end
    end

    -- Force disable pan randomization for multichannel containers (channelMode > 0)
    -- This ensures old presets don't apply pan in multichannel mode
    if effectiveParams.channelMode and effectiveParams.channelMode > 0 then
        effectiveParams.randomizePan = false
    end

    return effectiveParams
end

-- Migrate old presets: Add UUIDs to containers that don't have them
-- This ensures backward compatibility with presets created before UUID implementation
function Structures.migrateContainersToUUID(groups)
    local Utils = require("DM_Ambiance_Utils")
    local migrated = false

    for _, group in ipairs(groups) do
        if group.containers then
            for _, container in ipairs(group.containers) do
                if not container.id then
                    container.id = Utils.generateUUID()
                    migrated = true
                end
            end
        end
    end

    return migrated
end

-- Sync euclidean layer bindings for a group
-- This function maintains the binding system between group layers and containers
-- Called after container add/delete/move operations
function Structures.syncEuclideanBindings(group)
    -- Only sync if auto-bind is enabled
    if not group.euclideanAutoBindContainers then
        return
    end

    -- Initialize binding structures if missing
    if not group.euclideanLayerBindings then
        group.euclideanLayerBindings = {}
    end
    if not group.euclideanBindingOrder then
        group.euclideanBindingOrder = {}
    end

    -- Get list of containers that should have bindings
    local eligibleContainers = {}
    if group.containers then
        for _, container in ipairs(group.containers) do
            -- Container is eligible if:
            -- 1. It doesn't override parent (inherits euclidean settings), OR
            -- 2. It overrides AND uses euclidean trigger mode
            -- EXCLUDE: Containers that override and are NOT euclidean
            local isEligible = false
            if not container.overrideParent then
                -- Inherits from parent - eligible if parent is euclidean
                isEligible = (group.intervalMode == 5)  -- TRIGGER_MODES.EUCLIDEAN
            else
                -- Overrides parent - ONLY eligible if container itself is euclidean
                isEligible = (container.intervalMode == 5)
            end

            if isEligible and container.id then
                table.insert(eligibleContainers, container)
            end
        end
    end

    -- Create new bindings and binding order
    local newBindings = {}
    local newBindingOrder = {}
    local newSelectedLayers = {}

    for _, container in ipairs(eligibleContainers) do
        local uuid = container.id

        -- Preserve existing binding if it exists
        if group.euclideanLayerBindings[uuid] then
            local existingBinding = group.euclideanLayerBindings[uuid]

            -- MIGRATION: Convert old single-object binding to array format
            if existingBinding.pulses and existingBinding.steps then
                -- Old format: {pulses, steps, rotation} - convert to array
                newBindings[uuid] = {{
                    pulses = existingBinding.pulses,
                    steps = existingBinding.steps,
                    rotation = existingBinding.rotation or globals.Constants.DEFAULTS.EUCLIDEAN_ROTATION
                }}
            else
                -- Already array format - preserve it
                newBindings[uuid] = existingBinding
            end
        else
            -- Create new binding array with default values (single layer initially)
            newBindings[uuid] = {{
                pulses = globals.Constants.DEFAULTS.EUCLIDEAN_PULSES,
                steps = globals.Constants.DEFAULTS.EUCLIDEAN_STEPS,
                rotation = globals.Constants.DEFAULTS.EUCLIDEAN_ROTATION
            }}
        end

        -- Preserve selected layer index for this binding
        if group.euclideanSelectedLayerPerBinding and group.euclideanSelectedLayerPerBinding[uuid] then
            newSelectedLayers[uuid] = group.euclideanSelectedLayerPerBinding[uuid]
        else
            newSelectedLayers[uuid] = 1  -- Default to first layer
        end

        table.insert(newBindingOrder, uuid)
    end

    -- Update group's binding structures
    group.euclideanLayerBindings = newBindings
    group.euclideanBindingOrder = newBindingOrder
    group.euclideanSelectedLayerPerBinding = newSelectedLayers
end

return Structures
