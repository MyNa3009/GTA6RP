import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Env

passed = 0
failed = 0


def check(label, condition, info=None):
    global passed, failed
    if condition:
        passed += 1
        print(f'  ok    {label}')
    else:
        failed += 1
        print(f'  FEHLER {label}  {info if info is not None else ""}')


def note(env, src):
    msgs = [d['text'] for s, n, d in env.events if s == src and n == 'core:notify']
    return msgs[-1] if msgs else None


JAIL = (1641.64, 2571.08, 45.56)
CITY = (-269.4, -955.3, 31.2)

env = Env(debug=False)
ADMIN, PLAYER, JUNIOR = 1, 2, 3

print('Setup')
env.connect(ADMIN, ['license:aaa', 'license2:aaa2', 'discord:111'])
env.connect(PLAYER, ['license:bbb', 'discord:222'])
env.connect(JUNIOR, ['license:ccc'])
r = env.call(ADMIN, 'auth_register', {'email': 'admin@test.de', 'password': 'passwort123'})
check('Admin registriert', r['ok'], r)
r = env.call(PLAYER, 'auth_register', {'email': 'spieler@test.de', 'password': 'passwort123'})
check('Spieler registriert', r['ok'], r)
r = env.call(JUNIOR, 'auth_register', {'email': 'junior@test.de', 'password': 'passwort123'})

for src, first, last in [(ADMIN, 'Fabian', 'Nandes'), (PLAYER, 'Lena', 'Wojcik'), (JUNIOR, 'Kemal', 'Arslan')]:
    r = env.call(src, 'char_create', {'firstname': first, 'lastname': last, 'dateOfBirth': '1995-05-05', 'gender': 'male'})
    check(f'Charakter {first} erstellt', r['ok'], r)
env.command(0, 'setrank 1 chief')
env.command(0, 'setrank 3 junior')
check('Rang erst mit dem Charakter', env.lua.eval('Core.Players[1].rank') == 'player')
r = env.call(PLAYER, 'char_create', {'firstname': 'Lena', 'lastname': 'Brandt', 'dateOfBirth': '1996-05-05', 'gender': 'female'})
lena2 = r['data']['characterId']
lena1 = [c for c in r['data']['characters'] if c['lastname'] == 'Wojcik'][0]['id']

for src in (ADMIN, PLAYER, JUNIOR):
    chars = env.call(src, 'char_list')['data']['characters']
    r = env.call(src, 'char_select', {'id': chars[0]['id']})
    check(f'Spieler {src} spawnt', r['ok'] and r['data'].get('jail') is None, r)
    check(f'ID über dem Kopf = Charakter-ID ({src})', env.state.get((src, 'coreId')) == chars[0]['id'], env.state.get((src, 'coreId')))
    env.positions[src] = list(CITY)
check('Rang nach Charakterwahl', env.lua.eval('Core.Players[1].rank') == 'chief' and env.lua.eval('Core.Players[3].rank') == 'junior')

print('Rechte und Dienst')
env.command(ADMIN, 'ajail 2 30 Trollen')
check('Ohne Dienst kein /ajail', 'Admin-Dienst' in (note(env, ADMIN) or ''), note(env, ADMIN))
env.command(ADMIN, 'aduty')
env.command(JUNIOR, 'aduty')
env.command(JUNIOR, 'ban 2 7d Test')
check('Junior darf nicht bannen', 'keine Rechte' in (note(env, JUNIOR) or ''), note(env, JUNIOR))
env.command(JUNIOR, 'ajail 1 10 Rache')
check('Junior kann Chief nicht jailen', 'höheren' in (note(env, JUNIOR) or ''), note(env, JUNIOR))
env.command(ADMIN, 'ajail 1 10 Selbsttest')
check('Selbst jailen ohne Debug verboten', 'dir selbst' in (note(env, ADMIN) or ''), note(env, ADMIN))
env.command(ADMIN, 'ajail 2 abc Trollen')
check('Minuten werden geprueft', 'Minuten' in (note(env, ADMIN) or ''), note(env, ADMIN))
env.command(ADMIN, 'ajail 2 30 x')
check('Grund zu kurz', 'Grund' in (note(env, ADMIN) or ''), note(env, ADMIN))

