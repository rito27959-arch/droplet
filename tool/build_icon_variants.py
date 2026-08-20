#!/usr/bin/env python3
"""Décline les douze variantes d'icône aux formats Android.

Chaque variante devient une icône adaptative complète (fond + dessin +
silhouette monochrome) sur les cinq densités, plus une icône ronde pour
Android 7.1.

── Le problème que ce script résout ────────────────────────────────────

Les variantes sont fournies comme des VIGNETTES FINIES : fond, marque et
coins arrondis déjà composés. Or Android veut deux couches séparées, et
n'affiche que les 72 dp centraux d'une toile de 108 dp — le reste est
rogné selon la forme choisie par le fabricant.

Utiliser la vignette telle quelle comme fond ferait donc rogner la
marque elle-même sur les masques ronds. La vignette est donc RÉDUITE à
76 % de la toile, et le pourtour est comblé par un dégradé extrapolé de
ses quatre coins — qui sont du fond pur. Le raccord est invisible, et
après le rognage du système la marque tombe pile dans la zone sûre.
"""
import os

from PIL import Image, ImageDraw

SRC = 'assets/icon/variants'
RES = 'android/app/src/main/res'
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

# Part de la toile occupée par la vignette. 76 % laisse une marge
# suffisante pour tous les masques, sans rapetisser la marque au point
# de la noyer.
FILL = 0.76

CORNER = 0.2237


def edge_gradient(tile, size):
    """Le fond de la vignette, étendu à toute la toile.

    Les quatre coins d'une vignette sont du fond pur : on les prélève et
    on les étire. Pour un dégradé — ce que sont presque toutes les
    variantes — le raccord avec la vignette posée par-dessus est
    invisible.
    """
    s = tile.size[0]
    m = int(s * 0.06)
    d = int(s * 0.06)
    corners = [
        tile.crop((m, m, m + d, m + d)),
        tile.crop((s - m - d, m, s - m, m + d)),
        tile.crop((m, s - m - d, m + d, s - m)),
        tile.crop((s - m - d, s - m - d, s - m, s - m)),
    ]
    seed = Image.new('RGB', (2, 2))
    seed.putdata([
        c.convert('RGB').resize((1, 1), Image.LANCZOS).getpixel((0, 0))
        for c in corners
    ])
    return seed.resize((size, size), Image.BICUBIC).convert('RGBA')


def background(tile, size):
    """Couche « fond » : le dégradé étendu, à bord perdu."""
    return edge_gradient(tile, size)


def foreground(tile, size):
    """Couche « dessin » : la vignette réduite, sur fond transparent.

    On y laisse le fond de la vignette : c'est lui qui porte le dégradé
    et l'éventuelle lueur, et l'en séparer détruirait des variantes
    comme la n°2 (halo cyan) ou la n°7 (vagues).
    """
    inner = int(size * FILL)
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(
        tile.resize((inner, inner), Image.LANCZOS).convert('RGBA'),
        ((size - inner) // 2, (size - inner) // 2),
    )
    return canvas


def monochrome(tile, size):
    """Silhouette pour les icônes thématiques d'Android 13+.

    On garde la forme de la vignette, pleine : le système la recolore de
    toute façon selon le fond d'écran, donc le détail interne serait
    perdu.
    """
    inner = int(size * FILL)
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    shape = Image.new('L', (inner, inner), 0)
    ImageDraw.Draw(shape).rounded_rectangle(
        [0, 0, inner - 1, inner - 1], radius=int(inner * CORNER), fill=255)
    black = Image.new('RGBA', (inner, inner), (0, 0, 0, 255))
    black.putalpha(shape)
    canvas.alpha_composite(black, ((size - inner) // 2, (size - inner) // 2))
    return canvas


def circular(tile, size):
    """Version ronde, pour Android 7.1."""
    ss = 4
    big = size * ss
    out = tile.resize((big, big), Image.LANCZOS).convert('RGBA')
    mask = Image.new('L', (big, big), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, big - 1, big - 1], fill=255)
    out.putalpha(mask)
    return out.resize((size, size), Image.LANCZOS)


ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<!--
  Variante {n} de l'icône de Droplet.

  Une icône adaptative : le système découpe lui-même la forme (cercle,
  carré arrondi, goutte…) selon le téléphone. D'où les couches séparées,
  et la marge autour du dessin — seuls les 72 dp centraux des 108 dp
  sont garantis visibles.
-->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_v{n}_background" />
    <foreground android:drawable="@mipmap/ic_launcher_v{n}_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_v{n}_monochrome" />
</adaptive-icon>
"""

anydpi = f'{RES}/mipmap-anydpi-v26'
os.makedirs(anydpi, exist_ok=True)

count = 0
for index in range(1, 13):
    path = f'{SRC}/droplet_{index:02d}.png'
    if not os.path.exists(path):
        raise SystemExit(
            f'variante manquante : {path}\n'
            "Les trois dernières viennent des icônes premium : lancez "
            "d'abord `python3 tool/normalize_premium_icons.py`.")
    tile = Image.open(path).convert('RGBA')

    for name, factor in DENSITIES.items():
        d = f'{RES}/mipmap-{name}'
        os.makedirs(d, exist_ok=True)

        legacy = int(48 * factor)
        adaptive = int(108 * factor)

        tile.resize((legacy, legacy), Image.LANCZOS).save(
            f'{d}/ic_launcher_v{index}.png')
        circular(tile, legacy).save(f'{d}/ic_launcher_v{index}_round.png')
        background(tile, adaptive).save(
            f'{d}/ic_launcher_v{index}_background.png')
        foreground(tile, adaptive).save(
            f'{d}/ic_launcher_v{index}_foreground.png')
        monochrome(tile, adaptive).save(
            f'{d}/ic_launcher_v{index}_monochrome.png')

    with open(f'{anydpi}/ic_launcher_v{index}.xml', 'w', encoding='utf-8') as f:
        f.write(ADAPTIVE_XML.format(n=index))
    with open(f'{anydpi}/ic_launcher_v{index}_round.xml', 'w',
              encoding='utf-8') as f:
        f.write(ADAPTIVE_XML.format(n=index))

    count += 1
    print(f'variante {index} déclinée')

print(f'{count} variantes prêtes pour Android')
