"""Test fuer core_ems gegen MariaDB: Hochholen mit Minigame, Verbandskasten, Krankheiten mit Stadien,
Zusammenbruch im Endstadium (nur Krankenhaus), Behandlungsserie, Tabletten, Ansteckung, Verkauf zu festen Preisen
in die Kasse, Krankenversicherung mit Rabatt, Medizinische Datenbank und Rechte."""
import os
import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Env

ok = fail = 0


def check(label, condition, info=None):
    global ok, fail
    if condition:
        ok += 1
        print('  ok   ', label)
    else:
        fail += 1
        print('  FEHLER', label, info if info is not None else '')


env = Env(inventory=True, debug=True, extra=['core_lib', 'core_factions', 'core_ems'])
for name in ('core_lib', 'core_factions', 'core_ems'):
    env.runtimes[name].execute('Config.Network.MaxRequestsPerSecond = 0')
env.inv.execute('Config.Network.MaxRequestsPerSecond = 0')
ems = env.runtimes['core_ems']
E = lambda src, name, data=None: env.rcall('core_ems', src, name, data)
F = lambda src, name, data=None: env.rcall('core_factions', src, name, data)

HOSPITAL = [300.0, -590.0, 43.3]
LOCKER = [298.6, -598.3, 43.3]
people = {1: ('Lena', 'Hoffmann'), 2: ('Paul', 'Krüger'), 3: ('Mira', 'Schulz'), 4: ('Tom', 'Becker')}
ids = {}
for src, (first, last) in people.items():
    env.connect(src, [f'license:{src}'])
    env.call(src, 'auth_register', {'email': f'{src}@t.de', 'password': 'passwort123'})
    ids[src] = env.call(src, 'char_create', {'firstname': first, 'lastname': last, 'dateOfBirth': '1990-01-01', 'gender': 'male'})['data']['characterId']
env.sql('UPDATE characters SET cash = 5000 WHERE id = %s', (ids[2],))
for src in people:
    env.call(src, 'char_select', {'id': ids[src]})
env.tick(1500)
for src in people:
    env.positions[src] = list(HOSPITAL)
env.positions[4] = [1500.0, 1500.0, 50.0]   # Tom ist weit weg


def cash(cid):
    src = [s for s, c in ids.items() if c == cid][0]
    return env.to_py(env.lua.eval(f"Core.GetMoney({src}, 'cash')"))


def diseases(cid):
    return {r['disease']: r['stage'] for r in env.sql('SELECT disease, stage FROM ems_diseases WHERE character_id = %s AND cured_at IS NULL', (cid,))}


def balance():
    return env.to_py(env.runtimes['core_factions'].eval("Factions.GetBalance('ems')")) or 0


def notes(src):
    return [d.get('text', '') for d in env.events_for(src, 'core:notify')]


def answer_minigame(src, success=True, wait=300):
    games = env.events_for(src, 'core_lib:minigame')
    env.tick(wait)
    r = env.rcall('core_lib', src, 'lib_minigame_result', {'id': games[-1]['id'], 'success': success})
    env.tick(400)
    return games[-1], r


def is_dead(src):
    packed = env.to_py(env.lua.eval(f'table.pack(Core.IsDead({src}))'))
    return [packed.get('1', packed.get(1)), packed.get('2', packed.get(2))]


def disease_tick(src, seconds):
    ems.execute(f'Diseases.Tick({src}, {ids[src]}, {seconds})')
    env.tick(50)


print('Ohne Dienst nichts')
env.command(0, f'setorga {ids[1]} ems 30')
env.command(0, f'setorga {ids[3]} ems 1')
check('kein Mitglied: not_medic', E(2, 'ems_sell_list')['error'] == 'not_medic')
check('Mitglied ohne Dienst: not_on_duty', E(1, 'ems_sell_list')['error'] == 'not_on_duty')
env.positions[1] = list(LOCKER)
check('Lena tritt an der Umkleide den Dienst an', F(1, 'faction_duty')['data']['onDuty'] is True)
env.positions[1] = list(HOSPITAL)

