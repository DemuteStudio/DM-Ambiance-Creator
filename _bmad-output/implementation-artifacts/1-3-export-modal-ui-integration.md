# Story 1.3: Export Modal UI Integration

Status: ready-for-dev

## Story

As a **game sound designer**,
I want **to access the export through a modal window with visible global parameters**,
So that **I can configure and execute exports through a clear interface**.

## Acceptance Criteria

1. **Given** the user has containers in their project **When** the Export modal is opened **Then** the modal displays all global parameters (instanceAmount, spacing, alignToSeconds, exportMethod, preservePan/Vol/Pitch, maxPoolItems, loopMode) **And** the modal uses Export_Settings for state management

2. **Given** the user configures global parameters and clicks Export **When** performExport is called **Then** Export_Engine orchestrates the export using Export_Settings.getEffectiveParams() and Export_Placement.placeContainerItems() **And** export results (success/errors) are reported back to the UI

3. **Given** an export is executed on a single container **When** the export completes **Then** items are correctly placed on the timeline with the configured parameters **And** the user can immediately see the exported items in REAPER

4. **Given** the Export modal is open **When** any parameter changes **Then** the Preview section updates in real-time showing per-container: name, pool ratio, loop status, track count, estimated duration

## Tasks / Subtasks

- [ ] Task 1: Add Max Pool Items control to Export_UI.lua global params section (AC: #1)
  - [ ] 1.1 After "Spacing" control, add `imgui.Text(ctx, "Max Pool Items:")` label
  - [ ] 1.2 Add `imgui.DragInt` for maxPoolItems with range [0, 999] (actual pool size clamped at export)
  - [ ] 1.3 Display ratio text next to control: `"All (8)"` when 0, or `"6 / 12 available"` when > 0

- [ ] Task 2: Add Loop Mode control to Export_UI.lua global params section (AC: #1)
  - [ ] 2.1 After "Max Pool Items", add `imgui.Text(ctx, "Loop Mode:")` label
  - [ ] 2.2 Add `imgui.Combo` with options `"Auto\0On\0Off\0"` mapping to loopMode values
  - [ ] 2.3 Convert combo index to loopMode string: 0="auto", 1="on", 2="off"

- [ ] Task 3: Implement Export_Engine.generatePreview() (AC: #4)
  - [ ] 3.1 Replace stub with implementation that collects enabled containers
  - [ ] 3.2 For each enabled container, call Settings.getEffectiveParams()
  - [ ] 3.3 Call Settings.resolveLoopMode() to determine loop status
  - [ ] 3.4 Call Settings.getPoolSize() to get total pool size
  - [ ] 3.5 Calculate poolSelected as min(maxPoolItems, poolTotal) when maxPoolItems > 0, else poolTotal
  - [ ] 3.6 Call Placement.resolveTrackStructure() to get trackCount and trackType
  - [ ] 3.7 Call estimateDuration() for each container
  - [ ] 3.8 Return array of PreviewEntry objects: `{name, poolTotal, poolSelected, loopMode, trackCount, trackType, estimatedDuration}`

- [ ] Task 4: Implement Export_Engine.estimateDuration() (AC: #4)
  - [ ] 4.1 Replace stub with calculation: `(poolSize * params.instanceAmount * avgItemLength) + ((poolSize * params.instanceAmount - 1) * params.spacing)`
  - [ ] 4.2 For avgItemLength, use constant 5.0s (reasonable default) or calculate from container items if available
  - [ ] 4.3 If loop mode enabled, return params.loopDuration or estimated duration based on items

- [ ] Task 5: Add Preview section to Export_UI.lua (AC: #4)
  - [ ] 5.1 After "Region Creation" section, add separator and "Preview" header with `imgui.TextColored(ctx, 0x00AAFFFF, "Preview")`
  - [ ] 5.2 Create child window for preview list `imgui.BeginChild(ctx, "PreviewList", -1, 120, imgui.ChildFlags_Border)`
  - [ ] 5.3 Call `Export_Engine.generatePreview()` to get preview data
  - [ ] 5.4 For each PreviewEntry, render row: `"Name    6/12  Loop ✓  2trk  ~12s"`
  - [ ] 5.5 Format loop indicator: checkmark or X, plus "(auto)" suffix if auto-resolved to true
  - [ ] 5.6 Format track info: `"1trk"` for mono, `"2trk"` for stereo, etc.
  - [ ] 5.7 Format duration: `"~12s"` rounded to nearest second

- [ ] Task 6: Add maxPoolItems and loopMode to override params UI (AC: #1)
  - [ ] 6.1 In `renderOverrideParams()`, add Max Pool Items DragInt after spacing
  - [ ] 6.2 In `renderOverrideParams()`, add Loop Mode Combo after maxPoolItems
  - [ ] 6.3 In `renderBatchOverrideParams()`, add matching controls for batch editing

- [ ] Task 7: Integration verification (AC: #1, #2, #3, #4)
  - [ ] 7.1 Verify plugin loads without errors in REAPER console
  - [ ] 7.2 Verify Export modal displays all global params including new maxPoolItems and loopMode
  - [ ] 7.3 Verify Preview section updates when parameters change
  - [ ] 7.4 Verify export completes successfully and places items on timeline
  - [ ] 7.5 Verify per-container overrides work for maxPoolItems and loopMode

## Dev Notes

### Critical Architecture Patterns — MUST FOLLOW

**Module Pattern (all Export modules follow this):**
```lua
local M = {}
local globals = {}

function M.initModule(g)
    if not g then error("ModuleName.initModule: globals parameter is required") end
    globals = g
end

function M.setDependencies(dep1, dep2)
    -- store references for cross-module calls
end

return M
```

**Cross-Module Communication:** Access other modules via globals table or dependency injection: `globals.Constants`, `Settings.xxx()`, `Engine.xxx()`.

### UI Layout Reference (from Architecture 4.5)

Target modal size: **750x620** (currently 750x580, need to increase for Preview section).

```
┌───────────────────────────────────────────────────────┐
│                    Export Items                         │
├──────────────┬────────────────────────────────────────┤
│              │  Export Parameters                      │
│  Containers  │  ┌──────────────────────────────────┐  │
│              │  │ Instance Amount: [1]              │  │
│  [✓] Rain    │  │ Spacing: [1.0]s                  │  │
│  [✓] Wind    │  │ Max Pool Items: [0] (All)        │  │ ← NEW
│  [ ] Thunder │  │ Loop Mode: [Auto ▼]              │  │ ← NEW
│              │  │ Align to seconds: [✓]            │  │
│              │  │ Preserve Pan/Vol/Pitch: [✓][✓][✓]│  │
│              │  └──────────────────────────────────┘  │
│              │                                         │
│              │  Container Override (if selected)       │
│              │  ┌──────────────────────────────────┐  │
│              │  │ [Override params for selection]   │  │
│              │  └──────────────────────────────────┘  │
│              │                                         │
│              │  Preview                                │ ← NEW
│              │  ┌──────────────────────────────────┐  │
│              │  │ Rain    4/8  Loop ✓  2trk  ~12s │  │
│              │  │ Wind    2/2  Loop ✗  1trk  ~8s  │  │
│              │  └──────────────────────────────────┘  │
├──────────────┴────────────────────────────────────────┤
│  Export Method: [Current Track ▼] | Enabled: 2/3      │
│                    [Export]  [Cancel]                   │
└───────────────────────────────────────────────────────┘
```

### PreviewEntry Data Model

```lua
PreviewEntry = {
    name              = string,     -- Container display name
    poolTotal         = number,     -- Total items available in pool
    poolSelected      = number,     -- Items that will be exported
    loopMode          = boolean,    -- Resolved loop mode (true/false)
    loopModeAuto      = boolean,    -- True if loopMode was "auto" and resolved to true
    trackCount        = number,     -- Number of target tracks
    trackType         = string,     -- "mono" | "stereo" | "multi"
    estimatedDuration = number,     -- Estimated total duration in seconds
}
```

### Loop Mode Combo Mapping

```lua
-- Combo string (null-separated)
local loopModeOptions = "Auto\0On\0Off\0"

-- Index to value mapping
local loopModeIndexToValue = { [0] = "auto", [1] = "on", [2] = "off" }
local loopModeValueToIndex = { ["auto"] = 0, ["on"] = 1, ["off"] = 2 }
```

### Max Pool Items Display Logic

```lua
local function formatPoolDisplay(maxPoolItems, poolTotal)
    if maxPoolItems == 0 or maxPoolItems >= poolTotal then
        return string.format("All (%d)", poolTotal)
    else
        return string.format("%d / %d available", maxPoolItems, poolTotal)
    end
end
```

### Constants Used

From `DM_Ambiance_Constants.lua` (added in Story 1-1):
```lua
Constants.EXPORT = {
    MAX_POOL_ITEMS_DEFAULT     = 0,         -- 0 = all items
    LOOP_MODE_AUTO             = "auto",
    LOOP_MODE_ON               = "on",
    LOOP_MODE_OFF              = "off",
    LOOP_MODE_DEFAULT          = "auto",
    LOOP_ZERO_CROSSING_WINDOW  = 0.05,      -- ±50ms search window (Story 3.2)
    -- ... existing constants ...
}
```

### Functions to Use

**From Export_Settings (already implemented in Story 1-1):**
- `getGlobalParams()` — returns globalParams table
- `setGlobalParam(param, value)` — sets param with validation
- `getPoolSize(containerKey)` — returns total exportable entries
- `resolveLoopMode(container, params)` — returns boolean
- `collectAllContainers()` — returns array of ContainerInfo

**From Export_Placement (already implemented in Story 1-2):**
- `resolveTrackStructure(containerInfo)` — returns trackStructure with numTracks, trackType

**From Export_Engine (stubs to implement):**
- `generatePreview()` — returns array of PreviewEntry
- `estimateDuration(poolSize, params, container)` — returns estimated seconds

### Previous Story Intelligence (1-1 and 1-2)

From Story 1-1 completion:
- Module architecture split Export_Core into Settings, Engine, Placement
- All v2 constants added (MAX_POOL_ITEMS_DEFAULT, LOOP_MODE_*, etc.)
- Export_UI updated to use Settings and Engine via setDependencies
- Code review fixes applied: missing v2 params, getPoolSize bug, validation in setGlobalParam

From Story 1-2 completion:
- Multichannel fix implemented using realTrackIdx from trackStructure.trackIndices
- resolveTrackStructure() delegates to globals.Generation correctly
- placeContainerItems() returns PlacedItem array with position and length
- Defensive null-check added for globals.Generation

### Git Intelligence

Recent commits:
- `4111583 Epic for Export feature` — epics.md created
- `279348e docs: Update README for v0.16.0 and v0.16.1 Export features`
- Stories 1-1 and 1-2 changes are currently uncommitted (git shows files as untracked/modified)

### Project Structure Notes

**Files to Modify:**
```
Scripts/Modules/Export/
├── Export_UI.lua      -- MODIFY: Add maxPoolItems, loopMode controls, Preview section
└── Export_Engine.lua  -- MODIFY: Implement generatePreview(), estimateDuration()
```

**Files Referenced (read-only):**
```
Scripts/Modules/Export/
├── Export_Settings.lua    -- Provides getPoolSize(), resolveLoopMode(), etc.
└── Export_Placement.lua   -- Provides resolveTrackStructure()
```

### REAPER ImGui API Functions Used

- `imgui.DragInt(ctx, label, value, speed, min, max)` — Integer drag control
- `imgui.Combo(ctx, label, currentItem, items)` — Dropdown combo (null-separated string)
- `imgui.BeginChild(ctx, id, width, height, flags)` — Scrollable child region
- `imgui.EndChild(ctx)` — End child region
- `imgui.TextColored(ctx, color, text)` — Colored text
- `imgui.TextDisabled(ctx, text)` — Greyed out text
- `imgui.Separator(ctx)` — Horizontal line
- `imgui.Spacing(ctx)` — Vertical spacing

### References

- [Source: _bmad-output/planning-artifacts/export-v2-architecture.md#4.5 Export_UI.lua] — UI layout specification
- [Source: _bmad-output/planning-artifacts/export-v2-architecture.md#3. Data Model] — PreviewEntry data model
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.3] — Acceptance criteria (FR28)
- [Source: Scripts/Modules/Export/Export_UI.lua] — Current UI implementation to extend
- [Source: Scripts/Modules/Export/Export_Engine.lua:123-131] — Current stubs to implement
- [Source: Scripts/Modules/Export/Export_Settings.lua:271-318] — v2 functions (resolveLoopMode, getPoolSize)
- [Source: _bmad-output/implementation-artifacts/1-1-module-architecture-settings-management.md] — Previous story dev notes
- [Source: _bmad-output/implementation-artifacts/1-2-multichannel-item-placement.md] — Previous story dev notes

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List

