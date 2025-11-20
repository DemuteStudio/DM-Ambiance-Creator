--[[
@version 1.3
@noindex
--]]

local Settings = {}

local globals = {}

-- Temporary variables for sliders (avoids constant saves)
-- Variables used for sliders to avoid constant saving

local tempSettings = {}

local originalSettings = {}

-- Default settings for the module

local defaultSettings = {
    mediaItemDirectory = "", -- Path to the media directory
    autoImportMedia = true, -- Automatically copy media files
    buttonColor = 0x15856DFF, -- Default blue color for buttons
    backgroundColor = 0x2E2E2EFF, -- Dark gray background
    textColor = 0xD5D5D5FF, -- White text
    waveformColor = 0x00CCA0FF, -- Default blue color
    iconColor = 0xD5D5D5FF, -- Same as text color by default
    uiRounding = 2.0, -- Default rounding for UI elements
    itemSpacing = 8, -- Default item spacing
    crossfadeMargin = 0.2, -- Default crossfade margin in seconds
    waveformAutoPlayOnSelect = true, -- Auto-play when selecting items in waveform
    leftPanelWidth = nil, -- Width of the left panel (nil = use default percentage)
    uiScale = 1.0, -- UI scale factor (1.0 = 100%)
    showKnobIndicator = true, -- Show indicator line on knobs
    generateFolderTracks = true, -- Generate folder tracks in REAPER for groups
}

-- Initialize the module with global references and load settings

function Settings.initModule(g)
    globals = g
    -- Load settings from file or defaults
    Settings.loadSettings()
    -- Check if the media directory is configured at startup
    if Settings.getSetting("mediaItemDirectory") == "" then
        -- If no directory is set and the script is running normally (not as a module)
        if select(2, reaper.get_action_context()) == debug.getinfo(1, 'S').source:sub(2) then
            reaper.defer(function()
                globals.showSettingsWindow = true
            end)
        end
    end
end

-- Returns the base path for settings (same level as the Presets folder)

function Settings.getSettingsBasePath()
    local basePath = globals.Presets.getPresetsPath("Global"):match("(.+)Global[/\\]")
    return basePath or ""
end

-- Checks reliably if a directory exists

function Settings.directoryExists(path)
    if not path or path == "" then return false end
    -- Reliable method: try to create/open a temporary file in the directory
    local testFile = path .. "/.test_access"
    local file = io.open(testFile, "w")
    if file then
        file:close()
        os.remove(testFile)
        return true
    end
    return false
end

-- Load settings from the configuration file

function Settings.loadSettings()
    local settingsFile = Settings.getSettingsBasePath() .. "settings.cfg"
    local file = io.open(settingsFile, "r")
    if file then
        local settings = {}
        for line in file:lines() do
            local key, value = line:match("([^=]+)=(.+)")
            if key and value then
                -- Convert boolean values from string to boolean (robust conversion)
                if value == "true" or value == "1" then
                    value = true
                elseif value == "false" or value == "0" then
                    value = false
                elseif tonumber(value) then
                    -- Convert numeric strings to numbers
                    value = tonumber(value)
                end
                settings[key] = value
            end
        end
        file:close()
        -- Merge loaded settings with defaults
        globals.settings = {}
        for k, v in pairs(defaultSettings) do
            if settings[k] ~= nil then
                globals.settings[k] = settings[k]
            else
                globals.settings[k] = v
            end
        end
        -- Also load settings that are in the file but not in defaults
        for k, v in pairs(settings) do
            if globals.settings[k] == nil then
                globals.settings[k] = v
            end
        end
    else
        globals.settings = defaultSettings
    end
end

-- Save the current settings to the configuration file

function Settings.saveSettings()
    local settingsFile = Settings.getSettingsBasePath() .. "settings.cfg"
    local file = io.open(settingsFile, "w")
    if file then
        for k, v in pairs(globals.settings) do
            file:write(k .. "=" .. tostring(v) .. "\n")
        end
        file:close()
        return true
    end
    return false
end

-- Accessor to get a specific setting value

function Settings.getSetting(key)
    return globals.settings[key]
end

