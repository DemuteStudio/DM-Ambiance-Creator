# DM Ambiance Creator - Developer Context

## Project Overview

**DM Ambiance Creator** is a sophisticated Lua script for **REAPER** designed to automate the creation of soundscapes and ambiances. It allows users to define hierarchical structures of audio "Folders", "Groups" and "Containers" and generate random placements of audio items on the timeline based on various parameters (intervals, density, pitch/volume randomization, etc.).

*   **Primary Language:** Lua 5.3+ (as used in REAPER)
*   **Framework:** `ReaImGui` (REAPER implementation of Dear ImGui)
*   **Target Platform:** REAPER (Windows/macOS/Linux)
*   **Version:** ~0.15.6-beta (Active Development)

## Architecture

The project follows a modular, hierarchical architecture designed for scalability and maintainability. Monolithic legacy files have been refactored into focused sub-modules organized by responsibility.

### Entry Point
*   **`Scripts/DM_Ambiance Creator.lua`**: The main entry point.
    *   Checks for `ReaImGui` availability.
    *   Sets up `package.path` and initializes the `globals` state table.
    *   Loads and initializes all modular systems via `dofile` and `.initModule(globals)`.
    *   Starts the main `loop()` function which renders the UI and handles REAPER defer cycles.

### Module System
The project uses a structured module system where functional logic is isolated into sub-directories. Compatibility wrappers (`init.lua` and legacy file names) ensure backward compatibility while delegating to the new modular structure.

**Key Directories:**
*   `Scripts/Modules/Audio/Generation/`: Item placement logic, interval modes (Euclidean, Noise, etc.), and track management.
*   `Scripts/Modules/Audio/Waveform/`: Audio data extraction, peak rendering, and interactive waveform editing.
*   `Scripts/Modules/Routing/`: Channel configuration validation and conflict detection/resolution.
*   `Scripts/Modules/UI/`: Modular UI components (Core, Panels, and specialized widgets like `TriggerSection_Noise`).
*   `Scripts/Modules/Utils/`: Shared mathematical, string, validation, and REAPER API utility wrappers.
*   `Scripts/Modules/Export/`: Functionality for exporting generated content.

### Global State (`globals`)
The `globals` table is the central source of truth, passed to every module's `initModule` function. It contains:
*   `items`: The main data structure holding the path-based hierarchy of Folders, Groups, and Containers.
*   `ctx`: The ImGui context.
*   `timeSelectionValid`, `startTime`, `endTime`: Project timeline state.
*   Module references: `globals.Utils`, `globals.Generation`, etc., allowing cross-module calls without circular `require` issues.

## Key Subsystems

### 1. Generation Engine
Managed by `Audio/Generation/` modules:
*   **Interval Modes:** Absolute, Relative, Coverage, Chunk, Euclidean, and Noise.
*   **Placement Logic:** Calculates positions, handles overlaps/collisions, and applies randomizations.
*   **Multi-Channel Support:** Handles Surround (4.0, 5.0, 7.0) routing and track structure.
*   **Regeneration:** Smart auto-regeneration system that updates only what's necessary when parameters change.

### 2. User Interface
Built with `ReaImGui` and organized into `Modules/UI/` and `Modules/Panels/`.
*   **Main Window:** `DM_Ambiance_UI_MainWindow.lua` orchestrates the three-panel layout.
*   **Waveform Editor:** High-performance peak visualization and region slicing.
*   **Undo/Redo History:** Custom implementation with a dedicated visual history window.

### 3. Persistence & History
*   **Presets:** Path-based saving/loading of the entire hierarchy or individual components.
*   **History System:** Snapshot-based undo/redo mechanism tracking all state changes in `globals.items`.

## Development Guidelines

*   **Modularization:** All new features should be added as focused modules within the appropriate sub-directory.
*   **Dependency Injection:** Follow the `initModule(globals)` pattern to share state.
*   **Consistency:** Maintain the naming convention of `Snake_Case` for filenames and `camelCase` for functions.
*   **REAPER API:** Use the wrappers in `Utils_REAPER.lua` for track and item manipulations to ensure consistent behavior.

## Building and Running

1.  **Install REAPER**.
2.  **Install ReaPack** and **ReaImGui** (via ReaPack).
3.  **Run:** Open `Scripts/DM_Ambiance Creator.lua` in REAPER's Action List.

## Directory Structure

```text
DM-Ambiance-Creator/
├── Scripts/
│   ├── DM_Ambiance Creator.lua       # Entry point
│   └── Modules/
│       ├── Audio/
│       │   ├── Generation/           # Placement & Modes
│       │   └── Waveform/             # Audio Visualization
│       ├── Routing/                  # Channel Validation
│       ├── Utils/                    # Shared Helpers
│       ├── UI/                       # Modular Components
│       ├── Export/                   # Extraction Logic
│       └── ...                       # State & Core Modules
├── REFACTORING_PROGRESS.md           # History of the refactoring completion
├── README.md                         # User documentation
└── GEMINI.md                         # This file
```