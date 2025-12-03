--[[
@version 1.0
@noindex
DM Ambiance Creator - Routing Validator Fixes Module
Fix suggestion generation and application functions.
--]]

local RoutingValidator_Fixes = {}
local globals = {}
local Constants = nil
local Core = nil
local Detection = nil

function RoutingValidator_Fixes.initModule(g)
    globals = g
    Constants = require("DM_Ambiance_Constants")
end

function RoutingValidator_Fixes.setDependencies(core, detection)
    Core = core
    Detection = detection
end

-- ===================================================================
-- FIX SUGGESTION GENERATION
-- ===================================================================

-- Generate fix suggestions for all detected issues
function RoutingValidator_Fixes.generateFixSuggestions(issuesList, projectTree)
    local suggestions = {}

    for _, issue in ipairs(issuesList) do
        local suggestion = RoutingValidator_Fixes.generateFixSuggestion(issue, projectTree)
        if suggestion then
            table.insert(suggestions, suggestion)
        end
    end

    return suggestions
end

-- Generate a fix suggestion for a specific issue
function RoutingValidator_Fixes.generateFixSuggestion(issue, projectTree)
    local ISSUE_TYPES = Core.getIssueTypes()

    if issue.type == ISSUE_TYPES.CHANNEL_ORDER_CONFLICT then
        return RoutingValidator_Fixes.suggestChannelOrderFix(issue, projectTree)
    elseif issue.type == ISSUE_TYPES.CHANNEL_CONFLICT then
        return RoutingValidator_Fixes.suggestChannelConflictFix(issue, projectTree)
    elseif issue.type == ISSUE_TYPES.PARENT_INSUFFICIENT_CHANNELS then
        return issue.suggestedFix
    elseif issue.type == ISSUE_TYPES.PARENT_EXCESSIVE_CHANNELS then
        return issue.suggestedFix
    elseif issue.type == ISSUE_TYPES.ORPHAN_SEND then
        return RoutingValidator_Fixes.suggestOrphanSendFix(issue, projectTree)
    end

    return nil
end

-- Suggest fix for channel order conflicts
function RoutingValidator_Fixes.suggestChannelOrderFix(issue, projectTree)
    local conflictData = issue.conflictData

    return {
        action = "resolve_channel_order_conflict",
        issue = issue,
        conflictData = conflictData,
        requiresUserChoice = true,
        reason = string.format("Channel order conflict for %s.0 requires user choice between '%s' and '%s'",
            conflictData.channelMode, conflictData.variantName1, conflictData.variantName2),
        options = {
            {
                action = "use_variant_1",
                variant = conflictData.variant1,
                variantName = conflictData.variantName1,
                affectedContainers = {conflictData.container2},
                reason = string.format("Use %s for all %s.0 containers",
                    conflictData.variantName1, conflictData.channelMode)
            },
            {
                action = "use_variant_2",
                variant = conflictData.variant2,
                variantName = conflictData.variantName2,
                affectedContainers = conflictData.allContainersWithVariant1,
                reason = string.format("Use %s for all %s.0 containers",
                    conflictData.variantName2, conflictData.channelMode)
            }
        }
    }
end

-- Suggest fix for channel conflicts
function RoutingValidator_Fixes.suggestChannelConflictFix(issue, projectTree)
    local conflictData = issue.conflictData
    local track = conflictData.track
    local expectedRouting = conflictData.expectedRouting

    return {
        action = "reroute_container",
        track = track,
        newRouting = expectedRouting,
        reason = string.format("Align '%s' with master format (%s): %s",
            track.name,
            conflictData.masterFormat.config and conflictData.masterFormat.config.name or "Master",
            table.concat(expectedRouting, ", "))
    }
end

-- Suggest fix for orphan sends
function RoutingValidator_Fixes.suggestOrphanSendFix(issue, projectTree)
    return {
        action = "increase_parent_channels",
        track = issue.destTrack.track,
        channels = Core.parseDstChannel(issue.sendData.dstChannel),
        reason = string.format("Increase channels to accommodate send from %s", issue.track.name)
    }
end

-- Suggest fix for downmix errors
function RoutingValidator_Fixes.suggestDownmixFix(issue, projectTree)
    local channelInfo = issue.channelInfo
    local properRouting = RoutingValidator_Fixes.generateProperDownmix(channelInfo)

    return {
        action = "apply_proper_downmix",
        track = issue.track,
        newRouting = properRouting,
        reason = "Apply proper downmix routing"
    }
end

