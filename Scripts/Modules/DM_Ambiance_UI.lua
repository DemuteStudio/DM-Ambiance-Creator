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
        -- Independent fades - just apply the new value
        return newValue, obj[fadeType == "In" and "fadeOutDuration" or "fadeInDuration"]
    elseif linkMode == "link" then
        -- Linked fades - maintain same value for both
        return newValue, newValue
    end
    
    -- Fallback to unlink behavior
    return newValue, obj[fadeType == "In" and "fadeOutDuration" or "fadeInDuration"]
end

-- Draw the trigger settings section (shared by groups and containers)
-- dataObj must expose: intervalMode, triggerRate, triggerDrift, fadeIn, fadeOut
-- callbacks must provide setters for each parameter
function UI.drawTriggerSettingsSection(dataObj, callbacks, width, titlePrefix)
    -- Section separator and title
    imgui.Separator(globals.ctx)
    imgui.Text(globals.ctx, titlePrefix .. "Trigger Settings")

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
    else
        imgui.TextColored(globals.ctx, 0xFFAA00FF, "Chunk: Structured sound/silence periods")
    end

    -- Interval mode selection (Combo box)
    do
        imgui.BeginGroup(globals.ctx)
        imgui.PushItemWidth(globals.ctx, controlWidth)
        local intervalModes = "Absolute\0Relative\0Coverage\0Chunk\0"
        local rv, newIntervalMode = imgui.Combo(globals.ctx, "##IntervalMode", dataObj.intervalMode, intervalModes)
        if rv then callbacks.setIntervalMode(newIntervalMode) end
        imgui.EndGroup(globals.ctx)

        imgui.SameLine(globals.ctx, controlWidth + padding)
        imgui.Text(globals.ctx, "Interval Mode")
        imgui.SameLine(globals.ctx)
        globals.Utils.HelpMarker(
            "Absolute: Fixed interval in seconds\n" ..
            "Relative: Interval as percentage of time selection\n" ..
            "Coverage: Percentage of time selection to be filled\n" ..
            "Chunk: Create structured sound/silence periods"
        )
    end

    -- Interval value (slider)
    do
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
        local rv, newRate = imgui.SliderDouble(globals.ctx, "##TriggerRate", dataObj.triggerRate, rateMin, rateMax, "%.1f")
        if rv then callbacks.setTriggerRate(newRate) end
        imgui.EndGroup(globals.ctx)

        imgui.SameLine(globals.ctx, controlWidth + padding)
        imgui.Text(globals.ctx, rateLabel)
        
        -- Compact random variation control on same line
        imgui.SameLine(globals.ctx)
        imgui.PushItemWidth(globals.ctx, 60)
        local rvDrift, newDrift = imgui.DragInt(globals.ctx, "##TriggerDrift", dataObj.triggerDrift, 0.5, 0, 100, "%d%%")
        if rvDrift then callbacks.setTriggerDrift(newDrift) end
        imgui.PopItemWidth(globals.ctx)
        imgui.SameLine(globals.ctx)
        imgui.Text(globals.ctx, "Var")
    end

    -- Chunk mode specific controls
    if dataObj.intervalMode == 3 then
        -- Chunk Duration slider with variation knob
        do
            imgui.BeginGroup(globals.ctx)
            imgui.PushItemWidth(globals.ctx, controlWidth)
            local rv, newDuration = imgui.SliderDouble(globals.ctx, "##ChunkDuration", dataObj.chunkDuration, 0.5, 60.0, "%.1f sec")
            if rv then callbacks.setChunkDuration(newDuration) end
            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Chunk Duration")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("Duration of active sound periods in seconds")
            
            -- Compact variation control on same line
            imgui.SameLine(globals.ctx)
            imgui.PushItemWidth(globals.ctx, 60)
            local rv2, newDurationVar = imgui.DragInt(globals.ctx, "##ChunkDurationVar", dataObj.chunkDurationVariation, 0.5, 0, 100, "%d%%")
            if rv2 then callbacks.setChunkDurationVariation(newDurationVar) end
            imgui.PopItemWidth(globals.ctx)
            imgui.SameLine(globals.ctx)
            imgui.Text(globals.ctx, "Var")
        end

        -- Chunk Silence slider with variation knob
        do
            imgui.BeginGroup(globals.ctx)
            imgui.PushItemWidth(globals.ctx, controlWidth)
            local rv, newSilence = imgui.SliderDouble(globals.ctx, "##ChunkSilence", dataObj.chunkSilence, 0.0, 120.0, "%.1f sec")
            if rv then callbacks.setChunkSilence(newSilence) end
            imgui.EndGroup(globals.ctx)

            imgui.SameLine(globals.ctx, controlWidth + padding)
            imgui.Text(globals.ctx, "Silence Duration")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("Duration of silence periods between chunks in seconds")
            
            -- Compact variation control on same line
            imgui.SameLine(globals.ctx)
            imgui.PushItemWidth(globals.ctx, 60)
            local rv2, newSilenceVar = imgui.DragInt(globals.ctx, "##ChunkSilenceVar", dataObj.chunkSilenceVariation, 0.5, 0, 100, "%d%%")
            if rv2 then callbacks.setChunkSilenceVariation(newSilenceVar) end
            imgui.PopItemWidth(globals.ctx)
            imgui.SameLine(globals.ctx)
            imgui.Text(globals.ctx, "Var")
        end
    end

    -- Fade in/out controls are commented out but can be enabled if needed
