--[[
@version 1.5
@noindex
DM Ambiance Creator - UI Utilities Module
Extracted from DM_Ambiance_Utils.lua for better modularity

This module contains all UI helper functions (HelpMarker, tooltips, popups, colors, combo boxes).
--]]

local Utils_UI = {}
local Constants = require("DM_Ambiance_Constants")

-- Module globals (set by initModule)
local globals = {}

-- Dependencies (set during module loading)
local Utils_String = nil

-- Initialize the module with global references from the main script
function Utils_UI.initModule(g)
    if not g then
        error("Utils_UI.initModule: globals parameter is required")
    end
    globals = g

    -- Load Utils_String dependency for fuzzyMatch
    Utils_String = require("Utils.Utils_String")
end

-- ===================================================================
-- HELP MARKERS AND TOOLTIPS
-- ===================================================================

-- Display a help marker "(?)" with a tooltip containing the provided description
function Utils_UI.HelpMarker(desc)
    if not desc or desc == "" then
        error("Utils_UI.HelpMarker: description parameter is required")
    end

    globals.imgui.SameLine(globals.ctx)
    globals.imgui.TextDisabled(globals.ctx, '(?)')
    if globals.imgui.BeginItemTooltip(globals.ctx) then
        globals.imgui.PushTextWrapPos(globals.ctx, globals.imgui.GetFontSize(globals.ctx) * Constants.UI.HELP_MARKER_TEXT_WRAP)
        globals.imgui.Text(globals.ctx, desc)
        globals.imgui.PopTextWrapPos(globals.ctx)
        globals.imgui.EndTooltip(globals.ctx)
    end
end

-- ===================================================================
-- FOLDER OPENING UTILITIES
-- ===================================================================

-- Open the preset folder in the system file explorer
function Utils_UI.openPresetsFolder(type, groupName)
    local path = globals.Presets.getPresetsPath(type, groupName)
    if reaper.GetOS():match("Win") then
        os.execute('start "" "' .. path .. '"')
    elseif reaper.GetOS():match("OSX") then
        os.execute('open "' .. path .. '"')
    else -- Linux
        os.execute('xdg-open "' .. path .. '"')
    end
end

-- Open any folder in the system file explorer
function Utils_UI.openFolder(path)
    if not path or path == "" then
        return
    end
    local OS = reaper.GetOS()
    local command
    if OS:match("^Win") then
        command = 'explorer "'
    elseif OS:match("^macOS") or OS:match("^OSX") then
        command = 'open "'
    else -- Linux
        command = 'xdg-open "'
    end
    os.execute(command .. path .. '"')
end

-- ===================================================================
-- POPUP MANAGEMENT
-- ===================================================================

-- Open a popup safely (prevents multiple flashes or duplicate popups)
function Utils_UI.safeOpenPopup(popupName)
    -- Initialize activePopups if it doesn't exist
    if not globals.activePopups then
        globals.activePopups = {}
    end

    -- Only open if not already active and if we're in a valid ImGui context
    if not globals.activePopups[popupName] then
        local success = pcall(function()
            globals.imgui.OpenPopup(globals.ctx, popupName)
        end)

        if success then
            globals.activePopups[popupName] = {
                active = true,
                timeOpened = reaper.time_precise()
            }
        end
    end
end

-- Close a popup safely and remove it from the active popups list
function Utils_UI.safeClosePopup(popupName)
    -- Use pcall to prevent crashes
    pcall(function()
        globals.imgui.CloseCurrentPopup(globals.ctx)
    end)

    -- Clean up the popup tracking
    if globals.activePopups then
        globals.activePopups[popupName] = nil
    end
end

