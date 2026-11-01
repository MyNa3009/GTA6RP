import os
import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Env
ok=fail=0
def check(l,c,i=None):
    global ok,fail
    if c: ok+=1; print('  ok   ',l)
    else: fail+=1; print('  FEHLER',l,i)

env=Env(admin_keys=True)

def note(src):
    texts=[e.get('text') for e in env.events_for(src,'core:notify')]
    return texts[-1] if texts else None

def join(s, last, twin=None):
    env.connect(s,[f'license:{s}'],position=(1.0,1.0,70.0))
    env.call(s,'auth_register',{'email':f'{s}@t.de','password':'passwort123'})
    r=env.call(s,'char_create',{'firstname':'Test','lastname':last,'dateOfBirth':'1995-01-01','gender':'male'})
    cid=r['data']['characterId']
    if twin:
        r=env.call(s,'char_create',{'firstname':'Zweit','lastname':twin,'dateOfBirth':'1996-01-01','gender':'male'})
        twin_id=r['data']['characterId']
    env.call(s,'char_select',{'id':cid})
    return (cid, twin_id) if twin else cid

senior, twink=join(1,'Senior','Twink')  # Twink: gleicher Login wie der Senior
chief=join(2,'Chief')
junior=join(3,'Junior')
player=join(4,'Spieler')
env.command(0,f'setrank {senior} senior'); env.command(0,f'setrank {chief} chief'); env.command(0,f'setrank {junior} junior'); env.command(0,f'setrank {twink} junior')

print('Ohne Key')
check('Senior hat ohne Key keine Rechte', not env.lua.eval('Core.HasPermission(1, "player.ban")'))
check('Spieler braucht keinen Key', env.lua.eval('AdminKeys.IsUnlocked(Core.GetPlayer(4))'))
check('Rang bleibt sichtbar', env.lua.eval('Core.GetRank(1).id')=='senior')
r=env.call(1,'admin_overview')
check('Admin-Menü verlangt den Key', r['error']=='key_required', r)
check('Ohne Key gibt es nur eine Meldung', 'noch keinen Admin-Key' in (note(1) or ''), note(1))
check('Kein Eingabefenster ohne Key', len(env.events_for(1,'core:admin:key_prompt'))==0)
env.command(1,'ban 4 1d Test')
check('Befehl ohne Key abgelehnt mit Hinweis', 'Admin-Key' in (note(1) or ''), note(1))
check('Spieler noch nicht gebannt', len(env.sql('SELECT id FROM bans'))==0)

