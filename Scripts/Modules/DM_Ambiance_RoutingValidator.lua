--[[
@version 2.0
@author DM
@description Comprehensive Channel Routing Validator Module
This module validates and corrects the entire project's channel routing hierarchy,
ensuring proper channel allocation, parent-child consistency, and conflict resolution
across all tracks in the project, independent of the tool's internal structure.
@noindex
--]]

local RoutingValidator = {}
local globals = {}
local Constants = require("DM_Ambiance_Constants")

-- Module state variables
local showModal = false
local validationData = nil
local issuesList = nil
local fixSuggestions = nil
local autoFixEnabled = false
local shouldOpenModal = false

-- Channel order resolution modal state
local channelOrderConflictData = nil
local shouldOpenChannelOrderModal = false

-- Cache for performance
local projectTrackCache = nil
local lastValidationTime = 0

-- Initialize the module with global references
function RoutingValidator.initModule(g)
    if not g then
        error("RoutingValidator.initModule: globals parameter is required")
    end
    globals = g

    -- Initialize state
    globals.pendingValidationData = nil
    globals.pendingIssuesList = nil
    globals.autoFixRouting = false  -- Default: manual validation

    -- Initialize cache
    projectTrackCache = nil
    lastValidationTime = 0
end

-- ===================================================================
-- CORE DATA STRUCTURES
-- ===================================================================

-- Track information structure
local function createTrackInfo(track)
    if not track then return nil end

    local trackIdx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
    local trackName = ""
    local retval, name = reaper.GetTrackName(track)
    if retval then trackName = name end

    return {
        track = track,
        index = trackIdx,
        name = trackName,
        channelCount = reaper.GetMediaTrackInfo_Value(track, "I_NCHAN"),
        parent = reaper.GetParentTrack(track),
        children = {},
        sends = {},
        receives = {},
        issues = {},
        isMaster = (track == reaper.GetMasterTrack(0)),
        isFromTool = false  -- Will be determined by analyzing track names
    }
end

-- Issue types
local ISSUE_TYPES = {
    CHANNEL_CONFLICT = "channel_conflict",
    PARENT_INSUFFICIENT_CHANNELS = "parent_insufficient_channels",
    PARENT_EXCESSIVE_CHANNELS = "parent_excessive_channels",  -- NEW: Track has more channels than needed
    ORPHAN_SEND = "orphan_send",
    CIRCULAR_ROUTING = "circular_routing",
    DOWNMIX_ERROR = "downmix_error",
    MISSING_CHANNELS = "missing_channels",
    INVALID_ROUTING = "invalid_routing",
    CHANNEL_ORDER_CONFLICT = "channel_order_conflict"
}

-- Issue severity levels
local SEVERITY = {
    ERROR = "error",
    WARNING = "warning",
    INFO = "info"
}

-- ===================================================================
-- PROJECT SCANNING AND ANALYSIS
-- ===================================================================

-- Main validation function - validates entire project routing
-- Clear the validation cache to force a fresh scan
function RoutingValidator.clearCache()
    projectTrackCache = nil
    lastValidationTime = 0
end

function RoutingValidator.validateProjectRouting()
    -- CRITICAL: Skip validation if downgrade operation is in progress
    if globals.skipRoutingValidation then
        -- reaper.ShowConsoleMsg("INFO: RoutingValidator: Validation skipped (downgrade in progress)\n")
        return {}
    end

    local startTime = reaper.time_precise()

    -- Skip if validation was done recently (performance optimization)
    if projectTrackCache and (startTime - lastValidationTime) < 1.0 then
        return issuesList
    end

    reaper.PreventUIRefresh(1)

    -- Step 1: Scan all tracks in project
    local projectTree = RoutingValidator.scanAllProjectTracks()

    -- Step 2: Analyze track hierarchy and relationships
    RoutingValidator.analyzeTrackHierarchy(projectTree)

    -- Step 3: Validate channel consistency
    RoutingValidator.validateChannelConsistency(projectTree)

    -- Step 4: Detect routing issues
    issuesList = RoutingValidator.detectRoutingIssues(projectTree)

    -- Step 5: Generate fix suggestions
    fixSuggestions = RoutingValidator.generateFixSuggestions(issuesList, projectTree)

    -- Cache results
    projectTrackCache = projectTree
    lastValidationTime = startTime

    reaper.PreventUIRefresh(-1)

    return issuesList
end

-- Scan all tracks in the project and build the track tree
function RoutingValidator.scanAllProjectTracks()
    local projectTree = {
        master = nil,
        topLevelTracks = {},
        allTracks = {},
        toolTracks = {},  -- Tracks created by our tool
        globalIssues = {}
    }

    -- Get master track
    local masterTrack = reaper.GetMasterTrack(0)
    if masterTrack then
        projectTree.master = createTrackInfo(masterTrack)
        projectTree.allTracks[0] = projectTree.master
    end

    -- Scan all project tracks
    local trackCount = reaper.CountTracks(0)
    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local trackInfo = createTrackInfo(track)

            -- Determine if this track was created by our tool
            trackInfo.isFromTool = RoutingValidator.isToolTrack(track)

            projectTree.allTracks[i + 1] = trackInfo

            if trackInfo.isFromTool then
                table.insert(projectTree.toolTracks, trackInfo)
            end

            -- Collect top-level tracks (no parent)
            if not trackInfo.parent then
                table.insert(projectTree.topLevelTracks, trackInfo)
            end
        end
    end

    return projectTree
end

-- Determine if a track was created by our tool (based on naming patterns)
function RoutingValidator.isToolTrack(track)
    local retval, trackName = reaper.GetTrackName(track)
    if not retval or trackName == "" then return false end

    -- Check if track name matches any group/container names
    for _, group in ipairs(globals.groups or {}) do
        if trackName == group.name then
            return true
        end

        for _, container in ipairs(group.containers or {}) do
            if trackName == container.name then
                return true
            end

            -- Check for channel track naming pattern (e.g., "Container L", "Container R")
            local channelLabels = {"L", "R", "C", "LFE", "LS", "RS", "SL", "SR", "TL", "TR", "TFL", "TFR", "TBL", "TBR", "FWL", "FWR"}
            for _, label in ipairs(channelLabels) do
                if trackName == container.name .. " " .. label then
                    return true
                end
            end
        end
    end

    return false
end

-- ===================================================================
-- CHANNEL ORDER CONFLICT DETECTION
-- ===================================================================

-- Detect channel order conflicts across containers (OUTPUT + SOURCE variants)
function RoutingValidator.detectChannelOrderConflicts(projectTree)
    local conflicts = {}
    local outputVariants = {}  -- [channelMode] = {variant, containers} for OUTPUT (channelVariant)
    local sourceVariants = {}  -- [channelMode] = {variant, containers} for SOURCE (sourceChannelVariant)

    -- Scan all groups/containers for OUTPUT and SOURCE variant conflicts
    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if container.channelMode and container.channelMode > 0 then
                local config = Constants.CHANNEL_CONFIGS[container.channelMode]
                if config and config.hasVariants then
                    local channelMode = config.channels  -- 5 or 7

                    -- CHECK 1: OUTPUT variant conflicts (channelVariant)
                    local outputVariant = container.channelVariant or 0

                    if not outputVariants[channelMode] then
                        outputVariants[channelMode] = {
                            variant = outputVariant,
                            containers = {container},
                            group = group
                        }
                    else
                        if outputVariants[channelMode].variant ~= outputVariant then
                            -- OUTPUT CONFLICT DETECTED!
                            local existingInfo = outputVariants[channelMode]
                            local existingVariantName = RoutingValidator.getVariantName(channelMode, existingInfo.variant)
                            local newVariantName = RoutingValidator.getVariantName(channelMode, outputVariant)

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

                            return conflicts  -- Return immediately - critical error
                        else
                            table.insert(outputVariants[channelMode].containers, container)
                        end
                    end
                end

                -- CHECK 2: SOURCE variant conflicts (sourceChannelVariant) - ONLY if specified
                -- This applies to containers with items that are 5.0/7.0
                if container.sourceChannelVariant ~= nil and container.items and #container.items > 0 then
                    -- Determine if items are 5.0 or 7.0
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
                                -- SOURCE CONFLICT DETECTED! (CRITICAL)
                                local existingInfo = sourceVariants[itemChannelMode]
                                local existingVariantName = RoutingValidator.getVariantName(itemChannelMode, existingInfo.variant)
                                local newVariantName = RoutingValidator.getVariantName(itemChannelMode, sourceVariant)

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
                                        isCritical = true  -- Flag as unresolvable
                                    }
                                })

                                return conflicts  -- Return immediately - critical error
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

-- Get channel mode from track name (5.0, 7.0, etc.)
function RoutingValidator.getChannelModeFromTrackName(trackName)
    -- Find corresponding container configuration
    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if trackName == container.name and container.channelMode and container.channelMode > 0 then
                local config = Constants.CHANNEL_CONFIGS[container.channelMode]
                if config then
                    return config.channels  -- Return 4, 5, or 7
                end
            end
        end
    end
    return nil
end

-- Find container by track name
function RoutingValidator.findContainerByTrackName(trackName)
    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if trackName == container.name then
                return container
            end
        end
    end
    return nil
end

-- Get variant name (SMPTE or Dolby/ITU)
function RoutingValidator.getVariantName(channelMode, variant)
    -- Map channel count to config key
    local configKeys = {
        [5] = 5,  -- 5.0
        [7] = 7   -- 7.0
    }

    local configKey = configKeys[channelMode]
    if not configKey then return "Unknown" end

    local config = Constants.CHANNEL_CONFIGS[configKey]
    if config and config.hasVariants and config.variants and config.variants[variant] then
        return config.variants[variant].name or "Unknown"
    end

    -- Fallback names if constants are not available
    if channelMode == 5 then
        return variant == 0 and "SMPTE (L C R LS RS)" or "Dolby/ITU (L R C LS RS)"
    elseif channelMode == 7 then
        return variant == 0 and "SMPTE (L C R LS RS SL SR)" or "Dolby/ITU (L R C LS RS SL SR)"
    end

    return "Unknown"
end

