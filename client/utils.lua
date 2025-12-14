local Utils = {}

function Utils.LoadModel(model)
    local hash = type(model) == 'string' and GetHashKey(model) or model

    if not IsModelInCdimage(hash) then
        return false
    end

    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) do
        Wait(10)
        timeout = timeout + 10
        if timeout > 10000 then
            return false
        end
    end

    return true
end

function Utils.LoadAnimDict(dict)
    if HasAnimDictLoaded(dict) then return true end

    RequestAnimDict(dict)
    local timeout = 0
    while not HasAnimDictLoaded(dict) do
        Wait(10)
        timeout = timeout + 10
        if timeout > 5000 then
            return false
        end
    end

    return true
end

function Utils.SpawnVehicle(model, coords)
    if not Utils.LoadModel(model) then return nil end

    local hash = type(model) == 'string' and GetHashKey(model) or model
    local vehicle = CreateVehicle(hash, coords.x, coords.y, coords.z, coords.w, true, false)

    SetModelAsNoLongerNeeded(hash)

    if DoesEntityExist(vehicle) then
        SetVehicleOnGroundProperly(vehicle)
        SetEntityAsMissionEntity(vehicle, true, true)
        SetVehicleHasBeenOwnedByPlayer(vehicle, true)
        SetVehicleNeedsToBeHotwired(vehicle, false)
        SetVehicleEngineOn(vehicle, true, true, false)
        SetVehicleUndriveable(vehicle, false)
        SetVehicleIsStolen(vehicle, false)
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehiclePetrolTankHealth(vehicle, 1000.0)
        SetVehicleBodyHealth(vehicle, 1000.0)

        if Config.FuelLevel then
            if GetResourceState('ox_fuel') == 'started' then
                Entity(vehicle).state:set('fuel', Config.FuelLevel, true)
            elseif GetResourceState('LegacyFuel') == 'started' then
                exports['LegacyFuel']:SetFuel(vehicle, Config.FuelLevel)
            elseif GetResourceState('cdn-fuel') == 'started' then
                exports['cdn-fuel']:SetFuel(vehicle, Config.FuelLevel)
            end
        end
        
        CreateThread(function()
            Wait(500)
            if DoesEntityExist(vehicle) then
                SetVehicleEngineOn(vehicle, true, true, false)
            end
        end)

        return vehicle
    end

    return nil
end

function Utils.DeleteVehicle(vehicle)
    if DoesEntityExist(vehicle) then
        SetEntityAsMissionEntity(vehicle, false, true)
        DeleteVehicle(vehicle)
    end
end

function Utils.SpawnPed(model, coords, heading)
    if not Utils.LoadModel(model) then 
        return nil 
    end

    local hash = GetHashKey(model)
    local ped = CreatePed(4, hash, coords.x, coords.y, coords.z - 1.0, heading, false, true)

    SetModelAsNoLongerNeeded(hash)

    if DoesEntityExist(ped) then
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        return ped
    end

    return nil
end

function Utils.CreateBlip(coords, options)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)

    SetBlipSprite(blip, options.sprite or 225)
    SetBlipColour(blip, options.color or 17)
    SetBlipScale(blip, options.scale or 0.8)
    SetBlipAsShortRange(blip, true)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(options.label or 'Car Rental')
    EndTextCommandSetBlipName(blip)

    return blip
end

function Utils.GetDistanceToCoords(coords)
    local playerCoords = GetEntityCoords(PlayerPedId())
    return #(playerCoords - coords)
end

function Utils.IsNearCoords(coords, distance)
    return Utils.GetDistanceToCoords(coords) <= distance
end

function Utils.IsKeyJustPressed(key)
    return IsControlJustPressed(0, key)
end

function Utils.DrawText3D(msg, coords, scale)
    scale = scale or 0.35

    SetTextScale(scale, scale)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry('STRING')
    SetTextCentre(1)
    AddTextComponentString(msg)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

_G.Utils = Utils
return Utils