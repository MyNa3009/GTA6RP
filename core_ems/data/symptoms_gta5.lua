-- GTA-5-spezifisch: Animationen, Bildschirm-Effekte, Kamera-Wackeln und Gangarten fuer Symptome von Krankheiten.
-- Beim Umzug wird nur diese Datei ersetzt.

SymptomData = {
    anims = {
        cough    = { dict = 'timetable@gardener@smoking_joint', clip = 'idle_cough', ms = 3500 },
        sneeze   = { dict = 'timetable@gardener@smoking_joint', clip = 'idle_cough', ms = 2000 },
        headache = { dict = 'anim@mp_player_intcelebrationmale@face_palm', clip = 'face_palm', ms = 3000 },
        vomit    = { dict = 'oddjobs@taxi@tie', clip = 'vomit_outside', ms = 6000 },
    },
    -- Bildschirm-Effekte (AnimpostFX)
    effects = {
        blur = 'DrugsDrivingIn',
    },
    -- Kamera-Wackeln (ShakeGameplayCam)
    shake = 'DRUNK_SHAKE',
    -- Gangarten (Movement Clipsets)
    walks = {
        sick     = 'move_m@injured',
        confused = 'move_m@drunk@slightlydrunk',
    },
    fadeMs = 400,          -- Ab- und Aufblenden bei einem Blackout
    -- Mediziner beim Behandeln (Fortschrittsbalken)
    treatAnim = { scenario = 'CODE_HUMAN_MEDIC_TEND_TO_DEAD' },
}
