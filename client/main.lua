local spawnedPeds = {}
local spawnedBlips = {}
local rentedVehicles = {}
local currentLocation = nil
local returnBlip = nil
local notifiedExpired = {}
local expiredRentalData = {}

function ShowMoneyDeduction(amount)
    CreateThread(function()
        local alpha = 255
        local startTime = GetGameTimer()
        local duration = 3000
        local yOffset = 0.0
        
        while GetGameTimer() - startTime < duration do
            local elapsed = GetGameTimer() - startTime
            
            if elapsed > duration - 800 then
                alpha = math.floor(255 * (1 - (elapsed - (duration - 800)) / 800))
            end
            
            yOffset = (elapsed / duration) * 0.02
            
            SetTextFont(4)
            SetTextScale(0.6, 0.6)
            SetTextColour(200, 50, 50, alpha)
            SetTextDropShadow()
            SetTextOutline()
            SetTextRightJustify(true)
            SetTextWrap(0.0, 0.945)
            SetTextEntry("STRING")
            AddTextComponentString("-$" .. amount)
            DrawText(0.945, 0.058 - yOffset)
            
            Wait(0)
        end
    end)
end

CreateThread(function()
    while not Bridge.Framework do
        Wait(100)
    end

    for i, location in ipairs(Config.Locations) do
        InitializeLocation(i, location)
    end

    if Target.System == 'interact' and Target.AddGlobalRentedVehicleInteraction then
        Target.AddGlobalRentedVehicleInteraction()
    end
end)

function InitializeLocation(index, location)
    if Config.UseBlips and location.blip and location.blip.enabled then
        local blip = Utils.CreateBlip(location.coords, {
            sprite = location.blip.sprite,
            color = location.blip.color,
            scale = location.blip.scale,
            label = location.blip.label or location.name,
        })
        spawnedBlips[index] = blip
    end

    if Config.UsePeds and location.ped and location.ped.enabled then
        local ped = Utils.SpawnPed(location.ped.model, location.coords, location.heading)

        if ped then
            spawnedPeds[index] = ped

            if location.ped.scenario then
                TaskStartScenarioInPlace(ped, location.ped.scenario, 0, true)
            end

            if Target.System ~= 'none' then
                Target.AddPedInteraction(ped, {
                    label = 'Open Rental Menu',
                    locationIndex = index,
                    canInteract = function()
                        return not IsUIOpen()
                    end,
                })
            end
        end
    elseif Target.System ~= 'none' then
        Target.AddCoordInteraction(location.coords, {
            label = '🚗 ' .. location.name,
            locationIndex = index,
        })
    end
end

RegisterNetEvent('F4-Rental:client:openMenu', function(data)
    if IsUIOpen() then return end
    
    local locationIndex = 1
    
    if type(data) == 'number' then
        locationIndex = data
    elseif type(data) == 'table' then
        local rawIndex = data.locationIndex
        
        if type(rawIndex) == 'number' then
            locationIndex = rawIndex
        elseif type(rawIndex) == 'table' and rawIndex.locationIndex then
            locationIndex = tonumber(rawIndex.locationIndex) or 1
        else
            locationIndex = tonumber(rawIndex) or 1
        end
    end
    
    if Config.Debug then
        print('[F4-Rental Client] openMenu - Type:', type(data), 'locationIndex:', locationIndex)
    end
    
    currentLocation = locationIndex
    OpenRentalUI(currentLocation)
end)

RegisterNetEvent('F4-Rental:client:returnVehicle', function(vehicle)
    if not DoesEntityExist(vehicle) then return end

    local isRental = Entity(vehicle).state.rentalVehicle
    if not isRental then
        Bridge.Notify('This is not a rental vehicle', 'error')
        return
    end

    local rentalId = Entity(vehicle).state.rentalId

    if GetResourceState('ox_lib') == 'started' then
        local confirm = lib.alertDialog({
            header = 'Return Vehicle',
            content = 'Are you sure you want to return this rental vehicle?',
            centered = true,
            cancel = true,
        })

        if confirm ~= 'confirm' then return end
    end

    Bridge.TriggerCallback('F4-Rental:server:returnVehicle', function(result)
        if result.success then
            Utils.DeleteVehicle(vehicle)

            local refundMsg = ''
            if result.refund and result.refund > 0 then
                refundMsg = ' (Refunded: $' .. result.refund .. ')'
            end

            Bridge.AdvancedNotify(
                '✅ Vehicle Returned',
                'Thank you for renting with us!' .. refundMsg,
                'success'
            )
        else
            Bridge.Notify(result.message or 'Failed to return vehicle', 'error')
        end
    end, {
        rentalId = rentalId,
        vehicle = VehToNet(vehicle),
    })
end)

