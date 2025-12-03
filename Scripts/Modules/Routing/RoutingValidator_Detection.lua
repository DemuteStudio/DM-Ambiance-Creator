--[[
@version 1.0
@noindex
DM Ambiance Creator - Routing Validator Detection Module
Conflict detection, channel analysis, and validation functions.
--]]

local RoutingValidator_Detection = {}
local globals = {}
local Constants = nil
local Core = nil

function RoutingValidator_Detection.initModule(g)
    globals = g
    Constants = require("DM_Ambiance_Constants")
end

function RoutingValidator_Detection.setDependencies(core)
    Core = core
end

-- ===================================================================
-- MAIN VALIDATION FUNCTION
-- ===================================================================

-- Main validation function - validates entire project routing
function RoutingValidator_Detection.validateProjectRouting()
    -- CRITICAL: Skip validation if downgrade operation is in progress
    if globals.skipRoutingValidation then
        return {}
    end

    local state = Core.getState()
    local startTime = reaper.time_precise()

    -- Skip if validation was done recently (performance optimization)
    if state.projectTrackCache and (startTime - state.lastValidationTime) < 1.0 then
        return state.issuesList or {}
    end

    reaper.PreventUIRefresh(1)

    -- Step 1: Scan all tracks in project
    local projectTree = Core.scanAllProjectTracks()

    -- Step 2: Analyze track hierarchy and relationships
    RoutingValidator_Detection.analyzeTrackHierarchy(projectTree)

    -- Step 3: Validate channel consistency
    RoutingValidator_Detection.validateChannelConsistency(projectTree)

    -- Step 4: Detect routing issues
    local issuesList = RoutingValidator_Detection.detectRoutingIssues(projectTree)

    -- Cache results
    Core.setState({
        projectTrackCache = projectTree,
        lastValidationTime = startTime,
        issuesList = issuesList
    })

    reaper.PreventUIRefresh(-1)

    return issuesList
end

-- ===================================================================
-- HELPER FUNCTIONS
-- ===================================================================

-- Recursively calculate the actual channels used by a track and ALL its descendants
local function calculateActualChannelsUsed(trackInfo, projectTree)
    local maxChannels = trackInfo.channelCount or 0

    local folderDepth = reaper.GetMediaTrackInfo_Value(trackInfo.track, "I_FOLDERDEPTH")
    if folderDepth == 1 then
        for _, childTrack in pairs(projectTree.allTracks) do
            if childTrack.parent == trackInfo.track then
                for _, send in ipairs(childTrack.sends) do
                    if send.destTrack == trackInfo.track then
                        local channelNum = Core.parseDstChannel(send.dstChannel)
                        maxChannels = math.max(maxChannels, channelNum)
                    end
                end

                local parentSend = reaper.GetMediaTrackInfo_Value(childTrack.track, "B_MAINSEND")
                if parentSend == 1 then
                    local childActualChannels = calculateActualChannelsUsed(childTrack, projectTree)
                    maxChannels = math.max(maxChannels, childActualChannels)
                end
            end
        end
    end

    return maxChannels
end

-- Calculate folder depth for a track
local function calculateTrackDepth(trackInfo, projectTree)
    local depth = 0
    local current = trackInfo
    local visited = {}

    while current and current.parent do
        local parentInfo = nil
        for _, info in pairs(projectTree.allTracks) do
            if info and info.track == current.parent then
                parentInfo = info
                break
            end
        end

        if not parentInfo or visited[parentInfo.track] then
            break
        end

        visited[parentInfo.track] = true
        depth = depth + 1
        current = parentInfo
    end

    return depth
end

-- Sort tracks by depth (deepest first)
local function groupTracksByDepth(projectTree)
    local tracksByDepth = {}
    local maxDepth = 0

    for _, trackInfo in pairs(projectTree.allTracks) do
        if trackInfo then
            local depth = calculateTrackDepth(trackInfo, projectTree)
            maxDepth = math.max(maxDepth, depth)

            if not tracksByDepth[depth] then
                tracksByDepth[depth] = {}
            end
            table.insert(tracksByDepth[depth], trackInfo)
        end
    end

    return tracksByDepth, maxDepth
end

