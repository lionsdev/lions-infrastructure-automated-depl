#!/bin/bash
# Titre: Script de correction du service K3s
# Description: Supprime le flag RemoveSelfLink=false qui cause des erreurs dans K3s
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-22
# Version: 1.1.0
#
# Note: Ce script est destiné à corriger les installations existantes.
# Pour les nouvelles installations, le playbook Ansible install-k3s.yml
# inclut désormais une vérification proactive des drapeaux dépréciés
# qui empêche ce problème de se produire.

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
echo -e "${BLUE}║     ███████╗██╗██╗  ██╗      ██╗  ██╗██████╗ ███████╗             ║${NC}"
echo -e "${BLUE}║     ██╔════╝██║╚██╗██╔╝      ██║ ██╔╝╚════██╗██╔════╝             ║${NC}"
echo -e "${BLUE}║     █████╗  ██║ ╚███╔╝ █████╗█████╔╝  █████╔╝███████╗             ║${NC}"
echo -e "${BLUE}║     ██╔══╝  ██║ ██╔██╗ ╚════╝██╔═██╗  ╚═══██╗╚════██║             ║${NC}"
echo -e "${BLUE}║     ██║     ██║██╔╝ ██╗      ██║  ██╗██████╔╝███████║             ║${NC}"
echo -e "${BLUE}║     ╚═╝     ╚═╝╚═╝  ╚═╝      ╚═╝  ╚═╝╚═════╝ ╚══════╝             ║${NC}"
echo -e "${BLUE}║                                                                   ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo -e "${YELLOW}     Correction du service K3s - v1.0.0${NC}"
echo -e "${BLUE}  ════════════════════════════════════════════════════════${NC}\n"

# Vérification des privilèges root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[ERREUR]${NC} Ce script doit être exécuté en tant que root"
    echo -e "${YELLOW}[CONSEIL]${NC} Exécutez ce script avec sudo: sudo $0"
    exit 1
fi

# Vérification de l'existence du service K3s
if [ ! -f /etc/systemd/system/k3s.service ]; then
    echo -e "${RED}[ERREUR]${NC} Le fichier de service K3s n'existe pas"
    echo -e "${YELLOW}[CONSEIL]${NC} Vérifiez que K3s est installé correctement"
    exit 1
fi

echo -e "${GREEN}[INFO]${NC} Arrêt du service K3s..."
systemctl stop k3s

echo -e "${GREEN}[INFO]${NC} Sauvegarde du fichier de service K3s..."
cp /etc/systemd/system/k3s.service /etc/systemd/system/k3s.service.bak.$(date +%Y%m%d%H%M%S)

echo -e "${GREEN}[INFO]${NC} Suppression du flag RemoveSelfLink=false du fichier de service K3s..."
sed -i 's/--kube-controller-manager-arg feature-gates=RemoveSelfLink=false//' /etc/systemd/system/k3s.service

echo -e "${GREEN}[INFO]${NC} Rechargement de la configuration systemd..."
systemctl daemon-reload

echo -e "${GREEN}[INFO]${NC} Démarrage du service K3s..."
systemctl start k3s

# Attente que le service démarre
echo -e "${GREEN}[INFO]${NC} Attente que le service K3s démarre..."
sleep 10

# Vérification de l'état du service
echo -e "${GREEN}[INFO]${NC} Vérification de l'état du service K3s..."
if systemctl is-active --quiet k3s; then
    echo -e "${GREEN}[SUCCÈS]${NC} Le service K3s a été démarré avec succès"
else
    echo -e "${RED}[ERREUR]${NC} Le service K3s n'a pas pu être démarré"
    echo -e "${YELLOW}[CONSEIL]${NC} Vérifiez les journaux avec: journalctl -u k3s -n 50"

    # Affichage des journaux pour le diagnostic
    echo -e "${YELLOW}[JOURNAUX]${NC} Dernières entrées du journal K3s:"
    journalctl -u k3s -n 50 --no-pager

    exit 1
fi

echo -e "${GREEN}[INFO]${NC} Vérification de l'accès à l'API Kubernetes..."
if timeout 30s kubectl get nodes &>/dev/null; then
    echo -e "${GREEN}[SUCCÈS]${NC} L'API Kubernetes est accessible"
else
    echo -e "${YELLOW}[AVERTISSEMENT]${NC} L'API Kubernetes n'est pas encore accessible"
    echo -e "${YELLOW}[CONSEIL]${NC} Cela peut prendre quelques minutes pour que l'API soit complètement opérationnelle"
fi

echo -e "\n${GREEN}[SUCCÈS]${NC} La correction du service K3s est terminée"
echo -e "${YELLOW}[CONSEIL]${NC} Si vous rencontrez d'autres problèmes, consultez les journaux avec: journalctl -u k3s"