-- Analyze track hierarchy and build parent-child relationships
function RoutingValidator.analyzeTrackHierarchy(projectTree)
    -- Build parent-child relationships
    for _, trackInfo in pairs(projectTree.allTracks) do
        if trackInfo and trackInfo.parent then
            -- Find parent in our track info structure
            for _, parentInfo in pairs(projectTree.allTracks) do
                if parentInfo and parentInfo.track == trackInfo.parent then
                    table.insert(parentInfo.children, trackInfo)
                    break
                end
            end
        end
    end

    -- Analyze sends and receives for all tracks
    for _, trackInfo in pairs(projectTree.allTracks) do
        if trackInfo and trackInfo.track then
            RoutingValidator.analyzeSendsAndReceives(trackInfo)
        end
    end
end

-- Analyze sends and receives for a specific track
function RoutingValidator.analyzeSendsAndReceives(trackInfo)
    local track = trackInfo.track

    -- Analyze sends (0 = track sends, -1 = hardware sends)
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

-- Validate channel consistency across the entire project
function RoutingValidator.validateChannelConsistency(projectTree)
    -- Check master track has sufficient channels
    if projectTree.master then
        local maxRequiredChannels = RoutingValidator.calculateMaxRequiredChannels(projectTree)
        if projectTree.master.channelCount < maxRequiredChannels then
            table.insert(projectTree.master.issues, {
                type = ISSUE_TYPES.PARENT_INSUFFICIENT_CHANNELS,
                severity = SEVERITY.ERROR,
                description = string.format("Master track has %d channels but needs %d",
                    projectTree.master.channelCount, maxRequiredChannels),
                suggestedFix = {
                    action = "set_channel_count",
                    track = projectTree.master.track,
                    channels = maxRequiredChannels
                }
            })
        elseif projectTree.master.channelCount > maxRequiredChannels and maxRequiredChannels >= 2 then
            -- Master has more channels than needed - suggest reduction
            table.insert(projectTree.master.issues, {
                type = ISSUE_TYPES.PARENT_EXCESSIVE_CHANNELS,
                severity = SEVERITY.WARNING,
                description = string.format("Master track has %d channels but only needs %d",
                    projectTree.master.channelCount, maxRequiredChannels),
                suggestedFix = {
                    action = "set_channel_count",
                    track = projectTree.master.track,
                    channels = maxRequiredChannels
                }
            })
        end
    end

    -- Validate each track's channel requirements
    for _, trackInfo in pairs(projectTree.allTracks) do
        if trackInfo and #trackInfo.children > 0 then
            RoutingValidator.validateParentChannelRequirements(trackInfo)
        end
    end
end

-- Calculate maximum required channels for the entire project
-- NEW ARCHITECTURE: Uses trackStructure.numTracks as the source of truth
function RoutingValidator.calculateMaxRequiredChannels(projectTree)
    local maxChannels = 2  -- Minimum stereo

    if not globals.Generation then
        return maxChannels
    end

    -- Check tool tracks using NEW ARCHITECTURE
    for _, trackInfo in ipairs(projectTree.toolTracks) do
        if trackInfo.isFromTool then
            local container = RoutingValidator.findContainerByTrackName(trackInfo.name)

            if container then
                -- Use trackStructure to determine required channels
                local itemsAnalysis = globals.Generation.analyzeContainerItems(container)
                local trackStructure = globals.Generation.determineTrackStructure(container, itemsAnalysis)

                if trackStructure then
                    -- CRITICAL FIX: Use the actual channel count, not the number of tracks
                    -- For single-track multi-channel (e.g., perfect-match-passthrough):
                    --   numTracks = 1, trackChannels = 4 → need 4 channels
                    -- For multi-track mono (e.g., 4 mono child tracks):
                    --   numTracks = 4, trackChannels = 1 → need 4 channels
                    local requiredChannels = 0
                    if trackStructure.numTracks == 1 and trackStructure.trackChannels then
                        -- Single multi-channel track
                        requiredChannels = trackStructure.trackChannels
                    else
                        -- Multiple tracks (each routing to a channel)
                        requiredChannels = trackStructure.numTracks
                    end
                    maxChannels = math.max(maxChannels, requiredChannels)
                end
            end
        end
    end

    -- Check all sends to master
    if projectTree.master then
        for _, trackInfo in pairs(projectTree.allTracks) do
            if trackInfo then
                for _, send in ipairs(trackInfo.sends) do
                    if send.destTrack == projectTree.master.track then
                        local channelNum = RoutingValidator.parseDstChannel(send.dstChannel)
                        if channelNum > 0 then
                            maxChannels = math.max(maxChannels, channelNum)
                        end
                    end
                end
            end
        end
    end

    -- REAPER constraint: channel counts must be even numbers
    -- Round up to next even number if odd
    if maxChannels % 2 == 1 then
        maxChannels = maxChannels + 1
    end

    return maxChannels
end

-- Get required channels for a specific track based on its configuration
function RoutingValidator.getTrackRequiredChannels(trackInfo)
    if not trackInfo.isFromTool then
        local channels = trackInfo.channelCount
        -- Apply REAPER even constraint
        if channels % 2 == 1 then
            channels = channels + 1
        end
        return channels
    end

    -- Check if this is a container track from our tool
    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if trackInfo.name == container.name and container.channelMode and container.channelMode > 0 then
                local config = Constants.CHANNEL_CONFIGS[container.channelMode]
                if config then
                    local channels = config.channels or config.totalChannels or 2
                    -- Apply REAPER even constraint
                    if channels % 2 == 1 then
                        channels = channels + 1
                    end
                    return channels
                end
            end
        end
    end

    -- Calculate based on child tracks
    local maxChildChannel = 0
    for _, send in ipairs(trackInfo.sends) do
        local channelNum = RoutingValidator.parseDstChannel(send.dstChannel)
        maxChildChannel = math.max(maxChildChannel, channelNum)
    end

    local channels = math.max(trackInfo.channelCount, maxChildChannel)
    -- Apply REAPER even constraint
    if channels % 2 == 1 then
        channels = channels + 1
    end
    return channels
end

-- Parse REAPER's destination channel format
-- Returns the HIGHEST channel number used by this send (1-based)
function RoutingValidator.parseDstChannel(dstChan)
    if dstChan >= 1024 then
        -- Mono routing: 1024 + channel (0-based) = channel number (1-based)
        return (dstChan - 1024) + 1
    elseif dstChan >= 0 then
        -- Stereo pair routing: dstChan is the starting channel (0-based)
        -- A stereo pair uses 2 consecutive channels
        -- dstChan = 0 → channels 1-2 → highest = 2
        -- dstChan = 2 → channels 3-4 → highest = 4
        -- dstChan = 4 → channels 5-6 → highest = 6
        return dstChan + 2
    else
        return 1  -- Default
    end
end

-- Validate parent track has enough channels for its children
function RoutingValidator.validateParentChannelRequirements(parentInfo)
    local maxRequiredChannel = 0

    -- Check all sends from children to this parent
    for _, childInfo in ipairs(parentInfo.children) do
        for _, send in ipairs(childInfo.sends) do
            if send.destTrack == parentInfo.track then
                local channelNum = RoutingValidator.parseDstChannel(send.dstChannel)
                maxRequiredChannel = math.max(maxRequiredChannel, channelNum)
            end
        end

        -- CRITICAL FIX: Check folder parent routing (implicit routing)
        -- When a track is inside a folder, it automatically routes to the folder parent
        -- even without explicit sends. We need to check if the child's channel count
        -- requires more channels than the parent has.
        if childInfo.parent == parentInfo.track then
            -- This child implicitly routes to this parent via folder structure
            -- Check if child uses "Parent channel" routing (default behavior)
            local childTrack = childInfo.track
            local parentSend = reaper.GetMediaTrackInfo_Value(childTrack, "B_MAINSEND")

            if parentSend == 1 then
                -- Parent send is enabled (default behavior)
                -- Child channels route to parent: child needs parent to have at least as many channels
                -- Note: In REAPER folder routing, child's full channel count routes to parent
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
        -- Parent has more channels than needed - suggest reduction
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

-- Detect all routing issues in the project
function RoutingValidator.detectRoutingIssues(projectTree)
    local allIssues = {}

    -- PRIORITY 1: Detect channel order conflicts first (must be resolved before other checks)
    local channelOrderConflicts = RoutingValidator.detectChannelOrderConflicts(projectTree)
    for _, conflict in ipairs(channelOrderConflicts) do
        table.insert(allIssues, conflict)
    end

    -- If there are channel order conflicts, return early - they must be resolved first
    if #channelOrderConflicts > 0 then
        return allIssues
    end

    -- PRIORITY 2: Collect issues from all tracks
    for _, trackInfo in pairs(projectTree.allTracks) do
        if trackInfo and #trackInfo.issues > 0 then
            for _, issue in ipairs(trackInfo.issues) do
                issue.track = trackInfo
                table.insert(allIssues, issue)
            end
        end
    end

    -- PRIORITY 3: Detect channel conflicts (same channel used by different sources for different purposes)
    local channelConflicts = RoutingValidator.detectChannelConflicts(projectTree)
    for _, conflict in ipairs(channelConflicts) do
        table.insert(allIssues, conflict)
    end

    -- PRIORITY 4: Detect orphan sends (sends to non-existent channels)
    local orphanSends = RoutingValidator.detectOrphanSends(projectTree)
    for _, orphan in ipairs(orphanSends) do
        table.insert(allIssues, orphan)
    end

    -- PRIORITY 5: Downmix error detection REMOVED - Now handled by auto-optimization
    -- The new trackStructure system automatically handles downmix via Channel Selection modes

    return allIssues
end

