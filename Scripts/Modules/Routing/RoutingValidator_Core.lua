--[[
@version 1.0
@noindex
DM Ambiance Creator - Routing Validator Core Module
Core infrastructure, scanning, and basic validation functions.
--]]

local RoutingValidator_Core = {}
local globals = {}
local Constants = nil

-- Module state variables (shared with other modules via getState)
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

-- Issue types
local ISSUE_TYPES = {
    CHANNEL_CONFLICT = "channel_conflict",
    PARENT_INSUFFICIENT_CHANNELS = "parent_insufficient_channels",
    PARENT_EXCESSIVE_CHANNELS = "parent_excessive_channels",
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
        isFromTool = false
    }
end

-- Initialize the module with global references
function RoutingValidator_Core.initModule(g)
    if not g then
        error("RoutingValidator_Core.initModule: globals parameter is required")
    end
    globals = g
    Constants = require("DM_Ambiance_Constants")

    -- Initialize state
    globals.pendingValidationData = nil
    globals.pendingIssuesList = nil
    globals.autoFixRouting = false

    -- Initialize cache
    projectTrackCache = nil
    lastValidationTime = 0
end

-- Expose constants and state for other modules
function RoutingValidator_Core.getIssueTypes()
    return ISSUE_TYPES
end

function RoutingValidator_Core.getSeverity()
    return SEVERITY
end

function RoutingValidator_Core.getConstants()
    return Constants
end

function RoutingValidator_Core.getGlobals()
    return globals
end

function RoutingValidator_Core.getState()
    return {
        showModal = showModal,
        validationData = validationData,
        issuesList = issuesList,
        fixSuggestions = fixSuggestions,
        autoFixEnabled = autoFixEnabled,
        shouldOpenModal = shouldOpenModal,
        channelOrderConflictData = channelOrderConflictData,
        shouldOpenChannelOrderModal = shouldOpenChannelOrderModal,
        projectTrackCache = projectTrackCache,
        lastValidationTime = lastValidationTime
    }
end

function RoutingValidator_Core.setState(newState)
    if newState.showModal ~= nil then showModal = newState.showModal end
    if newState.validationData ~= nil then validationData = newState.validationData end
    if newState.issuesList ~= nil then issuesList = newState.issuesList end
    if newState.fixSuggestions ~= nil then fixSuggestions = newState.fixSuggestions end
    if newState.autoFixEnabled ~= nil then autoFixEnabled = newState.autoFixEnabled end
    if newState.shouldOpenModal ~= nil then shouldOpenModal = newState.shouldOpenModal end
    if newState.channelOrderConflictData ~= nil then channelOrderConflictData = newState.channelOrderConflictData end
    if newState.shouldOpenChannelOrderModal ~= nil then shouldOpenChannelOrderModal = newState.shouldOpenChannelOrderModal end
    if newState.projectTrackCache ~= nil then projectTrackCache = newState.projectTrackCache end
    if newState.lastValidationTime ~= nil then lastValidationTime = newState.lastValidationTime end
end

function RoutingValidator_Core.createTrackInfo(track)
    return createTrackInfo(track)
end

-- Clear the validation cache to force a fresh scan
function RoutingValidator_Core.clearCache()
    projectTrackCache = nil
    lastValidationTime = 0
end

