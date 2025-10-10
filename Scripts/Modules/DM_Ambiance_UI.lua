--[[
@version 1.3
@noindex
--]]

local UI = {}
local globals = {}
local Utils = require("DM_Ambiance_Utils")
local Structures = require("DM_Ambiance_Structures")
local Items = require("DM_Ambiance_Items")
local Presets = require("DM_Ambiance_Presets")
local Generation = require("DM_Ambiance_Generation")

-- Import UI submodules
local UI_Preset = require("DM_Ambiance_UI_Preset")
local UI_Container = require("DM_Ambiance_UI_Container")
local UI_Groups = require("DM_Ambiance_UI_Groups")
local UI_MultiSelection = require("DM_Ambiance_UI_MultiSelection")
local UI_Generation = require("DM_Ambiance_UI_Generation")
local UI_Group = require("DM_Ambiance_UI_Group")
local Icons = require("DM_Ambiance_Icons")

-- Initialize the module with global variables from the main script
function UI.initModule(g)
    globals = g

    -- Initialize selection variables for two-panel layout
    globals.selectedGroupIndex = nil
    globals.selectedContainerIndex = nil

    -- Initialize structure for multi-selection
    globals.selectedContainers = {} -- Format: {[groupIndex_containerIndex] = true}
    globals.inMultiSelectMode = false

    -- Initialize variables for Shift multi-selection
    globals.shiftAnchorGroupIndex = nil
    globals.shiftAnchorContainerIndex = nil

    -- Initialize splitter state
    globals.splitterDragging = false
    globals.leftPanelWidth = nil  -- Will be loaded from settings

    -- Initialize UI submodules with globals
    UI_Preset.initModule(globals)
    UI_Container.initModule(globals)
    UI_Groups.initModule(globals)
    UI_MultiSelection.initModule(globals)
    UI_Generation.initModule(globals)
    UI_Group.initModule(globals)
    Icons.initModule(globals)

    -- Make UI_Groups accessible to the UI_Group module
    globals.UI_Groups = UI_Groups

    -- Make Icons accessible to other modules
    globals.Icons = Icons

    -- Make UI accessible to other modules
    globals.UI = UI

    -- Detect default font size from ImGui
    globals.defaultFontSize = imgui.GetFontSize(globals.ctx) or 13
end

-- Helper function to scale a size value
function UI.scaleSize(size)
    local uiScale = globals.Settings.getSetting("uiScale") or 1.0
    return size * uiScale
end

-- Wrapper for Button with automatic scaling
function UI.Button(ctx, label, width, height)
    local scaledWidth = width and UI.scaleSize(width) or width
    local scaledHeight = height and UI.scaleSize(height) or height
    return globals.imgui.Button(ctx, label, scaledWidth, scaledHeight)
end

-- Update UI scale (called when scale changes)
function UI.updateScale(scale)
    local ctx = globals.ctx
    local imgui = globals.imgui

    -- Only update if scale actually changed
    if globals.currentScale == scale then
        return
    end

    local oldScale = globals.currentScale or 1.0
    globals.currentScale = scale

    -- Detach old font if exists
    if globals.scaledFont then
        imgui.Detach(ctx, globals.scaledFont)
        globals.scaledFont = nil
    end

    -- Create scaled font using detected default font size
    local baseFontSize = globals.defaultFontSize or 13
    local scaledSize = math.floor(baseFontSize * scale + 0.5) -- Round to nearest integer

    globals.scaledFont = imgui.CreateFont('sans-serif', scaledSize)
    imgui.Attach(ctx, globals.scaledFont)

    -- Scale waveform heights proportionally when scale changes
    if globals.waveformHeights then
        local scaleFactor = scale / oldScale
        for key, height in pairs(globals.waveformHeights) do
            globals.waveformHeights[key] = height * scaleFactor
        end
    end
end

-- Push custom style variables for UI
function UI.PushStyle()
    local ctx = globals.ctx
    local imgui = globals.imgui
    local settings = globals.Settings
    local utils = globals.Utils

    -- Update UI scale if changed
    local uiScale = settings.getSetting("uiScale") or 1.0
    UI.updateScale(uiScale)

    -- Push scaled font
    if globals.scaledFont then
        imgui.PushFont(ctx, globals.scaledFont)
    end

    -- Item Spacing (scaled)
    local itemSpacing = settings.getSetting("itemSpacing") * uiScale
    imgui.PushStyleVar(ctx, imgui.StyleVar_ItemSpacing, itemSpacing, itemSpacing)

    -- Frame padding (scaled)
    imgui.PushStyleVar(ctx, imgui.StyleVar_FramePadding, 4 * uiScale, 3 * uiScale)

    -- Window padding (scaled)
    imgui.PushStyleVar(ctx, imgui.StyleVar_WindowPadding, 8 * uiScale, 8 * uiScale)

    -- Round Style for buttons and frames (scaled)
    local rounding = settings.getSetting("uiRounding") * uiScale

    -- Apply the user-defined rounding value
    imgui.PushStyleVar(ctx, imgui.StyleVar_DisabledAlpha, 0.68)
    imgui.PushStyleVar(ctx, imgui.StyleVar_FrameRounding, rounding)
    imgui.PushStyleVar(ctx, imgui.StyleVar_GrabRounding, rounding)
    imgui.PushStyleVar(ctx, imgui.StyleVar_GrabMinSize, 10 * uiScale)
    
    -- Colors
    local buttonColor = settings.getSetting("buttonColor")
    local backgroundColor = settings.getSetting("backgroundColor")
    local textColor = settings.getSetting("textColor")
    local waveformColor = settings.getSetting("waveformColor")
    
    -- Apply button colors
    imgui.PushStyleColor(ctx, imgui.Col_Button, buttonColor)
    imgui.PushStyleColor(ctx, imgui.Col_ButtonHovered, utils.brightenColor(buttonColor, 0.1))
    imgui.PushStyleColor(ctx, imgui.Col_ButtonActive, utils.brightenColor(buttonColor, -0.1))
    -- Apply scroll bars
    imgui.PushStyleColor(ctx, imgui.Col_ScrollbarGrab, buttonColor)
    imgui.PushStyleColor(ctx, imgui.Col_ScrollbarGrabHovered, utils.brightenColor(buttonColor, 0.1))
    imgui.PushStyleColor(ctx, imgui.Col_ScrollbarGrabActive, utils.brightenColor(buttonColor, -0.1))
    -- Apply sliders
    imgui.PushStyleColor(ctx, imgui.Col_SliderGrab, buttonColor)
    imgui.PushStyleColor(ctx, imgui.Col_SliderGrabActive, buttonColor)
    -- Apply check marks
    imgui.PushStyleColor(ctx, imgui.Col_CheckMark, buttonColor)
    
    -- Apply background colors
    imgui.PushStyleColor(ctx, imgui.Col_Header, utils.brightenColor(backgroundColor, 0.1))
    imgui.PushStyleColor(ctx, imgui.Col_HeaderActive, utils.brightenColor(backgroundColor, 0.2))
    imgui.PushStyleColor(ctx, imgui.Col_HeaderHovered, utils.brightenColor(backgroundColor, 0.15))
    imgui.PushStyleColor(ctx, imgui.Col_TitleBgActive, utils.brightenColor(backgroundColor, -0.01))
    imgui.PushStyleColor(ctx, imgui.Col_WindowBg, backgroundColor)
    imgui.PushStyleColor(ctx, imgui.Col_PopupBg, utils.brightenColor(backgroundColor, 0.05))
    imgui.PushStyleColor(ctx, imgui.Col_FrameBg, utils.brightenColor(backgroundColor, 0.1))
    imgui.PushStyleColor(ctx, imgui.Col_FrameBgHovered, utils.brightenColor(backgroundColor, 0.15))
    imgui.PushStyleColor(ctx, imgui.Col_FrameBgActive, utils.brightenColor(backgroundColor, 0.2))
    
    -- Apply text colors
    imgui.PushStyleColor(ctx, imgui.Col_Text, textColor)
    imgui.PushStyleColor(ctx, imgui.Col_CheckMark, textColor)
