#!/usr/bin/env python3
"""Erzeugt die Hintergruende des Handys als SVG-Symbole und setzt sie in html/phone.html ein.

Laeuft nicht im Spiel. Aufruf:  python3 core_phone/tools/wallpapers.py
Ersetzt in html/phone.html alles zwischen <!-- WALLPAPERS:START --> und <!-- WALLPAPERS:END -->.

Jeder Hintergrund besteht aus grossen Kugeln mit Lichtkante. Alle Farben kommen aus den Farbvariablen
der UI (--rgb-base, --rgb-ink, --rgb-accent, --rgb-mark), also aus Config.UI.Colors der Core.
Bewusst ohne SVG-Filter: Schatten und Schein sind Verlaeufe und breite, blasse Linien. Das kostet im Spiel nichts.

Ein neuer Hintergrund: unten in WALLPAPERS eintragen, Script starten, den Namen in Config.Phone.Wallpapers
und in TEXT.wallpapers der UI ergaenzen.
"""
import pathlib
import re

WIDTH, HEIGHT = 390, 844
TARGET = pathlib.Path(__file__).resolve().parent.parent / 'html' / 'phone.html'
START, END = '<!-- WALLPAPERS:START -->', '<!-- WALLPAPERS:END -->'

# Kugel: Mitte, Radius, Richtung vom Licht weg (Einheitsvektor), Farbe der Kante, Staerke der Flaeche und der Kante,
# Zahl der feinen Innenringe, clip = Index einer frueheren Kugel, in der diese noch einmal durchscheint
def sphere(cx, cy, r, direction, tone, body, rim, rings=0, clip=None):
    return dict(cx=cx, cy=cy, r=r, dir=direction, tone=tone, body=body, rim=rim, rings=rings, clip=clip)

WALLPAPERS = {
    'sphaeren': dict(
        glows=[(60, 140, 380, 'ink', 0.09)],
        spheres=[
            sphere(370, 905, 300, (0.766, 0.643), 'accent', 0.06, 0.95),
            sphere(-20, 475, 345, (-0.966, 0.259), 'mark', 0.18, 0.95),
            sphere(370, 905, 300, (0.766, 0.643), 'accent', 0.10, 1.0, rings=2, clip=1),
            sphere(300, 40, 262, (0.574, -0.819), 'ink', 0.22, 0.9, rings=1),
        ]),
    'eklipse': dict(
        glows=[(300, 300, 360, 'accent', 0.22), (338, 104, 120, 'ink', 0.10)],
        spheres=[
            sphere(338, 104, 44, (0.5, 0.866), 'ink', 0.18, 0.9),
            sphere(150, 548, 318, (-0.669, 0.743), 'ink', 0.07, 1.0, rings=1),
        ]),
    'wellen': dict(
        glows=[(195, 250, 420, 'accent', 0.10)],
        spheres=[
            sphere(-80, 770, 470, (0.423, 0.906), 'ink', 0.16, 0.95),
            sphere(470, 880, 470, (-0.423, 0.906), 'accent', 0.14, 0.9, rings=1),
            sphere(60, 990, 470, (0.423, 0.906), 'ink', 0.12, 0.85),
            sphere(400, 1100, 470, (-0.423, 0.906), 'mark', 0.10, 0.8, rings=1),
            sphere(150, 1215, 470, (0.423, 0.906), 'ink', 0.08, 0.75),
        ]),
    'glut': dict(
        glows=[(330, 360, 360, 'mark', 0.14)],
        spheres=[
            sphere(10, 800, 320, (-0.766, 0.643), 'mark', 0.07, 0.85),
            sphere(420, 330, 290, (0.985, -0.174), 'mark', 0.16, 0.95),
            sphere(10, 800, 320, (-0.766, 0.643), 'accent', 0.12, 1.0, rings=2, clip=1),
            sphere(60, 90, 170, (-0.574, -0.819), 'ink', 0.14, 0.75),
        ]),
}

# Lichtkante: scharf, dazu zwei breite blasse Linien als Schein (statt Weichzeichner)
RIM_LINES = ((16, 0.07), (7, 0.16), (1.1, 1.0))
RING_STEP, RING_SHIFT, RING_FADE = 5.5, 2.2, (0.57, 0.39)
SHADOW_SHIFT, SHADOW_SPREAD = 0.07, 26


def num(value):
    return f'{value:.2f}'.rstrip('0').rstrip('.')


def stop(offset, tone, opacity):
    return f'<stop offset="{num(offset)}" style="stop-color:rgb(var(--rgb-{tone}));stop-opacity:{num(opacity)}"/>'


def linear(gid, s, stops):
    (dx, dy), r = s['dir'], s['r']
    x1, y1, x2, y2 = s['cx'] - dx * r, s['cy'] - dy * r, s['cx'] + dx * r, s['cy'] + dy * r
    return (f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="{num(x1)}" y1="{num(y1)}" x2="{num(x2)}" y2="{num(y2)}">'
            + ''.join(stops) + '</linearGradient>')


