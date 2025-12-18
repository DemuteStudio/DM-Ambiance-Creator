--[[
@version 1.5
@noindex
--]]

-- Trigger Settings Section for DM Ambiance Creator
-- Extracted from DM_Ambiance_UI.lua
-- Handles trigger mode controls (Absolute, Relative, Coverage, Chunk, Noise, Euclidean)

local TriggerSection = {}
local globals = {}

-- Get script path for loading sub-modules
local info = debug.getinfo(1, "S")
local modulePath = info.source:match[[^@?(.*[\\/])[^\\/]-$]]

-- Load sub-modules for complex interval modes
local TriggerSection_Noise = dofile(modulePath .. "UI/TriggerSection_Noise.lua")
local TriggerSection_Euclidean = dofile(modulePath .. "UI/TriggerSection_Euclidean.lua")

function TriggerSection.initModule(g)
    globals = g

    -- Initialize tracking table for variation sliders auto-regeneration
    if not globals.autoRegenTracking then
        globals.autoRegenTracking = {}
    end

    -- Initialize sub-modules
    TriggerSection_Noise.initModule(g)
    TriggerSection_Euclidean.initModule(g)
end

-- Helper function: Get Euclidean layer color
local function getEuclideanLayerColor(layerIndex, alpha)
    return globals.EuclideanUI.getLayerColor(layerIndex, alpha)
end

-- Helper function: Draw a slider row with automatic variation controls using table layout
-- This provides consistent alignment without pixel-perfect positioning
local function drawSliderWithVariation(params)
    local imgui = globals.imgui
    local sliderId = params.sliderId
    local sliderValue = params.sliderValue
    local sliderMin = params.sliderMin
    local sliderMax = params.sliderMax
    local sliderFormat = params.sliderFormat or "%.1f"
    local sliderLabel = params.sliderLabel
    local helpText = params.helpText
    local trackingKey = params.trackingKey
    local callbacks = params.callbacks
    local autoRegenCallback = params.autoRegenCallback
    local checkAutoRegen = params.checkAutoRegen
    local defaultValue = params.defaultValue or sliderValue  -- Default to current value if not specified

    -- Variation params (optional)
    local variationEnabled = params.variationEnabled ~= false  -- default true
    local variationValue = params.variationValue
    local variationDirection = params.variationDirection
    local variationLabel = params.variationLabel or "Var"
    local variationCallbacks = params.variationCallbacks or {}
    local defaultVariation = params.defaultVariation or 0  -- Variation default is typically 0

    local sliderWidth = params.sliderWidth or -1  -- -1 means fill available space

    imgui.TableNextRow(globals.ctx)

    -- Column 1: Slider
    imgui.TableSetColumnIndex(globals.ctx, 0)
    if sliderWidth > 0 then
        imgui.PushItemWidth(globals.ctx, sliderWidth)
    else
        imgui.PushItemWidth(globals.ctx, -1)  -- Fill column width
    end

    globals.SliderEnhanced.SliderDouble({
        id = sliderId,
        value = sliderValue,
        min = sliderMin,
        max = sliderMax,
        defaultValue = defaultValue,
        format = sliderFormat,
        onChange = function(newValue, wasReset)
            if callbacks.setValue then
                callbacks.setValue(newValue)
            end
        end,
        onChangeComplete = function(oldValue, newValue)
            if checkAutoRegen then
                checkAutoRegen(trackingKey, oldValue, newValue)
            end
        end
    })

    imgui.PopItemWidth(globals.ctx)

    -- Column 2: Label with help marker
    imgui.TableSetColumnIndex(globals.ctx, 1)
    imgui.Text(globals.ctx, sliderLabel)
    if helpText then
        imgui.SameLine(globals.ctx)
        globals.Utils.HelpMarker(helpText)
    end

    -- Column 3: Variation controls (if enabled)
    if variationEnabled and variationValue ~= nil then
        imgui.TableSetColumnIndex(globals.ctx, 2)

        -- Direction button (using icon button)
        local dirChanged, newDirection = globals.Icons.createVariationDirectionButton(
            globals.ctx,
            trackingKey .. "_dir",
            variationDirection
        )
        if dirChanged and variationCallbacks.setDirection then
            variationCallbacks.setDirection(newDirection)
        end

        imgui.SameLine(globals.ctx, 0, 2)

        -- Variation knob
        local varKey = trackingKey .. "_var"
        local rvVar, newVar, wasResetVar = globals.Knob.Knob({
            id = "##" .. varKey,
            label = "",
            value = variationValue,
            min = 0,
            max = 100,
            defaultValue = defaultVariation,
            size = 24,
            format = "%d",
            showLabel = false
        })

        -- Auto-regen tracking (skip if this was a reset)
        if not wasResetVar then
            if imgui.IsItemActive(globals.ctx) and autoRegenCallback and not globals.autoRegenTracking[varKey] then
                globals.autoRegenTracking[varKey] = variationValue
            end
        end

        if rvVar and variationCallbacks.setValue then variationCallbacks.setValue(math.floor(newVar + 0.5)) end

        -- Only check auto-regen if NOT a reset
        -- Note: Knob uses InvisibleButton, so use IsItemDeactivated instead of IsItemDeactivatedAfterEdit
        if not wasResetVar then
            local wasActive = globals.autoRegenTracking[varKey] ~= nil
            local isActive = imgui.IsItemActive(globals.ctx)

            -- Detect transition from active to inactive (release)
            if wasActive and not isActive then
                local oldValue = globals.autoRegenTracking[varKey]
                local newValue = math.floor(newVar + 0.5)  -- Use the actual new value from the knob
                if oldValue ~= newValue and globals.timeSelectionValid and autoRegenCallback then
                    autoRegenCallback(varKey, oldValue, newValue)
                end
                globals.autoRegenTracking[varKey] = nil
            end
        end

        imgui.SameLine(globals.ctx, 0, 2)
        imgui.Text(globals.ctx, string.format("%s %d%%", variationLabel, variationValue))
    end

    return rv, newValue
end

