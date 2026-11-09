"""Test fuer core_dispatch gegen MariaDB: Notruf per /dispatch, Dienst waehlen, Spam-Schutz, MDT mit Rechten,
Uebernehmen, Zuweisen, automatisch am Einsatzort, Nachricht an den Anrufer, Abschluss mit Ergebnis, Missbrauch-Sperre,
Funkstatus 0 und 5, Funkrufname, Archiv und Statistik, anonyme Anrufer, Admin-Ansicht, Protokoll und Log."""
import os
import re
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


env = Env(inventory=True, debug=True, extra=['core_lib', 'core_factions', 'core_dispatch'])
for name in ('core_lib', 'core_factions', 'core_dispatch'):
    env.runtimes[name].execute('Config.Network.MaxRequestsPerSecond = 0')
env.inv.execute('Config.Network.MaxRequestsPerSecond = 0')
disp = env.runtimes['core_dispatch']
D = lambda src, name, data=None: env.rcall('core_dispatch', src, name, data)
F = lambda src, name, data=None: env.rcall('core_factions', src, name, data)

HOSPITAL = [300.0, -590.0, 43.3]
LOCKER = [298.6, -598.3, 43.3]
PIER = [-1600.0, -1050.0, 13.0]
people = {1: ('Lena', 'Hoffmann'), 2: ('Paul', 'Krüger'), 3: ('Mira', 'Schulz'), 4: ('Tom', 'Becker'), 5: ('Sara', 'Yilmaz')}
ids = {}
for src, (first, last) in people.items():
    env.connect(src, [f'license:{src}'])
    env.call(src, 'auth_register', {'email': f'{src}@t.de', 'password': 'passwort123'})
    ids[src] = env.call(src, 'char_create', {'firstname': first, 'lastname': last, 'dateOfBirth': '1990-01-01', 'gender': 'male'})['data']['characterId']
for src in people:
    env.call(src, 'char_select', {'id': ids[src]})
env.tick(1500)
for src in people:
    env.positions[src] = list(HOSPITAL)
env.positions[2] = list(PIER)


def notes(src):
    return [d.get('text', '') for d in env.events_for(src, 'core:notify')]


def last(src, name):
    events = env.events_for(src, name)
    return events[-1] if events else None


def unit(src):
    return env.to_py(disp.eval(f'Disp.Unit({src})'))


print('Dienst und Einheiten')
env.command(0, f'setorga {ids[1]} ems 30')
env.command(0, f'setorga {ids[3]} ems 1')
env.command(0, f'setorga {ids[4]} ems 20')
for src in (1, 3, 4):
    env.positions[src] = list(LOCKER)
    F(src, 'faction_duty')
    env.positions[src] = list(HOSPITAL)
env.tick(300)
check('drei Einheiten im Dienst, Status 2 (auf Wache)', all(unit(s) and unit(s)['status'] == 2 for s in (1, 3, 4)), [unit(s) for s in (1, 3, 4)])
check('Einheit bekommt ihren Stand', (last(3, 'core_dispatch:self') or {}).get('status') == 2)
perms = [p['key'] for p in env.to_py(env.runtimes['core_factions'].eval("Factions.PermissionsOf('ems')"))]
check('Rechte im Organisationsmenü angemeldet', {'dispatch.view', 'dispatch.manage', 'dispatch.archive'} <= set(perms), perms)