-- Mutator to set a specific setting value (NO immediate save)
-- Mutator to set a specific setting value (WITHOUT immediate save)

function Settings.setSetting(key, value)
    globals.settings[key] = value
end

-- Initialise temporary variables if necessary
-- Initialize temporary variables if necessary

local function initTempSettings()
    if not tempSettings.initialized then
        -- Save the original values (use current in-memory settings, no reload)
        originalSettings.uiRounding = globals.settings.uiRounding
        originalSettings.itemSpacing = globals.settings.itemSpacing
        originalSettings.crossfadeMargin = globals.settings.crossfadeMargin
        originalSettings.waveformAutoPlayOnSelect = globals.settings.waveformAutoPlayOnSelect
        originalSettings.buttonColor = globals.settings.buttonColor
        originalSettings.backgroundColor = globals.settings.backgroundColor
        originalSettings.textColor = globals.settings.textColor
        originalSettings.waveformColor = globals.settings.waveformColor
        originalSettings.iconColor = globals.settings.iconColor
        originalSettings.uiScale = globals.settings.uiScale
        originalSettings.showKnobIndicator = globals.settings.showKnobIndicator
        -- Initialize temporary variables
        tempSettings.uiRounding = globals.settings.uiRounding
        tempSettings.itemSpacing = globals.settings.itemSpacing
        tempSettings.crossfadeMargin = globals.settings.crossfadeMargin
        tempSettings.waveformAutoPlayOnSelect = globals.settings.waveformAutoPlayOnSelect
        tempSettings.buttonColor = globals.settings.buttonColor
        tempSettings.backgroundColor = globals.settings.backgroundColor
        tempSettings.textColor = globals.settings.textColor
        tempSettings.waveformColor = globals.settings.waveformColor
        tempSettings.iconColor = globals.settings.iconColor
        tempSettings.uiScale = globals.settings.uiScale
        tempSettings.showKnobIndicator = globals.settings.showKnobIndicator
        tempSettings.initialized = true
    end
end

-- Resets temporary variables

local function resetTempSettings()
    tempSettings = {}
    originalSettings = {}
end

-- Restores original values (for Cancel)

local function restoreOriginalSettings()
    globals.settings.uiRounding = originalSettings.uiRounding
    globals.settings.itemSpacing = originalSettings.itemSpacing
    globals.settings.crossfadeMargin = originalSettings.crossfadeMargin
    globals.settings.waveformAutoPlayOnSelect = originalSettings.waveformAutoPlayOnSelect
    globals.settings.buttonColor = originalSettings.buttonColor
    globals.settings.backgroundColor = originalSettings.backgroundColor
    globals.settings.textColor = originalSettings.textColor
    globals.settings.waveformColor = originalSettings.waveformColor
    globals.settings.iconColor = originalSettings.iconColor
    globals.settings.uiScale = originalSettings.uiScale
    globals.settings.showKnobIndicator = originalSettings.showKnobIndicator
end

-- Applies all temporary changes to the real settings

local function applyTempSettings()
    Settings.setSetting("uiRounding", tempSettings.uiRounding)
    Settings.setSetting("itemSpacing", tempSettings.itemSpacing)
    Settings.setSetting("crossfadeMargin", tempSettings.crossfadeMargin)
    Settings.setSetting("waveformAutoPlayOnSelect", tempSettings.waveformAutoPlayOnSelect)
    Settings.setSetting("buttonColor", tempSettings.buttonColor)
    Settings.setSetting("backgroundColor", tempSettings.backgroundColor)
    Settings.setSetting("textColor", tempSettings.textColor)
    Settings.setSetting("waveformColor", tempSettings.waveformColor)
    Settings.setSetting("iconColor", tempSettings.iconColor)
    Settings.setSetting("uiScale", tempSettings.uiScale)
    Settings.setSetting("showKnobIndicator", tempSettings.showKnobIndicator)
    Settings.saveSettings()
end

