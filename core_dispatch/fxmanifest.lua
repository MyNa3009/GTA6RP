fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'core_dispatch'
description 'Notrufe und MDT fuer die eigene Core: Notruf per /dispatch, Einsaetze annehmen, FMS-Status, Leitstelle, Archiv'
version '1.2.0'

dependencies {
    'core',
    'core_lib',
    'core_factions',
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
    'server/calls.lua',
    'server/mdt.lua',
}

client_scripts {
    '@core/bridge/platform/fivem_client.lua',
    '@core/bridge/network/fivem_client.lua',
    '@core_lib/init.lua',
    'data/blips_gta5.lua',
    'client/main.lua',
}

ui_page 'html/dispatch.html'

files {
    'html/dispatch.html',
}
