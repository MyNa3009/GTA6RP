-- Twinks: Charaktere derselben Person.
-- Gleicher Login = immer Twink. Verknuepfte Logins (Multi-Account ueber Lizenz oder PC) zaehlen auch,
-- solange die Warnung nicht ausgeblendet wurde (Config.Twinks.IncludeLinkedLogins).
-- Andere Scripts fragen Core.AreTwinks und melden Interaktionen mit Core.ReportTwinkInteraction.

Twinks = {}

local LABELS = {
    money_transfer = 'Überweisung',
    item_give = 'Item gegeben',
}

-- Beide Charaktere mit einer Abfrage
local function ownersOf(characterA, characterB)
    local rows = DB.Query(
        "SELECT id, account_id, CONCAT(firstname, ' ', lastname) AS name FROM characters WHERE id IN (?, ?)",
        { characterA, characterB }
    ) or {}
    local byId = {}
    for _, row in ipairs(rows) do
        byId[row.id] = row
    end
    return byId[characterA], byId[characterB]
end

-- Gibt 'same_login', 'linked' oder nil zurueck
function Twinks.Relation(characterA, characterB)
    characterA, characterB = tonumber(characterA), tonumber(characterB)
    if not characterA or not characterB or characterA == characterB then
        return nil
    end
    local a, b = ownersOf(characterA, characterB)
    if not a or not b then
        return nil
    end
    if a.account_id == b.account_id then
        return 'same_login', a, b
    end
    if Config.Twinks.IncludeLinkedLogins then
        local low, high = math.min(a.account_id, b.account_id), math.max(a.account_id, b.account_id)
        local linked = DB.Scalar(
            'SELECT 1 FROM account_links WHERE account_a = ? AND account_b = ? AND dismissed_at IS NULL LIMIT 1',
            { low, high }
        )
        if linked then
            return 'linked', a, b
        end
    end
    return nil
end

function Twinks.Mode(interaction)
    return Config.Twinks.Interactions[interaction] or Config.Twinks.Default
end

-- Prueft und loggt. Gibt false zurueck, wenn die Interaktion laut Config blockiert ist.
-- extra: zusaetzliche Daten fuer das Log, z. B. { amount = 500, account = 'bank' }
function Twinks.Check(characterA, characterB, interaction, extra)
    local relation, a, b = Twinks.Relation(characterA, characterB)
    if not relation then
        return true
    end
    local mode = Twinks.Mode(interaction)
    local data = {
        interaction = interaction,
        label = LABELS[interaction],
        relation = relation,
        fromCharacterId = tonumber(characterA),
        fromName = a.name,
        toCharacterId = tonumber(characterB),
        toName = b.name,
        blocked = mode == 'block' or nil,
    }
    for key, value in pairs(extra or {}) do
        data[key] = value
    end
    Core.Log({
        account_id = a.account_id,
        character_id = tonumber(characterA),
        target_account_id = a.account_id ~= b.account_id and b.account_id or nil,
        category = 'twink',
        action = interaction,
        amount = tonumber(extra and extra.amount) or nil,
        data = data,
    })
    return mode ~= 'block'
end

-- Oeffentliche API fuer andere Scripts
function Core.AreTwinks(characterA, characterB)
    return Twinks.Relation(characterA, characterB) ~= nil
end

function Core.ReportTwinkInteraction(characterA, characterB, interaction, extra)
    if type(interaction) ~= 'string' or interaction == '' then
        return true
    end
    return Twinks.Check(characterA, characterB, interaction, extra)
end

Platform.Export('AreTwinks', Core.AreTwinks)
Platform.Export('ReportTwinkInteraction', Core.ReportTwinkInteraction)