-- Detect channel conflicts between different containers using master format logic
-- NEW ARCHITECTURE: Understands trackStructure strategies
function RoutingValidator.detectChannelConflicts(projectTree)
    local conflicts = {}

    if not globals.Generation then
        return conflicts
    end

    -- Step 1: Find the master format (highest channel count)
    local masterFormat = RoutingValidator.findMasterFormat(projectTree)
    if not masterFormat then
        return conflicts  -- No multi-channel formats to conflict
    end

    -- Step 2: Create the reference routing table based on master format
    local referenceRouting = RoutingValidator.createReferenceRouting(masterFormat)

    -- Step 3: Check all containers against the reference routing
    for _, trackInfo in ipairs(projectTree.toolTracks) do
        if trackInfo.isFromTool then
            local channelInfo = RoutingValidator.getTrackChannelInfo(trackInfo)
            if channelInfo and channelInfo.trackStructure then
                local trackStructure = channelInfo.trackStructure

                -- NEW: Skip validation for certain strategies that are INTENTIONAL
                local skipStrategies = {
                    ["perfect-match-passthrough"] = true,  -- No routing needed
                    ["surround-to-quad-skip-center"] = true,  -- Intentionally skips center
                    ["surround-to-stereo-front-only"] = true,  -- Intentionally uses L/R only
                    ["surround-unknown-format"] = true,  -- User hasn't specified format yet
                    ["mono-distribution"] = true,  -- Mono items distributed across tracks
                    ["mixed-items-forced-mono"] = true  -- Mixed items, forced to mono
                }

                if skipStrategies[trackStructure.strategy] then
                    -- These strategies are intentional, not conflicts
                    goto continue_channel_check
                end

                -- Calculate expected routing based on master format
                local expectedRouting = RoutingValidator.calculateExpectedRouting(channelInfo, referenceRouting)
                local actualRouting = channelInfo.routing

                -- Compare expected vs actual routing
                for i, expectedChannel in ipairs(expectedRouting) do
                    local actualChannel = actualRouting[i] or 0
                    local label = channelInfo.labels[i] or ("Channel " .. i)

                    if actualChannel ~= expectedChannel then
                        -- Conflict detected!
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
                        break  -- One conflict per container is enough
                    end
                end

                ::continue_channel_check::
            end
        end
    end

    return conflicts
end

-- Find the master format (configuration with the most channels)
-- NEW ARCHITECTURE: Uses trackStructure.numTracks instead of real child count
function RoutingValidator.findMasterFormat(projectTree)
    local masterFormat = nil
    local maxChannels = 0

    if not globals.Generation then
        return nil
    end

    -- Scan tool tracks and use trackStructure to determine required channels
    for _, trackInfo in ipairs(projectTree.toolTracks or {}) do
        if trackInfo.isFromTool then
            local container = RoutingValidator.findContainerByTrackName(trackInfo.name)

            if container then
                -- NEW ARCHITECTURE: Use trackStructure to determine channel count
                local itemsAnalysis = globals.Generation.analyzeContainerItems(container)
                local trackStructure = globals.Generation.determineTrackStructure(container, itemsAnalysis)

                if trackStructure and trackStructure.numTracks then
                    local requiredChannels = trackStructure.numTracks

                    if requiredChannels > maxChannels then
                        maxChannels = requiredChannels

                        -- Build labels based on trackStructure
                        local labels = trackStructure.trackLabels or {}

                        -- Fallback to config labels if trackStructure doesn't have them
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

                        -- Final fallback: generic labels
                        if #labels == 0 then
                            for i = 1, requiredChannels do
                                table.insert(labels, "Ch" .. i)
                            end
                        end

                        masterFormat = {
                            trackStructure = trackStructure,
                            routing = RoutingValidator.generateSequentialRouting(requiredChannels),
                            labels = labels,
                            container = container,
                            group = RoutingValidator.findGroupByContainer(container),
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

-- Get the REAL number of child tracks for a container track
function RoutingValidator.getRealChildTrackCount(trackInfo)
    if not trackInfo or not trackInfo.track then return 0 end

    local containerTrack = trackInfo.track
    local containerIdx = reaper.GetMediaTrackInfo_Value(containerTrack, "IP_TRACKNUMBER") - 1

    -- Check if it's a folder
    local folderDepth = reaper.GetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH")
    if folderDepth ~= 1 then
        return 0  -- Not a folder
    end

    -- Count direct children
    local childCount = 0
    local trackIdx = containerIdx + 1
    local depth = 1

    while trackIdx < reaper.CountTracks(0) and depth > 0 do
        local track = reaper.GetTrack(0, trackIdx)
        if not track then break end

        local parent = reaper.GetParentTrack(track)
        if parent == containerTrack then
            childCount = childCount + 1
        end

        local trackDepth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        depth = depth + trackDepth
        trackIdx = trackIdx + 1
    end

    return childCount
end

-- Generate sequential routing for a given channel count (1,2,3,4...)
function RoutingValidator.generateSequentialRouting(channelCount)
    local routing = {}
    for i = 1, channelCount do
        table.insert(routing, i)
    end
    return routing
end

-- Generate appropriate labels for a channel count based on configuration
function RoutingValidator.generateLabelsForChannelCount(channelCount, baseConfig)
    if channelCount == 2 then
        return {"L", "R"}
    elseif channelCount == 4 then
        return {"L", "R", "LS", "RS"}  -- 4.0 Quad
    elseif channelCount == 5 then
        -- Use base config to determine variant if available
        if baseConfig and baseConfig.hasVariants then
            local defaultVariant = baseConfig.variants[0]
            if defaultVariant and defaultVariant.labels then
                return defaultVariant.labels
            end
        end
        return {"L", "R", "C", "LS", "RS"}  -- Default 5.0
    elseif channelCount == 7 then
        -- Use base config to determine variant if available
        if baseConfig and baseConfig.hasVariants then
            local defaultVariant = baseConfig.variants[0]
            if defaultVariant and defaultVariant.labels then
                return defaultVariant.labels
            end
        end
        return {"L", "R", "C", "LS", "RS", "LB", "RB"}  -- Default 7.0
    else
        -- Fallback: generate generic labels
        local labels = {}
        for i = 1, channelCount do
            table.insert(labels, "Ch" .. i)
        end
        return labels
    end
end

-- Find group containing a specific container
function RoutingValidator.findGroupByContainer(targetContainer)
    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if container == targetContainer then
                return group
            end
        end
    end
    return nil
end

-- Create reference routing table based on master format
function RoutingValidator.createReferenceRouting(masterFormat)
    local referenceRouting = {}

    if not masterFormat or not masterFormat.labels or not masterFormat.routing then
        return referenceRouting
    end

    -- Map each label to its channel position in the master format
    for i, label in ipairs(masterFormat.labels) do
        if masterFormat.routing[i] then
            referenceRouting[label] = masterFormat.routing[i]
        end
    end

    return referenceRouting
end

-- Calculate expected routing for a container based on reference routing
function RoutingValidator.calculateExpectedRouting(channelInfo, referenceRouting)
    local expectedRouting = {}

    if not channelInfo or not channelInfo.labels then
        return expectedRouting
    end

    for i, label in ipairs(channelInfo.labels) do
        local expectedChannel = referenceRouting[label]
        if expectedChannel then
            table.insert(expectedRouting, expectedChannel)
        else
            -- Fallback: try to maintain logical channel positioning
            local fallbackChannel = RoutingValidator.getFallbackChannelForLabel(label, i)
            table.insert(expectedRouting, fallbackChannel)
        end
    end

    return expectedRouting
end

-- Get channel information for a track (labels and routing) using NEW ARCHITECTURE
function RoutingValidator.getTrackChannelInfo(trackInfo)
    -- Find corresponding container configuration
    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if trackInfo.name == container.name then
                -- Use NEW ARCHITECTURE: Analyze items and determine track structure
                if not globals.Generation then
                    return nil
                end

                local itemsAnalysis = globals.Generation.analyzeContainerItems(container)
                local trackStructure = globals.Generation.determineTrackStructure(container, itemsAnalysis)

                if not trackStructure then
                    return nil
                end

                -- Build routing and labels based on trackStructure
                local routing = {}
                local labels = {}

                if trackStructure.trackLabels then
                    -- Use track labels from structure
                    labels = trackStructure.trackLabels
                    -- Generate sequential routing based on number of tracks
                    for i = 1, trackStructure.numTracks do
                        table.insert(routing, i)
                    end
                else
                    -- Fallback: use output format configuration
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
                        -- Generic fallback
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
function RoutingValidator.detectOrphanSends(projectTree)
    local orphans = {}

    for _, trackInfo in pairs(projectTree.allTracks) do
        if trackInfo then
            for _, send in ipairs(trackInfo.sends) do
                -- Find destination track info
                local destTrackInfo = nil
                for _, destInfo in pairs(projectTree.allTracks) do
                    if destInfo and destInfo.track == send.destTrack then
                        destTrackInfo = destInfo
                        break
                    end
                end

                if destTrackInfo then
                    local channelNum = RoutingValidator.parseDstChannel(send.dstChannel)
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

-- OBSOLETE: detectDownmixErrors() removed
-- Downmix is now handled automatically by the new trackStructure system
-- via Channel Selection modes (Auto/Stereo Pairs/Mono Split) and smart routing

-- ===================================================================
-- AUTOMATIC FIXING AND SUGGESTIONS
-- ===================================================================

-- Generate fix suggestions for all detected issues
function RoutingValidator.generateFixSuggestions(issuesList, projectTree)
    local suggestions = {}

    for _, issue in ipairs(issuesList) do
        local suggestion = RoutingValidator.generateFixSuggestion(issue, projectTree)
        if suggestion then
            table.insert(suggestions, suggestion)
        end
    end

    return suggestions
end

-- Generate a fix suggestion for a specific issue
function RoutingValidator.generateFixSuggestion(issue, projectTree)
    if issue.type == ISSUE_TYPES.CHANNEL_ORDER_CONFLICT then
        return RoutingValidator.suggestChannelOrderFix(issue, projectTree)
    elseif issue.type == ISSUE_TYPES.CHANNEL_CONFLICT then
        return RoutingValidator.suggestChannelConflictFix(issue, projectTree)
    elseif issue.type == ISSUE_TYPES.PARENT_INSUFFICIENT_CHANNELS then
        return issue.suggestedFix  -- Already included in issue
    elseif issue.type == ISSUE_TYPES.PARENT_EXCESSIVE_CHANNELS then
        return issue.suggestedFix  -- Already included in issue
    elseif issue.type == ISSUE_TYPES.ORPHAN_SEND then
        return RoutingValidator.suggestOrphanSendFix(issue, projectTree)
    -- DOWNMIX_ERROR removed - handled by auto-optimization
    end

    return nil
end

-- Suggest fix for channel order conflicts (special handling - requires user choice)
function RoutingValidator.suggestChannelOrderFix(issue, projectTree)
    local conflictData = issue.conflictData

    -- Channel order conflicts require user intervention
    -- We can't automatically choose which variant to use
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
                affectedContainers = {conflictData.container2},  -- Change container2 to match container1
                reason = string.format("Use %s for all %s.0 containers",
                    conflictData.variantName1, conflictData.channelMode)
            },
            {
                action = "use_variant_2",
                variant = conflictData.variant2,
                variantName = conflictData.variantName2,
                affectedContainers = conflictData.allContainersWithVariant1,  -- Change all existing to match container2
                reason = string.format("Use %s for all %s.0 containers",
                    conflictData.variantName2, conflictData.channelMode)
            }
        }
    }
