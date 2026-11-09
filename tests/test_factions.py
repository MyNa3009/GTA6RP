"""Test fuer core_factions gegen MariaDB: Ränge, Rechte, Abteilungen, Prüfungen, Fahrzeuge, Leitstelle, Archiv,
Kasse, Dienst, Garage, G-Menü-Aktionen und Admin-Ansicht."""
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


env = Env(inventory=True, debug=True, extra=['core_lib', 'core_factions'])
fac = env.runtimes['core_factions']
fac.execute('Config.Network.MaxRequestsPerSecond = 0')   # Spam-Schutz aus, der Test fragt schneller als ein Mensch
F = lambda src, name, data=None: env.rcall('core_factions', src, name, data)

people = {1: ('Lena', 'Hoffmann'), 2: ('Jonas', 'Weber'), 3: ('Mira', 'Schulz'), 4: ('Tom', 'Becker'), 5: ('Sara', 'Yilmaz'), 9: ('Admin', 'Test')}
ids = {}
for src, (first, last) in people.items():
    env.connect(src, [f'license:{src}'])
    env.call(src, 'auth_register', {'email': f'{src}@t.de', 'password': 'passwort123'})
    ids[src] = env.call(src, 'char_create', {'firstname': first, 'lastname': last, 'dateOfBirth': '1995-01-01', 'gender': 'female'})['data']['characterId']
env.sql('UPDATE characters SET cash = 2000 WHERE id = %s', (ids[1],))
for src in people:
    env.call(src, 'char_select', {'id': ids[src]})
env.tick(500)
for src in people:
    env.positions[src] = [300.0, -590.0, 43.3]


def state(src):
    s = env.events_for(src, 'core_factions:state')
    return s[-1] if s else None


def notes(src):
    return [d.get('text', '') for d in env.events_for(src, 'core:notify')]


def member(cid):
    rows = env.sql('SELECT * FROM faction_members WHERE character_id = %s', (cid,))
    return rows[0] if rows else None


print('Admin setzt die Leitung (/setorga)')
env.command(0, f'setorga {ids[1]} ems 30')
env.command(0, f'setorga {ids[2]} ems 29')
env.command(0, f'setorga {ids[3]} ems 18')
check('Lena ist Leader (Rang 30), Dienstnummer EMS-001', member(ids[1])['rank'] == 30 and member(ids[1])['dn'] == 'EMS-001', member(ids[1]))
check('Jonas Vice (29), Mira 18', member(ids[2])['rank'] == 29 and member(ids[3])['rank'] == 18)
check('Stand an Lena: Leader, Rangname, Rechte', state(1)['isLeader'] is True and state(1)['rankName'] == 'Leader' and 'members.fire' in state(1)['permissions'], state(1))
check('Stand an Mira: kein Recht zu entlassen', 'members.fire' not in state(3)['permissions'] and 'leitstelle.view' in state(3)['permissions'])
lic = env.sql("SELECT * FROM licenses WHERE character_id = %s", (ids[1],))
check('Dienstausweis im Inventar ausgestellt', any('EMS' in str(r) for r in lic), lic)
env.command(0, f'setorga {ids[4]} lspd 3')
check('unbekannte Organisation: nichts passiert', member(ids[4]) is None)

print('Tab 1: Übersicht')
ov = F(1, 'faction_menu_open')
check('Leader in der Übersicht', ov['ok'] and ov['data']['leader'] == 'Lena Hoffmann', ov)
check('Lena sieht alle Tabs und die Kasse', all(ov['data']['access'].values()) and ov['data']['balance'] == 0, ov['data']['access'])
mira = F(3, 'faction_menu_open')['data']
check('Mira: Leitstelle ja, Anpassung, Archiv, Kasse nein', mira['access']['leitstelle'] and not mira['access']['structure'] and not mira['access']['archive'] and mira.get('balance') is None, mira['access'])
check('Mira: eigener Rang und Einstellungsdatum', mira['me']['rankName'] == 'Notarzt' and mira['me']['hiredAt'], mira['me'])
check('Nicht-Mitglied: not_member', F(4, 'faction_menu_open')['error'] == 'not_member')
r = F(1, 'faction_message_save', {'text': 'Neuer Dienstplan ab Montag.'})
check('Leader schreibt die Nachricht', r['ok'] and r['data']['message']['text'] == 'Neuer Dienstplan ab Montag.' and r['data']['message']['by'] == 'Lena Hoffmann', r)
check('Mira darf die Nachricht nicht ändern', F(3, 'faction_message_save', {'text': 'x'})['error'] == 'no_permission')

