--[[
@version 1.5
@noindex
--]]

-- Multi-Channel Configuration UI for Container
-- Extracted from DM_Ambiance_UI_Container.lua
-- Handles channel mode, stereo pairs, mono channel, distribution, and channel volumes

local Container_ChannelConfig = {}
local globals = {}
local Constants = require("DM_Ambiance_Constants")

function Container_ChannelConfig.initModule(g)
    globals = g
end

-- Draw the multi-channel configuration section
-- Parameters:
--   container: The container object
--   containerId: Unique ID string for widget IDs
--   groupPath: Path to the parent group
--   containerIndex: Index of the container
--   width: Available width for the UI
function Container_ChannelConfig.draw(container, containerId, groupPath, containerIndex, width)
    local imgui = globals.imgui

    -- Multi-Channel Configuration header
    imgui.Separator(globals.ctx)
    imgui.Text(globals.ctx, "Multi-Channel Configuration")
    imgui.Separator(globals.ctx)

    -- Initialize values if needed (with migration from old system)
    if container.channelMode == nil then container.channelMode = 0 end
    if container.itemDistributionMode == nil then container.itemDistributionMode = 0 end

    -- Migrate from old downmixMode to new channelSelectionMode
    if container.downmixMode ~= nil and container.channelSelectionMode == nil then
        if container.downmixMode == 0 then
            container.channelSelectionMode = "none"
        elseif container.downmixMode == 1 then
            container.channelSelectionMode = "stereo"
            container.stereoPairSelection = container.downmixChannel or 0
        elseif container.downmixMode == 2 then
            container.channelSelectionMode = "mono"
            container.monoChannelSelection = container.downmixChannel or 0
        end
        container.downmixMode = nil
        container.downmixChannel = nil
    end

    -- Default to "none" (auto) if not set
    if container.channelSelectionMode == nil then
        container.channelSelectionMode = "none"
    end
    if container.stereoPairSelection == nil then
        container.stereoPairSelection = 0
    end
    if container.monoChannelSelection == nil then
        container.monoChannelSelection = 0
    end

    -- Analyze items for preview (before UI rendering)
    local itemsAnalysis = nil
    local trackStructure = nil
    if container.items and #container.items > 0 then
        itemsAnalysis = globals.Generation.analyzeContainerItems(container)
        trackStructure = globals.Generation.determineTrackStructure(container, itemsAnalysis)
    end

    -- Layout: Left column (controls) + Right column (preview)
    local leftColumnWidth = width * 0.55
    local rightColumnWidth = width * 0.42

    -- Begin left column (in a child window for independent scrolling if needed)
    imgui.BeginGroup(globals.ctx)

    -- Define label column width for alignment
    local labelWidth = 120
    local comboWidth = leftColumnWidth - labelWidth - 8

    -- Build channel mode items
    local channelModeItems = ""
    for i = 0, 3 do
        local config = globals.Constants.CHANNEL_CONFIGS[i]
        if config then
            channelModeItems = channelModeItems .. config.name .. "\0"
        end
    end

    -- Output Format
    imgui.Text(globals.ctx, "Output Format:")
    imgui.SameLine(globals.ctx, labelWidth)
    imgui.PushItemWidth(globals.ctx, comboWidth)
    local rv, newMode = globals.UndoWrappers.Combo(globals.ctx, "##ChannelMode_" .. containerId, container.channelMode, channelModeItems)
    if imgui.IsItemHovered(globals.ctx) then
        imgui.SetTooltip(globals.ctx, "Output channel configuration for this container.\nDetermines how many channels the final output will have.\n\nStereo: 2 channels (L, R)\n4.0: 4 channels (L, R, LS, RS)\n5.0: 5 channels (L, R, C, LS, RS)\n7.0: 7 channels (L, R, C, LS, RS, LB, RB)")
    end
    if rv and newMode ~= container.channelMode then
        container.channelMode = newMode
        container.needsRegeneration = true
        container.channelVolumes = {}
        if newMode > 0 then
            container.randomizePan = false
        end
    end
    imgui.PopItemWidth(globals.ctx)

    -- Channel Order (Variant) - only for 5.0/7.0
    if container.channelMode > 0 then
        local config = globals.Constants.CHANNEL_CONFIGS[container.channelMode]
        if config and config.hasVariants then
            imgui.Text(globals.ctx, "Output Variant:")
            imgui.SameLine(globals.ctx, labelWidth)

            local variantItems = ""
            for i = 0, 1 do
                if config.variants[i] then
                    variantItems = variantItems .. config.variants[i].name .. "\0"
                end
            end

            if container.channelVariant == nil then
                container.channelVariant = 0
            end

            imgui.PushItemWidth(globals.ctx, comboWidth)
            local rvVar, newVariant = globals.UndoWrappers.Combo(globals.ctx, "##ChannelVariant_" .. containerId, container.channelVariant, variantItems)
            if imgui.IsItemHovered(globals.ctx) then
                imgui.SetTooltip(globals.ctx, "Channel order variant for OUTPUT tracks.\n\nITU/Dolby: L R C LS RS (Center at channel 3)\nSMPTE: L C R LS RS (Center at channel 2)\n\nThis defines where the center channel is positioned\nin the output track structure.")
            end
            if rvVar then
                container.channelVariant = newVariant
                container.needsRegeneration = true
                container.channelVolumes = {}
            end
            imgui.PopItemWidth(globals.ctx)
        end
    end

    -- Channel Selection Mode
    imgui.Text(globals.ctx, "Channel Selection:")
    imgui.SameLine(globals.ctx, labelWidth)

    -- Build channel selection options
    local selectionModeItems = "Auto Optimize\0Stereo Pairs\0Mono Split\0"
    local selectionModeIndex = 0
    if container.channelSelectionMode == "none" then selectionModeIndex = 0
    elseif container.channelSelectionMode == "stereo" then selectionModeIndex = 1
    elseif container.channelSelectionMode == "mono" then selectionModeIndex = 2
    end

    imgui.PushItemWidth(globals.ctx, comboWidth)
    local selChanged, newSelMode = globals.UndoWrappers.Combo(globals.ctx, "##ChannelSelection_" .. containerId, selectionModeIndex, selectionModeItems)
    if imgui.IsItemHovered(globals.ctx) then
        imgui.SetTooltip(globals.ctx, "How to handle items with different channel counts.\n\nAuto Optimize: Automatically choose the best routing\nbased on item channels vs output format.\n\nStereo Pairs: Extract a specific stereo pair from\nmultichannel items (e.g., Ch 1-2, Ch 3-4).\n\nMono Split: Extract a single channel from items\nand distribute across output tracks.")
    end
    if selChanged then
        if newSelMode == 0 then container.channelSelectionMode = "none"
        elseif newSelMode == 1 then container.channelSelectionMode = "stereo"
        elseif newSelMode == 2 then container.channelSelectionMode = "mono"
        end
        container.needsRegeneration = true
    end
    imgui.PopItemWidth(globals.ctx)

    -- === Stereo Pair Settings (visible if channelSelectionMode == "stereo") ===
    if container.channelSelectionMode == "stereo" then
        Container_ChannelConfig.drawStereoPairSettings(container, containerId, labelWidth, comboWidth)
    end

    -- === Mono Channel Settings (visible if channelSelectionMode == "mono") ===
    if container.channelSelectionMode == "mono" then
        Container_ChannelConfig.drawMonoChannelSettings(container, containerId, labelWidth, comboWidth)
    end

    -- Distribution (only for multichannel + mono items)
    if container.channelMode > 0 then
        imgui.Text(globals.ctx, "Item Distribution:")
        imgui.SameLine(globals.ctx, labelWidth)

        imgui.PushItemWidth(globals.ctx, comboWidth)
        local distChanged, newDist = globals.UndoWrappers.Combo(globals.ctx, "##ItemDistribution_" .. containerId, container.itemDistributionMode, "Round-robin\0Random\0All tracks\0")
        if imgui.IsItemHovered(globals.ctx) then
            imgui.SetTooltip(globals.ctx, "How to distribute mono items across output tracks.\n\nRound-robin: Cycle through tracks sequentially\n(item1→L, item2→R, item3→LS, item4→RS, repeat)\n\nRandom: Place each item on a random track\n\nAll tracks: Generate independently on ALL tracks\n(each track gets its own timeline with all parameters)")
        end
        if distChanged then
            container.itemDistributionMode = newDist
            container.needsRegeneration = true
        end
        imgui.PopItemWidth(globals.ctx)
    end

    -- Source Format dropdown (if needed for 5.0/7.0 items)
    if trackStructure and trackStructure.needsSourceVariant then
        imgui.Text(globals.ctx, "Source Format:")
        imgui.SameLine(globals.ctx, labelWidth)

        local sourceFormatItems = "Unknown\0ITU/Dolby\0SMPTE\0"
        local currentIndex = 0
        if container.sourceChannelVariant == nil then
            currentIndex = 0
        elseif container.sourceChannelVariant == 0 then
            currentIndex = 1
        elseif container.sourceChannelVariant == 1 then
            currentIndex = 2
        end

        imgui.PushItemWidth(globals.ctx, comboWidth)
        local sfChanged, newIndex = globals.UndoWrappers.Combo(globals.ctx, "##SourceFormat_" .. containerId, currentIndex, sourceFormatItems)
        if imgui.IsItemHovered(globals.ctx) then
            imgui.SetTooltip(globals.ctx, "Channel order of the SOURCE items (5.0/7.0).\n\nUnknown: Uses channel 1 only (mono)\n\nITU/Dolby: L R C LS RS (Center at ch 3)\n→ Enables smart routing: skips center channel\n→ Routes L, R, LS, RS to output tracks\n\nSMPTE: L C R LS RS (Center at ch 2)\n→ Same smart routing, different channel order\n\nSpecifying format enables intelligent multichannel routing.")
        end
        imgui.PopItemWidth(globals.ctx)

        if sfChanged then
            if newIndex == 0 then
                container.sourceChannelVariant = nil
            elseif newIndex == 1 then
                container.sourceChannelVariant = 0
            elseif newIndex == 2 then
                container.sourceChannelVariant = 1
            end
            container.needsRegeneration = true
        end
    end

    imgui.EndGroup(globals.ctx)

    -- === Track Structure Preview (Right Column) ===
    if trackStructure then
        imgui.SameLine(globals.ctx, 0, width * 0.03)
        imgui.BeginGroup(globals.ctx)

        imgui.Dummy(globals.ctx, 0, 4)
        imgui.Indent(globals.ctx, 8)

        -- Display preview header
        imgui.TextColored(globals.ctx, 0xFFAAFFFF, "Track Structure Preview")
        imgui.Separator(globals.ctx)
        imgui.Dummy(globals.ctx, 0, 2)

        -- Show structure info
        if trackStructure.numTracks == 1 then
            local channelText = trackStructure.trackChannels == 1 and "mono" or (trackStructure.trackChannels .. "ch")
            imgui.Text(globals.ctx, string.format("→ 1 track (%s)", channelText))
        else
            local trackTypeText = trackStructure.trackType == "stereo" and "stereo" or "mono"
            imgui.Text(globals.ctx, string.format("→ %d %s tracks", trackStructure.numTracks, trackTypeText))

            -- Show track labels if available
            if trackStructure.trackLabels then
                imgui.TextColored(globals.ctx, 0xFFCCCCCC, "  " .. table.concat(trackStructure.trackLabels, ", "))
            end
        end

        -- Show distribution info if applicable
        if trackStructure.useDistribution then
            local distModeText = {"Round-robin", "Random", "All tracks"}
            local distMode = distModeText[container.itemDistributionMode + 1] or "Round-robin"
            imgui.TextColored(globals.ctx, 0xFFCCCCCC, "→ " .. distMode)
        end

        imgui.Dummy(globals.ctx, 0, 2)
        imgui.TextColored(globals.ctx, 0xFF888888, trackStructure.strategy or "default")

        -- Show warning if any
        if trackStructure.warning then
            imgui.Dummy(globals.ctx, 0, 4)
            imgui.PushTextWrapPos(globals.ctx, imgui.GetCursorPosX(globals.ctx) + rightColumnWidth - 16)
            imgui.TextColored(globals.ctx, 0xFFAAAAFF, "⚠ " .. trackStructure.warning)
            imgui.PopTextWrapPos(globals.ctx)
        end

        imgui.Unindent(globals.ctx, 8)
        imgui.Dummy(globals.ctx, 0, 4)

        imgui.EndGroup(globals.ctx)
    end

    imgui.Separator(globals.ctx)

    -- Channel volume controls
    Container_ChannelConfig.drawChannelVolumeControls(container, containerId, groupPath, containerIndex, width)
