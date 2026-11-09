"""Testumgebung: echte Server-Dateien der Core gegen eine echte MariaDB, FiveM-Natives als Attrappen."""
import datetime
import decimal
import json
import re
import sys

import os

import lupa
import pymysql

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = os.path.join(ROOT, 'core')
INVENTORY = os.path.join(ROOT, 'core_inventory')
LIB = os.path.join(ROOT, 'core_lib')
FACTIONS = os.path.join(ROOT, 'core_factions')
EMS = os.path.join(ROOT, 'core_ems')

# Die Tests LOESCHEN alle Tabellen der Datenbank. Darum nur gegen eine eigene Test-Datenbank,
# deren Name "test" enthaelt. Nie gegen die Datenbank des Servers.
DB_HOST = os.environ.get('CORE_TEST_DB_HOST', 'localhost')
DB_USER = os.environ.get('CORE_TEST_DB_USER', 'core_test')
DB_PASSWORD = os.environ.get('CORE_TEST_DB_PASSWORD', '')
DB_NAME = os.environ.get('CORE_TEST_DB_NAME', 'core_test')
if 'test' not in DB_NAME.lower():
    sys.exit(f'Abbruch: Die Tests loeschen alle Tabellen. "{DB_NAME}" ist keine Test-Datenbank (Name muss "test" enthalten).')
SERVER_FILES = [
    'shared/config.lua', 'data/spawn_gta5.lua', 'data/models_gta5.lua', 'data/weapons_gta5.lua', 'data/jail_gta5.lua',
    'bridge/platform/fivem_server.lua', 'bridge/database/oxmysql.lua', 'bridge/identity/fivem.lua', 'bridge/network/fivem_server.lua',
    'server/log.lua', 'server/log_archive.lua', 'server/accounts.lua', 'server/main.lua', 'server/permissions.lua', 'server/multiaccount.lua', 'server/devices.lua', 'server/twinks.lua',
    'server/characters.lua', 'server/death.lua', 'server/money.lua', 'server/consent.lua', 'server/needs.lua', 'server/admin.lua', 'server/punishments.lua',
    'server/bans.lua', 'server/jail.lua', 'server/moderation.lua', 'server/vehicles.lua', 'server/admin_tools.lua', 'server/spectate.lua', 'server/tickets.lua', 'server/admin_help.lua', 'server/admin_keys.lua', 'server/auth.lua',
]

INVENTORY_FILES = [
    (CORE, 'shared/config.lua'), (INVENTORY, 'config.lua'), (INVENTORY, 'data/items.lua'), (INVENTORY, 'data/clothing_catalog_gta5.lua'), (INVENTORY, 'data/clothing_gta5.lua'), (INVENTORY, 'data/trunks_gta5.lua'),
    (CORE, 'bridge/platform/fivem_server.lua'), (CORE, 'bridge/database/oxmysql.lua'), (CORE, 'bridge/network/fivem_server.lua'),
    (INVENTORY, 'server/inventory.lua'), (INVENTORY, 'server/consent.lua'), (INVENTORY, 'server/drops.lua'), (INVENTORY, 'server/registry.lua'), (INVENTORY, 'server/api.lua'), (INVENTORY, 'server/documents.lua'), (INVENTORY, 'server/views.lua'),
]


# Weitere Resources fuer Env(extra=[...]), in dieser Reihenfolge geladen
BRIDGE = [(CORE, 'bridge/platform/fivem_server.lua'), (CORE, 'bridge/database/oxmysql.lua'), (CORE, 'bridge/network/fivem_server.lua')]
EXTRA_FILES = {
    'core_lib': [(CORE, 'shared/config.lua'), (LIB, 'config.lua')] + BRIDGE + [(LIB, 'server/main.lua')],
    'core_factions': [(CORE, 'shared/config.lua'), (FACTIONS, 'config.lua'), (FACTIONS, 'data/places_gta5.lua')] + BRIDGE + [
        (LIB, 'init.lua'), (FACTIONS, 'server/schema.lua'), (FACTIONS, 'server/main.lua'), (FACTIONS, 'server/protocol.lua'), (FACTIONS, 'server/consent.lua'),
        (FACTIONS, 'server/members.lua'), (FACTIONS, 'server/menu.lua'), (FACTIONS, 'server/places.lua'), (FACTIONS, 'server/commands.lua')],
    'core_ems': [(CORE, 'shared/config.lua'), (EMS, 'config.lua')] + BRIDGE + [
        (LIB, 'init.lua'), (EMS, 'server/schema.lua'), (EMS, 'server/main.lua'), (EMS, 'server/diseases.lua'),
        (EMS, 'server/actions.lua'), (EMS, 'server/records.lua')],
}


