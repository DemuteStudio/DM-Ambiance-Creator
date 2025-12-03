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
local UI_Core = require("DM_Ambiance_UI_Core")
local UI_MainWindow = require("DM_Ambiance_UI_MainWindow")
local UI_TriggerSection = require("DM_Ambiance_UI_TriggerSection")
local UI_FadeSection = require("DM_Ambiance_UI_FadeSection")
local UI_EuclideanSection = require("DM_Ambiance_UI_EuclideanSection")
local UI_NoisePreview = require("DM_Ambiance_UI_NoisePreview")
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
    UI_Core.initModule(globals)
    UI_MainWindow.initModule(globals)
    UI_TriggerSection.initModule(globals)
    UI_FadeSection.initModule(globals)
    UI_EuclideanSection.initModule(globals)
    UI_NoisePreview.initModule(globals)
    UI_Preset.initModule(globals)
    UI_Container.initModule(globals)
    UI_Groups.initModule(globals)
    UI_MultiSelection.initModule(globals)
    UI_Generation.initModule(globals)
    UI_Group.initModule(globals)
    Icons.initModule(globals)

    -- Make new UI modules accessible globally
    globals.UI_Core = UI_Core
    globals.UI_MainWindow = UI_MainWindow
    globals.UI_TriggerSection = UI_TriggerSection
    globals.UI_FadeSection = UI_FadeSection
    globals.UI_EuclideanSection = UI_EuclideanSection
    globals.UI_NoisePreview = UI_NoisePreview

    -- Make UI_Groups accessible to the UI_Group module
    globals.UI_Groups = UI_Groups
    globals.UI_Group = UI_Group
    globals.UI_Container = UI_Container
    globals.UI_MultiSelection = UI_MultiSelection

    -- Make Icons accessible to other modules
    globals.Icons = Icons

    -- Make UI accessible to other modules
    globals.UI = UI

    -- Pass helper functions to UI_MainWindow
    UI_MainWindow.setHelperFunctions({
        drawLeftPanel = UI.drawLeftPanel,
        drawRightPanel = UI.drawRightPanel,
        getLeftPanelWidth = UI_Core.getLeftPanelWidth,
        handlePopups = UI_Core.handlePopups,
        isContainerSelected = UI_Core.isContainerSelected,
        toggleContainerSelection = UI_Core.toggleContainerSelection,
        clearContainerSelections = UI_Core.clearContainerSelections,
        selectContainerRange = UI_Core.selectContainerRange
    })

    -- Detect default font size from ImGui
    globals.defaultFontSize = imgui.GetFontSize(globals.ctx) or 13
end

-- Helper function to scale a size value
function UI.scaleSize(size)
    local uiScale = globals.Settings.getSetting("uiScale") or 1.0
    return size * uiScale
end

-- Get color for a specific euclidean layer index (delegates to EuclideanUI module)
-- @param layerIndex number: Layer index (1-based)
-- @param alpha number: Optional alpha value (0.0-1.0), if nil uses color's original alpha
-- @return number: Color in 0xRRGGBBAA format
local function getEuclideanLayerColor(layerIndex, alpha)
    return globals.EuclideanUI.getLayerColor(layerIndex, alpha)
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

-- Push custom style variables for UI (delegates to UI_Core)
function UI.PushStyle()
    return UI_Core.PushStyle()
end


-- Pop custom style variables (delegates to UI_Core)
function UI.PopStyle()
    return UI_Core.PopStyle()
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

--- Draw the trigger settings section (shared by groups and containers)
-- dataObj must expose: intervalMode, triggerRate, triggerDrift, fadeIn, fadeOut
-- callbacks must provide setters for each parameter
-- Delegate to UI_TriggerSection
function UI.drawTriggerSettingsSection(dataObj, callbacks, width, titlePrefix, autoRegenCallback, isGroup, groupIndex, containerIndex)
    return UI_TriggerSection.drawTriggerSettingsSection(dataObj, callbacks, width, titlePrefix, autoRegenCallback, isGroup, groupIndex, containerIndex)
end

-- Display trigger and randomization settings for a group or container (delegates to UI_TriggerSection)
function UI.displayTriggerSettings(obj, objId, width, isGroup, groupIndex, containerIndex)
    return UI_TriggerSection.displayTriggerSettings(obj, objId, width, isGroup, groupIndex, containerIndex)
end

-- Function to draw fade settings controls (delegates to UI_FadeSection)
function UI.drawFadeSettingsSection(obj, objId, width, titlePrefix, groupIndex, containerIndex)
    return UI_FadeSection.drawFadeSettingsSection(obj, objId, width, titlePrefix, groupIndex, containerIndex)
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
-- Draw the left panel with groups (public function for UI_MainWindow)
function UI.drawLeftPanel(width)
    local availHeight = globals.imgui.GetWindowHeight(globals.ctx)

    if availHeight < 100 then -- Minimum height check
        -- Don't render anything when window is too small
        return
    end

    UI_Groups.drawGroupsPanel(width, UI_Core.isContainerSelected, UI_Core.toggleContainerSelection, UI_Core.clearContainerSelections, UI_Core.selectContainerRange)
end

-- Draw the right panel with details for the selected container or group (public function for UI_MainWindow)
function UI.drawRightPanel(width)
    -- Delegate to the new modular UI_RightPanel module (path-based system)
    globals.UI_RightPanel.render(width)
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

-- Draw noise preview visualization - delegates to UI_NoisePreview
-- @param dataObj table: Container or group object with noise parameters
-- @param width number: Width of preview area
-- @param height number: Height of preview area
function UI.drawNoisePreview(dataObj, width, height)
    return UI_NoisePreview.draw(dataObj, width, height)
end

-- Draw euclidean pattern preview visualization (circular representation) - delegates to UI_EuclideanSection
-- @param dataObj table: Container or group object with euclidean parameters
-- @param size number: Diameter of the container
function UI.drawEuclideanPreview(dataObj, size, isGroup)
    return UI_EuclideanSection.drawEuclideanPreview(dataObj, size, isGroup)
end

-- Draw Euclidean Pattern Preset Browser Modal - delegates to UI_EuclideanSection
function UI.drawEuclideanPatternPresetBrowser()
    return UI_EuclideanSection.drawEuclideanPatternPresetBrowser()
end

-- Draw saved euclidean patterns list with Save/Override buttons - delegates to UI_EuclideanSection
function UI.drawEuclideanSavedPatternsList(dataObj, callbacks, isGroup, groupIndex, containerIndex, height)
    return UI_EuclideanSection.drawEuclideanSavedPatternsList(dataObj, callbacks, isGroup, groupIndex, containerIndex, height)
end

-- Main window rendering function - delegates to UI_MainWindow
function UI.ShowMainWindow(open)
    return UI_MainWindow.ShowMainWindow(open)
end

return UI
