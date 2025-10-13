# DM AMBIANCE CREATOR - FEATURE GUIDE

Complete reference guide for all features available in DM Ambiance Creator.

---

## 1. AUDIO GENERATION & TIMELINE PLACEMENT

### 1.1 Interval Modes (8 Available Modes)

#### Absolute Mode
- Fixed intervals in seconds between audio elements
- Configurable random variation (drift)
- Supports negative intervals for intentional overlaps with automatic crossfades

#### Relative Mode
- Intervals calculated as percentage of time selection
- Enables pattern scalability across different timeline durations

#### Coverage Mode
- Automatic calculation to achieve target coverage percentage (0-100%)
- System fills timeline according to specified percentage

#### Chunk Mode
- Structured alternation between sound and silence periods
- Configurable chunk and silence durations with variation
- Both durations support percentage-based variation

#### Noise Mode
- Organic placement based on Perlin noise algorithms
- 2 algorithms: Probability and Accumulation
- Advanced parameters:
  - Frequency (Hz)
  - Octaves (fractal detail layers)
  - Persistence (amplitude decrease per octave)
  - Lacunarity (frequency increase per octave)
  - Amplitude (noise influence on placement density)
  - Density (base placement probability)
  - Threshold (minimum noise value for placement)
  - Seed (reproducible random patterns)
- **Real-time visual preview** with legend

#### Euclidean Rhythm Mode
- Optimal mathematical distribution (Bjorklund algorithm)
- Tempo mode (BPM) or fit-to-selection
- Multi-layer support for complex polyrhythms
- **Auto-bind**: Automatically assigns layers to containers
- **Interactive circular preview**
- **Pattern browser** with preset library

### 1.2 Randomization

#### Pitch
- Min/Max range in semitones (-48 to +48)
- Link modes: Unlink, Link, Mirror
- **2 modes**: Pitch Shift (D_PITCH) or Time Stretch (D_PLAYRATE)

#### Volume
- Min/Max range in dB (-24 to +24)
- Link modes: Unlink, Link, Mirror

#### Pan
- Min/Max range (-100 to +100)
- Link modes: Unlink, Link, Mirror
- ⚠️ Automatically disabled for multi-channel containers

### 1.3 Variation Controls

#### Trigger Drift
- Percentage-based variation applied to intervals
- Creates natural timing irregularities

#### Variation Direction
- Negative (←): Variation in negative direction only
- Bipolar (↔): Variation in both directions
- Positive (→): Variation in positive direction only

### 1.4 Advanced Generation Features

#### Negative Intervals (Overlaps)
- Absolute mode supports negative trigger rates
- Automatic crossfades at overlap points

#### Crossfade Support
- Automatic crossfades for overlapping items
- Crossfades with existing items at time selection boundaries
- Uses REAPER's default crossfade shape from preferences

---

## 2. MULTI-CHANNEL AUDIO & ROUTING

### 2.1 Channel Modes

#### Default (Stereo) - 2 channels: L, R

#### 4.0 Quad - 4 channels: L, R, LS, RS

#### 5.0 Surround - 5 channels with variants:
- Variant 0 (Dolby/ITU): L, R, C, LS, RS
- Variant 1 (SMPTE): L, C, R, LS, RS

#### 7.0 Surround - 7 channels with variants:
- Variant 0 (Dolby/ITU): L, R, C, LS, RS, LB, RB
- Variant 1 (SMPTE): L, C, R, LS, RS, LB, RB

⚠️ **Important**: ITU vs SMPTE difference concerns center channel position

### 2.2 Item Distribution

**Round-Robin**: Sequential cycle through child tracks
**Random**: Random track selection per item
**All Tracks**: Places same item on all tracks (for mono sources)

### 2.3 Channel Selection

#### Auto (None): Automatic optimization based on source/output format
- Intelligent downmix
- Skip center for 4.0→5.0/7.0
- Stereo pair extraction

#### Stereo Pairs: Extract specific stereo pairs (Ch 1-2, 3-4, 5-6, 7-8)

#### Mono Split: Single channel extraction or random selection

### 2.4 Routing Validation

**Automatic conflict detection**:
- Channel order conflicts (ITU vs SMPTE)
- Incorrect routing
- Insufficient channel counts
- Orphan sends
- Circular routing

**Auto-Fix**: Automatic correction of detected issues

⚠️ **Warning**: Source format conflicts (files with mixed ITU vs SMPTE orders) are **UNRESOLVABLE**

---

## 3. USER INTERFACE & INTERACTION

### 3.1 Groups & Containers Organization

#### Left Panel - Tree View
- Add/remove groups
- Add/remove containers
- Individual regeneration (↻ button)
- Expand/collapse groups
- Regeneration needed indicator (• prefix)
- Per-group/container presets (searchable dropdowns)

