--[[
@version 1.0
@author DM
@description Channel Routing Conflict Resolver Module
This module handles detection, resolution, and UI for channel routing conflicts
in multi-channel audio configurations.
@noindex
--]]

local ConflictResolver = {}
local globals = {}
local Constants = require("DM_Ambiance_Constants")

-- Module state variables
local showModal = false
local conflictData = nil
local resolutionData = nil
local selectedResolution = {}
local modalFirstOpen = true

-- Initialize the module with global references
function ConflictResolver.initModule(g)
    if not g then
        error("ConflictResolver.initModule: globals parameter is required")
    end
    globals = g
    
    -- Initialize state
    globals.showConflictModal = false
    globals.pendingConflictData = nil
    globals.pendingResolutionData = nil
end

-- Detect routing conflicts between containers
-- @return table|nil: Conflict information or nil if no conflicts
function ConflictResolver.detectConflicts()
    local channelUsage = {}  -- Track which channels are used for what
    local conflicts = {}
    local containers = {}  -- Store all containers with their routing
    local conflictPairs = {}

    -- Collect all containers with multi-channel routing
    for groupIdx, group in ipairs(globals.groups) do
        for containerIdx, container in ipairs(group.containers) do
            if container.channelMode and container.channelMode > 0 then
                local config = Constants.CHANNEL_CONFIGS[container.channelMode]

                if config then
                    local activeConfig = config
                    if config.hasVariants then
                        activeConfig = config.variants[container.channelVariant or 0]
                        activeConfig.channels = config.channels
                        activeConfig.name = config.name  -- Preserve base config name
                    end

                    local containerKey = group.name .. "_" .. container.name
                    containers[containerKey] = {
                        group = group,
                        container = container,
                        groupName = group.name,
                        containerName = container.name,
                        channelMode = container.channelMode,
                        channelCount = config.channels,
                        config = activeConfig,
                        routing = container.customRouting or activeConfig.routing,
                        labels = activeConfig.labels,
                        conflicts = {}
                    }

                    -- Track channel usage
                    local routing = container.customRouting or activeConfig.routing
                    for idx, channelNum in ipairs(routing) do
                        local label = activeConfig.labels[idx]

                        if not channelUsage[channelNum] then
                            channelUsage[channelNum] = {}
                        end

                        -- Check for conflicts
                        for _, usage in ipairs(channelUsage[channelNum]) do
                            if usage.label ~= label then
                                -- Conflict detected!
                                local conflictKey = usage.containerKey .. "_vs_" .. containerKey
                                
                                if not conflictPairs[conflictKey] then
                                    conflictPairs[conflictKey] = {
                                        container1 = usage,
                                        container2 = {
                                            containerKey = containerKey,
                                            groupName = group.name,
                                            containerName = container.name,
                                            label = label
                                        },
                                        conflictingChannels = {}
                                    }
                                end
                                
                                table.insert(conflictPairs[conflictKey].conflictingChannels, {
                                    channel = channelNum,
                                    label1 = usage.label,
                                    label2 = label
                                })
                                
                                -- Mark conflict in container data
                                containers[containerKey].conflicts[channelNum] = {
                                    channel = channelNum,
                                    label = label,
                                    conflictsWith = usage.containerKey
                                }
                                
                                if containers[usage.containerKey] then
                                    containers[usage.containerKey].conflicts[channelNum] = {
                                        channel = channelNum,
                                        label = usage.label,
                                        conflictsWith = containerKey
                                    }
                                end
                            end
                        end

                        table.insert(channelUsage[channelNum], {
                            label = label,
                            containerKey = containerKey,
                            groupName = group.name,
                            containerName = container.name
                        })
                    end
                end
            end
        end
    end

    -- Return nil if no conflicts
    local hasConflicts = false
    for _, _ in pairs(conflictPairs) do
        hasConflicts = true
        break
    end
    
    if not hasConflicts then
        return nil
    end

    return {
        containers = containers,
        conflictPairs = conflictPairs,
        channelUsage = channelUsage
    }
end

