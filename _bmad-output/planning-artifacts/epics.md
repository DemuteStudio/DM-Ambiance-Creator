---
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
  - step-03-create-stories
  - step-04-final-validation
inputDocuments:
  - prd.md
  - export-v2-architecture.md
---

# Reaper Ambiance Creator — Export v2 - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for Reaper Ambiance Creator — Export v2, decomposing the requirements from the PRD and Architecture into implementable stories.

## Requirements Inventory

### Functional Requirements

FR1: User can export container items with correct multichannel distribution matching Generation engine output
FR2: User can export containers with any supported channel configuration (mono, stereo, pure quad, stereo quad, mono quad, 5.0 ITU, 5.0 SMPTE, stereo-based 5.0, mono-based 5.0, 7.0 ITU, 7.0 SMPTE, stereo-based 7.0, mono-based 7.0 — any multichannel format constructable from mono, stereo, or native multichannel source files)
FR3: System delegates item placement to Generation engine for channel distribution consistency, while applying export-specific placement logic (spacing, position calculation, align-to-seconds, instance repetition)
FR4: User can set a maximum number of items to export per container
FR5: System randomly selects items from the pool when max pool items < total available
FR6: User can export all items in a container's pool (default when max = 0)
FR7: User can enable/disable loop mode per container; containers with negative interval values automatically set to loop mode, overriding global setting
FR8: System auto-detects loop candidacy from negative interval value
FR9: User can define target loop duration in seconds per container
FR10: User can define interval/overlap between items in loop mode per container
FR11: System creates seamless loops using zero-crossing detection for split points
FR12: System splits the last item at nearest zero-crossing and moves right portion before first item to create loop point
FR13: User can configure export parameters globally (applied to all containers by default)
FR14: User can override global parameters per container; loop auto-detection from negative intervals constitutes automatic override
FR15: User can set instance amount (copies per pool entry)
FR16: User can set spacing between exported instances
FR17: User can align exported positions to whole seconds
FR18: User can choose export method (current track or new track)
FR19: User can preserve or reset pan randomization
FR20: User can preserve or reset volume randomization
FR21: User can preserve or reset pitch randomization
FR22: User can select/deselect containers for export with multi-selection (Ctrl+Click toggle, Shift+Click range)
FR23: User can export multiple containers in a single operation
FR24: System handles mixed configurations (different multichannel setups, loop/non-loop) in a single batch
FR25: User can enable/disable REAPER region creation during export
FR26: User can define region naming patterns using tags ($container, $group, $index)
FR27: System creates one region per container spanning all exported items
FR28: User can access export through a modal window
FR29: User can see all containers with enable/disable toggles
FR30: User can configure per-container parameters when a container is selected
FR31: System continues export for remaining containers if one fails
FR32: System reports errors and warnings per container after completion
FR33: Loop interval auto-mode (0=use container interval) with UI indicator

### NonFunctional Requirements

NFR1: Export of up to 8 containers completes within 30 seconds on a standard workstation
NFR2: Zero-crossing detection per item completes without noticeable delay (AudioAccessor search window +/-50ms)
NFR3: Export UI remains responsive during execution (no REAPER freeze)
NFR4: Export never crashes REAPER regardless of configuration or content
NFR5: Per-container error isolation: one container failure does not affect others in batch
NFR6: Empty containers or missing source files gracefully skipped with warning

### Additional Requirements

- Migration: Delete Export_Core.lua, replaced by Export_Settings + Export_Engine + Export_Placement + Export_Loop (4 new modules)
- Module init.lua must be updated with new module loading and public API
- Export_UI.lua must be modified to add maxPoolItems, loopMode controls, and preview section
- DM_Ambiance_Constants.lua must be extended with new EXPORT constants (MAX_POOL_ITEMS_DEFAULT, LOOP_MODE_AUTO/ON/OFF/DEFAULT, LOOP_ZERO_CROSSING_WINDOW)
- Generation engine delegation: Export_Placement must call Generation_Modes.determineTrackStructure(), Generation_MultiChannel.analyzeContainerItems(), Generation_MultiChannel.applyChannelSelection(), and Generation_ItemPlacement.placeSingleItem()
- Per-track loop processing: each track in multichannel setup gets independent zero-crossing split/swap
- Zero-crossing detection via REAPER AudioAccessor API with +/-50ms search window; fallback to exact center if no zero-crossing found
- Live preview computation in UI (metadata only, no execution) via Export_Engine.generatePreview()
- Per-container error isolation with collected errors/warnings returned to UI
- No starter template — brownfield project, integrating into existing codebase
- No new external dependencies
- DM_Ambiance_Structures.lua — no changes needed (existing container structure supports all required fields)
- DM_Ambiance_UI_Preset.lua — no changes needed (already calls Export.openModal/renderModal)

