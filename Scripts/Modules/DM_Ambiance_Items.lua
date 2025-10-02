--[[
@version 1.3
@noindex
--]]

local Items = {}
local globals = {}

function Items.initModule(g)
  globals = g
end

-- Get selected items
function Items.getSelectedItems()
  local items = {}
  local count = reaper.CountSelectedMediaItems(0)
  
  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = reaper.GetActiveTake(item)
    
    if take then
      local source = reaper.GetMediaItemTake_Source(take)
      local filename = ""
      
      if source then
        -- Get the filename - GetMediaSourceFileName returns the filename directly
        filename = reaper.GetMediaSourceFileName(source, "")
        if not filename then
          filename = ""
        end
        -- reaper.ShowConsoleMsg(string.format("[Items] Retrieved filename: %s\n", filename or "nil"))
      end
      
      -- Also try to get the name from the take if the source filename is empty
      local takeName = reaper.GetTakeName(take)
      if takeName == "" and filename ~= "" then
        -- Extract just the filename from the path for the name
        takeName = filename:match("([^/\\]+)$") or filename
      end
      
      -- Detect number of channels
      local numChannels = 2 -- Default to stereo
      if source then
        numChannels = math.floor(reaper.GetMediaSourceNumChannels(source) or 2)
      end

      local itemData = {
        name = takeName,
        filePath = filename,
        source = source,  -- Store the source reference as well
        startOffset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"),
        length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
        originalPitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH"),
        originalVolume = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL"),
        originalPan = reaper.GetMediaItemTakeInfo_Value(take, "D_PAN"),
        numChannels = numChannels,
        gainDB = 0.0  -- Default gain offset in dB
      }
      table.insert(items, itemData)
    end
  end
  
  return items
end

-- Function to create a pan envelope and add a point
-- @param take MediaItemTake: The take to create envelope for
-- @param panValue number: Pan value (-1 to 1)
function Items.createTakePanEnvelope(take, panValue)
  -- Check if the take is valid
  if not take then 
    return 
  end
  
  -- Get the parent item
  local item = reaper.GetMediaItemTake_Item(take)
  if not item then 
    return 
  end
  
  -- Get the pan envelope by its name
  local env = reaper.GetTakeEnvelopeByName(take, "Pan")
  
  -- Check if envelope already exists (even if empty)
  if env then
      -- If envelope exists, just update it with new values
      Items.updateTakePanEnvelope(take, panValue)
      return
  end
  
  -- If the envelope doesn't exist, create it manually
  if not env then
      
      -- Save the complete current selection
      local numSelectedItems = reaper.CountSelectedMediaItems(0)
      local selectedItems = {}
      for i = 0, numSelectedItems - 1 do
          selectedItems[i + 1] = reaper.GetSelectedMediaItem(0, i)
      end
      
      -- Clear all selections and select only our target item
      reaper.SelectAllMediaItems(0, false)
      reaper.SetMediaItemSelected(item, true)
      
      -- Use ONLY the create envelope command, no visibility commands
      reaper.Main_OnCommand(40694, 0)  -- Create take pan envelope
      
      -- Force multiple updates to ensure envelope is created
      reaper.UpdateArrange()
      reaper.UpdateTimeline()
      
      -- Try to get the envelope multiple times with small delays
      local retryCount = 0
      local maxRetries = 5
      
      while retryCount < maxRetries do
          env = reaper.GetTakeEnvelopeByName(take, "Pan")
          if env then
              break
          end
          retryCount = retryCount + 1
          reaper.UpdateArrange()
      end
      
      -- Restore the original selection after envelope is confirmed
      reaper.SelectAllMediaItems(0, false)
      for i, selectedItem in ipairs(selectedItems) do
          reaper.SetMediaItemSelected(selectedItem, true)
      end
      
      if not env then
          return
      end
  end
  
  if env then
      -- Calculate time for envelope points
      local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      local playRate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
      
      -- Delete all existing points
      reaper.DeleteEnvelopePointRange(env, 0, itemLength * playRate)
      
      -- Add points at the beginning and end with the same value
      reaper.InsertEnvelopePoint(env, 0, panValue, 0, 0, false, true)
      reaper.InsertEnvelopePoint(env, itemLength * playRate, panValue, 0, 0, false, true)
      
      -- Sorting is necessary after adding points with noSort = true
      reaper.Envelope_SortPoints(env)
      
      -- Force display update to make envelope visible
      reaper.UpdateArrange()
  end
end

-- Function to remove pan envelope completely from a take
function Items.removeTakePanEnvelope(take)
  -- Check if the take is valid
  if not take then 
    return false
  end
  
  -- Get the existing pan envelope
  local env = reaper.GetTakeEnvelopeByName(take, "Pan")
  if not env then
    return false
  end
  
  -- Get the parent item for selection
  local item = reaper.GetMediaItemTake_Item(take)
  if not item then 
    return false
  end
  
  -- Save current selection
  local numSelectedItems = reaper.CountSelectedMediaItems(0)
  local selectedItems = {}
  for i = 0, numSelectedItems - 1 do
      selectedItems[i + 1] = reaper.GetSelectedMediaItem(0, i)
  end
  
  -- Select only our target item
  reaper.SelectAllMediaItems(0, false)
  reaper.SetMediaItemSelected(item, true)
  
  -- Use toggle command to remove take pan envelope (40694 toggles pan envelope on/off)
  reaper.Main_OnCommand(40694, 0)  -- Toggle take pan envelope (removes it if it exists)
  
  -- Restore the original selection
  reaper.SelectAllMediaItems(0, false)
  for i, selectedItem in ipairs(selectedItems) do
      reaper.SetMediaItemSelected(selectedItem, true)
  end
  
  reaper.UpdateArrange()
  return true
