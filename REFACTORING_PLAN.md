# Refactoring Plan: DM Ambiance Creator

**Generated:** 2025-12-02
**Project:** DM Ambiance Creator (REAPER Lua Script)
**Total LOC:** 34,764 lines
**Status:** NEEDS_REFACTORING (Critical violations detected)

---

## Executive Summary

| Metric | Current | Target | Status |
|--------|---------|--------|--------|
| Total LOC | 34,764 | N/A (Lua) | ℹ️ INFO |
| Largest file | 5,057 lines | <1,000 | 🔴 CRITICAL (5x over) |
| Largest function | 548 lines | <100 | 🔴 CRITICAL (5.5x over) |
| Files over 1000 lines | 8 | 0 | 🔴 CRITICAL |
| Files over 500 lines | 16 | 0 (ideally) | 🟡 ALERT |
| Files in root | 1 | ≤4 | ✅ EXCELLENT |

**Estimated refactoring effort:** 25+ modules to split, ~20-30 hours

**Priority Level:** URGENT - Multiple BLOCK-level violations

---

## Critical Violations (MUST FIX)

### 1. DM_Ambiance_Generation.lua - MONOLITHIC FILE

**Location:** `Scripts/Modules/DM_Ambiance_Generation.lua`
**Type:** FILE_SIZE
**Current:** 5,057 lines
**Limit:** 1,000 lines (BLOCK), 500 lines (ALERT)
**Severity:** 🔴 CRITICAL (5x over limit)

**Responsibilities detected:**
- Item placement logic with 6 different interval modes
- Multi-channel track creation and routing
- Track structure determination and folder management
- Generation for groups, containers, and individual items
- Project state validation and conflict resolution
- Channel requirement calculation and validation
- Noise mode and Euclidean rhythm generation
- Crossfade and fade management
- Collision detection and item positioning

**Proposed extraction:**

| New Module | Location | Est. Lines | Responsibility |
|------------|----------|------------|----------------|
| Generation_Core.lua | Audio/Generation_Core.lua | ~400 | Main generation coordinator, group/container generation |
| Generation_ItemPlacement.lua | Audio/Generation_ItemPlacement.lua | ~600 | Item placement core logic (from placeItemsForContainer) |
| Generation_Modes.lua | Audio/Generation_Modes.lua | ~800 | All interval mode implementations (exact, random, chunk, coverage, noise, euclidean) |
| Generation_MultiChannel.lua | Audio/Generation_MultiChannel.lua | ~900 | Channel routing, track structure, routing matrix |
| Generation_TrackManagement.lua | Audio/Generation_TrackManagement.lua | ~500 | REAPER track creation, folder structure, GUID management |
| Generation_Validation.lua | Audio/Generation_Validation.lua | ~700 | State validation, conflict resolution, channel requirements |
| Generation_Helpers.lua | Audio/Generation_Helpers.lua | ~300 | Shared utility functions for generation |

**After refactoring:**
- Original file: REMOVED (split into 7 modules)
- New modules: 7 files averaging ~600 lines each
- All modules < 1,000 line limit ✅

---

### 2. Generation.placeItemsForContainer - MEGA FUNCTION

**Location:** `Scripts/Modules/DM_Ambiance_Generation.lua:706-1253`
**Type:** FUNCTION_SIZE
**Current:** 548 lines
**Limit:** 100 lines (BLOCK), 80 lines (ALERT)
**Severity:** 🔴 CRITICAL (5.5x over limit)

**Responsibilities detected:**
- Interval calculation for 6 different modes
- Position calculation with drift and variation
- Channel routing and selection
- Multi-track placement logic
- Randomization application (pitch, volume, rate, etc.)
- Fade-in and fade-out application
- Crossfade creation and management
- Collision detection and handling
- Item color and naming

**Proposed decomposition:**

| New Function | Est. Lines | Responsibility |
|--------------|------------|----------------|
| calculateInterval() | ~60 | Calculate interval based on mode (exact/random/chunk/coverage) |
| calculateItemPosition() | ~80 | Calculate position with drift, variation, grid quantization |
| selectChannelForItem() | ~70 | Channel routing logic (direct/random/sequential/algorithm) |
| createItemOnTrack() | ~50 | REAPER item creation and basic properties |
| applyItemRandomization() | ~60 | Apply all randomization parameters (pitch, volume, rate, etc.) |
| applyItemFades() | ~40 | Apply fade-in and fade-out with randomization |
| handleItemCollision() | ~50 | Collision detection and resolution |
| createCrossfade() | ~40 | Crossfade creation between items |
| placeItemsForContainer() [coordinator] | ~80 | Main loop coordinating all helper functions |

