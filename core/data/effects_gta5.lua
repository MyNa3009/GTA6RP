-- GTA-5-spezifisch: Bildeffekte des Spiels. Beim Umzug wird nur diese Datei ersetzt.
-- Name eines AnimPostFX aus GTA 5. nil schaltet den Effekt ab.

ScreenEffects = {
    -- Waehrend man bewusstlos ist: Bild grau und dunkler, passend zum Bewusstlos-Bildschirm
    Unconscious = 'DeathFailOut',
}

-- Animationen rund um Tod und Hochholen
DeathAnims = {
    -- Nach dem Hochholen vor Ort: vom Boden aufrappeln statt einfach dazustehen
    getUp = { dict = 'get_up@directional@movement@from_knees@action', clip = 'getup_r_0', ms = 2500 },
}