print('Tab 2: Ränge und Rechte')
check('Mira sieht Tab 2 nicht', F(3, 'faction_ranks')['error'] == 'no_permission')
ranks = F(2, 'faction_ranks')['data']
editable = {r['rank']: r['editable'] for r in ranks['ranks']}
check('Vice: Ränge unter 29 änderbar, 29 und 30 nicht', editable[28] and not editable[29] and not editable[30], {k: editable[k] for k in (28, 29, 30)})
check('Rechte von core_factions in der Liste', any(p['key'] == 'members.hire' for p in ranks['permissions']))
check('Vice ändert seinen eigenen Rang nicht', F(2, 'faction_rank_save', {'rank': 29, 'name': 'Chef', 'permissions': []})['error'] == 'no_permission')
r = F(1, 'faction_rank_save', {'rank': 29, 'name': 'Stellv. Leitung', 'permissions': [p['key'] for p in ranks['permissions'] if p['key'] != 'members.fire']})
check('Leader nimmt dem Vice "Entlassen" weg', r['ok'] and 'members.fire' not in state(2)['permissions'], state(2)['permissions'])
check('Rangname beim Vice angekommen', state(2)['rankName'] == 'Stellv. Leitung')
r = F(2, 'faction_rank_save', {'rank': 28, 'name': 'Direktorin', 'permissions': ['leitstelle.view']})
row = env.to_py(fac.eval("{ fire = Factions.RankHas('ems', 28, 'members.fire'), hire = Factions.RankHas('ems', 28, 'members.hire'), name = Factions.RankName('ems', 28) }"))
check('Vice speichert Rang 28: was er nicht hat (Entlassen), bleibt wie es war', r['ok'] and row['fire'] is True and row['hire'] is False and row['name'] == 'Direktorin', row)
check('Leader: höchster Rang hat immer alles', env.to_py(fac.eval("Factions.RankHas('ems', 30, 'members.fire')")) is True)
check('Name zu lang wird gekürzt', F(1, 'faction_rank_save', {'rank': 1, 'name': 'P' * 80, 'permissions': ['leitstelle.view']})['ok'] and len(env.to_py(fac.eval("Factions.RankName('ems', 1)"))) == 32)
check('ungültiger Rang', F(1, 'faction_rank_save', {'rank': 31, 'name': 'x'})['error'] == 'invalid_rank')

print('Tab 2: Abteilungen und Prüfungen')
r = F(2, 'faction_department_save', {'name': 'Ausbildung', 'ranks': ['Mitglied', 'Ausbilder', 'Leitung', 'x4', 'x5', 'zu viel']})
deps = r['data']['departments']
check('Vice legt Abteilung an, höchstens 5 Ränge', r['ok'] and deps[0]['name'] == 'Ausbildung' and len(deps[0]['ranks']) == 5, deps)
dep_a = deps[0]['id']
r = F(2, 'faction_department_save', {'id': dep_a, 'name': 'Ausbildung', 'ranks': ['Mitglied', 'Ausbilder', 'Leitung']})
check('Abteilung bearbeitet (3 Ränge)', r['ok'] and r['data']['departments'][0]['ranks'] == ['Mitglied', 'Ausbilder', 'Leitung'])
dep_b = F(1, 'faction_department_save', {'name': 'Luftrettung', 'ranks': ['Pilot', 'Leitung']})['data']['departments'][1]['id']
check('Mira darf keine Abteilung anlegen', F(3, 'faction_department_save', {'name': 'Neu', 'ranks': ['a']})['error'] == 'no_permission')
check('Abteilung ohne Ränge geht nicht', F(1, 'faction_department_save', {'name': 'Leer', 'ranks': []})['error'] == 'invalid_ranks')
r = F(1, 'faction_exam_save', {'name': 'Notfallsanitäter'})
exam = r['data']['exams'][0]['id']
F(1, 'faction_exam_save', {'name': 'Hubschrauber'})
check('Prüfungen angelegt', len(F(1, 'faction_ranks')['data']['exams']) == 2)

print('Tab 3: Fahrzeuge ab Rang')
v = F(2, 'faction_vehicles')['data']
check('Fahrzeuge aus der Config', [x['model'] for x in v['vehicles']] == ['ambulance', 'lguard', 'firetruk'] and v['canEdit'])
r = F(2, 'faction_vehicle_save', {'model': 'lguard', 'minRank': 5})
check('Vice setzt Einsatzfahrzeug ab Rang 5', r['ok'] and [x for x in r['data']['vehicles'] if x['model'] == 'lguard'][0]['minRank'] == 5)
check('Mira darf das nicht', F(3, 'faction_vehicle_save', {'model': 'lguard', 'minRank': 1})['error'] == 'no_permission')
check('unbekanntes Modell', F(1, 'faction_vehicle_save', {'model': 'adder', 'minRank': 1})['error'] == 'invalid_input')