end


-- Pop custom style variables
function UI.PopStyle()
    local ctx = globals.ctx
    local imgui = globals.imgui

    -- Pop font if we pushed one
    if globals.scaledFont then
        imgui.PopFont(ctx)
    end

    -- Increase the number for PushStyleColor
    imgui.PopStyleColor(ctx, 20)

    -- Increase the number for PushStyleVar (now 8: ItemSpacing, FramePadding, WindowPadding, DisabledAlpha, FrameRounding, GrabRounding, GrabMinSize)
    imgui.PopStyleVar(ctx, 7)
end


-- Clear all container selections and reset selection state
local function clearContainerSelections()
    globals.selectedContainers = {}
    globals.inMultiSelectMode = false
    -- Also clear the shift anchor when clearing selections
    globals.shiftAnchorGroupIndex = nil
    globals.shiftAnchorContainerIndex = nil
end

-- Utility function to cycle through link modes
local function cycleLinkMode(currentMode)
    if currentMode == "unlink" then
        return "link"
    elseif currentMode == "link" then
        return "mirror"
    else -- currentMode == "mirror"
        return "unlink"
    end
end

-- Utility function to cycle through fade link modes
-- Fades support all three modes: unlink, link, and mirror
local function cycleFadeLinkMode(currentMode)
    return globals.LinkedSliders.cycleLinkMode(currentMode)
end

-- Apply linked slider changes
-- Keyboard shortcuts: Shift = unlink, Ctrl = link, Alt = mirror
local function applyLinkedSliderChange(obj, paramType, newMin, newMax, linkMode)
    -- Keyboard overrides for temporary mode changes (priority: Shift > Alt > Ctrl)
    if imgui.IsKeyDown(globals.ctx, imgui.Mod_Shift) then
        linkMode = "unlink"
    elseif imgui.IsKeyDown(globals.ctx, imgui.Mod_Alt) then
        linkMode = "mirror"
    elseif imgui.IsKeyDown(globals.ctx, imgui.Mod_Ctrl) then
        linkMode = "link"
    end

    if linkMode == "unlink" then
        -- Independent sliders - just apply the new values
        return newMin, newMax
    elseif linkMode == "link" then
        -- Linked sliders - maintain relative distance
        local currentMin = obj[paramType .. "Range"].min
        local currentMax = obj[paramType .. "Range"].max
        local currentRange = currentMax - currentMin
        
        -- Calculate which slider moved and apply the same relative change to both
        local minDiff = newMin - currentMin
        local maxDiff = newMax - currentMax
        
        if math.abs(minDiff) > math.abs(maxDiff) then
            -- Min slider moved more, adjust max to maintain relative distance
            return newMin, newMin + currentRange
        else
            -- Max slider moved more, adjust min to maintain relative distance  
            return newMax - currentRange, newMax
        end
    elseif linkMode == "mirror" then
        -- Mirror sliders - move opposite amounts from center
        local currentMin = obj[paramType .. "Range"].min
        local currentMax = obj[paramType .. "Range"].max
        local center = (currentMin + currentMax) / 2
        
        -- Calculate which slider moved and mirror the change
        local minDiff = newMin - currentMin
        local maxDiff = newMax - currentMax
        
        if math.abs(minDiff) > math.abs(maxDiff) then
            -- Min slider moved, mirror the change to max
            local newMinFromCenter = newMin - center
            return newMin, center - newMinFromCenter
        else
            -- Max slider moved, mirror the change to min
            local newMaxFromCenter = newMax - center
            return center - newMaxFromCenter, newMax
        end
    end
    
    return newMin, newMax
end

--- Helper to draw a slider row with automatic variation controls using table layout
-- This provides consistent alignment without pixel-perfect positioning
local function drawSliderWithVariation(params)
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

    local rv, newValue, wasReset = globals.SliderEnhanced.SliderDouble({
        id = sliderId,
        value = sliderValue,
        min = sliderMin,
        max = sliderMax,
        defaultValue = defaultValue,
        format = sliderFormat
    })

    -- Auto-regen tracking (skip if this was a reset)
    if not wasReset then
        if imgui.IsItemActive(globals.ctx) and not globals.autoRegenTracking[trackingKey] then
            globals.autoRegenTracking[trackingKey] = sliderValue
        end
    end

    if rv and callbacks.setValue then callbacks.setValue(newValue) end

    -- Only check auto-regen if NOT a reset
    if not wasReset then
        if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and globals.autoRegenTracking[trackingKey] then
            if checkAutoRegen then
                checkAutoRegen(trackingKey, globals.autoRegenTracking[trackingKey], sliderValue)
            end
            globals.autoRegenTracking[trackingKey] = nil
        end
    end

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