-- ===================================================================
-- ANALYSIS FUNCTIONS
-- ===================================================================

-- Analyze track hierarchy and build parent-child relationships
function RoutingValidator_Detection.analyzeTrackHierarchy(projectTree)
    for _, trackInfo in pairs(projectTree.allTracks) do
        if trackInfo and trackInfo.parent then
            for _, parentInfo in pairs(projectTree.allTracks) do
                if parentInfo and parentInfo.track == trackInfo.parent then
                    table.insert(parentInfo.children, trackInfo)
                    break
                end
            end
        end
    end

    for _, trackInfo in pairs(projectTree.allTracks) do
        if trackInfo and trackInfo.track then
            RoutingValidator_Detection.analyzeSendsAndReceives(trackInfo)
        end
    end
end

-- Analyze sends and receives for a specific track
function RoutingValidator_Detection.analyzeSendsAndReceives(trackInfo)
    local track = trackInfo.track

    local sendCount = reaper.GetTrackNumSends(track, 0)
    for sendIdx = 0, sendCount - 1 do
        local destTrack = reaper.GetTrackSendInfo_Value(track, 0, sendIdx, "P_DESTTRACK")
        local srcChan = reaper.GetTrackSendInfo_Value(track, 0, sendIdx, "I_SRCCHAN")
        local dstChan = reaper.GetTrackSendInfo_Value(track, 0, sendIdx, "I_DSTCHAN")
        local enabled = reaper.GetTrackSendInfo_Value(track, 0, sendIdx, "B_MUTE") == 0
        local volume = reaper.GetTrackSendInfo_Value(track, 0, sendIdx, "D_VOL")

        if destTrack and enabled then
            local sendInfo = {
                destTrack = destTrack,
                srcChannel = srcChan,
                dstChannel = dstChan,
                volume = volume,
                sendIndex = sendIdx
            }
            table.insert(trackInfo.sends, sendInfo)
        end
    end
end

-- ===================================================================
-- CHANNEL ORDER CONFLICT DETECTION
-- ===================================================================

-- Detect channel order conflicts across containers
function RoutingValidator_Detection.detectChannelOrderConflicts(projectTree)
    local ISSUE_TYPES = Core.getIssueTypes()
    local SEVERITY = Core.getSeverity()
    local conflicts = {}
    local outputVariants = {}
    local sourceVariants = {}

    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if container.channelMode and container.channelMode > 0 then
                local config = Constants.CHANNEL_CONFIGS[container.channelMode]
                if config and config.hasVariants then
                    local channelMode = config.channels

                    local outputVariant = container.channelVariant or 0

                    if not outputVariants[channelMode] then
                        outputVariants[channelMode] = {
                            variant = outputVariant,
                            containers = {container},
                            group = group
                        }
                    else
                        if outputVariants[channelMode].variant ~= outputVariant then
                            local existingInfo = outputVariants[channelMode]
                            local existingVariantName = Core.getVariantName(channelMode, existingInfo.variant)
                            local newVariantName = Core.getVariantName(channelMode, outputVariant)

                            table.insert(conflicts, {
                                type = ISSUE_TYPES.CHANNEL_ORDER_CONFLICT,
                                severity = SEVERITY.ERROR,
                                description = string.format("Output channel order conflict for %s.0: '%s' vs '%s'",
                                    channelMode, existingVariantName, newVariantName),
                                conflictData = {
                                    conflictType = "output",
                                    channelMode = channelMode,
                                    container1 = existingInfo.containers[1],
                                    variant1 = existingInfo.variant,
                                    variantName1 = existingVariantName,
                                    container2 = container,
                                    variant2 = outputVariant,
                                    variantName2 = newVariantName,
                                    allContainersWithVariant1 = existingInfo.containers,
                                    allContainersWithVariant2 = {container}
                                }
                            })
                            return conflicts
                        else
                            table.insert(outputVariants[channelMode].containers, container)
                        end
                    end
                end

                if container.sourceChannelVariant ~= nil and container.items and #container.items > 0 then
                    local itemChannelMode = nil
                    for _, item in ipairs(container.items) do
                        local numCh = item.numChannels or 2
                        if numCh == 5 or numCh == 7 then
                            itemChannelMode = numCh
                            break
                        end
                    end

                    if itemChannelMode then
                        local sourceVariant = container.sourceChannelVariant

                        if not sourceVariants[itemChannelMode] then
                            sourceVariants[itemChannelMode] = {
                                variant = sourceVariant,
                                containers = {container},
                                group = group
                            }
                        else
                            if sourceVariants[itemChannelMode].variant ~= sourceVariant then
                                local existingInfo = sourceVariants[itemChannelMode]
                                local existingVariantName = Core.getVariantName(itemChannelMode, existingInfo.variant)
                                local newVariantName = Core.getVariantName(itemChannelMode, sourceVariant)

                                table.insert(conflicts, {
                                    type = ISSUE_TYPES.CHANNEL_ORDER_CONFLICT,
                                    severity = SEVERITY.ERROR,
                                    description = string.format("CRITICAL: Source format conflict for %s.0 items: '%s' vs '%s' - Cannot be resolved!",
                                        itemChannelMode, existingVariantName, newVariantName),
                                    conflictData = {
                                        conflictType = "source",
                                        channelMode = itemChannelMode,
                                        container1 = existingInfo.containers[1],
                                        variant1 = existingInfo.variant,
                                        variantName1 = existingVariantName,
                                        container2 = container,
                                        variant2 = sourceVariant,
                                        variantName2 = newVariantName,
                                        allContainersWithVariant1 = existingInfo.containers,
                                        allContainersWithVariant2 = {container},
                                        isCritical = true
                                    }
                                })
                                return conflicts
                            else
                                table.insert(sourceVariants[itemChannelMode].containers, container)
                            end
                        end
                    end
                end
            end
        end
    end

    return conflicts
