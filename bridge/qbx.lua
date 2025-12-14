if not IsDuplicityVersion() then

    function Bridge.GetPlayerData()
        return exports.qbx_core:GetPlayerData()
    end

    function Bridge.GetMoney(moneyType)
        local playerData = Bridge.GetPlayerData()
        if playerData and playerData.money then
            return playerData.money[moneyType] or 0
        end
        return 0
    end

    function Bridge.GetJob()
        local playerData = Bridge.GetPlayerData()
        if playerData and playerData.job then
            return playerData.job.name
        end
        return nil
    end

    function Bridge.GetJobGrade()
        local playerData = Bridge.GetPlayerData()
        if playerData and playerData.job then
            return playerData.job.grade.level or 0
        end
        return 0
    end

    function Bridge.Notify(msg, type, duration)
        if GetResourceState('ox_lib') == 'started' then
            lib.notify({
                title = 'Rental',
                description = msg,
                type = type,
                duration = duration or 5000
            })
        else
            exports.qbx_core:Notify(msg, type, duration)
        end
    end

    function Bridge.AdvancedNotify(title, message, type)
        lib.notify({
            title = title,
            description = message,
            type = type,
            duration = 5000
        })
    end

    function Bridge.DrawText(msg, type)
        lib.showTextUI(msg, { position = 'right-center' })
    end

    function Bridge.HideText()
        lib.hideTextUI()
    end

    function Bridge.TriggerCallback(eventName, cb, ...)
        local result = lib.callback.await(eventName, false, ...)
        cb(result)
    end

    function Bridge.GiveKeys(vehicle)
        if GetResourceState('qbx_vehiclekeys') == 'started' then
            local netId = NetworkGetNetworkIdFromEntity(vehicle)
            TriggerServerEvent('F4-Rental:server:giveKeys', netId)
        elseif GetResourceState('qb-vehiclekeys') == 'started' then
            local plate = GetVehicleNumberPlateText(vehicle)
            TriggerEvent('vehiclekeys:client:SetOwner', plate)
        end
    end

end

if IsDuplicityVersion() then

    function Bridge.GetPlayer(source)
        return exports.qbx_core:GetPlayer(source)
    end

    function Bridge.GetIdentifier(source)
        local player = Bridge.GetPlayer(source)
        if player then
            return player.PlayerData.citizenid
        end
        return ''
    end

    function Bridge.GetMoney(source, moneyType)
        local player = Bridge.GetPlayer(source)
        if player then
            return player.PlayerData.money[moneyType] or 0
        end
        return 0
    end

    function Bridge.RemoveMoney(source, moneyType, amount, reason)
        local player = Bridge.GetPlayer(source)
        if player then
            return player.Functions.RemoveMoney(moneyType, amount, reason or 'car-rental')
        end
        return false
    end

    function Bridge.AddMoney(source, moneyType, amount, reason)
        local player = Bridge.GetPlayer(source)
        if player then
            return player.Functions.AddMoney(moneyType, amount, reason or 'car-rental-refund')
        end
        return false
    end

    function Bridge.Notify(source, msg, type)
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Rental',
            description = msg,
            type = type
        })
    end

    function Bridge.CreateCallback(name, cb)
        lib.callback.register(name, cb)
    end

    function Bridge.GetJob(source)
        local player = Bridge.GetPlayer(source)
        if player then
            return player.PlayerData.job.name
        end
        return ''
    end

    function Bridge.GetJobGrade(source)
        local player = Bridge.GetPlayer(source)
        if player then
            return player.PlayerData.job.grade.level or 0
        end
        return 0
    end

end