print('A-Jail online')
env.command(ADMIN, 'ajail 2 2 Trollen am Würfelpark')
check('Admin bekommt Bestaetigung', '2 Minuten' in (note(env, ADMIN) or ''), note(env, ADMIN))
start = env.events_for(PLAYER, 'core:jail:start')
check('Spieler bekommt jail:start', len(start) == 1 and start[0]['jail']['remaining'] == 120, start)
env.positions[PLAYER] = list(JAIL)
row = env.sql('SELECT * FROM admin_jails WHERE account_id = 2')[0]
check('Jail in DB, Charakter gemerkt', row['minutes'] == 2 and row['character_id'] == lena1 and row['released_at'] is None, row)

env.tick(5000)
env.positions[PLAYER] = list(CITY)
env.tick(3000)
check('Innerhalb der Schonfrist kein Zurücksetzen', len(env.events_for(PLAYER, 'core:jail:return')) == 0)
env.tick(5000)
ret = env.events_for(PLAYER, 'core:jail:return')
check('Flucht: zurück ins A-Jail', len(ret) >= 1 and abs(ret[0]['position']['x'] - JAIL[0]) < 0.01, ret)
env.positions[PLAYER] = list(JAIL)

r = env.call(PLAYER, 'admin_noclip', {'on': True})
check('Spieler ohne Recht: kein Noclip', not r['ok'] and r['error'] == 'no_permission', r)
r = env.call(PLAYER, 'death_report', {'weapon': 0})
r = env.call(PLAYER, 'death_respawn')
check('Krankenhaus zu frueh', r['error'] == 'too_early', r)
env.lua.execute('Core.Players[2].character.diedAt = os.time() - 999')
r = env.call(PLAYER, 'death_respawn')
check('Tod im A-Jail: Aufwachen im A-Jail', r['ok'] and abs(r['data']['position']['x'] - JAIL[0]) < 0.01, r)

r = env.call(ADMIN, 'admin_action', {'action': 'bring', 'serverId': PLAYER})
check('Holen aus dem A-Jail blockiert', r['error'] == 'target_jailed', r)

print('Relog behält Restzeit')
env.tick(30000)
before = env.lua.eval('Core.Players[2].jail.remaining')
env.command(PLAYER, 'relog')
row = env.sql('SELECT remaining_seconds FROM admin_jails WHERE account_id = 2')[0]
check('Restzeit gespeichert', abs(row['remaining_seconds'] - before) <= 1, (row, before))
env.tick(60000)
r = env.call(PLAYER, 'auth_login', {'email': 'spieler@test.de', 'password': 'passwort123'})
r = env.call(PLAYER, 'char_select', {'id': lena2})
check('Anderer Charakter: nicht im A-Jail', r['ok'] and r['data'].get('jail') is None, r)
check('ID über dem Kopf wechselt', env.state.get((PLAYER, 'coreId')) == lena2, env.state.get((PLAYER, 'coreId')))
env.positions[PLAYER] = list(CITY)
returns_before = len(env.events_for(PLAYER, 'core:jail:return'))
env.tick(15000)
check('Anderer Charakter wird nicht zurückgesetzt', len(env.events_for(PLAYER, 'core:jail:return')) == returns_before)
env.command(PLAYER, 'relog')
env.call(PLAYER, 'auth_login', {'email': 'spieler@test.de', 'password': 'passwort123'})
r = env.call(PLAYER, 'char_select', {'id': lena1})
check('Bestrafter Charakter: wieder im A-Jail', r['ok'] and r['data']['jail'] is not None and abs(r['data']['position']['x'] - JAIL[0]) < 0.01, r)
check('Offline lief keine Zeit', r['data']['jail']['remaining'] == row['remaining_seconds'], r['data']['jail'])
env.positions[PLAYER] = list(JAIL)
env.tick(int(row['remaining_seconds']) * 1000 + 2000)
end = env.events_for(PLAYER, 'core:jail:end')
check('Zeit abgesessen: jail:end mit Ausgang', len(end) == 1 and abs(end[0]['position']['x'] - 1847.0) < 0.01, end)
row = env.sql('SELECT * FROM admin_jails WHERE account_id = 2')[0]
check('In DB entlassen, ohne Admin', row['released_at'] is not None and row['released_by'] is None and row['release_reason'] == 'Zeit abgesessen', row)

