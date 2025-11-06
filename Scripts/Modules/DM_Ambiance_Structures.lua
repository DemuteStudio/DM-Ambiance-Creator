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

-- Helper function to generate a unique name by checking existing names and incrementing
-- @param baseName string: Base name (e.g., "New Folder")
-- @param items table: Array of items to check against
-- @return string: Unique name (e.g., "New Folder", "New Folder 2", "New Folder 3", etc.)
local function generateUniqueName(baseName, items)
    -- Recursive function to collect all names from items and their children
    local function collectNames(itemList, nameSet)
        for _, item in ipairs(itemList) do
            nameSet[item.name] = true
            if item.type == "folder" and item.children then
                collectNames(item.children, nameSet)
            end
        end
    end

    -- Collect all existing names
    local existingNames = {}
    collectNames(items, existingNames)

    -- If base name doesn't exist, use it
    if not existingNames[baseName] then
        return baseName
    end

    -- Otherwise, find the next available number
    local counter = 2
    while existingNames[baseName .. " " .. counter] do
        counter = counter + 1
    end

    return baseName .. " " .. counter
end

-- Folder structure for organizational purposes
-- @param name string: Folder name (optional, auto-generates unique name if not provided)
-- @return table: Folder structure
function Structures.createFolder(name)
    -- Generate unique name if not provided
    if not name then
        name = generateUniqueName("New Folder", globals.items or {})
    end
    return {
        type = "folder",
        name = name,
        trackVolume = Constants.DEFAULTS.FOLDER_VOLUME_DEFAULT or 0.0,
        solo = false,
        mute = false,
        expanded = true,
        children = {},  -- Array of folders and groups
        trackGUID = nil  -- GUID of the folder track in REAPER (set during generation)
    }
end

