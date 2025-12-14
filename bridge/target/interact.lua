function Target.AddPedInteraction(ped, options)
    exports.interact:AddLocalEntityInteraction({
        entity = ped,
        id = 'f4_rental_ped_' .. tostring(options.locationIndex or 1),
        name = 'f4_rental',
        distance = Config.InteractionDistance + 5,
        interactDst = Config.InteractionDistance,
        ignoreLos = false,
        options = {
            {
                label = options.label or 'Open Rental Menu',
                action = function()
                    TriggerEvent('F4-Rental:client:openMenu', options.locationIndex)
                end,
                canInteract = options.canInteract,
            }
        }
    })
end

function Target.AddCoordInteraction(coords, options)
    local interactionId = 'f4_rental_coord_' .. tostring(options.locationIndex or math.random(1000, 9999))
    
    exports.interact:AddInteraction({
        coords = coords,
        id = interactionId,
        name = 'f4_rental',
        distance = Config.InteractionDistance + 5,
        interactDst = Config.InteractionDistance,
        options = {
            {
                label = options.label or 'Open Rental Menu',
                action = function()
                    TriggerEvent('F4-Rental:client:openMenu', options.locationIndex)
                end,
            }
        }
    })
    
    return interactionId
end

function Target.AddVehicleInteraction(model, options)
    exports.interact:AddModelInteraction({
        model = model,
        id = 'f4_rental_vehicle_' .. tostring(model),
        name = 'f4_rental_vehicle',
        distance = Config.InteractionDistance + 3,
        interactDst = Config.InteractionDistance,
        offset = vec3(0.0, 0.0, 0.0),
        options = {
            {
                label = options.label or 'Return Vehicle',
                action = function(entity)
                    TriggerEvent('F4-Rental:client:returnVehicle', entity)
                end,
                canInteract = options.canInteract,
            }
        }
    })
end

function Target.RemovePed(ped, id)
    exports.interact:RemoveLocalEntityInteraction(ped, id or 'f4_rental_ped_1')
end

function Target.Remove(id)
    exports.interact:RemoveInteraction(id)
end

function Target.RemoveModel(model, id)
    exports.interact:RemoveModelInteraction(model, id or 'f4_rental_vehicle_' .. tostring(model))
end

function Target.AddGlobalRentedVehicleInteraction()
    exports.interact:AddGlobalVehicleInteraction({
        id = 'f4_rental_global_vehicle',
        name = 'f4_rental_return',
        distance = Config.InteractionDistance + 3,
        interactDst = Config.InteractionDistance,
        options = {
            {
                label = 'Return Rental Vehicle',
                action = function(entity)
                    TriggerEvent('F4-Rental:client:returnVehicle', entity)
                end,
                canInteract = function(entity)
                    local isRented = Entity(entity).state.rentalVehicle
                    return isRented == true
                end,
            }
        }
    })
end

function Target.RemoveGlobalVehicleInteraction()
    exports.interact:RemoveGlobalVehicleInteraction('f4_rental_global_vehicle')
end