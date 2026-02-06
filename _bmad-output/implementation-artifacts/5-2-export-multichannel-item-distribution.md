# Story 5.2: Export Multichannel Item Distribution

Status: ready-for-dev

## Story

As a **game sound designer**,
I want **the export to place different items on each channel track when exporting multichannel containers (like 4.0 from stereo sources)**,
So that **my exported multichannel audio has varied content per channel, matching the behavior of the Generation engine**.

## Context

This is a **regression bug** that should have been fixed in Story 1.2 (Multichannel Item Placement via Generation Engine).

Currently, when exporting a multichannel container (e.g., 4.0 quad built from stereo items), the same item is placed on ALL channel tracks. The Generation engine correctly distributes different items to different tracks using round-robin or random distribution.

### Current Behavior (Bug)
```
Export 4.0 quad container:
- Track L-R:   Item A at 0s
- Track Ls-Rs: Item A at 0s  <-- SAME ITEM!
```

### Expected Behavior (Generation Engine)
```
Generate 4.0 quad container:
- Track L-R:   Item A at 0s
- Track Ls-Rs: Item B at 0s  <-- DIFFERENT ITEM
```

## Acceptance Criteria

1. **Given** a 4.0 quad container with stereo source items and `itemDistributionMode = 0` (Round-Robin)
   **When** the container is exported
   **Then** each stereo track pair receives a different item from the pool
   **And** items are distributed in round-robin order across track pairs

2. **Given** a multichannel container with `itemDistributionMode = 1` (Random)
   **When** the container is exported
   **Then** each track receives a randomly selected item from the pool
   **And** the same item may appear on multiple tracks by chance, but not deterministically

3. **Given** a multichannel container where `trackStructure.useSmartRouting = true` (e.g., multichannel source files)
   **When** the container is exported
   **Then** the SAME item is placed on all tracks (smart routing extracts different channels from same source)
   **And** channel selection is applied to extract the correct channels per track

4. **Given** a container with mono source items on a stereo-split configuration
   **When** the container is exported
   **Then** items are distributed to L and R tracks using the container's distribution mode

5. **Given** loop mode is enabled with multichannel distribution
   **When** the container is exported in loop mode
   **Then** item distribution is maintained throughout the loop cycle
   **And** each track has its own sequence of distributed items

## Tasks / Subtasks

- [ ] Task 1: Implement item distribution in placeContainerItems() (AC: #1, #2)
  - [ ] 1.1: Add distribution counter to track round-robin state
  - [ ] 1.2: Before placing item, check `trackStructure.useDistribution`
  - [ ] 1.3: If useDistribution, select different pool entry for each track
  - [ ] 1.4: Support both round-robin (mode 0) and random (mode 1) distribution

- [ ] Task 2: Preserve smart routing behavior (AC: #3)
  - [ ] 2.1: Check `trackStructure.useSmartRouting` flag
  - [ ] 2.2: When useSmartRouting is true, use same item on all tracks
  - [ ] 2.3: Ensure channel selection is applied correctly for each track

- [ ] Task 3: Handle mono split scenarios (AC: #4)
  - [ ] 3.1: Detect stereo containers with mono items (`trackStructure.trackType == "mono"`)
  - [ ] 3.2: Apply distribution to L/R tracks

- [ ] Task 4: Maintain distribution in loop mode (AC: #5)
  - [ ] 4.1: Track pool index separately per track in loop mode
  - [ ] 4.2: Ensure distribution continues correctly as pool cycles

## Dev Notes

### Key Files to Modify

- **Export_Placement.lua** - `placeContainerItems()` function, lines 360-496

### Root Cause Analysis

Current code at line 413-438:
```lua
-- Place item on target tracks (handles multi-channel)
for tIdx, track in ipairs(targetTracks) do
    local realTrackIdx = trackStructure.trackIndices
        and trackStructure.trackIndices[tIdx] or tIdx

    local newItem, length = globals.Generation.placeSingleItem(
        track,
        itemData,  -- <-- BUG: Same itemData for ALL tracks!
        itemPos,
        genParams,
        trackStructure,
        realTrackIdx,
        trackStructure.channelSelectionMode,
        true
    )
```

The `itemData` is resolved ONCE before the track loop, then used for all tracks.

### Fix Approach

Move item selection INSIDE the track loop when distribution is needed:

```lua
for tIdx, track in ipairs(targetTracks) do
    local currentItemData = itemData  -- Default: same item

    if trackStructure.useDistribution then
        -- Select different item for this track
        local poolIdx = selectPoolIndexForTrack(tIdx, distributionMode, pool)
        local poolEntry = pool[poolIdx]
        currentItemData = M.buildItemData(poolEntry.item, poolEntry.area)
    end

    -- Place with track-specific item
    globals.Generation.placeSingleItem(track, currentItemData, ...)
end
```

### Reference: Generation Engine Distribution Logic

From [Generation_ItemPlacement.lua:354-369](../../../Scripts/Modules/Audio/Generation/Generation_ItemPlacement.lua#L354-L369):

```lua
if distributionMode == 0 then
    -- Round-robin
    if not container.distributionCounter then
        container.distributionCounter = 0
    end
    container.distributionCounter = container.distributionCounter + 1
    local targetChannel = ((container.distributionCounter - 1) % #channelTracks) + 1
    targetTracks = {channelTracks[targetChannel]}
elseif distributionMode == 1 then
    -- Random
    local targetChannel = math.random(1, #channelTracks)
    targetTracks = {channelTracks[targetChannel]}
end
```

### Key Flags to Check

From `trackStructure`:
- `useDistribution`: True when items should be distributed across tracks
- `useSmartRouting`: True when same item goes to all tracks (channel extraction)
- `needsChannelSelection`: True when items need channel extraction

### Testing Scenarios

1. Export 4.0 quad with stereo items, verify different items on L-R vs Ls-Rs
2. Export 5.0 with mono items, verify round-robin across all 5 tracks
3. Export multichannel container with native multichannel source files (should use same item, different channels)
4. Export stereo container with mono items (stereo split scenario)
5. Loop mode: export 30s loop, verify distribution continues correctly

### References

- [Source: Export_Placement.lua#placeContainerItems](../../../Scripts/Modules/Export/Export_Placement.lua#L360-L496)
- [Source: Generation_ItemPlacement.lua#distribution-logic](../../../Scripts/Modules/Audio/Generation/Generation_ItemPlacement.lua#L340-L388)
- [Source: Story 1.2 - Original multichannel story](./1-2-multichannel-item-placement.md)

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
