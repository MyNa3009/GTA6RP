-- G-Menue: Forderung an die Person ausstellen, die man anschaut (Rechnung oder Strafe der eigenen Organisation).
-- Wer das darf, steht in Config.Bank.Debts.Issuers. Der Eintrag erscheint nur im Dienst und mit dem Recht.
-- Betrag, Abstand, Recht und die Zustimmung der Person prueft der Server.

if BankDisabled then
    return
end

local CFG = Config.Bank.Debts
local FACTIONS = 'core_factions'

if type(lib) ~= 'table' or type(lib.addInteraction) ~= 'function' then
    Platform.Print('warn', 'core_bank: core_lib fehlt, Forderungen lassen sich nicht ueber das G-Menue ausstellen.')
    return
end

-- Einstellung der eigenen Organisation, wenn man gerade ausstellen darf (nur Anzeige)
local function issuer()
    if not Platform.IsResourceStarted(FACTIONS) then
        return nil
    end
    local state = Platform.CallExport(FACTIONS, 'GetState')
    local config = type(state) == 'table' and state.member == true and CFG.Issuers[state.faction] or nil
    if not config or Platform.CallExport(FACTIONS, 'HasPermission', config.permission, true) ~= true then
        return nil
    end
    return config
end

local function issue(ctx)
    local info = Network.Call('bank_issuer', {})
    if not info or not info.ok then
        BankClient.Error(info and info.error)
        return
    end
    local kindLabel = CFG.Kinds[info.data.kind] or CFG.Kinds.other
    local values = lib.inputDialog(('%s an ID %d'):format(kindLabel, ctx.player.characterId), {
        { type = 'number', label = 'Betrag in $', required = true, min = 1, max = info.data.max },
        { type = 'input', label = 'Wofür', required = true, maxLength = info.data.titleMax, placeholder = 'z. B. Transport ins Krankenhaus' },
    }, { confirmLabel = 'Ausstellen' })
    if not values or not values[1] or not values[2] then
        return
    end
    local result = Network.Call('bank_issue', { serverId = ctx.player.serverId, amount = values[1], title = values[2] })
    if not result or not result.ok then
        BankClient.Error(result and result.error)
        return
    end
    BankClient.Notify(('%s ausgestellt. Zahlbar bis %s, das Geld geht in die Kasse.'):format(result.data.kindLabel or kindLabel, result.data.due or '?'), 'success')
end

lib.addInteraction({
    id = 'bank_issue',
    path = 'Organisation',
    label = 'Forderung ausstellen',
    description = 'Rechnung oder Strafe, zahlbar in der Bank',
    icon = 'banknote',
    order = 40,
    target = 'player',
    canShow = function(ctx)
        return ctx.player ~= nil and issuer() ~= nil
    end,
    onSelect = function(ctx)
        issue(ctx)
    end,
})
