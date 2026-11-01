import os
import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Env
ok=fail=0
def check(l,c,i=None):
    global ok,fail
    if c: ok+=1; print('  ok   ',l)
    else: fail+=1; print('  FEHLER',l,i)
def notes(env, src):
    return [d['text'] for s,n,d in env.events if s==src and n=='core:notify']
def colors(env, src):
    return [d.get('type') for s,n,d in env.events if s==src and n=='core:notify']

env=Env()
PC_A=['2:aaa1','3:aaa2','4:aaa3']; PC_B=['2:bbb1','3:bbb2']; PC_C=['2:ccc1']
env.connect(1,['license:admin'],tokens=['2:adm'],ip='10.0.0.1')
env.call(1,'auth_register',{'email':'admin@t.de','password':'passwort123'})
r=env.call(1,'char_create',{'firstname':'Fabian','lastname':'Nandes','dateOfBirth':'1995-01-01','gender':'male'})
env.call(1,'char_select',{'id':r['data']['characterId']})
env.command(0,'setrank 1 chief')

print('Accountsharing')
env.connect(2,['license:lena'],tokens=PC_A,ip='1.1.1.1')
env.call(2,'auth_register',{'email':'lena@t.de','password':'passwort123'})
check('Erster PC: keine Warnung', env.sql('SELECT COUNT(*) n FROM device_alerts')[0]['n']==0)
env.command(2,'relog'); env.call(2,'auth_login',{'email':'lena@t.de','password':'passwort123'})
check('Gleicher PC: keine Warnung', env.sql('SELECT COUNT(*) n FROM device_alerts')[0]['n']==0)
env.lua.execute('DropPlayer(2, "weg")')
env.connect(3,['license:freund'],tokens=PC_B,ip='1.1.1.1')
r=env.call(3,'auth_login',{'email':'lena@t.de','password':'passwort123'})
check('Login am fremden PC klappt', r['ok'], r)
alerts=env.sql('SELECT * FROM device_alerts')
check('Warnung angelegt, IP bekannt', len(alerts)==1 and alerts[0]['ip_known']==1, alerts)
n=notes(env,1)
check('Admins bekommen rote Chat-Meldung', any('neuen PC' in x for x in n) and colors(env,1)[-1]=='warning', n[-2:])
r=env.call(1,'admin_profile',{'accountId':2})
d=r['data']['devices']
check('Akte: 2 Geräte, Warnung aktiv, IPs sichtbar (Chief)', d['deviceCount']==2 and d['alerts'][0]['active'] and d['ips'] and d['alerts'][0]['ip']=='1.1.1.1', d)
r=env.call(1,'admin_overview')
check('Warnungen zählen Geräte mit', r['data']['warningCount']>=1, r['data']['warningCount'])
r=env.call(1,'admin_warnings')
check('Warnungen-Liste enthält Gerät', len(r['data']['devices'])==1 and r['data']['devices'][0]['accountId']==2, r['data'])
aid=alerts[0]['id']
r=env.call(1,'admin_device_alert',{'accountId':2,'alertId':aid,'dismissed':True})
check('Warnung ausgeblendet', r['ok'] and not r['data']['devices']['alerts'][0]['active'], r)

print('Hardware-Multi-Account')
env.connect(4,['license:zweit'],tokens=['2:aaa1','9:neu'],ip='2.2.2.2')
r=env.call(4,'auth_register',{'email':'zweit@t.de','password':'passwort123'})
links=env.sql("SELECT * FROM account_links WHERE identifier_type='hardware'")
check('Gleicher PC, anderer Login: Multi-Account hardware', len(links)==1 and {links[0]['account_a'],links[0]['account_b']}=={2,3}, links)

print('Ban über Hardware')
env.command(1,'aduty')
r=env.call(3,'char_create',{'firstname':'Lena','lastname':'Wojcik','dateOfBirth':'1995-01-01','gender':'female'})
lena=r['data']['characterId']
env.command(1,f'loginban {lena} 7d Cheating')
msg=env.connect(5,['license:ganzneu'],tokens=['3:bbb2'])
check('Neue Lizenz, gebannter PC: abgelehnt', msg and 'gebannt' in msg, msg)
msg=env.connect(6,['license:sauber'],tokens=['7:sauber'])
check('Anderer PC kommt rein', msg is None, msg)
env.command(0,f'loginunban {lena}')

print('Twinks')
env.connect(7,['license:lena'],tokens=PC_A)
env.call(7,'auth_login',{'email':'lena@t.de','password':'passwort123'})
r=env.call(7,'char_create',{'firstname':'Mira','lastname':'Brandt','dateOfBirth':'1996-01-01','gender':'female'})
mira=r['data']['characterId']
env.call(7,'char_select',{'id':lena})
env.lua.execute(f'TWINK_RESULT = {{ Money.TransferByCharacter({lena}, {mira}, "bank", 500, "Test") }}')
check('Twink-Überweisung erlaubt', env.lua.eval('TWINK_RESULT[1]') is not None, env.lua.eval('TWINK_RESULT[2]'))
env.flush_log()
rows=env.sql("SELECT action, amount, data FROM audit_log WHERE category='twink'")
check('Twink im Log (gleicher Login)', len(rows)==1 and rows[0]['amount']==500 and '"same_login"' in rows[0]['data'], rows)
# Fremder ohne Verbindung
env.connect(8,['license:fremd'],tokens=['5:fremd'])
env.call(8,'auth_register',{'email':'fremd@t.de','password':'passwort123'})
r=env.call(8,'char_create',{'firstname':'Otto','lastname':'Fremd','dateOfBirth':'1990-01-01','gender':'male'})
otto=r['data']['characterId']
env.lua.execute(f'Money.TransferByCharacter({lena}, {otto}, "bank", 100, "Miete")')
env.flush_log()
check('Normale Überweisung: kein Twink-Eintrag', env.sql("SELECT COUNT(*) n FROM audit_log WHERE category='twink'")[0]['n']==1)
# verknuepfter Login (Hardware, Login 4 'zweit')
r=env.call(4,'char_create',{'firstname':'Zweit','lastname':'Charakter','dateOfBirth':'1990-01-01','gender':'male'})
zweit=r['data']['characterId']
env.lua.execute(f'Money.TransferByCharacter({lena}, {zweit}, "cash", 50, "Test")')
env.flush_log()
rows=env.sql("SELECT data, target_account_id FROM audit_log WHERE category='twink' ORDER BY id DESC LIMIT 1")
check('Verknüpfter Login zählt als Twink', '"linked"' in rows[0]['data'] and rows[0]['target_account_id']==3, rows)
r=env.call(1,'admin_profile',{'accountId':2})
check('Akte: Twink-Zusammenfassung', r['data']['twinks']['total']==2 and len(r['data']['twinks']['recent'])==2, r['data']['twinks'])
r=env.call(1,'admin_profile',{'accountId':3})
check('Twink auch in der Akte des anderen Logins', r['data']['twinks']['total']==1, r['data']['twinks'])
# Block-Modus
env.lua.execute('Config.Twinks.Interactions.money_transfer = "block"')
env.lua.execute(f'BLOCK = {{ Money.TransferByCharacter({lena}, {mira}, "bank", 10, "Test") }}')
check('Block-Modus verhindert', env.lua.eval('BLOCK[2]')=='twink_blocked', env.lua.eval('BLOCK[2]'))
print(ok,'ok',fail,'Fehler')
