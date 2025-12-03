--[[
@version 2.1
@author DM
@description Comprehensive Channel Routing Validator Compatibility Wrapper
@noindex

This file is a compatibility wrapper that delegates to the new modular RoutingValidator system.
It allows existing code using require("DM_Ambiance_RoutingValidator") to continue working.

The actual implementation is now in Routing/init.lua which aggregates:
- RoutingValidator_Core.lua (infrastructure, scanning, state management)
- RoutingValidator_Detection.lua (issue detection, channel analysis, validation)
- RoutingValidator_Fixes.lua (fix suggestion generation and application)
- RoutingValidator_UI.lua (user interface, modals, rendering)
--]]

-- Get script path for loading the new modular RoutingValidator
local info = debug.getinfo(1, "S")
local script_path = info.source:match[[^@?(.*[\\/])[^\\/]-$]]

-- Load and return the new modular RoutingValidator system
return dofile(script_path .. "Routing/init.lua")
