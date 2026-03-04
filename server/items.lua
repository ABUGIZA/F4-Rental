exports('rental_contract', function(event, item, inventory, slot, data)
    local source = inventory.id

    -- Open contract on use and prevent item consumption.
    if event ~= 'usingItem' then return end

    local slotData = exports.ox_inventory:GetSlot(source, slot)
    if slotData and slotData.metadata then
        TriggerClientEvent('F4-Rental:client:viewContract', source, slotData.metadata)
    end

    return false
end)

if GetResourceState('qbx_core') == 'started' then
    exports.qbx_core:CreateUseableItem('rental_contract', function(source, item)
        if item and item.info then
            TriggerClientEvent('F4-Rental:client:viewContract', source, item.info)
        end
    end)
elseif GetResourceState('qb-core') == 'started' then
    local QBCore = exports['qb-core']:GetCoreObject()
    if QBCore then
        QBCore.Functions.CreateUseableItem('rental_contract', function(source, item)
            if item and item.info then
                TriggerClientEvent('F4-Rental:client:viewContract', source, item.info)
            end
        end)
    end
end

-- C6 Fix: Validate ownership before granting vehicle keys
RegisterNetEvent('F4-Rental:server:giveKeys', function(netId)
    local source = source
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    -- Validate that this player owns the rental associated with this vehicle
    local rentalId = Entity(vehicle).state.rentalId
    if not rentalId then return end
    
    local cid = Bridge.GetIdentifier(source)
    if not cid or cid == '' then return end
    
    local owner = MySQL.scalar.await('SELECT citizenid FROM rental_history WHERE id = ? AND status = "active"', { rentalId })
    if owner ~= cid then
        if Config.Debug then
            print('[F4-Rental] giveKeys BLOCKED - Player', cid, 'does not own rental', rentalId)
        end
        return
    end
    
    if GetResourceState('qbx_vehiclekeys') == 'started' then
        exports.qbx_vehiclekeys:GiveKeys(source, vehicle)
    end
end)
