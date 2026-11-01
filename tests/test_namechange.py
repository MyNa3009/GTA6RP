import os
import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Env
ok = fail = 0
def check(l, c, i=None):
    global ok, fail
    if c: ok += 1; print('  ok   ', l)
    else: fail += 1; print('  FEHLER', l, i)
def last(src):
    n = [d['text'] for s, n, d in env.events if s == src and n == 'core:notify']
    return n[-1] if n else ''
name = lambda cid: (lambda r: f"{r['firstname']} {r['lastname']}")(env.sql('SELECT firstname, lastname FROM characters WHERE id=%s', (cid,))[0])

env = Env()
for s in (1, 2, 3):
    env.connect(s, [f'license:{s}'])
    env.call(s, 'auth_register', {'email': f'{s}@t.de', 'password': 'passwort123'})
fab = env.call(1, 'char_create', {'firstname': 'Fabian', 'lastname': 'Nandes', 'dateOfBirth': '1995-01-01', 'gender': 'male'})['data']['characterId']
mira = env.call(2, 'char_create', {'firstname': 'Mira', 'lastname': 'Brandt', 'dateOfBirth': '1995-01-01', 'gender': 'female'})['data']['characterId']
kemal = env.call(3, 'char_create', {'firstname': 'Kemal', 'lastname': 'Arslan', 'dateOfBirth': '1995-01-01', 'gender': 'male'})['data']['characterId']
env.command(0, f'setrank {fab} chief'); env.command(0, f'setrank {kemal} admin')
for s, c in ((1, fab), (2, mira), (3, kemal)): env.call(s, 'char_select', {'id': c})

env.command(1, f'namechange {mira} Lena Wójcik')
check('Ohne Dienst nicht', 'Admin-Dienst' in last(1), last(1))
env.command(1, 'aduty')
env.command(1, f'namechange {mira} Lena Wójcik')
check('Name in der Datenbank geändert', name(mira) == 'Lena Wójcik', name(mira))
check('Spieler bekommt Bescheid', 'Lena Wójcik' in last(2), last(2))
check('Admin bekommt alt und neu', 'vorher Mira Brandt' in last(1), last(1))
check('Online-Daten aktualisiert', env.lua.eval('Core.Players[2].character.firstname') == 'Lena')
env.command(1, f'namechange {mira} lena-marie wójcik')
check('Bindestrich erlaubt, erster Buchstabe groß', name(mira) == 'Lena-marie Wójcik', name(mira))
env.command(1, f'namechange {mira} Lena')
check('Zu wenig Angaben: Hilfe', 'Benutzung' in last(1))
env.command(1, f'namechange {mira} L3na Brandt')
check('Ziffern nicht erlaubt', 'Ungültiger Name' in last(1))
env.command(1, f'namechange {mira} Kemal Arslan')
check('Name schon vergeben', 'hat schon ID' in last(1) and name(mira) == 'Lena-marie Wójcik', last(1))
env.command(1, 'namechange 9999 Max Muster')
check('Unbekannte ID', 'gibt es nicht' in last(1))
env.command(3, 'aduty')
env.command(3, f'namechange {fab} Peter Pan')
check('Niedriger Rang darf höheren nicht umbenennen', 'höheren Rang' in last(3) and name(fab) == 'Fabian Nandes', last(3))
env.command(2, 'relog'); env.tick(200)
env.command(1, f'namechange {mira} Mira Brandt')
check('Geht auch offline', name(mira) == 'Mira Brandt')
env.flush_log()
rows = env.sql("SELECT data FROM audit_log WHERE action='namechange'")
import json; d0 = json.loads(rows[0]['data']); check('Steht im Log mit alt und neu', len(rows) == 3 and d0['old'] == 'Mira Brandt' and d0['new'] == 'Lena Wójcik', rows)
r = env.call(1, 'admin_overview', {})
cmds = [e['usage'] for g in r['data']['commands'] for e in g['entries']]
check('Steht in der Befehlsliste', any(u.startswith('/namechange') for u in cmds))
print(f'\n{ok} ok, {fail} Fehler')
