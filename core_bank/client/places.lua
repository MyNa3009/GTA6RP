-- Orte im Client: Filialen mit Blip, Markierung und Hinweis, dazu jeder Bankautomat der Spielwelt.
-- Hier wird nur angezeigt und die Taste gelesen. Ob man wirklich dort steht, prueft der Server beim Oeffnen
-- und bei jeder Anfrage.

if BankDisabled then
    return
end

local CFG = Config.Bank
local ATM = CFG.Atm
local KEY = 'interact'
local MARKER_DISTANCE = 15.0   -- ab hier wird die Markierung der Filiale gezeichnet
local ATM_SCAN_MS = 700        -- Suche nach einem Automaten in der Naehe
local ATM_NEAR_MS = 250        -- Pruefung, ob man noch davor steht

local blips = {}
local keyWasDown = false
local branchHint = false       -- Hinweis einer Filiale ist zu sehen (geht vor dem Automaten)
local atmNear = nil            -- Automat, vor dem man steht: { x, y, z }

local function markerStyle()
    local style = {}
    for k, v in pairs(BankMarker) do
        style[k] = v
    end
    local r, g, b = BankClient.Colors().accent:match('^(%d+) (%d+) (%d+)$')
    style.color = { r = tonumber(r), g = tonumber(g), b = tonumber(b) }
    return style
end

local MARKER = markerStyle()

-- Taste nur einmal pro Druck (nicht jedes Frame, solange sie gehalten wird)
local function pressedOnce()
    local down = Platform.IsActionPressed(KEY)
    local pressed = down and not keyWasDown
    keyWasDown = down
    return pressed
end

local function hint(text)
    lib.showTextUI(text, { key = Platform.GetActionLabel(KEY), position = 'left' })
end

------------------------------------------------------------------------
-- Filialen
------------------------------------------------------------------------

local function hideBranchHint(point)
    if point.hinted then
        point.hinted = false
        branchHint = false
        lib.hideTextUI()
    end
end

for index, branch in ipairs(BankBranches) do
    blips[#blips + 1] = Platform.AddBlip({ coords = branch, sprite = BankBlip.sprite, color = BankBlip.color, scale = BankBlip.scale, label = BankBlip.label, shortRange = true })

    lib.points.new({
        coords = branch,
        distance = MARKER_DISTANCE,
        nearby = function(self)
            Platform.DrawMarkerAt(branch, MARKER)
            local close = self.currentDistance and self.currentDistance <= CFG.BranchDistance
            if close and not BankClient.open and not Platform.IsOwnPedInVehicle() then
                if not self.hinted then
                    self.hinted = true
                    branchHint = true
                    hint(CFG.Name)
                end
                if pressedOnce() then
                    hideBranchHint(self)
                    Platform.Async(function()
                        BankClient.Open({ channel = 'bank', branch = index })
                    end)
                end
            else
                hideBranchHint(self)
            end
        end,
        onExit = hideBranchHint,
    })
end

------------------------------------------------------------------------
-- Bankautomaten: Objekte der Spielwelt mit einem Modell aus data/atms_gta5.lua
------------------------------------------------------------------------

local function leaveAtm()
    if atmNear then
        atmNear = nil
        if not branchHint then
            lib.hideTextUI()
        end
    end
end

-- Laeuft nur, solange man vor einem Automaten steht: Taste lesen
local function atmKeyLoop()
    Platform.Async(function()
        while atmNear do
            if pressedOnce() and not BankClient.open then
                local place = atmNear
                leaveAtm()
                BankClient.Open({ channel = 'atm', atm = { x = place.x, y = place.y, z = place.z } })
                return
            end
            Platform.Wait(0)
        end
    end)
end

Platform.Async(function()
    while true do
        local found = nil
        if not BankClient.open and not branchHint and not Platform.IsOwnPedInVehicle() and not Platform.IsOwnPedDead() then
            found = Platform.FindNearbyObject(BankAtmModels, ATM.Distance)
        end
        if found and not atmNear then
            atmNear = found
            hint('Bankautomat')
            atmKeyLoop()
        elseif found then
            atmNear = found
        else
            leaveAtm()
        end
        Platform.Wait(atmNear and ATM_NEAR_MS or ATM_SCAN_MS)
    end
end)

Platform.OnEvent('onResourceStop', function(resource)
    if resource == Platform.GetResourceName() then
        for _, blip in ipairs(blips) do
            Platform.RemoveBlip(blip)
        end
    end
end)