-- Main settings window for the user interface
function Settings.showSettingsWindow(open)
    local ctx = globals.ctx
    local imgui = globals.imgui

    -- Initialize temporary variables
    initTempSettings()

    local windowFlags = imgui.WindowFlags_NoResize | imgui.WindowFlags_AlwaysAutoResize
    local visible, openResult = imgui.Begin(ctx, 'Ambiance Creator Settings', open, windowFlags)

    -- Track if buttons were pressed
    local buttonPressed = false
    
    -- CRITICAL: Only render content and call End() if Begin() returned true
    if visible then
        imgui.TextColored(ctx, 0xFFAA00FF, "Media Management Settings")
        imgui.Separator(ctx)
        
        -- Media directory section
        imgui.Text(ctx, "Media Item Directory")
        local mediaDir = Settings.getSetting("mediaItemDirectory")
        if mediaDir == "" then
            mediaDir = "No directory selected"
            imgui.TextColored(ctx, 0xFF0000FF, "Warning: No media directory configured")
        end
        
        -- Show current directory path (read-only)
        imgui.PushItemWidth(ctx, 350)
        imgui.InputText(ctx, "##MediaDir", mediaDir, imgui.InputTextFlags_ReadOnly)
        
        -- Button to change the directory
        imgui.SameLine(ctx)
        if imgui.Button(ctx, "Browse") then
            Settings.setupMediaDirectory()
        end
        
        -- Option to automatically import media files
        local rv, autoImport = imgui.Checkbox(ctx, "Automatically import media files when saving presets",
            Settings.getSetting("autoImportMedia"))
        if rv then
            Settings.setSetting("autoImportMedia", autoImport)
        end
        
        -- Tooltip explaining the auto-import option
        imgui.SameLine(globals.ctx)
        globals.Utils.HelpMarker("- Enabled: Automatically copies all media files referenced in your presets to the central media directory when saving. This ensures your presets remain functional even if original files are moved or deleted.\n\n"..
            "- Disabled: Presets will maintain references to the original file locations without creating copies, which saves disk space but makes presets dependent on the original file locations.")
        
        -- Button to open the media directory in the system file explorer
        if mediaDir ~= "No directory selected" then
            if imgui.Button(ctx, "Open Media Directory") then
                local OS = reaper.GetOS()
                if OS:match("^Win") then
                    reaper.ExecProcess('explorer "' .. mediaDir .. '"', -2)
                elseif OS:match("^macOS") or OS:match("^OSX") then
                    reaper.ExecProcess('open "' .. mediaDir .. '"', -2)
                else
                    reaper.ExecProcess('xdg-open "' .. mediaDir .. '"', -2)
                end
            end
        end

        imgui.Separator(ctx)
        imgui.TextColored(ctx, 0xFFAA00FF, "REAPER Track Generation")
        imgui.Separator(ctx)

        local rv, val = imgui.Checkbox(ctx, "Generate folder tracks in REAPER",
            Settings.getSetting("generateFolderTracks"))
        if rv then
            Settings.setSetting("generateFolderTracks", val)
            Settings.saveSettings()
        end

        imgui.SameLine(ctx)
        globals.Utils.HelpMarker("When enabled: Folders are created as track folders in REAPER.\n"..
            "When disabled: Folders are only used for UI organization.")

        imgui.Separator(ctx)

        -- Crossfade settings section
        Settings.showCrossfadeSettings()
        
        -- Appearance settings section
        Settings.showAppearanceSettings()

        -- Waveform settings section
        Settings.showWaveformSettings()

        -- Control buttons at the bottom
        if globals.UI.Button(ctx, "Save & Close", 120, 0) then
            applyTempSettings()
            resetTempSettings()
            openResult = false
            buttonPressed = true
        end
        imgui.SameLine(ctx)
        if globals.UI.Button(ctx, "Cancel", 120, 0) then
            restoreOriginalSettings()
            resetTempSettings()
            openResult = false
            buttonPressed = true
        end
    end

    -- CRITICAL: Always call End() after Begin(), regardless of visibility
    imgui.End(ctx)
    
    -- Handle window closed by X button (not by Save/Cancel buttons)
    if open and not openResult and not buttonPressed then
        -- Window was closed by X button, restore original settings and reset temp settings
        restoreOriginalSettings()
        resetTempSettings()
    end

    -- Handle the popup for configuring the media directory (separate from main window)
    Settings.handleSetupMediaDirectoryPopup()

    return openResult