end

-- Suggest fix for channel conflicts using master format alignment
function RoutingValidator.suggestChannelConflictFix(issue, projectTree)
    local conflictData = issue.conflictData
    local track = conflictData.track
    local expectedRouting = conflictData.expectedRouting

    return {
        action = "reroute_container",
        track = track,
        newRouting = expectedRouting,
        reason = string.format("Align '%s' with master format (%s): %s",
            track.name,
            conflictData.masterFormat.config.name or "Master",
            table.concat(expectedRouting, ", "))
    }
end

-- Suggest fix for orphan sends
function RoutingValidator.suggestOrphanSendFix(issue, projectTree)
    return {
        action = "increase_parent_channels",
        track = issue.destTrack.track,
        channels = RoutingValidator.parseDstChannel(issue.sendData.dstChannel),
        reason = string.format("Increase channels to accommodate send from %s", issue.track.name)
    }
end

-- Suggest fix for downmix errors
function RoutingValidator.suggestDownmixFix(issue, projectTree)
    local channelInfo = issue.channelInfo

    -- Suggest proper downmix routing
    local properRouting = RoutingValidator.generateProperDownmix(channelInfo)

    return {
        action = "apply_proper_downmix",
        track = issue.track,
        newRouting = properRouting,
        reason = "Apply proper downmix routing"
    }
end


-- Generate proper downmix routing for a configuration
function RoutingValidator.generateProperDownmix(channelInfo)
    -- This is a simplified example - in practice, this would implement
    -- sophisticated downmix algorithms based on channel configuration

    local config = channelInfo.config
    local newRouting = {}

    -- For now, just implement a basic downmix strategy
    if config.channels >= 5 then
        -- 5.0+ to stereo downmix
        for i, label in ipairs(channelInfo.labels) do
            if label == "L" then
                table.insert(newRouting, 1)
            elseif label == "R" then
                table.insert(newRouting, 2)
            elseif label == "C" then
                table.insert(newRouting, 1)  -- Center to left (could be phantom)
            elseif label == "LS" then
                table.insert(newRouting, 1)  -- Left surround to left
            elseif label == "RS" then
                table.insert(newRouting, 2)  -- Right surround to right
            else
                table.insert(newRouting, (i % 2) + 1)  -- Alternate L/R for other channels
            end
        end
    else
        -- Keep original routing
        newRouting = channelInfo.routing
    end

    return newRouting
end

-- Get fallback channel assignment for a label when not found in master format
function RoutingValidator.getFallbackChannelForLabel(label, position)
    -- Standard channel assignments based on common conventions
    local standardChannels = {
        ["L"] = 1,
        ["R"] = 2,
        ["C"] = 3,
        ["LFE"] = 4,
        ["LS"] = 4,  -- Left surround (when no LFE)
        ["RS"] = 5,  -- Right surround
        ["SL"] = 6,  -- Side left
        ["SR"] = 7,  -- Side right
        ["TL"] = 8,  -- Top left
        ["TR"] = 9,  -- Top right
    }

    return standardChannels[label] or position
end

-- Apply all fix suggestions automatically
function RoutingValidator.autoFixRouting(issuesList, fixSuggestions)
    if not fixSuggestions or #fixSuggestions == 0 then
        return false
    end

    reaper.Undo_BeginBlock()

    local allSuccess = true

    for _, suggestion in ipairs(fixSuggestions) do
        local success = RoutingValidator.applySingleFix(suggestion, true)  -- Pass autoMode = true
        if not success then
            allSuccess = false
        end
    end

    reaper.Undo_EndBlock("Auto-fix Channel Routing Issues", -1)

    -- Clear cache to force re-validation
    projectTrackCache = nil

    return allSuccess
end

-- Apply a single fix suggestion
function RoutingValidator.applySingleFix(suggestion, autoMode)
    if suggestion.action == "resolve_channel_order_conflict" then
        if autoMode then
            -- In auto-fix mode, automatically choose the first variant
            local firstOption = suggestion.options and suggestion.options[1]
            if firstOption then
                return RoutingValidator.applyChannelOrderChoice(firstOption.variant, suggestion.conflictData.channelMode)
            end
            return false
        else
            -- In manual mode, show modal for user choice
            RoutingValidator.showChannelOrderResolutionModal(suggestion)
            return false  -- Return false because user needs to choose
        end

    elseif suggestion.action == "apply_channel_order_choice" then
        return RoutingValidator.applyChannelOrderChoice(suggestion)

    elseif suggestion.action == "set_channel_count" then
        local channels = suggestion.channels
        -- Apply REAPER even constraint
        if channels % 2 == 1 then
            channels = channels + 1
        end

        reaper.SetMediaTrackInfo_Value(suggestion.track, "I_NCHAN", channels)
        reaper.UpdateArrange()
        return true

    elseif suggestion.action == "reroute_container" then
        return RoutingValidator.applyNewRouting(suggestion.track, suggestion.newRouting)

    elseif suggestion.action == "increase_parent_channels" then
        local channels = suggestion.channels
        -- Apply REAPER even constraint
        if channels % 2 == 1 then
            channels = channels + 1
        end

        reaper.SetMediaTrackInfo_Value(suggestion.track, "I_NCHAN", channels)
        reaper.UpdateArrange()
        return true

    elseif suggestion.action == "apply_proper_downmix" then
        return RoutingValidator.applyNewRouting(suggestion.track, suggestion.newRouting)
    end

    return false
end

-- Apply new routing to a container track
function RoutingValidator.applyNewRouting(containerTrackInfo, newRouting)
    local containerTrack = containerTrackInfo.track

    -- Update container's channel count with REAPER even constraint
    local maxChannel = math.max(table.unpack(newRouting))

    -- Apply REAPER constraint: channel counts must be even
    if maxChannel % 2 == 1 then
        maxChannel = maxChannel + 1
    end

    local oldChannels = reaper.GetMediaTrackInfo_Value(containerTrack, "I_NCHAN")

    -- MEGATHINK: Comprehensive track identification logging
    local trackGUID = reaper.GetTrackGUID(containerTrack)
    local trackNumber = reaper.GetMediaTrackInfo_Value(containerTrack, "IP_TRACKNUMBER")
    local trackName = reaper.GetTrackName(containerTrack) or "unnamed"

    -- reaper.ShowConsoleMsg(string.format("ROUTING FIX: Track verification for '%s'\n", containerTrackInfo.name or "unknown"))
    -- reaper.ShowConsoleMsg(string.format("  GUID: %s\n", trackGUID or "nil"))
    -- reaper.ShowConsoleMsg(string.format("  Track Number: %d\n", trackNumber))
    -- reaper.ShowConsoleMsg(string.format("  Track Name: '%s'\n", trackName))
    -- reaper.ShowConsoleMsg(string.format("  Current Channels: %d → Target: %d\n", oldChannels, maxChannel))

    -- Check for duplicate track names that might cause confusion
    local duplicateCount = 0
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local name = reaper.GetTrackName(track) or "unnamed"
        if name == trackName then
            duplicateCount = duplicateCount + 1
        end
    end
    -- if duplicateCount > 1 then
    --     reaper.ShowConsoleMsg(string.format("  WARNING: Found %d tracks with name '%s'\n", duplicateCount, trackName))
    -- end

    -- CRITICAL FIX: Wrap in Undo block to ensure changes are committed to REAPER
    reaper.Undo_BeginBlock()

    -- Apply the change
    local success = reaper.SetMediaTrackInfo_Value(containerTrack, "I_NCHAN", maxChannel)

    -- MEGATHINK: Force REAPER UI synchronization immediately after change
    reaper.UpdateArrange()
    reaper.TrackList_AdjustWindows(false)

    -- MEGATHINK: Immediate verification with fresh track lookup
    local actualChannels = reaper.GetMediaTrackInfo_Value(containerTrack, "I_NCHAN")

    -- Also try to find track by GUID to verify it's the same track
    local foundTrack = nil
    if trackGUID then
        for i = 0, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, i)
            if reaper.GetTrackGUID(track) == trackGUID then
                foundTrack = track
                break
            end
        end
    end

    local foundChannels = foundTrack and reaper.GetMediaTrackInfo_Value(foundTrack, "I_NCHAN") or "N/A"

    -- reaper.ShowConsoleMsg(string.format("  Verification: Original ref=%d, GUID lookup=%s, Same track: %s\n",
    --     actualChannels, tostring(foundChannels), tostring(foundTrack == containerTrack)))

    if actualChannels == maxChannel then
        -- reaper.ShowConsoleMsg(string.format("✅ SUCCESS: Container '%s' confirmed at %d channels\n",
        --     containerTrackInfo.name or "unknown", actualChannels))
    else
        -- MEGATHINK: Enhanced retry with Undo blocks for each attempt (silent mode)
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

    -- Update child track routing
    local childIndex = 1
    for _, childInfo in ipairs(containerTrackInfo.children) do
        if childIndex <= #newRouting then
            -- Find send to parent and update destination channel
            for _, send in ipairs(childInfo.sends) do
                if send.destTrack == containerTrack then
                    local newDestChannel = 1024 + (newRouting[childIndex] - 1)  -- Convert to REAPER format
                    reaper.SetTrackSendInfo_Value(childInfo.track, 0, send.sendIndex, "I_DSTCHAN", newDestChannel)
                    break
                end
            end
            childIndex = childIndex + 1
        end
    end

    -- Update parent track channels if needed
    if globals.Utils and globals.Utils.ensureParentHasEnoughChannels then
        globals.Utils.ensureParentHasEnoughChannels(containerTrack, maxChannel)
    end

    -- Update container configuration in tool data
    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if container.name == containerTrackInfo.name then
                container.customRouting = newRouting
                break
            end
        end
    end

    -- CRITICAL FIX: Close Undo block to commit all changes to REAPER
    reaper.Undo_EndBlock("Fix Container Routing", -1)

    -- MEGATHINK: Final UI synchronization to ensure changes are visible
    reaper.UpdateArrange()
    reaper.UpdateTimeline()

    return true