**After refactoring:**
- Original function: ~80 lines (coordinator only)
- New helper functions: 8 functions averaging ~56 lines each
- All functions < 100 line limit ✅

---

### 3. DM_Ambiance_Utils.lua - UTILITY BLOAT

**Location:** `Scripts/Modules/DM_Ambiance_Utils.lua`
**Type:** FILE_SIZE
**Current:** 3,818 lines
**Limit:** 1,000 lines (BLOCK)
**Severity:** 🔴 CRITICAL (3.8x over limit)

**Responsibilities detected:**
- Deep copy and table manipulation
- UUID generation
- File path validation
- Mathematical helpers (randomization, conversions)
- REAPER API wrappers (track, item, FX operations)
- UI helpers (HelpMarker, tooltips)
- String utilities
- Validation functions

**Proposed extraction:**

| New Module | Location | Est. Lines | Responsibility |
|------------|----------|------------|----------------|
| Utils_Core.lua | Utils/Utils_Core.lua | ~800 | Essential utilities (deepCopy, UUID, table helpers) |
| Utils_Math.lua | Utils/Utils_Math.lua | ~600 | Mathematical helpers (randomization, conversions, range mapping) |
| Utils_REAPER.lua | Utils/Utils_REAPER.lua | ~1,200 | REAPER API wrappers (tracks, items, FX, media sources) |
| Utils_UI.lua | Utils/Utils_UI.lua | ~500 | UI helpers (HelpMarker, tooltips, formatters) |
| Utils_Validation.lua | Utils/Utils_Validation.lua | ~400 | Validation functions (paths, values, ranges) |
| Utils_String.lua | Utils/Utils_String.lua | ~300 | String utilities (formatting, parsing) |

**After refactoring:**
- Original file: REMOVED (split into 6 modules)
- New modules: 6 files, 1 file slightly over 1000 lines (needs further split)
- Subdirectory: Utils/

---

### 4. DM_Ambiance_UI.lua - MIXED UI LOGIC

**Location:** `Scripts/Modules/DM_Ambiance_UI.lua`
**Type:** FILE_SIZE
**Current:** 3,724 lines
**Limit:** 1,000 lines (BLOCK)
**Severity:** 🔴 CRITICAL (3.7x over limit)

**Note:** Many UI components are already extracted to separate UI_*.lua files. This file contains remaining orchestration logic.

**Proposed extraction:**

| New Module | Location | Est. Lines | Responsibility |
|------------|----------|------------|----------------|
| UI_Layout.lua | UI/Core/UI_Layout.lua | ~800 | Layout management, positioning logic |
| UI_EventHandlers.lua | UI/Core/UI_EventHandlers.lua | ~600 | Global event handling |
| UI_Rendering.lua | UI/Core/UI_Rendering.lua | ~900 | Rendering coordination |
| UI_State.lua | UI/Core/UI_State.lua | ~700 | UI state management |
| UI_Helpers.lua | UI/Core/UI_Helpers.lua | ~500 | Shared UI utilities |

**After refactoring:**
- Original file: REMOVED (split into 5 modules)
- New modules: 5 files averaging ~700 lines each
- All modules < 1,000 line limit ✅

---

### 5. DM_Ambiance_RoutingValidator.lua - VALIDATION MONOLITH

**Location:** `Scripts/Modules/DM_Ambiance_RoutingValidator.lua`
**Type:** FILE_SIZE
**Current:** 2,901 lines
**Limit:** 1,000 lines (BLOCK)
**Severity:** 🔴 CRITICAL (2.9x over limit)

**Responsibilities detected:**
- Routing validation logic
- Conflict detection
- Fix suggestions and auto-correction
- Channel mapping validation
- Configuration auditing

**Proposed extraction:**

| New Module | Location | Est. Lines | Responsibility |
|------------|----------|------------|----------------|
| RoutingValidator_Core.lua | Routing/RoutingValidator_Core.lua | ~1,000 | Core validation logic |
| RoutingValidator_Conflicts.lua | Routing/RoutingValidator_Conflicts.lua | ~900 | Conflict detection and resolution |
| RoutingValidator_Fixes.lua | Routing/RoutingValidator_Fixes.lua | ~1,000 | Auto-correction and fix suggestions |

**After refactoring:**
- Original file: REMOVED (split into 3 modules)
- New modules: 3 files at or just at 1,000 line limit
- May need further decomposition for strictness

---

### 6. DM_Ambiance_Waveform.lua - WAVEFORM ANALYSIS

**Location:** `Scripts/Modules/DM_Ambiance_Waveform.lua`
**Type:** FILE_SIZE
**Current:** 2,597 lines
**Limit:** 1,000 lines (BLOCK)
**Severity:** 🔴 CRITICAL (2.6x over limit)

