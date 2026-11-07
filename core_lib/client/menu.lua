-- Menue-UI (menu.html) fuer das G-Menue und fuer Kontextmenues anderer Scripts.
-- Es ist immer nur ein Menue offen. Wer es oeffnet, bekommt die Auswahl (select) und das Schliessen (closed).
-- Dazu die Kontextmenues: Scripts melden sie mit RegisterContext an und zeigen sie mit ShowContext.
if LibDisabled then return end

Menu = {}
Context = {}

local UI = 'menu'
local CFG = Config.Lib.Context
local SELECT_EVENT = 'core_lib:select'
local TITLE_LENGTH = 60
local DESCRIPTION_LENGTH = 160
local ICON_LENGTH = 32
local META_LENGTH = 40
local MAX_META = 8
local ID_LENGTH = 64

local current = nil   -- { owner, handlers = { select = fn(data), closed = fn() } }

------------------------------------------------------------------------
-- Menue-UI
------------------------------------------------------------------------

function Menu.Open(owner, payload, handlers)
    if current then
        Menu.Close()
    end
    current = { owner = owner, handlers = handlers or {} }
    Ui.Send(UI, 'menu_open', payload)
    Ui.Focus(UI, true, true)
end

-- Inhalt neu schicken, ohne die Stelle zu verlieren, an der der Spieler gerade ist
function Menu.Update(owner, payload)
    if current and current.owner == owner then
        Ui.Send(UI, 'menu_update', payload)
    end
end

function Menu.Close(owner)
    if not current or (owner and current.owner ~= owner) then
        return false
    end
    local closing = current
    current = nil
    Ui.Focus(UI, false)
    Ui.Send(UI, 'menu_close', {})
    if closing.handlers.closed then
        closing.handlers.closed()
    end
    return true
end

function Menu.IsOpen(owner)
    return current ~= nil and (not owner or current.owner == owner)
end

Platform.UiOn('menu_select', function(data)
    if not current or not current.handlers.select then
        return { ok = false, error = 'not_open' }
    end
    if type(data.id) ~= 'string' then
        return { ok = false, error = 'invalid_input' }
    end
    return current.handlers.select(data) or { ok = true }
end)

Platform.UiOn('menu_close', function()
    Menu.Close()
    return { ok = true }
end)

------------------------------------------------------------------------
-- Hilfen fuer Eintraege anderer Scripts
------------------------------------------------------------------------

