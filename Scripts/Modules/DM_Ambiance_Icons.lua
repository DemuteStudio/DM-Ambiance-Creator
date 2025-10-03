--[[
@version 1.3
@noindex
--]]

local Icons = {}
local globals = {}

-- Initialize the module with global variables from the main script
function Icons.initModule(g)
    globals = g
    Icons.loadIcons()
end

-- Helper function to get the icon paths
local function getIconPaths()
    -- Get the OS path separator
    local separator = package.config:sub(1,1)
    
    -- Get the current script path
    local info = debug.getinfo(1, "S")
    local script_path = info.source:match("@(.*)")
    
    
    if script_path then
        -- Replace forward slashes with backslashes on Windows
        if separator == "\\" then
            script_path = script_path:gsub("/", "\\")
        end
        
        -- Find the position of "Modules" in the path
        local modules_pos = script_path:find(separator .. "Modules" .. separator)
        if not modules_pos then
            modules_pos = script_path:find(separator .. "modules" .. separator)  -- Try lowercase
        end
        
        if modules_pos then
            -- Get everything before "Modules"
            local scripts_dir = script_path:sub(1, modules_pos - 1)
            
            
            -- Build paths to icons
            return {
                delete = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_delete_garbage_icon.png",
                regen = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_refresh_reload_icon.png",
                upload = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_save_icon.png",
                download = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_download_import_save_down_storage_icon.png",
                settings = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_settings_icon.png",
                folder = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_folder_icon.png",
                conflict = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_conflict_resolution_icon.png",
                add = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_+_add_increase_icon.png",
                link = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_link_icon.png",
                unlink = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_unlink_icon.png",
                mirror = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_arrow_left_right_icon.png",
                arrow_left = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_left_arrow_icon.png",
                arrow_right = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_right_arrow_icon.png",
                arrow_both = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_left_right_arrow_icon.png",
                undo = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_undo_icon.png",
                redo = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_redo_icon.png",
                history = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_undo_history_icon.png"
            }
        end
    end
    
    -- Fallback: return empty paths if we can't determine the location
    return {
        delete = "",
        regen = "",
        upload = "",
        download = "",
        settings = "",
        folder = "",
        conflict = "",
        add = "",
        link = "",
        unlink = "",
        mirror = "",
        arrow_left = "",
        arrow_right = "",
        arrow_both = "",
        undo = "",
        redo = "",
        history = ""
    }
end

-- Store loaded icon textures
local iconTextures = {}

