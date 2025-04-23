local loadedModules = {}
local Config = nil
local isLoadingConfig = false

local function Debug(message, ...)
    if isLoadingConfig then return end
    
    if Config and Config.Debug then
        local resourceName = GetCurrentResourceName()
        local formattedMessage = string.format("[%s] %s", resourceName, message)
        
        if ... then
            local args = {...}
            for i = 1, #args do
                if type(args[i]) == "table" then
                    formattedMessage = formattedMessage .. " " .. json.encode(args[i])
                else
                    formattedMessage = formattedMessage .. " " .. tostring(args[i])
                end
            end
        end
        
        print(formattedMessage)
    end
end

_G.Debug = Debug

local function require(modulePath)
    local isConfigModule = modulePath == "config" or modulePath == "config.lua"
    
    if isConfigModule then
        isLoadingConfig = true
    end
    
    if not isConfigModule or (Config and Config.Debug) then
        Debug("Attempting to require module: " .. modulePath)
    end
    
    if loadedModules[modulePath] then
        if not isConfigModule or (Config and Config.Debug) then
            Debug("Module already loaded: " .. modulePath)
        end
        return loadedModules[modulePath]
    end
    
    local resourceName = GetCurrentResourceName()
    local fileContent, moduleFunction, errorMessage
    
    fileContent = LoadResourceFile(resourceName, modulePath)
    if not isConfigModule or (Config and Config.Debug) then
        Debug("Trying path: " .. modulePath .. ", content found: " .. (fileContent ~= nil and "yes" or "no"))
    end
    
    if not fileContent then
        if not string.find(modulePath, "%.lua$") then
            local newPath = modulePath .. ".lua"
            fileContent = LoadResourceFile(resourceName, newPath)
            if not isConfigModule or (Config and Config.Debug) then
                Debug("Trying path with .lua: " .. newPath .. ", content found: " .. (fileContent ~= nil and "yes" or "no"))
            end
        end
        
        if not fileContent then
            local possiblePaths = {
                "shared/" .. modulePath,
                "shared/" .. modulePath .. ".lua",
                "config/" .. modulePath,
                "config/" .. modulePath .. ".lua",
                "client/" .. modulePath,
                "client/" .. modulePath .. ".lua",
                "server/" .. modulePath,
                "server/" .. modulePath .. ".lua"
            }
            
            for _, path in ipairs(possiblePaths) do
                if not isConfigModule or (Config and Config.Debug) then
                    Debug("Trying alternative path: " .. path)
                end
                fileContent = LoadResourceFile(resourceName, path)
                if fileContent then
                    if not isConfigModule or (Config and Config.Debug) then
                        Debug("Found content at path: " .. path)
                    end
                    break
                end
            end
        end
    end
    
    if not fileContent then
        local errorMsg = "Failed to load module '" .. modulePath .. "': File not found"
        print("[ERROR] " .. errorMsg) 
        error(errorMsg)
        return nil
    end
    
    moduleFunction, errorMessage = load(fileContent, modulePath)
    
    if not moduleFunction then
        local errorMsg = "Failed to parse module '" .. modulePath .. "': " .. (errorMessage or "Unknown error")
        print("[ERROR] " .. errorMsg) 
        error(errorMsg)
        return nil
    end
    
    local success, result = pcall(moduleFunction)
    
    if not success then
        local errorMsg = "Error executing module '" .. modulePath .. "': " .. result
        print("[ERROR] " .. errorMsg) 
        error(errorMsg)
        return nil
    end
    
    if not isConfigModule or (Config and Config.Debug) then
        Debug("Successfully loaded module: " .. modulePath)
    end
    
    loadedModules[modulePath] = result
    
    if isConfigModule then
        Config = result
        isLoadingConfig = false
        
        if Config.Debug then
            print("[" .. resourceName .. "] Config module loaded, Debug setting: " .. tostring(Config.Debug))
        end
    end
    
    return result
end

_G.require = require

return require