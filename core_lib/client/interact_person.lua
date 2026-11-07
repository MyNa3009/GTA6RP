-- G-Menue, Kategorie Person: Ausweis zeigen, Durchsuchen, Geld geben.
-- Alles laeuft ueber die Exports des Inventars. Ob es erlaubt ist (Distanz, Haende hoch, genug Geld), prueft der Server.
if LibDisabled then return end

local CFG = Config.Lib.Interact
local INVENTORY = 'core_inventory'

local ERROR_TEXT = {
    inventory_missing = 'Das Inventar läuft gerade nicht.',
    give_failed = 'Das Geld konnte nicht übergeben werden.',
}

local function inventoryRunning()
    return Platform.IsResourceStarted(INVENTORY)
end

local function needsInventory(fn)
    return function(ctx)
        if not inventoryRunning() then
            Lib.Notify(ERROR_TEXT.inventory_missing, 'error')
            return
        end
        fn(ctx)
    end
end

Interact.SetCategory('Person/Ausweis zeigen', { icon = 'id-card', order = 10 })

for index, document in ipairs(CFG.Documents) do
    Interact.Add({
        id = 'person_doc_' .. document.type,
        path = 'Person/Ausweis zeigen',
        label = document.label,
        icon = 'id-card',
        order = index,
        target = 'player',
        canShow = inventoryRunning,
        onSelect = needsInventory(function(ctx)
            Platform.CallExport(INVENTORY, 'ShowDocument', document.type, ctx.player.serverId)
        end),
    }, 'core_lib')
end

Interact.Add({
    id = 'person_search',
    path = 'Person',
    label = 'Durchsuchen',
    description = 'Geht nur, wenn die Person die Hände oben hat oder gefesselt ist.',
    icon = 'search',
    order = 20,
    target = 'player',
    canShow = inventoryRunning,
    onSelect = needsInventory(function(ctx)
        Platform.CallExport(INVENTORY, 'SearchPlayer', ctx.player.serverId)
    end),
}, 'core_lib')

Interact.Add({
    id = 'person_give_cash',
    path = 'Person',
    label = 'Geld geben',
    description = 'Bargeld aus deinem Inventar übergeben.',
    icon = 'banknote',
    order = 30,
    target = 'player',
    canShow = inventoryRunning,
    onSelect = needsInventory(function(ctx)
        local target = ctx.player
        local id = Dialogs.Input(('Geld geben an ID %d'):format(target.characterId), {
            { type = 'number', label = 'Betrag', min = CFG.GiveCash.Min, max = CFG.GiveCash.Max, step = 1, required = true,
              description = 'Nur ganze Beträge. Das Geld geht sofort an die Person.' },
        }, { confirmLabel = 'Übergeben' })
        if not id then
            return
        end
        local values = Lib.Await(id)
        local amount = values and math.floor(tonumber(values[1]) or 0)
        if not amount or amount < CFG.GiveCash.Min then
            return
        end
        local ok = Platform.CallExport(INVENTORY, 'GiveItem', target.serverId, 'cash', amount)
        if ok == nil then
            Lib.Notify(ERROR_TEXT.give_failed, 'error')
        end
    end),
}, 'core_lib')