end

-- Function to update all points in an existing pan envelope
function Items.updateTakePanEnvelope(take, newPanValue)
  -- Check if the take is valid
  if not take then 
    return false
  end
  
  -- Get the existing pan envelope
  local env = reaper.GetTakeEnvelopeByName(take, "Pan")
  if not env then
    return false
  end
  
  -- Get the number of existing points
  local numPoints = reaper.CountEnvelopePoints(env)
  
  if numPoints == 0 then
    -- No points exist, create initial points
    local item = reaper.GetMediaItemTake_Item(take)
    local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local playRate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    
    reaper.InsertEnvelopePoint(env, 0, newPanValue, 0, 0, false, true)
    reaper.InsertEnvelopePoint(env, itemLength * playRate, newPanValue, 0, 0, false, true)
    reaper.Envelope_SortPoints(env)
  else
    -- Update all existing points with the new pan value
    for i = 0, numPoints - 1 do
      local retval, time, oldValue, shape, tension, selected = reaper.GetEnvelopePoint(env, i)
      if retval then
        reaper.SetEnvelopePoint(env, i, time, newPanValue, shape, tension, selected, true)
      end
    end
  end
  
  -- Force display update
  reaper.UpdateArrange()
  return true
end

-- Create item data from file path (for drag and drop from Media Explorer)
function Items.createItemFromFilePath(filePath)
  if not filePath or type(filePath) ~= "string" or filePath == "" then
    return nil
  end

  -- Check if file exists
  local file = io.open(filePath, "r")
  if not file then
    return nil
  end
  file:close()

  -- Extract filename for name
  local fileName = filePath:match("([^/\\]+)$") or filePath
  local name = fileName:match("^(.+)%..+$") or fileName -- Remove extension

  -- Get audio file length and channel count using REAPER's PCM_Source
  local length = nil
  local numChannels = 2 -- Default to stereo
  local source = reaper.PCM_Source_CreateFromFile(filePath)
  if source then
    length = reaper.GetMediaSourceLength(source, nil)
    numChannels = math.floor(reaper.GetMediaSourceNumChannels(source) or 2)
    reaper.PCM_Source_Destroy(source)
  end

  -- Create basic item data (similar to getSelectedItems but from file path)
  local itemData = {
    name = name,
    filePath = filePath,
    source = nil, -- Will be created when needed
    startOffset = 0,
    length = length, -- Now properly calculated from the audio file
    originalPitch = 0,
    originalVolume = 1.0,
    originalPan = 0.0,
    numChannels = numChannels,
    gainDB = 0.0  -- Default gain offset in dB
  }

  return itemData
end

-- Process dropped files and create items array
function Items.processDroppedFiles(files)
  local items = {}

  for _, filePath in ipairs(files) do
    local item = Items.createItemFromFilePath(filePath)
    if item then
      table.insert(items, item)
    end
  end

  return items
end

-- Get default routing for an item based on its channel count and container channel mode
-- Returns a 1-to-1 routing matrix mapping source channels to destination channels
-- @param itemChannels number: Number of channels in the audio item
-- @param containerChannelMode number: Container channel mode (0=stereo, 1=4.0, 2=5.0, 3=7.0)
-- @return table: {routingMatrix = {[srcChannel] = destChannel}, isAutoRouting = true}
function Items.getDefaultRouting(itemChannels, containerChannelMode)
  -- Default mode (stereo) or invalid mode - no routing needed
  if not containerChannelMode or containerChannelMode == 0 then
    return {routingMatrix = {}, isAutoRouting = true}
  end

  -- Need access to constants
  if not globals.Constants then
    return {routingMatrix = {}, isAutoRouting = true}
  end

  local config = globals.Constants.CHANNEL_CONFIGS[containerChannelMode]
  if not config then
    return {routingMatrix = {}, isAutoRouting = true}
  end

  local containerChannels = config.channels
  local routingMatrix = {}

  -- Perfect match: direct 1-to-1 mapping
  if itemChannels == containerChannels then
    for i = 1, itemChannels do
      routingMatrix[i] = i
    end

  -- Mono item: special flag 0 = distribute across all channels (handled by distribution mode)
  elseif itemChannels == 1 then
    routingMatrix[1] = 0  -- Flag for distribution mode

  -- Stereo item in multichannel: Ch1→L, Ch2→R
  elseif itemChannels == 2 then
    routingMatrix[1] = 1  -- L
    routingMatrix[2] = 2  -- R

  -- 4.0 item in 5.0/7.0: map L/R/LS/RS (skip C)
  elseif itemChannels == 4 and containerChannelMode >= 2 then
    routingMatrix[1] = 1  -- L
    routingMatrix[2] = 2  -- R
    routingMatrix[3] = 4  -- LS (skip C which is 3)
    routingMatrix[4] = 5  -- RS

  -- 5.0 item in 7.0: map first 5 channels
  elseif itemChannels == 5 and containerChannelMode == 3 then
    for i = 1, 5 do
      routingMatrix[i] = i
    end

  -- Downmix: only use first channel → L
  else
    routingMatrix[1] = 1
  end

  return {routingMatrix = routingMatrix, isAutoRouting = true}
end


return Items
