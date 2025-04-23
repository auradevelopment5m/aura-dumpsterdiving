local QBCore = exports['qb-core']:GetCoreObject()
local Config = require('config')

Debug("Server script initializing")

local playerCooldowns = {}
local playerSearches = {}
local maxSearchesPerMinute = 5
local cooldownDuration = Config.CooldownDuration

Debug("Anti-exploit settings: maxSearchesPerMinute=" .. maxSearchesPerMinute .. ", cooldownDuration=" .. cooldownDuration)

local function IsPlayerOnCooldown(playerId)
    if not playerCooldowns[playerId] then return false end
    local isOnCooldown = (GetGameTimer() - playerCooldowns[playerId]) < cooldownDuration
    Debug("Checking player cooldown: " .. playerId .. ", on cooldown: " .. tostring(isOnCooldown))
    return isOnCooldown
end

local function SetPlayerCooldown(playerId)
    playerCooldowns[playerId] = GetGameTimer()
    Debug("Set player cooldown: " .. playerId .. ", timestamp: " .. playerCooldowns[playerId])
end

local function IncrementPlayerSearchCount(playerId)
    Debug("Incrementing search count for player: " .. playerId)
    
    if not playerSearches[playerId] then
        playerSearches[playerId] = {
            count = 0,
            timestamp = GetGameTimer()
        }
        Debug("Initialized search count for player: " .. playerId)
    end
    
    if (GetGameTimer() - playerSearches[playerId].timestamp) > 60000 then
        playerSearches[playerId] = {
            count = 1,
            timestamp = GetGameTimer()
        }
        Debug("Reset search count for player: " .. playerId .. " (time elapsed)")
        return true
    end
    
    playerSearches[playerId].count = playerSearches[playerId].count + 1
    Debug("New search count for player: " .. playerId .. " = " .. playerSearches[playerId].count)
    
    local withinLimit = playerSearches[playerId].count <= maxSearchesPerMinute
    Debug("Player " .. playerId .. " within search limit: " .. tostring(withinLimit))
    return withinLimit
end

local function GetRandomItem()
    Debug("Getting random item from loot table")
    
    local total = 0
    for _, v in ipairs(Config.Items) do
        total = total + v.probability
    end
    
    local chance = math.random(total)
    Debug("Random roll: " .. chance .. " / " .. total)
    
    local runningTotal = 0
    
    for _, v in ipairs(Config.Items) do
        runningTotal = runningTotal + v.probability
        if chance <= runningTotal then
            Debug("Selected item: " .. v.item .. " (probability: " .. v.probability .. ")")
            return v.item
        end
    end
    
    Debug("No item selected (should not happen)")
    return nil
end

local function ValidatePlayer(playerId)
    Debug("Validating player: " .. playerId)
    
    local player = QBCore.Functions.GetPlayer(playerId)
    if not player then
        Debug("Player validation failed: Player does not exist - ID: " .. playerId)
        return false
    end
    
    if IsPlayerOnCooldown(playerId) then
        Debug("Player validation failed: Player on cooldown - ID: " .. playerId)
        return false
    end

    if not IncrementPlayerSearchCount(playerId) then
        Debug("Player validation failed: Rate limit exceeded - ID: " .. playerId)
        print("[AURA-DUMPSTERDIVING] POTENTIAL EXPLOIT DETECTED: Player " .. playerId .. " (" .. player.PlayerData.name .. ") exceeded search rate limit")
        return false
    end
    
    Debug("Player validation passed: " .. playerId)
    return true
end

RegisterNetEvent('aura-dumpsterdiving:server:RewardItem', function()
    local src = source
    Debug("RewardItem event triggered by player: " .. src)
    
    if not ValidatePlayer(src) then
        Debug("Player validation failed, silently failing")
        return
    end
    
    SetPlayerCooldown(src)
    
    local Player = QBCore.Functions.GetPlayer(src)
    local item = GetRandomItem()
    
    if item then
        Debug("Giving item to player: " .. item)
        local canCarry = Player.Functions.AddItem(item, 1)
        if canCarry then
            Debug("Item added successfully")
            TriggerClientEvent('qb-inventory:client:ItemBox', src, QBCore.Shared.Items[item], "add")
        else
            Debug("Player inventory full")
            TriggerClientEvent('QBCore:Notify', src, 'Your pockets are full', 'error')
        end
    else
        Debug("No item found, notifying player")
        TriggerClientEvent('QBCore:Notify', src, 'You found nothing', 'error')
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    Debug("Player disconnected: " .. src .. ", cleaning up resources")
    
    if playerCooldowns[src] then
        playerCooldowns[src] = nil
        Debug("Removed cooldown for player: " .. src)
    end
    
    if playerSearches[src] then
        playerSearches[src] = nil
        Debug("Removed search count for player: " .. src)
    end
end)

CreateThread(function()
    while true do
        Wait(300000) 
        Debug("Performing periodic cleanup of stale data")
        
        local currentTime = GetGameTimer()
        local cleanupCount = 0
        
        for playerId, timestamp in pairs(playerCooldowns) do
            if (currentTime - timestamp) > cooldownDuration * 2 then
                playerCooldowns[playerId] = nil
                cleanupCount = cleanupCount + 1
                Debug("Cleaned up cooldown for inactive player: " .. playerId)
            end
        end
        
        for playerId, data in pairs(playerSearches) do
            if (currentTime - data.timestamp) > 120000 then 
                playerSearches[playerId] = nil
                cleanupCount = cleanupCount + 1
                Debug("Cleaned up search count for inactive player: " .. playerId)
            end
        end
        
        Debug("Cleanup complete, removed " .. cleanupCount .. " stale entries")
    end
end)

exports('IsPlayerOnDumpsterCooldown', function(playerId)
    return IsPlayerOnCooldown(playerId)
end)

Debug("Server script loaded")