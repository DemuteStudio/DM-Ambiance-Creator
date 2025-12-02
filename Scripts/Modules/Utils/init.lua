--[[
@version 1.5
@noindex
DM Ambiance Creator - Utils Module Aggregator
This module provides backward compatibility by re-exporting all functions
from the modular Utils sub-modules.

Usage:
    local Utils = dofile(script_path .. "Modules/Utils/init.lua")
    Utils.initModule(globals)
    Utils.functionName() -- All functions available as before
--]]

local Utils = {}
local globals = {}

-- Get the path to this file's directory for loading sub-modules
local info = debug.getinfo(1, "S")
local modulePath = info.source:match[[^@?(.*[\/])[^\/]-$]]

-- Load sub-modules immediately using dofile (REAPER compatible)
local Utils_Core = dofile(modulePath .. "Utils_Core.lua")
local Utils_String = dofile(modulePath .. "Utils_String.lua")
local Utils_Math = dofile(modulePath .. "Utils_Math.lua")
local Utils_Validation = dofile(modulePath .. "Utils_Validation.lua")
local Utils_UI = dofile(modulePath .. "Utils_UI.lua")
local Utils_REAPER = dofile(modulePath .. "Utils_REAPER.lua")

-- Track initialization state
local initialized = false

-- Initialize the Utils module and all sub-modules
function Utils.initModule(g)
    if not g then
        error("Utils.initModule: globals parameter is required")
    end
    globals = g

    -- Initialize sub-modules that need globals
    if Utils_Core.initModule then Utils_Core.initModule(g) end
    if Utils_Validation.initModule then Utils_Validation.initModule(g) end
    if Utils_UI.initModule then Utils_UI.initModule(g) end
    if Utils_REAPER.initModule then Utils_REAPER.initModule(g) end

    initialized = true
end

-- ===================================================================
-- RE-EXPORT ALL FUNCTIONS FOR BACKWARD COMPATIBILITY
-- ===================================================================

-- FROM Utils_Core
Utils.generateUUID = Utils_Core.generateUUID
Utils.deepCopy = Utils_Core.deepCopy
Utils.copyTable = Utils_Core.copyTable
Utils.getItemFromPath = Utils_Core.getItemFromPath
Utils.getParentFromPath = Utils_Core.getParentFromPath
Utils.pathsEqual = Utils_Core.pathsEqual
Utils.copyPath = Utils_Core.copyPath
Utils.removeItemAtPath = Utils_Core.removeItemAtPath
Utils.insertItemAtPath = Utils_Core.insertItemAtPath
Utils.getCollectionFromPath = Utils_Core.getCollectionFromPath

-- FROM Utils_String
Utils.formatTime = Utils_String.formatTime
Utils.fuzzyMatch = Utils_String.fuzzyMatch
Utils.pathToString = Utils_String.pathToString
Utils.pathFromString = Utils_String.pathFromString
Utils.makeContainerKey = Utils_String.makeContainerKey
Utils.parseContainerKey = Utils_String.parseContainerKey
Utils.generateItemKey = Utils_String.generateItemKey

-- FROM Utils_Math
Utils.randomInRange = Utils_Math.randomInRange
Utils.applyDirectionalVariation = Utils_Math.applyDirectionalVariation
Utils.semitonesToPlayrate = Utils_Math.semitonesToPlayrate
Utils.playrateToSemitones = Utils_Math.playrateToSemitones
Utils.dbToLinear = Utils_Math.dbToLinear
Utils.linearToDb = Utils_Math.linearToDb
Utils.normalizedToDbRelative = Utils_Math.normalizedToDbRelative
Utils.dbToNormalizedRelative = Utils_Math.dbToNormalizedRelative
Utils.calculateProportionalValue = Utils_Math.calculateProportionalValue
Utils.gcd = Utils_Math.gcd
Utils.lcm = Utils_Math.lcm
Utils.lcmMultiple = Utils_Math.lcmMultiple
Utils.euclideanRhythm = Utils_Math.euclideanRhythm
Utils.euclideanRhythmWithRotation = Utils_Math.euclideanRhythmWithRotation
Utils.combineEuclideanLayers = Utils_Math.combineEuclideanLayers