end

-------
--- Media Directory
------- -- Opens a dialog to configure the media directory, using the most reliable method available

function Settings.setupMediaDirectory()
    local retval, dirPath
    -- Prefer JS_ReaScriptAPI if available (most reliable method)
    if reaper.JS_Dialog_BrowseForFolder then
        retval, dirPath = reaper.JS_Dialog_BrowseForFolder("Select the directory for media files", "")
        if retval and dirPath and dirPath ~= "" then
            -- Test directory access without attempting to create it
            if Settings.directoryExists(dirPath) then
                Settings.setSetting("mediaItemDirectory", dirPath)
                Settings.saveSettings() -- Immediate save for this critical parameter
                return true
            else
                reaper.ShowMessageBox("Cannot access this directory. Check permissions.", "Access Error", 0)
            end
        end
        return false
    end
    -- Alternative: Use SWS extension if available
    if reaper.BR_Win32_BrowseForDirectory then
        retval, dirPath = reaper.BR_Win32_BrowseForDirectory(reaper.GetResourcePath(), "Select the directory for media files")
        if retval and dirPath and dirPath ~= "" then
            if Settings.directoryExists(dirPath) then
                Settings.setSetting("mediaItemDirectory", dirPath)
                Settings.saveSettings() -- Immediate save for this critical parameter
                return true
            else
                reaper.ShowMessageBox("Cannot access this directory. Check permissions.", "Access Error", 0)
            end
        end
        return false
    end
    -- Fallback: Manual entry with GetUserInputs
    reaper.ShowMessageBox("Please install the JS_ReaScriptAPI extension via ReaPack for best experience.", "Recommended Extensions", 0)
    retval, dirPath = reaper.GetUserInputs("Select the directory for media files", 1, "Full path:,extrawidth=300", reaper.GetResourcePath() .. "/Scripts")
    if retval and dirPath and dirPath ~= "" then
        if Settings.directoryExists(dirPath) then
            Settings.setSetting("mediaItemDirectory", dirPath)
            Settings.saveSettings() -- Immediate save for this critical parameter
            return true
        else
            reaper.ShowMessageBox("The specified directory does not exist or is not accessible.", "Error", 0)
        end
    end
    return false
end

-- Popup modal for configuring the media directory
function Settings.handleSetupMediaDirectoryPopup()
    local ctx = globals.ctx
    local imgui = globals.imgui
    
    local success = pcall(function()
        if imgui.BeginPopupModal(ctx, "Setup Media Directory", nil, imgui.WindowFlags_AlwaysAutoResize) then
            imgui.Text(ctx, "You need to configure a directory for your media files")
            imgui.TextWrapped(ctx, "This directory will be used to store copies of all media files used in your presets.")
            
            -- Show the current directory if set
            local mediaDir = Settings.getSetting("mediaItemDirectory") or ""
            if mediaDir ~= "" then
                imgui.Text(ctx, "Current directory:")
                imgui.PushStyleColor(ctx, imgui.Col_Text, 0x00AA00FF)
                imgui.Text(ctx, mediaDir)
                imgui.PopStyleColor(ctx)
            end
            
            -- Button to open the directory selector
            if imgui.Button(ctx, "Select a directory...", 200, 0) then
                local success = Settings.setupMediaDirectory()
                if success then
                    imgui.CloseCurrentPopup(ctx)
                end
            end
            imgui.SameLine(ctx)
            if imgui.Button(ctx, "Cancel", 120, 0) then
                imgui.CloseCurrentPopup(ctx)
            end
            
            imgui.EndPopup(ctx)
        end
    end)
    
    -- If popup fails, ignore silently (it will be retried next frame if needed)
end

-- Check if a file exists at the given path

function Settings.fileExists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

-- Copy a file from source to destination

