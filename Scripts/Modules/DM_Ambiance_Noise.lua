--[[
@version 1.6
@noindex
Noise Generator for Ambiance Creator
Provides multiple 1D noise types with octaves for organic patterns:
  Perlin (smooth), Ridged (sharp peaks), Worley (burst clusters), Sine (periodic)
--]]

local Noise = {}
local globals = {}

function Noise.initModule(g)
    if not g then
        error("Noise.initModule: globals parameter is required")
    end
    globals = g
end

-- Generate pseudo-random value from integer seed
-- @param x number: Input value
-- @param seed number: Random seed
-- @return number: Pseudo-random value between -1 and 1
local function pseudoRandom(x, seed)
    -- Mix x and seed using prime numbers for good distribution
    local n = math.floor(x) + seed * 57
    n = (n * 158371 + 251893) % 2147483647
    n = (n * (n * n * 15731 + 789221) + 1376312589) % 2147483647

    -- Normalize to -1 to 1
    return (n / 1073741824.0) - 1.0
end

-- Smoothstep interpolation (smoother than linear)
-- @param t number: Interpolation factor (0-1)
-- @return number: Smoothed value
local function smoothstep(t)
    return t * t * (3.0 - 2.0 * t)
end

-- Cosine interpolation
-- @param a number: Start value
-- @param b number: End value
-- @param t number: Interpolation factor (0-1)
-- @return number: Interpolated value
local function cosineInterpolate(a, b, t)
    local ft = t * math.pi
    local f = (1.0 - math.cos(ft)) * 0.5
    return a * (1.0 - f) + b * f
end

-- Generate interpolated noise value at a specific position
-- @param x number: Position
-- @param seed number: Random seed
-- @return number: Noise value between -1 and 1
local function interpolatedNoise(x, seed)
    local x0 = math.floor(x)
    local x1 = x0 + 1
    local fracX = x - x0

    local v0 = pseudoRandom(x0, seed)
    local v1 = pseudoRandom(x1, seed)

    -- Use smoothstep for even smoother transitions
    local smooth = smoothstep(fracX)
    return v0 * (1.0 - smooth) + v1 * smooth
end

-- ========================================
-- NOISE TYPE: PERLIN
-- Classic Perlin fBm: smooth organic curves
-- ========================================
-- @return number: Noise value between 0 and 1
function Noise.perlin1D(x, frequency, octaves, persistence, lacunarity, seed)
    frequency = frequency or 1.0
    octaves = octaves or 1
    persistence = persistence or 0.5
    lacunarity = lacunarity or 2.0
    seed = seed or 0

    local total = 0.0
    local amplitude = 1.0
    local maxValue = 0.0
    local freq = frequency

    for i = 1, octaves do
        -- Get noise value for this octave
        local noiseValue = interpolatedNoise(x * freq, seed + i)

        -- Accumulate weighted noise
        total = total + noiseValue * amplitude
        maxValue = maxValue + amplitude

        -- Reduce amplitude for next octave (persistence)
        amplitude = amplitude * persistence

        -- Increase frequency for next octave (lacunarity)
        freq = freq * lacunarity
    end

    -- Normalize to 0-1 range
    return (total / maxValue + 1.0) * 0.5
end

-- ========================================
-- NOISE TYPE: RIDGED
-- Ridged multifractal: sharp peaks separated by calm valleys
-- Takes abs(noise), inverts it, and squares for dramatic spikes
-- ========================================
-- @return number: Noise value between 0 and 1
function Noise.ridged1D(x, frequency, octaves, persistence, lacunarity, seed)
    frequency = frequency or 1.0
    octaves = octaves or 1
    persistence = persistence or 0.5
    lacunarity = lacunarity or 2.0
    seed = seed or 0

    local total = 0.0
    local amplitude = 1.0
    local maxValue = 0.0
    local freq = frequency
    local weight = 1.0

    for i = 1, octaves do
        local noiseValue = interpolatedNoise(x * freq, seed + i)

        -- Ridged transform: abs → invert → square
        noiseValue = 1.0 - math.abs(noiseValue)
        noiseValue = noiseValue * noiseValue

        -- Weight successive octaves by previous signal
        noiseValue = noiseValue * weight
        weight = math.max(0, math.min(1, noiseValue))

        total = total + noiseValue * amplitude
        maxValue = maxValue + amplitude

        amplitude = amplitude * persistence
        freq = freq * lacunarity
    end

    return math.max(0, math.min(1, total / maxValue))
end

