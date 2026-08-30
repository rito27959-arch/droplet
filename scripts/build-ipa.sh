# ============================================================================
# TRIGGER BUILD iOS IPA VIA GITHUB ACTIONS
# ============================================================================
#
# Ce script lance le build de l'IPA iOS via GitHub Actions.
#
# PRÉREQUIS :
#   - GitHub CLI (gh) installé
#   - Token GitHub configuré dans .env
#   - Secrets Apple configurés dans GitHub
#
# UTILISATION :
#   chmod +x scripts/build-ipa.sh
#   ./scripts/build-ipa.sh
# ============================================================================

#!/bin/bash
set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Charger les variables d'environnement
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo -e "${RED}❌ Fichier .env non trouvé${NC}"
    echo "Crée le fichier .env avec :"
    echo "GITHUB_TOKEN=ton_token_ici"
    echo "GITHUB_REPO=ton-user/ton-repo"
    exit 1
fi

# Vérifier les variables requises
if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${RED}❌ GITHUB_TOKEN non configuré dans .env${NC}"
    exit 1
fi

if [ -z "$GITHUB_REPO" ]; then
    echo -e "${RED}❌ GITHUB_REPO non configuré dans .env${NC}"
    exit 1
fi

# Vérifier GitHub CLI
if ! command -v gh &> /dev/null; then
    echo -e "${YELLOW}📥 Installation de GitHub CLI...${NC}"
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update
    sudo apt-get install gh -y
fi

# Configurer le token
echo "$GITHUB_TOKEN" | gh auth login --with-token

# Vérifier l'authentification
if ! gh auth status &> /dev/null; then
    echo -e "${RED}❌ Authentification GitHub échouée${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Authentifié sur GitHub${NC}"

# Demander le mode d'export
echo ""
echo -e "${YELLOW}📦 Sélectionne le mode d'export :${NC}"
echo "1) ad-hoc  — Pour AltStore (recommandé)"
echo "2) app-store — Pour App Store"
echo ""
read -p "Choix (1 ou 2) : " CHOICE

case $CHOICE in
    1) EXPORT_METHOD="ad-hoc" ;;
    2) EXPORT_METHOD="app-store" ;;
    *) EXPORT_METHOD="ad-hoc" ;;
esac

echo -e "${GREEN}✅ Mode sélectionné : $EXPORT_METHOD${NC}"

# Lancer le workflow
echo ""
echo -e "${YELLOW}🚀 Lancement du build iOS...${NC}"

gh workflow run "Build iOS IPA Release" \
    --repo "$GITHUB_REPO" \
    --field "export_method=$EXPORT_METHOD"

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}✅ BUILD LANCÉ${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "Suivi du build :"
echo "  $ gh run watch --repo $GITHUB_REPO"
echo ""
echo "Ou ouvre dans le navigateur :"
echo "  https://github.com/$GITHUB_REPO/actions"
echo ""
echo "L'IPA sera disponible dans l'onglet Artifacts (~15-20 min)"
