--[[
@version 1.0
@noindex
DM Ambiance Creator - Generation Module Aggregator
This module aggregates all generation sub-modules and provides backward compatibility.

Sub-modules:
- Generation_Core.lua: Main generation orchestration
- Generation_TrackManagement.lua: Track creation and folder management
- Generation_ItemPlacement.lua: Item placement on timeline
- Generation_MultiChannel.lua: Multi-channel routing and configuration
- Generation_Modes.lua: Special modes (Noise, Euclidean)
--]]

local Generation = {}
local globals = {}

-- Get the path to this file's directory for loading sub-modules
local info = debug.getinfo(1, "S")
local modulePath = info.source:match[[^@?(.*[\/])[^\/]-$]]

-- Load sub-modules
local Generation_TrackManagement = dofile(modulePath .. "Generation_TrackManagement.lua")
local Generation_MultiChannel = dofile(modulePath .. "Generation_MultiChannel.lua")
local Generation_ItemPlacement = dofile(modulePath .. "Generation_ItemPlacement.lua")
local Generation_Modes = dofile(modulePath .. "Generation_Modes.lua")
local Generation_Core = dofile(modulePath .. "Generation_Core.lua")

-- Initialize all sub-modules
function Generation.initModule(g)
    if not g then
        error("Generation.initModule: globals parameter is required")
    end
    globals = g

    -- Initialize sub-modules
    Generation_TrackManagement.initModule(g)
    Generation_MultiChannel.initModule(g)
    Generation_ItemPlacement.initModule(g)
    Generation_Modes.initModule(g)
    Generation_Core.initModule(g)

    -- Set dependencies between modules
    Generation_MultiChannel.setDependencies(Generation_TrackManagement)
    Generation_ItemPlacement.setDependencies(Generation_TrackManagement, Generation_MultiChannel)
    Generation_Modes.setDependencies(Generation_MultiChannel, Generation_ItemPlacement)
    Generation_Core.setDependencies(Generation_TrackManagement, Generation_MultiChannel, Generation_ItemPlacement, Generation_Modes)
end

-- ===================================================================
-- RE-EXPORT ALL FUNCTIONS FOR BACKWARD COMPATIBILITY
-- ===================================================================

-- FROM Generation_Core
Generation.deleteExistingGroups = Generation_Core.deleteExistingGroups
Generation.generateGroups = Generation_Core.generateGroups
Generation.generateSingleGroup = Generation_Core.generateSingleGroup
Generation.generateSingleGroupByPath = Generation_Core.generateSingleGroupByPath
Generation.generateSingleContainer = Generation_Core.generateSingleContainer
Generation.generateSingleContainerByPath = Generation_Core.generateSingleContainerByPath

-- FROM Generation_TrackManagement
Generation.createMultiChannelTracks = Generation_TrackManagement.createMultiChannelTracks
Generation.getExistingChannelTracks = Generation_TrackManagement.getExistingChannelTracks
Generation.getTrackGUID = Generation_TrackManagement.getTrackGUID
Generation.findTrackByGUID = Generation_TrackManagement.findTrackByGUID
Generation.storeTrackGUIDs = Generation_TrackManagement.storeTrackGUIDs
Generation.findTracksByGUIDs = Generation_TrackManagement.findTracksByGUIDs
Generation.restoreFolderStructure = Generation_TrackManagement.restoreFolderStructure
Generation.adjustFolderClosing = Generation_TrackManagement.adjustFolderClosing
Generation.validateMultiChannelStructure = Generation_TrackManagement.validateMultiChannelStructure
Generation.findChannelTracksByName = Generation_TrackManagement.findChannelTracksByName
Generation.clearChannelTracks = Generation_TrackManagement.clearChannelTracks
Generation.getTracksForContainer = Generation_TrackManagement.getTracksForContainer
Generation.clearContainerItems = Generation_TrackManagement.clearContainerItems
Generation.deleteContainerChildTracks = Generation_TrackManagement.deleteContainerChildTracks
Generation.fixGroupFolderStructure = Generation_TrackManagement.fixGroupFolderStructure
Generation.debugFolderStructure = Generation_TrackManagement.debugFolderStructure
Generation.findGroupTrackRobust = Generation_TrackManagement.findGroupTrackRobust
Generation.findContainerTrack = Generation_TrackManagement.findContainerTrack
Generation.findGroupTrack = Generation_TrackManagement.findGroupTrack
Generation.detectOrphanedContainerTracks = Generation_TrackManagement.detectOrphanedContainerTracks

