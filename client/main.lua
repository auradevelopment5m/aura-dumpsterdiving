local QBCore = exports['qb-core']:GetCoreObject()
local Config = require('config')

local searchedProps, isInteracting = {}, false
local floor, random = math.floor, math.random
local GetEntityCoords, GetEntityModel, GetGameTimer, PlayerPedId, GetEntityHeading = GetEntityCoords, GetEntityModel, GetGameTimer, PlayerPedId, GetEntityHeading
local TaskGoStraightToCoord, ClearPedTasks, TaskPlayAnim, DoesEntityExist = TaskGoStraightToCoord, ClearPedTasks, TaskPlayAnim, DoesEntityExist
local CreatePed, TaskCombatPed, SetEntityAsNoLongerNeeded, SetModelAsNoLongerNeeded = CreatePed, TaskCombatPed, SetEntityAsNoLongerNeeded, SetModelAsNoLongerNeeded
local RequestModel, HasModelLoaded, RequestAnimDict, HasAnimDictLoaded = RequestModel, HasModelLoaded, RequestAnimDict, HasAnimDictLoaded

local notificationSystems = {
    ps = function(msg, type, length) 
        Debug("Notification (ps): " .. msg)
        return exports['ps-ui']:Notify(msg, type, length) 
    end,
    qb = function(msg, type, length) 
        Debug("Notification (qb): " .. msg)
        return QBCore.Functions.Notify(msg, type, length) 
    end,
    k5 = function(msg, type, length) 
        Debug("Notification (k5): " .. msg)
        return exports["k5_notify"]:notify(type, msg, type, length) 
    end,
    ox = function(msg, type, length)
        Debug("Notification (ox): " .. msg)
        local oxType = type
        if type == "error" then oxType = "error" 
        elseif type == "success" then oxType = "success"
        else oxType = "inform" end
        
        return lib.notify({
            title = 'Dumpster Diving',
            description = msg,
            type = oxType,
            duration = length or 3000
        })
    end
}

local progressBarSystems = {
    qb = function(label, duration, options, onComplete, onCancel)
        Debug("ProgressBar (qb): " .. label .. ", duration: " .. duration)
        return QBCore.Functions.Progressbar("search_garbage", label, duration, false, true, options, {}, {}, {}, onComplete, onCancel)
    end,
    ox = function(label, duration, options, onComplete, onCancel)
        Debug("ProgressBar (ox): " .. label .. ", duration: " .. duration)
        local success = lib.progressBar({
            duration = duration,
            label = label,
            useWhileDead = false,
            canCancel = true,
            disable = {
                car = options.disableCarMovement,
                move = options.disableMovement,
                combat = options.disableCombat,
                mouse = options.disableMouse
            },
            anim = {
                dict = 'amb@prop_human_bum_bin@base',
                clip = 'base'
            }
        })
        
        if success then
            if onComplete then onComplete() end
        else
            if onCancel then onCancel() end
        end
    end
}

local minigameSystems = {
    ["ps-ui"] = function(callback)
        Debug("Starting ps-ui Circle minigame")
        local settings = Config.Minigame.Settings
        exports['ps-ui']:Circle(function(success)
            Debug("ps-ui Circle minigame result: " .. tostring(success))
            callback(success)
        end, settings.Circles, settings.Time * 1000)  
    end,
    
    ["boii"] = function(callback)
        Debug("Starting boii button_mash minigame")
        local settings = Config.Minigame.Settings
        exports['boii_minigames']:button_mash({
            style = settings.Style,
            difficulty = settings.Difficulty
        }, function(success)
            Debug("boii button_mash minigame result: " .. tostring(success))
            callback(success)
        end)
    end
}

local function CustomNotify(msg, type, length)
    local notifyFunc = notificationSystems[Config.Notifications]
    if notifyFunc then 
        return notifyFunc(msg, type, length) 
    else
        Debug("ERROR: Invalid notification type: " .. (Config.Notifications or "nil"))
    end
end

local function RunProgressBar(label, duration, options, onComplete, onCancel)
    local progressFunc = progressBarSystems[Config.ProgressBar]
    if progressFunc then
        return progressFunc(label, duration, options, onComplete, onCancel)
    else
        Debug("ERROR: Invalid progressbar type: " .. (Config.ProgressBar or "nil"))
        return QBCore.Functions.Progressbar("search_garbage", label, duration, false, true, options, {}, {}, {}, onComplete, onCancel)
    end
