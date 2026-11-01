-- Alle Items. Neues Item = neuer Eintrag hier, kein Code noetig.
--   label        Anzeigename
--   weight       Gewicht pro Stueck in Gramm
--   stack        so viele passen in einen Platz (1 = nicht stapelbar)
--   equip        passt in diesen Ausruestungs-Platz (siehe Config.Inventory.EquipSlots)
--   description  kurzer Text im Inventar
--   weapon       Waffe: { ammo = 'pistol', maxAmmo = 250 }. ammo = Kaliber (nil bei Nahkampf und Taser).
--                Jede Waffe bekommt eine Seriennummer und speichert ihre Munition selbst (meta.serial, meta.ammo).
--                Wie sie im Spiel heisst, steht in data/weapons_gta5.lua.
--   ammoType     Munition: passt in Waffen mit diesem Kaliber. Benutzen laedt sie in die Waffe in der Hand.
--   use          was beim Benutzen passiert: { remove = 1, health = 25, hunger = 25, thirst = 40, message = '...' }
--                hunger und thirst fuellen auf (0 bis 100, siehe Config.Needs in der Core)
--                Andere Scripts reagieren auf das Ereignis core_inventory:itemUsed (source, characterId, name, meta)
-- Bilder: images/<name>.png (z. B. images/water.png). Fehlt das Bild, zeigt der Platz den Namen.