def connect():
    return pymysql.connect(host=DB_HOST, user=DB_USER, password=DB_PASSWORD, database=DB_NAME, autocommit=True,
                           cursorclass=pymysql.cursors.DictCursor, charset='utf8mb4')


def reset_db():
    db = connect()
    with db.cursor() as cur:
        cur.execute('SET FOREIGN_KEY_CHECKS=0')
        for table in ['audit_log', 'account_links', 'account_identifiers', 'characters', 'accounts', 'bans', 'admin_jails', 'account_devices', 'account_ips', 'device_alerts', 'warns', 'tickets', 'ticket_messages', 'audit_log_archive', 'inventories', 'weapon_registry', 'licenses', 'admin_keys',
                      'faction_members', 'faction_settings', 'faction_ranks', 'faction_vehicles', 'faction_departments', 'faction_exams',
                      'faction_history', 'faction_archive', 'faction_divisions', 'faction_info', 'faction_logs', 'ems_diseases', 'ems_records', 'ems_insurance']:
            cur.execute(f'DROP TABLE IF EXISTS {table}')
        cur.execute('SET FOREIGN_KEY_CHECKS=1')
        for statement in open(f'{CORE}/database/schema.sql').read().split(';'):
            if statement.strip():
                cur.execute(statement)
    db.close()


