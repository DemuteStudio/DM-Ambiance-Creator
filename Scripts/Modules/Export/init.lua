--[[
@version 1.1
@noindex
DM Ambiance Creator - Export Module Aggregator
--]]

local Export = {}
local globals = {}

-- Get the module path for loading sub-modules
local info = debug.getinfo(1, "S")
local modulePath = info.source:match[[^@?(.*[\/])[^\/]-$]]

-- Load sub-modules
local Export_Settings = dofile(modulePath .. "Export_Settings.lua")
local Export_Engine = dofile(modulePath .. "Export_Engine.lua")
local Export_Placement = dofile(modulePath .. "Export_Placement.lua")
local Export_UI = dofile(modulePath .. "Export_UI.lua")

function Export.initModule(g)
    if not g then
        error("Export.initModule: globals parameter is required")
    end
    globals = g

    -- Initialize sub-modules
    Export_Settings.initModule(g)
    Export_Engine.initModule(g)
    Export_Placement.initModule(g)
    Export_UI.initModule(g)

    -- Wire dependencies
    Export_Engine.setDependencies(Export_Settings, Export_Placement)
    Export_Placement.setDependencies(Export_Settings)
    Export_UI.setDependencies(Export_Settings, Export_Engine)
end

-- Re-export main functions
Export.openModal = function()
    return Export_UI.openModal()
end

Export.renderModal = function()
    return Export_UI.renderModal()
end

Export.performExport = function()
    return Export_Engine.performExport()
end

Export.resetSettings = function()
    return Export_Settings.resetSettings()
end

-- Provide access to sub-modules for advanced usage
function Export.getSubModules()
    return {
        Settings = Export_Settings,
        Engine = Export_Engine,
        Placement = Export_Placement,
        UI = Export_UI
    }
end

return Export
