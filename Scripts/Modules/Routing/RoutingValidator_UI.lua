--[[
@version 1.0
@noindex
DM Ambiance Creator - Routing Validator UI Module
User interface rendering, modals, and display functions.
--]]

local RoutingValidator_UI = {}
local globals = {}
local Constants = nil
local Core = nil
local Detection = nil
local Fixes = nil

-- Local UI state
local showModal = false
local validationData = nil
local issuesList = nil
local fixSuggestions = nil
local autoFixEnabled = false
local shouldOpenModal = false

-- Channel order resolution modal state
local channelOrderConflictData = nil
local shouldOpenChannelOrderModal = false

function RoutingValidator_UI.initModule(g)
    globals = g
    Constants = require("DM_Ambiance_Constants")
end

function RoutingValidator_UI.setDependencies(core, detection, fixes)
    Core = core
    Detection = detection
    Fixes = fixes
end

-- Sync state from Core module
local function syncStateFromCore()
    local state = Core.getState()
    showModal = state.showModal
    validationData = state.validationData
    issuesList = state.issuesList
    fixSuggestions = state.fixSuggestions
    autoFixEnabled = state.autoFixEnabled
    shouldOpenModal = state.shouldOpenModal
    channelOrderConflictData = state.channelOrderConflictData
    shouldOpenChannelOrderModal = state.shouldOpenChannelOrderModal
end

-- Sync state back to Core module
local function syncStateToCore()
    Core.setState({
        showModal = showModal,
        validationData = validationData,
        issuesList = issuesList,
        fixSuggestions = fixSuggestions,
        autoFixEnabled = autoFixEnabled,
        shouldOpenModal = shouldOpenModal,
        channelOrderConflictData = channelOrderConflictData,
        shouldOpenChannelOrderModal = shouldOpenChannelOrderModal
    })
end

-- ===================================================================
-- USER INTERFACE
-- ===================================================================

-- Show the routing validation modal window
function RoutingValidator_UI.showValidationModal(issues, suggestions)
    if not issues then return end

    syncStateFromCore()

    local projectTrackCache = Core.getState().projectTrackCache
    validationData = projectTrackCache
    globals.pendingIssuesList = issues
    fixSuggestions = suggestions or Fixes.generateFixSuggestions(issues, validationData)

    globals.pendingValidationData = validationData
    shouldOpenModal = true

    syncStateToCore()
end

-- Get a human-readable description of what the fix will do
local function getFixDescription(issue)
    local ISSUE_TYPES = Core.getIssueTypes()

    if issue.type == ISSUE_TYPES.CHANNEL_ORDER_CONFLICT then
        return "Requires user choice between channel order variants"
    elseif issue.type == ISSUE_TYPES.CHANNEL_CONFLICT then
        if issue.conflictData and issue.conflictData.masterFormat then
            local masterName = issue.conflictData.masterFormat.config.name or "Master"
            return string.format("Realign routing to match %s format", masterName)
        end
        return "Realign routing to match master format"
    elseif issue.type == ISSUE_TYPES.PARENT_INSUFFICIENT_CHANNELS then
        if issue.suggestedFix and issue.suggestedFix.channels then
            return string.format("Increase track to %d channels", issue.suggestedFix.channels)
        end
        return "Increase track channel count"
    elseif issue.type == ISSUE_TYPES.PARENT_EXCESSIVE_CHANNELS then
        if issue.suggestedFix and issue.suggestedFix.channels then
            return string.format("Reduce track to %d channels", issue.suggestedFix.channels)
        end
        return "Reduce track channel count"
    elseif issue.type == ISSUE_TYPES.ORPHAN_SEND then
        if issue.sendData then
            local channelNum = Core.parseDstChannel(issue.sendData.dstChannel)
            return string.format("Increase destination track to %d channels", channelNum)
        end
        return "Increase destination track channel count"
    end

    return "Apply automatic fix"
end

