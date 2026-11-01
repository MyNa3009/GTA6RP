import os
import sys, time; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Env
ok = fail = 0
def check(l, c, i=None):
    global ok, fail
    if c: ok += 1; print('  ok   ', l)
    else: fail += 1; print('  FEHLER', l, i)

env = Env()
for s in (1, 2):
    env.connect(s, [f'license:{s}'])
    env.call(s, 'auth_register', {'email': f'{s}@t.de', 'password': 'passwort123'})
fab = env.call(1, 'char_create', {'firstname': 'Fabian', 'lastname': 'Nandes', 'dateOfBirth': '1995-01-01', 'gender': 'male'})['data']['characterId']
mira = env.call(2, 'char_create', {'firstname': 'Mira', 'lastname': 'Brandt', 'dateOfBirth': '1995-01-01', 'gender': 'female'})['data']['characterId']
env.command(0, f'setrank {fab} chief')
env.call(1, 'char_select', {'id': fab}); env.call(2, 'char_select', {'id': mira})
env.flush_log()

# 12 000 alte Eintraege fuer Login 2 (Mira) und ein paar neue
now = env.lua.eval('os.time()')
env.sql("INSERT INTO audit_log (created_at, account_id, category, action, reason) SELECT FROM_UNIXTIME(%s - 200*86400 + seq), 2, 'test', 'alt', 'alter Eintrag' FROM seq_1_to_12000", (now,))
env.sql("INSERT INTO audit_log (created_at, account_id, category, action, reason) VALUES (FROM_UNIXTIME(%s - 89*86400), 2, 'test', 'jung', 'neuer Eintrag')", (now,))
before = env.sql('SELECT COUNT(*) n FROM audit_log')[0]['n']

print('Archiv')
env.command(0, 'logarchive')
env.tick(20000)
after = env.sql('SELECT COUNT(*) n FROM audit_log')[0]['n']
arch = env.sql('SELECT COUNT(*) n FROM audit_log_archive')[0]['n']
check('12 000 alte Einträge verschoben, in Portionen', arch == 12000 and after == before - 12000 + 1, (before, after, arch))
check('Der 89 Tage alte Eintrag bleibt', env.sql("SELECT COUNT(*) n FROM audit_log WHERE action='jung'")[0]['n'] == 1)
check('Keine Doppelten', env.sql("SELECT COUNT(*) n FROM audit_log l JOIN audit_log_archive a ON a.id = l.id")[0]['n'] == 0)
env.flush_log()
check('Lauf steht im Log', env.sql("SELECT COUNT(*) n FROM audit_log WHERE action='log_archived'")[0]['n'] == 1)
env.command(0, 'logarchive'); env.tick(1000)
check('Zweiter Lauf: nichts mehr zu tun', env.sql('SELECT COUNT(*) n FROM audit_log_archive')[0]['n'] == 12000)
env.command(1, 'logarchive')
check('Ingame nicht erlaubt', any('Konsole' in d['text'] for s, n, d in env.events if s == 1 and n == 'core:notify'))

print('Akte')
r = env.call(1, 'admin_logs', {'accountId': 2, 'category': 'test', 'page': 0})
check('Aktuelle Akte zeigt nur den neuen', r['ok'] and [e['action'] for e in r['data']['entries']] == ['jung'] and r['data']['archive'] is False, r['data'].get('entries'))
r = env.call(1, 'admin_logs', {'accountId': 2, 'category': 'test', 'page': 0, 'archive': True})
check('Archiv in der Akte, seitenweise', r['ok'] and len(r['data']['entries']) == 50 and r['data']['hasMore'] and r['data']['archive'] and r['data']['archiveDays'] == 90)
r = env.call(1, 'admin_logs', {'accountId': 2, 'category': 'all', 'page': 3, 'archive': True})
check('Archiv Seite 4', r['ok'] and len(r['data']['entries']) == 50)
print(f'\n{ok} ok, {fail} Fehler')
