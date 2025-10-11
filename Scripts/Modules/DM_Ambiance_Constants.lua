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
    LEFT_PANEL_DEFAULT_WIDTH = 0.35,    -- Default left panel width as percentage of window
    MIN_LEFT_PANEL_WIDTH = 150,         -- Minimum left panel width in pixels
    SPLITTER_WIDTH = 4,                 -- Width of the splitter/divider
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
    VOLUME_RANGE_DB_MIN = -144,         -- Minimum volume range for sliders (dB, -inf)
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
    NOISE = 4,                          -- Noise mode: placement based on noise function
    EUCLIDEAN = 5,                      -- Euclidean rhythm: mathematically optimal distribution
    FIBONACCI = 6,                      -- Fibonacci sequence: intervals based on Fibonacci numbers
    GOLDEN_RATIO = 7,                   -- Golden ratio: intervals based on φ (phi ≈ 1.618)
}

-- Noise Algorithm Mode Constants
Constants.NOISE_ALGORITHMS = {
    PROBABILITY = 0,                    -- Probability test at intervals with jitter
    ACCUMULATION = 1,                   -- Probability accumulation until threshold
}

-- Channel Mode Constants
Constants.CHANNEL_MODES = {
    DEFAULT = 0,                        -- Standard stereo (1/2)
    QUAD = 1,                          -- 4.0: L, R, LS, RS
    FIVE_ZERO = 2,                     -- 5.0: L, R, C, LS, RS or L, C, R, LS, RS
    SEVEN_ZERO = 3                     -- 7.0: L, R, C, LS, RS, LB, RB or L, C, R, LS, RS, LB, RB
}

