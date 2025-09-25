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
                mirror = scripts_dir .. separator .. "Icons" .. separator .. "DM_Ambiance_arrow_left_right_icon.png"
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
        mirror = ""
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
    
    return iconTextures.delete ~= nil or iconTextures.regen ~= nil or iconTextures.upload ~= nil or iconTextures.download ~= nil or iconTextures.settings ~= nil or iconTextures.folder ~= nil or iconTextures.conflict ~= nil or iconTextures.add ~= nil or iconTextures.link ~= nil or iconTextures.unlink ~= nil or iconTextures.mirror ~= nil
end

-- Get icon size (48x48 based on actual icon files)
function Icons.getIconSize()
    -- The actual icons are 48x48 pixels
    -- We can scale them down if needed
    return 16, 16  -- Display at 16x16 for compact size
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
    
    local width, height = Icons.getIconSize()
    
    
    -- Use ImageButton with proper parameters
    -- The ID should not have ## prefix - that's for regular buttons
    local buttonId = "##ImgDel_" .. id  -- ## prefix hides the label
    local result = globals.imgui.ImageButton(ctx, buttonId, iconTextures.delete, width, height)
    
    if globals.imgui.IsItemHovered(ctx) then
        globals.imgui.SetTooltip(ctx, tooltip or "Delete")
    end
    
    return result
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
    
    local width, height = Icons.getIconSize()
    
    
    -- Use ImageButton with proper parameters
    -- The ID should not have ## prefix - that's for regular buttons
    local buttonId = "##ImgReg_" .. id  -- ## prefix hides the label
    local result = globals.imgui.ImageButton(ctx, buttonId, iconTextures.regen, width, height)
    
    if globals.imgui.IsItemHovered(ctx) then
        globals.imgui.SetTooltip(ctx, tooltip or "Regenerate")
    end
    
    return result
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
    
    local width, height = Icons.getIconSize()
    
    local buttonId = "##ImgSave_" .. id
    local result = globals.imgui.ImageButton(ctx, buttonId, iconTextures.upload, width, height)
    
    if globals.imgui.IsItemHovered(ctx) then
        globals.imgui.SetTooltip(ctx, tooltip or "Save")
    end
    
    return result
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
    
    local width, height = Icons.getIconSize()
    
    local buttonId = "##ImgLoad_" .. id
    local result = globals.imgui.ImageButton(ctx, buttonId, iconTextures.download, width, height)
    
    if globals.imgui.IsItemHovered(ctx) then
        globals.imgui.SetTooltip(ctx, tooltip or "Load")
    end
    
    return result
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
    
    local width, height = Icons.getIconSize()
    
    local buttonId = "##ImgSettings_" .. id
    local result = globals.imgui.ImageButton(ctx, buttonId, iconTextures.settings, width, height)
    
    if globals.imgui.IsItemHovered(ctx) then
        globals.imgui.SetTooltip(ctx, tooltip or "Settings")
    end
    
    return result
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
    
    local width, height = Icons.getIconSize()
    
    local buttonId = "##ImgFolder_" .. id
    local result = globals.imgui.ImageButton(ctx, buttonId, iconTextures.folder, width, height)
    
    if globals.imgui.IsItemHovered(ctx) then
        globals.imgui.SetTooltip(ctx, tooltip or "Open folder")
    end
    
    return result
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
    
    local width, height = Icons.getIconSize()
    
    local buttonId = "##ImgConflict_" .. id
    local result = globals.imgui.ImageButton(ctx, buttonId, iconTextures.conflict, width, height)
    
    if globals.imgui.IsItemHovered(ctx) then
        globals.imgui.SetTooltip(ctx, tooltip or "Channel Routing Conflicts")
    end
    
    return result
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
    
    local width, height = Icons.getIconSize()
    
    -- Use ImageButton with proper parameters (same format as other buttons)
    local buttonId = "##ImgAdd_" .. id  -- ## prefix hides the label
    local result = globals.imgui.ImageButton(ctx, buttonId, iconTextures.add, width, height)
    
    if globals.imgui.IsItemHovered(ctx) then
        globals.imgui.SetTooltip(ctx, tooltip or "Add")
    end
    
    return result
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
           iconTextures.mirror ~= nil
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
    
    local width, height = Icons.getIconSize()
    
    local buttonId = "##ImgLink_" .. id
    local result = globals.imgui.ImageButton(ctx, buttonId, currentIcon, width, height)
    
    if globals.imgui.IsItemHovered(ctx) then
        globals.imgui.SetTooltip(ctx, tooltip or ("Mode: " .. currentMode))
    end
    
    return result
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

return Icons