end

-- ===================================================================
-- CHANNEL CONSISTENCY VALIDATION
-- ===================================================================

-- Validate channel consistency across the entire project
function RoutingValidator_Detection.validateChannelConsistency(projectTree)
    local ISSUE_TYPES = Core.getIssueTypes()
    local SEVERITY = Core.getSeverity()
    local tracksByDepth, maxDepth = groupTracksByDepth(projectTree)

    for depth = maxDepth, 1, -1 do
        local tracksAtDepth = tracksByDepth[depth] or {}

        local childrenByParent = {}
        for _, trackInfo in ipairs(tracksAtDepth) do
            if trackInfo.parent then
                if not childrenByParent[trackInfo.parent] then
                    childrenByParent[trackInfo.parent] = {}
                end
                table.insert(childrenByParent[trackInfo.parent], trackInfo)
            end
        end

        for parentTrack, children in pairs(childrenByParent) do
            local parentInfo = nil
            for _, info in pairs(projectTree.allTracks) do
                if info and info.track == parentTrack then
                    parentInfo = info
                    break
                end
            end

            if parentInfo then
                local maxRequired = 0

                for _, child in ipairs(children) do
                    local parentSend = reaper.GetMediaTrackInfo_Value(child.track, "B_MAINSEND")
                    if parentSend == 1 then
                        local actualChannelsUsed = calculateActualChannelsUsed(child, projectTree)
                        maxRequired = math.max(maxRequired, actualChannelsUsed)
                    end

                    for _, send in ipairs(child.sends) do
                        if send.destTrack == parentTrack then
                            local channelNum = Core.parseDstChannel(send.dstChannel)
                            maxRequired = math.max(maxRequired, channelNum)
                        end
                    end
                end

                local maxRequiredEven = maxRequired
                if maxRequiredEven % 2 == 1 then
                    maxRequiredEven = maxRequiredEven + 1
                end

                if maxRequired > parentInfo.channelCount then
                    table.insert(parentInfo.issues, {
                        type = ISSUE_TYPES.PARENT_INSUFFICIENT_CHANNELS,
                        severity = SEVERITY.ERROR,
                        description = string.format("Track '%s' has %d channels but children require up to channel %d (rounded to %d for REAPER even constraint)",
                            parentInfo.name, parentInfo.channelCount, maxRequired, maxRequiredEven),
                        suggestedFix = {
                            action = "set_channel_count",
                            track = parentInfo.track,
                            channels = maxRequiredEven
                        }
                    })
                elseif maxRequiredEven < parentInfo.channelCount then
                    table.insert(parentInfo.issues, {
                        type = ISSUE_TYPES.PARENT_EXCESSIVE_CHANNELS,
                        severity = SEVERITY.WARNING,
                        description = string.format("Track '%s' has %d channels but only needs %d (children use channels 1-%d, rounded to %d for REAPER even constraint)",
                            parentInfo.name, parentInfo.channelCount, maxRequiredEven, maxRequired, maxRequiredEven),
                        suggestedFix = {
                            action = "set_channel_count",
                            track = parentInfo.track,
                            channels = maxRequiredEven
                        }
                    })
                end
            end
        end
    end

    -- Master validation
    if projectTree.master then
        local maxRequired = 2

        for _, trackInfo in pairs(projectTree.allTracks) do
            if trackInfo and trackInfo.channelCount and trackInfo.track ~= projectTree.master.track then
                maxRequired = math.max(maxRequired, trackInfo.channelCount)
            end
        end

        local maxRequiredEven = maxRequired
        if maxRequiredEven % 2 == 1 then
            maxRequiredEven = maxRequiredEven + 1
        end

        if maxRequired > projectTree.master.channelCount then
            table.insert(projectTree.master.issues, {
                type = ISSUE_TYPES.PARENT_INSUFFICIENT_CHANNELS,
                severity = SEVERITY.ERROR,
                description = string.format("Master track has %d channels but needs %d (project has tracks using up to %d channels, rounded to %d for REAPER even constraint)",
                    projectTree.master.channelCount, maxRequiredEven, maxRequired, maxRequiredEven),
                suggestedFix = {
                    action = "set_channel_count",
                    track = projectTree.master.track,
                    channels = maxRequiredEven
                }
            })
        elseif maxRequiredEven < projectTree.master.channelCount then
            table.insert(projectTree.master.issues, {
                type = ISSUE_TYPES.PARENT_EXCESSIVE_CHANNELS,
                severity = SEVERITY.WARNING,
                description = string.format("Master track has %d channels but only needs %d (highest track in project uses %d channels, rounded to %d for REAPER even constraint)",
                    projectTree.master.channelCount, maxRequiredEven, maxRequired, maxRequiredEven),
                suggestedFix = {
                    action = "set_channel_count",
                    track = projectTree.master.track,
                    channels = maxRequiredEven
                }
            })
        end
    end