### FR Coverage Map

| FR | Epic | Description |
|----|------|-------------|
| FR1 | Epic 1 | Multichannel distribution matching Generation engine |
| FR2 | Epic 1 | All supported channel configurations |
| FR3 | Epic 1 | Generation engine delegation for placement |
| FR4 | Epic 2 | Max items per container setting |
| FR5 | Epic 2 | Random subset selection |
| FR6 | Epic 2 | Export all items (default) |
| FR7 | Epic 3 | Loop mode enable/disable per container |
| FR8 | Epic 3 | Auto-detect loop from negative interval |
| FR9 | Epic 3 | Target loop duration per container |
| FR10 | Epic 3 | Interval/overlap in loop mode per container |
| FR11 | Epic 3 | Seamless loops via zero-crossing |
| FR12 | Epic 3 | Split/swap last item for loop point |
| FR13 | Epic 1 | Global export parameter configuration |
| FR14 | Epic 2 | Per-container parameter overrides |
| FR15 | Epic 1 | Instance amount setting |
| FR16 | Epic 1 | Spacing setting |
| FR17 | Epic 1 | Align to seconds |
| FR18 | Epic 1 | Export method (current/new track) |
| FR19 | Epic 1 | Preserve pan randomization |
| FR20 | Epic 1 | Preserve volume randomization |
| FR21 | Epic 1 | Preserve pitch randomization |
| FR22 | Epic 4 | Multi-selection containers |
| FR23 | Epic 4 | Batch export operation |
| FR24 | Epic 4 | Mixed configurations in single batch |
| FR25 | Epic 4 | Region creation toggle |
| FR26 | Epic 4 | Region naming patterns |
| FR27 | Epic 4 | One region per container |
| FR28 | Epic 1 | Export modal window |
| FR29 | Epic 2 | Container list with toggles |
| FR30 | Epic 2 | Per-container parameter UI |
| FR31 | Epic 4 | Continue on container failure |
| FR32 | Epic 4 | Error/warning reporting per container |
| FR33 | Epic 4 | Loop interval auto-mode with UI indicator |

## Epic List

### Epic 1: Export Foundation & Multichannel Fix
User can export individual container items with correct multichannel distribution through the Export modal, using the new module architecture that delegates to the Generation engine.
**FRs covered:** FR1, FR2, FR3, FR13, FR15, FR16, FR17, FR18, FR19, FR20, FR21, FR28

### Epic 2: Pool Control & Per-Container Configuration
User can limit the number of items exported per container via random subset selection, and configure different export parameters per container through the UI.
**FRs covered:** FR4, FR5, FR6, FR14, FR29, FR30

### Epic 3: Seamless Loop Export
User can export containers with negative intervals as seamless loops ready for game audio middleware, with configurable duration and zero-crossing-based split/swap processing.
**FRs covered:** FR7, FR8, FR9, FR10, FR11, FR12

### Epic 4: Batch Export, Regions & Error Resilience
User can batch-export multiple containers with mixed configurations in a single operation, create named REAPER regions, and receive reliable per-container error reporting.
**FRs covered:** FR22, FR23, FR24, FR25, FR26, FR27, FR31, FR32, FR33

## Epic 1: Export Foundation & Multichannel Fix

User can export individual container items with correct multichannel distribution through the Export modal, using the new module architecture that delegates to the Generation engine.

### Story 1.1: Module Architecture & Settings Management

As a **game sound designer**,
I want **a properly structured export system with configurable global parameters**,
So that **I have a reliable foundation for export with consistent, validated settings**.

**Acceptance Criteria:**

**Given** the plugin is loaded
**When** the Export module initializes
**Then** Export_Settings, Export_Engine, and Export_Placement modules are loaded via updated init.lua
**And** Export_Core.lua is no longer referenced or required

**Given** the export modal is opened
**When** the settings state is initialized
**Then** globalParams contains all parameters with correct defaults: instanceAmount=1, spacing=1.0, alignToSeconds=true, exportMethod=0, preservePan=true, preserveVolume=true, preservePitch=true, maxPoolItems=0, loopMode="auto", createRegions=false, regionPattern="$container"