end

-- Get actual channel routing from existing tracks (legacy compatibility)
-- @param groupName string: Name of the group
-- @param containerName string: Name of the container
-- @return table|nil: Actual routing configuration or nil if tracks don't exist
function RoutingValidator.getActualTrackRouting(groupName, containerName)
    -- Find the group track
    local groupTrack, groupTrackIdx = globals.Utils.findGroupByName(groupName)
    if not groupTrack then
        return nil
    end
    
    -- Find the container track within the group
    local containerTrack = globals.Utils.findContainerGroup(groupTrackIdx, containerName)
    if not containerTrack then
        return nil
    end
    
    -- Get container track index
    local containerIdx = reaper.GetMediaTrackInfo_Value(containerTrack, "IP_TRACKNUMBER") - 1
    
    -- Check if this is a multi-channel container (has child tracks)
    local folderDepth = reaper.GetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH")
    if folderDepth ~= 1 then
        return nil -- Not a folder, no child tracks to read
    end
    
    -- Read routing from child tracks
    local actualRouting = {}
    local trackIdx = containerIdx + 1
    local depth = 1
    
    while trackIdx < reaper.CountTracks(0) and depth > 0 do
        local childTrack = reaper.GetTrack(0, trackIdx)
        if not childTrack then break end
        
        -- Check if this is a direct child (not a grandchild)
        local parent = reaper.GetParentTrack(childTrack)
        if parent == containerTrack then
            -- Find the send to parent track and read its destination channel
            local sendCount = reaper.GetTrackNumSends(childTrack, 0)
            local destChannel = 1 -- Default to channel 1 if no send found
            
            for sendIdx = 0, sendCount - 1 do
                local destTrack = reaper.GetTrackSendInfo_Value(childTrack, 0, sendIdx, "P_DESTTRACK")
                if destTrack == containerTrack then
                    -- Read the destination channel for this send
                    local dstChan = reaper.GetTrackSendInfo_Value(childTrack, 0, sendIdx, "I_DSTCHAN")
                    -- Convert from Reaper's channel format (1024 + channel) to 1-based channel number
                    if dstChan >= 1024 then
                        destChannel = (dstChan - 1024) + 1
                    else
                        -- Handle stereo pairs and other formats
                        destChannel = math.floor(dstChan / 2) + 1
                    end
                    break
                end
            end
            
            table.insert(actualRouting, destChannel)
        end
        
        -- Update depth tracking
        local childDepth = reaper.GetMediaTrackInfo_Value(childTrack, "I_FOLDERDEPTH")
        depth = depth + childDepth
        trackIdx = trackIdx + 1
    end
    
    -- Return routing if we found child tracks
    return #actualRouting > 0 and actualRouting or nil
end

-- Legacy detect routing conflicts between containers (for backward compatibility)
-- @return table|nil: Conflict information or nil if no conflicts
function RoutingValidator.detectConflictsLegacy()
    local channelUsage = {}  -- Track which channels are used for what
    local conflicts = {}
    local containers = {}  -- Store all containers with their routing
    local conflictPairs = {}

    -- Collect all containers with multi-channel routing
    for groupIdx, group in ipairs(globals.groups) do
        for containerIdx, container in ipairs(group.containers) do
            if container.channelMode and container.channelMode > 0 then
                local config = Constants.CHANNEL_CONFIGS[container.channelMode]

                if config then
                    local activeConfig = config
                    if config.hasVariants then
                        activeConfig = config.variants[container.channelVariant or 0]
                        activeConfig.channels = config.channels
                        activeConfig.name = config.name  -- Preserve base config name
                    end

                    local containerKey = group.name .. "_" .. container.name
                    
                    -- Get actual routing from tracks if they exist
                    local actualRouting = RoutingValidator.getActualTrackRouting(group.name, container.name)
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

                    -- Track channel usage (routing already determined above)
                    for idx, channelNum in ipairs(routing) do
                        local label = activeConfig.labels[idx]

                        if not channelUsage[channelNum] then
                            channelUsage[channelNum] = {}
                        end

                        -- Check for conflicts
                        for _, usage in ipairs(channelUsage[channelNum]) do
                            if usage.label ~= label then
                                -- Conflict detected!
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
                                
                                -- Mark conflict in container data
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

    -- Return nil if no conflicts
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

-- Find intelligent routing solution based on channel labels
-- @param conflicts table: Conflict data from detectConflicts()
-- @return table: Resolution suggestions
function RoutingValidator.findIntelligentRoutingLegacy(conflicts)
    local resolutions = {}
    
    -- Identify master configurations (5.0, 7.0, etc.)
    local masterConfigs = {}
    local subordinateConfigs = {}
    
    for containerKey, data in pairs(conflicts.containers) do
        if data.channelCount >= 5 then
            masterConfigs[containerKey] = data
        else
            subordinateConfigs[containerKey] = data
        end
    end
    
    -- Process each subordinate configuration
    for containerKey, subConfig in pairs(subordinateConfigs) do
        if next(subConfig.conflicts) then  -- Has conflicts
            -- Find which master config it conflicts with
            local conflictingMaster = nil
            for channel, conflictInfo in pairs(subConfig.conflicts) do
                if masterConfigs[conflictInfo.conflictsWith] then
                    conflictingMaster = masterConfigs[conflictInfo.conflictsWith]
                    break
                end
            end
            
            if conflictingMaster then
                local resolution = RoutingValidator.matchChannelsByLabelLegacy(subConfig, conflictingMaster)
                if resolution then
                    table.insert(resolutions, resolution)
                end
            end
        end
    end
    
    return resolutions
end

-- Match channels between configurations based on labels
-- @param subConfig table: Subordinate configuration (e.g., Quad)
-- @param masterConfig table: Master configuration (e.g., 5.0)
-- @return table: Routing resolution
function RoutingValidator.matchChannelsByLabelLegacy(subConfig, masterConfig)
    -- Get actual routing if tracks exist, otherwise use config routing
    local actualRouting = RoutingValidator.getActualTrackRouting(subConfig.groupName, subConfig.containerName)
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
    
    -- Create label to channel mapping for master config
    local masterLabelMap = {}
    for idx, label in ipairs(masterConfig.labels) do
        masterLabelMap[label] = masterConfig.routing[idx]
    end
    
    -- Match each channel of subordinate config
    for idx, label in ipairs(subConfig.labels) do
        local oldChannel = currentRouting[idx]
        local newChannel = oldChannel  -- Default: keep same
        local reason = "Keep original"
        local matched = nil
        
        -- Try to find matching label in master config
        if masterLabelMap[label] then
            newChannel = masterLabelMap[label]
            matched = masterConfig.containerName .. "_" .. label
            reason = string.format("Match %s %s on channel %d", 
                masterConfig.config.name or "Master", label, newChannel)
        else
            -- Special handling for common channel mappings
            if label == "L" then
                newChannel = 1
                reason = "Standard L position"
            elseif label == "R" then
                -- Check if master has center channel
                if masterLabelMap["C"] and masterLabelMap["C"] == 2 then
                    newChannel = 3  -- R moves to channel 3 in L C R config
                else
                    newChannel = 2  -- R stays on channel 2 in L R C config
                end
                reason = newChannel == 3 and "Adapt to L C R layout" or "Standard R position"
            elseif label == "LS" or label == "RS" then
                -- Keep surround channels aligned with master if available
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
    
    -- Check if any changes are actually needed
    local needsChange = false
    for i, channel in ipairs(resolution.newRouting) do
        if channel ~= resolution.originalRouting[i] then
            needsChange = true
            break
        end
    end
    
    return needsChange and resolution or nil
end

-- ===================================================================
-- USER INTERFACE
-- ===================================================================

-- Show the routing validation modal window
-- @param issuesList table: List of detected issues
-- @param fixSuggestions table: List of fix suggestions
function RoutingValidator.showValidationModal(issuesList, fixSuggestions)
    if not issuesList then return end

    validationData = projectTrackCache
    globals.pendingIssuesList = issuesList
    fixSuggestions = fixSuggestions or RoutingValidator.generateFixSuggestions(issuesList, validationData)

    globals.pendingValidationData = validationData
    shouldOpenModal = true
end

-- Render the routing validation modal
function RoutingValidator.renderModal()
    local ctx = globals.ctx
    local imgui = globals.imgui

    -- Open popup when requested
    if shouldOpenModal then
        imgui.OpenPopup(ctx, "Project Routing Validator")
        shouldOpenModal = false
    end

    -- SetNextWindowSize must be called before BeginPopupModal
    imgui.SetNextWindowSize(ctx, 1400, 800, imgui.Cond_FirstUseEver)

    -- BeginPopupModal must be called every frame, it only shows if OpenPopup was called
    if imgui.BeginPopupModal(ctx, "Project Routing Validator", true, imgui.WindowFlags_NoCollapse) then
        -- Get window dimensions for proper layout
        local windowWidth, windowHeight = imgui.GetWindowSize(ctx)
        local headerHeight = 80
        local footerHeight = 100 -- Increased from 80 to prevent button clipping
        local contentHeight = windowHeight - headerHeight - footerHeight - 20

        -- Header
        RoutingValidator.renderHeader(ctx, imgui)

        -- Create scrollable content area
        if imgui.BeginChild(ctx, "ValidationContentArea", 0, contentHeight) then
            -- Tab bar for different views
            if imgui.BeginTabBar(ctx, "ValidationTabs") then

                -- Tab 1: Issues Overview
                if imgui.BeginTabItem(ctx, "Issues Overview") then
                    RoutingValidator.renderIssuesOverview(ctx, imgui)
                    imgui.EndTabItem(ctx)
                end

                -- Tab 2: Project Tree
                if imgui.BeginTabItem(ctx, "Project Tree") then
                    RoutingValidator.renderProjectTree(ctx, imgui)
                    imgui.EndTabItem(ctx)
                end

                -- Tab 3: Channel Map
                if imgui.BeginTabItem(ctx, "Channel Map") then
                    RoutingValidator.renderChannelMap(ctx, imgui)
                    imgui.EndTabItem(ctx)
                end

                -- Tab 4: Fix Suggestions
                if imgui.BeginTabItem(ctx, "Fix Suggestions") then
                    RoutingValidator.renderFixSuggestions(ctx, imgui)
                    imgui.EndTabItem(ctx)
                end

                imgui.EndTabBar(ctx)
            end
        end
        -- CRITICAL: Always call EndChild after BeginChild, regardless of visibility
        imgui.EndChild(ctx)

        -- Footer with buttons
        RoutingValidator.renderFooter(ctx, imgui)

        imgui.EndPopup(ctx)
    end