print('Tab 4: Leitstelle')
lst = F(3, 'faction_members')['data']
check('Mira sieht alle 3, höchster Rang zuerst', [m['characterId'] for m in lst['members']] == [ids[1], ids[2], ids[3]], lst['members'])
check('Mira darf Prüfungen eintragen, keine Strikes', lst['edit'].get('exams') and not lst['edit'].get('strikes'), lst['edit'])
r = F(1, 'faction_hire', {'characterId': ids[4]})
check('Leader stellt Tom per ID ein (mit Zustimmung)', r['ok'] and member(ids[4])['rank'] == 1 and member(ids[4])['dn'] == 'EMS-004', (r, member(ids[4])))
check('Tom wurde gefragt', any(d['title'] == 'Willst du Emergency Medical Service beitreten?' for d in env.events_for(4, 'core:consent')))
check('nochmal einstellen: already_member', F(1, 'faction_hire', {'characterId': ids[4]})['error'] == 'already_member')
env.consent[5] = 'no'
check('Sara lehnt ab', F(1, 'faction_hire', {'characterId': ids[5]})['error'] == 'consent_declined' and member(ids[5]) is None)
env.consent[5] = 'yes'
check('Offline-ID: target_offline', F(1, 'faction_hire', {'characterId': 9999})['error'] == 'target_offline')
r = F(3, 'faction_member_update', {'characterId': ids[4], 'field': 'exams', 'value': 'add', 'examId': exam})
check('Mira trägt bei Tom eine Prüfung ein', r['ok'] and [m for m in r['data']['members'] if m['characterId'] == ids[4]][0]['exams'][0]['by'] == 'Mira Schulz', r)
check('Mira darf sich selbst nichts eintragen', F(3, 'faction_member_update', {'characterId': ids[3], 'field': 'exams', 'value': 'add', 'examId': exam})['error'] == 'no_permission')
check('Mira darf keine Strikes', F(3, 'faction_member_update', {'characterId': ids[4], 'field': 'strikes', 'value': 1})['error'] == 'no_permission')
check('Vice: Strikes 2', F(2, 'faction_member_update', {'characterId': ids[4], 'field': 'strikes', 'value': 2})['ok'] and member(ids[4])['strikes'] == 2)
check('Strikes über dem Limit', F(2, 'faction_member_update', {'characterId': ids[4], 'field': 'strikes', 'value': 11})['error'] == 'invalid_input')
check('Vice: Urlaub 5 Tage', F(2, 'faction_member_update', {'characterId': ids[4], 'field': 'vacation', 'value': 5})['ok'] and member(ids[4])['vacation_days'] == 5)
check('Vice: Dienstnummer EMS-099', F(2, 'faction_member_update', {'characterId': ids[4], 'field': 'dn', 'value': 'EMS-099'})['ok'] and member(ids[4])['dn'] == 'EMS-099')
check('Dienstnummer doppelt', F(2, 'faction_member_update', {'characterId': ids[4], 'field': 'dn', 'value': 'EMS-001'})['error'] == 'dn_taken')
check('Vice kann den Leader nicht ändern', F(2, 'faction_member_update', {'characterId': ids[1], 'field': 'strikes', 'value': 1})['error'] == 'no_permission')
check('Vice: Mira wird Leitung der Ausbildung', F(2, 'faction_member_update', {'characterId': ids[3], 'field': 'departments', 'value': [{'id': dep_a, 'rank': 3}]})['ok'])
check('Vice: Tom in Ausbildung (1) und Luftrettung (1)', F(2, 'faction_member_update', {'characterId': ids[4], 'field': 'departments', 'value': [{'id': dep_a, 'rank': 1}, {'id': dep_b, 'rank': 1}]})['ok'])
env.tick(50)
lst = F(3, 'faction_members')['data']
check('Mira ist jetzt Abteilungsleitung', lst['leads'] == [dep_a], lst['leads'])
r = F(3, 'faction_member_update', {'characterId': ids[4], 'field': 'departments', 'value': [{'id': dep_a, 'rank': 2}, {'id': dep_b, 'rank': 1}]})
check('Abteilungsleitung ändert Toms Rang in ihrer Abteilung', r['ok'], r)
r = F(3, 'faction_member_update', {'characterId': ids[4], 'field': 'departments', 'value': [{'id': dep_a, 'rank': 2}]})
check('... aber nicht in einer fremden Abteilung', r['error'] == 'no_permission', r)
r = F(3, 'faction_department_save', {'id': dep_a, 'name': 'egal', 'ranks': ['Azubi', 'Ausbilder', 'Leitung']})
check('Abteilungsleitung benennt die Ränge um (Name bleibt)', r['ok'] and r['data']['departments'][0]['name'] == 'Ausbildung' and r['data']['departments'][0]['ranks'][0] == 'Azubi', r)
check('... aber nicht mehr Ränge', F(3, 'faction_department_save', {'id': dep_a, 'name': 'x', 'ranks': ['a', 'b', 'c', 'd']})['error'] == 'no_permission')
check('Vice befördert Tom auf 28', F(2, 'faction_member_rank', {'characterId': ids[4], 'rank': 28})['ok'] and member(ids[4])['rank'] == 28)
check('... nicht auf 29 (eigener Rang)', F(2, 'faction_member_rank', {'characterId': ids[4], 'rank': 29})['error'] == 'no_permission')
check('Vice darf nicht mehr entlassen', F(2, 'faction_member_fire', {'characterId': ids[4], 'reason': 'x'})['error'] == 'no_permission')