**Given** a user sets instanceAmount to 150
**When** validation runs
**Then** the value is clamped to 100 (INSTANCE_MAX)
**And** spacing is clamped to [0, 60], maxPoolItems to [0, pool size]

**Given** DM_Ambiance_Constants.lua is loaded
**When** Export constants are accessed
**Then** all new constants are available: MAX_POOL_ITEMS_DEFAULT, LOOP_MODE_AUTO, LOOP_MODE_ON, LOOP_MODE_OFF, LOOP_MODE_DEFAULT, LOOP_ZERO_CROSSING_WINDOW

**Given** the module is initialized
**When** collectAllContainers() is called
**Then** all containers from globals.items hierarchy are returned with path, key, and displayName

**FRs:** FR13, FR15, FR16, FR17, FR18, FR19, FR20, FR21

### Story 1.2: Multichannel Item Placement via Generation Engine

As a **game sound designer**,
I want **exported items to have correct multichannel channel distribution identical to the Generation engine**,
So that **my exported audio has proper channel routing ready for Wwise/FMOD integration**.

**Acceptance Criteria:**

**Given** a container with stereo items routed to a quad (4.0) track structure (channels 1-2 and 3-4)
**When** the container is exported
**Then** each stereo pair receives the correct item — tracks 3-4 get a different item than tracks 1-2, matching Generation engine behavior

**Given** a container with any supported channel configuration (mono, stereo, pure quad, stereo quad, mono quad, 5.0 ITU/SMPTE, 7.0 ITU/SMPTE, or any stereo/mono-based variant)
**When** the container is exported
**Then** Export_Placement delegates to Generation_Modes.determineTrackStructure() and Generation_MultiChannel.analyzeContainerItems() for correct channel mapping
**And** placeSingleItem() is called with the real track index from trackStructure, not a loop counter

**Given** a container with 8 items and instanceAmount=1, spacing=1.0s, alignToSeconds=true
**When** export is performed
**Then** items are placed sequentially with 1s spacing, positions aligned to whole seconds
**And** each item's position is calculated correctly accounting for spacing and alignment

**Given** a container with preservePan=false
**When** export is performed
**Then** pan randomization is reset on exported items
**And** volume and pitch preserve/reset respect their respective settings independently

**FRs:** FR1, FR2, FR3

### Story 1.3: Export Modal UI Integration

As a **game sound designer**,
I want **to access the export through a modal window with visible global parameters**,
So that **I can configure and execute exports through a clear interface**.

**Acceptance Criteria:**

**Given** the user has containers in their project
**When** the Export modal is opened
**Then** the modal displays all global parameters (instanceAmount, spacing, alignToSeconds, exportMethod, preservePan/Vol/Pitch)
**And** the modal uses Export_Settings for state management

**Given** the user configures global parameters and clicks Export
**When** performExport is called
**Then** Export_Engine orchestrates the export using Export_Settings.getEffectiveParams() and Export_Placement.placeContainerItems()
**And** export results (success/errors) are reported back to the UI

**Given** an export is executed on a single container
**When** the export completes
**Then** items are correctly placed on the timeline with the configured parameters
**And** the user can immediately see the exported items in REAPER

**FR:** FR28

## Epic 2: Pool Control & Per-Container Configuration

User can limit the number of items exported per container via random subset selection, and configure different export parameters per container through the UI.

### Story 2.1: Pool Control (Max Items & Random Subset)

As a **game sound designer**,
I want **to limit the number of unique items exported per container**,
So that **I can extract exactly the number of variations I need for my Wwise/FMOD Random Containers**.

**Acceptance Criteria:**

**Given** a container with 12 items in its pool and maxPoolItems set to 6
**When** the export is performed
**Then** exactly 6 items are exported, randomly selected from the full pool
**And** a different random subset is selected each time export is run

**Given** a container with 8 items and maxPoolItems set to 0 (default)
**When** the export is performed
**Then** all 8 items are exported

**Given** a container with 5 items and maxPoolItems set to 10
**When** validation runs
**Then** maxPoolItems is clamped to 5 (total pool size)
**And** all 5 items are exported

**Given** a container with waveformAreas (multiple areas per item)
**When** resolvePool is called
**Then** pool entries include all areas across all items
**And** maxPoolItems applies to the total entry count (items x areas)

