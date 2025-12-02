--[[
@version 1.5
@noindex
DM Ambiance Creator - Validation Utilities Module
Extracted from DM_Ambiance_Utils.lua for better modularity

This module contains all validation functions (paths, values, ranges).
--]]

local Utils_Validation = {}
local Constants = require("DM_Ambiance_Constants")

-- Module globals (set by initModule)
local globals = {}

-- Initialize the module with global references from the main script
function Utils_Validation.initModule(g)
    if not g then
        error("Utils_Validation.initModule: globals parameter is required")
    end
    globals = g
end

-- Check if media directory is configured and accessible
-- @return boolean: true if media directory is configured and exists
function Utils_Validation.isMediaDirectoryConfigured()
    -- Ensure the Settings module is properly initialized
    if not globals.Settings then
        return false
    end

    local mediaDir = globals.Settings.getSetting("mediaItemDirectory")
    return mediaDir ~= nil and mediaDir ~= "" and globals.Settings.directoryExists(mediaDir)
end

-- Check if a time selection exists in the project and update globals accordingly
-- @return boolean: true if time selection exists
function Utils_Validation.checkTimeSelection()
    local start, ending = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    if start ~= ending then
        globals.timeSelectionValid = true
        globals.startTime = start
        globals.endTime = ending
        globals.timeSelectionLength = ending - start
        return true
    else
        globals.timeSelectionValid = false
        return false
    end
end

-- Ensure noise parameters exist with proper defaults
-- @param params table: Parameter table to populate with defaults
-- @return table: Parameter table with defaults applied
function Utils_Validation.ensureNoiseDefaults(params)
    if not params then
        error("Utils_Validation.ensureNoiseDefaults: params parameter is required")
    end

    params.noiseSeed = params.noiseSeed or math.random(Constants.DEFAULTS.NOISE_SEED_MIN, Constants.DEFAULTS.NOISE_SEED_MAX)
    params.noiseAlgorithm = params.noiseAlgorithm or Constants.DEFAULTS.NOISE_ALGORITHM
    params.noiseFrequency = params.noiseFrequency or Constants.DEFAULTS.NOISE_FREQUENCY
    params.noiseAmplitude = params.noiseAmplitude or Constants.DEFAULTS.NOISE_AMPLITUDE
    params.noiseOctaves = params.noiseOctaves or Constants.DEFAULTS.NOISE_OCTAVES
    params.noisePersistence = params.noisePersistence or Constants.DEFAULTS.NOISE_PERSISTENCE
    params.noiseLacunarity = params.noiseLacunarity or Constants.DEFAULTS.NOISE_LACUNARITY
    params.noiseDensity = params.noiseDensity or Constants.DEFAULTS.NOISE_DENSITY
    params.noiseThreshold = params.noiseThreshold or Constants.DEFAULTS.NOISE_THRESHOLD
    params.densityLinkMode = params.densityLinkMode or "link"

    return params
end

-- Validate noise parameters are within acceptable ranges
-- @param params table: Parameter table to validate
-- @return boolean, string: true if valid, or false and error message
function Utils_Validation.validateNoiseParams(params)
    if not params then
        return false, "No parameters provided"
    end

    -- Frequency must be positive
    if params.noiseFrequency and params.noiseFrequency <= 0 then
        return false, "Noise frequency must be greater than 0"
    end

    -- Octaves must be at least 1
    if params.noiseOctaves and params.noiseOctaves < 1 then
        return false, "Noise octaves must be at least 1"
    end

    -- Persistence should be between 0 and 1
    if params.noisePersistence and (params.noisePersistence < 0 or params.noisePersistence > 1) then
        return false, "Noise persistence must be between 0 and 1"
    end

    -- Lacunarity must be at least 1
    if params.noiseLacunarity and params.noiseLacunarity < 1 then
        return false, "Noise lacunarity must be at least 1"
    end

    -- Density should be between 0 and 100
    if params.noiseDensity and (params.noiseDensity < 0 or params.noiseDensity > 100) then
        return false, "Noise density must be between 0 and 100"
    end

    -- Amplitude should be between 0 and 100
    if params.noiseAmplitude and (params.noiseAmplitude < 0 or params.noiseAmplitude > 100) then
        return false, "Noise amplitude must be between 0 and 100"
    end

    return true, ""
end

-- Check if sourcePath is an ancestor of targetPath (prevents circular nesting)
-- @param sourcePath table: Source path array
-- @param targetPath table: Target path array
-- @return boolean: true if source is ancestor of target
function Utils_Validation.isPathAncestor(sourcePath, targetPath)
    if not sourcePath or not targetPath then
        return false
    end

    -- Source can't be ancestor if it's longer or equal
    if #sourcePath >= #targetPath then
        return false
    end

    -- Check if all elements of sourcePath match start of targetPath
    for i = 1, #sourcePath do
        if sourcePath[i] ~= targetPath[i] then
            return false
        end
    end

    return true
end

return Utils_Validation
