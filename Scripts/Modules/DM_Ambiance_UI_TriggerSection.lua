--[[
@version 1.4
@noindex
--]]

-- Trigger Settings Section for DM Ambiance Creator
-- Extracted from DM_Ambiance_UI.lua
-- Handles trigger mode controls (Absolute, Relative, Coverage, Chunk, Noise, Euclidean)

local TriggerSection = {}
local globals = {}

function TriggerSection.initModule(g)
    globals = g
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
        if not wasResetVar then
            if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and autoRegenCallback and globals.autoRegenTracking[varKey] then
                if checkAutoRegen then
                    checkAutoRegen(varKey, varKey, globals.autoRegenTracking[varKey], variationValue)
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
function TriggerSection.drawTriggerSettingsSection(dataObj, callbacks, width, titlePrefix, autoRegenCallback, isGroup, groupIndex, containerIndex)
    local imgui = globals.imgui
    local UI = globals.UI

    -- Section separator and title
    imgui.Separator(globals.ctx)
    imgui.Text(globals.ctx, titlePrefix .. "Generation Settings")

    -- Initialize auto-regen tracking if not exists and callback provided

    -- Create unique tracking key for this function call
    local trackingKey = tostring(dataObj) .. "_" .. (titlePrefix or "")

    -- Helper function for auto-regeneration check
    local function checkAutoRegen(paramName, paramKey, oldValue, newValue)
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
        local intervalModes = "Absolute\0Relative\0Coverage\0Chunk\0Noise\0Euclidean\0Fibonacci\0Golden Ratio\0"
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
            "Euclidean: Mathematically optimal rhythm distribution\n" ..
            "Fibonacci: Intervals based on Fibonacci sequence\n" ..
            "Golden Ratio: Intervals based on φ (phi ≈ 1.618)"
        )

        -- Interval value (slider) - Not shown in Noise, Euclidean, Fibonacci, Golden Ratio modes
        if dataObj.intervalMode ~= 4 and dataObj.intervalMode ~= 5 and dataObj.intervalMode ~= 6 and dataObj.intervalMode ~= 7 then
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

    -- Noise mode specific controls
    if dataObj.intervalMode == 4 then
        -- Calculate controlWidth for noise section (using traditional layout)
        local labelWidth = 150
        local padding = 10
        local controlWidth = width - labelWidth - padding - 10
        -- Ensure noise parameters exist (backwards compatibility with old presets)
        globals.Utils.ensureNoiseDefaults(dataObj)

        imgui.Spacing(globals.ctx)
        imgui.Separator(globals.ctx)
        imgui.Spacing(globals.ctx)

        -- Noise Density Range (Min Density + Max Density with link mode)
        -- Using LinkedSliders component for reusability, with custom layout to match other sliders
        do
            if not dataObj.densityLinkMode then dataObj.densityLinkMode = "link" end

            -- BeginGroup to align with other sliders
            imgui.BeginGroup(globals.ctx)

            -- Link button
            local linkMode = dataObj.densityLinkMode or "link"
            if globals.Icons.createLinkModeButton(globals.ctx, "link_" .. trackingKey .. "_density", linkMode, "Link mode: " .. linkMode) then
                local newMode = globals.LinkedSliders.cycleLinkMode(linkMode)
                dataObj.densityLinkMode = newMode
                if globals.History then
                    globals.History.captureState("Change density link mode")
                end
            end
            imgui.SameLine(globals.ctx)

            -- Calculate slider width (subtract link button width and spacing)
            local linkButtonWidth = 24  -- Match the width in Randomization section
            local spacing = 4
            local sliderTotalWidth = controlWidth - linkButtonWidth - spacing

            -- Track which slider changed
            local changedIndex = nil
            local newValues = {}
            local anyChanged = false
            local anyActive = false

            -- Calculate individual slider width
            local sliderSpacing = 4
            local sliderWidth = (sliderTotalWidth - sliderSpacing) / 2
            local anyWasReset = false

            -- Min Density slider
            local rv1, newThreshold, wasReset1 = globals.SliderEnhanced.SliderDouble({
                id = "##" .. trackingKey .. "_density_slider1",
                value = dataObj.noiseThreshold,
                min = 0.0,
                max = 100.0,
                defaultValue = globals.Constants.DEFAULTS.NOISE_THRESHOLD,
                format = "%.1f%%",
                width = sliderWidth
            })

            if rv1 then
                changedIndex = 1
                anyChanged = true
                if wasReset1 then
                    anyWasReset = true
                end
            end
            if imgui.IsItemActive(globals.ctx) then
                anyActive = true
            end
            newValues[1] = newThreshold

            imgui.SameLine(globals.ctx)

            -- Max Density slider
            local rv2, newDensity, wasReset2 = globals.SliderEnhanced.SliderDouble({
                id = "##" .. trackingKey .. "_density_slider2",
                value = dataObj.noiseDensity,
                min = 0.0,
                max = 100.0,
                defaultValue = globals.Constants.DEFAULTS.NOISE_DENSITY,
                format = "%.1f%%",
                width = sliderWidth
            })

            if rv2 then
                changedIndex = 2
                anyChanged = true
                if wasReset2 then
                    anyWasReset = true
                end
            end
            if imgui.IsItemActive(globals.ctx) then
                anyActive = true
            end
            newValues[2] = newDensity

            -- Apply link mode logic if any slider changed
            if anyChanged then
                -- Check if this was a reset (right-click) - if so, bypass link mode
                if anyWasReset then
                    -- Reset: just apply the new value directly without link mode logic
                    callbacks.setNoiseThreshold(newValues[1])
                    callbacks.setNoiseDensity(newValues[2])
                else
                    -- Normal change: apply link mode logic
                    local effectiveMode = globals.LinkedSliders.checkKeyboardOverrides(dataObj.densityLinkMode)
                    local sliderConfigs = {
                        {value = dataObj.noiseThreshold, min = 0.0, max = 100.0},
                        {value = dataObj.noiseDensity, min = 0.0, max = 100.0}
                    }
                    local finalValues = globals.LinkedSliders.applyLinkModeLogic(
                        sliderConfigs,
                        newValues,
                        changedIndex,
                        effectiveMode
                    )

                    -- Clamp values
                    for i = 1, 2 do
                        finalValues[i] = math.max(0.0, math.min(100.0, finalValues[i]))
                    end

                    callbacks.setNoiseThreshold(finalValues[1])
                    callbacks.setNoiseDensity(finalValues[2])
                end
            end

            -- Track state for auto-regen on release
            if not globals.linkedSlidersTracking then
                globals.linkedSlidersTracking = {}
            end
            local trackingKey_density = trackingKey .. "_density"
            if anyActive and not globals.linkedSlidersTracking[trackingKey_density] then
                globals.linkedSlidersTracking[trackingKey_density] = {
                    originalValues = {dataObj.noiseThreshold, dataObj.noiseDensity}
                }
            end
            if not anyActive and globals.linkedSlidersTracking[trackingKey_density] then
                local hasChanged = math.abs(dataObj.noiseThreshold - globals.linkedSlidersTracking[trackingKey_density].originalValues[1]) > 0.001
                    or math.abs(dataObj.noiseDensity - globals.linkedSlidersTracking[trackingKey_density].originalValues[2]) > 0.001
                if hasChanged and checkAutoRegen then
                    checkAutoRegen("densityRange", trackingKey_density, nil, {dataObj.noiseThreshold, dataObj.noiseDensity})
                end
                globals.linkedSlidersTracking[trackingKey_density] = nil
            end

            imgui.EndGroup(globals.ctx)

            -- Label and help marker (aligned with other sliders)
            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Density")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker(
                "Density range for item placement probability.\n\n" ..
                "• Min Density: Floor below which no items are placed (left slider)\n" ..
                "• Max Density: Average/peak density of item placement (right slider)\n\n" ..
                "Link modes:\n" ..
                "• Unlink: Adjust sliders independently\n" ..
                "• Link: Maintain range width (default)\n" ..
                "• Mirror: Move symmetrically from center\n\n" ..
                "Keyboard shortcuts:\n" ..
                "• Hold Shift: Temporarily unlink (independent)\n" ..
                "• Hold Ctrl: Temporarily link (maintain range)\n" ..
                "• Hold Alt: Temporarily mirror (symmetric)"
            )
        end

        -- Noise Algorithm selector
        do
            imgui.BeginGroup(globals.ctx)
            imgui.PushItemWidth(globals.ctx, controlWidth)
            local algorithmNames = "Probability\0Accumulation\0"
            local currentAlgorithm = dataObj.noiseAlgorithm or globals.Constants.NOISE_ALGORITHMS.PROBABILITY
            -- Remap old Poisson (1) to Accumulation (1), keep others
            if currentAlgorithm > 1 then currentAlgorithm = 1 end
            local rv, newAlgorithm = globals.UndoWrappers.Combo(globals.ctx, "##NoiseAlgorithm", currentAlgorithm, algorithmNames)
            if rv then
                callbacks.setNoiseAlgorithm(newAlgorithm)
                -- Trigger regeneration when algorithm changes
                if checkAutoRegen then
                    checkAutoRegen("noiseAlgorithm", trackingKey .. "_algorithm", currentAlgorithm, newAlgorithm)
                end
            end
            imgui.PopItemWidth(globals.ctx)
            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Algorithm")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker(
                "Algorithm for item placement:\n\n" ..
                "• Probability: Test placement probability at regular intervals\n" ..
                "  Adds random jitter to avoid too-regular patterns\n" ..
                "  Best for: Natural variation, organic feel\n\n" ..
                "• Accumulation: Accumulate probability until threshold reached\n" ..
                "  Guarantees consistent density over time\n" ..
                "  Best for: Predictable coverage, smooth distribution"
            )
        end

        -- Noise Frequency slider
        do
            imgui.BeginGroup(globals.ctx)
            globals.SliderEnhanced.SliderDouble({
                id = "##NoiseFrequency",
                value = dataObj.noiseFrequency,
                min = 0.01,
                max = 10.0,
                defaultValue = globals.Constants.DEFAULTS.NOISE_FREQUENCY,
                format = "%.2f Hz",
                width = controlWidth,
                onChange = function(newValue)
                    callbacks.setNoiseFrequency(newValue)
                end,
                onChangeComplete = function(oldValue, newValue)
                    checkAutoRegen("noiseFrequency", oldValue, newValue)
                end
            })

            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Frequency")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker(
                "Controls the speed of density variations over time. " ..
                "Measured in cycles per 10 seconds.\n\n" ..
                "• 0.1 = Very slow (one cycle every 100 seconds) - for long, evolving ambient textures\n" ..
                "• 1.0 = Default (one cycle every 10 seconds) - balanced variation\n" ..
                "• 5.0 = Fast (5 cycles per 10 seconds) - for dynamic, rapidly changing patterns\n" ..
                "• 10.0 = Very fast (one cycle per second) - for quick, jittery effects"
            )
        end

        -- Noise Amplitude slider
        do
            imgui.BeginGroup(globals.ctx)
            globals.SliderEnhanced.SliderDouble({
                id = "##NoiseAmplitude",
                value = dataObj.noiseAmplitude,
                min = 0.0,
                max = 100.0,
                defaultValue = globals.Constants.DEFAULTS.NOISE_AMPLITUDE,
                format = "%.1f%%",
                width = controlWidth,
                onChange = function(newValue)
                    callbacks.setNoiseAmplitude(newValue)
                end,
                onChangeComplete = function(oldValue, newValue)
                    checkAutoRegen("noiseAmplitude", oldValue, newValue)
                end
            })

            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Amplitude")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("Intensity of density variation around average")
        end

        -- Noise Octaves slider
        do
            imgui.BeginGroup(globals.ctx)
            globals.SliderEnhanced.SliderInt({
                id = "##NoiseOctaves",
                value = dataObj.noiseOctaves,
                min = 1,
                max = 6,
                defaultValue = globals.Constants.DEFAULTS.NOISE_OCTAVES,
                format = "%d",
                width = controlWidth,
                onChange = function(newValue)
                    callbacks.setNoiseOctaves(newValue)
                end,
                onChangeComplete = function(oldValue, newValue)
                    checkAutoRegen("noiseOctaves", oldValue, newValue)
                end
            })

            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Octaves")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("Number of noise layers (more = more detail/complexity)")
        end

        -- Noise Persistence slider
        do
            imgui.BeginGroup(globals.ctx)
            globals.SliderEnhanced.SliderDouble({
                id = "##NoisePersistence",
                value = dataObj.noisePersistence,
                min = 0.1,
                max = 1.0,
                defaultValue = globals.Constants.DEFAULTS.NOISE_PERSISTENCE,
                format = "%.2f",
                width = controlWidth,
                onChange = function(newValue)
                    callbacks.setNoisePersistence(newValue)
                end,
                onChangeComplete = function(oldValue, newValue)
                    checkAutoRegen("noisePersistence", oldValue, newValue)
                end
            })

            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Persistence")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("How much each octave contributes (0.5 = balanced)")
        end

        -- Noise Lacunarity slider
        do
            imgui.BeginGroup(globals.ctx)
            globals.SliderEnhanced.SliderDouble({
                id = "##NoiseLacunarity",
                value = dataObj.noiseLacunarity,
                min = 1.5,
                max = 4.0,
                defaultValue = globals.Constants.DEFAULTS.NOISE_LACUNARITY,
                format = "%.2f",
                width = controlWidth,
                onChange = function(newValue)
                    callbacks.setNoiseLacunarity(newValue)
                end,
                onChangeComplete = function(oldValue, newValue)
                    checkAutoRegen("noiseLacunarity", oldValue, newValue)
                end
            })

            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Lacunarity")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("Frequency multiplier between octaves (2.0 = standard)")
        end

        -- Noise Seed control with randomize button
        do
            imgui.BeginGroup(globals.ctx)

            -- Calculate input width (subtract button width and spacing)
            local buttonWidth = 40
            local spacing = 4
            local inputWidth = controlWidth - buttonWidth - spacing

            imgui.PushItemWidth(globals.ctx, inputWidth)

            local seedKey = trackingKey .. "_noiseSeed"
            local rv, newSeed = globals.UndoWrappers.InputInt(globals.ctx, "##NoiseSeed", dataObj.noiseSeed)

            if rv then callbacks.setNoiseSeed(newSeed) end

            imgui.PopItemWidth(globals.ctx)
            imgui.SameLine(globals.ctx)

            -- Randomize button
            if imgui.Button(globals.ctx, "🎲##RandomizeSeed", buttonWidth, 0) then
                local randomSeed = math.random(1, 999999)
                callbacks.setNoiseSeed(randomSeed)
            end
            if imgui.IsItemHovered(globals.ctx) then
                imgui.SetTooltip(globals.ctx, "Generate random seed")
            end

            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Seed")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("Random seed for reproducible noise patterns")
        end

        -- Noise Visualization
        imgui.Spacing(globals.ctx)
        imgui.Text(globals.ctx, "Noise Preview:")
        if not globals.timeSelectionValid then
            imgui.SameLine(globals.ctx)
            imgui.TextColored(globals.ctx, 0xAAAA00FF, "(preview mode - 60s - Add time selection to better tweak)")
        end

        local legendWidth = UI.scaleSize(80)  -- Width reserved for legend (scaled)
        local previewWidth = width - legendWidth - UI.scaleSize(10)  -- Use full available width minus legend
        local previewHeight = UI.scaleSize(120)  -- Scaled height

        -- Draw preview and legend side by side
        imgui.BeginGroup(globals.ctx)
        UI.drawNoisePreview(dataObj, previewWidth, previewHeight)
        imgui.EndGroup(globals.ctx)

        imgui.SameLine(globals.ctx)

        -- Legend using invisible table for perfect alignment
        imgui.BeginGroup(globals.ctx)
        imgui.Dummy(globals.ctx, 0, 10)  -- Vertical spacing

        local drawList = imgui.GetWindowDrawList(globals.ctx)
        local waveformColor = globals.Settings.getSetting("waveformColor")

        -- Create invisible table with 2 columns (icon + text)
        local tableFlags = imgui.TableFlags_None
        if imgui.BeginTable(globals.ctx, "LegendTable", 2, tableFlags) then
            -- Setup columns
            imgui.TableSetupColumn(globals.ctx, "Icon", imgui.TableColumnFlags_WidthFixed, 25)
            imgui.TableSetupColumn(globals.ctx, "Label", imgui.TableColumnFlags_WidthStretch)

            -- Row 1: Noise line
            imgui.TableNextRow(globals.ctx)
            imgui.TableSetColumnIndex(globals.ctx, 0)

            -- Draw icon centered with text
            imgui.AlignTextToFramePadding(globals.ctx)
            local cursorX, cursorY = imgui.GetCursorScreenPos(globals.ctx)
            local textHeight = imgui.GetTextLineHeight(globals.ctx)
            local iconY = cursorY + (textHeight / 2)
            imgui.DrawList_AddLine(drawList, cursorX, iconY, cursorX + 20, iconY, waveformColor, 2.0)
            imgui.Dummy(globals.ctx, 20, textHeight)

            imgui.TableSetColumnIndex(globals.ctx, 1)
            imgui.AlignTextToFramePadding(globals.ctx)
            imgui.Text(globals.ctx, "Noise")

            -- Row 2: Item placement circle
            -- Calculate brighter color
            local baseColor = waveformColor or 0x00CCA0FF
            local r = (baseColor & 0x000000FF)
            local g = (baseColor & 0x0000FF00) >> 8
            local b = (baseColor & 0x00FF0000) >> 16
            local a = (baseColor & 0xFF000000) >> 24
            local brightnessFactor = 1.3
            r = math.min(255, math.floor(r * brightnessFactor))
            g = math.min(255, math.floor(g * brightnessFactor))
            b = math.min(255, math.floor(b * brightnessFactor))
            local itemMarkerColor = r | (g << 8) | (b << 16) | (a << 24)

            imgui.TableNextRow(globals.ctx)
            imgui.TableSetColumnIndex(globals.ctx, 0)

            -- Draw icon centered with text
            imgui.AlignTextToFramePadding(globals.ctx)
            cursorX, cursorY = imgui.GetCursorScreenPos(globals.ctx)
            textHeight = imgui.GetTextLineHeight(globals.ctx)
            iconY = cursorY + (textHeight / 2)
            imgui.DrawList_AddCircleFilled(drawList, cursorX + 10, iconY, 4, itemMarkerColor)
            imgui.Dummy(globals.ctx, 20, textHeight)

            imgui.TableSetColumnIndex(globals.ctx, 1)
            imgui.AlignTextToFramePadding(globals.ctx)
            imgui.Text(globals.ctx, "Items")

            imgui.EndTable(globals.ctx)
        end

        imgui.EndGroup(globals.ctx)
    end

    -- Euclidean Rhythm mode specific controls
    if dataObj.intervalMode == 5 then
        local labelWidth = 150
        local padding = 10
        local controlWidth = width - labelWidth - padding - 10

        imgui.Spacing(globals.ctx)
        imgui.Separator(globals.ctx)
        imgui.Spacing(globals.ctx)

        -- Check if this is a container whose parent is in auto-bind mode
        local isChildOfAutobindGroup = false
        if not isGroup and containerIndex and groupIndex then
            local group = globals.groups[groupIndex]
            local container = group.containers[containerIndex]
            if container and container.overrideParent and container.intervalMode == 5 and group.euclideanAutoBindContainers then
                isChildOfAutobindGroup = true
            end
        end

        -- Helper function for auto-regeneration (simplified)
        local function checkAutoRegen()
            if globals.timeSelectionValid then
                if isGroup then
                    globals.Generation.generateSingleGroup(groupIndex)
                else
                    globals.Generation.generateSingleContainer(groupIndex, containerIndex)
                end
            end
        end

        -- Mode selection (Tempo-Based / Fit-to-Selection)
        -- Disabled for children of auto-bind groups
        do
            imgui.BeginGroup(globals.ctx)
            if isChildOfAutobindGroup then
                imgui.BeginDisabled(globals.ctx)
            end
            local euclideanMode = dataObj.euclideanMode or 0
            local modeChanged = false
            if imgui.RadioButton(globals.ctx, "Tempo-Based##eucMode", euclideanMode == 0) then
                callbacks.setEuclideanMode(0)
                modeChanged = true
            end
            imgui.SameLine(globals.ctx)
            if imgui.RadioButton(globals.ctx, "Fit-to-Selection##eucMode", euclideanMode == 1) then
                callbacks.setEuclideanMode(1)
                modeChanged = true
            end
            if modeChanged and checkAutoRegen then
                checkAutoRegen("euclideanMode", trackingKey .. "_eucMode", not euclideanMode, euclideanMode)
            end
            if isChildOfAutobindGroup then
                imgui.EndDisabled(globals.ctx)
            end
            imgui.EndGroup(globals.ctx)
            if isChildOfAutobindGroup and imgui.IsItemHovered(globals.ctx, imgui.HoveredFlags_AllowWhenDisabled) then
                imgui.SetTooltip(globals.ctx, "This parameter is controlled by the parent group in Auto-bind mode")
            end
        end

        imgui.Spacing(globals.ctx)

        -- Auto-bind to Containers checkbox (only for groups)
        if isGroup then
            local autoBind = dataObj.euclideanAutoBindContainers or false
            local rv, newValue = imgui.Checkbox(globals.ctx, "Auto-bind to Containers##eucAutoBind", autoBind)
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("When enabled, each container gets its own euclidean pattern. Layer buttons show container names.")
            if rv then
                callbacks.setEuclideanAutoBindContainers(newValue)
                if checkAutoRegen then
                    checkAutoRegen("euclideanAutoBindContainers", trackingKey .. "_eucAutoBind", autoBind, newValue)
                end
            end
            imgui.Spacing(globals.ctx)
        end

        -- Layer selection UI
        do
            imgui.BeginGroup(globals.ctx)

            -- Determine if we're in auto-bind mode
            local isAutoBind = isGroup and (dataObj.euclideanAutoBindContainers or false)

            -- In auto-bind mode, use bindings; otherwise use layers
            local selectedIndex = 1
            local itemCount = 0
            local itemList = {}  -- List of {uuid, name, layerData} or {index, layerData}

            if isAutoBind then
                -- Auto-bind mode: show container names
                if dataObj.euclideanBindingOrder then
                    for _, uuid in ipairs(dataObj.euclideanBindingOrder) do
                        -- Find container by UUID
                        local containerName = "???"
                        if dataObj.containers then
                            for _, container in ipairs(dataObj.containers) do
                                if container.id == uuid then
                                    containerName = container.name
                                    break
                                end
                            end
                        end
                        table.insert(itemList, {
                            uuid = uuid,
                            name = containerName,
                            layerData = dataObj.euclideanLayerBindings[uuid]
                        })
                    end
                end
                itemCount = #itemList
                selectedIndex = dataObj.euclideanSelectedBindingIndex or 1
            else
                -- Manual mode: show layer numbers
                if not dataObj.euclideanLayers or #dataObj.euclideanLayers == 0 then
                    dataObj.euclideanLayers = {{pulses = 8, steps = 16, rotation = 0}}
                end
                for i, layerData in ipairs(dataObj.euclideanLayers) do
                    table.insert(itemList, {
                        index = i,
                        layerData = layerData
                    })
                end
                itemCount = #itemList
                selectedIndex = dataObj.euclideanSelectedLayer or 1
            end

            -- Layer/Container buttons
            -- NOTE: For containers in Auto-Bind mode, layers are enabled (additional to parent binding)
            for i, item in ipairs(itemList) do
                local isSelected = (i == selectedIndex)

                -- Check if this container is in Override Parent mode
                local isOverrideParent = false
                if isAutoBind and isGroup and groupIndex and item.uuid then
                    local group = globals.groups[groupIndex]
                    for _, container in ipairs(group.containers) do
                        if container.id == item.uuid and container.overrideParent and container.intervalMode == 5 then
                            isOverrideParent = true
                            break
                        end
                    end
                end

                -- Apply button color based on state
                local colorPushed = 0
                if isOverrideParent then
                    -- Orange/yellow warning color for override containers with black text
                    imgui.PushStyleColor(globals.ctx, imgui.Col_Button, 0xFFAA00FF)
                    imgui.PushStyleColor(globals.ctx, imgui.Col_Text, 0x000000FF)  -- Black text
                    colorPushed = 2
                elseif isSelected then
                    imgui.PushStyleColor(globals.ctx, imgui.Col_Button, 0x00AA77FF)
                    colorPushed = 1
                end

                local buttonLabel = ""
                local buttonWidth = 30
                if isAutoBind then
                    buttonLabel = item.name .. "##eucBinding" .. i
                    buttonWidth = 0  -- Auto-size to fit text
                else
                    -- Manual mode: Show color indicator before layer number
                    buttonLabel = tostring(i) .. "##eucLayer" .. i
                    buttonWidth = 30

                    -- Draw color indicator square before button
                    local layerColor = getEuclideanLayerColor(i)
                    imgui.ColorButton(globals.ctx, "##layerColor" .. i, layerColor, imgui.ColorEditFlags_NoTooltip, 12, 12)
                    imgui.SameLine(globals.ctx, 0, 2)
                end

                if imgui.Button(globals.ctx, buttonLabel, buttonWidth, 0) then
                    if isAutoBind then
                        callbacks.setEuclideanSelectedBindingIndex(i)
                        -- Store UUID for potential container highlight
                        callbacks.setHighlightedContainerUUID(item.uuid)
                    else
                        callbacks.setEuclideanSelectedLayer(i)
                    end
                end

                -- Pop style colors before tooltip so text stays white
                if colorPushed > 0 then
                    imgui.PopStyleColor(globals.ctx, colorPushed)
                end

                -- Tooltip for override containers (with default white text)
                if isOverrideParent and imgui.IsItemHovered(globals.ctx) then
                    imgui.SetTooltip(globals.ctx, "⚠ This container is in Override Parent mode.\nChanges sync bidirectionally with its own euclidean settings.")
                end

                imgui.SameLine(globals.ctx)
            end

            -- "+" and "-" buttons for layer management
            -- In manual mode: manage layers in euclideanLayers array
            -- In auto-bind mode: manage layers for selected container binding
            if not isAutoBind then
                -- MANUAL MODE: Add/remove layers
                if imgui.Button(globals.ctx, "+##eucAddLayer", 30, 0) then
                    callbacks.addEuclideanLayer()
                end
                if imgui.IsItemHovered(globals.ctx) then
                    imgui.SetTooltip(globals.ctx, "Add a new Euclidean layer")
                end

                -- "-" button to remove layer (only if more than 1 layer)
                if itemCount > 1 then
                    imgui.SameLine(globals.ctx)
                    if imgui.Button(globals.ctx, "-##eucRemoveLayer", 30, 0) then
                        callbacks.removeEuclideanLayer(selectedIndex)
                    end
                    if imgui.IsItemHovered(globals.ctx) then
                        imgui.SetTooltip(globals.ctx, "Remove current layer")
                    end
                end
            else
                -- AUTO-BIND MODE: Add/remove layers for selected container binding
                if imgui.Button(globals.ctx, "+##eucAddBindingLayer", 30, 0) then
                    callbacks.addEuclideanBindingLayer(selectedIndex)
                end
                if imgui.IsItemHovered(globals.ctx) then
                    imgui.SetTooltip(globals.ctx, "Add layer to selected container")
                end

                -- Get layer count for selected binding
                local bindingLayerCount = 0
                if dataObj.euclideanBindingOrder and dataObj.euclideanBindingOrder[selectedIndex] then
                    local uuid = dataObj.euclideanBindingOrder[selectedIndex]
                    if dataObj.euclideanLayerBindings and dataObj.euclideanLayerBindings[uuid] then
                        bindingLayerCount = #dataObj.euclideanLayerBindings[uuid]
                    end
                end

                -- "-" button to remove layer (only if more than 1 layer)
                if bindingLayerCount > 1 then
                    imgui.SameLine(globals.ctx)
                    if imgui.Button(globals.ctx, "-##eucRemoveBindingLayer", 30, 0) then
                        callbacks.removeEuclideanBindingLayer(selectedIndex)
                    end
                    if imgui.IsItemHovered(globals.ctx) then
                        imgui.SetTooltip(globals.ctx, "Remove selected layer from container")
                    end
                end
            end

            imgui.EndGroup(globals.ctx)
        end

        -- Warning if selected container is in Override mode
        if isAutoBind and isGroup and groupIndex then
            local selectedIndex = dataObj.euclideanSelectedBindingIndex or 1
            local bindingOrder = dataObj.euclideanBindingOrder or {}
            local uuid = bindingOrder[selectedIndex]
            if uuid then
                local group = globals.groups[groupIndex]
                for _, container in ipairs(group.containers) do
                    if container.id == uuid and container.overrideParent then
                        imgui.Spacing(globals.ctx)
                        imgui.PushStyleColor(globals.ctx, imgui.Col_Text, 0xFFAA00FF)  -- Orange warning
                        imgui.TextWrapped(globals.ctx, "⚠ This container is in Override Parent mode. Changes here will sync with the container's own settings.")
                        imgui.PopStyleColor(globals.ctx)
                        break
                    end
                end
            end
        end

        imgui.Spacing(globals.ctx)

        -- Tempo controls (only for Tempo-Based mode)
        if (dataObj.euclideanMode or 0) == 0 then
            -- Use Project Tempo checkbox (disabled for children of auto-bind groups)
            do
                imgui.BeginGroup(globals.ctx)
                if isChildOfAutobindGroup then
                    imgui.BeginDisabled(globals.ctx)
                end
                local useProjectTempo = dataObj.euclideanUseProjectTempo or false
                local rv, newValue = imgui.Checkbox(globals.ctx, "Use Project Tempo##eucUseProjectTempo", useProjectTempo)
                if rv then
                    callbacks.setEuclideanUseProjectTempo(newValue)
                    if checkAutoRegen then
                        checkAutoRegen("euclideanUseProjectTempo", trackingKey .. "_eucUseProjectTempo", useProjectTempo, newValue)
                    end
                end
                if isChildOfAutobindGroup then
                    imgui.EndDisabled(globals.ctx)
                end
                imgui.EndGroup(globals.ctx)

                if imgui.IsItemHovered(globals.ctx, isChildOfAutobindGroup and imgui.HoveredFlags_AllowWhenDisabled or 0) then
                    if isChildOfAutobindGroup then
                        imgui.SetTooltip(globals.ctx, "This parameter is controlled by the parent group in Auto-bind mode")
                    else
                        imgui.SetTooltip(globals.ctx, "Use REAPER's project tempo (supports tempo changes)")
                    end
                end
            end

            imgui.Spacing(globals.ctx)

            -- Tempo slider (only if not using project tempo, disabled for children of auto-bind groups)
            if not (dataObj.euclideanUseProjectTempo or false) then
                do
                    imgui.BeginGroup(globals.ctx)
                    if isChildOfAutobindGroup then
                        imgui.BeginDisabled(globals.ctx)
                    end
                    globals.SliderEnhanced.SliderDouble({
                        id = "##EuclideanTempo",
                        value = dataObj.euclideanTempo or 120,
                        min = 20,
                        max = 300,
                        defaultValue = globals.Constants.DEFAULTS.EUCLIDEAN_TEMPO,
                        format = "%.0f BPM",
                        width = controlWidth,
                        onChange = function(newValue)
                            callbacks.setEuclideanTempo(newValue)
                        end,
                        onChangeComplete = function(oldValue, newValue)
                            checkAutoRegen("euclideanTempo", oldValue, newValue)
                        end
                    })
                    if isChildOfAutobindGroup then
                        imgui.EndDisabled(globals.ctx)
                    end

                    imgui.EndGroup(globals.ctx)

                    imgui.SameLine(globals.ctx, controlWidth + padding)
                    imgui.Text(globals.ctx, "Tempo")
                    imgui.SameLine(globals.ctx)
                    if isChildOfAutobindGroup then
                        globals.Utils.HelpMarker("This parameter is controlled by the parent group in Auto-bind mode")
                    else
                        globals.Utils.HelpMarker("BPM for the Euclidean pattern")
                    end
                end
            end
        end

        -- Euclidean parameters: Multi-column layout for Manual mode, single column for Auto-bind
        local isAutoBind = isGroup and (dataObj.euclideanAutoBindContainers or false)

        local previewSize = UI.scaleSize(154)  -- Circle diameter

        -- Two-column layout without table: Preview on left (fixed), Layers on right (scrollable)
        local previewWidth = previewSize + 20
        local contentHeight = previewSize

        -- Left side: Preview
        UI.drawEuclideanPreview(dataObj, previewSize, isGroup)

        -- Put layers on the same line (right side)
        imgui.SameLine(globals.ctx)

        -- Right side: Scrollable container for layers with horizontal scrollbar
        local availWidth = imgui.GetContentRegionAvail(globals.ctx)

        -- Calculate total content width for all layers
        local layerCount
        if not isAutoBind then
            layerCount = #dataObj.euclideanLayers
        else
            local selectedBindingIndex = dataObj.euclideanSelectedBindingIndex or 1
            local bindingOrder = dataObj.euclideanBindingOrder or {}
            local uuid = bindingOrder[selectedBindingIndex]
            local bindingLayers = {}
            if uuid and dataObj.euclideanLayerBindings and dataObj.euclideanLayerBindings[uuid] then
                bindingLayers = dataObj.euclideanLayerBindings[uuid]
            end
            layerCount = math.max(#bindingLayers, 1)
        end

        local layerWidth = 180
        local spacing = imgui.GetStyleVar(globals.ctx, imgui.StyleVar_ItemSpacing)
        local totalWidth = (layerWidth * layerCount) + (spacing * math.max(0, layerCount - 1))

        -- Set content size BEFORE BeginChild to enable horizontal scrolling
        imgui.SetNextWindowContentSize(globals.ctx, totalWidth, 0)

        -- BeginChild with WindowFlags_HorizontalScrollbar
        -- Parameters: ctx, id, width, height, child_flags, window_flags
        local windowFlags = imgui.WindowFlags_HorizontalScrollbar
        imgui.BeginChild(globals.ctx, "EuclideanLayersScroll_" .. trackingKey, availWidth, contentHeight, 0, windowFlags)

        if not isAutoBind then
            -- MANUAL MODE: Use modular Euclidean UI
            local adaptedCallbacks = globals.EuclideanUI.createManualModeCallbacks(callbacks)
            globals.EuclideanUI.renderLayerColumns(
                dataObj.euclideanLayers,
                trackingKey,
                adaptedCallbacks,
                checkAutoRegen,
                "manual_",
                contentHeight
            )
        else
            -- AUTO-BIND MODE: Use modular Euclidean UI
            local selectedBindingIndex = dataObj.euclideanSelectedBindingIndex or 1
            local bindingOrder = dataObj.euclideanBindingOrder or {}
            local uuid = bindingOrder[selectedBindingIndex]

            -- Get binding layers for selected container
            local bindingLayers = {}
            if uuid and dataObj.euclideanLayerBindings and dataObj.euclideanLayerBindings[uuid] then
                bindingLayers = dataObj.euclideanLayerBindings[uuid]
            end

            local numLayers = #bindingLayers
            if numLayers == 0 then
                -- Fallback: create default layer
                bindingLayers = {{pulses = 8, steps = 16, rotation = 0}}
            end

            local adaptedCallbacks = globals.EuclideanUI.createAutoBindModeCallbacks(callbacks, selectedBindingIndex)
            local itemIdentifier = uuid or ("binding_" .. selectedBindingIndex)
            globals.EuclideanUI.renderLayerColumns(
                bindingLayers,
                trackingKey .. "_" .. itemIdentifier,
                adaptedCallbacks,
                checkAutoRegen,
                "bind" .. selectedBindingIndex .. "_",
                contentHeight
            )
        end

        imgui.EndChild(globals.ctx)
    end

    -- Fade in/out controls are commented out but can be enabled if needed
end

-- Display trigger and randomization settings for a group or container
function TriggerSection.displayTriggerSettings(obj, objId, width, isGroup, groupIndex, containerIndex)
    local imgui = globals.imgui
    local titlePrefix = isGroup and "Default " or ""
    local inheritText = isGroup and "These settings will be inherited by containers unless overridden" or ""


    -- Create a safe tracking key
    local trackingKey = objId or ""
    if trackingKey == "" then
        if isGroup then
            trackingKey = "group_" .. (groupIndex or "unknown")
        else
            trackingKey = "container_" .. (groupIndex or "unknown") .. "_" .. (containerIndex or "unknown")
        end
    end

    -- Helper function for auto-regeneration
    local function checkAutoRegen(paramName, oldValue, newValue)
        if oldValue ~= newValue and globals.timeSelectionValid then
            -- Value changed and time selection is valid, trigger auto-regeneration
            if isGroup then
                globals.Generation.generateSingleGroup(groupIndex)
            else
                globals.Generation.generateSingleContainer(groupIndex, containerIndex)
            end
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
                if isGroup and groupIndex and groupIndex >= 1 and groupIndex <= #globals.groups then
                    globals.Structures.syncEuclideanBindings(globals.groups[groupIndex])
                elseif not isGroup and groupIndex and groupIndex >= 1 and groupIndex <= #globals.groups then
                    -- Container mode changed - sync parent group
                    globals.Structures.syncEuclideanBindings(globals.groups[groupIndex])
                end
            end,
            setTriggerRate = function(v) obj.triggerRate = v; obj.needsRegeneration = true end,
            setTriggerDrift = function(v) obj.triggerDrift = v; obj.needsRegeneration = true end,
            setTriggerDriftDirection = function(v) obj.triggerDriftDirection = v; obj.needsRegeneration = true end,
            setFadeIn = function(v) obj.fadeIn = math.max(0, v); obj.needsRegeneration = true end,
            setFadeOut = function(v) obj.fadeOut = math.max(0, v); obj.needsRegeneration = true end,
            -- Chunk mode callbacks
            setChunkDuration = function(v) obj.chunkDuration = v; obj.needsRegeneration = true end,
            setChunkSilence = function(v) obj.chunkSilence = v; obj.needsRegeneration = true end,
            setChunkDurationVariation = function(v) obj.chunkDurationVariation = v; obj.needsRegeneration = true end,
            setChunkDurationVarDirection = function(v) obj.chunkDurationVarDirection = v; obj.needsRegeneration = true end,
            setChunkSilenceVariation = function(v) obj.chunkSilenceVariation = v; obj.needsRegeneration = true end,
            setChunkSilenceVarDirection = function(v) obj.chunkSilenceVarDirection = v; obj.needsRegeneration = true end,
            -- Noise mode callbacks
            setNoiseSeed = function(v) obj.noiseSeed = v; obj.needsRegeneration = true end,
            setNoiseAlgorithm = function(v) obj.noiseAlgorithm = v; obj.needsRegeneration = true end,
            setNoiseFrequency = function(v) obj.noiseFrequency = v; obj.needsRegeneration = true end,
            setNoiseAmplitude = function(v) obj.noiseAmplitude = v; obj.needsRegeneration = true end,
            setNoiseOctaves = function(v) obj.noiseOctaves = v; obj.needsRegeneration = true end,
            setNoisePersistence = function(v) obj.noisePersistence = v; obj.needsRegeneration = true end,
            setNoiseLacunarity = function(v) obj.noiseLacunarity = v; obj.needsRegeneration = true end,
            setNoiseDensity = function(v) obj.noiseDensity = v; obj.needsRegeneration = true end,
            setNoiseThreshold = function(v) obj.noiseThreshold = v; obj.needsRegeneration = true end,
            -- Euclidean mode callbacks
            setEuclideanMode = function(v)
                obj.euclideanMode = v

                -- If group, sync to all containers in override mode with Euclidean (parent -> children only)
                if isGroup and groupIndex then
                    local group = globals.groups[groupIndex]
                    for _, container in ipairs(group.containers) do
                        if container.overrideParent and container.intervalMode == 5 then
                            container.euclideanMode = v
                            container.needsRegeneration = true
                        end
                    end
                end

                obj.needsRegeneration = true
            end,
            setEuclideanTempo = function(v)
                obj.euclideanTempo = v

                -- If group, sync to all containers in override mode with Euclidean (parent -> children only)
                if isGroup and groupIndex then
                    local group = globals.groups[groupIndex]
                    for _, container in ipairs(group.containers) do
                        if container.overrideParent and container.intervalMode == 5 then
                            container.euclideanTempo = v
                            container.needsRegeneration = true
                        end
                    end
                end

                obj.needsRegeneration = true
            end,
            setEuclideanUseProjectTempo = function(v)
                obj.euclideanUseProjectTempo = v

                -- If group, sync to all containers in override mode with Euclidean (parent -> children only)
                if isGroup and groupIndex then
                    local group = globals.groups[groupIndex]
                    for _, container in ipairs(group.containers) do
                        if container.overrideParent and container.intervalMode == 5 then
                            container.euclideanUseProjectTempo = v
                            container.needsRegeneration = true
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
                if not isGroup and containerIndex and groupIndex then
                    local group = globals.groups[groupIndex]
                    local container = group.containers[containerIndex]
                    if container and container.overrideParent and container.intervalMode == 5 and container.id then
                        if group.euclideanLayerBindings and group.euclideanLayerBindings[container.id] then
                            table.insert(group.euclideanLayerBindings[container.id], {pulses = 8, steps = 16, rotation = 0})
                            -- Sync selected layer index
                            group.euclideanSelectedLayerPerBinding[container.id] = #group.euclideanLayerBindings[container.id]
                            -- Don't mark group for regeneration - only the container needs regen
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
                if not isGroup and containerIndex and groupIndex then
                    local group = globals.groups[groupIndex]
                    local container = group.containers[containerIndex]
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

                obj.needsRegeneration = true
            end,
            setEuclideanLayerPulses = function(layerIdx, v)
                if not obj.euclideanLayers or not obj.euclideanLayers[layerIdx] then return end
                obj.euclideanLayers[layerIdx].pulses = v

                -- If this is a container in override mode with Euclidean, sync back to parent binding
                if not isGroup and containerIndex and groupIndex then
                    local group = globals.groups[groupIndex]
                    local container = group.containers[containerIndex]
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

                obj.needsRegeneration = true
            end,
            setEuclideanLayerSteps = function(layerIdx, v)
                if not obj.euclideanLayers or not obj.euclideanLayers[layerIdx] then return end
                obj.euclideanLayers[layerIdx].steps = v

                -- If this is a container in override mode with Euclidean, sync back to parent binding
                if not isGroup and containerIndex and groupIndex then
                    local group = globals.groups[groupIndex]
                    local container = group.containers[containerIndex]
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

                obj.needsRegeneration = true
            end,
            setEuclideanLayerRotation = function(layerIdx, v)
                if not obj.euclideanLayers or not obj.euclideanLayers[layerIdx] then return end
                obj.euclideanLayers[layerIdx].rotation = v

                -- If this is a container in override mode with Euclidean, sync back to parent binding
                if not isGroup and containerIndex and groupIndex then
                    local group = globals.groups[groupIndex]
                    local container = group.containers[containerIndex]
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

                obj.needsRegeneration = true
            end,
            -- Euclidean auto-bind mode callbacks
            setEuclideanAutoBindContainers = function(v)
                obj.euclideanAutoBindContainers = v
                -- Sync bindings when toggling auto-bind
                if v and isGroup and groupIndex and groupIndex >= 1 and groupIndex <= #globals.groups then
                    globals.Structures.syncEuclideanBindings(globals.groups[groupIndex])
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
                if isGroup and groupIndex then
                    local group = globals.groups[groupIndex]
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
                if isGroup and groupIndex then
                    local group = globals.groups[groupIndex]
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

                -- Mark the container for regeneration and sync if it's in override mode
                if isGroup and groupIndex then
                    local group = globals.groups[groupIndex]
                    for _, container in ipairs(group.containers) do
                        if container.id == uuid then
                            -- Always mark container for regeneration
                            container.needsRegeneration = true

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

                -- Don't mark group for regeneration - only the container needs it
            end,
            setEuclideanBindingSteps = function(bindingIdx, layerIdx, v)
                if not obj.euclideanBindingOrder or not obj.euclideanBindingOrder[bindingIdx] then return end
                local uuid = obj.euclideanBindingOrder[bindingIdx]
                if not obj.euclideanLayerBindings or not obj.euclideanLayerBindings[uuid] then return end
                if not obj.euclideanLayerBindings[uuid][layerIdx] then return end

                obj.euclideanLayerBindings[uuid][layerIdx].steps = v

                -- Mark the container for regeneration and sync if it's in override mode
                if isGroup and groupIndex then
                    local group = globals.groups[groupIndex]
                    for _, container in ipairs(group.containers) do
                        if container.id == uuid then
                            -- Always mark container for regeneration
                            container.needsRegeneration = true

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

                -- Don't mark group for regeneration - only the container needs it
            end,
            setEuclideanBindingRotation = function(bindingIdx, layerIdx, v)
                if not obj.euclideanBindingOrder or not obj.euclideanBindingOrder[bindingIdx] then return end
                local uuid = obj.euclideanBindingOrder[bindingIdx]
                if not obj.euclideanLayerBindings or not obj.euclideanLayerBindings[uuid] then return end
                if not obj.euclideanLayerBindings[uuid][layerIdx] then return end

                obj.euclideanLayerBindings[uuid][layerIdx].rotation = v

                -- Mark the container for regeneration and sync if it's in override mode
                if isGroup and groupIndex then
                    local group = globals.groups[groupIndex]
                    for _, container in ipairs(group.containers) do
                        if container.id == uuid then
                            -- Always mark container for regeneration
                            container.needsRegeneration = true

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

                obj.needsRegeneration = true
            end,
        },
        width,
        titlePrefix,
        nil,  -- Don't pass auto-regen callback - let needsRegeneration flag be used instead
        isGroup,         -- Pass isGroup flag
        groupIndex,      -- Pass group index
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
        if groupIndex and containerIndex then
            globals.Utils.queueRandomizationUpdate(groupIndex, containerIndex, "pitch")
        elseif groupIndex then
            globals.Utils.queueRandomizationUpdate(groupIndex, nil, "pitch")
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
            obj.needsRegeneration = true
        end,
        onChangeComplete = function()
            if groupIndex and containerIndex then
                globals.Utils.queueRandomizationUpdate(groupIndex, containerIndex, "pitch")
            elseif groupIndex then
                globals.Utils.queueRandomizationUpdate(groupIndex, nil, "pitch")
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
        if groupIndex and containerIndex then
            local group = globals.groups[groupIndex]
            local container = group.containers[containerIndex]
            globals.Generation.syncPitchModeOnExistingItems(group, container)
        elseif groupIndex then
            -- For group-level toggle, sync all containers
            local group = globals.groups[groupIndex]
            for _, container in ipairs(group.containers) do
                if not container.overrideParent then
                    globals.Generation.syncPitchModeOnExistingItems(group, container)
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
        if groupIndex and containerIndex then
            globals.Utils.queueRandomizationUpdate(groupIndex, containerIndex, "volume")
        elseif groupIndex then
            globals.Utils.queueRandomizationUpdate(groupIndex, nil, "volume")
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
            obj.needsRegeneration = true
        end,
        onChangeComplete = function()
            if groupIndex and containerIndex then
                globals.Utils.queueRandomizationUpdate(groupIndex, containerIndex, "volume")
            elseif groupIndex then
                globals.Utils.queueRandomizationUpdate(groupIndex, nil, "volume")
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
    if groupIndex and containerIndex then
        -- For containers, check if it's in multichannel mode (non-stereo)
        local container = globals.groups[groupIndex].containers[containerIndex]
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
            if groupIndex and containerIndex then
                globals.Utils.queueRandomizationUpdate(groupIndex, containerIndex, "pan")
            elseif groupIndex then
                globals.Utils.queueRandomizationUpdate(groupIndex, nil, "pan")
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
                obj.needsRegeneration = true
            end,
            onChangeComplete = function()
                if groupIndex and containerIndex then
                    globals.Utils.queueRandomizationUpdate(groupIndex, containerIndex, "pan")
                elseif groupIndex then
                    globals.Utils.queueRandomizationUpdate(groupIndex, nil, "pan")
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
    globals.UI.drawFadeSettingsSection(obj, objId, width, titlePrefix, groupIndex, containerIndex)
end

return TriggerSection
