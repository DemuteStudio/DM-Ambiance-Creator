# Story 5.6: Fix Multi-Channel Preserve Loop - Synchronize Track Timestamps

**Status**: ready-for-dev
**Epic**: Epic 5 (Bug Fixes - Post-Implementation)
**Priority**: Critical
**Dependencies**: Story 3.2 (Zero-Crossing Split/Swap logic)

---

## User Story

As a **game sound designer**,
I want **all tracks in multi-channel preserve loop mode to start and end at the same timestamps**,
So that **the exported region loops seamlessly across all channels without gaps or desync**.

---

## Context

### Problem Description

In **multi-channel preserve loop mode**, each track generates its loop items **independently**, resulting in different start/end timestamps across tracks. This breaks the exported region's loop because tracks don't align temporally.

**Example**:
- User requests 30s loop export in 5.0 surround (5 tracks)
- Track L (Left): fills `[00:01:36 → 00:01:40]` (4s coverage)
- Track R (Right): fills `[00:01:30 → 00:01:38]` (8s coverage)
- **Exported Region**: `[00:01:30 → 00:01:40]` (10s to cover both)
- **Problem**: Track L ends at 00:01:40, Track R ends at 00:01:38 → **No seamless loop** ❌

### Current Behavior (Buggy)

```
Track L:  [empty]  [====items====]  [gap]
Track R:  [====items====]  [empty]
Region:   [--------30 seconds-------]
          ^ start differs  ^ end differs
```

Individual tracks loop correctly, but the **region as a whole does NOT loop** because:
1. Start timestamps differ across tracks
2. End timestamps differ across tracks
3. The exported region covers the union of all tracks, creating gaps

### Expected Behavior

```
Track L:  [====items aligned====]
Track R:  [====items aligned====]
Region:   [--------30 seconds-------]
          ^ synchronized start/end
```

All tracks should:
1. **Start at the SAME timestamp** (earliest item position)
2. **End at the SAME timestamp** (start + requested duration)
3. **Fill the requested duration completely** on each track
4. **Loop seamlessly** when the region is repeated

---

## Root Cause Analysis

### File: `Export_Placement.lua`

**Function**: `placeItemsLoopMode()` (lines ~596-650)

The loop placement logic operates **per-track independently**:
1. Each track fills items until `targetDuration` is reached
2. Each track starts at `startPos` but places items based on **its own item lengths**
3. Different item lengths → different end positions → **desynchronized timestamps**

**Why it happens**:
- Loop mode uses `(currentPos - startPos) < targetDuration` as exit condition
- Each track's `currentPos` advances differently based on **item length + effectiveInterval**
- No mechanism to **synchronize final positions** across tracks in multi-channel preserve

---

## Proposed Solution (Manual Workflow)

### User's Manual Approach:
1. **Overfill**: Fill each track to 110% (or overfill based on `abs(triggerRate)`)
2. **Detect timestamps**: Find earliest start and latest end across all tracks
3. **Shift right**: Move all items slightly to the right to create space
4. **Split & swap**: Cut items exceeding `targetEnd`, move them to the beginning
5. **Adjust intervals**: Ensure interval between swapped items and following items is correct
6. **Zero-crossing**: Apply zero-crossing detection for clean splits (already implemented in Story 3.2)

### Algorithmic Approach:

```lua
-- Phase 1: Overfill each track
local overfillFactor = 1.0 + (math.abs(effectiveInterval) / targetDuration)
local overfillDuration = targetDuration * overfillFactor

for track in tracks do
    placeItemsLoopMode(track, startPos, overfillDuration)  -- Fill 110%
end

-- Phase 2: Detect actual bounds
local earliestStart = math.huge
local latestEnd = -math.huge
for track in tracks do
    local firstItem = getFirstItem(track)
    local lastItem = getLastItem(track)
    earliestStart = math.min(earliestStart, firstItem.position)
    latestEnd = math.max(latestEnd, lastItem.position + lastItem.length)
end

-- Phase 3: Define target bounds
local targetStart = earliestStart
local targetEnd = targetStart + targetDuration

-- Phase 4: Synchronize each track
for track in tracks do
    -- Shift items to align start
    local currentStart = getFirstItem(track).position
    local shiftAmount = targetStart - currentStart
    shiftAllItems(track, shiftAmount)

    -- Split items exceeding targetEnd
    local itemsToSplit = getItemsExceeding(track, targetEnd)
    for item in itemsToSplit do
        local excessStart = targetEnd
        local excessEnd = item.position + item.length
        local excessDuration = excessEnd - excessStart

        -- Split at zero-crossing (Story 3.2 logic)
        local splitPos = findZeroCrossing(item, excessStart)
        local leftPart, rightPart = splitItem(item, splitPos)

        -- Move right part to beginning
        moveItem(rightPart, targetStart)

        -- Adjust interval with next item
        local nextItem = getNextItem(rightPart)
        adjustInterval(rightPart, nextItem, effectiveInterval)
    end
end
```