-- FROM Utils_Validation
Utils.isMediaDirectoryConfigured = Utils_Validation.isMediaDirectoryConfigured
Utils.checkTimeSelection = Utils_Validation.checkTimeSelection
Utils.ensureNoiseDefaults = Utils_Validation.ensureNoiseDefaults
Utils.validateNoiseParams = Utils_Validation.validateNoiseParams
Utils.isPathAncestor = Utils_Validation.isPathAncestor

-- FROM Utils_UI
Utils.HelpMarker = Utils_UI.HelpMarker
Utils.openPresetsFolder = Utils_UI.openPresetsFolder
Utils.openFolder = Utils_UI.openFolder
Utils.safeOpenPopup = Utils_UI.safeOpenPopup
Utils.safeClosePopup = Utils_UI.safeClosePopup
Utils.showDirectoryWarningPopup = Utils_UI.showDirectoryWarningPopup
Utils.unpackColor = Utils_UI.unpackColor
Utils.packColor = Utils_UI.packColor
Utils.brightenColor = Utils_UI.brightenColor
Utils.searchableCombo = Utils_UI.searchableCombo

-- FROM Utils_REAPER
Utils.findTrackByName = Utils_REAPER.findTrackByName
Utils.findGroupByName = Utils_REAPER.findGroupByName
Utils.findContainerGroup = Utils_REAPER.findContainerGroup
Utils.clearGroupItems = Utils_REAPER.clearGroupItems
Utils.getAllContainersInGroup = Utils_REAPER.getAllContainersInGroup
Utils.fixGroupFolderStructure = Utils_REAPER.fixGroupFolderStructure
Utils.validateAndRepairGroupStructure = Utils_REAPER.validateAndRepairGroupStructure
Utils.clearGroupItemsInTimeSelection = Utils_REAPER.clearGroupItemsInTimeSelection
Utils.reorganizeTracksAfterGroupReorder = Utils_REAPER.reorganizeTracksAfterGroupReorder
Utils.reorganizeTracksAfterContainerMove = Utils_REAPER.reorganizeTracksAfterContainerMove
Utils.createCrossfade = Utils_REAPER.createCrossfade
Utils.setContainerTrackVolume = Utils_REAPER.setContainerTrackVolume
Utils.getContainerTrackVolume = Utils_REAPER.getContainerTrackVolume
Utils.setChannelTrackVolume = Utils_REAPER.setChannelTrackVolume
Utils.getChannelTrackVolume = Utils_REAPER.getChannelTrackVolume
Utils.syncChannelVolumesFromTracks = Utils_REAPER.syncChannelVolumesFromTracks
Utils.setGroupTrackVolume = Utils_REAPER.setGroupTrackVolume
Utils.getGroupTrackVolume = Utils_REAPER.getGroupTrackVolume
Utils.getContainerTrackMute = Utils_REAPER.getContainerTrackMute
Utils.getContainerTrackSolo = Utils_REAPER.getContainerTrackSolo
Utils.setContainerTrackMute = Utils_REAPER.setContainerTrackMute
Utils.setContainerTrackSolo = Utils_REAPER.setContainerTrackSolo
Utils.getContainerTrackName = Utils_REAPER.getContainerTrackName
Utils.setContainerTrackName = Utils_REAPER.setContainerTrackName
Utils.syncContainerVolumeFromTrack = Utils_REAPER.syncContainerVolumeFromTrack
Utils.syncContainerNameFromTrack = Utils_REAPER.syncContainerNameFromTrack
Utils.syncContainerMuteFromTrack = Utils_REAPER.syncContainerMuteFromTrack
Utils.syncContainerSoloFromTrack = Utils_REAPER.syncContainerSoloFromTrack
Utils.getGroupTrackMute = Utils_REAPER.getGroupTrackMute
Utils.getGroupTrackSolo = Utils_REAPER.getGroupTrackSolo
Utils.setGroupTrackMute = Utils_REAPER.setGroupTrackMute
Utils.setGroupTrackSolo = Utils_REAPER.setGroupTrackSolo
Utils.getGroupTrackName = Utils_REAPER.getGroupTrackName
Utils.setGroupTrackName = Utils_REAPER.setGroupTrackName
Utils.syncGroupVolumeFromTrack = Utils_REAPER.syncGroupVolumeFromTrack
Utils.syncGroupNameFromTrack = Utils_REAPER.syncGroupNameFromTrack
Utils.syncGroupMuteFromTrack = Utils_REAPER.syncGroupMuteFromTrack
Utils.syncGroupSoloFromTrack = Utils_REAPER.syncGroupSoloFromTrack
Utils.getFolderTrackVolume = Utils_REAPER.getFolderTrackVolume
Utils.setFolderTrackVolume = Utils_REAPER.setFolderTrackVolume
Utils.setFolderTrackMute = Utils_REAPER.setFolderTrackMute
Utils.setFolderTrackSolo = Utils_REAPER.setFolderTrackSolo
Utils.setFolderTrackName = Utils_REAPER.setFolderTrackName
Utils.getFolderTrackMute = Utils_REAPER.getFolderTrackMute
Utils.getFolderTrackSolo = Utils_REAPER.getFolderTrackSolo
Utils.getFolderTrackName = Utils_REAPER.getFolderTrackName
Utils.syncFolderVolumeFromTrack = Utils_REAPER.syncFolderVolumeFromTrack
Utils.syncFolderNameFromTrack = Utils_REAPER.syncFolderNameFromTrack
Utils.syncFolderMuteFromTrack = Utils_REAPER.syncFolderMuteFromTrack
Utils.syncFolderSoloFromTrack = Utils_REAPER.syncFolderSoloFromTrack
Utils.initializeContainerVolumes = Utils_REAPER.initializeContainerVolumes
Utils.queueFadeUpdate = Utils_REAPER.queueFadeUpdate
Utils.processQueuedFadeUpdates = Utils_REAPER.processQueuedFadeUpdates
Utils.applyFadeSettingsToContainerItems = Utils_REAPER.applyFadeSettingsToContainerItems
Utils.applyFadeSettingsToGroupItems = Utils_REAPER.applyFadeSettingsToGroupItems
Utils.applyRandomizationSettingsToContainerItems = Utils_REAPER.applyRandomizationSettingsToContainerItems
Utils.applyRandomizationSettingsToGroupItems = Utils_REAPER.applyRandomizationSettingsToGroupItems
Utils.applyRandomizationToItem = Utils_REAPER.applyRandomizationToItem
Utils.queueRandomizationUpdate = Utils_REAPER.queueRandomizationUpdate
Utils.processQueuedRandomizationUpdates = Utils_REAPER.processQueuedRandomizationUpdates
Utils.updateContainerRouting = Utils_REAPER.updateContainerRouting
Utils.ensureParentHasEnoughChannels = Utils_REAPER.ensureParentHasEnoughChannels
Utils.optimizeProjectChannelCount = Utils_REAPER.optimizeProjectChannelCount
Utils.calculateActualChannelUsage = Utils_REAPER.calculateActualChannelUsage
Utils.applyChannelOptimizations = Utils_REAPER.applyChannelOptimizations
Utils.findContainerTrackByName = Utils_REAPER.findContainerTrackByName
Utils.findGroupTrackByName = Utils_REAPER.findGroupTrackByName
Utils.detectRoutingConflicts = Utils_REAPER.detectRoutingConflicts
Utils.suggestRoutingFix = Utils_REAPER.suggestRoutingFix
Utils.getItemAreas = Utils_REAPER.getItemAreas
Utils.selectRandomAreaOrFullItem = Utils_REAPER.selectRandomAreaOrFullItem

-- Provide direct access to sub-modules for advanced usage
function Utils.getSubModules()
    return {
        Core = Utils_Core,
        String = Utils_String,
        Math = Utils_Math,
        Validation = Utils_Validation,
        UI = Utils_UI,
        REAPER = Utils_REAPER
    }
end

-- Check if Utils is initialized
function Utils.isInitialized()
    return initialized
end

return Utils
