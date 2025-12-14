function Target.AddPedInteraction(ped, options)
    exports.ox_target:addLocalEntity(ped, {
        {
            name = 'f4_rental_' .. tostring(options.locationIndex or 1),
            icon = 'fas fa-car',
            label = options.label or 'Open Rental Menu',
            distance = Config.InteractionDistance,
            onSelect = function()
                TriggerEvent('F4-Rental:client:openMenu', options.locationIndex)
            end,
            canInteract = options.canInteract,
        }
    })
end

function Target.AddCoordInteraction(coords, options)
    exports.ox_target:addSphereZone({
        coords = coords,
        radius = Config.InteractionDistance,
        debug = Config.Debug,
        options = {
            {
                name = 'f4_rental_zone_' .. tostring(options.locationIndex or 1),
                icon = 'fas fa-car',
                label = options.label or 'Open Rental Menu',
                onSelect = function()
                    TriggerEvent('F4-Rental:client:openMenu', options.locationIndex)
                end,
                canInteract = options.canInteract,
            }
        }
    })
end

function Target.AddVehicleInteraction(model, options)
    exports.ox_target:addModel(model, {
        {
            name = 'f4_rental_vehicle_' .. tostring(model),
            icon = 'fas fa-key',
            label = options.label or 'Return Vehicle',
            bones = { 'door_dside_f', 'door_pside_f' },
            distance = Config.InteractionDistance,
            onSelect = function(data)
                TriggerEvent('F4-Rental:client:returnVehicle', data.entity)
            end,
            canInteract = options.canInteract,
        }
    })
end

function Target.RemovePed(ped)
    exports.ox_target:removeLocalEntity(ped)
end

function Target.Remove(id)
    exports.ox_target:removeZone(id)
end

function Target.RemoveModel(model)
    exports.ox_target:removeModel(model)
end