end

-- ===================================================================
-- CHANNEL REQUIREMENTS CALCULATION
-- ===================================================================

-- Calculate maximum required channels for the entire project
function RoutingValidator_Detection.calculateMaxRequiredChannels(projectTree)
    local maxChannels = 2

    if not globals.Generation then
        return maxChannels
    end

    for _, trackInfo in ipairs(projectTree.toolTracks) do
        if trackInfo.isFromTool then
            local container = Core.findContainerByTrackName(trackInfo.name)

            if container then
                local itemsAnalysis = globals.Generation.analyzeContainerItems(container)
                local trackStructure = globals.Generation.determineTrackStructure(container, itemsAnalysis)

                if trackStructure then
                    local requiredChannels = 0
                    if trackStructure.numTracks == 1 and trackStructure.trackChannels then
                        requiredChannels = trackStructure.trackChannels
                    else
                        requiredChannels = trackStructure.numTracks
                    end
                    maxChannels = math.max(maxChannels, requiredChannels)
                end
            end
        end
    end

    if projectTree.master then
        for _, trackInfo in pairs(projectTree.allTracks) do
            if trackInfo then
                for _, send in ipairs(trackInfo.sends) do
                    if send.destTrack == projectTree.master.track then
                        local channelNum = Core.parseDstChannel(send.dstChannel)
                        if channelNum > 0 then
                            maxChannels = math.max(maxChannels, channelNum)
                        end
                    end
                end
            end
        end
    end

    if maxChannels % 2 == 1 then
        maxChannels = maxChannels + 1
    end

    return maxChannels
end

