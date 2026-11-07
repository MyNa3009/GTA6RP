-- core_lib fuer andere Resources. Im fxmanifest nach der Bridge der Core eintragen, dann gibt es die Tabelle lib:
--
--   client_scripts { '@core/bridge/platform/fivem_client.lua', '@core/bridge/network/fivem_client.lua', '@core_lib/init.lua', 'client/main.lua' }
--   server_scripts { '@core/bridge/platform/fivem_server.lua', '@core/bridge/network/fivem_server.lua', '@core_lib/init.lua', 'server/main.lua' }
--
-- Funktionen mit Ergebnis (lib.progressBar, lib.skillCheck, lib.inputDialog ...) warten, bis es da ist.
-- Darum nur aus einem Thread aufrufen (Befehl, Ereignis, Platform.Async), nie aus canShow oder state.

if lib then
    return
end

local LIB = 'core_lib'
local POLL_MS = 50
local IS_CLIENT = type(Platform) == 'table' and type(Platform.GetOwnServerId) == 'function'

if type(Platform) ~= 'table' or type(Platform.CallExport) ~= 'function' then
    print('^1[core_lib] init.lua braucht die Bridge der Core 1.8.0 davor im fxmanifest.^7')
    return
end

lib = {}

local function call(name, ...)
    return Platform.CallExport(LIB, name, ...)
end

