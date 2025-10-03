--[[
@version 1.5
@noindex
Perlin Noise Generator for Ambiance Creator
Provides 1D Perlin noise generation with octaves for organic patterns
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

-- Generate Perlin noise value with multiple octaves
-- @param x number: Position
-- @param frequency number: Base frequency (larger = more variation)
-- @param octaves number: Number of noise layers (more = more detail)
-- @param persistence number: Amplitude decrease per octave (0-1, typical 0.5)
-- @param lacunarity number: Frequency increase per octave (typical 2.0)
-- @param seed number: Random seed for reproducibility
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

-- Generate noise curve data for visualization
-- @param startTime number: Start time
-- @param endTime number: End time
-- @param sampleCount number: Number of samples
-- @param frequency number: Noise frequency
-- @param octaves number: Number of octaves
-- @param persistence number: Amplitude decrease per octave
-- @param lacunarity number: Frequency increase per octave
-- @param seed number: Random seed
-- @return table: Array of {time, value} pairs
function Noise.generateCurve(startTime, endTime, sampleCount, frequency, octaves, persistence, lacunarity, seed)
    local duration = endTime - startTime
    local curve = {}

    for i = 0, sampleCount - 1 do
        local t = i / (sampleCount - 1)
        local time = startTime + t * duration

        -- Use absolute time (same as getValueAtTime)
        local timeInSeconds = time - startTime
        local noiseInput = timeInSeconds / 10.0  -- Normalize to 10-second units

        -- Get noise value at this time
        local value = Noise.perlin1D(noiseInput, frequency, octaves, persistence, lacunarity, seed)

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
-- @return number: Noise value between 0 and 1
function Noise.getValueAtTime(time, startTime, endTime, frequency, octaves, persistence, lacunarity, seed)
    local duration = endTime - startTime
    if duration <= 0 then return 0.5 end

    -- Use absolute time in seconds (not normalized)
    -- This makes frequency independent of timeline duration
    -- frequency = cycles per 10 seconds
    local timeInSeconds = time - startTime
    local noiseInput = timeInSeconds / 10.0  -- Normalize to 10-second units

    return Noise.perlin1D(noiseInput, frequency, octaves, persistence, lacunarity, seed)
end

return Noise