-- Load icons and create textures
function Icons.loadIcons()
    if not globals.imgui or not globals.ctx then
        return false
    end
    
    local iconPaths = getIconPaths()
    
    
    -- Check if files exist using Lua's io.open
    local function fileExists(path)
        local file = io.open(path, "r")
        if file then
            file:close()
            return true
        end
        return false
    end
    
    -- Try to load delete icon from file
    if fileExists(iconPaths.delete) then
        local success, result = pcall(function()
            -- Use Attach to keep the image in memory
            local img = globals.imgui.CreateImage(iconPaths.delete)
            if img then
                globals.imgui.Attach(globals.ctx, img)
            end
            return img
        end)
        
        if success and result then
            iconTextures.delete = result
        else
            iconTextures.delete = nil
        end
    else
        iconTextures.delete = nil
    end
    
    -- Try to load regenerate icon from file
    if fileExists(iconPaths.regen) then
        local success, result = pcall(function()
            -- Use Attach to keep the image in memory
            local img = globals.imgui.CreateImage(iconPaths.regen)
            if img then
                globals.imgui.Attach(globals.ctx, img)
            end
            return img
        end)
        
        if success and result then
            iconTextures.regen = result
        else
            iconTextures.regen = nil
        end
    else
        iconTextures.regen = nil
    end
    
    -- Try to load upload icon from file
    if fileExists(iconPaths.upload) then
        local success, result = pcall(function()
            local img = globals.imgui.CreateImage(iconPaths.upload)
            if img then
                globals.imgui.Attach(globals.ctx, img)
            end
            return img
        end)
        
        if success and result then
            iconTextures.upload = result
        else
            iconTextures.upload = nil
        end
    else
        iconTextures.upload = nil
    end
    
    -- Try to load download icon from file
    if fileExists(iconPaths.download) then
        local success, result = pcall(function()
            local img = globals.imgui.CreateImage(iconPaths.download)
            if img then
                globals.imgui.Attach(globals.ctx, img)
            end
            return img
        end)
        
        if success and result then
            iconTextures.download = result
        else
            iconTextures.download = nil
        end
    else
        iconTextures.download = nil
    end
    
    -- Try to load settings icon from file
    if fileExists(iconPaths.settings) then
        local success, result = pcall(function()
            local img = globals.imgui.CreateImage(iconPaths.settings)
            if img then
                globals.imgui.Attach(globals.ctx, img)
            end
            return img
        end)
        
        if success and result then
            iconTextures.settings = result
        else
            iconTextures.settings = nil
        end
    else
        iconTextures.settings = nil
    end
    
    -- Try to load folder icon from file
    if fileExists(iconPaths.folder) then
        local success, result = pcall(function()
            local img = globals.imgui.CreateImage(iconPaths.folder)
            if img then
                globals.imgui.Attach(globals.ctx, img)
            end
            return img
        end)
        
        if success and result then
            iconTextures.folder = result
        else
            iconTextures.folder = nil
        end
    else
        iconTextures.folder = nil
    end
    
    -- Try to load conflict icon from file
    if fileExists(iconPaths.conflict) then
        local success, result = pcall(function()
            local img = globals.imgui.CreateImage(iconPaths.conflict)
            if img then
                globals.imgui.Attach(globals.ctx, img)
            end
            return img
        end)
        
        if success and result then
            iconTextures.conflict = result
        else
            iconTextures.conflict = nil
        end
    else
        iconTextures.conflict = nil
    end
    
    -- Try to load add icon from file
    if fileExists(iconPaths.add) then
        local success, result = pcall(function()
            local img = globals.imgui.CreateImage(iconPaths.add)
            if img then
                globals.imgui.Attach(globals.ctx, img)
            end
            return img
        end)
        
        if success and result then
            iconTextures.add = result
        else
            iconTextures.add = nil
        end
    else
        iconTextures.add = nil
    end
    
    -- Try to load link icon from file
    if fileExists(iconPaths.link) then
        local success, result = pcall(function()
            local img = globals.imgui.CreateImage(iconPaths.link)
            if img then
                globals.imgui.Attach(globals.ctx, img)
            end
            return img
        end)
        
        if success and result then
            iconTextures.link = result
        else
            iconTextures.link = nil
        end
    else
        iconTextures.link = nil
    end
    
    -- Try to load unlink icon from file
    if fileExists(iconPaths.unlink) then
        local success, result = pcall(function()
            local img = globals.imgui.CreateImage(iconPaths.unlink)
            if img then
                globals.imgui.Attach(globals.ctx, img)
            end
            return img
        end)
        
        if success and result then
            iconTextures.unlink = result
        else
            iconTextures.unlink = nil
        end
    else
        iconTextures.unlink = nil
    end
    
    -- Try to load mirror icon from file
    if fileExists(iconPaths.mirror) then
        local success, result = pcall(function()
            local img = globals.imgui.CreateImage(iconPaths.mirror)
            if img then
                globals.imgui.Attach(globals.ctx, img)
            end
            return img
        end)

        if success and result then
            iconTextures.mirror = result
        else
            iconTextures.mirror = nil
        end
    else
        iconTextures.mirror = nil
    end

    -- Try to load arrow_left icon from file
    if fileExists(iconPaths.arrow_left) then
        local success, result = pcall(function()
            local img = globals.imgui.CreateImage(iconPaths.arrow_left)
            if img then
                globals.imgui.Attach(globals.ctx, img)
            end
            return img
        end)

        if success and result then
            iconTextures.arrow_left = result
        else
            iconTextures.arrow_left = nil
        end
    else
        iconTextures.arrow_left = nil
    end

    -- Try to load arrow_right icon from file
    if fileExists(iconPaths.arrow_right) then
        local success, result = pcall(function()
            local img = globals.imgui.CreateImage(iconPaths.arrow_right)
            if img then
                globals.imgui.Attach(globals.ctx, img)
            end
            return img
        end)

        if success and result then
            iconTextures.arrow_right = result
        else
            iconTextures.arrow_right = nil
        end
    else
        iconTextures.arrow_right = nil
    end

    -- Try to load arrow_both icon from file
    if fileExists(iconPaths.arrow_both) then
        local success, result = pcall(function()
            local img = globals.imgui.CreateImage(iconPaths.arrow_both)
            if img then
                globals.imgui.Attach(globals.ctx, img)
            end
            return img
        end)

        if success and result then
            iconTextures.arrow_both = result
        else
            iconTextures.arrow_both = nil
        end
    else
        iconTextures.arrow_both = nil
    end

    -- Try to load undo icon from file
    if fileExists(iconPaths.undo) then
        local success, result = pcall(function()
            local img = globals.imgui.CreateImage(iconPaths.undo)
            if img then
                globals.imgui.Attach(globals.ctx, img)
            end
            return img
        end)

        if success and result then
            iconTextures.undo = result
        else
            iconTextures.undo = nil
        end
    else
        iconTextures.undo = nil
    end

    -- Try to load redo icon from file
    if fileExists(iconPaths.redo) then
        local success, result = pcall(function()
            local img = globals.imgui.CreateImage(iconPaths.redo)
            if img then
                globals.imgui.Attach(globals.ctx, img)
            end
            return img
        end)

        if success and result then
            iconTextures.redo = result
        else
            iconTextures.redo = nil
        end
    else
        iconTextures.redo = nil
    end

    -- Try to load history icon from file
    if fileExists(iconPaths.history) then
        local success, result = pcall(function()
            local img = globals.imgui.CreateImage(iconPaths.history)
            if img then
                globals.imgui.Attach(globals.ctx, img)
            end
            return img
        end)

        if success and result then
            iconTextures.history = result
        else
            iconTextures.history = nil
        end
    else
        iconTextures.history = nil
    end

    return iconTextures.delete ~= nil or iconTextures.regen ~= nil or iconTextures.upload ~= nil or iconTextures.download ~= nil or iconTextures.settings ~= nil or iconTextures.folder ~= nil or iconTextures.conflict ~= nil or iconTextures.add ~= nil or iconTextures.link ~= nil or iconTextures.unlink ~= nil or iconTextures.mirror ~= nil or iconTextures.undo ~= nil or iconTextures.redo ~= nil or iconTextures.history ~= nil