-- Find intelligent routing solution based on channel labels
-- @param conflicts table: Conflict data from detectConflicts()
-- @return table: Resolution suggestions
function ConflictResolver.findIntelligentRouting(conflicts)
    local resolutions = {}
    
    -- Identify master configurations (5.0, 7.0, etc.)
    local masterConfigs = {}
    local subordinateConfigs = {}
    
    for containerKey, data in pairs(conflicts.containers) do
        if data.channelCount >= 5 then
            masterConfigs[containerKey] = data
        else
            subordinateConfigs[containerKey] = data
        end
    end
    
    -- Process each subordinate configuration
    for containerKey, subConfig in pairs(subordinateConfigs) do
        if next(subConfig.conflicts) then  -- Has conflicts
            -- Find which master config it conflicts with
            local conflictingMaster = nil
            for channel, conflictInfo in pairs(subConfig.conflicts) do
                if masterConfigs[conflictInfo.conflictsWith] then
                    conflictingMaster = masterConfigs[conflictInfo.conflictsWith]
                    break
                end
            end
            
            if conflictingMaster then
                local resolution = ConflictResolver.matchChannelsByLabel(subConfig, conflictingMaster)
                if resolution then
                    table.insert(resolutions, resolution)
                end
            end
        end
    end
    
    return resolutions
end

-- Match channels between configurations based on labels
-- @param subConfig table: Subordinate configuration (e.g., Quad)
-- @param masterConfig table: Master configuration (e.g., 5.0)
-- @return table: Routing resolution
function ConflictResolver.matchChannelsByLabel(subConfig, masterConfig)
    local resolution = {
        containerKey = subConfig.groupName .. "_" .. subConfig.containerName,
        groupName = subConfig.groupName,
        containerName = subConfig.containerName,
        affectedBy = masterConfig.groupName .. "_" .. masterConfig.containerName,
        changes = {},
        originalRouting = subConfig.routing,
        newRouting = {}
    }
    
    -- Create label to channel mapping for master config
    local masterLabelMap = {}
    for idx, label in ipairs(masterConfig.labels) do
        masterLabelMap[label] = masterConfig.routing[idx]
    end
    
    -- Match each channel of subordinate config
    for idx, label in ipairs(subConfig.labels) do
        local oldChannel = subConfig.routing[idx]
        local newChannel = oldChannel  -- Default: keep same
        local reason = "Keep original"
        local matched = nil
        
        -- Try to find matching label in master config
        if masterLabelMap[label] then
            newChannel = masterLabelMap[label]
            matched = masterConfig.containerName .. "_" .. label
            reason = string.format("Match %s %s on channel %d", 
                masterConfig.config.name or "Master", label, newChannel)
        else
            -- Special handling for common channel mappings
            if label == "L" then
                newChannel = 1
                reason = "Standard L position"
            elseif label == "R" then
                -- Check if master has center channel
                if masterLabelMap["C"] and masterLabelMap["C"] == 2 then
                    newChannel = 3  -- R moves to channel 3 in L C R config
                else
                    newChannel = 2  -- R stays on channel 2 in L R C config
                end
                reason = newChannel == 3 and "Adapt to L C R layout" or "Standard R position"
            elseif label == "LS" or label == "RS" then
                -- Keep surround channels aligned with master if available
                if masterLabelMap[label] then
                    newChannel = masterLabelMap[label]
                    reason = string.format("Match %s %s", masterConfig.config.name or "Master", label)
                end
            end
        end
        
        table.insert(resolution.changes, {
            label = label,
            oldChannel = oldChannel,
            newChannel = newChannel,
            matched = matched,
            reason = reason
        })
        
        table.insert(resolution.newRouting, newChannel)
    end
    
    -- Check if any changes are actually needed
    local needsChange = false
    for i, channel in ipairs(resolution.newRouting) do
        if channel ~= resolution.originalRouting[i] then
            needsChange = true
            break
        end
    end
    
    return needsChange and resolution or nil
end

-- Show the conflict resolution modal window
-- @param conflicts table: Conflict data
function ConflictResolver.showResolutionModal(conflicts)
    if not conflicts then return end
    
    conflictData = conflicts
    resolutionData = ConflictResolver.findIntelligentRouting(conflicts)
    
    globals.showConflictModal = true
    globals.pendingConflictData = conflictData
    globals.pendingResolutionData = resolutionData
    modalFirstOpen = true
end

