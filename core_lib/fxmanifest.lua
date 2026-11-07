fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'core_lib'
description 'Bibliothek fuer die eigene Core: G-Menue, Kontextmenues, Fortschritt, Minigames, Dialoge, TextUI, Zonen'
version '1.3.0'

-- Startet nach der Core und nutzt deren Config und Bridge (es gibt nur eine Stelle mit FiveM-Natives)
dependencies {
    'core',
}

shared_scripts {
    '@core/shared/config.lua',
    'config.lua',
    'data/vehicle_gta5.lua',
    'data/target_gta5.lua',
}

server_scripts {
    '@core/bridge/platform/fivem_server.lua',
    '@core/bridge/network/fivem_server.lua',
    'server/main.lua',
}

client_scripts {
    '@core/bridge/platform/fivem_client.lua',
    '@core/bridge/network/fivem_client.lua',
    'client/main.lua',
    'client/progress.lua',
    'client/minigames.lua',
    'client/dialogs.lua',
    'client/textui.lua',
    'client/menu.lua',
    'client/interact.lua',
    'client/interact_person.lua',
    'client/interact_vehicle.lua',
}

ui_page 'html/index.html'

-- init.lua und modules/ laden andere Resources selbst ('@core_lib/init.lua')
files {
    'init.lua',
    'modules/*.lua',
    'html/index.html',
    'html/menu.html',
    'html/progress.html',
    'html/game.html',
    'html/dialog.html',
    'html/textui.html',
}
