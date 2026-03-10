--[[
@version 1.0
@noindex
@description Noise mode controls for TriggerSection
Extracted from DM_Ambiance_UI_TriggerSection.lua
--]]

local TriggerSection_Noise = {}
local globals = {}

function TriggerSection_Noise.initModule(g)
    globals = g
end

-- Draw noise mode specific controls
-- @param dataObj table: Container or group object with noise parameters
-- @param callbacks table: Callback functions for parameter changes
-- @param trackingKey string: Unique key for tracking state
-- @param width number: Available width for controls
-- @param checkAutoRegen function: Function to check if auto-regen is needed
-- @param UI table: Reference to main UI module for helpers
function TriggerSection_Noise.draw(dataObj, callbacks, trackingKey, width, checkAutoRegen, UI)
    local imgui = globals.imgui

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
    TriggerSection_Noise.drawDensityRange(dataObj, callbacks, trackingKey, controlWidth, padding, checkAutoRegen)

    -- Noise Algorithm selector
    TriggerSection_Noise.drawAlgorithmSelector(dataObj, callbacks, trackingKey, controlWidth, padding, checkAutoRegen)

    -- Noise Resolution slider (only for Probability algorithm; Accumulation is resolution-independent)
    local algorithm = dataObj.noiseAlgorithm or globals.Constants.DEFAULTS.NOISE_ALGORITHM
    if algorithm == globals.Constants.NOISE_ALGORITHMS.PROBABILITY then
        TriggerSection_Noise.drawResolutionSlider(dataObj, callbacks, controlWidth, padding, checkAutoRegen)
    end

    -- Noise Placement Anchor toggle
    TriggerSection_Noise.drawPlacementAnchorSelector(dataObj, callbacks, trackingKey, controlWidth, padding, checkAutoRegen)

    -- Noise Frequency slider
    TriggerSection_Noise.drawFrequencySlider(dataObj, callbacks, controlWidth, padding, checkAutoRegen)

    -- Noise Amplitude slider
    TriggerSection_Noise.drawAmplitudeSlider(dataObj, callbacks, controlWidth, padding, checkAutoRegen)

    -- Noise Octaves slider
    TriggerSection_Noise.drawOctavesSlider(dataObj, callbacks, controlWidth, padding, checkAutoRegen)

    -- Noise Persistence slider
    TriggerSection_Noise.drawPersistenceSlider(dataObj, callbacks, controlWidth, padding, checkAutoRegen)

    -- Noise Lacunarity slider
    TriggerSection_Noise.drawLacunaritySlider(dataObj, callbacks, controlWidth, padding, checkAutoRegen)

    -- Noise Seed control with randomize button
    TriggerSection_Noise.drawSeedControl(dataObj, callbacks, trackingKey, controlWidth, padding)

    -- Noise Visualization
    TriggerSection_Noise.drawNoisePreview(dataObj, width, UI)
end

-- Draw density range controls (Min/Max density with link mode)
function TriggerSection_Noise.drawDensityRange(dataObj, callbacks, trackingKey, controlWidth, padding, checkAutoRegen)
    local imgui = globals.imgui

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
    local linkButtonWidth = 24
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
        if wasReset1 then anyWasReset = true end
    end
    if imgui.IsItemActive(globals.ctx) then anyActive = true end
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
        if wasReset2 then anyWasReset = true end
    end
    if imgui.IsItemActive(globals.ctx) then anyActive = true end
    newValues[2] = newDensity

    -- Apply link mode logic if any slider changed
    if anyChanged then
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
        local origValues = globals.linkedSlidersTracking[trackingKey_density].originalValues
        local hasChanged = math.abs(dataObj.noiseThreshold - origValues[1]) > 0.001
            or math.abs(dataObj.noiseDensity - origValues[2]) > 0.001
        if hasChanged and checkAutoRegen then
            checkAutoRegen("densityRange", origValues, {dataObj.noiseThreshold, dataObj.noiseDensity})
        end
        globals.linkedSlidersTracking[trackingKey_density] = nil
    end

    imgui.EndGroup(globals.ctx)

    -- Label and help marker
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

