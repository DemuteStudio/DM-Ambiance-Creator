--[[
@version 1.0
@noindex
DM Ambiance Creator - Export Module Aggregator
--]]

local Export = {}
local globals = {}

-- Get the module path for loading sub-modules
local info = debug.getinfo(1, "S")
local modulePath = info.source:match[[^@?(.*[\/])[^\/]-$]]

-- Load sub-modules
local Export_Core = dofile(modulePath .. "Export_Core.lua")
local Export_UI = dofile(modulePath .. "Export_UI.lua")

function Export.initModule(g)
    if not g then
        error("Export.initModule: globals parameter is required")
    end
    globals = g

    -- Initialize sub-modules
    Export_Core.initModule(g)
    Export_UI.initModule(g)
    Export_UI.setDependencies(Export_Core)
end

-- Re-export main functions
Export.openModal = function()
    return Export_UI.openModal()
end

Export.renderModal = function()
    return Export_UI.renderModal()
end

Export.performExport = function()
    return Export_Core.performExport()
end

Export.resetSettings = function()
    return Export_Core.resetSettings()
end

-- Provide access to sub-modules for advanced usage
function Export.getSubModules()
    return {
        Core = Export_Core,
        UI = Export_UI
    }
end

return Export