end

-- Render modal header
function RoutingValidator.renderHeader(ctx, imgui)
    local issuesCount = globals.pendingIssuesList and #globals.pendingIssuesList or 0
    local errorCount = 0
    local warningCount = 0

    if globals.pendingIssuesList then
        for _, issue in ipairs(globals.pendingIssuesList) do
            if issue.severity == SEVERITY.ERROR then
                errorCount = errorCount + 1
            elseif issue.severity == SEVERITY.WARNING then
                warningCount = warningCount + 1
            end
        end
    end

    -- Title with status
    if issuesCount == 0 then
        imgui.PushStyleColor(ctx, imgui.Col_Text, 0x00FF00FF)
        imgui.Text(ctx, "✓ Project Routing Validation - All OK")
        imgui.PopStyleColor(ctx)
    else
        imgui.PushStyleColor(ctx, imgui.Col_Text, 0xFF8800FF)
        imgui.Text(ctx, string.format("⚠ Project Routing Validation - %d Issues Found", issuesCount))
        imgui.PopStyleColor(ctx)
    end

    -- Status breakdown
    if issuesCount > 0 then
        imgui.Spacing(ctx)
        imgui.Text(ctx, string.format("Errors: %d | Warnings: %d | Info: %d",
            errorCount, warningCount, issuesCount - errorCount - warningCount))
    end

    -- Auto-fix option
    imgui.Spacing(ctx)
    local autoFix = globals.autoFixRouting or false
    local changed, newAutoFix = imgui.Checkbox(ctx, "Auto-fix routing issues after generation", autoFix)
    if changed then
        globals.autoFixRouting = newAutoFix
    end

    imgui.Separator(ctx)
    imgui.Spacing(ctx)
end

--- Get a human-readable description of what the fix will do
local function getFixDescription(issue)
    if issue.type == ISSUE_TYPES.CHANNEL_ORDER_CONFLICT then
        return "Requires user choice between channel order variants"
    elseif issue.type == ISSUE_TYPES.CHANNEL_CONFLICT then
        if issue.conflictData and issue.conflictData.masterFormat then
            local masterName = issue.conflictData.masterFormat.config.name or "Master"
            return string.format("Realign routing to match %s format", masterName)
        end
        return "Realign routing to match master format"
    elseif issue.type == ISSUE_TYPES.PARENT_INSUFFICIENT_CHANNELS then
        if issue.suggestedFix and issue.suggestedFix.channels then
            return string.format("Increase parent track to %d channels", issue.suggestedFix.channels)
        end
        return "Increase parent track channel count"
    elseif issue.type == ISSUE_TYPES.PARENT_EXCESSIVE_CHANNELS then
        if issue.suggestedFix and issue.suggestedFix.channels then
            return string.format("Reduce parent track to %d channels", issue.suggestedFix.channels)
        end
        return "Reduce parent track channel count"
    elseif issue.type == ISSUE_TYPES.ORPHAN_SEND then
        if issue.sendData then
            local channelNum = RoutingValidator.parseDstChannel(issue.sendData.dstChannel)
            return string.format("Increase destination track to %d channels", channelNum)
        end
        return "Increase destination track channel count"
    end

    return "Apply automatic fix"
end

-- Render issues overview tab
function RoutingValidator.renderIssuesOverview(ctx, imgui)
    if not globals.pendingIssuesList or #globals.pendingIssuesList == 0 then
        imgui.PushStyleColor(ctx, imgui.Col_Text, 0x00FF00FF)
        imgui.Text(ctx, "✓ No routing issues detected!")
        imgui.PopStyleColor(ctx)
        imgui.Text(ctx, "All channel routing in the project appears to be correct.")
        return
    end

    imgui.Text(ctx, "The following routing issues were detected:")
    imgui.Spacing(ctx)

    -- Issues table
    if imgui.BeginTable(ctx, "IssuesTable", 6,
        imgui.TableFlags_Borders | imgui.TableFlags_RowBg | imgui.TableFlags_Resizable | imgui.TableFlags_Sortable) then

        -- Headers
        imgui.TableSetupColumn(ctx, "Severity", imgui.TableColumnFlags_WidthFixed, 80)
        imgui.TableSetupColumn(ctx, "Type", imgui.TableColumnFlags_WidthFixed, 120)
        imgui.TableSetupColumn(ctx, "Track", imgui.TableColumnFlags_WidthStretch, 0)
        imgui.TableSetupColumn(ctx, "Description", imgui.TableColumnFlags_WidthStretch, 0)
        imgui.TableSetupColumn(ctx, "Proposed Fix", imgui.TableColumnFlags_WidthStretch, 0)
        imgui.TableSetupColumn(ctx, "Action", imgui.TableColumnFlags_WidthFixed, 100)
        imgui.TableHeadersRow(ctx)

        -- Display issues
        for i, issue in ipairs(globals.pendingIssuesList) do
            imgui.TableNextRow(ctx)

            -- Severity
            imgui.TableNextColumn(ctx)
            local severityColor = 0xAAAAAAFF
            local severityIcon = "ℹ"
            if issue.severity == SEVERITY.ERROR then
                severityColor = 0xFF0000FF
                severityIcon = "✗"
            elseif issue.severity == SEVERITY.WARNING then
                severityColor = 0xFFAA00FF
                severityIcon = "⚠"
            end

            imgui.PushStyleColor(ctx, imgui.Col_Text, severityColor)
            imgui.Text(ctx, string.format("%s %s", severityIcon, string.upper(issue.severity)))
            imgui.PopStyleColor(ctx)

            -- Type
            imgui.TableNextColumn(ctx)
            imgui.Text(ctx, issue.type:gsub("_", " "):upper())

            -- Track
            imgui.TableNextColumn(ctx)
            local trackName = issue.track and issue.track.name or "N/A"
            imgui.Text(ctx, trackName)

            -- Description
            imgui.TableNextColumn(ctx)
            imgui.TextWrapped(ctx, issue.description)

            -- Proposed Fix
            imgui.TableNextColumn(ctx)
            local fixDescription = getFixDescription(issue)
            imgui.PushStyleColor(ctx, imgui.Col_Text, 0x88CCFFFF)
            imgui.TextWrapped(ctx, fixDescription)
            imgui.PopStyleColor(ctx)

            -- Action
            imgui.TableNextColumn(ctx)
            if imgui.SmallButton(ctx, "Fix##" .. i) then
                RoutingValidator.fixSingleIssue(issue)
            end
        end

        imgui.EndTable(ctx)
    end
end

-- Render project tree tab
function RoutingValidator.renderProjectTree(ctx, imgui)
    if not globals.pendingValidationData then
        imgui.Text(ctx, "No validation data available")
        return
    end

    imgui.Text(ctx, "Project Track Hierarchy:")
    imgui.Spacing(ctx)

    -- Master track
    if globals.pendingValidationData.master then
        RoutingValidator.renderTrackNode(ctx, imgui, globals.pendingValidationData.master, 0)
    end

    -- Top-level tracks
    for _, trackInfo in ipairs(globals.pendingValidationData.topLevelTracks) do
        RoutingValidator.renderTrackNode(ctx, imgui, trackInfo, 0)
    end
end

-- Render a single track node in the tree
function RoutingValidator.renderTrackNode(ctx, imgui, trackInfo, depth)
    local indent = depth * 20

    imgui.Indent(ctx, indent)

    -- Track icon and name
    local icon = trackInfo.isMaster and "🎛" or (trackInfo.isFromTool and "🔧" or "🎵")
    local hasIssues = #trackInfo.issues > 0
    local textColor = hasIssues and 0xFF8800FF or (trackInfo.isFromTool and 0x00FFFFAA or 0xAAAAAAFF)

    imgui.PushStyleColor(ctx, imgui.Col_Text, textColor)
    imgui.Text(ctx, string.format("%s %s (ch: %d)", icon, trackInfo.name, trackInfo.channelCount))
    imgui.PopStyleColor(ctx)

    -- Show sends routing information if any
    if trackInfo.sends and #trackInfo.sends > 0 then
        imgui.Indent(ctx, 10)
        for _, send in ipairs(trackInfo.sends) do
            local destTrackName = send.destTrack and reaper.GetTrackName(send.destTrack) or "Unknown"

            -- Parse source and destination channels for display
            local srcChan = send.srcChannel
            local dstChan = send.dstChannel

            local srcDisplay, dstDisplay

            -- Parse source channel
            if srcChan >= 1024 then
                -- Mono: 1024 + channel (0-based)
                local ch = srcChan - 1024 + 1  -- Convert to 1-based
                srcDisplay = string.format("Ch %d (mono)", ch)
            elseif srcChan >= 0 then
                -- Stereo pair: srcChan is the starting channel (0-based)
                local ch1 = srcChan + 1
                local ch2 = srcChan + 2
                srcDisplay = string.format("Ch %d-%d (stereo)", ch1, ch2)
            else
                srcDisplay = string.format("Ch %d", srcChan)
            end

            -- Parse destination channel
            if dstChan >= 1024 then
                -- Mono: 1024 + channel (0-based)
                local ch = dstChan - 1024 + 1  -- Convert to 1-based
                dstDisplay = string.format("Ch %d (mono)", ch)
            elseif dstChan >= 0 then
                -- Stereo pair: dstChan is the starting channel (0-based)
                local ch1 = dstChan + 1
                local ch2 = dstChan + 2
                dstDisplay = string.format("Ch %d-%d (stereo)", ch1, ch2)
            else
                dstDisplay = string.format("Ch %d", dstChan)
            end

            imgui.PushStyleColor(ctx, imgui.Col_Text, 0x8888AAFF)
            imgui.Text(ctx, string.format("→ Send to '%s': %s → %s", destTrackName, srcDisplay, dstDisplay))
            imgui.PopStyleColor(ctx)
        end
        imgui.Unindent(ctx, 10)
    end

    -- Show issues if any
    if hasIssues then
        imgui.Indent(ctx, 10)
        for _, issue in ipairs(trackInfo.issues) do
            imgui.PushStyleColor(ctx, imgui.Col_Text, 0xFF0000FF)
            imgui.Text(ctx, "⚠ " .. issue.description)
            imgui.PopStyleColor(ctx)
        end
        imgui.Unindent(ctx, 10)
    end

    -- Render children
    for _, child in ipairs(trackInfo.children) do
        RoutingValidator.renderTrackNode(ctx, imgui, child, depth + 1)
    end

    imgui.Unindent(ctx, indent)