-- Draw the trigger settings section (shared by groups and containers)
-- dataObj must expose: intervalMode, triggerRate, triggerDrift, fadeIn, fadeOut
-- callbacks must provide setters for each parameter
function TriggerSection.drawTriggerSettingsSection(dataObj, callbacks, width, titlePrefix, autoRegenCallback, isGroup, groupPath, containerIndex, stableId)
    local imgui = globals.imgui
    local UI = globals.UI

    -- Section separator and title
    imgui.Separator(globals.ctx)
    imgui.Text(globals.ctx, (titlePrefix or "") .. "Generation Settings")

    -- Initialize auto-regen tracking if not exists and callback provided

    -- Create unique tracking key for this function call
    -- Use stableId if provided (for multi-selection), otherwise use titlePrefix or dataObj address
    local trackingKey = stableId or ((titlePrefix and titlePrefix ~= "") and titlePrefix or tostring(dataObj))

    -- Helper function for auto-regeneration check
    -- Called from onChangeComplete with (paramName, oldValue, newValue)
    local function checkAutoRegen(paramName, oldValue, newValue)
        if autoRegenCallback and oldValue ~= newValue and globals.timeSelectionValid then
            autoRegenCallback(paramName, oldValue, newValue)
        end
    end

    -- Layout parameters
    local fadeVisualSize = 15

    -- Info message for interval mode
    if dataObj.intervalMode == 0 then
        if dataObj.triggerRate < 0 then
            imgui.TextColored(globals.ctx, 0xFFAA00FF, "Negative interval: Items will overlap and crossfade")
        else
            imgui.TextColored(globals.ctx, 0xFFAA00FF, "Absolute: Fixed interval in seconds")
        end
    elseif dataObj.intervalMode == 1 then
        imgui.TextColored(globals.ctx, 0xFFAA00FF, "Relative: Interval as percentage of time selection")
    elseif dataObj.intervalMode == 2 then
        imgui.TextColored(globals.ctx, 0xFFAA00FF, "Coverage: Percentage of time selection to be filled")
    elseif dataObj.intervalMode == 3 then
        imgui.TextColored(globals.ctx, 0xFFAA00FF, "Chunk: Structured sound/silence periods")
    elseif dataObj.intervalMode == 4 then
        imgui.TextColored(globals.ctx, 0xFFAA00FF, "Noise: Organic placement based on Perlin noise")
    end

    -- Create table for automatic layout: [Control | Label | Variation]
    -- Column 0: Control (slider/combo) - stretches
    -- Column 1: Label + help - fixed width auto-sized
    -- Column 2: Variation controls (direction + value + label) - fixed width
    local tableFlags = imgui.TableFlags_SizingStretchProp
    if imgui.BeginTable(globals.ctx, "##GenerationSettings_" .. trackingKey, 3, tableFlags) then
        -- Setup columns
        imgui.TableSetupColumn(globals.ctx, "Control", imgui.TableColumnFlags_WidthStretch)
        imgui.TableSetupColumn(globals.ctx, "Label", imgui.TableColumnFlags_WidthFixed, 0)  -- Auto-size
        imgui.TableSetupColumn(globals.ctx, "Variation", imgui.TableColumnFlags_WidthFixed, 100)

        -- Interval mode selection (Combo box)
        imgui.TableNextRow(globals.ctx)
        imgui.TableSetColumnIndex(globals.ctx, 0)
        imgui.PushItemWidth(globals.ctx, -1)
        local intervalModes = "Absolute\0Relative\0Coverage\0Chunk\0Noise\0Euclidean\0"
        local rv, newIntervalMode = globals.UndoWrappers.Combo(globals.ctx, "##IntervalMode", dataObj.intervalMode, intervalModes)
        if rv then callbacks.setIntervalMode(newIntervalMode) end
        imgui.PopItemWidth(globals.ctx)

        imgui.TableSetColumnIndex(globals.ctx, 1)
        imgui.Text(globals.ctx, "Interval Mode")
        imgui.SameLine(globals.ctx)
        globals.Utils.HelpMarker(
            "Absolute: Fixed interval in seconds\n" ..
            "Relative: Interval as percentage of time selection\n" ..
            "Coverage: Percentage of time selection to be filled\n" ..
            "Chunk: Create structured sound/silence periods\n" ..
            "Noise: Place items based on Perlin noise function\n" ..
            "Euclidean: Mathematically optimal rhythm distribution"
        )

        -- Interval value (slider) - Not shown in Noise and Euclidean modes
        if dataObj.intervalMode ~= 4 and dataObj.intervalMode ~= 5 then
            local rateLabel = "Interval (sec)"
            local rateMin = -10.0
            local rateMax = 60.0

            if dataObj.intervalMode == 1 then
                rateLabel = "Interval (%)"
                rateMin = 0.1
                rateMax = 100.0
            elseif dataObj.intervalMode == 2 then
                rateLabel = "Coverage (%)"
                rateMin = 0.1
                rateMax = 100.0
            elseif dataObj.intervalMode == 3 then
                rateLabel = "Item Interval (sec)"
                rateMin = -10.0
                rateMax = 60.0
            end

            local driftLabel = (dataObj.intervalMode == 2) and "Drift" or "Var"

            drawSliderWithVariation({
                sliderId = "##TriggerRate",
                sliderValue = dataObj.triggerRate,
                sliderMin = rateMin,
                sliderMax = rateMax,
                sliderFormat = "%.1f",
                sliderLabel = rateLabel,
                trackingKey = trackingKey .. "_triggerRate",
                callbacks = { setValue = callbacks.setTriggerRate },
                autoRegenCallback = autoRegenCallback,
                checkAutoRegen = checkAutoRegen,
                variationEnabled = true,
                variationValue = dataObj.triggerDrift,
                variationDirection = dataObj.triggerDriftDirection,
                variationLabel = driftLabel,
                variationCallbacks = {
                    setValue = callbacks.setTriggerDrift,
                    setDirection = callbacks.setTriggerDriftDirection
                }
            })
        end

        -- Chunk mode specific controls
        if dataObj.intervalMode == 3 then
            -- Chunk Duration slider with variation
            drawSliderWithVariation({
                sliderId = "##ChunkDuration",
                sliderValue = dataObj.chunkDuration,
                sliderMin = 0.5,
                sliderMax = 60.0,
                sliderFormat = "%.1f sec",
                sliderLabel = "Chunk Duration",
                helpText = "Duration of active sound periods in seconds",
                trackingKey = trackingKey .. "_chunkDuration",
                callbacks = { setValue = callbacks.setChunkDuration },
                autoRegenCallback = autoRegenCallback,
                checkAutoRegen = checkAutoRegen,
                variationEnabled = true,
                variationValue = dataObj.chunkDurationVariation,
                variationDirection = dataObj.chunkDurationVarDirection,
                variationLabel = "Var",
                variationCallbacks = {
                    setValue = callbacks.setChunkDurationVariation,
                    setDirection = callbacks.setChunkDurationVarDirection
                }
            })

            -- Chunk Silence slider with variation
            drawSliderWithVariation({
                sliderId = "##ChunkSilence",
                sliderValue = dataObj.chunkSilence,
                sliderMin = 0.0,
                sliderMax = 120.0,
                sliderFormat = "%.1f sec",
                sliderLabel = "Silence Duration",
                helpText = "Duration of silence periods between chunks in seconds",
                trackingKey = trackingKey .. "_chunkSilence",
                callbacks = { setValue = callbacks.setChunkSilence },
                autoRegenCallback = autoRegenCallback,
                checkAutoRegen = checkAutoRegen,
                variationEnabled = true,
                variationValue = dataObj.chunkSilenceVariation,
                variationDirection = dataObj.chunkSilenceVarDirection,
                variationLabel = "Var",
                variationCallbacks = {
                    setValue = callbacks.setChunkSilenceVariation,
                    setDirection = callbacks.setChunkSilenceVarDirection
                }
            })
        end

        -- End the table before noise mode (noise has custom complex layout)
        imgui.EndTable(globals.ctx)
    end  -- End BeginTable check

    -- Noise mode specific controls (DELEGATED to sub-module)
    if dataObj.intervalMode == 4 then
        TriggerSection_Noise.draw(dataObj, callbacks, trackingKey, width, checkAutoRegen, UI)
    end


    -- Euclidean Rhythm mode specific controls (DELEGATED to sub-module)
    if dataObj.intervalMode == 5 then
        TriggerSection_Euclidean.draw(dataObj, callbacks, trackingKey, width, isGroup, groupPath, containerIndex, UI)
    end

    -- Fade in/out controls are commented out but can be enabled if needed