print('Entlassen und Archiv')
r = F(1, 'faction_member_fire', {'characterId': ids[4], 'reason': 'Dreimal unentschuldigt gefehlt'})
check('Leader entlässt Tom', r['ok'] and member(ids[4]) is None)
check('Tom bekommt Bescheid und keinen Stand mehr', state(4)['member'] is False and 'entlassen' in notes(4)[-1], notes(4)[-1:])
arch = F(1, 'faction_archive', {'page': 1})['data']['entries']
check('Archiv: Tom mit Grund, wer und Art', arch and arch[0]['name'] == 'Tom Becker' and arch[0]['reason'] == 'Dreimal unentschuldigt gefehlt' and arch[0]['by'] == 'Lena Hoffmann' and arch[0]['kind'] == 'fire', arch)
check('Archiv: Ränge mit Leader zu der Zeit', [(x['rank'], x['leader']) for x in arch[0]['ranks']] == [(1, 'Lena Hoffmann'), (28, 'Lena Hoffmann')], arch[0]['ranks'])
check('Archiv: Prüfungen mit Namen', arch[0]['exams'][0]['name'] == 'Notfallsanitäter', arch[0]['exams'])
check('Archiv: Suche nach ID', F(1, 'faction_archive', {'page': 1, 'search': str(ids[4])})['data']['entries'][0]['characterId'] == ids[4])
check('Mira sieht das Archiv nicht', F(3, 'faction_archive', {})['error'] == 'no_permission')
lic = env.sql("SELECT * FROM licenses WHERE character_id = %s", (ids[4],))
check('Dienstausweis entzogen', lic and all(r.get('revoked_at') or r.get('revoked') for r in lic), lic)
check('Leader kann nicht kündigen', F(1, 'faction_leave')['error'] == 'leader_cannot_leave')
check('Mira kündigt selbst', F(3, 'faction_leave')['ok'] and member(ids[3]) is None)
check('Archiv: Mira als gekündigt', F(1, 'faction_archive', {})['data']['entries'][0]['kind'] == 'leave')

print('Kasse')
r = F(1, 'faction_cash', {'action': 'deposit', 'amount': 500})
check('Leader zahlt 500 $ ein', r['ok'] and r['data']['balance'] == 500, r)
r = F(1, 'faction_cash', {'action': 'withdraw', 'amount': 200})
check('... und 200 $ aus', r['ok'] and r['data']['balance'] == 300)
check('mehr als in der Kasse', F(1, 'faction_cash', {'action': 'withdraw', 'amount': 5000})['error'] == 'not_enough_money')
check('mehr Bargeld als man hat', F(1, 'faction_cash', {'action': 'deposit', 'amount': 99999})['error'] == 'not_enough_money')
check('Kommabetrag', F(1, 'faction_cash', {'action': 'deposit', 'amount': 1.5})['error'] == 'invalid_amount')
check('Export Deposit von einem anderen Script', env.to_py(fac.eval("Factions.Deposit('ems', 120, { reason = 'Behandlung' })")) == 420)

print('Dienst und Garage')
env.positions[1] = [298.6, -598.3, 43.3]
r = F(1, 'faction_duty')
check('an der Umkleide: Dienst an', r['ok'] and r['data']['onDuty'] is True and state(1)['onDuty'] is True, r)
env.positions[2] = [0.0, 0.0, 70.0]
check('weit weg: too_far', F(2, 'faction_duty')['error'] == 'too_far')
env.positions[2] = [294.6, -574.6, 43.2]
check('Garage ohne Dienst', F(2, 'faction_garage_list')['error'] == 'not_on_duty')
env.positions[1] = [294.6, -574.6, 43.2]
gl = F(1, 'faction_garage_list')['data']
check('Garage: alle drei erlaubt für den Leader', all(x.get('allowed') for x in gl['vehicles']), gl)
r = F(1, 'faction_garage_take', {'model': 'firetruk'})
plate = r['data']['plate']
check('Ausparken: Kennzeichen EMS und Spawnpunkt', r['ok'] and plate.startswith('EMS ') and len(plate) == 8 and r['data']['spawn']['heading'] == 68.0, r)
fac.execute(f"VEHICLES[777] = {{ plate = '{plate}', x = 291.2, y = -567.4, z = 43.2 }}")
check('Fahrzeug gemeldet', F(1, 'faction_garage_spawned', {'netId': 777})['ok'])
check('zweites Fahrzeug: Limit', F(1, 'faction_garage_take', {'model': 'ambulance'})['error'] == 'vehicle_limit')
check('fremdes Kennzeichen wird nicht angenommen', F(1, 'faction_garage_spawned', {'netId': 778})['error'] == 'no_vehicle')
check('Einparken', F(1, 'faction_garage_store', {'netId': 777})['ok'] and 777 in env.to_py(fac.eval('DELETED')))
check('danach wieder Ausparken möglich', F(1, 'faction_garage_take', {'model': 'ambulance'})['ok'])

