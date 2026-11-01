import os
import sys, json; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Env
ok = fail = 0
def check(l, c, i=None):
    global ok, fail
    if c: ok += 1; print('  ok   ', l)
    else: fail += 1; print('  FEHLER', l, i)
def items(state):
    return {e['slot']: e for e in state['items']}
def call(src, name, data):
    env.tick(100)
    return env.icall(src, name, data)
outfits = lambda src: env.events_for(src, 'core_inventory:outfit')

env = Env(inventory=True)
for s in (1, 2):
    env.connect(s, [f'license:{s}'])
    env.call(s, 'auth_register', {'email': f'{s}@t.de', 'password': 'passwort123'})
fab = env.call(1, 'char_create', {'firstname': 'Fabian', 'lastname': 'Nandes', 'dateOfBirth': '1995-01-01', 'gender': 'male'})['data']['characterId']
mira = env.call(2, 'char_create', {'firstname': 'Mira', 'lastname': 'Brandt', 'dateOfBirth': '1995-01-01', 'gender': 'female'})['data']['characterId']
env.command(0, f'setrank {fab} chief')
# Mira hat noch ein altes Inventar: allgemeine Kleidung (T-Shirt aus dem alten Startoutfit lag im Jacken-Platz)
old = {'1': {'name': 'water', 'count': 1}, 'jacket': {'name': 'clothing_jacket', 'count': 1, 'meta': {'drawable': 0, 'label': 'Weißes T-Shirt'}},
       'pants': {'name': 'clothing_pants', 'count': 1, 'meta': {'drawable': 0}}}
env.sql("INSERT INTO inventories (id, data) VALUES (%s, %s)", (f'char:{mira}', json.dumps({'slots': old, 'flags': {'startOutfit': True}})))
env.call(1, 'char_select', {'id': fab}); env.call(2, 'char_select', {'id': mira}); env.tick(300)
env.positions[1] = [100.0, 100.0, 30.0]; env.positions[2] = [101.0, 100.0, 30.0]

print('Startoutfit')
it = items(call(1, 'inv_open', {})['data']['state'])
check('Neuer Charakter: T-Shirt, Jeans, Sneaker als eigene Items', it.get('shirt', {}).get('name') == 'shirt_white' and it.get('pants', {}).get('name') == 'pants_jeans' and it.get('shoes', {}).get('name') == 'shoes_sneaker', {k: v['name'] for k, v in it.items()})
o = outfits(1)
check('Client bekommt Platz und Item-Name', o and o[-1]['gender'] == 'male' and o[-1]['worn'] == {'shirt': 'shirt_white', 'pants': 'pants_jeans', 'shoes': 'shoes_sneaker'}, o[-1:])

print('Alte Kleidung')
it2 = items(call(2, 'inv_open', {})['data']['state'])
check('Altes T-Shirt aus dem Jacken-Platz rückt in den T-Shirt-Platz', it2.get('shirt', {}).get('name') == 'shirt_white' and 'jacket' not in it2, {k: v['name'] for k, v in it2.items()})
check('Alte Hose wird Jeans', it2.get('pants', {}).get('name') == 'pants_jeans')

print('Anziehen')
env.command(1, 'aduty'); env.command(1, f'giveitem {fab} jacket_bomber'); env.command(1, f'giveitem {fab} hat_beanie'); env.command(1, 'aduty')
st = call(1, 'inv_open', {})['data']['state']
j = [e['slot'] for e in st['items'] if e['name'] == 'jacket_bomber'][0]
r = call(1, 'inv_use', {'inv': 'self', 'slot': j})
check('Jacke über das T-Shirt', r['ok'] and outfits(1)[-1]['worn'].get('jacket') == 'jacket_bomber' and outfits(1)[-1]['worn'].get('shirt') == 'shirt_white')
r = call(1, 'inv_move', {'from': {'inv': 'self', 'slot': 'jacket'}, 'to': {'inv': 'self', 'slot': 'pants'}})
check('Jacke passt nicht in den Hosen-Platz', r.get('error') == 'wrong_slot')
n = len(outfits(1)); call(1, 'inv_open', {})
check('Ohne Änderung kein neues Outfit', len(outfits(1)) == n)
r = call(1, 'inv_use', {'inv': 'self', 'slot': 'jacket'})
check('Ausziehen', r['ok'] and 'jacket' not in outfits(1)[-1]['worn'])

print('Modell')
env.inv.execute("ClothingLooks.jacket_bomber.female = nil")
r = call(2, 'inv_give', {'from': {'inv': 'self', 'slot': [e['slot'] for e in r['data']['state']['items'] if e['name'] == 'jacket_bomber'][0]}, 'count': 1, 'target': 2}) if False else None
env.command(1, 'aduty'); env.command(1, f'giveitem {mira} jacket_bomber'); env.command(1, 'aduty')
st2 = call(2, 'inv_open', {})['data']['state']
j2 = [e['slot'] for e in st2['items'] if e['name'] == 'jacket_bomber'][0]
r = call(2, 'inv_use', {'inv': 'self', 'slot': j2})
check('Teil ohne weibliches Aussehen passt nicht an Mira', r.get('error') == 'wrong_gender', r.get('error'))
print(f'\n{ok} ok, {fail} Fehler')
