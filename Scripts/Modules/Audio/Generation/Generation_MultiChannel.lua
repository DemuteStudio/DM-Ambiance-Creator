--[[
@version 1.0
@noindex
DM Ambiance Creator - Generation Multi-Channel Module
Multi-channel routing, configuration management, and channel optimization.
--]]

local Generation_MultiChannel = {}
local globals = {}

-- Dependencies (set by aggregator)
local Generation_TrackManagement = nil

function Generation_MultiChannel.initModule(g)
    globals = g
end

function Generation_MultiChannel.setDependencies(trackMgmt)
    Generation_TrackManagement = trackMgmt
end

-- Map a channel label (L, R, C, LS, RS, etc.) to a channel number
-- Handles both ITU/Dolby and SMPTE variants, and different output formats (4.0, 5.0, 7.0)
function Generation_MultiChannel.labelToChannelNumber(label, config, channelVariant)
    -- Determine output format
    local numChannels = config and config.channels or 2

    local labelToChannel = {}

    if numChannels == 4 then
        -- 4.0 Quad: L R LS RS (no center)
        labelToChannel = {
            ["L"] = 1, ["R"] = 2, ["LS"] = 3, ["RS"] = 4
        }
    elseif numChannels == 5 then
        -- 5.0 Surround
        if config.hasVariants and channelVariant == 1 then
            -- SMPTE: L C R LS RS
            labelToChannel = {
                ["L"] = 1, ["C"] = 2, ["R"] = 3, ["LS"] = 4, ["RS"] = 5
            }
        else
            -- ITU/Dolby: L R C LS RS
            labelToChannel = {
                ["L"] = 1, ["R"] = 2, ["C"] = 3, ["LS"] = 4, ["RS"] = 5
            }
        end
    elseif numChannels == 7 then
        -- 7.0 Surround
        if config.hasVariants and channelVariant == 1 then
            -- SMPTE: L C R LS RS LB RB
            labelToChannel = {
                ["L"] = 1, ["C"] = 2, ["R"] = 3, ["LS"] = 4, ["RS"] = 5, ["LB"] = 6, ["RB"] = 7
            }
        else
            -- ITU/Dolby: L R C LS RS LB RB
            labelToChannel = {
                ["L"] = 1, ["R"] = 2, ["C"] = 3, ["LS"] = 4, ["RS"] = 5, ["LB"] = 6, ["RB"] = 7
            }
        end
    else
        -- Default stereo or unknown: L R
        labelToChannel = {
            ["L"] = 1, ["R"] = 2
        }
    end

    return labelToChannel[label]
end

-- Apply routing fixes to resolve conflicts
-- @param suggestions table: Array of routing suggestions
function Generation_MultiChannel.applyRoutingFixes(suggestions)
    for _, suggestion in ipairs(suggestions) do
        local container = suggestion.container

        -- Update the container's channel configuration with custom routing
        container.customRouting = suggestion.newRouting

        -- Find and update the actual tracks if they exist
        local group = nil
        for _, g in ipairs(globals.groups) do
            if g.name == suggestion.groupName then
                group = g
                break
            end
        end

        if group then
            local groupTrack, groupTrackIdx = globals.Utils.findGroupByName(group.name)
            if groupTrack then
                local containerTrack, containerTrackIdx = globals.Utils.findContainerGroup(
                    groupTrackIdx,
                    container.name
                )

                if containerTrack then
                    -- Update the routing of existing channel tracks
                    local channelTracks = Generation_TrackManagement.getExistingChannelTracks(containerTrack)
                    for i, channelTrack in ipairs(channelTracks) do
                        if i <= #suggestion.newRouting then
                            -- Update the send routing to new channel
                            local sendCount = reaper.GetTrackNumSends(channelTrack, 0)
                            for s = 0, sendCount - 1 do
                                local destTrack = reaper.GetTrackSendInfo_Value(channelTrack, 0, s, "P_DESTTRACK")
                                if destTrack == containerTrack then
                                    local newDestChannel = suggestion.newRouting[i] - 1
                                    local dstChannels = 1024 + newDestChannel  -- Mono routing format
                                    reaper.SetTrackSendInfo_Value(channelTrack, 0, s, "I_DSTCHAN", dstChannels)

                                    -- Update track name with new channel label if needed
                                    local channelLabel = suggestion.labels[i]
                                    local trackName = container.name .. " - " .. channelLabel
                                    reaper.GetSetMediaTrackInfo_String(channelTrack, "P_NAME", trackName, true)
                                end
                            end
                        end
                    end

                    -- Update container and parent track channel count if needed
                    local maxChannel = math.max(table.unpack(suggestion.newRouting))
                    reaper.SetMediaTrackInfo_Value(containerTrack, "I_NCHAN", maxChannel)
                    globals.Utils.ensureParentHasEnoughChannels(containerTrack, maxChannel)
                end
            end
        end
    end

    reaper.UpdateArrange()
end

-- ===================================================================
-- CHANNEL OPTIMIZATION AND RECALCULATION
-- ===================================================================

