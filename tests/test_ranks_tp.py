import os
import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Env
ok=fail=0
def check(l,c,i=None):
    global ok,fail
    if c: ok+=1; print('  ok   ',l)
    else: fail+=1; print('  FEHLER',l,i)
def notes(env, src): return [(d['text'], d['type']) for s,n,d in env.events if s==src and n=='core:notify']
env=Env()
for s in (1,2):
    env.connect(s,[f'license:{s}'])
    env.call(s,'auth_register',{'email':f'{s}@t.de','password':'passwort123'})
r=env.call(1,'char_create',{'firstname':'Fabian','lastname':'Nandes','dateOfBirth':'1995-01-01','gender':'male'}); fab=r['data']['characterId']
r=env.call(1,'char_create',{'firstname':'Twink','lastname':'Fabian','dateOfBirth':'1995-01-01','gender':'male'}); twink=r['data']['characterId']
r=env.call(2,'char_create',{'firstname':'Lena','lastname':'Wojcik','dateOfBirth':'1995-01-01','gender':'female'}); lena=r['data']['characterId']
r=env.call(2,'char_create',{'firstname':'Mira','lastname':'Brandt','dateOfBirth':'1995-01-01','gender':'female'}); mira=r['data']['characterId']

print('Rang pro Charakter')
env.command(0,f'setrank {fab} chief')
env.call(1,'char_select',{'id':twink})
check('Twink ist kein Admin', env.lua.eval('Core.Players[1].rank')=='player' and not env.call(1,'admin_overview')['ok'])
env.command(1,'relog'); env.call(1,'auth_login',{'email':'1@t.de','password':'passwort123'})
check('In der Auswahl kein Admin', env.lua.eval('Core.Players[1].rank')=='player')
env.call(1,'char_select',{'id':fab})
check('Admin-Charakter ist Chief', env.lua.eval('Core.Players[1].rank')=='chief' and env.call(1,'admin_overview')['ok'])
env.command(1,'aduty')
env.command(1,f'setrank {twink} admin')
check('Eigenen Twink nicht befördern', 'eigenen Charaktere' in notes(env,1)[-1][0], notes(env,1)[-1])
env.command(1,f'setrank {lena} junior')
env.call(2,'char_select',{'id':lena})
check('Junior nur auf Lena', env.lua.eval('Core.Players[2].rank')=='junior')
r=env.call(1,'admin_profile',{'characterId':mira})
ranks={c['id']:c['rank'] for c in r['data']['characters']}
check('Akte: Rang je Charakter', ranks[lena]=='Junior Administrator' and ranks[mira]=='Spieler' and r['data']['account']['rank']=='Spieler', ranks)

print('Altes Login-Rang-System wird übertragen')
env.sql("UPDATE characters SET admin_rank='player' WHERE id=%s", (fab,))
env.sql("UPDATE accounts SET admin_rank='deputy' WHERE id=1")
env.sql("UPDATE characters SET last_played = NOW() WHERE id=%s", (fab,))
env.sql("UPDATE characters SET last_played = DATE_SUB(NOW(), INTERVAL 1 DAY) WHERE id=%s", (twink,))
env.lua.execute('for _, fn in ipairs(READY or {}) do CreateThread(fn) end'); env.tick(10)
rows={r['id']:r['admin_rank'] for r in env.sql('SELECT id, admin_rank FROM characters WHERE account_id=1')}
check('Zuletzt gespielter Charakter übernimmt den Rang, Twink nicht', rows[fab]=='deputy' and rows[twink]=='player', rows)
check('Login-Rang zurückgesetzt', env.sql('SELECT admin_rank FROM accounts WHERE id=1')[0]['admin_rank']=='player')
env.command(0,f'setrank {fab} chief'); env.lua.execute('Core.Players[1].rank = "chief"')

