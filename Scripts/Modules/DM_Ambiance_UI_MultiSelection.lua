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

-- Function to get all selected containers as a table of {groupIndex, containerIndex} pairs
function UI_MultiSelection.getSelectedContainersList()
    local containers = {}
    for key in pairs(globals.selectedContainers) do
        local t, c = key:match("(%d+)_(%d+)")
        table.insert(containers, {groupIndex = tonumber(t), containerIndex = tonumber(c)})
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
        imgui.TextColored(globals.ctx, 0xFFAA00FF, "No containers selected. Select containers to edit them.")
        return
    end

    -- Get list of all selected containers
    local containers = UI_MultiSelection.getSelectedContainersList()

    -- Button to regenerate all selected containers
    if imgui.Button(globals.ctx, "Regenerate All", width * 0.5, 30) then
        for _, c in ipairs(containers) do
            globals.Generation.generateSingleContainer(c.groupIndex, c.containerIndex)
        end
    end

    imgui.Separator(globals.ctx)

    -- Collect info about override parent status
    local anyOverrideParent = false
    local allOverrideParent = true

    -- Check all containers for override parent setting
    for _, c in ipairs(containers) do
        local groupIndex = c.groupIndex
        local containerIndex = c.containerIndex
        local container = globals.groups[groupIndex].containers[containerIndex]

        -- Override parent status
        if container.overrideParent then
            anyOverrideParent = true
        else
            allOverrideParent = false
        end
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
        for _, c in ipairs(containers) do
            globals.groups[c.groupIndex].containers[c.containerIndex].overrideParent = newOverrideParent
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

    -- Default values for common parameters
    local commonIntervalMode = nil
    local commonTriggerRate = nil
    local commonTriggerDrift = nil
    local commonPitchMin, commonPitchMax = nil, nil
    local commonVolumeMin, commonVolumeMax = nil, nil
    local commonPanMin, commonPanMax = nil, nil
    -- Chunk mode parameters
    local commonChunkDuration = nil
    local commonChunkSilence = nil
    local commonChunkDurationVariation = nil
    local commonChunkSilenceVariation = nil

    -- Check all containers to determine common settings
    for _, c in ipairs(containers) do
        local groupIndex = c.groupIndex
        local containerIndex = c.containerIndex
        local container = globals.groups[groupIndex].containers[containerIndex]

        -- Check if this container is multichannel (non-stereo)
        if container.channelMode and container.channelMode > 0 then
            anyMultiChannel = true
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

        -- Pitch range
        if commonPitchMin == nil then
            commonPitchMin = container.pitchRange.min
            commonPitchMax = container.pitchRange.max
        else
            if math.abs(commonPitchMin - container.pitchRange.min) > 0.001 then commonPitchMin = -999 end
            if math.abs(commonPitchMax - container.pitchRange.max) > 0.001 then commonPitchMax = -999 end
        end

        -- Volume range
        if commonVolumeMin == nil then
            commonVolumeMin = container.volumeRange.min
            commonVolumeMax = container.volumeRange.max
        else
            if math.abs(commonVolumeMin - container.volumeRange.min) > 0.001 then commonVolumeMin = -999 end
            if math.abs(commonVolumeMax - container.volumeRange.max) > 0.001 then commonVolumeMax = -999 end
        end

        -- Pan range
        if commonPanMin == nil then
            commonPanMin = container.panRange.min
            commonPanMax = container.panRange.max
        else
            if math.abs(commonPanMin - container.panRange.min) > 0.001 then commonPanMin = -999 end
            if math.abs(commonPanMax - container.panRange.max) > 0.001 then commonPanMax = -999 end
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
    end

    -- TRIGGER SETTINGS SECTION
    
    -- Check if we have mixed values for any trigger settings
    local hasMixedTriggerValues = (commonIntervalMode == -1 or commonTriggerRate == -999 or commonTriggerDrift == -1)
    
    if hasMixedTriggerValues then
        -- Handle mixed values case by case
        imgui.Separator(globals.ctx)
        imgui.Text(globals.ctx, "Trigger Settings")
        
        -- Interval Mode - handle mixed values
        if commonIntervalMode == -1 then
            imgui.Text(globals.ctx, "Interval Mode:")
            showMixedValues()
            
            -- Add a dropdown to set all values to the same value
            imgui.PushItemWidth(globals.ctx, width * 0.5)
            local intervalModes = "Absolute\0Relative\0Coverage\0Chunk\0"
            local rv, newIntervalMode = globals.UndoWrappers.Combo(globals.ctx, "Set all to##IntervalMode", 0, intervalModes)
            if rv then
                -- Apply to all selected containers
                for _, c in ipairs(containers) do
                    globals.groups[c.groupIndex].containers[c.containerIndex].intervalMode = newIntervalMode
                end
                -- Update state for UI refresh
                commonIntervalMode = newIntervalMode
            end
        else
            -- Display current mode as text
            local modeText = "Absolute"
            if commonIntervalMode == 1 then modeText = "Relative"
            elseif commonIntervalMode == 2 then modeText = "Coverage" end
            
            imgui.Text(globals.ctx, "Interval Mode: " .. modeText)
        end
        
        -- Trigger rate - handle mixed values
        if commonTriggerRate == -999 then
            -- Different labels based on mode
            local triggerRateLabel = "Interval (sec)"
            local triggerRateMin = -10.0
            local triggerRateMax = 60.0
            
            if commonIntervalMode == 1 then
                triggerRateLabel = "Interval (%)"
                triggerRateMin = 0.1
                triggerRateMax = 100.0
            elseif commonIntervalMode == 2 then
                triggerRateLabel = "Coverage (%)"
                triggerRateMin = 0.1
                triggerRateMax = 100.0
            end
            
            imgui.Text(globals.ctx, triggerRateLabel .. ":")
            showMixedValues()
            
            -- Add a slider to set all values to the same value
            imgui.PushItemWidth(globals.ctx, width * 0.5)
            local rv, newTriggerRate = globals.UndoWrappers.SliderDouble(globals.ctx, "Set all to##TriggerRate",
                                                        0, triggerRateMin, triggerRateMax, "%.1f")
            if rv then
                -- Apply to all selected containers
                for _, c in ipairs(containers) do
                    globals.groups[c.groupIndex].containers[c.containerIndex].triggerRate = newTriggerRate
                end
                -- Update state for UI refresh
                commonTriggerRate = newTriggerRate
            end
        end

        -- Trigger drift - handle mixed values
        if commonTriggerDrift == -1 then
            imgui.Text(globals.ctx, "Random variation (%):")
            showMixedValues()

            -- Add a slider to set all values to the same value
            imgui.PushItemWidth(globals.ctx, width * 0.5)
            local rv, newTriggerDrift = globals.UndoWrappers.SliderInt(globals.ctx, "Set all to##TriggerDrift", 0, 0, 100, "%d")
            if rv then
                -- Apply to all selected containers
                for _, c in ipairs(containers) do
                    globals.groups[c.groupIndex].containers[c.containerIndex].triggerDrift = newTriggerDrift
                end
                -- Update state for UI refresh
                commonTriggerDrift = newTriggerDrift
            end
        end
    else
        -- No mixed values - use the common UI for trigger settings
        local dataObj = {
            intervalMode = commonIntervalMode,
            triggerRate = commonTriggerRate,
            triggerDrift = commonTriggerDrift,
            -- Chunk mode parameters
            chunkDuration = commonChunkDuration,
            chunkSilence = commonChunkSilence,
            chunkDurationVariation = commonChunkDurationVariation,
            chunkSilenceVariation = commonChunkSilenceVariation
        }
        
        local callbacks = {
            setIntervalMode = function(newValue)
                for _, c in ipairs(containers) do
                    globals.groups[c.groupIndex].containers[c.containerIndex].intervalMode = newValue
                end
                -- Update state for UI refresh
                commonIntervalMode = newValue
            end,
            
            setTriggerRate = function(newValue)
                for _, c in ipairs(containers) do
                    globals.groups[c.groupIndex].containers[c.containerIndex].triggerRate = newValue
                end
                -- Update state for UI refresh
                commonTriggerRate = newValue
            end,
            
            setTriggerDrift = function(newValue)
                for _, c in ipairs(containers) do
                    globals.groups[c.groupIndex].containers[c.containerIndex].triggerDrift = newValue
                end
                -- Update state for UI refresh
                commonTriggerDrift = newValue
            end,
            
            -- Chunk mode callbacks
            setChunkDuration = function(newValue)
                for _, c in ipairs(containers) do
                    globals.groups[c.groupIndex].containers[c.containerIndex].chunkDuration = newValue
                end
                -- Update state for UI refresh
                commonChunkDuration = newValue
            end,
            
            setChunkSilence = function(newValue)
                for _, c in ipairs(containers) do
                    globals.groups[c.groupIndex].containers[c.containerIndex].chunkSilence = newValue
                end
                -- Update state for UI refresh
                commonChunkSilence = newValue
            end,
            
            setChunkDurationVariation = function(newValue)
                for _, c in ipairs(containers) do
                    globals.groups[c.groupIndex].containers[c.containerIndex].chunkDurationVariation = newValue
                end
                -- Update state for UI refresh
                commonChunkDurationVariation = newValue
            end,
            setChunkSilenceVariation = function(newValue)
                for _, c in ipairs(containers) do
                    globals.groups[c.groupIndex].containers[c.containerIndex].chunkSilenceVariation = newValue
                end
                -- Update state for UI refresh
                commonChunkSilenceVariation = newValue
            end
        }
        
        -- Use the common trigger settings function
        globals.UI.drawTriggerSettingsSection(dataObj, callbacks, width, "", nil)
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
            globals.groups[c.groupIndex].containers[c.containerIndex].randomizePitch = newRandomizePitch
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

    -- Only show pitch range if any container uses pitch randomization
    if anyRandomizePitch then
        if commonPitchMin == -999 or commonPitchMax == -999 then
            -- Mixed values - show a text indicator and editable field
            imgui.Text(globals.ctx, "Pitch Range (semitones):")
            showMixedValues()

            -- Add a range slider to set all values to the same value
            imgui.PushItemWidth(globals.ctx, width * 0.7)
            local rv, newPitchMin, newPitchMax = imgui.DragFloatRange2(globals.ctx,
                                                                      "Set all to##PitchRange",
                                                                      -12, 12, 0.1, -48, 48)
            if rv then
                -- Apply to all selected containers
                for _, c in ipairs(containers) do
                    globals.groups[c.groupIndex].containers[c.containerIndex].pitchRange.min = newPitchMin
                    globals.groups[c.groupIndex].containers[c.containerIndex].pitchRange.max = newPitchMax
                end

                -- Update state for UI refresh
                commonPitchMin = newPitchMin
                commonPitchMax = newPitchMax
            end
        else
            -- All containers have the same value - normal edit
            imgui.PushItemWidth(globals.ctx, width * 0.7)
            local rv, newPitchMin, newPitchMax = imgui.DragFloatRange2(globals.ctx,
                                                                      "Pitch Range (semitones)",
                                                                      commonPitchMin, commonPitchMax, 0.1, -48, 48)
            if rv then
                -- Apply to all selected containers
                for _, c in ipairs(containers) do
                    globals.groups[c.groupIndex].containers[c.containerIndex].pitchRange.min = newPitchMin
                    globals.groups[c.groupIndex].containers[c.containerIndex].pitchRange.max = newPitchMax
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
            globals.groups[c.groupIndex].containers[c.containerIndex].randomizeVolume = newRandomizeVolume
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
        if commonVolumeMin == -999 or commonVolumeMax == -999 then
            -- Mixed values - show a text indicator and editable field
            imgui.Text(globals.ctx, "Volume Range (dB):")
            showMixedValues()

            -- Add a range slider to set all values to the same value
            imgui.PushItemWidth(globals.ctx, width * 0.7)
            local rv, newVolumeMin, newVolumeMax = imgui.DragFloatRange2(globals.ctx,
                                                                       "Set all to##VolumeRange",
                                                                       -6, 6, 0.1, -24, 24)
            if rv then
                -- Apply to all selected containers
                for _, c in ipairs(containers) do
                    globals.groups[c.groupIndex].containers[c.containerIndex].volumeRange.min = newVolumeMin
                    globals.groups[c.groupIndex].containers[c.containerIndex].volumeRange.max = newVolumeMax
                end

                -- Update state for UI refresh
                commonVolumeMin = newVolumeMin
                commonVolumeMax = newVolumeMax
            end
        else
            -- All containers have the same value - normal edit
            imgui.PushItemWidth(globals.ctx, width * 0.7)
            local rv, newVolumeMin, newVolumeMax = imgui.DragFloatRange2(globals.ctx,
                                                                       "Volume Range (dB)",
                                                                       commonVolumeMin, commonVolumeMax, 0.1, -24, 24)
            if rv then
                -- Apply to all selected containers
                for _, c in ipairs(containers) do
                    globals.groups[c.groupIndex].containers[c.containerIndex].volumeRange.min = newVolumeMin
                    globals.groups[c.groupIndex].containers[c.containerIndex].volumeRange.max = newVolumeMax
                end

                -- Update state for UI refresh
                commonVolumeMin = newVolumeMin
                commonVolumeMax = newVolumeMax
            end
        end
    end

    -- Pan randomization controls (only show if no containers are multichannel)
    if not anyMultiChannel then
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
            -- Apply to all selected containers
            for _, c in ipairs(containers) do
                globals.groups[c.groupIndex].containers[c.containerIndex].randomizePan = newRandomizePan
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
        if commonPanMin == -999 or commonPanMax == -999 then
            -- Mixed values - show a text indicator and editable field
            imgui.Text(globals.ctx, "Pan Range (-100/+100):")
            showMixedValues()

            -- Add a range slider to set all values to the same value
            imgui.PushItemWidth(globals.ctx, width * 0.7)
            local rv, newPanMin, newPanMax = imgui.DragFloatRange2(globals.ctx,
                                                                 "Set all to##PanRange",
                                                                 -50, 50, 1, -100, 100)
            if rv then
                -- Apply to all selected containers
                for _, c in ipairs(containers) do
                    globals.groups[c.groupIndex].containers[c.containerIndex].panRange.min = newPanMin
                    globals.groups[c.groupIndex].containers[c.containerIndex].panRange.max = newPanMax
                end

                -- Update state for UI refresh
                commonPanMin = newPanMin
                commonPanMax = newPanMax
            end
        else
            -- All containers have the same value - normal edit
            imgui.PushItemWidth(globals.ctx, width * 0.7)
            local rv, newPanMin, newPanMax = imgui.DragFloatRange2(globals.ctx,
                                                                 "Pan Range (-100/+100)",
                                                                 commonPanMin, commonPanMax, 1, -100, 100)
            if rv then
                -- Apply to all selected containers
                for _, c in ipairs(containers) do
                    globals.groups[c.groupIndex].containers[c.containerIndex].panRange.min = newPanMin
                    globals.groups[c.groupIndex].containers[c.containerIndex].panRange.max = newPanMax
                end

                -- Update state for UI refresh
                commonPanMin = newPanMin
                commonPanMax = newPanMax
            end
        end
        end  -- End of anyRandomizePan condition
    end  -- End of anyMultiChannel condition
end

return UI_MultiSelection
