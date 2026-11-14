-- Einstellungen von core_bank. Die Farben kommen aus Config.UI.Colors der Core.
-- Das Geld selbst liegt weiter in der Core (Spalte bank am Charakter). core_bank fuehrt Kontonummer,
-- Kontoauszug und Schulden und regelt, wo man an sein Geld kommt.

Config.Bank = {
    -- Name der Bank in beiden UIs
    Name = 'Fleeca Bank',

    -- Nur Werte eintragen, die von Config.UI.Colors abweichen sollen (Format 'R G B'), z. B. accent = '46 160 90'
    Colors = {},

    -- Filiale: so nah muss man am Schalter stehen (Meter). Der Server prueft das bei jeder Anfrage.
    BranchDistance = 2.5,

    -- Text im Kontoauszug und Verwendungszweck: Laengen
    PurposeMaxLength = 60,
    -- Kontoauszug: Zeilen pro Seite, Uebersicht: so viele letzte Buchungen
    PageSize = 20,
    RecentCount = 8,
    -- Ueberweisen: so viele letzte Empfaenger werden vorgeschlagen
    RecentRecipients = 6,

    -- Ueberweisung: hoechster Betrag auf einmal (zusaetzlich gilt Config.Money.MaxAmount der Core)
    TransferMax = 1000000,

    -- Bankautomat: schnelles Geld unterwegs, aber mit Grenzen. Ueberweisen und Schulden gibt es nur in der Filiale.
    Atm = {
        Distance = 1.6,            -- so nah muss man am Automaten stehen (Meter)
        WithdrawMax = 5000,        -- hoechste Auszahlung auf einmal
        DailyWithdraw = 20000,     -- hoechste Summe in 24 Stunden an Automaten, 0 = ohne Grenze
        Deposit = true,            -- Einzahlen am Automaten erlaubt
        DepositMax = 10000,        -- hoechste Einzahlung auf einmal
        QuickAmounts = { 100, 200, 500, 1000, 2000, 5000 },
        RecentCount = 5,
    },

    -- Schulden: Strafen, Rechnungen und Gebuehren. Jede hat eine Frist. Danach kommt einmal die Mahngebuehr dazu,
    -- und die Bank zieht den Betrag vom Konto ein, soweit Geld da ist. Der Rest bleibt offen.
    Debts = {
        DueHours = 72,             -- Frist ohne eigene Angabe
        MaxDueHours = 720,
        LateFeePercent = 10,       -- Mahngebuehr auf den offenen Rest, 0 = keine
        AutoCollect = true,        -- nach der Frist vom Konto einziehen
        CollectKeep = 500,         -- so viel bleibt beim Einzug immer auf dem Konto
        SweepMinutes = 10,         -- so oft prueft der Server ueberfaellige Schulden
        SweepLimit = 100,          -- hoechstens so viele pro Lauf
        TitleMaxLength = 120,
        MaxAmount = 1000000,
        PageSize = 30,
        -- Glaeubiger ohne Organisation
        StateLabel = 'Staat San Andreas',
        -- Bezeichnungen der Arten in Meldungen
        Kinds = { fine = 'Strafe', invoice = 'Rechnung', fee = 'Gebühr', other = 'Forderung' },

        -- Wer im Spiel Forderungen ausstellen darf (G-Menue, Person anschauen). Schluessel = Organisation aus core_factions.
        -- Das Geld geht beim Bezahlen in die Kasse der Organisation. consent = true: Die Person muss zustimmen (Rechnung).
        -- Ohne Zustimmung (Strafe) reicht das Recht. Das Recht erscheint im Organisationsmenue unter Anpassung.
        Issuers = {
            ems = { kind = 'invoice', label = 'Rechnung ausstellen', permission = 'bank.invoice', minRank = 3, max = 25000, consent = true },
            -- lspd = { kind = 'fine', label = 'Strafe ausstellen', permission = 'bank.fine', minRank = 2, max = 100000, consent = false },
        },
        IssueDistance = 3.0,
    },

    -- Admins: /konto <ID> zeigt Konto, Kontoauszug und Schulden jeder Person, auch offline.
    Admin = {
        Command = 'konto',
        ViewPermission = 'player.view',
        ManagePermission = 'money.manage',   -- Forderung eintragen oder erlassen
    },
}