**Given** the Export modal is open
**When** the user adjusts Max Pool Items
**Then** the UI displays the ratio (e.g., "6 / 12 available" or "All (8)" when 0)

**FRs:** FR4, FR5, FR6

### Story 2.2: Per-Container Parameter Overrides & Container List UI

As a **game sound designer**,
I want **to see all my containers with toggles and configure different export parameters per container**,
So that **I can fine-tune each container's export settings independently (e.g., different pool sizes for different containers)**.

**Acceptance Criteria:**

**Given** the Export modal is open
**When** the container list is displayed
**Then** all containers from the project are listed with enable/disable checkboxes
**And** all containers are enabled by default

**Given** a container is selected in the container list
**When** the per-container override section is displayed
**Then** the user can override any global parameter for that specific container
**And** overridden values are visually distinct from global defaults

**Given** a container has maxPoolItems overridden to 4 and global maxPoolItems is 0
**When** getEffectiveParams(containerKey) is called
**Then** the returned params have maxPoolItems=4 (override wins)
**And** all other params use global values

**Given** a container has no overrides set
**When** getEffectiveParams(containerKey) is called
**Then** all global parameter values are returned unchanged

**Given** multiple containers are displayed in the list
**When** a container is disabled (unchecked)
**Then** that container is excluded from export
**And** its per-container overrides are preserved for re-enabling

**FRs:** FR14, FR29, FR30

## Epic 3: Seamless Loop Export

User can export containers with negative intervals as seamless loops ready for game audio middleware, with configurable duration and zero-crossing-based split/swap processing.

### Story 3.1: Loop Mode Configuration & Auto-Detection

As a **game sound designer**,
I want **to enable loop mode per container with auto-detection for negative intervals, and configure loop duration and overlap**,
So that **my bed/texture containers are automatically recognized as loops and I can define the exact loop length I need**.

**Acceptance Criteria:**

**Given** a container with triggerRate < 0 and intervalMode == ABSOLUTE, and global loopMode set to "auto"
**When** resolveLoopMode is called
**Then** the function returns true (loop mode enabled)
**And** the UI shows a visual indicator "(auto)" next to the loop checkmark

**Given** a container with triggerRate > 0 (positive interval) and global loopMode set to "auto"
**When** resolveLoopMode is called
**Then** the function returns false (loop mode disabled)

**Given** global loopMode set to "on"
**When** resolveLoopMode is called for any container
**Then** the function returns true regardless of the container's interval value

**Given** global loopMode set to "off"
**When** resolveLoopMode is called for any container
**Then** the function returns false regardless of the container's interval value

**Given** a container with loop mode resolved to true
**When** the per-container override section is displayed
**Then** the user can set loopDuration in seconds (e.g., 30s)
**And** the user can set interval/overlap between items (e.g., -1s for 1s overlap)

**Given** a container with loopMode overridden to "on" per container while global is "off"
**When** resolveLoopMode is called with the container's effective params
**Then** the function returns true (per-container override wins)

**FRs:** FR7, FR8, FR9, FR10

### Story 3.2: Zero-Crossing Loop Processing (Split/Swap)

As a **game sound designer**,
I want **exported loops to be seamless with no clicks or artifacts at the loop point**,
So that **my loops play back perfectly in Wwise/FMOD without manual crossfade work**.

**Acceptance Criteria:**

**Given** a container in loop mode with placed items on a single track
**When** processLoop is called
**Then** the last item is identified, its center point calculated
**And** findNearestZeroCrossing searches within +/-50ms (LOOP_ZERO_CROSSING_WINDOW) of the center using AudioAccessor_GetSamples
**And** the item is split at the nearest zero-crossing point
**And** the right portion is moved to position: firstItem.position - rightPart.length

**Given** a multichannel container in loop mode with items on multiple tracks
**When** processLoop is called
**Then** items are grouped by track
**And** split/swap is applied independently per track
**And** each track's loop point is processed with its own zero-crossing detection

**Given** a container in loop mode where no zero-crossing is found within the search window
**When** findNearestZeroCrossing is called
**Then** the function falls back to the exact center of the item
**And** a warning is generated for the user

**Given** a container in loop mode with only 1 item
**When** processLoop is called
**Then** loop processing is skipped
**And** a warning is generated: "Need at least 2 items for meaningful loop"