print('G-Menü an der Person')
env.positions[5] = [295.0, -574.6, 43.2]
env.consent[5] = 'no'
check('Einstellen am Ziel: abgelehnt', F(1, 'faction_target_hire', {'serverId': 5})['error'] == 'consent_declined')
env.consent[5] = 'yes'
check('Einstellen am Ziel', F(1, 'faction_target_hire', {'serverId': 5})['ok'] and member(ids[5])['rank'] == 1)
r = F(1, 'faction_target_rank', {'serverId': 5, 'delta': 1})
check('Befördern am Ziel', r['ok'] and member(ids[5])['rank'] == 2 and r['data']['rankName'] == 'Rettungssanitäter-Anwärter', r)
env.positions[5] = [600.0, 0.0, 43.2]
check('zu weit weg', F(1, 'faction_target_rank', {'serverId': 5, 'delta': 1})['error'] == 'too_far')

print('Admin-Ansicht')
env.command(0, f'setrank {ids[9]} chief')
env.command(9, 'aduty')
env.command(9, 'orgaview ems')
check('Admin öffnet das Menü', env.events_for(9, 'core_factions:open_admin')[-1]['faction'] == 'ems')
ov = F(9, 'faction_menu_open', {'admin': True})['data']
check('als Admin mit allen Tabs', ov['me']['admin'] and all(ov['access'].values()), ov)
check('Admin ändert Ränge (factions.manage)', F(9, 'faction_rank_save', {'rank': 2, 'name': 'Sanitäter-Anwärter', 'permissions': ['leitstelle.view']})['ok'])
F(9, 'faction_menu_close')
check('nach dem Schließen wieder kein Mitglied', F(9, 'faction_menu_open')['error'] == 'not_member')
env.command(0, f'setrank {ids[9]} assistant')
env.command(9, 'orgaview ems')
check('Assistent: nur ansehen', F(9, 'faction_rank_save', {'rank': 2, 'name': 'x', 'permissions': []})['error'] == 'no_permission'
      and F(9, 'faction_members')['ok'])
env.command(0, f'removeorga {ids[5]} Test')
check('/removeorga: ins Archiv als admin', member(ids[5]) is None and F(1, 'faction_archive', {})['data']['entries'][0]['kind'] == 'admin')

print('Divisionen')
env.command(0, f'setorga {ids[3]} ems 18')
env.command(0, f'setorga {ids[4]} ems 5')
D = lambda src, data: F(src, 'faction_division_save', data)
check('Leader legt Highcommand an (26 bis 30)', D(1, {'name': 'Highcommand', 'minRank': 26, 'maxRank': 30})['ok'])
check('Vice legt Command an (15 bis 25)', D(2, {'name': 'Command', 'minRank': 15, 'maxRank': 25})['ok'])
r = D(1, {'name': 'Supervisor', 'minRank': 10, 'maxRank': 15})
check('Überschneidung mit Command: abgelehnt', r['error'] == 'division_overlap', r)
check('Rang 18 (Mira) darf keine anlegen', D(3, {'name': 'Officer', 'minRank': 1, 'maxRank': 9})['error'] == 'no_permission')
check('falscher Bereich (von > bis): invalid_ranks', D(1, {'name': 'X', 'minRank': 9, 'maxRank': 3})['error'] == 'invalid_ranks')
for name, lo, hi in (('Supervisor', 10, 14), ('Officer', 5, 9), ('Anwärter', 1, 4)):
    D(1, {'name': name, 'minRank': lo, 'maxRank': hi})
check('sechste Division: limit_reached', D(1, {'name': 'Extra', 'minRank': 1, 'maxRank': 1})['error'] == 'limit_reached')
dv = F(3, 'faction_divisions')['data']
by = {d['name']: [m['name'] for m in d['members']] for d in dv['divisions']}
check('Mitglieder pro Division (Highcommand: Lena, Jonas; Command: Mira; Officer: Tom)',
      by.get('Highcommand') == ['Lena Hoffmann', 'Jonas Weber'] and by.get('Command') == ['Mira Schulz'] and by.get('Officer') == ['Tom Becker'], by)
