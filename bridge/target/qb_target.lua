function Target.AddPedInteraction(ped, options)
    exports['qb-target']:AddTargetEntity(ped, {
        options = {
            {
                type = 'client',
                event = 'F4-Rental:client:openMenu',
                icon = 'fas fa-car',
                label = options.label or 'Open Rental Menu',
                locationIndex = options.locationIndex,
                canInteract = options.canInteract,
            }
        },
        distance = Config.InteractionDistance
    })
end

function Target.AddCoordInteraction(coords, options)
    local zoneId = 'f4_rental_' .. tostring(options.locationIndex or math.random(1000, 9999))
    
    exports['qb-target']:AddCircleZone(zoneId, coords, Config.InteractionDistance, {
        name = zoneId,
        debugPoly = Config.Debug,
        useZ = true,
    }, {
        options = {
            {
                type = 'client',
                event = 'F4-Rental:client:openMenu',
                icon = 'fas fa-car',
                label = options.label or 'Open Rental Menu',
                locationIndex = options.locationIndex,
            }
        },
        distance = Config.InteractionDistance
    })
    
    return zoneId
end

function Target.AddVehicleInteraction(model, options)
    exports['qb-target']:AddTargetModel(model, {
        options = {
            {
                type = 'client',
                event = 'F4-Rental:client:returnVehicle',
                icon = 'fas fa-key',
                label = options.label or 'Return Vehicle',
            }
        },
        distance = Config.InteractionDistance
    })
end

function Target.RemovePed(ped)
    exports['qb-target']:RemoveTargetEntity(ped)
end

function Target.Remove(id)
    exports['qb-target']:RemoveZone(id)
end

function Target.RemoveModel(model)
    exports['qb-target']:RemoveTargetModel(model)
end