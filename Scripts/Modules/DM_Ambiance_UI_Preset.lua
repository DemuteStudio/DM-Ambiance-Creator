--[[
@version 1.3
@noindex
--]]

local UI_Preset = {}
local globals = {}

-- Initialize the module with references to global variables from the main script
function UI_Preset.initModule(g)
    globals = g
end

-- Draw the UI controls for managing global presets in the top section of the interface
function UI_Preset.drawPresetControls()
    -- Display section title with a specific color (orange)
    imgui.TextColored(globals.ctx, 0xFFAA00FF, "Global Presets")
    
    -- -- Place the next item on the same line as the title
    -- imgui.SameLine(globals.ctx)
    -- -- Button to refresh the list of presets
    -- if imgui.Button(globals.ctx, "Refresh") then
    --     globals.Presets.listPresets("Global", nil, true) -- Refresh the global presets list forcibly
    -- end
    
    imgui.SameLine(globals.ctx)
    
    -- Retrieve the list of global presets from the Presets module
    local presetList = globals.Presets.listPresets("Global")
    
    -- Prepare the preset names as a null-separated string for ImGui Combo widget
    local presetItems = ""
    for _, name in ipairs(presetList) do
        presetItems = presetItems .. name .. "\0"
    end
    presetItems = presetItems .. "\0" -- ImGui requires double null termination
    
    -- Set the width of the combo box to 300 pixels
    imgui.PushItemWidth(globals.ctx, 300)
    
    -- Display the dropdown combo box for selecting a preset
    local rv, newSelectedIndex = globals.UndoWrappers.Combo(globals.ctx, "##PresetSelector", globals.selectedPresetIndex, presetItems)
    
    -- If the user changed the selection, update the current preset index and name
    if rv then
        globals.selectedPresetIndex = newSelectedIndex
        globals.currentPresetName = presetList[globals.selectedPresetIndex + 1] or ""
    end
    
    -- Button to load the selected preset, only active if a preset is selected
    imgui.SameLine(globals.ctx)
    if globals.Icons.createDownloadButton(globals.ctx, "preset", "Load preset") and globals.currentPresetName ~= "" then
        globals.Presets.loadPreset(globals.currentPresetName)
    end
    
    -- Button to save the current preset
    imgui.SameLine(globals.ctx)
    if globals.Icons.createUploadButton(globals.ctx, "preset", "Save preset") then
        
        -- Check if the media directory is configured before opening the save popup
        if not globals.Utils.isMediaDirectoryConfigured() then
            -- Set flag to show a warning about missing media directory configuration
            globals.showMediaDirWarning = true
        else
            -- Proceed to open the save preset popup safely
            globals.Utils.safeOpenPopup("Save Preset")
            globals.newPresetName = globals.currentPresetName -- Initialize the input field with the current preset name
        end
    end
    
    -- Button to delete the currently selected preset, only active if a preset is selected
    imgui.SameLine(globals.ctx)
    if globals.Icons.createDeleteButtonWithFallback(globals.ctx, "preset", "Delete", "Delete preset") and globals.currentPresetName ~= "" then
        globals.Utils.safeOpenPopup("Confirm deletion")
    end
    
    -- Button to open the folder containing presets
    imgui.SameLine(globals.ctx)
    if globals.Icons.createFolderButton(globals.ctx, "presetDir", "Open preset directory") then
        globals.Utils.openPresetsFolder("Presets")
    end
    
    -- Button to open the conflict resolver
    imgui.SameLine(globals.ctx)
    if globals.Icons.createConflictButton(globals.ctx, "conflictResolver", "Open Routing Validator") then
        -- Validate project routing using the new system
        local issues = globals.RoutingValidator.validateProjectRouting()
        -- Always show modal, even if no issues (issues can be empty array)
        globals.RoutingValidator.showValidationModal(issues or {})
    end

    -- Undo button
    imgui.SameLine(globals.ctx)
    local canUndo = globals.History.canUndo()
    imgui.BeginDisabled(globals.ctx, not canUndo)
    if imgui.Button(globals.ctx, "Undo##UndoBtn") then
        globals.History.undo()
    end
    if imgui.IsItemHovered(globals.ctx, imgui.HoveredFlags_AllowWhenDisabled) then
        imgui.SetTooltip(globals.ctx, "Undo last action (Ctrl+Z)")
    end
    imgui.EndDisabled(globals.ctx)

    -- Redo button
    imgui.SameLine(globals.ctx)
    local canRedo = globals.History.canRedo()
    imgui.BeginDisabled(globals.ctx, not canRedo)
    if imgui.Button(globals.ctx, "Redo##RedoBtn") then
        globals.History.redo()
    end
    if imgui.IsItemHovered(globals.ctx, imgui.HoveredFlags_AllowWhenDisabled) then
        imgui.SetTooltip(globals.ctx, "Redo last undone action (Ctrl+Y or Ctrl+Shift+Z)")
    end
    imgui.EndDisabled(globals.ctx)

    -- Undo History button
    imgui.SameLine(globals.ctx)
    if imgui.Button(globals.ctx, "History##UndoHistoryBtn") then
        globals.showUndoHistoryWindow = not globals.showUndoHistoryWindow
    end
    if imgui.IsItemHovered(globals.ctx) then
        imgui.SetTooltip(globals.ctx, "Show Undo History window")
    end

    -- Handle the save preset popup modal window
    UI_Preset.handleSavePresetPopup(presetList)
    
    -- Handle the delete preset confirmation popup modal window
    UI_Preset.handleDeletePresetPopup()