-- ========================================
-- NOISE TYPE: WORLEY (Cellular)
-- Distance to nearest random feature point in 1D
-- Creates sharp valleys between broad peaks — burst cluster pattern
-- ========================================
-- @return number: Noise value between 0 and 1
function Noise.worley1D(x, frequency, octaves, persistence, lacunarity, seed)
    frequency = frequency or 1.0
    octaves = octaves or 1
    persistence = persistence or 0.5
    lacunarity = lacunarity or 2.0
    seed = seed or 0

    local total = 0.0
    local amplitude = 1.0
    local maxValue = 0.0
    local freq = frequency

    for i = 1, octaves do
        local scaledX = x * freq
        local cell = math.floor(scaledX)

        -- Find minimum distance to feature points in neighboring cells
        local minDist = 1.0
        for offset = -1, 1 do
            local neighborCell = cell + offset
            -- Deterministic feature point position within cell (0-1)
            local rnd = pseudoRandom(neighborCell, seed + i)
            local featurePoint = neighborCell + (rnd + 1.0) * 0.5
            local dist = math.abs(scaledX - featurePoint)
            if dist < minDist then
                minDist = dist
            end
        end

        -- Invert: close to feature point = high value (peak)
        -- Clamp distance to [0,1] then invert
        local value = 1.0 - math.min(1.0, minDist * 2.0)

        total = total + value * amplitude
        maxValue = maxValue + amplitude

        amplitude = amplitude * persistence
        freq = freq * lacunarity
    end

    return math.max(0, math.min(1, total / maxValue))
end

-- ========================================
-- NOISE TYPE: SINE
-- Pure periodic sine wave — perfectly rhythmic pattern
-- Frequency = cycles per second, octaves add harmonics
-- ========================================
-- @return number: Noise value between 0 and 1
function Noise.sine1D(x, frequency, octaves, persistence, lacunarity, seed)
    frequency = frequency or 1.0
    octaves = octaves or 1
    persistence = persistence or 0.5
    lacunarity = lacunarity or 2.0
    seed = seed or 0

    local total = 0.0
    local amplitude = 1.0
    local maxValue = 0.0
    local freq = frequency

    for i = 1, octaves do
        -- Phase offset from seed for variety between different seeds
        local phase = pseudoRandom(i, seed) * math.pi

        local value = math.sin(2.0 * math.pi * x * freq + phase)

        total = total + value * amplitude
        maxValue = maxValue + amplitude

        amplitude = amplitude * persistence
        freq = freq * lacunarity
    end

    -- Normalize to 0-1 range
    return (total / maxValue + 1.0) * 0.5
end

-- ========================================
-- ROUTING: Get noise value by type
-- ========================================
-- @param noiseType number: Noise type constant (0=Perlin, 1=Ridged, 2=Worley, 3=Sine)
-- @return number: Noise value between 0 and 1
local function getNoiseByType(noiseType, x, frequency, octaves, persistence, lacunarity, seed)
    if noiseType == 1 then
        return Noise.ridged1D(x, frequency, octaves, persistence, lacunarity, seed)
    elseif noiseType == 2 then
        return Noise.worley1D(x, frequency, octaves, persistence, lacunarity, seed)
    elseif noiseType == 3 then
        return Noise.sine1D(x, frequency, octaves, persistence, lacunarity, seed)
    else
        return Noise.perlin1D(x, frequency, octaves, persistence, lacunarity, seed)
    end
end

-- Generate noise curve data for visualization
-- @param startTime number: Start time
-- @param endTime number: End time
-- @param sampleCount number: Number of samples
-- @param frequency number: Noise frequency
-- @param octaves number: Number of octaves
-- @param persistence number: Amplitude decrease per octave
-- @param lacunarity number: Frequency increase per octave
-- @param seed number: Random seed
-- @param noiseType number: Noise type (optional, default 0=Perlin)
-- @return table: Array of {time, value} pairs
function Noise.generateCurve(startTime, endTime, sampleCount, frequency, octaves, persistence, lacunarity, seed, noiseType)
    local duration = endTime - startTime
    local curve = {}
    noiseType = noiseType or 0

    for i = 0, sampleCount - 1 do
        local t = i / (sampleCount - 1)
        local time = startTime + t * duration

        -- Use absolute time (same as getValueAtTime)
        local timeInSeconds = time - startTime
        local noiseInput = timeInSeconds

        -- Get noise value at this time
        local value = getNoiseByType(noiseType, noiseInput, frequency, octaves, persistence, lacunarity, seed)

        table.insert(curve, {time = time, value = value})
    end

    return curve
end

-- Get noise value at specific time in timeline
-- @param time number: Time position
-- @param startTime number: Timeline start
-- @param endTime number: Timeline end
-- @param frequency number: Noise frequency
-- @param octaves number: Number of octaves
-- @param persistence number: Amplitude decrease per octave
-- @param lacunarity number: Frequency increase per octave
-- @param seed number: Random seed
-- @param noiseType number: Noise type (optional, default 0=Perlin)
-- @return number: Noise value between 0 and 1
function Noise.getValueAtTime(time, startTime, endTime, frequency, octaves, persistence, lacunarity, seed, noiseType)
    local duration = endTime - startTime
    if duration <= 0 then return 0.5 end

    local timeInSeconds = time - startTime
    local noiseInput = timeInSeconds
    noiseType = noiseType or 0

    return getNoiseByType(noiseType, noiseInput, frequency, octaves, persistence, lacunarity, seed)
end

return Noise
