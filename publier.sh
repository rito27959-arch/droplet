#!/usr/bin/env bash
#
# PUBLIER DROPLET — le dépôt, l'APK, et le site.
#
#   ./publier.sh <votre-compte-github>
#
# ── ⚠️ CE SCRIPT NE FAIT RIEN TOUT SEUL ────────────────────────────
#
# Il s'arrête à chaque étape qui demande VOS identifiants : personne
# d'autre ne doit pouvoir pousser du code ou déployer en votre nom.
# Il prépare, il vérifie, il vous dit quoi lancer.
#
# Ce qu'il vérifie avant de vous laisser publier :
#   • qu'aucun secret ne part dans le dépôt ;
#   • que les trois APK existent et sont signés de la MÊME clé ;
#   • que le site est reconstruit à partir de sa source.

set -euo pipefail

COMPTE="${1:-}"
if [ -z "$COMPTE" ]; then
  echo "usage : ./publier.sh <votre-compte-github>"
  exit 64
fi

RACINE="$(cd "$(dirname "$0")" && pwd)"
cd "$RACINE"

# ⚠️ LE DÉPÔT EST INITIALISÉ AVANT TOUT, ET SANS RIEN ENREGISTRER.
#
# `git check-ignore` a besoin d'un dépôt pour répondre. Sans lui, la
# vérification des secrets répondait « pas ignoré » pour TOUT — y
# compris pour des fichiers parfaitement protégés. Elle refusait donc de
# publier, ce qui est le bon sens de l'erreur, mais pour une raison
# fausse : impossible de distinguer une vraie fuite d'un dépôt absent.
#
# On crée donc le dépôt d'abord, on vérifie ensuite, et on n'enregistre
# QU'APRÈS que tout soit passé.
if [ ! -d .git ]; then
  git init -q
  echo "Dépôt git créé (rien n'est encore enregistré)."
  echo
fi

echo "═══ 1. Aucun secret ne doit partir ═══"
FUITES=0
for f in android/key.properties serveur/.dev.vars; do
  if [ -f "$f" ] && ! git check-ignore -q "$f" 2>/dev/null; then
    echo "  ⚠️  $f n'est PAS ignoré — il contient un secret."
    FUITES=1
  else
    echo "  ✓ $f est ignoré (ou absent)"
  fi
done
if [ "$FUITES" = "1" ]; then
  echo
  echo "ARRÊT. Publier un mot de passe de keystore est irréparable :"
  echo "n'importe qui pourrait signer un APK au nom de Droplet, et le"
  echo "téléphone de vos utilisateurs l'accepterait comme une mise à jour."
  exit 1
fi

echo
echo "═══ 2. Les APK ═══"
APKDIR="build/app/outputs/flutter-apk"
SIGNER="$HOME/Android/Sdk/build-tools/36.1.0/apksigner"
EMPREINTES=""
for abi in armeabi-v7a arm64-v8a x86_64; do
  f="$APKDIR/app-$abi-release.apk"
  if [ ! -f "$f" ]; then
    echo "  ✗ $f manque — lancez : flutter build apk --release --split-per-abi"
    exit 1
  fi
  if [ -x "$SIGNER" ]; then
    e=$("$SIGNER" verify --print-certs "$f" 2>/dev/null \
        | grep -m1 'SHA-256 digest' | awk '{print $NF}')
    echo "  ✓ $abi  $(du -h "$f" | cut -f1)  ${e:0:16}…"
    EMPREINTES="$EMPREINTES$e\n"
  else
    echo "  ✓ $abi  $(du -h "$f" | cut -f1)  (apksigner absent, signature non vérifiée)"
  fi
done
if [ -n "$EMPREINTES" ]; then
  N=$(printf "%b" "$EMPREINTES" | sort -u | grep -c .)
  if [ "$N" != "1" ]; then
    echo
    echo "ARRÊT : les APK ne portent pas la même signature."
    echo "Android refuserait la mise à jour de l'un vers l'autre."
    exit 1
  fi
  echo "  ✓ signature identique sur les trois"
fi

echo
echo "═══ 3. Le site ═══"
python3 site/construire.py

echo
echo "═══ 4. Le dépôt ═══"
git add -A
if git diff --cached --quiet; then
  echo "  ✓ rien de nouveau à enregistrer"
else
  git commit -qm "Droplet — publication"
  echo "  ✓ enregistré"
fi

# Dernier filet : on relit ce qui est RÉELLEMENT suivi par git, plutôt
# que ce qu'on croit ignoré. Une règle mal écrite dans .gitignore ne se
# voit qu'ici.
SUSPECTS=$(git ls-files | grep -iE 'key\.properties|\.dev\.vars|licence\.key|\.p12$|\.jks$|worker-secrets' || true)
if [ -n "$SUSPECTS" ]; then
  echo
  echo "ARRÊT : ces fichiers sont suivis par git alors qu'ils ne devraient pas :"
  echo "$SUSPECTS"
  echo "Retirez-les avec : git rm --cached <fichier>"
  exit 1
fi
echo "  ✓ aucun secret dans les fichiers suivis"

VERSION="v$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"

cat <<FIN

═══════════════════════════════════════════════════════════════════
TOUT EST PRÊT. Il reste trois commandes, à lancer par vous.
═══════════════════════════════════════════════════════════════════

1. LE DÉPÔT  (créez-le d'abord sur github.com/new, nommé « droplet »)

   git remote add origin https://github.com/$COMPTE/droplet.git
   git branch -M main
   git push -u origin main

2. L'APK  (2 Go par fichier, bande passante publique illimitée)

   Sur github.com/$COMPTE/droplet/releases/new :
     • étiquette   : $VERSION
     • déposez les trois fichiers de $APKDIR/

   Le site pointe déjà vers « latest » : cette adresse restera valable
   à chaque nouvelle version, sans retoucher une ligne.

3. LE SITE  (Cloudflare Pages)

   npx wrangler pages deploy site/public --project-name=droplet

   La première fois, votre navigateur s'ouvrira pour la connexion.

   ⚠️ NE METTEZ PAS L'APK DANS site/public/ : Cloudflare refuse tout
   fichier de plus de 25 Mio, et le vôtre en fait 55. Le déploiement
   échouerait sans dire pourquoi. Il reste sur GitHub Releases, et
   site/_redirects donne quand même une adresse propre sur votre
   domaine.

ENFIN : remplacez <compte> par « $COMPTE » dans site/index.html
(une occurrence, sur le bouton de téléchargement), puis relancez
python3 site/construire.py avant de déployer.

FIN