-- Recalculate channel requirements bottom-up: children define parent needs
-- CRITICAL: Now uses REAL track counts, not theoretical configuration
-- ENHANCED: Detects orphaned tracks (tracks without corresponding containers)
function Generation_MultiChannel.recalculateChannelRequirements()
    if not globals.groups or #globals.groups == 0 then
        return
    end

    -- STEP 0: Detect orphaned container tracks (tracks without matching tool containers)
    Generation_TrackManagement.detectOrphanedContainerTracks()

    -- reaper.ShowConsoleMsg("INFO: Starting bottom-up channel recalculation (REAL tracks)...\n")

    -- Phase 1: Calculate actual requirements for each container based on REAL tracks
    local containerRequirements = {}

    for _, group in ipairs(globals.groups) do
        for _, container in ipairs(group.containers) do
            if container.channelMode and container.channelMode > 0 then
                -- Get the REAL number of child tracks
                local realChildCount = Generation_MultiChannel.getExistingChildTrackCount(container)

                if realChildCount and realChildCount > 0 then
                    -- Use REAL count, not theoretical config
                    local requiredChannels = realChildCount

                    -- Apply REAPER even constraint
                    if requiredChannels % 2 == 1 then
                        requiredChannels = requiredChannels + 1
                    end

                    containerRequirements[container.name] = {
                        logicalChannels = realChildCount,  -- REAL count
                        physicalChannels = requiredChannels,
                        container = container,
                        group = group
                    }

                    -- reaper.ShowConsoleMsg(string.format("INFO: Container '%s' has %d REAL tracks → requires %d physical channels\n",
                    --     container.name, realChildCount, requiredChannels))
                else
                    -- No child tracks: could be perfect-match-passthrough or not generated yet
                    -- Check if container track exists and already has channel count set
                    local containerTrack = Generation_MultiChannel.findContainerTrackRobust(container)
                    if containerTrack then
                        -- Use actual I_NCHAN from the track (handles perfect-match-passthrough)
                        local actualChannels = reaper.GetMediaTrackInfo_Value(containerTrack, "I_NCHAN")
                        if actualChannels > 0 then
                            containerRequirements[container.name] = {
                                logicalChannels = actualChannels,
                                physicalChannels = actualChannels,
                                container = container,
                                group = group
                            }
                            -- reaper.ShowConsoleMsg(string.format("INFO: Container '%s' (no children) has %d channels (from I_NCHAN)\n",
                            --     container.name, actualChannels))
                        end
                    else
                        -- Track doesn't exist yet, use theoretical config
                        local config = globals.Constants.CHANNEL_CONFIGS[container.channelMode]
                        if config then
                            local requiredChannels = config.totalChannels or config.channels
                            if requiredChannels % 2 == 1 then
                                requiredChannels = requiredChannels + 1
                            end

                            containerRequirements[container.name] = {
                                logicalChannels = requiredChannels,
                                physicalChannels = requiredChannels,
                                container = container,
                                group = group
                            }

                            -- reaper.ShowConsoleMsg(string.format("INFO: Container '%s' (no tracks yet) → requires %d channels (theoretical)\n",
                            --     container.name, requiredChannels))
                        end
                    end
                end
            end
        end
    end

    -- Phase 2: Calculate requirements for each group (MAX of real container channels)
    local groupRequirements = {}

    for _, group in ipairs(globals.groups) do
        local maxChannels = 2  -- Minimum stereo
        local containerCount = 0

        for _, container in ipairs(group.containers) do
            local req = containerRequirements[container.name]
            if req then
                -- Use the REAL physical channels (based on actual tracks)
                maxChannels = math.max(maxChannels, req.physicalChannels)
                containerCount = containerCount + 1
                -- reaper.ShowConsoleMsg(string.format("    Container '%s' contributes %d physical channels\n",
                --     container.name, req.physicalChannels))
            end
        end

        groupRequirements[group.name] = {
            requiredChannels = maxChannels,
            containerCount = containerCount,
            group = group
        }

        -- reaper.ShowConsoleMsg(string.format("INFO: Group '%s' MAX requirement: %d channels for %d containers\n",
        --     group.name, maxChannels, containerCount))
    end

    -- Phase 3: Calculate master track requirement (maximum of all REAL group channels)
    local masterRequirement = 2  -- Minimum stereo

    for groupName, req in pairs(groupRequirements) do
        local oldMaster = masterRequirement
        masterRequirement = math.max(masterRequirement, req.requiredChannels)
        if req.requiredChannels > oldMaster then
            -- reaper.ShowConsoleMsg(string.format("    Group '%s' increases master requirement: %d → %d channels\n",
            --     groupName, oldMaster, masterRequirement))
        end
    end

    -- reaper.ShowConsoleMsg(string.format("INFO: Master track FINAL requirement: %d channels (based on REAL group usage)\n", masterRequirement))

    -- Phase 4: Apply the calculated requirements to actual tracks
    Generation_MultiChannel.applyChannelRequirements(containerRequirements, groupRequirements, masterRequirement)

    -- reaper.ShowConsoleMsg("INFO: Bottom-up channel recalculation completed.\n")
end

-- Apply calculated channel requirements to actual REAPER tracks
function Generation_MultiChannel.applyChannelRequirements(containerReqs, groupReqs, masterReq)
    reaper.Undo_BeginBlock()

    -- ULTRATHINK FIX: Update container tracks using robust finder
    for containerName, req in pairs(containerReqs) do
        local containerTrack = Generation_MultiChannel.findContainerTrackRobust(req.container)
        if containerTrack then
            local currentChannels = reaper.GetMediaTrackInfo_Value(containerTrack, "I_NCHAN")
            if currentChannels ~= req.physicalChannels then
                -- reaper.ShowConsoleMsg(string.format("APPLY: Updating container '%s' from %d to %d channels\n",
                --     containerName, currentChannels, req.physicalChannels))

                -- Apply change with verification
                reaper.SetMediaTrackInfo_Value(containerTrack, "I_NCHAN", req.physicalChannels)

                -- MEGATHINK: Verify the change actually took effect
                local verifyChannels = reaper.GetMediaTrackInfo_Value(containerTrack, "I_NCHAN")
                if verifyChannels == req.physicalChannels then
                    -- reaper.ShowConsoleMsg(string.format("✅ APPLY SUCCESS: Container '%s' confirmed at %d channels\n",
                    --     containerName, verifyChannels))
                else
                    -- reaper.ShowConsoleMsg(string.format("❌ APPLY FAILED: Container '%s' still at %d channels (expected %d)\n",
                    --     containerName, verifyChannels, req.physicalChannels))

                    -- Force multiple attempts with UI refresh
                    for attempt = 1, 3 do
                        -- reaper.ShowConsoleMsg(string.format("MEGATHINK: Retry attempt %d for container '%s'\n", attempt, containerName))
                        reaper.SetMediaTrackInfo_Value(containerTrack, "I_NCHAN", req.physicalChannels)
                        reaper.UpdateArrange()
                        reaper.TrackList_AdjustWindows(false)
                        local retryCheck = reaper.GetMediaTrackInfo_Value(containerTrack, "I_NCHAN")
                        if retryCheck == req.physicalChannels then
                            -- reaper.ShowConsoleMsg(string.format("✅ SUCCESS on retry %d\n", attempt))
                            break
                        end
                    end
                end
            else
                -- reaper.ShowConsoleMsg(string.format("APPLY: Container '%s' already has %d channels\n",
                --     containerName, currentChannels))
            end
        else
            -- reaper.ShowConsoleMsg(string.format("APPLY: FAILED to find container track '%s'\n", containerName))
        end
    end

    -- ULTRATHINK FIX: Update group tracks using robust search
    for groupName, req in pairs(groupReqs) do
        local groupTrack = Generation_MultiChannel.findGroupTrackRobust(groupName)
        if groupTrack then
            local currentChannels = reaper.GetMediaTrackInfo_Value(groupTrack, "I_NCHAN")
            if currentChannels ~= req.requiredChannels then
                -- reaper.ShowConsoleMsg(string.format("APPLY: Updating group '%s' from %d to %d channels\n",
                --     groupName, currentChannels, req.requiredChannels))
                reaper.SetMediaTrackInfo_Value(groupTrack, "I_NCHAN", req.requiredChannels)
            else
                -- reaper.ShowConsoleMsg(string.format("APPLY: Group '%s' already has %d channels\n",
                --     groupName, currentChannels))
            end
        else
            -- reaper.ShowConsoleMsg(string.format("APPLY: FAILED to find group track '%s'\n", groupName))
        end
    end

    -- Update master track
    local masterTrack = reaper.GetMasterTrack(0)
    if masterTrack then
        local currentChannels = reaper.GetMediaTrackInfo_Value(masterTrack, "I_NCHAN")
        if currentChannels ~= masterReq then
            -- reaper.ShowConsoleMsg(string.format("APPLY: Updating master track from %d to %d channels\n",
            --     currentChannels, masterReq))
            reaper.SetMediaTrackInfo_Value(masterTrack, "I_NCHAN", masterReq)
        else
            -- reaper.ShowConsoleMsg(string.format("APPLY: Master track already has %d channels\n", currentChannels))
        end
    end

    reaper.Undo_EndBlock("Optimize Project Channel Count", -1)