end

-- Render channel map tab
function RoutingValidator.renderChannelMap(ctx, imgui)
    if not globals.pendingValidationData then
        imgui.Text(ctx, "No validation data available")
        return
    end

    imgui.Text(ctx, "Channel Usage Map:")
    imgui.Spacing(ctx)

    -- Calculate channel usage
    local channelUsage = {}
    for _, trackInfo in ipairs(globals.pendingValidationData.toolTracks) do
        if trackInfo.isFromTool then
            local channelInfo = RoutingValidator.getTrackChannelInfo(trackInfo)
            if channelInfo then
                for _, channel in ipairs(channelInfo.channels) do
                    if not channelUsage[channel.channelNum] then
                        channelUsage[channel.channelNum] = {}
                    end
                    table.insert(channelUsage[channel.channelNum], {
                        track = trackInfo,
                        label = channel.label
                    })
                end
            end
        end
    end

    -- Render channel map
    for ch = 1, 16 do
        local usage = channelUsage[ch]

        if usage and #usage > 0 then
            -- Check for conflicts
            local labels = {}
            local hasConflict = false
            for _, u in ipairs(usage) do
                if not labels[u.label] then
                    labels[u.label] = {}
                end
                table.insert(labels[u.label], u.track.name)
            end

            local labelCount = 0
            for _, _ in pairs(labels) do
                labelCount = labelCount + 1
            end
            hasConflict = labelCount > 1

            -- Channel header
            imgui.Separator(ctx)
            local statusIcon = hasConflict and "⚠" or "✓"
            local statusColor = hasConflict and 0xFF0000FF or 0x00FF00FF

            imgui.PushStyleColor(ctx, imgui.Col_Text, statusColor)
            imgui.Text(ctx, string.format("Channel %d %s", ch, statusIcon))
            imgui.PopStyleColor(ctx)

            -- List usage
            imgui.Indent(ctx, 20)
            for label, tracks in pairs(labels) do
                local color = hasConflict and 0xFF8800FF or 0xAAAAAAFF
                imgui.PushStyleColor(ctx, imgui.Col_Text, color)
                imgui.Text(ctx, string.format("%s: %s", label, table.concat(tracks, ", ")))
                imgui.PopStyleColor(ctx)
            end
            imgui.Unindent(ctx, 20)
        end
    end
end

-- Render fix suggestions tab
function RoutingValidator.renderFixSuggestions(ctx, imgui)
    if not fixSuggestions or #fixSuggestions == 0 then
        imgui.Text(ctx, "No fix suggestions available.")
        return
    end

    imgui.Text(ctx, "Proposed fixes for detected issues:")
    imgui.Spacing(ctx)

    for i, suggestion in ipairs(fixSuggestions) do
        imgui.Separator(ctx)
        imgui.Text(ctx, string.format("Fix %d: %s", i, suggestion.action:gsub("_", " "):upper()))
        imgui.Indent(ctx, 10)
        imgui.TextWrapped(ctx, suggestion.reason)

        if imgui.Button(ctx, "Apply This Fix##" .. i) then
            RoutingValidator.applySingleFix(suggestion, false)  -- Manual mode
            -- Re-validate after fix
            RoutingValidator.validateProjectRouting()
        end

        imgui.Unindent(ctx, 10)
        imgui.Spacing(ctx)
    end
end

-- Render modal footer
function RoutingValidator.renderFooter(ctx, imgui)
    imgui.Separator(ctx)
    imgui.Spacing(ctx)

    -- Auto-fix all button
    if fixSuggestions and #fixSuggestions > 0 then
        imgui.PushStyleColor(ctx, imgui.Col_Button, 0x0088FFFF)
        if imgui.Button(ctx, "Auto-Fix All Issues", 200, 35) then
            RoutingValidator.autoFixRouting(globals.pendingIssuesList, fixSuggestions)
            imgui.CloseCurrentPopup(ctx)
        end
        imgui.PopStyleColor(ctx)
        imgui.SameLine(ctx)
    end

    -- Re-validate button
    if imgui.Button(ctx, "Re-Validate", 120, 35) then
        projectTrackCache = nil  -- Clear cache
        local newIssues = RoutingValidator.validateProjectRouting()
        -- Close current popup before opening new one
        imgui.CloseCurrentPopup(ctx)
        RoutingValidator.showValidationModal(newIssues, fixSuggestions)
    end

    imgui.SameLine(ctx)

    -- Close button
    if imgui.Button(ctx, "Close", 120, 35) then
        imgui.CloseCurrentPopup(ctx)
    end
end

-- Fix a single issue
function RoutingValidator.fixSingleIssue(issue)
    local suggestion = RoutingValidator.generateFixSuggestion(issue, globals.pendingValidationData)
    if suggestion then
        RoutingValidator.applySingleFix(suggestion, false)  -- Manual mode
        -- Re-validate and refresh modal automatically
        projectTrackCache = nil
        local newIssues = RoutingValidator.validateProjectRouting()
        RoutingValidator.showValidationModal(newIssues, fixSuggestions)
    end
end

-- ===================================================================
-- CHANNEL ORDER RESOLUTION MODAL
-- ===================================================================

-- Show channel order conflict resolution modal
function RoutingValidator.showChannelOrderResolutionModal(suggestion)
    channelOrderConflictData = suggestion
    shouldOpenChannelOrderModal = true
end

-- Render channel order resolution modal
function RoutingValidator.renderChannelOrderModal()
    local ctx = globals.ctx
    local imgui = globals.imgui

    if not channelOrderConflictData then return end

    -- Open popup when requested
    if shouldOpenChannelOrderModal then
        imgui.OpenPopup(ctx, "Channel Order Conflict Resolution")
        shouldOpenChannelOrderModal = false
    end

    -- SetNextWindowSize must be called before BeginPopupModal
    imgui.SetNextWindowSize(ctx, 600, 400, imgui.Cond_FirstUseEver)

    -- BeginPopupModal must be called every frame, it only shows if OpenPopup was called
    if imgui.BeginPopupModal(ctx, "Channel Order Conflict Resolution", true, imgui.WindowFlags_NoCollapse) then
        local conflictData = channelOrderConflictData.conflictData

        -- Header
        imgui.PushStyleColor(ctx, imgui.Col_Text, 0xFF8800FF)
        imgui.Text(ctx, "⚠ Channel Order Conflict Detected!")
        imgui.PopStyleColor(ctx)

        imgui.Separator(ctx)
        imgui.Spacing(ctx)

        -- Description
        imgui.TextWrapped(ctx, string.format(
            "Two %s.0 containers use different channel orders. A session can only use one channel order per configuration type.",
            conflictData.channelMode))

        imgui.Spacing(ctx)
        imgui.Spacing(ctx)

        -- Show the conflict details
        imgui.Text(ctx, "Conflicting configurations:")
        imgui.Spacing(ctx)

        -- Option 1
        imgui.PushStyleColor(ctx, imgui.Col_Button, 0x0088AAFF)
        if imgui.Button(ctx, string.format("Use: %s", conflictData.variantName1), 250, 40) then
            RoutingValidator.applyChannelOrderChoice(conflictData.variant1, conflictData.channelMode)
            channelOrderConflictData = nil
            imgui.CloseCurrentPopup(ctx)
        end
        imgui.PopStyleColor(ctx)

        imgui.SameLine(ctx)
        imgui.Text(ctx, string.format("(Container: %s)", conflictData.container1.name or "Unknown"))

        imgui.Spacing(ctx)

        -- Option 2
        imgui.PushStyleColor(ctx, imgui.Col_Button, 0x0088AAFF)
        if imgui.Button(ctx, string.format("Use: %s", conflictData.variantName2), 250, 40) then
            RoutingValidator.applyChannelOrderChoice(conflictData.variant2, conflictData.channelMode)
            channelOrderConflictData = nil
            imgui.CloseCurrentPopup(ctx)
        end
        imgui.PopStyleColor(ctx)

        imgui.SameLine(ctx)
        imgui.Text(ctx, string.format("(Container: %s)", conflictData.container2.name or "Unknown"))

        imgui.Spacing(ctx)
        imgui.Spacing(ctx)
        imgui.Separator(ctx)

        -- Footer
        imgui.Spacing(ctx)
        imgui.TextWrapped(ctx, "All containers of this type will be updated to use the chosen channel order.")

        imgui.Spacing(ctx)

        -- Cancel button
        local buttonWidth = 100
        local avail = imgui.GetContentRegionAvail(ctx)
        imgui.SetCursorPosX(ctx, imgui.GetCursorPosX(ctx) + (avail - buttonWidth) * 0.5)

        if imgui.Button(ctx, "Cancel", buttonWidth, 30) then
            channelOrderConflictData = nil
            imgui.CloseCurrentPopup(ctx)
        end

        imgui.EndPopup(ctx)
    end
end

-- Apply channel order choice to all containers of the same type
function RoutingValidator.applyChannelOrderChoice(chosenVariant, channelMode)
    reaper.Undo_BeginBlock()

    local success = true
    local containersUpdated = 0

    -- Find all containers with the same channel mode and update their variant
    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if container.channelMode then
                local config = Constants.CHANNEL_CONFIGS[container.channelMode]
                if config and config.channels == channelMode then
                    -- Update the container's channel variant
                    local oldVariant = container.channelVariant or 0
                    container.channelVariant = chosenVariant

                    -- Mark for regeneration if variant changed
                    if oldVariant ~= chosenVariant then
                        container.needsRegeneration = true
                        containersUpdated = containersUpdated + 1
                    end
                end
            end
        end
    end

    -- If any containers were updated, regenerate the affected tracks
    if containersUpdated > 0 and globals.Generation then
        globals.Generation.generateGroups()
    end

    reaper.Undo_EndBlock(string.format("Apply %s Channel Order",
        RoutingValidator.getVariantName(channelMode, chosenVariant)), -1)

    -- Clear cache and re-validate
    projectTrackCache = nil
    local newIssues = RoutingValidator.validateProjectRouting()

    -- Show validation modal if there are remaining issues
    if newIssues and #newIssues > 0 then
        RoutingValidator.showValidationModal(newIssues)
    end

    return success