function Settings.copyFile(source, dest)
    -- Open the source file for reading
    local sourceFile = io.open(source, "rb")
    if not sourceFile then
        return false
    end
    -- Read the entire content
    local content = sourceFile:read("*all")
    sourceFile:close()
    -- Write to the destination file
    local destFile = io.open(dest, "wb")
    if not destFile then
        return false
    end
    destFile:write(content)
    destFile:close()
    return true
end

-- Copy a media file to the configured directory, returns the new path and success status

function Settings.copyMediaFile(sourcePath)
    local mediaDir = Settings.getSetting("mediaItemDirectory")
    if mediaDir == "" or not sourcePath or sourcePath == "" then
        return sourcePath, false
    end
    -- Extract the file name from the source path
    local fileName = sourcePath:match("([^/\\]+)$")
    if not fileName then
        return sourcePath, false
    end
    -- Build the destination path
    local destPath = mediaDir
    if not destPath:match("[/\\]$") then
        destPath = destPath .. "\\"
    end
    destPath = destPath .. fileName
    -- Avoid copying if the file already exists at the destination
    if Settings.fileExists(destPath) then
        return destPath, true
    end
    -- Copy the file and return the result
    local success = Settings.copyFile(sourcePath, destPath)
    return destPath, success
end

-- Process all media files in a container, copying them if needed

function Settings.processContainerMedia(container)
    if not container or not container.items then
        return container
    end
    -- Copy media files for each item in the container
    for i, item in ipairs(container.items) do
        if item.filePath and item.filePath ~= "" then
            local newPath, success = Settings.copyMediaFile(item.filePath)
            if success then
                item.filePath = newPath
            end
        end
    end
    return container
end

-------
--- Style
------- -- Converts a hex color (0xRRGGBBAA) to individual RGB components (0-1 for ImGui)

function Settings.colorToRGBA(color)
    -- Convert string to number if necessary
    if type(color) == "string" then
        color = tonumber(color)
    end
    -- Check that the color is a number
    if type(color) ~= "number" then
        -- Default value in case of error (opaque white)
        return 1, 1, 1, 1
    end
    -- Extract components using bitwise operations
    local r = (color >> 24) & 0xFF
    local g = (color >> 16) & 0xFF
    local b = (color >> 8) & 0xFF
    local a = color & 0xFF
    return r/255, g/255, b/255, a/255
end

-- Converts RGB components (0-1) to a hex color (0xRRGGBBAA)

function Settings.rgbaToColor(r, g, b, a)
    r = math.floor(r * 255)
    g = math.floor(g * 255)
    b = math.floor(b * 255)
    a = math.floor((a or 1) * 255)
    return (r << 24) | (g << 16) | (b << 8) | a
end

-- Display a color picker UI element for a specific color setting (using temp settings)

function Settings.colorPicker(label, colorKey)
    local ctx = globals.ctx
    local imgui = globals.imgui

    -- Use temporary settings instead of actual settings
    local currentColor = tempSettings[colorKey] or Settings.getSetting(colorKey)
    local rv, newColor = imgui.ColorEdit4(ctx, label, currentColor)
    if rv then
        -- Update temporary settings
        tempSettings[colorKey] = newColor
        -- Update actual settings for immediate UI preview
        globals.settings[colorKey] = newColor
        return true
    end
    return false
end

-- Add the color settings section to the main settings window

