# Story 4.4: Loop Interval Auto-Mode UI Indicator

Status: pending

## Story

As a **game sound designer**,
I want **the export modal to clearly indicate when Loop Interval is in "auto" mode (value=0) and will use each container's own overlap setting**,
So that **I understand exactly what interval will be applied to each autoloop container, avoiding confusion between the displayed "0" and the actual behavior**.

## Context

When exporting loop containers, the Loop Interval parameter controls the overlap between items. A value of 0 means "auto-mode" — each container uses its own `triggerRate` value. However, the current UI shows "0" without explaining this semantic, creating ambiguity for users who don't know that 0 has special meaning.

## Acceptance Criteria

1. **Given** the global Loop Interval field in the Export modal **When** the value is set to 0 **Then** a helper text "(auto: uses container intervals)" is displayed next to the field **And** the helper text is visually distinct (greyed/disabled style)

2. **Given** a container's per-container override section **When** the loopInterval override is set to 0 **Then** the same "(auto: uses container intervals)" indicator is displayed

3. **Given** the global Loop Interval is set to 0 and a container has `triggerRate = -1.5` **When** the export runs **Then** the container uses its own triggerRate (-1.5s) as the effective interval

4. **Given** the global Loop Interval is set to a non-zero value (e.g., -2.0) **When** the export runs **Then** all autoloop containers use the global value (-2.0s) **And** the UI does NOT show the "(auto)" indicator

5. **Given** multiple containers with different triggerRate values and global loopInterval = 0 **When** batch export runs **Then** each container uses its own triggerRate as interval

## Tasks / Subtasks

- [ ] Task 1: Add auto-mode indicator to global Loop Interval UI
  - [ ] 1.1 In Export_UI.lua, after the Loop Interval DragDouble control
  - [ ] 1.2 Check if `(globalParams.loopInterval or 0) == 0`
  - [ ] 1.3 If true, display `imgui.TextDisabled(ctx, "(auto: uses container intervals)")`
  - [ ] 1.4 Use `imgui.SameLine(ctx)` to place indicator next to the field

- [ ] Task 2: Add auto-mode indicator to per-container override section
  - [ ] 2.1 Same logic in the per-container loopInterval override UI
  - [ ] 2.2 Check if `(containerOverrides[key].loopInterval or 0) == 0`
  - [ ] 2.3 Display the same "(auto)" indicator when applicable

- [ ] Task 3: Verify interval resolution logic in Export_Placement.lua
  - [ ] 3.1 Confirm current behavior: when loopInterval=0 AND container.triggerRate<0, use triggerRate
  - [ ] 3.2 Confirm when loopInterval!=0, it overrides container.triggerRate
  - [ ] 3.3 Add clarifying comment if not already present

- [ ] Task 4: Manual Testing
  - [ ] 4.1 Set global loopInterval=0, verify "(auto)" indicator appears
  - [ ] 4.2 Set global loopInterval=-2, verify "(auto)" indicator disappears
  - [ ] 4.3 Export with loopInterval=0 and autoloop container, verify container.triggerRate is used
  - [ ] 4.4 Export with loopInterval=-2 and autoloop container, verify -2 is used (not triggerRate)

## Dev Notes

### Current Code References

**Export_UI.lua** - Loop Interval control location:
- Global params section: approximately line 226-237
- Per-container override section: search for `loopInterval` in override rendering

**Export_Placement.lua** - Interval resolution logic:
- Lines 355-371: `effectiveInterval` calculation in loop mode
- Current behavior already implements auto-mode, just needs UI indicator

### UI Implementation Pattern

```lua
-- After Loop Interval DragDouble
if (globalParams.loopInterval or 0) == 0 then
    imgui.SameLine(ctx)
    imgui.TextDisabled(ctx, "(auto: uses container intervals)")
end
```

### Semantic Clarification

| loopInterval Value | Behavior | UI Indicator |
|-------------------|----------|--------------|
| 0 | Auto-mode: each container uses its own triggerRate | "(auto: uses container intervals)" |
| Non-zero (e.g., -2) | Explicit override: all containers use this value | No indicator |

## File List

- Scripts/Modules/Export/Export_UI.lua (modify) - Add "(auto)" indicator in 2 locations
- Scripts/Modules/Export/Export_Placement.lua (verify/comment) - Confirm interval resolution logic

## FRs Covered

- FR33: User can see a visual indicator when Loop Interval is set to 0 (auto-mode)

## Dev Agent Record

### Agent Model Used

(pending)

### Completion Notes List

(pending)

### Change Log

- 2026-02-06: Story created from Story 4.1 technical debt item
- 2026-02-06: Story reworked with proper structure, FR33 formalized in PRD