end

-- Get icon size (48x48 based on actual icon files)
function Icons.getIconSize()
    -- The actual icons are 48x48 pixels
    -- We can scale them down if needed
    return 14, 14  -- Display at 14x14 for compact size
end

-- Helper function to adjust the alpha channel of a color
local function adjustAlpha(color, alphaMultiplier)
    -- Extract current alpha (last 8 bits)
    local currentAlpha = color & 0xFF
    -- Calculate new alpha
    local newAlpha = math.floor((currentAlpha / 255) * alphaMultiplier * 255)
    -- Return color with new alpha
    return (color & 0xFFFFFF00) | newAlpha
end

-- Helper function to create an icon button with tint color and visual feedback
local function createTintedIconButton(ctx, texture, buttonId, tooltip)
    local width, height = Icons.getIconSize()

    -- Initialize icon button states table if needed
    if not globals.iconButtonStates then
        globals.iconButtonStates = {}
    end

    -- Get the previous state for this button
    local stateKey = buttonId
    local previousState = globals.iconButtonStates[stateKey] or "normal"

    -- Get base colors
    local iconColor = globals.Settings.getSetting("iconColor")
    local backgroundColor = globals.Settings.getSetting("backgroundColor")

    -- Calculate tint color based on previous state
    local tintColor = iconColor
    if previousState == "active" then
        -- Active: darken and reduce opacity
        tintColor = globals.Utils.brightenColor(iconColor, -0.2)
        tintColor = adjustAlpha(tintColor, 0.8)
    elseif previousState == "hovered" then
        -- Hover: brighten
        tintColor = globals.Utils.brightenColor(iconColor, 0.3)
    end

    -- Override button colors to match background (no visual change on button itself)
    globals.imgui.PushStyleColor(ctx, globals.imgui.Col_Button, backgroundColor)
    globals.imgui.PushStyleColor(ctx, globals.imgui.Col_ButtonHovered, backgroundColor)
    globals.imgui.PushStyleColor(ctx, globals.imgui.Col_ButtonActive, backgroundColor)

    -- Render the button with calculated tint
    local result = globals.imgui.ImageButton(ctx, buttonId, texture, width, height, 0, 0, 1, 1, 0, tintColor)

    globals.imgui.PopStyleColor(ctx, 3)

    -- Update state for next frame
    if globals.imgui.IsItemActive(ctx) then
        globals.iconButtonStates[stateKey] = "active"
    elseif globals.imgui.IsItemHovered(ctx) then
        globals.iconButtonStates[stateKey] = "hovered"
    else
        globals.iconButtonStates[stateKey] = "normal"
    end

    -- Show tooltip
    if globals.imgui.IsItemHovered(ctx) then
        globals.imgui.SetTooltip(ctx, tooltip)
    end

    return result
