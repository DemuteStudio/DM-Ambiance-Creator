--[[
@version 1.0
@noindex
DM Ambiance Creator - Waveform Module Aggregator
This module aggregates all waveform sub-modules and provides backward compatibility.

Sub-modules:
- Waveform_Core.lua: Data extraction, caching, peak generation
- Waveform_Rendering.lua: Waveform visualization and UI
- Waveform_Playback.lua: Audio preview controls
- Waveform_Areas.lua: Area/zone management
--]]

local Waveform = {}
local globals = {}

-- Get the path to this file's directory for loading sub-modules
local info = debug.getinfo(1, "S")
local modulePath = info.source:match[[^@?(.*[\/])[^\/]-$]]

-- Load sub-modules
local Waveform_Core = dofile(modulePath .. "Waveform_Core.lua")
local Waveform_Rendering = dofile(modulePath .. "Waveform_Rendering.lua")
local Waveform_Playback = dofile(modulePath .. "Waveform_Playback.lua")
local Waveform_Areas = dofile(modulePath .. "Waveform_Areas.lua")

-- Initialize all sub-modules
function Waveform.initModule(g)
    if not g then
        error("Waveform.initModule: globals parameter is required")
    end
    globals = g

    -- Initialize sub-modules
    Waveform_Core.initModule(g)
    Waveform_Rendering.initModule(g)
    Waveform_Playback.initModule(g)
    Waveform_Areas.initModule(g)

    -- Set dependencies for rendering module
    Waveform_Rendering.setDependencies(Waveform_Core, Waveform_Playback, Waveform_Areas)
end

-- ===================================================================
-- RE-EXPORT ALL FUNCTIONS FOR BACKWARD COMPATIBILITY
-- ===================================================================

-- FROM Waveform_Core
Waveform.createPlaceholderWaveform = Waveform_Core.createPlaceholderWaveform
Waveform.getWaveformData = Waveform_Core.getWaveformData
Waveform.getWaveformDataForEditedItem = Waveform_Core.getWaveformDataForEditedItem
Waveform.clearFileCache = Waveform_Core.clearFileCache
Waveform.clearContainerCache = Waveform_Core.clearContainerCache
Waveform.clearCache = Waveform_Core.clearCache
Waveform.generateReapeaksFile = Waveform_Core.generateReapeaksFile
Waveform.regeneratePeaksFile = Waveform_Core.regeneratePeaksFile
Waveform.generatePeaksForContainer = Waveform_Core.generatePeaksForContainer

-- FROM Waveform_Rendering
Waveform.drawWaveform = Waveform_Rendering.drawWaveform

-- FROM Waveform_Playback
Waveform.startPlayback = Waveform_Playback.startPlayback
Waveform.stopPlayback = Waveform_Playback.stopPlayback
Waveform.updatePlaybackPosition = Waveform_Playback.updatePlaybackPosition
Waveform.setPreviewVolume = Waveform_Playback.setPreviewVolume
Waveform.clearSavedPosition = Waveform_Playback.clearSavedPosition
Waveform.resetPositionForFile = Waveform_Playback.resetPositionForFile

-- FROM Waveform_Areas
Waveform.getAreas = Waveform_Areas.getAreas
Waveform.clearAreas = Waveform_Areas.clearAreas
Waveform.deleteArea = Waveform_Areas.deleteArea
Waveform.renameArea = Waveform_Areas.renameArea
Waveform.exportAreas = Waveform_Areas.exportAreas
Waveform.importAreas = Waveform_Areas.importAreas
Waveform.getAreaAtPosition = Waveform_Areas.getAreaAtPosition
Waveform.isWaveformBeingManipulated = Waveform_Areas.isWaveformBeingManipulated
Waveform.isMouseAboutToInteractWithWaveform = Waveform_Areas.isMouseAboutToInteractWithWaveform
Waveform.autoDetectAreas = Waveform_Areas.autoDetectAreas
Waveform.splitCountAreas = Waveform_Areas.splitCountAreas
Waveform.splitTimeAreas = Waveform_Areas.splitTimeAreas
Waveform.processGateDetectionDebounce = Waveform_Areas.processGateDetectionDebounce

-- Cleanup function that calls both Core and Playback cleanup
function Waveform.cleanup()
    Waveform_Playback.stopPlayback(true)
    Waveform_Core.clearCache()
end

-- Provide direct access to sub-modules for advanced usage
function Waveform.getSubModules()
    return {
        Core = Waveform_Core,
        Rendering = Waveform_Rendering,
        Playback = Waveform_Playback,
        Areas = Waveform_Areas
    }
end

return Waveform
