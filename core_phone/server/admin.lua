-- Admins sehen alles: /handy <ID> zeigt das Handy einer Person nur zum Lesen (Kontakte, Chats auch geloeschte,
-- Anrufliste), auch offline. Das laeuft ueber phone_open in numbers.lua. Hier: /nummer und die Befehlsliste.

if PhoneDisabled then
    return
end

local CFG = Config.Phone
local ADMIN = CFG.Admin

-- /nummer <Nummer>: wem gehoert sie?
Platform.RegisterCommand(ADMIN.NumberCommand, function(source, args)
    local allowed = Phone.Core('AuthorizeCommand', source, ADMIN.NumberCommand, ADMIN.ViewPermission, args, false)
    if not allowed then
        return
    end
    local number = Numbers.Normalize(table.concat(args, ''))
    if not number then
        Platform.Notify(source, ('Benutzung: /%s <Nummer mit %d Ziffern>'):format(ADMIN.NumberCommand, CFG.NumberDigits), 'error')
        return
    end
    local owner = Numbers.Owner(number)
    if not owner then
        Platform.Notify(source, ('Die Nummer %s ist nicht vergeben.'):format(number), 'error')
        return
    end
    Platform.Notify(source, ('Die Nummer %s gehört ID %d (%s).'):format(number, owner, Phone.NameOf(owner) or 'unbekannt'), 'info')
end)

DB.Ready(function()
    Phone.Core('AddCommandHelp', {
        title = 'Handy',
        entries = {
            { usage = ('/%s 17'):format(CFG.Command), text = 'Handy von ID 17 ansehen (nur lesen): Kontakte, Chats auch gelöschte, Anrufliste. Geht auch offline, jeder Blick wird geloggt.', permission = ADMIN.ViewPermission },
            { usage = ('/%s 482103'):format(ADMIN.NumberCommand), text = 'Zeigt, wem eine Handynummer gehört.', permission = ADMIN.ViewPermission },
        },
    })
end)
