--[[
@version 1.5
@noindex
DM Ambiance Creator - String Utilities Module
Extracted from DM_Ambiance_Utils.lua for better modularity

This module contains all string manipulation, formatting, and parsing functions.
--]]

local Utils_String = {}

-- Format seconds as HH:MM:SS
-- @param seconds number: Time in seconds
-- @return string: Formatted time string
function Utils_String.formatTime(seconds)
    seconds = tonumber(seconds) or 0

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)

    return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

-- Fuzzy match a search query against a target string
-- @param query string: The search query
-- @param target string: The target string to match against
-- @return boolean, number: true if match found, and match score (higher is better)
function Utils_String.fuzzyMatch(query, target)
    if not query or query == "" then
        return true, 0
    end

    if not target or target == "" then
        return false, 0
    end

    -- Convert to lowercase for case-insensitive matching
    query = query:lower()
    target = target:lower()

    local queryLen = #query
    local targetLen = #target

    -- If query is longer than target, no match possible
    if queryLen > targetLen then
        return false, 0
    end

    -- Simple substring match gets high score
    if target:find(query, 1, true) then
        local startPos = target:find(query, 1, true)
        -- Prefer matches at start of string
        local positionBonus = 1.0 / (startPos or 1)
        return true, 100 + positionBonus
    end

    -- Fuzzy sequential character matching
    local queryIdx = 1
    local targetIdx = 1
    local matchCount = 0
    local consecutiveMatches = 0
    local score = 0

    while queryIdx <= queryLen and targetIdx <= targetLen do
        local queryChar = query:sub(queryIdx, queryIdx)
        local targetChar = target:sub(targetIdx, targetIdx)

        if queryChar == targetChar then
            matchCount = matchCount + 1
            consecutiveMatches = consecutiveMatches + 1
            -- Bonus for consecutive matches
            score = score + 1 + consecutiveMatches
            queryIdx = queryIdx + 1
        else
            consecutiveMatches = 0
        end
        targetIdx = targetIdx + 1
    end

    -- All query characters must be found in sequence
    if matchCount == queryLen then
        return true, score
    end

    return false, 0
end

-- Convert path array to comma-separated string
-- @param path table: Path array like {1, 2, 3}
-- @return string: Path string like "1,2,3"
function Utils_String.pathToString(path)
    if not path or #path == 0 then
        return ""
    end
    return table.concat(path, ",")
end

-- Convert path string back to array
-- @param pathString string: Path string like "1,2,3"
-- @return table: Path array like {1, 2, 3}
function Utils_String.pathFromString(pathString)
    if not pathString or pathString == "" then
        return {}
    end

    local path = {}
    for num in pathString:gmatch("[^,]+") do
        table.insert(path, tonumber(num))
    end
    return path
end

-- Create a container selection key from path and container index
-- @param path table: Path to the parent group
-- @param containerIndex number: Index of the container
-- @return string: Container key like "1_2_3_5" (path + container index)
function Utils_String.makeContainerKey(path, containerIndex)
    if not path or not containerIndex then
        return nil
    end

    local pathStr = Utils_String.pathToString(path)
    if pathStr == "" then
        return tostring(containerIndex)
    end
    return pathStr .. "_" .. tostring(containerIndex)
end

-- Parse a container selection key back to path and container index
-- @param key string: Container key like "1_2_3_5"
-- @return table, number: Path array and container index
function Utils_String.parseContainerKey(key)
    if not key or key == "" then
        return nil, nil
    end

    local parts = {}
    for part in key:gmatch("[^_]+") do
        table.insert(parts, tonumber(part))
    end

    if #parts == 0 then
        return nil, nil
    end

    -- Last part is container index, rest is path
    local containerIndex = parts[#parts]
    local path = {}
    for i = 1, #parts - 1 do
        path[i] = parts[i]
    end

    return path, containerIndex
end

-- Generate unique itemKey for identifying items
-- @param groupIndex number: Group index
-- @param containerIndex number: Container index
-- @param itemIndex number: Item index
-- @return string: Item key like "g1_c2_i3"
function Utils_String.generateItemKey(groupIndex, containerIndex, itemIndex)
    return string.format("g%d_c%d_i%d", groupIndex, containerIndex, itemIndex)
end

return Utils_String