if IS_CLIENT then
    --------------------------------------------------------------------
    -- Warten auf Ergebnisse
    --------------------------------------------------------------------
    local DONE_EVENT = 'core_lib:done'
    local SELECT_EVENT = 'core_lib:select'
    local RESOURCE = Platform.GetResourceName()

    local waiting = {}   -- [id] = { done, value }

    Platform.OnEvent(DONE_EVENT, function(id, value)
        local entry = waiting[id]
        if entry then
            entry.done = true
            entry.value = value
        end
    end)

    -- id und Fehlercode aus einem Start-Export: wartet auf das Ergebnis, sonst nil und Fehlercode
    local function await(id, err)
        if not id then
            return nil, err or 'core_lib_missing'
        end
        local entry = { done = false }
        waiting[id] = entry
        local done, value = call('GetResult', id)
        if done then
            waiting[id] = nil
            return value
        end
        while not entry.done do
            Platform.Wait(POLL_MS)
        end
        waiting[id] = nil
        return entry.value
    end

    --------------------------------------------------------------------
    -- Aktionen aus Menues: laufen hier in dieser Resource, darum duerfen sie warten
    --------------------------------------------------------------------
    local handlers = {}  -- [schluessel] = function

    Platform.OnEvent(SELECT_EVENT, function(key, value)
        local fn = handlers[key]
        if not fn then
            return
        end
        Platform.Async(function()
            local ok, err = pcall(fn, value)
            if not ok then
                Platform.Print('error', ('Fehler in einer Menue-Aktion (%s): %s'):format(key, tostring(err)))
            end
        end)
    end)

    local function withKey(def, key)
        local copy = {}
        for k, v in pairs(def) do
            copy[k] = v
        end
        if key and type(def.onSelect) == 'function' then
            handlers[key] = def.onSelect
            copy.onSelect = nil
            copy.selectKey = key
        end
        return copy
    end

    --------------------------------------------------------------------
    -- Meldungen
    --------------------------------------------------------------------
    function lib.notify(text, kind, duration)
        call('Notify', text, kind, duration)
    end

    --------------------------------------------------------------------
    -- Fortschritt: true, wenn fertig. false bei Abbruch (X), Bewusstlosigkeit oder lib.cancelProgress().
    --------------------------------------------------------------------
    function lib.progressBar(options)
        return await(call('StartProgress', options)) == true
    end

    function lib.progressCircle(options)
        local copy = {}
        for k, v in pairs(type(options) == 'table' and options or {}) do
            copy[k] = v
        end
        copy.style = 'circle'
        return lib.progressBar(copy)
    end

    function lib.cancelProgress() return call('CancelProgress') == true end
    function lib.progressActive() return call('IsProgressActive') == true end

    --------------------------------------------------------------------
    -- Minigames: true, wenn geschafft. Fuer Wertvolles lieber lib.minigame auf dem Server.
    --------------------------------------------------------------------
    function lib.skillCheck(difficulty, keys)
        return await(call('StartSkillCheck', difficulty, keys)) == true
    end

    function lib.lockpick(options) return await(call('StartLockpick', options)) == true end
    function lib.hack(options) return await(call('StartHack', options)) == true end
    function lib.wires(options) return await(call('StartWires', options)) == true end
    function lib.cancelMinigame() return call('CancelMinigame') == true end

    --------------------------------------------------------------------
    -- Dialoge
    --------------------------------------------------------------------
    -- Liste der Werte oder nil bei Abbruch
    function lib.inputDialog(title, fields, options)
        return await(call('StartInput', title, fields, options))
    end

    -- 'confirm' oder 'cancel'
    function lib.alertDialog(options)
        return await(call('StartAlert', options)) or 'cancel'
    end

    function lib.closeDialog() return call('CloseDialog') == true end

    --------------------------------------------------------------------
    -- Kontextmenues
    --------------------------------------------------------------------
    local function wrapContext(def)
        local copy = withKey(def, nil)
        if type(def.options) == 'table' then
            copy.options = {}
            for index, option in ipairs(def.options) do
                copy.options[index] = withKey(option, ('%s:c:%s:%d'):format(RESOURCE, tostring(def.id), index))
            end
        end
        return copy
    end

    function lib.registerContext(def)
        if type(def) == 'table' and def.id == nil then
            local list = {}
            for i, entry in ipairs(def) do
                list[i] = wrapContext(entry)
            end
            return call('RegisterContext', list)
        end
        return call('RegisterContext', wrapContext(def))
    end

    function lib.showContext(id) return call('ShowContext', id) == true end
    function lib.hideContext() return call('HideContext') == true end
    function lib.getOpenContextMenu() return call('GetOpenContext') end

    --------------------------------------------------------------------
    -- TextUI
    --------------------------------------------------------------------
    function lib.showTextUI(text, options) return call('ShowTextUI', text, options) == true end
    function lib.hideTextUI() return call('HideTextUI') == true end
    function lib.isTextUIOpen() return call('IsTextUIOpen') end

    --------------------------------------------------------------------
    -- G-Menue
    --------------------------------------------------------------------
    -- def wie in der README: id, path, label, onSelect, optional target, vehicle, canShow, state, keepOpen ...
    function lib.addInteraction(def)
        if type(def) ~= 'table' then
            return false, 'invalid_input'
        end
        return call('AddInteraction', withKey(def, ('%s:i:%s'):format(RESOURCE, tostring(def.id))))
    end

    function lib.removeInteraction(id) return call('RemoveInteraction', id) == true end
    function lib.setInteractionCategory(path, options) return call('SetInteractionCategory', path, options) == true end
    function lib.openInteractionMenu() call('OpenInteractionMenu') end
    function lib.closeInteractionMenu() return call('CloseInteractionMenu') == true end
else
    --------------------------------------------------------------------
    -- Server
    --------------------------------------------------------------------

    -- Startet ein Minigame beim Spieler und wartet auf das Ergebnis. true nur, wenn geschafft und nicht zu schnell.
    -- kind: 'skillcheck' | 'lockpick' | 'hack' | 'wires'. Gibt bei einem Fehler false und den Fehlercode zurueck.
    function lib.minigame(source, kind, options)
        local id, err = call('StartMinigame', source, kind, options)
        if not id then
            return false, err or 'core_lib_missing'
        end
        while true do
            local result = call('GetMinigameResult', id)
            if result ~= nil then
                return result == true
            end
            Platform.Wait(POLL_MS)
        end
    end

    function lib.notify(source, text, kind)
        Platform.Notify(source, text, kind)
    end
end