check('Mira darf ansehen, aber nicht bearbeiten', dv['canEdit'] is False)
ov = F(1, 'faction_menu_open')['data']
summary = {d['name']: d['count'] for d in ov['divisions']}
check('Übersicht: 4 Mitglieder, Anzahl pro Division', ov['counts']['members'] == 4 and summary['Highcommand'] == 2 and summary['Command'] == 1, (ov['counts'], summary))
check('Übersicht: Logo und Farben der Organisation', ov['org']['logo'] == 'logos/ems.png' and ov['org']['theme']['mark'] == '237 28 36')
anw = [d for d in dv['divisions'] if d['name'] == 'Anwärter'][0]
check('Division umbenennen', D(1, {'id': anw['id'], 'name': 'Anwärterinnen', 'minRank': 1, 'maxRank': 4})['ok'])
check('Division löschen', F(1, 'faction_division_delete', {'id': anw['id']})['ok'] and len(F(1, 'faction_divisions')['data']['divisions']) == 4)

print('Gehalt pro Rang')
def rank_row(src, rank):
    return [r for r in F(src, 'faction_ranks')['data']['ranks'] if r['rank'] == rank][0]
row = rank_row(1, 18)
r = F(1, 'faction_rank_save', {'rank': 18, 'name': row['name'], 'permissions': row['permissions'], 'salary': 500, 'tasks': 'Leitet Einsätze, bildet aus.'})
check('Leader setzt Gehalt 500 $ und Aufgaben für Rang 18', r['ok'] and rank_row(1, 18)['salary'] == 500 and rank_row(1, 18)['tasks'] == 'Leitet Einsätze, bildet aus.', r)
check('Rangname und Rechte bleiben', rank_row(1, 18)['name'] == row['name'] and rank_row(1, 18)['permissions'] == row['permissions'])
check('über 1.000 $: invalid_salary', F(1, 'faction_rank_save', {'rank': 18, 'name': row['name'], 'permissions': row['permissions'], 'salary': 1500})['error'] == 'invalid_salary')
top = rank_row(2, 30)
check('Vice darf das Gehalt des Leaders nicht setzen', F(2, 'faction_rank_save', {'rank': 30, 'name': top['name'], 'permissions': top['permissions'], 'salary': 1000})['error'] == 'no_permission')
env.sql("UPDATE faction_settings SET balance = 5000 WHERE faction = 'ems'")
fac.execute(f'Factions.SetDuty(3, true)')
bank = lambda src: env.to_py(env.lua.eval(f"Core.GetMoney({src}, 'bank')"))
b0 = bank(3)
fac.execute('Factions.PaySalary(3, "ems")')
env.tick(100)
check('Gehalt: 500 $ aus der Kasse aufs Konto', bank(3) == b0 + 500 and env.to_py(fac.eval("Factions.GetBalance('ems')")) == 4500, (bank(3), b0))
env.sql("UPDATE faction_settings SET balance = 100 WHERE faction = 'ems'")
fac.execute('Factions.PaySalary(3, "ems")')
check('Kasse reicht nicht: kein Gehalt, Hinweis', bank(3) == b0 + 500 and any('Kasse' in t for t in notes(3)))
fac.execute('Factions.ForgetPay(3)')
env.sql("UPDATE faction_settings SET balance = 5000 WHERE faction = 'ems'")
env.tick(60 * 60 * 1000 + 1000)
check('nach 60 Minuten im Dienst automatisch', bank(3) == b0 + 1000, bank(3) - b0)
fac.execute('Factions.SetDuty(3, false)')

print('Bonus')
env.sql("UPDATE faction_settings SET balance = 5000 WHERE faction = 'ems'")
B = lambda src, data: F(src, 'faction_member_bonus', data)
b0 = bank(3)
r = B(1, {'characterId': ids[3], 'amount': 800, 'reason': 'Gute Arbeit beim Großeinsatz'})
check('Leader zahlt Mira 800 $ Bonus', r['ok'] and bank(3) == b0 + 800 and env.to_py(fac.eval("Factions.GetBalance('ems')")) == 4200, r)
check('Mira bekommt eine Meldung', any('Bonus' in t and '800' in t for t in notes(3)))
check('zweiter Bonus am selben Tag: bonus_today', B(2, {'characterId': ids[3], 'amount': 100})['error'] == 'bonus_today')
check('über 1.000 $: invalid_amount', B(1, {'characterId': ids[4], 'amount': 1200})['error'] == 'invalid_amount')
check('Mira (Rang 18) darf keinen Bonus zahlen', B(3, {'characterId': ids[4], 'amount': 100})['error'] == 'no_permission')
check('sich selbst: no_permission', B(1, {'characterId': ids[1], 'amount': 100})['error'] == 'no_permission')
env.sql("UPDATE faction_settings SET balance = 50 WHERE faction = 'ems'")
check('Kasse zu leer: not_enough_money', B(1, {'characterId': ids[4], 'amount': 100})['error'] == 'not_enough_money')
check('dann ist der Tag nicht verbraucht', member(ids[4])['last_bonus_at'] is None)
env.sql("UPDATE faction_settings SET balance = 5000 WHERE faction = 'ems'")
r = B(1, {'characterId': ids[4], 'amount': 250})
check('Bonus an Tom', r['ok'], r)
rows = {m['name']: m for m in F(1, 'faction_members')['data']['members']}
check('Leitstelle: Bonus heute, Division, Einstellungsdatum', rows['Mira Schulz'].get('bonusToday') is True and rows['Mira Schulz']['division'] == 'Command' and rows['Mira Schulz']['hiredAt'])
check('Leitstelle: Mira nie befördert, kein Uprank-Datum', rows['Mira Schulz'].get('lastPromotedAt') is None)
F(1, 'faction_member_rank', {'characterId': ids[4], 'rank': 6})
tom = [m for m in F(1, 'faction_members')['data']['members'] if m['name'] == 'Tom Becker'][0]
check('Tom befördert: letzter Uprank heute', tom.get('lastPromotedAt') == tom['hiredAt'], tom)
check('Leitstelle: Bonus-Recht nur für Leitung', F(1, 'faction_members')['data']['edit'].get('bonus') is True and not F(3, 'faction_members')['data']['edit'].get('bonus'))

