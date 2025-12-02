--[[
@version 1.5
@noindex
DM Ambiance Creator - Math Utilities Module
Extracted from DM_Ambiance_Utils.lua for better modularity

This module contains all mathematical helpers, randomization, conversions, and range mapping.
--]]

local Utils_Math = {}
local Constants = require("DM_Ambiance_Constants")

-- Generate random value between min and max
-- @param min number: Minimum value
-- @param max number: Maximum value
-- @return number: Random value in range [min, max]
function Utils_Math.randomInRange(min, max)
    return min + math.random() * (max - min)
end

-- Apply variation with directional control
-- @param baseValue number: The base value to vary
-- @param variationPercent number: Variation percentage (0-100)
-- @param direction number: Direction mode (0=negative, 1=bipolar, 2=positive)
-- @return number: The varied value
function Utils_Math.applyDirectionalVariation(baseValue, variationPercent, direction)
    if variationPercent <= 0 then
        return 0
    end

    local variationRange = baseValue * (variationPercent / 100)

    -- Default to bipolar if direction is nil (backward compatibility)
    if direction == nil then
        direction = Constants.VARIATION_DIRECTIONS.BIPOLAR
    end

    if direction == Constants.VARIATION_DIRECTIONS.NEGATIVE then
        -- Negative only: [0, -variationRange]
        return -math.random() * variationRange
    elseif direction == Constants.VARIATION_DIRECTIONS.POSITIVE then
        -- Positive only: [0, +variationRange]
        return math.random() * variationRange
    else
        -- Bipolar (default): [-variationRange, +variationRange]
        return Utils_Math.randomInRange(-variationRange, variationRange)
    end
end

-- Convert semitones to playrate for time stretching
-- @param semitones number: Pitch shift in semitones
-- @return number: Playrate value (1.0 = normal speed)
function Utils_Math.semitonesToPlayrate(semitones)
    return 2 ^ (semitones / 12)
end

-- Convert playrate to semitones (inverse of semitonesToPlayrate)
-- @param playrate number: Playrate value (1.0 = normal speed)
-- @return number: Pitch shift in semitones
function Utils_Math.playrateToSemitones(playrate)
    return 12 * math.log(playrate) / math.log(2)
end

-- Convert decibel value to linear volume factor
-- @param volumeDB number: Volume in decibels
-- @return number: Linear volume factor
function Utils_Math.dbToLinear(volumeDB)
    if type(volumeDB) ~= "number" then
        error("Utils_Math.dbToLinear: volumeDB parameter must be a number")
    end

    -- Special case for -inf dB (mute)
    if volumeDB <= Constants.AUDIO.VOLUME_RANGE_DB_MIN then
        return 0.0
    end

    return 10 ^ (volumeDB / 20)
end

-- Convert linear volume factor to decibel value
-- @param linearVolume number: Linear volume factor
-- @return number: Volume in decibels
function Utils_Math.linearToDb(linearVolume)
    if type(linearVolume) ~= "number" or linearVolume < 0 then
        error("Utils_Math.linearToDb: linearVolume parameter must be a non-negative number")
    end

    -- Special case for mute
    if linearVolume <= 0 then
        return Constants.AUDIO.VOLUME_RANGE_DB_MIN
    end

    return 20 * (math.log(linearVolume) / math.log(10))
end