**Responsibilities detected:**
- Waveform data extraction from PCM sources
- Peak analysis and caching
- Waveform rendering
- UI integration

**Proposed extraction:**

| New Module | Location | Est. Lines | Responsibility |
|------------|----------|------------|----------------|
| Waveform_Core.lua | Audio/Waveform/Waveform_Core.lua | ~900 | Core waveform data extraction, PCM reading |
| Waveform_Analysis.lua | Audio/Waveform/Waveform_Analysis.lua | ~800 | Peak analysis, caching, processing |
| Waveform_Rendering.lua | Audio/Waveform/Waveform_Rendering.lua | ~900 | UI rendering and visualization |

**After refactoring:**
- Original file: REMOVED (split into 3 modules)
- New modules: 3 files averaging ~850 lines each
- New subdirectory: Audio/Waveform/

---

### 7. DM_Ambiance_UI_TriggerSection.lua - COMPLEX UI PANEL

**Location:** `Scripts/Modules/DM_Ambiance_UI_TriggerSection.lua`
**Type:** FILE_SIZE
**Current:** 2,093 lines
**Limit:** 1,000 lines (BLOCK)
**Severity:** 🔴 CRITICAL (2x over limit)

**Proposed extraction:**

| New Module | Location | Est. Lines | Responsibility |
|------------|----------|------------|----------------|
| UI_TriggerSection_Main.lua | UI/Panels/UI_TriggerSection_Main.lua | ~800 | Main trigger panel logic |
| UI_TriggerSection_Controls.lua | UI/Panels/UI_TriggerSection_Controls.lua | ~650 | Individual control widgets |
| UI_TriggerSection_Events.lua | UI/Panels/UI_TriggerSection_Events.lua | ~600 | Event handling |

---

### 8. DM_Ambiance_UI_Container.lua - CONTAINER PANEL

**Location:** `Scripts/Modules/DM_Ambiance_UI_Container.lua`
**Type:** FILE_SIZE
**Current:** 1,967 lines
**Limit:** 1,000 lines (BLOCK)
**Severity:** 🔴 CRITICAL (2x over limit)

**Proposed extraction:**

| New Module | Location | Est. Lines | Responsibility |
|------------|----------|------------|----------------|
| UI_Container_Main.lua | UI/Panels/UI_Container_Main.lua | ~900 | Main container panel |
| UI_Container_Controls.lua | UI/Panels/UI_Container_Controls.lua | ~1,000 | Container controls and widgets |

---

### 9. DM_Ambiance_UI_Groups.lua - GROUPS PANEL

**Location:** `Scripts/Modules/DM_Ambiance_UI_Groups.lua`
**Type:** FILE_SIZE
**Current:** 1,367 lines
**Limit:** 1,000 lines (BLOCK)
**Severity:** 🔴 CRITICAL (1.4x over limit)

**Proposed extraction:**

| New Module | Location | Est. Lines | Responsibility |
|------------|----------|------------|----------------|
| UI_Groups_Main.lua | UI/Panels/UI_Groups_Main.lua | ~700 | Main groups panel |
| UI_Groups_Controls.lua | UI/Panels/UI_Groups_Controls.lua | ~650 | Group controls and list |

---

### Additional Function-Level Violations

**File: DM_Ambiance_Generation.lua**

| Function | Lines | Range | Action |
|----------|-------|-------|--------|
| placeItemsNoiseMode | 320 | 4436-4755 | Decompose into smaller functions |
| createMultiChannelTracks | 251 | 134-384 | Extract track creation helpers |
| generateGroups | 216 | 1432-1647 | Decompose generation loop |
| generateSingleGroupByPath | 211 | 1819-2029 | Extract validation and generation steps |
| placeItemsEuclideanMode | 205 | 4756-4960 | Decompose Euclidean logic |
| determineTrackStructure | 193 | 4243-4435 | Extract track structure calculation |
| generateSingleContainerByPath | 188 | 2217-2404 | Extract validation and generation steps |
| generateSingleContainer | 187 | 2030-2216 | Decompose container generation |
| generateSingleGroup | 171 | 1648-1818 | Decompose group generation |
| recalculateChannelRequirements | 128 | 2729-2856 | Extract channel calculation helpers |

---

## Alert-Level Issues (SHOULD FIX)

### Files in ALERT Range (500-1000 lines)