-- metadata: { { label, value } } oder { label = value }
function Menu.ReadMetadata(metadata)
    if type(metadata) ~= 'table' then
        return nil
    end
    local list = {}
    if #metadata > 0 then
        for i = 1, math.min(#metadata, MAX_META) do
            local entry = metadata[i]
            if type(entry) == 'table' then
                local label = Lib.Text(entry.label, META_LENGTH)
                if label then
                    list[#list + 1] = { label = label, value = Lib.Text(entry.value, META_LENGTH) or '' }
                end
            end
        end
    else
        for key, value in pairs(metadata) do
            if #list >= MAX_META then
                break
            end
            local label = Lib.Text(key, META_LENGTH)
            if label then
                list[#list + 1] = { label = label, value = Lib.Text(value, META_LENGTH) or '' }
            end
        end
        table.sort(list, function(a, b) return a.label < b.label end)
    end
    return #list > 0 and list or nil
end

-- Fuehrt die Aktion eines Eintrags aus: Funktion, Schluessel aus init.lua oder lokales Ereignis
-- done (optional): wird aufgerufen, wenn die Aktion fertig ist. Bei Ereignissen sofort, weil dort niemand Bescheid gibt.
function Menu.RunAction(action, value, done)
    if type(action.onSelect) == 'function' then
        Platform.Async(function()
            local ok, err = pcall(action.onSelect, value)
            if not ok then
                Platform.Print('error', ('core_lib: Fehler in einer Menue-Aktion von %s: %s'):format(tostring(action.owner), tostring(err)))
            end
            if done then
                done()
            end
        end)
        return
    elseif action.selectKey then
        Platform.Emit(SELECT_EVENT, action.selectKey, value)
    elseif action.event then
        Platform.Emit(action.event, value)
    end
    if done then
        Platform.Async(done)
    end
end

-- Liest die Aktion eines Eintrags (onSelect, selectKey von init.lua oder event)
function Menu.ReadAction(def, owner)
    local action = { owner = owner }
    if type(def.onSelect) == 'function' or type(def.onSelect) == 'table' then
        -- Funktionen aus anderen Resources kommen als aufrufbare Tabelle an
        action.onSelect = def.onSelect
    elseif type(def.selectKey) == 'string' then
        action.selectKey = def.selectKey
    elseif type(def.event) == 'string' then
        action.event = def.event
    end
    return action
end

------------------------------------------------------------------------
-- Kontextmenues
------------------------------------------------------------------------

local contexts = {}   -- [id] = { id, owner, title, options }
local openContext = nil
local actions = {}    -- [nodeId] = { action, args, keepOpen }

local function readContext(def, owner)
    if type(def) ~= 'table' then
        return nil, 'invalid_input'
    end
    local id = Lib.Text(def.id, ID_LENGTH)
    local title = Lib.Text(def.title, TITLE_LENGTH)
    if not id or not title or type(def.options) ~= 'table' then
        return nil, 'invalid_input'
    end
    local options = {}
    for i = 1, math.min(#def.options, CFG.MaxOptions) do
        local option = def.options[i]
        if type(option) == 'table' then
            local label = Lib.Text(option.title or option.label, TITLE_LENGTH)
            if label then
                options[#options + 1] = {
                    label = label,
                    description = Lib.Text(option.description, DESCRIPTION_LENGTH),
                    icon = Lib.Text(option.icon, ICON_LENGTH),
                    disabled = option.disabled == true,
                    readOnly = option.readOnly == true,
                    keepOpen = option.keepOpen == true,
                    progress = tonumber(option.progress) and math.max(0, math.min(100, tonumber(option.progress))) or nil,
                    metadata = Menu.ReadMetadata(option.metadata),
                    menu = Lib.Text(option.menu, ID_LENGTH),
                    args = option.args,
                    action = Menu.ReadAction(option, owner),
                }
            end
        end
    end
    return { id = id, owner = owner, title = title, options = options }
end

-- def oder Liste von defs: { id, title, options = { { title, description, icon, disabled, readOnly, keepOpen,
--   progress, metadata, menu = 'andere_id', onSelect = fn(args) | event = 'name', args } } }
function Context.Register(def)
    local owner = Platform.GetCallingResource() or Platform.GetResourceName()
    local list = (type(def) == 'table' and def.id == nil) and def or { def }
    for _, entry in ipairs(list) do
        local parsed, err = readContext(entry, owner)
        if not parsed then
            return false, err
        end
        contexts[parsed.id] = parsed
    end
    return true
end

-- Baut die Knoten fuer die UI. Untermenues (option.menu) werden eingesetzt, mit Schutz vor Schleifen.
local function buildNodes(context, prefix, depth, visited)
    local nodes = {}
    for index, option in ipairs(context.options) do
        local nodeId = ('%s.%d'):format(prefix, index)
        local node = {
            id = nodeId,
            label = option.label,
            description = option.description,
            icon = option.icon,
            disabled = option.disabled or nil,
            readOnly = option.readOnly or nil,
            progress = option.progress,
            metadata = option.metadata,
        }
        local child = option.menu and contexts[option.menu]
        if child and depth < CFG.MaxDepth and not visited[child.id] then
            visited[child.id] = true
            node.title = child.title
            node.children = buildNodes(child, nodeId, depth + 1, visited)
            visited[child.id] = nil
        elseif not option.disabled and not option.readOnly then
            actions[nodeId] = { action = option.action, args = option.args, keepOpen = option.keepOpen }
        end
        nodes[#nodes + 1] = node
    end
    return nodes
end

function Context.Show(id)
    local context = contexts[id]
    if not context then
        return false, 'not_found'
    end
    actions = {}
    openContext = id
    Menu.Open('context', {
        mode = 'context',
        title = context.title,
        items = buildNodes(context, 'c', 1, { [context.id] = true }),
    }, {
        select = function(data)
            local entry = actions[data.id]
            if not entry then
                return { ok = false, error = 'not_found' }
            end
            if not entry.keepOpen then
                Menu.Close('context')
            end
            Menu.RunAction(entry.action, entry.args)
            return { ok = true, data = { close = not entry.keepOpen } }
        end,
        closed = function()
            openContext = nil
            actions = {}
        end,
    })
    return true
end

function Context.Hide()
    return Menu.Close('context')
end

function Context.GetOpen()
    return openContext
end

Platform.OnResourceStop(function(resource)
    for id, context in pairs(contexts) do
        if context.owner == resource then
            if openContext == id then
                Context.Hide()
            end
            contexts[id] = nil
        end
    end
end)

Platform.Export('RegisterContext', Context.Register)
Platform.Export('ShowContext', Context.Show)
Platform.Export('HideContext', Context.Hide)
Platform.Export('GetOpenContext', Context.GetOpen)