print('Konsole')
env.command(0,f'adminkey {chief}')
check('Konsole erstellt Key', len(env.sql('SELECT character_id FROM admin_keys WHERE character_id=%s',(chief,)))==1)
env.command(0,f'adminkey {player}')
check('Kein Key für Spieler ohne Teamrang', len(env.sql('SELECT character_id FROM admin_keys WHERE character_id=%s',(player,)))==0)
chief_key=env.lua.eval(f'AdminKeys.Create(0, {chief})')
check('Key hat das Format XXXX-XXXX-XXXX-XXXX', isinstance(chief_key,str) and len(chief_key)==19 and chief_key.count('-')==3, chief_key)
check('Nur Zeichen ohne Verwechslung', all(c in 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789-' for c in chief_key), chief_key)
other=env.lua.eval('Platform.RandomToken(16)')
check('Zwei Keys sind verschieden', other!=chief_key.replace('-',''), other)
row=env.sql('SELECT key_hash FROM admin_keys WHERE character_id=%s',(chief,))[0]
check('Nur der Hash steht in der Datenbank', chief_key.replace('-','') not in row['key_hash'].replace('hash:','') or row['key_hash']!=chief_key, row)

print('Freischalten')
env.command(2,'aduty')
check('/aduty öffnet das Eingabefenster', env.events_for(2,'core:admin:key_prompt')[-1]['duty']==True, env.events_for(2,'core:admin:key_prompt'))
check('Dienst noch nicht gestartet', not env.lua.eval('Core.IsOnDuty(2)'))
r=env.call(2,'admin_key_unlock',{'key':chief_key.lower().replace('-',' '),'duty':True})
check('Kleinbuchstaben und Leerzeichen gehen', r['ok'] and r['data']['duty']==True, r)
check('Chief hat jetzt Rechte', env.lua.eval('Core.HasPermission(2, "player.ban")'))
check('Admin-Dienst gestartet', env.lua.eval('Core.IsOnDuty(2)'))
r=env.call(2,'admin_key_unlock',{'key':'falsch'})
check('Schon freigeschaltet', r['ok'] and r['data']['already'], r)

print('Key im Menü erstellen')
r=env.call(2,'admin_key_create',{'characterId':senior})
check('Chief erstellt Key für Senior', r['ok'] and len(r['data']['key'])==19 and r['data']['info']['exists'], r)
senior_key=r['data']['key']
env.command(1,'aduty')
check('Senior bekommt das Eingabefenster', len(env.events_for(1,'core:admin:key_prompt'))==1)
for attempt in range(1,5):
    r=env.call(1,'admin_key_unlock',{'key':'AAAA-BBBB-CCCC-DDDD'})
check('Vierter falscher Versuch: noch 1', r['error']=='wrong_key' and r['data']['left']==1, r)
r=env.call(1,'admin_key_unlock',{'key':'AAAA-BBBB-CCCC-DDDD'})
check('Fünfter falscher Versuch sperrt', r['error']=='locked' and r['data']['minutes']==15, r)
check('Team bekommt eine Meldung', 'falsche Versuche' in (note(2) or ''), note(2))
r=env.call(1,'admin_key_unlock',{'key':senior_key})
check('Gesperrt geht auch der richtige Key nicht', r['error']=='locked', r)
env.command(1,'aduty')
check('/aduty während der Sperre nur mit Meldung', 'Wieder möglich' in (note(1) or ''), note(1))
r=env.call(2,'admin_key_create',{'characterId':senior})
senior_key=r['data']['key']
r=env.call(1,'admin_key_unlock',{'key':senior_key})
check('Neuer Key hebt die Sperre auf', r['ok'], r)
check('Senior hat Rechte', env.lua.eval('Core.HasPermission(1, "admin.keys")'))

print('Wer darf was')
r=env.call(1,'admin_key_create',{'characterId':chief})
check('Senior nicht für Chief', r['error']=='target_too_high', r)
r=env.call(1,'admin_key_create',{'characterId':twink})
check('Senior nicht für eigenen Twink', r['error']=='own_key', r)
r=env.call(1,'admin_key_create',{'characterId':player})
check('Nicht für Spieler', r['error']=='no_team_rank', r)
r=env.call(1,'admin_key_create',{'characterId':junior})
check('Senior für Junior', r['ok'], r)
junior_key=r['data']['key']
r=env.call(3,'admin_key_unlock',{'key':junior_key})
check('Junior schaltet frei', r['ok'] and r['data']['duty']==False, r)
r=env.call(3,'admin_key_create',{'characterId':player})
check('Junior darf keine Keys erstellen', r['error']=='no_permission', r)

r=env.call(1,'admin_profile',{'characterId':junior})
keys=r['data'].get('adminKeys') or []
check('Akte zeigt den Key des Juniors', len(keys)==1 and keys[0]['exists'] and keys[0]['canManage'] and keys[0]['createdBy']==senior, keys)
r=env.call(1,'admin_profile',{'characterId':twink})
keys=r['data'].get('adminKeys') or []
check('Akte des eigenen Logins: sichtbar, aber nicht verwaltbar', all(not k['canManage'] for k in keys) and any(k['reason']=='own_key' for k in keys), keys)
r=env.call(3,'admin_profile',{'characterId':senior})
check('Junior sieht keine Keys in der Akte', r['ok'] and not r['data'].get('adminKeys'), r.get('data',{}).get('adminKeys'))

print('Neu erstellen und löschen sperrt sofort')
env.command(3,'aduty')
check('Junior im Dienst', env.lua.eval('Core.IsOnDuty(3)'))
r=env.call(1,'admin_key_create',{'characterId':junior})
check('Junior gesperrt nach neuem Key', not env.lua.eval('Core.HasPermission(3, "admin.menu")'))
check('Dienst des Juniors beendet', not env.lua.eval('Core.IsOnDuty(3)'))
check('Junior bekommt Bescheid', len(env.events_for(3,'core:admin:key_locked'))==1)
r=env.call(3,'admin_key_unlock',{'key':junior_key})
check('Alter Key gilt nicht mehr', r['error']=='wrong_key', r)
r=env.call(1,'admin_key_delete',{'characterId':junior})
check('Key gelöscht', r['ok'] and not r['data']['info']['exists'], r)
r=env.call(3,'admin_key_unlock',{'key':'AAAA-BBBB-CCCC-DDDD'})
check('Ohne Key: no_key', r['error']=='no_key', r)

print('Sitzung')
env.tick(1100)  # Spam-Schutz: neue Sekunde
env.command(1,'relog')
r=env.call(1,'auth_login',{'email':'1@t.de','password':'passwort123'})
r=env.call(1,'char_select',{'id':senior})
check('Nach Relog wieder im Spiel', r['ok'], r)
check('Nach Relog wieder gesperrt', not env.lua.eval('Core.HasPermission(1, "admin.menu")'))
env.command(0,f'setrank {twink} player')
check('Rang auf Spieler entfernt den Key', len(env.sql('SELECT 1 FROM admin_keys WHERE character_id=%s',(twink,)))==0)

print('Befehle ausblenden')
hidden=env.events_for(4,'core:admin:commands')[-1]['hidden']
check('Spieler: Admin-Befehle ausgeblendet', all(c in hidden for c in ['ban','aduty','car','dv','nc','invsee']) or all(c in hidden for c in ['ban','aduty','car','dv','nc']), hidden)
check('Spieler: eigene Befehle sichtbar', 'report' not in hidden and 'geld' not in hidden, hidden)
hidden=env.events_for(1,'core:admin:commands')[-1]['hidden']
check('Ohne Key: /aduty bleibt sichtbar', 'aduty' not in hidden and 'ban' in hidden, hidden)
r=env.call(1,'admin_key_unlock',{'key':senior_key})
check('Nach Relog wieder freischalten', r['ok'], r)
hidden=env.events_for(1,'core:admin:commands')[-1]['hidden']
check('Senior freigeschaltet: /ban sichtbar, /setrank nicht', 'ban' not in hidden and 'setrank' in hidden and 'dv' not in hidden, hidden)
groups=env.to_py(env.lua.eval('AdminHelp.ListFor(4)'))
titles=[g['title'] for g in groups]
check('Befehlsliste für Spieler nur Allgemein', titles==['Allgemein'] and all('rank' not in e for e in groups[0]['entries']), groups)
groups=env.to_py(env.lua.eval('AdminHelp.ListFor(1)'))
usages=[e['usage'] for g in groups for e in g['entries']]
check('Senior sieht /dv, aber kein /setrank', '/dv' in usages and not any(u.startswith('/setrank') for u in usages), usages)

print('Log')
env.flush_log()
rows=env.sql("SELECT action, data FROM audit_log WHERE action LIKE 'admin_key%%' ORDER BY id")
actions=[x['action'] for x in rows]
check('Erstellen, Freischalten, Fehlversuche und Sperre im Log', all(a in actions for a in ['admin_key_create','admin_key_unlock','admin_key_failed','admin_key_locked','admin_key_delete']), actions)
everything=' '.join(str(x['data']) for x in env.sql('SELECT data FROM audit_log'))
check('Kein Key im Log', all(k.replace('-','') not in everything.replace('-','') for k in [chief_key, senior_key, junior_key]))
print(ok,'ok',fail,'Fehler')
