#!/bin/bash
# Titre: Script de vérification des flags K3s
# Description: Vérifie la présence de flags dépréciés dans la configuration K3s
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-22
# Version: 1.0.0

set -euo pipefail

# Couleurs pour l'affichage
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                                   ║${NC}"
echo -e "${BLUE}║      ██╗     ██╗ ██████╗ ███╗   ██╗███████╗    ██╗███╗   ██╗      ║${NC}"
echo -e "${BLUE}║      ██║     ██║██╔═══██╗████╗  ██║██╔════╝    ██║████╗  ██║      ║${NC}"
echo -e "${BLUE}║      ██║     ██║██║   ██║██╔██╗ ██║███████╗    ██║██╔██╗ ██║      ║${NC}"
echo -e "${BLUE}║      ██║     ██║██║   ██║██║╚██╗██║╚════██║    ██║██║╚██╗██║      ║${NC}"
echo -e "${BLUE}║      ███████╗██║╚██████╔╝██║ ╚████║███████║    ██║██║ ╚████║      ║${NC}"
echo -e "${BLUE}║      ╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝    ╚═╝╚═╝  ╚═══╝      ║${NC}"
echo -e "${BLUE}║                                                                   ║${NC}"
echo -e "${BLUE}║     ██╗   ██╗███████╗██████╗ ██╗███████╗██╗ ██████╗ █████╗ ████████╗██╗ ██████╗ ███╗   ██╗ ║${NC}"
echo -e "${BLUE}║     ██║   ██║██╔════╝██╔══██╗██║██╔════╝██║██╔════╝██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║ ║${NC}"
echo -e "${BLUE}║     ██║   ██║█████╗  ██████╔╝██║█████╗  ██║██║     ███████║   ██║   ██║██║   ██║██╔██╗ ██║ ║${NC}"
echo -e "${BLUE}║     ╚██╗ ██╔╝██╔══╝  ██╔══██╗██║██╔══╝  ██║██║     ██╔══██║   ██║   ██║██║   ██║██║╚██╗██║ ║${NC}"
echo -e "${BLUE}║      ╚████╔╝ ███████╗██║  ██║██║██║     ██║╚██████╗██║  ██║   ██║   ██║╚██████╔╝██║ ╚████║ ║${NC}"
echo -e "${BLUE}║       ╚═══╝  ╚══════╝╚═╝  ╚═╝╚═╝╚═╝     ╚═╝ ╚═════╝╚═╝  ╚═╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ║${NC}"
echo -e "${BLUE}║                                                                   ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo -e "${YELLOW}     Vérification des flags K3s - v1.0.0${NC}"
echo -e "${BLUE}  ════════════════════════════════════════════════════════${NC}\n"

# Vérification de l'existence du service K3s
if [ ! -f /etc/systemd/system/k3s.service ]; then
    echo -e "${RED}[ERREUR]${NC} Le fichier de service K3s n'existe pas"
    echo -e "${YELLOW}[CONSEIL]${NC} Vérifiez que K3s est installé correctement"
    exit 1
fi

echo -e "${GREEN}[INFO]${NC} Vérification du fichier de service K3s..."
echo -e "${GREEN}[INFO]${NC} Fichier: /etc/systemd/system/k3s.service"

# Liste des flags dépréciés à vérifier
DEPRECATED_FLAGS=(
    "RemoveSelfLink=false"
    "--no-deploy"
)

# Vérification de chaque flag déprécié
FOUND_DEPRECATED_FLAGS=false

for flag in "${DEPRECATED_FLAGS[@]}"; do
    if grep -q "$flag" /etc/systemd/system/k3s.service; then
        echo -e "${RED}[ALERTE]${NC} Flag déprécié trouvé: ${flag}"
        FOUND_DEPRECATED_FLAGS=true
        
        # Affichage de la ligne contenant le flag
        echo -e "${YELLOW}[DÉTAIL]${NC} Ligne contenant le flag:"
        grep --color=always "$flag" /etc/systemd/system/k3s.service
    else
        echo -e "${GREEN}[OK]${NC} Flag déprécié non trouvé: ${flag}"
    fi
done

# Vérification de l'état du service K3s
echo -e "\n${GREEN}[INFO]${NC} Vérification de l'état du service K3s..."
if systemctl is-active --quiet k3s; then
    echo -e "${GREEN}[OK]${NC} Le service K3s est actif"
else
    echo -e "${RED}[ALERTE]${NC} Le service K3s n'est pas actif"
    
    # Affichage des journaux pour le diagnostic
    echo -e "${YELLOW}[JOURNAUX]${NC} Dernières entrées du journal K3s:"
    journalctl -u k3s -n 20 --no-pager
fi

# Résumé
echo -e "\n${GREEN}[INFO]${NC} Résumé de la vérification:"
if [ "$FOUND_DEPRECATED_FLAGS" = true ]; then
    echo -e "${RED}[RÉSULTAT]${NC} Des flags dépréciés ont été trouvés dans la configuration K3s"
    echo -e "${YELLOW}[CONSEIL]${NC} Exécutez le script fix-k3s.sh pour corriger les problèmes"
    exit 1
else
    echo -e "${GREEN}[RÉSULTAT]${NC} Aucun flag déprécié n'a été trouvé dans la configuration K3s"
    echo -e "${GREEN}[CONSEIL]${NC} La configuration K3s est à jour"
    exit 0
fi