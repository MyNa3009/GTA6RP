fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'core_ems'
description 'Rettungsdienst fuer die eigene Core: Hochholen, Verbandskasten, Verkauf, Behandlung, Krankheiten, Versicherung, Medizinische Datenbank'
version '1.4.2'

dependencies {
    'core',
    'core_lib',
    'core_factions',
    'core_inventory',
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
    '@core_lib/init.lua',
    'server/schema.lua',
    'server/main.lua',
    'server/diseases.lua',
    'server/actions.lua',
    'server/records.lua',
}

client_scripts {
    '@core/bridge/platform/fivem_client.lua',
    '@core/bridge/network/fivem_client.lua',
    '@core_lib/init.lua',
    'data/symptoms_gta5.lua',
    'client/main.lua',
    'client/symptoms.lua',
    'client/interact.lua',
}

ui_page 'html/records.html'

files {
    'html/records.html',
}