-- Render the routing validation modal
function RoutingValidator_UI.renderModal()
    local ctx = globals.ctx
    local imgui = globals.imgui

    syncStateFromCore()

    -- Open popup when requested
    if shouldOpenModal then
        imgui.OpenPopup(ctx, "Project Routing Validator")
        shouldOpenModal = false
        syncStateToCore()
    end

    -- SetNextWindowSize must be called before BeginPopupModal
    imgui.SetNextWindowSize(ctx, 1400, 800, imgui.Cond_FirstUseEver)

    -- BeginPopupModal must be called every frame, it only shows if OpenPopup was called
    if imgui.BeginPopupModal(ctx, "Project Routing Validator", true, imgui.WindowFlags_NoCollapse) then
        -- Get window dimensions for proper layout
        local windowWidth, windowHeight = imgui.GetWindowSize(ctx)
        local headerHeight = 80
        local footerHeight = 100
        local contentHeight = windowHeight - headerHeight - footerHeight - 20

        -- Header
        RoutingValidator_UI.renderHeader(ctx, imgui)

        -- Create scrollable content area
        if imgui.BeginChild(ctx, "ValidationContentArea", 0, contentHeight) then
            -- Tab bar for different views
            if imgui.BeginTabBar(ctx, "ValidationTabs") then

                -- Tab 1: Issues Overview
                if imgui.BeginTabItem(ctx, "Issues Overview") then
                    RoutingValidator_UI.renderIssuesOverview(ctx, imgui)
                    imgui.EndTabItem(ctx)
                end

                -- Tab 2: Project Tree
                if imgui.BeginTabItem(ctx, "Project Tree") then
                    RoutingValidator_UI.renderProjectTree(ctx, imgui)
                    imgui.EndTabItem(ctx)
                end

                -- Tab 3: Channel Map
                if imgui.BeginTabItem(ctx, "Channel Map") then
                    RoutingValidator_UI.renderChannelMap(ctx, imgui)
                    imgui.EndTabItem(ctx)
                end

                -- Tab 4: Fix Suggestions
                if imgui.BeginTabItem(ctx, "Fix Suggestions") then
                    RoutingValidator_UI.renderFixSuggestions(ctx, imgui)
                    imgui.EndTabItem(ctx)
                end

                imgui.EndTabBar(ctx)
            end
        end
        imgui.EndChild(ctx)

        -- Footer with buttons
        RoutingValidator_UI.renderFooter(ctx, imgui)

        imgui.EndPopup(ctx)
    end
end

-- Render modal header
function RoutingValidator_UI.renderHeader(ctx, imgui)
    local SEVERITY = Core.getSeverity()
    local issuesCount = globals.pendingIssuesList and #globals.pendingIssuesList or 0
    local errorCount = 0
    local warningCount = 0

    if globals.pendingIssuesList then
        for _, issue in ipairs(globals.pendingIssuesList) do
            if issue.severity == SEVERITY.ERROR then
                errorCount = errorCount + 1
            elseif issue.severity == SEVERITY.WARNING then
                warningCount = warningCount + 1
            end
        end
    end

    -- Title with status
    if issuesCount == 0 then
        imgui.PushStyleColor(ctx, imgui.Col_Text, 0x00FF00FF)
        imgui.Text(ctx, "Project Routing Validation - All OK")
        imgui.PopStyleColor(ctx)
    else
        imgui.PushStyleColor(ctx, imgui.Col_Text, 0xFF8800FF)
        imgui.Text(ctx, string.format("Project Routing Validation - %d Issues Found", issuesCount))
        imgui.PopStyleColor(ctx)
    end

    -- Status breakdown
    if issuesCount > 0 then
        imgui.Spacing(ctx)
        imgui.Text(ctx, string.format("Errors: %d | Warnings: %d | Info: %d",
            errorCount, warningCount, issuesCount - errorCount - warningCount))
    end

    -- Auto-fix option
    imgui.Spacing(ctx)
    local autoFix = globals.autoFixRouting or false
    local changed, newAutoFix = imgui.Checkbox(ctx, "Auto-fix routing issues after generation", autoFix)
    if changed then
        globals.autoFixRouting = newAutoFix
    end

    imgui.Separator(ctx)
    imgui.Spacing(ctx)