-- Render the conflict resolution modal
function ConflictResolver.renderModal()
    local ctx = globals.ctx
    local imgui = globals.imgui
    
    if not globals.showConflictModal then return end
    
    -- Set initial window size
    if modalFirstOpen then
        imgui.SetNextWindowSize(ctx, 900, 700, imgui.Cond_FirstUseEver)
        imgui.OpenPopup(ctx, "Channel Routing Conflict Resolver")
        modalFirstOpen = false
    end
    
    local visible, open = imgui.BeginPopupModal(ctx, "Channel Routing Conflict Resolver", true, 
        imgui.WindowFlags_NoCollapse)
    
    if visible then
        -- Get window dimensions for proper layout
        local windowWidth, windowHeight = imgui.GetWindowSize(ctx)
        local headerHeight = 60  -- Space for title and separator
        local footerHeight = 60  -- More space for buttons and padding below
        local contentHeight = windowHeight - headerHeight - footerHeight - 30  -- Increased padding for better spacing
        
        -- Header
        imgui.PushStyleColor(ctx, imgui.Col_Text, 0xFF8800FF)
        imgui.Text(ctx, "⚠ Channel Routing Conflicts Detected")
        imgui.PopStyleColor(ctx)
        
        imgui.Separator(ctx)
        imgui.Spacing(ctx)
        
        -- Create scrollable content area
        if imgui.BeginChild(ctx, "ContentArea", 0, contentHeight) then
            -- Tab bar for different views
            if imgui.BeginTabBar(ctx, "ConflictTabs") then
                
                -- Combined Tab: Conflicts & Resolution
                if imgui.BeginTabItem(ctx, "Conflicts & Resolution") then
                    ConflictResolver.renderCombinedView()
                    imgui.EndTabItem(ctx)
                end
                
                -- Tab 2: Channel Map
                if imgui.BeginTabItem(ctx, "Channel Map") then
                    ConflictResolver.renderChannelMap()
                    imgui.EndTabItem(ctx)
                end
                
                imgui.EndTabBar(ctx)
            end
            
            imgui.EndChild(ctx)
        end
        
        -- Footer with buttons (always at bottom)
        imgui.Separator(ctx)
        imgui.Spacing(ctx)
        
        -- Center the buttons
        local buttonWidth = 150
        local totalWidth = buttonWidth * 2 + imgui.GetStyleVar(ctx, imgui.StyleVar_ItemSpacing)
        local avail = imgui.GetContentRegionAvail(ctx)
        imgui.SetCursorPosX(ctx, imgui.GetCursorPosX(ctx) + (avail - totalWidth) * 0.5)
        
        imgui.PushStyleColor(ctx, imgui.Col_Button, 0x00AA00FF)
        if imgui.Button(ctx, "Apply Resolution", buttonWidth, 30) then
            ConflictResolver.applyResolution()
            globals.showConflictModal = false
            imgui.CloseCurrentPopup(ctx)
        end
        imgui.PopStyleColor(ctx)
        
        imgui.SameLine(ctx)
        
        if imgui.Button(ctx, "Cancel", buttonWidth, 30) then
            globals.showConflictModal = false
            imgui.CloseCurrentPopup(ctx)
        end
        
        imgui.EndPopup(ctx)
    end
    
    if not open then
        globals.showConflictModal = false
    end
end