print('Erklärungen')
I = lambda src, data: F(src, 'faction_info_save', data)
r = I(1, {'category': 'rules', 'title': 'Funkdisziplin', 'body': 'Kurz und klar funken. Statusmeldungen immer mit Dienstnummer.'})
check('Leader legt eine Regel an', r['ok'] and r['data']['sections'][0]['title'] == 'Funkdisziplin', r)
check('Vice legt einen Ablauf an', I(2, {'category': 'process', 'title': 'Einstellung', 'body': 'Bewerbung, Gespräch, Probetag.'})['ok'])
check('unbekannter Bereich: invalid_input', I(1, {'category': 'xyz', 'title': 'a', 'body': 'b'})['error'] == 'invalid_input')
check('Mira darf nichts anlegen', I(3, {'category': 'rules', 'title': 'a', 'body': 'b'})['error'] == 'no_permission')
exams = F(1, 'faction_ranks')['data']['exams']
r = F(1, 'faction_exam_save', {'id': exams[0]['id'], 'name': exams[0]['name'], 'description': 'Theorie und Praxis zur Herz-Lungen-Wiederbelebung.'})
check('Prüfung bekommt eine Beschreibung', r['ok'], r)
info = F(3, 'faction_info')['data']
check('Mira liest: Regeln, Abläufe, Prüfungen mit Beschreibung', len(info['sections']) == 2 and info['exams'][0]['description'].startswith('Theorie') and info['canEdit'] is False, info['sections'])
r18 = [r for r in info['ranks'] if r['rank'] == 18][0]
r1 = [r for r in info['ranks'] if r['rank'] == 1][0]
check('Rang 18: Aufgaben und Gehalt', r18['tasks'] == 'Leitet Einsätze, bildet aus.' and r18['salary'] == 500)
check('Rang 1 schaltet "Leitstelle ansehen" frei', 'Leitstelle ansehen' in r1['newPermissions'], r1)
sec = info['sections'][0]
check('Abschnitt bearbeiten', I(1, {'id': sec['id'], 'category': sec['category'], 'title': sec['title'], 'body': 'Neu.'})['ok'])
check('Abschnitt löschen', F(1, 'faction_info_delete', {'id': sec['id']})['ok'] and len(F(1, 'faction_info')['data']['sections']) == 1)

print('Protokolle')
env.tick(200)
P = lambda src, data=None: F(src, 'faction_logs', data or {})
r = P(1)
check('Leader sieht Protokolle, Bereiche als Filter', r['ok'] and len(r['data']['entries']) > 0 and len(r['data']['areas']) == 6, r.get('error'))
check('Mira (Rang 18) ohne Recht logs.view: no_permission', P(3)['error'] == 'no_permission')
check('Übersicht: Tab Protokolle nur mit Recht', F(1, 'faction_menu_open')['data']['access']['logs'] is True and not F(3, 'faction_menu_open')['data']['access']['logs'])
tom = P(1, {'characterId': ids[4]})['data']
texts = [e['text'] for e in tom['entries']]
check('Tom: Einstellung, Beförderung, Bonus, Entlassung', any(t.startswith('Eingestellt') for t in texts) and any(t.startswith('Befördert') for t in texts)
      and any(t.startswith('Bonus 250') for t in texts) and any(t.startswith('Entlassen') for t in texts), texts)