end

-- Create a delete icon button
function Icons.createDeleteButton(ctx, id, tooltip)
    if not iconTextures.delete then
        -- Fallback to text button if icon failed to load
        local result = globals.imgui.Button(ctx, "Del##" .. id)
        if globals.imgui.IsItemHovered(ctx) then
            globals.imgui.SetTooltip(ctx, tooltip or "Delete")
        end
        return result
    end

    local buttonId = "##ImgDel_" .. id
    return createTintedIconButton(ctx, iconTextures.delete, buttonId, tooltip or "Delete")
end

-- Create a regenerate icon button
function Icons.createRegenButton(ctx, id, tooltip)
    if not iconTextures.regen then
        -- Fallback to text button if icon failed to load
        local result = globals.imgui.Button(ctx, "Regen##" .. id)
        if globals.imgui.IsItemHovered(ctx) then
            globals.imgui.SetTooltip(ctx, tooltip or "Regenerate")
        end
        return result
    end

    local buttonId = "##ImgReg_" .. id
    return createTintedIconButton(ctx, iconTextures.regen, buttonId, tooltip or "Regenerate")
end

-- Create an upload icon button (for save)
function Icons.createUploadButton(ctx, id, tooltip)
    if not iconTextures.upload then
        -- Fallback to text button if icon failed to load
        local result = globals.imgui.Button(ctx, "Save##" .. id)
        if globals.imgui.IsItemHovered(ctx) then
            globals.imgui.SetTooltip(ctx, tooltip or "Save")
        end
        return result
    end

    local buttonId = "##ImgSave_" .. id
    return createTintedIconButton(ctx, iconTextures.upload, buttonId, tooltip or "Save")
end

-- Create a download icon button (for load)
function Icons.createDownloadButton(ctx, id, tooltip)
    if not iconTextures.download then
        -- Fallback to text button if icon failed to load
        local result = globals.imgui.Button(ctx, "Load##" .. id)
        if globals.imgui.IsItemHovered(ctx) then
            globals.imgui.SetTooltip(ctx, tooltip or "Load")
        end
        return result
    end

    local buttonId = "##ImgLoad_" .. id
    return createTintedIconButton(ctx, iconTextures.download, buttonId, tooltip or "Load")
end

-- Create a settings icon button
function Icons.createSettingsButton(ctx, id, tooltip)
    if not iconTextures.settings then
        -- Fallback to text button if icon failed to load
        local result = globals.imgui.Button(ctx, "Settings##" .. id)
        if globals.imgui.IsItemHovered(ctx) then
            globals.imgui.SetTooltip(ctx, tooltip or "Settings")
        end
        return result
    end

    local buttonId = "##ImgSettings_" .. id
    return createTintedIconButton(ctx, iconTextures.settings, buttonId, tooltip or "Settings")
end