end

local function RunMinigame(callback)
    if not Config.Minigame.Enabled then
        Debug("Minigames disabled, auto-success")
        return callback(true)
    end
    
    local minigameFunc = minigameSystems[Config.Minigame.Type]
    if minigameFunc then
        return minigameFunc(callback)
    else
        Debug("ERROR: Invalid minigame type: " .. (Config.Minigame.Type or "nil"))
        return callback(true)
    end
end

local function GetPropKey(entity)
    local coords = GetEntityCoords(entity)
    local model = GetEntityModel(entity)
    local key = model .. "_" .. floor(coords.x) .. "_" .. floor(coords.y) .. "_" .. floor(coords.z)
    Debug("Generated prop key: " .. key)
    return key
end

local function IsPropOnCooldown(entity)
    local propKey = GetPropKey(entity)
    local currentTime = GetGameTimer()
    local isOnCooldown = searchedProps[propKey] and searchedProps[propKey] > currentTime
    Debug("Checking prop cooldown: " .. propKey .. ", on cooldown: " .. tostring(isOnCooldown))
    return isOnCooldown
end

local function SetPropOnCooldown(entity)
    local propKey = GetPropKey(entity)
    searchedProps[propKey] = GetGameTimer() + Config.CooldownDuration
    Debug("Set prop on cooldown: " .. propKey .. ", until: " .. tostring(searchedProps[propKey]))
end

local function PlayAnimation(ped, dict, anim)
    Debug("Playing animation: " .. dict .. " / " .. anim)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do 
        Debug("Waiting for anim dict to load: " .. dict)
        Wait(5) 
    end
    TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 49, 0, false, false, false)
    Debug("Animation started")
end

local function WalkToEntityAndSearch(entity, onComplete)
    local playerPed = PlayerPedId()
    local propCoords = GetEntityCoords(entity)
    Debug("Walking to entity at coords: " .. json.encode(propCoords))
    TaskGoStraightToCoord(playerPed, propCoords.x, propCoords.y, propCoords.z, 1.0, -1, GetEntityHeading(entity), 0.5)
    
    CreateThread(function()
        local reached = false
        while not reached do
            Wait(250)
            local playerCoords = GetEntityCoords(playerPed)
            local distance = #(playerCoords - propCoords)
            Debug("Distance to target: " .. distance)
            if distance < 1.5 then 
                reached = true
                Debug("Reached target, playing animations")
                ClearPedTasks(playerPed)
                
                PlayAnimation(playerPed, "amb@prop_human_bum_bin@base", "base")
                Wait(1500)
                PlayAnimation(playerPed, "amb@prop_human_parking_meter@male@idle_a", "idle_a")
                
                if onComplete then 
                    Debug("Executing onComplete callback")
                    onComplete() 
                end
            end
        end
    end)
end

local function SpawnAttackingDog(propEntity)
    local propCoords = GetEntityCoords(propEntity)
    local dogModel = GetHashKey("a_c_rottweiler")
    Debug("Spawning attack dog at coords: " .. json.encode(propCoords))

    RequestModel(dogModel)
    while not HasModelLoaded(dogModel) do 
        Debug("Waiting for dog model to load")
        Wait(1) 
    end

    local offsetX, offsetY = random(-2, 2), random(-2, 2)
    Debug("Dog offset: " .. offsetX .. ", " .. offsetY)
    local dogPed = CreatePed(28, dogModel, propCoords.x + offsetX, propCoords.y + offsetY, propCoords.z, 0.0, true, true)

    if DoesEntityExist(dogPed) then
        Debug("Dog spawned successfully, entity ID: " .. dogPed)
        TaskCombatPed(dogPed, PlayerPedId(), 0, 16)
        SetEntityAsNoLongerNeeded(dogPed)
        SetModelAsNoLongerNeeded(dogModel)
    else
        Debug("Failed to spawn dog")
    end
end

