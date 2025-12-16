--[[
@version 1.3
@noindex
--]]

local UI_MultiSelection = {}

local globals = {}

-- Initialize the module with global variables from the main script
function UI_MultiSelection.initModule(g)
    globals = g
end

-- Helper function to display a "mixed values" indicator
local function showMixedValues()
    imgui.SameLine(globals.ctx)
    imgui.TextColored(globals.ctx, 0xFFAA00FF, "(Mixed values)")
end

-- Function to get all selected containers as a table of {groupPath, containerIndex} pairs
function UI_MultiSelection.getSelectedContainersList()
    local containers = {}
    for key in pairs(globals.selectedContainers) do
        -- Use Utils.parseContainerKey to match the format created by Utils.makeContainerKey
        local groupPath, containerIndex = globals.Utils.parseContainerKey(key)
        if groupPath and containerIndex then
            table.insert(containers, {groupPath = groupPath, containerIndex = containerIndex})
        end
    end
    return containers
end

-- Function to draw the right panel for multi-selection edit mode
function UI_MultiSelection.drawMultiSelectionPanel(width)
    -- Count selected containers
    local selectedCount = 0
    for _ in pairs(globals.selectedContainers) do
        selectedCount = selectedCount + 1
    end

    -- Title with count
    imgui.TextColored(globals.ctx, 0xFF4CAF50, "Editing " .. selectedCount .. " containers")

    if selectedCount == 0 then
        -- Don't render anything to avoid corrupting ImGui context
        return
    end

    -- Get list of all selected containers
    local containers = UI_MultiSelection.getSelectedContainersList()

    -- Button to regenerate all selected containers
    if imgui.Button(globals.ctx, "Regenerate All", width * 0.5, 30) then
        for _, c in ipairs(containers) do
            globals.Generation.generateSingleContainer(c.groupPath, c.containerIndex)
        end
    end

    imgui.Separator(globals.ctx)

    -- Collect info about override parent status
    local anyOverrideParent = false
    local allOverrideParent = true

    -- Check all containers for override parent setting
    for _, c in ipairs(containers) do
        local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
        if not container then
            goto continue
        end

        -- Override parent status
        if container.overrideParent then
            anyOverrideParent = true
        else
            allOverrideParent = false
        end

        ::continue::
    end

    -- Override Parent checkbox (three-state checkbox for mixed values)
    local overrideState = allOverrideParent and 1 or (anyOverrideParent and 2 or 0)
    local overrideText = "Override Parent Settings"
    if overrideState == 2 then -- Mixed values
        overrideText = overrideText .. " (Mixed)"
    end

    -- Custom drawing of the three-state checkbox
    local overrideParent = false
    if overrideState == 1 then
        overrideParent = true
    end

    local rv, newOverrideParent = globals.UndoWrappers.Checkbox(globals.ctx, overrideText, overrideParent)
    imgui.SameLine(globals.ctx)
    globals.Utils.HelpMarker("Enable 'Override Parent Settings' to customize parameters")

    if rv then
        -- Apply to all selected containers
        local affectedGroups = {}
        for _, c in ipairs(containers) do
            local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
            if container then
                container.overrideParent = newOverrideParent
                local pathStr = globals.Utils.pathToString(c.groupPath)
                affectedGroups[pathStr] = c.groupPath
            end
        end

        -- Sync euclidean bindings for all affected groups
        for pathStr, groupPath in pairs(affectedGroups) do
            local group = globals.Structures.getGroupFromPath(groupPath)
            if group then
                globals.Structures.syncEuclideanBindings(group)
            end
        end

        -- Update state for UI refresh
        if newOverrideParent then
            anyOverrideParent = true
            allOverrideParent = true
        else
            anyOverrideParent = false
            allOverrideParent = false
        end
    end

    -- Conditionally display a message based on override status
    if allOverrideParent then
        imgui.TextColored(globals.ctx, 0x00AA00FF, "Using containers' own settings")
    elseif not anyOverrideParent then
        imgui.TextColored(globals.ctx, 0x0088FFFF, "All containers inherit settings from parent groups")
    else
        imgui.TextColored(globals.ctx, 0xFFAA00FF, "Mixed inheritance settings")
    end

    -- Collect info about selected containers for initial values
    local anyRandomizePitch = false
    local allRandomizePitch = true
    local anyRandomizeVolume = false
    local allRandomizeVolume = true
    local anyRandomizePan = false
    local allRandomizePan = true
    local anyMultiChannel = false  -- Track if any container is multichannel
    local anyStereo = false        -- Track if any container supports pan (is NOT multichannel)

    -- Default values for common parameters
    local commonIntervalMode = nil
    local commonTriggerRate = nil
    local commonTriggerDrift = nil
    local commonTriggerDriftDirection = nil
    local commonPitchMin, commonPitchMax = nil, nil
    local commonVolumeMin, commonVolumeMax = nil, nil
    local commonPanMin, commonPanMax = nil, nil
    -- Chunk mode parameters
    local commonChunkDuration = nil
    local commonChunkSilence = nil
    local commonChunkDurationVariation = nil
    local commonChunkSilenceVariation = nil
    local commonChunkDurationVarDirection = nil
    local commonChunkSilenceVarDirection = nil
    -- Noise mode parameters
    local commonNoiseSeed = nil
    local commonNoiseFrequency = nil
    local commonNoiseAmplitude = nil
    local commonNoiseOctaves = nil
    local commonNoisePersistence = nil
    local commonNoiseLacunarity = nil
    local commonNoiseDensity = nil
    local commonNoiseThreshold = nil
    local commonDensityLinkMode = nil

    -- Check all containers to determine common settings
    for _, c in ipairs(containers) do
        local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
        if not container then
            goto continue_check
        end

        -- Check if this container is multichannel (non-stereo)
        if container.channelMode and container.channelMode > 0 then
            anyMultiChannel = true
        else
            anyStereo = true  -- This container supports pan
        end

        -- Randomization settings
        if container.randomizePitch then anyRandomizePitch = true else allRandomizePitch = false end
        if container.randomizeVolume then anyRandomizeVolume = true else allRandomizeVolume = false end
        if container.randomizePan then anyRandomizePan = true else allRandomizePan = false end

        -- Calculate common values
        if commonIntervalMode == nil then
            commonIntervalMode = container.intervalMode
        elseif commonIntervalMode ~= container.intervalMode then
            commonIntervalMode = -1 -- Mixed values
        end

        if commonTriggerRate == nil then
            commonTriggerRate = container.triggerRate
        elseif math.abs(commonTriggerRate - container.triggerRate) > 0.001 then
            commonTriggerRate = -999 -- Mixed values
        end

        if commonTriggerDrift == nil then
            commonTriggerDrift = container.triggerDrift
        elseif commonTriggerDrift ~= container.triggerDrift then
            commonTriggerDrift = -1 -- Mixed values
        end

        if commonTriggerDriftDirection == nil then
            commonTriggerDriftDirection = container.triggerDriftDirection or 0
        elseif commonTriggerDriftDirection ~= (container.triggerDriftDirection or 0) then
            commonTriggerDriftDirection = -1 -- Mixed values
        end

        -- Pitch range (with nil check)
        if container.pitchRange then
            if commonPitchMin == nil then
                commonPitchMin = container.pitchRange.min
                commonPitchMax = container.pitchRange.max
            else
                if math.abs(commonPitchMin - container.pitchRange.min) > 0.001 then commonPitchMin = -999 end
                if math.abs(commonPitchMax - container.pitchRange.max) > 0.001 then commonPitchMax = -999 end
            end
        end

        -- Volume range (with nil check)
        if container.volumeRange then
            if commonVolumeMin == nil then
                commonVolumeMin = container.volumeRange.min
                commonVolumeMax = container.volumeRange.max
            else
                if math.abs(commonVolumeMin - container.volumeRange.min) > 0.001 then commonVolumeMin = -999 end
                if math.abs(commonVolumeMax - container.volumeRange.max) > 0.001 then commonVolumeMax = -999 end
            end
        end

        -- Pan range (with nil check)
        if container.panRange then
            if commonPanMin == nil then
                commonPanMin = container.panRange.min
                commonPanMax = container.panRange.max
            else
                if math.abs(commonPanMin - container.panRange.min) > 0.001 then commonPanMin = -999 end
                if math.abs(commonPanMax - container.panRange.max) > 0.001 then commonPanMax = -999 end
            end
        end

        -- Chunk mode parameters
        if commonChunkDuration == nil then
            commonChunkDuration = container.chunkDuration or require("DM_Ambiance_Constants").DEFAULTS.CHUNK_DURATION
        elseif math.abs(commonChunkDuration - (container.chunkDuration or require("DM_Ambiance_Constants").DEFAULTS.CHUNK_DURATION)) > 0.001 then
            commonChunkDuration = -999 -- Mixed values
        end

        if commonChunkSilence == nil then
            commonChunkSilence = container.chunkSilence or require("DM_Ambiance_Constants").DEFAULTS.CHUNK_SILENCE
        elseif math.abs(commonChunkSilence - (container.chunkSilence or require("DM_Ambiance_Constants").DEFAULTS.CHUNK_SILENCE)) > 0.001 then
            commonChunkSilence = -999 -- Mixed values
        end

        if commonChunkDurationVariation == nil then
            commonChunkDurationVariation = container.chunkDurationVariation or require("DM_Ambiance_Constants").DEFAULTS.CHUNK_DURATION_VARIATION
        elseif commonChunkDurationVariation ~= (container.chunkDurationVariation or require("DM_Ambiance_Constants").DEFAULTS.CHUNK_DURATION_VARIATION) then
            commonChunkDurationVariation = -1 -- Mixed values
        end

        if commonChunkSilenceVariation == nil then
            commonChunkSilenceVariation = container.chunkSilenceVariation or require("DM_Ambiance_Constants").DEFAULTS.CHUNK_SILENCE_VARIATION
        elseif commonChunkSilenceVariation ~= (container.chunkSilenceVariation or require("DM_Ambiance_Constants").DEFAULTS.CHUNK_SILENCE_VARIATION) then
            commonChunkSilenceVariation = -1 -- Mixed values
        end

        if commonChunkDurationVarDirection == nil then
            commonChunkDurationVarDirection = container.chunkDurationVarDirection or 0
        elseif commonChunkDurationVarDirection ~= (container.chunkDurationVarDirection or 0) then
            commonChunkDurationVarDirection = -1 -- Mixed values
        end

        if commonChunkSilenceVarDirection == nil then
            commonChunkSilenceVarDirection = container.chunkSilenceVarDirection or 0
        elseif commonChunkSilenceVarDirection ~= (container.chunkSilenceVarDirection or 0) then
            commonChunkSilenceVarDirection = -1 -- Mixed values
        end

        -- Noise mode parameters
        local Constants = require("DM_Ambiance_Constants")
        if commonNoiseSeed == nil then
            commonNoiseSeed = container.noiseSeed or math.random(Constants.DEFAULTS.NOISE_SEED_MIN, Constants.DEFAULTS.NOISE_SEED_MAX)
        elseif commonNoiseSeed ~= (container.noiseSeed or math.random(Constants.DEFAULTS.NOISE_SEED_MIN, Constants.DEFAULTS.NOISE_SEED_MAX)) then
            commonNoiseSeed = -1 -- Mixed values
        end

        if commonNoiseFrequency == nil then
            commonNoiseFrequency = container.noiseFrequency or Constants.DEFAULTS.NOISE_FREQUENCY
        elseif math.abs(commonNoiseFrequency - (container.noiseFrequency or Constants.DEFAULTS.NOISE_FREQUENCY)) > 0.001 then
            commonNoiseFrequency = -999 -- Mixed values
        end

        if commonNoiseAmplitude == nil then
            commonNoiseAmplitude = container.noiseAmplitude or Constants.DEFAULTS.NOISE_AMPLITUDE
        elseif math.abs(commonNoiseAmplitude - (container.noiseAmplitude or Constants.DEFAULTS.NOISE_AMPLITUDE)) > 0.001 then
            commonNoiseAmplitude = -999 -- Mixed values
        end

        if commonNoiseOctaves == nil then
            commonNoiseOctaves = container.noiseOctaves or Constants.DEFAULTS.NOISE_OCTAVES
        elseif commonNoiseOctaves ~= (container.noiseOctaves or Constants.DEFAULTS.NOISE_OCTAVES) then
            commonNoiseOctaves = -1 -- Mixed values
        end

        if commonNoisePersistence == nil then
            commonNoisePersistence = container.noisePersistence or Constants.DEFAULTS.NOISE_PERSISTENCE
        elseif math.abs(commonNoisePersistence - (container.noisePersistence or Constants.DEFAULTS.NOISE_PERSISTENCE)) > 0.001 then
            commonNoisePersistence = -999 -- Mixed values
        end

        if commonNoiseLacunarity == nil then
            commonNoiseLacunarity = container.noiseLacunarity or Constants.DEFAULTS.NOISE_LACUNARITY
        elseif math.abs(commonNoiseLacunarity - (container.noiseLacunarity or Constants.DEFAULTS.NOISE_LACUNARITY)) > 0.001 then
            commonNoiseLacunarity = -999 -- Mixed values
        end

        if commonNoiseDensity == nil then
            commonNoiseDensity = container.noiseDensity or Constants.DEFAULTS.NOISE_DENSITY
        elseif math.abs(commonNoiseDensity - (container.noiseDensity or Constants.DEFAULTS.NOISE_DENSITY)) > 0.001 then
            commonNoiseDensity = -999 -- Mixed values
        end

        if commonNoiseThreshold == nil then
            commonNoiseThreshold = container.noiseThreshold or Constants.DEFAULTS.NOISE_THRESHOLD
        elseif math.abs(commonNoiseThreshold - (container.noiseThreshold or Constants.DEFAULTS.NOISE_THRESHOLD)) > 0.001 then
            commonNoiseThreshold = -999 -- Mixed values
        end

        if commonDensityLinkMode == nil then
            commonDensityLinkMode = container.densityLinkMode or "unlink"
        elseif commonDensityLinkMode ~= (container.densityLinkMode or "unlink") then
            commonDensityLinkMode = "mixed" -- Mixed values
        end

        ::continue_check::
    end

    -- TRIGGER SETTINGS SECTION

    -- Only show mixed values UI when interval MODE is mixed
    -- When mode is unified, drawTriggerSettingsSection handles everything (including rate/drift)
    if commonIntervalMode == -1 then
        -- Mode is mixed - show combo to unify
        imgui.Separator(globals.ctx)
        imgui.Text(globals.ctx, "Trigger Settings")
        imgui.Text(globals.ctx, "Interval Mode:")
        showMixedValues()

        -- Add a dropdown to set all values to the same value
        imgui.PushItemWidth(globals.ctx, width * 0.5)
        local intervalModes = "Absolute\0Relative\0Coverage\0Chunk\0Noise\0Euclidean\0"
        local rv, newIntervalMode = globals.UndoWrappers.Combo(globals.ctx, "Set all to##IntervalMode", 0, intervalModes)
        imgui.PopItemWidth(globals.ctx)
        if rv then
            -- Apply to all selected containers
            local affectedGroups = {}
            for _, c in ipairs(containers) do
                local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                if container then
                    container.intervalMode = newIntervalMode
                    local pathStr = globals.Utils.pathToString(c.groupPath)
                    affectedGroups[pathStr] = c.groupPath
                end
            end
            -- Sync euclidean bindings for all affected groups
            for pathStr, groupPath in pairs(affectedGroups) do
                local group = globals.Structures.getGroupFromPath(groupPath)
                if group then
                    globals.Structures.syncEuclideanBindings(group)
                end
            end
            -- Update state for UI refresh
            commonIntervalMode = newIntervalMode
        end
    end

    -- When interval mode is unified (not -1), use the standard trigger settings UI
    if commonIntervalMode ~= -1 then
        -- No mixed values - use the common UI for trigger settings
        local dataObj = {
            intervalMode = commonIntervalMode,
            triggerRate = commonTriggerRate,
            triggerDrift = commonTriggerDrift,
            triggerDriftDirection = commonTriggerDriftDirection,
            -- Chunk mode parameters
            chunkDuration = commonChunkDuration,
            chunkSilence = commonChunkSilence,
            chunkDurationVariation = commonChunkDurationVariation,
            chunkSilenceVariation = commonChunkSilenceVariation,
            chunkDurationVarDirection = commonChunkDurationVarDirection,
            chunkSilenceVarDirection = commonChunkSilenceVarDirection,
            -- Noise mode parameters
            noiseSeed = commonNoiseSeed,
            noiseFrequency = commonNoiseFrequency,
            noiseAmplitude = commonNoiseAmplitude,
            noiseOctaves = commonNoiseOctaves,
            noisePersistence = commonNoisePersistence,
            noiseLacunarity = commonNoiseLacunarity,
            noiseDensity = commonNoiseDensity,
            noiseThreshold = commonNoiseThreshold,
            densityLinkMode = commonDensityLinkMode
        }

        local callbacks = {
            setIntervalMode = function(newValue)
                local affectedGroups = {}
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.intervalMode = newValue
                        local pathStr = globals.Utils.pathToString(c.groupPath)
                        affectedGroups[pathStr] = c.groupPath
                    end
                end
                -- Sync euclidean bindings for all affected groups
                for pathStr, groupPath in pairs(affectedGroups) do
                    local group = globals.Structures.getGroupFromPath(groupPath)
                    if group then
                        globals.Structures.syncEuclideanBindings(group)
                    end
                end
                -- Update state for UI refresh
                commonIntervalMode = newValue
                dataObj.intervalMode = newValue  -- Update dataObj so UI refreshes immediately
            end,

            setTriggerRate = function(newValue)
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.triggerRate = newValue
                    end
                end
                -- Update state for UI refresh
                commonTriggerRate = newValue
            end,

            setTriggerDrift = function(newValue)
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.triggerDrift = newValue
                    end
                end
                -- Update state for UI refresh
                commonTriggerDrift = newValue
            end,

            setTriggerDriftDirection = function(newValue)
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.triggerDriftDirection = newValue
                    end
                end
                commonTriggerDriftDirection = newValue
            end,

            -- Chunk mode callbacks
            setChunkDuration = function(newValue)
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.chunkDuration = newValue
                    end
                end
                -- Update state for UI refresh
                commonChunkDuration = newValue
            end,

            setChunkSilence = function(newValue)
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.chunkSilence = newValue
                    end
                end
                -- Update state for UI refresh
                commonChunkSilence = newValue
            end,

            setChunkDurationVariation = function(newValue)
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.chunkDurationVariation = newValue
                    end
                end
                -- Update state for UI refresh
                commonChunkDurationVariation = newValue
            end,
            setChunkSilenceVariation = function(newValue)
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.chunkSilenceVariation = newValue
                    end
                end
                -- Update state for UI refresh
                commonChunkSilenceVariation = newValue
            end,

            setChunkDurationVarDirection = function(newValue)
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.chunkDurationVarDirection = newValue
                    end
                end
                commonChunkDurationVarDirection = newValue
            end,

            setChunkSilenceVarDirection = function(newValue)
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.chunkSilenceVarDirection = newValue
                    end
                end
                commonChunkSilenceVarDirection = newValue
            end,

            -- Noise mode callbacks
            setNoiseSeed = function(newValue)
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.noiseSeed = newValue
                    end
                end
                commonNoiseSeed = newValue
            end,

            setNoiseFrequency = function(newValue)
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.noiseFrequency = newValue
                    end
                end
                commonNoiseFrequency = newValue
            end,

            setNoiseAmplitude = function(newValue)
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.noiseAmplitude = newValue
                    end
                end
                commonNoiseAmplitude = newValue
            end,

            setNoiseOctaves = function(newValue)
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.noiseOctaves = newValue
                    end
                end
                commonNoiseOctaves = newValue
            end,

            setNoisePersistence = function(newValue)
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.noisePersistence = newValue
                    end
                end
                commonNoisePersistence = newValue
            end,

            setNoiseLacunarity = function(newValue)
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.noiseLacunarity = newValue
                    end
                end
                commonNoiseLacunarity = newValue
            end,

            setNoiseDensity = function(newValue)
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.noiseDensity = newValue
                    end
                end
                commonNoiseDensity = newValue
            end,

            setNoiseThreshold = function(newValue)
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        container.noiseThreshold = newValue
                    end
                end
                commonNoiseThreshold = newValue
            end
        }

        -- Use the common trigger settings function
        -- Multi-selection doesn't support auto-bind (not a group context)
        -- Pass stableId "MultiSelection" for stable ImGui widget IDs (last parameter)
        globals.UI.drawTriggerSettingsSection(dataObj, callbacks, width, "", nil, false, nil, nil, "MultiSelection")
    end

    -- RANDOMIZATION PARAMETERS SECTION
    imgui.Separator(globals.ctx)
    imgui.Text(globals.ctx, "Randomization parameters")

    -- Pitch randomization checkbox
    local pitchState = allRandomizePitch and 1 or (anyRandomizePitch and 2 or 0)
    local pitchText = "Randomize Pitch"
    if pitchState == 2 then -- Mixed values
        pitchText = pitchText .. " (Mixed)"
    end

    -- Custom drawing of the three-state checkbox
    local randomizePitch = false
    if pitchState == 1 then
        randomizePitch = true
    end

    local rv, newRandomizePitch = globals.UndoWrappers.Checkbox(globals.ctx, pitchText, randomizePitch)
    if rv then
        -- Apply to all selected containers
        for _, c in ipairs(containers) do
            local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
            if container then
                container.randomizePitch = newRandomizePitch
            end
        end

        -- Update state for UI refresh
        if newRandomizePitch then
            anyRandomizePitch = true
            allRandomizePitch = true
        else
            anyRandomizePitch = false
            allRandomizePitch = false
        end
    end

    -- Pitch mode toggle button (similar to main UI)
    imgui.SameLine(globals.ctx)
    imgui.Dummy(globals.ctx, 20, 0)  -- Add some spacing
    imgui.SameLine(globals.ctx)

    -- Determine common pitch mode
    local firstContainer = containers[1] and globals.Structures.getContainerFromGroup(containers[1].groupPath, containers[1].containerIndex)
    local commonPitchMode = firstContainer and firstContainer.pitchMode or Constants.PITCH_MODES.PITCH
    local hasMixedPitchModes = false
    for _, c in ipairs(containers) do
        local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
        if container then
            if not container.pitchMode then container.pitchMode = Constants.PITCH_MODES.PITCH end
            if container.pitchMode ~= commonPitchMode then
                hasMixedPitchModes = true
                break
            end
        end
    end

    local pitchModeLabel = hasMixedPitchModes and "Pitch Mode (Mixed)" or
                          (commonPitchMode == Constants.PITCH_MODES.STRETCH and "Stretch" or "Pitch")

    -- State tracking for text color feedback (similar to icon buttons)
    if not globals.pitchModeButtonStates then
        globals.pitchModeButtonStates = {}
    end
    local stateKey = "pitchMode_multi"
    local previousState = globals.pitchModeButtonStates[stateKey] or "normal"

    -- Get base text color
    local baseTextColor = imgui.GetStyleColor(globals.ctx, imgui.Col_Text)

    -- Calculate text color based on previous state
    local textColor = baseTextColor
    if previousState == "active" then
        -- Active: darken
        textColor = globals.Utils.brightenColor(baseTextColor, -0.2)
    elseif previousState == "hovered" then
        -- Hover: brighten
        textColor = globals.Utils.brightenColor(baseTextColor, 0.3)
    end

    -- Apply text color
    imgui.PushStyleColor(globals.ctx, imgui.Col_Text, textColor)

    -- Make button background invisible (no highlight on hover/active)
    imgui.PushStyleColor(globals.ctx, imgui.Col_Button, 0x00000000)
    imgui.PushStyleColor(globals.ctx, imgui.Col_ButtonHovered, 0x00000000)
    imgui.PushStyleColor(globals.ctx, imgui.Col_ButtonActive, 0x00000000)

    local clicked = imgui.Button(globals.ctx, pitchModeLabel .. "##MultiPitchModeToggle")

    imgui.PopStyleColor(globals.ctx, 4)

    -- Update state for next frame
    if imgui.IsItemActive(globals.ctx) then
        globals.pitchModeButtonStates[stateKey] = "active"
    elseif imgui.IsItemHovered(globals.ctx) then
        globals.pitchModeButtonStates[stateKey] = "hovered"
    else
        globals.pitchModeButtonStates[stateKey] = "normal"
    end

    if clicked then
        -- Toggle all selected containers
        local newMode = (commonPitchMode == Constants.PITCH_MODES.PITCH) and Constants.PITCH_MODES.STRETCH or Constants.PITCH_MODES.PITCH
        for _, c in ipairs(containers) do
            local group = globals.Structures.getGroupFromPath(c.groupPath)
            local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
            if group and container then
                container.pitchMode = newMode
                container.needsRegeneration = true

                -- Sync B_PPITCH on existing items
                globals.Generation.syncPitchModeOnExistingItems(group, container)
            end
        end
        if globals.History then
            globals.History.captureState("Toggle pitch mode (multi-selection)")
        end
    end

    if imgui.IsItemHovered(globals.ctx) then
        imgui.SetTooltip(globals.ctx, "Click to toggle between Pitch and Stretch modes for all selected containers")
    end

    -- Only show pitch range if any container uses pitch randomization
    if anyRandomizePitch then
        -- Use defaults if nil
        local pitchMin = commonPitchMin or -12
        local pitchMax = commonPitchMax or 12

        if commonPitchMin == -999 or commonPitchMax == -999 then
            -- Mixed values - show a text indicator and editable field
            imgui.Text(globals.ctx, "Pitch Range (semitones):")
            showMixedValues()

            -- Add a range slider to set all values to the same value
            imgui.PushItemWidth(globals.ctx, width * 0.7)
            local rv, newPitchMin, newPitchMax = globals.UndoWrappers.DragFloatRange2(globals.ctx,
                                                                      "Set all to##PitchRange",
                                                                      -12, 12, 0.1, -48, 48)
            imgui.PopItemWidth(globals.ctx)
            if rv then
                -- Apply to all selected containers
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        if not container.pitchRange then container.pitchRange = {} end
                        container.pitchRange.min = newPitchMin
                        container.pitchRange.max = newPitchMax
                    end
                end

                -- Update state for UI refresh
                commonPitchMin = newPitchMin
                commonPitchMax = newPitchMax
            end
        else
            -- All containers have the same value - normal edit
            imgui.PushItemWidth(globals.ctx, width * 0.7)
            local rv, newPitchMin, newPitchMax = globals.UndoWrappers.DragFloatRange2(globals.ctx,
                                                                      "Pitch Range (semitones)",
                                                                      pitchMin, pitchMax, 0.1, -48, 48)
            imgui.PopItemWidth(globals.ctx)
            if rv then
                -- Apply to all selected containers
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        if not container.pitchRange then container.pitchRange = {} end
                        container.pitchRange.min = newPitchMin
                        container.pitchRange.max = newPitchMax
                    end
                end

                -- Update state for UI refresh
                commonPitchMin = newPitchMin
                commonPitchMax = newPitchMax
            end
        end
    end

    -- Volume randomization checkbox
    local volumeState = allRandomizeVolume and 1 or (anyRandomizeVolume and 2 or 0)
    local volumeText = "Randomize Volume"
    if volumeState == 2 then -- Mixed values
        volumeText = volumeText .. " (Mixed)"
    end

    -- Custom drawing of the three-state checkbox
    local randomizeVolume = false
    if volumeState == 1 then
        randomizeVolume = true
    end

    local rv, newRandomizeVolume = globals.UndoWrappers.Checkbox(globals.ctx, volumeText, randomizeVolume)
    if rv then
        -- Apply to all selected containers
        for _, c in ipairs(containers) do
            local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
            if container then
                container.randomizeVolume = newRandomizeVolume
            end
        end

        -- Update state for UI refresh
        if newRandomizeVolume then
            anyRandomizeVolume = true
            allRandomizeVolume = true
        else
            anyRandomizeVolume = false
            allRandomizeVolume = false
        end
    end

    -- Only show volume range if any container uses volume randomization
    if anyRandomizeVolume then
        -- Use defaults if nil
        local volumeMin = commonVolumeMin or -6
        local volumeMax = commonVolumeMax or 6

        if commonVolumeMin == -999 or commonVolumeMax == -999 then
            -- Mixed values - show a text indicator and editable field
            imgui.Text(globals.ctx, "Volume Range (dB):")
            showMixedValues()

            -- Add a range slider to set all values to the same value
            imgui.PushItemWidth(globals.ctx, width * 0.7)
            local rv, newVolumeMin, newVolumeMax = globals.UndoWrappers.DragFloatRange2(globals.ctx,
                                                                       "Set all to##VolumeRange",
                                                                       -6, 6, 0.1, -24, 24)
            imgui.PopItemWidth(globals.ctx)
            if rv then
                -- Apply to all selected containers
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        if not container.volumeRange then container.volumeRange = {} end
                        container.volumeRange.min = newVolumeMin
                        container.volumeRange.max = newVolumeMax
                    end
                end

                -- Update state for UI refresh
                commonVolumeMin = newVolumeMin
                commonVolumeMax = newVolumeMax
            end
        else
            -- All containers have the same value - normal edit
            imgui.PushItemWidth(globals.ctx, width * 0.7)
            local rv, newVolumeMin, newVolumeMax = globals.UndoWrappers.DragFloatRange2(globals.ctx,
                                                                       "Volume Range (dB)",
                                                                       volumeMin, volumeMax, 0.1, -24, 24)
            imgui.PopItemWidth(globals.ctx)
            if rv then
                -- Apply to all selected containers
                for _, c in ipairs(containers) do
                    local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                    if container then
                        if not container.volumeRange then container.volumeRange = {} end
                        container.volumeRange.min = newVolumeMin
                        container.volumeRange.max = newVolumeMax
                    end
                end

                -- Update state for UI refresh
                commonVolumeMin = newVolumeMin
                commonVolumeMax = newVolumeMax
            end
        end
    end

    -- Pan randomization controls (show if ANY container supports pan - i.e., is stereo)
    if anyStereo then
        -- Show note if some containers are multichannel
        if anyMultiChannel then
            imgui.TextColored(globals.ctx, 0xFFAA00FF, "(Pan applies to stereo containers only)")
        end

        -- Pan randomization checkbox
        local panState = allRandomizePan and 1 or (anyRandomizePan and 2 or 0)
        local panText = "Randomize Pan"
        if panState == 2 then -- Mixed values
            panText = panText .. " (Mixed)"
        end

        -- Custom drawing of the three-state checkbox
        local randomizePan = false
        if panState == 1 then
            randomizePan = true
        end

        local rv, newRandomizePan = globals.UndoWrappers.Checkbox(globals.ctx, panText, randomizePan)
        if rv then
            -- Apply only to stereo containers (not multichannel)
            for _, c in ipairs(containers) do
                local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                if container and (not container.channelMode or container.channelMode == 0) then
                    container.randomizePan = newRandomizePan
                end
            end

            -- Update state for UI refresh
            if newRandomizePan then
                anyRandomizePan = true
                allRandomizePan = true
            else
                anyRandomizePan = false
                allRandomizePan = false
            end
        end

        -- Only show pan range if any container uses pan randomization
        if anyRandomizePan then
            -- Use defaults if nil
            local panMin = commonPanMin or -50
            local panMax = commonPanMax or 50

            if commonPanMin == -999 or commonPanMax == -999 then
                -- Mixed values - show a text indicator and editable field
                imgui.Text(globals.ctx, "Pan Range (-100/+100):")
                showMixedValues()

                -- Add a range slider to set all values to the same value
                imgui.PushItemWidth(globals.ctx, width * 0.7)
                local rv, newPanMin, newPanMax = globals.UndoWrappers.DragFloatRange2(globals.ctx,
                                                                     "Set all to##PanRange",
                                                                     -50, 50, 1, -100, 100)
                imgui.PopItemWidth(globals.ctx)
                if rv then
                    -- Apply only to stereo containers
                    for _, c in ipairs(containers) do
                        local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                        if container and (not container.channelMode or container.channelMode == 0) then
                            if not container.panRange then container.panRange = {} end
                            container.panRange.min = newPanMin
                            container.panRange.max = newPanMax
                        end
                    end

                    -- Update state for UI refresh
                    commonPanMin = newPanMin
                    commonPanMax = newPanMax
                end
            else
                -- All containers have the same value - normal edit
                imgui.PushItemWidth(globals.ctx, width * 0.7)
                local rv, newPanMin, newPanMax = globals.UndoWrappers.DragFloatRange2(globals.ctx,
                                                                     "Pan Range (-100/+100)",
                                                                     panMin, panMax, 1, -100, 100)
                imgui.PopItemWidth(globals.ctx)
                if rv then
                    -- Apply only to stereo containers
                    for _, c in ipairs(containers) do
                        local container = globals.Structures.getContainerFromGroup(c.groupPath, c.containerIndex)
                        if container and (not container.channelMode or container.channelMode == 0) then
                            if not container.panRange then container.panRange = {} end
                            container.panRange.min = newPanMin
                            container.panRange.max = newPanMax
                        end
                    end

                    -- Update state for UI refresh
                    commonPanMin = newPanMin
                    commonPanMax = newPanMax
                end
            end
        end  -- End of anyRandomizePan condition
    end  -- End of anyStereo condition
end

return UI_MultiSelection
