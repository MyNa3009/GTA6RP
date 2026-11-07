-- TextUI: kurzer Hinweis am Bildschirmrand, z. B. "[E] Tür öffnen". Reine Anzeige ohne Fokus.
if LibDisabled then return end

TextUi = {}

local UI = 'textui'
local POSITIONS = { left = true, right = true, top = true, bottom = true }
local KEY_LENGTH = 12

local current = nil   -- { text, key, position }

-- options: { key = 'E', position = 'left' | 'right' | 'top' | 'bottom' }
function TextUi.Show(text, options)
    text = Lib.Text(text, Config.Lib.TextUi.MaxLength)
    if not text then
        return false
    end
    options = type(options) == 'table' and options or {}
    local data = {
        text = text,
        key = Lib.Text(options.key, KEY_LENGTH),
        position = POSITIONS[options.position] and options.position or 'left',
    }
    -- Gleicher Hinweis noch einmal: nichts senden
    if current and current.text == data.text and current.key == data.key and current.position == data.position then
        return true
    end
    current = data
    Ui.Send(UI, 'textui_open', data)
    return true
end

function TextUi.Hide()
    if not current then
        return false
    end
    current = nil
    Ui.Send(UI, 'textui_close', {})
    return true
end

function TextUi.IsOpen()
    return current ~= nil, current and current.text or nil
end

Platform.Export('ShowTextUI', TextUi.Show)
Platform.Export('HideTextUI', TextUi.Hide)
Platform.Export('IsTextUIOpen', TextUi.IsOpen)
