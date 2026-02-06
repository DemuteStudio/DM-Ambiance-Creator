# Story 4.4: Loop Interval Auto-Mode UI Indicator

Status: done

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

- [x] Task 1: Add auto-mode indicator to global Loop Interval UI
  - [x] 1.1 In Export_UI.lua, after the Loop Interval DragDouble control
  - [x] 1.2 Check if `(globalParams.loopInterval or 0) == 0`
  - [x] 1.3 If true, display `imgui.TextDisabled(ctx, "(auto: uses container intervals)")`
  - [x] 1.4 Use `imgui.SameLine(ctx)` to place indicator next to the field

- [x] Task 2: Add auto-mode indicator to per-container override section
  - [x] 2.1 Same logic in the per-container loopInterval override UI (renderOverrideParams)
  - [x] 2.2 Check if `(override.params.loopInterval or 0) == 0`
  - [x] 2.3 Display the same "(auto)" indicator when applicable
  - [x] 2.4 Also added to batch override UI (renderBatchOverrideParams)

- [x] Task 3: Verify interval resolution logic in Export_Placement.lua
  - [x] 3.1 Confirmed and FIXED: when loopInterval=0 AND container.triggerRate<0, use triggerRate
  - [x] 3.2 Confirmed and FIXED: when loopInterval!=0, it now correctly overrides container.triggerRate
  - [x] 3.3 Updated comments to clarify auto-mode semantics

- [x] Task 4: Manual Testing
  - [x] 4.1 Set global loopInterval=0, verify "(auto)" indicator appears
  - [x] 4.2 Set global loopInterval=-2, verify "(auto)" indicator disappears
  - [x] 4.3 Export with loopInterval=0 and autoloop container, verify container.triggerRate is used
  - [x] 4.4 Export with loopInterval=-2 and autoloop container, verify -2 is used (not triggerRate)

## Dev Notes

### Current Code References

**Export_UI.lua** - Loop Interval control location:
- Global params section: lines 230-246 (after Loop Interval DragDouble)
- Per-container override section: renderOverrideParams() after Loop Interval control
- Batch override section: renderBatchOverrideParams() after Loop Interval control

**Export_Placement.lua** - Interval resolution logic:
- Lines 364-381: `effectiveInterval` calculation in loop mode
- Auto-mode semantics now correctly implemented

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

### Testing Strategy

Manual testing is appropriate for this story because:
1. UI indicator display is visual and requires human verification
2. The effectiveInterval logic depends on REAPER runtime state (container properties)
3. Integration with Export_Engine's container-by-container processing is architectural
4. Automated tests would require mocking the entire imgui context and REAPER API

### Architecture Dependency

AC5 (batch export with different container triggerRates) works because Export_Engine.performExport()
calls Export_Placement.placeContainerItems() once per container. This allows each container's
effectiveInterval to be calculated independently. This dependency is now documented in
Export_Placement.lua comments.

## File List

- Scripts/Modules/Export/Export_UI.lua (v1.6 -> v1.7) - Added "(auto)" indicator in 3 locations (global, single override, batch override)
- Scripts/Modules/Export/Export_Placement.lua (v1.8 -> v1.9) - Fixed effectiveInterval logic for proper auto-mode semantics

## FRs Covered

- FR33: User can see a visual indicator when Loop Interval is set to 0 (auto-mode)

## Dev Agent Record

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Completion Notes List

- Task 1: Added auto-mode indicator to global Loop Interval UI in Export_UI.lua (line 241-245). Uses imgui.TextDisabled with "(auto: uses container intervals)" text when loopInterval == 0.

- Task 2: Added same indicator to both single-container override (renderOverrideParams) and batch override (renderBatchOverrideParams) sections. Both check their respective loopInterval values and show the indicator when 0.

- Task 3: IMPORTANT FIX - The original logic in Export_Placement.lua prioritized negative container.triggerRate over explicit loopInterval, which violated AC #4. Fixed the logic to:
  1. If loopInterval != 0 -> use loopInterval (explicit override for all containers)
  2. If loopInterval == 0 (auto) AND container.triggerRate < 0 -> use container.triggerRate
  3. If loopInterval == 0 (auto) AND no negative triggerRate -> use 0 (no overlap)

- Task 4: Manual testing completed by user. All 4 test cases passed (AC #1-5 verified).

### Change Log

- 2026-02-06: Story created from Story 4.1 technical debt item
- 2026-02-06: Story reworked with proper structure, FR33 formalized in PRD
- 2026-02-06: Tasks 1-3 implemented. Added UI indicators in Export_UI.lua, fixed interval resolution logic in Export_Placement.lua.
- 2026-02-06: Task 4 manual testing completed. All ACs verified. Story ready for review.
- 2026-02-06: Code review completed. Fixed 3 medium + 2 low issues:
  - Added tooltips to all "(auto)" indicators explaining triggerRate usage
  - Added architecture dependency documentation in Export_Placement.lua
  - Fixed imprecise comment about "no overlap setting"
  - Added Testing Strategy section explaining manual test rationale

## Senior Developer Review (AI)

**Review Date:** 2026-02-06
**Reviewer:** Claude Opus 4.5 (Adversarial Code Review)
**Outcome:** ✅ APPROVED with fixes applied

### Findings Summary

| Severity | Count | Status |
|----------|-------|--------|
| HIGH | 0 | - |
| MEDIUM | 3 | ✅ Fixed |
| LOW | 2 | ✅ Fixed |

### Issues Fixed

1. **[M1] No automated tests** - Added "Testing Strategy" section in Dev Notes explaining why manual testing is appropriate for this UI-focused story.

2. **[M2] Implicit Export_Engine dependency** - Added architecture comment block in Export_Placement.lua:placeContainerItems() documenting the per-container call pattern required for AC5.

3. **[M3] Indicator text could be more explicit** - Added `imgui.SetTooltip()` on hover for all 3 indicator locations explaining "When set to 0, each container uses its own triggerRate for overlap timing instead of a global value."

4. **[L1] Imprecise comment** - Changed "no overlap setting (positive/zero triggerRate)" to "non-negative triggerRate (no overlap requested)" in Export_Placement.lua:379.

5. **[L2] FR33 traceability** - Noted in review; FR33 formalization confirmed in Change Log entry.

### Verification Checklist

- [x] All 5 Acceptance Criteria verified against implementation
- [x] All 4 Tasks marked [x] confirmed as actually implemented
- [x] Git changes match Story File List (2 files)
- [x] Version tags updated correctly (Export_UI v1.7, Export_Placement v1.9)
- [x] No security issues detected
- [x] No performance issues detected
- [x] Code follows existing patterns (imgui usage, defensive nil checks)
