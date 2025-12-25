local QBCore = exports['qb-core']:GetCoreObject()

if not IsDuplicityVersion() then

    function Bridge.GetPlayerData()
        return QBCore.Functions.GetPlayerData()
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
        if Config.NotifySystem == 'ox_lib' and GetResourceState('ox_lib') == 'started' then
            lib.notify({
                title = 'Rental',
                description = msg,
                type = type,
                duration = duration or 5000
            })
        else
            QBCore.Functions.Notify(msg, type, duration)
        end
    end

    function Bridge.AdvancedNotify(title, message, type)
        if GetResourceState('ox_lib') == 'started' then
            lib.notify({
                title = title,
                description = message,
                type = type,
                duration = 5000
            })
        else
            QBCore.Functions.Notify(message, type)
        end
    end

    function Bridge.DrawText(msg, type)
        if GetResourceState('ox_lib') == 'started' then
            lib.showTextUI(msg, { position = 'right-center' })
        elseif GetResourceState('qb-core') == 'started' then
            exports['qb-core']:DrawText(msg, type or 'left')
        end
    end

    function Bridge.HideText()
        if GetResourceState('ox_lib') == 'started' then
            lib.hideTextUI()
        elseif GetResourceState('qb-core') == 'started' then
            exports['qb-core']:HideText()
        end
    end

    function Bridge.TriggerCallback(eventName, cb, ...)
        if GetResourceState('ox_lib') == 'started' then
            local result = lib.callback.await(eventName, false, ...)
            cb(result)
        else
            QBCore.Functions.TriggerCallback(eventName, cb, ...)
        end
    end

    function Bridge.GiveKeys(vehicle)
        if GetResourceState('qb-vehiclekeys') == 'started' then
            local plate = GetVehicleNumberPlateText(vehicle)
            TriggerEvent('vehiclekeys:client:SetOwner', plate)
        end
    end

end

if IsDuplicityVersion() then

    function Bridge.GetPlayer(source)
        return QBCore.Functions.GetPlayer(source)
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
        TriggerClientEvent('QBCore:Notify', source, msg, type)
    end

function Bridge.CreateCallback(name, cb)
    if GetResourceState('ox_lib') == 'started' then
        lib.callback.register(name, cb)
    else
        QBCore.Functions.CreateCallback(name, function(source, callbackFn, data)
            -- QBCore passes data as first parameter (table)
            local result = cb(source, data)
            callbackFn(result)
        end)
    end
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