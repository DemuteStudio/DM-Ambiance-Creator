---
stepsCompleted:
  - step-01-init
  - step-02-discovery
  - step-03-success
  - step-04-journeys
  - step-05-domain-skipped
  - step-06-innovation-skipped
  - step-07-project-type
  - step-08-scoping
  - step-09-functional
  - step-10-nonfunctional
  - step-11-polish
  - step-12-complete
inputDocuments:
  - README.md
  - export-v2-architecture.md
workflowType: 'prd'
classification:
  projectType: desktop_app
  domain: audio_production_creative_tools
  complexity: low
  projectContext: brownfield
  scope: Export v2 feature only
---

# Product Requirements Document - Reaper Ambiance Creator — Export v2

**Author:** Antho
**Date:** 2026-02-05
**Scope:** Export System v2 feature only (not full product PRD)

## Executive Summary

The **Reaper Ambiance Creator** is a REAPER plugin that creates soundscapes by randomly placing audio elements on the timeline. It serves sound designers in both linear (film/TV) and game audio production.

The current Export system (v0.16.0-v0.16.1) is a prototype with critical blockers preventing game audio production use:

1. **Multichannel bug** — Export places the same item on every track instead of applying proper channel distribution
2. **No pool control** — No way to limit unique items exported per container
3. **No loop support** — Containers with negative intervals cannot be exported as seamless loops

**Export v2** resolves these blockers, transforming the tool from linear-only to a complete game audio pipeline tool. Target audience: game sound designers preparing assets for middleware integration (Wwise/FMOD).

**Development context:** Vibecoding with Claude as developer. Antho (sound designer) as product owner and tester.

## Success Criteria

### User Success

- Exported items are immediately ready for render — correct multichannel distribution, proper track routing
- Minimal post-export workflow: name files and integrate into middleware pipeline
- Loop-mode containers export as seamless loops with user-defined duration
- Pool control allows choosing exactly how many unique items to extract per container

### Business Success

- **Unlocks game audio use case** — without this, the tool is limited to linear work only
- Makes the tool viable for professional game audio production
- Directly addresses the creator's own production needs

### Technical Success

- Multichannel distribution identical between Generation and Export (single source of truth)
- Pool control: random subset selection respects max items setting
- Loop processing: zero-crossing detection producing seamless loops
- Loop duration: user-configurable per container (new requirement beyond current architecture)
- No crashes or errors on any container/group configuration

### Measurable Outcomes

- Multichannel export matches Generation engine output
- Exported loops play back seamlessly in a game engine
- Pool selection correctly limits exported items
- 100% of container/group configurations supported

## Product Scope

### Phase 1 — MVP

**Approach:** Problem-solving MVP — resolve core export blockers for game audio production.

**Core User Journeys Supported:** J1 (individual items), J2 (multichannel), J3 (loops), J4 (batch)

| Feature | Rationale |
|---------|-----------|
| Multichannel fix (Generation engine delegation) | Blocker — export broken without this |
| Pool control (max items per container) | Essential — no way to extract unique variations |
| Loop mode (auto/on/off) with duration + interval per container | Essential — beds/textures need seamless loops |
| Per-container parameter overrides in UI | Required to support loop + pool per container |
| Region creation with naming patterns | Already in v1, must be maintained |
| Align to seconds | Simple, high value for render workflow |

**Deferred from MVP:** Live preview in export modal (can export "blind" initially)

### Phase 2 — Growth

- Live preview in export modal (preview data per container before executing)
- Saveable/reusable export presets
- Batch export with pre-registered configurations

### Phase 3 — Vision

- Direct middleware API integration (Wwise/FMOD)

## User Journeys

### Journey 1: Individual Items Export for Middleware

**Persona:** Marco, senior sound designer at a AA studio.

**Opening Scene:** Marco created a "Tropical Forest" ambiance — 4 containers: Bird Chirps, Insects, Rain Drops, Wind Gusts. He needs to extract individual variations for Wwise Random Containers.