-- Display a warning popup if the media directory is not configured
function Utils_UI.showDirectoryWarningPopup(popupTitle)
    local ctx = globals.ctx
    local imgui = globals.imgui
    local title = popupTitle or "Warning: Media Directory Not Configured"

    -- Use safe popup management to avoid flashing issues
    Utils_UI.safeOpenPopup(title)

    -- Use pcall to protect against errors in popup rendering
    local success = pcall(function()
        if imgui.BeginPopupModal(ctx, title, nil, imgui.WindowFlags_AlwaysAutoResize) then
            imgui.TextColored(ctx, 0xFF8000FF, "No media directory has been configured in the settings.")
            imgui.TextWrapped(ctx, "You need to configure a media directory before saving presets to ensure proper media file management.")

            imgui.Separator(ctx)

            if imgui.Button(ctx, "Configure Now", 150, 0) then
                -- Open the settings window
                globals.showSettingsWindow = true
                Utils_UI.safeClosePopup(title)
                globals.showMediaDirWarning = false  -- Reset the state
            end

            imgui.SameLine(ctx)

            if imgui.Button(ctx, "Cancel", 120, 0) then
                Utils_UI.safeClosePopup(title)
                globals.showMediaDirWarning = false  -- Reset the state
            end

            imgui.EndPopup(ctx)
        end
    end)

    -- If popup rendering fails, reset the warning flag
    if not success then
        globals.showMediaDirWarning = false
        if globals.activePopups then
            globals.activePopups[title] = nil
        end
    end
end

-- ===================================================================
-- COLOR UTILITIES
-- ===================================================================

-- Unpacks a 32-bit color into individual RGBA components (0-1)
-- @param color number|string: Color value to unpack
-- @return number, number, number, number: r, g, b, a values (0-1)
function Utils_UI.unpackColor(color)
    -- Convert string to number if necessary
    if type(color) == "string" then
        color = tonumber(color)
    end

    -- Check that the color is a number
    if type(color) ~= "number" then
        -- Default value in case of error (opaque white)
        local defaultColor = Constants.COLORS.DEFAULT_WHITE
        local r = ((defaultColor >> 24) & 0xFF) / 255
        local g = ((defaultColor >> 16) & 0xFF) / 255
        local b = ((defaultColor >> 8) & 0xFF) / 255
        local a = (defaultColor & 0xFF) / 255
        return r, g, b, a
    end

    local r = ((color >> 24) & 0xFF) / 255
    local g = ((color >> 16) & 0xFF) / 255
    local b = ((color >> 8) & 0xFF) / 255
    local a = (color & 0xFF) / 255

    return r, g, b, a
end

-- Packs RGBA components (0-1) into a 32-bit color
-- @param r number: Red component (0-1)
-- @param g number: Green component (0-1)
-- @param b number: Blue component (0-1)
-- @param a number: Alpha component (0-1, optional, defaults to 1)
-- @return number: 32-bit color value
function Utils_UI.packColor(r, g, b, a)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        error("Utils_UI.packColor: r, g, b parameters must be numbers")
    end

    -- Clamp values to valid range
    r = math.max(0, math.min(1, r))
    g = math.max(0, math.min(1, g))
    b = math.max(0, math.min(1, b))
    a = math.max(0, math.min(1, a or 1))

    r = math.floor(r * 255)
    g = math.floor(g * 255)
    b = math.floor(b * 255)
    a = math.floor(a * 255)

    return (r << 24) | (g << 16) | (b << 8) | a
end

-- Utility function to brighten or darken a color
-- @param color number: Color value to modify
-- @param amount number: Amount to brighten (positive) or darken (negative)
-- @return number: Modified color value
function Utils_UI.brightenColor(color, amount)
    if type(amount) ~= "number" then
        error("Utils_UI.brightenColor: amount parameter must be a number")
    end

    local r, g, b, a = Utils_UI.unpackColor(color)

    r = math.max(0, math.min(1, r + amount))
    g = math.max(0, math.min(1, g + amount))
    b = math.max(0, math.min(1, b + amount))

    return Utils_UI.packColor(r, g, b, a)
end

