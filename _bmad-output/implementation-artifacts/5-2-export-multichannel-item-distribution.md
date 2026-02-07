# Story 5.2: Multichannel Export Mode Selection

Status: review

## Story

As a **game sound designer**,
I want **to choose between exporting all items sequentially on a single track (Flatten) or preserving the multichannel distribution behavior (Preserve)**,
So that **I can either prepare individual items for Wwise/FMOD import or create multichannel loops that match my configured ambiance**.

## Context

Multichannel containers use distribution modes (round-robin, random, all tracks) to spread items across channel tracks during Generation. During export, the user needs two distinct behaviors:

- **Flatten**: Export all pool items sequentially on one track (ch 1-2) for middleware that handles spatialization. This is the most common use case for game audio pipelines.
- **Preserve**: Reproduce the Generation engine's distribution logic across child tracks for direct use or looping.

**Replaces previous Story 5.2** which only addressed the "same item on all tracks" bug. The new scope introduces explicit mode selection that covers both the original bug and the new flatten use case.

### Current Behavior (Bug)

```
Export 4.0 quad container (stereo items):
- Track L-R:   Item A at 0s, Item B at 1s, Item C at 2s
- Track Ls-Rs: Item A at 0s, Item B at 1s, Item C at 2s  <-- SAME ITEMS!
```

The bug stems from `placeContainerItems()` building `itemData` ONCE per placement cycle and placing the SAME item on ALL target tracks.

### Expected Behavior: Flatten Mode

```
Export 4.0 quad container (Flatten):
- Track L-R:   Item A at 0s, Item B at 1s, Item C at 2s, Item D at 3s
- Track Ls-Rs: (empty)
```

All pool items placed sequentially on the first child track only.

### Expected Behavior: Preserve Mode

```
Export 4.0 quad container (Preserve, Round-Robin):
- Track L-R:   Item A at 0s, Item C at 1s, Item E at 2s
- Track Ls-Rs: Item B at 0s, Item D at 1s, Item F at 2s
```

Items distributed across tracks following the container's `itemDistributionMode`.

## Acceptance Criteria

### Mode A: Flatten

1. **AC1** — **Given** a multichannel container (e.g., 4.0 quad from stereo items) with export mode set to "Flatten"
   **When** the container is exported
   **Then** ALL pool items (respecting `maxPoolItems`) are placed sequentially on the first child track (ch 1-2)
   **And** the distribution mode (round-robin/random/all tracks) is ignored
   **And** other child tracks in the hierarchy remain empty

2. **AC2** — **Given** a container with native multichannel source files (4.0/5.0/7.0)
   **When** exported in Flatten mode
   **Then** items are placed as-is on the track without channel extraction

3. **AC3** — **Given** exportMethod = 0 (Current Track) and tracks already exist from a previous generation
   **When** exported in Flatten mode
   **Then** the existing track hierarchy is reused
   **And** items are placed on the first child track only

4. **AC4** — **Given** exportMethod = 1 (New Track) and no tracks exist
   **When** exported in Flatten mode
   **Then** the full track hierarchy is created (identical to what Generation would create)
   **And** items are placed on the first child track only

### Mode B: Preserve

5. **AC5** — **Given** `itemDistributionMode = 0` (Round-Robin) and export mode "Preserve"
   **When** the container is exported
   **Then** pool entries are distributed across child tracks in round-robin order
   **And** each track receives different items (matching Generation engine behavior)

6. **AC6** — **Given** `itemDistributionMode = 1` (Random) in Preserve mode
   **When** exported
   **Then** each pool entry is placed on a randomly selected child track

7. **AC7** — **Given** `itemDistributionMode = 2` (All Tracks) in Preserve mode
   **When** exported
   **Then** each child track receives its own independent sequence from the pool

8. **AC8** — **Given** Preserve mode with loop enabled and All Tracks distribution
   **When** the loop is processed
   **Then** each track has the same `targetDuration`
   **And** split/swap is applied ONLY on tracks where the last item reaches or exceeds `targetDuration`
   **And** tracks where the last item finishes before `targetDuration` are left untouched

### UI

9. **AC9** — **Given** the Export modal with a multichannel container selected (`channelMode != DEFAULT`)
   **Then** a "Multichannel Export Mode" selector is visible with options Flatten / Preserve
   **And** default is Flatten