end

-- Render issues overview tab
function RoutingValidator_UI.renderIssuesOverview(ctx, imgui)
    local SEVERITY = Core.getSeverity()

    if not globals.pendingIssuesList or #globals.pendingIssuesList == 0 then
        imgui.PushStyleColor(ctx, imgui.Col_Text, 0x00FF00FF)
        imgui.Text(ctx, "No routing issues detected!")
        imgui.PopStyleColor(ctx)
        imgui.Text(ctx, "All channel routing in the project appears to be correct.")
        return
    end

    imgui.Text(ctx, "The following routing issues were detected:")
    imgui.Spacing(ctx)

    -- Issues table
    if imgui.BeginTable(ctx, "IssuesTable", 6,
        imgui.TableFlags_Borders | imgui.TableFlags_RowBg | imgui.TableFlags_Resizable | imgui.TableFlags_Sortable) then

        -- Headers
        imgui.TableSetupColumn(ctx, "Severity", imgui.TableColumnFlags_WidthFixed, 80)
        imgui.TableSetupColumn(ctx, "Type", imgui.TableColumnFlags_WidthFixed, 120)
        imgui.TableSetupColumn(ctx, "Track", imgui.TableColumnFlags_WidthStretch, 0)
        imgui.TableSetupColumn(ctx, "Description", imgui.TableColumnFlags_WidthStretch, 0)
        imgui.TableSetupColumn(ctx, "Proposed Fix", imgui.TableColumnFlags_WidthStretch, 0)
        imgui.TableSetupColumn(ctx, "Action", imgui.TableColumnFlags_WidthFixed, 100)
        imgui.TableHeadersRow(ctx)

        -- Display issues
        for i, issue in ipairs(globals.pendingIssuesList) do
            imgui.TableNextRow(ctx)

            -- Severity
            imgui.TableNextColumn(ctx)
            local severityColor = 0xAAAAAAFF
            local severityIcon = "i"
            if issue.severity == SEVERITY.ERROR then
                severityColor = 0xFF0000FF
                severityIcon = "X"
            elseif issue.severity == SEVERITY.WARNING then
                severityColor = 0xFFAA00FF
                severityIcon = "!"
            end

            imgui.PushStyleColor(ctx, imgui.Col_Text, severityColor)
            imgui.Text(ctx, string.format("%s %s", severityIcon, string.upper(issue.severity)))
            imgui.PopStyleColor(ctx)

            -- Type
            imgui.TableNextColumn(ctx)
            imgui.Text(ctx, issue.type:gsub("_", " "):upper())

            -- Track
            imgui.TableNextColumn(ctx)
            local trackName = issue.track and issue.track.name or "N/A"
            imgui.Text(ctx, trackName)

            -- Description
            imgui.TableNextColumn(ctx)
            imgui.TextWrapped(ctx, issue.description)

            -- Proposed Fix
            imgui.TableNextColumn(ctx)
            local fixDescription = getFixDescription(issue)
            imgui.PushStyleColor(ctx, imgui.Col_Text, 0x88CCFFFF)
            imgui.TextWrapped(ctx, fixDescription)
            imgui.PopStyleColor(ctx)

            -- Action
            imgui.TableNextColumn(ctx)
            if imgui.SmallButton(ctx, "Fix##" .. i) then
                RoutingValidator_UI.fixSingleIssue(issue)
            end
        end

        imgui.EndTable(ctx)
    end
end

-- Render project tree tab
function RoutingValidator_UI.renderProjectTree(ctx, imgui)
    if not globals.pendingValidationData then
        imgui.Text(ctx, "No validation data available")
        return
    end

    imgui.Text(ctx, "Project Track Hierarchy:")
    imgui.Spacing(ctx)

    -- Master track
    if globals.pendingValidationData.master then
        RoutingValidator_UI.renderTrackNode(ctx, imgui, globals.pendingValidationData.master, 0)
    end

    -- Top-level tracks
    for _, trackInfo in ipairs(globals.pendingValidationData.topLevelTracks) do
        RoutingValidator_UI.renderTrackNode(ctx, imgui, trackInfo, 0)
    end