print('Notruf absetzen')
check('zu kurz: text_too_short', D(2, 'dispatch_send', {'text': 'Hi'})['error'] == 'text_too_short')
r = D(2, 'dispatch_send', {'text': 'Person liegt bewusstlos am Pier, atmet kaum', 'location': 'Del Perro Pier, Del Perro'})
check('Notruf angenommen, Einsatznummer EMS JJ/NNNN', r['ok'] and re.fullmatch(r'EMS \d\d/\d{4}', r['data']['number']), r)
check('Anrufer erfährt, wie viele Einheiten im Dienst sind', r['data']['units'] == 3)
c1 = r['data']['id']
row = env.sql('SELECT * FROM dispatch_calls WHERE id = %s', (c1,))[0]
check('Position vom Server, nicht vom Client', abs(row['x'] - PIER[0]) < 0.1 and abs(row['y'] - PIER[1]) < 0.1, row)
check('Ortsname gespeichert (nur Anzeige)', row['location'] == 'Del Perro Pier, Del Perro')
alert = last(3, 'core_dispatch:call')
check('Alarm an alle Einheiten (neu)', alert and alert['alert'] == 'new' and alert['call']['id'] == c1 and last(1, 'core_dispatch:call')['call']['id'] == c1)
check('Einheiten sehen den Anrufer', alert['call']['caller']['id'] == ids[2])
check('Paul (kein Mitglied) bekommt keinen Alarm', last(2, 'core_dispatch:call') is None)
check('Spam-Schutz: cooldown mit Sekunden', D(2, 'dispatch_send', {'text': 'Nochmal Hilfe bitte'})['error'] == 'cooldown')
disp.execute('Config.Dispatch.CooldownSeconds = 0')
r2 = D(2, 'dispatch_send', {'text': 'ems Unfall auf der Route 68, zwei Autos'})
check('Dienst über das erste Wort, Wort fällt weg', r2['ok'] and env.sql('SELECT text FROM dispatch_calls WHERE id = %s', (r2['data']['id'],))[0]['text'] == 'Unfall auf der Route 68, zwei Autos', r2)
c2 = r2['data']['id']
check('höchstens 2 offene Notrufe: too_many_open', D(2, 'dispatch_send', {'text': 'Noch ein dritter Notruf'})['error'] == 'too_many_open')
mine = D(2, 'dispatch_mine')['data']
check('Formular: eigene Notrufe, Dienste mit Einheiten', len(mine['calls']) == 2 and mine['services'][0]['units'] == 3 and mine['calls'][0]['status'] == 'open', mine)

print('MDT öffnen')
check('Paul (kein Mitglied): not_member', D(2, 'dispatch_mdt_open')['error'] == 'not_member')
m = D(3, 'dispatch_mdt_open')
md = m['data'] if m['ok'] else {}
check('Mira (Rang 1): MDT ohne Disponieren und Archiv', m['ok'] and md['manage'] is False and md['archive'] is False, m)
check('Einsätze, Einheiten, Status 0 bis 8, Ergebnisse', len(md['calls']) == 2 and len(md['units']) == 3 and len(md['statuses']) == 9 and len(md['results']) == 6)
check('Farben und Logo der Organisation', md['org']['theme']['accent'] == '37 94 190' and md['org']['logo'].endswith('logos/ems.png'), md.get('org'))
t = D(4, 'dispatch_mdt_open')['data']
check('Tom (Rang 20): disponieren und Archiv mit Statistik', t['manage'] is True and t['archive'] is True and t['stats']['today'] == 2 and len(t['stats']['days']) == 7, t.get('stats'))

print('Übernehmen und zuweisen')
r = D(3, 'dispatch_accept', {'id': c1})
check('Mira übernimmt', r['ok'] and r['data']['call']['status'] == 'active')
check('Mira: Status 3, Einsatz gemerkt', unit(3)['status'] == 3 and unit(3).get('callId') == c1)
check('Anrufer bekommt "übernommen"', any('übernommen' in n for n in notes(2)), notes(2))
check('nochmal übernehmen: already_assigned', D(3, 'dispatch_accept', {'id': c1})['error'] == 'already_assigned')
check('Mira darf nicht zuweisen', D(3, 'dispatch_assign', {'id': c1, 'characterId': ids[1]})['error'] == 'no_permission')
g = D(4, 'dispatch_call_get', {'id': c1})['data']
check('Leitstelle sieht nächste Einheiten, freie zuerst', g['nearest'] and g['nearest'][0]['free'] is True and not [u for u in g['nearest'] if u['id'] == ids[3]][0]['free'], g.get('nearest'))
check('Verlauf: eingegangen, übernommen', [e['kind'] for e in g['events']][:2] == ['created', 'accept'], g['events'])
check('Tom weist Lena zu', D(4, 'dispatch_assign', {'id': c1, 'characterId': ids[1]})['ok'])
check('Lena bekommt den Alarm als zugewiesen', last(1, 'core_dispatch:call')['alert'] == 'assigned')
check('Mira bekommt dafür keinen Alarm', last(3, 'core_dispatch:call').get('alert') is None)
check('Tom zieht Lena wieder ab', D(4, 'dispatch_assign', {'id': c1, 'characterId': ids[1], 'remove': True})['ok'] and unit(1).get('callId') is None and unit(1)['status'] == 1)
check('Lena übernimmt Einsatz 2, wechselt dann zu 1', D(1, 'dispatch_accept', {'id': c2})['ok'] and D(1, 'dispatch_accept', {'id': c1})['ok'])
c2row = env.to_py(disp.eval(f'Calls.Get({c2})'))
check('Einsatz 2 ist wieder offen', c2row['status'] == 'open' and not c2row['unitIds'], c2row)

