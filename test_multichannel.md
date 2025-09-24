# Test Plan for Multi-Channel Support

## Summary of Changes

### 1. **DM_Ambiance_Constants.lua**
- Added `CHANNEL_MODES` constants for different channel configurations
- Added `CHANNEL_CONFIGS` with routing and label information for each mode

### 2. **DM_Ambiance_Structures.lua**
- Added `channelMode` property to containers (default: 0 for stereo)
- Added `channelPanning` array for per-channel pan settings
- Added `channelVolumes` array for per-channel volume settings
- Added `channelDistribution` property for item distribution mode

### 3. **DM_Ambiance_Utils.lua**
- Added `updateContainerRouting()` function to configure track channel count

### 4. **DM_Ambiance_Generation.lua**
- Added `createMultiChannelTracks()` to create channel track structure
- Added `getExistingChannelTracks()` to retrieve existing tracks
- Added `clearChannelTracks()` to clear items from tracks
- Added `deleteContainerChildTracks()` for mode changes
- Modified `placeItemsForContainer()` to handle multi-channel distribution

### 5. **DM_Ambiance_UI_Container.lua**
- Added Channel Mode dropdown selector
- Added Item Distribution mode selector (for multi-channel)
- Added per-channel Pan and Volume sliders
- UI updates when channel mode changes

### 6. **DM_Ambiance_Presets.lua**
- No changes needed - existing serialization handles new properties

## Testing Steps

### Basic Functionality
1. Open Reaper and load the Ambiance Creator script
2. Create a new group and container
3. Import some audio items into the container

### Test Default Mode
1. Leave Channel Mode as "Default (Stereo)"
2. Generate ambiance
3. Verify single track is created with items

### Test 4.0 Quad Mode
1. Select container and change Channel Mode to "4.0 Quad"
2. Set Distribution to "Random"
3. Adjust pan/volume for each channel
4. Generate ambiance
5. Verify:
   - Container track becomes folder
   - 4 child tracks are created with proper names
   - Items are randomly distributed
   - Routing is configured correctly

### Test 5.1 Surround Mode
1. Change to "5.1 Surround"
2. Set Distribution to "Round-Robin"
3. Generate ambiance
4. Verify:
   - 6 child tracks created
   - Items distributed in round-robin fashion
   - Each track routed to correct channels

### Test All Channels Distribution
1. Set Distribution to "All Channels"
2. Generate ambiance
3. Verify items appear on all channel tracks simultaneously

### Test Regeneration
1. Change channel mode after generation
2. Regenerate container
3. Verify old structure is replaced with new

### Test Presets
1. Save container as preset with multi-channel config
2. Load preset on another container
3. Verify all settings are restored

## Expected Results

- **Default Mode**: Works exactly as before (backward compatible)
- **Multi-Channel Modes**: Creates proper folder structure with child tracks
- **Routing**: Each channel track sends to correct output channels
- **Distribution**: Items distributed according to selected mode
- **UI**: Shows/hides controls based on channel mode
- **Presets**: Save and restore all multi-channel settings

## Known Limitations
- Requires manual testing in Reaper environment
- Channel routing depends on Reaper's routing capabilities
- Visual feedback limited to track structure