print('A-Jail offline und Entlassen offline')
env.command(PLAYER, 'relog')
env.command(ADMIN, 'ajail 2 15 Offline-Test')
check('Offline-Jail gemeldet', 'nicht im Spiel' in (note(env, ADMIN) or ''), note(env, ADMIN))
env.call(PLAYER, 'auth_login', {'email': 'spieler@test.de', 'password': 'passwort123'})
r = env.call(PLAYER, 'char_select', {'id': lena1})
check('Beim Spielen im A-Jail', r['data']['jail'] is not None and r['data']['jail']['remaining'] == 900, r['data'])
env.positions[PLAYER] = list(JAIL)
env.tick(2000)
env.command(PLAYER, 'relog')
env.command(ADMIN, 'unjail 2 Fehler von mir')
check('Unjail offline', 'entlassen' in (note(env, ADMIN) or ''), note(env, ADMIN))
env.call(PLAYER, 'auth_login', {'email': 'spieler@test.de', 'password': 'passwort123'})
r = env.call(PLAYER, 'char_select', {'id': lena1})
check('Nach Entlassen offline: Spawn vor dem Tor', r['data'].get('jail') is None and abs(r['data']['position']['x'] - 1847.0) < 0.01, r['data'])
env.positions[PLAYER] = list(CITY)

print('Admin-Menü: Strafen')
r = env.call(ADMIN, 'admin_punish', {'type': 'jail', 'accountId': 2, 'characterId': lena1, 'minutes': 5, 'reason': 'Menü-Test'})
check('Jail ueber Menue', r['ok'] and r['data']['punishments']['activeJails'][0]['minutes'] == 5, r)
r = env.call(ADMIN, 'admin_punish', {'type': 'jail', 'accountId': 2, 'characterId': lena1, 'minutes': 5, 'reason': 'Doppelt'})
check('Doppeltes Jail abgelehnt', r['error'] == 'already_jailed', r)
r = env.call(ADMIN, 'admin_overview')
lena_entry = [p for p in r['data']['players'] if p['accountId'] == 2][0]
check('Spielerliste zeigt A-Jail', lena_entry['jailed'] is True, lena_entry)
r = env.call(ADMIN, 'admin_punish', {'type': 'unjail', 'accountId': 2, 'characterId': lena1})
check('Entlassen ohne Grund', r['ok'] and not r['data']['punishments'].get('activeJails'), r)
check('Spieler bekommt jail:end', len(env.events_for(PLAYER, 'core:jail:end')) == 2)

print('Charakter-Ban')
r = env.call(ADMIN, 'admin_punish', {'type': 'ban', 'accountId': 2, 'scope': 'character', 'characterId': lena1, 'duration': '3d', 'reason': 'Powergaming'})
check('Charakter-Ban ueber Menue', r['ok'], r)
ret = env.events_for(PLAYER, 'core:char:return')
check('Spieler zurück in die Auswahl', len(ret) == 1 and ret[0]['notice'] == 'character_banned', ret)
check('Charakter entladen', env.lua.eval('Core.Players[2].character') is None)
chars = env.call(PLAYER, 'char_list')['data']['characters']
banned = [c for c in chars if c['id'] == lena1][0]
check('Liste zeigt Ban', banned.get('ban') and banned['ban']['reason'] == 'Powergaming' and banned['ban']['expiresAt'], banned)
r = env.call(PLAYER, 'char_select', {'id': lena1})
check('Gebannter Charakter nicht spielbar', not r['ok'] and r['error'] == 'character_banned' and r['data']['ban']['id'], r)
r = env.call(PLAYER, 'char_delete', {'id': lena1})
check('Gebannter Charakter nicht löschbar', r['error'] == 'character_banned', r)
r = env.call(PLAYER, 'char_select', {'id': lena2})
check('Anderer Charakter spielbar', r['ok'], r)
r = env.call(ADMIN, 'admin_punish', {'type': 'ban', 'accountId': 3, 'characterId': lena1, 'duration': '3d', 'reason': 'Falscher Account'})
check('Charakter fremden Accounts abgelehnt', r['error'] == 'character_not_found', r)
r = env.call(ADMIN, 'admin_punish', {'type': 'ban', 'accountId': 2, 'scope': 'character', 'characterId': lena1, 'duration': '3d', 'reason': 'Nochmal'})
check('Doppelter Charakter-Ban abgelehnt', r['error'] == 'already_banned', r)
r = env.call(ADMIN, 'admin_punish', {'type': 'ban', 'accountId': 2, 'scope': 'login', 'duration': '400d', 'reason': 'Zu lang'})
check('Zu lange Dauer abgelehnt', r['error'] == 'invalid_duration', r)
env.command(ADMIN, f'unban {lena1} Einspruch angenommen')
check('Charakter entbannt', 'entbannt' in (note(env, ADMIN) or ''), note(env, ADMIN))
chars = env.call(PLAYER, 'char_list')['data']['characters']
check('Liste ohne Ban', not [c for c in chars if c['id'] == lena1][0].get('ban'))

