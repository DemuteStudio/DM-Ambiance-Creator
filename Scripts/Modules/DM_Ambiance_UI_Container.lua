--[[
@version 1.5
@noindex
--]]

local UI_Container = {}
local globals = {}
local Constants = require("DM_Ambiance_Constants")
local imgui = nil  -- Will be initialized from globals

-- Get script path for loading sub-modules
local info = debug.getinfo(1, "S")
local modulePath = info.source:match[[^@?(.*[\\/])[^\\/]-$]]

-- Load sub-modules
local Container_ChannelConfig = dofile(modulePath .. "UI/Container_ChannelConfig.lua")

-- Initialize the module with global variables from the main script
function UI_Container.initModule(g)
    if not g then
        error("UI_Container.initModule: globals parameter is required")
    end
    globals = g
    imgui = globals.imgui  -- Get imgui reference from globals

    -- Initialize sub-modules
    Container_ChannelConfig.initModule(g)

    -- Initialize container expanded states if not already set
    if not globals.containerExpandedStates then
        globals.containerExpandedStates = {}
    end
end

-- Display the preset controls for a specific container (load/save container presets)
function UI_Container.drawContainerPresetControls(groupPath, containerIndex, width, presetDropdownWidth, buttonSpacing)
    local group = globals.Structures.getItemFromPath(groupPath)
    if not group or not group.containers or not group.containers[containerIndex] then
        return
    end

    local container = group.containers[containerIndex]
    local pathStr = globals.Utils.pathToString(groupPath)
    local groupId = "group" .. pathStr
    local containerId = groupId .. "_container" .. containerIndex
    local presetKey = globals.Structures.makeContainerKey(groupPath, containerIndex)

    -- Initialize the selected preset index for this container if not already set
    if not globals.selectedContainerPresetIndex[presetKey] then
        globals.selectedContainerPresetIndex[presetKey] = -1
    end

    -- Initialize search query for this container if not already set
    if not globals.containerPresetSearchQuery then
        globals.containerPresetSearchQuery = {}
    end
    if not globals.containerPresetSearchQuery[presetKey] then
        globals.containerPresetSearchQuery[presetKey] = ""
    end

    -- Get a sanitized group name for folder structure (replace non-alphanumeric characters with underscores)
    local groupName = group.name:gsub("[^%w]", "_")

    -- Get the list of available container presets (shared across all groups)
    local containerPresetList = globals.Presets.listPresets("Containers")

    -- Use parameters if provided, otherwise use defaults for backward compatibility
    local dropdownWidth = presetDropdownWidth or (width * 0.65)
    local spacing = buttonSpacing or 8

    -- Use searchable combo box
    local changed, newIndex, newSearchQuery = globals.Utils.searchableCombo(
        "##ContainerPresetSelector" .. containerId,
        globals.selectedContainerPresetIndex[presetKey],
        containerPresetList,
        globals.containerPresetSearchQuery[presetKey],
        dropdownWidth
    )

    if changed then
        globals.selectedContainerPresetIndex[presetKey] = newIndex
    end

    globals.containerPresetSearchQuery[presetKey] = newSearchQuery

    -- Load preset button: loads the selected preset into this container
    imgui.SameLine(globals.ctx, 0, spacing)
    if globals.Icons.createDownloadButton(globals.ctx, "loadContainer" .. containerId, "Load container preset")
        and globals.selectedContainerPresetIndex[presetKey] >= 0
        and globals.selectedContainerPresetIndex[presetKey] < #containerPresetList then

        local presetName = containerPresetList[globals.selectedContainerPresetIndex[presetKey] + 1]
        globals.Presets.loadContainerPresetByPath(presetName, groupPath, containerIndex)
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
            globals.newContainerPresetName = container.name
            globals.currentSaveContainerGroup = groupPath
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
            if globals.Presets.saveContainerPresetByPath(
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
function UI_Container.displayContainerSettings(groupPath, containerIndex, width)
    local group = globals.Structures.getItemFromPath(groupPath)
    if not group or not group.containers or not group.containers[containerIndex] then
        return
    end

    local container = group.containers[containerIndex]
    local pathStr = globals.Utils.pathToString(groupPath)
    local groupId = "group" .. pathStr
    local containerId = groupId .. "_container" .. containerIndex

    -- Retroactive channel count calculation for old items
    for _, item in ipairs(container.items) do
        if not item.numChannels and item.filePath and item.filePath ~= "" then
            local source = reaper.PCM_Source_CreateFromFile(item.filePath)
            if source then
                item.numChannels = math.floor(reaper.GetMediaSourceNumChannels(source) or 2)
                reaper.PCM_Source_Destroy(source)
            end
        end
    end

    -- Sync channel volumes from tracks if in multichannel mode
    if container.channelMode and container.channelMode > 0 then
        globals.Utils.syncChannelVolumesFromTracks(groupPath, containerIndex)
    end

    -- Sync container volume, name, mute, and solo from track
    globals.Utils.syncContainerVolumeFromTrack(groupPath, containerIndex)
    globals.Utils.syncContainerNameFromTrack(groupPath, containerIndex)
    globals.Utils.syncContainerMuteFromTrack(groupPath, containerIndex)
    globals.Utils.syncContainerSoloFromTrack(groupPath, containerIndex)

    -- Panel title showing which container is being edited
    imgui.Text(globals.ctx, "Container Settings: " .. container.name)
    imgui.Separator(globals.ctx)

    -- Container name and preset controls on same line for full width usage
    local nameWidth = width * 0.25
    local presetDropdownWidth = width * 0.5
    local buttonSpacing = 4

    -- Editable container name input field
    imgui.PushItemWidth(globals.ctx, nameWidth)
    local rv, newContainerName = globals.UndoWrappers.InputText(globals.ctx, "Name##detail_" .. containerId, container.name)
    if rv then
        container.name = newContainerName
        -- Update track name in REAPER in real-time
        globals.Utils.setContainerTrackName(groupPath, containerIndex, newContainerName)
    end
    imgui.PopItemWidth(globals.ctx)

    -- Container preset controls on same line
    imgui.SameLine(globals.ctx, 0, 8)
    UI_Container.drawContainerPresetControls(groupPath, containerIndex, width, presetDropdownWidth, buttonSpacing)

    -- Drop zone for importing items from timeline or Media Explorer
    UI_Container.drawImportDropZone(groupPath, containerIndex, containerId, width)

    -- Display imported items with persistent state
    if #container.items > 0 then
        -- Create unique key for this container's expanded state and selection
        local expandedStateKey = globals.Structures.makeContainerKey(groupPath, containerIndex) .. "_items"
        local selectionKey = globals.Structures.makeContainerKey(groupPath, containerIndex)

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

        -- If we need to maintain the open state, set it before the header
        if globals.containerExpandedStates[expandedStateKey] then
            imgui.SetNextItemOpen(globals.ctx, true)
        end

        -- Create header with stable ID (using unique label instead of PushID)
        local headerLabel = "Imported items (" .. #container.items .. ")##" .. containerId .. "_items"
        local wasExpanded = globals.containerExpandedStates[expandedStateKey]
        local isExpanded = imgui.CollapsingHeader(globals.ctx, headerLabel)

        -- Track state changes
        if isExpanded ~= wasExpanded then
            globals.containerExpandedStates[expandedStateKey] = isExpanded
        end

        -- Show content if expanded
        if isExpanded then
            local itemToDelete = nil

            -- Use BeginGroup for items list to avoid nested child window conflicts
            -- The scrolling is already handled by the parent RightPanel child window
            local scrollbarWidth = 20  -- Approximate scrollbar width
            local listWidth = width - scrollbarWidth

            imgui.BeginGroup(globals.ctx)

            -- List all imported items as selectable items
            for l, item in ipairs(container.items) do
                    imgui.PushID(globals.ctx, "item_" .. l)

                    local isSelected = (globals.selectedItemIndex[selectionKey] == l)

                    -- Calculate width for selectable to leave space for buttons
                    local buttonWidth = 20  -- SmallButton approximate width
                    local spacing = 5  -- Spacing between elements
                    local buttonsSpace = (buttonWidth * 2) + (spacing * 3)  -- 2 buttons + spacing
                    local selectableWidth = listWidth - buttonsSpace

                    -- Make item selectable with limited width
                    imgui.PushItemWidth(globals.ctx, selectableWidth)
                    -- Add visual indicator for currently playing item
                    local playingIndicator = ""
                    if globals.audioPreview and globals.audioPreview.isPlaying and
                       globals.audioPreview.currentFile == item.filePath then
                        playingIndicator = "▶ "
                    end
                    -- Display channel count next to item name
                    local channelInfo = ""
                    if item.numChannels then
                        channelInfo = " (" .. item.numChannels .. " ch)"
                    end
                    if imgui.Selectable(globals.ctx, playingIndicator .. l .. ". " .. item.name .. channelInfo, isSelected, imgui.SelectableFlags_None, selectableWidth, 0) then
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

                            -- Reset marker position to beginning when selecting a new item
                            if globals.audioPreview then
                                globals.audioPreview.clickedPosition = nil
                                globals.audioPreview.playbackStartPosition = nil
                                globals.audioPreview.position = item.startOffset or 0
                                globals.audioPreview.currentFile = item.filePath
                            end
                        end

                        -- Auto-play if enabled and we actually changed selection
                        if globals.Settings.getSetting("waveformAutoPlayOnSelect") and previouslySelectedIndex ~= l then

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

                    -- Routing button (always visible)
                    imgui.SameLine(globals.ctx, 0, 5)
                    if imgui.SmallButton(globals.ctx, "⇄##route" .. l) then
                        -- Store item index to trigger popup in main loop
                        globals.routingPopupItemIndex = l
                        globals.routingPopupGroupPath = groupPath
                        globals.routingPopupContainerIndex = containerIndex
                        globals.routingPopupOpened = nil  -- Reset flag to trigger OpenPopup
                    end

                    -- Delete button on same line with proper spacing
                    imgui.SameLine(globals.ctx, 0, 5)
                    imgui.PushStyleColor(globals.ctx, imgui.Col_Button, 0xFF0000FF)
                    if imgui.SmallButton(globals.ctx, "X") then
                        itemToDelete = l
                    end
                    imgui.PopStyleColor(globals.ctx, 1)

                    imgui.PopID(globals.ctx)
                end

            -- End group (no visibility check needed for groups)
            imgui.EndGroup(globals.ctx)

            -- Remove the item if the delete button was pressed
            if itemToDelete then
                -- Get the item data before deletion for cache clearing
                local itemToDeleteData = container.items[itemToDelete]

                -- Capture state before deletion
                globals.History.captureState("Delete item from container")

                -- Directly modify the container reference to ensure persistence
                table.remove(container.items, itemToDelete)

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

        end
    end

    -- Waveform Viewer Section (for selected imported items) - only visible in Edit Mode
    local selectionKey = globals.Structures.makeContainerKey(groupPath, containerIndex)
    local editModeKey = globals.Structures.makeContainerKey(groupPath, containerIndex)
    local isEditMode = globals.containerEditModes and globals.containerEditModes[editModeKey]

    -- Handle spacebar for play/pause when NOT in edit mode (in the item list)
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
                    -- Check if currently playing
                    local isCurrentlyPlaying = globals.audioPreview and
                                              globals.audioPreview.isPlaying and
                                              globals.audioPreview.currentFile == selectedItem.filePath

                    if isCurrentlyPlaying then
                        -- Currently playing this file - stop it
                        globals.Waveform.stopPlayback()
                    else
                        -- Not playing - start playback
                        -- Use the saved clicked position if it exists, otherwise start from beginning
                        local startPosition = 0  -- Default to beginning
                        if globals.audioPreview and
                           globals.audioPreview.clickedPosition and
                           globals.audioPreview.currentFile == selectedItem.filePath then
                            startPosition = globals.audioPreview.clickedPosition
                        end

                        globals.Waveform.startPlayback(
                            selectedItem.filePath,
                            selectedItem.startOffset or 0,
                            selectedItem.length,
                            startPosition
                        )
                    end
                end
            end
        end
    end

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

        -- Display file status (item info now shown in waveform)
        if filePathValid then
            if not fileExists then
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
            local modeChanged, newMode = globals.UndoWrappers.Combo(globals.ctx, "##AreaMode" .. containerId, selectedItem.areaCreationMode - 1, modeNames)
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
                local openChanged, newOpenThreshold = globals.SliderEnhanced.SliderDouble({
                    id = "Open##" .. containerId,
                    value = selectedItem.gateOpenThreshold,
                    min = -60,
                    max = 0,
                    defaultValue = -40.0,  -- Typical gate open threshold
                    format = "%.1f dB",
                    width = 80
                })
                if openChanged then
                    selectedItem.gateOpenThreshold = newOpenThreshold
                    itemChanged = true
                end

                imgui.SameLine(globals.ctx)
                local closeChanged, newCloseThreshold = globals.SliderEnhanced.SliderDouble({
                    id = "Close##" .. containerId,
                    value = selectedItem.gateCloseThreshold,
                    min = -60,
                    max = 0,
                    defaultValue = -50.0,  -- Typical gate close threshold
                    format = "%.1f dB",
                    width = 80
                })
                if closeChanged then
                    selectedItem.gateCloseThreshold = newCloseThreshold
                    itemChanged = true
                end

                imgui.SameLine(globals.ctx)
                local minLenChanged, newMinLength = globals.SliderEnhanced.SliderDouble({
                    id = "Min Length##" .. containerId,
                    value = selectedItem.gateMinLength,
                    min = 0,
                    max = 5000,
                    defaultValue = 100.0,  -- Typical minimum gate length
                    format = "%.0f ms",
                    width = 80
                })
                if minLenChanged then
                    selectedItem.gateMinLength = newMinLength
                    itemChanged = true
                end

                -- Second line: Offsets
                imgui.Text(globals.ctx, "Offset:")
                imgui.SameLine(globals.ctx)
                imgui.PushItemWidth(globals.ctx, 60)
                local startOffsetChanged, newStartOffset = globals.UndoWrappers.InputDouble(globals.ctx, "Start##" .. containerId, selectedItem.gateStartOffset, 0, 0, "%.0f ms")
                if startOffsetChanged then
                    selectedItem.gateStartOffset = newStartOffset
                    itemChanged = true
                end

                imgui.SameLine(globals.ctx)
                local endOffsetChanged, newEndOffset = globals.UndoWrappers.InputDouble(globals.ctx, "End##" .. containerId, selectedItem.gateEndOffset, 0, 0, "%.0f ms")
                if endOffsetChanged then
                    selectedItem.gateEndOffset = newEndOffset
                    itemChanged = true
                end
                imgui.PopItemWidth(globals.ctx)

            elseif selectedItem.areaCreationMode == 2 then -- Split Count mode
                imgui.Text(globals.ctx, "Number of areas:")
                imgui.SameLine(globals.ctx)
                imgui.PushItemWidth(globals.ctx, 80)
                local countChanged, newCount = globals.UndoWrappers.InputInt(globals.ctx, "##SplitCount" .. containerId, selectedItem.splitCount)
                if countChanged then
                    selectedItem.splitCount = math.max(1, math.min(100, newCount)) -- Clamp between 1 and 100
                    itemChanged = true
                end
                imgui.PopItemWidth(globals.ctx)

            elseif selectedItem.areaCreationMode == 3 then -- Split Time mode
                imgui.Text(globals.ctx, "Area duration:")
                imgui.SameLine(globals.ctx)
                imgui.PushItemWidth(globals.ctx, 80)
                local durationChanged, newDuration = globals.UndoWrappers.InputDouble(globals.ctx, "##SplitDuration" .. containerId, selectedItem.splitDuration, 0.1, 1.0, "%.1f s")
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
                local itemKey = globals.Structures.makeItemKey(groupPath, containerIndex, globals.selectedItemIndex[selectionKey])

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
                local itemKey = globals.Structures.makeItemKey(groupPath, containerIndex, globals.selectedItemIndex[selectionKey])

                -- Initialize waveform height if not set
                if not globals.waveformHeights then
                    globals.waveformHeights = {}
                end
                if not globals.waveformHeights[itemKey] then
                    globals.waveformHeights[itemKey] = globals.UI.scaleSize(120)  -- Default height (scaled)
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

                        -- Store gain for playback
                        globals.audioPreview.gainDB = selectedItem.gainDB or 0.0

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
                    end,

                    -- Pass item info to display in waveform
                    itemInfo = {
                        name = selectedItem.name,
                        duration = selectedItem.length,
                        channels = selectedItem.numChannels
                    },

                    -- Pass gain for waveform visual scaling
                    gainDB = selectedItem.gainDB or 0.0
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
                    local newHeight = math.max(globals.UI.scaleSize(60), math.min(globals.UI.scaleSize(400), globals.waveformHeights[itemKey] + mouseY))
                    globals.waveformHeights[itemKey] = newHeight
                    imgui.ResetMouseDragDelta(globals.ctx, 0)
                end

                -- Change cursor when hovering over resize handle
                if imgui.IsItemHovered(globals.ctx) then
                    imgui.SetMouseCursor(globals.ctx, imgui.MouseCursor_ResizeNS)
                end

                -- Add gain control slider (compact)
                imgui.Spacing(globals.ctx)

                -- Initialize gainDB if not set (for legacy items)
                if selectedItem.gainDB == nil then
                    selectedItem.gainDB = 0.0
                end

                imgui.Text(globals.ctx, "Gain:")
                imgui.SameLine(globals.ctx)
                imgui.PushItemWidth(globals.ctx, 150)

                -- Use logarithmic scale for gain fader (similar to volume faders)
                -- Map slider position (0-1) to dB range (-60 to +24)
                local sliderPos = (selectedItem.gainDB + 60) / 84  -- Normalize to 0-1
                local changedSlider, newSliderPos = imgui.SliderDouble(globals.ctx, "##Gain" .. itemKey, sliderPos, 0.0, 1.0, "")

                -- Convert back to dB with logarithmic curve
                if changedSlider then
                    local gainDB
                    if newSliderPos <= 0.0 then
                        gainDB = -60.0
                    elseif newSliderPos >= 1.0 then
                        gainDB = 24.0
                    else
                        -- Logarithmic mapping: more precision around 0 dB
                        -- Center at 0 dB (slider position ~0.714)
                        if newSliderPos < 0.714 then
                            -- Map 0.0-0.714 to -60dB to 0dB with logarithmic curve
                            local normalized = newSliderPos / 0.714
                            gainDB = -60.0 * (1.0 - normalized * normalized)
                        else
                            -- Map 0.714-1.0 to 0dB to +24dB with logarithmic curve
                            local normalized = (newSliderPos - 0.714) / 0.286
                            gainDB = 24.0 * (normalized * normalized)
                        end
                    end

                    selectedItem.gainDB = gainDB
                    -- Invalidate waveform cache to force redraw with new gain
                    if globals.waveformCache then
                        globals.waveformCache[selectedItem.filePath] = nil
                    end
                end

                imgui.PopItemWidth(globals.ctx)

                -- Display current gain value
                imgui.SameLine(globals.ctx)
                imgui.Text(globals.ctx, string.format("%.1f dB", selectedItem.gainDB))

                -- Synchronize areas from waveformAreas back to the item after any changes
                if globals.waveformAreas[itemKey] then
                    selectedItem.areas = globals.waveformAreas[itemKey]
                else
                    selectedItem.areas = nil
                end
            else
                -- Create unique itemKey for this item even if file doesn't exist
                local itemKey = globals.Structures.makeItemKey(groupPath, containerIndex, globals.selectedItemIndex[selectionKey])

                -- Initialize waveform height if not set
                if not globals.waveformHeights then
                    globals.waveformHeights = {}
                end
                if not globals.waveformHeights[itemKey] then
                    globals.waveformHeights[itemKey] = globals.UI.scaleSize(120)  -- Default height (scaled)
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
                    local newHeight = math.max(globals.UI.scaleSize(60), math.min(globals.UI.scaleSize(400), globals.waveformHeights[itemKey] + mouseY))
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
                imgui.Text(globals.ctx, "Playback: [Space] play/pause • Click lower half to set position & play • Double-click to reset")
            else
                imgui.Text(globals.ctx, "Playback: [Space] play/pause • Click lower half to set position • Double-click to reset")
            end
            imgui.Text(globals.ctx, "Areas: Shift+Drag upper half to create • Ctrl+Click upper half to delete")
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
                local rv, newVolume = globals.SliderEnhanced.SliderDouble({
                    id = "##PreviewVolume_" .. containerId,
                    value = globals.audioPreview.volume,
                    min = 0.0,
                    max = 1.0,
                    defaultValue = 0.7,
                    format = "Vol: %.2f",
                    width = 100
                })
                if rv then
                    globals.audioPreview.volume = newVolume
                    if globals.Waveform and globals.Waveform.setPreviewVolume then
                        globals.Waveform.setPreviewVolume(newVolume)
                    end
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
                    local rv, newVolume = globals.SliderEnhanced.SliderDouble({
                        id = "##PreviewVolume_" .. containerId,
                        value = globals.audioPreview.volume,
                        min = 0.0,
                        max = 1.0,
                        defaultValue = 0.7,
                        format = "Vol: %.2f",
                        width = 100
                    })
                    if rv then
                        globals.audioPreview.volume = newVolume
                        if globals.Waveform and globals.Waveform.setPreviewVolume then
                            globals.Waveform.setPreviewVolume(newVolume)
                        end
                    end
                end
            end

            -- Handle spacebar for play/pause
            -- Note: Key_Space constant is 32 (ASCII code for space)
            local spaceKey = globals.imgui.Key_Space or 32
            if fileExists and globals.imgui.IsKeyPressed(globals.ctx, spaceKey) then
                -- Check if this window has focus (use RootAndChildWindows flag if available)
                local focusFlag = globals.imgui.FocusedFlags_RootAndChildWindows or 3
                if globals.imgui.IsWindowFocused(globals.ctx, focusFlag) then
                    -- Check if currently playing
                    local isCurrentlyPlaying = globals.audioPreview and
                                              globals.audioPreview.isPlaying and
                                              globals.audioPreview.currentFile == selectedItem.filePath

                    if isCurrentlyPlaying then
                        -- Currently playing this file - stop it
                        globals.Waveform.stopPlayback()
                    else
                        -- Not playing - start playback
                        -- Use the saved clicked position if it exists, otherwise start from beginning
                        local startPosition = 0  -- Default to beginning
                        if globals.audioPreview and
                           globals.audioPreview.clickedPosition and
                           globals.audioPreview.currentFile == selectedItem.filePath then
                            startPosition = globals.audioPreview.clickedPosition
                        end

                        globals.Waveform.startPlayback(
                            selectedItem.filePath,
                            selectedItem.startOffset or 0,
                            selectedItem.length,
                            startPosition
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
    imgui.Text(globals.ctx, "Container Volume")
    imgui.SameLine(globals.ctx)
    globals.Utils.HelpMarker("Controls the volume of the container's track in Reaper. Affects all items in this container.")

    -- Use the shared VolumeControls widget
    globals.UI_VolumeControls.draw({
        id = "Container_" .. containerId,
        item = container,
        onVolumeChange = function(newVolumeDB)
            globals.Utils.setContainerTrackVolume(groupPath, containerIndex, newVolumeDB)
        end,
        onMuteChange = function(isMuted)
            if isMuted and container.isSoloed then
                container.isSoloed = false
                globals.Utils.setContainerTrackSolo(groupPath, containerIndex, false)
            end
            globals.Utils.setContainerTrackMute(groupPath, containerIndex, isMuted)
        end,
        onSoloChange = function(isSoloed)
            if isSoloed and container.isMuted then
                container.isMuted = false
                globals.Utils.setContainerTrackMute(groupPath, containerIndex, false)
            end
            globals.Utils.setContainerTrackSolo(groupPath, containerIndex, isSoloed)
        end
    })


    -- Multi-Channel Configuration (DELEGATED to sub-module)
    Container_ChannelConfig.draw(container, containerId, groupPath, containerIndex, width)


    imgui.Separator(globals.ctx)

    -- "Override Parent Settings" checkbox
    local overrideParent = container.overrideParent
    local rv, newOverrideParent = globals.UndoWrappers.Checkbox(globals.ctx, "Override Parent Settings##" .. containerId, overrideParent)
    imgui.SameLine(globals.ctx)
    globals.Utils.HelpMarker("Enable 'Override Parent Settings' to customize parameters for this container instead of inheriting from the group.")
    if rv and newOverrideParent ~= overrideParent then
        -- UndoWrappers.Checkbox already captures state - no need for manual capture
        container.overrideParent = newOverrideParent
        container.needsRegeneration = true
        -- Sync euclidean bindings after override mode change
        if group then
            globals.Structures.syncEuclideanBindings(group)
        end
    end

    -- Display trigger/randomization settings or inheritance info
    if container.overrideParent then
        -- Display the trigger and randomization settings for this container
        globals.UI.displayTriggerSettings(container, containerId, width, false, groupPath, containerIndex)
    end
end

-- Draw import drop zone for importing items from timeline or Media Explorer
function UI_Container.drawImportDropZone(groupPath, containerIndex, containerId, width)
    local group = globals.Structures.getItemFromPath(groupPath)
    if not group or not group.containers or not group.containers[containerIndex] then
        return
    end

    local container = group.containers[containerIndex]
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
                if #items > 0 then
                    globals.History.captureState("Import items to container")
                end
                for _, item in ipairs(items) do
                    table.insert(container.items, item)

                    -- Auto-initialize routing for all containers (including stereo)
                    if item.numChannels then
                        if not container.customItemRouting then
                            container.customItemRouting = {}
                        end
                        local defaultRouting = globals.Items.getDefaultRouting(item.numChannels, container.channelMode or 0)
                        container.customItemRouting[#container.items] = defaultRouting
                    end

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
                globals.History.captureState("Import items from timeline")
                for _, item in ipairs(timelineItems) do
                    table.insert(container.items, item)

                    -- Auto-initialize routing for all containers (including stereo)
                    if item.numChannels then
                        if not container.customItemRouting then
                            container.customItemRouting = {}
                        end
                        local defaultRouting = globals.Items.getDefaultRouting(item.numChannels, container.channelMode or 0)
                        container.customItemRouting[#container.items] = defaultRouting
                    end

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
            globals.History.captureState("Import items from Media Explorer")
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

    -- Create key using path-based system
    local editModeKey = globals.Structures.makeContainerKey(groupPath, containerIndex)

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

-- Show routing matrix popup for configuring item channel routing
function UI_Container.showRoutingMatrixPopup(groupPath, containerIndex, containerId)
    if not globals.routingPopupItemIndex then
        return
    end

    -- Check if we're viewing the correct container
    if globals.routingPopupGroupPath ~= groupPath or globals.routingPopupContainerIndex ~= containerIndex then
        return
    end

    local group = globals.Structures.getItemFromPath(groupPath)
    if not group or not group.containers or not group.containers[containerIndex] then
        return
    end

    local container = group.containers[containerIndex]
    local itemIdx = globals.routingPopupItemIndex
    local item = container.items[itemIdx]

    if not item then
        return
    end

    -- IMPORTANT: OpenPopup must be called in the same frame as BeginPopupModal
    -- Check if we need to open the popup (first frame only)
    if not globals.routingPopupOpened then
        imgui.OpenPopup(globals.ctx, "RoutingMatrixPopup")
        globals.routingPopupOpened = true
    end

    -- Modal popup with flags to keep it always on top
    local modalFlags = imgui.WindowFlags_AlwaysAutoResize |
                       imgui.WindowFlags_NoMove |
                       imgui.WindowFlags_NoCollapse
    local popupVisible = imgui.BeginPopupModal(globals.ctx, "RoutingMatrixPopup", nil, modalFlags)

    if popupVisible then
        -- Force popup to stay focused (prevent main window from stealing focus)
        if not imgui.IsWindowFocused(globals.ctx, imgui.FocusedFlags_RootWindow) then
            imgui.SetWindowFocus(globals.ctx)
        end

        -- Get channel config
        local containerChannelMode = container.channelMode or 0
        local containerModeName = "Stereo"
        local containerChannels = 2
        local destLabels = {"L", "R"}

        if containerChannelMode > 0 then
            local config = globals.Constants.CHANNEL_CONFIGS[containerChannelMode]
            if config then
                containerModeName = config.name
                containerChannels = config.channels
                local activeConfig = config
                if config.hasVariants then
                    activeConfig = config.variants[container.channelVariant or 0]
                end
                destLabels = activeConfig.labels
            end
        end

        -- Header
        imgui.Text(globals.ctx, "Routing: " .. item.name)
        imgui.Text(globals.ctx, (item.numChannels or 2) .. " ch → " .. containerModeName)
        imgui.Separator(globals.ctx)

        -- Get or initialize routing
        local routing = container.customItemRouting and container.customItemRouting[itemIdx]
        if not routing then
            if not container.customItemRouting then
                container.customItemRouting = {}
            end
            local defaultRouting = globals.Items.getDefaultRouting(item.numChannels or 2, containerChannelMode)
            container.customItemRouting[itemIdx] = defaultRouting
            routing = container.customItemRouting[itemIdx]
        end

        -- Badge AUTO/CUSTOM
        local isAuto = (routing.isAutoRouting == true)
        if isAuto then
            imgui.PushStyleColor(globals.ctx, imgui.Col_Text, 0x888888FF) -- Gray
            imgui.Text(globals.ctx, "AUTO")
            imgui.PopStyleColor(globals.ctx, 1)
        else
            imgui.PushStyleColor(globals.ctx, imgui.Col_Text, 0xFF8800FF) -- Orange
            imgui.Text(globals.ctx, "CUSTOM")
            imgui.PopStyleColor(globals.ctx, 1)
        end

        imgui.Separator(globals.ctx)

        -- Matrix using table for proper alignment
        local itemChannels = item.numChannels or 2
        local tableFlags = imgui.TableFlags_Borders | imgui.TableFlags_SizingFixedFit

        if imgui.BeginTable(globals.ctx, "RoutingMatrix", containerChannels + 1, tableFlags) then
            -- Header row
            imgui.TableSetupColumn(globals.ctx, " ", imgui.TableColumnFlags_WidthFixed, 40)
            for destIdx = 1, containerChannels do
                imgui.TableSetupColumn(globals.ctx, destLabels[destIdx], imgui.TableColumnFlags_WidthFixed, 35)
            end
            imgui.TableHeadersRow(globals.ctx)

            -- Data rows (source channels)
            for srcCh = 1, itemChannels do
                imgui.TableNextRow(globals.ctx)

                -- First column: source channel label
                imgui.TableNextColumn(globals.ctx)
                imgui.Text(globals.ctx, "Ch" .. srcCh)

                -- Destination columns: radio buttons
                for destCh = 1, containerChannels do
                    imgui.TableNextColumn(globals.ctx)

                    local currentDest = routing.routingMatrix[srcCh]
                    local isSelected = (currentDest == destCh)

                    -- Special case: if destCh == 0 (distribute mode for mono), show all selected
                    if currentDest == 0 and itemChannels == 1 then
                        isSelected = true
                    end

                    if imgui.RadioButton(globals.ctx, "##r" .. srcCh .. "_" .. destCh, isSelected) then
                        -- Set routing
                        routing.routingMatrix[srcCh] = destCh
                        routing.isAutoRouting = false
                    end
                end
            end

            imgui.EndTable(globals.ctx)
        end

        imgui.Separator(globals.ctx)

        -- Buttons
        if imgui.Button(globals.ctx, "Reset to Auto", 120, 0) then
            local defaultRouting = globals.Items.getDefaultRouting(item.numChannels or 2, containerChannelMode)
            container.customItemRouting[itemIdx] = defaultRouting
        end

        imgui.SameLine(globals.ctx, 0, 10)
        if imgui.Button(globals.ctx, "Close", 120, 0) then
            globals.routingPopupItemIndex = nil
            globals.routingPopupGroupPath = nil
            globals.routingPopupContainerIndex = nil
            globals.routingPopupOpened = nil
            imgui.CloseCurrentPopup(globals.ctx)
        end

        imgui.EndPopup(globals.ctx)
    end

    -- IMPORTANT: Check if popup was closed externally (clicked outside or ESC)
    -- If we have routing data but popup is not visible, clean up
    if not popupVisible and globals.routingPopupItemIndex then
        globals.routingPopupItemIndex = nil
        globals.routingPopupGroupPath = nil
        globals.routingPopupContainerIndex = nil
        globals.routingPopupOpened = nil
    end
end

return UI_Container
