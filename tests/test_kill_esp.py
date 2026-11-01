import os
import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Env
ok = fail = 0
def check(l, c, i=None):
    global ok, fail
    if c: ok += 1; print('  ok   ', l)
    else: fail += 1; print('  FEHLER', l, i)
def notes(env, src): return [(d['text'], d['type']) for s, n, d in env.events if s == src and n == 'core:notify']
def last(env, src): n = notes(env, src); return n[-1] if n else (None, None)
def ev(env, src, name): return env.events_for(src, name)

env = Env()
for s in (1, 2, 3, 4):
    env.connect(s, [f'license:{s}'])
    env.call(s, 'auth_register', {'email': f'{s}@t.de', 'password': 'passwort123'})
ids = {}
for s, (fn, ln) in zip((1, 2, 3, 4), [('Fabian', 'Nandes'), ('Lena', 'Wojcik'), ('Mira', 'Brandt'), ('Jonas', 'Lehmkuhl')]):
    ids[s] = env.call(s, 'char_create', {'firstname': fn, 'lastname': ln, 'dateOfBirth': '1995-01-01', 'gender': 'male'})['data']['characterId']
fab, lena, mira, jonas = ids[1], ids[2], ids[3], ids[4]
env.command(0, f'setrank {fab} chief'); env.command(0, f'setrank {lena} admin')
for s in (1, 2, 3, 4): env.call(s, 'char_select', {'id': ids[s]})
env.command(1, 'aduty'); env.command(2, 'aduty')
env.positions[1] = [100.0, 100.0, 30.0]; env.positions[2] = [105.0, 100.0, 30.0]; env.positions[3] = [110.0, 100.0, 30.0]; env.positions[4] = [600.0, 100.0, 30.0]

print('/kill')
env.command(1, f'kill {mira}')
check('/kill ID', ev(env, 3, 'core:admin:kill') and 'bewusstlos gemacht' in last(env, 1)[0])
env.lua.execute(f'Core.GetPlayerByCharacter({mira}).character.diedAt = os.time()')
env.command(1, f'kill {mira}')
check('Schon bewusstlos', 'schon bewusstlos' in last(env, 1)[0])
env.lua.execute(f'Core.GetPlayerByCharacter({mira}).character.diedAt = nil')
env.events.clear()
env.command(1, 'kill r 20')
check('/kill r 20: Lena im Dienst übersprungen, Mira ja, nicht man selbst', ev(env, 3, 'core:admin:kill') and not ev(env, 2, 'core:admin:kill') and not ev(env, 1, 'core:admin:kill') and 'im Admin-Dienst' in last(env, 1)[0], last(env, 1))
env.command(2, f'kill {fab}')
check('Admin tötet Chief nicht', 'höheren Rang' in last(env, 2)[0])
env.command(2, 'kill all')
check('Admin hat kein "all"', 'Für "all"' in last(env, 2)[0])
env.command(1, 'kill')
check('/kill selbst geht auch im Dienst', ev(env, 1, 'core:admin:kill'))
env.command(3, f'kill {jonas}')
check('Spieler hat kein /kill', 'keine Rechte' in last(env, 3)[0])

print('Erkennungsmodus')
env.command(1, f'warn {mira} 0 Testverwarnung eins')
env.command(1, f'warn {mira} Testverwarnung zwei')
env.sql("INSERT INTO account_links (account_id, other_account_id, type, value) VALUES (3, 4, 'license', 'x')") if False else None
r = env.call(3, 'admin_esp', {'on': True})
check('Spieler darf nicht', r['error'] == 'no_permission')
env.command(2, 'aduty')
r = env.call(2, 'admin_esp', {'on': True})
check('Ohne Dienst nicht', r['error'] == 'duty_required', r)
env.command(2, 'aduty')
r = env.call(1, 'admin_esp', {})
check('Nachladen ohne Einschalten geht nicht', r['error'] == 'esp_off')
r = env.call(1, 'admin_esp', {'on': True})
players = {p['serverId']: p for p in r['data']['players']}
check('Einschalten liefert alle Spieler', r['ok'] and len(players) == 4, r)
m = players[3]
check('Mira: Name, IDs, 2 Verwarnungen', m['name'] == 'Mira Brandt' and m['characterId'] == mira and m['accountId'] == 3 and m.get('warns') == 2, m)
check('Lena: Rang und Dienst', players[2].get('rank') == 'Administrator' and players[2].get('duty') is True, players[2])
check('Spieler ohne Rang hat kein Rang-Feld', 'rank' not in players[4] or players[4]['rank'] is None, players[4])
check('Grenze für Auto-Ban mitgeschickt', r['data']['warnBanAt'] == 3)
r = env.call(1, 'admin_esp', {})
check('Nachladen geht, solange an', r['ok'])
env.command(1, 'aduty')
r = env.call(1, 'admin_esp', {})
check('Dienstende schaltet aus', r['error'] in ('duty_required', 'esp_off'), r)
env.flush_log()
rows = [x['action'] for x in env.sql("SELECT action FROM audit_log WHERE action IN ('esp_on','esp_off','kill') ORDER BY id")]
check('Ein, Aus und Kill geloggt', rows.count('esp_on') == 1 and rows.count('esp_off') == 1 and rows.count('kill') >= 3, rows)
print(f'\n{ok} ok, {fail} Fehler')