print('Teleport')
env.positions[1]=[100.0,200.0,30.0]; env.positions[2]=[-50.0,-60.0,20.0]
env.command(1,f'bring {lena}')
tp=env.events_for(2,'core:admin:teleport')
check('/bring holt Lena zum Admin', tp and abs(tp[-1]['x']-101.0)<0.01 and abs(tp[-1]['y']-200.0)<0.01, tp)
env.command(1,f'tp {lena}')
tp=env.events_for(1,'core:admin:teleport')
check('/tp ID', tp and abs(tp[-1]['x']-(-49.0))<0.01, tp)
env.command(1,'tp 215.3, -810.2, 30.7')
tp=env.events_for(1,'core:admin:teleport')
check('/tp Koordinaten mit Kommas', abs(tp[-1]['x']-215.3)<0.01 and abs(tp[-1]['y']+810.2)<0.01 and abs(tp[-1]['z']-30.7)<0.01 and not tp[-1].get('ground'), tp[-1])
env.command(1,'tp 215 -810')
tp=env.events_for(1,'core:admin:teleport')
check('/tp ohne Höhe: auf den Boden', tp[-1].get('ground') is True, tp[-1])
env.command(1,'tp 99999 5')
check('/tp außerhalb der Karte', notes(env,1)[-1][1]=='error', notes(env,1)[-1])
env.command(1,'tp 999')
check('/tp unbekannte ID', 'Niemand' in notes(env,1)[-1][0], notes(env,1)[-1])
env.command(1,'aduty')
env.command(1,'tp 1 2 3')
check('/tp ohne Dienst', 'Admin-Dienst' in notes(env,1)[-1][0], notes(env,1)[-1])
env.command(1,'aduty')

print('Warns ab Stufe 4, mit A-Jail, Auto-Ban')
env.command(0,f'setrank {fab} admin'); env.lua.execute('Core.Players[1].rank = "admin"')
env.command(1,f'warn {lena} Test')
check('Administrator (Stufe 3) darf nicht mehr verwarnen', 'keine Rechte' in notes(env,1)[-1][0], notes(env,1)[-1])
env.command(0,f'setrank {fab} serveradmin'); env.lua.execute('Core.Players[1].rank = "serveradmin"')
env.command(1,f'warn {lena} 30 RDM am Würfelpark')
check('Warn mit 30 Min A-Jail', 'A-Jail' in notes(env,1)[-1][0] and env.events_for(2,'core:jail:start'), notes(env,1)[-1])
check('Spieler sieht 1 von 3', any('(1 von 3)' in n[0] for n in notes(env,2)), notes(env,2)[-3:])
env.command(1,f'warn {lena} Zweite Verwarnung')
env.command(1,f'warn {mira} Andere Figur')
check('Mira zählt getrennt (1 von 3)', '1 von 3' in notes(env,1)[-1][0], notes(env,1)[-1])
env.command(1,f'warn {lena} Dritte Verwarnung')
check('Bei 3: automatisch gebannt', 'gebannt' in notes(env,1)[-1][0], notes(env,1)[-1])
ban=env.sql('SELECT * FROM bans WHERE character_id=%s', (lena,))
check('Charakter-Ban 7 Tage', len(ban)==1 and (ban[0]['expires_at']-ban[0]['created_at']).days==7, ban)
check('Lena zurück in die Auswahl', env.events_for(2,'core:char:return'))
check('Verwarnungen gehören zum Ban', env.sql('SELECT COUNT(*) n FROM warns WHERE character_id=%s AND ban_id=%s', (lena, ban[0]['id']))[0]['n']==3)
r=env.call(1,'admin_profile',{'characterId':lena})
p=r['data']['punishments']
check('Akte: Lena 0 offene, Mira 1', p['activeWarns'].get(str(lena),0)==0 and p['activeWarns'][str(mira)]==1, p['activeWarns'])
r=env.call(1,'admin_punish',{'type':'warn','accountId':2,'characterId':mira,'minutes':15,'reason':'Menü mit Jail'})
check('Menü: Warn mit A-Jail', r['ok'] and any(j['characterId']==mira and j['minutes']==15 for j in r['data']['punishments']['jails']), r.get('error'))
print(ok,'ok',fail,'Fehler')
