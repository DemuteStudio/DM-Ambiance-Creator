# Export System v2 — Architecture Document

**Version:** 2.0
**Date:** 2026-02-05
**Status:** Approved
**Replaces:** Export v0.16.0/v0.16.1 (prototype)

---

## 1. Context & Motivation

The Export system (v0.16.0-v0.16.1) was a prototype that revealed critical issues when used in production:

1. **Multichannel bug**: Export places the same item on every track instead of applying proper channel distribution. Root cause: the export loop uses a simple counter (`tIdx`) instead of real track indices, and doesn't replicate the Generation engine's per-track channel extraction logic.
2. **Missing pool control**: No way to limit the number of unique items exported from the pool.
3. **No loop support**: Containers with negative intervals (overlapping items) cannot be exported as seamless loops ready for render.

### Use Case

Game audio pipeline: preview ambiance in REAPER, then extract individual sources with proper multichannel distribution to reproduce the behavior in a game audio engine.

---

## 2. Module Structure

```
Scripts/Modules/Export/
├── init.lua                   -- Module aggregator, public API
├── Export_Settings.lua         -- State management, validation, parameter resolution
├── Export_Engine.lua            -- Orchestrator, preview generation, error handling
├── Export_Placement.lua         -- Pool resolution, multichannel placement (Generation delegation)
├── Export_Loop.lua              -- Zero-crossing detection, split/swap loop processing
└── Export_UI.lua                -- Modal window with live preview
```

### Module Dependency Graph

```
init.lua
  ├── Export_Settings.lua
  ├── Export_Engine.lua
  │     ├── Export_Settings (reads effective params)
  │     ├── Export_Placement (delegates item placement)
  │     └── Export_Loop (delegates loop processing)
  ├── Export_Placement.lua
  │     ├── Export_Settings (reads pool/track config)
  │     ├── Generation_Modes.determineTrackStructure()
  │     ├── Generation_MultiChannel.analyzeContainerItems()
  │     ├── Generation_MultiChannel.applyChannelSelection()
  │     └── Generation_ItemPlacement.placeSingleItem()
  └── Export_UI.lua
        ├── Export_Settings (reads/writes settings)
        └── Export_Engine.generatePreview() (live preview data)
```

---

## 3. Data Model

### 3.1 Export Settings State

```lua
exportSettings = {
    globalParams = {
        -- Retained from v1
        instanceAmount    = 1,              -- Number of copies per pool entry (1-100)
        spacing           = 1.0,            -- Seconds between instances
        alignToSeconds    = true,           -- Align positions to whole seconds
        exportMethod      = 0,              -- 0 = current track, 1 = new track
        preservePan       = true,           -- Preserve pan randomization
        preserveVolume    = true,           -- Preserve volume randomization
        preservePitch     = true,           -- Preserve pitch randomization
        createRegions     = false,          -- Create REAPER regions
        regionPattern     = "$container",   -- Region naming pattern

        -- New in v2
        maxPoolItems      = 0,              -- 0 = all items, >0 = random subset
        loopMode          = "auto",         -- "auto" | "on" | "off"

        -- Story 5.2: Multichannel export mode (Code Review L1)
        multichannelExportMode = "flatten", -- "flatten" | "preserve" (Story 5.2)
    },
    containerOverrides    = {},             -- Per-container param overrides (same keys as globalParams)
    enabledContainers     = {},             -- {[containerKey] = true/false}
    selectedContainerKeys = {},             -- Multi-selection tracking for UI
}
```

### 3.2 Pool Entry

```lua
PoolEntry = {
    item     = itemObject,          -- Reference to container item
    area     = {                    -- Waveform area (or full item)
        startPos = number,          -- Seconds
        endPos   = number,          -- Seconds
        name     = string,
    },
    itemIdx  = number,              -- Index in container.items
    itemKey  = string,              -- Composite key for waveformAreas lookup
}
```

### 3.3 Placed Item Record

```lua
PlacedItem = {
    item      = MediaItem,          -- REAPER MediaItem reference
    track     = MediaTrack,         -- REAPER track reference
    position  = number,             -- Timeline position in seconds
    length    = number,             -- Item duration in seconds
    trackIdx  = number,             -- Track index (for loop grouping)
}
```

### 3.4 Preview Entry

```lua
PreviewEntry = {
    name              = string,     -- Container display name
    poolTotal         = number,     -- Total items available in pool
    poolSelected      = number,     -- Items that will be exported
    loopMode          = boolean,    -- Resolved loop mode (true/false)
    trackCount        = number,     -- Number of target tracks
    trackType         = string,     -- "mono" | "stereo" | "multi"
    estimatedDuration = number,     -- Estimated total duration in seconds
    instanceCount     = number,     -- Instance amount
}
```