Items = {
    -- Dokumente: an den Charakter gebunden, liegen in der Reihe "Dokumente" (Config.Inventory.Documents)
    id_card         = { label = 'Personalausweis', weight = 0, stack = 1, document = 'id',      description = 'Zeigt, wer du bist.' },
    license_driver  = { label = 'Führerschein',    weight = 0, stack = 1, document = 'driver',  description = 'Fahrerlaubnis mit Klassen.' },
    license_weapon  = { label = 'Waffenschein',    weight = 0, stack = 1, document = 'weapon',  description = 'Erlaubt das Führen legaler Waffen.' },
    license_pilot   = { label = 'Flugschein',      weight = 0, stack = 1, document = 'pilot',   description = 'Erlaubt das Fliegen.' },
    license_boat    = { label = 'Bootsschein',     weight = 0, stack = 1, document = 'boat',    description = 'Erlaubt das Führen von Booten.' },
    license_fishing = { label = 'Angelschein',     weight = 0, stack = 1, document = 'fishing', description = 'Erlaubt das Angeln.' },

    -- Bargeld: wiegt nichts, ein Platz fasst beliebig viel. Die Core bucht ueber exports (AddMoney, RemoveMoney).
    cash     = { label = 'Bargeld', weight = 0, stack = 1000000000000, money = true, description = 'Scheine und Münzen.' },

    -- Essen und Trinken
    water    = { label = 'Wasser',  weight = 500, stack = 10, description = 'Eine Flasche stilles Wasser.',
                 use = { remove = 1, thirst = 40, message = 'Du trinkst eine Flasche Wasser.' } },
    bread    = { label = 'Brot',    weight = 250, stack = 10, description = 'Ein Laib Brot vom Bäcker.',
                 use = { remove = 1, hunger = 25, message = 'Du isst ein Stück Brot.' } },
    sandwich = { label = 'Sandwich', weight = 200, stack = 10, description = 'Belegtes Sandwich mit Käse.',
                 use = { remove = 1, hunger = 40, message = 'Du isst ein Sandwich.' } },

    -- Werkzeug und Sonstiges
    bandage  = { label = 'Verband',  weight = 100, stack = 20, description = 'Stoppt leichte Blutungen.',
                 use = { remove = 1, health = 25, message = 'Du legst einen Verband an.' } },
    lockpick = { label = 'Dietrich', weight = 50,  stack = 10, description = 'Zum Öffnen einfacher Schlösser.' },
    phone    = { label = 'Handy',    weight = 200, stack = 1,  description = 'Dein Smartphone.' },

    -- Waffen: kommen in den Waffenplatz (= in der Hand). Benutzen im Schnellzugriff zieht sie und steckt sie wieder weg.
    -- Kaliber: pistol, smg, rifle, shotgun, sniper, mg. GTA-Namen in data/weapons_gta5.lua.
    -- Nahkampf und Taser: zaehlen keine Munition
    weapon_knife              = { label = 'Messer', weight = 300, stack = 1, equip = 'weapon', weapon = {}, description = 'Klappmesser.' },
    weapon_dagger             = { label = 'Dolch', weight = 350, stack = 1, equip = 'weapon', weapon = {}, description = 'Antiker Kavalleriedolch.' },
    weapon_switchblade        = { label = 'Springmesser', weight = 200, stack = 1, equip = 'weapon', weapon = {}, description = 'Klinge springt auf Knopfdruck.' },
    weapon_machete            = { label = 'Machete', weight = 700, stack = 1, equip = 'weapon', weapon = {}, description = 'Lange, breite Klinge.' },
    weapon_knuckle            = { label = 'Schlagring', weight = 200, stack = 1, equip = 'weapon', weapon = {}, description = 'Für die Faust.' },
    weapon_bat                = { label = 'Baseballschläger', weight = 900, stack = 1, equip = 'weapon', weapon = {}, description = 'Aus Aluminium.' },
    weapon_nightstick         = { label = 'Schlagstock', weight = 600, stack = 1, equip = 'weapon', weapon = {}, description = 'Einsatzstock.' },
    weapon_flashlight         = { label = 'Taschenlampe', weight = 400, stack = 1, equip = 'weapon', weapon = {}, description = 'Robuste Stablampe.' },
    weapon_crowbar            = { label = 'Brecheisen', weight = 1500, stack = 1, equip = 'weapon', weapon = {}, description = 'Zum Aufhebeln.' },
    weapon_hammer             = { label = 'Hammer', weight = 800, stack = 1, equip = 'weapon', weapon = {}, description = 'Zimmermannshammer.' },
    weapon_wrench             = { label = 'Rohrzange', weight = 1200, stack = 1, equip = 'weapon', weapon = {}, description = 'Schwer und verstellbar.' },
    weapon_golfclub           = { label = 'Golfschläger', weight = 700, stack = 1, equip = 'weapon', weapon = {}, description = 'Ein Eisen.' },
    weapon_poolcue            = { label = 'Billardqueue', weight = 500, stack = 1, equip = 'weapon', weapon = {}, description = 'Zweiteiliges Queue.' },
    weapon_hatchet            = { label = 'Beil', weight = 1000, stack = 1, equip = 'weapon', weapon = {}, description = 'Kurzes Handbeil.' },
    weapon_battleaxe          = { label = 'Streitaxt', weight = 2500, stack = 1, equip = 'weapon', weapon = {}, description = 'Doppelte Klinge.' },
    weapon_stone_hatchet      = { label = 'Steinbeil', weight = 1500, stack = 1, equip = 'weapon', weapon = {}, description = 'Grob behauen.' },
    weapon_bottle             = { label = 'Zerbrochene Flasche', weight = 300, stack = 1, equip = 'weapon', weapon = {}, description = 'Scharfkantig.' },
    weapon_stungun            = { label = 'Taser', weight = 300, stack = 1, equip = 'weapon', weapon = {}, description = 'Elektroschocker.' },

    -- Pistolen und Revolver
    weapon_pistol             = { label = 'Pistole', weight = 1000, stack = 1, equip = 'weapon', weapon = { ammo = 'pistol', maxAmmo = 250 }, description = 'Halbautomatische Pistole.' },
    weapon_pistol_mk2         = { label = 'Pistole Mk II', weight = 1050, stack = 1, equip = 'weapon', weapon = { ammo = 'pistol', maxAmmo = 250 }, description = 'Weiterentwickelte Pistole.' },
    weapon_combatpistol       = { label = 'Dienstpistole', weight = 1000, stack = 1, equip = 'weapon', weapon = { ammo = 'pistol', maxAmmo = 250 }, description = 'Standardwaffe im Streifendienst.' },
    weapon_appistol           = { label = 'AP-Pistole', weight = 1100, stack = 1, equip = 'weapon', weapon = { ammo = 'pistol', maxAmmo = 250 }, description = 'Vollautomatische Pistole.' },
    weapon_pistol50           = { label = 'Pistole .50', weight = 1500, stack = 1, equip = 'weapon', weapon = { ammo = 'pistol', maxAmmo = 250 }, description = 'Großes Kaliber, wenig Schuss.' },
    weapon_snspistol          = { label = 'SNS-Pistole', weight = 600, stack = 1, equip = 'weapon', weapon = { ammo = 'pistol', maxAmmo = 250 }, description = 'Klein und leicht zu verstecken.' },
    weapon_snspistol_mk2      = { label = 'SNS-Pistole Mk II', weight = 650, stack = 1, equip = 'weapon', weapon = { ammo = 'pistol', maxAmmo = 250 }, description = 'Kompakte Pistole, weiterentwickelt.' },
    weapon_heavypistol        = { label = 'Schwere Pistole', weight = 1200, stack = 1, equip = 'weapon', weapon = { ammo = 'pistol', maxAmmo = 250 }, description = 'Großes Kaliber.' },
    weapon_vintagepistol      = { label = 'Vintage-Pistole', weight = 900, stack = 1, equip = 'weapon', weapon = { ammo = 'pistol', maxAmmo = 250 }, description = 'Alte Konstruktion, zuverlässig.' },
    weapon_marksmanpistol     = { label = 'Marksman-Pistole', weight = 1300, stack = 1, equip = 'weapon', weapon = { ammo = 'pistol', maxAmmo = 250 }, description = 'Einzelschuss, hohe Durchschlagskraft.' },
    weapon_ceramicpistol      = { label = 'Keramikpistole', weight = 700, stack = 1, equip = 'weapon', weapon = { ammo = 'pistol', maxAmmo = 250 }, description = 'Fällt in keinem Metalldetektor auf.' },
    weapon_revolver           = { label = 'Schwerer Revolver', weight = 1400, stack = 1, equip = 'weapon', weapon = { ammo = 'pistol', maxAmmo = 250 }, description = 'Sechs Schuss.' },
    weapon_revolver_mk2       = { label = 'Schwerer Revolver Mk II', weight = 1450, stack = 1, equip = 'weapon', weapon = { ammo = 'pistol', maxAmmo = 250 }, description = 'Sechs Schuss, weiterentwickelt.' },
    weapon_doubleaction       = { label = 'Double-Action-Revolver', weight = 1100, stack = 1, equip = 'weapon', weapon = { ammo = 'pistol', maxAmmo = 250 }, description = 'Klassischer Revolver.' },
    weapon_navyrevolver       = { label = 'Navy-Revolver', weight = 1200, stack = 1, equip = 'weapon', weapon = { ammo = 'pistol', maxAmmo = 250 }, description = 'Historischer Revolver.' },
    weapon_machinepistol      = { label = 'Reihenfeuerpistole', weight = 1300, stack = 1, equip = 'weapon', weapon = { ammo = 'pistol', maxAmmo = 250 }, description = 'Kompakt und schnell.' },

    -- Maschinenpistolen
    weapon_microsmg           = { label = 'Micro-SMG', weight = 1800, stack = 1, equip = 'weapon', weapon = { ammo = 'smg', maxAmmo = 250 }, description = 'Klein und schnell.' },
    weapon_minismg            = { label = 'Mini-SMG', weight = 1700, stack = 1, equip = 'weapon', weapon = { ammo = 'smg', maxAmmo = 250 }, description = 'Kompakte Maschinenpistole.' },
    weapon_smg                = { label = 'Maschinenpistole', weight = 3000, stack = 1, equip = 'weapon', weapon = { ammo = 'smg', maxAmmo = 250 }, description = 'Kompakte Maschinenpistole.' },
    weapon_smg_mk2            = { label = 'Maschinenpistole Mk II', weight = 3100, stack = 1, equip = 'weapon', weapon = { ammo = 'smg', maxAmmo = 250 }, description = 'Weiterentwickelte Maschinenpistole.' },
    weapon_assaultsmg         = { label = 'Sturm-SMG', weight = 3000, stack = 1, equip = 'weapon', weapon = { ammo = 'smg', maxAmmo = 250 }, description = 'Maschinenpistole mit großem Magazin.' },
    weapon_combatpdw          = { label = 'Kampf-PDW', weight = 3000, stack = 1, equip = 'weapon', weapon = { ammo = 'smg', maxAmmo = 250 }, description = 'Persönliche Verteidigungswaffe.' },
    weapon_gusenberg          = { label = 'Gusenberg', weight = 4500, stack = 1, equip = 'weapon', weapon = { ammo = 'smg', maxAmmo = 250 }, description = 'Trommelmagazin, alte Schule.' },

    -- Gewehre
    weapon_assaultrifle       = { label = 'Sturmgewehr', weight = 3500, stack = 1, equip = 'weapon', weapon = { ammo = 'rifle', maxAmmo = 250 }, description = 'Klassisches Sturmgewehr.' },
    weapon_assaultrifle_mk2   = { label = 'Sturmgewehr Mk II', weight = 3600, stack = 1, equip = 'weapon', weapon = { ammo = 'rifle', maxAmmo = 250 }, description = 'Weiterentwickeltes Sturmgewehr.' },
    weapon_carbinerifle       = { label = 'Karabiner', weight = 3500, stack = 1, equip = 'weapon', weapon = { ammo = 'rifle', maxAmmo = 250 }, description = 'Sturmgewehr im Karabiner-Format.' },
    weapon_carbinerifle_mk2   = { label = 'Karabiner Mk II', weight = 3600, stack = 1, equip = 'weapon', weapon = { ammo = 'rifle', maxAmmo = 250 }, description = 'Weiterentwickelter Karabiner.' },
    weapon_advancedrifle      = { label = 'Fortschrittliches Gewehr', weight = 3400, stack = 1, equip = 'weapon', weapon = { ammo = 'rifle', maxAmmo = 250 }, description = 'Bullpup-Gewehr.' },
    weapon_specialcarbine     = { label = 'Spezialkarabiner', weight = 3500, stack = 1, equip = 'weapon', weapon = { ammo = 'rifle', maxAmmo = 250 }, description = 'Präzise und kontrollierbar.' },
    weapon_specialcarbine_mk2 = { label = 'Spezialkarabiner Mk II', weight = 3600, stack = 1, equip = 'weapon', weapon = { ammo = 'rifle', maxAmmo = 250 }, description = 'Weiterentwickelter Spezialkarabiner.' },
    weapon_bullpuprifle       = { label = 'Bullpup-Gewehr', weight = 3300, stack = 1, equip = 'weapon', weapon = { ammo = 'rifle', maxAmmo = 250 }, description = 'Kurz und handlich.' },
    weapon_bullpuprifle_mk2   = { label = 'Bullpup-Gewehr Mk II', weight = 3400, stack = 1, equip = 'weapon', weapon = { ammo = 'rifle', maxAmmo = 250 }, description = 'Weiterentwickeltes Bullpup-Gewehr.' },
    weapon_compactrifle       = { label = 'Kompaktgewehr', weight = 2800, stack = 1, equip = 'weapon', weapon = { ammo = 'rifle', maxAmmo = 250 }, description = 'Gekürztes Sturmgewehr.' },

    -- Schrotflinten
    weapon_pumpshotgun        = { label = 'Pumpgun', weight = 3500, stack = 1, equip = 'weapon', weapon = { ammo = 'shotgun', maxAmmo = 100 }, description = 'Vorderschaftrepetierflinte.' },
    weapon_pumpshotgun_mk2    = { label = 'Pumpgun Mk II', weight = 3600, stack = 1, equip = 'weapon', weapon = { ammo = 'shotgun', maxAmmo = 100 }, description = 'Weiterentwickelte Pumpgun.' },
    weapon_sawnoffshotgun     = { label = 'Abgesägte Schrotflinte', weight = 2500, stack = 1, equip = 'weapon', weapon = { ammo = 'shotgun', maxAmmo = 100 }, description = 'Kurzer Lauf, große Streuung.' },
    weapon_dbshotgun          = { label = 'Doppelläufige Schrotflinte', weight = 2200, stack = 1, equip = 'weapon', weapon = { ammo = 'shotgun', maxAmmo = 100 }, description = 'Zwei Schuss.' },
    weapon_assaultshotgun     = { label = 'Sturmschrotflinte', weight = 4000, stack = 1, equip = 'weapon', weapon = { ammo = 'shotgun', maxAmmo = 100 }, description = 'Halbautomatisch.' },
    weapon_bullpupshotgun     = { label = 'Bullpup-Schrotflinte', weight = 3500, stack = 1, equip = 'weapon', weapon = { ammo = 'shotgun', maxAmmo = 100 }, description = 'Kompakte Schrotflinte.' },
    weapon_heavyshotgun       = { label = 'Schwere Schrotflinte', weight = 4200, stack = 1, equip = 'weapon', weapon = { ammo = 'shotgun', maxAmmo = 100 }, description = 'Trommelmagazin.' },
    weapon_autoshotgun        = { label = 'Automatische Schrotflinte', weight = 3800, stack = 1, equip = 'weapon', weapon = { ammo = 'shotgun', maxAmmo = 100 }, description = 'Vollautomatisch.' },
    weapon_musket             = { label = 'Muskete', weight = 4500, stack = 1, equip = 'weapon', weapon = { ammo = 'shotgun', maxAmmo = 100 }, description = 'Vorderlader.' },

    -- Scharfschuetzengewehre
    weapon_sniperrifle        = { label = 'Scharfschützengewehr', weight = 6000, stack = 1, equip = 'weapon', weapon = { ammo = 'sniper', maxAmmo = 100 }, description = 'Für große Entfernungen.' },
    weapon_heavysniper        = { label = 'Schweres Scharfschützengewehr', weight = 12000, stack = 1, equip = 'weapon', weapon = { ammo = 'sniper', maxAmmo = 100 }, description = 'Großes Kaliber.' },
    weapon_heavysniper_mk2    = { label = 'Schweres Scharfschützengewehr Mk II', weight = 12500, stack = 1, equip = 'weapon', weapon = { ammo = 'sniper', maxAmmo = 100 }, description = 'Weiterentwickelt.' },
    weapon_marksmanrifle      = { label = 'Präzisionsgewehr', weight = 5000, stack = 1, equip = 'weapon', weapon = { ammo = 'sniper', maxAmmo = 100 }, description = 'Halbautomatisch, präzise.' },
    weapon_marksmanrifle_mk2  = { label = 'Präzisionsgewehr Mk II', weight = 5100, stack = 1, equip = 'weapon', weapon = { ammo = 'sniper', maxAmmo = 100 }, description = 'Weiterentwickeltes Präzisionsgewehr.' },

    -- Maschinengewehre
    weapon_mg                 = { label = 'Maschinengewehr', weight = 9000, stack = 1, equip = 'weapon', weapon = { ammo = 'mg', maxAmmo = 500 }, description = 'Schweres Maschinengewehr.' },
    weapon_combatmg           = { label = 'Kampf-MG', weight = 9500, stack = 1, equip = 'weapon', weapon = { ammo = 'mg', maxAmmo = 500 }, description = 'Leichtes Maschinengewehr.' },
    weapon_combatmg_mk2       = { label = 'Kampf-MG Mk II', weight = 9600, stack = 1, equip = 'weapon', weapon = { ammo = 'mg', maxAmmo = 500 }, description = 'Weiterentwickeltes Kampf-MG.' },

    -- Munition: Benutzen laedt so viel wie moeglich in die passende Waffe in der Hand
    ammo_pistol  = { label = 'Pistolenmunition', weight = 12, stack = 250, ammoType = 'pistol',  use = { loadAmmo = true }, description = 'Passt in Pistolen.' },
    ammo_smg     = { label = 'MP-Munition',      weight = 12, stack = 250, ammoType = 'smg',     use = { loadAmmo = true }, description = 'Passt in Maschinenpistolen.' },
    ammo_rifle   = { label = 'Gewehrmunition',   weight = 16, stack = 250, ammoType = 'rifle',   use = { loadAmmo = true }, description = 'Passt in Gewehre.' },
    ammo_shotgun = { label = 'Schrotpatronen',   weight = 40, stack = 100, ammoType = 'shotgun', use = { loadAmmo = true }, description = 'Passt in Flinten.' },
    ammo_sniper  = { label = 'Scharfschützenmunition', weight = 30, stack = 100, ammoType = 'sniper', use = { loadAmmo = true }, description = 'Passt in Scharfschützen- und Präzisionsgewehre.' },
    ammo_mg      = { label = 'MG-Munition',      weight = 16, stack = 500, ammoType = 'mg',      use = { loadAmmo = true }, description = 'Passt in Maschinengewehre.' },

    -- Rucksaecke: bagLevel verweist auf Config.Inventory.Backpacks. Der Inhalt reist mit dem Rucksack.
    backpack_1 = { label = 'Rucksack Level 1', weight = 600,  stack = 1, equip = 'backpack', bagLevel = 1, description = '5 Plätze, bis 10 kg.' },
    backpack_2 = { label = 'Rucksack Level 2', weight = 800,  stack = 1, equip = 'backpack', bagLevel = 2, description = '10 Plätze, bis 15 kg.' },
    backpack_3 = { label = 'Rucksack Level 3', weight = 1000, stack = 1, equip = 'backpack', bagLevel = 3, description = '15 Plätze, bis 20 kg.' },
    backpack_4 = { label = 'Rucksack Level 4', weight = 1200, stack = 1, equip = 'backpack', bagLevel = 4, description = '25 Plätze, bis 30 kg.' },

    -- Kleidung: jedes Teil ist ein eigenes Item. Sie stehen in data/clothing_catalog_gta5.lua,
    -- erzeugt von tools/kleidung.py aus tools/kleidung_auswahl.json (mit Bild und GTA-Nummern).
}

-- Alte Item-Namen, die beim Laden umbenannt werden
ItemAliases = {
    backpack = 'backpack_4', -- bis 0.4.0 gab es nur einen Rucksack mit 20 Plaetzen
    -- bis 0.6 gab es nur eine allgemeine Kleidung pro Platz
    clothing_mask = 'mask_balaclava', clothing_hat = 'hat_beanie', clothing_glasses = 'glasses_sun', clothing_ears = 'ears_studs',
    clothing_jacket = 'shirt_white', clothing_shirt = 'shirt_white', clothing_watch = 'watch_gold',
    clothing_gloves = 'gloves_leather', clothing_pants = 'pants_jeans', clothing_shoes = 'shoes_sneaker',
}

-- Item nach Name oder nil
function ItemDef(name)
    return type(name) == 'string' and Items[name] or nil
end
