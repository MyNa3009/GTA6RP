-- Geld im Client. Die Zahlen kommen immer vom Server.
-- Das lokale Ereignis core:moneyChanged ({ cash, bank, changed? }) bekommt das HUD (Resource core_hud)
-- und jedes andere Script. exports.core:GetMoney() liefert den letzten Stand.
-- Config.Money.Hud = true zeigt zusaetzlich die alte, eigene Geldanzeige.
-- Nur zur Anzeige: Ein Cheater kann diese Werte auf seinem eigenen Client faelschen.
-- Ob jemand genug Geld hat, entscheidet immer der Server.

MoneyHud = {}

local shown = false
local lastMoney = nil

local function amount(value)
    value = tonumber(value)
    return value and math.floor(value) or 0
end

function MoneyHud.Show(money)
    money = money or {}
    lastMoney = { cash = amount(money.cash), bank = amount(money.bank) }
    Platform.Emit('core:moneyChanged', { cash = lastMoney.cash, bank = lastMoney.bank })

    if not Config.Money.Hud then
        return
    end
    shown = true
    Client.uiOpen('money', 'money_open', {
        colors = Config.UI.Colors,
        currency = Config.UI.Currency,
        deltaVisibleMs = Config.Money.DeltaVisibleMs,
        cash = lastMoney.cash,
        bank = lastMoney.bank,
    }, false)
end

function MoneyHud.Hide()
    lastMoney = nil
    Platform.Emit('core:moneyChanged', nil)

    if not shown then
        return
    end
    shown = false
    Client.uiClose('money', 'money_close')
end

-- Vom Server nach jeder Buchung
Network.On('core:money:update', function(data)
    if type(data) ~= 'table' then
        return
    end
    lastMoney = { cash = amount(data.cash), bank = amount(data.bank) }
    local changed = type(data.changed) == 'table' and data.changed or nil
    Platform.Emit('core:moneyChanged', { cash = lastMoney.cash, bank = lastMoney.bank, changed = changed })

    if shown then
        Platform.UiSend('money_update', {
            cash = lastMoney.cash,
            bank = lastMoney.bank,
            changed = changed,
        })
    end
end)

Platform.Export('GetMoney', function()
    return lastMoney and { cash = lastMoney.cash, bank = lastMoney.bank } or nil
end)
