#!/usr/bin/env python3
"""Décline l'icône fournie par l'auteur aux formats attendus par Android.

Aucun redessin : l'image source est la référence, on se contente de la
recadrer, de la redimensionner et d'en extraire les deux couches que
réclament les icônes adaptatives.
"""
import os
from PIL import Image, ImageDraw, ImageFilter

SRC = 'assets/icon/droplet_icon_1024.png'
RES = 'android/app/src/main/res'
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

src = Image.open(SRC).convert('RGB')


def crop_to_tile(img):
    """Retire la marge blanche autour de la vignette.

    L'image d'origine est une planche de présentation : la vignette bleue
    y flotte au milieu d'un fond blanc.

    ⚠️ On repère la vignette à sa COULEUR, pas à « ce qui n'est pas
    blanc ». Le fichier est un JPEG : sa compression sème autour du
    dessin de fines auréoles qui ne sont plus tout à fait blanches, et un
    simple seuil de blancheur les prenait pour la vignette — le recadrage
    ne retirait alors que dix pixels sur les quarante attendus, et la
    marge blanche restante venait polluer le détourage.
    Le bleu, lui, est sans ambiguïté : son canal bleu domine largement le
    rouge, ce qu'aucun gris de compression ne fait.
    """
    w, h = img.size
    px = img.load()

    left, right, top, bottom = w, 0, h, 0
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if b - r > 40:
                left = min(left, x)
                right = max(right, x)
                top = min(top, y)
                bottom = max(bottom, y)
    return img.crop((left, top, right + 1, bottom + 1))


tile = crop_to_tile(src)
side = min(tile.size)
tile = tile.resize((side, side), Image.LANCZOS)
print(f'vignette recadrée : {side}x{side}')

# ── Rayon des coins, mesuré sur la vignette ──────────────────────────
# On avance en diagonale depuis le coin haut-gauche jusqu'à toucher la
# couleur : la distance parcourue donne le rayon réel du dessin, plutôt
# qu'une valeur devinée.
px = tile.load()
d = 0
while d < side // 2 and sum(px[d, d]) > 700:
    d += 1
CORNER = int(d / 0.2929)  # un coin arrondi de rayon r commence à r*(1-1/√2)
print(f'rayon des coins : ~{CORNER}px sur {side}')


def rounded(img, size):
    """Vignette redimensionnée, coins arrondis rendus transparents."""
    ss = 4
    big = size * ss
    out = img.resize((big, big), Image.LANCZOS).convert('RGBA')
    mask = Image.new('L', (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, big - 1, big - 1],
        radius=int(CORNER * big / side), fill=255)
    out.putalpha(mask)
    return out.resize((size, size), Image.LANCZOS)


def background(size):
    """Couche « fond » de l'icône adaptative.

    Le dégradé de la vignette, étiré à bord perdu. Les coins arrondis
    disparaissent : c'est le système qui découpera la forme finale
    (cercle, carré, goutte…) selon le téléphone.
    """
    # Le dégradé est relevé sur quatre points pris BIEN À L'INTÉRIEUR de
    # la vignette : réduire l'image entière à 2x2 ferait entrer dans la
    # moyenne les coins arrondis (blancs) et le dessin blanc du milieu,
    # et délaverait le bleu.
    s = tile.size[0]
    m = int(s * 0.10)
    corners = [
        tile.crop((m, m, m + 40, m + 40)),
        tile.crop((s - m - 40, m, s - m, m + 40)),
        tile.crop((m, s - m - 40, m + 40, s - m)),
        tile.crop((s - m - 40, s - m - 40, s - m, s - m)),
    ]
    seed = Image.new('RGB', (2, 2))
    seed.putdata([c.resize((1, 1), Image.LANCZOS).getpixel((0, 0))
                  for c in corners])
    return seed.resize((size, size), Image.BICUBIC).convert('RGBA')


