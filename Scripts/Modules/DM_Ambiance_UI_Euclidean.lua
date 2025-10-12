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
    local columnHeight = config.columnHeight or 0  -- Optional fixed height
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

    -- Start column (use fixed height if provided, otherwise auto-resize)
    local childFlags = globals.imgui.ChildFlags_Border
    if columnHeight == 0 then
        childFlags = childFlags | globals.imgui.ChildFlags_AutoResizeY
    end
    globals.imgui.BeginChild(ctx, idPrefix .. "EucLayer" .. layerIdx, columnWidth, columnHeight, childFlags)

    -- Header with color indicator
    local layerColor = getLayerColor(layerIdx)
    globals.imgui.ColorButton(ctx, "##layerColorHeader" .. idPrefix .. layerIdx,
        layerColor, globals.imgui.ColorEditFlags_NoTooltip, 16, 16)
    globals.imgui.SameLine(ctx)
    globals.imgui.Text(ctx, "Layer " .. layerIdx)

    globals.imgui.Spacing(ctx)

    -- Pulses slider
    globals.SliderEnhanced.SliderDouble({
        id = "##Pulses_" .. idPrefix .. "Layer" .. layerIdx,
        value = currentPulses,
        min = 1,
        max = 64,
        defaultValue = globals.Constants.DEFAULTS.EUCLIDEAN_PULSES,
        format = "%.0f",
        width = sliderWidth,
        onChange = function(newValue)
            callbacks.setPulses(layerIdx, math.floor(newValue))
        end,
        onChangeComplete = function(oldValue, newValue)
            if checkAutoRegen then
                checkAutoRegen()
            end
        end
    })

    globals.imgui.SameLine(ctx, 0, 5)
    globals.imgui.AlignTextToFramePadding(ctx)
    globals.imgui.Text(ctx, "Pulses")

    globals.imgui.Spacing(ctx)

    -- Steps slider
    globals.SliderEnhanced.SliderDouble({
        id = "##Steps_" .. idPrefix .. "Layer" .. layerIdx,
        value = currentSteps,
        min = 1,
        max = 64,
        defaultValue = globals.Constants.DEFAULTS.EUCLIDEAN_STEPS,
        format = "%.0f",
        width = sliderWidth,
        onChange = function(newValue)
            callbacks.setSteps(layerIdx, math.floor(newValue))
        end,
        onChangeComplete = function(oldValue, newValue)
            if checkAutoRegen then
                checkAutoRegen()
            end
        end
    })

    globals.imgui.SameLine(ctx, 0, 5)
    globals.imgui.AlignTextToFramePadding(ctx)
    globals.imgui.Text(ctx, "Steps")

    globals.imgui.Spacing(ctx)

    -- Rotation slider
    local maxRotation = currentSteps - 1
    globals.SliderEnhanced.SliderDouble({
        id = "##Rotation_" .. idPrefix .. "Layer" .. layerIdx,
        value = currentRotation,
        min = 0,
        max = maxRotation,
        defaultValue = globals.Constants.DEFAULTS.EUCLIDEAN_ROTATION,
        format = "%.0f",
        width = sliderWidth,
        onChange = function(newValue)
            callbacks.setRotation(layerIdx, math.floor(newValue))
        end,
        onChangeComplete = function(oldValue, newValue)
            if checkAutoRegen then
                checkAutoRegen()
            end
        end
    })

    globals.imgui.SameLine(ctx, 0, 5)
    globals.imgui.AlignTextToFramePadding(ctx)
    globals.imgui.Text(ctx, "Rotation")

    -- End column
    globals.imgui.EndChild(ctx)
end

--- Render multi-column layer interface
--- @param layers table Array of layer data
--- @param trackingKey string Key prefix for auto-regen tracking
--- @param callbacks table Callbacks {setPulses, setSteps, setRotation}
--- @param checkAutoRegen function Auto-regeneration check function
--- @param idPrefix string Prefix for widget IDs
--- @param columnHeight number Optional fixed height for columns
function EuclideanUI.renderLayerColumns(layers, trackingKey, callbacks, checkAutoRegen, idPrefix, columnHeight)
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
            columnHeight = columnHeight,
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
