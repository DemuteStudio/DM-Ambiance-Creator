--[[
@version 1.4
@noindex
--]]

-- Constants for the Ambiance Creator
local Constants = {}

-- UI Constants
Constants.UI = {
    CONTAINER_INDENT = 20,              -- Indentation for containers in UI
    HELP_MARKER_TEXT_WRAP = 35.0,       -- Text wrap position for help markers
    PRESET_SELECTOR_WIDTH = 200,        -- Width of preset selector dropdowns
    BUTTON_WIDTH_STANDARD = 120,        -- Standard button width
    BUTTON_WIDTH_WIDE = 150,            -- Wide button width
    GROUP_DROP_ZONE_HEIGHT = 8,         -- Height of group drop zones
    CONTAINER_DROP_ZONE_HEIGHT = 6,     -- Height of container drop zones
    MIN_WINDOW_HEIGHT = 100,            -- Minimum window height
    MIN_WINDOW_WIDTH = 200,             -- Minimum window width
}

-- Color Constants
Constants.COLORS = {
    ERROR_RED = 0xFF0000FF,             -- Red color for errors
    SUCCESS_GREEN = 0xFF4CAF50,         -- Green color for success
    WARNING_ORANGE = 0xFF8000FF,        -- Orange color for warnings
    DEFAULT_WHITE = 0xFFFFFFFF,         -- Default white color
}

-- Audio Constants
Constants.AUDIO = {
    DEFAULT_CROSSFADE_MARGIN = 0.1,     -- Default crossfade margin in seconds
    DEFAULT_FADE_SHAPE = 0,             -- Default fade shape
    VOLUME_RANGE_DB_MIN = -60,          -- Minimum volume range for sliders (dB)
    VOLUME_RANGE_DB_MAX = 24,           -- Maximum volume range for sliders (dB)
}

-- File System Constants
Constants.FILESYSTEM = {
    PRESET_CACHE_TTL = 3600,            -- Preset cache time-to-live in seconds
}

-- Track Constants
Constants.TRACKS = {
    FOLDER_START_DEPTH = 1,             -- Folder start depth value
    FOLDER_END_DEPTH = -1,              -- Folder end depth value
    NORMAL_TRACK_DEPTH = 0,             -- Normal track depth value
}

-- Trigger Mode Constants
Constants.TRIGGER_MODES = {
    ABSOLUTE = 0,                       -- Absolute interval mode
    RELATIVE = 1,                       -- Relative interval mode  
    COVERAGE = 2,                       -- Coverage interval mode
    CHUNK = 3,                          -- Chunk mode: structured sound/silence periods
}

-- Fade Shape Constants (Reaper API values)
Constants.FADE_SHAPES = {
    LINEAR = 0,                         -- Linear fade
    FAST_START = 1,                     -- Fast start (log)
    FAST_END = 2,                       -- Fast end (exp)
    FAST_START_END = 3,                 -- Fast start/end
    SLOW_START_END = 4,                 -- Slow start/end  
    BEZIER = 5,                         -- Bezier curve
    S_CURVE = 6,                        -- S-curve
}

-- Default Values
Constants.DEFAULTS = {
    TRIGGER_RATE = 10.0,                -- Default trigger rate
    TRIGGER_DRIFT = 30,                 -- Default trigger drift percentage
    PITCH_RANGE_MIN = -3,               -- Default min pitch range
    PITCH_RANGE_MAX = 3,                -- Default max pitch range
    VOLUME_RANGE_MIN = -3,              -- Default min volume range (dB)
    VOLUME_RANGE_MAX = 3,               -- Default max volume range (dB)
    PAN_RANGE_MIN = -100,               -- Default min pan range
    PAN_RANGE_MAX = 100,                -- Default max pan range
    CONTAINER_VOLUME_DEFAULT = 0.0,     -- Default container track volume (dB)
    -- Chunk Mode defaults
    CHUNK_DURATION = 10.0,              -- Default chunk duration in seconds
    CHUNK_SILENCE = 5.0,                -- Default silence duration in seconds
    CHUNK_DURATION_VARIATION = 20,      -- Default chunk duration variation percentage
    CHUNK_SILENCE_VARIATION = 20,       -- Default silence duration variation percentage
    -- Fade defaults
    FADE_IN_ENABLED = true,             -- Default fade in state
    FADE_OUT_ENABLED = true,            -- Default fade out state
    FADE_IN_DURATION = 0.0,             -- Default fade in duration (seconds)
    FADE_OUT_DURATION = 0.0,            -- Default fade out duration (seconds)
    FADE_IN_USE_PERCENTAGE = false,     -- Use percentage by default
    FADE_OUT_USE_PERCENTAGE = false,    -- Use percentage by default
    FADE_IN_SHAPE = 0,                  -- Default to linear fade
    FADE_OUT_SHAPE = 0,                 -- Default to linear fade
    FADE_IN_CURVE = 0.0,                -- Default curve control
    FADE_OUT_CURVE = 0.0,               -- Default curve control
}

return Constants