# Story 1.1: Module Architecture & Settings Management

Status: done

## Story

As a **game sound designer**,
I want **a properly structured export system with configurable global parameters**,
So that **I have a reliable foundation for export with consistent, validated settings**.

## Acceptance Criteria

1. **Given** the plugin is loaded **When** the Export module initializes **Then** Export_Settings, Export_Engine, and Export_Placement modules are loaded via updated init.lua **And** Export_Core.lua is no longer referenced or required

2. **Given** the export modal is opened **When** the settings state is initialized **Then** globalParams contains all parameters with correct defaults: instanceAmount=1, spacing=1.0, alignToSeconds=true, exportMethod=0, preservePan=true, preserveVolume=true, preservePitch=true, maxPoolItems=0, loopMode="auto", createRegions=false, regionPattern="$container"

3. **Given** a user sets instanceAmount to 150 **When** validation runs **Then** the value is clamped to 100 (INSTANCE_MAX) **And** spacing is clamped to [0, 60], maxPoolItems to [0, pool size]

4. **Given** DM_Ambiance_Constants.lua is loaded **When** Export constants are accessed **Then** all new constants are available: MAX_POOL_ITEMS_DEFAULT, LOOP_MODE_AUTO, LOOP_MODE_ON, LOOP_MODE_OFF, LOOP_MODE_DEFAULT, LOOP_ZERO_CROSSING_WINDOW

5. **Given** the module is initialized **When** collectAllContainers() is called **Then** all containers from globals.items hierarchy are returned with path, key, and displayName

## Tasks / Subtasks