--- Draw the trigger settings section (shared by groups and containers)
-- dataObj must expose: intervalMode, triggerRate, triggerDrift, fadeIn, fadeOut
-- callbacks must provide setters for each parameter
function UI.drawTriggerSettingsSection(dataObj, callbacks, width, titlePrefix, autoRegenCallback)
    -- Section separator and title
    imgui.Separator(globals.ctx)
    imgui.Text(globals.ctx, titlePrefix .. "Generation Settings")

    -- Initialize auto-regen tracking if not exists and callback provided
    if autoRegenCallback and not globals.autoRegenTracking then
        globals.autoRegenTracking = {}
    end

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
        local intervalModes = "Absolute\0Relative\0Coverage\0Chunk\0Noise\0"
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
            "Noise: Place items based on Perlin noise function"
        )

        -- Interval value (slider) - Not shown in Noise mode
        if dataObj.intervalMode ~= 4 then
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

        -- Noise Frequency slider
        do
            imgui.BeginGroup(globals.ctx)
            local freqKey = trackingKey .. "_noiseFrequency"
            local rv, newFreq = globals.SliderEnhanced.SliderDouble({
                id = "##NoiseFrequency",
                value = dataObj.noiseFrequency,
                min = 0.01,
                max = 10.0,
                defaultValue = globals.Constants.DEFAULTS.NOISE_FREQUENCY,
                format = "%.2f",
                width = controlWidth
            })

            if imgui.IsItemActive(globals.ctx) and not globals.autoRegenTracking[freqKey] then
                globals.autoRegenTracking[freqKey] = dataObj.noiseFrequency
            end

            if rv then callbacks.setNoiseFrequency(newFreq) end

            if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and globals.autoRegenTracking[freqKey] then
                checkAutoRegen("noiseFrequency", freqKey, globals.autoRegenTracking[freqKey], dataObj.noiseFrequency)
                globals.autoRegenTracking[freqKey] = nil
            end

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
            local ampKey = trackingKey .. "_noiseAmplitude"
            local rv, newAmp = globals.SliderEnhanced.SliderDouble({
                id = "##NoiseAmplitude",
                value = dataObj.noiseAmplitude,
                min = 0.0,
                max = 100.0,
                defaultValue = globals.Constants.DEFAULTS.NOISE_AMPLITUDE,
                format = "%.1f%%",
                width = controlWidth
            })

            if imgui.IsItemActive(globals.ctx) and not globals.autoRegenTracking[ampKey] then
                globals.autoRegenTracking[ampKey] = dataObj.noiseAmplitude
            end

            if rv then callbacks.setNoiseAmplitude(newAmp) end

            if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and globals.autoRegenTracking[ampKey] then
                checkAutoRegen("noiseAmplitude", ampKey, globals.autoRegenTracking[ampKey], dataObj.noiseAmplitude)
                globals.autoRegenTracking[ampKey] = nil
            end

            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Amplitude")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("Intensity of density variation around average")
        end

        -- Noise Octaves slider
        do
            imgui.BeginGroup(globals.ctx)
            local octKey = trackingKey .. "_noiseOctaves"
            local rv, newOct = globals.SliderEnhanced.SliderInt({
                id = "##NoiseOctaves",
                value = dataObj.noiseOctaves,
                min = 1,
                max = 6,
                defaultValue = globals.Constants.DEFAULTS.NOISE_OCTAVES,
                format = "%d",
                width = controlWidth
            })

            if imgui.IsItemActive(globals.ctx) and not globals.autoRegenTracking[octKey] then
                globals.autoRegenTracking[octKey] = dataObj.noiseOctaves
            end

            if rv then callbacks.setNoiseOctaves(newOct) end

            if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and globals.autoRegenTracking[octKey] then
                checkAutoRegen("noiseOctaves", octKey, globals.autoRegenTracking[octKey], dataObj.noiseOctaves)
                globals.autoRegenTracking[octKey] = nil
            end

            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Octaves")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("Number of noise layers (more = more detail/complexity)")
        end

        -- Noise Persistence slider
        do
            imgui.BeginGroup(globals.ctx)
            local persKey = trackingKey .. "_noisePersistence"
            local rv, newPers = globals.SliderEnhanced.SliderDouble({
                id = "##NoisePersistence",
                value = dataObj.noisePersistence,
                min = 0.1,
                max = 1.0,
                defaultValue = globals.Constants.DEFAULTS.NOISE_PERSISTENCE,
                format = "%.2f",
                width = controlWidth
            })

            if imgui.IsItemActive(globals.ctx) and not globals.autoRegenTracking[persKey] then
                globals.autoRegenTracking[persKey] = dataObj.noisePersistence
            end

            if rv then callbacks.setNoisePersistence(newPers) end

            if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and globals.autoRegenTracking[persKey] then
                checkAutoRegen("noisePersistence", persKey, globals.autoRegenTracking[persKey], dataObj.noisePersistence)
                globals.autoRegenTracking[persKey] = nil
            end

            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Persistence")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("How much each octave contributes (0.5 = balanced)")
        end

        -- Noise Lacunarity slider
        do
            imgui.BeginGroup(globals.ctx)
            local lacKey = trackingKey .. "_noiseLacunarity"
            local rv, newLac = globals.SliderEnhanced.SliderDouble({
                id = "##NoiseLacunarity",
                value = dataObj.noiseLacunarity,
                min = 1.5,
                max = 4.0,
                defaultValue = globals.Constants.DEFAULTS.NOISE_LACUNARITY,
                format = "%.2f",
                width = controlWidth
            })

            if imgui.IsItemActive(globals.ctx) and not globals.autoRegenTracking[lacKey] then
                globals.autoRegenTracking[lacKey] = dataObj.noiseLacunarity
            end

            if rv then callbacks.setNoiseLacunarity(newLac) end

            if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and globals.autoRegenTracking[lacKey] then
                checkAutoRegen("noiseLacunarity", lacKey, globals.autoRegenTracking[lacKey], dataObj.noiseLacunarity)
                globals.autoRegenTracking[lacKey] = nil
            end

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

    -- Fade in/out controls are commented out but can be enabled if needed
end