---

## Acceptance Criteria

### AC1: All Tracks Start at Same Timestamp

**Given** multi-channel preserve loop export (e.g., 5.0 surround, 5 tracks)
**When** loop export completes
**Then** all tracks' first items start at the **exact same timestamp** (±0.001s tolerance)

**Validation**: Measure `firstItem.position` for each track, verify all equal.

### AC2: All Tracks End at Same Timestamp

**Given** multi-channel preserve loop export with `targetDuration = 30s`
**When** loop export completes
**Then** all tracks' last items end at `startTime + 30s` (±0.001s tolerance)

**Validation**: Measure `lastItem.position + lastItem.length` for each track, verify all equal `startTime + 30s`.

### AC3: Overfill Based on Interval

**Given** container with `triggerRate = -0.5s` (500ms overlap)
**When** loop export for 30s
**Then** each track is initially filled to `30s * (1 + 0.5/30) ≈ 30.5s` to provide material for repositioning

**Rationale**: Overfill factor must account for interval to ensure enough material exists for split/swap.

### AC4: Split & Swap Excess Items

**Given** track filled to 30.5s but target is 30s
**When** synchronization occurs
**Then**:
- Items exceeding 30s are **split at zero-crossing** (Story 3.2 logic)
- Excess portions are **moved to the beginning** of the track
- Interval between moved items and following items is `effectiveInterval`

**Validation**: Check first item was created via split, verify interval matches `triggerRate`.

### AC5: Preserve Zero-Crossing Splits (Story 3.2)

**Given** items must be split during sync
**When** split occurs
**Then** split position is at **zero-crossing** (amplitude near 0) for seamless loop

**Validation**: Verify split logic calls `findZeroCrossing()` from Story 3.2 implementation.

### AC6: Region Loops Seamlessly

**Given** exported region with all tracks synchronized
**When** region is repeated in REAPER timeline
**Then** audio loops seamlessly with no clicks, pops, or gaps

**Validation**: Manual listening test - loop region multiple times, verify no artifacts.

### AC7: Only Affects Preserve Mode

**Given** multi-channel export in **Flatten mode**
**When** loop export occurs
**Then** Flatten mode behavior is **unchanged** (no sync needed, all items on single track)

**Rationale**: This sync only applies to Preserve mode where tracks are independent.

---

## Tasks / Subtasks

### Task 1: Implement Overfill Phase

**File**: `Export_Placement.lua`

- [ ] **1.1**: Calculate overfill factor based on `abs(effectiveInterval) / targetDuration`
- [ ] **1.2**: Modify `placeItemsLoopMode()` to accept optional `overfillDuration` parameter
- [ ] **1.3**: Fill each track to `overfillDuration` instead of `targetDuration`
- [ ] **1.4**: Store overfill flag to indicate sync phase is needed

**AC Coverage**: AC3

---

### Task 2: Implement Timestamp Detection

**File**: `Export_Placement.lua`

- [ ] **2.1**: After all tracks filled, iterate to find earliest `firstItem.position`
- [ ] **2.2**: Find latest `lastItem.position + lastItem.length`
- [ ] **2.3**: Define `targetStart` and `targetEnd = targetStart + targetDuration`
- [ ] **2.4**: Log detected bounds for debugging

**AC Coverage**: AC1, AC2

---

### Task 3: Implement Item Shifting (Align Start)

**File**: `Export_Placement.lua`

- [ ] **3.1**: For each track, calculate `shiftAmount = targetStart - firstItem.position`
- [ ] **3.2**: Apply shift to all items on track using `reaper.SetMediaItemInfo_Value(item, "D_POSITION", newPos)`
- [ ] **3.3**: Verify all tracks now start at `targetStart`

**AC Coverage**: AC1

---

### Task 4: Implement Split & Swap (Excess Removal)

**File**: `Export_Placement.lua`

- [ ] **4.1**: Identify items exceeding `targetEnd` on each track
- [ ] **4.2**: For each excess item, calculate split position at `targetEnd`
- [ ] **4.3**: Call Story 3.2's `findZeroCrossing()` to find precise split point
- [ ] **4.4**: Split item using `reaper.SplitMediaItem()` at zero-crossing
- [ ] **4.5**: Move excess portion to `targetStart` (before first item)
- [ ] **4.6**: Adjust interval between moved item and following item to `effectiveInterval`

**AC Coverage**: AC2, AC4, AC5

---

### Task 5: Integration into Export Flow

**File**: `Export_Placement.lua`

- [ ] **5.1**: Detect if export is multi-channel preserve loop mode
- [ ] **5.2**: If true, invoke overfill phase
- [ ] **5.3**: After placement, invoke sync phase (Tasks 2-4)
- [ ] **5.4**: Ensure Flatten mode bypasses sync phase (AC7)

**AC Coverage**: AC7

---