---

## 4. Module Specifications

### 4.1 Export_Settings.lua

**Purpose:** State management, validation, parameter resolution. No export logic.

**Functions:**

| Function | Description |
|----------|-------------|
| `collectAllContainers()` | Recursively gather all containers from `globals.items` hierarchy. Returns array of ContainerInfo objects with path, key, displayName. |
| `initializeEnabledContainers()` | Enable all containers by default on modal open. |
| `getEffectiveParams(containerKey)` | Resolve parameters: override values take precedence over globals. |
| `resolveLoopMode(container, params)` | Returns `boolean`. If `params.loopMode == "auto"`: returns `true` when `container.triggerRate < 0 AND container.intervalMode == Constants.TRIGGER_MODES.ABSOLUTE`. If `"on"`: returns `true`. If `"off"`: returns `false`. |
| `validateMaxPoolItems(container, maxItems)` | Returns `math.min(maxItems, #container.items)` when `maxItems > 0`, else returns `#container.items`. |
| `getPoolSize(containerKey)` | Returns total number of exportable entries (items x areas). |
| `resetSettings()` | Reset all settings to defaults. |

**Validation Rules:**
- `maxPoolItems` clamped to `[0, total pool size]`
- `instanceAmount` clamped to `[1, 100]`
- `spacing` clamped to `[0, 60]`
- `loopMode` must be one of `"auto"`, `"on"`, `"off"`

### 4.2 Export_Engine.lua

**Purpose:** Orchestration, preview, region creation, error reporting.

**Functions:**

| Function | Description |
|----------|-------------|
| `performExport(settings)` | Main export execution. Returns results table with `success[]`, `errors[]`, `warnings[]`. |
| `generatePreview(settings)` | Returns array of `PreviewEntry` without executing anything. |
| `estimateDuration(poolSize, params, container)` | Calculate estimated duration based on pool size, spacing, instances, and interval. |
| `createRegion(placedItems, params, containerInfo, index)` | Create a REAPER region spanning all placed items for a container. |

**Export Flow (performExport):**

```
For each enabled container:
  1. Settings.getEffectiveParams(key) → params
  2. Settings.resolveLoopMode(container, params) → isLoop
  3. Placement.resolvePool(containerInfo, params.maxPoolItems) → pool
  4. Placement.resolveTrackStructure(containerInfo) → trackStructure
  5. Placement.resolveTargetTracks(containerInfo, trackStructure, params) → targetTracks
  6. Placement.placeContainerItems(pool, targetTracks, trackStructure, params, containerInfo) → placedItems
  7. IF isLoop AND #placedItems > 0:
       Loop.processLoop(placedItems, targetTracks) → loopResult
  8. IF params.createRegions:
       Engine.createRegion(placedItems, params, containerInfo, exportIndex)
  9. Accumulate results (success/error/warning)
```

**Error Handling:**
- Per-container try/catch: one container failing does not abort the entire export
- Errors and warnings collected and returned to UI for display
- Warnings for: empty pool, loop processing failure, track creation failure

### 4.3 Export_Placement.lua

**Purpose:** Pool resolution with random subset selection, and correct multichannel item placement. This module fixes the multichannel bug by properly delegating to the Generation engine.

**Functions:**

| Function | Description |
|----------|-------------|
| `resolvePool(containerInfo, maxPoolItems)` | Collect all items + areas into PoolEntry array. Apply random subset if `maxPoolItems > 0`. |
| `resolveTrackStructure(containerInfo)` | Delegate to `Generation_Modes.determineTrackStructure()` with proper analysis from `Generation_MultiChannel.analyzeContainerItems()`. |
| `resolveTargetTracks(containerInfo, trackStructure, params)` | Find or create target tracks based on `exportMethod`. Simplified track resolution: use existing container tracks (method 0) or create new tracks (method 1). |
| `placeContainerItems(pool, targetTracks, trackStructure, params, containerInfo)` | Place items from pool onto target tracks with correct multichannel distribution. Returns array of PlacedItem records. |
| `buildItemData(poolEntry, params)` | Construct ItemData object from pool entry for `placeSingleItem()`. |
| `buildGenParams(params, containerInfo)` | Construct genParams with preserve flags for `placeSingleItem()`. |
| `calculatePosition(currentPos, instance, params, container)` | Calculate timeline position accounting for spacing, alignment, and negative intervals. |