-- Draw algorithm selector
function TriggerSection_Noise.drawAlgorithmSelector(dataObj, callbacks, trackingKey, controlWidth, padding, checkAutoRegen)
    local imgui = globals.imgui

    imgui.BeginGroup(globals.ctx)
    imgui.PushItemWidth(globals.ctx, controlWidth)
    local algorithmNames = "Probability\0Accumulation\0"
    local currentAlgorithm = dataObj.noiseAlgorithm or globals.Constants.NOISE_ALGORITHMS.PROBABILITY
    -- Remap old Poisson (1) to Accumulation (1), keep others
    if currentAlgorithm > 1 then currentAlgorithm = 1 end
    local rv, newAlgorithm = globals.UndoWrappers.Combo(globals.ctx, "##NoiseAlgorithm", currentAlgorithm, algorithmNames)
    if rv then
        callbacks.setNoiseAlgorithm(newAlgorithm)
        if checkAutoRegen then
            checkAutoRegen("noiseAlgorithm", currentAlgorithm, newAlgorithm)
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

-- Draw resolution slider
function TriggerSection_Noise.drawResolutionSlider(dataObj, callbacks, controlWidth, padding, checkAutoRegen)
    local imgui = globals.imgui

    imgui.BeginGroup(globals.ctx)
    globals.SliderEnhanced.SliderInt({
        id = "##NoiseResolution",
        value = dataObj.noiseResolution or globals.Constants.DEFAULTS.NOISE_RESOLUTION,
        min = globals.Constants.DEFAULTS.NOISE_RESOLUTION_MIN,
        max = globals.Constants.DEFAULTS.NOISE_RESOLUTION_MAX,
        defaultValue = globals.Constants.DEFAULTS.NOISE_RESOLUTION,
        format = "%d",
        width = controlWidth,
        onChange = function(newValue)
            callbacks.setNoiseResolution(newValue)
        end,
        onChangeComplete = function(oldValue, newValue)
            checkAutoRegen("noiseResolution", oldValue, newValue)
        end
    })
    imgui.EndGroup(globals.ctx)

    imgui.SameLine(globals.ctx, controlWidth + padding)
    imgui.Text(globals.ctx, "Resolution")
    imgui.SameLine(globals.ctx)
    globals.Utils.HelpMarker(
        "Placement evaluation precision (samples per second).\n\n" ..
        "Controls how often the noise curve is sampled for item placement.\n" ..
        "Independent of Frequency (which controls curve shape).\n\n" ..
        "• 1 = Coarse grid (1 evaluation/sec)\n" ..
        "• 10 = Default (10 evaluations/sec)\n" ..
        "• 100 = Very fine (100 evaluations/sec)\n\n" ..
        "Higher values = more precise placement but more CPU usage."
    )
end

-- Draw placement anchor selector
function TriggerSection_Noise.drawPlacementAnchorSelector(dataObj, callbacks, trackingKey, controlWidth, padding, checkAutoRegen)
    local imgui = globals.imgui

    imgui.BeginGroup(globals.ctx)
    imgui.PushItemWidth(globals.ctx, controlWidth)
    local anchorNames = "Start \xE2\x86\x92 Start (allow overlap)\0End \xE2\x86\x92 Start (no overlap)\0"
    local currentAnchor = dataObj.noisePlacementAnchor or globals.Constants.DEFAULTS.NOISE_PLACEMENT_ANCHOR
    local rv, newAnchor = globals.UndoWrappers.Combo(globals.ctx, "##NoisePlacementAnchor", currentAnchor, anchorNames)
    if rv then
        callbacks.setNoisePlacementAnchor(newAnchor)
        if checkAutoRegen then
            checkAutoRegen("noisePlacementAnchor", currentAnchor, newAnchor)
        end
    end
    imgui.PopItemWidth(globals.ctx)
    imgui.EndGroup(globals.ctx)

    imgui.SameLine(globals.ctx, controlWidth + padding)
    imgui.Text(globals.ctx, "Placement")
    imgui.SameLine(globals.ctx)
    globals.Utils.HelpMarker(
        "Controls how items relate to each other temporally:\n\n" ..
        "• Start \xE2\x86\x92 Start: Next item is placed relative to previous item's START.\n" ..
        "  Items may overlap. Good for layered textures.\n\n" ..
        "• End \xE2\x86\x92 Start: Next item is placed AFTER previous item ends.\n" ..
        "  No overlap. Good for SFX, dialogue, punctual sounds."
    )
