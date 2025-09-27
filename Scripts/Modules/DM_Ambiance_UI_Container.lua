--[[
@version 1.5
@noindex
--]]

local UI_Container = {}
local globals = {}
local Constants = require("DM_Ambiance_Constants")
local imgui = nil  -- Will be initialized from globals

-- Initialize the module with global variables from the main script
function UI_Container.initModule(g)
    if not g then
        error("UI_Container.initModule: globals parameter is required")
    end
    globals = g
    imgui = globals.imgui  -- Get imgui reference from globals
    
    -- Initialize container expanded states if not already set
    if not globals.containerExpandedStates then
        globals.containerExpandedStates = {}
    end
end

-- Display the preset controls for a specific container (load/save container presets)
function UI_Container.drawContainerPresetControls(groupIndex, containerIndex)
    local groupId = "group" .. groupIndex
    local containerId = groupId .. "_container" .. containerIndex
    local presetKey = groupIndex .. "_" .. containerIndex

    -- Initialize the selected preset index for this container if not already set
    if not globals.selectedContainerPresetIndex[presetKey] then
        globals.selectedContainerPresetIndex[presetKey] = -1
    end

    -- Get a sanitized group name for folder structure (replace non-alphanumeric characters with underscores)
    local groupName = globals.groups[groupIndex].name:gsub("[^%w]", "_")

    -- Get the list of available container presets (shared across all groups)
    local containerPresetList = globals.Presets.listPresets("Containers")

    -- Prepare the items for the preset dropdown (ImGui Combo expects a null-separated string)
    local containerPresetItems = ""
    for _, name in ipairs(containerPresetList) do
        containerPresetItems = containerPresetItems .. name .. "\0"
    end

    -- Preset dropdown control
    imgui.PushItemWidth(globals.ctx, 200)
    local rv, newSelectedContainerIndex = imgui.Combo(
        globals.ctx,
        "##ContainerPresetSelector" .. containerId,
        globals.selectedContainerPresetIndex[presetKey],
        containerPresetItems
    )
    if rv then
        globals.selectedContainerPresetIndex[presetKey] = newSelectedContainerIndex
    end

    -- Load preset button: loads the selected preset into this container
    imgui.SameLine(globals.ctx)
    if globals.Icons.createDownloadButton(globals.ctx, "loadContainer" .. containerId, "Load container preset")
        and globals.selectedContainerPresetIndex[presetKey] >= 0
        and globals.selectedContainerPresetIndex[presetKey] < #containerPresetList then

        local presetName = containerPresetList[globals.selectedContainerPresetIndex[presetKey] + 1]
        globals.Presets.loadContainerPreset(presetName, groupIndex, containerIndex)
    end

    -- Save preset button: opens a popup to save the current container as a preset
    imgui.SameLine(globals.ctx)
    if globals.Icons.createUploadButton(globals.ctx, "saveContainer" .. containerId, "Save container preset") then
        -- Check if a media directory is configured before allowing save
        if not globals.Utils.isMediaDirectoryConfigured() then
            -- Set flag to show the warning popup
            globals.showMediaDirWarning = true
        else
            -- Continue with the normal save popup
            globals.newContainerPresetName = globals.groups[groupIndex].containers[containerIndex].name
            globals.currentSaveContainerGroup = groupIndex
            globals.currentSaveContainerIndex = containerIndex
            globals.Utils.safeOpenPopup("Save Container Preset##" .. containerId)
        end
    end

    -- Popup dialog for saving the container as a preset
    if imgui.BeginPopupModal(globals.ctx, "Save Container Preset##" .. containerId, nil, imgui.WindowFlags_AlwaysAutoResize) then
        imgui.Text(globals.ctx, "Container preset name:")
        local rv, value = imgui.InputText(globals.ctx, "##ContainerPresetName" .. containerId, globals.newContainerPresetName)
        if rv then globals.newContainerPresetName = value end

        if imgui.Button(globals.ctx, "Save", 120, 0) and globals.newContainerPresetName ~= "" then
            if globals.Presets.saveContainerPreset(
                globals.newContainerPresetName,
                globals.currentSaveContainerGroup,
                globals.currentSaveContainerIndex
            ) then
                globals.Utils.safeClosePopup("Save Container Preset##" .. containerId)
            end
        end

        imgui.SameLine(globals.ctx)
        if imgui.Button(globals.ctx, "Cancel", 120, 0) then
            globals.Utils.safeClosePopup("Save Container Preset##" .. containerId)
        end

        imgui.EndPopup(globals.ctx)
    end