function Settings.showAppearanceSettings()
    local ctx = globals.ctx
    local imgui = globals.imgui
    imgui.TextColored(ctx, 0xFFAA00FF, "UI Appearance Settings")
    imgui.Separator(ctx)

    -- UI Scale slider with immediate UI update
    local rv, newScale = globals.SliderEnhanced.SliderDouble({
        id = "UI Scale",
        value = tempSettings.uiScale,
        min = 0.5,
        max = 2.0,
        defaultValue = 1.0,
        format = "%.2f",
        width = 200
    })
    if rv and newScale ~= tempSettings.uiScale then
        tempSettings.uiScale = newScale
        globals.settings.uiScale = newScale -- Immediate update for UI
    end
    imgui.SameLine(ctx)
    globals.Utils.HelpMarker("Controls the overall size of the UI (0.5 = 50%, 1.0 = 100%, 2.0 = 200%). Changes the window content size without affecting the window dimensions.")

    -- UI Rounding slider with immediate UI update
    local rv, newRounding = globals.SliderEnhanced.SliderDouble({
        id = "UI Rounding",
        value = tempSettings.uiRounding,
        min = 0.0,
        max = 12.0,
        defaultValue = 4.0,  -- Reasonable default for UI rounding
        format = "%.1f",
        width = 200
    })
    if rv and newRounding ~= tempSettings.uiRounding then
        tempSettings.uiRounding = newRounding
        globals.settings.uiRounding = newRounding -- Immediate update for UI
    end
    imgui.SameLine(ctx)
    globals.Utils.HelpMarker("Controls the roundness of UI elements like buttons, frames, and sliders. Higher values create more rounded corners.")
    -- UI Item Spacing with immediate UI update
    local rv, newSpacing = globals.SliderEnhanced.SliderInt({
        id = "UI Spacing",
        value = tempSettings.itemSpacing,
        min = 0,
        max = 20,
        defaultValue = 4,  -- Reasonable default for item spacing
        format = "%d",
        width = 200
    })
    if rv and newSpacing ~= tempSettings.itemSpacing then
        tempSettings.itemSpacing = newSpacing
        globals.settings.itemSpacing = newSpacing -- Immediate update for UI
    end
    imgui.SameLine(ctx)
    globals.Utils.HelpMarker("Controls the space between UI elements.")
    -- Add color pickers for the color settings
    Settings.colorPicker("Button Color", "buttonColor")
    Settings.colorPicker("Background Color", "backgroundColor")
    Settings.colorPicker("Text Color", "textColor")
    Settings.colorPicker("Waveform Color", "waveformColor")
    Settings.colorPicker("Icon Color", "iconColor")

    -- Knob indicator visibility checkbox
    local rv, showIndicator = imgui.Checkbox(ctx, "Show knob indicator line",
        tempSettings.showKnobIndicator)
    if rv then
        tempSettings.showKnobIndicator = showIndicator
        globals.settings.showKnobIndicator = showIndicator -- Immediate update for UI
    end
    imgui.SameLine(ctx)
    globals.Utils.HelpMarker("Shows or hides the indicator line and center dot on rotary knobs")

    imgui.Separator(ctx)
end

-- Add the crossfade settings section

function Settings.showCrossfadeSettings()
    local ctx = globals.ctx
    local imgui = globals.imgui
    imgui.TextColored(ctx, 0xFFAA00FF, "Crossfade Settings")
    imgui.Separator(ctx)
    -- Crossfade margin/length setting with immediate UI update
    local rv, newMargin = globals.SliderEnhanced.SliderDouble({
        id = "Crossfade Length (seconds)",
        value = tempSettings.crossfadeMargin,
        min = 0.05,
        max = 2.0,
        defaultValue = globals.Constants.AUDIO.DEFAULT_CROSSFADE_MARGIN,
        format = "%.3f",
        width = 200
    })
    if rv and newMargin ~= tempSettings.crossfadeMargin then
        tempSettings.crossfadeMargin = newMargin
        globals.settings.crossfadeMargin = newMargin -- Immediate update for UI
    end
    imgui.SameLine(ctx)
    globals.Utils.HelpMarker("Determines the length of automatic crossfades created when regenerating content in a time selection. A higher value creates longer and smoother transitions")
    imgui.Separator(ctx)
end

-- Add the waveform settings section

function Settings.showWaveformSettings()
    local ctx = globals.ctx
    local imgui = globals.imgui
    imgui.TextColored(ctx, 0xFFAA00FF, "Waveform Settings")
    imgui.Separator(ctx)

    -- Auto-play checkbox
    local rv, autoPlay = imgui.Checkbox(ctx, "Auto-play on selection",
        tempSettings.waveformAutoPlayOnSelect)
    if rv then
        tempSettings.waveformAutoPlayOnSelect = autoPlay
    end
    imgui.SameLine(ctx)
    globals.Utils.HelpMarker("When enabled: Play on selection & click\nWhen disabled: Click only sets position marker")

    imgui.Separator(ctx)
end

return Settings