end

-- Draw stereo pair settings
function Container_ChannelConfig.drawStereoPairSettings(container, containerId, labelWidth, comboWidth)
    local imgui = globals.imgui

    -- Build stereo pair options based on item channels
    local maxItemChannels = 2
    if container.items and #container.items > 0 then
        for _, item in ipairs(container.items) do
            if item.numChannels and item.numChannels > maxItemChannels then
                maxItemChannels = item.numChannels
            end
        end
    end

    -- Calculate number of stereo tracks based on output format
    local outputChannels = globals.Generation.getOutputChannelCount(container.channelMode)
    local numTracks = 0
    if outputChannels == 2 then
        numTracks = 1  -- Single stereo track
    elseif outputChannels >= 4 then
        -- Multi-channel: calculate number of stereo pairs
        if outputChannels % 2 == 0 then
            numTracks = outputChannels / 2  -- Even formats (4.0)
        else
            numTracks = (outputChannels - 1) / 2  -- Odd formats (5.0, 7.0) - skip center
        end
    end

    -- Only show if items have enough channels for stereo pairs
    if maxItemChannels >= 2 and maxItemChannels % 2 == 0 then
        local numPairs = math.floor(maxItemChannels / 2)

        -- Initialize stereoPairMapping if needed
        globals.Structures.ensureStereoPairMapping(container, numTracks)

        -- If only 1 track (stereo output), show single dropdown (legacy behavior)
        if numTracks == 1 then
            imgui.Text(globals.ctx, "Stereo Pair:")
            imgui.SameLine(globals.ctx, labelWidth)

            local stereoPairOptions = ""
            for i = 0, numPairs - 1 do
                local ch1 = i * 2 + 1
                local ch2 = i * 2 + 2
                stereoPairOptions = stereoPairOptions .. "Ch " .. ch1 .. "-" .. ch2 .. "\0"
            end

            -- Use stereoPairMapping[1] or fallback to old stereoPairSelection
            local currentPair = container.stereoPairMapping[1] or container.stereoPairSelection or 0

            imgui.PushItemWidth(globals.ctx, comboWidth)
            local pairChanged, newPair = globals.UndoWrappers.Combo(globals.ctx, "##StereoPair_" .. containerId, currentPair, stereoPairOptions)
            if imgui.IsItemHovered(globals.ctx) then
                imgui.SetTooltip(globals.ctx, "Select which stereo pair to extract from multichannel items.\n\nCh 1-2: Front L/R (most common)\nCh 3-4: Rear LS/RS\nCh 5-6: Additional channels")
            end
            if pairChanged then
                container.stereoPairMapping[1] = newPair
                container.stereoPairSelection = newPair  -- Backward compatibility
                container.needsRegeneration = true
            end
            imgui.PopItemWidth(globals.ctx)

        elseif numTracks > 1 and numPairs > 1 then
            -- Multiple tracks: show dropdown per track
            imgui.Text(globals.ctx, "Stereo Pair Mapping:")

            -- Build stereo pair options with "Random"
            local stereoPairOptions = ""
            for i = 0, numPairs - 1 do
                local ch1 = i * 2 + 1
                local ch2 = i * 2 + 2
                stereoPairOptions = stereoPairOptions .. "Ch " .. ch1 .. "-" .. ch2 .. "\0"
            end
            stereoPairOptions = stereoPairOptions .. "Random\0"

            -- Show dropdown for each track
            for trackIdx = 1, numTracks do
                imgui.Indent(globals.ctx, 20)

                -- Track label (L+R, LS+RS, LB+RB, etc.)
                local trackLabel = ""
                if trackIdx == 1 then trackLabel = "L+R"
                elseif trackIdx == 2 then trackLabel = "LS+RS"
                elseif trackIdx == 3 then trackLabel = "LB+RB"
                else trackLabel = "Track " .. trackIdx
                end

                imgui.Text(globals.ctx, trackLabel .. ":")
                imgui.SameLine(globals.ctx, labelWidth - 20)

                -- Get current pair selection for this track
                local currentPair = container.stereoPairMapping[trackIdx]
                local comboIndex
                if currentPair == "random" then
                    comboIndex = numPairs  -- Last index is "Random"
                else
                    comboIndex = currentPair or (trackIdx - 1)  -- Default to logical mapping
                end

                imgui.PushItemWidth(globals.ctx, comboWidth)
                local pairChanged, newIndex = globals.UndoWrappers.Combo(globals.ctx, "##StereoPairTrack" .. trackIdx .. "_" .. containerId, comboIndex, stereoPairOptions)
                if imgui.IsItemHovered(globals.ctx) then
                    imgui.SetTooltip(globals.ctx, "Select which stereo pair from the source item to route to this track.\n\nCh 1-2: Usually Front L/R\nCh 3-4: Usually Rear LS/RS\nCh 5-6: Usually Back LB/RB or side surrounds\nRandom: Randomly select a pair for each item")
                end
                if pairChanged then
                    if newIndex == numPairs then
                        container.stereoPairMapping[trackIdx] = "random"
                    else
                        container.stereoPairMapping[trackIdx] = newIndex
                    end
                    container.needsRegeneration = true
                end
                imgui.PopItemWidth(globals.ctx)

                imgui.Unindent(globals.ctx, 20)
            end

        elseif numTracks > 1 and numPairs == 1 then
            -- Multiple tracks but items only have 1 stereo pair - show info message
            imgui.TextColored(globals.ctx, 0xFFAAAAFF, "ℹ Items have only 1 stereo pair")
            imgui.Indent(globals.ctx, 20)
            imgui.TextWrapped(globals.ctx, "Ch 1-2 will be used for all " .. numTracks .. " tracks")
            imgui.Unindent(globals.ctx, 20)
        end
    else
        -- Items don't support stereo pairs (odd channels)
        imgui.TextColored(globals.ctx, 0xFF4444FF, "⚠ Stereo pairs not available")
    end
