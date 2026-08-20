#!/usr/bin/env python3
"""Découpe la planche des neuf icônes en neuf fichiers séparés.

AUCUNE retouche : ni couleur, ni contraste, ni redessin. On repère la
position exacte de chaque vignette sur la planche, on la recadre au ras
de son bord, et on arrondit les coins pour que le fond de la planche ne
subsiste pas dans les angles.

Le repérage est AUTOMATIQUE plutôt que codé en dur : la planche est un
JPEG, ses bords sont donc légèrement flous et une grille calculée à la
main laisserait un liseré du fond sombre sur chaque vignette.
"""
import os

from PIL import Image, ImageDraw

SRC = 'assets/icon/5.jpeg'
OUT = 'assets/icon/variants'
COLS, ROWS = 3, 3

# Coin arrondi des vignettes, en fraction du côté — mesuré sur la
# planche, et identique à celui de l'icône principale.
CORNER = 0.2237

src = Image.open(SRC).convert('RGB')
w, h = src.size
px = src.load()

# ── Couleur du fond de la planche ───────────────────────────────────
# Prélevée dans le coin haut-gauche, là où il n'y a jamais de vignette.
bg = px[4, 4]


def is_background(p, tolerance=26):
    return all(abs(p[i] - bg[i]) < tolerance for i in range(3))


def spans(values, size):
    """Regroupe une liste d'indices en plages continues.

    Les colonnes (ou lignes) qui ne sont pas du fond forment trois
    blocs : ce sont les trois vignettes. Les trous entre elles sont les
    gouttières de la planche.
    """
    out = []
    start = None
    for i in range(size):
        if i in values:
            if start is None:
                start = i
        elif start is not None:
            out.append((start, i - 1))
            start = None
    if start is not None:
        out.append((start, size - 1))
    # Les plages minuscules viennent des numéros imprimés sous les
    # vignettes et du bruit de compression : on ne garde que les vraies.
    return [s for s in out if s[1] - s[0] > size // 12]


# Une colonne « contient de la vignette » si une part notable de ses
# pixels n'est pas du fond.
content_cols = {
    x for x in range(w)
    if sum(0 if is_background(px[x, y]) else 1
           for y in range(0, h, 8)) > (h // 8) * 0.12
}
content_rows = {
    y for y in range(h)
    if sum(0 if is_background(px[x, y]) else 1
           for x in range(0, w, 8)) > (w // 8) * 0.12
}

col_spans = spans(content_cols, w)
row_spans = spans(content_rows, h)

print(f'colonnes détectées : {col_spans}')
print(f'lignes détectées   : {row_spans}')

if len(col_spans) != COLS or len(row_spans) != ROWS:
    raise SystemExit(
        f'grille inattendue : {len(col_spans)}x{len(row_spans)}, '
        f'{COLS}x{ROWS} attendus'
    )

os.makedirs(OUT, exist_ok=True)

index = 0
for row, (top, bottom) in enumerate(row_spans):
    for col, (left, right) in enumerate(col_spans):
        index += 1

        # Les lignes détectées incluent le numéro imprimé SOUS chaque
        # vignette. On force donc une découpe carrée, calée sur le haut.
        side = min(right - left + 1, bottom - top + 1)
        box = (left, top, left + side, top + side)
        tile = src.crop(box)

        # Coins arrondis rendus transparents, sinon le fond sombre de la
        # planche resterait visible dans les angles.
        ss = 4
        big = side * ss
        out = tile.resize((big, big), Image.LANCZOS).convert('RGBA')
        mask = Image.new('L', (big, big), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, big - 1, big - 1],
            radius=int(big * CORNER), fill=255)
        out.putalpha(mask)
        out = out.resize((1024, 1024), Image.LANCZOS)

        path = f'{OUT}/droplet_{index:02d}.png'
        out.save(path)
        print(f'{path}  ({side}x{side} → 1024)')

print(f'{index} variantes découpées')