#### Right Panel - Parameter Editor
- Container mode: Detailed parameters
- Group mode: Default parameters
- Multi-selection mode: Batch editing
- Empty mode: Help text

### 3.2 Drag & Drop

#### Groups
- Drag to reorder
- Drop zones: before/after/into
- Visual feedback with insertion lines

#### Containers
- Drag within/between groups
- Multi-selection support (drags all selected)
- Smart drop zones

#### Media Files
- Import from Media Explorer
- Import from Windows Explorer
- Import from timeline items
- Multi-file support

### 3.3 Multi-Selection

**Ctrl+Click**: Toggle individual selection
**Shift+Click**: Range selection
**Cross-group selection**: Across multiple groups
**Dedicated panel**: "Editing N containers" with unified controls
**Clear button**: Deselect all

### 3.4 Custom Widgets

#### Knob (Rotary Control)
- Vertical drag
- Right-click to reset
- Hover animation
- Tooltip with value

#### Enhanced Slider
- Right-click to reset
- Ctrl+Click for manual input
- onChange and onChangeComplete callbacks

#### Linked Sliders
- 3 modes: Unlink, Link, Mirror
- **Keyboard overrides** during drag:
  - Shift: Temporary unlink
  - Ctrl: Temporary link
  - Alt: Temporary mirror

#### Fade Widget
- Visual fade curve editor
- 6 available shapes
- Real-time curve control

---

## 4. WAVEFORM SYSTEM

### 4.1 Visualization

**Multi-channel support**: Up to 8 simultaneous channels
**Adaptive normalization**: Automatically amplifies quiet audio
**Edited item support**: Respects start offset and length
**Info overlay**: Filename, duration, channel count

### 4.2 Interactive Zones

#### Creation
- **Shift + Drag**: Create zone
- Minimum size 0.01s
- Automatic naming

#### Manipulation
- **Drag edges**: Resize (5px handles)
- **Drag interior**: Move
- **Ctrl+Click**: Delete
- Right-click: Context menu (info, rename, play, delete)

#### Display
- Semi-transparent blue rectangle
- White borders
- Label with name and duration

### 4.3 Gate Detection (Auto-Zone Creation)

#### Parameters
- Open Threshold (dB): Gate opening level
- Close Threshold (dB): Closing level (hysteresis)
- Minimum Length (ms): Minimum zone duration
- Start/End Offset (ms): Beginning/end offsets

#### Creation Modes
- **Auto Detect**: Gate detection with thresholds
- **Split Count**: Division into N equal zones
- **Split Time**: Division by specific duration

#### Algorithm
- RMS analysis with 10ms windows
- Hysteresis logic (separate open/close thresholds)
- Debounce: 3 consecutive samples required
- Automatic merging (zones <50ms merged)
- Limit: 100 zones max

### 4.4 Integrated Playback

#### Click-to-Play
- **Left Click (lower half)**: Play at clicked position
- **Double Click**: Reset and play from beginning
- **Drag**: Scrub through audio

#### Controls
- Adjustable preview volume
- Per-item gain (±60dB to +24dB)
- Real-time position marker
- Auto-stop at edited item boundaries

#### Shortcuts
- **Space**: Play/pause

---

## 5. PRESETS & MEDIA MANAGEMENT

### 5.1 Preset Types

#### Global Presets
- Saves complete project state
- All groups + all containers

#### Group Presets
- Saves one group with its containers

#### Container Presets
- Saves one container with its items

### 5.2 File System

#### Media Directory (centralized repository)
- Configuration in Settings
- Automatic file copying on preset save
- ⚠️ Required to save presets

#### Auto-Import Media
- Enabled by default
- Trade-off: Portability vs disk space

#### Paths
- Always absolute (never relative)
- Cross-platform compatible

### 5.3 Preset Interface

**Searchable Dropdowns**: Real-time filtering
**Load/Save/Delete**: Buttons per preset type
**Open Directory**: Opens preset folder
**Media Directory Warning**: Alerts if not configured

### 5.4 Pattern Browser (Euclidean)

**Pattern Library**
- Categorized patterns (Basic/Complex/etc.)
- Save/Load/Override/Delete patterns
- Auto-naming: "pulses-steps-rotation"

---

## 6. FADES & ENVELOPES

### 6.1 Fade Controls

#### Independent Fade In/Out
- Enable/disable per fade
- Units: seconds or percentage
- Duration sliders

#### Fade Shapes
- Linear
- Equal Power
- Fast Start
- Fast End
- S-Curve
- Bezier (with curve control)

#### Link Modes for Fades
- Unlink: Independent
- Link: Synchronized movement
- Mirror: Symmetric from center

---

## 7. SETTINGS & PREFERENCES

### 7.1 Global Settings

#### UI Appearance
- UI Scale (0.5-2.0)
- Corner Rounding (0-12px)
- Item Spacing (0-20px)
- Customizable colors (buttons, background, text, waveform, icons)
- Show Knob Indicator