**Multichannel Fix — Core Logic:**

The critical fix is in `placeContainerItems()`:

```lua
for _, poolEntry in ipairs(pool) do
    for instance = 1, params.instanceAmount do
        local itemPos = calculatePosition(...)

        for tIdx, track in ipairs(targetTracks) do
            -- FIX: Use real track index from trackStructure, not loop counter
            local realTrackIdx = trackStructure.trackIndices
                and trackStructure.trackIndices[tIdx] or tIdx

            local itemData = buildItemData(poolEntry, params)

            local newItem, length = globals.Generation.placeSingleItem(
                track, itemData, itemPos,
                buildGenParams(params, containerInfo),
                trackStructure,
                realTrackIdx,                           -- Real track index
                trackStructure.channelSelectionMode,
                true                                    -- ignoreBounds
            )

            if newItem then
                table.insert(placedItems, {
                    item = newItem, track = track,
                    position = itemPos, length = length,
                    trackIdx = tIdx
                })
            end
        end

        -- Update position for next placement
        -- Negative interval → overlap
        if container.triggerRate < 0 and container.intervalMode == 0 then
            currentPos = itemPos + length + container.triggerRate
        else
            currentPos = itemPos + length + params.spacing
        end
    end
end
```

**Random Subset Selection:**

```lua
function resolvePool(containerInfo, maxPoolItems)
    local allEntries = {}

    for itemIdx, item in ipairs(containerInfo.container.items) do
        local itemKey = makeItemKey(containerInfo.path, containerInfo.containerIndex, itemIdx)
        local areas = globals.waveformAreas and globals.waveformAreas[itemKey]

        if areas and #areas > 0 then
            for _, area in ipairs(areas) do
                table.insert(allEntries, {
                    item = item, area = area,
                    itemIdx = itemIdx, itemKey = itemKey
                })
            end
        else
            table.insert(allEntries, {
                item = item,
                area = { startPos = 0, endPos = item.length or 10, name = item.name or "Full" },
                itemIdx = itemIdx, itemKey = itemKey
            })
        end
    end

    -- Random subset selection
    if maxPoolItems > 0 and maxPoolItems < #allEntries then
        local shuffled = Utils.shuffleArray(Utils.copyArray(allEntries))
        local subset = {}
        for i = 1, maxPoolItems do
            subset[i] = shuffled[i]
        end
        return subset
    end

    return allEntries
end
```

### 4.4 Export_Loop.lua

**Purpose:** Process placed items into seamless loops by finding zero-crossings, splitting, and swapping.

**Functions:**

| Function | Description |
|----------|-------------|
| `processLoop(placedItems, targetTracks)` | Main loop processing. Groups items by track, applies split/swap per track. Returns `{ success = bool, error = string? }`. |
| `findNearestZeroCrossing(item, targetTime)` | Uses `AudioAccessor_GetSamples()` to find the closest zero-crossing to `targetTime` within a search window. |
| `splitAndSwap(lastItem, firstItem)` | Split last item at center zero-crossing, move right part before first item. |

**Algorithm:**

```
For each track in placedItems:
  1. Sort items by position
  2. Get last item and first item
  3. Calculate center of last item
  4. Find nearest zero-crossing to center (±50ms window)
  5. SplitMediaItem(lastItem, zeroCrossingPoint)
  6. Move right part to position: firstItem.position - rightPart.length
```

**Zero-Crossing Detection:**

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

**Edge Cases:**
- No zero-crossing found in window → fall back to exact center (warn user)
- Single item in container → skip loop processing (warn: need at least 2 items for meaningful loop)
- Very short items → reduce search window proportionally

### 4.5 Export_UI.lua

**Purpose:** Modal window with container list, parameters, and live preview.

**Layout (750x620):**

