--[[
@version 1.5
@noindex
--]]

local Presets = {}
local globals = {}
local presetCache = {}
local presetCacheTime = {}

-- Initialize the module with global references from the main script
function Presets.initModule(g)
  globals = g
end

-- Function to determine the path for presets, creating the folder structure if needed
function Presets.getPresetsPath(type, groupName)
  local basePath

  if globals.presetsPath ~= "" then 
    basePath = globals.presetsPath 
  else
    -- Define the base path depending on the OS
    if reaper.GetOS():match("Win") then
      basePath = os.getenv("APPDATA") .. "\\REAPER\\Scripts\\Demute\\Ambiance Creator\\Presets\\"
    elseif reaper.GetOS():match("OSX") then
      basePath = os.getenv("HOME") .. "/Library/Application Support/REAPER/Scripts/Demute/Ambiance Creator/Presets/"
    else -- Linux
      basePath = os.getenv("HOME") .. "/.config/REAPER/Scripts/Demute/Ambiance Creator/Presets/"
    end

    -- Create the base directory if it doesn't exist
    reaper.RecursiveCreateDirectory(basePath, 1)

    globals.presetsPath = basePath
  end

  -- Determine the subfolder based on the preset type
  local specificPath = basePath

  if type == "Global" then
    specificPath = basePath .. "Global" .. package.config:sub(1,1)
  elseif type == "Groups" then
    specificPath = basePath .. "Groups" .. package.config:sub(1,1)
  elseif type == "Containers" then
    -- Remove dependency on groupName for containers
    specificPath = basePath .. "Containers" .. package.config:sub(1,1)
  end

  -- Create the specific directory if it doesn't exist
  reaper.RecursiveCreateDirectory(specificPath, 1)

  return specificPath
end