**Given** a container in loop mode with very short items
**When** findNearestZeroCrossing is called
**Then** the search window is reduced proportionally to avoid exceeding item bounds

**FRs:** FR11, FR12

## Epic 4: Batch Export, Regions & Error Resilience

User can batch-export multiple containers with mixed configurations in a single operation, create named REAPER regions, and receive reliable per-container error reporting.

### Story 4.1: Multi-Container Selection & Batch Export

As a **game sound designer**,
I want **to select multiple containers and export them all in one click, even with mixed configurations**,
So that **I can prepare an entire ambiance (loops + individual items + different multichannel setups) for middleware import in under a minute**.

**Acceptance Criteria:**

**Given** the Export modal container list is displayed
**When** the user Ctrl+Clicks on a container
**Then** that container's selection is toggled (selected/deselected) without affecting other selections

**Given** the Export modal container list is displayed
**When** the user Shift+Clicks on a container
**Then** all containers between the last selected and the clicked container are selected (range selection)

**Given** 8 containers are enabled with mixed configurations: 2 in loop mode, 6 as individual items, spanning mono/stereo/quad
**When** the user clicks Export
**Then** performExport iterates over all enabled containers in sequence
**And** each container is processed with its own effective params (loop/non-loop, multichannel config, pool size)
**And** all containers are exported successfully in a single operation

**Given** a batch export with 4 containers where container 2 has loop mode and container 4 is stereo quad
**When** the export completes
**Then** container 2's items are loop-processed (split/swap)
**And** container 4's items have correct stereo quad distribution
**And** all containers' items are placed on the timeline without overlap between containers

**FRs:** FR22, FR23, FR24

### Story 4.2: Region Creation with Naming Patterns

As a **game sound designer**,
I want **REAPER regions automatically created for each exported container with customizable naming**,
So that **I can render each container's export separately using REAPER's region render and files are already named for middleware import**.

**Acceptance Criteria:**

**Given** createRegions is enabled in export settings
**When** a container is exported
**Then** a REAPER region is created spanning from the first exported item's position to the end of the last exported item

**Given** regionPattern is set to "$group_$container"
**When** a region is created for container "Bird Chirps" in group "Tropical Forest"
**Then** the region is named "Tropical Forest_Bird Chirps"

**Given** regionPattern is set to "$container_$index"
**When** regions are created for a batch of 3 containers
**Then** regions are named with incrementing index: "Rain_1", "Wind_2", "Thunder_3"

**Given** regionPattern uses the tag "$container" (default)
**When** a region is created
**Then** the region name matches the container's display name

**Given** createRegions is disabled
**When** an export is performed
**Then** no REAPER regions are created

**FRs:** FR25, FR26, FR27

### Story 4.3: Per-Container Error Isolation & Reporting

As a **game sound designer**,
I want **export to continue even if one container fails, and get a clear report of what happened**,
So that **a single problematic container doesn't waste my entire export and I know exactly what to fix**.

**Acceptance Criteria:**

**Given** a batch export of 5 containers where container 3 encounters an error (e.g., missing source file)
**When** the export processes container 3
**Then** the error is caught and recorded
**And** export continues with containers 4 and 5
**And** containers 1, 2, 4, 5 are exported successfully

**Given** a batch export completes with mixed results
**When** the results are displayed in the UI
**Then** successful containers show a success indicator
**And** failed containers show the specific error message
**And** containers with warnings (e.g., empty pool, loop fallback) show warning details

**Given** a container with an empty pool (no items)
**When** the export attempts to process it
**Then** the container is gracefully skipped
**And** a warning is recorded: "Empty container skipped"

**Given** a container where a source file is missing
**When** the export attempts to process it
**Then** the container is skipped with an error
**And** the error message identifies the missing source

**FRs:** FR31, FR32

### Story 4.4: Loop Interval Auto-Mode UI Indicator

As a **game sound designer**,
I want **the export modal to clearly indicate when Loop Interval is in "auto" mode (value=0) and will use each container's own overlap setting**,
So that **I understand exactly what interval will be applied to each autoloop container, avoiding confusion between the displayed "0" and the actual behavior**.

**Context:** When exporting loop containers, the Loop Interval parameter controls the overlap between items. A value of 0 means "auto-mode" — each container uses its own `triggerRate` value. However, the current UI shows "0" without explaining this semantic, creating ambiguity for users who don't know that 0 has special meaning.

**Acceptance Criteria:**

