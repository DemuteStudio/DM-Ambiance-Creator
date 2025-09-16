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
      local filename = reaper.GetMediaSourceFileName(source, "")
      
      local itemData = {
        name = reaper.GetTakeName(take),
        filePath = filename,
        startOffset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"),
        length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
        originalPitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH"),
        originalVolume = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL"),
        originalPan = reaper.GetMediaItemTakeInfo_Value(take, "D_PAN")
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


return Items