end

-- Robust group track finder
function Generation_MultiChannel.findGroupTrackRobust(groupName)
    if not groupName then return nil end

    -- Search by name across all tracks
    local totalTracks = reaper.CountTracks(0)
    for i = 0, totalTracks - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local _, trackName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
            if trackName == groupName then
                -- reaper.ShowConsoleMsg(string.format("DEBUG: Found group '%s' at index %d\n", groupName, i))
                return track
            end
        end
    end

    -- reaper.ShowConsoleMsg(string.format("DEBUG: FAILED to find group track '%s'\n", groupName))
    return nil
end

-- Handle configuration downgrades (e.g., 5.0 → 4.0)
function Generation_MultiChannel.handleConfigurationDowngrade(container, oldChannelCount, newChannelCount)
    if newChannelCount >= oldChannelCount then
        return  -- Not a downgrade
    end

    -- reaper.ShowConsoleMsg(string.format("INFO: Handling downgrade for '%s': %d→%d channels\n",
    --     container.name or "unknown", oldChannelCount, newChannelCount))

    -- Find the container track
    local containerTrack = nil
    for _, group in ipairs(globals.groups or {}) do
        if group.containers then
            for _, cont in ipairs(group.containers) do
                if cont == container then
                    containerTrack = Generation_MultiChannel.findContainerTrack(group.name, container.name)
                    break
                end
            end
        end
        if containerTrack then break end
    end

    if not containerTrack then
        -- reaper.ShowConsoleMsg(string.format("WARNING: Could not find track for container '%s'\n", container.name))
        return
    end

    -- Remove excess child tracks
    Generation_MultiChannel.removeExcessChildTracks(containerTrack, oldChannelCount, newChannelCount)

    -- CRITICAL: Update container.channelMode to reflect the new configuration
    local newChannelMode = Generation_MultiChannel.detectChannelModeFromTrackCount(newChannelCount)
    if newChannelMode then
        local oldChannelMode = container.channelMode
        container.channelMode = newChannelMode
        -- reaper.ShowConsoleMsg(string.format("INFO: Updated channelMode for '%s': %d → %d\n",
        --     container.name, oldChannelMode, newChannelMode))
    end

    -- Clear corrupted customRouting
    if container.customRouting then
        -- reaper.ShowConsoleMsg(string.format("INFO: Clearing customRouting for '%s' due to downgrade\n", container.name))
        container.customRouting = nil
    end

    -- Force regeneration to apply new routing
    container.needsRegeneration = true

    -- reaper.ShowConsoleMsg(string.format("INFO: Downgrade handling completed for '%s'\n", container.name))
end

-- Detect channelMode from track count (inverse of config lookup)
function Generation_MultiChannel.detectChannelModeFromTrackCount(trackCount)
    -- Map track count to channelMode
    local trackCountToMode = {
        [2] = 0,  -- Default (Stereo)
        [4] = 1,  -- 4.0 Quad
        [5] = 2,  -- 5.0
        [7] = 3   -- 7.0
    }

    local newMode = trackCountToMode[trackCount]
    if newMode then
        -- reaper.ShowConsoleMsg(string.format("INFO: Detected channelMode %d for %d tracks\n", newMode, trackCount))
        return newMode
    else
        -- reaper.ShowConsoleMsg(string.format("WARNING: No channelMode mapping for %d tracks, keeping current\n", trackCount))
        return nil
    end
end

