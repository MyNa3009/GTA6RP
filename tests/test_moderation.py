import os
import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Env
ok=fail=0
def check(l,c,i=None):
    global ok,fail
    if c: ok+=1; print('  ok   ',l)
    else: fail+=1; print('  FEHLER',l,i)
def notes(env, src): return [(d['text'], d['type'], d.get('duration')) for s,n,d in env.events if s==src and n=='core:notify']
env=Env()
for s in (1,2,3):
    env.connect(s,[f'license:{s}'])
    env.call(s,'auth_register',{'email':f'{s}@t.de','password':'passwort123'})
    r=env.call(s,'char_create',{'firstname':'Test','lastname':'Nummer'+'abc'[s-1],'dateOfBirth':'1995-01-01','gender':'male'})
    env.call(s,'char_select',{'id':r['data']['characterId']})
env.command(0,'setrank 1 serveradmin'); env.command(0,'setrank 3 junior')
env.command(1,'aduty'); env.command(3,'aduty')

print('Notify')
env.command(1,'warn 2')
check('Benutzung als Hinweis', notes(env,1)[-1][1]=='info' and 'Benutzung' in notes(env,1)[-1][0], notes(env,1)[-1])

print('Verwarnen')
env.command(3,'warn 2 Test')
check('Junior darf nicht verwarnen', notes(env,3)[-1][1]=='error', notes(env,3)[-1])
env.command(1,'warn 2 RDM am Würfelpark')
check('Admin verwarnt, Erfolg', notes(env,1)[-1][1]=='success' and 'Warn-ID' in notes(env,1)[-1][0], notes(env,1)[-1])
w=[n for n in notes(env,2) if n[1]=='warning']
check('Spieler sieht Verwarnung sofort, lange', len(w)==1 and 'RDM' in w[0][0] and w[0][2]==20000, w)
row=env.sql('SELECT * FROM warns')[0]
check('Warn gespeichert und als gesehen markiert', row['seen_at'] is not None and row['character_id']==2, row)
# offline verwarnen
env.command(2,'relog')
env.command(1,'warn 2 Offline-Verwarnung Test')
check('Offline: Hinweis an Admin', 'nächsten Spielen' in notes(env,1)[-1][0], notes(env,1)[-1])
before=len([n for n in notes(env,2) if n[1]=='warning'])
env.call(2,'auth_login',{'email':'2@t.de','password':'passwort123'})
env.call(2,'char_select',{'id':2})
env.tick(5000)
after=[n for n in notes(env,2) if n[1]=='warning']
check('Beim Spielen nachgeliefert', len(after)==before+1 and 'Offline-Verwarnung' in after[-1][0], after)
check('Danach gesehen', env.sql('SELECT COUNT(*) n FROM warns WHERE seen_at IS NULL')[0]['n']==0)
r=env.call(1,'admin_profile',{'characterId':2})
p=r['data']['punishments']
check('Akte: 2 Verwarnungen offen', len(p['warns'])==2 and p['activeWarns']['2']==2, p.get('activeWarns'))
r=env.call(1,'admin_punish',{'type':'unwarn','accountId':2,'warnId':p['warns'][0]['id'],'reason':'Fehler'})
check('Zurücknehmen über Menü', r['ok'] and r['data']['punishments']['activeWarns']['2']==1, r)
env.command(1,'warn 2 Wieder zwei')
check('Nach Zurücknehmen kein Ban bei 2', 'gebannt' not in notes(env,1)[-1][0], notes(env,1)[-1])
r=env.call(1,'admin_punish',{'type':'unwarn','accountId':3,'warnId':p['warns'][1]['id']})
check('Falsche Akte abgelehnt', r['error']=='warn_not_found', r)
env.command(1,f"unwarn {p['warns'][1]['id']} Einspruch")
check('/unwarn', notes(env,1)[-1][1]=='success', notes(env,1)[-1])
env.sql("UPDATE warns SET created_at = DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 100 DAY) WHERE revoked_at IS NULL")
r=env.call(1,'admin_profile',{'characterId':2})
check('Nach 90 Tagen nicht mehr aktiv', not r['data']['punishments']['activeWarns'].get('2'), r['data']['punishments']['activeWarns'])
r=env.call(1,'admin_punish',{'type':'warn','accountId':2,'characterId':2,'reason':'Über Menü'})
check('Verwarnen über Menü', r['ok'] and r['data']['punishments']['activeWarns']['2']==1, r.get('error'))

print('Kick')
env.command(3,'kick 2 Test')
check('Junior darf nicht kicken', notes(env,3)[-1][1]=='error', notes(env,3)[-1])
env.command(1,'kick 3 Test')
check('Junior ist niedriger: Kick geht', notes(env,1)[-1][1]=='success', notes(env,1)[-1])
check('Kick-Text mit Rang', env.dropped and 'gekickt' in env.dropped[-1][1] and 'Server Administrator' in env.dropped[-1][1], env.dropped[-1:])
env.command(1,'kick 2 x')
check('Grund zu kurz', notes(env,1)[-1][1]=='error', notes(env,1)[-1])
r=env.call(1,'admin_punish',{'type':'kick','accountId':2,'characterId':2,'reason':'Über Menü gekickt'})
check('Kick über Menü', r['ok'] and 'Über Menü' in env.dropped[-1][1], r)
env.command(1,'kick 2 Nochmal')
check('Offline nicht kickbar', 'Niemand' in notes(env,1)[-1][0], notes(env,1)[-1])
# Login ohne Charakter kicken
env.connect(5,['license:2'])
r=env.call(1,'admin_punish',{'type':'kick','accountId':2,'reason':'Im Login gekickt'})
check('Im Login ohne Charakter: Kick über Login klappt nicht ohne Login', not r['ok'], r)

print('Spam-Schutz')
env.connect(6,['license:spam'])
res=[env.call(6,'auth_status') for _ in range(25)]
limited=[x for x in res if x and x.get('error')=='rate_limited']
check('Über 20 pro Sekunde abgelehnt', len(limited)>0, len(limited))
env.flush_log()
check('Einmal geloggt', env.sql("SELECT COUNT(*) n FROM audit_log WHERE action='rate_limited'")[0]['n']==1)
env.tick(1500)
check('Nach einer Sekunde wieder frei', env.call(6,'auth_status')['ok'])
env.flush_log()
rows=env.sql("SELECT action FROM audit_log WHERE category='punishment' AND action IN ('warn','unwarn','kick')")
check('Warn, Unwarn, Kick im Log', {x['action'] for x in rows}=={'warn','unwarn','kick'}, rows)
print(ok,'ok',fail,'Fehler')
