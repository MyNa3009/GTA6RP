-- Zustimmung der anderen Person (z. B. beim Einstellen). Die Core fragt die Person (Ja mit Y, Nein mit N),
-- gewartet wird hier in der eigenen Resource. Gibt true oder false und einen Fehlercode zurueck:
-- consent_declined, consent_timeout, target_busy, target_offline.

if FactionsDisabled then
    return
end

local CORE = 'core'
local POLL_MS = 50
local REASONS = {
    declined = 'consent_declined',
    timeout = 'consent_timeout',
    target_busy = 'target_busy',
    target_offline = 'target_offline',
    no_character = 'no_character',
    cancelled = 'consent_declined',
}

function FactionConsent(source, target, title, text)
    local id, err = Platform.CallExport(CORE, 'StartConsent', source, target, { title = title, text = text })
    if not id then
        return false, REASONS[err] or 'consent_declined'
    end
    Platform.Notify(source, Config.Consent and Config.Consent.WaitingText or 'Warte, bis die Person zustimmt…', 'info')
    while true do
        local accepted, reason = Platform.CallExport(CORE, 'GetConsentResult', id)
        if accepted == true then
            return true
        end
        if accepted == false then
            return false, REASONS[reason] or 'consent_declined'
        end
        Platform.Wait(POLL_MS)
    end
end