-- Generate proper downmix routing for a configuration
function RoutingValidator_Fixes.generateProperDownmix(channelInfo)
    local config = channelInfo.config
    local newRouting = {}

    if config.channels >= 5 then
        for i, label in ipairs(channelInfo.labels) do
            if label == "L" then
                table.insert(newRouting, 1)
            elseif label == "R" then
                table.insert(newRouting, 2)
            elseif label == "C" then
                table.insert(newRouting, 1)
            elseif label == "LS" then
                table.insert(newRouting, 1)
            elseif label == "RS" then
                table.insert(newRouting, 2)
            else
                table.insert(newRouting, (i % 2) + 1)
            end
        end
    else
        newRouting = channelInfo.routing
    end

    return newRouting
end

-- ===================================================================
-- FIX APPLICATION
-- ===================================================================

-- Apply all fix suggestions automatically
function RoutingValidator_Fixes.autoFixRouting(issuesList, fixSuggestions)
    if not fixSuggestions or #fixSuggestions == 0 then
        return false
    end

    reaper.Undo_BeginBlock()

    local allSuccess = true

    for _, suggestion in ipairs(fixSuggestions) do
        local success = RoutingValidator_Fixes.applySingleFix(suggestion, true)
        if not success then
            allSuccess = false
        end
    end

    reaper.Undo_EndBlock("Auto-fix Channel Routing Issues", -1)

    Core.clearCache()

    return allSuccess
end

-- Apply a single fix suggestion
function RoutingValidator_Fixes.applySingleFix(suggestion, autoMode)
    if suggestion.action == "resolve_channel_order_conflict" then
        if autoMode then
            local firstOption = suggestion.options and suggestion.options[1]
            if firstOption then
                return RoutingValidator_Fixes.applyChannelOrderChoice(firstOption.variant, suggestion.conflictData.channelMode)
            end
            return false
        else
            -- In manual mode, UI module handles this
            return false
        end

    elseif suggestion.action == "apply_channel_order_choice" then
        return RoutingValidator_Fixes.applyChannelOrderChoice(suggestion)

    elseif suggestion.action == "set_channel_count" then
        local channels = suggestion.channels
        if channels % 2 == 1 then
            channels = channels + 1
        end

        reaper.SetMediaTrackInfo_Value(suggestion.track, "I_NCHAN", channels)
        reaper.UpdateArrange()
        return true

    elseif suggestion.action == "reroute_container" then
        return RoutingValidator_Fixes.applyNewRouting(suggestion.track, suggestion.newRouting)

    elseif suggestion.action == "increase_parent_channels" then
        local channels = suggestion.channels
        if channels % 2 == 1 then
            channels = channels + 1
        end

        reaper.SetMediaTrackInfo_Value(suggestion.track, "I_NCHAN", channels)
        reaper.UpdateArrange()
        return true

    elseif suggestion.action == "apply_proper_downmix" then
        return RoutingValidator_Fixes.applyNewRouting(suggestion.track, suggestion.newRouting)
    end

    return false
end

-- Apply new routing to a container track
function RoutingValidator_Fixes.applyNewRouting(containerTrackInfo, newRouting)
    local containerTrack = containerTrackInfo.track
    local maxChannel = math.max(table.unpack(newRouting))

    if maxChannel % 2 == 1 then
        maxChannel = maxChannel + 1
    end

    local trackGUID = reaper.GetTrackGUID(containerTrack)

    reaper.Undo_BeginBlock()

    reaper.SetMediaTrackInfo_Value(containerTrack, "I_NCHAN", maxChannel)
    reaper.UpdateArrange()
    reaper.TrackList_AdjustWindows(false)

    local actualChannels = reaper.GetMediaTrackInfo_Value(containerTrack, "I_NCHAN")

    if actualChannels ~= maxChannel then
        for attempt = 1, 3 do
            reaper.Undo_BeginBlock()
            reaper.SetMediaTrackInfo_Value(containerTrack, "I_NCHAN", maxChannel)
            reaper.Undo_EndBlock(string.format("Retry Channel Fix %d", attempt), -1)

            reaper.UpdateArrange()
            reaper.TrackList_AdjustWindows(false)
            reaper.UpdateTimeline()

            local checkChannels = reaper.GetMediaTrackInfo_Value(containerTrack, "I_NCHAN")
            if checkChannels == maxChannel then
                break
            end
        end
    end

    local childIndex = 1
    for _, childInfo in ipairs(containerTrackInfo.children) do
        if childIndex <= #newRouting then
            for _, send in ipairs(childInfo.sends) do
                if send.destTrack == containerTrack then
                    local newDestChannel = 1024 + (newRouting[childIndex] - 1)
                    reaper.SetTrackSendInfo_Value(childInfo.track, 0, send.sendIndex, "I_DSTCHAN", newDestChannel)
                    break
                end
            end
            childIndex = childIndex + 1
        end
    end

    if globals.Utils and globals.Utils.ensureParentHasEnoughChannels then
        globals.Utils.ensureParentHasEnoughChannels(containerTrack, maxChannel)
    end

    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if container.name == containerTrackInfo.name then
                container.customRouting = newRouting
                break
            end
        end
    end

    reaper.Undo_EndBlock("Fix Container Routing", -1)

    reaper.UpdateArrange()
    reaper.UpdateTimeline()

    return true
