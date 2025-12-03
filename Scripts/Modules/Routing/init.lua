--[[
@version 1.0
@noindex
DM Ambiance Creator - Routing Validator Module Aggregator
This module aggregates all routing validation sub-modules and provides backward compatibility.

Sub-modules:
- RoutingValidator_Core.lua: Core infrastructure, scanning, state management
- RoutingValidator_Detection.lua: Issue detection, channel analysis, validation
- RoutingValidator_Fixes.lua: Fix suggestion generation and application
- RoutingValidator_UI.lua: User interface, modals, rendering
--]]

local RoutingValidator = {}
local globals = {}

-- Get the path to this file's directory for loading sub-modules
local info = debug.getinfo(1, "S")
local modulePath = info.source:match[[^@?(.*[\/])[^\/]-$]]

-- Load sub-modules
local RoutingValidator_Core = dofile(modulePath .. "RoutingValidator_Core.lua")
local RoutingValidator_Detection = dofile(modulePath .. "RoutingValidator_Detection.lua")
local RoutingValidator_Fixes = dofile(modulePath .. "RoutingValidator_Fixes.lua")
local RoutingValidator_UI = dofile(modulePath .. "RoutingValidator_UI.lua")

-- Initialize all sub-modules
function RoutingValidator.initModule(g)
    if not g then
        error("RoutingValidator.initModule: globals parameter is required")
    end
    globals = g

    -- Initialize sub-modules
    RoutingValidator_Core.initModule(g)
    RoutingValidator_Detection.initModule(g)
    RoutingValidator_Fixes.initModule(g)
    RoutingValidator_UI.initModule(g)

    -- Set dependencies between modules
    RoutingValidator_Detection.setDependencies(RoutingValidator_Core)
    RoutingValidator_Fixes.setDependencies(RoutingValidator_Core, RoutingValidator_Detection)
    RoutingValidator_UI.setDependencies(RoutingValidator_Core, RoutingValidator_Detection, RoutingValidator_Fixes)
end

-- ===================================================================
-- RE-EXPORT ALL FUNCTIONS FOR BACKWARD COMPATIBILITY
-- ===================================================================

-- FROM RoutingValidator_Core
RoutingValidator.clearCache = RoutingValidator_Core.clearCache
RoutingValidator.scanAllProjectTracks = RoutingValidator_Core.scanAllProjectTracks
RoutingValidator.isToolTrack = RoutingValidator_Core.isToolTrack
RoutingValidator.getChannelModeFromTrackName = RoutingValidator_Core.getChannelModeFromTrackName
RoutingValidator.findContainerByTrackName = RoutingValidator_Core.findContainerByTrackName
RoutingValidator.getVariantName = RoutingValidator_Core.getVariantName
RoutingValidator.findGroupByContainer = RoutingValidator_Core.findGroupByContainer
RoutingValidator.parseDstChannel = RoutingValidator_Core.parseDstChannel
RoutingValidator.generateSequentialRouting = RoutingValidator_Core.generateSequentialRouting
RoutingValidator.generateLabelsForChannelCount = RoutingValidator_Core.generateLabelsForChannelCount
RoutingValidator.getRealChildTrackCount = RoutingValidator_Core.getRealChildTrackCount
RoutingValidator.createTrackInfo = RoutingValidator_Core.createTrackInfo
RoutingValidator.getIssueTypes = RoutingValidator_Core.getIssueTypes
RoutingValidator.getSeverity = RoutingValidator_Core.getSeverity

-- FROM RoutingValidator_Detection
RoutingValidator.validateProjectRouting = RoutingValidator_Detection.validateProjectRouting
RoutingValidator.detectChannelOrderConflicts = RoutingValidator_Detection.detectChannelOrderConflicts
RoutingValidator.findMasterFormat = RoutingValidator_Detection.findMasterFormat
RoutingValidator.createReferenceRouting = RoutingValidator_Detection.createReferenceRouting
RoutingValidator.getTrackChannelInfo = RoutingValidator_Detection.getTrackChannelInfo
RoutingValidator.checkChannelConsistency = RoutingValidator_Detection.checkChannelConsistency
RoutingValidator.getTrackRequiredChannels = RoutingValidator_Detection.getTrackRequiredChannels
RoutingValidator.detectOrphanSends = RoutingValidator_Detection.detectOrphanSends

