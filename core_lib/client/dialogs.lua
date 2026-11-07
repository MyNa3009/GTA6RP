-- Dialoge: Eingabe (mehrere Felder) und Bestaetigung (Ja oder Nein).
-- Die Werte kommen vom Spieler. Wer damit etwas Wichtiges macht, prueft sie auf dem Server noch einmal.
if LibDisabled then return end

Dialogs = {}

local CFG = Config.Lib.Dialog
local UI = 'dialog'
local LABEL_LENGTH = 60
local DESCRIPTION_LENGTH = 200
local TITLE_LENGTH = 80
local BUTTON_LENGTH = 32
local TYPES = { input = true, number = true, textarea = true, select = true, checkbox = true, slider = true }
local NUMBER_LIMIT = 1e12

local active = nil   -- { id, kind, fields }

local function readNumber(value)
    value = tonumber(value)
    if not value or value ~= value or math.abs(value) > NUMBER_LIMIT then
        return nil
    end
    return value
end

local function readField(field)
    if type(field) ~= 'table' or not TYPES[field.type] then
        return nil
    end
    local label = Lib.Text(field.label, LABEL_LENGTH)
    if not label then
        return nil
    end
    local result = {
        type = field.type,
        label = label,
        description = Lib.Text(field.description, DESCRIPTION_LENGTH),
        placeholder = Lib.Text(field.placeholder, LABEL_LENGTH),
        required = field.required == true,
        disabled = field.disabled == true,
    }
    if field.type == 'input' or field.type == 'textarea' then
        result.maxLength = math.floor(math.min(readNumber(field.maxLength) or CFG.MaxTextLength, CFG.MaxTextLength))
        result.minLength = math.floor(math.max(0, readNumber(field.minLength) or 0))
        result.password = field.type == 'input' and field.password == true or nil
        result.default = Lib.Text(field.default, result.maxLength)
    elseif field.type == 'number' or field.type == 'slider' then
        result.min = readNumber(field.min)
        result.max = readNumber(field.max)
        result.step = readNumber(field.step)
        if field.type == 'slider' then
            result.min = result.min or 0
            result.max = result.max or 100
            result.step = result.step or 1
        end
        result.default = readNumber(field.default)
    elseif field.type == 'select' then
        if type(field.options) ~= 'table' then
            return nil
        end
        result.options = {}
        for i = 1, math.min(#field.options, CFG.MaxOptions) do
            local option = field.options[i]
            local value = type(option) == 'table' and option.value or option
            if type(value) == 'string' or type(value) == 'number' then
                result.options[#result.options + 1] = {
                    value = value,
                    label = Lib.Text(type(option) == 'table' and option.label or value, LABEL_LENGTH) or tostring(value),
                }
            end
        end
        if #result.options == 0 then
            return nil
        end
        result.default = field.default
    elseif field.type == 'checkbox' then
        result.default = field.default == true or field.checked == true
    end
    return result
end

-- Antwort der UI gegen die Felder pruefen. Ungueltige Werte werden nil.
local function readValues(fields, values)
    local result = {}
    for i, field in ipairs(fields) do
        local value = values[i]
        if field.type == 'input' or field.type == 'textarea' then
            value = Lib.Text(value, field.maxLength)
        elseif field.type == 'number' or field.type == 'slider' then
            value = readNumber(value)
            if value then
                if field.min then value = math.max(field.min, value) end
                if field.max then value = math.min(field.max, value) end
            end
        elseif field.type == 'select' then
            local found = nil
            for _, option in ipairs(field.options) do
                if option.value == value then
                    found = option.value
                end
            end
            value = found
        elseif field.type == 'checkbox' then
            value = value == true
        end
        result[i] = value
    end
    return result
end

local function open(kind, payload, fields)
    local id = Lib.NewRequest()
    active = { id = id, kind = kind, fields = fields }
    payload.id = id
    payload.kind = kind
    Ui.Send(UI, 'dialog_open', payload)
    Ui.Focus(UI, true, true)
    return id
end

-- title: Ueberschrift, fields: Liste der Felder, options: { confirmLabel, cancelLabel }
-- Ergebnis: Liste der Werte in derselben Reihenfolge wie fields, oder nil bei Abbruch.
function Dialogs.Input(title, fields, options)
    if active then
        return nil, 'busy'
    end
    title = Lib.Text(title, TITLE_LENGTH)
    if not title or type(fields) ~= 'table' or #fields == 0 or #fields > CFG.MaxFields then
        return nil, 'invalid_input'
    end
    local list = {}
    for i, field in ipairs(fields) do
        local parsed = readField(field)
        if not parsed then
            Platform.Print('warn', ('core_lib: Feld %d im Dialog "%s" ist ungueltig.'):format(i, title))
            return nil, 'invalid_input'
        end
        list[i] = parsed
    end
    options = type(options) == 'table' and options or {}
    return open('input', {
        title = title,
        fields = list,
        confirmLabel = Lib.Text(options.confirmLabel, BUTTON_LENGTH),
        cancelLabel = Lib.Text(options.cancelLabel, BUTTON_LENGTH),
    }, list)
end

-- options: { header, content, confirmLabel, cancelLabel, cancel = true, danger = false }
-- Ergebnis: 'confirm' oder 'cancel'
function Dialogs.Alert(options)
    if active then
        return nil, 'busy'
    end
    if type(options) ~= 'table' then
        return nil, 'invalid_input'
    end
    local header = Lib.Text(options.header, TITLE_LENGTH)
    if not header then
        return nil, 'invalid_input'
    end
    return open('alert', {
        title = header,
        content = Lib.Text(options.content, CFG.MaxTextLength),
        confirmLabel = Lib.Text(options.confirmLabel, BUTTON_LENGTH),
        cancelLabel = Lib.Text(options.cancelLabel, BUTTON_LENGTH),
        cancel = options.cancel ~= false,
        danger = options.danger == true,
    }, nil)
end

local function finish(value)
    local entry = active
    if not entry then
        return
    end
    active = nil
    Ui.Focus(UI, false)
    Ui.Send(UI, 'dialog_close', {})
    Lib.Finish(entry.id, value)
end

function Dialogs.Close()
    if not active then
        return false
    end
    finish(active.kind == 'alert' and 'cancel' or nil)
    return true
end

Platform.UiOn('dialog_submit', function(data)
    if not active or tonumber(data.id) ~= active.id then
        return { ok = false, error = 'not_active' }
    end
    if active.kind == 'alert' then
        finish(data.confirmed == true and 'confirm' or 'cancel')
        return { ok = true }
    end
    if data.cancelled == true or type(data.values) ~= 'table' then
        finish(nil)
        return { ok = true }
    end
    local values = readValues(active.fields, data.values)
    for i, field in ipairs(active.fields) do
        if field.required and values[i] == nil then
            return { ok = false, error = 'required', data = { field = i } }
        end
    end
    finish(values)
    return { ok = true }
end)

Platform.Export('StartInput', Dialogs.Input)
Platform.Export('StartAlert', Dialogs.Alert)
Platform.Export('CloseDialog', Dialogs.Close)