-- Create a folder icon button
function Icons.createFolderButton(ctx, id, tooltip)
    if not iconTextures.folder then
        -- Fallback to text button if icon failed to load
        local result = globals.imgui.Button(ctx, "Open##" .. id)
        if globals.imgui.IsItemHovered(ctx) then
            globals.imgui.SetTooltip(ctx, tooltip or "Open folder")
        end
        return result
    end

    local buttonId = "##ImgFolder_" .. id
    return createTintedIconButton(ctx, iconTextures.folder, buttonId, tooltip or "Open folder")
end

-- Create a conflict resolution icon button
function Icons.createConflictButton(ctx, id, tooltip)
    if not iconTextures.conflict then
        -- Fallback to text button if icon failed to load
        local result = globals.imgui.Button(ctx, "Conflicts##" .. id)
        if globals.imgui.IsItemHovered(ctx) then
            globals.imgui.SetTooltip(ctx, tooltip or "Channel Routing Conflicts")
        end
        return result
    end

    local buttonId = "##ImgConflict_" .. id
    return createTintedIconButton(ctx, iconTextures.conflict, buttonId, tooltip or "Channel Routing Conflicts")
end

-- Create a delete button with text fallback
function Icons.createDeleteButtonWithFallback(ctx, id, fallbackText, tooltip)
    if iconTextures.delete then
        return Icons.createDeleteButton(ctx, id, tooltip)
    else
        local result = globals.imgui.Button(ctx, fallbackText .. "##" .. id)
        if globals.imgui.IsItemHovered(ctx) then
            globals.imgui.SetTooltip(ctx, tooltip or "Delete")
        end
        return result
    end
end

-- Get raw icon texture (for advanced usage)
function Icons.getDeleteIcon()
    return iconTextures.delete
end

function Icons.getRegenIcon()
    return iconTextures.regen
end

function Icons.getUploadIcon()
    return iconTextures.upload
end

function Icons.getDownloadIcon()
    return iconTextures.download
end

function Icons.getSettingsIcon()
    return iconTextures.settings
end

function Icons.getFolderIcon()
    return iconTextures.folder
end

function Icons.getConflictIcon()
    return iconTextures.conflict
end

-- Create an add icon button
function Icons.createAddButton(ctx, id, tooltip)
    if not iconTextures.add then
        -- Fallback to text button if icon failed to load
        local result = globals.imgui.Button(ctx, "+##" .. id)
        if globals.imgui.IsItemHovered(ctx) then
            globals.imgui.SetTooltip(ctx, tooltip or "Add")
        end
        return result
    end

    local buttonId = "##ImgAdd_" .. id
    return createTintedIconButton(ctx, iconTextures.add, buttonId, tooltip or "Add")
end

-- Check if icons are loaded successfully
function Icons.isLoaded()
    return iconTextures.delete ~= nil and iconTextures.regen ~= nil
end

-- Check if all icons are loaded successfully
function Icons.areAllLoaded()
    return iconTextures.delete ~= nil and iconTextures.regen ~= nil and
           iconTextures.upload ~= nil and iconTextures.download ~= nil and
           iconTextures.settings ~= nil and iconTextures.folder ~= nil and
           iconTextures.conflict ~= nil and iconTextures.add ~= nil and
           iconTextures.link ~= nil and iconTextures.unlink ~= nil and
           iconTextures.mirror ~= nil and iconTextures.undo ~= nil and
           iconTextures.redo ~= nil and iconTextures.history ~= nil
end

-- Create a link/unlink/mirror cycling button that changes mode on click
function Icons.createLinkModeButton(ctx, id, currentMode, tooltip)
    local modeIcons = {
        ["unlink"] = iconTextures.unlink,
        ["link"] = iconTextures.link,
        ["mirror"] = iconTextures.mirror
    }

    local modeTexts = {
        ["unlink"] = "UL",
        ["link"] = "LK",
        ["mirror"] = "MR"
    }

    local currentIcon = modeIcons[currentMode]

    if not currentIcon then
        -- Fallback to text button if icon failed to load
        local text = modeTexts[currentMode] or "UL"
        local result = globals.imgui.Button(ctx, text .. "##" .. id)
        if globals.imgui.IsItemHovered(ctx) then
            globals.imgui.SetTooltip(ctx, tooltip or ("Mode: " .. currentMode))
        end
        return result
    end

    local buttonId = "##ImgLink_" .. id
    return createTintedIconButton(ctx, currentIcon, buttonId, tooltip or ("Mode: " .. currentMode))