if Config.TargetSystem == 'none' or Config.UseMarkers then
    CreateThread(function()
        while true do
            local sleep = 1000
            local playerCoords = GetEntityCoords(PlayerPedId())

            for i, location in ipairs(Config.Locations) do
                local distance = #(playerCoords - location.coords)

                if distance < 10.0 then
                    sleep = 0

                    if Config.UseMarkers then
                        DrawMarker(
                            21,
                            location.coords.x,
                            location.coords.y,
                            location.coords.z - 0.9,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            0.8, 0.8, 0.8,
                            230, 126, 34, 150,
                            false, true, 2, nil, nil, false
                        )
                    end

                    if distance < Config.InteractionDistance then
                        Bridge.DrawText('[E] ' .. location.name, 'primary')

                        if Utils.IsKeyJustPressed(Config.InteractionKey) then
                            Bridge.HideText()
                            currentLocation = i
                            OpenRentalUI(i)
                        end
                    end
                end
            end

            Wait(sleep)
        end
    end)
end

CreateThread(function()
    while true do
        Wait(15000)

        Bridge.TriggerCallback('F4-Rental:server:checkRentals', function(rentals)
            if not rentals then return end

            for _, rental in ipairs(rentals) do
                if rental.timeLeft and rental.timeLeft <= Config.WarnBeforeExpiry and rental.timeLeft > 0 then
                    Bridge.AdvancedNotify(
                        '⚠️ Rental Expiring',
                        'Your ' .. rental.label .. ' expires in ' .. rental.timeLeft .. ' minute(s)!',
                        'warning'
                    )
                end

                if rental.expired then
                    if not notifiedExpired[rental.id] then
                        notifiedExpired[rental.id] = true
                        Bridge.AdvancedNotify(
                            '❌ Rental Expired',
                            rental.label .. ' - Late fees will apply!',
                            'error'
                        )
                    end
                    
                    if Config.DeleteVehicleOnExpiry then
                        local vehicles = GetGamePool('CVehicle')
                        for _, veh in ipairs(vehicles) do
                            if Entity(veh).state.rentalId == rental.id then
                                Utils.DeleteVehicle(veh)
                                rentedVehicles[rental.id] = nil
                                break
                            end
                        end
                    end
                end
            end
        end)
    end
end)

RegisterNetEvent('F4-Rental:client:expiryWarning', function(data)
    if not data then return end
    
    Bridge.AdvancedNotify(
        '⚠️ Rental Expiring Soon!',
        (data.label or 'Rental') .. ' expires in ' .. (data.minutesLeft or 0) .. ' minute(s)!',
        'warning'
    )
    
    if data.returnLocation and data.returnLocation.coords then
        CreateReturnWaypoint(data.returnLocation.coords, data.returnLocation.name or 'Return Vehicle')
    end
end)

RegisterNetEvent('F4-Rental:client:lateFeeApplied', function(data)
    if not data then return end
    
    ShowMoneyDeduction(data.feeAmount or 100)
    PlaySoundFrontend(-1, 'PURCHASE', 'HUD_LIQUOR_STORE_SOUNDSET', true)
    
    if data.returnLocation then
        expiredRentalData[data.rentalId] = data.returnLocation
    end
    
    if data.returnLocation and data.returnLocation.coords then
        CreateReturnWaypoint(data.returnLocation.coords, data.returnLocation.name)
    end
end)

RegisterNetEvent('F4-Rental:client:forceReturn', function(data)
    if not data then return end
    
    Bridge.AdvancedNotify(
        '🚨 Return Vehicle Now!',
        'You cannot afford late fees! Return ' .. data.label .. ' immediately!',
        'error'
    )
    
    if data.returnLocation and data.returnLocation.coords then
        CreateReturnWaypoint(data.returnLocation.coords, data.returnLocation.name)
    end
end)

function CreateReturnWaypoint(coords, name)
    if returnBlip and DoesBlipExist(returnBlip) then
        RemoveBlip(returnBlip)
        returnBlip = nil
    end
    
    returnBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    
    if not returnBlip or returnBlip == 0 then return end
    
    SetBlipSprite(returnBlip, 225)
    SetBlipColour(returnBlip, 1)
    SetBlipScale(returnBlip, 1.5)
    SetBlipFlashes(returnBlip, true)
    SetBlipRoute(returnBlip, true)
    SetBlipRouteColour(returnBlip, 1)
    SetBlipAsShortRange(returnBlip, false)
    
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(name or 'Return Rental Vehicle!')
    EndTextCommandSetBlipName(returnBlip)
    
    SetNewWaypoint(coords.x, coords.y)
end

CreateThread(function()
    while true do
        Wait(2000)
        
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local vehicle = GetVehiclePedIsIn(playerPed, false)
        
        if vehicle and vehicle ~= 0 then
            local rentalId = Entity(vehicle).state.rentalId
            local isRental = Entity(vehicle).state.rentalVehicle
            
            if isRental and rentalId then
                local returnData = expiredRentalData[rentalId]
                
                if returnData and returnData.coords then
                    local returnCoords = returnData.coords
                    local distance = #(playerCoords - vector3(returnCoords.x, returnCoords.y, returnCoords.z))
                    local returnRadius = returnData.returnRadius or 15.0
                    
                    if distance <= returnRadius then
                        PerformAutoReturn(vehicle, rentalId, returnData.name)
                    end
                else
                    for i, location in ipairs(Config.Locations) do
                        local distance = #(playerCoords - location.coords)
                        if distance <= (location.returnRadius or 15.0) then
                            if notifiedExpired[rentalId] then
                                PerformAutoReturn(vehicle, rentalId, location.name)
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end)

