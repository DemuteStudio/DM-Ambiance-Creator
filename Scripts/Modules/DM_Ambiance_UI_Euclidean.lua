-- ====================================================================
-- DM AMBIANCE CREATOR - EUCLIDEAN UI MODULE
-- ====================================================================
-- Modular, reusable UI components for Euclidean rhythm interface
-- Follows DRY principles and provides unified rendering logic
-- ====================================================================

local EuclideanUI = {}
local globals = {}

-- ====================================================================
-- MODULE INITIALIZATION
-- ====================================================================

function EuclideanUI.initModule(g)
    globals = g
end

-- ====================================================================
-- HELPER FUNCTIONS
-- ====================================================================

--- Get color for a specific layer index
--- @param layerIndex number The layer index (1-based)
--- @param alpha number Optional alpha value (0-1)
--- @return number RGBA color value in 0xRRGGBBAA format
local function getLayerColor(layerIndex, alpha)
    -- Colors matching original UI (0xRRGGBBAA format)
    local colors = {
        0x4A90E2FF,  -- Bleu (layer 1)
        0xE67E22FF,  -- Orange (layer 2)
        0x9B59B6FF,  -- Violet (layer 3)
        0x1ABC9CFF,  -- Cyan (layer 4)
        0xF39C12FF,  -- Jaune (layer 5)
        0xE74C3CFF,  -- Rouge (layer 6)
    }

    local colorIndex = ((layerIndex - 1) % #colors) + 1
    local color = colors[colorIndex]

    -- Apply alpha if specified
    if alpha then
        color = (color & 0xFFFFFF00) | math.floor(alpha * 255)
    end

    return color
end

-- ====================================================================
-- LAYER RENDERING
-- ====================================================================

--- Configuration for rendering a single layer
--- @class LayerRenderConfig
--- @field layerIdx number Layer index
--- @field layerData table Layer data {pulses, steps, rotation}
--- @field columnWidth number Width of the column
--- @field trackingKey string Key prefix for auto-regen tracking
--- @field callbacks table Callbacks {setPulses, setSteps, setRotation}
--- @field checkAutoRegen function Auto-regeneration check function
--- @field idPrefix string Prefix for widget IDs

--- Render a single Euclidean layer column
--- @param config LayerRenderConfig Configuration for rendering
function EuclideanUI.renderLayerColumn(config)
    local ctx = globals.ctx
    local layerIdx = config.layerIdx
    local layer = config.layerData
    local columnWidth = config.columnWidth
    local trackingKey = config.trackingKey
    local callbacks = config.callbacks
    local checkAutoRegen = config.checkAutoRegen
    local idPrefix = config.idPrefix or ""

    -- Extract layer values
    local currentPulses = layer.pulses or 8
    local currentSteps = layer.steps or 16
    local currentRotation = layer.rotation or 0

    -- Calculate dimensions
    local labelWidth = 60
    local sliderWidth = columnWidth - labelWidth - 20

    -- Start column
    globals.imgui.BeginChild(ctx, idPrefix .. "EucLayer" .. layerIdx, columnWidth, 0,
        globals.imgui.ChildFlags_Border | globals.imgui.ChildFlags_AutoResizeY)

    -- Header with color indicator
    local layerColor = getLayerColor(layerIdx)
    globals.imgui.ColorButton(ctx, "##layerColorHeader" .. idPrefix .. layerIdx,
        layerColor, globals.imgui.ColorEditFlags_NoTooltip, 16, 16)
    globals.imgui.SameLine(ctx)
    globals.imgui.Text(ctx, "Layer " .. layerIdx)

    globals.imgui.Spacing(ctx)

    -- Pulses slider
    local pulsesKey = trackingKey .. "_euclideanPulses_" .. idPrefix .. "_layer_" .. layerIdx
    local rv, newPulses = globals.SliderEnhanced.SliderDouble({
        id = "##Pulses_" .. idPrefix .. "Layer" .. layerIdx,
        value = currentPulses,
        min = 1,
        max = 64,
        defaultValue = globals.Constants.DEFAULTS.EUCLIDEAN_PULSES,
        format = "%.0f",
        width = sliderWidth
    })
    globals.imgui.SameLine(ctx, 0, 5)
    globals.imgui.AlignTextToFramePadding(ctx)
    globals.imgui.Text(ctx, "Pulses")

    if globals.imgui.IsItemActive(ctx) and not globals.autoRegenTracking[pulsesKey] then
        globals.autoRegenTracking[pulsesKey] = currentPulses
    end

    if rv then
        callbacks.setPulses(layerIdx, math.floor(newPulses))
    end

    if globals.imgui.IsItemDeactivatedAfterEdit(ctx) and globals.autoRegenTracking[pulsesKey] then
        if checkAutoRegen then
            local finalValue = math.floor(newPulses)
            checkAutoRegen("euclideanPulses", pulsesKey, globals.autoRegenTracking[pulsesKey], finalValue)
        end
        globals.autoRegenTracking[pulsesKey] = nil
    end

    globals.imgui.Spacing(ctx)

    -- Steps slider
    local stepsKey = trackingKey .. "_euclideanSteps_" .. idPrefix .. "_layer_" .. layerIdx
    local rv, newSteps = globals.SliderEnhanced.SliderDouble({
        id = "##Steps_" .. idPrefix .. "Layer" .. layerIdx,
        value = currentSteps,
        min = 1,
        max = 64,
        defaultValue = globals.Constants.DEFAULTS.EUCLIDEAN_STEPS,
        format = "%.0f",
        width = sliderWidth
    })
    globals.imgui.SameLine(ctx, 0, 5)
    globals.imgui.AlignTextToFramePadding(ctx)
    globals.imgui.Text(ctx, "Steps")

    if globals.imgui.IsItemActive(ctx) and not globals.autoRegenTracking[stepsKey] then
        globals.autoRegenTracking[stepsKey] = currentSteps
    end

    if rv then
        callbacks.setSteps(layerIdx, math.floor(newSteps))
    end

    if globals.imgui.IsItemDeactivatedAfterEdit(ctx) and globals.autoRegenTracking[stepsKey] then
        if checkAutoRegen then
            local finalValue = math.floor(newSteps)
            checkAutoRegen("euclideanSteps", stepsKey, globals.autoRegenTracking[stepsKey], finalValue)
        end
        globals.autoRegenTracking[stepsKey] = nil
    end

    globals.imgui.Spacing(ctx)

    -- Rotation slider
    local rotationKey = trackingKey .. "_euclideanRotation_" .. idPrefix .. "_layer_" .. layerIdx
    local maxRotation = currentSteps - 1
    local rv, newRotation = globals.SliderEnhanced.SliderDouble({
        id = "##Rotation_" .. idPrefix .. "Layer" .. layerIdx,
        value = currentRotation,
        min = 0,
        max = maxRotation,
        defaultValue = globals.Constants.DEFAULTS.EUCLIDEAN_ROTATION,
        format = "%.0f",
        width = sliderWidth
    })
    globals.imgui.SameLine(ctx, 0, 5)
    globals.imgui.AlignTextToFramePadding(ctx)
    globals.imgui.Text(ctx, "Rotation")

    if globals.imgui.IsItemActive(ctx) and not globals.autoRegenTracking[rotationKey] then
        globals.autoRegenTracking[rotationKey] = currentRotation
    end

    if rv then
        callbacks.setRotation(layerIdx, math.floor(newRotation))
    end

    if globals.imgui.IsItemDeactivatedAfterEdit(ctx) and globals.autoRegenTracking[rotationKey] then
        if checkAutoRegen then
            local finalValue = math.floor(newRotation)
            checkAutoRegen("euclideanRotation", rotationKey, globals.autoRegenTracking[rotationKey], finalValue)
        end
        globals.autoRegenTracking[rotationKey] = nil
    end

    -- End column
    globals.imgui.EndChild(ctx)
end

--- Render multi-column layer interface
--- @param layers table Array of layer data
--- @param trackingKey string Key prefix for auto-regen tracking
--- @param callbacks table Callbacks {setPulses, setSteps, setRotation}
--- @param checkAutoRegen function Auto-regeneration check function
--- @param idPrefix string Prefix for widget IDs
function EuclideanUI.renderLayerColumns(layers, trackingKey, callbacks, checkAutoRegen, idPrefix)
    local ctx = globals.ctx
    local numLayers = #layers
    local availableWidth = globals.imgui.GetContentRegionAvail(ctx)
    local columnWidth = math.max(180, availableWidth / math.min(numLayers, 4))

    for layerIdx = 1, numLayers do
        if layerIdx > 1 then
            globals.imgui.SameLine(ctx)
        end

        EuclideanUI.renderLayerColumn({
            layerIdx = layerIdx,
            layerData = layers[layerIdx],
            columnWidth = columnWidth,
            trackingKey = trackingKey,
            callbacks = callbacks,
            checkAutoRegen = checkAutoRegen,
            idPrefix = idPrefix
        })
    end
end

-- ====================================================================
-- CALLBACK ADAPTERS
-- ====================================================================

--- Create callback adapter for Manual mode (container/group layers)
--- @param callbacks table Original callbacks object
--- @return table Adapted callbacks {setPulses, setSteps, setRotation}
function EuclideanUI.createManualModeCallbacks(callbacks)
    return {
        setPulses = function(layerIdx, value)
            if callbacks.setEuclideanLayerPulses then
                callbacks.setEuclideanLayerPulses(layerIdx, value)
            end
        end,
        setSteps = function(layerIdx, value)
            if callbacks.setEuclideanLayerSteps then
                callbacks.setEuclideanLayerSteps(layerIdx, value)
            end
        end,
        setRotation = function(layerIdx, value)
            if callbacks.setEuclideanLayerRotation then
                callbacks.setEuclideanLayerRotation(layerIdx, value)
            end
        end
    }
end

--- Create callback adapter for Auto-Bind mode (group bindings)
--- @param callbacks table Original callbacks object
--- @param selectedBindingIndex number Currently selected binding index
--- @return table Adapted callbacks {setPulses, setSteps, setRotation}
function EuclideanUI.createAutoBindModeCallbacks(callbacks, selectedBindingIndex)
    return {
        setPulses = function(layerIdx, value)
            if callbacks.setEuclideanBindingPulses then
                callbacks.setEuclideanBindingPulses(selectedBindingIndex, layerIdx, value)
            end
        end,
        setSteps = function(layerIdx, value)
            if callbacks.setEuclideanBindingSteps then
                callbacks.setEuclideanBindingSteps(selectedBindingIndex, layerIdx, value)
            end
        end,
        setRotation = function(layerIdx, value)
            if callbacks.setEuclideanBindingRotation then
                callbacks.setEuclideanBindingRotation(selectedBindingIndex, layerIdx, value)
            end
        end
    }
end

-- ====================================================================
-- EXPORT LAYER COLOR FUNCTION (for backward compatibility)
-- ====================================================================

EuclideanUI.getLayerColor = getLayerColor

return EuclideanUI