end

-- Render a single track node in the tree
function RoutingValidator_UI.renderTrackNode(ctx, imgui, trackInfo, depth)
    local indent = depth * 20

    imgui.Indent(ctx, indent)

    -- Track icon and name
    local icon = trackInfo.isMaster and "[M]" or (trackInfo.isFromTool and "[T]" or "[>]")
    local hasIssues = #trackInfo.issues > 0
    local textColor = hasIssues and 0xFF8800FF or (trackInfo.isFromTool and 0x00FFFFAA or 0xAAAAAAFF)

    imgui.PushStyleColor(ctx, imgui.Col_Text, textColor)
    imgui.Text(ctx, string.format("%s %s (ch: %d)", icon, trackInfo.name, trackInfo.channelCount))
    imgui.PopStyleColor(ctx)

    -- Show sends routing information if any
    if trackInfo.sends and #trackInfo.sends > 0 then
        imgui.Indent(ctx, 10)
        for _, send in ipairs(trackInfo.sends) do
            local destTrackName = send.destTrack and reaper.GetTrackName(send.destTrack) or "Unknown"

            -- Parse source and destination channels for display
            local srcChan = send.srcChannel
            local dstChan = send.dstChannel

            local srcDisplay, dstDisplay

            -- Parse source channel
            if srcChan >= 1024 then
                local ch = srcChan - 1024 + 1
                srcDisplay = string.format("Ch %d (mono)", ch)
            elseif srcChan >= 0 then
                local ch1 = srcChan + 1
                local ch2 = srcChan + 2
                srcDisplay = string.format("Ch %d-%d (stereo)", ch1, ch2)
            else
                srcDisplay = string.format("Ch %d", srcChan)
            end

            -- Parse destination channel
            if dstChan >= 1024 then
                local ch = dstChan - 1024 + 1
                dstDisplay = string.format("Ch %d (mono)", ch)
            elseif dstChan >= 0 then
                local ch1 = dstChan + 1
                local ch2 = dstChan + 2
                dstDisplay = string.format("Ch %d-%d (stereo)", ch1, ch2)
            else
                dstDisplay = string.format("Ch %d", dstChan)
            end

            imgui.PushStyleColor(ctx, imgui.Col_Text, 0x8888AAFF)
            imgui.Text(ctx, string.format("-> Send to '%s': %s -> %s", destTrackName, srcDisplay, dstDisplay))
            imgui.PopStyleColor(ctx)
        end
        imgui.Unindent(ctx, 10)
    end

    -- Show issues if any
    if hasIssues then
        imgui.Indent(ctx, 10)
        for _, issue in ipairs(trackInfo.issues) do
            imgui.PushStyleColor(ctx, imgui.Col_Text, 0xFF0000FF)
            imgui.Text(ctx, "! " .. issue.description)
            imgui.PopStyleColor(ctx)
        end
        imgui.Unindent(ctx, 10)
    end

    -- Render children
    for _, child in ipairs(trackInfo.children) do
        RoutingValidator_UI.renderTrackNode(ctx, imgui, child, depth + 1)
    end

    imgui.Unindent(ctx, indent)
end

