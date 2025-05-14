#!/bin/bash
# Titre: Script de déploiement Ollama via playbook standard (corrigé)
# Description: Utilise le playbook deploy-application.yml pour déployer Ollama
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-14
# Version: 1.1.0

set -euo pipefail

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variables par défaut
DEPLOY_ENV="${1:-production}"  # Renommé pour éviter collision avec variable réservée
VERSION="${2:-latest}"
APPLICATION_NAME="ollama"
TECHNOLOGY="ollama"

# Déterminer le domaine selon l'environnement
case "$DEPLOY_ENV" in
    production)
        DOMAIN_SUFFIX="lions.dev"
        ;;
    staging)
        DOMAIN_SUFFIX="staging.lions.dev"
        ;;
    development)
        DOMAIN_SUFFIX="dev.lions.dev"
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} Environnement inconnu: $DEPLOY_ENV"
        exit 1
        ;;
esac

# Naviguer vers le répertoire ansible
cd /lions-infrastructure-automated-depl/lions-infrastructure/ansible

echo -e "${GREEN}[INFO]${NC} Déploiement d'Ollama..."
echo -e "${GREEN}[INFO]${NC} Application: ${APPLICATION_NAME}"
echo -e "${GREEN}[INFO]${NC} Environnement: ${DEPLOY_ENV}"
echo -e "${GREEN}[INFO]${NC} Version: ${VERSION}"
echo -e "${GREEN}[INFO]${NC} Technology: ${TECHNOLOGY}"
echo -e "${GREEN}[INFO]${NC} Domaine: ${APPLICATION_NAME}.${DOMAIN_SUFFIX}"

# Exporter KUBECONFIG si nécessaire
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}

# Déployer avec le playbook standard deploy-application.yml
# Utiliser --ask-become-pass si nécessaire
ansible-playbook \
    -i inventories/${DEPLOY_ENV}/hosts.yml \
    playbooks/deploy-application.yml \
    -e "application_name=${APPLICATION_NAME}" \
    -e "environment=${DEPLOY_ENV}" \
    -e "technology=${TECHNOLOGY}" \
    -e "version=${VERSION}" \
    -e "config_file=/lions-infrastructure-automated-depl/lions-infrastructure/applications/catalog/ollama/application.yaml" \
    -e "ansible_become_method=sudo" \
    -e "ansible_become=yes" \
    --ask-become-pass

# Vérifier le déploiement
echo -e "${GREEN}[INFO]${NC} Vérification du déploiement..."
kubectl get pods -n ${APPLICATION_NAME}-${DEPLOY_ENV} -l app=${APPLICATION_NAME}
kubectl get ingress -n ${APPLICATION_NAME}-${DEPLOY_ENV}

echo -e "${GREEN}[INFO]${NC} ✅ Déploiement terminé!"
echo -e "${GREEN}[INFO]${NC} 🌐 URL: https://${APPLICATION_NAME}.${DOMAIN_SUFFIX}"

# Tester l'API
echo -e "${GREEN}[INFO]${NC} Test de l'API..."
sleep 10
curl -s https://${APPLICATION_NAME}.${DOMAIN_SUFFIX}/api/tags | jq . || echo -e "${YELLOW}[WARNING]${NC} API pas encore disponible"