-- Scan all tracks in the project and build the track tree
function RoutingValidator_Core.scanAllProjectTracks()
    local projectTree = {
        master = nil,
        topLevelTracks = {},
        allTracks = {},
        toolTracks = {},
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
            trackInfo.isFromTool = RoutingValidator_Core.isToolTrack(track)

            projectTree.allTracks[i + 1] = trackInfo

            if trackInfo.isFromTool then
                table.insert(projectTree.toolTracks, trackInfo)
            end

            if not trackInfo.parent then
                table.insert(projectTree.topLevelTracks, trackInfo)
            end
        end
    end

    return projectTree
end

-- Determine if a track was created by our tool (based on naming patterns)
function RoutingValidator_Core.isToolTrack(track)
    local retval, trackName = reaper.GetTrackName(track)
    if not retval or trackName == "" then return false end

    for _, group in ipairs(globals.groups or {}) do
        if trackName == group.name then
            return true
        end

        for _, container in ipairs(group.containers or {}) do
            if trackName == container.name then
                return true
            end

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

-- Get channel mode from track name (5.0, 7.0, etc.)
function RoutingValidator_Core.getChannelModeFromTrackName(trackName)
    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if trackName == container.name and container.channelMode and container.channelMode > 0 then
                local config = Constants.CHANNEL_CONFIGS[container.channelMode]
                if config then
                    return config.channels
                end
            end
        end
    end
    return nil
end

-- Find container by track name
function RoutingValidator_Core.findContainerByTrackName(trackName)
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
function RoutingValidator_Core.getVariantName(channelMode, variant)
    local configKeys = {
        [5] = 5,
        [7] = 7
    }

    local configKey = configKeys[channelMode]
    if not configKey then return "Unknown" end

    local config = Constants.CHANNEL_CONFIGS[configKey]
    if config and config.hasVariants and config.variants and config.variants[variant] then
        return config.variants[variant].name or "Unknown"
    end

    if channelMode == 5 then
        return variant == 0 and "SMPTE (L C R LS RS)" or "Dolby/ITU (L R C LS RS)"
    elseif channelMode == 7 then
        return variant == 0 and "SMPTE (L C R LS RS SL SR)" or "Dolby/ITU (L R C LS RS SL SR)"
    end

    return "Unknown"
end

-- Find group containing a specific container
function RoutingValidator_Core.findGroupByContainer(targetContainer)
    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if container == targetContainer then
                return group
            end
        end
    end
    return nil
end

-- Parse REAPER's destination channel format
function RoutingValidator_Core.parseDstChannel(dstChan)
    if dstChan >= 1024 then
        return (dstChan - 1024) + 1
    elseif dstChan >= 0 then
        return dstChan + 2
    else
        return 1
    end
end

-- Generate sequential routing for a given channel count
function RoutingValidator_Core.generateSequentialRouting(channelCount)
    local routing = {}
    for i = 1, channelCount do
        table.insert(routing, i)
    end
    return routing
end

-- Generate appropriate labels for a channel count
function RoutingValidator_Core.generateLabelsForChannelCount(channelCount, baseConfig)
    if channelCount == 2 then
        return {"L", "R"}
    elseif channelCount == 4 then
        return {"L", "R", "LS", "RS"}
    elseif channelCount == 5 then
        if baseConfig and baseConfig.hasVariants then
            local defaultVariant = baseConfig.variants[0]
            if defaultVariant and defaultVariant.labels then
                return defaultVariant.labels
            end
        end
        return {"L", "R", "C", "LS", "RS"}
    elseif channelCount == 7 then
        if baseConfig and baseConfig.hasVariants then
            local defaultVariant = baseConfig.variants[0]
            if defaultVariant and defaultVariant.labels then
                return defaultVariant.labels
            end
        end
        return {"L", "R", "C", "LS", "RS", "LB", "RB"}
    else
        local labels = {}
        for i = 1, channelCount do
            table.insert(labels, "Ch" .. i)
        end
        return labels
    end
end

-- Get the REAL number of child tracks for a container track
function RoutingValidator_Core.getRealChildTrackCount(trackInfo)
    if not trackInfo or not trackInfo.track then return 0 end

    local containerTrack = trackInfo.track
    local containerIdx = reaper.GetMediaTrackInfo_Value(containerTrack, "IP_TRACKNUMBER") - 1

    local folderDepth = reaper.GetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH")
    if folderDepth ~= 1 then
        return 0
    end

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

return RoutingValidator_Core