-- Render combined conflicts and resolution view
function ConflictResolver.renderCombinedView()
    local ctx = globals.ctx
    local imgui = globals.imgui
    
    if not globals.pendingConflictData then return end
    
    -- Section 1: Conflicts Overview
    imgui.PushStyleColor(ctx, imgui.Col_Text, 0xFF8800FF)
    imgui.Text(ctx, "Detected Conflicts")
    imgui.PopStyleColor(ctx)
    imgui.Separator(ctx)
    imgui.Spacing(ctx)
    
    imgui.Text(ctx, "The following channel routing conflicts were detected:")
    imgui.Spacing(ctx)
    
    -- Conflicts table
    if imgui.BeginTable(ctx, "ConflictTable", 9, 
        imgui.TableFlags_Borders | imgui.TableFlags_RowBg | imgui.TableFlags_Resizable) then
        
        -- Headers
        imgui.TableSetupColumn(ctx, "Container 1")
        imgui.TableSetupColumn(ctx, "Group 1")
        imgui.TableSetupColumn(ctx, "Label 1", imgui.TableColumnFlags_WidthFixed, 60)
        imgui.TableSetupColumn(ctx, "Ch.", imgui.TableColumnFlags_WidthFixed, 40)
        imgui.TableSetupColumn(ctx, "⚡", imgui.TableColumnFlags_WidthFixed, 30)
        imgui.TableSetupColumn(ctx, "Ch.", imgui.TableColumnFlags_WidthFixed, 40)
        imgui.TableSetupColumn(ctx, "Label 2", imgui.TableColumnFlags_WidthFixed, 60)
        imgui.TableSetupColumn(ctx, "Container 2")
        imgui.TableSetupColumn(ctx, "Group 2")
        imgui.TableHeadersRow(ctx)
        
        -- Display conflicts
        for _, pair in pairs(globals.pendingConflictData.conflictPairs) do
            for _, conflict in ipairs(pair.conflictingChannels) do
                imgui.TableNextRow(ctx)
                
                -- Container 1 info
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, pair.container1.containerName)
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, pair.container1.groupName)
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, conflict.label1)
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, tostring(conflict.channel))
                
                -- Conflict indicator
                imgui.TableNextColumn(ctx)
                imgui.PushStyleColor(ctx, imgui.Col_Text, 0xFF0000FF)
                imgui.Text(ctx, "⚡")
                imgui.PopStyleColor(ctx)
                
                -- Container 2 info
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, tostring(conflict.channel))
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, conflict.label2)
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, pair.container2.containerName)
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, pair.container2.groupName)
            end
        end
        
        imgui.EndTable(ctx)
    end
    
    -- Spacing between sections
    imgui.Spacing(ctx)
    imgui.Dummy(ctx, 0, 20)
    
    -- Section 2: Proposed Resolution
    imgui.PushStyleColor(ctx, imgui.Col_Text, 0x00FF00FF)
    imgui.Text(ctx, "Proposed Resolution")
    imgui.PopStyleColor(ctx)
    imgui.Separator(ctx)
    imgui.Spacing(ctx)
    
    if not globals.pendingResolutionData or #globals.pendingResolutionData == 0 then
        imgui.Text(ctx, "No automatic resolution available.")
        imgui.Text(ctx, "Manual routing adjustment may be required.")
        return
    end
    
    imgui.Text(ctx, "Proposed routing changes to resolve conflicts:")
    imgui.Spacing(ctx)
    
    for _, resolution in ipairs(globals.pendingResolutionData) do
        -- Container header
        imgui.PushStyleColor(ctx, imgui.Col_Text, 0x00FFFFFF)
        imgui.Text(ctx, string.format("▪ %s / %s", resolution.groupName, resolution.containerName))
        imgui.PopStyleColor(ctx)
        
        imgui.Indent(ctx, 10)
        imgui.Text(ctx, string.format("Resolving conflict with: %s", resolution.affectedBy))
        imgui.Unindent(ctx, 10)
        imgui.Spacing(ctx)
        
        -- Resolution table
        if imgui.BeginTable(ctx, "ResolutionTable_" .. resolution.containerKey, 6,
            imgui.TableFlags_Borders | imgui.TableFlags_RowBg | imgui.TableFlags_SizingFixedFit) then
            
            imgui.TableSetupColumn(ctx, "Label", imgui.TableColumnFlags_WidthFixed, 60)
            imgui.TableSetupColumn(ctx, "Current Ch.", imgui.TableColumnFlags_WidthFixed, 80)
            imgui.TableSetupColumn(ctx, "→", imgui.TableColumnFlags_WidthFixed, 30)
            imgui.TableSetupColumn(ctx, "New Ch.", imgui.TableColumnFlags_WidthFixed, 70)
            imgui.TableSetupColumn(ctx, "Reason")
            imgui.TableSetupColumn(ctx, "Status", imgui.TableColumnFlags_WidthFixed, 100)
            imgui.TableHeadersRow(ctx)
            
            for _, change in ipairs(resolution.changes) do
                imgui.TableNextRow(ctx)
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, change.label)
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, tostring(change.oldChannel))
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, "→")
                
                imgui.TableNextColumn(ctx)
                if change.oldChannel ~= change.newChannel then
                    imgui.PushStyleColor(ctx, imgui.Col_Text, 0x00FF00FF)
                    imgui.Text(ctx, tostring(change.newChannel))
                    imgui.PopStyleColor(ctx)
                else
                    imgui.Text(ctx, tostring(change.newChannel))
                end
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, change.reason)
                
                imgui.TableNextColumn(ctx)
                if change.oldChannel ~= change.newChannel then
                    imgui.PushStyleColor(ctx, imgui.Col_Text, 0xFFFF00FF)
                    imgui.Text(ctx, "Will change")
                    imgui.PopStyleColor(ctx)
                else
                    imgui.TextDisabled(ctx, "No change")
                end
            end
            
            imgui.EndTable(ctx)
        end
        
        imgui.Spacing(ctx)
    end