-- Remove excess child tracks during downgrade (FOLDER STRUCTURE SAFE)
function Generation_MultiChannel.removeExcessChildTracks(containerTrack, oldChannelCount, newChannelCount)
    if not containerTrack then return end

    local tracksToRemove = oldChannelCount - newChannelCount
    if tracksToRemove <= 0 then return end

    -- reaper.ShowConsoleMsg(string.format("INFO: Safely removing %d excess child tracks (folder aware)\n", tracksToRemove))

    -- STEP 1: Find all direct children of the container
    local childTracks = {}
    local totalTracks = reaper.CountTracks(0)

    for i = 0, totalTracks - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local parent = reaper.GetParentTrack(track)
            if parent == containerTrack then
                table.insert(childTracks, {
                    track = track,
                    index = i,
                    depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
                })
            end
        end
    end

    -- reaper.ShowConsoleMsg(string.format("INFO: Found %d child tracks before removal\n", #childTracks))

    if #childTracks ~= oldChannelCount then
        -- reaper.ShowConsoleMsg(string.format("WARNING: Expected %d children, found %d\n", oldChannelCount, #childTracks))
    end

    -- STEP 2: Determine which tracks to keep and which to remove
    local tracksToKeep = newChannelCount
    local tracksToDelete = {}

    -- Remove from the end (last tracks first)
    for i = #childTracks, tracksToKeep + 1, -1 do
        table.insert(tracksToDelete, childTracks[i])
    end

    -- reaper.ShowConsoleMsg(string.format("INFO: Will remove %d tracks, keep %d tracks\n", #tracksToDelete, tracksToKeep))

    -- STEP 3: CRITICAL - Adjust folder structure BEFORE removing tracks
    if tracksToKeep > 0 and #childTracks >= tracksToKeep then
        local newLastChild = childTracks[tracksToKeep]
        -- reaper.ShowConsoleMsg(string.format("INFO: Setting new last child (index %d) to I_FOLDERDEPTH = -1\n",
        --     newLastChild.index))
        reaper.SetMediaTrackInfo_Value(newLastChild.track, "I_FOLDERDEPTH", -1)
    end

    -- STEP 4: Remove tracks in reverse order to avoid index shifts
    for i = #tracksToDelete, 1, -1 do
        local trackInfo = tracksToDelete[i]
        -- reaper.ShowConsoleMsg(string.format("INFO: Removing child track at index %d (depth was %d)\n",
        --     trackInfo.index, trackInfo.depth))
        reaper.DeleteTrack(trackInfo.track)
    end

    -- STEP 5: Validate folder structure after removal
    Generation_MultiChannel.validateFolderStructure(containerTrack, newChannelCount)
end

-- Validate that folder structure is correct after track removal
function Generation_MultiChannel.validateFolderStructure(containerTrack, expectedChildren)
    local containerDepth = reaper.GetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH")

    if containerDepth ~= 1 then
        -- reaper.ShowConsoleMsg(string.format("WARNING: Container lost folder status (depth = %d, should be 1)\n", containerDepth))
        reaper.SetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH", 1)
    end

    -- Count remaining children
    local actualChildren = 0
    local totalTracks = reaper.CountTracks(0)
    local lastChild = nil

    for i = 0, totalTracks - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local parent = reaper.GetParentTrack(track)
            if parent == containerTrack then
                actualChildren = actualChildren + 1
                lastChild = track
            end
        end
    end

    -- reaper.ShowConsoleMsg(string.format("VALIDATE: Expected %d children, found %d children\n",
    --     expectedChildren, actualChildren))

    -- Ensure last child closes the folder
    if lastChild then
        local lastDepth = reaper.GetMediaTrackInfo_Value(lastChild, "I_FOLDERDEPTH")
        if lastDepth ~= -1 then
            -- reaper.ShowConsoleMsg("VALIDATE: Correcting last child folder depth to -1\n")
            reaper.SetMediaTrackInfo_Value(lastChild, "I_FOLDERDEPTH", -1)
        end
    end

    if actualChildren == expectedChildren then
        -- reaper.ShowConsoleMsg("VALIDATE: ✅ Folder structure is correct\n")
    else
        -- reaper.ShowConsoleMsg("VALIDATE: ❌ Folder structure mismatch\n")
    end
end

-- Detect configuration changes and handle them appropriately
function Generation_MultiChannel.detectAndHandleConfigurationChanges(container)
    if not container.channelMode then
        return  -- No configuration
    end

    -- ULTRATHINK FIX: Store and compare previous channelMode
    local currentChannelMode = container.channelMode
    local previousChannelMode = container.previousChannelMode

    -- Store current as previous for next time
    container.previousChannelMode = currentChannelMode

    if currentChannelMode == 0 then
        return  -- No multi-channel configuration
    end

    local config = globals.Constants.CHANNEL_CONFIGS[currentChannelMode]
    if not config then return end

    local newChannelCount = config.channels

    -- Get real track count
    local realTrackCount = Generation_MultiChannel.getExistingChildTrackCount(container)

    -- reaper.ShowConsoleMsg(string.format("DEBUG: Container '%s' - channelMode: %s→%d, config channels: %d, real tracks: %s\n",
    --     container.name or "unknown",
    --     previousChannelMode and tostring(previousChannelMode) or "nil",
    --     currentChannelMode,
    --     newChannelCount,
    --     realTrackCount and tostring(realTrackCount) or "nil"))

    -- Detect changes based on previousChannelMode
    if previousChannelMode and previousChannelMode ~= currentChannelMode then
        -- User changed channelMode in UI
        local previousConfig = globals.Constants.CHANNEL_CONFIGS[previousChannelMode]
        if previousConfig then
            local oldChannelCount = previousConfig.channels

            if oldChannelCount > newChannelCount then
                -- TRUE DOWNGRADE DETECTED
                -- reaper.ShowConsoleMsg(string.format("INFO: TRUE DOWNGRADE: %s changed %d.0→%d.0 (%d→%d channels)\n",
                --     container.name or "unknown", oldChannelCount, newChannelCount, oldChannelCount, newChannelCount))

                Generation_MultiChannel.propagateConfigurationDowngrade(oldChannelCount, newChannelCount, currentChannelMode)

                -- MEGATHINK FIX: Force complete stabilization after downgrade
                -- reaper.ShowConsoleMsg("INFO: Starting complete project stabilization after downgrade...\n")
                reaper.UpdateArrange()

                -- Clear skip flag before stabilization
                globals.skipRoutingValidation = false

                -- Run fix-point stabilization until convergence
                Generation_MultiChannel.stabilizeProjectConfiguration()

            elseif oldChannelCount < newChannelCount then
                -- TRUE UPGRADE DETECTED
                -- reaper.ShowConsoleMsg(string.format("INFO: TRUE UPGRADE: %s changed %d.0→%d.0 (%d→%d channels)\n",
                --     container.name or "unknown", oldChannelCount, newChannelCount, oldChannelCount, newChannelCount))
                -- Normal creation will handle upgrades
            end
        end
    else
        -- No channelMode change, check for track count mismatch
        if realTrackCount and realTrackCount ~= newChannelCount then
            -- reaper.ShowConsoleMsg(string.format("INFO: Track mismatch for '%s': has %d tracks but should have %d\n",
            --     container.name or "unknown", realTrackCount, newChannelCount))
        end
    end
end

-- Propagate configuration downgrades to ALL containers of the same type
function Generation_MultiChannel.propagateConfigurationDowngrade(oldChannelCount, newChannelCount, channelModeType)
    local affectedContainers = {}

    -- Find ALL containers with the same channel mode
    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if container.channelMode == channelModeType then
                local currentChildCount = Generation_MultiChannel.getExistingChildTrackCount(container)
                if currentChildCount and currentChildCount == oldChannelCount then
                    table.insert(affectedContainers, {
                        container = container,
                        group = group,
                        currentChildCount = currentChildCount
                    })
                end
            end
        end
    end

    -- reaper.ShowConsoleMsg(string.format("INFO: Found %d containers to downgrade\n", #affectedContainers))

    -- Apply downgrade to ALL affected containers
    for _, info in ipairs(affectedContainers) do
        Generation_MultiChannel.handleConfigurationDowngrade(info.container, oldChannelCount, newChannelCount)
        -- reaper.ShowConsoleMsg(string.format("INFO: Downgraded container '%s' in group '%s'\n",
        --     info.container.name or "unknown", info.group.name or "unknown"))
    end

    -- CRITICAL: Set a flag to prevent RoutingValidator from "fixing" during this operation
    globals.skipRoutingValidation = true

    -- Clear RoutingValidator cache to force fresh validation next time
    if globals.RoutingValidator and globals.RoutingValidator.clearValidation then
        globals.RoutingValidator.clearValidation()
    end

    -- reaper.ShowConsoleMsg(string.format("INFO: Propagation complete. %d containers processed.\n", #affectedContainers))

    -- REGRESSION FIX: Clear skip flag immediately after propagation
    -- This allows validation to detect other containers with bad routing
    globals.skipRoutingValidation = false
    -- reaper.ShowConsoleMsg("INFO: Propagation finished - validation re-enabled to catch other issues\n")
end

-- Get the current number of child tracks for a container
function Generation_MultiChannel.getExistingChildTrackCount(container)
    -- ULTRATHINK FIX: Use more robust track finding
    local containerTrack = Generation_MultiChannel.findContainerTrackRobust(container)

    if not containerTrack then
        -- reaper.ShowConsoleMsg(string.format("DEBUG: Could not find container track for '%s'\n", container.name or "unknown"))
        return nil
    end

    -- Count direct children using REAPER's direct parent-child relationship
    local childCount = 0
    local totalTracks = reaper.CountTracks(0)

    for i = 0, totalTracks - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local parent = reaper.GetParentTrack(track)
            if parent == containerTrack then
                childCount = childCount + 1
            end
        end
    end

    -- reaper.ShowConsoleMsg(string.format("DEBUG: Container '%s' has %d direct children\n",
    --     container.name or "unknown", childCount))

    return childCount
end

-- Robust container track finder that actually works
function Generation_MultiChannel.findContainerTrackRobust(container)
    local containerName = container.name
    if not containerName then return nil end

    -- Method 1: Use stored GUID if available
    if container.trackGUID then
        local track = reaper.BR_GetMediaTrackByGUID(0, container.trackGUID)
        if track then
            -- reaper.ShowConsoleMsg(string.format("DEBUG: Found container '%s' by GUID\n", containerName))
            return track
        end
    end

    -- Method 2: Search by name across all tracks
    local totalTracks = reaper.CountTracks(0)
    for i = 0, totalTracks - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local _, trackName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
            if trackName == containerName then
                -- reaper.ShowConsoleMsg(string.format("DEBUG: Found container '%s' by name at index %d\n",
                --     containerName, i))
                return track
            end
        end
    end

    -- reaper.ShowConsoleMsg(string.format("DEBUG: FAILED to find container track '%s'\n", containerName))
    return nil
end

-- Find container track by group and container name
function Generation_MultiChannel.findContainerTrack(groupName, containerName)
    local groupTrack = Generation_MultiChannel.findGroupTrack(groupName)
    if not groupTrack then return nil end

    local groupIdx = reaper.GetMediaTrackInfo_Value(groupTrack, "IP_TRACKNUMBER") - 1
    return globals.Utils.findContainerGroup(groupIdx, containerName)
end

-- Find group track by name
function Generation_MultiChannel.findGroupTrack(groupName)
    local groupTrack, _ = globals.Utils.findGroupByName(groupName)
    return groupTrack
end

-- ===================================================================
-- FIX-POINT STABILIZATION SYSTEM
-- ===================================================================

-- Stabilize project configuration until convergence (Fix-Point approach)
function Generation_MultiChannel.stabilizeProjectConfiguration(lightMode)
    local maxIterations = lightMode and 2 or 5  -- Light mode: fewer iterations
    local iteration = 0
    local hasChanges = true

    -- reaper.ShowConsoleMsg(string.format("INFO: Starting %s fix-point stabilization...\n", lightMode and "light" or "full"))

    while hasChanges and iteration < maxIterations do
        iteration = iteration + 1
        -- reaper.ShowConsoleMsg(string.format("INFO: Stabilization iteration %d/%d\n", iteration, maxIterations))

        -- Capture project state before changes
        local startState = Generation_MultiChannel.captureProjectState()

        -- CRITICAL: Only recalculate channel requirements if auto-fix is enabled
        -- This prevents automatic modification of parent tracks without user authorization
        -- The RoutingValidator will detect issues and let the user decide whether to apply fixes
        if globals.autoFixRouting then
            -- reaper.ShowConsoleMsg("  → Recalculating channel requirements (auto-fix enabled)...\n")
            Generation_MultiChannel.recalculateChannelRequirements()
        else
            -- reaper.ShowConsoleMsg("  → Skipping recalculation (manual validation mode)...\n")
        end

        -- Capture project state after changes
        local endState = Generation_MultiChannel.captureProjectState()

        -- Check if anything changed
        hasChanges = not Generation_MultiChannel.compareProjectStates(startState, endState)

        if hasChanges then
            -- reaper.ShowConsoleMsg(string.format("  → Changes detected, continuing iteration %d\n", iteration + 1))
        else
            -- reaper.ShowConsoleMsg("  → No changes detected, system is stable!\n")
        end

        -- Force update REAPER display between iterations
        reaper.UpdateArrange()
    end

    if iteration >= maxIterations and hasChanges then
        -- reaper.ShowConsoleMsg("WARNING: Stabilization reached max iterations, may not be fully stable\n")
    else
        -- reaper.ShowConsoleMsg(string.format("SUCCESS: Project stabilized after %d iterations\n", iteration))
    end

    -- CRITICAL: Validate and resolve routing conflicts AFTER stabilization is complete
    -- This ensures fixes are not overwritten by recalculation iterations
    Generation_MultiChannel.checkAndResolveConflicts()

    return not hasChanges  -- Return true if fully stabilized
end

-- Capture current project state for comparison
function Generation_MultiChannel.captureProjectState()
    local state = {
        containerChannels = {},
        groupChannels = {},
        masterChannels = 0
    }

    -- Capture all container track channel counts
    for _, group in ipairs(globals.groups or {}) do
        for _, container in ipairs(group.containers or {}) do
            if container.name then
                local containerTrack = Generation_MultiChannel.findContainerTrackRobust(container)
                if containerTrack then
                    state.containerChannels[container.name] = reaper.GetMediaTrackInfo_Value(containerTrack, "I_NCHAN")
                end
            end
        end

        -- Capture group track channel count
        if group.name then
            local groupTrack = Generation_MultiChannel.findGroupTrackRobust(group.name)
            if groupTrack then
                state.groupChannels[group.name] = reaper.GetMediaTrackInfo_Value(groupTrack, "I_NCHAN")
            end
        end
    end

    -- Capture master track channels
    local masterTrack = reaper.GetMasterTrack(0)
    if masterTrack then
        state.masterChannels = reaper.GetMediaTrackInfo_Value(masterTrack, "I_NCHAN")
    end

    return state
end

-- Compare two project states to detect changes
function Generation_MultiChannel.compareProjectStates(state1, state2)
    if not state1 or not state2 then return false end

    -- Compare master channels
    if state1.masterChannels ~= state2.masterChannels then
        -- reaper.ShowConsoleMsg(string.format("  State change: Master %d → %d\n",
        --     state1.masterChannels, state2.masterChannels))
        return false
    end

    -- Compare container channels
    for name, channels1 in pairs(state1.containerChannels) do
        local channels2 = state2.containerChannels[name]
        if channels1 ~= channels2 then
            -- reaper.ShowConsoleMsg(string.format("  State change: Container '%s' %d → %d\n",
            --     name, channels1, channels2 or 0))
            return false
        end
    end

    -- Compare group channels
    for name, channels1 in pairs(state1.groupChannels) do
        local channels2 = state2.groupChannels[name]
        if channels1 ~= channels2 then
            -- reaper.ShowConsoleMsg(string.format("  State change: Group '%s' %d → %d\n",
            --     name, channels1, channels2 or 0))
            return false
        end
    end

    return true  -- No changes detected
end

-- Centralized routing validation and issue resolution
-- Call this from any generation function
function Generation_MultiChannel.checkAndResolveConflicts()
    -- Use the new RoutingValidator module for comprehensive validation
    if not globals.RoutingValidator then
        return  -- Module not initialized
    end

    -- CRITICAL: Clear cache before validation to ensure fresh scan after generation
    globals.RoutingValidator.clearCache()

    -- Validate entire project routing using the new robust system
    local issues = globals.RoutingValidator.validateProjectRouting()

    -- Handle issues based on auto-fix setting
    if issues and #issues > 0 then
        if globals.autoFixRouting then
            -- Auto-fix mode: apply fixes automatically in a loop until all issues resolved
            local maxIterations = 10  -- Prevent infinite loops
            local iteration = 0
            local currentIssues = issues

            while currentIssues and #currentIssues > 0 and iteration < maxIterations do
                iteration = iteration + 1

                local suggestions = globals.RoutingValidator.generateFixSuggestions(currentIssues, globals.RoutingValidator.getProjectTrackCache())
                local success = globals.RoutingValidator.autoFixRouting(currentIssues, suggestions)

                if not success then
                    -- Auto-fix failed, show modal for manual resolution
                    globals.RoutingValidator.showValidationModal(currentIssues)
                    break
                end

                -- Re-validate to check for remaining issues
                globals.RoutingValidator.clearCache()
                currentIssues = globals.RoutingValidator.validateProjectRouting()

                if not currentIssues or #currentIssues == 0 then
                    break
                end
            end

            -- If we hit max iterations, show remaining issues
            if iteration >= maxIterations and currentIssues and #currentIssues > 0 then
                globals.RoutingValidator.showValidationModal(currentIssues)
            end
        else
            -- Manual mode: show validation modal for user review
            globals.RoutingValidator.showValidationModal(issues)
        end
    end
end

-- Apply channel selection (downmix/split) to an item via REAPER actions
-- @param item userdata: The media item to apply channel selection to
-- @param container table: Container configuration
-- @param itemChannels number: Number of channels in the item
-- @param channelSelectionMode string: "none", "stereo", or "mono"
-- @param trackStructure table: Track structure (optional, for auto-forced values)
-- @param trackIdx number: Track index (1-based) for smart routing
function Generation_MultiChannel.applyChannelSelection(item, container, itemChannels, channelSelectionMode, trackStructure, trackIdx)
    if not item or not container then return end

    -- Select the item for applying actions
    reaper.SelectAllMediaItems(0, false)
    reaper.SetMediaItemSelected(item, true)

    if channelSelectionMode == "stereo" then
        -- Stereo pair selection
        -- Priority: trackStructure value (auto-forced) > container value (user choice)
        local stereoPairSelection = (trackStructure and trackStructure.stereoPairSelection) or container.stereoPairSelection or 0

        -- Apply stereo downmix action based on pair index
        if stereoPairSelection == 0 then
            reaper.Main_OnCommand(41450, 0) -- Channels 1-2 (L/R)
        elseif stereoPairSelection == 1 then
            reaper.Main_OnCommand(41452, 0) -- Channels 3-4 (LS/RS or C/LFE)
        elseif stereoPairSelection == 2 then
            reaper.Main_OnCommand(41454, 0) -- Channels 5-6
        elseif stereoPairSelection == 3 then
            reaper.Main_OnCommand(41456, 0) -- Channels 7-8
        end

    elseif channelSelectionMode == "split-stereo" then
        -- Split stereo pairs: Extract different stereo pair per track
        -- Used for multi-channel containers with stereo pair distribution
        -- trackIdx (1-based) determines which stereo pair to extract

        local pairIndex

        -- NEW: Check if container has stereoPairMapping (per-track pair selection)
        if container.stereoPairMapping and container.stereoPairMapping[trackIdx] then
            local mappedPair = container.stereoPairMapping[trackIdx]

            if mappedPair == "random" then
                -- Random mode: select random pair from available
                local numPairs = math.floor(itemChannels / 2)
                pairIndex = math.random(0, numPairs - 1)
            else
                pairIndex = mappedPair  -- Use user-selected pair for this track
            end
        else
            -- FALLBACK: Old behavior (default mapping)
            pairIndex = trackIdx - 1  -- Track 1 → pair 0, Track 2 → pair 1, etc.

            -- UPSAMPLING: If items don't have enough stereo pairs, randomly select from available
            if trackStructure and trackStructure.upsampling and pairIndex >= trackStructure.availableStereoPairs then
                pairIndex = math.random(0, trackStructure.availableStereoPairs - 1)
            end
        end

        -- Apply stereo pair extraction based on pair index
        if pairIndex == 0 then
            reaper.Main_OnCommand(41450, 0) -- Channels 1-2 (L/R)
        elseif pairIndex == 1 then
            reaper.Main_OnCommand(41452, 0) -- Channels 3-4 (LS/RS)
        elseif pairIndex == 2 then
            reaper.Main_OnCommand(41454, 0) -- Channels 5-6 (LB/RB)
        elseif pairIndex == 3 then
            reaper.Main_OnCommand(41456, 0) -- Channels 7-8
        end

    elseif channelSelectionMode == "mono" then
        -- Mono channel selection
        -- Priority: trackStructure value (auto-forced) > container value (user choice)
        local monoChannelSelection = (trackStructure and trackStructure.monoChannelSelection) or container.monoChannelSelection or itemChannels

        -- Special case: Smart routing for surround items with known center position
        if trackStructure and trackStructure.useSmartRouting then
            -- Smart routing: Extract specific channel based on track index and source variant
            -- For 5.0: L R C LS RS (ITU) or L C R LS RS (SMPTE)
            -- For 7.0: L R C LS RS LB RB (ITU) or L C R LS RS LB RB (SMPTE)
            -- Target: 4 tracks = L, R, LS, RS (skip center)

            local sourceChannelVariant = trackStructure.sourceChannelVariant or container.sourceChannelVariant or 0
            local sourceChannel = 0  -- 0-based channel index

            if itemChannels == 5 then
                -- 5.0 surround
                if sourceChannelVariant == 0 then
                    -- ITU/Dolby: L(0) R(1) C(2) LS(3) RS(4)
                    local channelMap = {0, 1, 3, 4}  -- L, R, LS, RS (skip C at index 2)
                    sourceChannel = channelMap[trackIdx] or 0
                else
                    -- SMPTE: L(0) C(1) R(2) LS(3) RS(4)
                    local channelMap = {0, 2, 3, 4}  -- L, R, LS, RS (skip C at index 1)
                    sourceChannel = channelMap[trackIdx] or 0
                end
            elseif itemChannels == 7 then
                -- 7.0 surround
                if sourceChannelVariant == 0 then
                    -- ITU/Dolby: L(0) R(1) C(2) LS(3) RS(4) LB(5) RB(6)
                    local channelMap = {0, 1, 3, 4}  -- L, R, LS, RS (skip C, LB, RB)
                    sourceChannel = channelMap[trackIdx] or 0
                else
                    -- SMPTE: L(0) C(1) R(2) LS(3) RS(4) LB(5) RB(6)
                    local channelMap = {0, 2, 3, 4}  -- L, R, LS, RS (skip C, LB, RB)
                    sourceChannel = channelMap[trackIdx] or 0
                end
            end

            -- Apply mono channel selection action based on source channel (0-based)
            if sourceChannel == 0 then
                reaper.Main_OnCommand(40179, 0) -- Mono channel 1 (left)
            elseif sourceChannel == 1 then
                reaper.Main_OnCommand(40180, 0) -- Mono channel 2 (right)
            elseif sourceChannel == 2 then
                reaper.Main_OnCommand(41388, 0) -- Mono channel 3
            elseif sourceChannel == 3 then
                reaper.Main_OnCommand(41389, 0) -- Mono channel 4
            elseif sourceChannel == 4 then
                reaper.Main_OnCommand(41390, 0) -- Mono channel 5
            elseif sourceChannel == 5 then
                reaper.Main_OnCommand(41391, 0) -- Mono channel 6
            elseif sourceChannel == 6 then
                reaper.Main_OnCommand(41392, 0) -- Mono channel 7
            elseif sourceChannel == 7 then
                reaper.Main_OnCommand(41393, 0) -- Mono channel 8
            end
        else
            -- Normal mono channel selection
            -- Check if random mode (index >= itemChannels means Random)
            local selectedChannel = monoChannelSelection
            if selectedChannel >= itemChannels then
                -- Random: choose random channel (0-based)
                selectedChannel = math.random(0, itemChannels - 1)
            end

            -- Apply mono channel selection action based on channel index (0-based)
            if selectedChannel == 0 then
                reaper.Main_OnCommand(40179, 0) -- Mono channel 1 (left)
            elseif selectedChannel == 1 then
                reaper.Main_OnCommand(40180, 0) -- Mono channel 2 (right)
            elseif selectedChannel == 2 then
                reaper.Main_OnCommand(41388, 0) -- Mono channel 3
            elseif selectedChannel == 3 then
                reaper.Main_OnCommand(41389, 0) -- Mono channel 4
            elseif selectedChannel == 4 then
                reaper.Main_OnCommand(41390, 0) -- Mono channel 5
            elseif selectedChannel == 5 then
                reaper.Main_OnCommand(41391, 0) -- Mono channel 6
            elseif selectedChannel == 6 then
                reaper.Main_OnCommand(41392, 0) -- Mono channel 7
            elseif selectedChannel == 7 then
                reaper.Main_OnCommand(41393, 0) -- Mono channel 8
            end
        end
    end

    -- Deselect the item
    reaper.SetMediaItemSelected(item, false)
end

-- Get output channel count from channel mode
-- @param channelMode number: Channel mode (0=Stereo, 1=Quad, 2=5.0, 3=7.0)
-- @return number: Number of output channels
function Generation_MultiChannel.getOutputChannelCount(channelMode)
    if not channelMode or channelMode == 0 then
        return 2  -- Stereo
    end

    local config = globals.Constants.CHANNEL_CONFIGS[channelMode]
    if not config then
        return 2  -- Fallback to stereo
    end

    return config.channels or 2
end

-- Analyze container items to understand channel configuration
-- Pure function with no side effects
-- @param container table: The container to analyze
-- @return table: Analysis result with channel information
function Generation_MultiChannel.analyzeContainerItems(container)
    -- Default result for empty container
    if not container.items or #container.items == 0 then
        return {
            isEmpty = true,
            isHomogeneous = true,
            dominantChannelCount = 2,
            uniqueChannelCounts = {},
            totalItems = 0
        }
    end

    -- Count channel occurrences
    local channelCounts = {}
    for _, item in ipairs(container.items) do
        local ch = item.numChannels or 2
        channelCounts[ch] = (channelCounts[ch] or 0) + 1
    end

    -- Get unique channel counts
    local uniqueChannels = {}
    for ch, _ in pairs(channelCounts) do
        table.insert(uniqueChannels, ch)
    end

    -- Sort for consistency
    table.sort(uniqueChannels)

    -- Find dominant channel count (most frequent)
    local dominantChannel = uniqueChannels[1]
    local maxCount = 0
    for ch, count in pairs(channelCounts) do
        if count > maxCount then
            maxCount = count
            dominantChannel = ch
        end
    end

    return {
        isEmpty = false,
        isHomogeneous = (#uniqueChannels == 1),
        dominantChannelCount = dominantChannel,
        uniqueChannelCounts = uniqueChannels,
        totalItems = #container.items,
        channelCounts = channelCounts
    }
end

-- Generate stereo pair labels based on item channels
-- @param itemChannels number: Number of channels in items
-- @param numPairs number: Number of stereo pairs to generate
-- @return table: Array of label strings
function Generation_MultiChannel.generateStereoPairLabels(itemChannels, numPairs)
    local labels = {}

    if itemChannels == 4 and numPairs == 2 then
        return {"L+R", "LS+RS"}
    elseif itemChannels == 6 and numPairs == 3 then
        return {"L+R", "C+LFE", "LS+RS"}
    elseif itemChannels == 8 and numPairs == 4 then
        return {"L+R", "C+LFE", "LS+RS", "LB+RB"}
    else
        -- Generic labels
        for i = 1, numPairs do
            local ch1 = (i-1)*2 + 1
            local ch2 = i*2
            labels[i] = "Ch" .. ch1 .. "+" .. ch2
        end
    end

    return labels
end

-- Auto-optimization logic when channelSelectionMode = "none"
-- @param container table: Container configuration
-- @param itemsAnalysis table: Result from analyzeContainerItems
-- @param outputChannels number: Target output channel count
-- @return table: Track structure description
function Generation_MultiChannel.determineAutoOptimization(container, itemsAnalysis, outputChannels)
    local itemCh = itemsAnalysis.dominantChannelCount

    -- ──────────────────────────────────────────────────────────
    -- CAS A : Stereo items (2ch) dans Quad/5.0/7.0
    -- ──────────────────────────────────────────────────────────
    if itemCh == 2 and outputChannels >= 4 then
        if outputChannels == 4 then
            return {
                strategy = "auto-stereo-pairs-quad",
                numTracks = 2,
                trackType = "stereo",
                trackChannels = 2,
                trackLabels = {"L+R", "LS+RS"},
                needsChannelSelection = false,
                useDistribution = true
            }
        else  -- 5.0 or 7.0
            return {
                strategy = "auto-stereo-pairs-surround",
                numTracks = 2,
                trackType = "stereo",
                trackChannels = 2,
                trackLabels = {"L+R", "LS+RS"},
                needsChannelSelection = false,
                useDistribution = true
            }
        end
    end

    -- ──────────────────────────────────────────────────────────
    -- CAS B : 4.0 items dans 5.0/7.0
    -- ──────────────────────────────────────────────────────────
    if itemCh == 4 and outputChannels >= 5 then
        return {
            strategy = "auto-4ch-in-surround",
            numTracks = 4,
            trackType = "mono",
            trackChannels = 1,
            trackLabels = {"L", "R", "LS", "RS"},
            needsChannelSelection = false,
            needsRouting = true,
            routingMap = {1, 2, 4, 5},  -- Skip center (channel 3)
        }
    end

    -- ──────────────────────────────────────────────────────────
    -- CAS C : Items > Output → Auto downmix intelligent
    -- ──────────────────────────────────────────────────────────
    if itemCh > outputChannels then
        -- Cas spécial : 5.0/7.0 items avec source variant connu → Smart routing vers 4.0/Stereo
        if (itemCh == 5 or itemCh == 7) and container.sourceChannelVariant ~= nil then
            -- L'utilisateur a spécifié où est le center, on peut faire du routing intelligent
            if outputChannels == 4 then
                -- 5.0/7.0 → 4.0 : Map L/R/LS/RS (skip center)
                return {
                    strategy = "surround-to-quad-skip-center",
                    numTracks = 4,
                    trackType = "mono",
                    trackChannels = 1,
                    trackLabels = {"L", "R", "LS", "RS"},
                    needsChannelSelection = true,
                    channelSelectionMode = "mono",
                    useSmartRouting = true,
                    sourceChannelVariant = container.sourceChannelVariant,
                    warning = string.format(
                        "Items have %d channels, mapping to 4.0 (skipping center channel).",
                        itemCh
                    )
                }
            elseif outputChannels == 2 then
                -- 5.0/7.0 → Stereo : Downmix L/R only (skip center + surrounds)
                return {
                    strategy = "surround-to-stereo-front-only",
                    numTracks = 1,
                    trackType = "stereo",
                    trackChannels = 2,
                    needsChannelSelection = true,
                    channelSelectionMode = "stereo",
                    stereoPairSelection = 0,  -- Force Ch1-2 (L/R front)
                    warning = string.format(
                        "Items have %d channels, using front L/R only (skipping center and surrounds).",
                        itemCh
                    )
                }
            end
        end

        -- Cas spécial : 4.0 items → Stereo/4.0 (pairs)
        if itemCh == 4 and outputChannels == 2 then
            -- 4.0 → Stereo : Downmix automatique vers Ch1-2
            return {
                strategy = "auto-downmix-stereo",
                numTracks = 1,
                trackType = "stereo",
                trackChannels = 2,
                needsChannelSelection = true,
                channelSelectionMode = "stereo",
                stereoPairSelection = 0,  -- Force Ch1-2 (L/R)
                itemsGoDirectly = true,
                warning = "Items have 4 channels but output is stereo. Auto-downmixing to channels 1-2 (L/R)."
            }
        end

        -- Cas spécial : Items pairs (6, 8) → Stereo
        if outputChannels == 2 and itemCh % 2 == 0 then
            -- Items avec channels pairs → Downmix stereo automatique vers Ch1-2
            return {
                strategy = "auto-downmix-stereo",
                numTracks = 1,
                trackType = "stereo",
                trackChannels = 2,
                needsChannelSelection = true,
                channelSelectionMode = "stereo",
                stereoPairSelection = 0,  -- Force Ch1-2 (L/R)
                itemsGoDirectly = true,
                warning = string.format(
                    "Items have %d channels but output is stereo. Auto-downmixing to channels 1-2 (L/R).",
                    itemCh
                )
            }
        end

        -- Cas général : 5.0/7.0 sans variant connu → Downmix mono avec warning
        if (itemCh == 5 or itemCh == 7) and container.sourceChannelVariant == nil then
            local targetChannels = outputChannels == 2 and "stereo" or (outputChannels .. ".0")
            return {
                strategy = "surround-unknown-format",
                numTracks = 1,
                trackType = "multi",
                trackChannels = outputChannels,
                needsChannelSelection = true,
                channelSelectionMode = "mono",
                monoChannelSelection = 0,  -- Force channel 1
                warning = string.format(
                    "Items have %d channels but output is %s. Using channel 1 only.\n" ..
                    "To enable smart routing (skip center), specify the source format below.",
                    itemCh, targetChannels
                ),
                needsSourceVariant = true  -- Flag to show source format dropdown
            }
        end

        -- Cas général : Downmix vers channel 1
        return {
            strategy = "auto-downmix-to-first",
            numTracks = 1,
            trackType = "multi",
            trackChannels = outputChannels,
            needsChannelSelection = true,
            channelSelectionMode = "mono",
            monoChannelSelection = 0,  -- Force channel 1
            warning = string.format(
                "Items have %d channels but output is %d channels. Using channel 1 only. " ..
                "Consider using 'Channel Selection: Mono' or 'Channel Selection: Stereo' for more control.",
                itemCh, outputChannels
            )
        }
    end

    -- ──────────────────────────────────────────────────────────
    -- CAS D : Autres cas → Structure multi-channel standard
    -- ──────────────────────────────────────────────────────────
    return {
        strategy = "auto-default",
        numTracks = outputChannels,
        trackType = "mono",
        trackChannels = 1,
        needsChannelSelection = (itemCh > 1),
        channelSelectionMode = "mono",
        monoChannelSelection = 0,  -- Channel 1
        useDistribution = true
    }
end

-- Synchronize B_PPITCH property for existing items based on current pitch mode
function Generation_MultiChannel.syncPitchModeOnExistingItems(group, container)
    if not group or not container then return end

    local Constants = globals.Constants
    local Utils = globals.Utils

    -- Get effective pitch mode
    local effectivePitchMode = container.overrideParent and container.pitchMode or group.pitchMode
    if not effectivePitchMode then effectivePitchMode = Constants.PITCH_MODES.PITCH end

    -- Find container track
    local trackCount = reaper.CountTracks(0)
    local containerTrack = nil

    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        local _, trackName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

        -- Check if this track belongs to our container
        if trackName == container.name then
            containerTrack = track
            break
        end
    end

    if not containerTrack then return end

    -- Process all tracks (container track + any child tracks)
    local tracksToProcess = {containerTrack}

    -- Check if container has child tracks (multi-channel mode)
    local folderDepth = reaper.GetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH")
    if folderDepth == 1 then
        -- Has child tracks, add them
        local trackIndex = reaper.GetMediaTrackInfo_Value(containerTrack, "IP_TRACKNUMBER") - 1
        local currentDepth = 1
        local childIndex = trackIndex + 1

        while currentDepth > 0 and childIndex < trackCount do
            local childTrack = reaper.GetTrack(0, childIndex)
            local childDepth = reaper.GetMediaTrackInfo_Value(childTrack, "I_FOLDERDEPTH")
            currentDepth = currentDepth + childDepth

            if currentDepth > 0 then
                table.insert(tracksToProcess, childTrack)
            end

            childIndex = childIndex + 1
        end
    end

    -- Process all items on these tracks
    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()

    for _, track in ipairs(tracksToProcess) do
        local itemCount = reaper.CountTrackMediaItems(track)

        for j = 0, itemCount - 1 do
            local item = reaper.GetTrackMediaItem(track, j)
            local take = reaper.GetActiveTake(item)

            if take then
                -- Get current pitch/playrate values
                local currentPitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH")
                local currentPlayrate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")

                if effectivePitchMode == Constants.PITCH_MODES.STRETCH then
                    -- STRETCH mode: Disable preserve pitch
                    reaper.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 0)

                    -- If currently using D_PITCH, convert to D_PLAYRATE
                    if currentPitch ~= 0 and currentPlayrate == 1.0 then
                        local playrate = Utils.semitonesToPlayrate(currentPitch)
                        reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", playrate)
                        reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", 0)
                    end
                else
                    -- PITCH mode: Reset B_PPITCH to default (doesn't matter for D_PITCH)
                    -- Convert from D_PLAYRATE back to D_PITCH if needed
                    if currentPlayrate ~= 1.0 then
                        local semitones = Utils.playrateToSemitones(currentPlayrate)
                        reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", semitones)
                        reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", 1.0)
                        reaper.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 1)
                    end
                end
            end
        end
    end

    reaper.Undo_EndBlock("Sync Pitch Mode on Existing Items", -1)
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
end

return Generation_MultiChannel
