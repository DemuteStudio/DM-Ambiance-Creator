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
end

-- Push custom style variables for UI
function UI.PushStyle()
    local ctx = globals.ctx
    local imgui = globals.imgui
    local settings = globals.Settings
    local utils = globals.Utils
    
    -- Item Spacing
    local itemSpacing = settings.getSetting("itemSpacing")
    imgui.PushStyleVar(ctx, imgui.StyleVar_ItemSpacing, itemSpacing, itemSpacing)
    


    -- Round Style for buttons and frames
    local rounding = settings.getSetting("uiRounding")
    
    -- Apply the user-defined rounding value
    imgui.PushStyleVar(ctx, imgui.StyleVar_DisabledAlpha, 0.68)
    imgui.PushStyleVar(ctx, imgui.StyleVar_FrameRounding, rounding)
    imgui.PushStyleVar(ctx, imgui.StyleVar_GrabRounding, rounding)
    
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
    
    -- Increase the number for PushStyleColor
    imgui.PopStyleColor(ctx, 20)
    
    -- Increase the number for PushStyleVar
    imgui.PopStyleVar(ctx, 4)
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

-- Utility function to cycle through fade link modes (only unlink and link)
local function cycleFadeLinkMode(currentMode)
    if currentMode == "unlink" then
        return "link"
    else -- currentMode == "link"
        return "unlink"
    end
end

-- Apply linked slider changes
local function applyLinkedSliderChange(obj, paramType, newMin, newMax, linkMode)
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

-- Apply linked fade changes
local function applyLinkedFadeChange(obj, fadeType, newValue, linkMode)
    if linkMode == "unlink" then
        -- Independent fades - keep the other fade unchanged
        if fadeType == "In" then
            -- Modifying fadeIn, keep fadeOut unchanged
            return newValue, obj.fadeOutDuration
        else
            -- Modifying fadeOut, keep fadeIn unchanged
            return obj.fadeInDuration, newValue
        end
    elseif linkMode == "link" then
        -- Linked fades - maintain same value for both
        return newValue, newValue
    end

    -- Fallback to unlink behavior
    if fadeType == "In" then
        return newValue, obj.fadeOutDuration
    else
        return obj.fadeInDuration, newValue
    end
end