end

-- Render the conflict overview table
function ConflictResolver.renderConflictTable()
    local ctx = globals.ctx
    local imgui = globals.imgui
    
    if not globals.pendingConflictData then return end
    
    imgui.Text(ctx, "The following channel routing conflicts were detected:")
    imgui.Spacing(ctx)
    
    -- Create table
    if imgui.BeginTable(ctx, "ConflictTable", 9, 
        imgui.TableFlags_Borders | imgui.TableFlags_RowBg | imgui.TableFlags_Resizable) then
        
        -- Headers
        imgui.TableSetupColumn(ctx, "Container 1")
        imgui.TableSetupColumn(ctx, "Group 1")
        imgui.TableSetupColumn(ctx, "Label 1", imgui.TableColumnFlags_WidthFixed, 60)
        imgui.TableSetupColumn(ctx, "Ch.", imgui.TableColumnFlags_WidthFixed, 40)
        imgui.TableSetupColumn(ctx, "⚡", imgui.TableColumnFlags_WidthFixed, 30)
        imgui.TableSetupColumn(ctx, "Ch.", imgui.TableColumnFlags_WidthFixed, 40)
        imgui.TableSetupColumn(ctx, "Label 2", imgui.TableColumnFlags_WidthFixed, 60)
        imgui.TableSetupColumn(ctx, "Container 2")
        imgui.TableSetupColumn(ctx, "Group 2")
        imgui.TableHeadersRow(ctx)
        
        -- Display conflicts
        for _, pair in pairs(globals.pendingConflictData.conflictPairs) do
            for _, conflict in ipairs(pair.conflictingChannels) do
                imgui.TableNextRow(ctx)
                
                -- Container 1 info
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, pair.container1.containerName)
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, pair.container1.groupName)
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, conflict.label1)
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, tostring(conflict.channel))
                
                -- Conflict indicator
                imgui.TableNextColumn(ctx)
                imgui.PushStyleColor(ctx, imgui.Col_Text, 0xFF0000FF)
                imgui.Text(ctx, "⚡")
                imgui.PopStyleColor(ctx)
                
                -- Container 2 info
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, tostring(conflict.channel))
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, conflict.label2)
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, pair.container2.containerName)
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, pair.container2.groupName)
            end
        end
        
        imgui.EndTable(ctx)
    end
end

-- Render the resolution table
function ConflictResolver.renderResolutionTable()
    local ctx = globals.ctx
    local imgui = globals.imgui
    
    if not globals.pendingResolutionData or #globals.pendingResolutionData == 0 then
        imgui.Text(ctx, "No automatic resolution available.")
        imgui.Text(ctx, "Manual routing adjustment may be required.")
        return
    end
    
    imgui.Text(ctx, "Proposed routing changes to resolve conflicts:")
    imgui.Spacing(ctx)
    
    for _, resolution in ipairs(globals.pendingResolutionData) do
        -- Container header
        imgui.PushStyleColor(ctx, imgui.Col_Text, 0x00FFFFFF)
        imgui.Text(ctx, string.format("%s / %s", resolution.groupName, resolution.containerName))
        imgui.PopStyleColor(ctx)
        
        imgui.Text(ctx, string.format("   Resolving conflict with: %s", resolution.affectedBy))
        imgui.Spacing(ctx)
        
        -- Resolution table
        if imgui.BeginTable(ctx, "ResolutionTable_" .. resolution.containerKey, 6,
            imgui.TableFlags_Borders | imgui.TableFlags_RowBg | imgui.TableFlags_SizingFixedFit) then
            
            imgui.TableSetupColumn(ctx, "Label", imgui.TableColumnFlags_WidthFixed, 60)
            imgui.TableSetupColumn(ctx, "Current Ch.", imgui.TableColumnFlags_WidthFixed, 80)
            imgui.TableSetupColumn(ctx, "→", imgui.TableColumnFlags_WidthFixed, 30)
            imgui.TableSetupColumn(ctx, "New Ch.", imgui.TableColumnFlags_WidthFixed, 70)
            imgui.TableSetupColumn(ctx, "Reason")
            imgui.TableSetupColumn(ctx, "Status", imgui.TableColumnFlags_WidthFixed, 100)
            imgui.TableHeadersRow(ctx)
            
            for _, change in ipairs(resolution.changes) do
                imgui.TableNextRow(ctx)
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, change.label)
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, tostring(change.oldChannel))
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, "→")
                
                imgui.TableNextColumn(ctx)
                if change.oldChannel ~= change.newChannel then
                    imgui.PushStyleColor(ctx, imgui.Col_Text, 0x00FF00FF)
                    imgui.Text(ctx, tostring(change.newChannel))
                    imgui.PopStyleColor(ctx)
                else
                    imgui.Text(ctx, tostring(change.newChannel))
                end
                
                imgui.TableNextColumn(ctx)
                imgui.Text(ctx, change.reason)
                
                imgui.TableNextColumn(ctx)
                if change.oldChannel ~= change.newChannel then
                    imgui.PushStyleColor(ctx, imgui.Col_Text, 0xFFFF00FF)
                    imgui.Text(ctx, "Will change")
                    imgui.PopStyleColor(ctx)
                else
                    imgui.TextDisabled(ctx, "No change")
                end
            end
            
            imgui.EndTable(ctx)
        end
        
        imgui.Spacing(ctx)
        imgui.Separator(ctx)
        imgui.Spacing(ctx)
    end
