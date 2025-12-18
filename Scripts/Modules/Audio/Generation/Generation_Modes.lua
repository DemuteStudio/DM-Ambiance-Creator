--[[
@version 1.0
@noindex
DM Ambiance Creator - Generation Modes Module
Special generation modes: Noise-based and Euclidean rhythm generation.
--]]

local Generation_Modes = {}
local globals = {}

-- Dependencies (set by aggregator)
local Generation_MultiChannel = nil
local Generation_ItemPlacement = nil

function Generation_Modes.initModule(g)
    globals = g
end

function Generation_Modes.setDependencies(multiChannel, itemPlacement)
    Generation_MultiChannel = multiChannel
    Generation_ItemPlacement = itemPlacement
end

-- ============================================================================
-- TRACK STRUCTURE DETERMINATION
-- ============================================================================

-- Determine track structure based on container configuration and item analysis
-- This function implements a priority-based rule system for track creation
function Generation_Modes.determineTrackStructure(container, itemsAnalysis)
    local outputChannels = Generation_MultiChannel.getOutputChannelCount(container.channelMode)
    local itemCh = itemsAnalysis.dominantChannelCount

    -- ═══════════════════════════════════════════════════════════
    -- RÈGLE 0 : Items mixtes → FORCE MONO
    -- ═══════════════════════════════════════════════════════════
    if not itemsAnalysis.isHomogeneous then
        return {
            strategy = "mixed-items-forced-mono",
            numTracks = outputChannels,
            trackType = "mono",
            trackChannels = 1,
            needsChannelSelection = true,
            channelSelectionMode = "mono",
            useDistribution = true,
            warning = "Mixed channel items detected - forcing mono channel selection"
        }
    end

    -- ═══════════════════════════════════════════════════════════
    -- RÈGLE 1 : Container vide → Structure par défaut
    -- ═══════════════════════════════════════════════════════════
    if itemsAnalysis.isEmpty then
        return {
            strategy = "empty-default",
            numTracks = 1,
            trackType = "multi",
            trackChannels = outputChannels,
            needsChannelSelection = false
        }
    end

    -- ═══════════════════════════════════════════════════════════
    -- RÈGLE 2 : Channel Selection Mode (get early for priority check)
    -- ═══════════════════════════════════════════════════════════
    local channelSelectionMode = container.channelSelectionMode or "none"

    -- ═══════════════════════════════════════════════════════════
    -- RÈGLE 3 : Match parfait → Passthrough (1 track)
    -- SAUF si l'utilisateur force explicitement Mono ou Stereo
    -- ═══════════════════════════════════════════════════════════
    if itemCh == outputChannels and channelSelectionMode == "none" then
        return {
            strategy = "perfect-match-passthrough",
            numTracks = 1,
            trackType = "multi",
            trackChannels = outputChannels,
            needsChannelSelection = false,
            itemsGoDirectly = true
        }
    end

    -- ═══════════════════════════════════════════════════════════
    -- RÈGLE 4 : Items MONO → Distribution sur N tracks mono
    -- ═══════════════════════════════════════════════════════════
    if itemCh == 1 then
        return {
            strategy = "mono-distribution",
            numTracks = outputChannels,
            trackType = "mono",
            trackChannels = 1,
            needsChannelSelection = false,
            useDistribution = true
        }
    end

    -- ═══════════════════════════════════════════════════════════
    -- À partir d'ici : itemCh > 1 et itemCh != outputChannels
    -- (ou itemCh == outputChannels avec mode explicite mono/stereo)
    -- → Besoin de Channel Selection (downmix/split)
    -- ═══════════════════════════════════════════════════════════

    -- ═══════════════════════════════════════════════════════════
    -- RÈGLE 4 : Channel Selection = STEREO
    -- ═══════════════════════════════════════════════════════════
    if channelSelectionMode == "stereo" then
        -- Vérifier que les items ont un nombre pair de channels
        if itemCh % 2 ~= 0 then
            return {
                strategy = "invalid-stereo-fallback-mono",
                numTracks = outputChannels,
                trackType = "mono",
                trackChannels = 1,
                needsChannelSelection = true,
                channelSelectionMode = "mono",
                useDistribution = true,
                warning = "Cannot split odd-channel items into stereo pairs - using mono"
            }
        end

        local numStereoPairs = itemCh / 2

        -- Cas : Container Stereo avec items multi-channel pairs
        if outputChannels == 2 then
            return {
                strategy = "stereo-pair-selection",
                numTracks = 1,
                trackType = "stereo",
                trackChannels = 2,
                needsChannelSelection = true,
                channelSelectionMode = "stereo",
                availableStereoPairs = numStereoPairs,
            }
        end

        -- Cas : Container Quad/5.0/7.0 avec items stereo
        if itemCh == 2 and outputChannels >= 4 then
            if outputChannels == 4 then
                return {
                    strategy = "stereo-pairs-quad",
                    numTracks = 2,
                    trackType = "stereo",
                    trackChannels = 2,
                    trackLabels = {"L+R", "LS+RS"},
                    needsChannelSelection = false,
                    useDistribution = true
                }
            elseif outputChannels >= 5 then
                return {
                    strategy = "stereo-pairs-surround",
                    numTracks = 2,
                    trackType = "stereo",
                    trackChannels = 2,
                    trackLabels = {"L+R", "LS+RS"},
                    needsChannelSelection = false,
                    useDistribution = true
                }
            end
        end

        -- Cas : Container multi avec items 2ch+ (allow upsampling if needed)
        if outputChannels >= 4 and numStereoPairs >= 1 then
            -- CORRECTED: Calculate target pairs correctly for odd/even channel formats
            -- Even formats (4.0): outputChannels / 2 = 2 pairs (L+R, LS+RS)
            -- Odd formats (5.0, 7.0): (outputChannels - 1) / 2 (skip center channel)
            --   5.0: (5-1)/2 = 2 pairs (L+R, LS+RS)
            --   7.0: (7-1)/2 = 3 pairs (L+R, LS+RS, LB+RB)
            local targetPairs
            if outputChannels % 2 == 0 then
                targetPairs = outputChannels / 2  -- Even channel formats
            else
                targetPairs = (outputChannels - 1) / 2  -- Odd channel formats (skip center)
            end

            -- Check if upsampling is needed (items have fewer pairs than needed)
            local needsUpsampling = numStereoPairs < targetPairs

            return {
                strategy = "split-stereo-pairs",
                numTracks = targetPairs,
                trackType = "stereo",
                trackChannels = 2,
                needsChannelSelection = true,
                channelSelectionMode = "split-stereo",
                trackLabels = Generation_MultiChannel.generateStereoPairLabels(itemCh, targetPairs),
                upsampling = needsUpsampling,
                availableStereoPairs = numStereoPairs,
            }
        end

        -- Fallback
        return Generation_MultiChannel.determineAutoOptimization(container, itemsAnalysis, outputChannels)
    end

    -- ═══════════════════════════════════════════════════════════
    -- RÈGLE 5 : Channel Selection = MONO
    -- ═══════════════════════════════════════════════════════════
    if channelSelectionMode == "mono" then
        -- Generate labels based on output channels
        local trackLabels
        if outputChannels == 2 then
            trackLabels = {"L", "R"}
        elseif outputChannels == 4 then
            trackLabels = {"L", "R", "LS", "RS"}
        elseif outputChannels >= 5 then
            -- 5.0/7.0: Use 4 tracks (L, R, LS, RS - skip center)
            trackLabels = {"L", "R", "LS", "RS"}
        end

        return {
            strategy = "split-to-mono",
            numTracks = outputChannels,
            trackType = "mono",
            trackChannels = 1,
            needsChannelSelection = true,
            channelSelectionMode = "mono",
            useDistribution = true,
            trackLabels = trackLabels,
        }
    end

    -- ═══════════════════════════════════════════════════════════
    -- RÈGLE 6 : Channel Selection = NONE (Auto-optimization)
    -- ═══════════════════════════════════════════════════════════
    return Generation_MultiChannel.determineAutoOptimization(container, itemsAnalysis, outputChannels)