end

-- Check if there are active validation issues requiring attention
function RoutingValidator.hasActiveIssues()
    return globals.showRoutingModal and globals.pendingIssuesList and #globals.pendingIssuesList > 0
end

-- Clear all validation data and close modal
function RoutingValidator.clearValidation()
    globals.showRoutingModal = false
    globals.pendingValidationData = nil
    globals.pendingIssuesList = nil
    validationData = nil
    issuesList = nil
    fixSuggestions = nil
end

-- ===================================================================
-- LEGACY COMPATIBILITY FUNCTIONS
-- ===================================================================

-- Legacy function for backward compatibility
function RoutingValidator.getActualTrackRouting(groupName, containerName)
    -- Redirect to new validation system
    local issues = RoutingValidator.validateProjectRouting()

    -- Find the specific container in the validation data
    if projectTrackCache then
        for _, trackInfo in ipairs(projectTrackCache.toolTracks) do
            if trackInfo.name == containerName then
                local channelInfo = RoutingValidator.getTrackChannelInfo(trackInfo)
                if channelInfo then
                    return channelInfo.routing
                end
            end
        end
    end

    return nil
end

-- Legacy function for detecting conflicts (redirects to new system)
function RoutingValidator.detectConflicts()
    local issues = RoutingValidator.validateProjectRouting()

    -- Convert new format to legacy format for compatibility
    local legacyConflicts = {
        containers = {},
        conflictPairs = {},
        channelUsage = {}
    }

    -- Process issues and convert to legacy format if needed
    for _, issue in ipairs(issues or {}) do
        if issue.type == ISSUE_TYPES.CHANNEL_CONFLICT and issue.conflictData then
            local conflictData = issue.conflictData
            local conflictKey = conflictData.track1.name .. "_vs_" .. conflictData.track2.name

            legacyConflicts.conflictPairs[conflictKey] = {
                container1 = {
                    containerName = conflictData.track1.name,
                    groupName = conflictData.track1.groupName or "Unknown"
                },
                container2 = {
                    containerName = conflictData.track2.name,
                    groupName = conflictData.track2.groupName or "Unknown"
                },
                conflictingChannels = {{
                    channel = conflictData.channel,
                    label1 = conflictData.label1,
                    label2 = conflictData.label2
                }}
            }
        end
    end

    return next(legacyConflicts.conflictPairs) and legacyConflicts or nil
end

-- Entry point for the new validation system
function RoutingValidator.validateAndShow()
    local issues = RoutingValidator.validateProjectRouting()

    if issues and #issues > 0 then
        if globals.autoFixRouting then
            local suggestions = RoutingValidator.generateFixSuggestions(issues, projectTrackCache)
            RoutingValidator.autoFixRouting(issues, suggestions)
        else
            RoutingValidator.showValidationModal(issues)
        end
    else
        -- No routing issues, check for optimization opportunities
        RoutingValidator.checkOptimizationOpportunities()
    end

    return issues
end

-- Check for channel optimization opportunities
function RoutingValidator.checkOptimizationOpportunities()
    if not projectTrackCache then return end

    local optimizationNeeded = false
    local savings = {}

    -- Check if any tracks have more channels than needed
    for _, trackInfo in pairs(projectTrackCache.allTracks) do
        if trackInfo and trackInfo.track then
            local currentChannels = trackInfo.channelCount
            local requiredChannels = RoutingValidator.getTrackRequiredChannels(trackInfo)

            if currentChannels > requiredChannels then
                optimizationNeeded = true
                table.insert(savings, {
                    track = trackInfo,
                    current = currentChannels,
                    required = requiredChannels,
                    savings = currentChannels - requiredChannels
                })
            end
        end
    end

    if optimizationNeeded then
        -- reaper.ShowConsoleMsg(string.format("INFO: Channel optimization opportunities detected (%d tracks)\n", #savings))

        -- Auto-optimize if enabled, otherwise suggest
        if globals.autoOptimizeChannels then
            RoutingValidator.applyChannelOptimization(savings)
        else
            RoutingValidator.showOptimizationSuggestion(savings)
        end
    else
        -- reaper.ShowConsoleMsg("INFO: Project channel allocation is already optimal.\n")
    end
end

-- Apply channel optimization
function RoutingValidator.applyChannelOptimization(savings)
    reaper.Undo_BeginBlock()

    for _, saving in ipairs(savings) do
        -- reaper.ShowConsoleMsg(string.format("INFO: Optimizing track '%s': %d → %d channels\n",
        --     saving.track.name, saving.current, saving.required))
        reaper.SetMediaTrackInfo_Value(saving.track.track, "I_NCHAN", saving.required)
    end

    reaper.Undo_EndBlock("Optimize Channel Count", -1)

    -- Clear cache to reflect changes
    projectTrackCache = nil
end

-- Show optimization suggestion to user
function RoutingValidator.showOptimizationSuggestion(savings)
    local totalSavings = 0
    for _, saving in ipairs(savings) do
        totalSavings = totalSavings + saving.savings
    end

    -- reaper.ShowConsoleMsg(string.format("SUGGESTION: %d channels could be saved across %d tracks. Enable auto-optimization or run manual optimization.\n",
    --     totalSavings, #savings))
end

-- Get current project track cache (for external access)
function RoutingValidator.getProjectTrackCache()
    return projectTrackCache
end

-- Legacy aliases for backward compatibility (redirects to new functions)
RoutingValidator.showResolutionModal = function(conflicts)
    -- Convert legacy conflicts to issues and show new modal
    if conflicts then
        local issues = RoutingValidator.validateProjectRouting()
        RoutingValidator.showValidationModal(issues)
    end
end

RoutingValidator.findIntelligentRouting = RoutingValidator.findIntelligentRoutingLegacy
RoutingValidator.matchChannelsByLabel = RoutingValidator.matchChannelsByLabelLegacy
RoutingValidator.hasActiveConflicts = function()
    return RoutingValidator.hasActiveIssues()
end
RoutingValidator.clearConflicts = RoutingValidator.clearValidation
-- renderModal is already defined above
RoutingValidator.applyResolution = function()
    -- Auto-apply all current fixes
    if globals.pendingIssuesList and fixSuggestions then
        RoutingValidator.autoFixRouting(globals.pendingIssuesList, fixSuggestions)
        RoutingValidator.clearValidation()
    end
end

-- ===================================================================
-- TESTING AND DEBUG FUNCTIONS
-- ===================================================================

-- Test function to verify the complete routing validation system
function RoutingValidator.testValidationSystem()
    if not globals or not globals.groups then
        return "No groups available for testing"
    end

    local results = {
        "=== Routing Validation System Test ===",
        ""
    }

    -- Test 1: Basic validation
    table.insert(results, "1. Running full project validation...")
    local issues = RoutingValidator.validateProjectRouting()
    table.insert(results, string.format("   Found %d issues", issues and #issues or 0))

    -- Test 2: Channel order conflict detection
    table.insert(results, "")
    table.insert(results, "2. Testing channel order conflict detection...")
    local projectTree = RoutingValidator.scanAllProjectTracks()
    local channelOrderConflicts = RoutingValidator.detectChannelOrderConflicts(projectTree)
    table.insert(results, string.format("   Found %d channel order conflicts", #channelOrderConflicts))

    -- Test 3: Master format detection
    table.insert(results, "")
    table.insert(results, "3. Testing master format detection...")
    local masterFormat = RoutingValidator.findMasterFormat(projectTree)
    if masterFormat then
        table.insert(results, string.format("   Master format: %s (%d channels)",
            masterFormat.config.name or "Unknown", masterFormat.config.channels or 0))
    else
        table.insert(results, "   No master format detected")
    end

    -- Test 4: Reference routing creation
    if masterFormat then
        table.insert(results, "")
        table.insert(results, "4. Testing reference routing creation...")
        local referenceRouting = RoutingValidator.createReferenceRouting(masterFormat)
        local refCount = 0
        for label, channel in pairs(referenceRouting) do
            refCount = refCount + 1
        end
        table.insert(results, string.format("   Created reference routing with %d mappings", refCount))
    end

    -- Test 5: Summary
    table.insert(results, "")
    table.insert(results, "5. System status:")
    if issues and #issues > 0 then
        local errorCount = 0
        local warningCount = 0
        for _, issue in ipairs(issues) do
            if issue.severity == SEVERITY.ERROR then
                errorCount = errorCount + 1
            elseif issue.severity == SEVERITY.WARNING then
                warningCount = warningCount + 1
            end
        end
        table.insert(results, string.format("   Errors: %d, Warnings: %d", errorCount, warningCount))
    else
        table.insert(results, "   ✓ All validation tests passed")
    end

    table.insert(results, "")
    table.insert(results, "=== Test Complete ===")

    return table.concat(results, "\n")
end

-- Debug function to print current validation state
function RoutingValidator.debugValidationState()
    if not globals then return "No globals available" end

    local debug = {
        "=== Routing Validator Debug State ===",
        "",
        string.format("showRoutingModal: %s", tostring(globals.showRoutingModal)),
        string.format("autoFixRouting: %s", tostring(globals.autoFixRouting)),
        string.format("pendingIssuesList: %s", globals.pendingIssuesList and #globals.pendingIssuesList or "nil"),
        string.format("showChannelOrderModal: %s", tostring(showChannelOrderModal)),
        string.format("channelOrderConflictData: %s", channelOrderConflictData and "present" or "nil"),
        string.format("projectTrackCache: %s", projectTrackCache and "cached" or "nil"),
        string.format("lastValidationTime: %.2f", lastValidationTime)
    }

    return table.concat(debug, "\n")
end

-- TEMPORARY: Global alias for backward compatibility during transition
-- This allows old code that still references ConflictResolver to work
_G.ConflictResolver = RoutingValidator

return RoutingValidator