local function SearchGarbage()
    Debug("SearchGarbage function called")
    
    if isInteracting then 
        Debug("Already interacting, aborting search")
        CustomNotify("You are already searching.", "error")
        return 
    end
    
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    Debug("Player coords: " .. json.encode(coords))
    
    local entity, distance = QBCore.Functions.GetClosestObject(coords, Config.GarbageProps)
    Debug("Closest garbage entity: " .. (entity or "none") .. ", distance: " .. (distance or "n/a"))
    
    if not entity or distance >= 2.0 then
        Debug("No garbage nearby or too far away")
        CustomNotify("No garbage nearby to search.", "error")
        return
    end
    
    if IsPropOnCooldown(entity) then
        Debug("Prop is on cooldown")
        CustomNotify("You've already searched this. Try another.", "error")
        return
    end
    
    local requiredItem = Config.RequiredItem
    Debug("Checking for required item: " .. requiredItem)
    
    local requiredItemLabel = requiredItem
    if QBCore.Shared.Items[requiredItem] and QBCore.Shared.Items[requiredItem].label then
        requiredItemLabel = QBCore.Shared.Items[requiredItem].label
        Debug("Found item label: " .. requiredItemLabel)
    else
        Debug("Could not find item label for: " .. requiredItem)
    end
    
    local hasItem = exports['qb-inventory']:HasItem(requiredItem)
    Debug("Has required item: " .. tostring(hasItem))
    
    if not hasItem then
        CustomNotify("You need a " .. requiredItemLabel .. " to search.", "error")
        return
    end

    Debug("Starting interaction")
    isInteracting = true

    WalkToEntityAndSearch(entity, function()
        Debug("Walk to entity completed")
        
        if IsPropOnCooldown(entity) then
            Debug("Prop was searched by someone else while walking to it")
            CustomNotify("Someone else just searched this. Try another.", "error")
            ClearPedTasks(PlayerPedId())
            isInteracting = false
            return
        end
        
        Debug("Starting minigame")
        RunMinigame(function(success)
            if success then
                Debug("Minigame succeeded, starting progress bar")
                CustomNotify("You found a way to search the garbage!", "success")
                
                local progressOptions = {
                    disableMovement = true,
                    disableCarMovement = true,
                    disableMouse = false,
                    disableCombat = true,
                }
                
                RunProgressBar("Searching garbage...", 5000, progressOptions, 
                    function() -- On complete
                        Debug("Progress bar completed")
                        ClearPedTasks(PlayerPedId())
                        SetPropOnCooldown(entity)
                        TriggerServerEvent('aura-dumpsterdiving:server:RewardItem')
                        Debug("Triggered reward event")

                        local attackRoll = random(1, 100)
                        Debug("Attack chance roll: " .. attackRoll .. " / " .. Config.AttackChance)
                        if attackRoll <= Config.AttackChance then 
                            Debug("Spawning attack dog")
                            SpawnAttackingDog(entity)
                        end
                        
                        isInteracting = false
                        Debug("Interaction completed")
                    end, 
                    function() -- On cancel
                        Debug("Progress bar cancelled")
                        ClearPedTasks(PlayerPedId())
                        CustomNotify("Cancelled", "error")
                        isInteracting = false
                    end
                )
            else
                Debug("Minigame failed")
                CustomNotify("You failed to find a way to search the garbage.", "error")
                ClearPedTasks(PlayerPedId())
                isInteracting = false
            end
        end)
    end)
end

CreateThread(function()
    Debug("Initializing target options for garbage props")
    for _, propModel in ipairs(Config.GarbageProps) do
        exports['qb-target']:AddTargetModel(propModel, {
            options = {
                {
                    event = "aura-dumpsterdiving:client:SearchGarbage",
                    icon = "fas fa-search",
                    label = "Search Garbage",
                },
            },
            distance = 2.5,
        })
        Debug("Added target option for prop: " .. propModel)
    end
    Debug("Target options initialized")
end)

RegisterNetEvent('aura-dumpsterdiving:client:SearchGarbage', SearchGarbage)
Debug("Registered client event: aura-dumpsterdiving:client:SearchGarbage")

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    Debug("Resource stopping: " .. resourceName)
    local playerPed = PlayerPedId()
    if DoesEntityExist(playerPed) then
        Debug("Clearing player tasks on resource stop")
        ClearPedTasks(playerPed)
    end
end)

Debug("Client script loaded")