-- FROM Generation_MultiChannel
Generation.labelToChannelNumber = Generation_MultiChannel.labelToChannelNumber
Generation.applyRoutingFixes = Generation_MultiChannel.applyRoutingFixes
Generation.recalculateChannelRequirements = Generation_MultiChannel.recalculateChannelRequirements
Generation.applyChannelRequirements = Generation_MultiChannel.applyChannelRequirements
Generation.handleConfigurationDowngrade = Generation_MultiChannel.handleConfigurationDowngrade
Generation.detectChannelModeFromTrackCount = Generation_MultiChannel.detectChannelModeFromTrackCount
Generation.removeExcessChildTracks = Generation_MultiChannel.removeExcessChildTracks
Generation.validateFolderStructure = Generation_MultiChannel.validateFolderStructure
Generation.detectAndHandleConfigurationChanges = Generation_MultiChannel.detectAndHandleConfigurationChanges
Generation.propagateConfigurationDowngrade = Generation_MultiChannel.propagateConfigurationDowngrade
Generation.getExistingChildTrackCount = Generation_MultiChannel.getExistingChildTrackCount
Generation.findContainerTrackRobust = Generation_MultiChannel.findContainerTrackRobust
Generation.stabilizeProjectConfiguration = Generation_MultiChannel.stabilizeProjectConfiguration
Generation.captureProjectState = Generation_MultiChannel.captureProjectState
Generation.compareProjectStates = Generation_MultiChannel.compareProjectStates
Generation.checkAndResolveConflicts = Generation_MultiChannel.checkAndResolveConflicts
Generation.applyChannelSelection = Generation_MultiChannel.applyChannelSelection
Generation.getOutputChannelCount = Generation_MultiChannel.getOutputChannelCount
Generation.analyzeContainerItems = Generation_MultiChannel.analyzeContainerItems
Generation.generateStereoPairLabels = Generation_MultiChannel.generateStereoPairLabels
Generation.determineAutoOptimization = Generation_MultiChannel.determineAutoOptimization
Generation.syncPitchModeOnExistingItems = Generation_MultiChannel.syncPitchModeOnExistingItems

-- FROM Generation_ItemPlacement
Generation.placeItemsForContainer = Generation_ItemPlacement.placeItemsForContainer
Generation.placeItemsChunkMode = Generation_ItemPlacement.placeItemsChunkMode
Generation.generateItemsInTimeRange = Generation_ItemPlacement.generateItemsInTimeRange
Generation.applyRandomization = Generation_ItemPlacement.applyRandomization
Generation.applyFades = Generation_ItemPlacement.applyFades
Generation.calculateInterval = Generation_ItemPlacement.calculateInterval
Generation.generateIndependentTrack = Generation_ItemPlacement.generateIndependentTrack

-- FROM Generation_Modes
Generation.determineTrackStructure = Generation_Modes.determineTrackStructure
Generation.placeItemsNoiseMode = Generation_Modes.placeItemsNoiseMode
Generation.placeItemsEuclideanMode = Generation_Modes.placeItemsEuclideanMode

-- Provide direct access to sub-modules for advanced usage
function Generation.getSubModules()
    return {
        Core = Generation_Core,
        TrackManagement = Generation_TrackManagement,
        MultiChannel = Generation_MultiChannel,
        ItemPlacement = Generation_ItemPlacement,
        Modes = Generation_Modes
    }
end

return Generation
