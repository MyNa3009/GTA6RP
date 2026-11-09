fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'core_factions'
description 'Organisationen fuer die eigene Core: Raenge, Rechte, Abteilungen, Leitstelle, Archiv, Kasse, Dienst'
version '1.3.0'

dependencies {
    'core',
    'core_lib',
    'oxmysql',
}

shared_scripts {
    '@core/shared/config.lua',
    'config.lua',
    'data/places_gta5.lua',   -- Umkleide und Garage (Server prueft den Abstand, Client zeigt sie)
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@core/bridge/platform/fivem_server.lua',
    '@core/bridge/database/oxmysql.lua',
    '@core/bridge/network/fivem_server.lua',
    '@core_lib/init.lua',
    'server/schema.lua',
    'server/main.lua',
    'server/protocol.lua',
    'server/consent.lua',
    'server/members.lua',
    'server/menu.lua',
    'server/places.lua',
    'server/commands.lua',
}

client_scripts {
    '@core/bridge/platform/fivem_client.lua',
    '@core/bridge/network/fivem_client.lua',
    '@core_lib/init.lua',
    '@core_lib/modules/zones.lua',
    'client/main.lua',
    'client/places.lua',
    'client/interact.lua',
}

ui_page 'html/orgmenu.html'

files {
    'html/orgmenu.html',
    'html/logos/*.png',
}