print('Am Einsatz')
env.positions[3] = [PIER[0] + 10, PIER[1], PIER[2]]
env.tick(5200)
check('Mira am Pier: Status 4 automatisch', unit(3)['status'] == 4)
check('Einsatz: angekommen gemerkt', env.sql('SELECT arrived_at FROM dispatch_calls WHERE id = %s', (c1,))[0]['arrived_at'] is not None)
check('Priorität ändern (zugewiesen)', D(3, 'dispatch_priority', {'id': c1, 'level': 3})['ok'] and last(4, 'core_dispatch:call')['alert'] == 'urgent')
check('ungültige Priorität', D(3, 'dispatch_priority', {'id': c1, 'level': 7})['error'] == 'invalid_priority')
check('Nachricht an den Anrufer', D(3, 'dispatch_message', {'id': c1, 'text': 'RTW ist in zwei Minuten da. Bitte bleib bei der Person.'})['ok']
      and any(n.startswith('Leitstelle Rettungsdienst zu EMS') for n in notes(2)))
check('Notiz', D(3, 'dispatch_note', {'id': c1, 'text': 'Person ansprechbar, Kopfplatzwunde'})['ok'])
mine = D(2, 'dispatch_mine')['data']
check('Anrufer sieht die Nachricht im Formular', mine['calls'][-1]['messages'][0]['text'].startswith('RTW ist'), mine['calls'])
check('nicht zugewiesen: Nachricht no_permission', D(3, 'dispatch_message', {'id': c2, 'text': 'Hallo'})['error'] == 'no_permission')
check('falsches Ergebnis: invalid_result', D(3, 'dispatch_close', {'id': c1, 'result': 'cancelled'})['error'] == 'invalid_result')
r = D(3, 'dispatch_close', {'id': c1, 'result': 'transport', 'report': 'Kopfplatzwunde versorgt, Transport ins Pillbox'})
check('abschließen mit Ergebnis und Bericht', r['ok'] and env.sql('SELECT status, result, report FROM dispatch_calls WHERE id = %s', (c1,))[0]['result'] == 'transport')
check('beide Einheiten wieder Status 1', unit(3)['status'] == 1 and unit(1)['status'] == 1 and unit(3).get('callId') is None)
check('Anrufer: abgeschlossen', any('abgeschlossen' in n for n in notes(2)))
check('Abgeschlossen geht an alle (aus der Liste nehmen)', last(4, 'core_dispatch:call')['call']['status'] == 'closed')
check('zurückziehen: fremder Einsatz not_found', D(3, 'dispatch_cancel', {'id': c2})['error'] == 'not_found')
check('Paul zieht Einsatz 2 zurück', D(2, 'dispatch_cancel', {'id': c2})['ok'] and env.sql('SELECT result FROM dispatch_calls WHERE id = %s', (c2,))[0]['result'] == 'cancelled')

