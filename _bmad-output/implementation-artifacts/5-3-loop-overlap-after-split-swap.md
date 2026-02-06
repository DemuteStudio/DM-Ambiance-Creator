# Story 5.3: Loop Overlap After Split/Swap

Status: ready-for-dev

## Story

As a **game sound designer**,
I want **the loop split/swap processing to maintain consistent overlap/interval between ALL items including the repositioned piece**,
So that **my seamless loops have uniform spacing throughout, creating proper rhythmic consistency for game audio middleware**.

## Context

When exporting containers in loop mode, the system:
1. Places items with overlap (negative interval, e.g., -1.5s)
2. Splits the last item at zero-crossing
3. Moves the right portion to before the first item

**Current Bug:** After split/swap, the moved piece is placed directly adjacent to the second item (which was the first item before the move), with NO overlap between them. This creates an inconsistent gap in the loop.

### Current Behavior (Bug)
```
Before split/swap:
[Item1]----[Item2]----[Item3]----[Item4]
        -1.5s     -1.5s     -1.5s  (overlaps)

After split/swap (WRONG):
[RightPart][Item1]----[Item2]----[LeftPart]
          ^--- NO OVERLAP HERE! Items are touching/adjacent
```

### Expected Behavior
```
After split/swap (CORRECT):
[RightPart]----[Item1]----[Item2]----[LeftPart]
          -1.5s     -1.5s     -1.5s  (consistent overlaps)
```

## Acceptance Criteria

1. **Given** a loop export with `loopInterval = -1.5s` (1.5s overlap)
   **When** split/swap is performed
   **Then** the second item (original first) is positioned with the same -1.5s overlap relative to the moved right part
   **And** all other items maintain their original positions

2. **Given** a loop export with `loopInterval = 0` (auto-mode, uses container's triggerRate)
   **When** split/swap is performed with container `triggerRate = -2.0s`
   **Then** the overlap between right part and second item is 2.0s (matching container setting)

3. **Given** a multichannel loop export (multiple tracks processed independently)
   **When** split/swap is performed
   **Then** each track maintains its own consistent overlap
   **And** the overlap value is the same across all tracks (from effective params)

4. **Given** a loop where the right part is very short (< overlap amount)
   **When** split/swap is performed
   **Then** the right part is positioned with available overlap (may be less than target)
   **And** a warning is generated if overlap had to be reduced

5. **Given** loop export completes
   **When** crossfades are applied
   **Then** the overlap region between right part and second item has proper crossfade
   **And** all other crossfades remain intact

## Tasks / Subtasks

- [ ] Task 1: Modify splitAndSwap() to accept interval parameter (AC: #1, #2)
  - [ ] 1.1: Add `effectiveInterval` parameter to splitAndSwap() function signature
  - [ ] 1.2: Calculate new position as: `firstItemPos - rightPartLen + abs(effectiveInterval)`
  - [ ] 1.3: Update return value documentation

- [ ] Task 2: Pass interval from processLoop() to splitAndSwap() (AC: #1, #2)
  - [ ] 2.1: Modify processLoop() to accept effectiveInterval parameter
  - [ ] 2.2: Pass effectiveInterval from Export_Engine to processLoop()
  - [ ] 2.3: Calculate effectiveInterval in Export_Engine using same logic as placeContainerItems

- [ ] Task 3: Handle edge cases (AC: #4)
  - [ ] 3.1: Check if rightPartLen > abs(effectiveInterval)
  - [ ] 3.2: If right part is too short, use maximum possible overlap
  - [ ] 3.3: Generate warning when overlap is reduced

- [ ] Task 4: Ensure crossfades are applied correctly (AC: #5)
  - [ ] 4.1: Verify applyCrossfadesToTrack is called after loop processing
  - [ ] 4.2: Verify right part overlaps with second item (now in correct position)

- [ ] Task 5: Update multichannel handling (AC: #3)
  - [ ] 5.1: Ensure same effectiveInterval is used for all tracks
  - [ ] 5.2: Verify independent processing maintains consistency

## Dev Notes

### Key Files to Modify

- **Export_Loop.lua** - `splitAndSwap()` and `processLoop()` functions
- **Export_Engine.lua** - Pass effectiveInterval to loop processing

### Root Cause Analysis

Current `splitAndSwap()` at line 155-156:
```lua
-- Calculate new position: firstItem.position - rightPart.length
local newPosition = firstItemPos - rightPartLen
```

This places the right part IMMEDIATELY before the first item with NO gap for overlap.

### Fix: Calculate position with overlap

```lua
-- Calculate new position WITH overlap consideration
-- The right part should overlap with the second item (original first item)
-- by the same amount as other items in the loop
local overlapAmount = math.abs(effectiveInterval)
local newPosition = firstItemPos - rightPartLen + overlapAmount
```

Visual explanation:
```
firstItemPos = 10s
rightPartLen = 3s
effectiveInterval = -1.5s (overlap)

Current (WRONG):
newPosition = 10 - 3 = 7s
[RightPart 7-10s][Item1 starts at 10s] -- NO OVERLAP

Fixed (CORRECT):
newPosition = 10 - 3 + 1.5 = 8.5s
[RightPart 8.5-11.5s]
          [Item1 10-15s] -- 1.5s OVERLAP at 10-11.5s
```

### Function Signature Changes

```lua
-- Export_Loop.lua
function M.splitAndSwap(lastItem, firstItem, splitPoint, effectiveInterval)
    -- effectiveInterval: The overlap/interval value (negative for overlap)
    local overlapAmount = math.abs(effectiveInterval or 0)
    local newPosition = firstItemPos - rightPartLen + overlapAmount
    ...
end

function M.processLoop(placedItems, targetTracks, effectiveInterval)
    -- Pass effectiveInterval to splitAndSwap
    local swapResult = M.splitAndSwap(lastPlaced.item, firstPlaced.item, zeroCrossingTime, effectiveInterval)
    ...
end
```

```lua
-- Export_Engine.lua (in processContainerExport)
if isLoopMode and Loop and #placedItems > 1 then
    -- Calculate effectiveInterval (same logic as placeContainerItems)
    local effectiveInterval = 0
    if (params.loopInterval or 0) ~= 0 then
        effectiveInterval = params.loopInterval
    elseif container.triggerRate and container.triggerRate < 0 then
        effectiveInterval = container.triggerRate
    end

    local loopResult = Loop.processLoop(placedItems, targetTracks, effectiveInterval)
    ...
end
```

### Testing Scenarios

1. Export loop with -1.5s overlap, verify gap between right part and Item1 is 1.5s overlap
2. Export loop with loopInterval=0 (auto), verify uses container.triggerRate
3. Export multichannel loop, verify all tracks have same overlap
4. Export loop where split creates very short right part (< overlap), verify warning
5. Verify crossfades are applied in overlap regions

### References

- [Source: Export_Loop.lua#splitAndSwap](../../../Scripts/Modules/Export/Export_Loop.lua#L142-L189)
- [Source: Export_Loop.lua#processLoop](../../../Scripts/Modules/Export/Export_Loop.lua#L197-L285)
- [Source: Export_Placement.lua#effectiveInterval-logic](../../../Scripts/Modules/Export/Export_Placement.lua#L376-L390)
- [Source: Story 3.2 - Zero-Crossing Loop Processing](./3-2-zero-crossing-loop-processing-split-swap.md)

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
