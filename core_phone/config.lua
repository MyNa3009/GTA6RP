-- Einstellungen von core_phone. Die Farben kommen aus Config.UI.Colors der Core.
-- Das Handy ist ein Item (core_inventory). Die eSIM mit der Nummer haengt an der Person, nicht am Geraet:
-- Wer sein Handy verliert, holt sich ein neues und hat dieselbe Nummer, Kontakte und Nachrichten.

Config.Phone = {
    -- Nur Werte eintragen, die von Config.UI.Colors abweichen sollen (Format 'R G B')
    Colors = {},

    Key = 'F1',                 -- Standardtaste zum Oeffnen, im Spiel aenderbar
    Command = 'handy',          -- /handy oeffnet das Handy. Admins: /handy <ID> zeigt das Handy einer Person (nur lesen)

    -- Dieses Item braucht man im Inventar. nil = Handy geht ohne Item.
    Item = 'phone',
    -- Wer beim ersten Einloggen noch kein Handy hat, bekommt einmal eins geschenkt (solange es keinen Laden gibt)
    StarterPhone = true,
    -- Bewusstlos geht das Handy nicht. Den Notruf gibt es dann im Bewusstlos-Bildschirm.
    AllowWhenDead = false,

    NumberDigits = 6,           -- Laenge der Handynummer

    MaxContacts = 100,
    ContactNameMax = 32,

    MessageMax = 300,           -- Zeichen pro Nachricht
    MessageCooldownMs = 800,    -- Pause zwischen zwei Nachrichten
    ThreadPage = 30,            -- Nachrichten pro Seite im Chat
    ThreadsShown = 40,          -- so viele Chats in der Liste

    RingSeconds = 30,           -- so lange klingelt es, danach "verpasst"
    CallsShown = 40,            -- Eintraege in der Anrufliste

    -- Toene macht das Handy selbst (keine GTA-Sounds): Klingelton, Freizeichen, Nachricht. 0 bis 1.
    Volume = 0.25,

    -- Bank-App (braucht core_bank): Kontostand, Ueberweisen, Schulden bezahlen
    Bank = { Enabled = true, RecentCount = 6 },
    -- Notruf-App (braucht core_dispatch): Notruf mit Text an einen Dienst
    Dispatch = { Enabled = true },

    Admin = {
        ViewPermission = 'player.view',   -- /handy <ID> und /nummer <Nummer>
        NumberCommand = 'nummer',
    },
}
