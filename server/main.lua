local activeRentals = {}
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
    -- Clean the data - remove client-side info that shouldn't be here
    local cleanData = {
        model = data.model,
        duration = data.duration,
        paymentMethod = data.paymentMethod,
        totalPrice = data.totalPrice,
        locationIndex = data.locationIndex
    }
    
    if type(cleanData.model) ~= 'string' then
        DebugPrint('rentVehicle FAILED - Invalid data format')
        return { success = false, message = 'Invalid request format' }
    end

    DebugPrint('=== CLEANED DATA ===')
    DebugPrint('Model:', cleanData.model)
    DebugPrint('Duration:', cleanData.duration)
    DebugPrint('Payment:', cleanData.paymentMethod)
    DebugPrint('Price:', cleanData.totalPrice)
    DebugPrint('Location:', cleanData.locationIndex)
    DebugPrint('====================')

    local identifier = Bridge.GetIdentifier(source)

    if not identifier or identifier == '' then
        DebugPrint('rentVehicle FAILED - Player not found')
        return { success = false, message = 'Player not found' }
    end

    -- Validate required fields
    if not cleanData.model or not cleanData.duration or not cleanData.paymentMethod or not cleanData.totalPrice then
        DebugPrint('rentVehicle FAILED - Missing required data')
        return { success = false, message = 'Invalid rental data' }
    end

    -- Find vehicle config
    local vehicleConfig = nil
    for _, v in ipairs(Config.Vehicles) do
        if v.model == cleanData.model then
            vehicleConfig = v
            break
        end
    end

    if not vehicleConfig then
        DebugPrint('rentVehicle FAILED - Invalid vehicle model:', cleanData.model)
        return { success = false, message = 'Invalid vehicle model' }
    end

    -- Validate duration (now using minutes as primary field)
    local validDuration = nil
    for _, d in ipairs(Config.RentalDurations) do
        if d.minutes == cleanData.duration then
            validDuration = d
            break
        end
    end

    if not validDuration then
        DebugPrint('rentVehicle FAILED - Invalid duration:', cleanData.duration)
        return { success = false, message = 'Invalid rental duration' }
    end

    -- Validate price (using minutes)
    local expectedPrice = math.floor((vehicleConfig.price / 24 / 60) * validDuration.minutes)
    if math.abs(cleanData.totalPrice - expectedPrice) > 1 then
        DebugPrint('rentVehicle FAILED - Price mismatch. Expected:', expectedPrice, 'Got:', cleanData.totalPrice)
        return { success = false, message = 'Price validation failed' }
    end

    -- Validate location index
    local locationIndex = tonumber(cleanData.locationIndex)
    if not locationIndex or locationIndex < 1 or locationIndex > #Config.Locations then
        DebugPrint('rentVehicle WARNING - Invalid locationIndex, using default 1')
        locationIndex = 1
    end

    -- Check for existing rentals
    if not Config.AllowMultipleRentals then
        local existingRentals = MySQL.scalar.await([[
            SELECT COUNT(*) FROM rental_history 
            WHERE citizenid = ? AND status = 'active' AND end_date > NOW()
        ]], { identifier })
        
        if existingRentals and existingRentals > 0 then
            DebugPrint('rentVehicle BLOCKED - Player has active rentals')
            return { success = false, message = 'You already have an active rental' }
        end
    end

    -- Check player money
    local playerMoney = Bridge.GetMoney(source, cleanData.paymentMethod)
    if playerMoney < cleanData.totalPrice then
        DebugPrint('rentVehicle FAILED - Insufficient funds')
        return { success = false, message = 'Insufficient funds' }
    end

    -- Remove money
    local paymentSuccess = Bridge.RemoveMoney(source, cleanData.paymentMethod, cleanData.totalPrice, 'Car rental - ' .. vehicleConfig.label)
    if not paymentSuccess then
        DebugPrint('rentVehicle FAILED - Payment removal failed')
        return { success = false, message = 'Payment failed' }
    end

    -- Calculate times (using minutes)
    local startTime = os.time()
    local durationSeconds = validDuration.minutes * 60
    local endTime = startTime + durationSeconds
    local startDate = os.date('%Y-%m-%d %H:%M:%S', startTime)
    local endDate = os.date('%Y-%m-%d %H:%M:%S', endTime)

    DebugPrint('=== SQL INSERT ===')
    DebugPrint('citizenid:', identifier)
    DebugPrint('model:', vehicleConfig.model)
    DebugPrint('label:', vehicleConfig.label)
    DebugPrint('price:', cleanData.totalPrice)
    DebugPrint('payment:', cleanData.paymentMethod)
    DebugPrint('start:', startDate)
    DebugPrint('end:', endDate)
    DebugPrint('location:', locationIndex)
    DebugPrint('==================')

    -- Insert into database
    local dbId = MySQL.insert.await([[
        INSERT INTO rental_history 
        (citizenid, vehicle_model, vehicle_label, rental_price, payment_method, start_date, end_date, location_index, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { 
        identifier, 
        vehicleConfig.model, 
        vehicleConfig.label, 
        cleanData.totalPrice, 
        cleanData.paymentMethod, 
        startDate, 
        endDate, 
        locationIndex,
        'active'
    })

    if not dbId then
        DebugPrint('❌ Database insert FAILED - Refunding money')
        Bridge.AddMoney(source, cleanData.paymentMethod, cleanData.totalPrice, 'Rental refund - DB error')
        return { success = false, message = 'Database error, payment refunded' }
    end

    -- Create rental object
    local rental = {
        id = dbId,
        identifier = identifier,
        model = cleanData.model,
        label = vehicleConfig.label,
        duration = cleanData.duration,
        totalPrice = cleanData.totalPrice,
        paymentMethod = cleanData.paymentMethod,
        locationIndex = locationIndex,
        startTime = startTime,
        endTime = endTime,
        startDate = startDate,
        endDate = endDate,
    }

    -- Store in active rentals
    if not activeRentals[source] then
        activeRentals[source] = {}
    end
    table.insert(activeRentals[source], rental)
    
    DebugPrint(('✅ Rental #%d created - %s (%dm) for $%d'):format(
        dbId, vehicleConfig.label, cleanData.duration, cleanData.totalPrice
    ))

    -- Give rental contract
    if GetResourceState('ox_inventory') == 'started' then
        exports.ox_inventory:AddItem(source, 'rental_contract', 1, {
            label = 'Rental Contract - ' .. vehicleConfig.label,
            description = 'Rental contract for ' .. vehicleConfig.label,
            rentalId = dbId,
            citizenid = identifier,
            vehicle = vehicleConfig.label,
            model = cleanData.model,
            price = cleanData.totalPrice,
            duration = cleanData.duration,
            paymentMethod = cleanData.paymentMethod,
            startDate = os.date('%d/%m/%Y %H:%M', startTime),
            endDate = os.date('%d/%m/%Y %H:%M', endTime),
        })
    elseif GetResourceState('qb-inventory') == 'started' or GetResourceState('qs-inventory') == 'started' then
        local Player = Bridge.GetPlayer(source)
        if Player then
            Player.Functions.AddItem('rental_contract', 1, false, {
                rentalId = dbId,
                citizenid = identifier,
                vehicle = vehicleConfig.label,
                model = cleanData.model,
                price = cleanData.totalPrice,
                duration = cleanData.duration,
                startDate = os.date('%d/%m/%Y %H:%M', startTime),
                endDate = os.date('%d/%m/%Y %H:%M', endTime),
            })
        end
    end

    local durationText = cleanData.duration >= 60 and (cleanData.duration / 60) .. 'h' or cleanData.duration .. 'min'
    Bridge.Notify(source, 'Vehicle rented successfully! Duration: ' .. durationText, 'success')

    return {
        success = true,
        rentalId = dbId,
        rental = rental,
        message = 'Rental confirmed'
    }
end)

Bridge.CreateCallback('F4-Rental:server:returnVehicle', function(source, data)
    if type(data) ~= 'table' then
        return { success = false, message = 'Invalid request format' }
    end

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

    local rentals = MySQL.query.await([[
        SELECT id, vehicle_model, vehicle_label, 
               UNIX_TIMESTAMP(end_date) as end_timestamp,
               UNIX_TIMESTAMP(NOW()) as now_ts
        FROM rental_history 
        WHERE citizenid = ? AND status = 'active'
    ]], { identifier })

    if not rentals or #rentals == 0 then
        return nil
    end

    local result = {}
    for _, rental in ipairs(rentals) do
        local timeLeft = math.floor((rental.end_timestamp - rental.now_ts) / 60)

        table.insert(result, {
            id = rental.id,
            model = rental.vehicle_model,
            label = rental.vehicle_label,
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
    if type(data) ~= 'table' then
        return { success = false, message = 'Invalid request format' }
    end

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
        locationIndex = rental.location_index or tonumber(data.locationIndex) or 1
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
    local source = source
    local identifier = Bridge.GetIdentifier(source)
    
    if not identifier or identifier == '' then return end
    
    local rental = MySQL.single.await('SELECT citizenid FROM rental_history WHERE id = ?', { rentalId })
    if not rental or rental.citizenid ~= identifier then
        DebugPrint('vehicleStored BLOCKED - Ownership validation failed for rental', rentalId)
        return
    end
    
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
    local identifier = Bridge.GetIdentifier(source)
    
    if not identifier or identifier == '' then return end
    
    local rental = MySQL.single.await('SELECT citizenid FROM rental_history WHERE id = ?', { rentalId })
    if not rental or rental.citizenid ~= identifier then
        DebugPrint('saveVehiclePosition BLOCKED - Ownership validation failed for rental', rentalId)
        return
    end
    
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
