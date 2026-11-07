-- core_ems im Client: eigener Stand (Krankheiten, Mediziner im Dienst), Meldung nass und Stress an den Server,
-- Medizinische Datenbank (UI). Was erlaubt ist, entscheidet der Server.

-- Braucht Core 1.10.0. Fehlt eine Bridge-Funktion, ist die Core zu alt: klar melden statt mitten im Spiel abzustuerzen.
local REQUIRED_CORE = '1.10.3'
local missingBridge = {}
for _, name in ipairs({ 'Async', 'Blackout', 'CallExport', 'DisableActionsThisFrame', 'Emit', 'FacePlayer', 'GetOwnExposure', 'GetPedStatus', 'GetPlayerPedByServerId', 'GetResourceName', 'GetTime', 'IsOwnPedInVehicle',
    'IsOwnPedDead', 'IsPauseMenuOpen', 'OnEvent', 'PlayOwnAnim', 'Print', 'RagdollOwnPed', 'RegisterClientCommand', 'SetMinimapHidden',
    'SetOwnWalkStyle', 'SetScreenEffect', 'ShakeCamera', 'StopOwnAnim', 'UiFocus', 'UiOn', 'UiSend', 'Wait' }) do
    if type(Platform[name]) ~= 'function' then
        missingBridge[#missingBridge + 1] = name
    end
end
if #missingBridge > 0 then
    Platform.Print('error', ('core_ems: Core ist zu alt, gebraucht wird mindestens %s. Fehlt in der Client-Bridge: %s. Ordner core ersetzen und Server neu starten.'):format(REQUIRED_CORE, table.concat(missingBridge, ', ')))
    EmsDisabled = true
    return
end

EmsClient = { diseases = {}, faction = { member = false } }

local CFG = Config.Ems
local FACTIONS = 'core_factions'
local SAMPLE_MS = 2000

local ERROR_TEXT = {
    not_medic = 'Das darf nur der Rettungsdienst.',
    not_on_duty = 'Dafür musst du im Dienst sein. Geh zur Umkleide.',
    no_permission = 'Dafür hast du keine Rechte.',
    target_offline = 'Die Person ist nicht mehr da.',
    too_far = 'Du bist zu weit weg. Geh näher ran.',
    not_dead = 'Die Person ist nicht bewusstlos.',
    hospital_only = 'Die Person muss ins Krankenhaus, vor Ort geht das nicht.',
    is_dead = 'Die Person ist bewusstlos. Erst hochholen.',
    target_busy = 'Gerade kümmert sich schon jemand um die Person.',
    no_medkit = 'Du brauchst einen Verbandskasten. Den verkauft der Rettungsdienst.',
    consent_declined = 'Die Person hat abgelehnt.',
    consent_timeout = 'Die Person hat nicht geantwortet.',
    not_enough_money = 'Die Person hat nicht genug Geld.',
    target_full = 'Die Person hat keinen Platz im Inventar. Das Geld ist zurück.',
    not_sick = 'Die Person hat diese Krankheit nicht (mehr).',
    not_diagnosed = 'Untersuche die Person zuerst.',
    too_fast = 'Die Behandlung braucht ihre Zeit.',
    too_soon = 'Zu früh. Zwischen zwei Behandlungen muss etwas Zeit vergehen.',
    no_id_card = 'Die Person hat keinen Personalausweis dabei.',
    invalid_input = 'Die Eingabe passt nicht.',
    timeout = 'Der Server antwortet nicht.',
}

function EmsClient.Notify(text, kind)
    Platform.Emit('core:notify', { text = text, type = kind or 'info' })
end

function EmsClient.Error(code, data)
    if code == 'too_soon' and type(data) == 'table' and data.minutes then
        EmsClient.Notify(('Zu früh. Die nächste Behandlung geht in %d Minuten.'):format(data.minutes), 'error')
        return
    end
    EmsClient.Notify(ERROR_TEXT[code] or 'Das hat nicht geklappt.', 'error')
end

function EmsClient.Call(name, data)
    local result = Network.Call(name, data)
    if not result or not result.ok then
        EmsClient.Error(result and result.error, result and result.data)
        return nil
    end
    return result.data or {}
end

------------------------------------------------------------------------
-- Stand: eigene Krankheiten (vom Server), Organisation (von core_factions)
------------------------------------------------------------------------

-- Animation waehrend eines Minigames am Patienten (Hochholen, Versorgen). Der Server startet das Minigame und
-- sagt darum auch, wann die Animation beginnt ({ kind, target }) und endet ({}).
local currentAnim = nil
Network.On('core_ems:anim', function(data)
    if type(data) ~= 'table' then
        return
    end
    if currentAnim then
        Platform.StopOwnAnim(currentAnim.dict, currentAnim.clip)
        currentAnim = nil
    end
    local anim = type(data.kind) == 'string' and SymptomData.actionAnims[data.kind] or nil
    if not anim then
        return
    end
    currentAnim = anim
    Platform.Async(function()
        if data.target then
            Platform.FacePlayer(data.target)
        end
        Platform.PlayOwnAnim(anim.dict, anim.clip, { loop = true })
        -- Waehrend des Ladens schon beendet? Dann gleich wieder aufhoeren.
        if currentAnim ~= anim then
            Platform.StopOwnAnim(anim.dict, anim.clip)
        end
    end)
end)

Network.On('core_ems:diseases', function(list)
    EmsClient.diseases = type(list) == 'table' and list or {}
    Platform.Emit('core_ems:diseasesChanged', EmsClient.diseases)
end)

Platform.OnEvent('core_factions:stateChanged', function(state)
    if type(state) == 'table' then
        EmsClient.faction = state
    end
end)

-- core_ems neu gestartet: Stand einmal holen
Platform.Async(function()
    local ok, state = pcall(Platform.CallExport, FACTIONS, 'GetState')
    if ok and type(state) == 'table' then
        EmsClient.faction = state
    end
end)

-- Mediziner im Dienst mit diesem Recht? (nur fuer die Anzeige, der Server prueft selbst)
function EmsClient.Can(key)
    local state = EmsClient.faction
    if state.member ~= true or state.faction ~= CFG.Faction or not state.onDuty then
        return false
    end
    for _, permission in ipairs(state.permissions or {}) do
        if permission == key then
            return true
        end
    end
    return false
end

------------------------------------------------------------------------
-- Nass und Stress zaehlen und dem Server melden (nur fuer die Chance, krank zu werden)
------------------------------------------------------------------------

Platform.Async(function()
    local wet, stress, elapsed = 0, 0, 0
    local step = SAMPLE_MS / 1000
    while true do
        Platform.Wait(SAMPLE_MS)
        if not Platform.IsOwnPedDead() then
            local exposure = Platform.GetOwnExposure()
            if exposure.wet then
                wet = wet + step
            end
            if exposure.sprinting or exposure.shooting or exposure.aiming then
                stress = stress + step
            end
        end
        elapsed = elapsed + step
        if elapsed >= CFG.ExposureReportSeconds then
            Network.Call('ems_exposure', { wet = wet, stress = stress })
            wet, stress, elapsed = 0, 0, 0
        end
    end
end)

------------------------------------------------------------------------
-- Medizinische Datenbank
------------------------------------------------------------------------

local RECORD_CALLS = { ems_records_search = true, ems_records_get = true, ems_records_note = true }
local uiReady, pending, open = false, nil, false

local function colors()
    local core = Config.UI.Colors
    local own = CFG.Colors or {}
    return { base = own.base or core.base, ink = own.ink or core.ink, accent = own.accent or core.accent, signal = own.signal or core.signal }
end

Platform.UiOn('ui_ready', function()
    uiReady = true
    if pending then
        Platform.UiSend(pending.action, pending.data)
        pending = nil
    end
    return { ok = true, data = { colors = colors() } }
end)

function EmsClient.OpenRecords(characterId)
    if open or Platform.IsPauseMenuOpen() then
        return
    end
    local info = EmsClient.Call('ems_records_open', {})
    if not info then
        return
    end
    open = true
    Platform.UiFocus(true, true)
    local data = { colors = colors(), canNote = info.canNote, admin = info.admin, noteMax = info.noteMax, characterId = characterId }
    if uiReady then
        Platform.UiSend('records_open', data)
    else
        pending = { action = 'records_open', data = data }
    end
end

Platform.UiOn('records_close', function()
    if open then
        open = false
        Platform.UiFocus(false)
    end
    return { ok = true }
end)

Platform.UiOn('records_call', function(data)
    if not open or type(data.name) ~= 'string' or not RECORD_CALLS[data.name] then
        return { ok = false, error = 'invalid_input' }
    end
    return Network.Call(data.name, type(data.data) == 'table' and data.data or {})
end)

Platform.RegisterClientCommand(CFG.Records.Command, function(args)
    EmsClient.OpenRecords(tonumber(args[1]))
end)

Platform.OnEvent('onResourceStop', function(resource)
    if resource == Platform.GetResourceName() and open then
        Platform.UiFocus(false)
    end
end)

-- Fuer andere Scripts im Client: { { disease, stage } }
Platform.Export('GetDiseases', function()
    return EmsClient.diseases
end)