-- Convert normalized slider value (0-1) to dB with 0dB at center
-- @param normalizedValue number: Normalized value from 0.0 to 1.0
-- @return number: Volume in decibels
function Utils_Math.normalizedToDbRelative(normalizedValue)
    if type(normalizedValue) ~= "number" or normalizedValue < 0 or normalizedValue > 1 then
        error("Utils_Math.normalizedToDbRelative: normalizedValue must be between 0 and 1")
    end

    if normalizedValue < 0.5 then
        -- Left half: -144dB to 0dB with audio taper curve (convex, not concave)
        local ratio = normalizedValue / 0.5  -- 0 to 1 for left half

        -- Use audio taper curve for natural mixing console feel
        -- This provides better resolution in the mixing range (-40dB to 0dB)
        if ratio < 0.001 then
            -- Very close to zero, return minimum
            return Constants.AUDIO.VOLUME_RANGE_DB_MIN
        else
            -- Use exponential curve for natural audio taper
            -- This creates a convex curve that matches professional mixing consoles
            -- At ratio 0.5 (position 0.25), this gives approximately -20dB
            local dB = 60 * (math.log(ratio) / math.log(10))
            -- Clamp to minimum
            return math.max(dB, Constants.AUDIO.VOLUME_RANGE_DB_MIN)
        end
    else
        -- Right half: 0dB to +24dB (linear)
        local ratio = (normalizedValue - 0.5) / 0.5
        return Constants.AUDIO.VOLUME_RANGE_DB_MAX * ratio
    end
end

-- Convert dB value to normalized slider position (0-1)
-- @param volumeDB number: Volume in decibels
-- @return number: Normalized value from 0.0 to 1.0
function Utils_Math.dbToNormalizedRelative(volumeDB)
    if type(volumeDB) ~= "number" then
        error("Utils_Math.dbToNormalizedRelative: volumeDB must be a number")
    end

    if volumeDB <= Constants.AUDIO.VOLUME_RANGE_DB_MIN then
        return 0.0
    elseif volumeDB <= 0 then
        -- Map -144dB to 0dB → 0.0 to 0.5 with inverse audio taper curve
        -- Use the inverse of the exponential curve for consistency
        -- 10^(dB/60) gives us the ratio for our audio taper
        local ratio = 10^(volumeDB / 60)
        -- Clamp ratio to valid range [0, 1]
        ratio = math.max(0, math.min(1, ratio))
        return ratio * 0.5
    else
        -- Map 0dB to +24dB → 0.5 to 1.0
        local ratio = volumeDB / Constants.AUDIO.VOLUME_RANGE_DB_MAX
        return 0.5 + (ratio * 0.5)
    end
end

-- Calculate proportional value when range changes
-- @param currentValue number: Current value in old range
-- @param oldMin number: Old range minimum
-- @param oldMax number: Old range maximum
-- @param newMin number: New range minimum
-- @param newMax number: New range maximum
-- @param defaultValue number: Default/center value
-- @return number: Proportional value in new range
function Utils_Math.calculateProportionalValue(currentValue, oldMin, oldMax, newMin, newMax, defaultValue)
    -- If current value is at default, keep it at default
    if math.abs(currentValue - defaultValue) < 0.001 then
        return defaultValue
    end

    -- Calculate the relative position in the old range
    local oldRange = oldMax - oldMin
    if oldRange == 0 then
        return defaultValue -- Avoid division by zero
    end

    local relativePosition = (currentValue - defaultValue) / oldRange

    -- Apply this relative position to the new range
    local newRange = newMax - newMin
    local newValue = defaultValue + (relativePosition * newRange)

    return newValue
end

-- Calculate GCD (Greatest Common Divisor) using Euclidean algorithm
-- @param a number: First number
-- @param b number: Second number
-- @return number: GCD of a and b
function Utils_Math.gcd(a, b)
    while b ~= 0 do
        a, b = b, a % b
    end
    return a
end

-- Calculate LCM (Least Common Multiple)
-- @param a number: First number
-- @param b number: Second number
-- @return number: LCM of a and b
function Utils_Math.lcm(a, b)
    return (a * b) / Utils_Math.gcd(a, b)
end

-- Calculate LCM of multiple numbers
-- @param numbers table: Array of numbers
-- @return number: LCM of all numbers
function Utils_Math.lcmMultiple(numbers)
    if #numbers == 0 then return 1 end
    if #numbers == 1 then return numbers[1] end

    local result = numbers[1]
    for i = 2, #numbers do
        result = Utils_Math.lcm(result, numbers[i])
    end
    return result
end

