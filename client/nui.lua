local isUIOpen = false

local function DebugPrint(...)
    if Config.Debug then
        print('[F4-Rental Client Debug]', ...)
    end
end
function OpenRentalUI(locationIndex, vehicleData)
    if isUIOpen then return end

    isUIOpen = true
    SetNuiFocus(true, true)

    local vehicles = vehicleData or Config.Vehicles
    local formattedVehicles = {}

    for i, v in ipairs(vehicles) do
        formattedVehicles[i] = {
            model = v.model,
            label = v.label,
            manufacturer = v.manufacturer,
            category = v.category,
            price = v.price,
            image = v.image,
            stats = v.stats,
        }
    end

    local durations = {}
    for i, d in ipairs(Config.RentalDurations) do
        durations[i] = {
            days = d.days,
            label = d.label,
            multiplier = d.multiplier,
            hours = d.hours or (d.days * 24),
        }
    end

    local payments = {}
    for i, p in ipairs(Config.PaymentMethods) do
        payments[i] = {
            id = p.id,
            label = p.label,
            icon = p.icon,
        }
    end

    SendNUIMessage({
        action = 'open',
        vehicles = formattedVehicles,
        durations = durations,
        payments = payments,
        locationIndex = locationIndex or 1,
    })
end

function CloseRentalUI()
    if not isUIOpen then return end

    isUIOpen = false
    SetNuiFocus(false, false)

    SendNUIMessage({
        action = 'close'
    })
end

function IsUIOpen()
    return isUIOpen
end

RegisterNUICallback('close', function(_, cb)
    isUIOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('getMoney', function(data, cb)
    Bridge.TriggerCallback('F4-Rental:server:getMoney', function(money)
        cb(money)
    end, data.type or 'bank')
end)

RegisterNUICallback('confirmRental', function(data, cb)
    DebugPrint('confirmRental callback - Model:', data.model, 'Duration:', data.duration, 'Payment:', data.paymentMethod)
    if not data.model or not data.duration or not data.paymentMethod then
        DebugPrint('confirmRental FAILED - Invalid rental data')
        Bridge.Notify('Invalid rental data', 'error')
        cb({ success = false, message = 'Invalid rental data' })
        return
    end

    local vehicleConfig = nil
    for _, v in ipairs(Config.Vehicles) do
        if v.model == data.model then
            vehicleConfig = v
            break
        end
    end

    if not vehicleConfig then
        DebugPrint('confirmRental FAILED - Vehicle not found:', data.model)
        Bridge.Notify('Vehicle not found', 'error')
        cb({ success = false, message = 'Vehicle not found' })
        return
    end

    local hours = data.duration or 24
    local hourlyRate = vehicleConfig.price / 24
    local totalPrice = math.floor(hourlyRate * hours)
    DebugPrint('confirmRental - Price calculated:', totalPrice, 'Hours:', hours)

    Bridge.TriggerCallback('F4-Rental:server:rentVehicle', function(result)
        if result.success then
            isUIOpen = false
            SetNuiFocus(false, false)
            SendNUIMessage({ action = 'close' })

            local currentLocation = Config.Locations[data.locationIndex or 1]
            if currentLocation then
                local spawnCoords = currentLocation.spawnPoint
                local vehicle = Utils.SpawnVehicle(data.model, spawnCoords)

                if vehicle then
                    Entity(vehicle).state:set('rentalVehicle', true, true)
                    Entity(vehicle).state:set('rentalId', result.rentalId, true)

                    if Config.GiveKeys then
                        Bridge.GiveKeys(vehicle)
                    end

                    TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)

                    Bridge.AdvancedNotify(
                        '🚗 Rental Confirmed',
                        'You rented ' .. vehicleConfig.label .. ' for ' .. data.duration .. ' hour(s)',
                        'success'
                    )
                else
                    Bridge.Notify('Failed to spawn vehicle', 'error')
                end
            end
        else
            Bridge.Notify(result.message or 'Rental failed', 'error')
        end

        cb(result)
    end, {
        model = data.model,
        duration = data.duration,
        paymentMethod = data.paymentMethod,
        totalPrice = totalPrice,
        locationIndex = data.locationIndex or 1,
    })
end)

RegisterNUICallback('selectVehicle', function(data, cb)
    cb('ok')
end)

RegisterNUICallback('searchVehicles', function(data, cb)
    local searchTerm = data.term:lower()
    local filtered = {}

    for _, v in ipairs(Config.Vehicles) do
        if v.label:lower():find(searchTerm) or
           v.manufacturer:lower():find(searchTerm) or
           v.category:lower():find(searchTerm) then
            table.insert(filtered, v)
        end
    end

    cb(filtered)
end)

RegisterNetEvent('F4-Rental:client:viewContract', function(contractData)
    if not contractData then return end

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openContract',
        contract = contractData
    })
end)

RegisterNUICallback('closeContract', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('getMyRentals', function(_, cb)
    cb('ok')
    
    CreateThread(function()
        local rentals = lib.callback.await('F4-Rental:server:getActiveRentals', false)
        
        SendNUIMessage({
            action = 'receiveMyRentals',
            rentals = rentals or {}
        })
    end)
end)

RegisterNUICallback('retrieveVehicle', function(data, cb)
    if not data.rentalId then
        cb({ success = false, message = 'Invalid rental' })
        return
    end
    
    Bridge.TriggerCallback('F4-Rental:server:retrieveRentalVehicle', function(result)
        if result.success then
            local locationIndex = data.locationIndex or result.locationIndex or 1
            local location = Config.Locations[locationIndex]
            
            if not location then
                cb({ success = false, message = 'Location not found' })
                return
            end
            
            local vehicle = Utils.SpawnVehicle(result.model, location.spawnPoint)
            
            if vehicle then
                if result.plate then
                    SetVehicleNumberPlateText(vehicle, result.plate)
                end
                
                Entity(vehicle).state:set('rentalVehicle', true, true)
                Entity(vehicle).state:set('rentalId', result.rentalId, true)
                
                local rentedVehicles = exports['F4-Rental']:GetRentedVehicles()
                rentedVehicles[result.rentalId] = vehicle
                
                if Config.GiveKeys and Bridge.GiveKeys then
                    Bridge.GiveKeys(vehicle)
                end
                
                TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
                
                Bridge.AdvancedNotify('✅ Vehicle Retrieved', 'Your ' .. result.label .. ' is ready!', 'success')
                cb({ success = true })
            else
                TriggerServerEvent('F4-Rental:server:vehicleStored', result.rentalId)
                cb({ success = false, message = 'Failed to spawn vehicle' })
            end
        else
            if result.isSpawned then
                Bridge.AdvancedNotify('🚗 Vehicle Outside', result.message, 'warning')
            else
                Bridge.AdvancedNotify('❌ Error', result.message, 'error')
            end
            cb(result)
        end
    end, { rentalId = data.rentalId, locationIndex = data.locationIndex })
end)

exports('OpenRentalUI', OpenRentalUI)
exports('CloseRentalUI', CloseRentalUI)
exports('IsUIOpen', IsUIOpen)