| File | Lines | Status | Recommendation |
|------|-------|--------|----------------|
| DM_Ambiance_UI_MultiSelection.lua | 975 | Near limit | Review for potential extraction |
| DM_Ambiance_Presets.lua | 916 | Near limit | Consider splitting preset load/save |
| DM_Ambiance_Icons.lua | 843 | Acceptable | Icon data - OK as-is (mostly data) |
| DM_Ambiance_UI_EuclideanSection.lua | 784 | Near limit | Consider splitting if grows |
| DM_Ambiance_Structures.lua | 778 | Near limit | Review data structures |
| DM_AmbianceCreator_Settings.lua | 680 | Acceptable | Settings logic - OK |
| DM_Ambiance_UI_Core.lua | 546 | Acceptable | Core UI - OK |
| DM_Ambiance_UI_LinkedSliders.lua | 521 | Acceptable | Widget component - OK |

**Recommendation:** Monitor these files and split if they exceed 800 lines or add significant new logic.

---

## Proposed Module Structure

After refactoring, the Scripts/Modules/ directory should look like:

```
Scripts/
├── DM_Ambiance Creator.lua              [281 lines] ✅ Already good - Main entry point
│
└── Modules/
    │
    ├── Core/                             [Core functionality]
    │   ├── DM_Ambiance_Constants.lua    [481 lines] ✅ Keep as-is
    │   ├── DM_Ambiance_ErrorHandler.lua [Existing] ✅
    │   └── DM_Ambiance_History.lua      [Existing] ✅
    │
    ├── Audio/                            [Audio processing & generation]
    │   ├── Generation_Core.lua           [~400 lines] NEW - Main coordinator
    │   ├── Generation_ItemPlacement.lua  [~600 lines] NEW - Item placement logic
    │   ├── Generation_Modes.lua          [~800 lines] NEW - Interval modes
    │   ├── Generation_MultiChannel.lua   [~900 lines] NEW - Channel routing
    │   ├── Generation_TrackManagement.lua[~500 lines] NEW - Track operations
    │   ├── Generation_Validation.lua     [~700 lines] NEW - Validation logic
    │   ├── Generation_Helpers.lua        [~300 lines] NEW - Shared helpers
    │   ├── DM_Ambiance_Items.lua         [Existing] ✅
    │   └── Waveform/
    │       ├── Waveform_Core.lua         [~900 lines] NEW - Data extraction
    │       ├── Waveform_Analysis.lua     [~800 lines] NEW - Peak analysis
    │       └── Waveform_Rendering.lua    [~900 lines] NEW - UI rendering
    │
    ├── Routing/                          [Channel routing & validation]
    │   ├── RoutingValidator_Core.lua     [~1,000 lines] NEW - Core validation
    │   ├── RoutingValidator_Conflicts.lua[~900 lines] NEW - Conflict detection
    │   └── RoutingValidator_Fixes.lua    [~1,000 lines] NEW - Auto-correction
    │
    ├── State/                            [Preset management & serialization]
    │   ├── DM_Ambiance_Presets.lua       [916 lines] ✅ Keep (monitor)
    │   ├── DM_Ambiance_Structures.lua    [778 lines] ✅ Keep (monitor)
    │   └── DM_AmbianceCreator_Settings.lua[680 lines] ✅ Keep
    │
    ├── Utils/                            [Shared utilities]
    │   ├── Utils_Core.lua                [~800 lines] NEW - Essential utilities
    │   ├── Utils_Math.lua                [~600 lines] NEW - Math helpers
    │   ├── Utils_REAPER.lua              [~1,200 lines] NEW - REAPER API wrappers
    │   ├── Utils_UI.lua                  [~500 lines] NEW - UI helpers
    │   ├── Utils_Validation.lua          [~400 lines] NEW - Validation functions
    │   ├── Utils_String.lua              [~300 lines] NEW - String utilities
    │   └── DM_Ambiance_UndoWrappers.lua  [Existing] ✅
    │
    └── UI/                               [User interface]
        ├── Core/
        │   ├── UI_Core.lua               [546 lines] ✅ Keep
        │   ├── UI_Layout.lua             [~800 lines] NEW - Layout management
        │   ├── UI_EventHandlers.lua      [~600 lines] NEW - Event handling
        │   ├── UI_Rendering.lua          [~900 lines] NEW - Rendering
        │   ├── UI_State.lua              [~700 lines] NEW - State management
        │   ├── UI_Helpers.lua            [~500 lines] NEW - UI utilities
        │   ├── DM_Ambiance_UI_MainWindow.lua [483 lines] ✅ Keep
        │   ├── DM_Ambiance_Icons.lua     [843 lines] ✅ Keep (data file)
        │   └── DM_Ambiance_UI.lua        [→ Split into above]
        │
        ├── Components/                    [Reusable widgets]
        │   ├── DM_Ambiance_UI_LinkedSliders.lua [521 lines] ✅ Keep
        │   ├── DM_Ambiance_UI_SliderEnhanced.lua [Existing] ✅
        │   ├── DM_Ambiance_UI_Knob.lua   [Existing] ✅
        │   ├── DM_Ambiance_UI_FadeWidget.lua [Existing] ✅
        │   └── DM_Ambiance_UI_NoisePreview.lua [Existing] ✅
        │
        └── Panels/                        [Specific views]
            ├── DM_Ambiance_UI_LeftPanel.lua [Existing] ✅
            ├── DM_Ambiance_UI_RightPanel.lua [Existing] ✅
            ├── UI_Groups_Main.lua        [~700 lines] NEW - Groups panel
            ├── UI_Groups_Controls.lua    [~650 lines] NEW - Group controls
            ├── DM_Ambiance_UI_Group.lua  [Existing] ✅
            ├── UI_Container_Main.lua     [~900 lines] NEW - Container panel
            ├── UI_Container_Controls.lua [~1,000 lines] NEW - Container controls
            ├── UI_TriggerSection_Main.lua[~800 lines] NEW - Trigger panel
            ├── UI_TriggerSection_Controls.lua [~650 lines] NEW - Controls
            ├── UI_TriggerSection_Events.lua [~600 lines] NEW - Events
            ├── DM_Ambiance_UI_FadeSection.lua [Existing] ✅
            ├── DM_Ambiance_UI_EuclideanSection.lua [784 lines] ✅ Keep (monitor)
            ├── DM_Ambiance_UI_Preset.lua [Existing] ✅
            ├── DM_Ambiance_UI_VolumeControls.lua [Existing] ✅
            ├── DM_Ambiance_UI_UndoHistory.lua [Existing] ✅
            └── DM_Ambiance_UI_MultiSelection.lua [975 lines] ✅ Keep (monitor)
```