-- Draw the trigger settings section (shared by groups and containers)
-- dataObj must expose: intervalMode, triggerRate, triggerDrift, fadeIn, fadeOut
-- callbacks must provide setters for each parameter
function UI.drawTriggerSettingsSection(dataObj, callbacks, width, titlePrefix, autoRegenCallback)
    -- Section separator and title
    imgui.Separator(globals.ctx)
    imgui.Text(globals.ctx, titlePrefix .. "Trigger Settings")

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
    local controlHeight = 20
    local controlWidth = width * 0.55
    local labelWidth = width * 0.35
    local padding = 5
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

    -- Interval mode selection (Combo box)
    do
        imgui.BeginGroup(globals.ctx)
        imgui.PushItemWidth(globals.ctx, controlWidth)
        local intervalModes = "Absolute\0Relative\0Coverage\0Chunk\0Noise\0"
        local rv, newIntervalMode = globals.UndoWrappers.Combo(globals.ctx, "##IntervalMode", dataObj.intervalMode, intervalModes)
        if rv then callbacks.setIntervalMode(newIntervalMode) end
        imgui.EndGroup(globals.ctx)

        imgui.SameLine(globals.ctx, controlWidth + padding)
        imgui.Text(globals.ctx, "Interval Mode")
        imgui.SameLine(globals.ctx)
        globals.Utils.HelpMarker(
            "Absolute: Fixed interval in seconds\n" ..
            "Relative: Interval as percentage of time selection\n" ..
            "Coverage: Percentage of time selection to be filled\n" ..
            "Chunk: Create structured sound/silence periods\n" ..
            "Noise: Place items based on Perlin noise function"
        )
    end

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

        imgui.BeginGroup(globals.ctx)
        imgui.PushItemWidth(globals.ctx, controlWidth)

        local triggerRateKey = trackingKey .. "_triggerRate"
        local rv, newRate = globals.UndoWrappers.SliderDouble(globals.ctx, "##TriggerRate", dataObj.triggerRate, rateMin, rateMax, "%.1f")

        -- Store initial value when starting to drag
        if imgui.IsItemActive(globals.ctx) and not globals.autoRegenTracking[triggerRateKey] then
            globals.autoRegenTracking[triggerRateKey] = dataObj.triggerRate
        end

        if rv then callbacks.setTriggerRate(newRate) end

        -- Check for auto-regen on release
        if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and globals.autoRegenTracking[triggerRateKey] then
            checkAutoRegen("triggerRate", globals.autoRegenTracking[triggerRateKey], dataObj.triggerRate)
            globals.autoRegenTracking[triggerRateKey] = nil
        end

        imgui.EndGroup(globals.ctx)

        imgui.SameLine(globals.ctx, controlWidth + padding)
        imgui.Text(globals.ctx, rateLabel)

        -- Compact random variation control on same line
        imgui.SameLine(globals.ctx)
        imgui.PushItemWidth(globals.ctx, 60)

        local triggerDriftKey = trackingKey .. "_triggerDrift"
        local rvDrift, newDrift = globals.UndoWrappers.DragInt(globals.ctx, "##TriggerDrift", dataObj.triggerDrift, 0.5, 0, 100, "%d%%")

        -- Store initial value when starting to drag
        if imgui.IsItemActive(globals.ctx) and autoRegenCallback and not globals.autoRegenTracking[triggerDriftKey] then
            globals.autoRegenTracking[triggerDriftKey] = dataObj.triggerDrift
        end

        if rvDrift then callbacks.setTriggerDrift(newDrift) end

        -- Check for auto-regen on release
        if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and autoRegenCallback and globals.autoRegenTracking[triggerDriftKey] then
            checkAutoRegen("triggerDrift", triggerDriftKey, globals.autoRegenTracking[triggerDriftKey], dataObj.triggerDrift)
            globals.autoRegenTracking[triggerDriftKey] = nil
        end

        imgui.PopItemWidth(globals.ctx)
        imgui.SameLine(globals.ctx)
        -- Show "Drift" for Coverage mode, "Var" for other modes
        local driftLabel = (dataObj.intervalMode == 2) and "Drift" or "Var"
        imgui.Text(globals.ctx, driftLabel)
    end

    -- Chunk mode specific controls
    if dataObj.intervalMode == 3 then
        -- Chunk Duration slider with variation knob
        do
            imgui.BeginGroup(globals.ctx)
            imgui.PushItemWidth(globals.ctx, controlWidth)

            local chunkDurationKey = trackingKey .. "_chunkDuration"
            local rv, newDuration = globals.UndoWrappers.SliderDouble(globals.ctx, "##ChunkDuration", dataObj.chunkDuration, 0.5, 60.0, "%.1f sec")

            -- Store initial value when starting to drag
            if imgui.IsItemActive(globals.ctx) and not globals.autoRegenTracking[chunkDurationKey] then
                globals.autoRegenTracking[chunkDurationKey] = dataObj.chunkDuration
            end

            if rv then callbacks.setChunkDuration(newDuration) end

            -- Check for auto-regen on release
            if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and globals.autoRegenTracking[chunkDurationKey] then
                checkAutoRegen("chunkDuration", globals.autoRegenTracking[chunkDurationKey], dataObj.chunkDuration)
                globals.autoRegenTracking[chunkDurationKey] = nil
            end

            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Chunk Duration")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("Duration of active sound periods in seconds")
            
            -- Compact variation control on same line
            imgui.SameLine(globals.ctx)
            imgui.PushItemWidth(globals.ctx, 60)

            local chunkDurationVarKey = trackingKey .. "_chunkDurationVar"
            local rv2, newDurationVar = globals.UndoWrappers.DragInt(globals.ctx, "##ChunkDurationVar", dataObj.chunkDurationVariation, 0.5, 0, 100, "%d%%")

            -- Store initial value when starting to drag
            if imgui.IsItemActive(globals.ctx) and not globals.autoRegenTracking[chunkDurationVarKey] then
                globals.autoRegenTracking[chunkDurationVarKey] = dataObj.chunkDurationVariation
            end

            if rv2 then callbacks.setChunkDurationVariation(newDurationVar) end

            -- Check for auto-regen on release
            if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and globals.autoRegenTracking[chunkDurationVarKey] then
                checkAutoRegen("chunkDurationVar", chunkDurationVarKey, globals.autoRegenTracking[chunkDurationVarKey], dataObj.chunkDurationVariation)
                globals.autoRegenTracking[chunkDurationVarKey] = nil
            end

            imgui.PopItemWidth(globals.ctx)
            imgui.SameLine(globals.ctx)
            imgui.Text(globals.ctx, "Var")
        end

        -- Chunk Silence slider with variation knob
        do
            imgui.BeginGroup(globals.ctx)
            imgui.PushItemWidth(globals.ctx, controlWidth)

            local chunkSilenceKey = trackingKey .. "_chunkSilence"
            local rv, newSilence = globals.UndoWrappers.SliderDouble(globals.ctx, "##ChunkSilence", dataObj.chunkSilence, 0.0, 120.0, "%.1f sec")

            -- Store initial value when starting to drag
            if imgui.IsItemActive(globals.ctx) and not globals.autoRegenTracking[chunkSilenceKey] then
                globals.autoRegenTracking[chunkSilenceKey] = dataObj.chunkSilence
            end

            if rv then callbacks.setChunkSilence(newSilence) end

            -- Check for auto-regen on release
            if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and globals.autoRegenTracking[chunkSilenceKey] then
                checkAutoRegen("chunkSilence", globals.autoRegenTracking[chunkSilenceKey], dataObj.chunkSilence)
                globals.autoRegenTracking[chunkSilenceKey] = nil
            end

            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Silence Duration")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("Duration of silence periods between chunks in seconds")
            
            -- Compact variation control on same line
            imgui.SameLine(globals.ctx)
            imgui.PushItemWidth(globals.ctx, 60)

            local chunkSilenceVarKey = trackingKey .. "_chunkSilenceVar"
            local rv2, newSilenceVar = globals.UndoWrappers.DragInt(globals.ctx, "##ChunkSilenceVar", dataObj.chunkSilenceVariation, 0.5, 0, 100, "%d%%")

            -- Store initial value when starting to drag
            if imgui.IsItemActive(globals.ctx) and not globals.autoRegenTracking[chunkSilenceVarKey] then
                globals.autoRegenTracking[chunkSilenceVarKey] = dataObj.chunkSilenceVariation
            end

            if rv2 then callbacks.setChunkSilenceVariation(newSilenceVar) end

            -- Check for auto-regen on release
            if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and globals.autoRegenTracking[chunkSilenceVarKey] then
                checkAutoRegen("chunkSilenceVar", chunkSilenceVarKey, globals.autoRegenTracking[chunkSilenceVarKey], dataObj.chunkSilenceVariation)
                globals.autoRegenTracking[chunkSilenceVarKey] = nil
            end

            imgui.PopItemWidth(globals.ctx)
            imgui.SameLine(globals.ctx)
            imgui.Text(globals.ctx, "Var")
        end
    end

    -- Noise mode specific controls
    if dataObj.intervalMode == 4 then
        -- Ensure noise parameters exist (backwards compatibility with old presets)
        dataObj.noiseSeed = dataObj.noiseSeed or math.random(1, 999999)
        dataObj.noiseFrequency = dataObj.noiseFrequency or 1.0
        dataObj.noiseAmplitude = dataObj.noiseAmplitude or 100.0
        dataObj.noiseOctaves = dataObj.noiseOctaves or 2
        dataObj.noisePersistence = dataObj.noisePersistence or 0.5
        dataObj.noiseLacunarity = dataObj.noiseLacunarity or 2.0
        dataObj.noiseDensity = dataObj.noiseDensity or 50.0
        dataObj.noiseThreshold = dataObj.noiseThreshold or 0.0

        imgui.Spacing(globals.ctx)
        imgui.Separator(globals.ctx)
        imgui.Spacing(globals.ctx)

        -- Noise Density slider (main parameter)
        do
            imgui.BeginGroup(globals.ctx)
            imgui.PushItemWidth(globals.ctx, controlWidth)

            local densityKey = trackingKey .. "_noiseDensity"
            local rv, newDensity = globals.UndoWrappers.SliderDouble(globals.ctx, "##NoiseDensity", dataObj.noiseDensity, 1.0, 100.0, "%.1f%%")

            if imgui.IsItemActive(globals.ctx) and not globals.autoRegenTracking[densityKey] then
                globals.autoRegenTracking[densityKey] = dataObj.noiseDensity
            end

            if rv then callbacks.setNoiseDensity(newDensity) end

            if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and globals.autoRegenTracking[densityKey] then
                checkAutoRegen("noiseDensity", densityKey, globals.autoRegenTracking[densityKey], dataObj.noiseDensity)
                globals.autoRegenTracking[densityKey] = nil
            end

            imgui.PopItemWidth(globals.ctx)
            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Density")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("Average probability of item placement (0-100%)")
        end

        -- Noise Frequency slider
        do
            imgui.BeginGroup(globals.ctx)
            imgui.PushItemWidth(globals.ctx, controlWidth)

            local freqKey = trackingKey .. "_noiseFrequency"
            local rv, newFreq = globals.UndoWrappers.SliderDouble(globals.ctx, "##NoiseFrequency", dataObj.noiseFrequency, 0.1, 10.0, "%.2f")

            if imgui.IsItemActive(globals.ctx) and not globals.autoRegenTracking[freqKey] then
                globals.autoRegenTracking[freqKey] = dataObj.noiseFrequency
            end

            if rv then callbacks.setNoiseFrequency(newFreq) end

            if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and globals.autoRegenTracking[freqKey] then
                checkAutoRegen("noiseFrequency", freqKey, globals.autoRegenTracking[freqKey], dataObj.noiseFrequency)
                globals.autoRegenTracking[freqKey] = nil
            end

            imgui.PopItemWidth(globals.ctx)
            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Frequency")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("Speed of noise variations (low = slow waves, high = rapid changes)")
        end

        -- Noise Amplitude slider
        do
            imgui.BeginGroup(globals.ctx)
            imgui.PushItemWidth(globals.ctx, controlWidth)

            local ampKey = trackingKey .. "_noiseAmplitude"
            local rv, newAmp = globals.UndoWrappers.SliderDouble(globals.ctx, "##NoiseAmplitude", dataObj.noiseAmplitude, 0.0, 100.0, "%.1f%%")

            if imgui.IsItemActive(globals.ctx) and not globals.autoRegenTracking[ampKey] then
                globals.autoRegenTracking[ampKey] = dataObj.noiseAmplitude
            end

            if rv then callbacks.setNoiseAmplitude(newAmp) end

            if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and globals.autoRegenTracking[ampKey] then
                checkAutoRegen("noiseAmplitude", ampKey, globals.autoRegenTracking[ampKey], dataObj.noiseAmplitude)
                globals.autoRegenTracking[ampKey] = nil
            end

            imgui.PopItemWidth(globals.ctx)
            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Amplitude")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("Intensity of density variation around average")
        end

        -- Noise Octaves slider
        do
            imgui.BeginGroup(globals.ctx)
            imgui.PushItemWidth(globals.ctx, controlWidth)

            local octKey = trackingKey .. "_noiseOctaves"
            local rv, newOct = globals.UndoWrappers.SliderInt(globals.ctx, "##NoiseOctaves", dataObj.noiseOctaves, 1, 6, "%d")

            if imgui.IsItemActive(globals.ctx) and not globals.autoRegenTracking[octKey] then
                globals.autoRegenTracking[octKey] = dataObj.noiseOctaves
            end

            if rv then callbacks.setNoiseOctaves(newOct) end

            if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and globals.autoRegenTracking[octKey] then
                checkAutoRegen("noiseOctaves", octKey, globals.autoRegenTracking[octKey], dataObj.noiseOctaves)
                globals.autoRegenTracking[octKey] = nil
            end

            imgui.PopItemWidth(globals.ctx)
            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Octaves")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("Number of noise layers (more = more detail/complexity)")
        end

        -- Noise Persistence slider
        do
            imgui.BeginGroup(globals.ctx)
            imgui.PushItemWidth(globals.ctx, controlWidth)

            local persKey = trackingKey .. "_noisePersistence"
            local rv, newPers = globals.UndoWrappers.SliderDouble(globals.ctx, "##NoisePersistence", dataObj.noisePersistence, 0.1, 1.0, "%.2f")

            if imgui.IsItemActive(globals.ctx) and not globals.autoRegenTracking[persKey] then
                globals.autoRegenTracking[persKey] = dataObj.noisePersistence
            end

            if rv then callbacks.setNoisePersistence(newPers) end

            if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and globals.autoRegenTracking[persKey] then
                checkAutoRegen("noisePersistence", persKey, globals.autoRegenTracking[persKey], dataObj.noisePersistence)
                globals.autoRegenTracking[persKey] = nil
            end

            imgui.PopItemWidth(globals.ctx)
            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Persistence")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("How much each octave contributes (0.5 = balanced)")
        end

        -- Noise Lacunarity slider
        do
            imgui.BeginGroup(globals.ctx)
            imgui.PushItemWidth(globals.ctx, controlWidth)

            local lacKey = trackingKey .. "_noiseLacunarity"
            local rv, newLac = globals.UndoWrappers.SliderDouble(globals.ctx, "##NoiseLacunarity", dataObj.noiseLacunarity, 1.5, 4.0, "%.2f")

            if imgui.IsItemActive(globals.ctx) and not globals.autoRegenTracking[lacKey] then
                globals.autoRegenTracking[lacKey] = dataObj.noiseLacunarity
            end

            if rv then callbacks.setNoiseLacunarity(newLac) end

            if imgui.IsItemDeactivatedAfterEdit(globals.ctx) and globals.autoRegenTracking[lacKey] then
                checkAutoRegen("noiseLacunarity", lacKey, globals.autoRegenTracking[lacKey], dataObj.noiseLacunarity)
                globals.autoRegenTracking[lacKey] = nil
            end

            imgui.PopItemWidth(globals.ctx)
            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Lacunarity")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("Frequency multiplier between octaves (2.0 = standard)")
        end

        -- Noise Seed control with randomize button
        do
            imgui.BeginGroup(globals.ctx)
            imgui.PushItemWidth(globals.ctx, controlWidth - 50)

            local seedKey = trackingKey .. "_noiseSeed"
            local rv, newSeed = globals.UndoWrappers.InputInt(globals.ctx, "##NoiseSeed", dataObj.noiseSeed)

            if rv then callbacks.setNoiseSeed(newSeed) end

            imgui.PopItemWidth(globals.ctx)
            imgui.SameLine(globals.ctx)

            -- Randomize button
            if imgui.Button(globals.ctx, "🎲##RandomizeSeed", 40, 0) then
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
            imgui.TextColored(globals.ctx, 0xAAAA00FF, "(preview mode - 10s)")
        end

        local previewWidth = controlWidth + padding + 200
        local previewHeight = 120

        UI.drawNoisePreview(dataObj, previewWidth, previewHeight)
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
            setFadeIn = function(v) obj.fadeIn = math.max(0, v); obj.needsRegeneration = true end,
            setFadeOut = function(v) obj.fadeOut = math.max(0, v); obj.needsRegeneration = true end,
            -- Chunk mode callbacks
            setChunkDuration = function(v) obj.chunkDuration = v; obj.needsRegeneration = true end,
            setChunkSilence = function(v) obj.chunkSilence = v; obj.needsRegeneration = true end,
            setChunkDurationVariation = function(v) obj.chunkDurationVariation = v; obj.needsRegeneration = true end,
            setChunkSilenceVariation = function(v) obj.chunkSilenceVariation = v; obj.needsRegeneration = true end,
            -- Noise mode callbacks
            setNoiseSeed = function(v) obj.noiseSeed = v; obj.needsRegeneration = true end,
            setNoiseFrequency = function(v) obj.noiseFrequency = v; obj.needsRegeneration = true end,
            setNoiseAmplitude = function(v) obj.noiseAmplitude = v; obj.needsRegeneration = true end,
            setNoiseOctaves = function(v) obj.noiseOctaves = v; obj.needsRegeneration = true end,
            setNoisePersistence = function(v) obj.noisePersistence = v; obj.needsRegeneration = true end,
            setNoiseLacunarity = function(v) obj.noiseLacunarity = v; obj.needsRegeneration = true end,
            setNoiseDensity = function(v) obj.noiseDensity = v; obj.needsRegeneration = true end,
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

    -- Pitch randomization (checkbox + link button + slider on same line)
    imgui.BeginGroup(globals.ctx)
    local rv, newRandomizePitch = globals.UndoWrappers.Checkbox(globals.ctx, "##RandomizePitch", obj.randomizePitch)
    if rv then
        obj.randomizePitch = newRandomizePitch
        obj.needsRegeneration = true
        -- Queue randomization update to avoid ImGui conflicts
        if groupIndex and containerIndex then
            globals.Utils.queueRandomizationUpdate(groupIndex, containerIndex, "pitch")
        elseif groupIndex then
            globals.Utils.queueRandomizationUpdate(groupIndex, nil, "pitch")
        end
    end
    
    -- Link mode button for pitch
    imgui.SameLine(globals.ctx)
    -- Ensure link mode is initialized
    if not obj.pitchLinkMode then obj.pitchLinkMode = "mirror" end
    if globals.Icons.createLinkModeButton(globals.ctx, "pitchLink" .. objId, obj.pitchLinkMode, "Link mode: " .. obj.pitchLinkMode) then
        obj.pitchLinkMode = cycleLinkMode(obj.pitchLinkMode)
        -- Capture AFTER mode change
        if globals.History then
            globals.History.captureState("Change pitch link mode")
        end
    end
    
    imgui.SameLine(globals.ctx)
    imgui.BeginDisabled(globals.ctx, not obj.randomizePitch)
    imgui.PushItemWidth(globals.ctx, controlWidth)
    local rv, newPitchMin, newPitchMax = globals.UndoWrappers.DragFloatRange2(globals.ctx, "##PitchRange",
        obj.pitchRange.min, obj.pitchRange.max, 0.1, -48, 48, "%.1f", "%.1f")
    if rv then
        -- Apply linked slider logic
        local linkedMin, linkedMax = applyLinkedSliderChange(obj, "pitch", newPitchMin, newPitchMax, obj.pitchLinkMode)
        obj.pitchRange.min = linkedMin
        obj.pitchRange.max = linkedMax
        obj.needsRegeneration = true
        -- Queue randomization update to avoid ImGui conflicts
        if groupIndex and containerIndex then
            globals.Utils.queueRandomizationUpdate(groupIndex, containerIndex, "pitch")
        elseif groupIndex then
            globals.Utils.queueRandomizationUpdate(groupIndex, nil, "pitch")
        end
    end
    imgui.PopItemWidth(globals.ctx)
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
        if globals.History then
            globals.History.captureState("Toggle pitch mode")
        end
    end

    -- Add tooltip to explain the modes
    if imgui.IsItemHovered(globals.ctx) then
        imgui.SetTooltip(globals.ctx, "Click to toggle between:\n• Pitch: Standard pitch shift (may have artifacts)\n• Stretch: Time-stretch pitch (better quality, changes duration)")
    end

    imgui.EndGroup(globals.ctx)

    -- Volume randomization (checkbox + link button + slider on same line)
    imgui.BeginGroup(globals.ctx)
    local rv, newRandomizeVolume = globals.UndoWrappers.Checkbox(globals.ctx, "##RandomizeVolume", obj.randomizeVolume)
    if rv then
        obj.randomizeVolume = newRandomizeVolume
        obj.needsRegeneration = true
        -- Queue randomization update to avoid ImGui conflicts
        if groupIndex and containerIndex then
            globals.Utils.queueRandomizationUpdate(groupIndex, containerIndex, "volume")
        elseif groupIndex then
            globals.Utils.queueRandomizationUpdate(groupIndex, nil, "volume")
        end
    end
    
    -- Link mode button for volume
    imgui.SameLine(globals.ctx)
    -- Ensure link mode is initialized
    if not obj.volumeLinkMode then obj.volumeLinkMode = "mirror" end
    if globals.Icons.createLinkModeButton(globals.ctx, "volumeLink" .. objId, obj.volumeLinkMode, "Link mode: " .. obj.volumeLinkMode) then
        obj.volumeLinkMode = cycleLinkMode(obj.volumeLinkMode)
        -- Capture AFTER mode change
        if globals.History then
            globals.History.captureState("Change volume link mode")
        end
    end
    
    imgui.SameLine(globals.ctx)
    imgui.BeginDisabled(globals.ctx, not obj.randomizeVolume)
    imgui.PushItemWidth(globals.ctx, controlWidth)
    local rv, newVolumeMin, newVolumeMax = globals.UndoWrappers.DragFloatRange2(globals.ctx, "##VolumeRange",
        obj.volumeRange.min, obj.volumeRange.max, 0.1, -24, 24, "%.1f", "%.1f")
    if rv then
        -- Apply linked slider logic
        local linkedMin, linkedMax = applyLinkedSliderChange(obj, "volume", newVolumeMin, newVolumeMax, obj.volumeLinkMode)
        obj.volumeRange.min = linkedMin
        obj.volumeRange.max = linkedMax
        obj.needsRegeneration = true
        -- Queue randomization update to avoid ImGui conflicts
        if groupIndex and containerIndex then
            globals.Utils.queueRandomizationUpdate(groupIndex, containerIndex, "volume")
        elseif groupIndex then
            globals.Utils.queueRandomizationUpdate(groupIndex, nil, "volume")
        end
    end
    imgui.PopItemWidth(globals.ctx)
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
        -- Pan randomization (checkbox + link button + slider on same line)
        imgui.BeginGroup(globals.ctx)
        local rv, newRandomizePan = globals.UndoWrappers.Checkbox(globals.ctx, "##RandomizePan", obj.randomizePan)
        if rv then
            obj.randomizePan = newRandomizePan
            obj.needsRegeneration = true
            -- Queue randomization update to avoid ImGui conflicts
            if groupIndex and containerIndex then
                globals.Utils.queueRandomizationUpdate(groupIndex, containerIndex, "pan")
            elseif groupIndex then
                globals.Utils.queueRandomizationUpdate(groupIndex, nil, "pan")
            end
        end

        -- Link mode button for pan
        imgui.SameLine(globals.ctx)
        -- Ensure link mode is initialized
        if not obj.panLinkMode then obj.panLinkMode = "mirror" end
        if globals.Icons.createLinkModeButton(globals.ctx, "panLink" .. objId, obj.panLinkMode, "Link mode: " .. obj.panLinkMode) then
            obj.panLinkMode = cycleLinkMode(obj.panLinkMode)
            -- Capture AFTER mode change
            if globals.History then
                globals.History.captureState("Change pan link mode")
            end
        end

        imgui.SameLine(globals.ctx)
        imgui.BeginDisabled(globals.ctx, not obj.randomizePan)
        imgui.PushItemWidth(globals.ctx, controlWidth)
        local rv, newPanMin, newPanMax = globals.UndoWrappers.DragFloatRange2(globals.ctx, "##PanRange",
            obj.panRange.min, obj.panRange.max, 1, -100, 100, "%.0f", "%.0f")
        if rv then
            -- Apply linked slider logic
            local linkedMin, linkedMax = applyLinkedSliderChange(obj, "pan", newPanMin, newPanMax, obj.panLinkMode)
            obj.panRange.min = linkedMin
            obj.panRange.max = linkedMax
            obj.needsRegeneration = true
            -- Queue randomization update to avoid ImGui conflicts
            if groupIndex and containerIndex then
                globals.Utils.queueRandomizationUpdate(groupIndex, containerIndex, "pan")
            elseif groupIndex then
                globals.Utils.queueRandomizationUpdate(groupIndex, nil, "pan")
            end
        end
        imgui.PopItemWidth(globals.ctx)
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
    
    -- Column positions for perfect alignment
    local colCheckbox = 0      -- Checkbox column
    local colLabel = 25        -- Label column 
    local colUnit = 100        -- Unit button column
    local colDuration = 145    -- Duration slider column
    local colShapeLabel = 275  -- "Shape:" label column
    local colShape = 315       -- Shape dropdown column
    local colCurveLabel = 440  -- "Curve:" label column (when visible)
    local colCurve = 480       -- Curve slider column (when visible)
    
    -- Element widths
    local unitButtonWidth = 40
    local durationWidth = 120
    local shapeWidth = 120
    local curveWidth = 80
    
    -- Helper function to draw fade controls with column-based alignment
    local function drawFadeControls(fadeType, enabled, usePercentage, duration, shape, curve)
        local suffix = fadeType .. objId
        local isIn = fadeType == "In"
        
        imgui.BeginGroup(globals.ctx)
        
        -- Column 1: Checkbox (position 0)
        imgui.SetCursorPosX(globals.ctx, colCheckbox)
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
        
        -- Column 2: Label (position 25)
        imgui.SameLine(globals.ctx)
        imgui.SetCursorPosX(globals.ctx, colLabel)
        imgui.AlignTextToFramePadding(globals.ctx)
        imgui.Text(globals.ctx, "Fade " .. fadeType .. ":")
        
        -- Column 3: Unit button (position 100)
        imgui.SameLine(globals.ctx)
        imgui.SetCursorPosX(globals.ctx, colUnit)
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
        
        -- Column 4: Duration slider (position 145)
        imgui.SameLine(globals.ctx)
        imgui.SetCursorPosX(globals.ctx, colDuration)
        imgui.PushItemWidth(globals.ctx, durationWidth)
        local maxVal = usePercentage and 100 or 10
        local format = usePercentage and "%.0f%%" or "%.2f"
        local rv, newDuration = globals.UndoWrappers.SliderDouble(globals.ctx, "##Duration" .. suffix,
            duration or 0.1, 0, maxVal, format)
        if rv then
            -- Apply linked fade logic
            local newInDuration, newOutDuration = applyLinkedFadeChange(obj, fadeType, newDuration, obj.fadeLinkMode or "link")
            obj.fadeInDuration = newInDuration
            obj.fadeOutDuration = newOutDuration
            -- Queue fade update to avoid ImGui conflicts
            local modifiedFade = isIn and "fadeIn" or "fadeOut"
            if groupIndex and containerIndex then
                globals.Utils.queueFadeUpdate(groupIndex, containerIndex, modifiedFade)
            elseif groupIndex then
                globals.Utils.queueFadeUpdate(groupIndex, nil, modifiedFade)
            end
        end
        imgui.PopItemWidth(globals.ctx)
        
        -- Column 5: "Shape:" label (position 275)
        imgui.SameLine(globals.ctx)
        imgui.SetCursorPosX(globals.ctx, colShapeLabel)
        imgui.AlignTextToFramePadding(globals.ctx)
        imgui.Text(globals.ctx, "Shape:")
        
        -- Column 6: Shape dropdown (position 315)
        imgui.SameLine(globals.ctx)
        imgui.SetCursorPosX(globals.ctx, colShape)
        imgui.PushItemWidth(globals.ctx, shapeWidth)
        local fadeShapes = "Linear\0Fast Start\0Fast End\0Fast S/E\0Slow S/E\0Bezier\0S-Curve\0"
        local rv, newShape = globals.UndoWrappers.Combo(globals.ctx, "##Shape" .. suffix, shape or 0, fadeShapes)
        if rv then
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
        imgui.PopItemWidth(globals.ctx)
        
        -- Column 7 & 8: Curve controls (for Linear, Bezier and S-Curve)
        -- Default to Linear if shape is nil/undefined
        local actualShape = shape or Constants.FADE_SHAPES.LINEAR
        if actualShape == Constants.FADE_SHAPES.LINEAR or actualShape == Constants.FADE_SHAPES.BEZIER or actualShape == Constants.FADE_SHAPES.S_CURVE then
            -- Column 7: "Curve:" label (position 440)
            imgui.SameLine(globals.ctx)
            imgui.SetCursorPosX(globals.ctx, colCurveLabel)
            imgui.AlignTextToFramePadding(globals.ctx)
            imgui.Text(globals.ctx, "Curve:")
            
            -- Column 8: Curve slider (position 480)
            imgui.SameLine(globals.ctx)
            imgui.SetCursorPosX(globals.ctx, colCurve)
            imgui.PushItemWidth(globals.ctx, curveWidth)
            local rv, newCurve = globals.UndoWrappers.SliderDouble(globals.ctx, "##Curve" .. suffix,
                curve or 0.0, -1.0, 1.0, "%.1f")
            if rv then
                if isIn then obj.fadeInCurve = newCurve
                else obj.fadeOutCurve = newCurve end
                -- Queue fade update to avoid ImGui conflicts
                local modifiedFade = isIn and "fadeIn" or "fadeOut"
                if groupIndex and containerIndex then
                    globals.Utils.queueFadeUpdate(groupIndex, containerIndex, modifiedFade)
                elseif groupIndex then
                    globals.Utils.queueFadeUpdate(groupIndex, nil, modifiedFade)
                end
            end
            imgui.PopItemWidth(globals.ctx)
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
        endTime = 10  -- 10 seconds preview
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

    for i, point in ipairs(curve) do
        -- Apply same formula as generation algorithm
        local rawValue = point.value  -- 0-1
        local centered = (rawValue - 0.5) * 2  -- -1 to 1
        -- Amplitude is relative to density
        local variation = centered * amplitudeScale * density
        local final = density + variation

        -- Clamp to 0-1
        final = math.max(0, math.min(1, final))

        -- Convert to screen coordinates
        local x = cursorX + (i - 1) * (width / (sampleCount - 1))
        local y = cursorY + height - (final * height)

        if prevX and prevY then
            -- Draw line segment (white)
            local lineColor = 0xFFFFFFFF
            imgui.DrawList_AddLine(drawList, prevX, prevY, x, y, lineColor, 1.5)
        end

        prevX, prevY = x, y
    end

    -- Draw zero line (for reference)
    local zeroY = cursorY + height
    local zeroColor = 0x888888AA
    imgui.DrawList_AddLine(drawList, cursorX, zeroY, cursorX + width, zeroY, zeroColor, 1.0)

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
        local rightPanelWidth = windowWidth - leftPanelWidth - Constants.UI.SPLITTER_WIDTH - 20
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