end

-- Draw mono channel settings
function Container_ChannelConfig.drawMonoChannelSettings(container, containerId, labelWidth, comboWidth)
    local imgui = globals.imgui

    -- Find max item channels
    local maxItemChannels = 2
    if container.items and #container.items > 0 then
        for _, item in ipairs(container.items) do
            if item.numChannels and item.numChannels > maxItemChannels then
                maxItemChannels = item.numChannels
            end
        end
    end

    imgui.Text(globals.ctx, "Mono Channel:")
    imgui.SameLine(globals.ctx, labelWidth)

    -- Build options: Channel 1, Channel 2, ..., Random
    local monoChannelOptions = ""
    for i = 1, maxItemChannels do
        monoChannelOptions = monoChannelOptions .. "Channel " .. i .. "\0"
    end
    monoChannelOptions = monoChannelOptions .. "Random\0"

    -- Default to Random if not set or out of range
    if container.monoChannelSelection == nil or container.monoChannelSelection >= maxItemChannels then
        container.monoChannelSelection = maxItemChannels  -- Random index
    end

    imgui.PushItemWidth(globals.ctx, comboWidth)
    local monoChChanged, newMonoCh = globals.UndoWrappers.Combo(globals.ctx, "##MonoChannel_" .. containerId, container.monoChannelSelection, monoChannelOptions)
    if imgui.IsItemHovered(globals.ctx) then
        imgui.SetTooltip(globals.ctx, "Select which channel to extract from multichannel items.\n\nChannel 1: Usually Left\nChannel 2: Usually Right\nChannel 3+: Surround/center channels\nRandom: Pick a random channel for each item\n\nExtracted channels are distributed across output tracks.")
    end
    if monoChChanged then
        container.monoChannelSelection = newMonoCh
        container.needsRegeneration = true
    end
    imgui.PopItemWidth(globals.ctx)