end

-- In DM_Ambiance_UI_Preset.lua, replace these functions:

-- Handle the popup window for saving a preset
function UI_Preset.handleSavePresetPopup(presetList)
    local success = pcall(function()
        if imgui.BeginPopupModal(globals.ctx, "Save Preset", nil, imgui.WindowFlags_AlwaysAutoResize) then
            
            -- Label for the preset name input field
            imgui.Text(globals.ctx, "Preset name:")
            
            -- Input text box for entering the new preset name
            local rv, value = imgui.InputText(globals.ctx, "##PresetName", globals.newPresetName)
            if rv then globals.newPresetName = value end
            
            -- Save button, enabled only if the preset name is not empty
            if imgui.Button(globals.ctx, "Save", 120, 0) and globals.newPresetName ~= "" then
                if globals.Presets.savePreset(globals.newPresetName) then
                    -- Update current preset name and selected index after successful save
                    globals.currentPresetName = globals.newPresetName
                    for i, name in ipairs(presetList) do
                        if name == globals.currentPresetName then
                            globals.selectedPresetIndex = i - 1 -- ImGui combo index is zero-based
                            break
                        end
                    end
                    -- Close the save preset popup safely
                    globals.Utils.safeClosePopup("Save Preset")
                end
            end
            
            imgui.SameLine(globals.ctx)
            -- Cancel button to close the popup without saving
            if imgui.Button(globals.ctx, "Cancel", 120, 0) then
                globals.Utils.safeClosePopup("Save Preset")
            end
            
            imgui.EndPopup(globals.ctx)
        end
    end)
    
    -- If popup rendering fails, close it safely
    if not success then
        globals.Utils.safeClosePopup("Save Preset")
    end
end

-- Handle the popup window for confirming preset deletion
function UI_Preset.handleDeletePresetPopup()
    local success = pcall(function()
        if imgui.BeginPopupModal(globals.ctx, "Confirm deletion", nil, imgui.WindowFlags_AlwaysAutoResize) then
            -- Confirmation message with the name of the preset to delete
            imgui.Text(globals.ctx, "Are you sure you want to delete the preset \"" .. globals.currentPresetName .. "\"?")
            imgui.Separator(globals.ctx)
            
            -- Yes button to confirm deletion
            if imgui.Button(globals.ctx, "Yes", 120, 0) then
                globals.Presets.deletePreset(globals.currentPresetName, "Global")
                globals.Utils.safeClosePopup("Confirm deletion")
            end
            
            imgui.SameLine(globals.ctx)
            -- No button to cancel deletion
            if imgui.Button(globals.ctx, "No", 120, 0) then
                globals.Utils.safeClosePopup("Confirm deletion")
            end
            
            imgui.EndPopup(globals.ctx)
        end
    end)
    
    -- If popup rendering fails, close it safely
    if not success then
        globals.Utils.safeClosePopup("Confirm deletion")
    end
end

return UI_Preset