#### Waveform
- Auto-play on select
- Waveform color
- Left panel width (saved)

#### Media Management
- Media Directory path
- Auto-import media toggle

#### Crossfade
- Default crossfade margin (0.05-2.0s)

### 7.2 Live Preview

**Temporary Buffer**: Changes previewed before saving
**Cancel**: Restores original values
**Save & Close**: Applies and persists

---

## 8. INHERITANCE SYSTEM

### 8.1 Override Parent

#### Checkbox per container
- Enabled: Container uses its own parameters
- Disabled: Container inherits from parent group

#### Inherited Parameters
- All randomization parameters
- Trigger settings (rate, drift, mode)
- Chunk/Noise/Euclidean settings
- Fade settings
- Link modes

#### Cascade
- Container → Group → Constants (default values)

---

## 9. KEYBOARD SHORTCUTS

### 9.1 Global

- **Ctrl+C**: Copy group/container(s)
- **Ctrl+V**: Paste
- **Ctrl+D**: Duplicate
- **Del**: Delete
- **Space**: Play/pause (in waveform)

### 9.2 Widgets

- **Right-Click**: Reset slider/knob
- **Ctrl+Click**: Manual input (sliders)
- **Shift+Drag**: Create waveform zone
- **Ctrl+Click**: Delete waveform zone
- **Double-Click**: Reset waveform marker

### 9.3 Link Mode Overrides (during drag)

- **Shift+Drag**: Temporary unlink
- **Ctrl+Drag**: Temporary link
- **Alt+Drag**: Temporary mirror

---

## 10. SPECIALIZED FEATURES

### 10.1 Undo/Redo History

- Visual timeline of states
- Click to return to a state
- Automatic change capture
- Descriptive labels

### 10.2 Real-Time Previews

#### Noise Preview
- Noise curve visualization
- Green item markers
- Legend with icons
- Real-time updates

#### Euclidean Preview
- Circular display
- Concentric circles (auto-bind mode)
- Colored dots per layer
- Central info (mode/tempo/steps)

### 10.3 Track Management

#### Track Hierarchy
```
Project
└── Group Folder
    ├── Container Track (or Folder if multi-channel)
    │   ├── Channel Track L
    │   ├── Channel Track R
    │   └── ... (more channels)
    └── ...
```

#### Volume Controls
- Per group (dB, Solo, Mute)
- Per container (dB, Solo, Mute)
- Per channel (for multi-channel)

### 10.4 Validation & Errors

#### Error Handler
- 4 levels: INFO, WARNING, ERROR, CRITICAL
- Safe execution with retry
- Parameter validation
- Logging to REAPER console

#### Routing Validator
- Complete project scan
- Conflict detection
- Auto-fix for common issues
- Modal with error list

### 10.5 Icons & Visual Feedback

#### 14 Icon Types
- Action: delete, regen, upload, download, add
- UI: settings, folder, conflict
- Link: link, unlink, mirror
- Direction: arrow_left, arrow_right, arrow_both
- History: undo, redo, history

#### Dynamic States
- Normal, Hovered, Active
- Colored tint based on state
- Text fallback if icon missing

---

## IMPORTANT CONSIDERATIONS

### ⚠️ Multi-Channel Audio

1. **Configure source format early**: Specify ITU or SMPTE for 5.0/7.0 files
2. **Source format conflicts UNRESOLVABLE**: Do not mix ITU and SMPTE files in same project
3. **Run validation before generation**: Avoids routing issues
4. **Pan auto-disabled**: For multi-channel containers (prevents conflicts)

### ⚠️ Media Management

1. **Always configure Media Directory**: Required to save presets
2. **Auto-Import enabled recommended**: Maximizes preset portability
3. **Absolute paths only**: No relative paths
4. **Preview before saving**: Verify files are accessible

### ⚠️ Performance

1. **Waveform cache limit**: Implements LRU to avoid memory overload
2. **Validation cached 1 second**: Avoids repeated scans
3. **100 zones max per waveform**: Prevents UI issues
4. **Debounce gate detection**: Avoids UI lag during adjustments

### ⚠️ Workflow

1. **Time selection required**: All items placed within selection
2. **Undo/Redo available**: Use History browser for complex states
3. **Override Parent with caution**: Loses group inheritance
4. **Multi-selection for batch edits**: More efficient than individual modifications

---

## COMPATIBILITY & DEPENDENCIES

### Required
- REAPER (DAW)
- ReaImGui extension (for UI)

### Recommended
- SWS Extension (for audio preview and folder browser)
- JS_ReaScriptAPI (for improved folder browser)

### Installation
- Via ReaPack (recommended)
- Or manual copy to REAPER Scripts folder

### Platforms
- Windows ✓
- macOS ✓
- Linux ✓

---

**END OF DOCUMENT**