-- Render channel map tab
function RoutingValidator_UI.renderChannelMap(ctx, imgui)
    if not globals.pendingValidationData then
        imgui.Text(ctx, "No validation data available")
        return
    end

    imgui.Text(ctx, "Channel Usage Map:")
    imgui.Spacing(ctx)

    -- Calculate channel usage
    local channelUsage = {}
    for _, trackInfo in ipairs(globals.pendingValidationData.toolTracks) do
        if trackInfo.isFromTool then
            local channelInfo = Detection.getTrackChannelInfo(trackInfo)
            if channelInfo then
                for _, channel in ipairs(channelInfo.channels) do
                    if not channelUsage[channel.channelNum] then
                        channelUsage[channel.channelNum] = {}
                    end
                    table.insert(channelUsage[channel.channelNum], {
                        track = trackInfo,
                        label = channel.label
                    })
                end
            end
        end
    end

    -- Render channel map
    for ch = 1, 16 do
        local usage = channelUsage[ch]

        if usage and #usage > 0 then
            -- Check for conflicts
            local labels = {}
            local hasConflict = false
            for _, u in ipairs(usage) do
                if not labels[u.label] then
                    labels[u.label] = {}
                end
                table.insert(labels[u.label], u.track.name)
            end

            local labelCount = 0
            for _, _ in pairs(labels) do
                labelCount = labelCount + 1
            end
            hasConflict = labelCount > 1

            -- Channel header
            imgui.Separator(ctx)
            local statusIcon = hasConflict and "!" or "+"
            local statusColor = hasConflict and 0xFF0000FF or 0x00FF00FF

            imgui.PushStyleColor(ctx, imgui.Col_Text, statusColor)
            imgui.Text(ctx, string.format("Channel %d %s", ch, statusIcon))
            imgui.PopStyleColor(ctx)

            -- List usage
            imgui.Indent(ctx, 20)
            for label, tracks in pairs(labels) do
                local color = hasConflict and 0xFF8800FF or 0xAAAAAAFF
                imgui.PushStyleColor(ctx, imgui.Col_Text, color)
                imgui.Text(ctx, string.format("%s: %s", label, table.concat(tracks, ", ")))
                imgui.PopStyleColor(ctx)
            end
            imgui.Unindent(ctx, 20)
        end
    end
end

-- Render fix suggestions tab
function RoutingValidator_UI.renderFixSuggestions(ctx, imgui)
    syncStateFromCore()

    if not fixSuggestions or #fixSuggestions == 0 then
        imgui.Text(ctx, "No fix suggestions available.")
        return
    end

    imgui.Text(ctx, "Proposed fixes for detected issues:")
    imgui.Spacing(ctx)

    for i, suggestion in ipairs(fixSuggestions) do
        imgui.Separator(ctx)
        imgui.Text(ctx, string.format("Fix %d: %s", i, suggestion.action:gsub("_", " "):upper()))
        imgui.Indent(ctx, 10)
        imgui.TextWrapped(ctx, suggestion.reason)

        if imgui.Button(ctx, "Apply This Fix##" .. i) then
            Fixes.applySingleFix(suggestion, false)
            -- Re-validate after fix
            globals.RoutingValidator.validateProjectRouting()
        end

        imgui.Unindent(ctx, 10)
        imgui.Spacing(ctx)
    end
end

-- Render modal footer
function RoutingValidator_UI.renderFooter(ctx, imgui)
    syncStateFromCore()

    imgui.Separator(ctx)
    imgui.Spacing(ctx)

    -- Auto-fix all button
    if fixSuggestions and #fixSuggestions > 0 then
        imgui.PushStyleColor(ctx, imgui.Col_Button, 0x0088FFFF)
        if imgui.Button(ctx, "Auto-Fix All Issues", 200, 35) then
            Fixes.autoFixRouting(globals.pendingIssuesList, fixSuggestions)
            imgui.CloseCurrentPopup(ctx)
        end
        imgui.PopStyleColor(ctx)
        imgui.SameLine(ctx)
    end

    -- Re-validate button
    if imgui.Button(ctx, "Re-Validate", 120, 35) then
        Core.clearCache()
        local newIssues = globals.RoutingValidator.validateProjectRouting()
        imgui.CloseCurrentPopup(ctx)
        RoutingValidator_UI.showValidationModal(newIssues, fixSuggestions)
    end

    imgui.SameLine(ctx)

    -- Close button
    if imgui.Button(ctx, "Close", 120, 35) then
        imgui.CloseCurrentPopup(ctx)
    end
end