end

-- Draw channel volume controls
function Container_ChannelConfig.drawChannelVolumeControls(container, containerId, groupPath, containerIndex, width)
    local imgui = globals.imgui

    -- Get the active configuration (with variant if applicable)
    if container.channelMode > 0 then
        local config = globals.Constants.CHANNEL_CONFIGS[container.channelMode]
        local activeConfig = config
        if config.hasVariants then
            activeConfig = config.variants[container.channelVariant or 0]
        end

        -- Detect how many tracks will actually be created
        local itemsAnalysis = globals.Generation.analyzeContainerItems(container)
        local trackStructure = globals.Generation.determineTrackStructure(container, itemsAnalysis)
        local numTracks = trackStructure.numTracks
        local trackLabels = trackStructure.trackLabels or activeConfig.labels

        -- Only show channel settings if multiple tracks will be created
        if numTracks > 1 then
            -- Channel-specific controls
            imgui.Text(globals.ctx, "Channel Settings:")

            -- Calculate optimal layout for 100% width usage
            local labelWidth = 80            -- Fixed width for labels
            local inputWidth = 85            -- Fixed width for dB input
            local sliderWidth = width - labelWidth - inputWidth - 16  -- Remaining space minus spacing

            for i = 1, numTracks do
                local label = trackLabels and trackLabels[i] or ("Channel " .. i)

                imgui.PushID(globals.ctx, "channel_" .. i .. "_" .. containerId)

                -- Label with fixed width
                imgui.Text(globals.ctx, label .. ":")

                -- Initialize volume if needed
                if container.channelVolumes[i] == nil then
                    container.channelVolumes[i] = 0.0
                end

                -- Volume slider on same line with optimized spacing
                imgui.SameLine(globals.ctx, labelWidth)

                -- Convert current dB to normalized
                local normalizedVolume = globals.Utils.dbToNormalizedRelative(container.channelVolumes[i])

                -- Volume control with optimized width
                local defaultNormalizedVol = globals.Utils.dbToNormalizedRelative(globals.Constants.DEFAULTS.CONTAINER_VOLUME_DEFAULT)
                local rv, newNormalizedVolume = globals.SliderEnhanced.SliderDouble({
                    id = "##Vol_" .. i,
                    value = normalizedVolume,
                    min = 0.0,
                    max = 1.0,
                    defaultValue = defaultNormalizedVol,
                    format = "",
                    width = sliderWidth
                })
                if rv then
                    local newVolumeDB = globals.Utils.normalizedToDbRelative(newNormalizedVolume)
                    container.channelVolumes[i] = newVolumeDB
                    -- Apply volume to channel track in real-time
                    globals.Utils.setChannelTrackVolume(groupPath, containerIndex, i, newVolumeDB)
                end

                -- Manual dB input field with consistent spacing
                imgui.SameLine(globals.ctx, 0, 8)
                imgui.PushItemWidth(globals.ctx, inputWidth)
                local displayValue = container.channelVolumes[i] <= -144 and -144 or container.channelVolumes[i]
                local rv2, manualDB = globals.UndoWrappers.InputDouble(
                    globals.ctx,
                    "##VolInput_" .. i,
                    displayValue,
                    0, 0,  -- step, step_fast (not used)
                    "%.1f dB"
                )
                if rv2 then
                    -- Clamp to valid range
                    manualDB = math.max(Constants.AUDIO.VOLUME_RANGE_DB_MIN,
                                       math.min(Constants.AUDIO.VOLUME_RANGE_DB_MAX, manualDB))
                    container.channelVolumes[i] = manualDB
                    globals.Utils.setChannelTrackVolume(groupPath, containerIndex, i, manualDB)
                end
                imgui.PopItemWidth(globals.ctx)

                imgui.PopID(globals.ctx)
            end
        end -- End of if numTracks > 1
    end -- End of if container.channelMode > 0 for channel settings
end

return Container_ChannelConfig
