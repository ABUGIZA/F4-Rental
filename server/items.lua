exports('rental_contract', function(event, item, inventory, slot, data)
    local source = inventory.id
    
    if event == 'usingItem' or event == 'usedItem' then
        local slotData = exports.ox_inventory:GetSlot(source, slot)
        
        if slotData and slotData.metadata then
            TriggerClientEvent('F4-Rental:client:viewContract', source, slotData.metadata)
        end
    end
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

RegisterNetEvent('F4-Rental:server:giveKeys', function(netId)
    local source = source
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    
    if vehicle and DoesEntityExist(vehicle) then
        if GetResourceState('qbx_vehiclekeys') == 'started' then
            exports.qbx_vehiclekeys:GiveKeys(source, vehicle)
        end
    end
end)