**Given** the global Loop Interval field in the Export modal
**When** the value is set to 0
**Then** a helper text "(auto: uses container intervals)" is displayed next to the field
**And** the helper text is visually distinct (e.g., greyed/disabled style) to indicate it's informational

**Given** a container's per-container override section
**When** the loopInterval override is set to 0
**Then** the same "(auto: uses container intervals)" indicator is displayed

**Given** the global Loop Interval is set to 0 and a container has `triggerRate = -1.5` (autoloop with 1.5s overlap)
**When** the export runs for that container
**Then** the container uses its own triggerRate (-1.5s) as the effective interval
**And** items are placed with 1.5s overlap

**Given** the global Loop Interval is set to a non-zero value (e.g., -2.0)
**When** the export runs for any autoloop container
**Then** all autoloop containers use the global value (-2.0s) regardless of their individual triggerRate
**And** the UI does NOT show the "(auto)" indicator since a specific value is set

**Given** multiple containers with different triggerRate values (-0.5s, -1.0s, -2.0s) and global loopInterval = 0
**When** batch export runs
**Then** each container uses its own triggerRate as interval
**And** the user can see in the per-container preview what interval will be applied (future enhancement)

**FRs:** FR33
**Journey:** J3 (Seamless Loop Export) — clarifies loop configuration UX

## Epic 5: Bug Fixes (Post-Implementation)

Critical bug fixes discovered after Export v2 implementation. These bugs affect core export functionality and must be resolved before production use.

### Story 5.1: Export Track Hierarchy Creation

As a **game sound designer**,
I want **the export to create the proper track hierarchy (folder + channel tracks) when exporting a preset that hasn't been generated yet**,
So that **I can export directly from a loaded preset without having to generate the ambiance first**.

**Acceptance Criteria:**

**Given** a preset is loaded with a multichannel container but no tracks exist in REAPER
**When** the user exports with exportMethod = 1 (New Track)
**Then** the export creates a folder track with child channel tracks matching the container's configuration
**And** track routing is configured correctly (sends to parent with proper channel mapping)

**Given** a container with channelTrackGUIDs pointing to non-existent tracks
**When** the user exports with exportMethod = 0 (Current Track)
**Then** the export falls back to creating the proper track hierarchy

**Bug:** Export creates flat tracks instead of folder hierarchy when preset is loaded without generation
**Root Cause:** `Export_Placement.resolveTargetTracks()` uses simple `createExportTrack()` instead of `Generation_TrackManagement.createMultiChannelTracks()`

### Story 5.2: Export Multichannel Item Distribution

As a **game sound designer**,
I want **the export to place different items on each channel track when exporting multichannel containers**,
So that **my exported multichannel audio has varied content per channel, matching Generation engine behavior**.

**Acceptance Criteria:**

**Given** a 4.0 quad container with stereo source items and round-robin distribution
**When** the container is exported
**Then** each stereo track pair (L-R, Ls-Rs) receives a DIFFERENT item from the pool

**Given** a multichannel container with random distribution mode
**When** the container is exported
**Then** each track receives a randomly selected item (not deterministically the same)

**Given** a container where trackStructure.useSmartRouting = true
**When** the container is exported
**Then** the SAME item is placed on all tracks (channel extraction from multichannel source)

**Bug:** Same item placed on ALL channel tracks instead of distributing different items
**Root Cause:** `placeContainerItems()` uses same `itemData` for all tracks in the loop
**Regression:** Should have been fixed in Story 1.2

### Story 5.3: Loop Overlap After Split/Swap

As a **game sound designer**,
I want **loop split/swap processing to maintain consistent overlap between ALL items including the repositioned piece**,
So that **my seamless loops have uniform spacing throughout**.

**Acceptance Criteria:**

**Given** a loop export with loopInterval = -1.5s (1.5s overlap)
**When** split/swap is performed
**Then** the second item is positioned with the same -1.5s overlap relative to the moved right part

**Given** a multichannel loop export
**When** split/swap is performed
**Then** each track maintains its own consistent overlap using the same interval value

**Given** a loop where the right part is very short (< overlap amount)
**When** split/swap is performed
**Then** maximum possible overlap is applied and a warning is generated

**Bug:** After split/swap, moved piece is adjacent to second item with NO overlap
**Root Cause:** `splitAndSwap()` calculates `newPosition = firstItemPos - rightPartLen` without adding overlap