**Rising Action:** He opens the Export modal. For "Bird Chirps" (12 items in pool) he sets max pool to 6. For "Rain Drops" he wants all 8. Instance amount 1, spacing 1s, align to seconds enabled. Region pattern: `$group_$container`.

**Climax:** One click — each container's individual items placed correctly on the timeline, each with its own named region. Ready to render.

**Resolution:** 20-30 minutes of manual work reduced to 30 seconds.

### Journey 2: Multichannel Export (Stereo-to-Quad)

**Opening Scene:** Marco has a "Cave" ambiance in quad (4.0) — stereo files routed to channels 1-2 and 3-4. Different items distributed per stereo pair.

**Rising Action:** He selects "Cave Drips", sets max pool to 4.

**Climax:** Each stereo pair receives the correct item — tracks 3-4 get a different item than 1-2, matching normal generation behavior.

**Resolution:** No manual verification needed. Export faithfully reproduces generation engine behavior.

### Journey 3: Seamless Loop Export

**Opening Scene:** Marco has "Forest Bed" with -1s overlap interval, creating a continuous bed. He needs a 30-second loop for Wwise.

**Rising Action:** In the Export modal, per-container parameters show Loop Mode "On" (auto-detected from negative interval). He sets interval to -1s, loop duration to 30s.

**Climax:** The tool generates a 30-second bed with 1s overlaps, then applies zero-crossing split/swap — end connects perfectly to beginning. No clicks or artifacts.

**Resolution:** Render-ready loop for direct Wwise import. No manual crossfade work.

### Journey 4: Batch Multi-Container with Mixed Configurations

**Opening Scene:** Marco finalized "Haunted Forest" — 8 containers. Some individual items, some loops. Mixed multichannel configurations.

**Rising Action:** Per-container config: "Wind Bed" and "Crickets Bed" as loops (30s/20s), 6 others as individual items with varying max pool sizes. Regions enabled. Containers span mono, stereo, quad — each with its own routing.

**Climax:** One Export click. Loops on their tracks, individual items on theirs, named regions, multichannel respected across all configurations.

**Resolution:** Entire ambiance ready for render and middleware import in under a minute.

**Edge Case:** Batch export where every container has a different multichannel configuration (mono, stereo, pure quad, stereo quad, mono quad, 5.0 pure, 5.0 stereo, etc.) — validates all channel configurations in a single pass.

### Journey-to-Capability Traceability

| Capability | Journeys |
|-----------|----------|
| Pool control (max items per container) | J1, J2, J4 |
| Correct multichannel distribution | J2, J4 |
| Loop mode with duration & interval | J3, J4 |
| Per-container export parameters | J3, J4 |
| Region creation with naming patterns | J1, J3, J4 |
| Batch multi-container export | J4 |
| Align to seconds | J1 |
| Mixed multichannel batch | J4 (edge case) |

## Technical Context

### Platform

REAPER plugin/extension in Lua with ReaImGui. Cross-platform (Windows, Mac, Linux) via REAPER's scripting environment. Distributed through ReaPack. 100% offline.

### Architecture Constraints

- Export v2 maintains compatibility with existing module architecture (`Scripts/Modules/Export/`)
- Integrates with REAPER API: MediaItems, MediaTracks, AudioAccessor (zero-crossing), region creation
- Delegates to Generation engine for item placement — shared dependency
- No new external dependencies

### Risk Mitigation

**Loop zero-crossing:** Mitigated — existing REAPER script implements the core single-item algorithm (find zero-crossing near center, split, reposition, crossfade). For Export_Loop: apply to the LAST item in the chain, split at zero-crossing, take right part and move before first item. Fallback: simple trim-to-duration without zero-crossing.

**Multichannel delegation:** Medium risk — requires correct mapping between Export and Generation engine track structures. Mitigation: extensive testing across all channel configurations.