end

-- Display trigger and randomization settings for a group or container
function UI.displayTriggerSettings(obj, objId, width, isGroup, groupIndex, containerIndex)
    local titlePrefix = isGroup and "Default " or ""
    local inheritText = isGroup and "These settings will be inherited by containers unless overridden" or ""

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
            setIntervalMode = function(v) obj.intervalMode = v end,
            setTriggerRate = function(v) obj.triggerRate = v end,
            setTriggerDrift = function(v) obj.triggerDrift = v end,
            setFadeIn = function(v) obj.fadeIn = math.max(0, v) end,
            setFadeOut = function(v) obj.fadeOut = math.max(0, v) end,
            -- Chunk mode callbacks
            setChunkDuration = function(v) obj.chunkDuration = v end,
            setChunkSilence = function(v) obj.chunkSilence = v end,
            setChunkDurationVariation = function(v) obj.chunkDurationVariation = v end,
            setChunkSilenceVariation = function(v) obj.chunkSilenceVariation = v end,
        },
        width,
        titlePrefix
    )

    -- Randomization parameters section
    imgui.Separator(globals.ctx)
    imgui.Text(globals.ctx, titlePrefix .. "Randomization parameters")

    local checkboxWidth = 20
    local controlWidth = width * 0.50
    local labelOffset = checkboxWidth + controlWidth + 10

    -- Pitch randomization (checkbox + link button + slider on same line)
    imgui.BeginGroup(globals.ctx)
    local rv, newRandomizePitch = imgui.Checkbox(globals.ctx, "##RandomizePitch", obj.randomizePitch)
    if rv then 
        obj.randomizePitch = newRandomizePitch 
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
    end
    
    imgui.SameLine(globals.ctx)
    imgui.BeginDisabled(globals.ctx, not obj.randomizePitch)
    imgui.PushItemWidth(globals.ctx, controlWidth)
    local rv, newPitchMin, newPitchMax = imgui.DragFloatRange2(globals.ctx, "##PitchRange", 
        obj.pitchRange.min, obj.pitchRange.max, 0.1, -48, 48, "%.1f", "%.1f")
    if rv then
        -- Apply linked slider logic
        local linkedMin, linkedMax = applyLinkedSliderChange(obj, "pitch", newPitchMin, newPitchMax, obj.pitchLinkMode)
        obj.pitchRange.min = linkedMin
        obj.pitchRange.max = linkedMax
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
    imgui.Text(globals.ctx, "Pitch (semitones)")
    imgui.EndGroup(globals.ctx)

    -- Volume randomization (checkbox + link button + slider on same line)
    imgui.BeginGroup(globals.ctx)
    local rv, newRandomizeVolume = imgui.Checkbox(globals.ctx, "##RandomizeVolume", obj.randomizeVolume)
    if rv then 
        obj.randomizeVolume = newRandomizeVolume 
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
    end
    
    imgui.SameLine(globals.ctx)
    imgui.BeginDisabled(globals.ctx, not obj.randomizeVolume)
    imgui.PushItemWidth(globals.ctx, controlWidth)
    local rv, newVolumeMin, newVolumeMax = imgui.DragFloatRange2(globals.ctx, "##VolumeRange", 
        obj.volumeRange.min, obj.volumeRange.max, 0.1, -24, 24, "%.1f", "%.1f")
    if rv then
        -- Apply linked slider logic
        local linkedMin, linkedMax = applyLinkedSliderChange(obj, "volume", newVolumeMin, newVolumeMax, obj.volumeLinkMode)
        obj.volumeRange.min = linkedMin
        obj.volumeRange.max = linkedMax
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

    -- Pan randomization (checkbox + link button + slider on same line)
    imgui.BeginGroup(globals.ctx)
    local rv, newRandomizePan = imgui.Checkbox(globals.ctx, "##RandomizePan", obj.randomizePan)
    if rv then 
        obj.randomizePan = newRandomizePan 
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
    end
    
    imgui.SameLine(globals.ctx)
    imgui.BeginDisabled(globals.ctx, not obj.randomizePan)
    imgui.PushItemWidth(globals.ctx, controlWidth)
    local rv, newPanMin, newPanMax = imgui.DragFloatRange2(globals.ctx, "##PanRange", 
        obj.panRange.min, obj.panRange.max, 1, -100, 100, "%.0f", "%.0f")
    if rv then
        -- Apply linked slider logic
        local linkedMin, linkedMax = applyLinkedSliderChange(obj, "pan", newPanMin, newPanMax, obj.panLinkMode)
        obj.panRange.min = linkedMin
        obj.panRange.max = linkedMax
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
        local rv, newEnabled = imgui.Checkbox(globals.ctx, "##Enable" .. suffix, enabled or false)
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
        end
        
        -- Column 4: Duration slider (position 145)
        imgui.SameLine(globals.ctx)
        imgui.SetCursorPosX(globals.ctx, colDuration)
        imgui.PushItemWidth(globals.ctx, durationWidth)
        local maxVal = usePercentage and 100 or 10
        local format = usePercentage and "%.0f%%" or "%.2f"
        local rv, newDuration = imgui.SliderDouble(globals.ctx, "##Duration" .. suffix,
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
        local rv, newShape = imgui.Combo(globals.ctx, "##Shape" .. suffix, shape or 0, fadeShapes)
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
            local rv, newCurve = imgui.SliderDouble(globals.ctx, "##Curve" .. suffix,
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

-- Main window rendering function
function UI.ShowMainWindow(open)
    local windowFlags = imgui.WindowFlags_None
    local visible, open = globals.imgui.Begin(globals.ctx, 'Ambiance Creator', open, windowFlags)

    -- CRITICAL: Only call End() if Begin() returned true (visible)
    if visible then
        -- Handle keyboard input for Delete key
        if globals.imgui.IsKeyPressed(globals.ctx, globals.imgui.Key_Delete) then
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
        globals.imgui.SameLine(globals.ctx)
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

        -- Two-panel layout dimensions
        local windowWidth = globals.imgui.GetWindowWidth(globals.ctx)
        local leftPanelWidth = windowWidth * 0.35
        local rightPanelWidth = windowWidth * 0.63

        -- Left panel: groups and containers
        local leftVisible = globals.imgui.BeginChild(globals.ctx, "LeftPanel", leftPanelWidth, 0)
        if leftVisible then
            drawLeftPanel(leftPanelWidth)
            globals.imgui.EndChild(globals.ctx)
        end

        -- Right panel: container or group details
        globals.imgui.SameLine(globals.ctx)
        local rightVisible = globals.imgui.BeginChild(globals.ctx, "RightPanel", rightPanelWidth, 0)
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

    -- Handle other popups
    handlePopups()
    
    -- Process any queued fade updates after ImGui frame is complete
    globals.Utils.processQueuedFadeUpdates()
    
    -- Process any queued randomization updates after ImGui frame is complete
    globals.Utils.processQueuedRandomizationUpdates()
    
    return open
end



return UI
