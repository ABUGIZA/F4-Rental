# 🚗 F4-Rental - Professional Car Rental System

A modern, fully-featured car rental system for FiveM servers with a beautiful UI, contract system, and automatic expiry management.

![Main Interface](https://res.cloudinary.com/dmcz9xz4d/image/upload/v1765731623/ce8edbe0-425c-4bd5-9bef-675a0ae3eea7.png)

## ✨ Features

- 🎨 **Modern Dark UI** - Beautiful, responsive interface with smooth animations
- 📋 **Digital Contracts** - Usable rental contract items with all rental details
- ⏰ **Automatic Expiry System** - Warnings before expiry and late fee management
- 🚙 **My Rentals Tab** - Track all your active rentals in one place
- 💰 **Flexible Pricing** - Hourly-based pricing with customizable durations
- 🔑 **Vehicle Keys Integration** - Automatic key assignment (qb-vehiclekeys/qbx_vehiclekeys)
- 💾 **Vehicle Persistence** - Rented vehicles persist across reconnects
- 🗺️ **Return Location GPS** - Automatic waypoint to return location on expiry

## 📸 Screenshots

<details>
<summary>Click to view screenshots</summary>

### Main Rental Interface
![Main Interface](https://res.cloudinary.com/dmcz9xz4d/image/upload/v1765731623/ce8edbe0-425c-4bd5-9bef-675a0ae3eea7.png)

### My Rentals
![My Rentals](https://res.cloudinary.com/dmcz9xz4d/image/upload/v1765731636/971574b1-9a23-4284-8438-c5b8e9a3f759.png)

### Rental Contract
![Contract](https://res.cloudinary.com/dmcz9xz4d/image/upload/v1765731806/ddf78791-6d32-4bf7-8888-f379a71a2155.png)

### Expiry Warning
![Warning](https://res.cloudinary.com/dmcz9xz4d/image/upload/v1765731660/b8e3ea13-a28b-4e96-8cfa-0072a5066e74.png)

### Return Location GPS
![GPS](https://res.cloudinary.com/dmcz9xz4d/image/upload/v1765731654/6968335f-5672-43b7-b0ea-ba3d4236c925.png)

</details>

## 📦 Dependencies

- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- **Framework**: QBCore / QBox / ESX Legacy

### Optional
- ox_target / qb-target / interact
- ox_inventory / qb-inventory
- qb-vehiclekeys / qbx_vehiclekeys

## 🛠️ Installation

1. **Download** the resource and place it in your `resources` folder

2. **Import the SQL** - Run the SQL file in your database:
   ```sql
   -- Located in: sql/rental_history.sql
   ```

3. **Add to server.cfg**:
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure F4-Rental
   ```

4. **Configure** - Edit `config.lua` to customize:
   - Rental locations
   - Available vehicles
   - Rental durations
   - Pricing
   - And more...

5. **Add required item (`rental_contract`)**

### ox_inventory
Add this item to your `ox_inventory` items file (for example `ox_inventory/data/items.lua`):

```lua
['rental_contract'] = {
    label = 'Rental Contract',
    weight = 0,
    stack = false,
    consume = 0,
    close = true,
    description = 'Vehicle rental contract',
    server = {
        export = 'F4-Rental.rental_contract'
    }
},
```

> If you renamed this resource folder, replace `F4-Rental` with your actual resource name.

### qb-inventory / qb-core shared items
Add this item to `qb-core/shared/items.lua`:

```lua
['rental_contract'] = {
    ['name'] = 'rental_contract',
    ['label'] = 'Rental Contract',
    ['weight'] = 0,
    ['type'] = 'item',
    ['image'] = 'rental_contract.png',
    ['unique'] = true,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['description'] = 'Vehicle rental contract'
},
```

## ⚙️ Configuration

### Rental Locations
```lua
Config.Locations = {
    {
        name = "Premium Rentals",
        coords = vector3(-50.0, -1090.0, 26.5),
        spawnPoint = vector4(-47.0, -1095.0, 26.5, 160.0),
        blip = { sprite = 56, color = 5, scale = 0.8 },
    },
}
```

### Rental Durations
```lua
Config.RentalDurations = {
    { days = 1, label = "1 Hour", multiplier = 0.5, minutes = 60 },
    { days = 1, label = "3 Hours", multiplier = 0.5, minutes = 180 },
    { days = 1, label = "6 Hours", multiplier = 0.8, minutes = 360 },
    { days = 1, label = "12 Hours", multiplier = 1.0, minutes = 720 },
    { days = 1, label = "1 Day", multiplier = 1.5, minutes = 1440 },
}
```

### Vehicles
```lua
Config.Vehicles = {
    {
        model = "sultan",
        label = "Sultan",
        manufacturer = "Karin",
        category = "Sports",
        price = 500,
        image = "https://docs.fivem.net/vehicles/sultan.webp",
        stats = { speed = 75, acceleration = 70, braking = 65, handling = 72 },
    },
}
```

## 🔧 Framework Support

| Framework | Status |
|-----------|--------|
| QBox (qbx_core) | ✅ Full Support |
| QBCore | ✅ Full Support |
| ESX Legacy | ✅ Full Support |

## 📝 License

This resource is free to use and redistribute. Resale is not permitted.

## 💬 Support

For support, please open an issue on GitHub or contact the author

## 🔧 Fixed Issues

| Issue | Status |
|-------|--------|
| Vehicle duplication after server restart | ✅ Fixed |
| Multiple rentals bypass after disconnect | ✅ Fixed |
| Retrieve spawning duplicate vehicles | ✅ Fixed |
| Return not updating database | ✅ Fixed |

## 🆕 Latest Updates (v1.1.0)

### 🎥 Update Showcase
[![Watch Update](https://img.shields.io/badge/Watch-Latest_Updates-brightgreen?style=for-the-badge&logo=youtube)](https://streamable.com/37awax)

### ✅ Major Fixes & Improvements

#### **Customer Reported Issues - RESOLVED**
1. **DoesEntityExist Script Error (interact/sleepless_interact)**
   - ✅ Fixed entity parameter validation in return vehicle event
   - ✅ Added comprehensive type checking and conversion
   - ✅ No more script errors when using target systems

2. **Rental Data Not Deleting After Return**
   - ✅ Changed database operation from UPDATE to DELETE
   - ✅ Rentals now properly removed from database on return
   - ✅ Clean database without leftover rental records

3. **QBCore Callback Data Handling**
   - ✅ Fixed callback bridge for QBCore framework
   - ✅ Proper data passing between client and server
   - ✅ DELETE operations now work correctly in QBCore

#### **Late Fee System Enhancements**
- **Accurate Accounting** - Late fees are added only when charge succeeds
- **Retry Logic** - If charge fails (insufficient funds), system retries next interval
- 🎯 **Smart Detection** - Only charges online players
- 🗑️ **Auto-Cleanup** - Offline expired rentals are deleted without fees

#### **Database Management**
- 🗄️ **Clean Records** - All returns now DELETE instead of UPDATE status
- 🚀 **Better Performance** - Fewer database records to query
- 📊 **Accurate Tracking** - Only active rentals in database

#### **Code Quality Improvements**
- 🐛 **Enhanced Debugging** - Comprehensive debug logging for troubleshooting
- ✅ **Better Validation** - Improved entity and data validation
- 🔒 **Safer Operations** - Proper error handling and fallbacks

### 📋 Technical Changes

```lua
// Before (Old Code)
UPDATE rental_history SET status = 'returned' WHERE id = ?

// After (New Code)
DELETE FROM rental_history WHERE id = ? AND citizenid = ?
```

### 🎮 Player Experience
- ✅ Smoother return process without errors
- ✅ Clear balance warnings when going negative
- ✅ Fair system: only online players pay late fees
- ✅ Offline players don't accumulate charges

---

### Demo Videos
[![Original Demo](https://img.shields.io/badge/Watch-Original_Demo-red)](https://streamable.com/6n4poh)
[![Latest Update](https://img.shields.io/badge/Watch-Latest_Updates-brightgreen)](https://streamable.com/37awax)

---

## New Update (Post v1.1.0)

### Core Fixes
- Fixed proximity fallback when `TargetSystem = auto` and no target script is running.
- Added return interaction registration for `ox_target` and `qb-target`.
- Synced initial vehicle spawn to server memory/database (`vehicleSpawned` flow).
- Added stale `vehicle_spawned` recovery to prevent blocked retrieval states.
- Added retrieve lock/pending flow to prevent duplicate vehicle spawn race conditions.
- Plate is now generated and saved immediately on rental creation.

### Security & Validation
- Return callbacks now validate rental vehicle proof (`netId` + rental state checks).
- Auto-return event now validates player ownership, vehicle state, and return proximity.
- QBX key grant now verifies rental ownership before giving keys.
- Added stronger return-location enforcement when `Config.ReturnAtAnyLocation = false`.

### Data Integrity
- Improved spawned vehicle lifecycle sync on disconnect and reconnect.
- Added configurable reconnect behavior via `Config.RespawnOnReconnect`.
- Position save now validates ownership from database and updates reliably.
- Rental contract item is removed on successful return/cancel cleanup paths.

### Inventory & UI
- `rental_contract` in `ox_inventory` is now handled as non-consumable on use.
- Added per-character favorites storage in NUI (`localStorage` scoping).
- Fixed contract duration display to correctly use minutes/hours.
- Updated price rounding consistency for rental total display.

### Late Fee Policy
- Late fee total now increases only when actual money removal succeeds.
- If charge fails, player is warned and the system retries on next interval.

### Defaults / Config
- `Config.Debug` default changed to `false` for production.

### RespawnOnReconnect Demo (Enabled)
- This demo shows the behavior when `Config.RespawnOnReconnect = true`.
- If the player disconnects and reconnects, the rented vehicle respawns where it was left.

[![Watch RespawnOnReconnect Demo](https://img.shields.io/badge/Watch-RespawnOnReconnect-blue)](https://streamable.com/29gp3q)

