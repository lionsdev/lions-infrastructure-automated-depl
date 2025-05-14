#!/bin/bash
# Titre: Script de déploiement Ollama via playbook standard
# Description: Utilise le playbook deploy-application.yml pour déployer Ollama
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-14
# Version: 1.0.0

set -euo pipefail

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variables par défaut
ENVIRONMENT="${1:-production}"
VERSION="${2:-latest}"
APPLICATION_NAME="ollama"
TECHNOLOGY="ollama"

# Naviguer vers le répertoire ansible
cd /lions-infrastructure-automated-depl/lions-infrastructure/ansible

echo -e "${GREEN}[INFO]${NC} Déploiement d'Ollama..."
echo -e "${GREEN}[INFO]${NC} Application: ${APPLICATION_NAME}"
echo -e "${GREEN}[INFO]${NC} Environnement: ${ENVIRONMENT}"
echo -e "${GREEN}[INFO]${NC} Version: ${VERSION}"
echo -e "${GREEN}[INFO]${NC} Technology: ${TECHNOLOGY}"

# Déployer avec le playbook standard deploy-application.yml
ansible-playbook \
    -i inventories/${ENVIRONMENT}/hosts.yml \
    playbooks/deploy-application.yml \
    -e "application_name=${APPLICATION_NAME}" \
    -e "environment=${ENVIRONMENT}" \
    -e "technology=${TECHNOLOGY}" \
    -e "version=${VERSION}" \
    -e "config_file=/lions-infrastructure-automated-depl/lions-infrastructure/applications/catalog/ollama/application.yaml"

# Vérifier le déploiement
echo -e "${GREEN}[INFO]${NC} Vérification du déploiement..."
kubectl get pods -n ${APPLICATION_NAME}-${ENVIRONMENT} -l app=${APPLICATION_NAME}
kubectl get ingress -n ${APPLICATION_NAME}-${ENVIRONMENT}

echo -e "${GREEN}[INFO]${NC} ✅ Déploiement terminé!"
echo -e "${GREEN}[INFO]${NC} 🌐 URL: https://${APPLICATION_NAME}.${ENVIRONMENT}.lions.dev"

# Tester l'API
echo -e "${GREEN}[INFO]${NC} Test de l'API..."
sleep 10
curl -s https://${APPLICATION_NAME}.${ENVIRONMENT}.lions.dev/api/tags | jq .