end

-- ============================================================================
-- NOISE MODE GENERATION
-- ============================================================================

-- Place items using Noise mode (Perlin noise-based probability)
-- @param effectiveParams table: Effective parameters for generation
-- @param track MediaTrack: REAPER track to place items on
-- @param channelTracks table: Array of channel tracks (for multi-channel)
-- @param container table: Container object
-- @param trackStructure table: Track structure information
-- @param xfadeshape number: Crossfade shape
function Generation_Modes.placeItemsNoiseMode(effectiveParams, track, channelTracks, container, trackStructure, xfadeshape)
    if not effectiveParams.items or #effectiveParams.items == 0 then
        return
    end

    -- Ensure noise parameters exist (backwards compatibility)
    globals.Utils.ensureNoiseDefaults(effectiveParams)

    -- Validate noise parameters
    local isValid, errorMsg = globals.Utils.validateNoiseParams(effectiveParams)
    if not isValid then
        reaper.ShowConsoleMsg("ERROR: Invalid noise parameters - " .. errorMsg .. "\n")
        return
    end

    -- Calculate average item length (considering areas if they exist)
    local totalLength = 0
    local totalCount = 0
    for _, item in ipairs(effectiveParams.items) do
        if item.areas and #item.areas > 0 then
            -- If item has areas, count each area
            for _, area in ipairs(item.areas) do
                totalLength = totalLength + (area.endPos - area.startPos)
                totalCount = totalCount + 1
            end
        else
            -- No areas, use full item length
            totalLength = totalLength + item.length
            totalCount = totalCount + 1
        end
    end
    local avgItemLength = totalLength / math.max(1, totalCount)

    -- Helper function to get placement probability at a specific time (defined outside loop for performance)
    local function getPlacementProbability(time)
        local noiseValue = globals.Noise.getValueAtTime(
            time,
            globals.startTime,
            globals.endTime,
            effectiveParams.noiseFrequency,
            effectiveParams.noiseOctaves,
            effectiveParams.noisePersistence,
            effectiveParams.noiseLacunarity,
            effectiveParams.noiseSeed
        )

        -- Convert noise (0-1) to -1 to +1 range for variation
        local normalizedNoiseValue = (noiseValue - 0.5) * 2

        -- Calculate base density (0-1)
        local baseDensity = effectiveParams.noiseDensity / 100.0

        -- Apply amplitude modulation (how much noise affects density)
        local amplitudeScale = effectiveParams.noiseAmplitude / 100.0
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
            globals.startTime,
            globals.endTime,
            effectiveParams.noiseFrequency * 1.13,
            1,  -- Single octave
            0.5,
            2.0,
            effectiveParams.noiseSeed + seedOffset
        )
    end

    -- Get algorithm mode (default to PROBABILITY for backwards compatibility)
    local algorithm = effectiveParams.noiseAlgorithm or globals.Constants.NOISE_ALGORITHMS.PROBABILITY
    local Constants = globals.Constants
    local noiseGen = Constants.NOISE_GENERATION
    local minDensityThreshold = effectiveParams.noiseThreshold / 100.0

    -- Collection of item placement times (calculated by selected algorithm)
    local placementTimes = {}

    -- ========================================
    -- ALGORITHM 1: PROBABILITY
    -- Probability test at intervals with timing jitter
    -- ========================================
    if algorithm == Constants.NOISE_ALGORITHMS.PROBABILITY then
        local currentTime = globals.startTime
        local baseInterval = 1.0 / math.max(0.01, effectiveParams.noiseFrequency)

        while currentTime < globals.endTime do
            local placementProbability = getPlacementProbability(currentTime)

            -- Check if probability meets threshold
            if placementProbability >= minDensityThreshold then
                -- Use deterministic random value to decide placement
                local decisionNoise = getDecisionNoise(currentTime, 54321)

                -- Place item if decision noise falls within placement probability
                if decisionNoise <= placementProbability then
                    -- Add timing jitter to avoid perfectly regular placement
                    -- Use another noise value for jitter amount
                    local jitterNoise = getDecisionNoise(currentTime, 11111)
                    -- Jitter is ±25% of the interval
                    local jitter = (jitterNoise - 0.5) * 0.5 * baseInterval
                    local placementTime = currentTime + jitter

                    -- Ensure we don't place outside bounds
                    if placementTime >= globals.startTime and placementTime < globals.endTime then
                        table.insert(placementTimes, placementTime)
                    end
                end
            end

            currentTime = currentTime + baseInterval
        end

    -- ========================================
    -- ALGORITHM 2: ACCUMULATION
    -- Accumulate probability until threshold is reached
    -- ========================================
    elseif algorithm == Constants.NOISE_ALGORITHMS.ACCUMULATION then
        local currentTime = globals.startTime
        local sampleInterval = 1.0 / math.max(0.01, effectiveParams.noiseFrequency * 10)  -- Fine sampling
        local accumulated = 0.0

        while currentTime < globals.endTime do
            local placementProbability = getPlacementProbability(currentTime)

            if placementProbability >= minDensityThreshold then
                -- Accumulate probability weighted by frequency and time step
                local rate = placementProbability * effectiveParams.noiseFrequency
                accumulated = accumulated + (rate * sampleInterval)

                -- When accumulated probability >= 1.0, place item and reset
                if accumulated >= 1.0 then
                    table.insert(placementTimes, currentTime)
                    accumulated = accumulated - 1.0
                end
            else
                -- Below threshold: decay accumulated probability
                accumulated = accumulated * 0.9
            end

            currentTime = currentTime + sampleInterval
        end
    end

    -- ========================================
    -- ITEM PLACEMENT
    -- Place items at all calculated times
    -- ========================================
    for _, currentTime in ipairs(placementTimes) do
        if currentTime >= globals.endTime then
            break
        end

        -- Select item deterministically using noise-based index
        local selectionNoise = globals.Noise.getValueAtTime(
            currentTime + noiseGen.SELECTION_TIME_OFFSET,
            globals.startTime,
            globals.endTime,
            effectiveParams.noiseFrequency * noiseGen.SELECTION_FREQ_MULT,
            1,  -- Single octave for selection
            0.5,
            2.0,
            effectiveParams.noiseSeed + noiseGen.SELECTION_SEED_OFFSET
        )
        local randomItemIndex = math.floor(selectionNoise * #effectiveParams.items) + 1
        randomItemIndex = math.max(1, math.min(#effectiveParams.items, randomItemIndex))

        local originalItemData = effectiveParams.items[randomItemIndex]

        -- Select area deterministically if areas exist
        local itemData
        if originalItemData.areas and #originalItemData.areas > 0 then
            local areaNoise = globals.Noise.getValueAtTime(
                currentTime + noiseGen.AREA_TIME_OFFSET,
                globals.startTime,
                globals.endTime,
                effectiveParams.noiseFrequency * noiseGen.AREA_FREQ_MULT,
                1,
                0.5,
                2.0,
                effectiveParams.noiseSeed + noiseGen.AREA_SEED_OFFSET
            )
            local areaIndex = math.floor(areaNoise * #originalItemData.areas) + 1
            areaIndex = math.max(1, math.min(#originalItemData.areas, areaIndex))

            local selectedArea = originalItemData.areas[areaIndex]
            itemData = {}
            for k, v in pairs(originalItemData) do
                itemData[k] = v
            end
            itemData.startOffset = selectedArea.startPos
            itemData.length = selectedArea.endPos - selectedArea.startPos
            itemData.originalLength = originalItemData.length
            itemData.selectedArea = selectedArea
        else
            itemData = originalItemData
        end

        -- Determine target track(s)
            local targetTracks = {track}
            if channelTracks and #channelTracks > 1 then
                -- For multi-channel, use distribution mode
                local distributionMode = container.itemDistributionMode or 0
                if distributionMode == 0 then
                    -- Round-robin
                    if not container.distributionCounter then
                        container.distributionCounter = 0
                    end
                    container.distributionCounter = container.distributionCounter + 1
                    local targetChannel = ((container.distributionCounter - 1) % #channelTracks) + 1
                    targetTracks = {channelTracks[targetChannel]}
                elseif distributionMode == 1 then
                    -- Random
                    local targetChannel = math.random(1, #channelTracks)
                    targetTracks = {channelTracks[targetChannel]}
                end
            end

            -- Place item on target track(s)
            for _, targetTrack in ipairs(targetTracks) do
                -- Create and configure the new item
                local newItem = reaper.AddMediaItemToTrack(targetTrack)
                local newTake = reaper.AddTakeToMediaItem(newItem)

                -- Configure the item
                local PCM_source = reaper.PCM_Source_CreateFromFile(itemData.filePath)
                reaper.SetMediaItemTake_Source(newTake, PCM_source)
                reaper.SetMediaItemTakeInfo_Value(newTake, "D_STARTOFFS", itemData.startOffset)

                -- Trim item so it never exceeds the selection end
                local maxLen = globals.endTime - currentTime
                local actualLen = math.min(itemData.length, maxLen)

                -- Pre-calculate pitch and adjust length if using STRETCH mode
                local randomPitch = nil
                local playrate = nil
                if effectiveParams.pitchMode == Constants.PITCH_MODES.STRETCH then
                    if effectiveParams.randomizePitch then
                        randomPitch = itemData.originalPitch + globals.Utils.randomInRange(effectiveParams.pitchRange.min, effectiveParams.pitchRange.max)
                    else
                        randomPitch = itemData.originalPitch
                    end
                    playrate = globals.Utils.semitonesToPlayrate(randomPitch)

                    -- Adjust length for playrate (slower playrate = longer item)
                    actualLen = actualLen / playrate
                    actualLen = math.min(actualLen, maxLen)  -- Re-clamp to timeline bounds
                end

                reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", currentTime)
                reaper.GetSetMediaItemTakeInfo_String(newTake, "P_NAME", itemData.name, true)

                -- Apply randomizations
                if effectiveParams.randomizePitch then
                    if effectiveParams.pitchMode == Constants.PITCH_MODES.STRETCH then
                        -- Use time stretch (D_PLAYRATE) - already calculated above
                        reaper.SetMediaItemTakeInfo_Value(newTake, "D_PLAYRATE", playrate)
                        reaper.SetMediaItemTakeInfo_Value(newTake, "B_PPITCH", 0)  -- Disable preserve pitch for stretch mode
                    else
                        local pitchValue = itemData.originalPitch + globals.Utils.randomInRange(effectiveParams.pitchRange.min, effectiveParams.pitchRange.max)
                        reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", pitchValue)
                    end
                else
                    if effectiveParams.pitchMode == Constants.PITCH_MODES.STRETCH then
                        -- Use time stretch (D_PLAYRATE) - already calculated above
                        reaper.SetMediaItemTakeInfo_Value(newTake, "D_PLAYRATE", playrate)
                        reaper.SetMediaItemTakeInfo_Value(newTake, "B_PPITCH", 0)  -- Disable preserve pitch for stretch mode
                    else
                        reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", itemData.originalPitch)
                    end
                end

                -- Set D_LENGTH with adjusted value (after playrate adjustment if STRETCH mode)
                reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH", actualLen)

                -- Apply gain
                local gainDB = itemData.gainDB or 0.0
                local gainScale = 10 ^ (gainDB / 20)

                if effectiveParams.randomizeVolume then
                    local randomVolume = itemData.originalVolume * gainScale * 10^(globals.Utils.randomInRange(effectiveParams.volumeRange.min, effectiveParams.volumeRange.max) / 20)
                    reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", randomVolume)
                else
                    reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", itemData.originalVolume * gainScale)
                end

                -- Apply pan for stereo items
                local canUsePan = false
                if not effectiveParams.channelMode or effectiveParams.channelMode == 0 then
                    canUsePan = true
                elseif trackStructure and trackStructure.trackType == "stereo" and trackStructure.trackChannels == 2 then
                    canUsePan = true
                end

                if effectiveParams.randomizePan and canUsePan then
                    local randomPan = itemData.originalPan - globals.Utils.randomInRange(effectiveParams.panRange.min, effectiveParams.panRange.max) / 100
                    randomPan = math.max(-1, math.min(1, randomPan))
                    globals.Items.createTakePanEnvelope(newTake, randomPan)
                end

                -- Apply fades
                if effectiveParams.fadeInEnabled then
                    local fadeInDuration = effectiveParams.fadeInDuration or 0.1
                    if effectiveParams.fadeInUsePercentage then
                        fadeInDuration = (fadeInDuration / 100) * actualLen
                    end
                    fadeInDuration = math.min(fadeInDuration, actualLen)

                    reaper.SetMediaItemInfo_Value(newItem, "D_FADEINLEN", fadeInDuration)
                    reaper.SetMediaItemInfo_Value(newItem, "C_FADEINSHAPE", effectiveParams.fadeInShape or 0)
                    reaper.SetMediaItemInfo_Value(newItem, "D_FADEINDIR", effectiveParams.fadeInCurve or 0.0)
                end

                if effectiveParams.fadeOutEnabled then
                    local fadeOutDuration = effectiveParams.fadeOutDuration or 0.1
                    if effectiveParams.fadeOutUsePercentage then
                        fadeOutDuration = (fadeOutDuration / 100) * actualLen
                    end
                    fadeOutDuration = math.min(fadeOutDuration, actualLen)

                    reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTLEN", fadeOutDuration)
                    reaper.SetMediaItemInfo_Value(newItem, "C_FADEOUTSHAPE", effectiveParams.fadeOutShape or 0)
                    reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTDIR", effectiveParams.fadeOutCurve or 0.0)
                end
            end
    end
end

-- ============================================================================
-- EUCLIDEAN MODE GENERATION
-- ============================================================================

-- Place items using Euclidean Rhythm mode
function Generation_Modes.placeItemsEuclideanMode(effectiveParams, track, channelTracks, container, trackStructure, xfadeshape)
    if not effectiveParams.items or #effectiveParams.items == 0 then
        return
    end

    local Constants = globals.Constants
    local Utils = globals.Utils
    local Items = globals.Items

    -- Get parameters with defaults
    local mode = effectiveParams.euclideanMode or 0
    local useProjectTempo = effectiveParams.euclideanUseProjectTempo or false
    local tempo = effectiveParams.euclideanTempo or 120
    local layers = effectiveParams.euclideanLayers

    -- Ensure we have at least one layer
    if not layers or #layers == 0 then
        layers = {{pulses = 8, steps = 16, rotation = 0}}
    end

    -- Use shared utility function to combine euclidean layers
    local combinedPattern, lcmSteps = Utils.combineEuclideanLayers(layers)

    -- Place items according to combined pattern
    local itemIndex = 0
    local currentTime = globals.startTime

    while currentTime < globals.endTime do
        for stepIdx = 1, lcmSteps do
            local placementTime

            -- Calculate placement time based on mode
            if mode == 0 then
                -- Tempo-Based mode
                if useProjectTempo then
                    -- Use project tempo at current position (supports tempo changes)
                    -- Calculate beat position for each step
                    local beatStart = reaper.TimeMap2_timeToQN(0, currentTime)
                    local beatOffset = (stepIdx - 1) * (4.0 / lcmSteps)  -- Fraction of 4 beats
                    local targetBeat = beatStart + beatOffset
                    placementTime = reaper.TimeMap2_QNToTime(0, targetBeat)
                else
                    -- Use fixed tempo
                    local stepDuration = (60.0 / tempo) * 4 / lcmSteps  -- Assuming 4/4 time
                    placementTime = currentTime + (stepIdx - 1) * stepDuration
                end
            else
                -- Fit-to-Selection mode: stretch pattern to fit time selection exactly once
                local duration = globals.endTime - globals.startTime
                local stepDuration = duration / lcmSteps
                placementTime = currentTime + (stepIdx - 1) * stepDuration
            end

            -- Stop if we exceed time selection
            if placementTime >= globals.endTime then
                break
            end

            if combinedPattern[stepIdx] then

                -- Select item (cycle through available items)
                itemIndex = (itemIndex % #effectiveParams.items) + 1
                local originalItemData = effectiveParams.items[itemIndex]

                -- Handle areas if present
                local itemData
                if originalItemData.areas and #originalItemData.areas > 0 then
                    local areaIndex = math.random(1, #originalItemData.areas)
                    local selectedArea = originalItemData.areas[areaIndex]
                    itemData = {}
                    for k, v in pairs(originalItemData) do
                        itemData[k] = v
                    end
                    itemData.startOffset = selectedArea.startPos
                    itemData.length = selectedArea.endPos - selectedArea.startPos
                    itemData.originalLength = originalItemData.length
                    itemData.selectedArea = selectedArea
                else
                    itemData = originalItemData
                end

                -- Determine target track(s)
                local targetTracks = {track}
                if channelTracks and #channelTracks > 1 then
                    local distributionMode = container.itemDistributionMode or 0
                    if distributionMode == 0 then
                        -- Round-robin
                        if not container.distributionCounter then
                            container.distributionCounter = 0
                        end
                        container.distributionCounter = container.distributionCounter + 1
                        local targetChannel = ((container.distributionCounter - 1) % #channelTracks) + 1
                        targetTracks = {channelTracks[targetChannel]}
                    elseif distributionMode == 1 then
                        -- Random
                        local targetChannel = math.random(1, #channelTracks)
                        targetTracks = {channelTracks[targetChannel]}
                    end
                end

                -- Place item on target track(s)
                for _, targetTrack in ipairs(targetTracks) do
                    local newItem = reaper.AddMediaItemToTrack(targetTrack)
                    local newTake = reaper.AddTakeToMediaItem(newItem)

                    local PCM_source = reaper.PCM_Source_CreateFromFile(itemData.filePath)
                    reaper.SetMediaItemTake_Source(newTake, PCM_source)
                    reaper.SetMediaItemTakeInfo_Value(newTake, "D_STARTOFFS", itemData.startOffset)

                    local maxLen = globals.endTime - placementTime
                    local actualLen = math.min(itemData.length, maxLen)

                    -- Pre-calculate pitch and adjust length if using STRETCH mode
                    local randomPitch = nil
                    local playrate = nil
                    if effectiveParams.pitchMode == Constants.PITCH_MODES.STRETCH then
                        if effectiveParams.randomizePitch then
                            randomPitch = itemData.originalPitch + Utils.randomInRange(effectiveParams.pitchRange.min, effectiveParams.pitchRange.max)
                        else
                            randomPitch = itemData.originalPitch
                        end
                        playrate = Utils.semitonesToPlayrate(randomPitch)

                        -- Adjust length for playrate (slower playrate = longer item)
                        actualLen = actualLen / playrate
                        actualLen = math.min(actualLen, maxLen)  -- Re-clamp to timeline bounds
                    end

                    reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", placementTime)
                    reaper.GetSetMediaItemTakeInfo_String(newTake, "P_NAME", itemData.name, true)

                    -- Apply randomizations
                    if effectiveParams.randomizePitch then
                        if effectiveParams.pitchMode == Constants.PITCH_MODES.STRETCH then
                            -- Use time stretch (D_PLAYRATE) - already calculated above
                            reaper.SetMediaItemTakeInfo_Value(newTake, "D_PLAYRATE", playrate)
                            reaper.SetMediaItemTakeInfo_Value(newTake, "B_PPITCH", 0)
                        else
                            local pitchValue = itemData.originalPitch + Utils.randomInRange(effectiveParams.pitchRange.min, effectiveParams.pitchRange.max)
                            reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", pitchValue)
                        end
                    else
                        if effectiveParams.pitchMode == Constants.PITCH_MODES.STRETCH then
                            -- Use time stretch (D_PLAYRATE) - already calculated above
                            reaper.SetMediaItemTakeInfo_Value(newTake, "D_PLAYRATE", playrate)
                            reaper.SetMediaItemTakeInfo_Value(newTake, "B_PPITCH", 0)
                        else
                            reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", itemData.originalPitch)
                        end
                    end

                    -- Set D_LENGTH with adjusted value (after playrate adjustment if STRETCH mode)
                    reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH", actualLen)

                    local gainDB = itemData.gainDB or 0.0
                    local gainScale = 10 ^ (gainDB / 20)

                    if effectiveParams.randomizeVolume then
                        local randomVolume = itemData.originalVolume * gainScale * 10^(Utils.randomInRange(effectiveParams.volumeRange.min, effectiveParams.volumeRange.max) / 20)
                        reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", randomVolume)
                    else
                        reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", itemData.originalVolume * gainScale)
                    end

                    local canUsePan = false
                    if not effectiveParams.channelMode or effectiveParams.channelMode == 0 then
                        canUsePan = true
                    elseif trackStructure and trackStructure.trackType == "stereo" and trackStructure.trackChannels == 2 then
                        canUsePan = true
                    end

                    if effectiveParams.randomizePan and canUsePan then
                        local randomPan = itemData.originalPan - Utils.randomInRange(effectiveParams.panRange.min, effectiveParams.panRange.max) / 100
                        randomPan = math.max(-1, math.min(1, randomPan))
                        Items.createTakePanEnvelope(newTake, randomPan)
                    end

                    -- Apply fades
                    if effectiveParams.fadeInEnabled then
                        local fadeInDuration = effectiveParams.fadeInDuration or 0.1
                        if effectiveParams.fadeInUsePercentage then
                            fadeInDuration = (fadeInDuration / 100) * actualLen
                        end
                        fadeInDuration = math.min(fadeInDuration, actualLen)
                        reaper.SetMediaItemInfo_Value(newItem, "D_FADEINLEN", fadeInDuration)
                        reaper.SetMediaItemInfo_Value(newItem, "C_FADEINSHAPE", effectiveParams.fadeInShape or 0)
                        reaper.SetMediaItemInfo_Value(newItem, "D_FADEINDIR", effectiveParams.fadeInCurve or 0.0)
                    end

                    if effectiveParams.fadeOutEnabled then
                        local fadeOutDuration = effectiveParams.fadeOutDuration or 0.1
                        if effectiveParams.fadeOutUsePercentage then
                            fadeOutDuration = (fadeOutDuration / 100) * actualLen
                        end
                        fadeOutDuration = math.min(fadeOutDuration, actualLen)
                        reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTLEN", fadeOutDuration)
                        reaper.SetMediaItemInfo_Value(newItem, "C_FADEOUTSHAPE", effectiveParams.fadeOutShape or 0)
                        reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTDIR", effectiveParams.fadeOutCurve or 0.0)
                    end
                end
            end
        end

        -- Advance to next pattern repetition (only for Tempo-Based mode)
        if mode == 0 then
            if useProjectTempo then
                -- Use project tempo: advance by musical beats
                local beatStart = reaper.TimeMap2_timeToQN(0, currentTime)
                local targetBeat = beatStart + 4.0  -- Advance by 4 beats (one bar)
                currentTime = reaper.TimeMap2_QNToTime(0, targetBeat)
            else
                -- Use fixed tempo
                local stepDuration = (60.0 / tempo) * 4 / lcmSteps
                currentTime = currentTime + lcmSteps * stepDuration
            end
        else
            -- Fit mode: only one repetition
            break
        end
    end
end

return Generation_Modes