### Task 6: Manual Testing & Validation

**Testing Checklist**:

- [ ] **6.1**: Export 5.0 ITU surround loop (5 tracks), verify all start/end synchronized (AC1, AC2)
- [ ] **6.2**: Export with `-0.5s` interval, verify overfill factor applied (AC3)
- [ ] **6.3**: Verify split occurs at zero-crossing (AC5) - check waveform
- [ ] **6.4**: Loop region 10 times in REAPER, verify no clicks/pops (AC6)
- [ ] **6.5**: Export same container in Flatten mode, verify no sync applied (AC7)

**AC Coverage**: All

---

## Implementation Notes

### Key Files to Modify

| File | Function | Changes |
|------|----------|---------|
| `Export_Placement.lua` | `placeItemsLoopMode()` | Add overfill parameter, fill logic |
| `Export_Placement.lua` | `placeContainerItems()` | Detect multi-channel preserve, invoke sync |
| `Export_Placement.lua` | `syncMultiChannelLoopTracks()` | New function for timestamp sync (Tasks 2-4) |
| `Export_Loop.lua` | `findZeroCrossing()` | Reuse Story 3.2 logic for split positioning |

### Reusable Components from Story 3.2

Story 3.2 implemented zero-crossing detection and split/swap logic for single-track loops. This story **reuses that logic** but applies it **per-track in multi-channel mode**.

**Story 3.2 Functions to Reuse**:
- `findZeroCrossing(item, targetPos)` - Find zero-crossing near target position
- Split logic (if abstracted into reusable function)

### Algorithm Pseudocode

```lua
-- In placeContainerItems() for multi-channel preserve loop
if isMultiChannelPreserveLoop then
    -- Phase 1: Overfill
    local overfillFactor = 1.0 + (math.abs(effectiveInterval) / targetDuration)
    local overfillDuration = targetDuration * overfillFactor

    for track in effectiveTargetTracks do
        placeItemsLoopMode(track, startPos, overfillDuration, ...)
    end

    -- Phase 2: Sync
    syncMultiChannelLoopTracks(effectiveTargetTracks, startPos, targetDuration, effectiveInterval)
end

function syncMultiChannelLoopTracks(tracks, startPos, targetDuration, effectiveInterval)
    -- Detect bounds
    local earliestStart, latestEnd = detectBounds(tracks)
    local targetStart = earliestStart
    local targetEnd = targetStart + targetDuration

    -- Sync each track
    for track in tracks do
        -- Shift to align start
        shiftTrackItems(track, targetStart)

        -- Split & swap excess
        local excessItems = getItemsExceeding(track, targetEnd)
        for item in excessItems do
            local splitPos = Loop.findZeroCrossing(item, targetEnd)  -- Story 3.2 reuse
            local leftPart, rightPart = reaper.SplitMediaItem(item, splitPos)
            reaper.SetMediaItemInfo_Value(rightPart, "D_POSITION", targetStart)
            adjustIntervalAfterSwap(rightPart, track, effectiveInterval)
        end
    end
end
```

### Edge Cases

1. **Overfill too small**: If `abs(effectiveInterval)` is very small, overfill might not provide enough material. **Solution**: Minimum overfill factor = 1.05 (5%)
2. **No items exceed targetEnd**: If all tracks naturally fit, skip split/swap phase
3. **Very short items**: Items shorter than `abs(effectiveInterval)` might cause issues. **Solution**: Validate item lengths before split
4. **Zero-crossing not found**: Fallback to exact targetEnd if zero-crossing search fails

---

## Cross-References

### Related Stories
- **Story 3.2**: [Loop Overlap After Split/Swap](./5-3-loop-overlap-after-split-swap.md) - Zero-crossing split logic (reused here)
- **Story 5.2**: [Export Multichannel Item Distribution](./5-2-export-multichannel-item-distribution.md) - Multi-channel track handling
- **Story 5.4**: [Fix All Tracks Mode - Respect Container Interval](./5-4-all-tracks-respect-container-interval.md) - Interval calculation fixes

### Source Code References
- [Export_Placement.lua](../../Scripts/Modules/Export/Export_Placement.lua) - Main placement logic
- [Export_Loop.lua](../../Scripts/Modules/Export/Export_Loop.lua) - Zero-crossing detection (Story 3.2)
- [Export_Settings.lua](../../Scripts/Modules/Export/Export_Settings.lua) - Loop mode detection

### Architecture Documents
- [Export v2 Architecture](../planning-artifacts/export-v2-architecture.md)
- [Epic 5: Bug Fixes](../planning-artifacts/epics.md#epic-5-bug-fixes-post-implementation)

---

## Dev Agent Record

### Agent Model Used
_To be filled during implementation_

### Implementation Log
_Track key decisions, challenges, and solutions here_

### Completion Notes
_Summary of implementation, deviations from plan, follow-up items_

### Modified Files
_List of all files modified during implementation_