def radial(gid, cx, cy, r, stops):
    return f'<radialGradient id="{gid}" gradientUnits="userSpaceOnUse" cx="{num(cx)}" cy="{num(cy)}" r="{num(r)}">' + ''.join(stops) + '</radialGradient>'


def build(name, spec):
    defs, body = [], [f'<rect width="{WIDTH}" height="{HEIGHT}" style="fill:rgb(var(--rgb-base))"/>']
    counter = [0]

    def gid(kind):
        counter[0] += 1
        return f'wp-{name}-{kind}{counter[0]}'

    for cx, cy, r, tone, strength in spec['glows']:
        g = gid('glow')
        defs.append(radial(g, cx, cy, r, [stop(0, tone, strength), stop(0.45, tone, strength * 0.35), stop(1, tone, 0)]))
        body.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" style="fill:url(#{g})"/>')

    for s in spec['spheres']:
        cx, cy, r, (dx, dy), tone = s['cx'], s['cy'], s['r'], s['dir'], s['tone']
        circle = f'cx="{cx}" cy="{cy}" r="{r}"'
        parts = []
        if s['clip'] is None:
            # weicher Schatten hinter der Kugel, zur dunklen Seite versetzt
            g, outer = gid('shade'), r * 1.01 + SHADOW_SPREAD
            defs.append(radial(g, cx + dx * r * SHADOW_SHIFT, cy + dy * r * SHADOW_SHIFT, outer,
                               [stop(0, 'base', 0.85), stop((r * 1.01 - SHADOW_SPREAD) / outer, 'base', 0.85), stop(1, 'base', 0)]))
            parts.append(f'<circle cx="{num(cx + dx * r * SHADOW_SHIFT)}" cy="{num(cy + dy * r * SHADOW_SHIFT)}" r="{num(outer)}" style="fill:url(#{g})"/>')
        parts.append(f'<circle {circle} style="fill:rgb(var(--rgb-base))"/>')
        g = gid('body')
        defs.append(linear(g, s, [stop(0, 'ink', s['body']), stop(0.22, 'ink', s['body'] / 2), stop(0.65, 'ink', 0)]))
        parts.append(f'<circle {circle} style="fill:url(#{g})"/>')
        g = gid('tint')
        defs.append(linear(g, s, [stop(0, tone, s['body'] * 0.55), stop(0.4, tone, 0)]))
        parts.append(f'<circle {circle} style="fill:url(#{g})"/>')
        g = gid('in')
        defs.append(radial(g, cx + dx * r * 0.2, cy + dy * r * 0.2, r * 1.2,
                           [stop(0, tone, 0), stop(0.8, tone, 0), stop(0.93, tone, s['rim'] * 0.12), stop(1, tone, s['rim'] * 0.42)]))
        parts.append(f'<circle {circle} style="fill:url(#{g})"/>')
        g = gid('rim')
        defs.append(linear(g, s, [stop(0, tone, s['rim']), stop(0.16, tone, s['rim'] * 0.8), stop(0.38, tone, s['rim'] * 0.22), stop(0.58, tone, 0), stop(1, tone, 0)]))
        for width, opacity in RIM_LINES:
            parts.append(f'<circle {circle} style="fill:none;stroke:url(#{g});stroke-width:{num(width)};opacity:{num(opacity)}"/>')
        for index in range(s['rings']):
            step = index + 1
            parts.append(f'<circle cx="{num(cx - dx * RING_SHIFT * step)}" cy="{num(cy - dy * RING_SHIFT * step)}" r="{num(r - RING_STEP * step)}" '
                         f'style="fill:none;stroke:url(#{g});stroke-width:0.8;opacity:{RING_FADE[index]}"/>')
        if s['clip'] is None:
            body.extend(parts)
        else:
            other = spec['spheres'][s['clip']]
            c = gid('clip')
            defs.append(f'<clipPath id="{c}"><circle cx="{other["cx"]}" cy="{other["cy"]}" r="{other["r"]}"/></clipPath>')
            body.append(f'<g clip-path="url(#{c})">' + ''.join(parts) + '</g>')

    symbol = f'<symbol id="wp-{name}" viewBox="0 0 {WIDTH} {HEIGHT}" preserveAspectRatio="xMidYMid slice">' + ''.join(body) + '</symbol>'
    return ''.join(defs), symbol


def main():
    defs, symbols = [], []
    for name, spec in WALLPAPERS.items():
        d, s = build(name, spec)
        defs.append(d)
        symbols.append(s)
    block = START + '\n' + '\n'.join(defs) + '\n' + '\n'.join(symbols) + '\n' + END
    html = TARGET.read_text(encoding='utf-8')
    if START not in html or END not in html:
        raise SystemExit(f'Marker fehlen in {TARGET}')
    html = re.sub(re.escape(START) + r'.*?' + re.escape(END), lambda _: block, html, flags=re.S)
    TARGET.write_text(html, encoding='utf-8')
    print(f'{len(WALLPAPERS)} Hintergruende in {TARGET.name} eingesetzt: {", ".join(WALLPAPERS)}')


if __name__ == '__main__':
    main()