end

-- Render visual channel map with vertical list design
function ConflictResolver.renderChannelMap()
    local ctx = globals.ctx
    local imgui = globals.imgui
    
    imgui.Text(ctx, "Channel Assignment Overview:")
    imgui.Spacing(ctx)
    
    if not globals.pendingConflictData or not globals.pendingConflictData.channelUsage then
        imgui.TextDisabled(ctx, "No channel data available")
        return
    end
    
    -- Process channels 1-16
    for ch = 1, 16 do
        local usage = globals.pendingConflictData.channelUsage[ch]
        
        if usage and #usage > 0 then
            -- Check for conflicts on this channel
            local hasConflict = false
            local uniqueLabels = {}
            
            -- Collect unique labels to detect conflicts
            for _, u in ipairs(usage) do
                if not uniqueLabels[u.label] then
                    uniqueLabels[u.label] = true
                end
            end
            
            -- Count unique labels - more than 1 means conflict
            local labelCount = 0
            local labelList = {}
            for label, _ in pairs(uniqueLabels) do
                labelCount = labelCount + 1
                table.insert(labelList, label)
            end
            hasConflict = labelCount > 1
            
            -- Channel header with status
            imgui.Separator(ctx)
            
            if hasConflict then
                imgui.PushStyleColor(ctx, imgui.Col_Text, 0xFF0000FF)
                imgui.Text(ctx, string.format("Channel %d - ⚠ CONFLICT (%s)", 
                    ch, table.concat(labelList, " vs ")))
                imgui.PopStyleColor(ctx)
            else
                imgui.PushStyleColor(ctx, imgui.Col_Text, 0x00FF00FF)
                imgui.Text(ctx, string.format("Channel %d - ✓ OK [%s]", 
                    ch, labelList[1] or ""))
                imgui.PopStyleColor(ctx)
            end
            
            -- List containers using this channel
            imgui.Indent(ctx, 20)
            for _, u in ipairs(usage) do
                local statusIcon = hasConflict and "✗" or "✓"
                local color = hasConflict and 0xFF8800FF or 0xAAAAAAFF
                
                imgui.PushStyleColor(ctx, imgui.Col_Text, color)
                imgui.Text(ctx, string.format("%s %s / %s (%s)", 
                    statusIcon,
                    u.groupName or "Unknown",
                    u.containerName or "Unknown", 
                    u.label or ""))
                imgui.PopStyleColor(ctx)
            end
            imgui.Unindent(ctx, 20)
            
            imgui.Spacing(ctx)
        end
    end
    
    -- Show summary of unused channels
    imgui.Separator(ctx)
    imgui.Spacing(ctx)
    imgui.TextDisabled(ctx, "Channel Usage Summary:")
    imgui.Spacing(ctx)
    
    local unusedChannels = {}
    local usedCount = 0
    
    for ch = 1, 16 do
        if not globals.pendingConflictData.channelUsage[ch] or 
           #globals.pendingConflictData.channelUsage[ch] == 0 then
            table.insert(unusedChannels, tostring(ch))
        else
            usedCount = usedCount + 1
        end
    end
    
    imgui.Text(ctx, string.format("Channels in use: %d/16", usedCount))
    
    if #unusedChannels > 0 then
        imgui.TextDisabled(ctx, "Available channels: " .. table.concat(unusedChannels, ", "))
    else
        imgui.TextColored(ctx, 0xFFFF00FF, "All channels are in use!")
    end