-- Channel Configuration Details
Constants.CHANNEL_CONFIGS = {
    [0] = {
        name = "Default (Stereo)",
        channels = 0,  -- No child tracks, generate on container
        totalChannels = 2,
        routing = nil,
        labels = nil
    },
    [1] = {
        name = "4.0 Quad",
        channels = 4,
        totalChannels = 4,
        routing = {1, 2, 3, 4},  -- Each track to single channel
        labels = {"L", "R", "LS", "RS"}
    },
    [2] = {
        name = "5.0",
        channels = 5,
        totalChannels = 5,
        hasVariants = true,
        variants = {
            [0] = {
                name = "Dolby/ITU (L R C LS RS)",
                routing = {1, 2, 3, 4, 5},
                labels = {"L", "R", "C", "LS", "RS"}
            },
            [1] = {
                name = "SMPTE (L C R LS RS)",
                routing = {1, 3, 2, 4, 5},  -- C in position 2
                labels = {"L", "C", "R", "LS", "RS"}
            }
        }
    },
    [3] = {
        name = "7.0",
        channels = 7,
        totalChannels = 7,
        hasVariants = true,
        variants = {
            [0] = {
                name = "Dolby/ITU (L R C LS RS LB RB)",
                routing = {1, 2, 3, 4, 5, 6, 7},
                labels = {"L", "R", "C", "LS", "RS", "LB", "RB"}
            },
            [1] = {
                name = "SMPTE (L C R LS RS LB RB)",
                routing = {1, 3, 2, 4, 5, 6, 7},  -- C in position 2
                labels = {"L", "C", "R", "LS", "RS", "LB", "RB"}
            }
        }
    }
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

-- Pitch Mode Constants
Constants.PITCH_MODES = {
    PITCH = 0,                          -- Standard pitch shift (D_PITCH)
    STRETCH = 1,                        -- Time stretch (D_PLAYRATE)
}

-- Variation Direction Constants
Constants.VARIATION_DIRECTIONS = {
    NEGATIVE = 0,                       -- Negative only (←)
    BIPOLAR = 1,                        -- Bipolar (↔)
    POSITIVE = 2,                       -- Positive only (→)
}

-- Noise Generation Algorithm Constants
Constants.NOISE_GENERATION = {
    SKIP_INTERVAL = 0.5,                -- Seconds to skip ahead in silent zones
    MIN_INTERVAL_MULTIPLIER = 0.3,      -- Minimum interval as multiplier of average item length
    MAX_INTERVAL_SECONDS = 10.0,        -- Maximum spacing when curve is near 0
    SELECTION_TIME_OFFSET = 0.123,      -- Time offset to decorrelate item selection noise
    SELECTION_SEED_OFFSET = 12345,      -- Seed offset for item selection noise
    SELECTION_FREQ_MULT = 1.23,         -- Frequency multiplier for item selection
    AREA_TIME_OFFSET = 0.456,           -- Time offset to decorrelate area selection noise
    AREA_SEED_OFFSET = 67890,           -- Seed offset for area selection noise
    AREA_FREQ_MULT = 0.87,              -- Frequency multiplier for area selection
}

-- Default Values
Constants.DEFAULTS = {
    TRIGGER_RATE = 10.0,                -- Default trigger rate
    TRIGGER_DRIFT = 30,                 -- Default trigger drift percentage
    TRIGGER_DRIFT_DIRECTION = 1,        -- Default trigger drift direction (BIPOLAR)
    PITCH_MODE = 0,                     -- Default pitch mode (PITCH)
    PITCH_RANGE_MIN = -3,               -- Default min pitch range
    PITCH_RANGE_MAX = 3,                -- Default max pitch range
    VOLUME_RANGE_MIN = -3,              -- Default min volume range (dB)
    VOLUME_RANGE_MAX = 3,               -- Default max volume range (dB)
    PAN_RANGE_MIN = -100,               -- Default min pan range
    PAN_RANGE_MAX = 100,                -- Default max pan range
    CONTAINER_VOLUME_DEFAULT = 0.0,     -- Default container track volume (dB)
    UI_SCALE = 1.0,                     -- Default UI scale factor (1.0 = 100%)
    -- Chunk Mode defaults
    CHUNK_DURATION = 10.0,              -- Default chunk duration in seconds
    CHUNK_SILENCE = 5.0,                -- Default silence duration in seconds
    CHUNK_DURATION_VARIATION = 20,      -- Default chunk duration variation percentage
    CHUNK_DURATION_VAR_DIRECTION = 1,   -- Default chunk duration variation direction (BIPOLAR)
    CHUNK_SILENCE_VARIATION = 20,       -- Default silence duration variation percentage
    CHUNK_SILENCE_VAR_DIRECTION = 1,    -- Default silence variation direction (BIPOLAR)
    -- Noise Mode defaults
    NOISE_SEED_MIN = 1,                 -- Minimum seed value
    NOISE_SEED_MAX = 999999,            -- Maximum seed value
    NOISE_FREQUENCY = 1.0,              -- Default noise frequency (Hz)
    NOISE_AMPLITUDE = 100.0,            -- Default noise amplitude (%)
    NOISE_OCTAVES = 2,                  -- Default number of octaves
    NOISE_PERSISTENCE = 0.5,            -- Default persistence (amplitude decrease per octave)
    NOISE_LACUNARITY = 2.0,             -- Default lacunarity (frequency increase per octave)
    NOISE_DENSITY = 50.0,               -- Default average density percentage
    NOISE_THRESHOLD = 0.0,              -- Default minimum noise value to place item
    NOISE_ALGORITHM = 0,                -- Default algorithm (PROBABILITY)
    -- Euclidean Mode defaults
    EUCLIDEAN_MODE = 0,                 -- Default mode (0=Tempo-Based, 1=Fit-to-Selection)
    EUCLIDEAN_TEMPO = 120,              -- Default tempo (BPM)
    EUCLIDEAN_USE_PROJECT_TEMPO = false, -- Default use project tempo
    EUCLIDEAN_PULSES = 8,               -- Default number of pulses (hits)
    EUCLIDEAN_STEPS = 16,               -- Default number of steps (subdivisions)
    EUCLIDEAN_ROTATION = 0,             -- Default rotation offset
    EUCLIDEAN_SELECTED_LAYER = 1,       -- Default selected layer index
    -- Fibonacci Mode defaults
    FIBONACCI_MODE = 0,                 -- Default mode (0=Tempo-Based, 1=Fit-to-Selection)
    FIBONACCI_TEMPO = 120,              -- Default tempo (BPM)
    FIBONACCI_START = 2,                -- Default start index in sequence (2 = first '2' in 1,1,2,3,5...)
    FIBONACCI_SCALE = 1.0,              -- Default time scale multiplier
    FIBONACCI_COUNT = 8,                -- Default count for fit-to-selection mode
    -- Golden Ratio Mode defaults
    GOLDEN_RATIO_MODE = 0,              -- Default mode (0=Tempo-Based, 1=Fit-to-Selection)
    GOLDEN_RATIO_TEMPO = 120,           -- Default tempo (BPM)
    GOLDEN_RATIO_BASE = 1.0,            -- Default base interval (beats)
    GOLDEN_RATIO_DEPTH = 5,             -- Default recursion depth for fit-to-selection
    -- Fade defaults
    FADE_IN_ENABLED = true,             -- Default fade in state
    FADE_OUT_ENABLED = true,            -- Default fade out state
    FADE_IN_DURATION = 0.0,             -- Default fade in duration (seconds)
    FADE_OUT_DURATION = 0.0,            -- Default fade out duration (seconds)
    FADE_IN_USE_PERCENTAGE = true,      -- Use percentage by default
    FADE_OUT_USE_PERCENTAGE = true,     -- Use percentage by default
    FADE_IN_SHAPE = 0,                  -- Default to linear fade
    FADE_OUT_SHAPE = 0,                 -- Default to linear fade
    FADE_IN_CURVE = 0.0,                -- Default curve control
    FADE_OUT_CURVE = 0.0,               -- Default curve control
}

return Constants