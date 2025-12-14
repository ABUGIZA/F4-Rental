Bridge = {}
Bridge.Framework = nil
Bridge.FrameworkName = nil

function Bridge.Debug(...)
    if Config.Debug then
        print('[F4-Rental]', ...)
    end
end

local function DetectFramework()
    if Config.Framework ~= 'auto' then
        return Config.Framework
    end

    if GetResourceState('qbx_core') == 'started' then
        return 'qbx'
    end

    if GetResourceState('qb-core') == 'started' then
        return 'qb'
    end

    if GetResourceState('es_extended') == 'started' then
        return 'esx'
    end

    return nil
end

local function LoadBridge(framework)
    local fileName = ('bridge/%s.lua'):format(framework)
    local bridgeFile = LoadResourceFile(GetCurrentResourceName(), fileName)

    if bridgeFile then
        local fn, err = load(bridgeFile, ('@@%s/%s'):format(GetCurrentResourceName(), fileName))
        if fn then
            fn()
            return true
        else
            print(('[F4-Rental] Error loading bridge: %s'):format(err))
            return false
        end
    else
        print(('[F4-Rental] Bridge file not found: %s'):format(fileName))
        return false
    end
end

local framework = DetectFramework()

if framework then
    if LoadBridge(framework) then
        Bridge.Framework = framework
        Bridge.FrameworkName = ({
            qb = 'QBCore',
            qbx = 'QBox',
            esx = 'ESX Legacy'
        })[framework] or framework:upper()

        print(('[F4-Rental] Loaded %s framework bridge'):format(Bridge.FrameworkName))
    end
else
    print('[F4-Rental] ERROR: No supported framework detected!')
    print('[F4-Rental] Supported: QBCore, QBox (qbx_core), ESX Legacy')
end