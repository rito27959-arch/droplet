#!/usr/bin/env python3
"""
CONSTRUIT LA VERSION DÉPLOYABLE DU SITE.

    python3 site/construire.py

── ⚠️ POURQUOI CE SCRIPT EXISTE ────────────────────────────────────

`index.html` est écrit pour être publié en artifact : il commence
directement par son <title>, sans <!doctype>, sans <html>, sans <head>
ni <body>. L'hôte des artifacts fournit cette enveloppe lui-même, et
en ajouter une deuxième produirait un document imbriqué.

Un serveur ordinaire, lui, ne fournit rien du tout. Livré tel quel sur
Cloudflare Pages, le fichier s'afficherait quand même — les navigateurs
réparent le balisage manquant — mais SANS <meta viewport>, donc rendu
comme une page de bureau réduite sur téléphone, et SANS <meta charset>,
donc avec tous les accents cassés. Sur un site en français destiné à
des lecteurs sur mobile, ces deux oublis suffisent à le rendre
inutilisable.

Plutôt que de maintenir deux copies du site qui divergeraient dès la
première correction, on garde UNE source et on l'habille ici.
"""

import shutil
from pathlib import Path

SOURCE = Path(__file__).parent
SORTIE = SOURCE / "public"

ENVELOPPE = """<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="Droplet — une messagerie qui fonctionne sans internet, sans opérateur et sans serveur. Vos messages passent de téléphone en téléphone, chiffrés.">
<meta name="theme-color" content="#0066E0" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#070E18" media="(prefers-color-scheme: dark)">
<meta property="og:title" content="Droplet">
<meta property="og:description" content="Le réseau tombe. Le message, non.">
<meta property="og:type" content="website">
<meta property="og:locale" content="fr_FR">
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath fill='%230066E0' d='M12 2.4c3.6 4.2 6.4 7.6 6.4 10.9A6.4 6.4 0 0 1 12 19.7a6.4 6.4 0 0 1-6.4-6.4C5.6 10 8.4 6.6 12 2.4Z'/%3E%3C/svg%3E">
<style>
  /* La remise à zéro que l'hôte des artifacts appliquait pour nous. */
  *, *::before, *::after { box-sizing: border-box; }
  body { margin: 0; }
  img { max-width: 100%; }
</style>
<!--TETE-->
</head>
<body>
<!--CORPS-->
</body>
</html>
"""


def construire() -> None:
    brut = (SOURCE / "index.html").read_text(encoding="utf-8")

    # Ce qui doit monter dans <head> : le titre et les feuilles de style.
    # Tout le reste — y compris les <script> — reste dans <body>, où il
    # se trouve déjà et où l'ordre d'exécution est correct.
    tete: list[str] = []
    corps = brut

    for balise in ("<title>", "<link ", "<style>"):
        while True:
            debut = corps.find(balise)
            if debut == -1:
                break
            fin_balise = {
                "<title>": corps.find("</title>", debut) + len("</title>"),
                "<style>": corps.find("</style>", debut) + len("</style>"),
                "<link ": corps.find(">", debut) + 1,
            }[balise]
            tete.append(corps[debut:fin_balise])
            corps = corps[:debut] + corps[fin_balise:]

    SORTIE.mkdir(exist_ok=True)
    (SORTIE / "index.html").write_text(
        ENVELOPPE.replace("<!--TETE-->", "\n".join(tete))
                 .replace("<!--CORPS-->", corps.strip()),
        encoding="utf-8",
    )

    # Les fichiers de configuration de Cloudflare, et le runtime
    # d'animation s'il a été déposé.
    for nom in ("_headers", "_redirects", "lottie_light.min.js"):
        origine = SOURCE / nom
        if origine.exists():
            shutil.copy2(origine, SORTIE / nom)

    poids = (SORTIE / "index.html").stat().st_size
    print(f"→ {SORTIE / 'index.html'}  ({poids / 1024:.1f} Ko)")
    for f in sorted(SORTIE.iterdir()):
        if f.name != "index.html":
            print(f"→ {f}  ({f.stat().st_size / 1024:.1f} Ko)")


if __name__ == "__main__":
    construire()