print('Account-Ban')
env.command(ADMIN, f'loginban {lena2} 7d Cheating mit Mod-Menü')
check('Bestätigung mit Kick', 'gekickt' in (note(env, ADMIN) or ''), note(env, ADMIN))
check('Spieler gekickt mit Ban-Text', env.dropped and 'Cheating' in env.dropped[-1][1] and 'Ban-ID' in env.dropped[-1][1], env.dropped)
check('Spieler entfernt', env.lua.eval('Core.Players[2]') is None)
msg = env.connect(PLAYER, ['license:bbb', 'discord:222'])
check('Neu verbinden: abgelehnt', msg and 'gebannt' in msg, msg)
msg = env.connect(7, ['license:neu', 'discord:222'])
check('Zweit-Account mit gleichem Discord: abgelehnt', msg and 'gebannt' in msg, msg)
msg = env.connect(8, ['license:fremd'])
check('Fremdes Gerät kommt rein', msg is None, msg)
r = env.call(8, 'auth_login', {'email': 'spieler@test.de', 'password': 'passwort123'})
check('Login am fremden Gerät: banned mit Daten', not r['ok'] and r['error'] == 'banned' and r['data']['reason'].startswith('Cheating'), r)
check('Kein Login trotz Ban', env.lua.eval('Core.Players[8].loggedIn') is False)
r = env.call(ADMIN, 'admin_accounts', {'page': 0})
rows2 = [a for a in r['data']['accounts'] if a['accountId'] == 2]
check('Alle-Liste: jeder Charakter eigene Zeile', sorted(a['characterId'] for a in rows2) == sorted([lena1, lena2]), rows2)
check('Alle-Liste zeigt Gebannt', all(a['banned'] for a in rows2), rows2)
r = env.call(ADMIN, 'admin_search', {'query': str(lena2)})
check('Suche nach permanenter ID', r['data']['results'][0]['characterId'] == lena2, r)
r = env.call(ADMIN, 'admin_profile', {'characterId': lena2})
check('Akte über permanente ID', r['ok'] and r['data']['account']['id'] == 2 and r['data']['focusCharacterId'] == lena2, r.get('error'))
r = env.call(ADMIN, 'admin_profile', {'accountId': 2})
p = r['data']['punishments']
check('Akte: aktiver Ban mit Name des Admins', p['activeBan'] and p['activeBan']['bannedByName'] == 'Fabian Nandes', p.get('activeBan'))
check('Akte: Ban-Historie', len(p['bans']) == 2 and len(p['jails']) == 3, (len(p['bans']), len(p['jails'])))
check('Akte: Charakterbezeichnung', any(b.get('characterName') == 'Lena Wojcik' for b in p['bans']), p['bans'])
r = env.call(JUNIOR, 'admin_punish', {'type': 'unban', 'accountId': 2, 'banId': p['activeBan']['id']})
check('Junior darf nicht entbannen', r['error'] == 'no_permission', r)
r = env.call(ADMIN, 'admin_punish', {'type': 'unban', 'accountId': 3, 'banId': p['activeBan']['id']})
check('Ban-ID zum falschen Account abgelehnt', r['error'] == 'not_banned', r)
env.command(0, f'loginunban {lena1} Konsole')
row = env.sql('SELECT * FROM bans WHERE account_id = 2 AND character_id IS NULL')[0]
check('Konsole entbannt (lifted_by NULL)', row['lifted_at'] is not None and row['lifted_by'] is None and row['lift_reason'] == 'Konsole', row)
msg = env.connect(PLAYER, ['license:bbb', 'discord:222'])
check('Nach Entbannen: Verbinden geht', msg is None, msg)

print('Zeitlicher Ban läuft ab')
env.command(0, f'loginban {lena1} 30m Kurzer Test')
msg = env.connect(9, ['license:bbb'])
check('Gebannt', msg is not None)
env.sql("UPDATE bans SET expires_at = DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 SECOND) WHERE lifted_at IS NULL")
msg = env.connect(10, ['license:bbb'])
check('Nach Ablauf wieder rein', msg is None, msg)

