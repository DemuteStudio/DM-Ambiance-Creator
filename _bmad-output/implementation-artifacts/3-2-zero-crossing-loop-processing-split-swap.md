# Story 3.2: Zero-Crossing Loop Processing (Split/Swap)

Status: done

## Story

As a **game sound designer**,
I want **exported loops to be seamless with no clicks or artifacts at the loop point**,
So that **my loops play back perfectly in Wwise/FMOD without manual crossfade work**.

## Acceptance Criteria

1. **Given** a container in loop mode with placed items on a single track **When** processLoop is called **Then** the last item is identified, its center point calculated **And** findNearestZeroCrossing searches within +/-50ms (LOOP_ZERO_CROSSING_WINDOW) of the center using AudioAccessor_GetSamples **And** the item is split at the nearest zero-crossing point **And** the right portion is moved to position: firstItem.position - rightPart.length

2. **Given** a multichannel container in loop mode with items on multiple tracks **When** processLoop is called **Then** items are grouped by track **And** split/swap is applied independently per track **And** each track's loop point is processed with its own zero-crossing detection

3. **Given** a container in loop mode where no zero-crossing is found within the search window **When** findNearestZeroCrossing is called **Then** the function falls back to the exact center of the item **And** a warning is generated for the user

4. **Given** a container in loop mode with only 1 item **When** processLoop is called **Then** loop processing is skipped **And** a warning is generated: "Need at least 2 items for meaningful loop"

5. **Given** a container in loop mode with very short items **When** findNearestZeroCrossing is called **Then** the search window is reduced proportionally to avoid exceeding item bounds

## Tasks / Subtasks

- [x] Task 1: Create Export_Loop.lua module structure (AC: All)
  - [x] 1.1 Create Export_Loop.lua with module pattern (M = {}, initModule, setDependencies)
  - [x] 1.2 Add module header with @version 1.0 and description
  - [x] 1.3 Implement findNearestZeroCrossing(item, targetTime) using AudioAccessor API
  - [x] 1.4 Implement splitAndSwap(lastItem, firstItem, splitPoint) using SplitMediaItem
  - [x] 1.5 Implement processLoop(placedItems, targetTracks) with per-track grouping