print('Hochholen (Skillcheck mit Z)')
check('wache Person: not_dead', E(1, 'ems_revive', {'serverId': 2})['error'] == 'not_dead')
env.call(2, 'death_report', {})
check('Paul ist bewusstlos', is_dead(2)[0] is True)
r = E(1, 'ems_revive', {'serverId': 2})
game, _ = answer_minigame(1, success=False)
check('Minigame startet bei Lena: Skillcheck mit Taste Z', r['ok'] and game['kind'] == 'skillcheck' and game['options']['keys'] == ['Z'], game)
check('verloren: Paul bleibt bewusstlos', is_dead(2)[0] is True and any('nicht geklappt' in t for t in notes(1)))
E(1, 'ems_revive', {'serverId': 2})
answer_minigame(1, success=True)
check('geschafft: Paul ist wach', is_dead(2)[0] is False and env.events_for(2, 'core:death:revive'))
rec = env.sql("SELECT * FROM ems_records WHERE character_id = %s AND kind = 'revive'", (ids[2],))
check('in der Krankenakte: hochgeholt von Lena', rec and rec[0]['actor_name'] == 'Lena Hoffmann', rec)
env.positions[2] = [400.0, -590.0, 43.3]
check('zu weit weg: too_far', E(1, 'ems_revive', {'serverId': 2})['error'] == 'too_far')
env.positions[2] = list(HOSPITAL)

print('Verbandskasten')
check('ohne Kasten: no_medkit', E(1, 'ems_medkit', {'serverId': 2})['error'] == 'no_medkit')
env.inv.execute(f"Inventory = Inventory or {{}}")
added = env.to_py(env.inv.eval(f"Platform.CallExport('core_inventory', 'AddItem', {ids[1]}, 'medkit', 2)"))
r = E(1, 'ems_medkit', {'serverId': 2})
game, _ = answer_minigame(1, success=True)
check('Minigame, dann Heilung bei Paul', r['ok'] and env.events_for(2, 'core:heal')[-1]['amount'] == 100, env.events_for(2, 'core:heal'))
count = env.to_py(env.inv.eval(f"Platform.CallExport('core_inventory', 'GetItemCount', {ids[1]}, 'medkit')"))
check('ein Kasten verbraucht', count == 1, count)

print('Verkaufen zu festen Preisen, Geld in die Kasse')
lst = E(1, 'ems_sell_list')['data']
check('Liste mit festen Preisen', {i['item']: i['price'] for i in lst['items']}['bandage'] == 60, lst)
before_cash, before_bal = cash(ids[2]), balance()
r = E(1, 'ems_sell', {'serverId': 2, 'item': 'bandage', 'count': 3})
check('3 Verbände für 180 $', r['ok'] and r['data']['total'] == 180, r)
check('Paul zahlt 180 $, die Kasse bekommt 180 $', cash(ids[2]) == before_cash - 180 and balance() == before_bal + 180, (cash(ids[2]), balance()))
check('Verbände bei Paul', env.to_py(env.inv.eval(f"Platform.CallExport('core_inventory', 'GetItemCount', {ids[2]}, 'bandage')")) == 3)
check('Preis vom Client wird ignoriert', E(1, 'ems_sell', {'serverId': 2, 'item': 'bandage', 'count': 1, 'price': 1})['data']['total'] == 60)
check('zu viele: invalid_input', E(1, 'ems_sell', {'serverId': 2, 'item': 'bandage', 'count': 99})['error'] == 'invalid_input')
check('unbekanntes Item: invalid_input', E(1, 'ems_sell', {'serverId': 2, 'item': 'weapon_pistol', 'count': 1})['error'] == 'invalid_input')
env.consent[2] = 'no'
before_cash = cash(ids[2])
check('Paul lehnt ab: nichts bezahlt', E(1, 'ems_sell', {'serverId': 2, 'item': 'bandage', 'count': 1})['error'] == 'consent_declined' and cash(ids[2]) == before_cash)
env.consent[2] = 'yes'