10. **AC10** — **Given** a stereo container (`channelMode == DEFAULT`, single track)
    **Then** the multichannel export mode selector is hidden (not applicable)

## Tasks / Subtasks

- [x] Task 1: Add Constants and Settings support (AC: #9, #10)
  - [x] 1.1: Add `MULTICHANNEL_EXPORT_MODE_FLATTEN`, `MULTICHANNEL_EXPORT_MODE_PRESERVE`, `MULTICHANNEL_EXPORT_MODE_DEFAULT` to `Constants.EXPORT`
  - [x] 1.2: Add `multichannelExportMode` to `globalParams` in Export_Settings.lua with default "flatten"
  - [x] 1.3: Add validation in `setGlobalParam()` for "flatten"/"preserve" values
  - [x] 1.4: Ensure `getEffectiveParams()` includes the new parameter (automatic via existing override copy pattern)

- [x] Task 2: Implement Flatten mode in placeContainerItems() (AC: #1, #2, #3, #4)
  - [x] 2.1: At the start of `placeContainerItems()`, check effective `multichannelExportMode`
  - [x] 2.2: When "flatten": restrict `targetTracks` to first child track only (`targetTracks = {targetTracks[1]}`)
  - [x] 2.3: When "flatten": set `trackStructure.channelSelectionMode = "none"` to skip channel extraction
  - [x] 2.4: Verify that track hierarchy is still created fully for both export methods (needed for Preserve mode compatibility)

- [x] Task 3: Implement Preserve mode distribution in placeContainerItems() (AC: #5, #6, #7)
  - [x] 3.1: When "preserve" AND `trackStructure.useDistribution == true`: implement per-item track assignment
  - [x] 3.2: Round-Robin (mode 0): Add distribution counter, cycle through tracks using `((counter - 1) % #targetTracks) + 1`
  - [x] 3.3: Random (mode 1): Select track via `math.random(1, #targetTracks)` per pool entry
  - [x] 3.4: All Tracks (mode 2): Restructure to iterate tracks OUTER, pool INNER — each track gets its own independent sequence from the full pool
  - [x] 3.5: When `trackStructure.useSmartRouting == true` (native multichannel sources): keep existing behavior (same item on all tracks with channel extraction)

- [x] Task 4: Handle Preserve + Loop + All Tracks (AC: #8)
  - [x] 4.1: In All Tracks mode, each track independently fills to `targetDuration`
  - [x] 4.2: After placement, `processLoop()` split/swap only applies to tracks where the last item reaches/exceeds `targetDuration`
  - [x] 4.3: Tracks where items finish before `targetDuration` are left untouched (no split/swap)

- [x] Task 5: Add UI controls (AC: #9, #10)
  - [x] 5.1: Add "Multichannel Export Mode" Combo widget in Export_UI.lua global parameters section
  - [x] 5.2: Only show when at least one enabled container has `channelMode != DEFAULT` (0)
  - [x] 5.3: Add same control in `renderOverrideParams()` for per-container override (visible only when selected container is multichannel)
  - [x] 5.4: Add same control in `renderBatchOverrideParams()` for batch editing

## Dev Notes

### Critical Architecture Knowledge

**Export module hierarchy** ([Source: export-v2-architecture.md#2](../../_bmad-output/planning-artifacts/export-v2-architecture.md)):
```
Export/
├── init.lua                    -- Module aggregator
├── Export_Settings.lua          -- State + validation (ADD new param here)
├── Export_Engine.lua             -- Orchestrator (minimal changes)
├── Export_Placement.lua          -- Core placement logic (MAIN CHANGES HERE)
├── Export_Loop.lua               -- Loop processing (check AC8 compatibility)
└── Export_UI.lua                 -- Modal window (ADD mode selector here)
```

### Root Cause Analysis

**Current bug location**: [Export_Placement.lua:496-523](Scripts/Modules/Export/Export_Placement.lua#L496-L523)

```lua
-- CURRENT CODE (buggy): Same item placed on ALL tracks
for tIdx, track in ipairs(targetTracks) do
    local realTrackIdx = trackStructure.trackIndices
        and trackStructure.trackIndices[tIdx] or tIdx
    local newItem, length = globals.Generation.placeSingleItem(
        track,
        itemData,  -- <-- BUG: Same itemData for ALL tracks!
        itemPos, genParams, trackStructure, realTrackIdx,
        trackStructure.channelSelectionMode, true
    )
end
```

The `itemData` is built ONCE from the current pool entry (line 491), then used for all tracks. This causes identical items on every channel track.

### Fix Strategy: Flatten Mode

The simplest fix — restrict to first track only:

```lua
-- At the start of placeContainerItems(), before the main loop:
local flattenMode = params.multichannelExportMode == "flatten"
local effectiveTargetTracks = targetTracks
if flattenMode and #targetTracks > 1 then
    effectiveTargetTracks = {targetTracks[1]}
    -- Override channel selection: place full items, no extraction
end
```

- The rest of the function works unchanged — items are sequentially placed on the single track
- Track hierarchy is still created (Story 5.1 already handles this) for routing consistency
- `channelSelectionMode` should be set to "none" for flatten to avoid extracting channels from stereo items

### Fix Strategy: Preserve Mode

Replicate Generation engine distribution logic from [Generation_ItemPlacement.lua:354-369](Scripts/Modules/Audio/Generation/Generation_ItemPlacement.lua#L354-L369):

**Round-Robin (mode 0):**
```lua
-- Add counter before main loop
local distributionCounter = 0

-- Inside the placement loop, for each pool entry:
distributionCounter = distributionCounter + 1
local targetChannel = ((distributionCounter - 1) % #targetTracks) + 1
-- Place on targetTracks[targetChannel] ONLY
```

**Random (mode 1):**
```lua
local targetChannel = math.random(1, #targetTracks)
-- Place on targetTracks[targetChannel] ONLY
```

**All Tracks (mode 2) — Major restructure needed:**
```lua
-- Iterate TRACKS outer, POOL inner
for tIdx, track in ipairs(targetTracks) do
    local trackPos = startPosition
    for _, poolEntry in ipairs(pool) do
        for inst = 1, params.instanceAmount do
            local itemData = M.buildItemData(poolEntry.item, poolEntry.area)
            local realTrackIdx = trackStructure.trackIndices[tIdx] or tIdx
            local newItem, length = globals.Generation.placeSingleItem(
                track, itemData, trackPos, genParams,
                trackStructure, realTrackIdx,
                trackStructure.channelSelectionMode, true
            )
            trackPos = trackPos + length + effectiveInterval
        end
    end
end
```

### Key trackStructure Flags

From [Generation_Modes.determineTrackStructure()](Scripts/Modules/Audio/Generation/Generation_Modes.lua#L30):

| Flag | Meaning | Impact on Export |
|------|---------|-----------------|
| `useDistribution` | Items should be distributed across tracks | Triggers Preserve distribution logic |
| `useSmartRouting` | Same item goes to all tracks (native multichannel) | Keep existing behavior: same item, channel extraction per track |
| `needsChannelSelection` | Items need channel extraction | Applied in Preserve mode, skipped in Flatten mode |
| `numTracks` | Number of child tracks | 1 = no distribution needed (stereo container) |
| `trackIndices` | Maps logical to real track indices | Critical for correct channel extraction in placeSingleItem() |
| `channelSelectionMode` | "none", "mono", "stereo" | Override to "none" in Flatten mode |

### Previous Story 5.1 Learnings (CRITICAL)

From [Story 5.1 completion notes](../../_bmad-output/implementation-artifacts/5-1-export-track-hierarchy-creation.md):

1. **Suppress Generation side effects** during export:
   ```lua
   local savedPreviousChannelMode = container.previousChannelMode
   globals.suppressViewRefresh = true
   -- ... call Generation functions ...
   globals.suppressViewRefresh = nil
   container.previousChannelMode = savedPreviousChannelMode
   ```

2. **Architecture decision**: Direct call to Generation module (approach #1) — this is the established pattern, continue using it.

3. **Track hierarchy creation**: `createExportTrackHierarchy()` at [Export_Placement.lua:83-138](Scripts/Modules/Export/Export_Placement.lua#L83-L138) handles track creation. Always creates full hierarchy — Flatten mode should still create it but only USE the first child track.

4. **Code review issues fixed**: suppressViewRefresh guard, previousChannelMode save/restore, removed dead code. These patterns are now established and should be maintained.

### Git Intelligence (Recent Commits)

```
cad4e48 fix: Story 5.1 code review - suppress Generation side effects during export
db82973 docs: Add Epic 5 Bug Fixes and Stories 5.2, 5.3
1b4cbd6 feat: Implement Story 5.1 Export Track Hierarchy Creation
e3e1d32 feat: Implement Story 4.4 Loop Interval Auto-Mode UI with code review fixes
cb8848e docs: Rework Story 4.4 with proper structure and formalize FR33
```

**Key patterns from recent commits:**
- Export_Placement.lua was the primary file modified in Story 5.1
- Export_Engine.lua had minor orchestration changes (reordering calls)
- Generation_TrackManagement.lua was guarded with `suppressViewRefresh`
- UI patterns for conditional display established in Story 4.4 (loop interval auto-mode indicator)

### Project Structure Notes

**Files to modify:**

| File | Change | Scope |
|------|--------|-------|
| [DM_Ambiance_Constants.lua](Scripts/Modules/DM_Ambiance_Constants.lua) | Add 3 new EXPORT constants | ~5 lines |
| [Export_Settings.lua](Scripts/Modules/Export/Export_Settings.lua) | Add param to globalParams + validation | ~15 lines |
| [Export_Placement.lua](Scripts/Modules/Export/Export_Placement.lua) | Major: Flatten/Preserve logic in `placeContainerItems()` | ~80-120 lines |
| [Export_UI.lua](Scripts/Modules/Export/Export_UI.lua) | Add Combo widget in 3 locations (global, override, batch) | ~40-60 lines |

**Files that should NOT be modified:**
- Export_Engine.lua — orchestration unchanged, processContainerExport() flow works as-is
- Export_Loop.lua — processLoop() already groups by trackIdx, works correctly for both modes
- Generation modules — no changes needed, they are called correctly already
- Structures.lua — no new data fields needed on container

### Alignment with Architecture

- **Module pattern**: All changes follow `initModule(globals)` pattern, globals-based communication
- **Constants usage**: No magic numbers — all new values go into `Constants.EXPORT`
- **Deferred operations**: No ImGui state changes during rendering — mode selector uses standard Combo pattern
- **Error handling**: Flatten/Preserve logic should not introduce new failure paths — both modes use existing placement primitives

### Testing Requirements

**Manual Testing in REAPER:**

1. **Flatten mode** — Export 4.0 quad container with stereo items:
   - Verify ALL items appear on first child track (L-R)
   - Verify other tracks are empty (Ls-Rs)
   - Verify full track hierarchy still exists (folder + children)

2. **Flatten mode with native multichannel** — Export 5.0 container with 5.0 source files:
   - Verify items placed as-is without channel extraction
   - Verify no errors from mismatched channel counts

3. **Preserve Round-Robin** — Export 4.0 quad container with 8 stereo items:
   - Verify items alternate: L-R gets items 1,3,5,7; Ls-Rs gets items 2,4,6,8
   - Compare visually with Generation engine output

4. **Preserve Random** — Export 4.0 quad with random distribution:
   - Verify items are distributed (not all on same track)
   - Run multiple times to confirm randomness

5. **Preserve All Tracks** — Export with All Tracks distribution:
   - Verify each child track gets its own complete sequence from pool
   - Each track should have the same number of items

6. **Preserve + Loop + All Tracks** (AC8):
   - Export 30s loop with All Tracks distribution
   - Verify split/swap only on tracks where items reach/exceed 30s
   - Short tracks left untouched

7. **UI visibility** — Open Export modal:
   - Select a multichannel container → mode selector visible
   - Select a stereo container → mode selector hidden
   - Switch between containers → visibility updates correctly

8. **Per-container override** — Set global to Flatten, override one container to Preserve:
   - Verify flattened containers have items on first track only
   - Verify preserved container has distributed items

9. **Regression: stereo containers unchanged** — Export stereo container:
   - Behavior should be identical to before (no mode selector, items on single track)

10. **Regression: Loop mode still works** — Export loop container:
    - Verify zero-crossing split/swap still works correctly
    - Verify no regression from new mode parameter

### References

- [Source: epics.md#Story-5.2](../../_bmad-output/planning-artifacts/epics.md) — Full acceptance criteria with Flatten/Preserve modes
- [Source: export-v2-architecture.md#4.3](../../_bmad-output/planning-artifacts/export-v2-architecture.md) — Export_Placement specification
- [Source: Export_Placement.lua#placeContainerItems](Scripts/Modules/Export/Export_Placement.lua#L444-L580) — Current placement function
- [Source: Generation_ItemPlacement.lua#distribution-logic](Scripts/Modules/Audio/Generation/Generation_ItemPlacement.lua#L354-L369) — Distribution counter pattern to replicate
- [Source: Generation_Modes.lua#determineTrackStructure](Scripts/Modules/Audio/Generation/Generation_Modes.lua#L30) — trackStructure flags
- [Source: Export_Settings.lua#globalParams](Scripts/Modules/Export/Export_Settings.lua#L16-L30) — Current parameter structure
- [Source: Export_UI.lua#renderOverrideParams](Scripts/Modules/Export/Export_UI.lua#L666-L885) — Override rendering pattern
- [Source: Story 5.1 completion](../../_bmad-output/implementation-artifacts/5-1-export-track-hierarchy-creation.md) — Previous story learnings

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (claude-opus-4-6)

### Debug Log References

N/A — REAPER script project, no automated tests.

### Completion Notes List

- **Task 1**: Added 3 constants to `Constants.EXPORT` (`MULTICHANNEL_EXPORT_MODE_FLATTEN`, `MULTICHANNEL_EXPORT_MODE_PRESERVE`, `MULTICHANNEL_EXPORT_MODE_DEFAULT`). Added `multichannelExportMode` to `Export_Settings.globalParams` with default "flatten". Added validation in `setGlobalParam()`. Parameter flows through existing `getEffectiveParams()` automatically.

- **Task 2 (Flatten)**: At start of `placeContainerItems()`, detects multichannel mode. When "flatten" and multiple target tracks: creates `effectiveTargetTracks` restricted to first child track only, shallow-copies `trackStructure` with `channelSelectionMode = "none"` to prevent channel extraction. Track hierarchy is still fully created (needed for routing).

- **Task 3 (Preserve Round-Robin/Random)**: Added `preserveDistribution` flag, `distributionCounter`, and `getDistributionTarget()` helper inside `placeContainerItems()`. For Round-Robin (mode 0): cycles through tracks using modulo counter. For Random (mode 1): picks random track per pool entry. Smart Routing containers keep existing behavior (same item on all tracks with channel extraction).

- **Task 4 (Preserve All Tracks)**: Implemented as `isAllTracksMode` branch with track-OUTER/pool-INNER loop structure. Each track independently iterates the full pool. In loop mode, each track fills to `targetDuration` independently. The existing `processLoop()` in Export_Loop.lua already handles per-track split/swap correctly (groups by `trackIdx`, skips tracks with < 2 items) — no changes needed there.

- **Task 5 (UI)**: Added Combo selector "Multichannel Mode" (Flatten/Preserve) in 3 locations: global params section (visible only when at least one enabled container is multichannel), single override section (visible only when selected container is multichannel), and batch override section (visible when any selected container is multichannel). Added `multichannelExportMode` to all 3 override templates. Used module-level lookup tables for consistent value mapping.

### Implementation Plan

**Approach**: Minimal modification to existing placement flow. Flatten mode restricts the target to a single track via `effectiveTargetTracks`. Preserve mode adds distribution logic (Round-Robin/Random) via `getDistributionTarget()` helper, and All Tracks via restructured outer loop. No changes needed to Export_Engine, Export_Loop, or Generation modules.

**Key Design Decisions**:
1. Shallow copy of `trackStructure` in Flatten mode to avoid mutating the original (which is used by Export_Engine for bounds calculations)
2. Distribution counter is local to `placeContainerItems()` (reset per container), matching Generation engine behavior
3. All Tracks mode uses the `currentPos` upvar from the closure to coordinate with `placePoolEntry`, then tracks maximum position across all tracks
4. UI visibility tied to `channelMode != 0` matching AC #10 exactly

### File List

| File | Action | Description |
|------|--------|-------------|
| Scripts/Modules/DM_Ambiance_Constants.lua | Modified | Added 3 MULTICHANNEL_EXPORT_MODE constants to EXPORT section |
| Scripts/Modules/Export/Export_Settings.lua | Modified | Added multichannelExportMode param to globalParams, resetSettings(), and setGlobalParam() validation |
| Scripts/Modules/Export/Export_Placement.lua | Modified | Major: Flatten/Preserve mode logic in placeContainerItems() with Round-Robin, Random, All Tracks distribution |
| Scripts/Modules/Export/Export_UI.lua | Modified | Added Multichannel Mode Combo in global, single override, and batch override sections |

### Change Log

- 2026-02-07: Story 5.2 implementation — Multichannel Export Mode Selection (Flatten/Preserve) with full distribution support