```
┌───────────────────────────────────────────────────────┐
│                    Export Items                         │
├──────────────┬────────────────────────────────────────┤
│              │  Export Parameters                      │
│  Containers  │  ┌──────────────────────────────────┐  │
│              │  │ Instance Amount: [1]              │  │
│  [✓] Rain    │  │ Spacing: [1.0]s                  │  │
│  [✓] Wind    │  │ Align to seconds: [✓]            │  │
│  [ ] Thunder │  │ Preserve Pan/Vol/Pitch: [✓][✓][✓]│  │
│              │  │ Export Method: [Current Track ▼]  │  │
│              │  │ Max Pool Items: [0] (all)         │  │ ← NEW
│              │  │ Loop Mode: [Auto ▼]              │  │ ← NEW
│              │  │ Create Regions: [ ]               │  │
│              │  └──────────────────────────────────┘  │
│              │                                         │
│              │  Container Override (if selected)       │
│              │  ┌──────────────────────────────────┐  │
│              │  │ [Override params for selection]   │  │
│              │  └──────────────────────────────────┘  │
│              │                                         │
│              │  Preview                                │
│              │  ┌──────────────────────────────────┐  │
│              │  │ Rain    4/8  Loop ✓  2trk  ~12s │  │ ← NEW
│              │  │ Wind    2/2  Loop ✗  1trk  ~8s  │  │
│              │  └──────────────────────────────────┘  │
├──────────────┴────────────────────────────────────────┤
│                    [Export]  [Cancel]                   │
└───────────────────────────────────────────────────────┘
```

**Preview Section:**
- Live-updates on any parameter change
- Calls `Export_Engine.generatePreview()` to compute preview data
- Displays per enabled container: name, pool selection ratio, loop status, track count, estimated duration
- Loop indicator: if `loopMode == "auto"` and resolved to true, show "(auto)" next to checkmark

**New UI Controls:**
- **Max Pool Items**: `DragInt` (0-pool size). Display: `"3 / 8 available"` or `"All (8)"` when 0.
- **Loop Mode**: `Combo` with options `Auto | On | Off`. When Auto and resolved to loop, display visual indicator.

---

## 5. Constants

```lua
Constants.EXPORT = {
    -- Retained
    INSTANCE_MIN               = 1,
    INSTANCE_MAX               = 100,
    INSTANCE_DEFAULT           = 1,
    SPACING_MIN                = 0,
    SPACING_MAX                = 60,
    SPACING_DEFAULT            = 1.0,
    ALIGN_TO_SECONDS_DEFAULT   = true,
    PRESERVE_PAN_DEFAULT       = true,
    PRESERVE_VOLUME_DEFAULT    = true,
    PRESERVE_PITCH_DEFAULT     = true,
    METHOD_CURRENT_TRACK       = 0,
    METHOD_NEW_TRACK           = 1,
    METHOD_DEFAULT             = 0,
    CREATE_REGIONS_DEFAULT     = false,
    REGION_PATTERN_DEFAULT     = "$container",

    -- New in v2
    MAX_POOL_ITEMS_DEFAULT         = 0,         -- 0 = all items
    LOOP_MODE_AUTO                 = "auto",
    LOOP_MODE_ON                   = "on",
    LOOP_MODE_OFF                  = "off",
    LOOP_MODE_DEFAULT              = "auto",
    LOOP_ZERO_CROSSING_WINDOW      = 0.05,      -- ±50ms search window
}
```

---

## 6. Migration from v1

### Files to Delete
- `Export/Export_Core.lua` — replaced by Export_Settings + Export_Engine + Export_Placement

### Files to Create
- `Export/Export_Settings.lua`
- `Export/Export_Engine.lua`
- `Export/Export_Placement.lua`
- `Export/Export_Loop.lua`

### Files to Modify
- `Export/init.lua` — update module loading and public API
- `Export/Export_UI.lua` — add maxPoolItems, loopMode controls, preview section
- `DM_Ambiance_Constants.lua` — add new EXPORT constants
- `DM_Ambiance_Structures.lua` — no changes needed (container structure already supports all required fields)
- `DM_Ambiance_UI_Preset.lua` — no changes needed (already calls Export.openModal/renderModal)

### Breaking Changes
- `Export_Core.lua` is fully replaced; any direct references to `Export_Core` functions must be updated
- `exportSettings` state shape adds new fields; defaults handle backward compatibility

---

## 7. Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Delegate to Generation engine** for item placement | Ensures multichannel behavior is identical between generation and export. Single source of truth. |
| **Random subset** for max pool items | User requested random selection. Shuffled array approach is simple and unbiased. |
| **Loop mode "auto"** as default | Containers with negative intervals are natural loop candidates. Auto-detection reduces manual configuration. |
| **Zero-crossing at item center** | Simple, predictable split point. ±50ms window is sufficient for most audio material. |
| **Per-track loop processing** | Each track in a multichannel setup may have different items; loop split must be independent per track. |
| **Live preview in UI** | Gives user confidence about what will be exported before executing. Low cost since it only computes metadata. |
| **Per-container error handling** | One container failing should not abort the entire export. Results reported per container. |
| **Split Export_Core into 3 modules** | Separation of concerns: settings (state), engine (orchestration), placement (execution). Each module is testable in isolation. |