**Summary:**
- **Remove:** 8 monolithic files (replaced by smaller modules)
- **Add:** 28 new focused modules
- **Keep:** 30 existing compliant files
- **Create:** 5 new subdirectories (Core/, Audio/, Routing/, State/, Utils/)

---

## Extraction Order (Recommended)

Process modules in this order to minimize dependency issues:

### Phase 1: Foundation & Utilities (No dependencies)

| Order | Module | Dependencies | Est. Effort | Priority |
|-------|--------|--------------|-------------|----------|
| 1 | Utils_String.lua | None | 30 min | 🔴 HIGH |
| 2 | Utils_Math.lua | None | 30 min | 🔴 HIGH |
| 3 | Utils_Validation.lua | Utils_String | 30 min | 🔴 HIGH |
| 4 | Utils_Core.lua | Utils_String | 45 min | 🔴 HIGH |
| 5 | Utils_UI.lua | Utils_Core | 45 min | 🟡 MEDIUM |
| 6 | Utils_REAPER.lua | Utils_Core, Utils_Math | 90 min | 🔴 HIGH |

**Subtotal Phase 1:** ~4.5 hours

### Phase 2: Audio Foundation (Depends on Utils)

| Order | Module | Dependencies | Est. Effort | Priority |
|-------|--------|--------------|-------------|----------|
| 7 | Generation_Helpers.lua | Utils_* | 30 min | 🔴 HIGH |
| 8 | Generation_TrackManagement.lua | Utils_REAPER, Generation_Helpers | 60 min | 🔴 HIGH |
| 9 | Waveform_Core.lua | Utils_REAPER | 90 min | 🟡 MEDIUM |
| 10 | Waveform_Analysis.lua | Waveform_Core | 60 min | 🟡 MEDIUM |
| 11 | Waveform_Rendering.lua | Waveform_Core, Waveform_Analysis | 60 min | 🟡 MEDIUM |

**Subtotal Phase 2:** ~5 hours

### Phase 3: Generation Core (Depends on Audio Foundation)

| Order | Module | Dependencies | Est. Effort | Priority |
|-------|--------|--------------|-------------|----------|
| 12 | Generation_MultiChannel.lua | Generation_TrackManagement, Utils_* | 120 min | 🔴 HIGH |
| 13 | Generation_ItemPlacement.lua | Generation_Helpers, Utils_* | 90 min | 🔴 CRITICAL |
| 14 | Generation_Modes.lua | Generation_ItemPlacement | 120 min | 🔴 CRITICAL |
| 15 | Generation_Validation.lua | Generation_MultiChannel, RoutingValidator_* | 90 min | 🔴 HIGH |
| 16 | Generation_Core.lua | All Generation_* modules | 60 min | 🔴 CRITICAL |

**Subtotal Phase 3:** ~8 hours