-- Display trigger and randomization settings for a group or container
function UI.displayTriggerSettings(obj, objId, width, isGroup, groupIndex, containerIndex)
    local titlePrefix = isGroup and "Default " or ""
    local inheritText = isGroup and "These settings will be inherited by containers unless overridden" or ""

    -- Initialize auto-regen tracking if not exists
    if not globals.autoRegenTracking then
        globals.autoRegenTracking = {}
    end

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
    UI.drawTriggerSettingsSection(
        obj,
        {
            setIntervalMode = function(v) obj.intervalMode = v; obj.needsRegeneration = true end,
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
            setNoiseFrequency = function(v) obj.noiseFrequency = v; obj.needsRegeneration = true end,
            setNoiseAmplitude = function(v) obj.noiseAmplitude = v; obj.needsRegeneration = true end,
            setNoiseOctaves = function(v) obj.noiseOctaves = v; obj.needsRegeneration = true end,
            setNoisePersistence = function(v) obj.noisePersistence = v; obj.needsRegeneration = true end,
            setNoiseLacunarity = function(v) obj.noiseLacunarity = v; obj.needsRegeneration = true end,
            setNoiseDensity = function(v) obj.noiseDensity = v; obj.needsRegeneration = true end,
            setNoiseThreshold = function(v) obj.noiseThreshold = v; obj.needsRegeneration = true end,
        },
        width,
        titlePrefix,
        checkAutoRegen  -- Pass the auto-regen callback
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
    if not obj.pitchMode then obj.pitchMode = Constants.PITCH_MODES.PITCH end
    local pitchModeLabel = obj.pitchMode == Constants.PITCH_MODES.STRETCH and "Stretch (semitones)" or "Pitch (semitones)"

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
        obj.pitchMode = (obj.pitchMode == Constants.PITCH_MODES.PITCH) and Constants.PITCH_MODES.STRETCH or Constants.PITCH_MODES.PITCH
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
    UI.drawFadeSettingsSection(obj, objId, width, titlePrefix, groupIndex, containerIndex)
end

-- Function to draw fade settings controls
function UI.drawFadeSettingsSection(obj, objId, width, titlePrefix, groupIndex, containerIndex)
    local Constants = require("DM_Ambiance_Constants")
    
    -- Ensure all fade properties are properly initialized with defaults
    -- Only initialize if nil (not if false) to allow unchecking
    if obj.fadeInEnabled == nil then
        obj.fadeInEnabled = Constants.DEFAULTS.FADE_IN_ENABLED
    end
    if obj.fadeOutEnabled == nil then
        obj.fadeOutEnabled = Constants.DEFAULTS.FADE_OUT_ENABLED
    end
    obj.fadeInShape = obj.fadeInShape or Constants.DEFAULTS.FADE_IN_SHAPE
    obj.fadeOutShape = obj.fadeOutShape or Constants.DEFAULTS.FADE_OUT_SHAPE
    obj.fadeInCurve = obj.fadeInCurve or Constants.DEFAULTS.FADE_IN_CURVE
    obj.fadeOutCurve = obj.fadeOutCurve or Constants.DEFAULTS.FADE_OUT_CURVE
    
    -- Section separator and title
    imgui.Separator(globals.ctx)
    imgui.BeginGroup(globals.ctx)
    imgui.Text(globals.ctx, titlePrefix .. "Fade Settings")
    
    -- Link mode button for fades
    imgui.SameLine(globals.ctx)
    -- Ensure link mode is initialized
    if not obj.fadeLinkMode then obj.fadeLinkMode = "link" end
    if globals.Icons.createLinkModeButton(globals.ctx, "fadeLink" .. objId, obj.fadeLinkMode, "Fade link mode: " .. obj.fadeLinkMode) then
        obj.fadeLinkMode = cycleFadeLinkMode(obj.fadeLinkMode)
        -- Capture AFTER mode change
        if globals.History then
            globals.History.captureState("Change fade link mode")
        end
    end
    imgui.EndGroup(globals.ctx)
    
    -- Layout parameters for dynamic width (matching other sections)
    local checkboxWidth = 20
    local labelWidth = 75       -- "Fade In:" / "Fade Out:"
    local unitButtonWidth = 45  -- "sec" / "%"
    local spacing = 4

    -- Calculate available space for sliders
    local totalControlWidth = width - checkboxWidth - labelWidth - 10

    -- Allocate space for duration slider, shape dropdown, and curve slider
    local shapeDropdownWidth = 120
    local curveSliderWidth = 80
    local shapeLabelWidth = 50   -- "Shape:"
    local curveLabelWidth = 50   -- "Curve:"

    -- Duration slider gets remaining space
    local durationSliderWidth = totalControlWidth - unitButtonWidth - shapeDropdownWidth - curveSliderWidth - shapeLabelWidth - curveLabelWidth - (spacing * 6)
    
    -- Helper function to draw fade controls with column-based alignment
    local function drawFadeControls(fadeType, enabled, usePercentage, duration, shape, curve)
        local suffix = fadeType .. objId
        local isIn = fadeType == "In"
        
        imgui.BeginGroup(globals.ctx)

        -- Checkbox
        local rv, newEnabled = globals.UndoWrappers.Checkbox(globals.ctx, "##Enable" .. suffix, enabled or false)
        if rv then
            if isIn then obj.fadeInEnabled = newEnabled
            else obj.fadeOutEnabled = newEnabled end
            -- Queue fade update to avoid ImGui conflicts
            local modifiedFade = isIn and "fadeIn" or "fadeOut"
            if groupIndex and containerIndex then
                globals.Utils.queueFadeUpdate(groupIndex, containerIndex, modifiedFade)
            elseif groupIndex then
                globals.Utils.queueFadeUpdate(groupIndex, nil, modifiedFade)
            end
        end

        -- Label (with fixed width for alignment)
        imgui.SameLine(globals.ctx)
        imgui.BeginGroup(globals.ctx)
        imgui.AlignTextToFramePadding(globals.ctx)
        imgui.Text(globals.ctx, "Fade " .. fadeType .. ":")
        imgui.SameLine(globals.ctx, labelWidth)  -- Force position after label
        imgui.Dummy(globals.ctx, 0, 0)  -- Invisible spacer to maintain width
        imgui.EndGroup(globals.ctx)

        -- Unit button
        imgui.SameLine(globals.ctx)
        imgui.BeginDisabled(globals.ctx, not enabled)
        local unitText = usePercentage and "%" or "sec"
        if imgui.Button(globals.ctx, unitText .. "##Unit" .. suffix, unitButtonWidth, 0) then
            if isIn then obj.fadeInUsePercentage = not obj.fadeInUsePercentage
            else obj.fadeOutUsePercentage = not obj.fadeOutUsePercentage end
            -- Queue fade update to avoid ImGui conflicts
            local modifiedFade = isIn and "fadeIn" or "fadeOut"
            if groupIndex and containerIndex then
                globals.Utils.queueFadeUpdate(groupIndex, containerIndex, modifiedFade)
            elseif groupIndex then
                globals.Utils.queueFadeUpdate(groupIndex, nil, modifiedFade)
            end
            -- Capture AFTER value change (simple buttons don't need deferred capture)
            if globals.History then
                globals.History.captureState("Toggle " .. (isIn and "fade in" or "fade out") .. " unit mode")
            end
        end

        -- Duration slider
        imgui.SameLine(globals.ctx)
        local maxVal = usePercentage and 100 or 10
        local format = usePercentage and "%.0f%%" or "%.2f"
        local defaultDuration = isIn and globals.Constants.DEFAULTS.FADE_IN_DURATION or globals.Constants.DEFAULTS.FADE_OUT_DURATION
        local rv, newDuration = globals.SliderEnhanced.SliderDouble({
            id = "##Duration" .. suffix,
            value = duration or 0.1,
            min = 0,
            max = maxVal,
            defaultValue = defaultDuration,
            format = format,
            width = durationSliderWidth
        })
        if rv then
            -- Apply link mode logic using LinkedSliders logic functions
            local effectiveMode = globals.LinkedSliders.checkKeyboardOverrides(obj.fadeLinkMode or "link")

            -- Build sliders config for link mode logic
            local fadeSliders = {
                {value = obj.fadeInDuration or 0.1},
                {value = obj.fadeOutDuration or 0.1}
            }
            local changedIndex = isIn and 1 or 2
            local newValues = {isIn and newDuration or obj.fadeInDuration, isIn and obj.fadeOutDuration or newDuration}

            -- Apply link mode logic
            local finalValues = globals.LinkedSliders.applyLinkModeLogic(fadeSliders, newValues, changedIndex, effectiveMode)

            -- Clamp to valid range
            finalValues[1] = math.max(0, math.min(maxVal, finalValues[1]))
            finalValues[2] = math.max(0, math.min(maxVal, finalValues[2]))

            -- Update both fade durations
            obj.fadeInDuration = finalValues[1]
            obj.fadeOutDuration = finalValues[2]

            -- Queue fade update to avoid ImGui conflicts
            local modifiedFade = isIn and "fadeIn" or "fadeOut"
            if groupIndex and containerIndex then
                globals.Utils.queueFadeUpdate(groupIndex, containerIndex, modifiedFade)
            elseif groupIndex then
                globals.Utils.queueFadeUpdate(groupIndex, nil, modifiedFade)
            end
        end

        -- Interactive Fade Widget (replaces shape dropdown and curve slider)
        imgui.SameLine(globals.ctx)
        -- For fade out, invert the curve value for display to match REAPER's behavior
        local displayCurve = (not isIn) and -(curve or 0.0) or (curve or 0.0)
        local shapeChanged, newShape, curveChanged, newCurve = globals.FadeWidget.FadeWidget({
            id = "##FadeWidget" .. suffix,
            fadeType = fadeType,
            shape = shape or 0,
            curve = displayCurve,
            size = 48
        })

        if shapeChanged then
            if isIn then obj.fadeInShape = newShape
            else obj.fadeOutShape = newShape end
            -- Queue fade update to avoid ImGui conflicts
            local modifiedFade = isIn and "fadeIn" or "fadeOut"
            if groupIndex and containerIndex then
                globals.Utils.queueFadeUpdate(groupIndex, containerIndex, modifiedFade)
            elseif groupIndex then
                globals.Utils.queueFadeUpdate(groupIndex, nil, modifiedFade)
            end
        end

        if curveChanged then
            -- For fade out, invert the curve value to match REAPER's behavior
            local finalCurve = (not isIn) and -newCurve or newCurve
            if isIn then obj.fadeInCurve = finalCurve
            else obj.fadeOutCurve = finalCurve end
            -- Queue fade update to avoid ImGui conflicts
            local modifiedFade = isIn and "fadeIn" or "fadeOut"
            if groupIndex and containerIndex then
                globals.Utils.queueFadeUpdate(groupIndex, containerIndex, modifiedFade)
            elseif groupIndex then
                globals.Utils.queueFadeUpdate(groupIndex, nil, modifiedFade)
            end
        end
        
        imgui.EndDisabled(globals.ctx)
        imgui.EndGroup(globals.ctx)
    end
    
    -- Draw Fade In controls
    drawFadeControls("In", 
        obj.fadeInEnabled, 
        obj.fadeInUsePercentage, 
        obj.fadeInDuration, 
        obj.fadeInShape, 
        obj.fadeInCurve)
    
    -- Draw Fade Out controls  
    drawFadeControls("Out",
        obj.fadeOutEnabled,
        obj.fadeOutUsePercentage,
        obj.fadeOutDuration,
        obj.fadeOutShape,
        obj.fadeOutCurve)
end

-- Check if a container is selected
local function isContainerSelected(groupIndex, containerIndex)
    return globals.selectedContainers[groupIndex .. "_" .. containerIndex] == true
end

-- Toggle the selection state of a container
local function toggleContainerSelection(groupIndex, containerIndex)
    local key = groupIndex .. "_" .. containerIndex
    local isShiftPressed = (globals.imgui.GetKeyMods(globals.ctx) & globals.imgui.Mod_Shift ~= 0)

    -- If Shift is pressed and an anchor exists, select a range
    if isShiftPressed and globals.shiftAnchorGroupIndex and globals.shiftAnchorContainerIndex then
        selectContainerRange(globals.shiftAnchorGroupIndex, globals.shiftAnchorContainerIndex, groupIndex, containerIndex)
    else
        -- Without Shift, clear previous selections unless Ctrl is pressed
        if not (globals.imgui.GetKeyMods(globals.ctx) & globals.imgui.Mod_Ctrl ~= 0) then
            clearContainerSelections()
        end

        -- Toggle the current container selection
        if globals.selectedContainers[key] then
            globals.selectedContainers[key] = nil
        else
            globals.selectedContainers[key] = true
        end

        -- Update anchor for future Shift selections
        globals.shiftAnchorGroupIndex = groupIndex
        globals.shiftAnchorContainerIndex = containerIndex
    end

    -- Update main selection and multi-select mode
    globals.selectedGroupIndex = groupIndex
    globals.selectedContainerIndex = containerIndex
    globals.inMultiSelectMode = UI_Groups.getSelectedContainersCount() > 1
end

-- Select a range of containers between two points (supports cross-group selection)
local function selectContainerRange(startGroupIndex, startContainerIndex, endGroupIndex, endContainerIndex)
    -- Clear selection if not in multi-select mode
    if not (globals.imgui.GetKeyMods(globals.ctx) & globals.imgui.Mod_Ctrl ~= 0) then
        clearContainerSelections()
    end

    -- Range selection within the same group
    if startGroupIndex == endGroupIndex then
        local group = globals.groups[startGroupIndex]
        local startIdx = math.min(startContainerIndex, endContainerIndex)
        local endIdx = math.max(startContainerIndex, endContainerIndex)
        for i = startIdx, endIdx do
            if i <= #group.containers then
                globals.selectedContainers[startGroupIndex .. "_" .. i] = true
            end
        end
        return
    end

    -- Range selection across groups
    local startGroup = math.min(startGroupIndex, endGroupIndex)
    local endGroup = math.max(startGroupIndex, endGroupIndex)
    local firstContainerIdx, lastContainerIdx
    if startGroupIndex < endGroupIndex then
        firstContainerIdx, lastContainerIdx = startContainerIndex, endContainerIndex
    else
        firstContainerIdx, lastContainerIdx = endContainerIndex, startContainerIndex
    end

    for t = startGroup, endGroup do
        if globals.groups[t] then
            if t == startGroup then
                for c = firstContainerIdx, #globals.groups[t].containers do
                    globals.selectedContainers[t .. "_" .. c] = true
                end
            elseif t == endGroup then
                for c = 1, lastContainerIdx do
                    globals.selectedContainers[t .. "_" .. c] = true
                end
            else
                for c = 1, #globals.groups[t].containers do
                    globals.selectedContainers[t .. "_" .. c] = true
                end
            end
        end
    end

    globals.inMultiSelectMode = UI_Groups.getSelectedContainersCount() > 1
end

-- Draw the left panel with the list of groups and containers
local function drawLeftPanel(width)
    local availHeight = globals.imgui.GetWindowHeight(globals.ctx)
    if availHeight < 100 then -- Minimum height check
        globals.imgui.TextColored(globals.ctx, 0xFF0000FF, "Window too small")
        return
    end
    UI_Groups.drawGroupsPanel(width, isContainerSelected, toggleContainerSelection, clearContainerSelections, selectContainerRange)
end

-- Draw the right panel with details for the selected container or group
local function drawRightPanel(width)
    if globals.selectedContainers == {} then
        return
    end

    if globals.inMultiSelectMode then
        UI_MultiSelection.drawMultiSelectionPanel(width)
        return
    end

    if globals.selectedGroupIndex and globals.selectedContainerIndex then
        UI_Container.displayContainerSettings(globals.selectedGroupIndex, globals.selectedContainerIndex, width)
    elseif globals.selectedGroupIndex then
        UI_Group.displayGroupSettings(globals.selectedGroupIndex, width)
    else
        globals.imgui.TextColored(globals.ctx, 0xFFAA00FF, "Select a group or container to view and edit its settings.")
    end
end

-- Handle popups and force close if a popup is stuck for too long
local function handlePopups()
    for name, popup in pairs(globals.activePopups or {}) do
        if popup.active and reaper.time_precise() - popup.timeOpened > 5 then
            globals.imgui.CloseCurrentPopup(globals.ctx)
            globals.activePopups[name] = nil
        end
    end
end

local function detectAndFixImGuiImbalance()
    -- Get ImGui context state (if accessible)
    -- This is a safety net to prevent crashes
    local success = pcall(function()
        -- Try to detect if we're in an inconsistent state
        -- by checking if any operation causes an error
        local testVar = globals.imgui.GetWindowWidth(globals.ctx)
    end)
    
    if not success then
        -- If there's an issue, reset some flags that might help
        globals.showMediaDirWarning = false
        globals.activePopups = {}
        
        -- Force close any open popups
        pcall(function()
            globals.imgui.CloseCurrentPopup(globals.ctx)
        end)
    end
end

-- Get the left panel width (with resizing support)
local function getLeftPanelWidth(windowWidth)
    local Constants = require("DM_Ambiance_Constants")

    -- Load saved width from settings or use default
    if globals.leftPanelWidth == nil then
        local savedWidth = globals.Settings.getSetting("leftPanelWidth")
        if savedWidth then
            globals.leftPanelWidth = savedWidth
        else
            globals.leftPanelWidth = windowWidth * Constants.UI.LEFT_PANEL_DEFAULT_WIDTH
        end
    end

    -- Ensure minimum width and adjust for window size
    local minWidth = Constants.UI.MIN_LEFT_PANEL_WIDTH
    local maxWidth = windowWidth - 200  -- Leave at least 200px for right panel
    globals.leftPanelWidth = math.max(minWidth, math.min(globals.leftPanelWidth, maxWidth))

    return globals.leftPanelWidth
end

-- Draw noise preview visualization
-- @param dataObj table: Container or group object with noise parameters
-- @param width number: Width of preview area
-- @param height number: Height of preview area
function UI.drawNoisePreview(dataObj, width, height)
    -- Ensure noise parameters exist (for backwards compatibility with old presets)
    local noiseSeed = dataObj.noiseSeed or math.random(1, 999999)
    local noiseFrequency = dataObj.noiseFrequency or 1.0
    local noiseAmplitude = dataObj.noiseAmplitude or 100.0
    local noiseOctaves = dataObj.noiseOctaves or 2
    local noisePersistence = dataObj.noisePersistence or 0.5
    local noiseLacunarity = dataObj.noiseLacunarity or 2.0
    local noiseDensity = dataObj.noiseDensity or 50.0
    local noiseThreshold = dataObj.noiseThreshold or 0.0

    local drawList = imgui.GetWindowDrawList(globals.ctx)
    local cursorX, cursorY = imgui.GetCursorScreenPos(globals.ctx)

    -- Background
    local bgColor = 0x202020FF
    imgui.DrawList_AddRectFilled(drawList, cursorX, cursorY, cursorX + width, cursorY + height, bgColor)

    -- Border
    local borderColor = 0x666666FF
    imgui.DrawList_AddRect(drawList, cursorX, cursorY, cursorX + width, cursorY + height, borderColor)

    -- Use time selection if available, otherwise use 10 seconds preview
    local startTime, endTime
    if globals.timeSelectionValid then
        startTime = globals.startTime
        endTime = globals.endTime
    else
        startTime = 0
        endTime = 60  -- 60 seconds preview
    end

    -- Generate noise curve data
    local sampleCount = math.floor(width)
    local curve = globals.Noise.generateCurve(
        startTime,
        endTime,
        sampleCount,
        noiseFrequency,
        noiseOctaves,
        noisePersistence,
        noiseLacunarity,
        noiseSeed
    )

    -- Calculate amplitude scaling based on noiseAmplitude parameter
    local amplitudeScale = noiseAmplitude / 100.0
    local density = noiseDensity / 100.0

    -- Draw the noise curve
    local prevX, prevY = nil, nil
    local thresholdNormalized = noiseThreshold / 100.0

    -- Use waveform color for consistency
    local waveformColor = globals.Settings.getSetting("waveformColor")

    for i, point in ipairs(curve) do
        -- Apply same formula as generation algorithm
        local rawValue = point.value  -- 0-1
        local centered = (rawValue - 0.5) * 2  -- -1 to 1
        -- Amplitude is relative to density
        local variation = centered * amplitudeScale * density
        local final = density + variation

        -- Clamp to 0-1
        final = math.max(0, math.min(1, final))

        -- Apply min density threshold - clamp the curve from below
        final = math.max(thresholdNormalized, final)

        -- Convert to screen coordinates
        local x = cursorX + (i - 1) * (width / (sampleCount - 1))
        local y = cursorY + height - (final * height)

        if prevX and prevY then
            -- Draw line segment using waveform color
            imgui.DrawList_AddLine(drawList, prevX, prevY, x, y, waveformColor, 1.5)
        end

        prevX, prevY = x, y
    end

    -- Draw zero line (for reference)
    local zeroY = cursorY + height
    local zeroColor = 0x888888AA
    imgui.DrawList_AddLine(drawList, cursorX, zeroY, cursorX + width, zeroY, zeroColor, 1.0)

    -- Calculate and draw item placement positions
    -- This simulates the same algorithm used in DM_Ambiance_Generation.lua (lines 3707-3889)
    local noiseGen = globals.Constants.NOISE_GENERATION
    local avgItemLength = 3.0  -- Estimate for preview (can be improved later if we pass actual items)
    local itemPositions = {}

    -- Helper function to get curve value at a specific time (same as generation)
    local function getCurveValue(time)
        local noiseValue = globals.Noise.getValueAtTime(
            time,
            startTime,
            endTime,
            noiseFrequency,
            noiseOctaves,
            noisePersistence,
            noiseLacunarity,
            noiseSeed
        )

        local normalizedDensity = noiseDensity / 100.0
        local normalizedNoiseValue = (noiseValue - 0.5) * 2
        local densityVariation = normalizedNoiseValue * amplitudeScale * normalizedDensity
        local placementProbability = normalizedDensity + densityVariation
        return math.max(0, math.min(1, placementProbability))
    end

    -- Simulate item placement algorithm
    local currentTime = startTime
    local maxPositions = 500  -- Limit to prevent performance issues
    local positionCount = 0

    while currentTime < endTime and positionCount < maxPositions do
        local curveValue = getCurveValue(currentTime)

        -- Skip ahead in silent zones (below threshold)
        local minDensityThreshold = thresholdNormalized
        if curveValue < minDensityThreshold then
            currentTime = currentTime + noiseGen.SKIP_INTERVAL
            goto continue_preview
        end

        -- Calculate interval based on curve value
        -- High curve = short interval (high density), Low curve = long interval (low density)
        local minInterval = avgItemLength * noiseGen.MIN_INTERVAL_MULTIPLIER
        local maxInterval = noiseGen.MAX_INTERVAL_SECONDS
        local interval = minInterval + (maxInterval - minInterval) * (1.0 - curveValue)

        -- Store this position
        table.insert(itemPositions, currentTime)
        positionCount = positionCount + 1

        -- Advance time by calculated interval
        currentTime = currentTime + interval

        ::continue_preview::
    end

    -- Draw item position markers
    -- Use waveform color with brightness boost for better visibility
    local baseColor = waveformColor or 0x00CCA0FF

    -- Extract RGBA components (ImGui format: 0xAABBGGRR)
    local r = (baseColor & 0x000000FF)
    local g = (baseColor & 0x0000FF00) >> 8
    local b = (baseColor & 0x00FF0000) >> 16
    local a = (baseColor & 0xFF000000) >> 24

    -- Boost brightness by 30% (clamped to 255)
    local brightnessFactor = 1.3
    r = math.min(255, math.floor(r * brightnessFactor))
    g = math.min(255, math.floor(g * brightnessFactor))
    b = math.min(255, math.floor(b * brightnessFactor))

    -- Reconstruct color
    local markerColor = r | (g << 8) | (b << 16) | (a << 24)

    local markerRadius = 3.0
    local duration = endTime - startTime

    for _, itemTime in ipairs(itemPositions) do
        -- Convert time to screen X coordinate
        local normalizedTime = (itemTime - startTime) / duration
        local markerX = cursorX + normalizedTime * width
        local markerY = cursorY + height - 5  -- Near bottom of preview

        -- Draw circle marker
        imgui.DrawList_AddCircleFilled(drawList, markerX, markerY, markerRadius, markerColor)
    end

    -- Draw time markers
    local duration = endTime - startTime
    local textColor = 0xAAAAAAFF

    -- Start time
    local startText = string.format("%.1fs", startTime)
    imgui.DrawList_AddText(drawList, cursorX + 5, cursorY + height + 5, textColor, startText)

    -- Middle time
    local midTime = startTime + duration / 2
    local midText = string.format("%.1fs", midTime)
    imgui.DrawList_AddText(drawList, cursorX + width / 2 - 15, cursorY + height + 5, textColor, midText)

    -- End time
    local endText = string.format("%.1fs", endTime)
    imgui.DrawList_AddText(drawList, cursorX + width - 30, cursorY + height + 5, textColor, endText)

    -- Reserve space for the preview + text
    imgui.Dummy(globals.ctx, width, height + 20)
end

-- Main window rendering function
function UI.ShowMainWindow(open)
    local windowFlags = imgui.WindowFlags_None

    -- Lock window movement during waveform manipulations or when about to interact
    if globals.Waveform and (globals.Waveform.isWaveformBeingManipulated() or
                            globals.Waveform.isMouseAboutToInteractWithWaveform()) then
        windowFlags = windowFlags | imgui.WindowFlags_NoMove
    end

    local visible, open = globals.imgui.Begin(globals.ctx, 'Ambiance Creator', open, windowFlags)

    -- CRITICAL: Only call End() if Begin() returned true (visible)
    if visible then

        -- Handle Undo/Redo keyboard shortcuts
        local ctrlPressed = (globals.imgui.GetKeyMods(globals.ctx) & globals.imgui.Mod_Ctrl ~= 0)
        local shiftPressed = (globals.imgui.GetKeyMods(globals.ctx) & globals.imgui.Mod_Shift ~= 0)

        -- Ctrl+Z: Undo (works everywhere)
        if ctrlPressed and not shiftPressed and globals.imgui.IsKeyPressed(globals.ctx, globals.imgui.Key_Z) then
            globals.History.undo()
        end

        -- Ctrl+Y or Ctrl+Shift+Z: Redo (works everywhere)
        if (ctrlPressed and globals.imgui.IsKeyPressed(globals.ctx, globals.imgui.Key_Y)) or
           (ctrlPressed and shiftPressed and globals.imgui.IsKeyPressed(globals.ctx, globals.imgui.Key_Z)) then
            globals.History.redo()
        end

        -- Handle keyboard input for Delete key
        if globals.imgui.IsKeyPressed(globals.ctx, globals.imgui.Key_Delete) then
            -- Capture state before deletion
            globals.History.captureState("Delete items")

            -- Check if we're in multi-selection mode
            if globals.inMultiSelectMode and next(globals.selectedContainers) then
                -- Build list of containers to delete (sorted in reverse to maintain indices)
                local toDelete = {}
                for key, _ in pairs(globals.selectedContainers) do
                    local groupIdx, containerIdx = key:match("(%d+)_(%d+)")
                    if groupIdx and containerIdx then
                        table.insert(toDelete, {
                            groupIndex = tonumber(groupIdx),
                            containerIndex = tonumber(containerIdx)
                        })
                    end
                end

                -- Sort in reverse order (highest indices first)
                table.sort(toDelete, function(a, b)
                    if a.groupIndex == b.groupIndex then
                        return a.containerIndex > b.containerIndex
                    end
                    return a.groupIndex > b.groupIndex
                end)

                -- Delete containers
                for _, item in ipairs(toDelete) do
                    local group = globals.groups[item.groupIndex]
                    if group and group.containers[item.containerIndex] then
                        table.remove(group.containers, item.containerIndex)
                    end
                end

                -- Clear selections
                globals.selectedContainers = {}
                globals.inMultiSelectMode = false
                globals.selectedContainerIndex = nil

            -- Check if a single container is selected
            elseif globals.selectedGroupIndex and globals.selectedContainerIndex then
                local group = globals.groups[globals.selectedGroupIndex]
                if group and group.containers[globals.selectedContainerIndex] then
                    -- Store current indices
                    local containerIdx = globals.selectedContainerIndex

                    -- Remove the container
                    table.remove(group.containers, containerIdx)

                    -- Clear selection
                    globals.selectedContainerIndex = nil

                    -- Clear from multi-selection if present
                    local selectionKey = globals.selectedGroupIndex .. "_" .. containerIdx
                    if globals.selectedContainers[selectionKey] then
                        globals.selectedContainers[selectionKey] = nil
                    end

                    -- Update selection indices for containers after the deleted one
                    for k = containerIdx + 1, #group.containers + 1 do
                        local oldKey = globals.selectedGroupIndex .. "_" .. k
                        local newKey = globals.selectedGroupIndex .. "_" .. (k-1)
                        if globals.selectedContainers[oldKey] then
                            globals.selectedContainers[newKey] = true
                            globals.selectedContainers[oldKey] = nil
                        end
                    end
                end
            -- Check if only a group is selected (no container selected)
            elseif globals.selectedGroupIndex and not globals.selectedContainerIndex then
                local groupIdx = globals.selectedGroupIndex

                -- Remove the group and all its containers
                table.remove(globals.groups, groupIdx)

                -- Clear selection
                globals.selectedGroupIndex = nil

                -- Clear any selected containers from this group
                for key in pairs(globals.selectedContainers) do
                    local t, c = key:match("(%d+)_(%d+)")
                    if tonumber(t) == groupIdx then
                        globals.selectedContainers[key] = nil
                    end
                    -- Update indices for groups after the deleted one
                    if tonumber(t) > groupIdx then
                        local newKey = (tonumber(t) - 1) .. "_" .. c
                        globals.selectedContainers[newKey] = globals.selectedContainers[key]
                        globals.selectedContainers[key] = nil
                    end
                end

                -- Update selected group index if needed
                if globals.selectedGroupIndex and globals.selectedGroupIndex > groupIdx then
                    globals.selectedGroupIndex = globals.selectedGroupIndex - 1
                end
            end
        end

        -- Top section: preset controls and generation button
        UI_Preset.drawPresetControls()

        -- Settings button positioned at the far right
        local settingsButtonWidth = 14  -- Icon size
        local windowWidth = globals.imgui.GetWindowWidth(globals.ctx)
        local cursorX = globals.imgui.GetCursorPosX(globals.ctx)
        local spacing = globals.imgui.GetStyleVar(globals.ctx, globals.imgui.StyleVar_ItemSpacing)
        globals.imgui.SameLine(globals.ctx)
        globals.imgui.SetCursorPosX(globals.ctx, windowWidth - settingsButtonWidth - spacing - 10)
        if globals.Icons.createSettingsButton(globals.ctx, "main", "Open settings") then
            globals.showSettingsWindow = true
        end

        if globals.Utils.checkTimeSelection() then
            UI_Generation.drawMainGenerationButton()
            globals.imgui.SameLine(globals.ctx)
            UI_Generation.drawKeepExistingTracksButton()  -- Changed from drawOverrideExistingTracksButton
        else
            UI_Generation.drawTimeSelectionInfo()
        end

        globals.imgui.Separator(globals.ctx)

        -- Two-panel layout dimensions with resizable splitter
        local windowWidth = globals.imgui.GetWindowWidth(globals.ctx)
        local Constants = require("DM_Ambiance_Constants")

        -- Get the left panel width
        local leftPanelWidth = getLeftPanelWidth(windowWidth)

        -- Left panel: groups and containers
        local leftVisible = globals.imgui.BeginChild(globals.ctx, "LeftPanel", leftPanelWidth, 0, imgui.WindowFlags_None)
        if leftVisible then
            drawLeftPanel(leftPanelWidth)
            globals.imgui.EndChild(globals.ctx)
        end

        -- Splitter between panels
        globals.imgui.SameLine(globals.ctx)

        -- Style the splitter to look like a separator
        local separatorColor = globals.imgui.GetStyleColor(globals.ctx, globals.imgui.Col_Separator)
        globals.imgui.PushStyleColor(globals.ctx, globals.imgui.Col_Button, separatorColor)
        globals.imgui.PushStyleColor(globals.ctx, globals.imgui.Col_ButtonHovered, separatorColor)
        globals.imgui.PushStyleColor(globals.ctx, globals.imgui.Col_ButtonActive, separatorColor)

        globals.imgui.Button(globals.ctx, "##vsplitter", 2, -1)

        globals.imgui.PopStyleColor(globals.ctx, 3)

        -- Check if splitter is being dragged
        if globals.imgui.IsItemActive(globals.ctx) then
            local deltaX, deltaY = globals.imgui.GetMouseDragDelta(globals.ctx, 0)
            if deltaX ~= 0 then
                globals.leftPanelWidth = globals.leftPanelWidth + deltaX
                globals.imgui.ResetMouseDragDelta(globals.ctx, 0)

                -- Clamp width
                local minWidth = Constants.UI.MIN_LEFT_PANEL_WIDTH
                local maxWidth = windowWidth - 200
                globals.leftPanelWidth = math.max(minWidth, math.min(globals.leftPanelWidth, maxWidth))
            end
        end

        -- Save when drag is released
        if globals.imgui.IsItemDeactivated(globals.ctx) and globals.leftPanelWidth then
            globals.Settings.setSetting("leftPanelWidth", globals.leftPanelWidth)
            globals.Settings.saveSettings()  -- Write to file
        end

        -- Change cursor on hover
        if globals.imgui.IsItemHovered(globals.ctx) then
            globals.imgui.SetMouseCursor(globals.ctx, globals.imgui.MouseCursor_ResizeEW)
        end

        -- Right panel: container or group details
        globals.imgui.SameLine(globals.ctx)
        local rightMargin = 15  -- Right margin for balanced UI
        local rightPanelWidth = windowWidth - leftPanelWidth - Constants.UI.SPLITTER_WIDTH - 20 - rightMargin
        local rightVisible = globals.imgui.BeginChild(globals.ctx, "RightPanel", rightPanelWidth, 0, imgui.WindowFlags_None)
        if rightVisible then
            drawRightPanel(rightPanelWidth)
            globals.imgui.EndChild(globals.ctx)
        end

        -- CRITICAL: Only call End() if Begin() returned true
        globals.imgui.End(globals.ctx)
    end

    -- Handle settings window with the same pattern
    if globals.showSettingsWindow then
        globals.showSettingsWindow = globals.Settings.showSettingsWindow(true)
    end

    -- Show the media directory warning popup if needed
    if globals.showMediaDirWarning then
        Utils.showDirectoryWarningPopup()
    end

    -- Handle routing matrix popup
    if globals.routingPopupItemIndex then
        UI_Container.showRoutingMatrixPopup(globals.routingPopupGroupIndex, globals.routingPopupContainerIndex, "routing")
    end

    -- Handle other popups
    handlePopups()

    -- Process any queued fade updates after ImGui frame is complete
    globals.Utils.processQueuedFadeUpdates()

    -- Process any queued randomization updates after ImGui frame is complete
    globals.Utils.processQueuedRandomizationUpdates()

    return open
end



return UI
