--[[
@version 1.5
@noindex
DM Ambiance Creator - Utils Compatibility Wrapper

This file is a compatibility wrapper that delegates to the new modular Utils system.
It allows existing code using require("DM_Ambiance_Utils") to continue working.

The actual implementation is now in Utils/init.lua which aggregates:
- Utils_Core.lua (essential utilities)
- Utils_String.lua (string manipulation)
- Utils_Math.lua (mathematical helpers)
- Utils_Validation.lua (validation functions)
- Utils_UI.lua (UI helpers)
- Utils_REAPER.lua (REAPER API wrappers)
--]]

-- Get script path for loading the new modular Utils
local info = debug.getinfo(1, "S")
local script_path = info.source:match[[^@?(.*[\/])[^\/]-$]]

-- Load and return the new modular Utils system
return dofile(script_path .. "Utils/init.lua")