end

-- Draw frequency slider
function TriggerSection_Noise.drawFrequencySlider(dataObj, callbacks, controlWidth, padding, checkAutoRegen)
    local imgui = globals.imgui

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
        "Controls the speed of density variations over time (Hz).\n" ..
        "Only affects the noise curve shape, NOT placement precision.\n\n" ..
        "• 0.01 = Very slow (one cycle every 100 seconds)\n" ..
        "• 0.1 = Default (one cycle every 10 seconds)\n" ..
        "• 1.0 = Fast (one cycle per second)\n" ..
        "• 10.0 = Very fast (ten cycles per second)"
    )
end

-- Draw amplitude slider
function TriggerSection_Noise.drawAmplitudeSlider(dataObj, callbacks, controlWidth, padding, checkAutoRegen)
    local imgui = globals.imgui

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

-- Draw octaves slider
function TriggerSection_Noise.drawOctavesSlider(dataObj, callbacks, controlWidth, padding, checkAutoRegen)
    local imgui = globals.imgui

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

-- Draw persistence slider
function TriggerSection_Noise.drawPersistenceSlider(dataObj, callbacks, controlWidth, padding, checkAutoRegen)
    local imgui = globals.imgui

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

-- Draw lacunarity slider
function TriggerSection_Noise.drawLacunaritySlider(dataObj, callbacks, controlWidth, padding, checkAutoRegen)
    local imgui = globals.imgui

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

-- Draw seed control with randomize button
function TriggerSection_Noise.drawSeedControl(dataObj, callbacks, trackingKey, controlWidth, padding)
    local imgui = globals.imgui

    imgui.BeginGroup(globals.ctx)

    -- Calculate input width (subtract button width and spacing)
    local buttonWidth = 40
    local spacing = 4
    local inputWidth = controlWidth - buttonWidth - spacing

    imgui.PushItemWidth(globals.ctx, inputWidth)

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

-- Draw noise visualization preview
function TriggerSection_Noise.drawNoisePreview(dataObj, width, UI)
    local imgui = globals.imgui

    imgui.Spacing(globals.ctx)
    imgui.Text(globals.ctx, "Noise Preview:")
    if not globals.timeSelectionValid then
        imgui.SameLine(globals.ctx)
        imgui.TextColored(globals.ctx, 0xAAAA00FF, "(preview mode - 60s - Add time selection to better tweak)")
    end

    local legendWidth = UI.scaleSize(80)
    local previewWidth = width - legendWidth - UI.scaleSize(10)
    local previewHeight = UI.scaleSize(120)

    -- Draw preview and legend side by side
    imgui.BeginGroup(globals.ctx)
    UI.drawNoisePreview(dataObj, previewWidth, previewHeight)
    imgui.EndGroup(globals.ctx)

    imgui.SameLine(globals.ctx)

    -- Legend using invisible table for perfect alignment
    imgui.BeginGroup(globals.ctx)
    imgui.Dummy(globals.ctx, 0, 10)

    local drawList = imgui.GetWindowDrawList(globals.ctx)
    local waveformColor = globals.Settings.getSetting("waveformColor")

    -- Create invisible table with 2 columns (icon + text)
    local tableFlags = imgui.TableFlags_None
    if imgui.BeginTable(globals.ctx, "LegendTable", 2, tableFlags) then
        imgui.TableSetupColumn(globals.ctx, "Icon", imgui.TableColumnFlags_WidthFixed, 25)
        imgui.TableSetupColumn(globals.ctx, "Label", imgui.TableColumnFlags_WidthStretch)

        -- Row 1: Noise line
        imgui.TableNextRow(globals.ctx)
        imgui.TableSetColumnIndex(globals.ctx, 0)

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

return TriggerSection_Noise
