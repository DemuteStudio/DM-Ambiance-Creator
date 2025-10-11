-- Script to fix malformed preset file
local presetPath = [[C:\Users\antho\AppData\Roaming\REAPER\Scripts\Demute\Ambiance Creator\Presets\Global\Euclidian Test.lua]]

-- Read the file
local file = io.open(presetPath, "r")
if not file then
    print("Could not open preset file")
    return
end

local content = file:read("*all")
file:close()

-- Fix UUID keys by adding quotes and brackets
-- Pattern: finds lines like "      1760177996-0032 = {"
-- Replaces with: "      ["1760177996-0032"] = {"
local fixed = content:gsub("(%s+)([%d]+-[%da-f]+)%s*=%s*{", '%1["%2"] = {')

-- Write back
file = io.open(presetPath, "w")
if not file then
    print("Could not write preset file")
    return
end

file:write(fixed)
file:close()

print("Preset file fixed!")
