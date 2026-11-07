fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'core'
description 'Eigene Core: Login, Charaktere, permanente IDs, Geld, Tod, Teamraenge, Admin-Menue, Tickets, Logging'
version '1.8.2'

dependencies {
    'oxmysql',
    'spawnmanager', -- Spawn in der Client-Bridge (bridge/platform/fivem_client.lua)
}

-- Config und GTA-5-Daten (nur Tabellen, keine Natives) auf beiden Seiten
shared_scripts {
    'shared/config.lua',
    'data/spawn_gta5.lua',
    'data/models_gta5.lua',
    'data/weapons_gta5.lua',
    'data/jail_gta5.lua',
}

-- Reihenfolge zaehlt: erst die Bridges, dann Log und Accounts, Login zuletzt
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/platform/fivem_server.lua',
    'bridge/database/oxmysql.lua',
    'bridge/identity/fivem.lua',
    'bridge/network/fivem_server.lua',
    'server/log.lua',
    'server/log_archive.lua',
    'server/accounts.lua',
    'server/main.lua',
    'server/permissions.lua',
    'server/multiaccount.lua',
    'server/devices.lua',
    'server/twinks.lua',
    'server/characters.lua',
    'server/death.lua',
    'server/money.lua',
    'server/consent.lua',
    'server/needs.lua',
    'server/admin.lua',
    'server/punishments.lua',
    'server/bans.lua',
    'server/jail.lua',
    'server/moderation.lua',
    'server/vehicles.lua',
    'server/admin_tools.lua',
    'server/spectate.lua',
    'server/tickets.lua',
    'server/admin_help.lua',
    'server/admin_keys.lua',
    'server/auth.lua',
}

client_scripts {
    'bridge/platform/fivem_client.lua',
    'bridge/network/fivem_client.lua',
    'data/effects_gta5.lua',
    'client/notify.lua',
    'client/consent.lua',
    'client/main.lua',
    'client/death.lua',
    'client/jail.lua',
    'client/money.lua',
    'client/needs.lua',
    'client/overhead.lua',
    'client/noclip.lua',
    'client/vehicles.lua',
    'client/admin.lua',
    'client/admin_key.lua',
    'client/admin_esp.lua',
    'client/admin_tools.lua',
    'client/spectate.lua',
    'client/tickets.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/login.html',
    'html/characters.html',
    'html/death.html',
    'html/money.html',
    'html/needs.html',
    'html/jail.html',
    'html/admin.html',
    'html/adminkey.html',
    'html/tickets.html',
    'html/notify.html',
    'html/consent.html',
}
