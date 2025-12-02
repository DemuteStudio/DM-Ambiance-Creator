--[[
@version 1.0
@noindex
DM Ambiance Creator - Waveform Playback Module
Audio preview and playback controls for waveform display.
--]]

local Waveform_Playback = {}
local globals = {}

function Waveform_Playback.initModule(g)
    globals = g
end

-- Start audio playback from a specific position
-- @param filePath: path to the audio file
-- @param startOffset: start offset in the file (in seconds)
-- @param length: length of the item (in seconds)
-- @param relativePosition: position relative to startOffset (in seconds)
function Waveform_Playback.startPlayback(filePath, startOffset, length, relativePosition)
    if not filePath or filePath == "" then
        return false
    end

    Waveform_Playback.stopPlayback()

    local file = io.open(filePath, "r")
    if not file then
        return false
    end
    file:close()

    -- Check if SWS extension is available for isolated playback
    if reaper.CF_CreatePreview then
        local source = reaper.PCM_Source_CreateFromFile(filePath)
        if not source then
            return false
        end

        local preview = reaper.CF_CreatePreview(source)
        if not preview then
            reaper.PCM_Source_Destroy(source)
            return false
        end

        globals.audioPreview.cfPreview = preview
        globals.audioPreview.cfSource = source

        -- Calculate actual start position
        local actualStartPos = startOffset or 0
        if relativePosition and relativePosition > 0 then
            actualStartPos = actualStartPos + relativePosition
            -- Ensure we don't exceed the item bounds
            if length and actualStartPos > (startOffset or 0) + length then
                actualStartPos = (startOffset or 0) + length
            end
        end

        -- Apply gain scaling to preview volume
        local baseVolume = globals.audioPreview.volume or 0.7
        local gainDB = globals.audioPreview.gainDB or 0.0
        local gainScale = 10 ^ (gainDB / 20)  -- Convert dB to linear
        local scaledVolume = baseVolume * gainScale

        reaper.CF_Preview_SetValue(preview, 'D_VOLUME', scaledVolume)
        reaper.CF_Preview_SetValue(preview, 'D_POSITION', actualStartPos)
        reaper.CF_Preview_SetValue(preview, 'B_LOOP', 0)

        reaper.CF_Preview_Play(preview)

        globals.audioPreview.isPlaying = true
        globals.audioPreview.currentFile = filePath
        globals.audioPreview.startTime = reaper.time_precise()
        globals.audioPreview.position = actualStartPos  -- This is the absolute position in the file
        globals.audioPreview.startOffset = startOffset or 0
        globals.audioPreview.playbackLength = length or nil
        globals.audioPreview.clickedPosition = relativePosition  -- Store for visual feedback (relative to item)
        globals.audioPreview.playbackStartPosition = actualStartPos  -- Store where playback actually started (absolute)

        return true
    end

    return false
end

-- Stop audio playback
-- @param resetToStart: if true, reset position to beginning instead of keeping current marker position
function Waveform_Playback.stopPlayback(resetToStart)
    if globals.audioPreview.isPlaying then
        local startOffset = globals.audioPreview.startOffset or 0

        if globals.audioPreview.cfPreview then
            reaper.CF_Preview_Stop(globals.audioPreview.cfPreview)

            if globals.audioPreview.cfSource then
                reaper.PCM_Source_Destroy(globals.audioPreview.cfSource)
            end

            globals.audioPreview.cfPreview = nil
            globals.audioPreview.cfSource = nil
        end

        globals.audioPreview.isPlaying = false
        -- KEEP currentFile so the marker stays visible for the correct file
        -- globals.audioPreview.currentFile = nil  -- DON'T clear this or the marker will disappear

        if resetToStart then
            -- Reset to beginning
            globals.audioPreview.position = startOffset
            globals.audioPreview.clickedPosition = 0
        end
        -- If not resetToStart, keep the existing position/clickedPosition unchanged

        globals.audioPreview.playbackStartPosition = nil  -- Clear the start position
    end
end

-- Update playback position
function Waveform_Playback.updatePlaybackPosition()
    if globals.audioPreview.isPlaying and globals.audioPreview.cfPreview then
        local pos = reaper.CF_Preview_GetValue(globals.audioPreview.cfPreview, 'D_POSITION')
        if pos and type(pos) == "number" then
            globals.audioPreview.position = pos

            -- Check if we've reached the end of the edited portion
            if globals.audioPreview.playbackLength then
                local endPosition = (globals.audioPreview.startOffset or 0) + globals.audioPreview.playbackLength
                if pos >= endPosition then
                    -- Stop and reset to start
                    Waveform_Playback.stopPlayback(true)  -- Reset to beginning
                    return
                end
            end
        else
            -- Fallback: calculate position based on elapsed time
            local currentTime = reaper.time_precise()
            local elapsed = currentTime - globals.audioPreview.startTime

            -- Use playbackStartPosition if we started from a clicked position
            -- This ensures the visual position starts at the clicked point
            if globals.audioPreview.playbackStartPosition then
                globals.audioPreview.position = globals.audioPreview.playbackStartPosition + elapsed
            else
                globals.audioPreview.position = (globals.audioPreview.startOffset or 0) + elapsed
            end

            -- Check elapsed time
            if globals.audioPreview.playbackLength then
                -- Calculate remaining time based on where we started
                local effectiveLength = globals.audioPreview.playbackLength
                if globals.audioPreview.clickedPosition then
                    effectiveLength = globals.audioPreview.playbackLength - globals.audioPreview.clickedPosition
                end

                if elapsed >= effectiveLength then
                    Waveform_Playback.stopPlayback(true)  -- Reset to beginning
                    return
                end
            end
        end

        local isPlaying = reaper.CF_Preview_GetValue(globals.audioPreview.cfPreview, 'B_PLAY')
        if isPlaying and isPlaying == 0 then
            Waveform_Playback.stopPlayback(true)  -- Reset to beginning when preview stops externally
        end
    end
end

-- Set preview volume
function Waveform_Playback.setPreviewVolume(volume)
    globals.audioPreview.volume = volume

    if globals.audioPreview.cfPreview then
        -- Apply gain scaling to volume
        local gainDB = globals.audioPreview.gainDB or 0.0
        local gainScale = 10 ^ (gainDB / 20)  -- Convert dB to linear
        local scaledVolume = volume * gainScale

        reaper.CF_Preview_SetValue(globals.audioPreview.cfPreview, 'D_VOLUME', scaledVolume)
    end
end

-- Clear saved playback position (marker)
function Waveform_Playback.clearSavedPosition()
    if globals.audioPreview then
        globals.audioPreview.clickedPosition = nil
        globals.audioPreview.playbackStartPosition = nil
    end
end

-- Reset position for a specific file
function Waveform_Playback.resetPositionForFile(filePath)
    if globals.audioPreview and globals.audioPreview.currentFile == filePath then
        globals.audioPreview.clickedPosition = nil
        globals.audioPreview.playbackStartPosition = nil
        globals.audioPreview.currentFile = nil
    end
end

return Waveform_Playback
