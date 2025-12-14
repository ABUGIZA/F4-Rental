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
    { label = "1 Hour", hours = 1, multiplier = 1.5 },
    { label = "3 Hours", hours = 3, multiplier = 1.3 },
    { label = "6 Hours", hours = 6, multiplier = 1.2 },
    { label = "12 Hours", hours = 12, multiplier = 1.1 },
    { label = "24 Hours", hours = 24, multiplier = 1.0 },
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