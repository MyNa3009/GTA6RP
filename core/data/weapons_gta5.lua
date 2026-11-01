-- GTA-5-spezifisch: Waffen und Todesursachen fuer Log und Admin-Menue.
-- Schluessel ist der Hash (joaat des Namens, als positive Zahl). Beim Umzug wird nur diese Datei ersetzt.

WeaponNames = {
    [2725352035] = 'Faust', -- WEAPON_UNARMED
    [2578778090] = 'Messer', -- WEAPON_KNIFE
    [1737195953] = 'Schlagstock', -- WEAPON_NIGHTSTICK
    [1317494643] = 'Hammer', -- WEAPON_HAMMER
    [2508868239] = 'Baseballschläger', -- WEAPON_BAT
    [2227010557] = 'Brechstange', -- WEAPON_CROWBAR
    [1141786504] = 'Golfschläger', -- WEAPON_GOLFCLUB
    [4192643659] = 'Flasche', -- WEAPON_BOTTLE
    [2460120199] = 'Dolch', -- WEAPON_DAGGER
    [4191993645] = 'Beil', -- WEAPON_HATCHET
    [3713923289] = 'Machete', -- WEAPON_MACHETE
    [3756226112] = 'Klappmesser', -- WEAPON_SWITCHBLADE
    [419712736] = 'Rohrzange', -- WEAPON_WRENCH
    [3441901897] = 'Streitaxt', -- WEAPON_BATTLEAXE
    [2484171525] = 'Billardqueue', -- WEAPON_POOLCUE
    [3638508604] = 'Schlagring', -- WEAPON_KNUCKLE
    [2343591895] = 'Taschenlampe', -- WEAPON_FLASHLIGHT
    [453432689] = 'Pistole', -- WEAPON_PISTOL
    [3219281620] = 'Pistole Mk II', -- WEAPON_PISTOL_MK2
    [1593441988] = 'Kampfpistole', -- WEAPON_COMBATPISTOL
    [584646201] = 'AP-Pistole', -- WEAPON_APPISTOL
    [2578377531] = 'Pistole .50', -- WEAPON_PISTOL50
    [3218215474] = 'SNS-Pistole', -- WEAPON_SNSPISTOL
    [3523564046] = 'Schwere Pistole', -- WEAPON_HEAVYPISTOL
    [137902532] = 'Vintage-Pistole', -- WEAPON_VINTAGEPISTOL
    [911657153] = 'Taser', -- WEAPON_STUNGUN
    [1198879012] = 'Leuchtpistole', -- WEAPON_FLAREGUN
    [3696079510] = 'Marksman-Pistole', -- WEAPON_MARKSMANPISTOL
    [3249783761] = 'Revolver', -- WEAPON_REVOLVER
    [2548703416] = 'Double-Action-Revolver', -- WEAPON_DOUBLEACTION
    [727643628] = 'Keramikpistole', -- WEAPON_CERAMICPISTOL
    [2441047180] = 'Navy-Revolver', -- WEAPON_NAVYREVOLVER
    [324215364] = 'Micro-SMG', -- WEAPON_MICROSMG
    [736523883] = 'SMG', -- WEAPON_SMG
    [2024373456] = 'SMG Mk II', -- WEAPON_SMG_MK2
    [4024951519] = 'Sturm-SMG', -- WEAPON_ASSAULTSMG
    [171789620] = 'Kampf-PDW', -- WEAPON_COMBATPDW
    [3675956304] = 'Reihenfeuerpistole', -- WEAPON_MACHINEPISTOL
    [3173288789] = 'Mini-SMG', -- WEAPON_MINISMG
    [1627465347] = 'Gusenberg', -- WEAPON_GUSENBERG
    [487013001] = 'Pump-Schrotflinte', -- WEAPON_PUMPSHOTGUN
    [2017895192] = 'Abgesägte Schrotflinte', -- WEAPON_SAWNOFFSHOTGUN
    [3800352039] = 'Sturm-Schrotflinte', -- WEAPON_ASSAULTSHOTGUN
    [2640438543] = 'Bullpup-Schrotflinte', -- WEAPON_BULLPUPSHOTGUN
    [984333226] = 'Schwere Schrotflinte', -- WEAPON_HEAVYSHOTGUN
    [4019527611] = 'Doppelläufige Schrotflinte', -- WEAPON_DBSHOTGUN
    [317205821] = 'Automatische Schrotflinte', -- WEAPON_AUTOSHOTGUN
    [2828843422] = 'Muskete', -- WEAPON_MUSKET
    [3220176749] = 'Sturmgewehr', -- WEAPON_ASSAULTRIFLE
    [961495388] = 'Sturmgewehr Mk II', -- WEAPON_ASSAULTRIFLE_MK2
    [2210333304] = 'Karabiner', -- WEAPON_CARBINERIFLE
    [4208062921] = 'Karabiner Mk II', -- WEAPON_CARBINERIFLE_MK2
    [2937143193] = 'Kampfgewehr', -- WEAPON_ADVANCEDRIFLE
    [3231910285] = 'Spezialkarabiner', -- WEAPON_SPECIALCARBINE
    [2132975508] = 'Bullpup-Gewehr', -- WEAPON_BULLPUPRIFLE
    [1649403952] = 'Kompaktgewehr', -- WEAPON_COMPACTRIFLE
    [2636060646] = 'Militärgewehr', -- WEAPON_MILITARYRIFLE
    [2634544996] = 'MG', -- WEAPON_MG
    [2144741730] = 'Kampf-MG', -- WEAPON_COMBATMG
    [100416529] = 'Scharfschützengewehr', -- WEAPON_SNIPERRIFLE
    [205991906] = 'Schweres Scharfschützengewehr', -- WEAPON_HEAVYSNIPER
    [3342088282] = 'Marksman-Gewehr', -- WEAPON_MARKSMANRIFLE
    [2982836145] = 'Raketenwerfer', -- WEAPON_RPG
    [2726580491] = 'Granatwerfer', -- WEAPON_GRENADELAUNCHER
    [1119849093] = 'Minigun', -- WEAPON_MINIGUN
    [2481070269] = 'Granate', -- WEAPON_GRENADE
    [741814745] = 'Haftbombe', -- WEAPON_STICKYBOMB
    [3125143736] = 'Rohrbombe', -- WEAPON_PIPEBOMB
    [615608432] = 'Molotowcocktail', -- WEAPON_MOLOTOV
    [883325847] = 'Benzinkanister', -- WEAPON_PETROLCAN
    [2741846334] = 'Überfahren', -- WEAPON_RUN_OVER_BY_CAR
    [133987706] = 'Von Fahrzeug gerammt', -- WEAPON_RAMMED_BY_CAR
    [3452007600] = 'Sturz', -- WEAPON_FALL
    [4284007675] = 'Ertrunken', -- WEAPON_DROWNING
    [1936677264] = 'Im Fahrzeug ertrunken', -- WEAPON_DROWNING_IN_VEHICLE
    [539292904] = 'Explosion', -- WEAPON_EXPLOSION
    [3750660587] = 'Feuer', -- WEAPON_FIRE
    [2339582971] = 'Verblutet', -- WEAPON_BLEEDING
    [2461879995] = 'Elektrozaun', -- WEAPON_ELECTRIC_FENCE
    [910830060] = 'Erschöpfung', -- WEAPON_EXHAUSTION
    [341774354] = 'Hubschrauberabsturz', -- WEAPON_HELI_CRASH
    [1223143800] = 'Stacheldraht', -- WEAPON_BARBED_WIRE
    [4194021054] = 'Tierangriff', -- WEAPON_ANIMAL
    [148160082] = 'Puma-Angriff', -- WEAPON_COUGAR
    [3425972830] = 'Wasserwerfer', -- WEAPON_HIT_BY_WATER_CANNON
}