-- ===================================================================
-- SEARCHABLE COMBO BOX
-- ===================================================================

-- Searchable combo box with fuzzy matching
-- @param label string: The combo box label (include ## for hidden label)
-- @param currentIndex number: Currently selected index (-1 for none)
-- @param items table: Array of item names
-- @param searchQuery string: Current search query
-- @param width number: Width of the combo box (optional)
-- @return boolean, number, string: changed, new selected index, new search query
function Utils_UI.searchableCombo(label, currentIndex, items, searchQuery, width)
    local ctx = globals.ctx
    local imgui = globals.imgui

    -- Filter items based on search query
    local filteredItems = {}
    local itemScores = {}
    local indexMap = {} -- Maps filtered index to original index

    for i, name in ipairs(items) do
        local matches, score = Utils_String.fuzzyMatch(searchQuery, name)
        if matches then
            table.insert(filteredItems, name)
            itemScores[name] = score
            indexMap[#filteredItems] = i
        end
    end

    -- Sort filtered items
    if searchQuery ~= "" then
        -- When searching, sort by score (highest first)
        table.sort(filteredItems, function(a, b)
            return itemScores[a] > itemScores[b]
        end)
    else
        -- When not searching, sort alphabetically (case-insensitive)
        table.sort(filteredItems, function(a, b)
            return a:lower() < b:lower()
        end)
    end

    -- Rebuild index map after sort
    indexMap = {}
    for filteredIdx, name in ipairs(filteredItems) do
        for originalIdx, originalName in ipairs(items) do
            if name == originalName then
                indexMap[filteredIdx] = originalIdx
                break
            end
        end
    end

    -- Find current item in filtered list
    local filteredIndex = -1
    if currentIndex >= 0 and currentIndex < #items then
        local currentName = items[currentIndex + 1]
        for i, name in ipairs(filteredItems) do
            if name == currentName then
                filteredIndex = i - 1
                break
            end
        end
    end

    -- Display preview value (current selection or search query)
    local previewValue = ""
    if searchQuery ~= "" then
        previewValue = searchQuery
    elseif currentIndex >= 0 and currentIndex < #items then
        previewValue = items[currentIndex + 1]
    end

    if width then
        imgui.PushItemWidth(ctx, width)
    end

    local changed = false
    local newIndex = currentIndex
    local newSearchQuery = searchQuery

    -- Track if combo was just opened
    if not globals.comboJustOpened then
        globals.comboJustOpened = {}
    end

    -- Begin combo
    local comboOpened = imgui.BeginCombo(ctx, label, previewValue, 0)
    if comboOpened then
        -- Only set focus on first frame when combo opens
        if not globals.comboJustOpened[label] then
            imgui.SetKeyboardFocusHere(ctx, 0)
            globals.comboJustOpened[label] = true
        end

        -- Search input at the top of the combo
        local searchChanged, newQuery = imgui.InputTextWithHint(ctx, "##Search" .. label, "Type to search...", searchQuery)
        if searchChanged then
            newSearchQuery = newQuery
        end

        imgui.Separator(ctx)

        -- Display filtered items
        for i, name in ipairs(filteredItems) do
            local isSelected = (i - 1 == filteredIndex)
            if imgui.Selectable(ctx, name, isSelected) then
                newIndex = indexMap[i] - 1  -- Convert back to original index
                newSearchQuery = ""  -- Clear search when selecting
                changed = true
            end

            if isSelected then
                imgui.SetItemDefaultFocus(ctx)
            end
        end

        -- Show "no results" message if nothing matches
        if #filteredItems == 0 then
            imgui.TextDisabled(ctx, "No matches found")
        end

        imgui.EndCombo(ctx)
    else
        -- Combo is closed, reset the "just opened" flag
        globals.comboJustOpened[label] = nil
    end

    if width then
        imgui.PopItemWidth(ctx)
    end

    return changed, newIndex, newSearchQuery
end

return Utils_UI