end

-- Apply the resolution to the affected containers
function ConflictResolver.applyResolution()
    if not globals.pendingResolutionData then return end
    
    reaper.Undo_BeginBlock()
    
    local allSuccess = true
    
    for _, resolution in ipairs(globals.pendingResolutionData) do
        -- Find the container in the data structure
        for _, group in ipairs(globals.groups) do
            if group.name == resolution.groupName then
                for _, container in ipairs(group.containers) do
                    if container.name == resolution.containerName then
                        -- Store the new routing in the container configuration
                        container.customRouting = resolution.newRouting
                        
                        -- Apply routing to existing tracks immediately
                        local success = ConflictResolver.applyRoutingToExistingTracks(
                            resolution.groupName, 
                            resolution.containerName, 
                            resolution.newRouting
                        )
                        
                        if not success then
                            -- If tracks don't exist, mark for regeneration
                            container.needsRegeneration = true
                            allSuccess = false
                        end
                        
                        break
                    end
                end
            end
        end
    end
    
    -- Only regenerate if some tracks were not found
    if not allSuccess and globals.Generation then
        globals.Generation.generateGroups()
    end
    
    reaper.Undo_EndBlock("Apply Channel Routing Resolution", -1)
    
    -- Update the arrange view to reflect changes
    reaper.UpdateArrange()
    reaper.TrackList_AdjustWindows(false)
end

-- Apply routing changes to existing multi-channel tracks
-- @param groupName string: Name of the group
-- @param containerName string: Name of the container  
-- @param newRouting table: New routing configuration
-- @return boolean: Success status
function ConflictResolver.applyRoutingToExistingTracks(groupName, containerName, newRouting)
    -- Find the group track
    local groupTrack, groupTrackIdx = globals.Utils.findGroupByName(groupName)
    if not groupTrack then
        return false
    end
    
    -- Find the container track within the group
    local containerTrack = globals.Utils.findContainerGroup(groupTrackIdx, containerName)
    if not containerTrack then
        return false
    end
    
    -- Get container track index
    local containerIdx = reaper.GetMediaTrackInfo_Value(containerTrack, "IP_TRACKNUMBER") - 1
    
    -- Check if this is a multi-channel container (has child tracks)
    local folderDepth = reaper.GetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH")
    if folderDepth ~= 1 then
        return false -- Not a folder, no child tracks to update
    end
    
    -- Find all child tracks and update their sends
    local trackIdx = containerIdx + 1
    local depth = 1
    local channelIndex = 1
    
    while trackIdx < reaper.CountTracks(0) and depth > 0 do
        local childTrack = reaper.GetTrack(0, trackIdx)
        if not childTrack then break end
        
        -- Check if this is a direct child (not a grandchild)
        local parent = reaper.GetParentTrack(childTrack)
        if parent == containerTrack and channelIndex <= #newRouting then
            -- Find the send to parent track
            local sendCount = reaper.GetTrackNumSends(childTrack, 0)
            for sendIdx = 0, sendCount - 1 do
                local destTrack = reaper.GetTrackSendInfo_Value(childTrack, 0, sendIdx, "P_DESTTRACK")
                if destTrack == containerTrack then
                    -- Update the destination channel for this send
                    local destChannel = newRouting[channelIndex] - 1  -- Convert to 0-based
                    local dstChannels = 1024 + destChannel  -- Mono routing to specific channel
                    
                    reaper.SetTrackSendInfo_Value(childTrack, 0, sendIdx, "I_DSTCHAN", dstChannels)
                    break
                end
            end
            
            channelIndex = channelIndex + 1
        end
        
        -- Update depth tracking
        local childDepth = reaper.GetMediaTrackInfo_Value(childTrack, "I_FOLDERDEPTH")
        depth = depth + childDepth
        trackIdx = trackIdx + 1
    end
    
    return true
end

-- Check if there are active conflicts requiring resolution
function ConflictResolver.hasActiveConflicts()
    return globals.showConflictModal and globals.pendingConflictData ~= nil
end

-- Clear all conflict data and close modal
function ConflictResolver.clearConflicts()
    globals.showConflictModal = false
    globals.pendingConflictData = nil
    globals.pendingResolutionData = nil
    conflictData = nil
    resolutionData = nil
end

return ConflictResolver