-- Get required channels for a specific track
function RoutingValidator_Detection.getTrackRequiredChannels(trackInfo)
    if not trackInfo.isFromTool then
        local channels = trackInfo.channelCount
        if channels % 2 == 1 then
            channels = channels + 1
        end
        return channels
    end

    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if trackInfo.name == container.name and container.channelMode and container.channelMode > 0 then
                local config = Constants.CHANNEL_CONFIGS[container.channelMode]
                if config then
                    local channels = config.channels or config.totalChannels or 2
                    if channels % 2 == 1 then
                        channels = channels + 1
                    end
                    return channels
                end
            end
        end
    end

    local maxChildChannel = 0
    for _, send in ipairs(trackInfo.sends) do
        local channelNum = Core.parseDstChannel(send.dstChannel)
        maxChildChannel = math.max(maxChildChannel, channelNum)
    end

    local channels = math.max(trackInfo.channelCount, maxChildChannel)
    if channels % 2 == 1 then
        channels = channels + 1
    end
    return channels
end

-- Validate parent track has enough channels for its children
function RoutingValidator_Detection.validateParentChannelRequirements(parentInfo)
    local ISSUE_TYPES = Core.getIssueTypes()
    local SEVERITY = Core.getSeverity()
    local maxRequiredChannel = 0

    for _, childInfo in ipairs(parentInfo.children) do
        for _, send in ipairs(childInfo.sends) do
            if send.destTrack == parentInfo.track then
                local channelNum = Core.parseDstChannel(send.dstChannel)
                maxRequiredChannel = math.max(maxRequiredChannel, channelNum)
            end
        end

        if childInfo.parent == parentInfo.track then
            local childTrack = childInfo.track
            local parentSend = reaper.GetMediaTrackInfo_Value(childTrack, "B_MAINSEND")

            if parentSend == 1 then
                local requiredChannels = childInfo.channelCount
                maxRequiredChannel = math.max(maxRequiredChannel, requiredChannels)
            end
        end
    end

    if maxRequiredChannel > parentInfo.channelCount then
        table.insert(parentInfo.issues, {
            type = ISSUE_TYPES.PARENT_INSUFFICIENT_CHANNELS,
            severity = SEVERITY.ERROR,
            description = string.format("Track '%s' has %d channels but children require up to channel %d",
                parentInfo.name, parentInfo.channelCount, maxRequiredChannel),
            suggestedFix = {
                action = "set_channel_count",
                track = parentInfo.track,
                channels = maxRequiredChannel
            }
        })
    elseif maxRequiredChannel > 0 and maxRequiredChannel < parentInfo.channelCount then
        table.insert(parentInfo.issues, {
            type = ISSUE_TYPES.PARENT_EXCESSIVE_CHANNELS,
            severity = SEVERITY.WARNING,
            description = string.format("Track '%s' has %d channels but only needs %d (children use channels 1-%d)",
                parentInfo.name, parentInfo.channelCount, maxRequiredChannel, maxRequiredChannel),
            suggestedFix = {
                action = "set_channel_count",
                track = parentInfo.track,
                channels = maxRequiredChannel
            }
        })
    end
end

-- ===================================================================
-- ROUTING ISSUE DETECTION
-- ===================================================================

-- Detect all routing issues in the project
function RoutingValidator_Detection.detectRoutingIssues(projectTree)
    local allIssues = {}

    local channelOrderConflicts = RoutingValidator_Detection.detectChannelOrderConflicts(projectTree)
    for _, conflict in ipairs(channelOrderConflicts) do
        table.insert(allIssues, conflict)
    end

    if #channelOrderConflicts > 0 then
        return allIssues
    end

    for _, trackInfo in pairs(projectTree.allTracks) do
        if trackInfo and #trackInfo.issues > 0 then
            for _, issue in ipairs(trackInfo.issues) do
                issue.track = trackInfo
                table.insert(allIssues, issue)
            end
        end
    end

    local channelConflicts = RoutingValidator_Detection.detectChannelConflicts(projectTree)
    for _, conflict in ipairs(channelConflicts) do
        table.insert(allIssues, conflict)
    end

    local orphanSends = RoutingValidator_Detection.detectOrphanSends(projectTree)
    for _, orphan in ipairs(orphanSends) do
        table.insert(allIssues, orphan)
    end

    return allIssues
end

