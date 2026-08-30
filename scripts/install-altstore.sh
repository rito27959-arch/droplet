# ============================================================================
# INSTALL ALTSTORE SUR LINUX (Ubuntu/Debian)
# ============================================================================
#
# Ce script installe AltServer pour Linux et AltStore sur ton iPhone.
#
# PRÉREQUIS :
#   - iPhone branché en USB
#   - iPhone déverrouillé
#   - Connexion Internet
#
# UTILISATION :
#   chmod +x scripts/install-altstore.sh
#   ./scripts/install-altstore.sh
# ============================================================================

#!/bin/bash
set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}📱 Installation d'AltStore sur Linux${NC}"
echo "================================================"

# Vérifier si on est sur Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo -e "${RED}❌ Ce script est pour Linux uniquement${NC}"
    exit 1
fi

# Vérifier si iPhone est connecté
echo -e "${YELLOW}🔍 Vérification de l'iPhone...${NC}"
if ! command -v idevice_id &> /dev/null; then
    echo -e "${YELLOW}📥 Installation de libimobiledevice...${NC}"
    sudo apt-get update
    sudo apt-get install -y libimobiledevice6 libimobiledevice-utils usbmuxd
fi

# Vérifier la connexion iPhone
if ! idevice_id -l | grep -q .; then
    echo -e "${RED}❌ Aucun iPhone détecté. Branche ton iPhone et déverrouille-le.${NC}"
    exit 1
fi

DEVICE_UDID=$(idevice_id -l | head -1)
echo -e "${GREEN}✅ iPhone détecté : $DEVICE_UDID${NC}"

# Installer AltServer pour Linux
echo -e "${YELLOW}📥 Installation d'AltServer...${NC}"

# Télécharger AltServer Linux
ALTSERVER_URL="https://github.com/nickalt/AltServer-Linux/releases/latest/download/AltServer.AppImage"
ALTSERVER_DIR="$HOME/.local/bin"
ALTSERVER_PATH="$ALTSERVER_DIR/AltServer"

mkdir -p "$ALTSERVER_DIR"

if [ ! -f "$ALTSERVER_PATH" ]; then
    echo "Téléchargement d'AltServer..."
    curl -L -o "$ALTSERVER_PATH" "$ALTSERVER_URL"
    chmod +x "$ALTSERVER_PATH"
    echo -e "${GREEN}✅ AltServer installé dans $ALTSERVER_DIR${NC}"
else
    echo -e "${GREEN}✅ AltServer déjà installé${NC}"
fi

# Ajouter au PATH si nécessaire
if [[ ":$PATH:" != *":$ALTSERVER_DIR:"* ]]; then
    echo "export PATH=\"\$PATH:$ALTSERVER_DIR\"" >> "$HOME/.bashrc"
    echo -e "${YELLOW}⚠️  Redémarre ton terminal ou exécute : export PATH=\"\$PATH:$ALTSERVER_DIR\"${NC}"
fi

# Installer usbmuxd (nécessaire pour la communication USB)
echo -e "${YELLOW}🔍 Vérification de usbmuxd...${NC}"
if ! command -v usbmuxd &> /dev/null; then
    sudo apt-get install -y usbmuxd
fi

# Démarrer usbmuxd
sudo systemctl start usbmuxd
sudo systemctl enable usbmuxd

# Installer AltStore sur l'iPhone
echo -e "${YELLOW}📱 Installation d'AltStore sur l'iPhone...${NC}"
echo ""
echo "ÉTAPES MANUELLES :"
echo "1. Lance AltServer : $ALTSERVER_PATH"
echo "2. Ouvre AltServer dans la barre des tâches"
echo "3. Clique sur l'icône AltServer → Install AltStore → ton iPhone"
echo "4. Connecte-toi avec ton Apple ID"
echo ""
echo -e "${GREEN}⏳ Attends l'installation sur ton iPhone...${NC}"
echo ""

# Lancer AltServer
if command -v AltServer &> /dev/null; then
    AltServer &
    echo -e "${GREEN}✅ AltServer lancé. Suis les instructions dans l'interface.${NC}"
else
    echo -e "${YELLOW}⚠️  Lance manuellement : $ALTSERVER_PATH${NC}"
fi

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}✅ INSTALLATION TERMINÉE${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "PROCHAINES ÉTAPES :"
echo "1. Ouvre AltStore sur ton iPhone"
echo "2. Va dans Settings → signe-toi avec ton Apple ID"
echo "3. Télécharge l'IPA depuis GitHub Actions"
echo "4. Ouvre l'IPA dans AltStore"
echo ""
echo "⚠️  L'IPA expire après 7 jours. Relance-la via AltStore."
