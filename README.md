# Reaper Ambiance Creator

<img width="3120" height="794" alt="image" src="https://github.com/user-attachments/assets/4746d89e-a3f0-4584-b4a7-390556b84935" />



The **Ambiance Creator** is a tool that makes it easy to create soundscapes by randomly placing audio elements on the REAPER timeline according to user parameters.

We wanted to make ambiance creation and preview for games and linear content as easy and efficient as possible. Here are the main pillars for this tool:

- **Fast creation**: Creating ambiances can be tedious, time-consuming, and repetitive. The idea here is to build a complete ambiance in just a few seconds.
- **Iteration**: Iterating on an ambiance should be as easy as drinking a glass of water.
- **Reusability**: We wanted to be able to save creations as presets.
- **Modularity**: Each part of the ambiance should exist as a separate module that can be reused later.
- **Not context-dependent**: The tool should be useful for both linear and video game workflows.

## Video Tutorial

[I'm a video link](https://www.youtube.com/watch?v=aU6pfuM3aPQ)

## Installing the Ambiance Creator

### Requirements

- **Reaper**: The package was made for Reaper 7.39+ but should work with older versions as well.
- **ReaPack**: Used to import the package into Reaper.
- **ReaImGui**: Used for the whole interface. It's included in the ReaTeam Extensions package, which you can install with ReaPack. To check if it's installed, you should see a ReaImGui tab under the ReaScript tab in Preferences: **Options > Preferences > Plug-ins > ReaImGui**.

### Reapack:
To install Reapack follow these steps:
1. Download Reapack for your platform here(also the user Guide): [Reapack Download](https://reapack.com/user-guide#installation)
2. From REAPER: **Options > Show REAPER resource path in explorer/finder**
3. Put the downloaded file in the **UserPlugins** subdirectory
4. Restart REAPER. Done!

If you have Reapack installed go to **Extensions->Reapack->Import Repositories** paste the following link there and press **Ok**.

--> https://github.com/DemuteStudio/DM-Ambiance-Creator/raw/main/index.xml

Then in **Extensions->Reapack->Manage repositories** you should see **Ambiance Creator** double click it and then press **Install/update Ambiance Creator** and choose **Install all packages in this repository**. It should Install without any errors.

To install **ReaImGui**, find **ReaTeam Extensions** in Manage repositories. Then if you only want ReaImGui Choose **Install individual packages in this repository** and find ReaImGui.



## General Overview

<img width="1516" height="555" alt="image" src="https://github.com/user-attachments/assets/0b22c6b9-cc6b-48f2-bfba-ff3a537b3f37" />


The interface is divided into three main sections:

1. **Global section**: This is where you manage global presets, settings, and generate the whole ambiance.
2. **Groups and containers section**: This is where you organize your Groups and Containers.
3. **Parameters section**: This is where you tweak the parameters of Groups and Containers.

The tool works by defining "Groups" that contain "Containers," which group audio elements that will be randomly placed according to your parameters.
This may change in the future to be even more abstract (because who doesn’t love abstraction?).


## Creating/Editing Ambiances in the Ambiance Creator

The very first step is to create your own containers database. The idea is to build a collection of modules (containers) that can be reused over and over. There’s no “right way” to organize groups and containers, but here’s a suggestion.

Let’s say you want to create a Winter Forest. There are lots of different forest types, but all forests are made of two things: fauna and flora. Let’s break these down further:
- Fauna: Birds, Insects, Canidae, ...
- Flora: Leaves, Branches, Grass, Bushes, ...

You might also want to add a third generic category:
- Winds: Strong, Soft, Howling, Gust, ...

Now that we’ve divided our forest into smaller categories, let’s create our first group:
- Press the "Add group" button.
- Name the newly created group "Birds".
  
<img width="1434" height="508" alt="image" src="https://github.com/user-attachments/assets/3983519d-63f1-4d3b-a521-ee75063c733a" />

We'll discuss the parameters later, let’s focus on containers for now.
- In the Birds group, press the "Add containers" button to create your first container.
- Name it "Birds - Generic Bed Chirps".

<img width="1310" height="218" alt="image" src="https://github.com/user-attachments/assets/8e8c278f-13c2-4373-839c-3dd87710d998" />

*IMPORTANT NOTE: The following steps are needed only once per new container.*

Now that we have the beginning of a hierarchy, we need to create the assets that will be used to build the ambiance. So let’s find our best generic bird chirps sound and add them into the session.

<img width="873" height="322" alt="image" src="https://github.com/user-attachments/assets/ef333b9f-20b3-4ca3-8627-f532619a643e" />

Here I took a nice generic bed of birds. The file is 1'40 long. I could keep it as one single file, but I chose to split it into 10 parts—you’ll see why later.
Select your items and make sure that the "Birds - Generic Bed Chirps" container is also selected, then press "Import Selected Items" in the right panel.

You should now see all the imported items in the list:

<img width="354" height="301" alt="image" src="https://github.com/user-attachments/assets/c94b8cbb-63a4-4a00-876e-a54a71ae0966" />

**Save Presets**
---
Depending on your workflow, this might be a good moment to save this container. You haven’t set any parameters yet, but it contains files that can be recalled and tweaked later.

Let’s see how the preset system works.

When you save a preset, the path of the imported files is saved. By default, Reaper imports your media items into a 'Media Files' directory, located at the project’s root. This means that by default, the item’s path is this directory.
It’s not a problem. BUT! If you delete this folder or the entire project folder, the reference to the item will be lost.
In the Settings, you can choose a Media Item Directory. By default, this field is empty. Once you set a location, all media files will be copied to this directory when you save a preset (if they don’t already exist). This means you’ll have all your file references in the same place. Convenient!

<img width="465" height="429" alt="image" src="https://github.com/user-attachments/assets/0043f665-ac45-4a10-98f8-b405881dacf8" />

Now that you’ve set up your *Media File Directory*, it’s time to press the "Save Container" button.
By default, it will be named as the container. Feel free to change the name as you wish.

<img width="1063" height="652" alt="image" src="https://github.com/user-attachments/assets/defa5aff-ae17-4513-82c5-33f7e3213daa" />

*Note: You can find all your preset files into a dedicated folder accessible by pressing the "Open Preset Directory" button.*

If you work in a team and everyone uses the same directory, it means the preset can be shared and used by anyone with access to this shared directory.

*Note again: It’s not planned to create a customizable "Preset Directory" because it means anyone could delete/override a shared preset. It’s better to keep presets user-side. Share them carefully.*

**Parameters**
---

Now it’s time to customize our container. If you’re familiar with audio middleware, it’s the same logic.
The concept is to define some parameters to give a specific behavior to a container.
Both Groups and Containers have parameters. Containers inherit from their parent group by default.
Depending on the nature of your group, it can be good practice to first set a global rule for trigger and random settings.
But for now, let’s create some specific behavior for our bed of birds.

Select the "Birds - Generic Bed Chirps" container and check the "Override Parent Settings" box. The parameters will appear.

<img width="1063" height="652" alt="image" src="https://github.com/user-attachments/assets/8f3f8359-3f94-4180-981f-0b614b8e04d6" />

Here is a quick explanation of each parameters:

**Trigger Settings**
- Interval Mode: Choice between Absolute, Relative, or Coverage
- Absolute: Fixed interval in seconds (can be negative to create overlaps)
- Relative: Interval expressed as a percentage of the time selection
- Coverage: Percentage of the time selection to fill
- Interval: Time interval between sounds (in seconds or percentage depending on the mode)
- Random variation (%): Percentage of random variation applied to the interval

**Randomize Parameters**
- Randomize Pitch: Enables pitch randomization
- Pitch Range: Variation range in semitones (e.g., -3 to +3)
- Randomize Volume: Enables volume randomization
- Volume Range: Variation range in dB (e.g., -3 to +3)
- Randomize Pan: Enables pan randomization
- Pan Range: Variation range from -100 to +100


The tool is meant to create ambiances of any length. If the total length is 20 minutes but your file is only 1 minute long, it will be copied 20 times.
If you remember, I split the 1'40 long file into 10 pieces. Let’s roll 2d20 and take advantage of that.

Choose the "Absolute" mode and set the interval to a negative value. This value will be the length of the overlap between each item. Let’s say we want a 1-second overlap, so set the interval to -1 second.
We don’t need any variation for this value, so set it to 0%.

Pitch and Volume are up to you. I’ll leave these at their default values.
However, since our bed is supposed to be the foundation of the ambiance, let’s disable random pan.

Your container should look like this:

<img width="1063" height="652" alt="image" src="https://github.com/user-attachments/assets/37f80daf-74b1-4fd4-a5e0-0b360d5c679b" />

You can save the container as a preset now if you wish. Keep in mind that with the same preset name, the previous one will be overwritten. Feel free to rename it if you want to have both a raw and a tweaked version.

Now it’s time to test these parameters.
Create a time selection on the Reaper timeline of the desired size.
You’ll see that the previous "No time selection, please create one" message has turned into a "Create Ambiance" button with an option next to it.
We’ll discuss this option in a second. Press the "Create Ambiance" button.

<img width="2081" height="454" alt="image" src="https://github.com/user-attachments/assets/7e3957f3-7aa1-4f41-a2ff-bafa6dfe2d0c" />

Congratulation ! You’ve created your first bed with the tool o//

You’ll notice that the track structure matches the Group/Container.
Each item are placed randomly, overlaps the next with a 1-second crossfade, and the last item has been trimmed precisely at the end of the time selection.

Each item has its own pitch and volume.

<img width="795" height="90" alt="image" src="https://github.com/user-attachments/assets/4396f9f1-8be7-41c5-bcc2-40539b504cbd" />

If you're not satisfied with the result, you can change the parameters and press the "Regenerate" button next to the container. You can also regenerate a whole group or the whole ambiance. It's up to you. Your call. Your decision. Trust yourself.


- With the "Override existing tracks" checkbox enabled, the track structure will be preserved on each regeneration, no matter the source (Global, Groups, or Container). This is handy if you’ve already tweaked your track volume, pan, FX, etc., and want to keep that but just change the content.
If you change the time selection, only that time selection will be generated. If there’s content in the time selection, it will be deleted and regenerated. The new content will be crossfaded with what’s outside the time selection. The length of this crossfade can be set in the Settings.

<img width="406" height="77" alt="image" src="https://github.com/user-attachments/assets/120c7ffa-a1df-4439-8dbd-c17993dbb0cf" />

- If "Override existing tracks" is disabled, the tracks will be deleted and recreated each time you Generate (It's still local. So if you regenerate only 1 container, only the track related to this container will be deleted/created.)

**Tadaaaa**
---

All right, that's the whole loop! Now let's populate our database, play around with the parameters to create reusable containers and modular ambiances!
Once you're done, you can save the whole structure as one single preset "Winter Forest" that can be recalled at any time. You can also save the groups to reuse them in other contexts, or just use the containers to manually build another type of ambiance. The possibilities are endless.


<img width="984" height="610" alt="image" src="https://github.com/user-attachments/assets/25269ea8-96a1-4e42-a3f8-4667257855b5" />


## Advanced Features

**Euclidean Rhythm System**
---

Want to create complex rhythmic patterns? The Euclidean Rhythm System lets you distribute items according to mathematical rhythm patterns.

Instead of using traditional interval modes (Absolute, Relative, Coverage), you can switch to **Euclidean Mode** to create polyrhythmic ambiances.

Key features:
- **Multi-layer rhythm generation**: Stack multiple euclidean patterns on top of each other
- **Visual preview**: See your rhythm pattern before generating
- **Pattern library**: Access famous traditional rhythm patterns from around the world
- **Auto-bind mode**: Synchronize child layers with parent patterns
- **Rotation control**: Shift patterns to create variations

This is particularly useful for creating:
- Rhythmic industrial ambiances (machinery, construction)
- Musical ambiances (bells, percussion elements)
- Structured nature sounds (dripping water, ticking clocks)

**Interactive Waveform Editor & Advanced File Splitting**
---

The Waveform Editor provides a visual way to work with your audio items and automatically split them into variations.

**Three Split Modes:**

1. **Auto Detect Mode** - Intelligently detect sound regions using gate analysis
   - **Gate Open Threshold** (dB): Level to trigger sound detection
   - **Gate Close Threshold** (dB): Level to end sound region
   - **Min Length** (ms): Minimum duration for detected regions
   - **Start/End Offset** (ms): Extend region boundaries
   - Perfect for: Splitting field recordings with natural silences, isolating individual sounds

2. **Split Count Mode** - Divide audio into equal parts
   - **Number of Areas**: Choose how many equal divisions (1-100)
   - Creates areas of identical length
   - Perfect for: Evenly dividing loops, creating systematic variations

3. **Split Time Mode** - Create fixed-duration segments
   - **Area Duration** (seconds): Set the length of each segment
   - Creates as many areas as fit within the file
   - Perfect for: Time-based variations, consistent segment lengths

**Interactive Features:**

The waveform is divided into **two interaction zones** for intuitive control:

**Upper Half - Area Manipulation:**
- **Create areas**: Shift+Click+Drag to draw custom regions
- **Resize areas**: Click and drag the edges to adjust boundaries
- **Move areas**: Click and drag the center to reposition
- **Delete areas**: Ctrl+Click to remove unwanted regions

**Lower Half - Playback Control:**
- **Set playback position**: Click to jump to any position in the audio
- **Scrub audio**: Click and drag to preview different parts of the file
- **Playback marker**: Visual indicator shows current playback position

**Additional Features:**
- **Visual waveform display**: See the audio content with peak data visualization
- **Real-time updates**: Parameters update instantly with debouncing
- **Zoom and pan**: Navigate through long audio files easily

**Workflow:**
1. Import audio files into a container
2. Select an item to view its waveform
3. Choose a split mode (Auto Detect, Split Count, or Split Time)
4. Adjust parameters and click "Generate" to create areas
5. Fine-tune areas manually if needed
6. Generate your ambiance - the tool randomly selects from all defined areas

Use cases:
- Extract multiple variations from a single long recording
- Isolate individual bird calls from a field recording
- Create multiple versions from one sound effect
- Build evolving soundscapes from fewer source files

**Undo/Redo System**
---

Mistakes happen. That's why we added a complete undo/redo system.

- **Full history window**: View all your previous actions with icons
- **Jump to any state**: Click any entry to go back to that moment
- **Works with everything**: Parameters, drag & drop, item imports, generation
- **Keyboard shortcuts**: Ctrl+Z (undo) and Ctrl+Shift+Z (redo)

Never fear experimenting again!

**Multi-Channel Audio Support**
---

Create immersive surround ambiances with advanced multi-channel support.

Supported formats:
- **Stereo** (2.0) - Standard stereo
- **Quad** (4.0) - L, R, LS, RS
- **5.0 Surround** - ITU/Dolby and SMPTE formats
- **7.0 Surround** - ITU/Dolby and SMPTE formats

Features:
- **Per-track routing**: Each container can target specific speaker channels
- **Channel conflict resolver**: Automatic detection and fixing of routing issues
- **Channel volume controls**: Individual volume control per channel with dB input
- **Stereo pair mapping**: Extract stereo pairs from multi-channel files
- **Split-stereo selection**: Use specific channels from multi-channel sources

The tool handles all the track creation, routing, and channel management automatically.

**Noise Generation Mode**
---

Sometimes randomness isn't random enough. The Noise Generation Mode uses mathematical noise functions to create organic, evolving placements.

Instead of pure random intervals, this mode:
- Uses **deterministic noise algorithms** for reproducible results
- Creates **natural-sounding distributions** that avoid clustering
- Provides a **60-second visual preview** of item placement
- Works great for sparse ambiances (distant birds, occasional creaks)

**Folder and Group Hierarchy**
---

Organize complex ambiances with nested folders and groups.

- **Path-based system**: Groups can now live inside folders
- **Unique name generation**: Automatically prevents naming conflicts
- **Drag and drop**: Reorganize your structure effortlessly
- **Track hierarchy**: Generated tracks mirror your folder structure

This makes managing large ambiances (50+ containers) much more practical.

**Copy/Paste System**
---

Speed up your workflow by duplicating groups and containers.

- **Keyboard shortcuts**: Ctrl+C to copy, Ctrl+V to paste
- **Preserves all settings**: Parameters, items, routing—everything
- **Works across groups**: Copy a container from one group to another
- **Multi-selection support**: Copy multiple containers at once (Ctrl+Click to select multiple)

**Auto-Regeneration**
---

Change parameters and see results immediately with auto-regeneration.

- **Real-time updates**: Changes trigger automatic regeneration
- **Visual indicators**: See which containers need regeneration
- **Smart updates**: Only regenerates what changed
- **Toggle on/off**: Disable when experimenting, enable for final tweaks

Perfect for fine-tuning during the final stages of ambiance creation.

**Settings**
---

You can also customize the interface in the Settings.

<img width="463" height="171" alt="image" src="https://github.com/user-attachments/assets/f954cf56-6a0b-432b-b81f-57399b83d41c" />


## Quick Reference Guide

**Keyboard Shortcuts:**
- **Ctrl+C** - Copy selected group or container(s)
- **Ctrl+V** - Paste copied group or container(s)
- **Ctrl+Z** - Undo last action
- **Ctrl+Shift+Z** - Redo action
- **Space** - Play/pause from current position (in waveform editor)
- **Shift+Click+Drag** - Create new area on waveform (upper half)
- **Ctrl+Click** - Delete area on waveform (upper half)

**Linked Faders Control (Override Link Mode):**
- **Ctrl+Drag** - Force "Link" mode (move min/max together)
- **Shift+Drag** - Force "Mirror" mode (mirror values around zero)
- **Alt+Drag** - Force "Unlink" mode (move independently)
- Override the button-defined link mode temporarily while dragging

**Multi-Selection:**
- **Ctrl+Click** - Toggle individual container selection
- **Shift+Click** - Range selection (select all containers between anchor and current)
- Works with copy/paste, drag & drop, and batch operations

**Advanced UI Interactions:**
- **Fade Controls:**
  - **Click label** - Toggle between seconds (sec) and percentage (%)
  - **Drag fade curve** - Adjust fade shape interactively
  - **Right-click fade** - Choose from predefined slope presets
- **Pitch Controls:**
  - **Click "Pitch" label** - Switch to "Stretch" mode (time-stretching instead of pitch-shifting)
  - **Click "Stretch" label** - Switch back to "Pitch" mode

**Waveform Editor Interaction:**
- **Upper Half** - Area manipulation (create, resize, move, delete)
- **Lower Half** - Playback control (click to jump, drag to scrub)
- **Click area edges** - Resize area boundaries
- **Click area center** - Move entire area
- **Mouse wheel** - Zoom in/out
- **Middle-click+Drag** - Pan through waveform

**Drag & Drop:**
- Drag containers between groups
- Drag groups to reorder
- Drag audio files from Media Explorer directly into containers
- Drag items from REAPER timeline into containers
- Multi-container drag support (select multiple, drag any one)

**Generation Tips:**
- Use **Coverage Mode** for consistent sound density
- Use **Euclidean Mode** for rhythmic patterns
- Use **Noise Mode** for organic, natural-sounding distributions
- Use **Auto Detect** split mode for field recordings with natural silences
- Enable **Auto-Regeneration** for real-time parameter tweaking


## Planned future additions:

- **Preview Listening for Containers/Groups**: A new function will enable you to preview the sound of a container or an entire group directly within the interface before generating it in REAPER, saving time in the creative process.
- **Flexible Group Generation Options**: The ability to generate content into a new group, a specific existing group chosen from a list, or directly into the currently selected group, providing more workflow flexibility and integration with existing projects.
- **Action List**: Adds some Reaper actions to manipulate containers outside of the tool interface.
- **Export**: For video games, allow the extraction of one instance of each item variation, so they can be exported and used to replicate the generated behavior in an audio middleware.
- **Middleware API**: Directly create Random or Sequence containers from the tool in your preferred audio middleware.
- **Ambisonic Support**: Extend multi-channel support to include ambisonic formats for spatial audio.


## Known Issues


## Change log

### 0.10.0-beta (Major Feature Release)

**New Features:**
- Euclidean Rhythm System with multi-layer generation and pattern library
- Interactive Waveform Editor with drawable zones and playback
- Complete Undo/Redo System with history window
- Multi-Channel Audio Support (Quad, 5.0, 7.0 surround with ITU/SMPTE)
- Channel Volume Controls with per-channel management
- Noise Generation Mode with visual preview
- Folder/Group Hierarchy with path-based organization
- Copy/Paste System with keyboard shortcuts
- Auto-Regeneration System with visual indicators
- Advanced UI Components (rotating knobs, S-curve fades, enhanced sliders)
- Improved drag & drop from media explorer and timeline
- UI Scaling Support and modular architecture

**Bug Fixes:**
- Fixed multiple ImGui crashes on window resize and mode changes
- Fixed multi-channel routing and fade issues
- Fixed various generation and parameter synchronization bugs
- Improved overall stability and performance

### 0.9.2
- Fix time selection crash

### 0.9.1
- Fix crashes when switching window modes

### 0.9.0
- Initial Release