### Phase 4: Routing Validation (Parallel with Phase 3)

| Order | Module | Dependencies | Est. Effort | Priority |
|-------|--------|--------------|-------------|----------|
| 17 | RoutingValidator_Core.lua | Utils_* | 120 min | 🔴 HIGH |
| 18 | RoutingValidator_Conflicts.lua | RoutingValidator_Core | 90 min | 🔴 HIGH |
| 19 | RoutingValidator_Fixes.lua | RoutingValidator_Core, RoutingValidator_Conflicts | 120 min | 🔴 HIGH |

**Subtotal Phase 4:** ~5.5 hours

### Phase 5: UI Refactoring (Depends on all logic modules)

| Order | Module | Dependencies | Est. Effort | Priority |
|-------|--------|--------------|-------------|----------|
| 20 | UI_State.lua | Utils_UI, Generation_Core | 90 min | 🟡 MEDIUM |
| 21 | UI_Helpers.lua | Utils_UI | 60 min | 🟡 MEDIUM |
| 22 | UI_EventHandlers.lua | UI_State, UI_Helpers | 90 min | 🟡 MEDIUM |
| 23 | UI_Layout.lua | UI_Helpers | 90 min | 🟡 MEDIUM |
| 24 | UI_Rendering.lua | UI_Layout, UI_State | 120 min | 🟡 MEDIUM |

**Subtotal Phase 5:** ~7.5 hours

### Phase 6: Complex UI Panels (Depends on UI Core)

| Order | Module | Dependencies | Est. Effort | Priority |
|-------|--------|--------------|-------------|----------|
| 25 | UI_TriggerSection_Events.lua | UI_EventHandlers | 60 min | 🟢 LOW |
| 26 | UI_TriggerSection_Controls.lua | UI_Helpers | 60 min | 🟢 LOW |
| 27 | UI_TriggerSection_Main.lua | UI_TriggerSection_* | 90 min | 🟢 LOW |
| 28 | UI_Container_Controls.lua | UI_Helpers | 90 min | 🟢 LOW |
| 29 | UI_Container_Main.lua | UI_Container_Controls | 90 min | 🟢 LOW |
| 30 | UI_Groups_Controls.lua | UI_Helpers | 60 min | 🟢 LOW |
| 31 | UI_Groups_Main.lua | UI_Groups_Controls | 60 min | 🟢 LOW |

**Subtotal Phase 6:** ~8.5 hours

---

**Total estimated effort:** ~39 hours (can be spread across multiple sessions)

**Critical path:** Phase 1 → Phase 2 → Phase 3 (Phases 4-6 can be parallelized)

---

## Function Decomposition Plan

### Priority: Generation.placeItemsForContainer (548 lines)

**Location:** DM_Ambiance_Generation.lua:706-1253

**Decomposition strategy:**

```lua
-- NEW: Generation_ItemPlacement.lua structure

-- Helper 1: Calculate interval based on mode (~60 lines)
local function calculateInterval(container, triggerData, itemIdx, lastSuccessfulPos)
    -- Extract interval calculation logic for:
    -- INTERVAL_EXACT, INTERVAL_RANDOM_RANGE,
    -- INTERVAL_CHUNK, INTERVAL_COVERAGE
    return intervalSeconds
end

-- Helper 2: Calculate item position (~80 lines)
local function calculateItemPosition(container, triggerData, currentPos,
                                     intervalSeconds, itemIdx)
    -- Extract position calculation with:
    -- - Drift application
    -- - Variation application
    -- - Grid quantization
    -- - Bounds checking
    return positionSeconds, adjustedInterval
end

-- Helper 3: Select channel for item (~70 lines)
local function selectChannelForItem(container, triggerData, itemIdx,
                                   availableChannels, lastChannel)
    -- Extract channel selection logic:
    -- - CHANNEL_MODE_DIRECT
    -- - CHANNEL_MODE_RANDOM
    -- - CHANNEL_MODE_SEQUENTIAL
    -- - CHANNEL_MODE_ALGORITHM
    return selectedChannel
end

-- Helper 4: Create REAPER item (~50 lines)
local function createItemOnTrack(track, mediaSource, position, length,
                                containerColor)
    -- REAPER item creation and basic setup
    return item
end

-- Helper 5: Apply randomization parameters (~60 lines)
local function applyItemRandomization(item, triggerData)
    -- Apply all randomization:
    -- - Pitch
    -- - Volume
    -- - Rate
    -- - Pan
    -- - Offset
end

-- Helper 6: Apply fades to item (~40 lines)
local function applyItemFades(item, triggerData, itemIdx, totalItems)
    -- Apply fade-in and fade-out with randomization
end

-- Helper 7: Handle collision detection (~50 lines)
local function handleItemCollision(item, track, collisionMode)
    -- Collision detection and resolution
    return adjustedItem
end

-- Helper 8: Create crossfade between items (~40 lines)
local function createCrossfade(prevItem, currentItem, crossfadeSettings)
    -- Crossfade creation logic
end

-- Main function: Coordinator only (~80 lines)
function Generation.placeItemsForContainer(container, tracks, triggerData)
    -- Initialization
    local itemCount = triggerData.item_count or 1
    local lastPos = triggerData.start_time or 0
    local lastChannel = nil
    local prevItem = nil

    -- Main loop (simplified)
    for i = 1, itemCount do
        -- Calculate interval
        local interval = calculateInterval(container, triggerData, i, lastPos)

        -- Calculate position
        local position, adjustedInterval = calculateItemPosition(
            container, triggerData, lastPos, interval, i
        )

        -- Select channel
        local channel = selectChannelForItem(
            container, triggerData, i, tracks, lastChannel
        )

        -- Create item
        local item = createItemOnTrack(
            tracks[channel], container.source, position,
            triggerData.length, container.color
        )

        -- Apply randomization
        applyItemRandomization(item, triggerData)

        -- Apply fades
        applyItemFades(item, triggerData, i, itemCount)

        -- Handle collisions
        handleItemCollision(item, tracks[channel], triggerData.collision_mode)

        -- Create crossfade if needed
        if prevItem and triggerData.crossfade_enabled then
            createCrossfade(prevItem, item, triggerData.crossfade_settings)
        end

        -- Update state
        lastPos = position + adjustedInterval
        lastChannel = channel
        prevItem = item
    end
end
```

