fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'core_phone'
description 'Handy fuer die eigene Core: Item mit eSIM, Telefon, Kontakte, Nachrichten, Bank-App, Notruf'
version '1.0.0'

dependencies {
    'core',
    'oxmysql',
}

shared_scripts {
    '@core/shared/config.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@core/bridge/platform/fivem_server.lua',
    '@core/bridge/database/oxmysql.lua',
    '@core/bridge/network/fivem_server.lua',
    'server/schema.lua',
    'server/main.lua',
    'server/numbers.lua',
    'server/messages.lua',
    'server/calls.lua',
    'server/apps.lua',
    'server/admin.lua',
}

client_scripts {
    '@core/bridge/platform/fivem_client.lua',
    '@core/bridge/network/fivem_client.lua',
    'data/phone_gta5.lua',
    'client/main.lua',
}

ui_page 'html/phone.html'

files {
    'html/phone.html',
}