print('Missbrauch')
r = D(2, 'dispatch_send', {'text': 'Hier brennt alles lol'})
c3 = r['data']['id']
check('Tom schließt als Missbrauch', D(4, 'dispatch_close', {'id': c3, 'result': 'abuse'})['ok'])
b = D(2, 'dispatch_send', {'text': 'Wirklich ein Notfall jetzt'})
check('Paul gesperrt, mit Uhrzeit', b['error'] == 'blocked' and re.fullmatch(r'\d\d:\d\d', b['data']['until']), b)
check('Anrufer erfährt die Sperre', any('Missbrauch' in n for n in notes(2)))
env.sql('DELETE FROM dispatch_blocks')

print('Bewusstlos und anonym')
env.call(2, 'death_report', {})
r = D(2, 'dispatch_send', {'text': 'Hilfe ich verblute', 'anonymous': True})
c4 = r['data']['id']
call4 = last(3, 'core_dispatch:call')['call']
check('bewusstlos: mindestens Dringend, markiert', call4['priority'] == 2 and call4['callerDown'] is True, call4)
check('anonym: Einheiten sehen keinen Anrufer', call4.get('caller') is None and call4['anonymous'] is True)

print('Funkstatus und Funkrufname')
check('Status 9 gibt es nicht', D(3, 'dispatch_status', {'status': 9})['error'] == 'invalid_status')
check('Funkrufname setzen', D(3, 'dispatch_callsign', {'callsign': 'RTW 1/83-1'})['data']['callsign'] == 'RTW 1/83-1')
check('Funkrufname gespeichert', env.sql('SELECT callsign FROM dispatch_units WHERE character_id = %s', (ids[3],))[0]['callsign'] == 'RTW 1/83-1')
check('Status 5: Sprechwunsch an alle', D(3, 'dispatch_status', {'status': 5})['ok'] and last(4, 'core_dispatch:talk')['callsign'] == 'RTW 1/83-1')
r = D(3, 'dispatch_status', {'status': 0, 'location': 'Pier'})
unitcall = last(4, 'core_dispatch:call')
check('Status 0: eigener Einsatz "Einheit in Not", Lebensgefahr, dringend gemeldet', r['ok'] and unitcall['alert'] == 'urgent'
      and unitcall['call']['kind'] == 'unit' and unitcall['call']['priority'] == 3 and 'RTW 1/83-1' in unitcall['call']['text'], unitcall)
check('Status 0 zweimal: kein zweiter Einsatz', D(3, 'dispatch_status', {'status': 0})['ok']
      and env.sql("SELECT COUNT(*) AS n FROM dispatch_calls WHERE kind = 'unit'")[0]['n'] == 1)
D(3, 'dispatch_status', {'status': 1})

print('Archiv und Statistik')
check('Mira (Rang 1): kein Archiv', D(3, 'dispatch_archive', {})['error'] == 'no_permission')
a = D(1, 'dispatch_archive', {})['data']
check('Lena: Archiv mit abgeschlossenen Einsätzen', len(a['entries']) == 3 and a['entries'][0]['result'], [e['result'] for e in a['entries']])
number1 = env.sql('SELECT number FROM dispatch_calls WHERE id = %s', (c1,))[0]['number']
s = D(1, 'dispatch_archive', {'search': number1.split(' ')[1]})['data']['entries']
check('Suche nach Einsatznummer', len(s) == 1 and s[0]['number'] == number1)
check('Suche nach ID des Anrufers', len(D(1, 'dispatch_archive', {'search': str(ids[2])})['data']['entries']) == 3)
check('Filter Ergebnis', [e['resultKey'] for e in D(1, 'dispatch_archive', {'result': 'abuse'})['data']['entries']] == ['abuse'])
d = D(1, 'dispatch_call_get', {'id': c1})['data']
check('archivierter Einsatz mit Verlauf und Einheiten', d['call']['status'] == 'closed' and len(d['call']['units']) == 2
      and any(e['kind'] == 'arrive' for e in d['events']) and any(e['kind'] == 'message' for e in d['events']), d['call'].get('units'))
st = a['stats']
check('Statistik heute: Einsätze, Reaktionszeit, Missbrauch, 7 Tage', st['today'] == 5 and st['days'][-1] == {'ago': 0, 'calls': 5} and st['avgAccept'] is not None and st['abuse'] == 1, st)

