fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'core_inventory'
description 'Inventar fuer die eigene Core: Plaetze, Gewicht, Kleidung, Rucksack, Schnellzugriff'
version '1.1.0'

-- Startet nach der Core und nutzt deren Config und Bridge (es gibt nur eine Stelle mit FiveM-Natives)
dependencies {
    'core',
    'oxmysql',
}

shared_scripts {
    '@core/shared/config.lua',
    'config.lua',
    'data/items.lua',
    'data/clothing_catalog_gta5.lua', -- Kleidungs-Items mit Aussehen (erzeugt von tools/kleidung.py)
    'data/clothing_gta5.lua',
    'data/trunks_gta5.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@core/bridge/platform/fivem_server.lua',
    '@core/bridge/database/oxmysql.lua',
    '@core/bridge/network/fivem_server.lua',
    'server/inventory.lua',
    'server/drops.lua',
    'server/registry.lua',
    'server/api.lua',
    'server/documents.lua',
    'server/views.lua',
}

client_scripts {
    '@core/bridge/platform/fivem_client.lua',
    '@core/bridge/network/fivem_client.lua',
    'data/props_gta5.lua',
    'data/weapons_gta5.lua',
    'client/main.lua',
}

ui_page 'html/inventory.html'

files {
    'html/inventory.html',
    'html/icons/*.png',
    'images/*.png',
}
