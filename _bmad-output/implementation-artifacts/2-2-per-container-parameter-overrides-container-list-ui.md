# Story 2.2: Per-Container Parameter Overrides & Container List UI

Status: done

## Story

As a **game sound designer**,
I want **to see all my containers with toggles and configure different export parameters per container**,
So that **I can fine-tune each container's export settings independently (e.g., different pool sizes for different containers)**.

## Acceptance Criteria

1. **Given** the Export modal is open **When** the container list is displayed **Then** all containers from the project are listed with enable/disable checkboxes **And** all containers are enabled by default

2. **Given** a container is selected in the container list **When** the per-container override section is displayed **Then** the user can override any global parameter for that specific container **And** overridden values are visually distinct from global defaults

3. **Given** a container has maxPoolItems overridden to 4 and global maxPoolItems is 0 **When** getEffectiveParams(containerKey) is called **Then** the returned params have maxPoolItems=4 (override wins) **And** all other params use global values

4. **Given** a container has no overrides set **When** getEffectiveParams(containerKey) is called **Then** all global parameter values are returned unchanged

5. **Given** multiple containers are displayed in the list **When** a container is disabled (unchecked) **Then** that container is excluded from export **And** its per-container overrides are preserved for re-enabling

## Tasks / Subtasks

- [x] Task 1: Container list with enable/disable checkboxes (AC: #1)
  - [x] 1.1 Render container list in left panel with checkboxes
  - [x] 1.2 Implement `initializeEnabledContainers()` to enable all by default
  - [x] 1.3 Support multi-selection (Ctrl+Click toggle, Shift+Click range)
  - [x] 1.4 Store enabled state in `exportSettings.enabledContainers`

- [x] Task 2: Per-container override section UI (AC: #2)
  - [x] 2.1 Display "Container Override" section in right panel
  - [x] 2.2 Show selected container name when single selection
  - [x] 2.3 Add "Enable Override" checkbox to activate per-container params
  - [x] 2.4 Render override parameter controls (instances, spacing, maxPool, loopMode, preserves)
  - [x] 2.5 Add visual distinction for overridden values (highlight values that differ from global)

- [x] Task 3: getEffectiveParams implementation (AC: #3, #4)
  - [x] 3.1 Return override.params when override.enabled = true
  - [x] 3.2 Return globalParams when no override or override.enabled = false
  - [x] 3.3 Ensure override.params is initialized with copy of globalParams on first enable

- [x] Task 4: Disabled container behavior (AC: #5)
  - [x] 4.1 Filter enabled containers in `performExport()`
  - [x] 4.2 Preserve containerOverrides when container is disabled
  - [x] 4.3 Skip disabled containers in preview generation

- [x] Task 5: Multi-selection batch editing (AC: #2 extension)
  - [x] 5.1 Show "X containers selected" when multiple selected
  - [x] 5.2 Add batch "Enable Override for all" checkbox
  - [x] 5.3 Implement `applyParamToSelected()` for batch parameter changes
  - [x] 5.4 Show batch editing controls when all selected have overrides enabled

- [x] Task 6: Visual distinction for overridden values (AC: #2 - REMAINING)
  - [x] 6.1 Compare override.params values against current globalParams
  - [x] 6.2 Add colored indicator (e.g., orange text/icon) for values that differ
  - [x] 6.3 Apply visual distinction in both single and batch override UI

## Dev Notes

### Implementation Status Analysis

**CRITICAL:** Most of this story's functionality was already implemented in Story 1-3 (Export Modal UI Integration). The container list, override section, getEffectiveParams, and enabled/disabled behavior are all working.

**THE ONLY REMAINING GAP is Task 6:** Visual distinction for overridden values (AC #2 partial). Currently:
- When override is enabled, ALL global values are copied to override.params
- User can change any value, but there's NO visual indicator showing which values differ from current globals
- This is a UX enhancement, not a functional bug

### Current Implementation Details

**Export_Settings.lua (v1.1):**
- `containerOverrides = {}` — stores {[containerKey] = {enabled, params}} (line 28)
- `enabledContainers = {}` — stores {[containerKey] = true/false} (line 29)
- `selectedContainerKeys = {}` — multi-selection tracking (line 30)
- `getEffectiveParams(containerKey)` — returns override.params if enabled, else globalParams (lines 248-254)
- `initializeEnabledContainers()` — enables all containers on modal open (lines 110-116)

**Export_UI.lua (v1.1):**
- Left panel: Container list with checkboxes + multi-selection support (lines 68-114)
- Right panel: Global params + Container Override section + Preview (lines 119-438)
- `renderOverrideParams()` — single container override UI (lines 500-588)
- `renderBatchOverrideParams()` — multi-selection override UI (lines 591-669)

**Export_Engine.lua (v1.4):**
- `performExport()` filters enabled containers at lines 49-53
- `generatePreview()` skips disabled containers at lines 150-152
- Uses `Settings.getEffectiveParams(containerInfo.key)` for per-container params

### Visual Distinction Implementation Approach

To complete AC #2 ("overridden values are visually distinct"), implement Task 6:

**Option A: Text Color Change**
```lua
-- In renderOverrideParams, compare value to global
local isOverridden = override.params.maxPoolItems ~= globalParams.maxPoolItems
if isOverridden then
    imgui.PushStyleColor(ctx, imgui.Col_Text, 0xFFAA00FF)  -- Orange
end
-- ... render control ...
if isOverridden then
    imgui.PopStyleColor(ctx)
end
```

**Option B: Suffix Indicator**
```lua
local label = "Max Pool:"
if override.params.maxPoolItems ~= globalParams.maxPoolItems then
    label = label .. " *"  -- Asterisk indicates override
end
```

**Option C: Side Icon**
```lua
imgui.Text(ctx, "Max Pool:")
if override.params.maxPoolItems ~= globalParams.maxPoolItems then
    imgui.SameLine(ctx)
    imgui.TextColored(ctx, 0xFFAA00FF, "*")  -- Orange asterisk
end
```

**Recommendation:** Option C (Side Icon) provides clearest UX without cluttering the layout.

### Functions Already Implemented

**From Export_Settings.lua:**
- `collectAllContainers()` — recursive container collection (line 68)
- `initializeEnabledContainers()` — enable all by default (line 110)
- `isContainerEnabled()` / `setContainerEnabled()` — enabled state (lines 154-159)
- `isContainerSelected()` / `setContainerSelected()` / `toggleContainerSelected()` — selection (lines 163-181)
- `clearContainerSelection()` / `selectContainerRange()` — selection helpers (lines 183-205)
- `getContainerOverride()` / `setContainerOverride()` / `hasContainerOverride()` — overrides (lines 235-245)
- `getEffectiveParams(containerKey)` — param resolution (line 248)
- `applyParamToSelected(param, value)` — batch editing (line 224)

**From Export_UI.lua:**
- Container list rendering with Ctrl/Shift+Click support
- Override section with Enable checkbox
- Single selection override params
- Multi-selection batch editing

### Module Pattern

```lua
local M = {}
local globals = {}

function M.initModule(g)
    if not g then error("ModuleName.initModule: globals parameter is required") end
    globals = g
end

function M.setDependencies(settings, engine)
    Settings = settings
    Engine = engine
end

return M
```

### Constants Used

From `DM_Ambiance_Constants.lua`:
```lua
Constants.EXPORT = {
    INSTANCE_MIN = 1,
    INSTANCE_MAX = 100,
    INSTANCE_DEFAULT = 1,
    SPACING_MIN = 0,
    SPACING_MAX = 60,
    SPACING_DEFAULT = 1.0,
    MAX_POOL_ITEMS_DEFAULT = 0,
    LOOP_MODE_AUTO = "auto",
    LOOP_MODE_ON = "on",
    LOOP_MODE_OFF = "off",
    LOOP_MODE_DEFAULT = "auto",
}
```

### Previous Story Intelligence (Story 2-1)

From Story 2-1 completion:
- Pool control (maxPoolItems) fully implemented with random subset selection
- `validateMaxPoolItems()` properly clamps to pool size including waveformAreas
- Preview section shows pool ratio correctly
- Fisher-Yates shuffle ensures different random selection each export run

**Key patterns established:**
- Override params initialized as copy of globalParams at enable time
- Changes to override params only affect that container
- Disabled containers skipped in both export and preview

### Git Intelligence

Recent commits:
```
5c63dd7 feat: Implement Story 2.1 Pool Control with code review fixes
83df52b fix: Code review fixes for Story 1.3 Export Modal UI
874f56a docs: Add Export feature story files (1-1, 1-2, 1-3)
0cb7a9f feat: Refactor Export module architecture and fix multichannel placement
```

Epic 1 complete, Story 2.1 complete. This is Story 2.2 (second and final story of Epic 2).

### Project Structure Notes

**Files to Modify:**
```
Scripts/Modules/Export/
└── Export_UI.lua   -- MODIFY: Add visual distinction for overridden values (Task 6)
```

**Files Referenced (read-only):**
```
Scripts/Modules/Export/
├── Export_Settings.lua  -- Provides getEffectiveParams(), getGlobalParams()
└── Export_Engine.lua    -- Uses getEffectiveParams() in performExport()
```

### Testing Strategy

1. Open Export modal with 3+ containers
2. Verify all containers listed with enabled checkboxes checked
3. Select one container, verify "Container Override" section appears
4. Enable override, change maxPoolItems from 0 to 5
5. Verify maxPoolItems field shows visual indicator (different from global)
6. Change spacing, verify spacing also shows indicator
7. Select different container, verify its values are still global (no indicator)
8. Disable first container, select it again, verify override preserved
9. Run export, verify first container skipped
10. Multi-select 3 containers, enable override for all, change spacing
11. Verify all 3 get new spacing value

### Edge Cases to Handle

1. **Override enabled but values unchanged:** No visual distinction (matches global)
2. **Global value changed after override set:** Override still wins, but visual shows as "different"
3. **Multi-selection with mixed override states:** Show "Enable Override for all" checkbox
4. **All containers disabled:** Export shows "No containers enabled" message

### References

- [Source: _bmad-output/planning-artifacts/export-v2-architecture.md#3.1 Export Settings State] — containerOverrides data model
- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.2] — Acceptance criteria (FR14, FR29, FR30)
- [Source: Scripts/Modules/Export/Export_Settings.lua:248-254] — getEffectiveParams implementation
- [Source: Scripts/Modules/Export/Export_UI.lua:260-378] — Container Override section
- [Source: Scripts/Modules/Export/Export_UI.lua:500-588] — renderOverrideParams function
- [Source: Scripts/Modules/Export/Export_Engine.lua:49-53] — Enabled container filtering
- [Source: _bmad-output/implementation-artifacts/2-1-pool-control-max-items-random-subset.md] — Previous story learnings

## Dev Agent Record

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

None - clean implementation

### Completion Notes List

- ✅ **BUG FIX:** Fixed pre-existing ImGui BeginChild/EndChild assertion failure
  - Root cause: EndChild() called unconditionally even when BeginChild() returned false
  - Fix: Moved EndChild() calls inside their respective if blocks (ContainerList, Parameters, PreviewList)
- ✅ Implemented visual distinction for override values using orange text + asterisk suffix
- ✅ Compares each override param against globalParams at render time
- ✅ Applied to both single selection (`renderOverrideParams`) and batch mode (`renderBatchOverrideParams`)
- ✅ All 8 parameters covered: instanceAmount, spacing, maxPoolItems, loopMode, alignToSeconds, preservePan, preserveVolume, preservePitch
- ✅ Labels turn orange with "*" suffix when value differs from global (e.g., "Instances: *")
- ✅ Checkboxes show "*" in label when toggled differently from global

#### Code Review Fixes (v1.3)

- ✅ **HIGH FIX:** Added export error display - errors now shown in red text next to Export button
- ✅ **HIGH FIX:** Added 3 missing override parameters to fully implement AC #2:
  - `exportMethod` - Choose current track or new track per-container
  - `createRegions` - Toggle region creation per-container
  - `regionPattern` - Custom region pattern per-container
- ✅ **MEDIUM FIX:** Extracted loopMode constants to module-level (LOOP_MODE_OPTIONS, LOOP_MODE_VALUE_TO_INDEX, LOOP_MODE_INDEX_TO_VALUE)
- ✅ **MEDIUM FIX:** Added OVERRIDE_LABEL_WIDTH and MAX_POOL_UI_LIMIT constants to replace magic numbers
- ✅ **MEDIUM FIX:** Added nil checks for preview entry fields to prevent crash on malformed data
- ✅ **MEDIUM FIX:** Cached collectAllContainers() result at frame start (called once, used 4 places)
- ✅ Now all 11 globalParams are overridable per-container (was 8)

### File List

- Scripts/Modules/Export/Export_UI.lua (MODIFIED) - v1.1 → v1.3: BeginChild fix, visual distinction, code review fixes (error display, all params, constants, nil checks, caching)