-- Group structure with randomization parameters
-- @param name string: Group name (optional, auto-generates unique name if not provided)
-- @return table: Group structure
function Structures.createGroup(name)
    -- Generate unique name if not provided
    if not name then
        name = generateUniqueName("New Group", globals.items or {})
    end
    return {
        type = "group",
        name = name,
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

-- ============================================================================
-- PATH-BASED ACCESS HELPERS
-- ============================================================================

-- Local helper to copy a table (shallow copy for paths)
-- @param t table: Table to copy
-- @return table: New table with same contents
local function copyTable(t)
    if not t or type(t) ~= "table" then
        return {}
    end
    local result = {}
    for i, v in ipairs(t) do
        result[i] = v
    end
    return result
end

-- Local helper for pathToString (forwards to Utils module after initialization)
local function pathToString(path)
    -- Use Utils.pathToString for consistency across all modules
    if globals and globals.Utils and globals.Utils.pathToString then
        return globals.Utils.pathToString(path)
    end
    -- Fallback for early initialization
    if not path or type(path) ~= "table" or #path == 0 then
        return ""
    end
    return table.concat(path, ",")
end

-- Get an item (folder or group) from a path array
-- @param path table: Path array like {1, 2, 3}
-- @return table|nil: The item at the path, or nil if not found
function Structures.getItemFromPath(path)
    if not path or type(path) ~= "table" or #path == 0 then
        return nil
    end

    local current = globals.items
    for i = 1, #path do
        if not current or #current < path[i] then
            return nil
        end

        local item = current[path[i]]
        if not item then
            return nil
        end

        -- If this is the last index in the path, return the item
        if i == #path then
            return item
        end

        -- Navigate deeper based on item type
        if item.type == "folder" then
            current = item.children
        elseif item.type == "group" then
            -- Groups don't have children, only containers
            return nil
        else
            return nil
        end
    end

    return nil
end

-- Get a container by its ID (UUID)
-- Searches recursively through all groups in globals.items
-- @param containerID string: The container's UUID
-- @return table|nil, table|nil: The container and its parent group, or nil if not found
function Structures.getContainerByID(containerID)
    if not containerID or not globals.items then
        return nil, nil
    end

    local function searchItems(items)
        for _, item in ipairs(items) do
            if item.type == "group" and item.containers then
                for _, container in ipairs(item.containers) do
                    if container.id == containerID then
                        return container, item
                    end
                end
            elseif item.type == "folder" and item.children then
                local container, group = searchItems(item.children)
                if container then
                    return container, group
                end
            end
        end
        return nil, nil
    end

    return searchItems(globals.items)
end

-- Get a container from a group by index
-- @param groupPath table: Path to the group
-- @param containerIndex number: Index of the container (1-based)
-- @return table|nil: The container, or nil if not found
function Structures.getContainerFromGroup(groupPath, containerIndex)
    local group = Structures.getItemFromPath(groupPath)
    if not group or group.type ~= "group" or not group.containers then
        return nil
    end

    return group.containers[containerIndex]
end

-- Get the parent group of a container by its ID
-- @param containerID string: The container's UUID
-- @return table|nil, table|nil: The parent group and its path, or nil if not found
function Structures.getParentGroupOfContainer(containerID)
    local _, group = Structures.getContainerByID(containerID)
    if not group then
        return nil, nil
    end

    -- Find the path to this group
    local function findPath(items, targetGroup, currentPath)
        for i, item in ipairs(items) do
            local newPath = copyTable(currentPath)
            table.insert(newPath, i)

            if item == targetGroup then
                return newPath
            end

            if item.type == "folder" and item.children then
                local path = findPath(item.children, targetGroup, newPath)
                if path then
                    return path
                end
            end
        end
        return nil
    end

    local path = findPath(globals.items, group, {})
    return group, path
end

-- Get a group by its path
-- This is essentially an alias for getItemFromPath with type checking
-- @param path table: Path array like {1, 2, 3}
-- @return table|nil: The group, or nil if not found or not a group
function Structures.getGroupByPath(path)
    local item = Structures.getItemFromPath(path)
    if item and item.type == "group" then
        return item
    end
    return nil
end

-- Make a unique key for a container selection
-- @param path table: Path to the group
-- @param containerIndex number: Index of the container
-- @return string: A unique key like "1_2_3::5"
function Structures.makeContainerKey(path, containerIndex)
    if type(path) == "table" then
        local pathStr = pathToString(path)
        return pathStr .. "::" .. tostring(containerIndex)
    else
        -- Fallback for legacy numeric index
        return tostring(path) .. "_" .. tostring(containerIndex)
    end
end

-- Parse a container selection key back into path and index
-- @param key string: A key like "1_2_3::5" or "3_5" (legacy)
-- @return table|number, number: The path (or legacy index) and container index
function Structures.parseContainerKey(key)
    if not key then
        return nil, nil
    end

    -- Try new format first: "path::containerIndex"
    local pathStr, containerIndexStr = key:match("^(.+)::(%d+)$")
    if pathStr and containerIndexStr then
        -- Parse path string back to array
        local path = {}
        for num in pathStr:gmatch("(%d+)") do
            table.insert(path, tonumber(num))
        end
        return path, tonumber(containerIndexStr)
    end

    -- Fallback to legacy format: "groupIndex_containerIndex"
    local groupIndexStr, containerIndexStr = key:match("^(%d+)_(%d+)$")
    if groupIndexStr and containerIndexStr then
        return tonumber(groupIndexStr), tonumber(containerIndexStr)
    end

    return nil, nil
end

-- Make a unique key for an item (for waveform cache, etc.)
-- @param groupPath table: Path to the group
-- @param containerIndex number: Index of the container
-- @param itemIndex number: Index of the item
-- @return string: A unique key like "1_2_3::5::2"
function Structures.makeItemKey(groupPath, containerIndex, itemIndex)
    if type(groupPath) == "table" then
        local containerKey = Structures.makeContainerKey(groupPath, containerIndex)
        return containerKey .. "::" .. tostring(itemIndex)
    else
        -- Legacy format
        return string.format("g%d_c%d_i%d", groupPath, containerIndex, itemIndex)
    end
end

return Structures