def foreground(size, fill=0.63):
    """Couche « dessin » : la marque blanche seule, détourée du fond bleu.

    `fill` = la part du côté qu'occupe la vignette une fois ramenée dans
    la zone sûre du centre (le système rogne les bords).
    """
    ss = 4
    big = size * ss
    inner = int(big * fill)

    # Les coins arrondis sont d'abord remplis de bleu : sans ça, le blanc
    # qui les entoure serait détouré comme s'il faisait partie du dessin,
    # et la marque se retrouverait cernée d'un halo carré.
    flat = tile.copy()
    corner_mask = Image.new('L', tile.size, 255)
    ImageDraw.Draw(corner_mask).rounded_rectangle(
        [0, 0, tile.size[0] - 1, tile.size[1] - 1], radius=CORNER, fill=0)
    edge = tile.getpixel((tile.size[0] // 2, 4))
    flat.paste(Image.new('RGB', tile.size, edge), (0, 0), corner_mask)

    small = flat.resize((inner, inner), Image.LANCZOS).convert('RGB')
    sp = small.load()

    # Détourage : le dessin est blanc, le fond est bleu. On mesure à quel
    # point chaque pixel est « blanc » pour en faire une transparence —
    # ce qui préserve l'antialiasing des courbes au lieu de produire des
    # marches d'escalier.
    alpha = Image.new('L', (inner, inner), 0)
    ap = alpha.load()
    for y in range(inner):
        for x in range(inner):
            r, g, b = sp[x, y]
            # Distance au bleu du fond, normalisée : 0 = fond, 1 = blanc pur.
            v = (min(r, g, b) - 95) / 160.0
            ap[x, y] = max(0, min(255, int(v * 255)))

    # Tout ce qui déborde du carré arrondi est mis à zéro : il y subsiste
    # sinon un liseré fantôme, là où le bleu de bouchage des coins ne
    # correspond pas exactement au dégradé qu'il remplace.
    inside = Image.new('L', (inner, inner), 0)
    ImageDraw.Draw(inside).rounded_rectangle(
        [0, 0, inner - 1, inner - 1],
        radius=int(CORNER * inner / side), fill=255)
    alpha = Image.composite(alpha, Image.new('L', (inner, inner), 0), inside)

    # Tout ce qui déborde du carré arrondi est remis à zéro, et la coupe
    # est rentrée de 3 %.
    #
    # Le bouchage des coins ci-dessus se fait avec UNE seule couleur,
    # alors qu'il remplace un dégradé : il subsiste donc, exactement sur
    # le contour du carré arrondi, un écart de teinte que le détourage
    # interprète comme un léger blanc. Sur le fond bleu de l'icône, ce
    # résidu dessinait un carré arrondi fantôme autour de la marque.
    # Couper au ras du contour ne suffisait pas — c'est le contour
    # lui-même qu'il faut retirer.
    pad = int(inner * 0.03)
    inside = Image.new('L', (inner, inner), 0)
    ImageDraw.Draw(inside).rounded_rectangle(
        [pad, pad, inner - 1 - pad, inner - 1 - pad],
        radius=int((inner - 2 * pad) * CORNER / side), fill=255)
    alpha = Image.composite(alpha, Image.new('L', (inner, inner), 0), inside)

    mark = Image.new('RGBA', (inner, inner), (255, 255, 255, 255))
    mark.putalpha(alpha)

    canvas = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    canvas.alpha_composite(mark, ((big - inner) // 2, (big - inner) // 2))
    return canvas.resize((size, size), Image.LANCZOS)


def circular(img, size):
    """Version ronde, pour Android 7.1 : cette version-là réclame déjà une
    icône ronde (`roundIcon`) mais ne sait pas encore découper les icônes
    adaptatives elle-même."""
    ss = 4
    big = size * ss
    out = img.resize((big, big), Image.LANCZOS).convert('RGBA')
    mask = Image.new('L', (big, big), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, big - 1, big - 1], fill=255)
    out.putalpha(mask)
    return out.resize((size, size), Image.LANCZOS)


def monochrome(size):
    """Silhouette pour les icônes thématiques d'Android 13+ : le système
    la recolore selon le fond d'écran."""
    fg = foreground(size)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.putalpha(fg.getchannel('A'))
    return out


for name, factor in DENSITIES.items():
    d = f'{RES}/mipmap-{name}'
    os.makedirs(d, exist_ok=True)
    rounded(tile, int(48 * factor)).save(f'{d}/ic_launcher.png')
    circular(tile, int(48 * factor)).save(f'{d}/ic_launcher_round.png')

    fg = int(108 * factor)
    background(fg).save(f'{d}/ic_launcher_background.png')
    foreground(fg).save(f'{d}/ic_launcher_foreground.png')
    monochrome(fg).save(f'{d}/ic_launcher_monochrome.png')

# Vignette propre en PNG, pour l'écran de démarrage et les boutiques.
rounded(tile, 1024).save('assets/icon/droplet_icon.png')

# La marque seule, en bleu : c'est celle qu'on pose sur un fond clair,
# où une marque blanche serait invisible. La teinte est prélevée sur
# l'icône elle-même, à mi-chemin de son dégradé, plutôt que choisie au
# jugé.
mark = foreground(1024, fill=1.0)
a = tile.getpixel((int(side * 0.12), int(side * 0.12)))
b = tile.getpixel((int(side * 0.88), int(side * 0.88)))
blue = tuple((a[i] + b[i]) // 2 for i in range(3))
tinted = Image.new('RGBA', mark.size, blue + (255,))
tinted.putalpha(mark.getchannel('A'))
tinted.save('assets/icon/droplet_mark.png')
print('marque bleue : #%02X%02X%02X' % blue)

print('icônes déclinées')