**Benefits:**
- Main function reduced from 548 lines to ~80 lines
- Each helper function has single, clear responsibility
- Functions can be unit tested independently
- Code reuse potential (helpers used by other generation modes)
- Much easier to understand and maintain

---

## Module Initialization Pattern

All new modules should follow this Lua module pattern:

```lua
-- Example: Generation_Helpers.lua

local Generation_Helpers = {}

-- Dependencies
local Utils = require("DM_Ambiance_Utils_Core")
local Constants = require("DM_Ambiance_Constants")

-- Module functions
function Generation_Helpers.someFunction()
    -- Implementation
end

function Generation_Helpers.anotherFunction()
    -- Implementation
end

-- Module initialization (if needed)
function Generation_Helpers.init(globals)
    -- Store reference to globals
    Generation_Helpers.globals = globals
end

return Generation_Helpers
```

**Main script update pattern:**

```lua
-- In DM_Ambiance Creator.lua
local Generation_Core = require("Modules.Audio.Generation_Core")
local Generation_ItemPlacement = require("Modules.Audio.Generation_ItemPlacement")
-- ... etc

-- Initialize modules
Generation_Core.init(globals)
Generation_ItemPlacement.init(globals)
```

---

## Testing Strategy

After each module extraction:

### 1. Syntax Check
```lua
-- Run script in REAPER to check for Lua syntax errors
-- Should load without errors
```

### 2. Functional Testing
- Test basic ambiance generation
- Test each trigger mode (exact, random, chunk, coverage, noise, euclidean)
- Test multi-channel routing
- Test preset load/save
- Test undo/redo

### 3. Regression Testing
- Compare generated project structure with pre-refactor version
- Verify item placement matches previous behavior
- Check that all UI panels render correctly
- Ensure no performance degradation

### 4. Integration Testing
- Test cross-module communication
- Verify all module dependencies load correctly
- Check globals table access patterns

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Lua require() path issues** | High | Use consistent relative paths, test module loading early |
| **Globals table access patterns** | Medium | Document all globals access, consider passing as parameters |
| **Circular dependencies** | High | Use dependency diagram, extract in proper order |
| **REAPER API behavior changes** | Low | Existing code already works, just moving it |
| **Function call overhead** | Low | Lua function calls are fast, negligible impact |
| **Lost functionality** | High | Comprehensive testing after each phase |
| **Merge conflicts** | Medium | Work in dedicated branch, commit frequently |
| **Time estimation** | Medium | Budget 20-40 hours, work in phases over multiple days |

---

## Success Criteria

Refactoring is complete when:

- ✅ All files < 1,000 lines (ideally < 500)
- ✅ All functions < 100 lines (ideally < 80)
- ✅ Each module has ONE clear responsibility (passes SRP test)
- ✅ Script loads without errors in REAPER
- ✅ All functionality works identically to before
- ✅ No performance regression
- ✅ Code is easier to navigate and understand
- ✅ Directory structure matches target organization

---

## Version Control Strategy