-- Fix a single issue
function RoutingValidator_UI.fixSingleIssue(issue)
    local suggestion = Fixes.generateFixSuggestion(issue, globals.pendingValidationData)
    if suggestion then
        Fixes.applySingleFix(suggestion, false)
        Core.clearCache()
        local newIssues = globals.RoutingValidator.validateProjectRouting()
        RoutingValidator_UI.showValidationModal(newIssues, fixSuggestions)
    end
end

-- ===================================================================
-- CHANNEL ORDER RESOLUTION MODAL
-- ===================================================================

-- Show channel order conflict resolution modal
function RoutingValidator_UI.showChannelOrderResolutionModal(suggestion)
    syncStateFromCore()
    channelOrderConflictData = suggestion
    shouldOpenChannelOrderModal = true
    syncStateToCore()
end

-- Render channel order resolution modal
function RoutingValidator_UI.renderChannelOrderModal()
    local ctx = globals.ctx
    local imgui = globals.imgui

    syncStateFromCore()

    if not channelOrderConflictData then return end

    -- Open popup when requested
    if shouldOpenChannelOrderModal then
        imgui.OpenPopup(ctx, "Channel Order Conflict Resolution")
        shouldOpenChannelOrderModal = false
        syncStateToCore()
    end

    -- SetNextWindowSize must be called before BeginPopupModal
    imgui.SetNextWindowSize(ctx, 600, 400, imgui.Cond_FirstUseEver)

    -- BeginPopupModal must be called every frame, it only shows if OpenPopup was called
    if imgui.BeginPopupModal(ctx, "Channel Order Conflict Resolution", true, imgui.WindowFlags_NoCollapse) then
        local conflictData = channelOrderConflictData.conflictData

        -- Header
        imgui.PushStyleColor(ctx, imgui.Col_Text, 0xFF8800FF)
        imgui.Text(ctx, "! Channel Order Conflict Detected!")
        imgui.PopStyleColor(ctx)

        imgui.Separator(ctx)
        imgui.Spacing(ctx)

        -- Description
        imgui.TextWrapped(ctx, string.format(
            "Two %s.0 containers use different channel orders. A session can only use one channel order per configuration type.",
            conflictData.channelMode))

        imgui.Spacing(ctx)
        imgui.Spacing(ctx)

        -- Show the conflict details
        imgui.Text(ctx, "Conflicting configurations:")
        imgui.Spacing(ctx)

        -- Option 1
        imgui.PushStyleColor(ctx, imgui.Col_Button, 0x0088AAFF)
        if imgui.Button(ctx, string.format("Use: %s", conflictData.variantName1), 250, 40) then
            RoutingValidator_UI.applyChannelOrderChoice(conflictData.variant1, conflictData.channelMode)
            channelOrderConflictData = nil
            syncStateToCore()
            imgui.CloseCurrentPopup(ctx)
        end
        imgui.PopStyleColor(ctx)

        imgui.SameLine(ctx)
        imgui.Text(ctx, string.format("(Container: %s)", conflictData.container1.name or "Unknown"))

        imgui.Spacing(ctx)

        -- Option 2
        imgui.PushStyleColor(ctx, imgui.Col_Button, 0x0088AAFF)
        if imgui.Button(ctx, string.format("Use: %s", conflictData.variantName2), 250, 40) then
            RoutingValidator_UI.applyChannelOrderChoice(conflictData.variant2, conflictData.channelMode)
            channelOrderConflictData = nil
            syncStateToCore()
            imgui.CloseCurrentPopup(ctx)
        end
        imgui.PopStyleColor(ctx)

        imgui.SameLine(ctx)
        imgui.Text(ctx, string.format("(Container: %s)", conflictData.container2.name or "Unknown"))

        imgui.Spacing(ctx)
        imgui.Spacing(ctx)
        imgui.Separator(ctx)

        -- Footer
        imgui.Spacing(ctx)
        imgui.TextWrapped(ctx, "All containers of this type will be updated to use the chosen channel order.")

        imgui.Spacing(ctx)

        -- Cancel button
        local buttonWidth = 100
        local avail = imgui.GetContentRegionAvail(ctx)
        imgui.SetCursorPosX(ctx, imgui.GetCursorPosX(ctx) + (avail - buttonWidth) * 0.5)

        if imgui.Button(ctx, "Cancel", buttonWidth, 30) then
            channelOrderConflictData = nil
            syncStateToCore()
            imgui.CloseCurrentPopup(ctx)
        end

        imgui.EndPopup(ctx)
    end
