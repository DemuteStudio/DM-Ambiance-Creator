--[[
@version 1.5
@noindex
--]]

local UI_Container = {}
local globals = {}
local Constants = require("DM_Ambiance_Constants")

-- Initialize the module with global variables from the main script
function UI_Container.initModule(g)
    if not g then
        error("UI_Container.initModule: globals parameter is required")
    end
    globals = g
    
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
    containerPresetItems = containerPresetItems .. "\0"

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
            end
        else
            reaper.MB("No item selected!", "Error", 0)
        end
    end

    -- Display imported items with persistent state
    if #container.items > 0 then
        -- Create unique key for this container's expanded state
        local expandedStateKey = groupIndex .. "_" .. containerIndex .. "_items"
        
        -- Initialize expanded state if not set (default to collapsed)
        if globals.containerExpandedStates[expandedStateKey] == nil then
            globals.containerExpandedStates[expandedStateKey] = false
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
            
            -- List all imported items with a button to remove each one
            for l, item in ipairs(container.items) do
                imgui.Text(globals.ctx, l .. ". " .. item.name)
                imgui.SameLine(globals.ctx)
                if imgui.Button(globals.ctx, "X##item" .. l) then
                    itemToDelete = l
                end
            end
            
            -- Remove the item if the delete button was pressed
            if itemToDelete then
                table.remove(container.items, itemToDelete)
                -- Keep the header expanded after deletion
                globals.containerExpandedStates[expandedStateKey] = true
            end
        end
        
        imgui.PopID(globals.ctx)
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
    
    local volumeDB = container.trackVolume
    local rv, newVolumeDB = imgui.SliderDouble(
        globals.ctx, 
        "##TrackVolume_" .. containerId, 
        volumeDB, 
        Constants.AUDIO.VOLUME_RANGE_DB_MIN, 
        Constants.AUDIO.VOLUME_RANGE_DB_MAX, 
        "%.1f dB"
    )
    if rv then 
        container.trackVolume = newVolumeDB
        -- Apply volume to track in real-time
        globals.Utils.setContainerTrackVolume(groupIndex, containerIndex, newVolumeDB)
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
    for i = 0, 3 do  -- Changed from 4 to 3 (removed 5.1 and 7.1)
        local config = globals.Constants.CHANNEL_CONFIGS[i]
        channelModeItems = channelModeItems .. config.name .. "\0"
    end
    channelModeItems = channelModeItems .. "\0"

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
            for i = 0, #config.variants do
                variantItems = variantItems .. config.variants[i].name .. "\0"
            end
            variantItems = variantItems .. "\0"

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

        for i = 1, config.channels do
            local label = activeConfig.labels and activeConfig.labels[i] or ("Channel " .. i)

            imgui.PushID(globals.ctx, "channel_" .. i .. "_" .. containerId)
            
            -- Channel label and volume on same line
            imgui.Text(globals.ctx, label .. ":")
            imgui.SameLine(globals.ctx)
            
            -- Initialize volume if needed
            if container.channelVolumes[i] == nil then
                container.channelVolumes[i] = 0.0
            end
            
            -- Volume control on same line as label
            imgui.PushItemWidth(globals.ctx, width * 0.5)
            local rv, newVol = imgui.SliderDouble(
                globals.ctx,
                "##Vol_" .. i,
                container.channelVolumes[i],
                -12.0, 12.0,
                "%.1f dB"
            )
            if rv then
                container.channelVolumes[i] = newVol
                -- Apply volume to channel track in real-time
                globals.Utils.setChannelTrackVolume(groupIndex, containerIndex, i, newVol)
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