-- Detect channel conflicts between different containers
function RoutingValidator_Detection.detectChannelConflicts(projectTree)
    local ISSUE_TYPES = Core.getIssueTypes()
    local SEVERITY = Core.getSeverity()
    local conflicts = {}

    if not globals.Generation then
        return conflicts
    end

    local masterFormat = RoutingValidator_Detection.findMasterFormat(projectTree)
    if not masterFormat then
        return conflicts
    end

    local referenceRouting = RoutingValidator_Detection.createReferenceRouting(masterFormat)

    for _, trackInfo in ipairs(projectTree.toolTracks) do
        if trackInfo.isFromTool then
            local channelInfo = RoutingValidator_Detection.getTrackChannelInfo(trackInfo)
            if channelInfo and channelInfo.trackStructure then
                local trackStructure = channelInfo.trackStructure

                local skipStrategies = {
                    ["perfect-match-passthrough"] = true,
                    ["surround-to-quad-skip-center"] = true,
                    ["surround-to-stereo-front-only"] = true,
                    ["surround-unknown-format"] = true,
                    ["mono-distribution"] = true,
                    ["mixed-items-forced-mono"] = true
                }

                if skipStrategies[trackStructure.strategy] then
                    goto continue_channel_check
                end

                local expectedRouting = RoutingValidator_Detection.calculateExpectedRouting(channelInfo, referenceRouting)
                local actualRouting = channelInfo.routing

                for i, expectedChannel in ipairs(expectedRouting) do
                    local actualChannel = actualRouting[i] or 0
                    local label = channelInfo.labels[i] or ("Channel " .. i)

                    if actualChannel ~= expectedChannel then
                        table.insert(conflicts, {
                            type = ISSUE_TYPES.CHANNEL_CONFLICT,
                            severity = SEVERITY.ERROR,
                            description = string.format("Container '%s' has incorrect routing: %s should go to channel %d but goes to %d",
                                trackInfo.name, label, expectedChannel or 0, actualChannel),
                            track = trackInfo,
                            conflictData = {
                                track = trackInfo,
                                channelInfo = channelInfo,
                                expectedRouting = expectedRouting,
                                actualRouting = actualRouting,
                                masterFormat = masterFormat,
                                strategy = trackStructure.strategy
                            }
                        })
                        break
                    end
                end

                ::continue_channel_check::
            end
        end
    end

    return conflicts
end

-- Find the master format (configuration with the most channels)
function RoutingValidator_Detection.findMasterFormat(projectTree)
    local masterFormat = nil
    local maxChannels = 0

    if not globals.Generation then
        return nil
    end

    for _, trackInfo in ipairs(projectTree.toolTracks or {}) do
        if trackInfo.isFromTool then
            local container = Core.findContainerByTrackName(trackInfo.name)

            if container then
                local itemsAnalysis = globals.Generation.analyzeContainerItems(container)
                local trackStructure = globals.Generation.determineTrackStructure(container, itemsAnalysis)

                if trackStructure and trackStructure.numTracks then
                    local requiredChannels = trackStructure.numTracks

                    if requiredChannels > maxChannels then
                        maxChannels = requiredChannels

                        local labels = trackStructure.trackLabels or {}

                        if #labels == 0 and container.channelMode and container.channelMode > 0 then
                            local config = Constants.CHANNEL_CONFIGS[container.channelMode]
                            if config then
                                local activeConfig = config
                                if config.hasVariants then
                                    activeConfig = config.variants[container.channelVariant or 0]
                                end
                                labels = activeConfig.labels or {}
                            end
                        end

                        if #labels == 0 then
                            for i = 1, requiredChannels do
                                table.insert(labels, "Ch" .. i)
                            end
                        end

                        masterFormat = {
                            trackStructure = trackStructure,
                            routing = Core.generateSequentialRouting(requiredChannels),
                            labels = labels,
                            container = container,
                            group = Core.findGroupByContainer(container),
                            realChannelCount = requiredChannels,
                            strategy = trackStructure.strategy
                        }
                    end
                end
            end
        end
    end

    return masterFormat
end

-- Create reference routing table based on master format
function RoutingValidator_Detection.createReferenceRouting(masterFormat)
    local referenceRouting = {}

    if not masterFormat or not masterFormat.labels or not masterFormat.routing then
        return referenceRouting
    end

    for i, label in ipairs(masterFormat.labels) do
        if masterFormat.routing[i] then
            referenceRouting[label] = masterFormat.routing[i]
        end
    end

    return referenceRouting
