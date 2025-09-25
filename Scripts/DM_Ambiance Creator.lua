--[[
@description DM_Ambiance Creator
@version 0.9.2-beta
@about
    The Ambiance Creator is a tool that makes it easy to create soundscapes by randomly placing audio elements on the REAPER timeline according to user parameters.
@author Anthony Deneyer
@provides
    [nomain] Modules/*.lua
    Icons/*.png
@changelog
  Fix a crash when doing a time selection.
--]]

-- Check if ReaImGui is available; display an error and exit if not
if not reaper.ImGui_CreateContext then
    reaper.MB("This script requires ReaImGui. Please install the extension via ReaPack.", "Error", 0)
    return
end

-- Proper initialization of ReaImGui as recommended by the developer
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local imgui = require 'imgui' '0.9.3'

-- Define the path for custom modules (relative to the script location)
local script_path = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]
-- Add modules path so sub-modules can find each other
package.path = script_path .. "Modules/?.lua;" .. package.path

-- Import all project modules using dofile for better performance
local Constants = dofile(script_path .. "Modules/DM_Ambiance_Constants.lua")
local Utils = dofile(script_path .. "Modules/DM_Ambiance_Utils.lua")
local Structures = dofile(script_path .. "Modules/DM_Ambiance_Structures.lua")
local Items = dofile(script_path .. "Modules/DM_Ambiance_Items.lua")
local Presets = dofile(script_path .. "Modules/DM_Ambiance_Presets.lua")
local Generation = dofile(script_path .. "Modules/DM_Ambiance_Generation.lua")
local UI = dofile(script_path .. "Modules/DM_Ambiance_UI.lua")
local Settings = dofile(script_path .. "Modules/DM_AmbianceCreator_Settings.lua")
local ConflictResolver = dofile(script_path .. "Modules/DM_Ambiance_ConflictResolver.lua")

-- Global state shared across modules and UI
local globals = {
    groups = {},                      -- Stores all defined groups
    timeSelectionValid = false,       -- Indicates if a valid time selection exists in the project
    startTime = 0,                    -- Start time of the current time selection
    endTime = 0,                      -- End time of the current time selection
    timeSelectionLength = 0,          -- Length of the time selection
    currentPresetName = "",           -- Name of the currently loaded global preset
    presetsPath = "",                 -- Path to the presets directory
    selectedGroupPresetIndex = {},    -- Stores selected group preset indices for each group
    selectedContainerPresetIndex = {},-- Stores selected container preset indices for each container
    currentSaveGroupIndex = nil,      -- Index of the group currently being saved as a preset
    currentSaveContainerGroup = nil,  -- Index of the group for the container being saved
    currentSaveContainerIndex = nil,  -- Index of the container being saved as a preset
    newGroupPresetName = "",          -- Input field for new group preset name
    newContainerPresetName = "",      -- Input field for new container preset name
    newPresetName = "",               -- Input field for new global preset name
    selectedPresetIndex = -1,         -- Index of the currently selected global preset
    activePopups = {},                -- Table tracking active popup windows
    showMediaDirWarning = false,      -- Flag to display a warning if the media directory is not configured
    mediaWarningShown = false,        -- Prevents showing the media warning multiple times
    keepExistingTracks = true,        -- Default behavior for generation (changed from overrideExistingTracks)
    containerExpandedStates = {},     -- Stores expanded/collapsed states for container item lists to prevent auto-collapse
    
    -- Pending operations to avoid ImGui conflicts
    pendingGroupMove = nil,           -- Pending group reorder operation
    pendingContainerMove = nil,       -- Pending container move operation
    pendingContainerReorder = nil,    -- Pending container reorder within same group
    
    -- Drag and drop state
    draggedItem = nil,                -- Currently dragged item info
}

-- Main loop function for the GUI; called repeatedly via reaper.defer
local function loop()
    UI.PushStyle()

    -- Show the media directory warning popup ONLY if required
    if globals.showMediaDirWarning then
        Utils.showDirectoryWarningPopup()
    end
    
    -- Show conflict resolution modal if needed
    if globals.showConflictModal then
        ConflictResolver.renderModal()
    end

    -- Render the main window; returns 'open' (true if window is open)
    local open = UI.ShowMainWindow(true)
    
    UI.PopStyle()

    -- Continue the loop if the window is still open
    if open then
        reaper.defer(loop)
    end
end

-- Script entry point when run directly (not as a module)
if select(2, reaper.get_action_context()) == debug.getinfo(1, 'S').source:sub(2) then
    -- Expose variables and modules globally for debugging and live tweaking
    _G.globals = globals
    _G.Constants = Constants
    _G.Utils = Utils
    _G.Structures = Structures
    _G.Items = Items
    _G.Presets = Presets
    _G.Generation = Generation
    _G.UI = UI
    _G.Settings = Settings
    _G.ConflictResolver = ConflictResolver
    _G.imgui = imgui

    -- Seed the random number generator for consistent randomization
    math.randomseed(os.time())

    -- Create the ImGui context for the application window
    local ctx = imgui.CreateContext('Ambiance Creator')
    globals.ctx = ctx
    globals.imgui = imgui

    -- Share module references through the globals table for cross-module access
    globals.Constants = Constants
    globals.Utils = Utils
    globals.Structures = Structures
    globals.Items = Items
    globals.Presets = Presets
    globals.Generation = Generation
    globals.UI = UI
    globals.Settings = Settings
    globals.ConflictResolver = ConflictResolver

    -- Initialize all modules with the shared globals table
    Utils.initModule(globals)
    Structures.initModule(globals)
    Items.initModule(globals)
    Presets.initModule(globals)
    Generation.initModule(globals)
    UI.initModule(globals)
    Settings.initModule(globals)
    ConflictResolver.initModule(globals)
    
    -- Initialize backward compatibility for container volumes
    Utils.initializeContainerVolumes()

    -- Start the main UI loop
    reaper.defer(loop)
end