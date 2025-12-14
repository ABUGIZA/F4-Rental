Target = {}
Target.System = nil
Target.SystemName = nil

local function DetectTargetSystem()
    if Config.TargetSystem ~= 'auto' then
        return Config.TargetSystem
    end

    if GetResourceState('ox_target') == 'started' then
        return 'ox_target'
    end

    if GetResourceState('qb-target') == 'started' then
        return 'qb-target'
    end

    if GetResourceState('interact') == 'started' then
        return 'interact'
    end

    return 'none'
end

local function LoadTargetBridge(system)
    if system == 'none' then
        Target.System = 'none'
        Target.SystemName = 'Proximity'
        return true
    end

    local fileName = ('bridge/target/%s.lua'):format(system:gsub('-', '_'))
    local bridgeFile = LoadResourceFile(GetCurrentResourceName(), fileName)

    if bridgeFile then
        local fn, err = load(bridgeFile, ('@@%s/%s'):format(GetCurrentResourceName(), fileName))
        if fn then
            fn()
            return true
        else
            print(('[F4-Rental] Error loading target bridge: %s'):format(err))
            return false
        end
    else
        print(('[F4-Rental] Target bridge not found: %s'):format(fileName))
        return false
    end
end

local targetSystem = DetectTargetSystem()

if LoadTargetBridge(targetSystem) then
    Target.System = targetSystem
    Target.SystemName = ({
        ox_target = 'ox_target',
        ['qb-target'] = 'qb-target',
        interact = 'interact',
        none = 'Proximity'
    })[targetSystem] or targetSystem

    if targetSystem ~= 'none' then
        print(('[F4-Rental] Loaded %s target bridge'):format(Target.SystemName))
    end
end

if Target.System == 'none' then
    function Target.AddPedInteraction(ped, options)
        Target.ProximityPeds = Target.ProximityPeds or {}
        Target.ProximityPeds[ped] = options
    end

    function Target.AddCoordInteraction(coords, options)
        Target.ProximityCoords = Target.ProximityCoords or {}
        table.insert(Target.ProximityCoords, { coords = coords, options = options })
    end

    function Target.Remove(id) end
    function Target.RemovePed(ped)
        if Target.ProximityPeds then
            Target.ProximityPeds[ped] = nil
        end
    end
end