Config = {}
-----------------------------------------------------------
-- FRAMEWORK SETTINGS
-----------------------------------------------------------

Config.Framework = 'auto'      -- 'auto' | 'qb' | 'qbx' | 'esx'
Config.TargetSystem = 'auto'   -- 'auto' | 'ox_target' | 'qb-target' | 'interact' | 'none'
Config.NotifySystem = 'auto'   -- 'auto' | 'ox_lib' | 'framework'

-----------------------------------------------------------
-- RENTAL LOCATIONS
-----------------------------------------------------------

Config.Locations = {
    {
        id = 'rental_main',
        name = 'Car Rental',
        coords = vector3(-50.0, -1090.0, 26.5),
        heading = 160.0,
        spawnPoint = vector4(-45.0, -1085.0, 26.5, 70.0),
        returnRadius = 15.0,
        blip = {
            enabled = true,
            sprite = 225,
            color = 17,
            scale = 0.8,
            label = 'Car Rental'
        },
        ped = {
            enabled = true,
            model = 's_m_y_valet_01',
            scenario = 'WORLD_HUMAN_CLIPBOARD',
        },
    },
}

-----------------------------------------------------------
-- AVAILABLE VEHICLES
-----------------------------------------------------------

Config.Vehicles = {
    {
        model = 'baller8',
        label = 'Baller 8',
        manufacturer = 'Gallivanter',
        category = 'SUV',
        price = 500,
        image = 'https://docs.fivem.net/vehicles/baller8.webp',
        stats = { speed = 85, acceleration = 70, braking = 75, handling = 80 },
    },
    {
        model = 'cavalcade3',
        label = 'Cavalcade 3',
        manufacturer = 'Albany',
        category = 'SUV',
        price = 450,
        image = 'https://docs.fivem.net/vehicles/cavalcade3.webp',
        stats = { speed = 75, acceleration = 65, braking = 70, handling = 75 },
    },
    {
        model = 'stafford',
        label = 'Stafford',
        manufacturer = 'Enus',
        category = 'Classic',
        price = 600,
        image = 'https://docs.fivem.net/vehicles/stafford.webp',
        stats = { speed = 70, acceleration = 60, braking = 85, handling = 90 },
    },
    {
        model = 'comet6',
        label = 'Comet S2',
        manufacturer = 'Pfister',
        category = 'Sports',
        price = 800,
        image = 'https://docs.fivem.net/vehicles/comet6.webp',
        stats = { speed = 90, acceleration = 85, braking = 80, handling = 85 },
    },
    {
        model = 'jester4',
        label = 'Jester RR',
        manufacturer = 'Dinka',
        category = 'Sports',
        price = 750,
        image = 'https://docs.fivem.net/vehicles/jester4.webp',
        stats = { speed = 88, acceleration = 90, braking = 78, handling = 82 },
    },
    {
        model = 'buffalo4',
        label = 'Buffalo STX',
        manufacturer = 'Bravado',
        category = 'Muscle',
        price = 550,
        image = 'https://docs.fivem.net/vehicles/buffalo4.webp',
        stats = { speed = 82, acceleration = 75, braking = 72, handling = 70 },
    },
}

-----------------------------------------------------------
-- RENTAL DURATIONS
-----------------------------------------------------------

Config.RentalDurations = {
    { days = 1, label = '1 Hour', multiplier = 0.5, hours = 1 },
    { days = 1, label = '2 Hours', multiplier = 0.5, hours = 2 },
    { days = 1, label = '3 Hours', multiplier = 0.5, hours = 3 },
    { days = 1, label = '6 Hours', multiplier = 0.8, hours = 6 },
    { days = 1, label = '12 Hours', multiplier = 1.0, hours = 12 },
    { days = 1, label = '1 Day', multiplier = 1.5, hours = 24 },
    { days = 2, label = '2 Days', multiplier = 2.5, hours = 48 },
    { days = 3, label = '3 Days', multiplier = 3.5, hours = 72 },
    { days = 7, label = '7 Days', multiplier = 6.0, hours = 168 },
}

Config.PaymentMethods = {
    { id = 'bank', label = 'Bank Transfer', icon = 'fa-credit-card' },
    { id = 'cash', label = 'Cash', icon = 'fa-money-bill-wave' },
}

-----------------------------------------------------------
-- RENTAL RULES
-----------------------------------------------------------

Config.AllowMultipleRentals = false
Config.ReturnAtAnyLocation = true
Config.RefundOnReturn = true
Config.RefundPercentage = 50
Config.DeleteVehicleOnExpiry = false
Config.WarnBeforeExpiry = 5

-----------------------------------------------------------
-- LATE FEE SETTINGS
-----------------------------------------------------------

Config.LateFee = 100
Config.LateFeeInterval = 1
Config.AutoTerminateOffline = true

-----------------------------------------------------------
-- INTERACTION SETTINGS
-----------------------------------------------------------

Config.InteractionDistance = 2.5
Config.UseBlips = true
Config.UsePeds = true
Config.UseMarkers = false
Config.InteractionKey = 38

-----------------------------------------------------------
-- VEHICLE SETTINGS
-----------------------------------------------------------

Config.FuelLevel = 100
Config.LockVehicle = false
Config.GiveKeys = true

-----------------------------------------------------------
-- DEBUG
-----------------------------------------------------------

Config.Debug = true