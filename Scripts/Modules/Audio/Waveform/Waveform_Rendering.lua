--[[
@version 1.0
@noindex
DM Ambiance Creator - Waveform Rendering Module
Handles waveform visualization and UI rendering.
--]]

local Waveform_Rendering = {}
local globals = {}

-- Dependencies (will be set by aggregator)
local Waveform_Core = nil
local Waveform_Playback = nil
local Waveform_Areas = nil

function Waveform_Rendering.initModule(g)
    globals = g
end

-- Set dependencies (called by aggregator after all modules are loaded)
function Waveform_Rendering.setDependencies(core, playback, areas)
    Waveform_Core = core
    Waveform_Playback = playback
    Waveform_Areas = areas
end

function Waveform_Rendering.drawWaveform(filePath, width, height, options)
    local ctx = globals.ctx
    local imgui = globals.imgui

    -- Validate inputs
    width = math.floor(tonumber(width) or 400)
    height = math.floor(tonumber(height) or 100)
    if width <= 0 then width = 400 end
    if height <= 0 then height = 100 end

    options = options or {}

    -- Use itemKey for area storage instead of filePath
    local itemKey = options.itemKey or filePath  -- Fallback to filePath if no itemKey provided

    -- Get waveform data with options
    local waveformData = Waveform_Core.getWaveformData(filePath, width, options)
    if not waveformData then
        imgui.Text(ctx, "Unable to load waveform")
        return nil
    end

    -- Get drawing position
    local draw_list = imgui.GetWindowDrawList(ctx)
    local pos_x, pos_y = imgui.GetCursorScreenPos(ctx)

    -- Calculate channel layout
    local numChannels = waveformData.numChannels or 1
    local displayChannels = math.min(numChannels, 8)  -- Limit to 8 channels for display
    local channelHeight = height / displayChannels
    local channelSpacing = 2  -- Pixels between channels

    -- Draw background
    imgui.DrawList_AddRectFilled(draw_list,
        pos_x, pos_y,
        pos_x + width, pos_y + height,
        0x1A1A1AFF
    )

    -- Push clipping rectangle to prevent waveform from drawing outside bounds when zoomed
    imgui.DrawList_PushClipRect(draw_list, pos_x, pos_y, pos_x + width, pos_y + height, true)

    -- Draw each channel
    local peaks = waveformData.peaks

    -- Single color for all waveform elements
    local waveformColor = globals.Settings.getSetting("waveformColor") -- Bright cyan for both peaks and RMS

    for ch = 1, displayChannels do
        local channelY = pos_y + (ch - 1) * channelHeight
        local centerY = channelY + channelHeight / 2 - channelSpacing / 2

        -- Draw zero line for this channel
        imgui.DrawList_AddLine(draw_list,
            pos_x, centerY,
            pos_x + width, centerY,
            0x404040FF,
            1
        )

        -- Get channel data
        local channelPeaks = nil
        if peaks.channels and peaks.channels[ch] then
            channelPeaks = peaks.channels[ch]
        elseif ch == 1 then
            -- Fallback for backward compatibility
            channelPeaks = peaks
        end

            -- Draw waveform peaks for this channel
        if channelPeaks and channelPeaks.max and #channelPeaks.max > 0 then
            local channelDrawHeight = channelHeight - channelSpacing

            -- Draw waveform
            for pixel = 1, width do
                local x = pos_x + pixel - 1

                -- Direct 1:1 mapping since data is already interpolated to width
                local sampleIndex = pixel
                local maxVal = channelPeaks.max[sampleIndex] or 0
                local minVal = channelPeaks.min[sampleIndex] or 0

                -- Draw vertical line from min to max (only if showPeaks is enabled)
                local verticalZoom = options.verticalZoom or globals.waveformVerticalZoom or 1.0
                local gainDB = options.gainDB or 0.0
                local gainScale = 10 ^ (gainDB / 20)  -- Convert dB to linear scale

                local topY = centerY - (maxVal * channelDrawHeight / 2 * verticalZoom * gainScale)
                local bottomY = centerY - (minVal * channelDrawHeight / 2 * verticalZoom * gainScale)

                if options.showPeaks ~= false then
                    imgui.DrawList_AddLine(draw_list,
                        x, topY,
                        x, bottomY,
                        waveformColor,
                        1
                    )
                end

                -- Draw RMS (only if showRMS is enabled)
                if options.showRMS ~= false then
                    local rmsVal = channelPeaks.rms[sampleIndex] or 0
                    if math.abs(rmsVal) > 0.01 then
                        imgui.DrawList_AddLine(draw_list,
                            x, centerY - (rmsVal * channelDrawHeight / 2 * verticalZoom * gainScale),
                            x, centerY + (rmsVal * channelDrawHeight / 2 * verticalZoom * gainScale),
                            waveformColor,
                            1
                        )
                    end
                end
            end
        end

        -- Draw separator between channels
        if ch < displayChannels then
            local separatorY = channelY + channelHeight - 1
            imgui.DrawList_AddLine(draw_list,
                pos_x, separatorY,
                pos_x + width, separatorY,
                0x303030FF,
                1
            )
        end
    end

    -- Draw playback position if playing (the moving white bar)
    if globals.audioPreview.isPlaying and globals.audioPreview.currentFile == filePath then
        local position = globals.audioPreview.position
        local startOffset = waveformData.startOffset or 0

        if position and type(position) == "number" and waveformData.length and waveformData.length > 0 then
            -- Calculate the relative position in the edited item
            local relativePos = position - startOffset

            -- Draw the playback position (white bar)
            local playPos = (relativePos / waveformData.length) * width

            -- Only draw if within visible range
            if playPos >= 0 and playPos <= width then
                imgui.DrawList_AddLine(draw_list,
                    pos_x + playPos, pos_y,
                    pos_x + playPos, pos_y + height,
                    0xFFFFFFFF,
                    0.5  -- Very thin line (half pixel)
                )
            end
        end
    end

    -- Pop clipping rectangle
    imgui.DrawList_PopClipRect(draw_list)

    -- Draw waveform areas/regions before the border (full height visual, upper half interaction)
    if globals.waveformAreas[itemKey] then
        for i, area in ipairs(globals.waveformAreas[itemKey]) do
            local areaStartX = pos_x + (area.startPos / waveformData.length) * width
            local areaEndX = pos_x + (area.endPos / waveformData.length) * width
            local areaWidth = areaEndX - areaStartX

            -- Draw quasi-transparent area with very subtle gradient effect (full height)
            imgui.DrawList_AddRectFilled(draw_list,
                areaStartX, pos_y,
                areaEndX, pos_y + height,
                0x15856D50  -- Quasi-transparent blue (5% opacity)
            )

            -- Draw very subtle gradient overlay (barely visible darker at edges) (full height)
            imgui.DrawList_AddRectFilled(draw_list,
                areaStartX, pos_y,
                areaStartX + 3, pos_y + height,
                0x15856D50  -- Very slightly darker blue
            )
            imgui.DrawList_AddRectFilled(draw_list,
                areaEndX - 3, pos_y,
                areaEndX, pos_y + height,
                0x15856D50  -- Very slightly darker blue
            )

            -- Draw area borders (more subtle) (full height)
            imgui.DrawList_AddLine(draw_list,
                areaStartX, pos_y,
                areaStartX, pos_y + height,
                0x40FFFFFF, 1  -- Subtle white border left
            )
            imgui.DrawList_AddLine(draw_list,
                areaEndX, pos_y,
                areaEndX, pos_y + height,
                0x40FFFFFF, 1  -- Subtle white border right
            )

            -- Draw area name label if there's enough space
            if areaWidth > 40 then
                local areaName = area.name or string.format("Area %d", i)
                local textX = areaStartX + 5
                local textY = pos_y + 5

                -- Draw text background for better readability
                local textWidth = imgui.CalcTextSize(ctx, areaName)
                imgui.DrawList_AddRectFilled(draw_list,
                    textX - 2, textY - 1,
                    math.min(textX + textWidth + 2, areaEndX - 2), textY + 14,
                    0x80000000  -- Semi-transparent black background
                )

                -- Draw area name
                imgui.DrawList_AddText(draw_list, textX, textY, 0xFFFFFFFF, areaName)
            end

            -- Draw area duration in bottom-left corner
            local areaDuration = area.endPos - area.startPos
            local durationText = string.format("%.2fs", areaDuration)
            local durationTextWidth = imgui.CalcTextSize(ctx, durationText)

            -- Position duration text in bottom-left with some padding
            local durationX = areaStartX + 5
            local durationY = pos_y + height - 18  -- 18 pixels from bottom

            -- Only draw duration if there's enough space and area is wide enough
            if areaWidth > 60 and durationX + durationTextWidth < areaEndX - 5 then
                -- Draw text background for better readability
                imgui.DrawList_AddRectFilled(draw_list,
                    durationX - 2, durationY - 1,
                    durationX + durationTextWidth + 2, durationY + 14,
                    0x80000000  -- Semi-transparent black background
                )

                -- Draw duration text in a slightly dimmer color to distinguish from area name
                imgui.DrawList_AddText(draw_list, durationX, durationY, 0xCCFFFFFF, durationText)
            end

            -- Draw resize handles in upper half (subtle, only visible on hover)
            local handleWidth = 4
            local handleHeight = 20
            local handleColor = 0x40FFFFFF  -- Very subtle semi-transparent white

            -- Check if mouse is near handles for highlighting
            local mouse_x, mouse_y = imgui.GetMousePos(ctx)
            local relative_x = mouse_x - pos_x
            local leftHandleHover = math.abs(relative_x - (areaStartX - pos_x)) < 5
            local rightHandleHover = math.abs(relative_x - (areaEndX - pos_x)) < 5

            local halfHeight = height / 2

            -- Left handle (positioned in upper half)
            local leftHandleColor = leftHandleHover and 0xA0FFFFFF or handleColor
            imgui.DrawList_AddRectFilled(draw_list,
                areaStartX - handleWidth/2, pos_y + halfHeight/2 - handleHeight/2,
                areaStartX + handleWidth/2, pos_y + halfHeight/2 + handleHeight/2,
                leftHandleColor
            )
            -- Add subtle grip lines on handle when hovering
            if leftHandleHover then
                imgui.DrawList_AddLine(draw_list,
                    areaStartX, pos_y + halfHeight/2 - 5,
                    areaStartX, pos_y + halfHeight/2 + 5,
                    0x60000000, 1
                )
            end

            -- Right handle (positioned in upper half)
            local rightHandleColor = rightHandleHover and 0xA0FFFFFF or handleColor
            imgui.DrawList_AddRectFilled(draw_list,
                areaEndX - handleWidth/2, pos_y + halfHeight/2 - handleHeight/2,
                areaEndX + handleWidth/2, pos_y + halfHeight/2 + handleHeight/2,
                rightHandleColor
            )
            -- Add subtle grip lines on handle when hovering
            if rightHandleHover then
                imgui.DrawList_AddLine(draw_list,
                    areaEndX, pos_y + halfHeight/2 - 5,
                    areaEndX, pos_y + halfHeight/2 + 5,
                    0x60000000, 1
                )
            end
        end
    end

    -- Draw area being created (full height visual, upper half interaction)
    if globals.waveformAreaDrag.isDragging and globals.waveformAreaDrag.currentItemKey == itemKey then
        local dragStartX = math.min(globals.waveformAreaDrag.startX, globals.waveformAreaDrag.endX)
        local dragEndX = math.max(globals.waveformAreaDrag.startX, globals.waveformAreaDrag.endX)

        imgui.DrawList_AddRectFilled(draw_list,
            dragStartX, pos_y,
            dragEndX, pos_y + height,
            0x0C80FF80  -- Quasi-transparent green for new area (5% opacity)
        )

        imgui.DrawList_AddRect(draw_list,
            dragStartX, pos_y,
            dragEndX, pos_y + height,
            0x40FF80FF, -- Subtle green border
            0, 0, 1
        )
    end

    -- Draw border
    imgui.DrawList_AddRect(draw_list,
        pos_x, pos_y,
        pos_x + width, pos_y + height,
        0x606060FF,
        0, 0, 1
    )

    -- Draw item info in bottom-right corner
    if options.itemInfo then
        local info = options.itemInfo
        local padding = 5
        local lineHeight = 12
        local infoY = pos_y + height - padding - lineHeight

        -- Build info text (compact format)
        local durationText = info.duration and string.format("%.2fs", info.duration) or "?"
        local channelText = info.channels and string.format("%dch", info.channels) or "?"
        local infoText = string.format("%s | %s | %s", info.name or "Unknown", durationText, channelText)

        -- Calculate text width for background
        local textWidth = imgui.CalcTextSize(ctx, infoText)
        local bgX1 = pos_x + width - textWidth - padding * 2
        local bgY1 = infoY - padding / 2
        local bgX2 = pos_x + width - padding
        local bgY2 = infoY + lineHeight + padding / 2

        -- Draw semi-transparent background
        imgui.DrawList_AddRectFilled(draw_list,
            bgX1, bgY1,
            bgX2, bgY2,
            0xC0000000  -- Semi-transparent black
        )

        -- Draw text
        imgui.DrawList_AddText(draw_list,
            pos_x + width - textWidth - padding, infoY,
            0xFFFFFFFF,  -- White text
            infoText
        )
    end

    -- Store waveform bounds for interaction detection
    globals.waveformBounds[itemKey] = {
        x = pos_x,
        y = pos_y,
        width = width,
        height = height
    }

    -- Reserve space and capture interactions with InvisibleButton
    local buttonPressed = imgui.InvisibleButton(ctx, "WaveformInteraction##" .. itemKey, width, height)

    -- Get mouse position for all interactions
    local mouse_x, mouse_y = imgui.GetMousePos(ctx)
    local relative_x = mouse_x - pos_x
    local relative_y = mouse_y - pos_y
    local isUpperHalf = relative_y < (height / 2)

    -- Check for interactions
    if imgui.IsItemHovered(ctx) then
        -- First, check if hovering on any area or handle
        local hoverOnHandle = false
        local hoverOnArea = false

        if globals.waveformAreas[itemKey] and not globals.waveformAreaDrag.isDragging and isUpperHalf then
            for i, area in ipairs(globals.waveformAreas[itemKey]) do
                local areaStartX = (area.startPos / waveformData.length) * width
                local areaEndX = (area.endPos / waveformData.length) * width

                -- Check if hovering on left edge
                if math.abs(relative_x - areaStartX) < 5 then
                    hoverOnHandle = true
                    break
                -- Check if hovering on right edge
                elseif math.abs(relative_x - areaEndX) < 5 then
                    hoverOnHandle = true
                    break
                -- Check if hovering inside area
                elseif relative_x >= areaStartX and relative_x <= areaEndX then
                    hoverOnArea = true
                    break
                end
            end
        end

        -- Check for vertical zoom with Ctrl+MouseWheel
        local wheel = imgui.GetMouseWheel(ctx)
        local ctrlPressed = (imgui.GetKeyMods(ctx) & imgui.Mod_Ctrl) ~= 0
        local shiftPressed = (imgui.GetKeyMods(ctx) & imgui.Mod_Shift) ~= 0

        if ctrlPressed and wheel ~= 0 then
            options.verticalZoom = options.verticalZoom or globals.waveformVerticalZoom or 1.0
            options.verticalZoom = math.max(0.1, math.min(5.0, options.verticalZoom + wheel * 0.1))
            -- Store zoom level in globals for persistence
            globals.waveformVerticalZoom = options.verticalZoom
        end

        -- Check for Ctrl+Click to delete area (only in upper half)
        if ctrlPressed and imgui.IsMouseClicked(ctx, 0) and not globals.waveformAreaDrag.isResizing and isUpperHalf then
            -- Check if clicking on an area to delete it
            local clickPos = (relative_x / width) * waveformData.length
            local clickedArea, clickedAreaIndex = Waveform_Areas.getAreaAtPosition(itemKey, clickPos, waveformData.length)

            if clickedArea then
                -- Delete the area with Ctrl+Click
                Waveform_Areas.deleteArea(itemKey, clickedAreaIndex)
            end
        -- Check for Shift+Click to create new area (only in upper half)
        elseif shiftPressed and imgui.IsMouseClicked(ctx, 0) and not hoverOnHandle and not hoverOnArea and
               not globals.waveformAreaDrag.isResizing and not globals.waveformAreaDrag.isMoving and isUpperHalf then
            -- Start dragging to create new area with Shift+LeftClick
            globals.waveformAreaDrag.isDragging = true
            globals.waveformAreaDrag.startX = mouse_x
            globals.waveformAreaDrag.endX = mouse_x
            globals.waveformAreaDrag.currentItemKey = itemKey
            globals.waveformAreaDrag.interactingWithArea = true
        -- Check for double-click to reset position (only if not on area)
        elseif imgui.IsMouseDoubleClicked(ctx, 0) and not hoverOnArea and not hoverOnHandle then  -- Double left click
            -- Clear the saved position
            if globals.audioPreview then
                globals.audioPreview.clickedPosition = nil
                globals.audioPreview.playbackStartPosition = nil
                -- Don't clear currentFile here - it will be set when playing
            end

            -- Start playback from beginning if onWaveformClick is defined
            if options.onWaveformClick then
                options.onWaveformClick(0, waveformData)  -- Start from beginning
            end
        elseif imgui.IsMouseClicked(ctx, 0) and not ctrlPressed and not shiftPressed and
                not globals.waveformAreaDrag.interactingWithArea then  -- Single left click
            -- Lower half: ALWAYS allow playback (ignore areas)
            -- Upper half: Only on empty space (no areas)
            local allowPlayback = (not isUpperHalf) or (not hoverOnArea and not hoverOnHandle)

            if allowPlayback then
                -- Calculate position in the audio file
                if relative_x >= 0 and relative_x <= width then
                    local clickRatio = relative_x / width
                    local clickPosition = clickRatio * waveformData.length

                    -- Store click information for starting playback
                    if options.onWaveformClick then
                        options.onWaveformClick(clickPosition, waveformData)
                    end

                    -- Start tracking playback marker drag in lower half
                    if not isUpperHalf then
                        globals.waveformAreaDrag.isDraggingPlayback = true
                        globals.waveformAreaDrag.playbackDragItemKey = itemKey
                    end
                end
            end
        end

        -- Handle playback marker dragging in lower half
        if globals.waveformAreaDrag.isDraggingPlayback and globals.waveformAreaDrag.playbackDragItemKey == itemKey then
            if imgui.IsMouseDragging(ctx, 0) and not isUpperHalf then
                -- Update playback position as mouse moves
                if relative_x >= 0 and relative_x <= width then
                    local dragRatio = relative_x / width
                    local dragPosition = dragRatio * waveformData.length

                    if options.onWaveformClick then
                        options.onWaveformClick(dragPosition, waveformData)
                    end
                end
            elseif imgui.IsMouseReleased(ctx, 0) then
                -- Stop tracking when mouse is released
                globals.waveformAreaDrag.isDraggingPlayback = false
                globals.waveformAreaDrag.playbackDragItemKey = nil
            end
        end

        -- Handle area interactions (resize/move) - only in upper half
        if globals.waveformAreas[itemKey] and not globals.waveformAreaDrag.isDragging and
           not shiftPressed and imgui.IsMouseClicked(ctx, 0) and isUpperHalf then
            for i, area in ipairs(globals.waveformAreas[itemKey]) do
                local areaStartX = (area.startPos / waveformData.length) * width
                local areaEndX = (area.endPos / waveformData.length) * width

                -- Check if clicking on left edge to resize
                if math.abs(relative_x - areaStartX) < 5 then
                    globals.waveformAreaDrag.isResizing = true
                    globals.waveformAreaDrag.resizeEdge = 'left'
                    globals.waveformAreaDrag.resizeAreaIndex = i
                    globals.waveformAreaDrag.currentItemKey = itemKey
                    globals.waveformAreaDrag.interactingWithArea = true
                    break
                -- Check if clicking on right edge to resize
                elseif math.abs(relative_x - areaEndX) < 5 then
                    globals.waveformAreaDrag.isResizing = true
                    globals.waveformAreaDrag.resizeEdge = 'right'
                    globals.waveformAreaDrag.resizeAreaIndex = i
                    globals.waveformAreaDrag.currentItemKey = itemKey
                    globals.waveformAreaDrag.interactingWithArea = true
                    break
                -- Check if clicking inside area to move
                elseif relative_x >= areaStartX and relative_x <= areaEndX then
                    globals.waveformAreaDrag.isMoving = true
                    globals.waveformAreaDrag.movingAreaIndex = i
                    globals.waveformAreaDrag.movingStartOffset = relative_x - areaStartX
                    globals.waveformAreaDrag.currentItemKey = itemKey
                    globals.waveformAreaDrag.interactingWithArea = true
                    break
                end
            end
        end

        -- Set cursor based on hover state
        if hoverOnHandle then
            imgui.SetMouseCursor(ctx, imgui.MouseCursor_ResizeEW)
        elseif hoverOnArea then
            imgui.SetMouseCursor(ctx, imgui.MouseCursor_Hand)
        end

        -- Handle area resizing
        if globals.waveformAreaDrag.isResizing and globals.waveformAreaDrag.currentItemKey == itemKey then
            if imgui.IsMouseDragging(ctx, 0) then
                local area = globals.waveformAreas[itemKey][globals.waveformAreaDrag.resizeAreaIndex]
                if area then
                    local newPos = math.max(0, math.min(1, relative_x / width)) * waveformData.length

                    if globals.waveformAreaDrag.resizeEdge == 'left' then
                        area.startPos = math.min(newPos, area.endPos - 0.01)  -- Minimum area size
                    else
                        area.endPos = math.max(newPos, area.startPos + 0.01)
                    end
                end
            elseif imgui.IsMouseReleased(ctx, 0) then
                globals.waveformAreaDrag.isResizing = false
                globals.waveformAreaDrag.resizeEdge = nil
                globals.waveformAreaDrag.resizeAreaIndex = nil
                globals.waveformAreaDrag.interactingWithArea = false
            end
        end

        -- Handle area moving
        if globals.waveformAreaDrag.isMoving and globals.waveformAreaDrag.currentItemKey == itemKey then
            if imgui.IsMouseDragging(ctx, 0) then
                local area = globals.waveformAreas[itemKey][globals.waveformAreaDrag.movingAreaIndex]
                if area then
                    local newStartX = relative_x - globals.waveformAreaDrag.movingStartOffset
                    local newStartPos = (newStartX / width) * waveformData.length
                    local areaLength = area.endPos - area.startPos

                    -- Clamp the movement to keep area within bounds
                    newStartPos = math.max(0, math.min(waveformData.length - areaLength, newStartPos))

                    area.startPos = newStartPos
                    area.endPos = newStartPos + areaLength
                end
            elseif imgui.IsMouseReleased(ctx, 0) then
                globals.waveformAreaDrag.isMoving = false
                globals.waveformAreaDrag.movingAreaIndex = nil
                globals.waveformAreaDrag.movingStartOffset = 0
                globals.waveformAreaDrag.interactingWithArea = false
            end
        end


        -- Check for right-click for context menu on existing area
        if imgui.IsMouseClicked(ctx, 2) and not globals.waveformAreaDrag.isDragging then  -- Right click
            -- Check if we're clicking on an existing area
            local clickPos = (relative_x / width) * waveformData.length
            local clickedArea, clickedAreaIndex = Waveform_Areas.getAreaAtPosition(itemKey, clickPos, waveformData.length)

            if clickedArea then
                -- Open context menu for existing area
                imgui.OpenPopup(ctx, string.format("##AreaContextMenu_%s_%d", itemKey, clickedAreaIndex))
                globals.contextMenuArea = {area = clickedArea, index = clickedAreaIndex, itemKey = itemKey}
            end
        end

        if globals.waveformAreaDrag.isDragging and globals.waveformAreaDrag.currentItemKey == itemKey then
            if imgui.IsMouseDragging(ctx, 0) then  -- Left drag
                globals.waveformAreaDrag.endX = mouse_x
            elseif imgui.IsMouseReleased(ctx, 0) then  -- Left release
                -- Create the new area
                local startX = math.min(globals.waveformAreaDrag.startX, globals.waveformAreaDrag.endX) - pos_x
                local endX = math.max(globals.waveformAreaDrag.startX, globals.waveformAreaDrag.endX) - pos_x

                -- Convert to time positions
                local startPos = math.max(0, math.min(1, startX / width)) * waveformData.length
                local endPos = math.max(0, math.min(1, endX / width)) * waveformData.length

                -- Only create area if it has meaningful size
                if math.abs(endPos - startPos) > 0.01 then
                    if not globals.waveformAreas[itemKey] then
                        globals.waveformAreas[itemKey] = {}
                    end

                    table.insert(globals.waveformAreas[itemKey], {
                        startPos = startPos,
                        endPos = endPos,
                        name = string.format("Area %d", #globals.waveformAreas[itemKey] + 1)
                    })
                end

                -- Reset drag state
                globals.waveformAreaDrag.isDragging = false
                globals.waveformAreaDrag.startX = 0
                globals.waveformAreaDrag.endX = 0
                globals.waveformAreaDrag.currentItemKey = nil
                globals.waveformAreaDrag.interactingWithArea = false
            end
        end

        -- Show hand cursor for waveform interaction when not on areas
        if not hoverOnHandle and not hoverOnArea and not globals.waveformAreaDrag.isDragging
           and not globals.waveformAreaDrag.isResizing and not globals.waveformAreaDrag.isMoving then
            imgui.SetMouseCursor(ctx, imgui.MouseCursor_Hand)
        end
    else
        -- Reset drag state if mouse left the waveform area
        if globals.waveformAreaDrag.isDragging and imgui.IsMouseReleased(ctx, 0) then
            globals.waveformAreaDrag.isDragging = false
            globals.waveformAreaDrag.currentItemKey = nil
            globals.waveformAreaDrag.interactingWithArea = false
        end
        if globals.waveformAreaDrag.isResizing and imgui.IsMouseReleased(ctx, 0) then
            globals.waveformAreaDrag.isResizing = false
            globals.waveformAreaDrag.resizeAreaIndex = nil
            globals.waveformAreaDrag.currentItemKey = nil
            globals.waveformAreaDrag.interactingWithArea = false
        end
        if globals.waveformAreaDrag.isMoving and imgui.IsMouseReleased(ctx, 0) then
            globals.waveformAreaDrag.isMoving = false
            globals.waveformAreaDrag.movingAreaIndex = nil
            globals.waveformAreaDrag.currentItemKey = nil
            globals.waveformAreaDrag.interactingWithArea = false
        end
    end

    -- Handle area context menu
    if globals.contextMenuArea and globals.contextMenuArea.itemKey == itemKey then
        local menuOpen = imgui.BeginPopup(ctx, string.format("##AreaContextMenu_%s_%d",
                                          globals.contextMenuArea.itemKey,
                                          globals.contextMenuArea.index))
        if menuOpen then
            local area = globals.contextMenuArea.area
            local areaIndex = globals.contextMenuArea.index

            -- Display area info
            imgui.Text(ctx, area.name or string.format("Area %d", areaIndex))
            imgui.Separator(ctx)
            imgui.Text(ctx, string.format("Start: %.2fs", area.startPos))
            imgui.Text(ctx, string.format("End: %.2fs", area.endPos))
            imgui.Text(ctx, string.format("Duration: %.2fs", area.endPos - area.startPos))
            imgui.Separator(ctx)

            -- Rename area
            if imgui.Selectable(ctx, "Rename") then
                -- Set up for rename (would need an input dialog)
                globals.renameAreaDialog = {
                    itemKey = itemKey,
                    index = areaIndex,
                    currentName = area.name or string.format("Area %d", areaIndex),
                    show = true
                }
                imgui.CloseCurrentPopup(ctx)
            end

            -- Play area
            if imgui.Selectable(ctx, "Play Area") then
                -- Start playback from area start
                if options.onWaveformClick then
                    options.onWaveformClick(area.startPos, waveformData)
                end
                imgui.CloseCurrentPopup(ctx)
            end

            imgui.Separator(ctx)

            -- Delete area
            if imgui.Selectable(ctx, "Delete") then
                Waveform_Areas.deleteArea(itemKey, areaIndex)
                imgui.CloseCurrentPopup(ctx)
            end

            -- Clear all areas
            if imgui.Selectable(ctx, "Clear All Areas") then
                Waveform_Areas.clearAreas(itemKey)
                imgui.CloseCurrentPopup(ctx)
            end

            imgui.EndPopup(ctx)
        else
            -- Clear context menu data when popup is closed
            if not menuOpen then
                globals.contextMenuArea = nil
            end
        end
    end

    -- Draw click position marker (where playback will start) - this stays fixed even after stopping
    -- Only show if this is the file that has the saved position
    if globals.audioPreview and globals.audioPreview.clickedPosition and
       globals.audioPreview.currentFile == filePath then
        local clickPos = globals.audioPreview.clickedPosition
        if clickPos and type(clickPos) == "number" and waveformData.length and waveformData.length > 0 then
            -- Calculate position within the waveform
            local markerPos = (clickPos / waveformData.length) * width

            -- Draw marker line (this is the starting point)
            if markerPos >= 0 and markerPos <= width then
                -- Draw a thin, precise marker line
                imgui.DrawList_AddLine(draw_list,
                    pos_x + markerPos, pos_y,
                    pos_x + markerPos, pos_y + height,
                    0xFF8888FF,  -- Light red color for click marker
                    0.5  -- Very thin line (half pixel)
                )
            end
        end
    end

    -- Handle rename dialog
    if globals.renameAreaDialog and globals.renameAreaDialog.show and globals.renameAreaDialog.itemKey == itemKey then
        imgui.OpenPopup(ctx, "Rename Area")

        local flags = imgui.WindowFlags_AlwaysAutoResize | imgui.WindowFlags_NoSavedSettings

        if imgui.BeginPopupModal(ctx, "Rename Area", nil, flags) then
            -- Initialize input buffer if not exists
            if not globals.renameAreaDialog.buffer then
                globals.renameAreaDialog.buffer = globals.renameAreaDialog.currentName
            end

            imgui.Text(ctx, "Enter new name for area:")

            local changed, newName = imgui.InputText(ctx, "##AreaName",
                                                     globals.renameAreaDialog.buffer)
            if changed then
                globals.renameAreaDialog.buffer = newName
            end

            imgui.Spacing(ctx)

            -- OK button
            if imgui.Button(ctx, "OK", 100, 0) or imgui.IsKeyPressed(ctx, imgui.Key_Enter) then
                Waveform_Areas.renameArea(globals.renameAreaDialog.itemKey,
                                   globals.renameAreaDialog.index,
                                   globals.renameAreaDialog.buffer)
                globals.renameAreaDialog = nil
                imgui.CloseCurrentPopup(ctx)
            end

            imgui.SameLine(ctx)

            -- Cancel button
            if imgui.Button(ctx, "Cancel", 100, 0) or imgui.IsKeyPressed(ctx, imgui.Key_Escape) then
                globals.renameAreaDialog = nil
                imgui.CloseCurrentPopup(ctx)
            end

            imgui.EndPopup(ctx)
        end
    end

    return waveformData
end

return Waveform_Rendering
