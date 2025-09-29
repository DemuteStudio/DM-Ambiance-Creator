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
function UI_Container.drawContainerPresetControls(groupIndex, containerIndex, width, presetDropdownWidth, buttonSpacing)
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

    -- Use parameters if provided, otherwise use defaults for backward compatibility
    local dropdownWidth = presetDropdownWidth or (width * 0.65)
    local spacing = buttonSpacing or 8

    -- Preset dropdown control
    imgui.PushItemWidth(globals.ctx, dropdownWidth)
    local rv, newSelectedContainerIndex = imgui.Combo(
        globals.ctx,
        "##ContainerPresetSelector" .. containerId,
        globals.selectedContainerPresetIndex[presetKey],
        containerPresetItems
    )
    if rv then
        globals.selectedContainerPresetIndex[presetKey] = newSelectedContainerIndex
    end
    imgui.PopItemWidth(globals.ctx)

    -- Load preset button: loads the selected preset into this container
    imgui.SameLine(globals.ctx, 0, spacing)
    if globals.Icons.createDownloadButton(globals.ctx, "loadContainer" .. containerId, "Load container preset")
        and globals.selectedContainerPresetIndex[presetKey] >= 0
        and globals.selectedContainerPresetIndex[presetKey] < #containerPresetList then

        local presetName = containerPresetList[globals.selectedContainerPresetIndex[presetKey] + 1]
        globals.Presets.loadContainerPreset(presetName, groupIndex, containerIndex)
    end

    -- Save preset button: opens a popup to save the current container as a preset
    imgui.SameLine(globals.ctx, 0, spacing)
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

    -- Container name and preset controls on same line for full width usage
    local nameWidth = width * 0.25
    local presetDropdownWidth = width * 0.5
    local buttonSpacing = 4

    -- Editable container name input field
    local containerName = container.name
    imgui.PushItemWidth(globals.ctx, nameWidth)
    local rv, newContainerName = imgui.InputText(globals.ctx, "Name##detail_" .. containerId, containerName)
    if rv then container.name = newContainerName end
    imgui.PopItemWidth(globals.ctx)

    -- Container preset controls on same line
    imgui.SameLine(globals.ctx, 0, 8)
    UI_Container.drawContainerPresetControls(groupIndex, containerIndex, width, presetDropdownWidth, buttonSpacing)

    -- Drop zone for importing items from timeline or Media Explorer
    UI_Container.drawImportDropZone(groupIndex, containerIndex, containerId, width)

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
                    imgui.PushID(globals.ctx, "item_" .. l)

                    local isSelected = (globals.selectedItemIndex[selectionKey] == l)

                    -- Calculate width for selectable to leave space for delete button
                    local selectableWidth = width * 0.80

                    -- Make item selectable with limited width
                    imgui.PushItemWidth(globals.ctx, selectableWidth)
                    -- Add visual indicator for currently playing item
                    local playingIndicator = ""
                    if globals.audioPreview and globals.audioPreview.isPlaying and
                       globals.audioPreview.currentFile == item.filePath then
                        playingIndicator = "▶ "
                    end
                    if imgui.Selectable(globals.ctx, playingIndicator .. l .. ". " .. item.name, isSelected, imgui.SelectableFlags_None, selectableWidth, 0) then
                        -- Store the previously selected item
                        local previouslySelectedIndex = globals.selectedItemIndex[selectionKey]

                        globals.selectedItemIndex[selectionKey] = l
                        -- Debug: clear cache when selecting new item
                        if globals.Waveform and item.filePath then
                            -- reaper.ShowConsoleMsg(string.format("[UI] Selected item with path: %s\n", item.filePath))
                            globals.Waveform.clearFileCache(item.filePath)
                        end

                        -- Stop any current playback when changing selection (regardless of autoplay setting)
                        if previouslySelectedIndex ~= l and globals.Waveform then
                            globals.Waveform.stopPlayback()
                        end

                        -- Auto-play if enabled and we actually changed selection
                        if globals.Settings.getSetting("waveformAutoPlayOnSelect") and previouslySelectedIndex ~= l then

                            -- Clear any saved position marker when auto-playing
                            if globals.audioPreview then
                                globals.audioPreview.clickedPosition = nil
                                globals.audioPreview.playbackStartPosition = nil
                                globals.audioPreview.currentFile = item.filePath
                            end

                            -- Start playback from the beginning
                            if globals.Waveform and item.filePath then
                                -- Check if file exists before trying to play
                                local file = io.open(item.filePath, "r")
                                if file then
                                    file:close()
                                    globals.Waveform.startPlayback(
                                        item.filePath,
                                        item.startOffset or 0,
                                        item.length,
                                        0  -- Start from beginning (not nil, explicitly 0)
                                    )
                                end
                            end
                        end
                    end
                    imgui.PopItemWidth(globals.ctx)

                    -- Delete button on same line with proper spacing
                    imgui.SameLine(globals.ctx, 0, 5)
                    imgui.PushStyleColor(globals.ctx, imgui.Col_Button, 0xFF0000FF)
                    if imgui.SmallButton(globals.ctx, "X") then
                        itemToDelete = l
                    end
                    imgui.PopStyleColor(globals.ctx, 1)

                    imgui.PopID(globals.ctx)
                end
                
                imgui.EndChild(globals.ctx)
            end
            
            -- Remove the item if the delete button was pressed
            if itemToDelete then
                -- Get the item data before deletion for cache clearing
                local itemToDeleteData = globals.groups[groupIndex].containers[containerIndex].items[itemToDelete]

                -- Directly modify the global container reference to ensure persistence
                table.remove(globals.groups[groupIndex].containers[containerIndex].items, itemToDelete)

                -- Keep the header expanded after deletion
                globals.containerExpandedStates[expandedStateKey] = true

                -- Reset selection if deleted item was selected
                if globals.selectedItemIndex[selectionKey] == itemToDelete then
                    globals.selectedItemIndex[selectionKey] = -1
                elseif globals.selectedItemIndex[selectionKey] > itemToDelete then
                    globals.selectedItemIndex[selectionKey] = globals.selectedItemIndex[selectionKey] - 1
                end

                -- Clear any related cached data for the deleted item
                if globals.Waveform and itemToDeleteData and itemToDeleteData.filePath then
                    globals.Waveform.clearFileCache(itemToDeleteData.filePath)
                end
            end

            -- Handle spacebar for play/pause (outside edit mode)
            if not isEditMode and globals.selectedItemIndex and globals.selectedItemIndex[selectionKey] and
               globals.selectedItemIndex[selectionKey] > 0 and
               globals.selectedItemIndex[selectionKey] <= #container.items then

                local selectedItem = container.items[globals.selectedItemIndex[selectionKey]]
                if selectedItem and selectedItem.filePath and selectedItem.filePath ~= "" then
                    local spaceKey = globals.imgui.Key_Space or 32
                    if globals.imgui.IsKeyPressed(globals.ctx, spaceKey) then
                        -- Check if this window has focus
                        local focusFlag = globals.imgui.FocusedFlags_RootAndChildWindows or 3
                        if globals.imgui.IsWindowFocused(globals.ctx, focusFlag) then
                            if globals.audioPreview and globals.audioPreview.isPlaying and
                               globals.audioPreview.currentFile == selectedItem.filePath then
                                -- Stop if playing the same item
                                globals.Waveform.stopPlayback()
                            else
                                -- Start playback if not playing or playing different item
                                -- Spacebar should always allow play/pause, regardless of autoplay setting
                                globals.Waveform.startPlayback(
                                    selectedItem.filePath,
                                    selectedItem.startOffset or 0,
                                    selectedItem.length,
                                    0 -- Start from beginning
                                )
                            end
                        end
                    end
                end
            end
        end
        
        imgui.PopID(globals.ctx)
    end
    
    -- Waveform Viewer Section (for selected imported items) - only visible in Edit Mode
    local selectionKey = groupIndex .. "_" .. containerIndex
    local editModeKey = groupIndex .. "_" .. containerIndex
    local isEditMode = globals.containerEditModes and globals.containerEditModes[editModeKey]

    if isEditMode and globals.selectedItemIndex and globals.selectedItemIndex[selectionKey] and
       globals.selectedItemIndex[selectionKey] > 0 and
       globals.selectedItemIndex[selectionKey] <= #container.items then
        
        local selectedItem = container.items[globals.selectedItemIndex[selectionKey]]
        
        imgui.Separator(globals.ctx)
        imgui.Text(globals.ctx, "Waveform Viewer")

        -- -- Add display options on the same line
        -- imgui.SameLine(globals.ctx)
        -- local _, showPeaks = imgui.Checkbox(globals.ctx, "Peaks##waveform",
        --     globals.waveformShowPeaks ~= false)
        -- globals.waveformShowPeaks = showPeaks
        
        -- imgui.SameLine(globals.ctx)
        -- local _, showRMS = imgui.Checkbox(globals.ctx, "RMS##waveform",
        --     globals.waveformShowRMS ~= false)
        -- globals.waveformShowRMS = showRMS

        imgui.Separator(globals.ctx)

        -- Display selected item info
        imgui.Text(globals.ctx, "Selected: " .. selectedItem.name)
        
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
                local durationText = selectedItem.length and string.format("Duration: %.2f s", selectedItem.length) or "Duration: Unknown"
                imgui.Text(globals.ctx, durationText)
                imgui.PushStyleColor(globals.ctx, imgui.Col_Text, 0x00FF00FF)
                -- imgui.Text(globals.ctx, "File: Available")
                imgui.PopStyleColor(globals.ctx, 1)
            else
                local durationText = selectedItem.length and string.format("Duration: %.2f s", selectedItem.length) or "Duration: Unknown"
                imgui.Text(globals.ctx, durationText)
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

        -- Gate detection controls (only show if file exists)
        if fileExists and filePathValid then
            imgui.Spacing(globals.ctx)

            -- Initialize gate parameters with defaults if not set
            if selectedItem.gateOpenThreshold == nil then selectedItem.gateOpenThreshold = -20 end
            if selectedItem.gateCloseThreshold == nil then selectedItem.gateCloseThreshold = -30 end
            if selectedItem.gateMinLength == nil then selectedItem.gateMinLength = 100 end
            if selectedItem.gateStartOffset == nil then selectedItem.gateStartOffset = 0 end
            if selectedItem.gateEndOffset == nil then selectedItem.gateEndOffset = 0 end

            -- Initialize area creation mode and parameters with defaults if not set
            if selectedItem.areaCreationMode == nil then selectedItem.areaCreationMode = 1 end -- 1: Auto Detect, 2: Split Count, 3: Split Time
            if selectedItem.splitCount == nil then selectedItem.splitCount = 5 end
            if selectedItem.splitDuration == nil then selectedItem.splitDuration = 2.0 end

            -- Area creation mode dropdown
            imgui.Text(globals.ctx, "Area Creation Mode:")
            imgui.SameLine(globals.ctx)
            imgui.PushItemWidth(globals.ctx, 120)
            local modeNames = "Auto Detect\0Split Count\0Split Time\0"
            local modeChanged, newMode = imgui.Combo(globals.ctx, "##AreaMode" .. containerId, selectedItem.areaCreationMode - 1, modeNames)
            if modeChanged then
                selectedItem.areaCreationMode = newMode + 1
            end
            imgui.PopItemWidth(globals.ctx)

            imgui.SameLine(globals.ctx)
            local buttonPressed = imgui.Button(globals.ctx, "Generate##" .. containerId, 80, 0)

            -- Parameters section based on selected mode
            local itemChanged = false

            if selectedItem.areaCreationMode == 1 then -- Auto Detect mode
                -- First line: Thresholds and Min Length
                imgui.PushItemWidth(globals.ctx, 80)
                local openChanged, newOpenThreshold = imgui.SliderDouble(globals.ctx, "Open##" .. containerId, selectedItem.gateOpenThreshold, -60, 0, "%.1f dB")
                if openChanged then
                    selectedItem.gateOpenThreshold = newOpenThreshold
                    itemChanged = true
                end

                imgui.SameLine(globals.ctx)
                local closeChanged, newCloseThreshold = imgui.SliderDouble(globals.ctx, "Close##" .. containerId, selectedItem.gateCloseThreshold, -60, 0, "%.1f dB")
                if closeChanged then
                    selectedItem.gateCloseThreshold = newCloseThreshold
                    itemChanged = true
                end

                imgui.SameLine(globals.ctx)
                local minLenChanged, newMinLength = imgui.SliderDouble(globals.ctx, "Min Length##" .. containerId, selectedItem.gateMinLength, 0, 5000, "%.0f ms")
                if minLenChanged then
                    selectedItem.gateMinLength = newMinLength
                    itemChanged = true
                end
                imgui.PopItemWidth(globals.ctx)

                -- Second line: Offsets
                imgui.Text(globals.ctx, "Offset:")
                imgui.SameLine(globals.ctx)
                imgui.PushItemWidth(globals.ctx, 60)
                local startOffsetChanged, newStartOffset = imgui.InputDouble(globals.ctx, "Start##" .. containerId, selectedItem.gateStartOffset, 0, 0, "%.0f ms")
                if startOffsetChanged then
                    selectedItem.gateStartOffset = newStartOffset
                    itemChanged = true
                end

                imgui.SameLine(globals.ctx)
                local endOffsetChanged, newEndOffset = imgui.InputDouble(globals.ctx, "End##" .. containerId, selectedItem.gateEndOffset, 0, 0, "%.0f ms")
                if endOffsetChanged then
                    selectedItem.gateEndOffset = newEndOffset
                    itemChanged = true
                end
                imgui.PopItemWidth(globals.ctx)

            elseif selectedItem.areaCreationMode == 2 then -- Split Count mode
                imgui.Text(globals.ctx, "Number of areas:")
                imgui.SameLine(globals.ctx)
                imgui.PushItemWidth(globals.ctx, 80)
                local countChanged, newCount = imgui.InputInt(globals.ctx, "##SplitCount" .. containerId, selectedItem.splitCount)
                if countChanged then
                    selectedItem.splitCount = math.max(1, math.min(100, newCount)) -- Clamp between 1 and 100
                    itemChanged = true
                end
                imgui.PopItemWidth(globals.ctx)

            elseif selectedItem.areaCreationMode == 3 then -- Split Time mode
                imgui.Text(globals.ctx, "Area duration:")
                imgui.SameLine(globals.ctx)
                imgui.PushItemWidth(globals.ctx, 80)
                local durationChanged, newDuration = imgui.InputDouble(globals.ctx, "##SplitDuration" .. containerId, selectedItem.splitDuration, 0.1, 1.0, "%.1f s")
                if durationChanged then
                    selectedItem.splitDuration = math.max(0.1, newDuration) -- Minimum 0.1 seconds
                    itemChanged = true
                end
                imgui.PopItemWidth(globals.ctx)
            end
            if buttonPressed then
                itemChanged = true
            end

            -- Auto-trigger area creation when any parameter changes
            if itemChanged and globals.Waveform then
                local itemKey = string.format("g%d_c%d_i%d", groupIndex, containerIndex, globals.selectedItemIndex[selectionKey])

                if buttonPressed then
                    -- Button was pressed: immediate area creation (no debouncing)
                    local success, numAreas = false, 0

                    if selectedItem.areaCreationMode == 1 then -- Auto Detect
                        if globals.Waveform.autoDetectAreas then
                            success, numAreas = globals.Waveform.autoDetectAreas(selectedItem, itemKey)
                            if success then
                                -- Store the parameters used for this detection
                                selectedItem.lastGateParams = {
                                    openThreshold = selectedItem.gateOpenThreshold,
                                    closeThreshold = selectedItem.gateCloseThreshold,
                                    minLength = selectedItem.gateMinLength,
                                    startOffset = selectedItem.gateStartOffset,
                                    endOffset = selectedItem.gateEndOffset
                                }
                            end
                        end
                    elseif selectedItem.areaCreationMode == 2 then -- Split Count
                        if globals.Waveform.splitCountAreas then
                            success, numAreas = globals.Waveform.splitCountAreas(selectedItem, itemKey, selectedItem.splitCount)
                        end
                    elseif selectedItem.areaCreationMode == 3 then -- Split Time
                        if globals.Waveform.splitTimeAreas then
                            success, numAreas = globals.Waveform.splitTimeAreas(selectedItem, itemKey, selectedItem.splitDuration)
                        end
                    end
                else
                    -- Parameter changed: use debouncing to avoid lag during slider dragging (only for Auto Detect mode)
                    if selectedItem.areaCreationMode == 1 and globals.Waveform.autoDetectAreas then
                        -- Initialize debounce system if needed
                        if not globals.gateDetectionDebounce then
                            globals.gateDetectionDebounce = {}
                        end

                        -- Store the parameters and timestamp for debouncing
                        globals.gateDetectionDebounce[itemKey] = {
                            timestamp = reaper.time_precise(),
                            params = {
                                openThreshold = selectedItem.gateOpenThreshold,
                                closeThreshold = selectedItem.gateCloseThreshold,
                                minLength = selectedItem.gateMinLength,
                                startOffset = selectedItem.gateStartOffset,
                                endOffset = selectedItem.gateEndOffset
                            },
                            item = selectedItem
                        }
                    end
                end
            end
        end
        
        -- Note: We don't clear the marker when switching files anymore
        -- Each file keeps its own marker until explicitly cleared with double-click
        -- The marker will only show on the file it belongs to (checked in drawWaveform)

        -- Draw waveform if the Waveform module is available
        if globals.Waveform then
            -- reaper.ShowConsoleMsg(string.format("[UI] Drawing waveform - fileExists: %s, path: %s\n",
                -- tostring(fileExists), selectedItem.filePath or "nil"))
            local waveformData = nil
            if fileExists then
                -- Create unique itemKey for this item
                local itemKey = string.format("g%d_c%d_i%d", groupIndex, containerIndex, globals.selectedItemIndex[selectionKey])

                -- Initialize waveform height if not set
                if not globals.waveformHeights then
                    globals.waveformHeights = {}
                end
                if not globals.waveformHeights[itemKey] then
                    globals.waveformHeights[itemKey] = 120  -- Default height
                end

                -- Ensure areas from the item are loaded into waveformAreas for display
                if selectedItem.areas and #selectedItem.areas > 0 then
                    globals.waveformAreas[itemKey] = selectedItem.areas
                end

                -- Enhanced waveform options
                local waveformOptions = {
                    useLogScale = false,   -- Disable logarithmic scaling for more accurate representation
                    amplifyQuiet = 3.0,    -- Amplification factor for quiet sounds
                    startOffset = selectedItem.startOffset or 0,  -- Start position in the file (D_STARTOFFS)
                    displayLength = selectedItem.length,          -- Length to display (D_LENGTH - edited duration)
                    verticalZoom = globals.waveformVerticalZoom or 1.0,  -- Vertical zoom factor
                    showPeaks = globals.waveformShowPeaks,        -- Show/hide peaks
                    showRMS = globals.waveformShowRMS,            -- Show/hide RMS
                    itemKey = itemKey,    -- Pass the unique item key
                    -- Callback when waveform is clicked
                    onWaveformClick = function(clickPosition, waveformData)
                        -- If clicking on a different file, clear the old marker first
                        if globals.audioPreview and globals.audioPreview.currentFile and
                           globals.audioPreview.currentFile ~= selectedItem.filePath then
                            -- Clear the marker from the previous file
                            globals.audioPreview.clickedPosition = nil
                            globals.audioPreview.playbackStartPosition = nil
                        end

                        -- Update currentFile to this file when setting a marker
                        if not globals.audioPreview then
                            globals.audioPreview = {}
                        end
                        globals.audioPreview.currentFile = selectedItem.filePath

                        -- Store the clicked position as the marker
                        globals.audioPreview.clickedPosition = clickPosition

                        -- Only start playback if auto-play is enabled
                        if globals.Settings.getSetting("waveformAutoPlayOnSelect") then
                            -- Start playback from the clicked position
                            globals.Waveform.startPlayback(
                                selectedItem.filePath,
                                selectedItem.startOffset or 0,
                                selectedItem.length,
                                clickPosition  -- Position relative to the edited item
                            )
                        else
                            -- Just set the marker without playing
                            -- Stop any current playback if playing
                            if globals.audioPreview.isPlaying then
                                globals.Waveform.stopPlayback()
                            end
                            -- The marker is already set above, nothing more to do
                        end
                    end
                }

                -- Debug: Show what portion we're displaying (commented for production)
                -- reaper.ShowConsoleMsg(string.format("[Waveform Display] File: %s\n", selectedItem.filePath or ""))
                -- reaper.ShowConsoleMsg(string.format("  StartOffset: %.3f, Length: %.3f\n",
                --     waveformOptions.startOffset, waveformOptions.displayLength))
                waveformData = globals.Waveform.drawWaveform(selectedItem.filePath, math.floor(width * 0.95), globals.waveformHeights[itemKey], waveformOptions)

                -- Add resize handle after waveform
                local draw_list = imgui.GetWindowDrawList(globals.ctx)
                local pos_x, pos_y = imgui.GetCursorScreenPos(globals.ctx)
                local handleHeight = 8
                local waveformWidth = width * 0.95

                -- Draw resize handle
                imgui.DrawList_AddRectFilled(draw_list,
                    pos_x, pos_y,
                    pos_x + waveformWidth, pos_y + handleHeight,
                    0x606060FF
                )

                -- Make resize handle interactive
                imgui.InvisibleButton(globals.ctx, "WaveformResize##" .. itemKey, waveformWidth, handleHeight)

                if imgui.IsItemActive(globals.ctx) and imgui.IsMouseDragging(globals.ctx, 0) then
                    local _, mouseY = imgui.GetMouseDragDelta(globals.ctx, 0)
                    local newHeight = math.max(60, math.min(400, globals.waveformHeights[itemKey] + mouseY))
                    globals.waveformHeights[itemKey] = newHeight
                    imgui.ResetMouseDragDelta(globals.ctx, 0)
                end

                -- Change cursor when hovering over resize handle
                if imgui.IsItemHovered(globals.ctx) then
                    imgui.SetMouseCursor(globals.ctx, imgui.MouseCursor_ResizeNS)
                end

                -- Synchronize areas from waveformAreas back to the item after any changes
                if globals.waveformAreas[itemKey] then
                    selectedItem.areas = globals.waveformAreas[itemKey]
                else
                    selectedItem.areas = nil
                end
            else
                -- Create unique itemKey for this item even if file doesn't exist
                local itemKey = string.format("g%d_c%d_i%d", groupIndex, containerIndex, globals.selectedItemIndex[selectionKey])

                -- Initialize waveform height if not set
                if not globals.waveformHeights then
                    globals.waveformHeights = {}
                end
                if not globals.waveformHeights[itemKey] then
                    globals.waveformHeights[itemKey] = 120  -- Default height
                end

                -- Draw empty waveform box for missing files
                local draw_list = imgui.GetWindowDrawList(globals.ctx)
                local pos_x, pos_y = imgui.GetCursorScreenPos(globals.ctx)
                local waveformWidth = width * 0.95
                local waveformHeight = globals.waveformHeights[itemKey]

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

                -- Add resize handle after empty waveform box
                local pos_x2, pos_y2 = imgui.GetCursorScreenPos(globals.ctx)
                local handleHeight = 8

                -- Draw resize handle
                imgui.DrawList_AddRectFilled(draw_list,
                    pos_x2, pos_y2,
                    pos_x2 + waveformWidth, pos_y2 + handleHeight,
                    0x606060FF
                )

                -- Make resize handle interactive
                imgui.InvisibleButton(globals.ctx, "WaveformResize##" .. itemKey, waveformWidth, handleHeight)

                if imgui.IsItemActive(globals.ctx) and imgui.IsMouseDragging(globals.ctx, 0) then
                    local _, mouseY = imgui.GetMouseDragDelta(globals.ctx, 0)
                    local newHeight = math.max(60, math.min(400, globals.waveformHeights[itemKey] + mouseY))
                    globals.waveformHeights[itemKey] = newHeight
                    imgui.ResetMouseDragDelta(globals.ctx, 0)
                end

                -- Change cursor when hovering over resize handle
                if imgui.IsItemHovered(globals.ctx) then
                    imgui.SetMouseCursor(globals.ctx, imgui.MouseCursor_ResizeNS)
                end
            end
            
            -- Audio playback controls
            imgui.Separator(globals.ctx)

            -- Add hint about spacebar and clicking
            imgui.PushStyleColor(globals.ctx, imgui.Col_Text, 0x808080FF)
            if globals.Settings.getSetting("waveformAutoPlayOnSelect") then
                imgui.Text(globals.ctx, "Tip: [Space] play/pause • Click to set position & play • Double-click to reset")
            else
                imgui.Text(globals.ctx, "Tip: [Space] play/pause • Click to set position • Double-click to reset")
            end
            imgui.PopStyleColor(globals.ctx, 1)

            -- Initialize audio preview volume if needed
            if not globals.audioPreview then
                globals.audioPreview = { volume = 0.7 }
            end

            -- Play/Stop buttons
            if globals.audioPreview and globals.audioPreview.isPlaying and
               globals.audioPreview.currentFile == selectedItem.filePath then
                -- Stop button
                if imgui.Button(globals.ctx, "■ Stop##" .. containerId, 80, 0) then
                    globals.Waveform.stopPlayback()
                end

                -- Volume control on same line as stop button
                imgui.SameLine(globals.ctx)
                imgui.PushItemWidth(globals.ctx, 100)
                local rv, newVolume = imgui.SliderDouble(
                    globals.ctx,
                    "##PreviewVolume_" .. containerId,
                    globals.audioPreview.volume,
                    0.0,
                    1.0,
                    "Vol: %.2f"
                )
                if rv then
                    globals.audioPreview.volume = newVolume
                    if globals.Waveform and globals.Waveform.setPreviewVolume then
                        globals.Waveform.setPreviewVolume(newVolume)
                    end
                end
                imgui.PopItemWidth(globals.ctx)

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
                        -- Use the saved clicked position if it exists, otherwise start from beginning
                        local startPosition = nil
                        if globals.audioPreview and globals.audioPreview.clickedPosition and
                           globals.audioPreview.currentFile == selectedItem.filePath then
                            startPosition = globals.audioPreview.clickedPosition
                        end

                        globals.Waveform.startPlayback(
                            selectedItem.filePath,
                            selectedItem.startOffset or 0,
                            selectedItem.length,
                            startPosition  -- Use saved position if available
                        )
                    end

                    -- Volume control on same line as play button
                    imgui.SameLine(globals.ctx)
                    imgui.PushItemWidth(globals.ctx, 100)
                    local rv, newVolume = imgui.SliderDouble(
                        globals.ctx,
                        "##PreviewVolume_" .. containerId,
                        globals.audioPreview.volume,
                        0.0,
                        1.0,
                        "Vol: %.2f"
                    )
                    if rv then
                        globals.audioPreview.volume = newVolume
                        if globals.Waveform and globals.Waveform.setPreviewVolume then
                            globals.Waveform.setPreviewVolume(newVolume)
                        end
                    end
                    imgui.PopItemWidth(globals.ctx)
                end
            end

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
                        -- Use the saved clicked position if it exists
                        local startPosition = nil
                        if globals.audioPreview and globals.audioPreview.clickedPosition and
                           globals.audioPreview.currentFile == selectedItem.filePath then
                            startPosition = globals.audioPreview.clickedPosition
                        end

                        globals.Waveform.startPlayback(
                            selectedItem.filePath,
                            selectedItem.startOffset or 0,
                            selectedItem.length,
                            startPosition  -- Use saved position if available
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

    -- Ensure trackVolume is initialized
    if container.trackVolume == nil then
        container.trackVolume = Constants.DEFAULTS.CONTAINER_VOLUME_DEFAULT
    end

    -- Convert current dB to normalized
    local normalizedVolume = globals.Utils.dbToNormalizedRelative(container.trackVolume)

    -- Layout: slider and input field occupy full width (100%)
    local inputFieldWidth = 85  -- Fixed width for dB input
    local sliderWidth = width - inputFieldWidth - 8  -- Remaining space minus spacing

    imgui.PushItemWidth(globals.ctx, sliderWidth)
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
        -- Apply volume to track in real-time (no regeneration needed)
        globals.Utils.setContainerTrackVolume(groupIndex, containerIndex, newVolumeDB)
    end
    imgui.PopItemWidth(globals.ctx)

    -- Manual dB input field with remaining space
    imgui.SameLine(globals.ctx, 0, 8)
    imgui.PushItemWidth(globals.ctx, inputFieldWidth)
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
        -- Apply volume to track in real-time (no regeneration needed)
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

    imgui.PushItemWidth(globals.ctx, width * 0.95)  -- Use 95% of width for better visual alignment
    local rv, newMode = imgui.Combo(
        globals.ctx,
        "##ChannelMode_" .. containerId,
        container.channelMode,
        channelModeItems
    )
    if rv and newMode ~= container.channelMode then
        container.channelMode = newMode
        container.needsRegeneration = true
        -- Reset channel settings when mode changes
        container.channelVolumes = {}
        -- Force disable pan randomization when switching to multichannel mode
        if newMode > 0 then
            container.randomizePan = false
        end
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

            imgui.PushItemWidth(globals.ctx, width * 0.95)  -- Match channel mode width
            local rv, newVariant = imgui.Combo(
                globals.ctx,
                "##ChannelVariant_" .. containerId,
                container.channelVariant,
                variantItems
            )
            if rv then
                container.channelVariant = newVariant
                container.needsRegeneration = true
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

        -- Calculate optimal layout for 100% width usage
        local labelWidth = 80            -- Fixed width for labels
        local inputWidth = 85            -- Fixed width for dB input
        local sliderWidth = width - labelWidth - inputWidth - 16  -- Remaining space minus spacing

        for i = 1, config.channels do
            local label = activeConfig.labels and activeConfig.labels[i] or ("Channel " .. i)

            imgui.PushID(globals.ctx, "channel_" .. i .. "_" .. containerId)

            -- Label with fixed width
            imgui.Text(globals.ctx, label .. ":")

            -- Initialize volume if needed
            if container.channelVolumes[i] == nil then
                container.channelVolumes[i] = 0.0
            end

            -- Volume slider on same line with optimized spacing
            imgui.SameLine(globals.ctx, labelWidth)

            -- Convert current dB to normalized
            local normalizedVolume = globals.Utils.dbToNormalizedRelative(container.channelVolumes[i])

            -- Volume control with optimized width
            imgui.PushItemWidth(globals.ctx, sliderWidth)
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

            -- Manual dB input field with consistent spacing
            imgui.SameLine(globals.ctx, 0, 8)
            imgui.PushItemWidth(globals.ctx, inputWidth)
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
    if rv then
        container.overrideParent = newOverrideParent
        container.needsRegeneration = true
    end

    -- Display trigger/randomization settings or inheritance info
    if container.overrideParent then
        -- Display the trigger and randomization settings for this container
        globals.UI.displayTriggerSettings(container, containerId, width, false, groupIndex, containerIndex)
    end
end

-- Draw import drop zone for importing items from timeline or Media Explorer
function UI_Container.drawImportDropZone(groupIndex, containerIndex, containerId, width)
    local container = globals.groups[groupIndex].containers[containerIndex]
    local dropZoneHeight = 60
    local buttonWidth = 90
    local dropZoneWidth = width * 0.75 - buttonWidth - 12 -- Optimized space usage

    -- Get current cursor position for drawing
    local cursorX, cursorY = imgui.GetCursorScreenPos(globals.ctx)
    local drawList = imgui.GetWindowDrawList(globals.ctx)

    -- Calculate drop zone bounds
    local min_x = cursorX
    local min_y = cursorY
    local max_x = min_x + dropZoneWidth
    local max_y = min_y + dropZoneHeight

    -- Colors for the drop zone
    local backgroundColor = 0x22222222
    local borderColor = 0x77777777
    local hoverColor = 0x44444444
    local hoverBorderColor = 0xAAAAAAAA

    -- Create an invisible button for the drop zone area
    imgui.SetCursorScreenPos(globals.ctx, min_x, min_y)
    local isHovered = imgui.InvisibleButton(globals.ctx, "DropZone##" .. containerId, dropZoneWidth, dropZoneHeight)
    local isClicked = imgui.IsItemClicked(globals.ctx)

    -- Check if we're in a drag-drop operation
    local isDragActive = false
    local currentBgColor = backgroundColor
    local currentBorderColor = borderColor

    if isHovered then
        currentBgColor = hoverColor
        currentBorderColor = hoverBorderColor
    end

    -- Draw the drop zone background and border
    imgui.DrawList_AddRectFilled(drawList, min_x, min_y, max_x, max_y, currentBgColor)
    imgui.DrawList_AddRect(drawList, min_x, min_y, max_x, max_y, currentBorderColor, 4, 0, 2)

    -- Handle drag and drop
    if imgui.BeginDragDropTarget(globals.ctx) then
        isDragActive = true
        -- Highlight the drop zone when hovering with valid payload
        imgui.DrawList_AddRectFilled(drawList, min_x, min_y, max_x, max_y, 0x44AA4444)
        imgui.DrawList_AddRect(drawList, min_x, min_y, max_x, max_y, 0xAAAAAAAA, 4, 0, 3)

        -- Handle external file drops (from Media Explorer, Windows Explorer, etc.)
        local files = {}

        -- Check if there are files to be dropped
        local hasFiles = imgui.GetDragDropPayloadFile(globals.ctx, 0)

        -- Only process on actual drop completion (when mouse is released)
        if hasFiles and imgui.IsMouseReleased(globals.ctx, 0) then
            -- Get all dropped files using correct syntax
            local fileIndex = 0
            while true do
                local retval, filePath = imgui.GetDragDropPayloadFile(globals.ctx, fileIndex)

                if not retval or not filePath or filePath == "" then
                    break
                end

                table.insert(files, filePath)
                fileIndex = fileIndex + 1
            end

            -- Process dropped files
            if #files > 0 then
                local items = globals.Items.processDroppedFiles(files)
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
            end
        elseif not hasFiles and imgui.IsMouseReleased(globals.ctx, 0) then
            -- If no files, check for timeline items on drop completion
            -- This handles drops from REAPER timeline
            local timelineItems = globals.Items.getSelectedItems()
            if #timelineItems > 0 then
                for _, item in ipairs(timelineItems) do
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
            end
        end

        imgui.EndDragDropTarget(globals.ctx)
    end

    -- Handle click on drop zone to import selected timeline items
    if isClicked and not isDragActive then
        local timelineItems = globals.Items.getSelectedItems()
        if #timelineItems > 0 then
            for _, item in ipairs(timelineItems) do
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
        end
    end

    -- Add text centered in the drop zone
    local textLabel = "Drag files here or click to import selected timeline items"
    local textSizeX, textSizeY = imgui.CalcTextSize(globals.ctx, textLabel)
    local textX = min_x + (dropZoneWidth - textSizeX) / 2
    local textY = min_y + (dropZoneHeight - textSizeY) / 2

    -- Draw the text
    imgui.DrawList_AddText(drawList, textX, textY, 0xCCCCCCCC, textLabel)

    -- Add Media Explorer button next to the drop zone
    imgui.SameLine(globals.ctx, 0, 8) -- Consistent 8px margin
    if imgui.Button(globals.ctx, "Media\nExplorer##" .. containerId, buttonWidth, dropZoneHeight) then
        reaper.Main_OnCommand(50124, 0) -- Open Media Explorer
    end

    -- Add buttons below the drop zone
    imgui.Spacing(globals.ctx)

    -- Build All Peaks button
    if imgui.Button(globals.ctx, "Build All Peaks##" .. containerId) then
        local generated = globals.Waveform.generatePeaksForContainer(container)
    end

    -- Clear All Peaks button
    imgui.SameLine(globals.ctx)
    if imgui.Button(globals.ctx, "Clear All Peaks##" .. containerId) then
        globals.Waveform.clearContainerCache(container)
    end

    -- Edit Mode toggle button
    imgui.SameLine(globals.ctx)
    imgui.Text(globals.ctx, " | ")
    imgui.SameLine(globals.ctx)

    -- Initialize edit mode state if not set
    if not globals.containerEditModes then
        globals.containerEditModes = {}
    end
    local editModeKey = groupIndex .. "_" .. containerIndex
    if globals.containerEditModes[editModeKey] == nil then
        globals.containerEditModes[editModeKey] = false
    end

    local isEditMode = globals.containerEditModes[editModeKey]
    local buttonLabel = isEditMode and "Exit Edit Mode##" .. containerId or "Edit Mode##" .. containerId
    local buttonColor = isEditMode and 0xFF4444FF or 0x44AA44FF

    imgui.PushStyleColor(globals.ctx, imgui.Col_Button, buttonColor)
    if imgui.Button(globals.ctx, buttonLabel) then
        -- If we're exiting edit mode (going from true to false), stop any playing audio
        if isEditMode then
            globals.Waveform.stopPlayback()
        end
        globals.containerEditModes[editModeKey] = not isEditMode
    end
    imgui.PopStyleColor(globals.ctx, 1)
end

return UI_Container