check('Tom: Name zur ID', tom['person'] == {'id': ids[4], 'name': 'Tom Becker'}, tom.get('person'))
promo = [e for e in tom['entries'] if e['text'].startswith('Befördert')][0]
check('Beförderung: wer (mit ID) und wen', promo['actor']['id'] == ids[1] and promo['target']['id'] == ids[4] and promo['area'] == 'leitstelle', promo)
mine = P(1, {'characterId': ids[1], 'role': 'actor'})['data']['entries']
check('Nur was Lena selbst gemacht hat', mine and all(e['actor']['id'] == ids[1] for e in mine))
about = P(1, {'characterId': ids[3], 'role': 'target'})['data']['entries']
check('Nur was Mira betrifft', about and all(e['target']['id'] == ids[3] for e in about))
an = P(1, {'area': 'anpassung'})['data']['entries']
check('Filter Anpassung: Rang mit Gehalt, Division, Erklärung', all(e['area'] == 'anpassung' for e in an)
      and any(e['text'].startswith('Rang 18') and 'Gehalt' in e['text'] for e in an) and any(e['text'].startswith('Division') for e in an)
      and any(e['text'].startswith('Erklärung') for e in an), [e['text'] for e in an])
duty = P(1, {'characterId': ids[3], 'area': 'dienst'})['data']['entries']
check('Dienst an und aus', any(e['text'] == 'Dienst angetreten' for e in duty) and any(e['text'].startswith('Dienst beendet') for e in duty), [e['text'] for e in duty])
kasse = P(1, {'area': 'kasse'})['data']['entries']
check('Kasse: Gehalt ohne Handelnden, mit Empfänger', any(e['text'].startswith('Gehalt') and e.get('actor') is None and e['target']['id'] == ids[3] for e in kasse), kasse[:3])
lst = [e['text'] for e in P(1, {'area': 'leitstelle'})['data']['entries']]
check('Leitstelle: Strikes, Prüfungen, Dienstnummer', any(t.startswith('Strikes von') for t in lst) and any('Prüfung eingetragen' in t for t in lst)
      and any(t.startswith('Dienstnummer von') for t in lst), lst)
fac.execute('Config.Factions.Protocol.PageSize = 3')
p1 = P(1)['data']
p2 = P(1, {'before': p1['next']})['data']
check('Seiten: 3 pro Seite, weiter mit "mehr"', len(p1['entries']) == 3 and p1['more'] and p2['entries'] and p2['entries'][0]['id'] < p1['entries'][-1]['id'])
fac.execute('Config.Factions.Protocol.PageSize = 50')

print('Admin: Archiv korrigieren')
env.command(0, f'setrank {ids[9]} chief')
env.command(9, 'orgaview ems')
arch = F(9, 'faction_archive', {'page': 1})['data']
check('Admin mit factions.manage darf das Archiv korrigieren', arch.get('canEdit') is True and not F(1, 'faction_archive', {})['data'].get('canEdit'))
entry = arch['entries'][0]
check('Leader darf nicht korrigieren', F(1, 'faction_archive_update', {'id': entry['id'], 'hidden': True})['error'] == 'no_permission')
check('Grund korrigieren', F(9, 'faction_archive_update', {'id': entry['id'], 'reason': 'Unentschuldigt gefehlt'})['ok']
      and F(9, 'faction_archive', {})['data']['entries'][0]['reason'] == 'Unentschuldigt gefehlt')
check('ausblenden', F(9, 'faction_archive_update', {'id': entry['id'], 'hidden': True})['ok'])
check('Leader sieht ihn nicht mehr', all(e['id'] != entry['id'] for e in F(1, 'faction_archive', {})['data']['entries']))
seen = [e for e in F(9, 'faction_archive', {})['data']['entries'] if e['id'] == entry['id']]
check('Admin sieht ihn markiert', seen and seen[0]['hiddenBy'].startswith('Admin'), seen)
check('noch in der Datenbank', env.sql('SELECT COUNT(*) AS n FROM faction_archive WHERE id = %s', (entry['id'],))[0]['n'] == 1)
check('wieder zeigen', F(9, 'faction_archive_update', {'id': entry['id'], 'hidden': False})['ok']
      and any(e['id'] == entry['id'] for e in F(1, 'faction_archive', {})['data']['entries']))
env.tick(100)
adm = [e for e in P(1, {'characterId': entry['characterId']})['data']['entries'] if e['text'].startswith('Archiv')]
check('im Protokoll als Admin', len(adm) == 3 and all(e.get('admin') for e in adm), adm)
check('Admin sieht die Protokolle (factions.view)', P(9)['ok'])
F(9, 'faction_menu_close')

print('Log')
env.flush_log()
actions = {r['action'] for r in env.sql("SELECT action FROM audit_log WHERE category = 'faction'")}
check('Einstellen, Rang, Entlassen, Kasse, Dienst, Bonus, Divisionen, Erklärungen geloggt', {'hire', 'rank', 'fire', 'cash_in', 'cash_out', 'duty_on', 'rank_settings', 'bonus', 'division_save', 'info_save'} <= actions, actions)

print(f'\n{ok} ok, {fail} Fehler')
sys.exit(1 if fail else 0)