function PerformAutoReturn(vehicle, rentalId, locationName)
    expiredRentalData[rentalId] = nil
    notifiedExpired[rentalId] = nil
    rentedVehicles[rentalId] = nil
    
    if returnBlip and DoesBlipExist(returnBlip) then
        SetBlipRoute(returnBlip, false)
        RemoveBlip(returnBlip)
        returnBlip = nil
    end
    
    local playerPed = PlayerPedId()
    TaskLeaveVehicle(playerPed, vehicle, 0)
    
    Wait(1500)
    
    if DoesEntityExist(vehicle) then
        Utils.DeleteVehicle(vehicle)
    end
    
    TriggerServerEvent('F4-Rental:server:vehicleReturned', rentalId)
    
    Bridge.AdvancedNotify(
        '✅ Vehicle Returned',
        'Thank you for returning your rental at ' .. (locationName or 'the rental location') .. '!',
        'success'
    )
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    for _, ped in pairs(spawnedPeds) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end

    for _, blip in pairs(spawnedBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    
    if returnBlip and DoesBlipExist(returnBlip) then
        RemoveBlip(returnBlip)
        returnBlip = nil
    end

    for rentalId, vehicle in pairs(rentedVehicles) do
        if DoesEntityExist(vehicle) then
            local coords = GetEntityCoords(vehicle)
            local heading = GetEntityHeading(vehicle)
            TriggerServerEvent('F4-Rental:server:saveVehiclePosition', rentalId, {
                x = coords.x,
                y = coords.y,
                z = coords.z
            }, heading)
        end
    end

    CloseRentalUI()
end)

CreateThread(function()
    while true do
        Wait(30000)
        
        for rentalId, vehicle in pairs(rentedVehicles) do
            if DoesEntityExist(vehicle) then
                local coords = GetEntityCoords(vehicle)
                local heading = GetEntityHeading(vehicle)
                TriggerServerEvent('F4-Rental:server:saveVehiclePosition', rentalId, {
                    x = coords.x,
                    y = coords.y,
                    z = coords.z
                }, heading)
            end
        end
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(2000)
    RespawnSavedVehicles()
end)

RegisterNetEvent('esx:playerLoaded', function()
    Wait(2000)
    RespawnSavedVehicles()
end)

function RespawnSavedVehicles()
    Bridge.TriggerCallback('F4-Rental:server:getSpawnedVehicles', function(vehicles)
        if not vehicles or #vehicles == 0 then return end
        
        local respawnedCount = 0
        
        for _, v in ipairs(vehicles) do
            CreateThread(function()
                local existingVehicle = FindVehicleByPlate(v.plate)
                if existingVehicle then
                    rentedVehicles[v.id] = existingVehicle
                    return
                end
                
                if rentedVehicles[v.id] and DoesEntityExist(rentedVehicles[v.id]) then
                    return
                end
                
                local modelHash = joaat(v.model)
                RequestModel(modelHash)
                local timeout = 0
                while not HasModelLoaded(modelHash) and timeout < 50 do
                    Wait(100)
                    timeout = timeout + 1
                end
                
                if not HasModelLoaded(modelHash) then return end
                
                local vehicle = CreateVehicle(modelHash, v.coords.x, v.coords.y, v.coords.z, v.heading or 0.0, true, true)
                
                if not vehicle then return end
                
                local existTimeout = 0
                while not DoesEntityExist(vehicle) and existTimeout < 50 do
                    Wait(10)
                    existTimeout = existTimeout + 1
                end
                
                if not DoesEntityExist(vehicle) then return end
                
                if v.plate then
                    SetVehicleNumberPlateText(vehicle, v.plate)
                end
                
                if v.props and lib and lib.setVehicleProperties then
                    lib.setVehicleProperties(vehicle, v.props)
                end
                
                Entity(vehicle).state:set('rentalVehicle', true, true)
                Entity(vehicle).state:set('rentalId', v.id, true)
                
                rentedVehicles[v.id] = vehicle
                respawnedCount = respawnedCount + 1
                
                if Bridge.GiveKeys then
                    Bridge.GiveKeys(vehicle)
                end
                
                SetModelAsNoLongerNeeded(modelHash)
            end)
        end
        
        Wait(1000)
        if respawnedCount > 0 then
            Bridge.Notify('Your rental vehicle(s) are where you left them!', 'success')
        end
    end)
end

function FindVehicleByPlate(plate)
    if not plate then return nil end
    
    local vehicles = GetGamePool('CVehicle')
    for _, veh in ipairs(vehicles) do
        local vehPlate = GetVehicleNumberPlateText(veh)
        if vehPlate and vehPlate:gsub('%s+', '') == plate:gsub('%s+', '') then
            return veh
        end
    end
    return nil
end

exports('GetRentedVehicles', function()
    return rentedVehicles
end)

exports('GetCurrentLocation', function()
    return currentLocation
end)