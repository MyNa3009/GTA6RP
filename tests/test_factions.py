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

print('Log')
env.flush_log()
actions = {r['action'] for r in env.sql("SELECT action FROM audit_log WHERE category = 'faction'")}
check('Einstellen, Rang, Entlassen, Kasse, Dienst geloggt', {'hire', 'rank', 'fire', 'cash_in', 'cash_out', 'duty_on', 'rank_settings'} <= actions, actions)

print(f'\n{ok} ok, {fail} Fehler')
sys.exit(1 if fail else 0)
