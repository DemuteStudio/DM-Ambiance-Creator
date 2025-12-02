--[[
@version 1.0
@noindex
DM Ambiance Creator - Waveform Compatibility Wrapper

This file is a compatibility wrapper that delegates to the new modular Waveform system.
It allows existing code using require("DM_Ambiance_Waveform") to continue working.

The actual implementation is now in Audio/Waveform/ which contains:
- Waveform_Core.lua (data extraction, caching, peak generation)
- Waveform_Rendering.lua (waveform visualization)
- Waveform_Playback.lua (audio preview controls)
- Waveform_Areas.lua (area/zone management)
--]]

-- Get script path for loading the new modular Waveform
local info = debug.getinfo(1, "S")
local script_path = info.source:match[[^@?(.*[\/])[^\/]-$]]

-- Load and return the new modular Waveform system
return dofile(script_path .. "Audio/Waveform/init.lua")