end

-- Apply channel order choice to all containers of the same type
function RoutingValidator_UI.applyChannelOrderChoice(chosenVariant, channelMode)
    reaper.Undo_BeginBlock()

    local success = true
    local containersUpdated = 0

    -- Find all containers with the same channel mode and update their variant
    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if container.channelMode then
                local config = Constants.CHANNEL_CONFIGS[container.channelMode]
                if config and config.channels == channelMode then
                    local oldVariant = container.channelVariant or 0
                    container.channelVariant = chosenVariant

                    if oldVariant ~= chosenVariant then
                        container.needsRegeneration = true
                        containersUpdated = containersUpdated + 1
                    end
                end
            end
        end
    end

    -- If any containers were updated, regenerate the affected tracks
    if containersUpdated > 0 and globals.Generation then
        globals.Generation.generateGroups()
    end

    reaper.Undo_EndBlock(string.format("Apply %s Channel Order",
        Core.getVariantName(channelMode, chosenVariant)), -1)

    -- Clear cache and re-validate
    Core.clearCache()
    local newIssues = globals.RoutingValidator.validateProjectRouting()

    -- Show validation modal if there are remaining issues
    if newIssues and #newIssues > 0 then
        RoutingValidator_UI.showValidationModal(newIssues)
    end

    return success
end

-- ===================================================================
-- UTILITY FUNCTIONS
-- ===================================================================

-- Check if there are active validation issues requiring attention
function RoutingValidator_UI.hasActiveIssues()
    return globals.showRoutingModal and globals.pendingIssuesList and #globals.pendingIssuesList > 0
end

-- Clear all validation data and close modal
function RoutingValidator_UI.clearValidation()
    syncStateFromCore()

    globals.showRoutingModal = false
    globals.pendingValidationData = nil
    globals.pendingIssuesList = nil
    validationData = nil
    issuesList = nil
    fixSuggestions = nil

    syncStateToCore()
end

-- Entry point for the new validation system
function RoutingValidator_UI.validateAndShow()
    local issues = globals.RoutingValidator.validateProjectRouting()

    if issues and #issues > 0 then
        if globals.autoFixRouting then
            local projectTrackCache = Core.getState().projectTrackCache
            local suggestions = Fixes.generateFixSuggestions(issues, projectTrackCache)
            Fixes.autoFixRouting(issues, suggestions)
        else
            RoutingValidator_UI.showValidationModal(issues)
        end
    else
        RoutingValidator_UI.checkOptimizationOpportunities()
    end

    return issues
end

-- Check for channel optimization opportunities
function RoutingValidator_UI.checkOptimizationOpportunities()
    local projectTrackCache = Core.getState().projectTrackCache
    if not projectTrackCache then return end

    local optimizationNeeded = false
    local savings = {}

    -- Check if any tracks have more channels than needed
    for _, trackInfo in pairs(projectTrackCache.allTracks) do
        if trackInfo and trackInfo.track then
            local currentChannels = trackInfo.channelCount
            local requiredChannels = Detection.getTrackRequiredChannels(trackInfo)

            if currentChannels > requiredChannels then
                optimizationNeeded = true
                table.insert(savings, {
                    track = trackInfo,
                    current = currentChannels,
                    required = requiredChannels,
                    savings = currentChannels - requiredChannels
                })
            end
        end
    end

    if optimizationNeeded then
        if globals.autoOptimizeChannels then
            RoutingValidator_UI.applyChannelOptimization(savings)
        else
            RoutingValidator_UI.showOptimizationSuggestion(savings)
        end
    end
end

