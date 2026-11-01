#!/usr/bin/env python3
"""
Erzeugt Kleidungs-Items aus FiveM-ClothingData (Bilder und GTA-Nummern).

  python tools/kleidung.py <Pfad zu FiveM-ClothingData-master>

Liest tools/kleidung_auswahl.json und schreibt:
  data/clothing_catalog_gta5.lua   Items und Aussehen (nicht von Hand aendern, neu erzeugen)
  images/<item>.png                128 x 128, durchsichtig

Braucht Python 3 und Pillow (pip install pillow).
"""
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PICKS = ROOT / 'tools' / 'kleidung_auswahl.json'
OUT_LUA = ROOT / 'data' / 'clothing_catalog_gta5.lua'
OUT_IMAGES = ROOT / 'images'
IMAGE_SIZE = 128
IMAGE_PADDING = 6

MODELS = {'male': ('mp_m_freemode_01', 'male'), 'female': ('mp_f_freemode_01', 'female')}
DRAWABLE_KEYS = {1: 'BERD', 3: 'UPPR', 4: 'LOWR', 5: 'HAND', 6: 'FEET', 7: 'TEEF', 8: 'ACCS', 9: 'TASK', 11: 'JBIB'}
PROP_KEYS = {0: 'P_HEAD', 1: 'P_EYES', 2: 'P_EARS', 6: 'P_LWRIST', 7: 'P_RWRIST'}
SLOT_TARGET = {
    'mask': ('D', 1), 'jacket': ('D', 11), 'shirt': ('D', 11), 'gloves': ('D', 3), 'pants': ('D', 4), 'shoes': ('D', 6),
    'hat': ('P', 0), 'glasses': ('P', 1), 'ears': ('P', 2), 'watch': ('P', 6),
}


def fail(text):
    sys.exit(f'Fehler: {text}')


def load_data(source):
    data = {}
    for gender, (_, prefix) in MODELS.items():
        data[gender] = {
            'D': json.loads((source / f'{prefix}_drawables.json').read_text(encoding='utf-8')),
            'P': json.loads((source / f'{prefix}_props.json').read_text(encoding='utf-8')),
        }
    return data


def resolve(data, source, gender, bild, item, expect=None):
    """'Male_Heist/D_1_21_1' -> (globale Nummer, Farbe, Bildpfad)"""
    try:
        collection, name = bild.split('/')
        kind, number, index, texture = name.split('_')
        number, texture = int(number), int(texture)
    except ValueError:
        fail(f'{item}: Bild-Angabe "{bild}" hat nicht die Form Ordner/D_11_4_2')
    if expect and (kind, number) != expect:
        fail(f'{item}: "{bild}" passt nicht zum Platz (erwartet {expect[0]}_{expect[1]}_...)')
    key = (DRAWABLE_KEYS if kind == 'D' else PROP_KEYS).get(number)
    entry = data[gender][kind].get('' if collection == 'base' else collection, {}).get(key, {}).get(index)
    if not entry:
        fail(f'{item}: "{bild}" steht nicht in den Daten fuer {gender}')
    if str(texture) not in entry['textures']:
        fail(f'{item}: Farbe {texture} gibt es bei "{bild}" nicht')
    image = source / 'images' / MODELS[gender][0] / collection / f'{name}.webp'
    return entry['globalId'], texture, image


def save_image(path, target):
    image = Image.open(path).convert('RGBA')
    box = image.getbbox()
    if box:
        image = image.crop(box)
    inner = IMAGE_SIZE - 2 * IMAGE_PADDING
    image.thumbnail((inner, inner), Image.LANCZOS)
    canvas = Image.new('RGBA', (IMAGE_SIZE, IMAGE_SIZE), (0, 0, 0, 0))
    canvas.paste(image, ((IMAGE_SIZE - image.width) // 2, (IMAGE_SIZE - image.height) // 2), image)
    canvas.save(target, optimize=True)


def lua_string(value):
    return "'" + str(value).replace('\\', '\\\\').replace("'", "\\'") + "'"


def main():
    if len(sys.argv) != 2:
        fail('Pfad zu FiveM-ClothingData-master angeben')
    source = Path(sys.argv[1])
    data = load_data(source)
    picks = json.loads(PICKS.read_text(encoding='utf-8'))['items']

    items_lua, looks_lua, missing = [], [], []
    for pick in picks:
        item, slot = pick['item'], pick['slot']
        if slot not in SLOT_TARGET:
            fail(f'{item}: unbekannter Platz "{slot}"')
        looks, image = [], None
        for gender in ('male', 'female'):
            spec = pick.get(gender)
            if not spec:
                continue
            global_id, texture, path = resolve(data, source, gender, spec['bild'], item, SLOT_TARGET[slot])
            parts = [str(global_id), str(texture)]
            if 'arms' in spec:
                parts.append(str(int(spec['arms'])))
            look = '{ ' + ', '.join(parts)
            if 'under' in spec:
                under_id, under_texture, _ = resolve(data, source, gender, spec['under'], item, ('D', 8))
                look += f', under = {{ {under_id}, {under_texture} }}'
            looks.append(f'{gender} = {look} }}')
            if image is None and path.exists():
                image = path
        if not looks:
            fail(f'{item}: weder male noch female angegeben')
        items_lua.append(
            f"    {item} = {{ label = {lua_string(pick['label'])}, weight = {int(pick.get('weight', 200))}, stack = 1, "
            f"equip = {lua_string(slot)}, description = {lua_string(pick.get('description', ''))} }},")
        looks_lua.append(f"    {item} = {{ {', '.join(looks)} }},")
        if image:
            save_image(image, OUT_IMAGES / f'{item}.png')
        else:
            missing.append(item)

    OUT_LUA.write_text(
        '-- Automatisch erzeugt von tools/kleidung.py aus tools/kleidung_auswahl.json. Nicht von Hand aendern.\n'
        '-- Nummern und Bilder: FiveM-ClothingData (Colbss), Game Build 3407.\n\n'
        'ClothingItems = {\n' + '\n'.join(items_lua) + '\n}\n\n'
        '-- { globale drawable-Nummer, Farbe, Arme } pro Modell, under = so unter einer Jacke\n'
        'ClothingLooks = {\n' + '\n'.join(looks_lua) + '\n}\n\n'
        'for name, def in pairs(ClothingItems) do\n    Items[name] = def\nend\n',
        encoding='utf-8')
    print(f'{len(picks)} Teile geschrieben: {OUT_LUA.relative_to(ROOT)}')
    if missing:
        print('Ohne Bild (in den Daten fehlt eins):', ', '.join(missing))


if __name__ == '__main__':
    main()
