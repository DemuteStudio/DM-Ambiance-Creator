# Story 5.1: Export Track Hierarchy Creation

Status: review

## Story

As a **game sound designer**,
I want **the export to create the proper track hierarchy (folder + channel tracks) when exporting a preset that hasn't been generated yet**,
So that **I can export directly from a loaded preset without having to generate the ambiance first, and get the same multichannel track structure**.

## Context

When a preset is loaded but the ambiance hasn't been generated in the session (no tracks exist in REAPER), the export currently creates simple flat tracks instead of the proper folder hierarchy with channel tracks. This forces users to generate the ambiance first before exporting, which is an unnecessary workflow step.

The Generation engine already has robust track hierarchy creation via `Generation_TrackManagement.createMultiChannelTracks()`. The export should leverage this same system.

## Acceptance Criteria

1. **Given** a preset is loaded with a multichannel container (e.g., 4.0 quad) but no tracks exist in REAPER
   **When** the user exports with `exportMethod = 1` (New Track)
   **Then** the export creates a folder track with child channel tracks matching the container's channel configuration
   **And** the track names follow the pattern "ContainerName - ChannelLabel" (e.g., "Birds - L", "Birds - R", "Birds - Ls", "Birds - Rs")

2. **Given** a preset is loaded with a stereo container using mono items (mono split scenario)
   **When** the user exports
   **Then** the export creates separate L/R tracks under a folder if the Generation engine would do so
   **And** items are correctly distributed to L and R tracks

3. **Given** a container with `channelTrackGUIDs` that point to non-existent tracks
   **When** the user exports with `exportMethod = 0` (Current Track)
   **Then** the export falls back to creating the proper track hierarchy instead of simple tracks

4. **Given** a standard stereo container (channelMode = 0 or nil)
   **When** the export creates tracks
   **Then** a single stereo track is created (no folder hierarchy needed)

5. **Given** the export creates a multichannel track hierarchy
   **When** the export completes
   **Then** channel track routing is configured correctly (sends to parent with proper channel mapping)
   **And** the container's `trackGUID` and `channelTrackGUIDs` are updated for future exports

## Tasks / Subtasks

- [x] Task 1: Refactor resolveTargetTracks() to use Generation track creation (AC: #1, #2)
  - [x] 1.1: Add check for when track hierarchy creation is needed (no existing tracks found)
  - [x] 1.2: Call `Generation_TrackManagement.createMultiChannelTracks()` or equivalent logic
  - [x] 1.3: Ensure proper folder depth settings (folder parent, children, closing track)
  - [x] 1.4: Configure channel routing (sends to parent track with correct channel mapping)

- [x] Task 2: Handle GUID fallback scenarios (AC: #3)
  - [x] 2.1: Detect when channelTrackGUIDs point to non-existent tracks
  - [x] 2.2: Trigger track hierarchy creation as fallback

- [x] Task 3: Store GUIDs after track creation (AC: #5)
  - [x] 3.1: Update container.trackGUID with folder track GUID
  - [x] 3.2: Update container.channelTrackGUIDs with child track GUIDs

- [x] Task 4: Handle stereo containers correctly (AC: #4)
  - [x] 4.1: Ensure stereo containers (channelMode = 0) don't create unnecessary hierarchy

## Dev Notes

### Key Files to Modify

- **Export_Placement.lua** - Main changes in `resolveTargetTracks()` and `createExportTrack()`
- **Export_Engine.lua** - May need to pass additional context for track creation

### Reference Implementation

The Generation engine's track creation logic is in:
- [Generation_TrackManagement.lua:20-267](../../../Scripts/Modules/Audio/Generation/Generation_TrackManagement.lua#L20-L267) - `createMultiChannelTracks()`

Key patterns to replicate:
1. Analyze items with `Generation_MultiChannel.analyzeContainerItems()`
2. Determine track structure with `Generation_Modes.determineTrackStructure()`
3. Create folder track with `I_FOLDERDEPTH = 1`
4. Create child tracks, configure routing, set last child `I_FOLDERDEPTH = -1`

### Architecture Consideration

Two approaches possible:
1. **Direct call**: Export calls `Generation_TrackManagement.createMultiChannelTracks()` directly
2. **Shared utility**: Extract common logic to a shared utility module

Recommend approach #1 for simplicity since Generation module is already a dependency.

### Track Routing Pattern

For stereo tracks in quad:
```lua
-- Track 1 (L-R) → channels 1-2 (destChannel = 0)
-- Track 2 (Ls-Rs) → channels 3-4 (destChannel = 2)
srcChannels = 0  -- Stereo from source
dstChannels = (trackIndex - 1) * 2  -- Stereo pair position
```

For mono tracks:
```lua
srcChannels = 1024  -- Mono mode
dstChannels = 1024 + (channelNumber - 1)  -- Mono to specific channel
```

### Testing Scenarios

1. Load preset with 4.0 quad container, export without generating first
2. Load preset with stereo container using mono items, export
3. Load preset, generate, delete tracks manually, export again
4. Load preset with stereo-only containers, verify no folder created

### References

- [Source: Export_Placement.lua#resolveTargetTracks](../../../Scripts/Modules/Export/Export_Placement.lua#L115-L194)
- [Source: Generation_TrackManagement.lua#createMultiChannelTracks](../../../Scripts/Modules/Audio/Generation/Generation_TrackManagement.lua#L20-L267)
- [Source: Story 1.2 - Multichannel Item Placement](./1-2-multichannel-item-placement.md)

## Dev Agent Record

### Agent Model Used

Claude Opus 4.5 (claude-opus-4-5-20251101)

### Debug Log References

N/A - No debug issues encountered during implementation.

### Completion Notes List

1. **Task 1 Complete**: Created `createExportTrackHierarchy()` function that delegates to Generation engine's `createMultiChannelTracks()` for proper track hierarchy creation. The function analyzes container items to determine track structure and creates folder + channel tracks when needed.

2. **Task 2 Complete**: Modified `resolveTargetTracks()` to detect when GUIDs point to non-existent tracks. Uses `allTracksFound` flag to track GUID validity. Falls through to hierarchy creation if any GUID is invalid.

3. **Task 3 Complete**: GUIDs are stored automatically by `createMultiChannelTracks()` via its internal call to `storeTrackGUIDs()`. For stereo containers, the trackGUID is stored directly in `createExportTrackHierarchy()`.

4. **Task 4 Complete**: Stereo containers (channelMode = 0) are handled via track structure analysis. If `trackStructure.numTracks == 1`, a simple stereo track is created without folder hierarchy.

5. **Architecture Decision**: Used approach #1 (Direct call) as recommended in Dev Notes. Export directly calls `globals.Generation.createMultiChannelTracks()` for consistency with Generation engine behavior.

### File List

- Scripts/Modules/Export/Export_Placement.lua (modified)
  - Added `createExportTrackHierarchy()` function (lines 75-126)
  - Added `needsTrackHierarchy()` helper function (lines 170-187)
  - Refactored `resolveTargetTracks()` (lines 189-284)
  - Updated version to 1.10 with changelog

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2026-02-06 | Initial implementation of Story 5.1 - Export track hierarchy creation | Claude Opus 4.5 |
