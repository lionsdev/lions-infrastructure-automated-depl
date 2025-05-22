#!/bin/bash
# Titre: Script de mise à jour du playbook Ansible K3s
# Description: Modifie le playbook Ansible pour supprimer le flag RemoveSelfLink=false
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-22
# Version: 1.1.0
#
# Note: Ce script a été mis à jour pour vérifier la présence des tâches
# de vérification proactive des drapeaux dépréciés dans le playbook Ansible.
# Ces tâches empêchent les problèmes liés aux drapeaux dépréciés comme
# RemoveSelfLink=false en les supprimant avant le démarrage du service K3s.

set -euo pipefail

# Couleurs pour l'affichage
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Chemins des fichiers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLAYBOOK_PATH="${PROJECT_ROOT}/ansible/playbooks/install-k3s.yml"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                                   ║${NC}"
echo -e "${BLUE}║      ██╗     ██╗ ██████╗ ███╗   ██╗███████╗    ██╗███╗   ██╗      ║${NC}"
echo -e "${BLUE}║      ██║     ██║██╔═══██╗████╗  ██║██╔════╝    ██║████╗  ██║      ║${NC}"
echo -e "${BLUE}║      ██║     ██║██║   ██║██╔██╗ ██║███████╗    ██║██╔██╗ ██║      ║${NC}"
echo -e "${BLUE}║      ██║     ██║██║   ██║██║╚██╗██║╚════██║    ██║██║╚██╗██║      ║${NC}"
echo -e "${BLUE}║      ███████╗██║╚██████╔╝██║ ╚████║███████║    ██║██║ ╚████║      ║${NC}"
echo -e "${BLUE}║      ╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝    ╚═╝╚═╝  ╚═══╝      ║${NC}"
echo -e "${BLUE}║                                                                   ║${NC}"
echo -e "${BLUE}║     ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗            ║${NC}"
echo -e "${BLUE}║     ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝            ║${NC}"
echo -e "${BLUE}║     ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗              ║${NC}"
echo -e "${BLUE}║     ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝              ║${NC}"
echo -e "${BLUE}║     ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗            ║${NC}"
echo -e "${BLUE}║      ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝            ║${NC}"
echo -e "${BLUE}║                                                                   ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo -e "${YELLOW}     Mise à jour du playbook Ansible K3s - v1.0.0${NC}"
echo -e "${BLUE}  ════════════════════════════════════════════════════════${NC}\n"

# Vérification de l'existence du playbook
if [ ! -f "${PLAYBOOK_PATH}" ]; then
    echo -e "${RED}[ERREUR]${NC} Le playbook Ansible n'existe pas: ${PLAYBOOK_PATH}"
    exit 1
fi

echo -e "${GREEN}[INFO]${NC} Sauvegarde du playbook Ansible..."
cp "${PLAYBOOK_PATH}" "${PLAYBOOK_PATH}.bak.$(date +%Y%m%d%H%M%S)"

echo -e "${GREEN}[INFO]${NC} Mise à jour du playbook Ansible..."

# Modification des arguments du serveur K3s pour supprimer le flag RemoveSelfLink=false
sed -i 's/--kubelet-arg feature-gates=GracefulNodeShutdown=false --kube-controller-manager-arg feature-gates=RemoveSelfLink=false/--kubelet-arg feature-gates=GracefulNodeShutdown=false/g' "${PLAYBOOK_PATH}"

# Vérification que la modification a été appliquée
if grep -q "RemoveSelfLink=false" "${PLAYBOOK_PATH}"; then
    echo -e "${RED}[ERREUR]${NC} La modification n'a pas été appliquée correctement"
    echo -e "${YELLOW}[CONSEIL]${NC} Vérifiez le playbook manuellement: ${PLAYBOOK_PATH}"
    exit 1
else
    echo -e "${GREEN}[SUCCÈS]${NC} Le playbook Ansible a été mis à jour avec succès"
fi

echo -e "\n${GREEN}[INFO]${NC} Vérification des tâches de correction existantes..."

# Vérification que la tâche de suppression du flag existe toujours
if grep -q "Suppression du flag RemoveSelfLink=false" "${PLAYBOOK_PATH}"; then
    echo -e "${GREEN}[INFO]${NC} La tâche de suppression du flag existe déjà dans le playbook"
else
    echo -e "${YELLOW}[AVERTISSEMENT]${NC} La tâche de suppression du flag n'a pas été trouvée dans le playbook"
    echo -e "${YELLOW}[CONSEIL]${NC} Vérifiez le playbook manuellement: ${PLAYBOOK_PATH}"
fi

# Vérification que les tâches de vérification proactive existent
echo -e "\n${GREEN}[INFO]${NC} Vérification des tâches de vérification proactive..."

if grep -q "Vérification et correction proactive des drapeaux dépréciés" "${PLAYBOOK_PATH}"; then
    echo -e "${GREEN}[INFO]${NC} Les tâches de vérification proactive existent déjà dans le playbook"
else
    echo -e "${YELLOW}[AVERTISSEMENT]${NC} Les tâches de vérification proactive n'ont pas été trouvées dans le playbook"
    echo -e "${YELLOW}[CONSEIL]${NC} Exécutez le script de mise à jour complet pour ajouter ces tâches"

    # Vérification de la présence de la variable deprecated_flags
    if ! grep -q "deprecated_flags:" "${PLAYBOOK_PATH}"; then
        echo -e "${YELLOW}[INFO]${NC} Ajout de la variable deprecated_flags au playbook..."

        # Ajout de la variable deprecated_flags après les variables existantes
        sed -i '/traefik_version:/a \    deprecated_flags:\n      - name: "RemoveSelfLink=false"\n        regexp: "--kube-controller-manager-arg feature-gates=RemoveSelfLink=false"\n        replace: ""\n      - name: "no-deploy"\n        regexp: "--no-deploy ([a-zA-Z0-9-]+)"\n        replace: "--disable=\\\\1"' "${PLAYBOOK_PATH}"

        echo -e "${GREEN}[SUCCESS]${NC} Variable deprecated_flags ajoutée au playbook"
    fi
fi

echo -e "\n${GREEN}[SUCCÈS]${NC} La mise à jour du playbook Ansible est terminée"
echo -e "${YELLOW}[CONSEIL]${NC} Vérifiez le playbook manuellement pour vous assurer que les modifications sont correctes"
