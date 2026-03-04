local activeRentals = {}
local spawnedRentalVehicles = {}
local warnedRentals = {}
local lastFeeApplied = {}

-- Seed random once on resource start for unique plate generation
math.randomseed(os.time())

local function DebugPrint(...)
    if Config.Debug then
        print('[F4-Rental Debug]', ...)
    end
end

-- Helper: Generate a unique plate that doesn't collide with existing rentals
local function GenerateUniquePlate()
    local attempts = 0
    while attempts < 20 do
        local plate = 'RNT' .. math.random(10000, 99999)
        local exists = MySQL.scalar.await('SELECT COUNT(*) FROM rental_history WHERE vehicle_plate = ?', { plate })
        if not exists or exists == 0 then
            return plate
        end
        attempts = attempts + 1
    end
    -- Fallback: use timestamp-based plate to guarantee uniqueness
    return 'RNT' .. tostring(os.time()):sub(-5)
end

-- Helper: Remove the rental_contract item from a player's inventory by rentalId
local function RemoveContractItem(playerId, rentalId)
    if not playerId or not rentalId then return end
    
    if GetResourceState('ox_inventory') == 'started' then
        local items = exports.ox_inventory:Search(playerId, 'slots', 'rental_contract')
        if items then
            for _, item in pairs(items) do
                if item and item.metadata and item.metadata.rentalId == rentalId then
                    exports.ox_inventory:RemoveItem(playerId, 'rental_contract', 1, nil, item.slot)
                    DebugPrint('RemoveContractItem - Removed contract from slot', item.slot, 'for rental', rentalId)
                    return true
                end
            end
        end
    elseif GetResourceState('qb-inventory') == 'started' or GetResourceState('qs-inventory') == 'started' then
        local Player = Bridge.GetPlayer(playerId)
        if Player then
            local items = Player.PlayerData and Player.PlayerData.items or {}
            for slot, item in pairs(items) do
                if item and item.name == 'rental_contract' and item.info and item.info.rentalId == rentalId then
                    Player.Functions.RemoveItem('rental_contract', 1, slot)
                    DebugPrint('RemoveContractItem - Removed contract from slot', slot, 'for rental', rentalId)
                    return true
                end
            end
        end
    end
    return false
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
    local expectedPrice = math.ceil((vehicleConfig.price / 24 / 60) * validDuration.minutes)
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

    -- Check for existing rentals (includes expired-but-not-returned)
    if not Config.AllowMultipleRentals then
        local existingRentals = MySQL.scalar.await([[
            SELECT COUNT(*) FROM rental_history 
            WHERE citizenid = ? AND status = 'active'
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

    -- C9 Fix: Generate unique plate and persist in DB
    local plate = GenerateUniquePlate()
    MySQL.update.await('UPDATE rental_history SET vehicle_plate = ? WHERE id = ?', { plate, dbId })

    return {
        success = true,
        rentalId = dbId,
        plate = plate,
        rental = rental,
        message = 'Rental confirmed'
    }
end)

Bridge.CreateCallback('F4-Rental:server:returnVehicle', function(source, data)
    DebugPrint('=== returnVehicle DEBUG ===')
    DebugPrint('Data type:', type(data))
    DebugPrint('Data:', json.encode(data or {}))

    if type(data) ~= 'table' then
        DebugPrint('returnVehicle FAILED - Invalid data type:', type(data))
        return { success = false, message = 'Invalid request format' }
    end

    local rentalId = tonumber(data.rentalId)
    if not rentalId then
        return { success = false, message = 'Invalid rental' }
    end

    -- C5 Fix: Validate vehicle proof (entity must exist)
    local netId = tonumber(data.vehicle)
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if veh == 0 or not DoesEntityExist(veh) then
        DebugPrint('returnVehicle FAILED - Vehicle proof missing or invalid')
        return { success = false, message = 'Vehicle not found' }
    end

    -- Pass-2 Fix #1: Verify entity state matches the claimed rentalId
    local vehState = Entity(veh).state
    if not vehState.rentalVehicle then
        DebugPrint('returnVehicle FAILED - Entity is not a rental vehicle')
        return { success = false, message = 'This is not a rental vehicle' }
    end
    local entityRentalId = tonumber(vehState.rentalId)
    if entityRentalId ~= rentalId then
        DebugPrint('returnVehicle FAILED - Entity rentalId mismatch:', vehState.rentalId, '~=', rentalId)
        return { success = false, message = 'Vehicle does not match this rental' }
    end

    DebugPrint('returnVehicle callback - Player:', source, 'RentalID:', rentalId)
    local identifier = Bridge.GetIdentifier(source)

    if not identifier or identifier == '' then
        DebugPrint('returnVehicle FAILED - Player not found')
        return { success = false, message = 'Player not found' }
    end

    local rental = MySQL.single.await([[
        SELECT id, rental_price, payment_method, start_date, end_date,
               UNIX_TIMESTAMP(end_date) as end_timestamp, location_index
        FROM rental_history 
        WHERE id = ? AND citizenid = ? AND status = 'active'
    ]], { rentalId, identifier })

    if not rental then
        DebugPrint('returnVehicle FAILED - Rental not found in database')
        return { success = false, message = 'Rental not found' }
    end

    -- H2 / Pass-2 Fix #4: Enforce ReturnAtAnyLocation config
    -- When false, only allow return at the SAME location where the vehicle was rented
    if not Config.ReturnAtAnyLocation then
        local playerPed = GetPlayerPed(source)
        if playerPed and playerPed ~= 0 then
            local playerCoords = GetEntityCoords(playerPed)
            local originLocation = Config.Locations[rental.location_index or 1]
            if originLocation then
                local dist = #(playerCoords - originLocation.coords)
                if dist > (originLocation.returnRadius or 15.0) then
                    DebugPrint('returnVehicle FAILED - Not near original rental location')
                    return { success = false, message = 'You must return the vehicle at the location where you rented it (' .. (originLocation.name or 'Unknown') .. ')' }
                end
            end
        end
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

    -- Delete rental from database
    DebugPrint('Attempting DELETE - RentalID:', rentalId, 'CitizenID:', identifier)

    local result = MySQL.query.await([[
        DELETE FROM rental_history WHERE id = ? AND citizenid = ?
    ]], { rentalId, identifier })

    DebugPrint('DELETE result type:', type(result))
    DebugPrint('DELETE result:', json.encode(result or {}))

    local affectedRows = type(result) == 'number' and result or (type(result) == 'table' and result.affectedRows or 0)
    DebugPrint('Affected rows:', affectedRows)

    if not affectedRows or affectedRows == 0 then
        DebugPrint('returnVehicle FAILED - Database delete failed, no rows affected')
        return { success = false, message = 'Failed to delete rental' }
    end

    DebugPrint('returnVehicle SUCCESS - Rental', rentalId, 'deleted from database (', affectedRows, 'rows)')

    -- Remove rental_contract item from player inventory
    RemoveContractItem(source, rentalId)

    -- Clean up memory
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

    -- Clear warning flags
    if warnedRentals[rentalId] then
        warnedRentals[rentalId] = nil
    end

    if lastFeeApplied[rentalId] then
        lastFeeApplied[rentalId] = nil
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
    
    -- C8 Fix: Check memory lock AND set pending lock atomically (pre-yield)
    if spawnedRentalVehicles[data.rentalId] then
        DebugPrint('retrieveRentalVehicle FAILED - Vehicle already spawned or pending (memory)')
        return { success = false, message = 'Vehicle is outside. Search for it!', isSpawned = true }
    end
    -- Set pending lock before any async call to prevent race condition
    spawnedRentalVehicles[data.rentalId] = { pending = true, source = source }
    
    -- C4 Fix: Check DB spawned flag and recover stale state
    local spawnCheck = MySQL.single.await([[
        SELECT vehicle_spawned, vehicle_coords FROM rental_history WHERE id = ? AND citizenid = ?
    ]], { data.rentalId, identifier })
    
    if spawnCheck and spawnCheck.vehicle_spawned == 1 then
        if not spawnCheck.vehicle_coords then
            -- C4: Stale flag with no coords — reset it
            DebugPrint('retrieveRentalVehicle - Recovering stale vehicle_spawned flag for rental', data.rentalId)
            MySQL.update.await('UPDATE rental_history SET vehicle_spawned = 0 WHERE id = ?', { data.rentalId })
        else
            -- Vehicle really is spawned somewhere
            spawnedRentalVehicles[data.rentalId] = nil -- release lock
            DebugPrint('retrieveRentalVehicle FAILED - Vehicle already spawned (database with coords)')
            return { success = false, message = 'Vehicle is already outside. Search for it!', isSpawned = true }
        end
    end
    
    local rental = MySQL.single.await([[
        SELECT id, vehicle_model, vehicle_label, end_date, location_index, vehicle_plate,
               UNIX_TIMESTAMP(end_date) as end_timestamp, UNIX_TIMESTAMP(NOW()) as now_ts
        FROM rental_history 
        WHERE id = ? AND citizenid = ? AND status = 'active'
    ]], { data.rentalId, identifier })
    
    if not rental then
        spawnedRentalVehicles[data.rentalId] = nil -- C8: release lock on failure
        DebugPrint('retrieveRentalVehicle FAILED - Rental not found')
        return { success = false, message = 'Rental not found' }
    end
    
    local isExpired = rental.end_timestamp and rental.now_ts and (rental.end_timestamp < rental.now_ts)
    if isExpired then
        DebugPrint('retrieveRentalVehicle - Rental is EXPIRED but allowing retrieval for return')
    end
    
    local plate = rental.vehicle_plate
    if not plate or plate == '' then
        plate = GenerateUniquePlate()
        MySQL.update.await('UPDATE rental_history SET vehicle_plate = ? WHERE id = ?', { plate, rental.id })
    end
    
    -- Pass-2 Fix #3: Store structure with netId=nil; client will update via vehicleSpawned event
    spawnedRentalVehicles[data.rentalId] = {
        source = source,
        netId = nil, -- updated when client fires vehicleSpawned
        model = rental.vehicle_model,
        label = rental.vehicle_label,
        plate = plate,
        spawnTime = os.time()
    }
    
    MySQL.update.await('UPDATE rental_history SET vehicle_spawned = 1, vehicle_coords = NULL WHERE id = ?', { rental.id })
    
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

    -- If RespawnOnReconnect is disabled, reset all spawned flags so player retrieves from NPC menu
    if not Config.RespawnOnReconnect then
        MySQL.update.await([[
            UPDATE rental_history
            SET vehicle_spawned = 0, vehicle_coords = NULL, vehicle_heading = 0
            WHERE citizenid = ? AND status = 'active' AND vehicle_spawned = 1
        ]], { identifier })
        DebugPrint('getSpawnedVehicles - RespawnOnReconnect disabled, reset spawned flags for', identifier)
        return {}
    end
    
    local vehicles = MySQL.query.await([[
        SELECT id, vehicle_model, vehicle_plate, vehicle_coords, vehicle_heading, vehicle_props
        FROM rental_history 
        WHERE citizenid = ? AND status = 'active' AND vehicle_spawned = 1
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

-- C3 Fix: Register vehicle spawn on server when client spawns from initial rent
RegisterNetEvent('F4-Rental:server:vehicleSpawned', function(rentalId, netId)
    local src = source
    local cid = Bridge.GetIdentifier(src)
    if not cid or cid == '' then return end
    if not rentalId then return end

    -- Validate rental belongs to this player and is active
    local row = MySQL.single.await(
        'SELECT id FROM rental_history WHERE id = ? AND citizenid = ? AND status = "active"',
        { rentalId, cid }
    )
    if not row then
        DebugPrint('vehicleSpawned BLOCKED - Rental not found or not owned by player', rentalId)
        return
    end

    -- If already tracked from retrieve path, just update netId
    if spawnedRentalVehicles[rentalId] and not spawnedRentalVehicles[rentalId].pending then
        -- Pass-2 Fix #3: Update netId on existing entry (retrieve path sets netId=nil initially)
        if netId and not spawnedRentalVehicles[rentalId].netId then
            spawnedRentalVehicles[rentalId].netId = netId
            DebugPrint('vehicleSpawned - Updated netId for rental', rentalId, 'netId:', netId)
        else
            DebugPrint('vehicleSpawned SKIPPED - Already tracked in memory', rentalId)
        end
        return
    end

    spawnedRentalVehicles[rentalId] = {
        source = src,
        netId = netId,
        spawnTime = os.time()
    }
    MySQL.update.await('UPDATE rental_history SET vehicle_spawned = 1 WHERE id = ?', { rentalId })
    DebugPrint('vehicleSpawned SUCCESS - Rental', rentalId, 'marked as spawned')
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

-- H6 Fix: Allow position saves when rental is verified via DB ownership, 
-- not just memory (handles C3 initial spawn case)
RegisterNetEvent('F4-Rental:server:saveVehiclePosition', function(rentalId, coords, heading, props)
    local source = source
    local identifier = Bridge.GetIdentifier(source)
    
    if not identifier or identifier == '' then return end
    if not rentalId or not coords then return end
    
    -- Verify ownership via DB
    local rental = MySQL.single.await('SELECT citizenid FROM rental_history WHERE id = ? AND status = "active"', { rentalId })
    if not rental or rental.citizenid ~= identifier then
        DebugPrint('saveVehiclePosition BLOCKED - Ownership validation failed for rental', rentalId)
        return
    end
    
    -- Update position in DB regardless of memory entry
    local coordsJson = json.encode(coords)
    local propsJson = props and json.encode(props) or nil
    
    MySQL.update.await([[
        UPDATE rental_history 
        SET vehicle_coords = ?, vehicle_heading = ?, vehicle_props = ?
        WHERE id = ?
    ]], { coordsJson, heading or 0, propsJson, rentalId })
    
    -- Also ensure memory entry exists (handles edge cases)
    if not spawnedRentalVehicles[rentalId] then
        spawnedRentalVehicles[rentalId] = {
            source = source,
            spawnTime = os.time()
        }
    end
end)

-- C7 Fix: Validate vehicleReturned event with proximity + vehicle proof
RegisterNetEvent('F4-Rental:server:vehicleReturned', function(rentalId, netId)
    local source = source
    local identifier = Bridge.GetIdentifier(source)

    rentalId = tonumber(rentalId)
    if not rentalId then return end
    if not identifier or identifier == '' then return end

    -- Pass-2 Fix #2: Validate vehicle entity + state before allowing return
    -- Primary: check live entity. Fallback: if entity just deleted by client, verify via memory.
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    local entityValid = false

    if veh ~= 0 and DoesEntityExist(veh) then
        -- Entity still alive — validate state bags
        local vehState = Entity(veh).state
        if not vehState.rentalVehicle then
            DebugPrint('vehicleReturned BLOCKED - Entity is not a rental vehicle')
            return
        end
        local entityRentalId = tonumber(vehState.rentalId)
        if entityRentalId ~= rentalId then
            DebugPrint('vehicleReturned BLOCKED - Entity rentalId mismatch:', vehState.rentalId, '~=', rentalId)
            return
        end
        entityValid = true
    else
        -- Entity gone (client deleted before event arrived) — fall back to memory validation
        local memEntry = spawnedRentalVehicles[rentalId]
        if memEntry and memEntry.source == source and memEntry.netId == netId then
            DebugPrint('vehicleReturned - Entity gone but memory netId matches, accepting')
            entityValid = true
        else
            DebugPrint('vehicleReturned BLOCKED - No valid entity and memory netId mismatch')
            return
        end
    end

    -- C7: Validate the rental belongs to this player
    local rental = MySQL.single.await([[
        SELECT id, location_index FROM rental_history WHERE id = ? AND citizenid = ? AND status = 'active'
    ]], { rentalId, identifier })
    if not rental then
        DebugPrint('vehicleReturned BLOCKED - Rental not found for player')
        return
    end

    -- C7: Validate proximity to allowed return location(s)
    local playerPed = GetPlayerPed(source)
    if playerPed == 0 then
        DebugPrint('vehicleReturned BLOCKED - Player ped not found')
        return
    end
    local playerCoords = GetEntityCoords(playerPed)
    local nearReturnPoint = false

    if Config.ReturnAtAnyLocation then
        for _, location in ipairs(Config.Locations) do
            local dist = #(playerCoords - location.coords)
            if dist <= (location.returnRadius or 15.0) + 5.0 then
                nearReturnPoint = true
                break
            end
        end
    else
        local originLocation = Config.Locations[rental.location_index or 1]
        if originLocation then
            local dist = #(playerCoords - originLocation.coords)
            nearReturnPoint = dist <= (originLocation.returnRadius or 15.0) + 5.0
        end
    end

    if not nearReturnPoint then
        DebugPrint('vehicleReturned BLOCKED - Player not in allowed return area')
        return
    end

    -- Delete rental from database (auto-return at location)
    DebugPrint('vehicleReturned - Attempting DELETE - RentalID:', rentalId, 'CitizenID:', identifier)

    local result = MySQL.query.await([[
        DELETE FROM rental_history WHERE id = ? AND citizenid = ?
    ]], { rentalId, identifier })

    DebugPrint('vehicleReturned - DELETE result:', type(result), json.encode(result or {}))
    local affectedRows = type(result) == 'number' and result or (type(result) == 'table' and result.affectedRows or 0)
    if not affectedRows or affectedRows == 0 then
        DebugPrint('vehicleReturned FAILED - Database delete failed, no rows affected for rental #' .. rentalId)
        return
    end
    DebugPrint('vehicleReturned - Rental #' .. rentalId .. ' deleted from database (' .. affectedRows .. ' rows)')

    -- Remove rental_contract item from player inventory
    RemoveContractItem(source, rentalId)

    -- Clean up memory
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

    -- Clear warning flags
    if warnedRentals[rentalId] then
        warnedRentals[rentalId] = nil
    end

    if lastFeeApplied[rentalId] then
        lastFeeApplied[rentalId] = nil
    end
end)

-- H4 Fix: Sync DB vehicle_spawned flag on player disconnect
-- + Auto-delete expired rentals when player disconnects (if expired, no need to return manually)
AddEventHandler('playerDropped', function()
    local source = source
    local identifier = Bridge.GetIdentifier(source)
    
    if activeRentals[source] then
        activeRentals[source] = nil
    end
    
    -- Handle spawned vehicles based on RespawnOnReconnect config
    for rentalId, data in pairs(spawnedRentalVehicles) do
        if data.source == source then
            local veh = data.netId and NetworkGetEntityFromNetworkId(data.netId) or 0

            if Config.RespawnOnReconnect then
                -- Save last coords so vehicle respawns at same spot on reconnect
                if veh ~= 0 and DoesEntityExist(veh) then
                    local coords = GetEntityCoords(veh)
                    local heading = GetEntityHeading(veh)
                    MySQL.update('UPDATE rental_history SET vehicle_coords = ?, vehicle_heading = ? WHERE id = ?',
                        { json.encode({x = coords.x, y = coords.y, z = coords.z}), heading, rentalId })
                else
                    -- Vehicle entity gone, reset flag so player can retrieve from NPC
                    MySQL.update('UPDATE rental_history SET vehicle_spawned = 0, vehicle_coords = NULL, vehicle_heading = 0 WHERE id = ?',
                        { rentalId })
                end
            else
                -- RespawnOnReconnect disabled: delete entity and reset flag → player retrieves from NPC
                if veh ~= 0 and DoesEntityExist(veh) then
                    DeleteEntity(veh)
                end
                MySQL.update('UPDATE rental_history SET vehicle_spawned = 0, vehicle_coords = NULL, vehicle_heading = 0 WHERE id = ?',
                    { rentalId })
            end
            spawnedRentalVehicles[rentalId] = nil
        end
    end

    -- Auto-delete EXPIRED rentals for this player on disconnect
    -- This prevents the stuck state: expired + can't retrieve + late fees accumulating
    if identifier and identifier ~= '' then
        local expiredRentals = MySQL.query.await([[
            SELECT id FROM rental_history
            WHERE citizenid = ? AND status = 'active' AND end_date <= NOW()
        ]], { identifier })

        if expiredRentals and #expiredRentals > 0 then
            for _, rental in ipairs(expiredRentals) do
                DebugPrint('playerDropped - Auto-deleting expired rental #' .. rental.id .. ' for player ' .. identifier)
                -- Remove contract item before player fully disconnects
                RemoveContractItem(source, rental.id)
                MySQL.update('DELETE FROM rental_history WHERE id = ?', { rental.id })
                -- Clean memory tables
                spawnedRentalVehicles[rental.id] = nil
                warnedRentals[rental.id] = nil
                lastFeeApplied[rental.id] = nil
            end
            DebugPrint('playerDropped - Deleted ' .. #expiredRentals .. ' expired rental(s) for ' .. identifier)
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

    local feeAmount = Config.LateFee

    -- H1 Fix + Pass-2 Fix #5: Late fee policy = accumulate ONLY on successful charge.
    -- Rationale: DB late_fee_total must match actual money removed from player.
    -- If charge fails (insufficient funds), we notify + retry next interval.
    local charged = Bridge.RemoveMoney(source, 'bank', feeAmount, 'Rental late fee - ' .. rental.vehicle_label)
    if not charged then
        Bridge.Notify(source, 'Late fee pending: insufficient funds', 'warning')
        lastFeeApplied[rentalKey] = nil -- allow retry next interval
        return
    end

    local newTotal = (rental.late_fee_total or 0) + feeAmount
    MySQL.update.await([[
        UPDATE rental_history
        SET late_fee_total = ?, last_fee_time = NOW()
        WHERE id = ?
    ]], { newTotal, rental.id })

    local location = Config.Locations[rental.location_index or 1]

    -- Notify player about late fee
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
end

local function AutoTerminateRental(rental)
    -- Delete rental from database (offline players, no late fees)
    DebugPrint('AutoTerminate - Attempting DELETE - RentalID:', rental.id)

    local result = MySQL.query.await([[
        DELETE FROM rental_history WHERE id = ?
    ]], { rental.id })

    DebugPrint('AutoTerminate - DELETE result:', type(result), json.encode(result or {}))
    DebugPrint('AutoTerminate - Rental #' .. rental.id .. ' deleted (player offline)')

    -- Clean up memory
    if spawnedRentalVehicles[rental.id] then
        spawnedRentalVehicles[rental.id] = nil
    end

    if warnedRentals[rental.id] then
        warnedRentals[rental.id] = nil
    end

    if lastFeeApplied[rental.id] then
        lastFeeApplied[rental.id] = nil
    end
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

-- H5 Fix: CancelRental export now also cleans DB and all memory tables
exports('CancelRental', function(source, rentalId)
    if not activeRentals[source] then return false end

    for i, r in ipairs(activeRentals[source]) do
        if r.id == rentalId then
            table.remove(activeRentals[source], i)
            -- Remove contract item from inventory
            RemoveContractItem(source, rentalId)
            -- Clean DB
            MySQL.update.await('DELETE FROM rental_history WHERE id = ?', { rentalId })
            -- Clean all memory tables
            spawnedRentalVehicles[rentalId] = nil
            warnedRentals[rentalId] = nil
            lastFeeApplied[rentalId] = nil
            return true
        end
    end

    return false
end)