-- Function to list available presets by type, with optional cache and force refresh
function Presets.listPresets(type, groupName, forceRefresh)
  local currentTime = os.time()
  local cacheKey = type -- No need to include groupName for containers

  if not type then type = "Global" end

  -- Initialize cache if necessary
  if not presetCache then presetCache = {} end
  if not presetCacheTime then presetCacheTime = {} end

  if not forceRefresh and presetCache[cacheKey] then
    return presetCache[cacheKey] -- Return from cache if available
  end

  -- Get the directory path (groupName ignored for containers)
  local path = Presets.getPresetsPath(type, nil)

  -- Reset the preset list
  local typePresets = {}

  -- Use reaper.EnumerateFiles to list all .lua preset files
  local i = 0
  local file = reaper.EnumerateFiles(path, i)
  while file do
    if file:match("%.lua$") then
      local presetName = file:gsub("%.lua$", "")
      typePresets[#typePresets + 1] = presetName
    end
    i = i + 1
    file = reaper.EnumerateFiles(path, i)
  end

  table.sort(typePresets)
  presetCache[cacheKey] = typePresets
  presetCacheTime[cacheKey] = currentTime

  return typePresets
end

-- Helper function to serialize a table into a Lua string
local function serializeTable(val, name, depth)
  depth = depth or 0
  local indent = string.rep("  ", depth)
  local result = ""

  if name then result = indent .. name .. " = " end

  if type(val) == "table" then
    result = result .. "{\n"
    for k, v in pairs(val) do
      local key
      if type(k) == "number" then
        key = "[" .. k .. "]"
      elseif type(k) == "string" then
        -- Check if key is a valid Lua identifier
        if k:match("^[%a_][%w_]*$") then
          key = k
        else
          -- Non-identifier string (like UUID), use bracket notation with quotes
          key = "[" .. string.format("%q", k) .. "]"
        end
      else
        key = "[" .. tostring(k) .. "]"
      end
      result = result .. serializeTable(v, key, depth + 1) .. ",\n"
    end
    result = result .. indent .. "}"
  elseif type(val) == "number" then
    result = result .. tostring(val)
  elseif type(val) == "string" then
    result = result .. string.format("%q", val)
  elseif type(val) == "boolean" then
    result = result .. (val and "true" or "false")
  else
    result = result .. "nil"
  end

  return result
end

-- Save a global preset (all groups) to disk
function Presets.savePreset(name)
  if name == "" then return false end

  -- If auto-import media is enabled, process all containers in all groups
  if globals.Settings and globals.Settings.getSetting("autoImportMedia") then
    for _, group in ipairs(globals.groups) do
      for _, container in ipairs(group.containers) do
        globals.Settings.processContainerMedia(container)
      end
    end
  end

  local path = Presets.getPresetsPath("Global") .. name .. ".lua"
  local file = io.open(path, "w")

  if file then
    file:write("-- Ambiance Creator Global Preset: " .. name .. "\n")
    file:write("-- Created on " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
    file:write("return " .. serializeTable(globals.groups) .. "\n")
    file:close()

    -- Refresh the preset list
    Presets.listPresets("Global", nil, true)
    return true
  end

  return false
end

-- Load a global preset from disk and set it as the current groups
function Presets.loadPreset(name)
  if name == "" then return false end

  globals.selectedContainers = {}

  local path = Presets.getPresetsPath("Global") .. name .. ".lua"
  local success, presetData = pcall(dofile, path)

  if success and type(presetData) == "table" then
    globals.groups = presetData
    globals.currentPresetName = name

    -- Migrate containers to UUID system (backward compatibility)
    local migrated = globals.Structures.migrateContainersToUUID(presetData)
    if migrated then
      reaper.ShowConsoleMsg("Migrated containers to UUID system - Please save your presets again.\n")
    end

    -- Apply backward compatibility and track volumes for all groups and containers
    for groupIndex, group in ipairs(presetData) do
      -- Backward compatibility: Set pitchMode to PITCH if it doesn't exist
      if group.pitchMode == nil then
        group.pitchMode = globals.Constants.PITCH_MODES.PITCH
      end

      -- Apply group track volume if it exists
      if group.trackVolume then
        globals.Utils.setGroupTrackVolume(groupIndex, group.trackVolume)
      end

      -- Apply container track volumes and backward compatibility
      if group.containers then
        for containerIndex, container in ipairs(group.containers) do
          -- Backward compatibility: Set pitchMode to PITCH if it doesn't exist
          if container.pitchMode == nil then
            container.pitchMode = globals.Constants.PITCH_MODES.PITCH
          end

          if container.trackVolume then
            globals.Utils.setContainerTrackVolume(groupIndex, containerIndex, container.trackVolume)
          end
        end
      end
    end

    -- Clear history and capture the loaded preset state as the starting point
    if globals.History then
      globals.History.clear()
      globals.History.captureState("Loaded preset: " .. name)
    end

    return true
  else
    reaper.ShowConsoleMsg("Error loading preset: " .. tostring(presetData) .. "\n")
    return false
  end
end

-- Delete a preset file by name and type
function Presets.deletePreset(name, type, groupName)
  if name == "" then return false end

  if not type then type = "Global" end

  local path = Presets.getPresetsPath(type, groupName) .. name .. ".lua"
  local success, result = os.remove(path)

  if success then
    -- Refresh the preset list
    Presets.listPresets(type, groupName, true)
    if type == "Global" then
      globals.currentPresetName = ""
      globals.selectedPresetIndex = 0
    end
    return true
  else
    reaper.ShowConsoleMsg("Error deleting preset: " .. tostring(result) .. "\n")
    return false
  end
end

-- Save a group preset (single group) to disk
function Presets.saveGroupPreset(name, groupIndex)
  if name == "" then return false end

  -- If auto-import media is enabled, process all containers in the group
  if globals.Settings and globals.Settings.getSetting("autoImportMedia") then
    local group = globals.groups[groupIndex]
    for _, container in ipairs(group.containers) do
      globals.Settings.processContainerMedia(container)
    end
  end

  local group = globals.groups[groupIndex]
  local path = Presets.getPresetsPath("Groups") .. name .. ".lua"
  local file = io.open(path, "w")

  if file then
    file:write("-- Ambiance Creator Group Preset: " .. name .. "\n")
    file:write("-- Created on " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
    file:write("return " .. serializeTable(group) .. "\n")
    file:close()

    -- Refresh the preset list
    Presets.listPresets("Groups", nil, true)
    return true
  end

  return false
end

-- Load a group preset from disk and assign it to the specified group index
function Presets.loadGroupPreset(name, groupIndex)
  if name == "" then return false end

  -- Capture state before loading group preset
  if globals.History then
    globals.History.captureState("Load group preset: " .. name)
  end

  local path = Presets.getPresetsPath("Groups") .. name .. ".lua"
  local success, presetData = pcall(dofile, path)

  if success and type(presetData) == "table" then
    -- Backward compatibility: Set pitchMode to PITCH if it doesn't exist
    if presetData.pitchMode == nil then
      presetData.pitchMode = globals.Constants.PITCH_MODES.PITCH
    end

    -- Migrate containers to UUID system
    if presetData.containers then
      globals.Structures.migrateContainersToUUID({presetData})
    end

    globals.groups[groupIndex] = presetData

    -- Set regeneration flag since preset loading changes parameters
    globals.groups[groupIndex].needsRegeneration = true
    if presetData.containers then
      for _, container in ipairs(presetData.containers) do
        -- Backward compatibility: Set pitchMode to PITCH if it doesn't exist
        if container.pitchMode == nil then
          container.pitchMode = globals.Constants.PITCH_MODES.PITCH
        end

        container.needsRegeneration = true
        -- Force disable pan randomization for multichannel containers from old presets
        if container.channelMode and container.channelMode > 0 then
          container.randomizePan = false
        end
      end
    end

    -- Areas are now stored directly in items and will be synchronized to waveformAreas by the UI when needed

    -- Apply group track volume if it exists
    if presetData.trackVolume then
      globals.Utils.setGroupTrackVolume(groupIndex, presetData.trackVolume)
    end

    -- Apply track volumes for all containers in the group if they have tracks
    if presetData.containers then
      for containerIndex, container in ipairs(presetData.containers) do
        if container.trackVolume then
          globals.Utils.setContainerTrackVolume(groupIndex, containerIndex, container.trackVolume)
        end
      end
    end

    return true
  else
    reaper.ShowConsoleMsg("Error loading group preset: " .. tostring(presetData) .. "\n")
    return false
  end
end

-- Save a container preset (single container) to disk
function Presets.saveContainerPreset(name, groupIndex, containerIndex)
  if name == "" then return false end

  -- If auto-import media is enabled, process the container
  if globals.Settings and globals.Settings.getSetting("autoImportMedia") then
    local container = globals.groups[groupIndex].containers[containerIndex]
    globals.Settings.processContainerMedia(container)
  end

  -- Remove any reference to track name (if any)
  local container = globals.groups[groupIndex].containers[containerIndex]

  local path = Presets.getPresetsPath("Containers") .. name .. ".lua"
  local file = io.open(path, "w")

  if file then
    file:write("-- Ambiance Creator Container Preset: " .. name .. "\n")
    file:write("-- Created on " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
    file:write("return " .. serializeTable(container) .. "\n")
    file:close()

    -- Refresh the preset list (no groupName reference)
    Presets.listPresets("Containers", nil, true)
    return true
  end

  return false
end

-- Load a container preset from disk and apply it to the specified container, preserving existing items
function Presets.loadContainerPreset(name, groupIndex, containerIndex)
  if name == "" then return false end

  -- Capture state before loading container preset
  if globals.History then
    globals.History.captureState("Load container preset: " .. name)
  end

  -- Remove any reference to track name (if any)
  local path = Presets.getPresetsPath("Containers") .. name .. ".lua"
  local success, presetData = pcall(dofile, path)

  if success and type(presetData) == "table" then
    -- Backward compatibility: Set pitchMode to PITCH if it doesn't exist
    if presetData.pitchMode == nil then
      presetData.pitchMode = globals.Constants.PITCH_MODES.PITCH
    end

    -- Migrate container to UUID system
    if not presetData.id then
      local Utils = require("DM_Ambiance_Utils")
      presetData.id = Utils.generateUUID()
    end

    -- Apply the preset data to the container
    globals.groups[groupIndex].containers[containerIndex] = presetData

    -- Set regeneration flag since preset loading changes parameters
    globals.groups[groupIndex].containers[containerIndex].needsRegeneration = true

    -- Force disable pan randomization for multichannel containers from old presets
    if presetData.channelMode and presetData.channelMode > 0 then
      globals.groups[groupIndex].containers[containerIndex].randomizePan = false
    end

    -- Apply the container track volume if the container track exists
    if presetData.trackVolume then
      globals.Utils.setContainerTrackVolume(groupIndex, containerIndex, presetData.trackVolume)
    end

    return true
  else
    reaper.ShowConsoleMsg("Error loading container preset: " .. tostring(presetData) .. "\n")
    return false
  end
end

-- ====================================================================
-- EUCLIDEAN PATTERN MANAGEMENT
-- ====================================================================

--- Save a euclidean pattern to the saved patterns list (supports multi-layer)
-- @param dataObj table The group or container object
-- @param layers table Array of layers {{pulses, steps, rotation}, ...}
-- @return string The auto-generated pattern name
function Presets.saveEuclideanPattern(dataObj, layers)
  if not dataObj then return nil end
  if not layers or #layers == 0 then return nil end

  -- Initialize saved patterns array if needed
  if not dataObj.euclideanSavedPatterns then
    dataObj.euclideanSavedPatterns = {}
  end

  -- Auto-generate name from parameters
  local patternName = ""
  for i, layer in ipairs(layers) do
    if i > 1 then patternName = patternName .. " | " end
    patternName = patternName .. string.format("%d-%d-%d", layer.pulses, layer.steps, layer.rotation)
  end

  -- Check if pattern already exists
  for _, pattern in ipairs(dataObj.euclideanSavedPatterns) do
    if pattern.name == patternName then
      -- Pattern already exists, don't add duplicate
      return patternName
    end
  end

  -- Add new pattern with deep copy of layers
  local layersCopy = {}
  for i, layer in ipairs(layers) do
    table.insert(layersCopy, {
      pulses = layer.pulses,
      steps = layer.steps,
      rotation = layer.rotation
    })
  end

  table.insert(dataObj.euclideanSavedPatterns, {
    name = patternName,
    layers = layersCopy  -- Store entire array of layers
  })

  return patternName
end

--- Override an existing euclidean pattern with new values (supports multi-layer)
-- @param dataObj table The group or container object
-- @param patternName string Name of the pattern to override
-- @param layers table Array of layers {{pulses, steps, rotation}, ...}
-- @return boolean Success status
function Presets.overrideEuclideanPattern(dataObj, patternName, layers)
  if not dataObj or not patternName then return false end
  if not dataObj.euclideanSavedPatterns then return false end
  if not layers or #layers == 0 then return false end

  -- Find and update the pattern
  for i, pattern in ipairs(dataObj.euclideanSavedPatterns) do
    if pattern.name == patternName then
      -- Update with new auto-generated name
      local newName = ""
      for j, layer in ipairs(layers) do
        if j > 1 then newName = newName .. " | " end
        newName = newName .. string.format("%d-%d-%d", layer.pulses, layer.steps, layer.rotation)
      end

      -- Deep copy layers
      local layersCopy = {}
      for j, layer in ipairs(layers) do
        table.insert(layersCopy, {
          pulses = layer.pulses,
          steps = layer.steps,
          rotation = layer.rotation
        })
      end

      pattern.name = newName
      pattern.layers = layersCopy
      -- Clear old format fields if they exist
      pattern.pulses = nil
      pattern.steps = nil
      pattern.rotation = nil
      return true
    end
  end

  return false
end

--- Load a saved euclidean pattern (supports multi-layer)
-- @param dataObj table The group or container object
-- @param patternName string Name of the pattern to load
-- @return table|nil Pattern data {layers = {{pulses, steps, rotation}, ...}} or nil if not found
function Presets.loadEuclideanPattern(dataObj, patternName)
  if not dataObj or not patternName then return nil end
  if not dataObj.euclideanSavedPatterns then return nil end

  for _, pattern in ipairs(dataObj.euclideanSavedPatterns) do
    if pattern.name == patternName then
      -- Support old format (single layer) and new format (multi-layer)
      if pattern.layers then
        -- New format: return deep copy of layers
        local layersCopy = {}
        for i, layer in ipairs(pattern.layers) do
          table.insert(layersCopy, {
            pulses = layer.pulses,
            steps = layer.steps,
            rotation = layer.rotation
          })
        end
        return {layers = layersCopy}
      else
        -- Old format: convert to new format
        return {
          layers = {{
            pulses = pattern.pulses,
            steps = pattern.steps,
            rotation = pattern.rotation
          }}
        }
      end
    end
  end

  return nil
end

--- Delete a saved euclidean pattern
-- @param dataObj table The group or container object
-- @param patternName string Name of the pattern to delete
-- @return boolean Success status
function Presets.deleteEuclideanPattern(dataObj, patternName)
  if not dataObj or not patternName then return false end
  if not dataObj.euclideanSavedPatterns then return false end

  for i, pattern in ipairs(dataObj.euclideanSavedPatterns) do
    if pattern.name == patternName then
      table.remove(dataObj.euclideanSavedPatterns, i)
      return true
    end
  end

  return false
end

--- Get list of saved pattern names
-- @param dataObj table The group or container object
-- @return table Array of pattern names
function Presets.getEuclideanPatternNames(dataObj)
  if not dataObj or not dataObj.euclideanSavedPatterns then
    return {}
  end

  local names = {}
  for _, pattern in ipairs(dataObj.euclideanSavedPatterns) do
    table.insert(names, pattern.name)
  end

  return names
end

return Presets
