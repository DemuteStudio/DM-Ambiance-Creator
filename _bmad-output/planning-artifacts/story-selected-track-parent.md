---
type: story
status: draft
priority: low
scope: Generation_Core
affects:
  - Scripts/Modules/Audio/Generation/Generation_Core.lua
  - Scripts/Modules/Audio/Generation/Generation_TrackManagement.lua
---

# Story: Use Selected Track as Parent on First Generation

As a **sound designer**,
I want **the generated ambiance tracks to be created as children of my currently selected REAPER track**,
So that **I can organize my ambiances within an existing track hierarchy instead of always generating at the root level**.

## Context

Currently, when generating an ambiance (group folder + container tracks), the group folder is always inserted at the end of the track list at root level (`I_FOLDERDEPTH = 0` equivalent). There is no way to control where in the track hierarchy the generated tracks are placed.

This feature only applies to **first-time generation** — when re-generating, the tool already reuses existing tracks.

## Acceptance Criteria

### AC1: Selected track becomes parent folder

**Given** a track is selected in REAPER and a group has no existing tracks in the project
**When** the user triggers generation
**Then** the group folder track is created as a child of the selected track (inside it), not at the root level
**And** the selected track is set to folder mode (`I_FOLDERDEPTH = 1`) if it isn't already

### AC2: Multiple tracks selected = use the topmost one

**Given** multiple tracks are selected in REAPER
**When** the user triggers generation
**Then** the first selected track (highest in the track list) is used as parent
**And** other selected tracks are ignored

### AC2b: No selection = current behavior

**Given** no track is selected in REAPER
**When** the user triggers generation
**Then** the group folder track is created at the end of the track list as usual (current behavior unchanged)

### AC3: Selected track already has children

**Given** a track is selected that already contains child tracks (existing folder)
**When** the user triggers generation
**Then** the group folder tracks are added as additional children inside the existing folder
**And** existing children are preserved and not affected

### AC4: Multiple groups generated at once

**Given** a track is selected and multiple groups are being generated
**When** the user triggers generation
**Then** all group folders are created as children of the selected track
**And** they appear in order inside the selected track's folder

### AC5: Re-generation ignores selection

**Given** a track is selected and the groups already have associated tracks in the project
**When** the user triggers re-generation
**Then** the existing tracks are reused as usual, ignoring the selected track
**And** the behavior is identical to current re-generation logic

## Technical Notes

### Current behavior (Generation_Core.lua)
- Line ~123: `local parentGroupIdx = reaper.GetNumTracks()` — always appends at end
- Line ~124: `reaper.InsertTrackAtIndex(parentGroupIdx, true)` — inserts at end
- Line ~129: `reaper.SetMediaTrackInfo_Value(parentGroup, "I_FOLDERDEPTH", 1)` — sets as folder

### Implementation approach
1. At the start of `generateGroups()`, check `reaper.CountSelectedTracks(0)`
2. If >= 1 track selected, capture the first (topmost) with `reaper.GetSelectedTrack(0, 0)`
3. Determine insertion index: find the last child of the selected track (or insert right after it if no children)
4. Ensure selected track has `I_FOLDERDEPTH >= 1`
5. Insert group folder at the calculated index instead of `GetNumTracks()`
6. Adjust `I_FOLDERDEPTH` of the last existing child (if any) to not close the parent folder prematurely

### REAPER API needed
- `reaper.CountSelectedTracks(0)` — check if a track is selected
- `reaper.GetSelectedTrack(0, 0)` — get the selected track
- `reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")` — get track index
- `reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")` — check/set folder state

### Edge cases to handle
- Selected track is already a deeply nested folder → should still work (insert inside)
- Selected track is a container track from another ambiance → should still work
- `I_FOLDERDEPTH` accounting: the last child of the parent group must properly close both the group folder AND maintain the parent folder structure
