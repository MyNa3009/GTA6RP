fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'core_bank'
description 'Bank fuer die eigene Core: Konto mit Kontonummer, Kontoauszug, Ueberweisungen, Schulden (Strafen, Rechnungen), Bankautomaten'
version '1.0.3'

dependencies {
    'core',
    'core_lib',
    'oxmysql',
}

shared_scripts {
    '@core/shared/config.lua',
    'config.lua',
    'data/banks_gta5.lua',   -- Filialen (Server prueft den Abstand, Client zeigt sie)
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@core/bridge/platform/fivem_server.lua',
    '@core/bridge/database/oxmysql.lua',
    '@core/bridge/network/fivem_server.lua',
    'server/schema.lua',
    'server/main.lua',
    'server/accounts.lua',
    'server/debts.lua',
    'server/sessions.lua',
    'server/admin.lua',
}

client_scripts {
    '@core/bridge/platform/fivem_client.lua',
    '@core/bridge/network/fivem_client.lua',
    '@core_lib/init.lua',
    '@core_lib/modules/zones.lua',
    'data/atms_gta5.lua',
    'client/main.lua',
    'client/places.lua',
    'client/interact.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/bank.html',
    'html/atm.html',
}
