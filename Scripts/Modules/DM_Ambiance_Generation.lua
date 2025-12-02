--[[
@version 1.5
@noindex
DM Ambiance Creator - Generation Compatibility Wrapper

This file is a compatibility wrapper that delegates to the new modular Generation system.
It allows existing code using require("DM_Ambiance_Generation") to continue working.

The actual implementation is now in Audio/Generation/init.lua which aggregates:
- Generation_TrackManagement.lua (track creation and management)
- Generation_MultiChannel.lua (multi-channel routing and distribution)
- Generation_ItemPlacement.lua (item placement on timeline)
- Generation_Modes.lua (interval mode calculations)
- Generation_Core.lua (main generation orchestration)
--]]

-- Get script path for loading the new modular Generation
local info = debug.getinfo(1, "S")
local script_path = info.source:match[[^@?(.*[\\/])[^\\/]-$]]

-- Load and return the new modular Generation system
return dofile(script_path .. "Audio/Generation/init.lua")