print('Krankenversicherung (halber Preis, 30 Tage)')
before_bal = balance()
r = E(1, 'ems_insurance', {'serverId': 2})
until = env.sql('SELECT DATEDIFF(valid_until, NOW()) AS d FROM ems_insurance WHERE character_id = %s', (ids[2],))
check('Versicherung verkauft, gilt 30 Tage, Geld in die Kasse', r['ok'] and until[0]['d'] == 30 and balance() == before_bal + 2000, (r, until))
r = E(1, 'ems_sell', {'serverId': 2, 'item': 'bandage', 'count': 2})
check('mit Versicherung: 2 Verbände für 60 $ statt 120 $', r['data']['total'] == 60, r)

print('Krankheit mit Behandlung: Serie, Endstadium, Krankenhaus')
env.command(0, f'krankheit {ids[2]} hypertension 2')
check('Bluthochdruck Stadium 2 gespeichert', diseases(ids[2]) == {'hypertension': 2}, diseases(ids[2]))
check('Client bekommt die Liste für Symptome', env.events_for(2, 'core_ems:diseases')[-1] == [{'disease': 'hypertension', 'stage': 2}])
disease_tick(2, 3600)
check('nach einer Stunde ohne Behandlung: Stadium 3', diseases(ids[2]) == {'hypertension': 3}, diseases(ids[2]))
disease_tick(2, 3600)
check('Endstadium: Zusammenbruch', diseases(ids[2])['hypertension'] == 4 and env.events_for(2, 'core:death:collapse'))
env.call(2, 'death_report', {})
check('bewusstlos und nur Krankenhaus', is_dead(2) == [True, True], is_dead(2))
check('Rettungsdienst kann nicht hochholen: hospital_only', E(1, 'ems_revive', {'serverId': 2})['error'] == 'hospital_only')
env.lua.execute(f'Core.GetCharacter(2).diedAt = os.time() - 100000')
r = env.call(2, 'death_respawn', {})
env.tick(200)
check('Krankenhaus: wach, Bluthochdruck zurück auf Stadium 2', r['ok'] and is_dead(2)[0] is False and diseases(ids[2]) == {'hypertension': 2}, (r, diseases(ids[2])))

r = E(1, 'ems_treat', {'serverId': 2, 'disease': 'hypertension'})
check('Behandeln ohne Untersuchung: not_diagnosed', r['error'] == 'not_diagnosed')
d = E(1, 'ems_diagnose', {'serverId': 2})['data']
h = d['diseases'][0]
check('Befund: Bluthochdruck 2 von 3, Behandlung 0 von 3, versichert 200 $ statt 400 $', h['stage'] == 2 and h['stages'] == 3 and h['series'] == 0 and h['needed'] == 3 and h['price'] == 200 and d['insured'], d)
check('zu schnell (Balken nicht gelaufen): too_fast', E(1, 'ems_treat', {'serverId': 2, 'disease': 'hypertension'})['error'] == 'too_fast')
before_bal = balance()
env.tick(8100)
r = E(1, 'ems_treat', {'serverId': 2, 'disease': 'hypertension'})
check('Behandlung 1 von 3, 200 $ in die Kasse', r['ok'] and r['data']['series'] == 1 and balance() == before_bal + 200, r)
E(1, 'ems_diagnose', {'serverId': 2})
env.tick(8100)
r = E(1, 'ems_treat', {'serverId': 2, 'disease': 'hypertension'})
check('zweite Behandlung direkt danach: too_soon', r['error'] == 'too_soon', r)
disease_tick(2, 600)
for n in (2, 3):
    E(1, 'ems_diagnose', {'serverId': 2})
    env.tick(8100)
    r = E(1, 'ems_treat', {'serverId': 2, 'disease': 'hypertension'})
    if n == 2:
        disease_tick(2, 600)
check('dritte Behandlung in der Stunde: geheilt', r['ok'] and r['data']['cured'] is True and diseases(ids[2]) == {}, (r, diseases(ids[2])))