end

-- Get raw link mode icon textures (for advanced usage)
function Icons.getLinkIcon()
    return iconTextures.link
end

function Icons.getUnlinkIcon()
    return iconTextures.unlink
end

function Icons.getMirrorIcon()
    return iconTextures.mirror
end

-- Create an undo icon button
function Icons.createUndoButton(ctx, id, tooltip)
    if not iconTextures.undo then
        -- Fallback to text button if icon failed to load
        local result = globals.imgui.Button(ctx, "Undo##" .. id)
        if globals.imgui.IsItemHovered(ctx) then
            globals.imgui.SetTooltip(ctx, tooltip or "Undo")
        end
        return result
    end

    local buttonId = "##ImgUndo_" .. id
    return createTintedIconButton(ctx, iconTextures.undo, buttonId, tooltip or "Undo")
end

-- Create a redo icon button
function Icons.createRedoButton(ctx, id, tooltip)
    if not iconTextures.redo then
        -- Fallback to text button if icon failed to load
        local result = globals.imgui.Button(ctx, "Redo##" .. id)
        if globals.imgui.IsItemHovered(ctx) then
            globals.imgui.SetTooltip(ctx, tooltip or "Redo")
        end
        return result
    end

    local buttonId = "##ImgRedo_" .. id
    return createTintedIconButton(ctx, iconTextures.redo, buttonId, tooltip or "Redo")
end

-- Create a history icon button
function Icons.createHistoryButton(ctx, id, tooltip)
    if not iconTextures.history then
        -- Fallback to text button if icon failed to load
        local result = globals.imgui.Button(ctx, "History##" .. id)
        if globals.imgui.IsItemHovered(ctx) then
            globals.imgui.SetTooltip(ctx, tooltip or "History")
        end
        return result
    end

    local buttonId = "##ImgHistory_" .. id
    return createTintedIconButton(ctx, iconTextures.history, buttonId, tooltip or "History")
end

-- Get raw undo/redo/history icon textures (for advanced usage)
function Icons.getUndoIcon()
    return iconTextures.undo
end

function Icons.getRedoIcon()
    return iconTextures.redo
end

function Icons.getHistoryIcon()
    return iconTextures.history
end

-- Create a variation direction button (cycles through left, both, right)
-- @param ctx ImGui context
-- @param id Unique button ID
-- @param direction Current direction (0=negative/left, 1=bipolar/both, 2=positive/right)
-- @param tooltip Tooltip text
-- @return clicked (boolean), newDirection (0, 1, or 2)
function Icons.createVariationDirectionButton(ctx, id, direction, tooltip)
    -- Initialize direction if nil (backward compatibility)
    if direction == nil then
        local Constants = require("DM_Ambiance_Constants")
        direction = Constants.VARIATION_DIRECTIONS.BIPOLAR
    end

    local textures = {
        [0] = iconTextures.arrow_left,
        [1] = iconTextures.arrow_both,
        [2] = iconTextures.arrow_right
    }

    local fallbackSymbols = {"←", "↔", "→"}
    local tooltips = {
        "Negative only: variation reduces value",
        "Bipolar: variation can increase or decrease",
        "Positive only: variation increases value"
    }

    -- Use provided tooltip or default
    local finalTooltip = tooltip or tooltips[direction + 1]

    -- If icon exists, use it
    if textures[direction] then
        local buttonId = "##VarDir_" .. id
        local clicked = createTintedIconButton(ctx, textures[direction], buttonId, finalTooltip)

        if clicked then
            local newDirection = (direction + 1) % 3
            return true, newDirection
        end
        return false, direction
    else
        -- Fallback to text button
        local buttonLabel = fallbackSymbols[direction + 1] .. "##" .. id
        local clicked = globals.imgui.Button(ctx, buttonLabel, 24, 0)

        if globals.imgui.IsItemHovered(ctx) then
            globals.imgui.SetTooltip(ctx, finalTooltip)
        end

        if clicked then
            local newDirection = (direction + 1) % 3
            return true, newDirection
        end
        return false, direction
    end
end

return Icons