-- FROM RoutingValidator_Fixes
RoutingValidator.generateFixSuggestions = RoutingValidator_Fixes.generateFixSuggestions
RoutingValidator.generateFixSuggestion = RoutingValidator_Fixes.generateFixSuggestion
RoutingValidator.autoFixRouting = RoutingValidator_Fixes.autoFixRouting
RoutingValidator.applySingleFix = RoutingValidator_Fixes.applySingleFix
RoutingValidator.applyNewRouting = RoutingValidator_Fixes.applyNewRouting
RoutingValidator.applyChannelOrderChoice = RoutingValidator_Fixes.applyChannelOrderChoice
RoutingValidator.getActualTrackRouting = RoutingValidator_Fixes.getActualTrackRouting
RoutingValidator.detectConflictsLegacy = RoutingValidator_Fixes.detectConflictsLegacy
RoutingValidator.findIntelligentRoutingLegacy = RoutingValidator_Fixes.findIntelligentRoutingLegacy
RoutingValidator.matchChannelsByLabelLegacy = RoutingValidator_Fixes.matchChannelsByLabelLegacy

-- FROM RoutingValidator_UI
RoutingValidator.showValidationModal = RoutingValidator_UI.showValidationModal
RoutingValidator.renderModal = RoutingValidator_UI.renderModal
RoutingValidator.renderHeader = RoutingValidator_UI.renderHeader
RoutingValidator.renderIssuesOverview = RoutingValidator_UI.renderIssuesOverview
RoutingValidator.renderProjectTree = RoutingValidator_UI.renderProjectTree
RoutingValidator.renderTrackNode = RoutingValidator_UI.renderTrackNode
RoutingValidator.renderChannelMap = RoutingValidator_UI.renderChannelMap
RoutingValidator.renderFixSuggestions = RoutingValidator_UI.renderFixSuggestions
RoutingValidator.renderFooter = RoutingValidator_UI.renderFooter
RoutingValidator.fixSingleIssue = RoutingValidator_UI.fixSingleIssue
RoutingValidator.showChannelOrderResolutionModal = RoutingValidator_UI.showChannelOrderResolutionModal
RoutingValidator.renderChannelOrderModal = RoutingValidator_UI.renderChannelOrderModal
RoutingValidator.hasActiveIssues = RoutingValidator_UI.hasActiveIssues
RoutingValidator.clearValidation = RoutingValidator_UI.clearValidation
RoutingValidator.validateAndShow = RoutingValidator_UI.validateAndShow
RoutingValidator.checkOptimizationOpportunities = RoutingValidator_UI.checkOptimizationOpportunities
RoutingValidator.applyChannelOptimization = RoutingValidator_UI.applyChannelOptimization
RoutingValidator.showOptimizationSuggestion = RoutingValidator_UI.showOptimizationSuggestion
RoutingValidator.testValidationSystem = RoutingValidator_UI.testValidationSystem
RoutingValidator.debugValidationState = RoutingValidator_UI.debugValidationState

-- ===================================================================
-- LEGACY COMPATIBILITY ALIASES
-- ===================================================================

-- Legacy function redirects
RoutingValidator.showResolutionModal = function(conflicts)
    if conflicts then
        local issues = RoutingValidator.validateProjectRouting()
        RoutingValidator.showValidationModal(issues)
    end
end

RoutingValidator.findIntelligentRouting = RoutingValidator_Fixes.findIntelligentRoutingLegacy
RoutingValidator.matchChannelsByLabel = RoutingValidator_Fixes.matchChannelsByLabelLegacy

RoutingValidator.hasActiveConflicts = function()
    return RoutingValidator.hasActiveIssues()
end

RoutingValidator.clearConflicts = RoutingValidator.clearValidation

RoutingValidator.applyResolution = function()
    if globals.pendingIssuesList then
        local state = RoutingValidator_Core.getState()
        local fixSuggestions = state.fixSuggestions
        if fixSuggestions then
            RoutingValidator.autoFixRouting(globals.pendingIssuesList, fixSuggestions)
            RoutingValidator.clearValidation()
        end
    end
end

-- Legacy detectConflicts that returns legacy format
RoutingValidator.detectConflicts = function()
    local issues = RoutingValidator.validateProjectRouting()
    local ISSUE_TYPES = RoutingValidator_Core.getIssueTypes()

    local legacyConflicts = {
        containers = {},
        conflictPairs = {},
        channelUsage = {}
    }

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

-- Get current project track cache (for external access)
RoutingValidator.getProjectTrackCache = function()
    local state = RoutingValidator_Core.getState()
    return state.projectTrackCache
end

-- ===================================================================
-- SUB-MODULE ACCESS
-- ===================================================================

-- Provide direct access to sub-modules for advanced usage
function RoutingValidator.getSubModules()
    return {
        Core = RoutingValidator_Core,
        Detection = RoutingValidator_Detection,
        Fixes = RoutingValidator_Fixes,
        UI = RoutingValidator_UI
    }
end

-- TEMPORARY: Global alias for backward compatibility during transition
_G.ConflictResolver = RoutingValidator

return RoutingValidator
