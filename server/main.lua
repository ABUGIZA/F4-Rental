local activeRentals = {}
local rentalIdCounter = 0
local spawnedRentalVehicles = {}
local warnedRentals = {}
local lastFeeApplied = {}

local function DebugPrint(...)
    if Config.Debug then
        print('[F4-Rental Debug]', ...)
    end
end

print('[F4-Rental] Server loaded - Debug mode:', Config.Debug and 'ENABLED' or 'DISABLED')

Bridge.CreateCallback('F4-Rental:server:getMoney', function(source, moneyType)
    return Bridge.GetMoney(source, moneyType or 'bank')
end)

Bridge.CreateCallback('F4-Rental:server:rentVehicle', function(source, data)
    DebugPrint('rentVehicle callback - Player:', source, 'Model:', data.model, 'Duration:', data.duration, 'Price:', data.totalPrice)
    local identifier = Bridge.GetIdentifier(source)

    if not identifier or identifier == '' then
        DebugPrint('rentVehicle FAILED - Player not found')
        return { success = false, message = 'Player not found' }
    end

    if not data.model or not data.duration or not data.paymentMethod or not data.totalPrice then
        DebugPrint('rentVehicle FAILED - Invalid rental data')
        return { success = false, message = 'Invalid rental data' }
    end

    if not Config.AllowMultipleRentals then
        local existingRentals = MySQL.scalar.await([[
            SELECT COUNT(*) FROM rental_history 
            WHERE citizenid = ? AND status = 'active' AND end_date > NOW()
        ]], { identifier })
        
        if existingRentals and existingRentals > 0 then
            DebugPrint('rentVehicle BLOCKED - Player already has', existingRentals, 'active rentals in database')
            return { success = false, message = 'You already have an active rental' }
        end
    end

    local playerMoney = Bridge.GetMoney(source, data.paymentMethod)
    if playerMoney < data.totalPrice then
        return { success = false, message = 'Insufficient funds' }
    end

    local success = Bridge.RemoveMoney(source, data.paymentMethod, data.totalPrice, 'Car rental - ' .. data.model)
    if not success then
        return { success = false, message = 'Payment failed' }
    end

    local vehicleLabel = data.model
    for _, v in ipairs(Config.Vehicles) do
        if v.model == data.model then
            vehicleLabel = v.label
            break
        end
    end

    local startTime = os.time()
    local rentalHours = data.duration or 24

    local validHours = false
    for _, d in ipairs(Config.RentalDurations) do
        if d.hours == rentalHours then
            validHours = true
            break
        end
    end
    
    if not validHours then
        rentalHours = 24
    end
    
    local durationSeconds = rentalHours * 60 * 60
    local endTime = startTime + durationSeconds
    local startDate = os.date('%Y-%m-%d %H:%M:%S', startTime)
    local endDate = os.date('%Y-%m-%d %H:%M:%S', endTime)

    local dbId = MySQL.insert.await([[
        INSERT INTO rental_history 
        (citizenid, vehicle_model, vehicle_label, rental_price, payment_method, start_date, end_date, location_index, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active')
    ]], { identifier, data.model, vehicleLabel, data.totalPrice, data.paymentMethod, startDate, endDate, data.locationIndex or 1 })

    rentalIdCounter = rentalIdCounter + 1
    local rentalId = dbId or rentalIdCounter

    local rental = {
        id = rentalId,
        identifier = identifier,
        model = data.model,
        label = vehicleLabel,
        duration = data.duration,
        totalPrice = data.totalPrice,
        paymentMethod = data.paymentMethod,
        locationIndex = data.locationIndex,
        startTime = startTime,
        endTime = endTime,
        startDate = startDate,
        endDate = endDate,
    }

    if not activeRentals[source] then
        activeRentals[source] = {}
    end
    table.insert(activeRentals[source], rental)
    
    DebugPrint(('New rental created - ID: %d, Player: %s, Model: %s, Duration: %dh, Price: $%d'):format(
        rentalId, identifier, data.model, data.duration, data.totalPrice
    ))

    if GetResourceState('ox_inventory') == 'started' then
        local contractMetadata = {
            label = 'Rental Contract - ' .. vehicleLabel,
            description = 'Rental contract for ' .. vehicleLabel,
            rentalId = rentalId,
            citizenid = identifier,
            vehicle = vehicleLabel,
            model = data.model,
            price = data.totalPrice,
            duration = data.duration,
            paymentMethod = data.paymentType or 'cash',
            startDate = os.date('%d/%m/%Y %H:%M', startTime),
            endDate = os.date('%d/%m/%Y %H:%M', endTime),
        }
        exports.ox_inventory:AddItem(source, 'rental_contract', 1, contractMetadata)
    elseif GetResourceState('qb-inventory') == 'started' or GetResourceState('qs-inventory') == 'started' then
        local Player = exports.qbx_core:GetPlayer(source)
        if Player then
            local contractInfo = {
                rentalId = rentalId,
                citizenid = identifier,
                vehicle = vehicleLabel,
                model = data.model,
                price = data.totalPrice,
                duration = data.duration,
                startDate = os.date('%d/%m/%Y %H:%M', startTime),
                endDate = os.date('%d/%m/%Y %H:%M', endTime),
            }
            Player.Functions.AddItem('rental_contract', 1, false, contractInfo)
            TriggerClientEvent('inventory:client:ItemBox', source, exports.qbx_core:GetItems()['rental_contract'], 'add')
        end
    end

    Bridge.Notify(source, 'Vehicle rented successfully!', 'success')

    return {
        success = true,
        rentalId = rentalId,
        message = 'Rental confirmed'
    }
end)

Bridge.CreateCallback('F4-Rental:server:returnVehicle', function(source, data)
    DebugPrint('returnVehicle callback - Player:', source, 'RentalID:', data.rentalId)
    local identifier = Bridge.GetIdentifier(source)

    if not identifier or identifier == '' then
        DebugPrint('returnVehicle FAILED - Player not found')
        return { success = false, message = 'Player not found' }
    end

    if not data.rentalId then
        return { success = false, message = 'Invalid rental' }
    end

    local rental = MySQL.single.await([[
        SELECT id, rental_price, payment_method, start_date, end_date,
               UNIX_TIMESTAMP(end_date) as end_timestamp
        FROM rental_history 
        WHERE id = ? AND citizenid = ? AND status = 'active'
    ]], { data.rentalId, identifier })

    if not rental then
        DebugPrint('returnVehicle FAILED - Rental not found in database')
        return { success = false, message = 'Rental not found' }
    end

    local refund = 0
    if Config.RefundOnReturn then
        local timeRemaining = (rental.end_timestamp or 0) - os.time()
        if timeRemaining > 0 then
            local startTimestamp = MySQL.scalar.await('SELECT UNIX_TIMESTAMP(?)', { rental.start_date })
            local totalDuration = (rental.end_timestamp or 0) - (startTimestamp or 0)
            if totalDuration > 0 then
                local percentRemaining = timeRemaining / totalDuration
                refund = math.floor((rental.rental_price or 0) * percentRemaining * (Config.RefundPercentage / 100))

                if refund > 0 then
                    Bridge.AddMoney(source, rental.payment_method or 'cash', refund, 'Car rental refund')
                end
            end
        end
    end

    MySQL.update.await([[
        DELETE FROM rental_history WHERE id = ?
    ]], { data.rentalId })
    
    DebugPrint('returnVehicle SUCCESS - Rental', data.rentalId, 'deleted from database')

    if spawnedRentalVehicles[data.rentalId] then
        spawnedRentalVehicles[data.rentalId] = nil
    end

    if activeRentals[source] then
        for i, r in ipairs(activeRentals[source]) do
            if r.id == data.rentalId then
                table.remove(activeRentals[source], i)
                break
            end
        end
    end

    return {
        success = true,
        refund = refund,
        message = 'Vehicle returned'
    }
end)

Bridge.CreateCallback('F4-Rental:server:checkRentals', function(source)
    local identifier = Bridge.GetIdentifier(source)

    if not identifier or identifier == '' then
        return nil
    end

    local rentals = activeRentals[source]
    if not rentals or #rentals == 0 then
        return nil
    end

    local result = {}
    local currentTime = os.time()

    for _, rental in ipairs(rentals) do
        local timeLeft = math.floor((rental.endTime - currentTime) / 60)

        local label = rental.model
        for _, v in ipairs(Config.Vehicles) do
            if v.model == rental.model then
                label = v.label
                break
            end
        end

        table.insert(result, {
            id = rental.id,
            model = rental.model,
            label = label,
            timeLeft = timeLeft,
            expired = timeLeft <= 0,
        })
    end

    return result
end)

Bridge.CreateCallback('F4-Rental:server:getActiveRentals', function(source)
    local identifier = Bridge.GetIdentifier(source)
    
    if not identifier or identifier == '' then
        return {}
    end
    
    local rentals = MySQL.query.await([[
        SELECT id, vehicle_model, vehicle_label, rental_price, payment_method, 
               start_date, end_date, location_index, status, late_fee_total
        FROM rental_history 
        WHERE citizenid = ? AND status = 'active'
        ORDER BY start_date DESC
    ]], { identifier })
    
    if not rentals or #rentals == 0 then
        return {}
    end
    
    local result = {}
    for _, rental in ipairs(rentals) do
        local isSpawned = spawnedRentalVehicles[rental.id] ~= nil
        
        table.insert(result, {
            id = rental.id,
            model = rental.vehicle_model,
            label = rental.vehicle_label,
            price = rental.rental_price,
            paymentMethod = rental.payment_method,
            startDate = rental.start_date,
            endDate = rental.end_date,
            locationIndex = rental.location_index,
            isSpawned = isSpawned,
            lateFeeTotal = rental.late_fee_total or 0
        })
    end
    
    return result
end)

Bridge.CreateCallback('F4-Rental:server:retrieveRentalVehicle', function(source, data)
    DebugPrint('retrieveRentalVehicle callback - Player:', source, 'RentalID:', data.rentalId)
    local identifier = Bridge.GetIdentifier(source)
    
    if not identifier or identifier == '' then
        DebugPrint('retrieveRentalVehicle FAILED - Player not found')
        return { success = false, message = 'Player not found' }
    end
    
    if not data.rentalId then
        DebugPrint('retrieveRentalVehicle FAILED - Invalid rental ID')
        return { success = false, message = 'Invalid rental ID' }
    end
    
    if spawnedRentalVehicles[data.rentalId] then
        DebugPrint('retrieveRentalVehicle FAILED - Vehicle already spawned (memory)')
        return { success = false, message = 'Vehicle is outside. Search for it!', isSpawned = true }
    end
    
    local isSpawnedInDb = MySQL.scalar.await([[
        SELECT vehicle_spawned FROM rental_history WHERE id = ? AND citizenid = ?
    ]], { data.rentalId, identifier })
    
    if isSpawnedInDb and isSpawnedInDb == 1 then
        DebugPrint('retrieveRentalVehicle FAILED - Vehicle already spawned (database)')
        return { success = false, message = 'Vehicle is already outside. Search for it!', isSpawned = true }
    end
    
    local rental = MySQL.single.await([[
        SELECT id, vehicle_model, vehicle_label, end_date, location_index, vehicle_plate
        FROM rental_history 
        WHERE id = ? AND citizenid = ? AND status = 'active' AND end_date > NOW()
    ]], { data.rentalId, identifier })
    
    if not rental then
        DebugPrint('retrieveRentalVehicle FAILED - Rental not found or expired')
        return { success = false, message = 'Rental not found or expired' }
    end
    
    local plate = rental.vehicle_plate
    if not plate or plate == '' then
        plate = 'RNT' .. math.random(10000, 99999)
        MySQL.update.await('UPDATE rental_history SET vehicle_plate = ? WHERE id = ?', { plate, rental.id })
    end
    
    spawnedRentalVehicles[data.rentalId] = {
        source = source,
        model = rental.vehicle_model,
        label = rental.vehicle_label,
        plate = plate,
        spawnTime = os.time()
    }
    
    MySQL.update.await('UPDATE rental_history SET vehicle_spawned = 1 WHERE id = ?', { rental.id })
    
    DebugPrint('retrieveRentalVehicle SUCCESS - Model:', rental.vehicle_model, 'Plate:', plate)
    return { 
        success = true, 
        model = rental.vehicle_model,
        label = rental.vehicle_label,
        plate = plate,
        rentalId = rental.id,
        locationIndex = rental.location_index or data.locationIndex
    }
end)

Bridge.CreateCallback('F4-Rental:server:getSpawnedVehicles', function(source)
    local identifier = Bridge.GetIdentifier(source)
    
    if not identifier or identifier == '' then
        return {}
    end
    
    local vehicles = MySQL.query.await([[
        SELECT id, vehicle_model, vehicle_plate, vehicle_coords, vehicle_heading, vehicle_props
        FROM rental_history 
        WHERE citizenid = ? AND status = 'active' AND vehicle_spawned = 1 AND end_date > NOW()
    ]], { identifier })
    
    if not vehicles or #vehicles == 0 then
        return {}
    end
    
    local result = {}
    for _, v in ipairs(vehicles) do
        local coords = v.vehicle_coords and json.decode(v.vehicle_coords) or nil
        local props = v.vehicle_props and json.decode(v.vehicle_props) or nil
        
        if coords then
            spawnedRentalVehicles[v.id] = {
                source = source,
                identifier = identifier,
                model = v.vehicle_model,
                plate = v.vehicle_plate,
                spawnTime = os.time()
            }
            
            table.insert(result, {
                id = v.id,
                model = v.vehicle_model,
                plate = v.vehicle_plate,
                coords = coords,
                heading = v.vehicle_heading or 0,
                props = props
            })
        end
    end
    
    return result
end)

Bridge.CreateCallback('F4-Rental:server:getReturnLocation', function(source, rentalId)
    local rental = MySQL.single.await([[
        SELECT location_index FROM rental_history WHERE id = ?
    ]], { rentalId })
    
    if rental and rental.location_index then
        local location = Config.Locations[rental.location_index]
        if location then
            return {
                coords = location.coords,
                name = location.name,
                returnRadius = location.returnRadius or 15.0
            }
        end
    end
    return nil
end)

RegisterNetEvent('F4-Rental:server:vehicleStored', function(rentalId)
    if spawnedRentalVehicles[rentalId] then
        spawnedRentalVehicles[rentalId] = nil
        
        MySQL.update.await([[
            UPDATE rental_history 
            SET vehicle_spawned = 0, vehicle_coords = NULL, vehicle_heading = 0 
            WHERE id = ?
        ]], { rentalId })
    end
end)

RegisterNetEvent('F4-Rental:server:saveVehiclePosition', function(rentalId, coords, heading, props)
    local source = source
    
    if spawnedRentalVehicles[rentalId] and spawnedRentalVehicles[rentalId].source == source then
        local coordsJson = json.encode(coords)
        local propsJson = props and json.encode(props) or nil
        
        MySQL.update.await([[
            UPDATE rental_history 
            SET vehicle_coords = ?, vehicle_heading = ?, vehicle_props = ?
            WHERE id = ?
        ]], { coordsJson, heading or 0, propsJson, rentalId })
    end
end)

RegisterNetEvent('F4-Rental:server:vehicleReturned', function(rentalId)
    local source = source
    local identifier = Bridge.GetIdentifier(source)
    
    if not rentalId then return end
    
    MySQL.update.await([[
        UPDATE rental_history 
        SET status = 'returned', returned_at = NOW(), vehicle_spawned = 0, vehicle_coords = NULL
        WHERE id = ? AND citizenid = ?
    ]], { rentalId, identifier })
    
    if spawnedRentalVehicles[rentalId] then
        spawnedRentalVehicles[rentalId] = nil
    end
    
    if activeRentals[source] then
        for i, r in ipairs(activeRentals[source]) do
            if r.id == rentalId then
                table.remove(activeRentals[source], i)
                break
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local source = source
    
    if activeRentals[source] then
        activeRentals[source] = nil
    end
    
    for rentalId, data in pairs(spawnedRentalVehicles) do
        if data.source == source then
            spawnedRentalVehicles[rentalId] = nil
        end
    end
end)

local function FindPlayerByIdentifier(identifier)
    local players = GetPlayers()
    for _, playerId in ipairs(players) do
        local playerIdentifier = Bridge.GetIdentifier(tonumber(playerId))
        if playerIdentifier == identifier then
            return tonumber(playerId)
        end
    end
    return nil
end

local function ApplyLateFee(source, rental)
    local currentTime = os.time()
    local feeInterval = Config.LateFeeInterval * 60
    local rentalKey = rental.id
    
    local lastTime = lastFeeApplied[rentalKey] or 0
    local timeSinceLast = currentTime - lastTime
    
    if lastTime > 0 and timeSinceLast < feeInterval then
        return
    end
    
    lastFeeApplied[rentalKey] = currentTime
    
    local playerMoney = Bridge.GetMoney(source, 'bank')
    local feeAmount = Config.LateFee
    
    if playerMoney >= feeAmount then
        Bridge.RemoveMoney(source, 'bank', feeAmount, 'Rental late fee - ' .. rental.vehicle_label)
        
        local newTotal = (rental.late_fee_total or 0) + feeAmount
        MySQL.update.await([[
            UPDATE rental_history 
            SET late_fee_total = ?, last_fee_time = NOW() 
            WHERE id = ?
        ]], { newTotal, rental.id })
        
        local location = Config.Locations[rental.location_index or 1]
        
        TriggerClientEvent('F4-Rental:client:lateFeeApplied', source, {
            rentalId = rental.id,
            label = rental.vehicle_label,
            feeAmount = feeAmount,
            totalFees = newTotal,
            returnLocation = location and {
                coords = { x = location.coords.x, y = location.coords.y, z = location.coords.z },
                name = location.name,
                returnRadius = location.returnRadius or 15.0
            } or nil
        })
    else
        Bridge.Notify(source, 'You cannot afford the late fee! Return your rental vehicle immediately.', 'error')
        
        local location = Config.Locations[rental.location_index or 1]
        TriggerClientEvent('F4-Rental:client:forceReturn', source, {
            rentalId = rental.id,
            label = rental.vehicle_label,
            returnLocation = location and {
                coords = { x = location.coords.x, y = location.coords.y, z = location.coords.z },
                name = location.name
            } or nil
        })
    end
end

local function AutoTerminateRental(rental)
    MySQL.update.await([[
        UPDATE rental_history 
        SET status = 'expired', vehicle_spawned = 0, vehicle_coords = NULL 
        WHERE id = ?
    ]], { rental.id })
    
    if spawnedRentalVehicles[rental.id] then
        spawnedRentalVehicles[rental.id] = nil
    end
    
    warnedRentals[rental.id] = nil
end

CreateThread(function()
    Wait(5000)
    
    while true do
        Wait(60000)
        
        local rentals = MySQL.query.await([[
            SELECT id, citizenid, vehicle_model, vehicle_label, 
                   UNIX_TIMESTAMP(end_date) as end_timestamp,
                   UNIX_TIMESTAMP(NOW()) as now_ts,
                   late_fee_total, vehicle_spawned, location_index
            FROM rental_history 
            WHERE status = 'active'
        ]])
        
        if rentals then
            DebugPrint('Checking', #rentals, 'active rentals...')
            for _, rental in ipairs(rentals) do
                local endTime = rental.end_timestamp or 0
                local currentTime = rental.now_ts or os.time()
                local timeLeft = endTime - currentTime
                local minutesLeft = math.floor(timeLeft / 60)
                
                DebugPrint(('Rental #%d (%s) - Time left: %d minutes'):format(rental.id, rental.vehicle_label, minutesLeft))
                
                local playerSource = FindPlayerByIdentifier(rental.citizenid)
                
                if timeLeft <= 0 then
                    DebugPrint('Rental #' .. rental.id .. ' EXPIRED - Applying late fee')
                    if playerSource then
                        ApplyLateFee(playerSource, rental)
                    elseif Config.AutoTerminateOffline then
                        DebugPrint('Rental #' .. rental.id .. ' - Player offline, auto-terminating')
                        AutoTerminateRental(rental)
                    end
                elseif minutesLeft <= Config.WarnBeforeExpiry and not warnedRentals[rental.id] then
                    DebugPrint('Rental #' .. rental.id .. ' EXPIRING SOON - Sending warning')
                    if playerSource then
                        warnedRentals[rental.id] = true
                        local location = Config.Locations[rental.location_index or 1]
                        
                        TriggerClientEvent('F4-Rental:client:expiryWarning', playerSource, {
                            rentalId = rental.id,
                            label = rental.vehicle_label,
                            minutesLeft = minutesLeft,
                            returnLocation = location and {
                                coords = { x = location.coords.x, y = location.coords.y, z = location.coords.z },
                                name = location.name
                            } or nil
                        })
                    end
                end
            end
        end
    end
end)

exports('GetActiveRentals', function(source)
    return activeRentals[source] or {}
end)

exports('GetAllRentals', function()
    return activeRentals
end)

exports('CancelRental', function(source, rentalId)
    if not activeRentals[source] then return false end

    for i, r in ipairs(activeRentals[source]) do
        if r.id == rentalId then
            table.remove(activeRentals[source], i)
            return true
        end
    end

    return false
end)
