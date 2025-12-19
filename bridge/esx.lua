local ESX = exports['es_extended']:getSharedObject()

if not IsDuplicityVersion() then

    function Bridge.GetPlayerData()
        return ESX.GetPlayerData()
    end

    function Bridge.GetMoney(moneyType)
        local playerData = Bridge.GetPlayerData()
        if not playerData then return 0 end

        if moneyType == 'cash' then
            moneyType = 'money'
        end

        if playerData.accounts then
            for _, account in ipairs(playerData.accounts) do
                if account.name == moneyType then
                    return account.money or 0
                end
            end
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
            return playerData.job.grade or 0
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
            ESX.ShowNotification(msg, type, duration)
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
            ESX.ShowNotification(message, type)
        end
    end

    function Bridge.DrawText(msg, type)
        if GetResourceState('ox_lib') == 'started' then
            lib.showTextUI(msg, { position = 'right-center' })
        else
            ESX.TextUI(msg)
        end
    end

    function Bridge.HideText()
        if GetResourceState('ox_lib') == 'started' then
            lib.hideTextUI()
        else
            ESX.HideUI()
        end
    end

    function Bridge.TriggerCallback(eventName, cb, ...)
        if GetResourceState('ox_lib') == 'started' then
            local result = lib.callback.await(eventName, false, ...)
            cb(result)
        else
            ESX.TriggerServerCallback(eventName, cb, ...)
        end
    end

    function Bridge.GiveKeys(vehicle)
        if GetResourceState('esx_vehiclelock') == 'started' then
            local plate = GetVehicleNumberPlateText(vehicle)
            TriggerServerEvent('esx_vehiclelock:setVehicleOwner', plate)
        end
    end

end

if IsDuplicityVersion() then

    function Bridge.GetPlayer(source)
        return ESX.GetPlayerFromId(source)
    end

    function Bridge.GetIdentifier(source)
        local player = Bridge.GetPlayer(source)
        if player then
            return player.identifier
        end
        return ''
    end

    function Bridge.GetMoney(source, moneyType)
        local player = Bridge.GetPlayer(source)
        if not player then return 0 end

        if moneyType == 'cash' then
            moneyType = 'money'
        end

        return player.getAccount(moneyType).money or 0
    end

    function Bridge.RemoveMoney(source, moneyType, amount, reason)
        local player = Bridge.GetPlayer(source)
        if not player then return false end

        if moneyType == 'cash' then
            moneyType = 'money'
        end

        local account = player.getAccount(moneyType)
        if account and account.money >= amount then
            player.removeAccountMoney(moneyType, amount, reason or 'car-rental')
            return true
        end
        return false
    end

    function Bridge.AddMoney(source, moneyType, amount, reason)
        local player = Bridge.GetPlayer(source)
        if not player then return false end

        if moneyType == 'cash' then
            moneyType = 'money'
        end

        player.addAccountMoney(moneyType, amount, reason or 'car-rental-refund')
        return true
    end

    function Bridge.Notify(source, msg, type)
        TriggerClientEvent('esx:showNotification', source, msg, type)
    end

    function Bridge.CreateCallback(name, cb)
        if GetResourceState('ox_lib') == 'started' then
            lib.callback.register(name, cb)
        else
            ESX.RegisterServerCallback(name, function(source, callbackFn, data)
                local result = cb(source, data)
                callbackFn(result)
            end)
        end
    end

    function Bridge.GetJob(source)
        local player = Bridge.GetPlayer(source)
        if player then
            return player.getJob().name
        end
        return ''
    end

    function Bridge.GetJobGrade(source)
        local player = Bridge.GetPlayer(source)
        if player then
            return player.getJob().grade or 0
        end
        return 0
    end

end