end

-- Apply channel order choice
function RoutingValidator_Fixes.applyChannelOrderChoice(chosenVariant, channelMode)
    if type(chosenVariant) == "table" then
        -- Called with suggestion table
        channelMode = chosenVariant.conflictData and chosenVariant.conflictData.channelMode
        chosenVariant = chosenVariant.variant
    end

    if not channelMode then return false end

    reaper.Undo_BeginBlock()

    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if container.channelMode and container.channelMode > 0 then
                local config = Constants.CHANNEL_CONFIGS[container.channelMode]
                if config and config.hasVariants and config.channels == channelMode then
                    container.channelVariant = chosenVariant
                end
            end
        end
    end

    reaper.Undo_EndBlock("Apply Channel Order Choice", -1)

    Core.clearCache()

    return true
end

-- ===================================================================
-- LEGACY FUNCTIONS
-- ===================================================================

-- Get actual channel routing from existing tracks (legacy compatibility)
function RoutingValidator_Fixes.getActualTrackRouting(groupName, containerName)
    local groupTrack, groupTrackIdx = globals.Utils.findGroupByName(groupName)
    if not groupTrack then
        return nil
    end

    local containerTrack = globals.Utils.findContainerGroup(groupTrackIdx, containerName)
    if not containerTrack then
        return nil
    end

    local containerIdx = reaper.GetMediaTrackInfo_Value(containerTrack, "IP_TRACKNUMBER") - 1

    local folderDepth = reaper.GetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH")
    if folderDepth ~= 1 then
        return nil
    end

    local actualRouting = {}
    local trackIdx = containerIdx + 1
    local depth = 1

    while trackIdx < reaper.CountTracks(0) and depth > 0 do
        local childTrack = reaper.GetTrack(0, trackIdx)
        if not childTrack then break end

        local parent = reaper.GetParentTrack(childTrack)
        if parent == containerTrack then
            local sendCount = reaper.GetTrackNumSends(childTrack, 0)
            local destChannel = 1

            for sendIdx = 0, sendCount - 1 do
                local destTrack = reaper.GetTrackSendInfo_Value(childTrack, 0, sendIdx, "P_DESTTRACK")
                if destTrack == containerTrack then
                    local dstChan = reaper.GetTrackSendInfo_Value(childTrack, 0, sendIdx, "I_DSTCHAN")
                    if dstChan >= 1024 then
                        destChannel = (dstChan - 1024) + 1
                    else
                        destChannel = math.floor(dstChan / 2) + 1
                    end
                    break
                end
            end

            table.insert(actualRouting, destChannel)
        end

        local childDepth = reaper.GetMediaTrackInfo_Value(childTrack, "I_FOLDERDEPTH")
        depth = depth + childDepth
        trackIdx = trackIdx + 1
    end

    return #actualRouting > 0 and actualRouting or nil
end

-- Legacy detect routing conflicts
function RoutingValidator_Fixes.detectConflictsLegacy()
    local channelUsage = {}
    local conflicts = {}
    local containers = {}
    local conflictPairs = {}

    for groupIdx, group in ipairs(globals.groups) do
        for containerIdx, container in ipairs(group.containers) do
            if container.channelMode and container.channelMode > 0 then
                local config = Constants.CHANNEL_CONFIGS[container.channelMode]

                if config then
                    local activeConfig = config
                    if config.hasVariants then
                        activeConfig = config.variants[container.channelVariant or 0]
                        activeConfig.channels = config.channels
                        activeConfig.name = config.name
                    end

                    local containerKey = group.name .. "_" .. container.name

                    local actualRouting = RoutingValidator_Fixes.getActualTrackRouting(group.name, container.name)
                    local routing = actualRouting or container.customRouting or activeConfig.routing

                    containers[containerKey] = {
                        group = group,
                        container = container,
                        groupName = group.name,
                        containerName = container.name,
                        channelMode = container.channelMode,
                        channelCount = config.channels,
                        config = activeConfig,
                        routing = routing,
                        labels = activeConfig.labels,
                        conflicts = {}
                    }

                    for idx, channelNum in ipairs(routing) do
                        local label = activeConfig.labels[idx]

                        if not channelUsage[channelNum] then
                            channelUsage[channelNum] = {}
                        end

                        for _, usage in ipairs(channelUsage[channelNum]) do
                            if usage.label ~= label then
                                local conflictKey = usage.containerKey .. "_vs_" .. containerKey

                                if not conflictPairs[conflictKey] then
                                    conflictPairs[conflictKey] = {
                                        container1 = usage,
                                        container2 = {
                                            containerKey = containerKey,
                                            groupName = group.name,
                                            containerName = container.name,
                                            label = label
                                        },
                                        conflictingChannels = {}
                                    }
                                end

                                table.insert(conflictPairs[conflictKey].conflictingChannels, {
                                    channel = channelNum,
                                    label1 = usage.label,
                                    label2 = label
                                })

                                containers[containerKey].conflicts[channelNum] = {
                                    channel = channelNum,
                                    label = label,
                                    conflictsWith = usage.containerKey
                                }

                                if containers[usage.containerKey] then
                                    containers[usage.containerKey].conflicts[channelNum] = {
                                        channel = channelNum,
                                        label = usage.label,
                                        conflictsWith = containerKey
                                    }
                                end
                            end
                        end

                        table.insert(channelUsage[channelNum], {
                            label = label,
                            containerKey = containerKey,
                            groupName = group.name,
                            containerName = container.name
                        })
                    end
                end
            end
        end
    end

    local hasConflicts = false
    for _, _ in pairs(conflictPairs) do
        hasConflicts = true
        break
    end

    if not hasConflicts then
        return nil
    end

    return {
        containers = containers,
        conflictPairs = conflictPairs,
        channelUsage = channelUsage
    }
