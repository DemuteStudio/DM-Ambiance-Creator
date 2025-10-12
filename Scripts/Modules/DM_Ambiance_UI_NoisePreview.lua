--[[
@version 1.3
@noindex
--]]

local NoisePreview = {}
local globals = {}

function NoisePreview.initModule(g)
    globals = g
end

-- Draw noise preview visualization
-- @param dataObj table: Container or group object with noise parameters
-- @param width number: Width of preview area
-- @param height number: Height of preview area
function NoisePreview.draw(dataObj, width, height)
    -- Ensure noise parameters exist (for backwards compatibility with old presets)
    local noiseSeed = dataObj.noiseSeed or math.random(1, 999999)
    local noiseFrequency = dataObj.noiseFrequency or 1.0
    local noiseAmplitude = dataObj.noiseAmplitude or 100.0
    local noiseOctaves = dataObj.noiseOctaves or 2
    local noisePersistence = dataObj.noisePersistence or 0.5
    local noiseLacunarity = dataObj.noiseLacunarity or 2.0
    local noiseDensity = dataObj.noiseDensity or 50.0
    local noiseThreshold = dataObj.noiseThreshold or 0.0

    local imgui = globals.imgui
    local drawList = imgui.GetWindowDrawList(globals.ctx)
    local cursorX, cursorY = imgui.GetCursorScreenPos(globals.ctx)

    -- Background
    local bgColor = 0x202020FF
    imgui.DrawList_AddRectFilled(drawList, cursorX, cursorY, cursorX + width, cursorY + height, bgColor)

    -- Border
    local borderColor = 0x666666FF
    imgui.DrawList_AddRect(drawList, cursorX, cursorY, cursorX + width, cursorY + height, borderColor)

    -- Use time selection if available, otherwise use 60 seconds preview
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
    -- This simulates the same algorithm used in DM_Ambiance_Generation.lua
    local itemPositions = {}

    -- Calculate duration and adaptive max positions
    local duration = endTime - startTime
    local maxPositions = math.min(5000, math.ceil(duration * noiseFrequency * 5))  -- Adaptive limit based on expected density

    -- Helper function to get placement probability at a specific time (same as generation)
    local function getPlacementProbability(time)
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

        -- Convert noise (0-1) to -1 to +1 range for variation
        local normalizedNoiseValue = (noiseValue - 0.5) * 2

        -- Calculate base density (0-1)
        local baseDensity = noiseDensity / 100.0

        -- Apply amplitude modulation (how much noise affects density)
        local densityVariation = normalizedNoiseValue * amplitudeScale

        -- Final probability = base density + variation
        local placementProbability = baseDensity + densityVariation

        -- Clamp to 0-1 range
        return math.max(0, math.min(1, placementProbability))
    end

    -- Helper function to generate deterministic random value for decisions
    local function getDecisionNoise(time, seedOffset)
        return globals.Noise.getValueAtTime(
            time + 0.789,
            startTime,
            endTime,
            noiseFrequency * 1.13,
            1,  -- Single octave
            0.5,
            2.0,
            noiseSeed + seedOffset
        )
    end

    -- Get algorithm mode from dataObj (default to PROBABILITY)
    local algorithm = dataObj.noiseAlgorithm or globals.Constants.NOISE_ALGORITHMS.PROBABILITY
    local Constants = globals.Constants

    -- ALGORITHM 1: PROBABILITY
    if algorithm == Constants.NOISE_ALGORITHMS.PROBABILITY then
        local currentTime = startTime
        local baseInterval = 1.0 / math.max(0.01, noiseFrequency)

        while currentTime < endTime and #itemPositions < maxPositions do
            local placementProbability = getPlacementProbability(currentTime)

            if placementProbability >= thresholdNormalized then
                local decisionNoise = getDecisionNoise(currentTime, 54321)
                if decisionNoise <= placementProbability then
                    -- Add timing jitter to avoid perfectly regular placement
                    local jitterNoise = getDecisionNoise(currentTime, 11111)
                    local jitter = (jitterNoise - 0.5) * 0.5 * baseInterval
                    local placementTime = currentTime + jitter

                    -- Ensure we don't place outside bounds
                    if placementTime >= startTime and placementTime < endTime then
                        table.insert(itemPositions, placementTime)
                    end
                end
            end

            currentTime = currentTime + baseInterval
        end

    -- ALGORITHM 2: ACCUMULATION
    elseif algorithm == Constants.NOISE_ALGORITHMS.ACCUMULATION then
        local currentTime = startTime
        local sampleInterval = 1.0 / math.max(0.01, noiseFrequency * 10)
        local accumulated = 0.0
        local iterationCount = 0
        local maxIterations = math.min(50000, math.ceil(duration / sampleInterval))  -- Limit iterations, not placements

        while currentTime < endTime and iterationCount < maxIterations do
            local placementProbability = getPlacementProbability(currentTime)

            if placementProbability >= thresholdNormalized then
                local rate = placementProbability * noiseFrequency
                accumulated = accumulated + (rate * sampleInterval)

                if accumulated >= 1.0 then
                    table.insert(itemPositions, currentTime)
                    accumulated = accumulated - 1.0
                end
            else
                accumulated = accumulated * 0.9
            end

            currentTime = currentTime + sampleInterval
            iterationCount = iterationCount + 1
        end
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

    for _, itemTime in ipairs(itemPositions) do
        -- Convert time to screen X coordinate
        local normalizedTime = (itemTime - startTime) / duration
        local markerX = cursorX + normalizedTime * width
        local markerY = cursorY + height - 5  -- Near bottom of preview

        -- Draw circle marker
        imgui.DrawList_AddCircleFilled(drawList, markerX, markerY, markerRadius, markerColor)
    end

    -- Draw time markers
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

return NoisePreview