print('Befehle mit permanenter ID')
env.command(ADMIN, 'revive 3')
check('/revive mit permanenter ID', 'ID 3 wiederbelebt' in (note(env, ADMIN) or ''), note(env, ADMIN))
env.command(ADMIN, 'revive 999')
check('/revive unbekannte ID', 'Niemand' in (note(env, ADMIN) or ''), note(env, ADMIN))
env.command(ADMIN, 'givemoney cash 3 100')
check('/givemoney Kontostand', 'Kontostand (cash) von ID 3' in (note(env, ADMIN) or ''), note(env, ADMIN))
env.command(ADMIN, 'removemoney bank 3 50')
check('/removemoney', 'Kontostand (bank) von ID 3' in (note(env, ADMIN) or ''), note(env, ADMIN))
env.command(ADMIN, 'removemoney bank 3 999999')
check('/removemoney zu viel', 'Nicht genug' in (note(env, ADMIN) or ''), note(env, ADMIN))
env.command(ADMIN, 'givemoney konto 3 10')
check('/givemoney falsches Konto zeigt Benutzung', 'Benutzung' in (note(env, ADMIN) or ''), note(env, ADMIN))


print('Noclip')
env.command(ADMIN, 'aduty')
r = env.call(ADMIN, 'admin_noclip', {'on': True})
check('Noclip ohne Dienst abgelehnt', r['error'] == 'duty_required', r)
env.command(ADMIN, 'aduty')
r = env.call(ADMIN, 'admin_noclip', {'on': True})
check('Noclip im Dienst', r['ok'] and r['data']['on'], r)
env.tick(20000)
env.command(ADMIN, 'aduty')
off = env.events_for(ADMIN, 'core:admin:noclip')
check('Dienstende beendet Noclip', off and off[-1]['on'] is False, off)
env.flush_log()
rows = env.sql("SELECT action, reason, data FROM audit_log WHERE action LIKE 'noclip%%' ORDER BY id")
check('Noclip an und aus im Log', [r['action'] for r in rows] == ['noclip_on', 'noclip_off'] and rows[1]['reason'] == 'Admin-Dienst beendet', rows)

print('Log')
rows = env.sql("SELECT action, COUNT(*) n FROM audit_log WHERE category = 'punishment' GROUP BY action")
actions = {r['action']: r['n'] for r in rows}
check('Strafen im Log', all(a in actions for a in ['jail', 'unjail', 'jail_done', 'jail_escape', 'ban', 'character_ban', 'unban']), actions)
rows = env.sql("SELECT action FROM audit_log WHERE category = 'security' AND action IN ('ban_blocked','login_banned','banned_character_select')")
check('Sicherheits-Einträge', {r['action'] for r in rows} == {'ban_blocked', 'login_banned', 'banned_character_select'}, rows)
r = env.call(ADMIN, 'admin_logs', {'accountId': 2, 'category': 'punishment', 'page': 0})
check('Akte: Strafen-Logs abrufbar', r['ok'] and len(r['data']['entries']) >= 7, r.get('error'))

print('Debug-Modus: selbst testen')
env2 = Env(debug=True)
env2.connect(1, ['license:aaa'])
env2.call(1, 'auth_register', {'email': 'a@b.de', 'password': 'passwort123'})
r = env2.call(1, 'char_create', {'firstname': 'Fabian', 'lastname': 'Nandes', 'dateOfBirth': '1995-05-05', 'gender': 'male'})
env2.call(1, 'char_select', {'id': r['data']['characterId']})
env2.command(0, 'setrank 1 chief')
env2.command(1, 'aduty')
env2.command(1, 'ajail 1 1 Selbsttest')
check('Debug: sich selbst jailen', len(env2.events_for(1, 'core:jail:start')) == 1, note(env2, 1))
check('Debug: Dienst endet im A-Jail', env2.lua.eval('Core.Players[1].adminDuty') is None and env2.events_for(1, 'core:admin:duty')[-1]['on'] is False)
env2.command(1, 'aduty')
check('Debug: im A-Jail kein Dienst', 'A-Jail' in (note(env2, 1) or ''), note(env2, 1))

print(f'\n{passed} ok, {failed} Fehler')
sys.exit(1 if failed else 0)