end

-- Find intelligent routing solution (legacy)
function RoutingValidator_Fixes.findIntelligentRoutingLegacy(conflicts)
    local resolutions = {}

    local masterConfigs = {}
    local subordinateConfigs = {}

    for containerKey, data in pairs(conflicts.containers) do
        if data.channelCount >= 5 then
            masterConfigs[containerKey] = data
        else
            subordinateConfigs[containerKey] = data
        end
    end

    for containerKey, subConfig in pairs(subordinateConfigs) do
        if next(subConfig.conflicts) then
            local conflictingMaster = nil
            for channel, conflictInfo in pairs(subConfig.conflicts) do
                if masterConfigs[conflictInfo.conflictsWith] then
                    conflictingMaster = masterConfigs[conflictInfo.conflictsWith]
                    break
                end
            end

            if conflictingMaster then
                local resolution = RoutingValidator_Fixes.matchChannelsByLabelLegacy(subConfig, conflictingMaster)
                if resolution then
                    table.insert(resolutions, resolution)
                end
            end
        end
    end

    return resolutions
end

-- Match channels between configurations based on labels (legacy)
function RoutingValidator_Fixes.matchChannelsByLabelLegacy(subConfig, masterConfig)
    local actualRouting = RoutingValidator_Fixes.getActualTrackRouting(subConfig.groupName, subConfig.containerName)
    local currentRouting = actualRouting or subConfig.routing

    local resolution = {
        containerKey = subConfig.groupName .. "_" .. subConfig.containerName,
        groupName = subConfig.groupName,
        containerName = subConfig.containerName,
        affectedBy = masterConfig.groupName .. "_" .. masterConfig.containerName,
        changes = {},
        originalRouting = currentRouting,
        newRouting = {}
    }

    local masterLabelMap = {}
    for idx, label in ipairs(masterConfig.labels) do
        masterLabelMap[label] = masterConfig.routing[idx]
    end

    for idx, label in ipairs(subConfig.labels) do
        local oldChannel = currentRouting[idx]
        local newChannel = oldChannel
        local reason = "Keep original"
        local matched = nil

        if masterLabelMap[label] then
            newChannel = masterLabelMap[label]
            matched = masterConfig.containerName .. "_" .. label
            reason = string.format("Match %s %s on channel %d",
                masterConfig.config.name or "Master", label, newChannel)
        else
            if label == "L" then
                newChannel = 1
                reason = "Standard L position"
            elseif label == "R" then
                if masterLabelMap["C"] and masterLabelMap["C"] == 2 then
                    newChannel = 3
                else
                    newChannel = 2
                end
                reason = newChannel == 3 and "Adapt to L C R layout" or "Standard R position"
            elseif label == "LS" or label == "RS" then
                if masterLabelMap[label] then
                    newChannel = masterLabelMap[label]
                    reason = string.format("Match %s %s", masterConfig.config.name or "Master", label)
                end
            end
        end

        table.insert(resolution.changes, {
            label = label,
            oldChannel = oldChannel,
            newChannel = newChannel,
            matched = matched,
            reason = reason
        })

        table.insert(resolution.newRouting, newChannel)
    end

    local needsChange = false
    for i, channel in ipairs(resolution.newRouting) do
        if channel ~= resolution.originalRouting[i] then
            needsChange = true
            break
        end
    end

    return needsChange and resolution or nil
end

return RoutingValidator_Fixes