class Env:
    def __init__(self, debug=False, inventory=False, admin_keys=False, extra=None):
        reset_db()
        self.db = connect()
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.events = []      # (source, event, data)
        # Zustimmung beim Geben: wie antwortet wer? 'yes' (Standard), 'no' oder 'ignore' (gar nicht, laeuft ab)
        self.consent = {}
        self._consent_answered = set()
        self._rid = 0          # eigene Nummer je Anfrage, damit keine alte Antwort gelesen wird
        self.dropped = []     # (source, reason)
        self.notes = []       # (source, text)
        self.state = {}       # (source, key) -> value
        self.identifiers = {}
        self.tokens = {}
        self.ips = {}
        self.positions = {}
        self.buckets = {}
        self.names = {}
        self.debug = debug
        self.sql_log = []
        self.runtimes = {'core': self.lua}
        self.with_inventory = inventory
        # Admin-Keys nur in test_admin_keys.py an, die anderen Tests pruefen Rechte ohne Key
        self.admin_keys = admin_keys
        if inventory:
            self.inv = lupa.LuaRuntime(unpack_returned_tuples=True)
            self.runtimes['core_inventory'] = self.inv
        self.extra = list(extra or [])
        for resource in self.extra:
            self.runtimes[resource] = lupa.LuaRuntime(unpack_returned_tuples=True)
        self._setup()
        if inventory:
            self._install(self.inv, 'core_inventory', INVENTORY_FILES)
        for resource in self.extra:
            self._install(self.runtimes[resource], resource, EXTRA_FILES[resource])

    # ---------- Lua <-> Python ----------
    def to_py(self, value):
        if lupa.lua_type(value) == 'table':
            keys = list(value.keys())
            if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
                return [self.to_py(value[k]) for k in sorted(keys)]
            if not keys:
                return {}
            return {str(k): self.to_py(value[k]) for k in keys}
        return value

    def to_lua(self, value, lua=None):
        lua = lua or self.lua
        if isinstance(value, dict):
            t = lua.table()
            for k, v in value.items():
                if v is not None:
                    t[k] = self.to_lua(v, lua)
            return t
        if isinstance(value, list):
            t = lua.table()
            for i, v in enumerate(value, 1):
                if v is not None:
                    t[i] = self.to_lua(v, lua)
            return t
        if isinstance(value, decimal.Decimal):
            return float(value) if value % 1 else int(value)
        if isinstance(value, datetime.datetime):
            return int(value.timestamp() * 1000)
        if isinstance(value, datetime.date):
            return value.isoformat()
        if isinstance(value, bytes):
            return value.decode()
        return value

    def params(self, params):
        if params is None:
            return []
        keys = list(params.keys())
        ints = [k for k in keys if isinstance(k, int)]
        if ints and sorted(ints) != list(range(1, len(ints) + 1)):
            raise RuntimeError(f'Parameterliste mit Luecke: {sorted(ints)}')
        if any(not isinstance(k, int) for k in keys):
            raise RuntimeError(f'Parameterliste mit Text-Schluesseln: {keys}')
        return [params[i] for i in range(1, len(ints) + 1)]

    def run_sql(self, sql, params):
        args = self.params(params)
        if sql.count('?') != len(args):
            raise RuntimeError(f'{sql.count("?")} Platzhalter, aber {len(args)} Werte: {sql}')
        py_sql = sql.replace('%', '%%').replace('?', '%s')
        self.sql_log.append(sql)
        cur = self.db.cursor()
        cur.execute(py_sql, args)
        return cur

    def _setup(self):
        self._install(self.lua, 'core', [(CORE, f) for f in SERVER_FILES])

    # Andere Resource aufrufen: Werte gehen ueber Python von einer Lua-Umgebung in die andere
    def _exports_of(self, caller, resource):
        env = self
        lua_caller = self.runtimes[caller]
        target = self.runtimes.get(resource)

        def call(name):
            def fn(_self, *args):
                if target is None:
                    raise RuntimeError(f'Resource {resource} laeuft nicht')
                g = target.globals()
                func = g.EXPORTS[name]
                if func is None:
                    raise RuntimeError(f'Export {resource}:{name} fehlt')
                py_args = [env.to_py(a) for a in args]
                g.INVOKER = caller
                try:
                    result = func(*[env.to_lua(a, target) for a in py_args])
                finally:
                    g.INVOKER = None
                if isinstance(result, tuple):
                    return tuple(env.to_lua(env.to_py(r), lua_caller) for r in result)
                return env.to_lua(env.to_py(result), lua_caller)
            return fn

        proxy = lua_caller.eval('function(call) return setmetatable({}, { __index = function(_, name) return call(name) end }) end')
        return proxy(call)

    # Lokales Server-Ereignis an die anderen Resources weiterreichen
    def _broadcast(self, sender, name, args):
        values = [self.to_py(args[i]) for i in range(1, int(args['n'] or 0) + 1)]
        for resource, lua in self.runtimes.items():
            if resource == sender:
                continue
            packed = lua.table(*[self.to_lua(v, lua) for v in values])
            lua.globals().RECEIVE(name, packed, len(values))

    def _install(self, lua, resource, files):
        g = lua.globals()
        env = self

        def q(sql, params=None):
            cur = env.run_sql(sql, params)
            rows = cur.fetchall() if cur.description else []
            return env.to_lua([dict(r) for r in rows], lua)

        def single(sql, params=None):
            cur = env.run_sql(sql, params)
            row = cur.fetchone() if cur.description else None
            return env.to_lua(dict(row), lua) if row else None

        def scalar(sql, params=None):
            cur = env.run_sql(sql, params)
            row = cur.fetchone() if cur.description else None
            if not row:
                return None
            return env.to_lua(list(row.values())[0], lua)

        def insert(sql, params=None):
            return env.run_sql(sql, params).lastrowid

        def update(sql, params=None):
            return env.run_sql(sql, params).rowcount

        g.py = lua.table(q=q, single=single, scalar=scalar, insert=insert, update=update,
                         encode=lambda v: json.dumps(env.to_py(v)),
                         decode=lambda s: env.to_lua(json.loads(s), lua),
                         event=lambda src, name, data: env.events.append((src, name, env.to_py(data) if lupa.lua_type(data) == 'table' else data)),
                         drop=lambda src, reason: env.dropped.append((src, reason)),
                         note=lambda src, text: env.notes.append((src, text)),
                         setstate=lambda src, key, val: env.state.__setitem__((src, key), env.to_py(val) if lupa.lua_type(val) == 'table' else val),
                         ident_count=lambda src: len(env.identifiers.get(src, [])),
                         ident=lambda src, i: env.identifiers.get(src, [])[i] if i < len(env.identifiers.get(src, [])) else None,
                         pos=lambda src: (lambda p: lua.table(x=float(p[0]), y=float(p[1]), z=float(p[2])) if p else None)(env.positions.get(src)),
                         tokcount=lambda src: len(env.tokens.get(src, [])),
                         tok=lambda src, i: env.tokens.get(src, [])[i],
                         ip=lambda src: env.ips.get(src),
                         name=lambda src: env.names.get(src, f'spieler{src}'),
                         debug='true' if self.debug else 'false',
                         exports_of=lambda target: env._exports_of(resource, target),
                         broadcast=lambda name, args: env._broadcast(resource, name, args),
                         started=lambda name: name in env.runtimes,
                         setbucket=lambda src, b: env.buckets.__setitem__(src, b),
                         getbucket=lambda src: env.buckets.get(src, 0))
        g.RESOURCE_NAME = resource

        lua.execute(r'''
        CLOCK = 1800000000
        local realTime = os.time
        os.time = function(t) if t then return realTime(t) end return CLOCK end

        local threads = {}
        NOW_MS = 0
        function CreateThread(fn)
            local co = coroutine.create(fn)
            local ok, wait = coroutine.resume(co)
            if not ok then error(wait) end
            if coroutine.status(co) ~= 'dead' then threads[#threads + 1] = { co = co, at = NOW_MS + (wait or 0) } end
        end
        Citizen = { CreateThread = CreateThread }
        function Wait(ms)
            if coroutine.isyieldable() then coroutine.yield(ms or 0) end
        end
        function TICK(ms)
            local target = NOW_MS + ms
            while true do
                local nextAt, index = nil, nil
                for i, t in ipairs(threads) do
                    if t.at <= target and (not nextAt or t.at < nextAt) then nextAt, index = t.at, i end
                end
                if not index then break end
                local t = table.remove(threads, index)
                NOW_MS = t.at
                CLOCK = 1800000000 + NOW_MS // 1000
                local ok, wait = coroutine.resume(t.co)
                if not ok then error(wait) end
                if coroutine.status(t.co) ~= 'dead' then threads[#threads + 1] = { co = t.co, at = NOW_MS + math.max(1, wait or 0) } end
            end
            NOW_MS = target
            CLOCK = 1800000000 + NOW_MS // 1000
        end

        MySQL = {
            query = { await = function(s, p) return py.q(s, p) end },
            single = { await = function(s, p) return py.single(s, p) end },
            scalar = { await = function(s, p) return py.scalar(s, p) end },
            insert = { await = function(s, p) return py.insert(s, p) end },
            update = { await = function(s, p) return py.update(s, p) end },
            ready = function(fn) READY = READY or {}; READY[#READY + 1] = fn end,
        }
        MySQL.query.hcall = nil
        setmetatable(MySQL.query, { __call = function(_, s, p) return py.q(s, p) end })

        json = { encode = function(v) return py.encode(v) end, decode = function(s) return py.decode(s) end }
        function GetCurrentResourceName() return RESOURCE_NAME end
        function GetConvar(name, default) if name == 'core_debug' then return py.debug end return default end
        function GetConvarInt(_, d) return d end
        function GetInvokingResource() return INVOKER end
        function DropPlayer(src, reason) py.drop(src, reason); if HANDLERS.playerDropped then source = tonumber(src); for _, h in ipairs(HANDLERS.playerDropped) do h('dropped') end end end
        HANDLERS = {}
        function AddEventHandler(name, fn) HANDLERS[name] = HANDLERS[name] or {}; table.insert(HANDLERS[name], fn) end
        NET = {}
        function RegisterNetEvent(name, fn) NET[name] = fn end
        PLAYERS = {}
        function GetPlayers() local l = {} for id in pairs(PLAYERS) do l[#l + 1] = tostring(id) end return l end
        function GetPlayerName(src) return py.name(src) end
        function GetPasswordHash(p) return 'hash:' .. p end
        function VerifyPasswordHash(p, h) return h == 'hash:' .. p end
        function GetPlayerPed(src) return PLAYERS[src] and src or 0 end
        function GetEntityCoords(ped) local p = py.pos(ped); if not p then return { x = 0.0, y = 0.0, z = 0.0 } end return { x = p.x, y = p.y, z = p.z } end
        function GetEntityHeading() return 90.0 end
        function TriggerClientEvent(name, src, a, b) if name:sub(-12) == ':cb:response' then RESPONSES[a] = b else py.event(src, name, a) end end
        function RegisterCommand(name, fn) COMMANDS[name] = fn end
        COMMANDS = {}
        RESPONSES = {}
        EXPORTS = {}
        exports = setmetatable({}, {
            __call = function(_, name, fn) EXPORTS[name] = fn end,
            __index = function(_, res) return py.exports_of(res) end,
        })
        function GetResourceState(name) if py.started(name) then return 'started' end return 'missing' end
        function GetResourceMetadata(name, key, i) return '1.6.0' end
        function TriggerEvent(name, ...)
            local args = table.pack(...)
            for _, h in ipairs(HANDLERS[name] or {}) do h(table.unpack(args, 1, args.n)) end
            py.broadcast(name, args)
        end
        function RECEIVE(name, args, n)
            for _, h in ipairs(HANDLERS[name] or {}) do h(table.unpack(args, 1, n)) end
        end
        function GetNumPlayerIdentifiers(src) return py.ident_count(src) end
        function GetPlayerIdentifier(src, i) return py.ident(src, i) end
        DELETED = {}
        function NetworkGetEntityFromNetworkId(id) return id end
        function DoesEntityExist(e) return e == 500 end
        function GetEntityType(e) return 2 end
        function DeleteEntity(e) DELETED[#DELETED + 1] = e end
        function GetGameTimer() return NOW_MS end
        function GetNumPlayerTokens(src) return py.tokcount(src) end
        function GetPlayerToken(src, i) return py.tok(src, i) end
        function GetPlayerEndpoint(src) return py.ip(src) end
        function Player(src) return { state = { set = function(_, k, v) py.setstate(src, k, v) end } } end
        BUCKETS = {}
        VEHICLES = {}
        function SetPlayerRoutingBucket(src, b) BUCKETS[tonumber(src)] = b; py.setbucket(tonumber(src), b) end
        function GetPlayerRoutingBucket(src) return py.getbucket(tonumber(src)) end
        function SetEntityRoutingBucket(e, b) if VEHICLES[e] then VEHICLES[e].bucket = b end end
        function GetVehiclePedIsIn() return 0 end
        function GetPedInVehicleSeat() return 0 end
        function GetAllVehicles() local l = {} for id in pairs(VEHICLES) do l[#l + 1] = id end return l end
        function GetEntityRoutingBucket(e) return VEHICLES[e] and VEHICLES[e].bucket or 0 end
        function NetworkGetNetworkIdFromEntity(e) return e end
        function NetworkGetEntityOwner(e) return VEHICLES[e] and VEHICLES[e].owner or -1 end
        local baseCoords = GetEntityCoords
        function GetEntityCoords(e) local v = VEHICLES[e]; if v then return { x = v.x, y = v.y, z = v.z } end return baseCoords(e) end
        function DoesEntityExist(e) return e == 500 or VEHICLES[e] ~= nil end
        function GetVehicleNumberPlateText(e) return VEHICLES[e] and VEHICLES[e].plate or 'ADMIN' end
        function GetVehicleDoorLockStatus(e) return VEHICLES[e] and VEHICLES[e].lock or 1 end
        ''')
        for base, f in files:
            lua.execute(open(f'{base}/{f}', encoding='utf-8').read())
            if f == 'shared/config.lua' and not self.admin_keys:
                lua.execute('Config.AdminKeys.Enabled = false')
        lua.execute('for _, fn in ipairs(READY or {}) do CreateThread(fn) end')
        self.tick(0)

    # ---------- Helfer ----------
    def tick(self, ms):
        active = [lua for lua in self.runtimes.values() if lua.globals().TICK is not None]
        if len(active) == 1 or ms <= 0:
            for lua in active:
                lua.globals().TICK(ms)
            return
        # Mehrere Resources: in kleinen Schritten, damit sie abwechselnd laufen
        step = 50
        done = 0
        while done < ms:
            part = min(step, ms - done)
            for lua in active:
                lua.globals().TICK(part)
            done += part

    def connect(self, src, identifiers, position=(0.0, 0.0, 70.0), tokens=None, ip=None):
        """playerConnecting + playerJoining. Gibt die Ablehnung zurueck oder None."""
        self.identifiers[src] = identifiers
        self.tokens[src] = tokens or []
        self.ips[src] = ip
        self.positions[src] = list(position)
        result = {}
        lua = self.lua
        deferrals = lua.table(defer=lambda: None, update=lambda *_: None,
                              done=lambda msg=None: result.__setitem__('msg', msg))
        lua.execute('function hconnect(src, d) source = src; for _, h in ipairs(HANDLERS.playerConnecting or {}) do h("n", nil, d) end end')
        lua.globals().hconnect(src, deferrals)
        self.tick(10)
        if result.get('msg'):
            return result['msg']
        for rt in self.runtimes.values():
            rt.execute(f'PLAYERS[{src}] = true')
        lua.execute('function hjoin(src) source = src; for _, h in ipairs(HANDLERS.playerJoining or {}) do h() end end')
        lua.globals().hjoin(src)
        self.tick(10)
        return None

    # Offene Fragen nach Zustimmung beantworten, wie in self.consent eingestellt
    def _answer_consents(self):
        answered = False
        for target, name, data in list(self.events):
            if name != 'core:consent' or data['id'] in self._consent_answered:
                continue
            mode = self.consent.get(target, 'yes')
            if mode == 'ignore':
                continue
            self._consent_answered.add(data['id'])
            self.call(target, 'consent_answer', {'id': data['id'], 'accept': mode == 'yes'})
            answered = True
        return answered

    # Warten, bis die Antwort da ist (Callbacks koennen auf eine Zustimmung warten)
    CONSENT_BUDGET_MS = 10000
    CONSENT_STEP_MS = 100

    def _settle(self, lua, rid):
        waited = 0
        while lua.globals().RESPONSES[rid] is None and waited < self.CONSENT_BUDGET_MS:
            if not self._answer_consents():
                self.tick(self.CONSENT_STEP_MS)
                waited += self.CONSENT_STEP_MS
            else:
                self.tick(10)

    def call(self, src, name, data=None):
        lua = self.lua
        self._rid += 1
        rid = 100000 + self._rid
        lua.execute('function hcall(src, n, id, d) source = src; NET["core:cb:request"](n, id, d) end')
        lua.globals().hcall(src, name, rid, self.to_lua(data or {}))
        self.tick(10)
        if name != 'consent_answer':
            self._settle(lua, rid)
        return self.to_py(lua.globals().RESPONSES[rid])

    def command(self, src, line):
        parts = line.split()
        for lua in self.runtimes.values():
            fn = lua.globals().COMMANDS[parts[0]]
            if fn is not None:
                fn(src, self.to_lua(parts[1:], lua))
                self.tick(10)
                return
        raise RuntimeError(f'Befehl fehlt: {parts[0]}')

    def icall(self, src, name, data=None):
        lua = self.inv
        self._rid += 1
        rid = 200000 + self._rid
        lua.execute('function hcall(src, n, id, d) source = src; NET["core_inventory:cb:request"](n, id, d) end')
        lua.globals().hcall(src, name, rid, self.to_lua(data or {}, lua))
        self.tick(10)
        self._settle(lua, rid)
        return self.to_py(lua.globals().RESPONSES[rid])

    # Anfrage an eine weitere Resource (core_factions, core_ems, core_lib)
    def rcall(self, resource, src, name, data=None):
        lua = self.runtimes[resource]
        self._rid += 1
        rid = 300000 + self._rid
        lua.execute(f'function hcall(src, n, id, d) source = src; NET["{resource}:cb:request"](n, id, d) end')
        lua.globals().hcall(src, name, rid, self.to_lua(data or {}, lua))
        self.tick(10)
        self._settle(lua, rid)
        return self.to_py(lua.globals().RESPONSES[rid])

    def events_for(self, src, name):
        return [d for s, n, d in self.events if s == src and n == name]

    def last_note(self, src):
        texts = [t for s, t in self.notes if s == src]
        return texts[-1] if texts else None

    def sql(self, statement, args=()):
        cur = self.db.cursor()
        cur.execute(statement, args)
        return cur.fetchall()

    def flush_log(self):
        self.tick(6000)