**Vibecoding with Claude:** Code must be modular and well-documented for AI-assisted development sessions. Architecture document provides clear module separation (Settings, Engine, Placement, Loop, UI).

## Functional Requirements

### Item Placement & Multichannel Distribution (J1, J2, J4)

- **FR1:** User can export container items with correct multichannel distribution matching Generation engine output
- **FR2:** User can export containers with any supported channel configuration: mono, stereo, pure quad (4ch source), stereo quad (2x stereo → 1-2/3-4), mono quad (4x mono), 5.0 ITU, 5.0 SMPTE, stereo-based 5.0, mono-based 5.0, 7.0 ITU, 7.0 SMPTE, stereo-based 7.0, mono-based 7.0 — any multichannel format constructable from mono, stereo, or native multichannel source files
- **FR3:** System delegates item placement to Generation engine for channel distribution consistency, while applying export-specific placement logic (spacing, position calculation, align-to-seconds, instance repetition)

### Pool Control (J1, J2, J4)

- **FR4:** User can set a maximum number of items to export per container
- **FR5:** System randomly selects items from the pool when max pool items < total available
- **FR6:** User can export all items in a container's pool (default when max = 0)

### Loop Processing (J3, J4)

- **FR7:** User can enable/disable loop mode per container; containers with negative interval values automatically set to loop mode, overriding global setting
- **FR8:** System auto-detects loop candidacy from negative interval value
- **FR9:** User can define target loop duration in seconds per container
- **FR10:** User can define interval/overlap between items in loop mode per container
- **FR11:** System creates seamless loops using zero-crossing detection for split points
- **FR12:** System splits the last item at nearest zero-crossing and moves right portion before first item to create loop point
- **FR33:** User can see a visual indicator when Loop Interval is set to 0 (auto-mode), clarifying that container-specific intervals will be used

### Export Configuration (J1, J2, J3, J4)

- **FR13:** User can configure export parameters globally (applied to all containers by default)
- **FR14:** User can override global parameters per container; loop auto-detection from negative intervals constitutes automatic override
- **FR15:** User can set instance amount (copies per pool entry)
- **FR16:** User can set spacing between exported instances
- **FR17:** User can align exported positions to whole seconds
- **FR18:** User can choose export method (current track or new track)
- **FR19:** User can preserve or reset pan randomization
- **FR20:** User can preserve or reset volume randomization
- **FR21:** User can preserve or reset pitch randomization

### Container Selection & Batch Export (J4)

- **FR22:** User can select/deselect containers for export with multi-selection (Ctrl+Click toggle, Shift+Click range)
- **FR23:** User can export multiple containers in a single operation
- **FR24:** System handles mixed configurations (different multichannel setups, loop/non-loop) in a single batch

### Region Management (J1, J3, J4)

- **FR25:** User can enable/disable REAPER region creation during export
- **FR26:** User can define region naming patterns using tags ($container, $group, $index)
- **FR27:** System creates one region per container spanning all exported items

### Export UI (J1, J2, J3, J4)

- **FR28:** User can access export through a modal window
- **FR29:** User can see all containers with enable/disable toggles
- **FR30:** User can configure per-container parameters when a container is selected

### Error Handling (J4)

- **FR31:** System continues export for remaining containers if one fails
- **FR32:** System reports errors and warnings per container after completion

## Non-Functional Requirements

### Performance

- **NFR1:** Export of up to 8 containers completes within 30 seconds on a standard workstation
- **NFR2:** Zero-crossing detection per item completes without noticeable delay (AudioAccessor search window ±50ms)
- **NFR3:** Export UI remains responsive during execution (no REAPER freeze)

### Reliability & Stability

- **NFR4:** Export never crashes REAPER regardless of configuration or content
- **NFR5:** Per-container error isolation: one container failure does not affect others in batch
- **NFR6:** Empty containers or missing source files gracefully skipped with warning
