local currentVersion = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '1.0.0'

CreateThread(function()
    Wait(2000)
    print('^5╔══════════════════════════════════════════════════════════╗^0')
    print('^5║                 ^2F4-RENTAL SYSTEM^5                        ║^0')
    print('^5║             ^3Professional Car Rental^5                     ║^0')
    print('^5╠══════════════════════════════════════════════════════════╣^0')
    print(('^5║  ^0Version: ^2%s^5                                           ║^0'):format(currentVersion))
    print(('^5║  ^0Framework: ^2%-15s^5                            ║^0'):format(Bridge.FrameworkName or 'Detecting...'))
    print(('^5║  ^0Target: ^2%-18s^5                            ║^0'):format((Target and Target.SystemName) or 'Proximity'))
    print('^5╚══════════════════════════════════════════════════════════╝^0')
end)

exports('GetVersion', function()
    return currentVersion
end)