-- Apply channel optimization
function RoutingValidator_UI.applyChannelOptimization(savings)
    reaper.Undo_BeginBlock()

    for _, saving in ipairs(savings) do
        reaper.SetMediaTrackInfo_Value(saving.track.track, "I_NCHAN", saving.required)
    end

    reaper.Undo_EndBlock("Optimize Channel Count", -1)

    Core.clearCache()
end

-- Show optimization suggestion to user
function RoutingValidator_UI.showOptimizationSuggestion(savings)
    local totalSavings = 0
    for _, saving in ipairs(savings) do
        totalSavings = totalSavings + saving.savings
    end
    -- Suggestion available but not shown (could be logged or displayed in UI)
end

-- ===================================================================
-- TEST AND DEBUG FUNCTIONS
-- ===================================================================

-- Test function to verify the complete routing validation system
function RoutingValidator_UI.testValidationSystem()
    local SEVERITY = Core.getSeverity()

    if not globals or not globals.groups then
        return "No groups available for testing"
    end

    local results = {
        "=== Routing Validation System Test ===",
        ""
    }

    -- Test 1: Basic validation
    table.insert(results, "1. Running full project validation...")
    local issues = globals.RoutingValidator.validateProjectRouting()
    table.insert(results, string.format("   Found %d issues", issues and #issues or 0))

    -- Test 2: Channel order conflict detection
    table.insert(results, "")
    table.insert(results, "2. Testing channel order conflict detection...")
    local projectTree = Core.scanAllProjectTracks()
    local channelOrderConflicts = Detection.detectChannelOrderConflicts(projectTree)
    table.insert(results, string.format("   Found %d channel order conflicts", #channelOrderConflicts))

    -- Test 3: Master format detection
    table.insert(results, "")
    table.insert(results, "3. Testing master format detection...")
    local masterFormat = Detection.findMasterFormat(projectTree)
    if masterFormat then
        table.insert(results, string.format("   Master format: %s (%d channels)",
            masterFormat.config.name or "Unknown", masterFormat.config.channels or 0))
    else
        table.insert(results, "   No master format detected")
    end

    -- Test 4: Reference routing creation
    if masterFormat then
        table.insert(results, "")
        table.insert(results, "4. Testing reference routing creation...")
        local referenceRouting = Detection.createReferenceRouting(masterFormat)
        local refCount = 0
        for label, channel in pairs(referenceRouting) do
            refCount = refCount + 1
        end
        table.insert(results, string.format("   Created reference routing with %d mappings", refCount))
    end

    -- Test 5: Summary
    table.insert(results, "")
    table.insert(results, "5. System status:")
    if issues and #issues > 0 then
        local errorCount = 0
        local warningCount = 0
        for _, issue in ipairs(issues) do
            if issue.severity == SEVERITY.ERROR then
                errorCount = errorCount + 1
            elseif issue.severity == SEVERITY.WARNING then
                warningCount = warningCount + 1
            end
        end
        table.insert(results, string.format("   Errors: %d, Warnings: %d", errorCount, warningCount))
    else
        table.insert(results, "   + All validation tests passed")
    end

    table.insert(results, "")
    table.insert(results, "=== Test Complete ===")

    return table.concat(results, "\n")
end

-- Debug function to print current validation state
function RoutingValidator_UI.debugValidationState()
    if not globals then return "No globals available" end

    syncStateFromCore()
    local state = Core.getState()

    local debug = {
        "=== Routing Validator Debug State ===",
        "",
        string.format("showRoutingModal: %s", tostring(globals.showRoutingModal)),
        string.format("autoFixRouting: %s", tostring(globals.autoFixRouting)),
        string.format("pendingIssuesList: %s", globals.pendingIssuesList and #globals.pendingIssuesList or "nil"),
        string.format("shouldOpenChannelOrderModal: %s", tostring(shouldOpenChannelOrderModal)),
        string.format("channelOrderConflictData: %s", channelOrderConflictData and "present" or "nil"),
        string.format("projectTrackCache: %s", state.projectTrackCache and "cached" or "nil"),
        string.format("lastValidationTime: %.2f", state.lastValidationTime)
    }

    return table.concat(debug, "\n")
end

return RoutingValidator_UI