print('Serie verfällt nach einer Stunde')
env.command(0, f'krankheit {ids[3]} dementia 1')
env.positions[1] = list(HOSPITAL)
E(1, 'ems_diagnose', {'serverId': 3})
env.tick(8100)
E(1, 'ems_treat', {'serverId': 3, 'disease': 'dementia'})
disease_tick(3, 3700)
row = env.sql("SELECT series FROM ems_diseases WHERE character_id = %s AND cured_at IS NULL", (ids[3],))
check('nach über einer Stunde ohne zweite Behandlung: wieder bei 0', row and row[0]['series'] == 0, row)
env.command(0, f'heilen {ids[3]}')
check('/heilen: Mira gesund', diseases(ids[3]) == {})

print('Tabletten')
env.command(0, f'krankheit {ids[2]} cold 2')
env.to_py(env.inv.eval(f"Platform.CallExport('core_inventory', 'AddItem', {ids[2]}, 'pill_cold', 3)"))
inv = env.icall(2, 'inv_open', {})
slots = [e['slot'] for e in inv['data']['state']['items'] if e['name'] == 'pill_cold']
r = env.icall(2, 'inv_use', {'inv': 'self', 'slot': slots[0]})
env.tick(100)
check('Erkältungstablette: Stadium 2 auf 1', r['ok'] and diseases(ids[2]) == {'cold': 1}, (r, diseases(ids[2])))
env.icall(2, 'inv_use', {'inv': 'self', 'slot': slots[0]})
env.tick(100)
check('zweite direkt danach bringt nichts', diseases(ids[2]) == {'cold': 1} and any('wirkt noch' in t for t in notes(2)))
disease_tick(2, 300)
env.icall(2, 'inv_use', {'inv': 'self', 'slot': slots[0]})
env.tick(100)
check('nach 5 Minuten: geheilt', diseases(ids[2]) == {})

print('Ansteckung')
env.command(0, f'krankheit {ids[2]} cold 3')
ems.execute('math.randomseed(1)')
ems.execute('Diseases.Spread(Ems.Active(), 6000000)')
env.tick(100)
check('Mira steht daneben: angesteckt', diseases(ids[3]).get('cold') == 1, diseases(ids[3]))
check('Tom ist weit weg: gesund', diseases(ids[4]) == {})
rec = env.sql("SELECT text FROM ems_records WHERE character_id = %s AND kind = 'onset'", (ids[3],))
check('Akte sagt "angesteckt"', rec and 'angesteckt' in rec[-1]['text'], rec)
check('Lena: höchstens die Erkältung, nicht doppelt', list(diseases(ids[1]).values()).count(1) <= 1)

print('Medizinische Datenbank')
check('Mira (Rang 1, ohne Dienst): not_on_duty', E(3, 'ems_records_open')['error'] == 'not_on_duty')
check('Tom (kein Mitglied, kein Admin): not_medic', E(4, 'ems_records_open')['error'] == 'not_medic')
s = E(1, 'ems_records_search', {'text': 'Paul Krü'})
hit = s['data']['results'][0] if s.get('data') and s['data'].get('results') else None
check('Suche nach Name findet Paul mit Versicherung', hit and hit['characterId'] == ids[2] and hit.get('insuredUntil'), s)
g = E(1, 'ems_records_get', {'characterId': ids[2]})
kinds = [e['kind'] for e in g['data']['history']]
check('Akte: Verlauf mit Hochholen, Behandlung, Versicherung', all(k in kinds for k in ('revive', 'treatment', 'insurance')), kinds)
check('Akte: aktuelle Krankheit Erkältung', [x['label'] for x in g['data']['diseases']] == ['Erkältung'], g['data']['diseases'])
r = E(1, 'ems_records_note', {'characterId': ids[2], 'text': 'Allergie gegen Penicillin.'})
check('Eintrag schreiben', r['ok'] and env.sql("SELECT COUNT(*) AS n FROM ems_records WHERE character_id = %s AND kind = 'note'", (ids[2],))[0]['n'] == 1, r)
env.flush_log()
logs = env.sql("SELECT action FROM audit_log WHERE category = 'ems'")
check('Blick in die Akte und Verkäufe geloggt', {'records_view', 'sell', 'treat', 'revive'} <= {l['action'] for l in logs}, {l['action'] for l in logs})

print(f'\n{ok} ok, {fail} Fehler')
sys.exit(1 if fail else 0)
