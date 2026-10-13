"""Les icônes de Droplet Drop pour les cinq plateformes, tirées de l'icône
de référence (docs/icone-source.png : la goutte en deux formes fluides,
bleu électrique et cyan, sur fond sombre).

  • iOS     : carré plein, sans transparence (le système arrondit) ;
  • macOS   : carré arrondi avec la marge des icônes du Mac ;
  • Android : icône classique + adaptative (avant-plan, fond, monochrome) ;
  • Windows : .ico multi-tailles ;
  • Linux et l'application elle-même : assets/icone.png.

Usage : python3 scripts/icones/generer_icones.py
"""
import pathlib

from PIL import Image, ImageChops, ImageDraw, ImageFilter

DEPOT = pathlib.Path(__file__).parents[2]
APP = DEPOT / "apps/droplet_drop_flutter"
SOURCE = DEPOT / "docs/icone-source.png"

# La tuile dans l'image source (mesurée) : bords et rayon des coins.
X0, Y0, X1, Y1 = 14, 13, 1237, 1233
RAYON = 0.235
FOND = (2, 10, 30)


def tuile() -> Image.Image:
    """La tuile seule, coins transparents."""
    im = Image.open(SOURCE).convert("RGBA").crop((X0, Y0, X1 + 1, Y1 + 1))
    w, h = im.size
    m = Image.new("L", (w * 4, h * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w * 4 - 1, h * 4 - 1], radius=int(w * 4 * RAYON), fill=255)
    im.putalpha(m.resize((w, h), Image.LANCZOS))
    return im


def carre_plein() -> Image.Image:
    """Pour iOS : l'intérieur de la tuile (sans le liseré lumineux), carré
    et opaque — le système pose son propre arrondi."""
    t = tuile()
    w = t.width
    marge = int(w * 0.035)
    interieur = t.crop((marge, marge, w - marge, w - marge))
    fond = Image.new("RGBA", interieur.size, FOND + (255,))
    # Les coins arrondis de la source sont remplis par le fond sombre.
    fond.alpha_composite(interieur)
    return fond.convert("RGB")


def region() -> Image.Image:
    """Le carré central de la tuile, autour de la goutte."""
    t = tuile()
    w = t.width
    return t.crop((int(w * 0.10), int(w * 0.08), int(w * 0.90), int(w * 0.88)))


def symbole() -> Image.Image:
    """La goutte seule sur fond transparent (Android adaptatif) : on garde
    la zone centrale et on fond doucement ses bords dans la couleur de fond."""
    c = region()
    n = c.width
    masque = Image.new("L", (n, n), 0)
    ImageDraw.Draw(masque).ellipse([n * 0.06, n * 0.06, n * 0.94, n * 0.94], fill=255)
    masque = masque.filter(ImageFilter.GaussianBlur(n * 0.04))
    c = c.resize((n, n))
    c.putalpha(ImageChops.multiply(c.getchannel("A"), masque))
    return c


def monochrome(sym: Image.Image) -> Image.Image:
    """La silhouette blanche de la goutte (icônes à thème d'Android 13+).

    Tout ce qui est bleu fait partie de la goutte ; on remplit ensuite tout
    ce qui n'est pas relié à l'extérieur : les reflets sombres DANS les
    formes disparaissent, la courbe qui les sépare (ouverte sur
    l'extérieur) reste."""
    r, g, b, a = sym.split()
    bleu = ImageChops.multiply(b.point(lambda v: 255 if v > 120 else 0), a.point(lambda v: 255 if v > 200 else 0))
    bleu = bleu.filter(ImageFilter.MaxFilter(11)).filter(ImageFilter.MinFilter(11))
    # Le liseré lumineux de la tuile, au bord de la zone : ce n'est pas la goutte.
    ImageDraw.Draw(bleu).rectangle([0, 0, bleu.width, int(bleu.height * 0.05)], fill=0)
    # Un cadre noir autour, pour que le remplissage parte bien de l'extérieur.
    exterieur = Image.new("L", (bleu.width + 4, bleu.height + 4), 0)
    exterieur.paste(bleu, (2, 2))
    ImageDraw.floodfill(exterieur, (0, 0), 128)
    interieur = exterieur.point(lambda v: 0 if v == 128 else 255).crop((2, 2, bleu.width + 2, bleu.height + 2))
    alpha = interieur.filter(ImageFilter.GaussianBlur(1.2))
    blanc = Image.new("RGBA", sym.size, (255, 255, 255, 0))
    blanc.putalpha(alpha)
    return blanc


def main():
    t = tuile()
    plein = carre_plein()
    sym = symbole()
    mono = monochrome(region())

    # iOS
    ios = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for p in ios.glob("Icon-App-*.png"):
        base, echelle = p.stem.split("-")[-1].split("@")
        n = round(float(base.split("x")[0]) * int(echelle[:-1]))
        plein.resize((n, n), Image.LANCZOS).save(p)

    # macOS : la tuile occupe ~82 % du carré, comme les icônes du système.
    mac = APP / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for p in mac.glob("app_icon_*.png"):
        n = int(p.stem.split("_")[-1])
        cadre = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        k = max(1, round(n * 0.82))
        cadre.alpha_composite(t.resize((k, k), Image.LANCZOS), ((n - k) // 2, (n - k) // 2))
        cadre.save(p)

    # Android
    res = APP / "android/app/src/main/res"
    for dossier, n in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        rond = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        k = round(n * 0.92)
        rond.alpha_composite(t.resize((k, k), Image.LANCZOS), ((n - k) // 2, (n - k) // 2))
        rond.save(res / f"mipmap-{dossier}/ic_launcher.png")
        a = n * 9 // 4  # 108 dp
        for img, nom in [(sym, "ic_launcher_foreground"), (mono, "ic_launcher_monochrome")]:
            calque = Image.new("RGBA", (a, a), (0, 0, 0, 0))
            k = round(a * 0.66)  # dans la zone sûre de 72 dp
            calque.alpha_composite(img.resize((k, k), Image.LANCZOS), ((a - k) // 2, (a - k) // 2))
            calque.save(res / f"mipmap-{dossier}/{nom}.png")
    (res / "mipmap-anydpi-v26").mkdir(exist_ok=True)
    (res / "mipmap-anydpi-v26/ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        "</adaptive-icon>\n"
    )
    (res / "values/colors.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">#{FOND[0]:02X}{FOND[1]:02X}{FOND[2]:02X}</color>\n</resources>\n'
    )

    # Windows
    t.resize((256, 256), Image.LANCZOS).save(
        APP / "windows/runner/resources/app_icon.ico",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

    # Linux et l'application
    (APP / "assets").mkdir(exist_ok=True)
    t.resize((512, 512), Image.LANCZOS).save(APP / "assets/icone.png")

    # Contrôle : lisibilité à 96, 48 et 32 px, sur fond clair et sombre.
    planche = Image.new("RGBA", (300, 200))
    for ligne, couleur in enumerate([(243, 246, 250, 255), (8, 12, 22, 255)]):
        bande = Image.new("RGBA", (300, 100), couleur)
        for x, n in [(10, 96), (130, 48), (200, 32)]:
            bande.alpha_composite(t.resize((n, n), Image.LANCZOS), (x, (100 - n) // 2))
        planche.paste(bande, (0, ligne * 100))
    planche.save(DEPOT / "docs/icone-tailles.png")
    for f in ["icone-1024.png"]:
        (DEPOT / "docs" / f).unlink(missing_ok=True)
    print("icônes générées depuis", SOURCE.name)


if __name__ == "__main__":
    main()