### Branch Strategy
```bash
# Create refactoring branch
git checkout -b refactor/modularity-cleanup

# Work in sub-branches per phase
git checkout -b refactor/phase-1-utils
git checkout -b refactor/phase-2-audio
# etc.

# Merge to main after full testing
```

### Commit Strategy
```bash
# Commit after each module extraction
git add Scripts/Modules/Utils/Utils_Core.lua
git commit -m "refactor: Extract Utils_Core from Utils (800 lines → compliant)"

# Commit when removing old file
git rm Scripts/Modules/DM_Ambiance_Utils.lua
git commit -m "refactor: Remove monolithic Utils file (split into 6 modules)"

# Tag major milestones
git tag refactor-phase-1-complete
git tag refactor-phase-2-complete
```

---

## Next Steps

### Immediate Actions (Today):

1. ✅ Review this plan
2. Create refactoring branch: `git checkout -b refactor/modularity-cleanup`
3. Create subdirectories:
   ```bash
   mkdir -p Scripts/Modules/Core
   mkdir -p Scripts/Modules/Audio/Waveform
   mkdir -p Scripts/Modules/Routing
   mkdir -p Scripts/Modules/State
   mkdir -p Scripts/Modules/Utils
   mkdir -p Scripts/Modules/UI/Core
   mkdir -p Scripts/Modules/UI/Components
   mkdir -p Scripts/Modules/UI/Panels
   ```
4. Begin Phase 1 (Utils extraction)

### This Week:
- Complete Phase 1 (Utils) - ~4.5 hours
- Complete Phase 2 (Audio Foundation) - ~5 hours
- Start Phase 3 (Generation Core) - ~8 hours

### Next Week:
- Complete Phase 3 (Generation Core)
- Complete Phase 4 (Routing Validation) - ~5.5 hours
- Begin Phase 5 (UI Refactoring) - ~7.5 hours

### Following Weeks:
- Complete Phase 5 (UI Refactoring)
- Complete Phase 6 (Complex UI Panels) - ~8.5 hours
- Full regression testing
- Documentation updates
- Merge to main

---

## Monitoring Progress

Create `REFACTORING_PROGRESS.md` to track completion:

```markdown
# Refactoring Progress: DM Ambiance Creator

**Started:** 2025-12-02
**Status:** IN_PROGRESS
**Current Phase:** Phase 1 - Foundation & Utilities

## Phases

- [ ] Phase 1: Foundation & Utilities (0/6 modules)
- [ ] Phase 2: Audio Foundation (0/5 modules)
- [ ] Phase 3: Generation Core (0/5 modules)
- [ ] Phase 4: Routing Validation (0/3 modules)
- [ ] Phase 5: UI Refactoring (0/5 modules)
- [ ] Phase 6: Complex UI Panels (0/7 modules)

**Total Progress:** 0/31 modules (0%)
```

---

## Notes

### Why This Matters

This refactoring is critical because:

1. **Maintainability:** 548-line functions and 5,000-line files are impossible to maintain
2. **Debugging:** Isolated modules make bug tracking much easier
3. **Testing:** Smaller functions can be tested independently
4. **Collaboration:** Clear module boundaries enable parallel development
5. **Code Reuse:** Extracted helpers can be reused across the codebase
6. **Onboarding:** New developers can understand isolated modules more easily
7. **Performance:** No negative impact (Lua function calls are fast)
8. **Future Growth:** Modular structure scales better as features are added

### Important Considerations

- **Backward Compatibility:** Old presets and saved projects will still work
- **File Organization:** Lua's require() system makes module loading straightforward
- **No Feature Changes:** This is PURE refactoring - behavior stays identical
- **Incremental Approach:** Can pause after any phase, script remains functional
- **Rollback Safety:** Git branches allow easy rollback if needed

### Questions for Review

Before starting, consider:

1. Should we target 500-line limit (ALERT) or 1000-line limit (BLOCK)?
   - **Recommendation:** Target 500, accept up to 800 temporarily
2. Should we create REFACTORING_PROGRESS.md now or after Phase 1?
   - **Recommendation:** Create now for tracking
3. Should we refactor functions simultaneously with file splits?
   - **Recommendation:** Yes, decompose functions during module extraction
4. Should we write unit tests alongside refactoring?
   - **Recommendation:** Yes, at least for complex generation logic

---

**Ready to begin refactoring?**

Run the following to start:
```bash
git checkout -b refactor/modularity-cleanup
mkdir -p Scripts/Modules/{Core,Audio/Waveform,Routing,State,Utils,UI/{Core,Components,Panels}}
```

Then proceed with Phase 1, Module 1: `Utils_String.lua` extraction.