- [x] Task 2: Implement findNearestZeroCrossing algorithm (AC: #1, #3, #5)
  - [x] 2.1 Get take and source from MediaItem
  - [x] 2.2 Create AudioAccessor with CreateTakeAudioAccessor
  - [x] 2.3 Calculate search window (use LOOP_ZERO_CROSSING_WINDOW constant)
  - [x] 2.4 Handle short items by reducing search window proportionally
  - [x] 2.5 Read samples with GetAudioAccessorSamples
  - [x] 2.6 Find zero-crossing closest to center (sign change detection)
  - [x] 2.7 Return fallback (exact center) if no zero-crossing found + warning
  - [x] 2.8 Cleanup: DestroyAudioAccessor

- [x] Task 3: Implement splitAndSwap algorithm (AC: #1)
  - [x] 3.1 Split last item at zero-crossing point using SplitMediaItem
  - [x] 3.2 Get the right portion (new item after split)
  - [x] 3.3 Calculate new position: firstItem.position - rightPart.length
  - [x] 3.4 Move right portion to new position using SetMediaItemPosition

- [x] Task 4: Implement processLoop with per-track handling (AC: #2, #4)
  - [x] 4.1 Group placedItems by trackIdx
  - [x] 4.2 For each track group: sort by position
  - [x] 4.3 Check if track has at least 2 items (skip with warning if not)
  - [x] 4.4 Identify first and last items per track
  - [x] 4.5 Calculate center of last item
  - [x] 4.6 Call findNearestZeroCrossing for last item
  - [x] 4.7 Call splitAndSwap for that track
  - [x] 4.8 Return result with success/warnings/errors

- [x] Task 5: Integrate into Export_Engine.lua (AC: All)
  - [x] 5.1 Import Export_Loop in init.lua (add to dofile loading)
  - [x] 5.2 Initialize Export_Loop in init.lua initModule
  - [x] 5.3 Wire dependencies: Export_Loop.setDependencies(Export_Settings)
  - [x] 5.4 Update Export_Engine.setDependencies to receive loop module
  - [x] 5.5 Call Loop.processLoop after placeContainerItems when isLoopMode
  - [x] 5.6 Handle loop processing result (warnings to console)

## Dev Notes

### CRITICAL: Export_Loop.lua Must Be Created

This story creates a **new module** that does not exist yet. The module implements seamless loop creation via zero-crossing detection and split/swap processing.

### Architecture Specification (from export-v2-architecture.md Section 4.4)

**Export_Loop.lua Functions:**

| Function | Description |
|----------|-------------|
| `processLoop(placedItems, targetTracks)` | Main loop processing. Groups items by track, applies split/swap per track. Returns `{ success = bool, warnings = [], errors = [] }`. |
| `findNearestZeroCrossing(item, targetTime)` | Uses `AudioAccessor_GetSamples()` to find the closest zero-crossing to `targetTime` within a search window. |
| `splitAndSwap(lastItem, firstItem, splitPoint)` | Split last item at split point, move right part before first item. |

### Zero-Crossing Detection Algorithm

```lua
function Loop.findNearestZeroCrossing(item, targetTime)
    local take = reaper.GetActiveTake(item)
    if not take then return targetTime end

    local source = reaper.GetMediaItemTake_Source(take)
    local sampleRate = reaper.GetMediaSourceSampleRate(source)
    local accessor = reaper.CreateTakeAudioAccessor(take)

    local searchWindow = Constants.EXPORT.LOOP_ZERO_CROSSING_WINDOW  -- 0.05s = ±50ms
    local searchStart = targetTime - searchWindow
    local numSamples = math.floor(searchWindow * 2 * sampleRate)
    local buffer = reaper.new_array(numSamples)

    reaper.GetAudioAccessorSamples(accessor, sampleRate, 1, searchStart, numSamples, buffer)

    -- Find zero-crossing closest to center
    local centerSample = math.floor(numSamples / 2)
    local bestIdx = centerSample
    local bestDistance = math.huge

    for i = 1, numSamples - 1 do
        local val = buffer[i]
        local nextVal = buffer[i + 1]
        -- Sign change = zero crossing
        if (val >= 0 and nextVal < 0) or (val <= 0 and nextVal > 0) then
            local distFromCenter = math.abs(i - centerSample)
            if distFromCenter < bestDistance then
                bestDistance = distFromCenter
                bestIdx = i
            end
        end
    end

    reaper.DestroyAudioAccessor(accessor)
    return searchStart + (bestIdx / sampleRate)
end
```

### Split/Swap Algorithm

```
For each track in placedItems:
  1. Sort items by position
  2. Get last item and first item
  3. Calculate center of last item: lastItem.position + (lastItem.length / 2)
  4. Find nearest zero-crossing to center (±50ms window)
  5. reaper.SplitMediaItem(lastItem, zeroCrossingPoint) → returns rightPart
  6. Calculate new position: firstItem.position - rightPart.length
  7. reaper.SetMediaItemPosition(rightPart, newPosition, false)
```

### Integration Point in Export_Engine.performExport()

After line 106 (after placeContainerItems), add:

```lua
-- Process loop if in loop mode
local isLoopMode = Settings.resolveLoopMode(containerInfo.container, params)
if isLoopMode and #placedItems > 1 then
    local loopResult = Loop.processLoop(placedItems, targetTracks)
    if loopResult.warnings then
        for _, warn in ipairs(loopResult.warnings) do
            reaper.ShowConsoleMsg("[Export] Warning: " .. warn .. "\n")
        end
    end
end
```

### PlacedItem Structure (from Export_Placement.placeContainerItems)

```lua
PlacedItem = {
    item = MediaItem,      -- REAPER MediaItem reference
    track = MediaTrack,    -- REAPER track reference
    position = number,     -- Timeline position in seconds
    length = number,       -- Item duration in seconds
    trackIdx = number,     -- Real track index from trackStructure
}
```

### REAPER API Functions Required

- `reaper.GetActiveTake(item)` - Get active take from item
- `reaper.GetMediaItemTake_Source(take)` - Get source from take
- `reaper.GetMediaSourceSampleRate(source)` - Get sample rate
- `reaper.CreateTakeAudioAccessor(take)` - Create audio accessor
- `reaper.GetAudioAccessorSamples(accessor, sampleRate, numChannels, startTime, numSamples, buffer)` - Read samples
- `reaper.DestroyAudioAccessor(accessor)` - Cleanup accessor
- `reaper.new_array(size)` - Create sample buffer
- `reaper.SplitMediaItem(item, position)` - Split item at position, returns right part
- `reaper.SetMediaItemPosition(item, position, wantRefresh)` - Move item
- `reaper.GetMediaItemInfo_Value(item, "D_POSITION")` - Get item position
- `reaper.GetMediaItemInfo_Value(item, "D_LENGTH")` - Get item length

### Edge Cases to Handle

1. **No zero-crossing found:** Fall back to exact center, generate warning
2. **Single item per track:** Skip processing, warn "Need at least 2 items for meaningful loop"
3. **Very short items:** Reduce search window to half item length if item < 100ms
4. **No take on item:** Return targetTime as fallback, warn
5. **Empty placedItems:** Return early with success (nothing to process)
6. **Split fails:** REAPER SplitMediaItem returns nil if position out of bounds

### Previous Story Intelligence (Story 3-1)

From Story 3-1 completion:
- `resolveLoopMode()` correctly detects loop mode (auto/on/off)
- `loopDuration` and `loopInterval` parameters are in place
- Items are placed with overlap (loopInterval) until loopDuration reached
- `placeContainerItems()` returns PlacedItem array ready for loop processing

**Key patterns established:**
- Module pattern: `local M = {}, initModule(g), setDependencies(...)`
- Constants access via `globals.Constants`
- Warning messages to console via `reaper.ShowConsoleMsg`

### Git Intelligence

Recent commits:
```
80a6a9a feat: Implement Story 3.1 Loop Mode Configuration with code review fixes
70ce421 feat: Implement Story 2.2 Per-Container Overrides with code review fixes
5c63dd7 feat: Implement Story 2.1 Pool Control with code review fixes
```

Epic 1 complete, Epic 2 complete, Story 3.1 complete. This is Story 3.2 (second story of Epic 3).

### Module Pattern

```lua
--[[
@version 1.0
@noindex
DM Ambiance Creator - Export Loop Module
Handles zero-crossing detection and seamless loop creation via split/swap processing.
--]]

local M = {}
local globals = {}
local Settings = nil

function M.initModule(g)
    if not g then error("Export_Loop.initModule: globals parameter is required") end
    globals = g
end

function M.setDependencies(settings)
    Settings = settings
end

-- Implementation functions here...

return M
```

### Testing Strategy

1. Create container with negative triggerRate (loop candidate)
2. Set loopMode to "on" or "auto"
3. Set loopDuration to 10s, loopInterval to -0.5s
4. Export container
5. Verify: last item is split, right portion moved before first item
6. Verify: split occurs at zero-crossing (no click at loop point)
7. Test multichannel: verify each track processes independently
8. Test single item: verify warning generated and no crash
9. Test short items (< 100ms): verify reduced search window
10. Play back rendered loop in REAPER: verify seamless

### References

- [Source: _bmad-output/planning-artifacts/export-v2-architecture.md#4.4 Export_Loop.lua] — Complete module specification
- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.2] — Acceptance criteria (FR11, FR12)
- [Source: Scripts/Modules/Export/Export_Engine.lua:100-106] — placeContainerItems integration point
- [Source: Scripts/Modules/Export/Export_Placement.lua:339-443] — PlacedItem structure
- [Source: Scripts/Modules/DM_Ambiance_Constants.lua:507] — LOOP_ZERO_CROSSING_WINDOW (0.05)
- [Source: Scripts/Modules/Export/Export_Settings.lua:287-303] — resolveLoopMode()
- [Source: Scripts/Modules/Export/init.lua] — Module loading pattern
- [Source: _bmad-output/implementation-artifacts/3-1-loop-mode-configuration-auto-detection.md] — Previous story learnings

### Project Structure Notes

**Files to Create:**
```
Scripts/Modules/Export/
└── Export_Loop.lua           -- NEW: Zero-crossing detection and loop processing
```

**Files to Modify:**
```
Scripts/Modules/Export/
├── init.lua                  -- ADD Export_Loop loading and wiring
└── Export_Engine.lua         -- ADD Loop.processLoop() call after placement
```

**Files Referenced (read-only):**
```
Scripts/Modules/Export/Export_Settings.lua   -- resolveLoopMode()
Scripts/Modules/Export/Export_Placement.lua  -- PlacedItem structure
Scripts/Modules/DM_Ambiance_Constants.lua    -- LOOP_ZERO_CROSSING_WINDOW
```

## Dev Agent Record

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

None

### Completion Notes List

- Created Export_Loop.lua module with full implementation of zero-crossing detection and split/swap loop processing
- findNearestZeroCrossing uses AudioAccessor API to read samples and detect sign changes within +/-50ms window (LOOP_ZERO_CROSSING_WINDOW)
- Short items (< 200ms) get proportionally reduced search windows to avoid exceeding bounds (AC #5)
- splitAndSwap splits last item at zero-crossing, moves right portion before first item (AC #1)
- processLoop groups items by trackIdx, processes each track independently (AC #2)
- Single-item tracks generate warning and skip processing (AC #4)
- Fallback to center point when no zero-crossing found with warning (AC #3)
- Integrated into Export_Engine.lua to call Loop.processLoop after placeContainerItems when isLoopMode
- Updated init.lua to load and wire Export_Loop module with dependencies

### File List

**New Files:**
- Scripts/Modules/Export/Export_Loop.lua (v1.1)

**Modified Files:**
- Scripts/Modules/Export/init.lua (v1.1 -> v1.2)
- Scripts/Modules/Export/Export_Engine.lua (v1.5 -> v1.7)

## Change Log

- 2026-02-06: Story 3.2 implementation complete - Zero-crossing loop processing with split/swap for seamless loops
- 2026-02-06: Code review fixes applied:
  - [HIGH] Region bounds now include loop-created items (rightParts moved to start)
  - [HIGH] totalItemsExported counts new items from split operations
  - [MEDIUM] Added MIDI item detection with fallback warning
  - [MEDIUM] Added locked item check before split operations
  - [MEDIUM] Added warning when rightPart position clamped to 0
  - [MEDIUM] processLoop now returns newItems array for downstream tracking