end

-- Display the settings for a specific container in the right panel
function UI_Container.displayContainerSettings(groupIndex, containerIndex, width)
    if not globals.groups[groupIndex] or not globals.groups[groupIndex].containers[containerIndex] then
        imgui.Text(globals.ctx, "No container selected")
        return
    end
    local group = globals.groups[groupIndex]
    local container = group.containers[containerIndex]
    local groupId = "group" .. groupIndex
    local containerId = groupId .. "_container" .. containerIndex
    
    -- Sync channel volumes from tracks if in multichannel mode
    if container.channelMode and container.channelMode > 0 then
        globals.Utils.syncChannelVolumesFromTracks(groupIndex, containerIndex)
    end
    
    -- Sync container volume from track
    globals.Utils.syncContainerVolumeFromTrack(groupIndex, containerIndex)

    -- Panel title showing which container is being edited
    imgui.Text(globals.ctx, "Container Settings: " .. container.name)
    imgui.Separator(globals.ctx)

    -- Editable container name input field
    local containerName = container.name
    imgui.PushItemWidth(globals.ctx, width * 0.5)
    local rv, newContainerName = imgui.InputText(globals.ctx, "Name##detail_" .. containerId, containerName)
    if rv then container.name = newContainerName end
    
    -- Container preset controls (load/save)
    UI_Container.drawContainerPresetControls(groupIndex, containerIndex)

    -- Button to import selected items from REAPER into this container
    if imgui.Button(globals.ctx, "Import Selected Items##" .. containerId) then
        local items = globals.Items.getSelectedItems()
        if #items > 0 then
            for _, item in ipairs(items) do
                table.insert(container.items, item)
                -- Generate peaks for the imported item if needed
                if item.filePath and item.filePath ~= "" then
                    local peaksFile = item.filePath .. ".reapeaks"
                    local exists = io.open(peaksFile, "rb")
                    if exists then
                        exists:close()
                    else
                        -- Generate peaks in background
                        globals.Waveform.generateReapeaksFile(item.filePath)
                    end
                end
            end
            -- reaper.ShowConsoleMsg(string.format("[UI] Imported %d items\n", #items))
        else
            reaper.MB("No item selected!", "Error", 0)
        end
    end
    
    -- Button to generate peaks for all items in container
    imgui.SameLine(globals.ctx)
    if imgui.Button(globals.ctx, "Build All Peaks##" .. containerId) then
        local generated = globals.Waveform.generatePeaksForContainer(container)
        -- reaper.ShowConsoleMsg(string.format("[UI] Generated peaks for %d files\n", generated))
    end

    -- Display imported items with persistent state
    if #container.items > 0 then
        -- Create unique key for this container's expanded state and selection
        local expandedStateKey = groupIndex .. "_" .. containerIndex .. "_items"
        local selectionKey = groupIndex .. "_" .. containerIndex
        
        -- Initialize expanded state if not set (default to collapsed)
        if globals.containerExpandedStates[expandedStateKey] == nil then
            globals.containerExpandedStates[expandedStateKey] = false
        end
        
        -- Initialize selected item index if not set
        if not globals.selectedItemIndex then
            globals.selectedItemIndex = {}
        end
        if globals.selectedItemIndex[selectionKey] == nil then
            globals.selectedItemIndex[selectionKey] = -1
        end
        
        -- Use PushID to create stable context
        imgui.PushID(globals.ctx, containerId .. "_items")
        
        -- If we need to maintain the open state, set it before the header
        if globals.containerExpandedStates[expandedStateKey] then
            imgui.SetNextItemOpen(globals.ctx, true)
        end
        
        -- Create header with stable ID
        local headerLabel = "Imported items (" .. #container.items .. ")"
        local wasExpanded = globals.containerExpandedStates[expandedStateKey]
        local isExpanded = imgui.CollapsingHeader(globals.ctx, headerLabel)
        
        -- Track state changes
        if isExpanded ~= wasExpanded then
            globals.containerExpandedStates[expandedStateKey] = isExpanded
        end
        
        -- Show content if expanded
        if isExpanded then
            local itemToDelete = nil
            
            -- Create a child window for the item list to make it scrollable
            if imgui.BeginChild(globals.ctx, "ItemsList" .. containerId, width * 0.95, 100) then
                -- List all imported items as selectable items
                for l, item in ipairs(container.items) do
                    local isSelected = (globals.selectedItemIndex[selectionKey] == l)
                    
                    -- Make item selectable
                    if imgui.Selectable(globals.ctx, l .. ". " .. item.name .. "##item" .. l, isSelected) then
                        globals.selectedItemIndex[selectionKey] = l
                        -- Debug: clear cache when selecting new item
                        if globals.Waveform and item.filePath then
                            -- reaper.ShowConsoleMsg(string.format("[UI] Selected item with path: %s\n", item.filePath))
                            globals.Waveform.clearFileCache(item.filePath)
                        end
                    end
                    
                    -- Delete button on same line
                    imgui.SameLine(globals.ctx, width * 0.85)
                    imgui.PushStyleColor(globals.ctx, imgui.Col_Button, 0xFF0000FF)
                    if imgui.SmallButton(globals.ctx, "X##delete" .. l) then
                        itemToDelete = l
                    end
                    imgui.PopStyleColor(globals.ctx, 1)
                end
                
                imgui.EndChild(globals.ctx)
            end
            
            -- Remove the item if the delete button was pressed
            if itemToDelete then
                table.remove(container.items, itemToDelete)
                -- Keep the header expanded after deletion
                globals.containerExpandedStates[expandedStateKey] = true
                -- Reset selection if deleted item was selected
                if globals.selectedItemIndex[selectionKey] == itemToDelete then
                    globals.selectedItemIndex[selectionKey] = -1
                elseif globals.selectedItemIndex[selectionKey] > itemToDelete then
                    globals.selectedItemIndex[selectionKey] = globals.selectedItemIndex[selectionKey] - 1
                end
            end
        end
        
        imgui.PopID(globals.ctx)
    end
    
    -- Waveform Viewer Section (for selected imported items)
    local selectionKey = groupIndex .. "_" .. containerIndex
    if globals.selectedItemIndex and globals.selectedItemIndex[selectionKey] and 
       globals.selectedItemIndex[selectionKey] > 0 and 
       globals.selectedItemIndex[selectionKey] <= #container.items then
        
        local selectedItem = container.items[globals.selectedItemIndex[selectionKey]]
        
        imgui.Separator(globals.ctx)
        imgui.Text(globals.ctx, "Waveform Viewer")

        -- Add display options on the same line
        imgui.SameLine(globals.ctx)
        imgui.SetCursorPosX(globals.ctx, width * 0.4)
        local _, showPeaks = imgui.Checkbox(globals.ctx, "Peaks##waveform",
            globals.waveformShowPeaks ~= false)
        globals.waveformShowPeaks = showPeaks

        imgui.SameLine(globals.ctx)
        local _, showRMS = imgui.Checkbox(globals.ctx, "RMS##waveform",
            globals.waveformShowRMS ~= false)
        globals.waveformShowRMS = showRMS

        imgui.Separator(globals.ctx)

        -- Display selected item info and controls on one line
        imgui.Text(globals.ctx, "Selected: " .. selectedItem.name)

        -- Clear Cache button
        imgui.SameLine(globals.ctx)
        if imgui.SmallButton(globals.ctx, "Clear Cache") then
            globals.Waveform.clearFileCache(selectedItem.filePath)
        end

        -- Rebuild Peaks button
        imgui.SameLine(globals.ctx)
        if imgui.SmallButton(globals.ctx, "Rebuild Peaks") then
            if globals.Waveform.regeneratePeaksFile(selectedItem.filePath) then
                globals.Waveform.clearFileCache(selectedItem.filePath)
            end
        end
        
        -- Check if file path exists and is valid
        local filePathValid = selectedItem.filePath and selectedItem.filePath ~= ""
        local fileExists = false
        
        if filePathValid then
            local file = io.open(selectedItem.filePath, "rb")  -- Use binary mode for better compatibility
            if file then
                fileExists = true
                file:close()
                -- reaper.ShowConsoleMsg(string.format("[UI] File exists: %s\n", selectedItem.filePath))
            else
                -- Try alternative method for network drives on Windows
                local source = reaper.PCM_Source_CreateFromFile(selectedItem.filePath)
                if source then
                    fileExists = true
                    reaper.PCM_Source_Destroy(source)
                    -- reaper.ShowConsoleMsg(string.format("[UI] File exists (via PCM_Source): %s\n", selectedItem.filePath))
                else
                    -- reaper.ShowConsoleMsg(string.format("[UI] File NOT found: %s\n", selectedItem.filePath))
                end
            end
        end
        
        if filePathValid then
            if fileExists then
                imgui.Text(globals.ctx, string.format("Duration: %.2f s", selectedItem.length))
                imgui.PushStyleColor(globals.ctx, imgui.Col_Text, 0x00FF00FF)
                imgui.Text(globals.ctx, "File: Available")
                imgui.PopStyleColor(globals.ctx, 1)
            else
                imgui.Text(globals.ctx, string.format("Duration: %.2f s", selectedItem.length))
                imgui.PushStyleColor(globals.ctx, imgui.Col_Text, 0xFF0000FF)
                imgui.Text(globals.ctx, "File: Not found")
                imgui.PopStyleColor(globals.ctx, 1)
                imgui.TextWrapped(globals.ctx, "Path: " .. selectedItem.filePath)
            end
        else
            imgui.PushStyleColor(globals.ctx, imgui.Col_Text, 0xFFFF00FF)
            imgui.Text(globals.ctx, "File: No path specified")
            imgui.PopStyleColor(globals.ctx, 1)
        end
        
        -- Draw waveform if the Waveform module is available
        if globals.Waveform then
            -- reaper.ShowConsoleMsg(string.format("[UI] Drawing waveform - fileExists: %s, path: %s\n", 
                -- tostring(fileExists), selectedItem.filePath or "nil"))
            local waveformData = nil
            if fileExists then
                -- Enhanced waveform options
                local waveformOptions = {
                    useLogScale = false,   -- Disable logarithmic scaling for more accurate representation
                    amplifyQuiet = 3.0,    -- Amplification factor for quiet sounds
                    startOffset = selectedItem.startOffset or 0,  -- Start position in the file (D_STARTOFFS)
                    displayLength = selectedItem.length,          -- Length to display (D_LENGTH - edited duration)
                    verticalZoom = globals.waveformVerticalZoom or 1.0,  -- Vertical zoom factor
                    showPeaks = globals.waveformShowPeaks,        -- Show/hide peaks
                    showRMS = globals.waveformShowRMS,            -- Show/hide RMS
                    -- Callback when waveform is clicked
                    onWaveformClick = function(clickPosition, waveformData)
                        -- Start playback from the clicked position
                        globals.Waveform.startPlayback(
                            selectedItem.filePath,
                            selectedItem.startOffset or 0,
                            selectedItem.length,
                            clickPosition  -- Position relative to the edited item
                        )
                    end
                }

                -- Debug: Show what portion we're displaying (commented for production)
                -- reaper.ShowConsoleMsg(string.format("[Waveform Display] File: %s\n", selectedItem.filePath or ""))
                -- reaper.ShowConsoleMsg(string.format("  StartOffset: %.3f, Length: %.3f\n",
                --     waveformOptions.startOffset, waveformOptions.displayLength))
                waveformData = globals.Waveform.drawWaveform(selectedItem.filePath, math.floor(width * 0.95), 120, waveformOptions)
            else
                -- Draw empty waveform box for missing files
                local draw_list = imgui.GetWindowDrawList(globals.ctx)
                local pos_x, pos_y = imgui.GetCursorScreenPos(globals.ctx)
                local waveformWidth = width * 0.95
                local waveformHeight = 120
                
                -- Draw background
                imgui.DrawList_AddRectFilled(draw_list,
                    pos_x, pos_y,
                    pos_x + waveformWidth, pos_y + waveformHeight,
                    0x1A1A1AFF
                )
                
                -- Draw border
                imgui.DrawList_AddRect(draw_list,
                    pos_x, pos_y,
                    pos_x + waveformWidth, pos_y + waveformHeight,
                    0x606060FF,
                    0, 0, 1
                )
                
                -- Draw "No waveform" text in center
                local text = fileExists and "Loading..." or "File not found"
                local text_size_x, text_size_y = imgui.CalcTextSize(globals.ctx, text)
                imgui.DrawList_AddText(draw_list,
                    pos_x + (waveformWidth - text_size_x) / 2,
                    pos_y + (waveformHeight - text_size_y) / 2,
                    0x808080FF,
                    text
                )
                
                imgui.Dummy(globals.ctx, waveformWidth, waveformHeight)
            end
            
            -- Audio playback controls
            imgui.Separator(globals.ctx)

            -- Add hint about spacebar and clicking
            imgui.PushStyleColor(globals.ctx, imgui.Col_Text, 0x808080FF)
            imgui.Text(globals.ctx, "Tip: Press [Space] to play/pause • Click waveform to set position")
            imgui.PopStyleColor(globals.ctx, 1)

            -- Play/Stop buttons
            if globals.audioPreview and globals.audioPreview.isPlaying and 
               globals.audioPreview.currentFile == selectedItem.filePath then
                -- Stop button
                if imgui.Button(globals.ctx, "■ Stop##" .. containerId, 80, 0) then
                    globals.Waveform.stopPlayback()
                end
                
                -- Show playback position
                if waveformData then
                    imgui.SameLine(globals.ctx)
                    local position = globals.audioPreview.position or 0
                    imgui.Text(globals.ctx, string.format("Position: %.2f / %.2f s", position, waveformData.length))
                end
            else
                -- Play button (disabled if file doesn't exist)
                if not fileExists then
                    imgui.PushStyleVar(globals.ctx, imgui.StyleVar_Alpha, 0.5)
                    imgui.Button(globals.ctx, "Play##" .. containerId, 80, 0)
                    imgui.PopStyleVar(globals.ctx, 1)
                    imgui.SameLine(globals.ctx)
                    imgui.Text(globals.ctx, "(File not available)")
                else
                    if imgui.Button(globals.ctx, "▶ Play##" .. containerId, 80, 0) then
                        globals.Waveform.startPlayback(
                            selectedItem.filePath,
                            selectedItem.startOffset or 0,
                            selectedItem.length
                        )
                    end
                end
            end
            
            -- Volume control for preview
            imgui.Text(globals.ctx, "Preview Volume:")
            imgui.PushItemWidth(globals.ctx, width * 0.6)
            
            if not globals.audioPreview then
                globals.audioPreview = { volume = 0.7 }
            end
            
            local rv, newVolume = imgui.SliderDouble(
                globals.ctx,
                "##PreviewVolume_" .. containerId,
                globals.audioPreview.volume,
                0.0,
                1.0,
                "%.2f"
            )
            if rv then
                globals.audioPreview.volume = newVolume
                if globals.Waveform and globals.Waveform.setPreviewVolume then
                    globals.Waveform.setPreviewVolume(newVolume)
                end
            end
            imgui.PopItemWidth(globals.ctx)

            -- Handle spacebar for play/pause
            -- Note: Key_Space constant is 32 (ASCII code for space)
            local spaceKey = globals.imgui.Key_Space or 32
            if fileExists and globals.imgui.IsKeyPressed(globals.ctx, spaceKey) then
                -- Check if this window has focus (use RootAndChildWindows flag if available)
                local focusFlag = globals.imgui.FocusedFlags_RootAndChildWindows or 3
                if globals.imgui.IsWindowFocused(globals.ctx, focusFlag) then
                    if globals.audioPreview and globals.audioPreview.isPlaying and
                       globals.audioPreview.currentFile == selectedItem.filePath then
                        -- Currently playing this file - stop it
                        globals.Waveform.stopPlayback()
                    else
                        -- Not playing - start playback
                        globals.Waveform.startPlayback(
                            selectedItem.filePath,
                            selectedItem.startOffset or 0,
                            selectedItem.length
                        )
                    end
                end
            end
        else
            imgui.Text(globals.ctx, "Waveform viewer not available")
        end
    end
    -- Container track volume slider
    imgui.Separator(globals.ctx)
    imgui.Text(globals.ctx, "Track Volume")
    imgui.SameLine(globals.ctx)
    globals.Utils.HelpMarker("Controls the volume of the container's track in Reaper. Affects all items in this container.")
    
    imgui.PushItemWidth(globals.ctx, width * 0.6)
    
    -- Ensure trackVolume is initialized
    if container.trackVolume == nil then
        container.trackVolume = Constants.DEFAULTS.CONTAINER_VOLUME_DEFAULT
    end
    
    -- Convert current dB to normalized
    local normalizedVolume = globals.Utils.dbToNormalizedRelative(container.trackVolume)
    
    local rv, newNormalizedVolume = imgui.SliderDouble(
        globals.ctx, 
        "##TrackVolume_" .. containerId, 
        normalizedVolume, 
        0.0,  -- Min normalized
        1.0,  -- Max normalized
        ""    -- No format
    )
    if rv then 
        local newVolumeDB = globals.Utils.normalizedToDbRelative(newNormalizedVolume)
        container.trackVolume = newVolumeDB
        -- Apply volume to track in real-time
        globals.Utils.setContainerTrackVolume(groupIndex, containerIndex, newVolumeDB)
    end
    
    -- Manual dB input field
    imgui.SameLine(globals.ctx)
    imgui.PushItemWidth(globals.ctx, 65)
    local displayValue = container.trackVolume <= -144 and -144 or container.trackVolume
    local rv2, manualDB = imgui.InputDouble(
        globals.ctx,
        "##TrackVolumeInput_" .. containerId,
        displayValue,
        0, 0,  -- step, step_fast (not used)
        "%.1f dB"
    )
    if rv2 then
        -- Clamp to valid range
        manualDB = math.max(Constants.AUDIO.VOLUME_RANGE_DB_MIN, 
                           math.min(Constants.AUDIO.VOLUME_RANGE_DB_MAX, manualDB))
        container.trackVolume = manualDB
        globals.Utils.setContainerTrackVolume(groupIndex, containerIndex, manualDB)
    end
    imgui.PopItemWidth(globals.ctx)

    -- Multi-Channel Configuration
    imgui.Separator(globals.ctx)
    imgui.Text(globals.ctx, "Multi-Channel Configuration")
    imgui.Separator(globals.ctx)

    imgui.Text(globals.ctx, "Channel Mode")
    imgui.SameLine(globals.ctx)
    globals.Utils.HelpMarker("Select channel configuration. Creates multiple child tracks for surround output.")

    -- Build dropdown items
    local channelModeItems = ""
    for i = 0, 3 do  -- Channel modes: Default, Quad, 5.0, 7.0
        local config = globals.Constants.CHANNEL_CONFIGS[i]
        if config then
            channelModeItems = channelModeItems .. config.name .. "\0"
        end
    end

    -- Initialize if needed
    if container.channelMode == nil then
        container.channelMode = 0
    end

    imgui.PushItemWidth(globals.ctx, width * 0.6)
    local rv, newMode = imgui.Combo(
        globals.ctx,
        "##ChannelMode_" .. containerId,
        container.channelMode,
        channelModeItems
    )
    if rv and newMode ~= container.channelMode then
        container.channelMode = newMode
        -- Reset channel settings when mode changes
        container.channelVolumes = {}
    end
    imgui.PopItemWidth(globals.ctx)

    -- Show channel-specific controls for multi-channel modes
    if container.channelMode > 0 then
        local config = globals.Constants.CHANNEL_CONFIGS[container.channelMode]

        -- Show variant dropdown if the mode has variants
        if config.hasVariants then
            imgui.Text(globals.ctx, "Channel Order")
            imgui.SameLine(globals.ctx)
            globals.Utils.HelpMarker("Select channel order standard (ITU/Dolby or SMPTE)")

            -- Build variant dropdown items
            local variantItems = ""
            for i = 0, 1 do  -- Always exactly 2 variants (0 and 1)
                if config.variants[i] then
                    variantItems = variantItems .. config.variants[i].name .. "\0"
                end
            end

            -- Initialize if needed
            if container.channelVariant == nil then
                container.channelVariant = 0
            end

            imgui.PushItemWidth(globals.ctx, width * 0.6)
            local rv, newVariant = imgui.Combo(
                globals.ctx,
                "##ChannelVariant_" .. containerId,
                container.channelVariant,
                variantItems
            )
            if rv then
                container.channelVariant = newVariant
                -- Reset channel settings when variant changes
                container.channelVolumes = {}
            end
            imgui.PopItemWidth(globals.ctx)
        end

        -- Get the active configuration (with variant if applicable)
        local activeConfig = config
        if config.hasVariants then
            activeConfig = config.variants[container.channelVariant or 0]
        end

        -- Channel-specific controls
        imgui.Text(globals.ctx, "Channel Settings:")

        -- Define fixed positions for alignment
        local labelPosX = 10      -- Starting position for labels
        local sliderPosX = 90     -- Fixed position for all sliders (after longest label)
        
        for i = 1, config.channels do
            local label = activeConfig.labels and activeConfig.labels[i] or ("Channel " .. i)

            imgui.PushID(globals.ctx, "channel_" .. i .. "_" .. containerId)
            
            -- Position and draw the label
            imgui.SetCursorPosX(globals.ctx, labelPosX)
            imgui.Text(globals.ctx, label .. ":")
            
            -- Initialize volume if needed
            if container.channelVolumes[i] == nil then
                container.channelVolumes[i] = 0.0
            end
            
            -- Move to same line and position the slider
            imgui.SameLine(globals.ctx)
            imgui.SetCursorPosX(globals.ctx, sliderPosX)
            
            -- Convert current dB to normalized
            local normalizedVolume = globals.Utils.dbToNormalizedRelative(container.channelVolumes[i])
            
            -- Volume control at fixed position
            imgui.PushItemWidth(globals.ctx, width * 0.5)
            local rv, newNormalizedVolume = imgui.SliderDouble(
                globals.ctx,
                "##Vol_" .. i,
                normalizedVolume,
                0.0,  -- Min normalized
                1.0,  -- Max normalized
                ""    -- No format
            )
            if rv then
                local newVolumeDB = globals.Utils.normalizedToDbRelative(newNormalizedVolume)
                container.channelVolumes[i] = newVolumeDB
                -- Apply volume to channel track in real-time
                globals.Utils.setChannelTrackVolume(groupIndex, containerIndex, i, newVolumeDB)
            end
            imgui.PopItemWidth(globals.ctx)
            
            -- Manual dB input field
            imgui.SameLine(globals.ctx)
            imgui.PushItemWidth(globals.ctx, 65)
            local displayValue = container.channelVolumes[i] <= -144 and -144 or container.channelVolumes[i]
            local rv2, manualDB = imgui.InputDouble(
                globals.ctx,
                "##VolInput_" .. i,
                displayValue,
                0, 0,  -- step, step_fast (not used)
                "%.1f dB"
            )
            if rv2 then
                -- Clamp to valid range
                manualDB = math.max(Constants.AUDIO.VOLUME_RANGE_DB_MIN, 
                                   math.min(Constants.AUDIO.VOLUME_RANGE_DB_MAX, manualDB))
                container.channelVolumes[i] = manualDB
                globals.Utils.setChannelTrackVolume(groupIndex, containerIndex, i, manualDB)
            end
            imgui.PopItemWidth(globals.ctx)
            
            imgui.PopID(globals.ctx)
        end
    end

    imgui.Separator(globals.ctx)

    -- "Override Parent Settings" checkbox
    local overrideParent = container.overrideParent
    local rv, newOverrideParent = imgui.Checkbox(globals.ctx, "Override Parent Settings##" .. containerId, overrideParent)
    imgui.SameLine(globals.ctx)
    globals.Utils.HelpMarker("Enable 'Override Parent Settings' to customize parameters for this container instead of inheriting from the group.")
    if rv then container.overrideParent = newOverrideParent end

    -- Display trigger/randomization settings or inheritance info
    if container.overrideParent then
        -- Display the trigger and randomization settings for this container
        globals.UI.displayTriggerSettings(container, containerId, width, false, groupIndex, containerIndex)
    end
end

return UI_Container