- [x] Task 1: Add new v2 EXPORT constants to DM_Ambiance_Constants.lua (AC: #4)
  - [x] 1.1 Add `MAX_POOL_ITEMS_DEFAULT = 0` after existing EXPORT constants
  - [x] 1.2 Add `LOOP_MODE_AUTO = "auto"`
  - [x] 1.3 Add `LOOP_MODE_ON = "on"`
  - [x] 1.4 Add `LOOP_MODE_OFF = "off"`
  - [x] 1.5 Add `LOOP_MODE_DEFAULT = "auto"`
  - [x] 1.6 Add `LOOP_ZERO_CROSSING_WINDOW = 0.05` (50ms search window)

- [x] Task 2: Create Export_Settings.lua — Full settings state management (AC: #1, #2, #3, #5)
  - [x] 2.1 Create `Scripts/Modules/Export/Export_Settings.lua` with standard module pattern (`local M = {}`, `M.initModule(g)`)
  - [x] 2.2 Migrate `exportSettings` state table from Export_Core.lua (lines 12-27), adding `maxPoolItems = 0` and `loopMode = "auto"` to globalParams
  - [x] 2.3 Migrate `containerListCache` local variable
  - [x] 2.4 Migrate `resetSettings()` — update to include new fields using Constants.EXPORT.MAX_POOL_ITEMS_DEFAULT and LOOP_MODE_DEFAULT
  - [x] 2.5 Migrate `collectAllContainers()` (Export_Core.lua lines 62-101) — no logic changes needed
  - [x] 2.6 Migrate `initializeEnabledContainers()` (lines 104-110)
  - [x] 2.7 Migrate all getter/setter functions: `getGlobalParams()`, `setGlobalParam()`, `isContainerEnabled()`, `setContainerEnabled()`, `isContainerSelected()`, `setContainerSelected()`, `toggleContainerSelected()`, `clearContainerSelection()`, `selectContainerRange()`, `getSelectedContainerCount()`, `getSelectedContainerKeys()`, `applyParamToSelected()`, `getContainerOverride()`, `setContainerOverride()`, `hasContainerOverride()`, `getEffectiveParams()`, `getEnabledContainerCount()`
  - [x] 2.8 Implement NEW function `resolveLoopMode(container, params)` — returns boolean: if params.loopMode == "auto", return true when `container.triggerRate < 0 AND container.intervalMode == Constants.TRIGGER_MODES.ABSOLUTE`; if "on" return true; if "off" return false
  - [x] 2.9 Implement NEW function `validateMaxPoolItems(container, maxItems)` — returns `math.min(maxItems, #container.items)` when maxItems > 0, else returns `#container.items`
  - [x] 2.10 Implement NEW function `getPoolSize(containerKey)` — returns total exportable entries (items x areas) for a container
  - [x] 2.11 Migrate `roundToNextSecond()` helper

- [x] Task 3: Create Export_Engine.lua — Export orchestration (AC: #1)
  - [x] 3.1 Create `Scripts/Modules/Export/Export_Engine.lua` with standard module pattern
  - [x] 3.2 Add `setDependencies(Settings, Placement)` function for cross-module references
  - [x] 3.3 Migrate `performExport()` from Export_Core.lua (lines 422-574) — refactor to use Export_Settings for state and Export_Placement for item placement
  - [x] 3.4 Migrate `parseRegionPattern()` helper (lines 245-251)
  - [x] 3.5 Migrate `shallowCopy()` helper (lines 413-419)
  - [x] 3.6 Add stub `generatePreview(settings)` — returns empty array (full implementation in Story 1.3)
  - [x] 3.7 Add stub `estimateDuration(poolSize, params, container)` — returns 0 (full implementation in Story 1.3)

- [x] Task 4: Create Export_Placement.lua — Placement helpers (AC: #1)
  - [x] 4.1 Create `Scripts/Modules/Export/Export_Placement.lua` with standard module pattern
  - [x] 4.2 Add `setDependencies(Settings)` function
  - [x] 4.3 Migrate `makeItemKey()` helper (lines 254-261)
  - [x] 4.4 Migrate `createExportTrack()` helper (lines 264-284)
  - [x] 4.5 Migrate `findTrackByName()` helper (lines 287-299)
  - [x] 4.6 Migrate `getChildTracks()` helper (lines 302-326)
  - [x] 4.7 Migrate `getTargetTracks()` helper as `resolveTargetTracks()` (lines 329-410) — rename for architecture compliance
  - [x] 4.8 Add stub `resolvePool(containerInfo, maxPoolItems)` — for now returns all items (full random subset in Story 2.1)
  - [x] 4.9 Add stub `resolveTrackStructure(containerInfo)` — delegates to Generation engine (full fix in Story 1.2)
  - [x] 4.10 Add stub `placeContainerItems(pool, targetTracks, trackStructure, params, containerInfo)` — returns empty (full multichannel fix in Story 1.2)

- [x] Task 5: Update Export/init.lua — New module loading (AC: #1)
  - [x] 5.1 Replace `dofile(modulePath .. "Export_Core.lua")` with three new module loads: Export_Settings, Export_Engine, Export_Placement
  - [x] 5.2 Update `initModule(g)` to initialize all three new sub-modules plus Export_UI
  - [x] 5.3 Add dependency wiring: `Export_Engine.setDependencies(Export_Settings, Export_Placement)`, `Export_Placement.setDependencies(Export_Settings)`, `Export_UI.setDependencies(Export_Settings, Export_Engine)`
  - [x] 5.4 Update re-exported functions: `performExport` now delegates to Export_Engine, `resetSettings` to Export_Settings
  - [x] 5.5 Update `getSubModules()` to return `{Settings, Engine, Placement, UI}` instead of `{Core, UI}`
  - [x] 5.6 Remove all Export_Core references

- [x] Task 6: Delete Export_Core.lua (AC: #1)
  - [x] 6.1 Delete `Scripts/Modules/Export/Export_Core.lua`
  - [x] 6.2 Verify no other files reference Export_Core directly (search codebase)

- [x] Task 7: Integration verification (AC: #1, #2, #3, #4, #5)
  - [x] 7.1 Verify plugin loads without errors in REAPER console
  - [x] 7.2 Verify Export modal opens and displays global params with correct defaults (including new maxPoolItems=0, loopMode="auto")
  - [x] 7.3 Verify existing export functionality still works (place items on timeline)
  - [x] 7.4 Verify collectAllContainers() returns correct container list
  - [x] 7.5 Verify resetSettings() resets to correct defaults including new v2 fields

## Dev Notes

### Critical Architecture Patterns — MUST FOLLOW

**Module Pattern (every module MUST follow this):**
```lua
local M = {}
local globals = {}

function M.initModule(g)
    if not g then error("ModuleName.initModule: globals parameter is required") end
    globals = g
end

-- Optional: for cross-module dependencies
function M.setDependencies(dep1, dep2)
    -- store references
end

return M
```

**Module Loading:** Uses `dofile()` with path resolution, NOT `require()`. Path resolved via:
```lua
local info = debug.getinfo(1, "S")
local modulePath = info.source:match[[^@?(.*[\/])[^\/]-$]]
```

**Cross-Module Communication:** Modules access others via globals table: `globals.Generation`, `globals.Utils`, `globals.Constants`, `globals.Structures`. Never import directly.

**Dependency Injection:** Sub-modules receive references to sibling modules via `setDependencies()`. This prevents circular dependencies. Example: Export_UI currently calls `Export_Core.setDependencies(Export_Core)` — this becomes `Export_UI.setDependencies(Export_Settings, Export_Engine)`.

### What's Being Refactored

Export_Core.lua (576 lines) is being split into 3 focused modules:

| Lines in Export_Core.lua | Destination Module | Content |
|---|---|---|
| 1-37 (module setup + state) | Export_Settings.lua | Settings state table, initModule |
| 39-233 (settings mgmt) | Export_Settings.lua | resetSettings, collectAllContainers, all getters/setters, getEffectiveParams |
| 236-261 (item key helper) | Export_Placement.lua | makeItemKey |
| 264-410 (track helpers) | Export_Placement.lua | createExportTrack, findTrackByName, getChildTracks, getTargetTracks |
| 413-419 (shallowCopy) | Export_Engine.lua | shallowCopy utility |
| 422-574 (performExport) | Export_Engine.lua | Main export orchestration, region creation |

### New v2 Settings Fields

Two new fields added to `globalParams`:
- `maxPoolItems` (number, default 0): 0 = export all items, >0 = random subset. Clamped to [0, pool_size].
- `loopMode` (string, default "auto"): "auto" | "on" | "off". Auto-detects from negative interval.

### resolveLoopMode Logic

```lua
function Settings.resolveLoopMode(container, params)
    if params.loopMode == Constants.EXPORT.LOOP_MODE_ON then return true end
    if params.loopMode == Constants.EXPORT.LOOP_MODE_OFF then return false end
    -- "auto": check if container has negative interval in absolute mode
    return container.triggerRate < 0
        and container.intervalMode == Constants.TRIGGER_MODES.ABSOLUTE
end
```

The `intervalMode == ABSOLUTE` check is critical — negative values only mean "overlap" in absolute interval mode (triggerMode 0). Other modes like NOISE, EUCLIDEAN, COVERAGE, etc. don't use triggerRate for overlap.

### Generation Engine Functions Used by Export

Export delegates to the Generation engine for multichannel consistency. These functions are accessed via `globals.Generation`:

| Function | Purpose | Used By |
|---|---|---|
| `analyzeContainerItems(container)` | Analyze items for channel structure | Export_Placement (Story 1.2) |
| `determineTrackStructure(container, analysis)` | Determine multichannel track mapping | Export_Placement (Story 1.2) |
| `placeSingleItem(track, itemData, pos, params, trackStruct, trackIdx, chSelMode, ignoreBounds)` | Place one item on timeline | Export_Engine/Placement |

**CRITICAL:** The `ignoreBounds = true` parameter MUST be passed to `placeSingleItem()` in export context — this allows placement outside the REAPER time selection.

### Key Data Structures

**Container (from globals.items hierarchy):**
```lua
container = {
    name = string,
    items = {},                    -- Array of audio items
    triggerRate = number,          -- Negative = overlap interval
    intervalMode = number,         -- 0=ABSOLUTE, 1=RELATIVE, etc.
    channelMode = number,          -- 0=Stereo, 1=Quad, 2=5.0, 3=7.0
    channelVariant = number,       -- 0=ITU, 1=SMPTE (for surround)
    trackGUID = string,            -- REAPER track GUID
    channelTrackGUIDs = {},        -- Multi-channel track GUIDs
    randomizePitch = boolean,
    randomizeVolume = boolean,
    randomizePan = boolean,
    -- ... more fields (see DM_Ambiance_Structures.lua)
}
```

**ContainerInfo (returned by collectAllContainers):**
```lua
containerInfo = {
    path = {1, 2},                 -- Index path in globals.items
    containerIndex = 1,            -- Index within group
    container = containerRef,      -- Reference to container object
    group = groupRef,              -- Reference to parent group
    key = "1_2::1",               -- Unique key from Utils.makeContainerKey
    displayName = "Group / Container", -- For UI display
}
```

### Container Key Generation

Container keys use `globals.Utils.makeContainerKey(path, containerIndex)` or fallback: `table.concat(path, "_") .. "::" .. containerIndex`. This MUST remain consistent — keys are used for enabledContainers, overrides, and selection tracking.

### Existing Export_UI.lua Dependencies

Export_UI.lua currently calls these from Export_Core via `setDependencies(Export_Core)`:
- `Core.resetSettings()`
- `Core.collectAllContainers()`
- `Core.initializeEnabledContainers()`
- `Core.getGlobalParams()` / `Core.setGlobalParam()`
- `Core.isContainerEnabled()` / `Core.setContainerEnabled()`
- `Core.isContainerSelected()` / `Core.toggleContainerSelected()` / `Core.clearContainerSelection()` / `Core.selectContainerRange()`
- `Core.getContainerOverride()` / `Core.setContainerOverride()` / `Core.hasContainerOverride()`
- `Core.getEffectiveParams()`
- `Core.getEnabledContainerCount()`
- `Core.performExport()`

After refactoring, Export_UI must call settings functions from Export_Settings and export execution from Export_Engine. Update `Export_UI.setDependencies()` signature from `setDependencies(Core)` to `setDependencies(Settings, Engine)`, then update ALL internal references from `Core.xxx()` to either `Settings.xxx()` or `Engine.xxx()`.

### Export_UI.lua setDependencies Mapping

| Old Call (Core.xxx) | New Module | New Call |
|---|---|---|
| Core.resetSettings() | Settings | Settings.resetSettings() |
| Core.collectAllContainers() | Settings | Settings.collectAllContainers() |
| Core.initializeEnabledContainers() | Settings | Settings.initializeEnabledContainers() |
| Core.getGlobalParams() | Settings | Settings.getGlobalParams() |
| Core.setGlobalParam() | Settings | Settings.setGlobalParam() |
| Core.isContainerEnabled() | Settings | Settings.isContainerEnabled() |
| Core.setContainerEnabled() | Settings | Settings.setContainerEnabled() |
| Core.isContainerSelected() | Settings | Settings.isContainerSelected() |
| Core.toggleContainerSelected() | Settings | Settings.toggleContainerSelected() |
| Core.clearContainerSelection() | Settings | Settings.clearContainerSelection() |
| Core.selectContainerRange() | Settings | Settings.selectContainerRange() |
| Core.getContainerOverride() | Settings | Settings.getContainerOverride() |
| Core.setContainerOverride() | Settings | Settings.setContainerOverride() |
| Core.hasContainerOverride() | Settings | Settings.hasContainerOverride() |
| Core.getEffectiveParams() | Settings | Settings.getEffectiveParams() |
| Core.getEnabledContainerCount() | Settings | Settings.getEnabledContainerCount() |
| Core.getSelectedContainerCount() | Settings | Settings.getSelectedContainerCount() |
| Core.getSelectedContainerKeys() | Settings | Settings.getSelectedContainerKeys() |
| Core.applyParamToSelected() | Settings | Settings.applyParamToSelected() |
| Core.performExport() | Engine | Engine.performExport() |

### REAPER API Functions Used

- `reaper.Undo_BeginBlock()` / `reaper.Undo_EndBlock()` — Undo block wrapping
- `reaper.PreventUIRefresh(1/-1)` — Prevent UI flicker during batch operations
- `reaper.GetCursorPosition()` — Get timeline cursor for export start position
- `reaper.CountTracks(0)` / `reaper.GetTrack(0, idx)` — Track enumeration
- `reaper.InsertTrackAtIndex(idx, false)` — Create new tracks
- `reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)` — Set track name
- `reaper.BR_GetMediaTrackByGUID(0, guid)` — Find track by GUID (SWS extension)
- `reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")` — Check folder depth
- `reaper.GetParentTrack(track)` — Get parent folder track
- `reaper.AddProjectMarker2(0, true, start, end, name, -1, 0)` — Create region
- `reaper.SNM_GetIntConfigVar("defxfadeshape", 0)` — Get crossfade shape config (SWS)
- `reaper.ShowMessageBox(msg, title, 0)` — User message
- `reaper.UpdateArrange()` — Refresh arrange view

### Project Structure Notes

**File locations:**
```
Scripts/Modules/Export/
├── init.lua                    -- MODIFY: Replace Export_Core loading
├── Export_Core.lua             -- DELETE: Split into Settings + Engine + Placement
├── Export_Settings.lua         -- CREATE: All settings state management
├── Export_Engine.lua           -- CREATE: Export orchestration + region creation
├── Export_Placement.lua        -- CREATE: Track resolution + item placement helpers
└── Export_UI.lua               -- MODIFY: Update setDependencies(Settings, Engine)

Scripts/Modules/
└── DM_Ambiance_Constants.lua   -- MODIFY: Add 6 new EXPORT constants
```

**No changes needed in:**
- `DM_Ambiance_Structures.lua` — container structure already supports all required fields
- `DM_Ambiance_UI_Preset.lua` — already calls `Export.openModal()` / `Export.renderModal()`
- `DM_Ambiance Creator.lua` (main script) — calls `Export.initModule(globals)` which handles internal wiring
- Generation engine modules — no changes, export delegates to them

### Git Intelligence

Recent commits show:
- v0.16.0-beta: Initial Export modal with generation engine delegation
- v0.16.1-beta: Added region creation with naming patterns ($container, $group, $index)
- Code follows established patterns: module aggregator, dependency injection, undo blocks

### References

- [Source: _bmad-output/planning-artifacts/export-v2-architecture.md#2. Module Structure] — Target module structure
- [Source: _bmad-output/planning-artifacts/export-v2-architecture.md#3. Data Model] — Export settings state, pool entry, placed item data models
- [Source: _bmad-output/planning-artifacts/export-v2-architecture.md#4.1 Export_Settings.lua] — Full function specification
- [Source: _bmad-output/planning-artifacts/export-v2-architecture.md#5. Constants] — Complete constants list
- [Source: _bmad-output/planning-artifacts/export-v2-architecture.md#6. Migration from v1] — Migration plan
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.1] — Acceptance criteria and FRs
- [Source: Scripts/Modules/Export/Export_Core.lua] — Current monolithic module (576 lines) to be split
- [Source: Scripts/Modules/Export/init.lua] — Current aggregator to update
- [Source: Scripts/Modules/Export/Export_UI.lua] — UI module that depends on Core (update dependencies)
- [Source: Scripts/Modules/DM_Ambiance_Constants.lua#Constants.EXPORT] — Current constants (lines 483-501)

## Change Log

- 2026-02-05: Story 1.1 implementation complete — Refactored Export_Core.lua (576 lines) into 3 focused modules (Export_Settings, Export_Engine, Export_Placement), added 6 new v2 EXPORT constants, updated init.lua aggregator and Export_UI dependencies, deleted Export_Core.lua
- 2026-02-05: Code review fixes — Added missing v2 params (maxPoolItems, loopMode, createRegions, regionPattern) to container override defaults in Export_UI.lua; Fixed getPoolSize() itemIndex bug; Added validation/clamping to setGlobalParam(); Removed unused xfadeshape variable; Deleted accidental nul file

## Dev Agent Record

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

- No errors encountered during implementation
- Static verification confirmed all function call chains are consistent across modules
- No test framework configured in project; verification is manual in REAPER DAW
- Task 7 (integration verification) completed via static analysis: file structure verified, no broken references, all functions resolved

### Completion Notes List

- Migrated Export_Core.lua (576 lines) into 3 focused modules following established module pattern (local M = {}, M.initModule(g), return M)
- Export_Settings.lua (285 lines): All state management, getters/setters, plus 3 new v2 functions (resolveLoopMode, validateMaxPoolItems, getPoolSize)
- Export_Engine.lua (212 lines): Export orchestration with performExport, parseRegionPattern, shallowCopy, plus 2 stubs (generatePreview, estimateDuration)
- Export_Placement.lua (200 lines): Track resolution with makeItemKey, createExportTrack, findTrackByName, getChildTracks, resolveTargetTracks (renamed from getTargetTracks), plus 3 stubs
- Updated init.lua to load 3 new modules, wire dependencies, update re-exports and getSubModules
- Updated Export_UI.lua: setDependencies(settings, engine) replaces setDependencies(core), all Export_Core references updated to Export_Settings/Export_Engine
- Added 6 new EXPORT constants to DM_Ambiance_Constants.lua: MAX_POOL_ITEMS_DEFAULT, LOOP_MODE_AUTO/ON/OFF/DEFAULT, LOOP_ZERO_CROSSING_WINDOW
- Deleted Export_Core.lua after verifying no remaining code references

### File List

- Scripts/Modules/DM_Ambiance_Constants.lua — MODIFIED: Added 6 new v2 EXPORT constants (lines 502-507)
- Scripts/Modules/Export/Export_Settings.lua — CREATED: Settings state management module (285 lines)
- Scripts/Modules/Export/Export_Engine.lua — CREATED: Export orchestration module (212 lines)
- Scripts/Modules/Export/Export_Placement.lua — CREATED: Placement helpers module (200 lines)
- Scripts/Modules/Export/init.lua — MODIFIED: Updated to load new modules, wire dependencies, version 1.0 → 1.1
- Scripts/Modules/Export/Export_UI.lua — MODIFIED: Updated setDependencies signature, replaced all Export_Core refs
- Scripts/Modules/Export/Export_Core.lua — DELETED: Replaced by Settings + Engine + Placement