end

-- Display trigger and randomization settings for a group or container
function TriggerSection.displayTriggerSettings(obj, objId, width, isGroup, groupPath, containerIndex)
    local imgui = globals.imgui
    local titlePrefix = isGroup and "Default " or ""
    local inheritText = isGroup and "These settings will be inherited by containers unless overridden" or ""


    -- Create a safe tracking key
    local trackingKey = objId or ""
    if trackingKey == "" then
        if isGroup then
            trackingKey = "group_" .. (groupPath or "unknown")
        else
            trackingKey = "container_" .. (groupPath or "unknown") .. "_" .. (containerIndex or "unknown")
        end
    end

    -- Helper function for auto-regeneration
    -- Marks the object as needing regeneration when slider is released (onChangeComplete)
    -- The RegenManager will handle the actual regeneration
    local function checkAutoRegen(paramName, oldValue, newValue)
        if not globals.timeSelectionValid then
            return
        end

        -- Mark the appropriate object for regeneration
        if isGroup then
            -- For groups in Euclidean AutoBind mode, mark only the selected container
            if obj.euclideanAutoBindContainers then
                local selectedBindingIndex = obj.euclideanSelectedBindingIndex or 1
                local bindingOrder = obj.euclideanBindingOrder or {}
                local selectedUUID = bindingOrder[selectedBindingIndex]

                if selectedUUID and groupPath then
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        for _, container in ipairs(group.containers) do
                            if container.id == selectedUUID then
                                container.needsRegeneration = true
                                return  -- Don't mark group
                            end
                        end
                    end
                end
            end
            -- Default: mark group (if not in AutoBind mode)
            --reaper.ShowConsoleMsg("[checkAutoRegen] Marking GROUP for regeneration\n")
            obj.needsRegeneration = true
        else
            -- Mark container
            -- reaper.ShowConsoleMsg("[checkAutoRegen] Marking CONTAINER for regeneration\n")
            obj.needsRegeneration = true
        end
    end

    -- Inheritance info
    if inheritText ~= "" then
        imgui.TextColored(globals.ctx, 0xFFAA00FF, inheritText)
    end

    -- Ensure fade properties are initialized
    obj.fadeIn = obj.fadeIn or 0.0
    obj.fadeOut = obj.fadeOut or 0.0

    -- Ensure chunk mode properties are initialized
    obj.chunkDuration = obj.chunkDuration or require("DM_Ambiance_Constants").DEFAULTS.CHUNK_DURATION
    obj.chunkSilence = obj.chunkSilence or require("DM_Ambiance_Constants").DEFAULTS.CHUNK_SILENCE
    obj.chunkDurationVariation = obj.chunkDurationVariation or require("DM_Ambiance_Constants").DEFAULTS.CHUNK_DURATION_VARIATION
    obj.chunkSilenceVariation = obj.chunkSilenceVariation or require("DM_Ambiance_Constants").DEFAULTS.CHUNK_SILENCE_VARIATION

    -- Draw trigger settings section
    TriggerSection.drawTriggerSettingsSection(
        obj,
        {
            setIntervalMode = function(v)
                obj.intervalMode = v
                obj.needsRegeneration = true
                -- Sync euclidean bindings if interval mode changes
                if isGroup and groupPath then
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        globals.Structures.syncEuclideanBindings(group)
                    end
                elseif not isGroup and groupPath then
                    -- Container mode changed - sync parent group
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        globals.Structures.syncEuclideanBindings(group)
                    end
                end
            end,
            -- Note: needsRegeneration is set by checkAutoRegen callback on slider release, not here
            setTriggerRate = function(v) obj.triggerRate = v end,
            setTriggerDrift = function(v) obj.triggerDrift = v end,
            setTriggerDriftDirection = function(v) obj.triggerDriftDirection = v end,
            setFadeIn = function(v) obj.fadeIn = math.max(0, v) end,
            setFadeOut = function(v) obj.fadeOut = math.max(0, v) end,
            -- Chunk mode callbacks
            setChunkDuration = function(v) obj.chunkDuration = v end,
            setChunkSilence = function(v) obj.chunkSilence = v end,
            setChunkDurationVariation = function(v) obj.chunkDurationVariation = v end,
            setChunkDurationVarDirection = function(v) obj.chunkDurationVarDirection = v end,
            setChunkSilenceVariation = function(v) obj.chunkSilenceVariation = v end,
            setChunkSilenceVarDirection = function(v) obj.chunkSilenceVarDirection = v end,
            -- Noise mode callbacks
            setNoiseSeed = function(v) obj.noiseSeed = v end,
            setNoiseAlgorithm = function(v) obj.noiseAlgorithm = v end,
            setNoiseFrequency = function(v) obj.noiseFrequency = v end,
            setNoiseAmplitude = function(v) obj.noiseAmplitude = v end,
            setNoiseOctaves = function(v) obj.noiseOctaves = v end,
            setNoisePersistence = function(v) obj.noisePersistence = v end,
            setNoiseLacunarity = function(v) obj.noiseLacunarity = v end,
            setNoiseDensity = function(v) obj.noiseDensity = v end,
            setNoiseThreshold = function(v) obj.noiseThreshold = v end,
            -- Euclidean mode callbacks
            setEuclideanMode = function(v)
                obj.euclideanMode = v

                -- If group, sync to all containers in override mode with Euclidean (parent -> children only)
                if isGroup and groupPath then
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        for _, container in ipairs(group.containers) do
                            if container.overrideParent and container.intervalMode == 5 then
                                container.euclideanMode = v
                                container.needsRegeneration = true
                            end
                        end
                    end
                end

                obj.needsRegeneration = true
            end,
            setEuclideanTempo = function(v)
                obj.euclideanTempo = v

                -- If group, sync value to all containers in override mode with Euclidean
                -- Note: Don't mark containers for regeneration here (during drag)
                -- They will be regenerated when the group is regenerated on slider release
                if isGroup and groupPath then
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        for _, container in ipairs(group.containers) do
                            if container.overrideParent and container.intervalMode == 5 then
                                container.euclideanTempo = v
                            end
                        end
                    end
                end
                -- Note: obj.needsRegeneration is set by checkAutoRegen on slider release
            end,
            setEuclideanUseProjectTempo = function(v)
                obj.euclideanUseProjectTempo = v

                -- If group, sync to all containers in override mode with Euclidean (parent -> children only)
                if isGroup and groupPath then
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        for _, container in ipairs(group.containers) do
                            if container.overrideParent and container.intervalMode == 5 then
                                container.euclideanUseProjectTempo = v
                                container.needsRegeneration = true
                            end
                        end
                    end
                end

                obj.needsRegeneration = true
            end,
            setEuclideanSelectedLayer = function(v) obj.euclideanSelectedLayer = v end,
            addEuclideanLayer = function()
                if not obj.euclideanLayers then obj.euclideanLayers = {} end
                table.insert(obj.euclideanLayers, {pulses = 8, steps = 16, rotation = 0})
                obj.euclideanSelectedLayer = #obj.euclideanLayers

                -- If this is a container in override mode with Euclidean, sync to parent binding
                if not isGroup and containerIndex and groupPath then
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        local container = globals.Structures.getContainerFromGroup(groupPath, containerIndex)
                        if container and container.overrideParent and container.intervalMode == 5 and container.id then
                            if group.euclideanLayerBindings and group.euclideanLayerBindings[container.id] then
                                table.insert(group.euclideanLayerBindings[container.id], {pulses = 8, steps = 16, rotation = 0})
                                -- Sync selected layer index
                                group.euclideanSelectedLayerPerBinding[container.id] = #group.euclideanLayerBindings[container.id]
                                -- Don't mark group for regeneration - only the container needs regen
                            end
                        end
                    end
                end

                obj.needsRegeneration = true
            end,
            removeEuclideanLayer = function(layerIdx)
                if not obj.euclideanLayers or #obj.euclideanLayers <= 1 then return end
                table.remove(obj.euclideanLayers, layerIdx)
                if obj.euclideanSelectedLayer > #obj.euclideanLayers then
                    obj.euclideanSelectedLayer = #obj.euclideanLayers
                end

                -- If this is a container in override mode with Euclidean, sync to parent binding
                if not isGroup and containerIndex and groupPath then
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        local container = globals.Structures.getContainerFromGroup(groupPath, containerIndex)
                        if container and container.overrideParent and container.intervalMode == 5 and container.id then
                            if group.euclideanLayerBindings and group.euclideanLayerBindings[container.id] then
                                if #group.euclideanLayerBindings[container.id] > 1 then
                                    table.remove(group.euclideanLayerBindings[container.id], layerIdx)
                                    -- Sync selected layer index
                                    local selectedLayerIdx = group.euclideanSelectedLayerPerBinding[container.id] or 1
                                    if selectedLayerIdx > #group.euclideanLayerBindings[container.id] then
                                        group.euclideanSelectedLayerPerBinding[container.id] = #group.euclideanLayerBindings[container.id]
                                    end
                                    -- Don't mark group for regeneration - only the container needs regen
                                end
                            end
                        end
                    end
                end

                obj.needsRegeneration = true
            end,
            setEuclideanLayerPulses = function(layerIdx, v)
                if not obj.euclideanLayers or not obj.euclideanLayers[layerIdx] then return end
                obj.euclideanLayers[layerIdx].pulses = v

                -- If this is a container in override mode with Euclidean, sync back to parent binding
                if not isGroup and containerIndex and groupPath then
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        local container = globals.Structures.getContainerFromGroup(groupPath, containerIndex)
                        if container and container.overrideParent and container.intervalMode == 5 and container.id then
                            if group.euclideanLayerBindings and group.euclideanLayerBindings[container.id] then
                                -- Ensure parent binding has enough layers by copying from container
                                while #group.euclideanLayerBindings[container.id] < #container.euclideanLayers do
                                    local missingIdx = #group.euclideanLayerBindings[container.id] + 1
                                    local containerLayer = container.euclideanLayers[missingIdx]
                                    table.insert(group.euclideanLayerBindings[container.id], {
                                        pulses = containerLayer.pulses,
                                        steps = containerLayer.steps,
                                        rotation = containerLayer.rotation
                                    })
                                end

                                -- Sync the changed value
                                group.euclideanLayerBindings[container.id][layerIdx].pulses = v
                                -- Don't mark group for regeneration - only the container needs regen
                            end
                        end
                    end
                end
                -- Note: obj.needsRegeneration is set by checkAutoRegen on slider release
            end,
            setEuclideanLayerSteps = function(layerIdx, v)
                if not obj.euclideanLayers or not obj.euclideanLayers[layerIdx] then return end
                obj.euclideanLayers[layerIdx].steps = v

                -- If this is a container in override mode with Euclidean, sync back to parent binding
                if not isGroup and containerIndex and groupPath then
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        local container = globals.Structures.getContainerFromGroup(groupPath, containerIndex)
                        if container and container.overrideParent and container.intervalMode == 5 and container.id then
                            if group.euclideanLayerBindings and group.euclideanLayerBindings[container.id] then
                                -- Ensure parent binding has enough layers by copying from container
                                while #group.euclideanLayerBindings[container.id] < #container.euclideanLayers do
                                    local missingIdx = #group.euclideanLayerBindings[container.id] + 1
                                    local containerLayer = container.euclideanLayers[missingIdx]
                                    table.insert(group.euclideanLayerBindings[container.id], {
                                        pulses = containerLayer.pulses,
                                        steps = containerLayer.steps,
                                        rotation = containerLayer.rotation
                                    })
                                end

                                -- Sync the changed value
                                group.euclideanLayerBindings[container.id][layerIdx].steps = v
                                -- Don't mark group for regeneration - only the container needs regen
                            end
                        end
                    end
                end
                -- Note: obj.needsRegeneration is set by checkAutoRegen on slider release
            end,
            setEuclideanLayerRotation = function(layerIdx, v)
                if not obj.euclideanLayers or not obj.euclideanLayers[layerIdx] then return end
                obj.euclideanLayers[layerIdx].rotation = v

                -- If this is a container in override mode with Euclidean, sync back to parent binding
                if not isGroup and containerIndex and groupPath then
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        local container = globals.Structures.getContainerFromGroup(groupPath, containerIndex)
                        if container and container.overrideParent and container.intervalMode == 5 and container.id then
                            if group.euclideanLayerBindings and group.euclideanLayerBindings[container.id] then
                                -- Ensure parent binding has enough layers by copying from container
                                while #group.euclideanLayerBindings[container.id] < #container.euclideanLayers do
                                    local missingIdx = #group.euclideanLayerBindings[container.id] + 1
                                    local containerLayer = container.euclideanLayers[missingIdx]
                                    table.insert(group.euclideanLayerBindings[container.id], {
                                        pulses = containerLayer.pulses,
                                        steps = containerLayer.steps,
                                        rotation = containerLayer.rotation
                                    })
                                end

                                -- Sync the changed value
                                group.euclideanLayerBindings[container.id][layerIdx].rotation = v
                                -- Don't mark group for regeneration - only the container needs regen
                            end
                        end
                    end
                end
                -- Note: obj.needsRegeneration is set by checkAutoRegen on slider release
            end,
            -- Euclidean auto-bind mode callbacks
            setEuclideanAutoBindContainers = function(v)
                obj.euclideanAutoBindContainers = v
                -- Sync bindings when toggling auto-bind
                if v and isGroup and groupPath then
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        globals.Structures.syncEuclideanBindings(group)
                    end
                end
                obj.needsRegeneration = true
            end,
            setEuclideanSelectedBindingIndex = function(v) obj.euclideanSelectedBindingIndex = v end,
            setHighlightedContainerUUID = function(uuid)
                -- Store the UUID and timestamp for container highlight
                globals.highlightedContainerUUID = uuid
                globals.highlightStartTime = reaper.time_precise()  -- Start highlight timer
            end,
            addEuclideanBindingLayer = function(bindingIdx)
                if not obj.euclideanBindingOrder or not obj.euclideanBindingOrder[bindingIdx] then return end
                local uuid = obj.euclideanBindingOrder[bindingIdx]
                if not obj.euclideanLayerBindings or not obj.euclideanLayerBindings[uuid] then return end

                table.insert(obj.euclideanLayerBindings[uuid], {pulses = 8, steps = 16, rotation = 0})

                -- Update selected layer for this binding
                if not obj.euclideanSelectedLayerPerBinding then obj.euclideanSelectedLayerPerBinding = {} end
                obj.euclideanSelectedLayerPerBinding[uuid] = #obj.euclideanLayerBindings[uuid]

                -- Sync with container if it's in override mode with Euclidean
                if isGroup and groupPath then
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        for _, container in ipairs(group.containers) do
                            if container.id == uuid and container.overrideParent and container.intervalMode == 5 then
                                if not container.euclideanLayers then
                                    container.euclideanLayers = {}
                                end
                                table.insert(container.euclideanLayers, {pulses = 8, steps = 16, rotation = 0})
                                container.euclideanSelectedLayer = #container.euclideanLayers
                                container.needsRegeneration = true
                                break
                            end
                        end
                    end
                end

                obj.needsRegeneration = true
            end,
            removeEuclideanBindingLayer = function(bindingIdx)
                if not obj.euclideanBindingOrder or not obj.euclideanBindingOrder[bindingIdx] then return end
                local uuid = obj.euclideanBindingOrder[bindingIdx]
                if not obj.euclideanLayerBindings or not obj.euclideanLayerBindings[uuid] then return end
                if #obj.euclideanLayerBindings[uuid] <= 1 then return end  -- Keep at least one layer

                local selectedLayer = (obj.euclideanSelectedLayerPerBinding and obj.euclideanSelectedLayerPerBinding[uuid]) or 1
                table.remove(obj.euclideanLayerBindings[uuid], selectedLayer)

                -- Adjust selected layer index
                if not obj.euclideanSelectedLayerPerBinding then obj.euclideanSelectedLayerPerBinding = {} end
                if obj.euclideanSelectedLayerPerBinding[uuid] > #obj.euclideanLayerBindings[uuid] then
                    obj.euclideanSelectedLayerPerBinding[uuid] = #obj.euclideanLayerBindings[uuid]
                end

                -- Sync with container if it's in override mode with Euclidean
                if isGroup and groupPath then
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        for _, container in ipairs(group.containers) do
                            if container.id == uuid and container.overrideParent and container.intervalMode == 5 then
                                if container.euclideanLayers and #container.euclideanLayers > 1 then
                                    table.remove(container.euclideanLayers, selectedLayer)
                                    if container.euclideanSelectedLayer > #container.euclideanLayers then
                                        container.euclideanSelectedLayer = #container.euclideanLayers
                                    end
                                    container.needsRegeneration = true
                                end
                                break
                            end
                        end
                    end
                end

                -- Don't mark group for regeneration in AutoBind mode
                -- The individual container is already marked above
                if not (isGroup and obj.euclideanAutoBindContainers) then
                    obj.needsRegeneration = true
                end
            end,
            setEuclideanBindingPulses = function(bindingIdx, layerIdx, v)
                if not obj.euclideanBindingOrder or not obj.euclideanBindingOrder[bindingIdx] then return end
                local uuid = obj.euclideanBindingOrder[bindingIdx]
                if not obj.euclideanLayerBindings or not obj.euclideanLayerBindings[uuid] then return end
                if not obj.euclideanLayerBindings[uuid][layerIdx] then return end

                obj.euclideanLayerBindings[uuid][layerIdx].pulses = v

                -- Sync if container is in override mode (but don't mark for regeneration yet)
                if isGroup and groupPath then
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        for _, container in ipairs(group.containers) do
                            if container.id == uuid then
                                -- Sync layers if container is in override mode with Euclidean
                                if container.overrideParent and container.intervalMode == 5 then
                                -- Ensure container has euclideanLayers array
                                if not container.euclideanLayers then
                                    container.euclideanLayers = {}
                                end

                                -- Sync ALL layers from parent binding to container
                                local parentBinding = obj.euclideanLayerBindings[uuid]
                                for i, bindingLayer in ipairs(parentBinding) do
                                    if not container.euclideanLayers[i] then
                                        -- Create missing layer by copying from parent binding
                                        container.euclideanLayers[i] = {
                                            pulses = bindingLayer.pulses,
                                            steps = bindingLayer.steps,
                                            rotation = bindingLayer.rotation
                                        }
                                    else
                                        -- Update existing layer with current change
                                        if i == layerIdx then
                                            container.euclideanLayers[i].pulses = v
                                        else
                                            -- Sync other parameters to stay in sync
                                            container.euclideanLayers[i].pulses = bindingLayer.pulses
                                            container.euclideanLayers[i].steps = bindingLayer.steps
                                            container.euclideanLayers[i].rotation = bindingLayer.rotation
                                        end
                                    end
                                end

                                -- Remove extra layers if container has more than parent
                                while #container.euclideanLayers > #parentBinding do
                                    table.remove(container.euclideanLayers)
                                end
                                end
                            end
                        end
                    end
                end

                -- Don't mark for regeneration here - let checkAutoRegen() handle it on slider release
            end,
            setEuclideanBindingSteps = function(bindingIdx, layerIdx, v)
                if not obj.euclideanBindingOrder or not obj.euclideanBindingOrder[bindingIdx] then return end
                local uuid = obj.euclideanBindingOrder[bindingIdx]
                if not obj.euclideanLayerBindings or not obj.euclideanLayerBindings[uuid] then return end
                if not obj.euclideanLayerBindings[uuid][layerIdx] then return end

                obj.euclideanLayerBindings[uuid][layerIdx].steps = v

                -- Sync if container is in override mode (but don't mark for regeneration yet)
                if isGroup and groupPath then
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        for _, container in ipairs(group.containers) do
                            if container.id == uuid then
                                -- Sync layers if container is in override mode with Euclidean
                                if container.overrideParent and container.intervalMode == 5 then
                                -- Ensure container has euclideanLayers array
                                if not container.euclideanLayers then
                                    container.euclideanLayers = {}
                                end

                                -- Sync ALL layers from parent binding to container
                                local parentBinding = obj.euclideanLayerBindings[uuid]
                                for i, bindingLayer in ipairs(parentBinding) do
                                    if not container.euclideanLayers[i] then
                                        -- Create missing layer by copying from parent binding
                                        container.euclideanLayers[i] = {
                                            pulses = bindingLayer.pulses,
                                            steps = bindingLayer.steps,
                                            rotation = bindingLayer.rotation
                                        }
                                    else
                                        -- Update existing layer with current change
                                        if i == layerIdx then
                                            container.euclideanLayers[i].steps = v
                                        else
                                            -- Sync other parameters to stay in sync
                                            container.euclideanLayers[i].pulses = bindingLayer.pulses
                                            container.euclideanLayers[i].steps = bindingLayer.steps
                                            container.euclideanLayers[i].rotation = bindingLayer.rotation
                                        end
                                    end
                                end

                                -- Remove extra layers if container has more than parent
                                while #container.euclideanLayers > #parentBinding do
                                    table.remove(container.euclideanLayers)
                                end
                                end
                            end
                        end
                    end
                end

                -- Don't mark for regeneration here - let checkAutoRegen() handle it on slider release
            end,
            setEuclideanBindingRotation = function(bindingIdx, layerIdx, v)
                if not obj.euclideanBindingOrder or not obj.euclideanBindingOrder[bindingIdx] then return end
                local uuid = obj.euclideanBindingOrder[bindingIdx]
                if not obj.euclideanLayerBindings or not obj.euclideanLayerBindings[uuid] then return end
                if not obj.euclideanLayerBindings[uuid][layerIdx] then return end

                obj.euclideanLayerBindings[uuid][layerIdx].rotation = v

                -- Sync if container is in override mode (but don't mark for regeneration yet)
                if isGroup and groupPath then
                    local group = globals.Structures.getGroupByPath(groupPath)
                    if group then
                        for _, container in ipairs(group.containers) do
                            if container.id == uuid then
                                -- Sync layers if container is in override mode with Euclidean
                                if container.overrideParent and container.intervalMode == 5 then
                                -- Ensure container has euclideanLayers array
                                if not container.euclideanLayers then
                                    container.euclideanLayers = {}
                                end

                                -- Sync ALL layers from parent binding to container
                                local parentBinding = obj.euclideanLayerBindings[uuid]
                                for i, bindingLayer in ipairs(parentBinding) do
                                    if not container.euclideanLayers[i] then
                                        -- Create missing layer by copying from parent binding
                                        container.euclideanLayers[i] = {
                                            pulses = bindingLayer.pulses,
                                            steps = bindingLayer.steps,
                                            rotation = bindingLayer.rotation
                                        }
                                    else
                                        -- Update existing layer with current change
                                        if i == layerIdx then
                                            container.euclideanLayers[i].rotation = v
                                        else
                                            -- Sync other parameters to stay in sync
                                            container.euclideanLayers[i].pulses = bindingLayer.pulses
                                            container.euclideanLayers[i].steps = bindingLayer.steps
                                            container.euclideanLayers[i].rotation = bindingLayer.rotation
                                        end
                                    end
                                end

                                -- Remove extra layers if container has more than parent
                                while #container.euclideanLayers > #parentBinding do
                                    table.remove(container.euclideanLayers)
                                end
                                end
                            end
                        end
                    end
                end

                -- Don't mark for regeneration here - let checkAutoRegen() handle it on slider release
            end,
        },
        width,
        titlePrefix,
        checkAutoRegen,  -- Pass auto-regen callback to trigger regeneration on slider release
        isGroup,         -- Pass isGroup flag
        groupPath,       -- Pass group path
        containerIndex   -- Pass container index
    )

    -- Randomization parameters section
    imgui.Separator(globals.ctx)
    imgui.Text(globals.ctx, titlePrefix .. "Randomization parameters")

    local checkboxWidth = 20
    local linkButtonWidth = 24  -- Approximate width of link button
    local labelWidth = 120      -- Fixed width for labels
    local controlWidth = width - checkboxWidth - linkButtonWidth - labelWidth - 20  -- Use remaining space

    -- Pitch randomization (checkbox + LinkedSliders + mode toggle)
    imgui.BeginGroup(globals.ctx)
    local rv, newRandomizePitch = globals.UndoWrappers.Checkbox(globals.ctx, "##RandomizePitch", obj.randomizePitch)
    if rv then
        obj.randomizePitch = newRandomizePitch
        obj.needsRegeneration = true
        if groupPath and containerIndex then
            globals.Utils.queueRandomizationUpdate(groupPath, containerIndex, "pitch")
        elseif groupPath then
            globals.Utils.queueRandomizationUpdate(groupPath, nil, "pitch")
        end
    end

    imgui.SameLine(globals.ctx)
    imgui.BeginDisabled(globals.ctx, not obj.randomizePitch)

    -- Use LinkedSliders component for pitch range
    if not obj.pitchLinkMode then obj.pitchLinkMode = "mirror" end
    globals.LinkedSliders.draw({
        id = objId .. "_pitchRange",
        sliders = {
            {value = obj.pitchRange.min, min = -48, max = 48, defaultValue = globals.Constants.DEFAULTS.PITCH_RANGE_MIN, format = "%.1f"},
            {value = obj.pitchRange.max, min = -48, max = 48, defaultValue = globals.Constants.DEFAULTS.PITCH_RANGE_MAX, format = "%.1f"}
        },
        linkMode = obj.pitchLinkMode,
        width = controlWidth,
        helpText = "Pitch randomization range in semitones.",
        sliderLabels = {"Min: Lower pitch bound", "Max: Upper pitch bound"},
        onChange = function(values)
            obj.pitchRange.min = values[1]
            obj.pitchRange.max = values[2]
            -- Note: needsRegeneration set in onChangeComplete, not during drag
        end,
        onChangeComplete = function()
            -- STRETCH mode changes item duration due to playrate, requires full regeneration
            -- PITCH mode only changes pitch property, can update existing items
            if obj.pitchMode == globals.Constants.PITCH_MODES.STRETCH then
                obj.needsRegeneration = true
            else
                -- Standard pitch mode: just update randomization on existing items
                if groupPath and containerIndex then
                    globals.Utils.queueRandomizationUpdate(groupPath, containerIndex, "pitch")
                elseif groupPath then
                    globals.Utils.queueRandomizationUpdate(groupPath, nil, "pitch")
                end
            end
        end,
        onLinkModeChange = function(newMode)
            obj.pitchLinkMode = newMode
            if globals.History then
                globals.History.captureState("Change pitch link mode")
            end
        end
    })

    imgui.EndDisabled(globals.ctx)
    imgui.SameLine(globals.ctx)

    -- Pitch mode toggle button (transparent button to switch between Pitch and Stretch)
    if not obj.pitchMode then obj.pitchMode = globals.Constants.PITCH_MODES.PITCH end
    local pitchModeLabel = obj.pitchMode == globals.Constants.PITCH_MODES.STRETCH and "Stretch (semitones)" or "Pitch (semitones)"

    -- State tracking for text color feedback (similar to icon buttons)
    if not globals.pitchModeButtonStates then
        globals.pitchModeButtonStates = {}
    end
    local stateKey = "pitchMode_" .. objId
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

    local clicked = imgui.Button(globals.ctx, pitchModeLabel .. "##PitchModeToggle" .. objId)

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
        -- Toggle between PITCH and STRETCH modes
        obj.pitchMode = (obj.pitchMode == globals.Constants.PITCH_MODES.PITCH) and globals.Constants.PITCH_MODES.STRETCH or globals.Constants.PITCH_MODES.PITCH
        obj.needsRegeneration = true

        -- Sync B_PPITCH on existing items
        if groupPath and containerIndex then
            local group = globals.Structures.getGroupByPath(groupPath)
            if group then
                local container = globals.Structures.getContainerFromGroup(groupPath, containerIndex)
                if container then
                    globals.Generation.syncPitchModeOnExistingItems(group, container)
                end
            end
        elseif groupPath then
            -- For group-level toggle, sync all containers
            local group = globals.Structures.getGroupByPath(groupPath)
            if group then
                for _, container in ipairs(group.containers) do
                    if not container.overrideParent then
                        globals.Generation.syncPitchModeOnExistingItems(group, container)
                    end
                end
            end
        end

        if globals.History then
            globals.History.captureState("Toggle pitch mode")
        end
    end

    -- Add tooltip to explain the modes
    if imgui.IsItemHovered(globals.ctx) then
        imgui.SetTooltip(globals.ctx, "Click to toggle between:\n• Pitch: Standard pitch shift (may have artifacts)\n• Stretch: Time-stretch pitch (better quality, changes duration)")
    end

    imgui.EndGroup(globals.ctx)

    -- Volume randomization (checkbox + LinkedSliders + label)
    imgui.BeginGroup(globals.ctx)
    local rv, newRandomizeVolume = globals.UndoWrappers.Checkbox(globals.ctx, "##RandomizeVolume", obj.randomizeVolume)
    if rv then
        obj.randomizeVolume = newRandomizeVolume
        obj.needsRegeneration = true
        if groupPath and containerIndex then
            globals.Utils.queueRandomizationUpdate(groupPath, containerIndex, "volume")
        elseif groupPath then
            globals.Utils.queueRandomizationUpdate(groupPath, nil, "volume")
        end
    end

    imgui.SameLine(globals.ctx)
    imgui.BeginDisabled(globals.ctx, not obj.randomizeVolume)

    -- Use LinkedSliders component for volume range
    if not obj.volumeLinkMode then obj.volumeLinkMode = "mirror" end
    globals.LinkedSliders.draw({
        id = objId .. "_volumeRange",
        sliders = {
            {value = obj.volumeRange.min, min = -24, max = 24, defaultValue = globals.Constants.DEFAULTS.VOLUME_RANGE_MIN, format = "%.1f dB"},
            {value = obj.volumeRange.max, min = -24, max = 24, defaultValue = globals.Constants.DEFAULTS.VOLUME_RANGE_MAX, format = "%.1f dB"}
        },
        linkMode = obj.volumeLinkMode,
        width = controlWidth,
        helpText = "Volume randomization range in decibels.",
        sliderLabels = {"Min: Lower volume bound", "Max: Upper volume bound"},
        onChange = function(values)
            obj.volumeRange.min = values[1]
            obj.volumeRange.max = values[2]
            -- Note: needsRegeneration set in onChangeComplete, not during drag
        end,
        onChangeComplete = function()
            -- Note: Randomization parameters don't require full regeneration
            -- They only affect values applied to existing items
            if groupPath and containerIndex then
                globals.Utils.queueRandomizationUpdate(groupPath, containerIndex, "volume")
            elseif groupPath then
                globals.Utils.queueRandomizationUpdate(groupPath, nil, "volume")
            end
        end,
        onLinkModeChange = function(newMode)
            obj.volumeLinkMode = newMode
            if globals.History then
                globals.History.captureState("Change volume link mode")
            end
        end
    })

    imgui.EndDisabled(globals.ctx)
    imgui.SameLine(globals.ctx)
    imgui.Text(globals.ctx, "Volume (dB)")
    imgui.EndGroup(globals.ctx)

    -- Pan randomization (only show for stereo containers - hide for multichannel)
    local showPanControls = true
    if groupPath and containerIndex then
        -- For containers, check if it's in multichannel mode (non-stereo)
        local container = globals.Structures.getContainerFromGroup(groupPath, containerIndex)
        if container and container.channelMode and container.channelMode > 0 then
            showPanControls = false
        end
    end

    if showPanControls then
        -- Pan randomization (checkbox + LinkedSliders + label)
        imgui.BeginGroup(globals.ctx)
        local rv, newRandomizePan = globals.UndoWrappers.Checkbox(globals.ctx, "##RandomizePan", obj.randomizePan)
        if rv then
            obj.randomizePan = newRandomizePan
            obj.needsRegeneration = true
            if groupPath and containerIndex then
                globals.Utils.queueRandomizationUpdate(groupPath, containerIndex, "pan")
            elseif groupPath then
                globals.Utils.queueRandomizationUpdate(groupPath, nil, "pan")
            end
        end

        imgui.SameLine(globals.ctx)
        imgui.BeginDisabled(globals.ctx, not obj.randomizePan)

        -- Use LinkedSliders component for pan range
        if not obj.panLinkMode then obj.panLinkMode = "mirror" end
        globals.LinkedSliders.draw({
            id = objId .. "_panRange",
            sliders = {
                {value = obj.panRange.min, min = -100, max = 100, defaultValue = globals.Constants.DEFAULTS.PAN_RANGE_MIN, format = "%.0f"},
                {value = obj.panRange.max, min = -100, max = 100, defaultValue = globals.Constants.DEFAULTS.PAN_RANGE_MAX, format = "%.0f"}
            },
            linkMode = obj.panLinkMode,
            width = controlWidth,
            helpText = "Pan randomization range (-100% left to +100% right).",
            sliderLabels = {"Min: Left bound", "Max: Right bound"},
            onChange = function(values)
                obj.panRange.min = values[1]
                obj.panRange.max = values[2]
                -- Note: needsRegeneration set in onChangeComplete, not during drag
            end,
            onChangeComplete = function()
                -- Note: Randomization parameters don't require full regeneration
                -- They only affect values applied to existing items
                if groupPath and containerIndex then
                    globals.Utils.queueRandomizationUpdate(groupPath, containerIndex, "pan")
                elseif groupPath then
                    globals.Utils.queueRandomizationUpdate(groupPath, nil, "pan")
                end
            end,
            onLinkModeChange = function(newMode)
                obj.panLinkMode = newMode
                if globals.History then
                    globals.History.captureState("Change pan link mode")
                end
            end
        })

        imgui.EndDisabled(globals.ctx)

        imgui.SameLine(globals.ctx)
        imgui.Text(globals.ctx, "Pan (-100/+100)")
        imgui.EndGroup(globals.ctx)
    end

    -- Fade Settings section
    globals.UI.drawFadeSettingsSection(obj, objId, width, titlePrefix, groupPath, containerIndex)
end

-- Expose sub-modules for use in MultiSelection and other contexts
TriggerSection.Noise = TriggerSection_Noise
TriggerSection.Euclidean = TriggerSection_Euclidean

return TriggerSection
