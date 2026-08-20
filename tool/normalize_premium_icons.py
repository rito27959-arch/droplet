#!/usr/bin/env python3
"""Met les icônes « premium » au même format que les autres variantes.

── Le problème ─────────────────────────────────────────────────────────

Les neuf premières variantes sont des vignettes propres : 1024×1024,
coins arrondis transparents, aucune marge. Les trois icônes premium, en
revanche, arrivent comme des IMAGES DE PRÉSENTATION — la vignette y
flotte au milieu d'un fond (gris clair pour l'une, presque noir pour les
deux autres), et ses coins arrondis sont peints, pas découpés.

Utilisées telles quelles, elles donneraient une icône avec un cadre
disgracieux, et le système d'Android — qui redécoupe lui-même la forme —
rognerait dans le dessin au lieu de rogner dans la marge.

── Ce que fait ce script ───────────────────────────────────────────────

1. Il repère la vignette en cherchant les pixels qui S'ÉCARTENT de la
   couleur des coins. C'est plus robuste qu'un seuil de luminosité :
   ça marche aussi bien sur un fond clair que sur un fond noir.
2. Il la recadre au carré.
3. Il rend les coins arrondis transparents, comme sur les neuf autres.

Le résultat rejoint `assets/icon/variants/`, et `build_icon_variants.py`
le décline ensuite sans savoir qu'il vient d'ailleurs.
"""
import os

from PIL import Image, ImageDraw

SRC = 'assets/icon/premuim'
DST = 'assets/icon/variants'

# Les trois icônes premium, et le numéro de variante qu'elles prennent.
PREMIUM = {7: 10, 8: 11, 9: 12}

CORNER = 0.2237
SIZE = 1024


def crop_to_tile(img):
    """Retire la marge autour de la vignette.

    On prélève la couleur des quatre coins — qui est forcément celle du
    fond — puis on cherche la boîte des pixels qui s'en écartent
    nettement. Le seuil est généreux : un fond dégradé ou légèrement
    bruité ne doit pas être pris pour du contenu.
    """
    rgb = img.convert('RGB')
    w, h = rgb.size
    px = rgb.load()

    corners = [px[2, 2], px[w - 3, 2], px[2, h - 3], px[w - 3, h - 3]]
    bg = tuple(sum(c[i] for c in corners) // 4 for i in range(3))

    # Seuil volontairement haut : ces vignettes ont un halo lumineux
    # autour d'elles, presque de la couleur du fond clair. Un seuil bas
    # le prenait pour du dessin et gardait une frange blanche visible
    # sur l'icône finale.
    def differs(p):
        return sum(abs(p[i] - bg[i]) for i in range(3)) > 90

    left, right, top, bottom = w, 0, h, 0
    # Un pixel sur deux suffit largement et divise le temps par quatre.
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if differs(px[x, y]):
                if x < left:
                    left = x
                if x > right:
                    right = x
                if y < top:
                    top = y
                if y > bottom:
                    bottom = y

    if left >= right or top >= bottom:
        # Aucune marge détectée : l'image est déjà la vignette.
        return img

    # On recadre AU CARRÉ, centré sur ce qu'on a trouvé : une vignette
    # d'application est carrée par définition, et un recadrage
    # rectangulaire la déformerait au redimensionnement.
    #
    # On retient le côté le PLUS PETIT des deux. Prendre le plus grand
    # garantissait de ne rien perdre du dessin, mais faisait entrer un
    # peu de fond sur l'autre axe — la frange claire qu'on voyait au
    # bord de l'icône. Ce qu'on rogne ainsi n'est de toute façon que le
    # coin arrondi, rendu transparent juste après.
    side = min(right - left, bottom - top) + 1
    cx = (left + right) // 2
    cy = (top + bottom) // 2
    half = side // 2
    box = (
        max(0, cx - half),
        max(0, cy - half),
        min(w, cx + half),
        min(h, cy + half),
    )
    return img.crop(box)


def rounded(img, size=SIZE):
    """Vignette carrée, coins arrondis rendus transparents."""
    ss = 4
    big = size * ss
    out = img.resize((big, big), Image.LANCZOS).convert('RGBA')
    mask = Image.new('L', (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, big - 1, big - 1],
        radius=int(big * CORNER),
        fill=255,
    )
    out.putalpha(mask)
    return out.resize((size, size), Image.LANCZOS)


os.makedirs(DST, exist_ok=True)

for source, index in PREMIUM.items():
    path = f'{SRC}/premium_{source}.png'
    if not os.path.exists(path):
        raise SystemExit(f'icône premium manquante : {path}')

    tile = crop_to_tile(Image.open(path).convert('RGBA'))
    target = f'{DST}/droplet_{index}.png'
    rounded(tile).save(target)
    print(f'premium_{source} → droplet_{index} '
          f'(recadrée à {tile.size[0]}×{tile.size[1]})')

print('icônes premium normalisées')