end

-- Calculate expected routing for a container based on reference routing
function RoutingValidator_Detection.calculateExpectedRouting(channelInfo, referenceRouting)
    local expectedRouting = {}

    if not channelInfo or not channelInfo.labels then
        return expectedRouting
    end

    for i, label in ipairs(channelInfo.labels) do
        local expectedChannel = referenceRouting[label]
        if expectedChannel then
            table.insert(expectedRouting, expectedChannel)
        else
            local fallbackChannel = RoutingValidator_Detection.getFallbackChannelForLabel(label, i)
            table.insert(expectedRouting, fallbackChannel)
        end
    end

    return expectedRouting
end

-- Get fallback channel assignment for a label
function RoutingValidator_Detection.getFallbackChannelForLabel(label, position)
    local standardChannels = {
        ["L"] = 1,
        ["R"] = 2,
        ["C"] = 3,
        ["LFE"] = 4,
        ["LS"] = 4,
        ["RS"] = 5,
        ["SL"] = 6,
        ["SR"] = 7,
        ["TL"] = 8,
        ["TR"] = 9,
    }

    return standardChannels[label] or position
end

-- Get channel information for a track
function RoutingValidator_Detection.getTrackChannelInfo(trackInfo)
    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if trackInfo.name == container.name then
                if not globals.Generation then
                    return nil
                end

                local itemsAnalysis = globals.Generation.analyzeContainerItems(container)
                local trackStructure = globals.Generation.determineTrackStructure(container, itemsAnalysis)

                if not trackStructure then
                    return nil
                end

                local routing = {}
                local labels = {}

                if trackStructure.trackLabels then
                    labels = trackStructure.trackLabels
                    for i = 1, trackStructure.numTracks do
                        table.insert(routing, i)
                    end
                else
                    local outputChannels = globals.Generation.getOutputChannelCount(container.channelMode)
                    local config = Constants.CHANNEL_CONFIGS[container.channelMode]

                    if config then
                        local activeConfig = config
                        if config.hasVariants then
                            activeConfig = config.variants[container.channelVariant or 0]
                        end

                        labels = activeConfig.labels or {}
                        routing = activeConfig.routing or {}
                    else
                        for i = 1, trackStructure.numTracks do
                            table.insert(routing, i)
                            table.insert(labels, "Ch" .. i)
                        end
                    end
                end

                local channelInfo = {
                    trackStructure = trackStructure,
                    routing = routing,
                    labels = labels,
                    channels = {},
                    container = container,
                    group = group
                }

                for i, channelNum in ipairs(routing) do
                    table.insert(channelInfo.channels, {
                        channelNum = channelNum,
                        label = labels[i] or ("Ch" .. i),
                        index = i
                    })
                end

                return channelInfo
            end
        end
    end

    return nil
end

-- Detect orphan sends (sends to channels that don't exist on destination)
function RoutingValidator_Detection.detectOrphanSends(projectTree)
    local ISSUE_TYPES = Core.getIssueTypes()
    local SEVERITY = Core.getSeverity()
    local orphans = {}

    for _, trackInfo in pairs(projectTree.allTracks) do
        if trackInfo then
            for _, send in ipairs(trackInfo.sends) do
                local destTrackInfo = nil
                for _, destInfo in pairs(projectTree.allTracks) do
                    if destInfo and destInfo.track == send.destTrack then
                        destTrackInfo = destInfo
                        break
                    end
                end

                if destTrackInfo then
                    local channelNum = Core.parseDstChannel(send.dstChannel)
                    if channelNum > destTrackInfo.channelCount then
                        table.insert(orphans, {
                            type = ISSUE_TYPES.ORPHAN_SEND,
                            severity = SEVERITY.ERROR,
                            description = string.format("Track '%s' sends to channel %d of '%s', but '%s' only has %d channels",
                                trackInfo.name, channelNum, destTrackInfo.name, destTrackInfo.name, destTrackInfo.channelCount),
                            track = trackInfo,
                            sendData = send,
                            destTrack = destTrackInfo
                        })
                    end
                end
            end
        end
    end

    return orphans
end

return RoutingValidator_Detection