-- Generate Euclidean rhythm pattern using Bjorklund's algorithm
-- @param pulses number: Number of hits in the pattern
-- @param steps number: Total number of steps
-- @return table: Boolean array representing the pattern (true = hit, false = silence)
function Utils_Math.euclideanRhythm(pulses, steps)
    if pulses >= steps then
        -- All steps are hits
        local pattern = {}
        for i = 1, steps do
            pattern[i] = true
        end
        return pattern
    end

    if pulses == 0 then
        -- No hits
        local pattern = {}
        for i = 1, steps do
            pattern[i] = false
        end
        return pattern
    end

    -- Bjorklund's algorithm
    local pattern = {}
    local bucket = 0

    for i = 1, steps do
        bucket = bucket + pulses
        if bucket >= steps then
            bucket = bucket - steps
            pattern[i] = true
        else
            pattern[i] = false
        end
    end

    return pattern
end

-- Generate euclidean rhythm pattern with rotation applied
-- This is the single source of truth for euclidean pattern generation
-- @param pulses number: Number of hits in the pattern
-- @param steps number: Total number of steps
-- @param rotation number: Rotation offset (0 = no rotation)
-- @return table: Boolean array representing the pattern (true = hit, false = silence)
function Utils_Math.euclideanRhythmWithRotation(pulses, steps, rotation)
    -- Generate base pattern
    local pattern = Utils_Math.euclideanRhythm(pulses, steps)

    -- Apply rotation: adjust by +1 so rotation=0 means no rotation
    -- (previously rotation=1 was effectively "no rotation")
    local adjustedRotation = (rotation or 0) + 1

    if adjustedRotation ~= 0 then
        local normalizedRotation = adjustedRotation % steps
        local rotated = {}
        for i = 1, steps do
            local sourceIndex = ((i - 1 - normalizedRotation) % steps) + 1
            rotated[i] = pattern[sourceIndex]
        end
        pattern = rotated
    end

    return pattern
end

-- Combine euclidean layers into a single pattern using polyrhythmic mapping
-- @param layers table: Array of layer objects with {pulses, steps, rotation}
-- @return table: Combined pattern array (1-indexed, true=hit, false=rest)
-- @return number: LCM steps (length of combined pattern)
function Utils_Math.combineEuclideanLayers(layers)
    if not layers or #layers == 0 then
        return {true}, 1
    end

    -- Calculate LCM of all step counts
    local stepCounts = {}
    for _, layer in ipairs(layers) do
        table.insert(stepCounts, layer.steps or 16)
    end
    local lcmSteps = math.floor(Utils_Math.lcmMultiple(stepCounts))

    -- Initialize combined pattern
    local combinedPattern = {}
    for i = 1, lcmSteps do
        combinedPattern[i] = false
    end

    -- Process each layer
    for layerIdx, layer in ipairs(layers) do
        local pulses = layer.pulses or 8
        local steps = layer.steps or 16
        local rotation = layer.rotation or 0

        -- Generate euclidean pattern with rotation (single source of truth)
        local pattern = Utils_Math.euclideanRhythmWithRotation(pulses, steps, rotation)

        -- Extract pulse steps
        local pulseSteps = {}
        for i = 1, steps do
            if pattern[i] then
                table.insert(pulseSteps, i)
            end
        end

        -- Map pulses to LCM grid
        -- Rotation already applied to pattern above, so just map step indices to grid
        local stepSize = lcmSteps / steps  -- How many LCM positions per layer step

        for _, stepIndex in ipairs(pulseSteps) do
            local gridPos = (stepIndex - 1) * stepSize + 1  -- +1 for 1-based indexing

            -- Round to nearest integer and clamp
            gridPos = math.floor(gridPos + 0.5)
            if gridPos < 1 then gridPos = 1 end
            if gridPos > lcmSteps then gridPos = lcmSteps end

            combinedPattern[gridPos] = true
        end
    end

    return combinedPattern, lcmSteps
end

return Utils_Math