print('Dienstende')
check('Lena übernimmt den Einsatz von Paul', D(1, 'dispatch_accept', {'id': c4})['ok'])
env.positions[1] = list(LOCKER)
F(1, 'faction_duty')
env.tick(200)
check('Lena aus dem Dienst: keine Einheit mehr', unit(1) is None)
check('Einsatz ohne Lena wieder offen', env.to_py(disp.eval(f'Calls.Get({c4}).status')) == 'open')
check('ohne Dienst: MDT not_on_duty', D(1, 'dispatch_mdt_open')['error'] == 'not_on_duty')

print('Admin')
check('ohne Recht: not_member', D(5, 'dispatch_mdt_open')['error'] == 'not_member')
env.command(0, f'setrank {ids[5]} chief')
env.command(5, 'aduty')
check('Admin ohne Dienst-Angabe: invalid_service', D(5, 'dispatch_mdt_open')['error'] == 'invalid_service')
adm = D(5, 'dispatch_mdt_open', {'service': 'ems'})
check('Admin mit /mdt ems: sieht alles, darf disponieren', adm['ok'] and adm['data']['admin'] is True and adm['data']['manage'] is True and adm['data'].get('me') is None)
check('Admin sieht den anonymen Anrufer', [c for c in adm['data']['calls'] if c['id'] == c4][0]['caller']['id'] == ids[2])
check('Admin bekommt neue Einsätze, solange das MDT offen ist', D(4, 'dispatch_note', {'id': c4, 'text': 'Prüfe Lage'})['ok']
      and last(5, 'core_dispatch:call')['call']['id'] == c4)
check('Admin schließt den Einsatz', D(5, 'dispatch_close', {'id': c4, 'result': 'done', 'report': 'Vom Admin geschlossen'})['ok'])
check('Admin kann nicht übernehmen (keine Einheit)', D(5, 'dispatch_accept', {'id': c4})['error'] in ('not_unit', 'not_found'))
D(5, 'dispatch_mdt_close')
check('MDT zu: keine Einsätze mehr an den Admin', not env.runtimes['core_dispatch'].eval('Disp.Receivers("ems")[3] ~= nil'))

print('Für andere Scripts')
num = env.to_py(disp.eval("exports.core_dispatch and nil or EXPORTS.SendCall('ems', { text = 'Stiller Alarm in der Fleeca Bank', pos = { x = 150.0, y = -1040.0, z = 29.0 }, priority = 2 })"))
check('Export SendCall legt einen Einsatz an', isinstance(num, str) and num.startswith('EMS '), num)

print('Protokoll und Log')
env.tick(300)
texts = [r['text'] for r in env.sql("SELECT text FROM faction_logs WHERE faction = 'ems' AND area = 'einsatz' ORDER BY id")]
check('Protokoll: Notruf, übernommen, zugewiesen, abgeschlossen', any('Notruf eingegangen' in t for t in texts) and any('Einsatz übernommen' in t for t in texts)
      and any('Einheit zugewiesen: Lena Hoffmann' in t for t in texts) and any('Abgeschlossen: Transport' in t for t in texts), texts)
paul = [r for r in env.sql("SELECT target_id FROM faction_logs WHERE area = 'einsatz' AND text LIKE %s", ('%Notruf eingegangen%',))]
check('Notruf im Protokoll beim Anrufer (pro ID)', all(r['target_id'] == ids[2] for r in paul[:3]))
check('Funkstatus im Protokoll (Dienst)', env.sql("SELECT COUNT(*) AS n FROM faction_logs WHERE area = 'dienst' AND text LIKE 'Funkstatus 0%%'")[0]['n'] == 1)
env.flush_log()
check('Core-Log Kategorie dispatch', env.sql("SELECT COUNT(*) AS n FROM audit_log WHERE category = 'dispatch' AND action = 'call'")[0]['n'] >= 6)

print(f'\n{ok} ok, {fail} Fehler')
