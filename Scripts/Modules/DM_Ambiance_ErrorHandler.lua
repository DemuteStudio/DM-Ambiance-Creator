--[[
@version 1.4
@noindex
--]]

-- Error handling utilities for the Ambiance Creator
local ErrorHandler = {}
local Constants = require("DM_Ambiance_Constants")

-- Error severity levels
ErrorHandler.SEVERITY = {
    INFO = 1,
    WARNING = 2,
    ERROR = 3,
    CRITICAL = 4
}

-- Initialize error handler (if needed for logging setup)
function ErrorHandler.init()
    -- Future: setup logging files, etc.
end

-- Safe function execution with error handling
-- @param func function: Function to execute
-- @param errorMessage string: Error message prefix (optional)
-- @param defaultReturn any: Default return value on error (optional)
-- @return boolean, any: success status and result/error
function ErrorHandler.safeCall(func, errorMessage, defaultReturn)
    if type(func) ~= "function" then
        return false, "ErrorHandler.safeCall: first parameter must be a function"
    end
    
    local success, result = pcall(func)
    if not success then
        local finalMessage = errorMessage and (errorMessage .. ": " .. tostring(result)) or tostring(result)
        ErrorHandler.logError(finalMessage, ErrorHandler.SEVERITY.ERROR)
        return false, defaultReturn
    end
    
    return true, result
end

-- Safe property access for nested objects
-- @param obj table: Object to access
-- @param path string: Dot-separated path (e.g., "settings.ui.color")
-- @param defaultValue any: Default value if path doesn't exist
-- @return any: Value at path or default
function ErrorHandler.safeGet(obj, path, defaultValue)
    if not obj or type(obj) ~= "table" then
        return defaultValue
    end
    
    if not path or path == "" then
        return defaultValue
    end
    
    local current = obj
    for part in string.gmatch(path, "[^%.]+") do
        if type(current) ~= "table" or current[part] == nil then
            return defaultValue
        end
        current = current[part]
    end
    
    return current
end

-- Validate parameter with detailed error messages
-- @param value any: Value to validate
-- @param validators table: Array of validator functions
-- @param paramName string: Parameter name for error messages
-- @return boolean, string: validation result and error message
function ErrorHandler.validateParam(value, validators, paramName)
    if not validators or type(validators) ~= "table" then
        return false, "ErrorHandler.validateParam: validators must be a table"
    end
    
    paramName = paramName or "parameter"
    
    for i, validator in ipairs(validators) do
        if type(validator) ~= "function" then
            return false, string.format("Validator %d for %s is not a function", i, paramName)
        end
        
        local isValid, errorMsg = validator(value)
        if not isValid then
            return false, string.format("%s validation failed: %s", paramName, errorMsg or "unknown error")
        end
    end
    
    return true, nil
end

-- Common validator functions
ErrorHandler.validators = {
    -- Check if value is not nil
    notNil = function(value)
        return value ~= nil, "value cannot be nil"
    end,
    
    -- Check if value is a number
    isNumber = function(value)
        return type(value) == "number", "value must be a number"
    end,
    
    -- Check if value is a string
    isString = function(value)
        return type(value) == "string", "value must be a string"
    end,
    
    -- Check if value is a function
    isFunction = function(value)
        return type(value) == "function", "value must be a function"
    end,
    
    -- Check if value is a table
    isTable = function(value)
        return type(value) == "table", "value must be a table"
    end,
    
    -- Check if string is not empty
    notEmpty = function(value)
        return value ~= "", "string cannot be empty"
    end,
    
    -- Check if number is positive
    isPositive = function(value)
        return type(value) == "number" and value > 0, "value must be positive"
    end,
    
    -- Check if number is non-negative
    isNonNegative = function(value)
        return type(value) == "number" and value >= 0, "value must be non-negative"
    end,
    
    -- Create range validator
    inRange = function(min, max)
        return function(value)
            if type(value) ~= "number" then
                return false, "value must be a number"
            end
            return value >= min and value <= max, string.format("value must be between %s and %s", min, max)
        end
    end
}

-- Log error with severity
-- @param message string: Error message
-- @param severity number: Error severity level
function ErrorHandler.logError(message, severity)
    severity = severity or ErrorHandler.SEVERITY.ERROR
    
    local prefix = ""
    if severity == ErrorHandler.SEVERITY.WARNING then
        prefix = "WARNING: "
    elseif severity == ErrorHandler.SEVERITY.ERROR then
        prefix = "ERROR: "
    elseif severity == ErrorHandler.SEVERITY.CRITICAL then
        prefix = "CRITICAL: "
    end
    
    -- For now, just use Reaper's console. Could be extended to file logging
    reaper.ShowConsoleMsg(prefix .. tostring(message) .. "\n")
end

-- Retry mechanism for operations
-- @param func function: Function to retry
-- @param maxRetries number: Maximum number of retries (default: 3)
-- @param delay number: Delay between retries in seconds (default: 0.1)
-- @return boolean, any: success status and result
function ErrorHandler.retry(func, maxRetries, delay)
    maxRetries = maxRetries or 3
    delay = delay or 0.1
    
    for attempt = 1, maxRetries do
        local success, result = ErrorHandler.safeCall(func)
        if success then
            return true, result
        end
        
        if attempt < maxRetries then
            -- Simple delay mechanism (could be improved)
            local startTime = reaper.time_precise()
            while reaper.time_precise() - startTime < delay do
                -- Busy wait
            end
        end
    end
    
    return false, "Operation failed after " .. maxRetries .. " attempts"
end

-- Create a safe wrapper for a function with validation
-- @param func function: Function to wrap
-- @param paramValidators table: Array of parameter validators
-- @return function: Wrapped function
function ErrorHandler.createSafeWrapper(func, paramValidators)
    return function(...)
        local args = {...}
        
        -- Validate parameters if validators provided
        if paramValidators then
            for i, validators in ipairs(paramValidators) do
                if validators then
                    local isValid, errorMsg = ErrorHandler.validateParam(args[i], validators, "parameter " .. i)
                    if not isValid then
                        error("Parameter validation failed: " .. errorMsg)
                    end
                end
            end
        end
        
        -- Call original function
        local success, result = ErrorHandler.safeCall(func, "Wrapped function call failed")
        if not success then
            error("Function execution failed: " .. tostring(result))
        end
        
        return result
    end
end

return ErrorHandler