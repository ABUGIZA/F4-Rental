fx_version 'cerulean'
game 'gta5'

name 'F4-Rental'
author 'F4'
description 'Professional Car Rental System'
version '1.0.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'bridge/loader.lua',
}

client_scripts {
    'client/utils.lua',
    'bridge/target/loader.lua',
    'client/main.lua',
    'client/nui.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/items.lua',
    'server/version.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'bridge/*.lua',
    'bridge/target/*.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
}