-- Hash aus dem Spiel kann negativ sein, darum vorher normalisieren
function WeaponLabel(hash)
    hash = tonumber(hash)
    if not hash then
        return nil
    end
    return WeaponNames[math.floor(hash) % 4294967296]
end

-- Waffen, die Admins mit /gun geben koennen. Kurzname (ohne WEAPON_, klein) -> Spielname und Anzeige.
-- Todesursachen wie Sturz oder Ertrinken stehen hier bewusst nicht drin.
WeaponGive = {
    knife = { id = 'WEAPON_KNIFE', label = 'Messer' },
    nightstick = { id = 'WEAPON_NIGHTSTICK', label = 'Schlagstock' },
    hammer = { id = 'WEAPON_HAMMER', label = 'Hammer' },
    bat = { id = 'WEAPON_BAT', label = 'Baseballschläger' },
    crowbar = { id = 'WEAPON_CROWBAR', label = 'Brechstange' },
    golfclub = { id = 'WEAPON_GOLFCLUB', label = 'Golfschläger' },
    bottle = { id = 'WEAPON_BOTTLE', label = 'Flasche' },
    dagger = { id = 'WEAPON_DAGGER', label = 'Dolch' },
    hatchet = { id = 'WEAPON_HATCHET', label = 'Beil' },
    machete = { id = 'WEAPON_MACHETE', label = 'Machete' },
    switchblade = { id = 'WEAPON_SWITCHBLADE', label = 'Klappmesser' },
    wrench = { id = 'WEAPON_WRENCH', label = 'Rohrzange' },
    battleaxe = { id = 'WEAPON_BATTLEAXE', label = 'Streitaxt' },
    poolcue = { id = 'WEAPON_POOLCUE', label = 'Billardqueue' },
    knuckle = { id = 'WEAPON_KNUCKLE', label = 'Schlagring' },
    flashlight = { id = 'WEAPON_FLASHLIGHT', label = 'Taschenlampe' },
    pistol = { id = 'WEAPON_PISTOL', label = 'Pistole' },
    pistol_mk2 = { id = 'WEAPON_PISTOL_MK2', label = 'Pistole Mk II' },
    combatpistol = { id = 'WEAPON_COMBATPISTOL', label = 'Kampfpistole' },
    appistol = { id = 'WEAPON_APPISTOL', label = 'AP-Pistole' },
    pistol50 = { id = 'WEAPON_PISTOL50', label = 'Pistole .50' },
    snspistol = { id = 'WEAPON_SNSPISTOL', label = 'SNS-Pistole' },
    heavypistol = { id = 'WEAPON_HEAVYPISTOL', label = 'Schwere Pistole' },
    vintagepistol = { id = 'WEAPON_VINTAGEPISTOL', label = 'Vintage-Pistole' },
    stungun = { id = 'WEAPON_STUNGUN', label = 'Taser' },
    flaregun = { id = 'WEAPON_FLAREGUN', label = 'Leuchtpistole' },
    marksmanpistol = { id = 'WEAPON_MARKSMANPISTOL', label = 'Marksman-Pistole' },
    revolver = { id = 'WEAPON_REVOLVER', label = 'Revolver' },
    doubleaction = { id = 'WEAPON_DOUBLEACTION', label = 'Double-Action-Revolver' },
    ceramicpistol = { id = 'WEAPON_CERAMICPISTOL', label = 'Keramikpistole' },
    navyrevolver = { id = 'WEAPON_NAVYREVOLVER', label = 'Navy-Revolver' },
    microsmg = { id = 'WEAPON_MICROSMG', label = 'Micro-SMG' },
    smg = { id = 'WEAPON_SMG', label = 'SMG' },
    smg_mk2 = { id = 'WEAPON_SMG_MK2', label = 'SMG Mk II' },
    assaultsmg = { id = 'WEAPON_ASSAULTSMG', label = 'Sturm-SMG' },
    combatpdw = { id = 'WEAPON_COMBATPDW', label = 'Kampf-PDW' },
    machinepistol = { id = 'WEAPON_MACHINEPISTOL', label = 'Reihenfeuerpistole' },
    minismg = { id = 'WEAPON_MINISMG', label = 'Mini-SMG' },
    gusenberg = { id = 'WEAPON_GUSENBERG', label = 'Gusenberg' },
    pumpshotgun = { id = 'WEAPON_PUMPSHOTGUN', label = 'Pump-Schrotflinte' },
    sawnoffshotgun = { id = 'WEAPON_SAWNOFFSHOTGUN', label = 'Abgesägte Schrotflinte' },
    assaultshotgun = { id = 'WEAPON_ASSAULTSHOTGUN', label = 'Sturm-Schrotflinte' },
    bullpupshotgun = { id = 'WEAPON_BULLPUPSHOTGUN', label = 'Bullpup-Schrotflinte' },
    heavyshotgun = { id = 'WEAPON_HEAVYSHOTGUN', label = 'Schwere Schrotflinte' },
    dbshotgun = { id = 'WEAPON_DBSHOTGUN', label = 'Doppelläufige Schrotflinte' },
    autoshotgun = { id = 'WEAPON_AUTOSHOTGUN', label = 'Automatische Schrotflinte' },
    musket = { id = 'WEAPON_MUSKET', label = 'Muskete' },
    assaultrifle = { id = 'WEAPON_ASSAULTRIFLE', label = 'Sturmgewehr' },
    assaultrifle_mk2 = { id = 'WEAPON_ASSAULTRIFLE_MK2', label = 'Sturmgewehr Mk II' },
    carbinerifle = { id = 'WEAPON_CARBINERIFLE', label = 'Karabiner' },
    carbinerifle_mk2 = { id = 'WEAPON_CARBINERIFLE_MK2', label = 'Karabiner Mk II' },
    advancedrifle = { id = 'WEAPON_ADVANCEDRIFLE', label = 'Kampfgewehr' },
    specialcarbine = { id = 'WEAPON_SPECIALCARBINE', label = 'Spezialkarabiner' },
    bullpuprifle = { id = 'WEAPON_BULLPUPRIFLE', label = 'Bullpup-Gewehr' },
    compactrifle = { id = 'WEAPON_COMPACTRIFLE', label = 'Kompaktgewehr' },
    militaryrifle = { id = 'WEAPON_MILITARYRIFLE', label = 'Militärgewehr' },
    mg = { id = 'WEAPON_MG', label = 'MG' },
    combatmg = { id = 'WEAPON_COMBATMG', label = 'Kampf-MG' },
    sniperrifle = { id = 'WEAPON_SNIPERRIFLE', label = 'Scharfschützengewehr' },
    heavysniper = { id = 'WEAPON_HEAVYSNIPER', label = 'Schweres Scharfschützengewehr' },
    marksmanrifle = { id = 'WEAPON_MARKSMANRIFLE', label = 'Marksman-Gewehr' },
    rpg = { id = 'WEAPON_RPG', label = 'Raketenwerfer' },
    grenadelauncher = { id = 'WEAPON_GRENADELAUNCHER', label = 'Granatwerfer' },
    minigun = { id = 'WEAPON_MINIGUN', label = 'Minigun' },
    grenade = { id = 'WEAPON_GRENADE', label = 'Granate' },
    stickybomb = { id = 'WEAPON_STICKYBOMB', label = 'Haftbombe' },
    pipebomb = { id = 'WEAPON_PIPEBOMB', label = 'Rohrbombe' },
    molotov = { id = 'WEAPON_MOLOTOV', label = 'Molotowcocktail' },
    petrolcan = { id = 'WEAPON_PETROLCAN', label = 'Benzinkanister' },
}

-- "pistol", "PISTOL" oder "weapon_pistol" -> { id, label } oder nil
function WeaponByName(name)
    if type(name) ~= 'string' then
        return nil
    end
    name = name:lower():gsub('^weapon_', '')
    return WeaponGive[name]
end
