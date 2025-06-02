#!/bin/bash
# Titre: Script de déploiement des services LIONS
# Description: Déploie les services d'application LIONS
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-16
# Version: 1.0.0

set -euo pipefail

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
LOG_DIR="${SCRIPT_DIR}/logs/applications"
ENVIRONMENT="${1:-development}"

# Détection d'exécution locale
IS_LOCAL_EXECUTION=false

# Fonction pour détecter si le script est exécuté sur le VPS cible
function is_local_execution() {
    local target_host="$1"

    # Si l'hôte cible est localhost ou 127.0.0.1, c'est une exécution locale
    if [[ "${target_host}" == "localhost" || "${target_host}" == "127.0.0.1" ]]; then
        return 0
    fi

    # Récupération des adresses IP locales
    local local_ips=$(ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1 | tr '\n' ' ' 2>/dev/null || echo "")

    # Si l'hôte cible est une des adresses IP locales, c'est une exécution locale
    for ip in ${local_ips}; do
        if [[ "${target_host}" == "${ip}" ]]; then
            return 0
        fi
    done

    # Vérification du nom d'hôte
    local hostname=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "")
    if [[ -n "${hostname}" && "${target_host}" == "${hostname}" ]]; then
        return 0
    fi

    # Vérification si on est déjà connecté via SSH (en vérifiant la variable SSH_CONNECTION)
    if [[ -n "${SSH_CONNECTION}" ]]; then
        # Extraire l'adresse IP du serveur SSH depuis SSH_CONNECTION
        local ssh_server_ip=$(echo "${SSH_CONNECTION}" | awk '{print $3}')

        # Si l'adresse IP du serveur SSH correspond à l'hôte cible, on est déjà connecté
        if [[ "${ssh_server_ip}" == "${target_host}" ]]; then
            return 0
        fi

        # Vérifier également si l'hôte cible est résolu vers l'adresse IP du serveur SSH
        local resolved_ip=$(getent hosts "${target_host}" 2>/dev/null | awk '{print $1}' | head -1)
        if [[ -n "${resolved_ip}" && "${resolved_ip}" == "${ssh_server_ip}" ]]; then
            return 0
        fi
    fi

    # Ce n'est pas une exécution locale
    return 1
}

# Création des répertoires de logs
mkdir -p "${LOG_DIR}"

# Affichage du logo
echo -e "${BLUE}"
echo -e "╔═══════════════════════════════════════════════════════════════════╗"
echo -e "║                                                                   ║"
echo -e "║      ██╗     ██╗ ██████╗ ███╗   ██╗███████╗    ██╗███╗   ██╗      ║"
echo -e "║      ██║     ██║██╔═══██╗████╗  ██║██╔════╝    ██║████╗  ██║      ║"
echo -e "║      ██║     ██║██║   ██║██╔██╗ ██║███████╗    ██║██╔██╗ ██║      ║"
echo -e "║      ██║     ██║██║   ██║██║╚██╗██║╚════██║    ██║██║╚██╗██║      ║"
echo -e "║      ███████╗██║╚██████╔╝██║ ╚████║███████║    ██║██║ ╚████║      ║"
echo -e "║      ╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝    ╚═╝╚═╝  ╚═══╝      ║"
echo -e "║                                                                   ║"
echo -e "║     ███████╗███████╗██████╗ ██╗   ██╗██╗ ██████╗███████╗███████╗  ║"
echo -e "║     ██╔════╝██╔════╝██╔══██╗██║   ██║██║██╔════╝██╔════╝██╔════╝  ║"
echo -e "║     ███████╗█████╗  ██████╔╝██║   ██║██║██║     █████╗  ███████╗  ║"
echo -e "║     ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██║██║     ██╔══╝  ╚════██║  ║"
echo -e "║     ███████║███████╗██║  ██║ ╚████╔╝ ██║╚██████╗███████╗███████║  ║"
echo -e "║     ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚═╝ ╚═════╝╚══════╝╚══════╝  ║"
echo -e "║                                                                   ║"
echo -e "╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo -e "${YELLOW}     Déploiement des Services LIONS - v1.0.0${NC}"
echo -e "${BLUE}  ════════════════════════════════════════════════════════${NC}\n"

# Vérification des prérequis
echo -e "${GREEN}[INFO]${NC} Vérification des prérequis..."

# Détection d'exécution locale
target_host="localhost"
# Si on a un inventaire Ansible, on peut extraire l'hôte cible
if [[ -f "${ANSIBLE_DIR}/inventories/${ENVIRONMENT}/hosts.yml" ]]; then
    target_host=$(grep -A10 "hosts:" "${ANSIBLE_DIR}/inventories/${ENVIRONMENT}/hosts.yml" | grep "ansible_host:" | head -1 | awk -F': ' '{print $2}' | tr -d ' ' 2>/dev/null || echo "localhost")
fi

if is_local_execution "${target_host}"; then
    IS_LOCAL_EXECUTION=true
    echo -e "${GREEN}[INFO]${NC} Détection d'exécution locale: le script est exécuté directement sur le VPS cible ou via une connexion SSH existante"
    echo -e "${GREEN}[INFO]${NC} Les commandes SSH seront remplacées par des commandes locales"
else
    IS_LOCAL_EXECUTION=false
    echo -e "${GREEN}[INFO]${NC} Détection d'exécution distante: le script est exécuté depuis une machine différente du VPS cible"
fi

# Vérification de kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} kubectl n'est pas installé ou n'est pas dans le PATH"
    exit 1
fi

# Vérification de l'accès au cluster Kubernetes
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Impossible d'accéder au cluster Kubernetes"
    echo -e "${YELLOW}[TIP]${NC} Vérifiez votre configuration kubectl et le fichier kubeconfig"
    exit 1
fi

# Vérification d'Ansible
if ! command -v ansible-playbook &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} ansible-playbook n'est pas installé ou n'est pas dans le PATH"
    exit 1
fi

echo -e "${GREEN}[INFO]${NC} Déploiement des services pour l'environnement: ${ENVIRONMENT}"

# Exécution du playbook Ansible
echo -e "${GREEN}[INFO]${NC} Exécution du playbook de déploiement des services..."

# Construction de la commande Ansible
ansible_cmd="ansible-playbook \"${ANSIBLE_DIR}/playbooks/deploy-application-services.yml\" --extra-vars \"target_env=${ENVIRONMENT}\""

# Si exécution locale, utiliser la connexion locale
if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
    ansible_cmd="${ansible_cmd} -c local"
    echo -e "${GREEN}[INFO]${NC} Utilisation de la connexion locale pour Ansible"
else
    ansible_cmd="${ansible_cmd} --ask-become-pass"
fi

# Exécution de la commande
eval ${ansible_cmd}

# Vérification du déploiement
echo -e "${GREEN}[INFO]${NC} Vérification du déploiement..."

# Liste des services à vérifier
SERVICES=(
    "api-principale"
    "associations-api"
    "afterwork-api"
    "bacy-event-api"
    "btp-api"
    "immobilier-api"
    "mail-api"
    "afterwork-app"
    "associations-app"
    "btp-app"
    "immobilier-app"
    "mail-service"
)

# Vérification des services
for service in "${SERVICES[@]}"; do
    namespace="${service}-${ENVIRONMENT}"

    echo -e "${GREEN}[INFO]${NC} Vérification du service ${service} dans le namespace ${namespace}..."

    # Vérification du namespace
    if ! kubectl get namespace "${namespace}" &> /dev/null; then
        echo -e "${YELLOW}[WARNING]${NC} Le namespace ${namespace} n'existe pas"
        continue
    fi

    # Vérification des pods
    pods=$(kubectl get pods -n "${namespace}" -o jsonpath='{.items[*].metadata.name}')
    if [[ -z "${pods}" ]]; then
        echo -e "${YELLOW}[WARNING]${NC} Aucun pod trouvé dans le namespace ${namespace}"
    else
        echo -e "${GREEN}[SUCCESS]${NC} Pods trouvés dans le namespace ${namespace}: ${pods}"
    fi

    # Vérification des services
    services=$(kubectl get services -n "${namespace}" -o jsonpath='{.items[*].metadata.name}')
    if [[ -z "${services}" ]]; then
        echo -e "${YELLOW}[WARNING]${NC} Aucun service trouvé dans le namespace ${namespace}"
    else
        echo -e "${GREEN}[SUCCESS]${NC} Services trouvés dans le namespace ${namespace}: ${services}"
    fi

    # Vérification des ingress
    ingresses=$(kubectl get ingress -n "${namespace}" -o jsonpath='{.items[*].metadata.name}')
    if [[ -z "${ingresses}" ]]; then
        echo -e "${YELLOW}[WARNING]${NC} Aucun ingress trouvé dans le namespace ${namespace}"
    else
        echo -e "${GREEN}[SUCCESS]${NC} Ingresses trouvés dans le namespace ${namespace}: ${ingresses}"
    fi
done

# Vérification des ingress pour les services d'infrastructure
echo -e "${GREEN}[INFO]${NC} Vérification des ingress pour les services d'infrastructure..."

# Liste des ingress à vérifier
INGRESSES=(
    "kubernetes-dashboard:kubernetes-dashboard"
    "grafana:monitoring"
    "prometheus:monitoring"
    "pgadmin:pgadmin-${ENVIRONMENT}"
    "gitea:gitea-${ENVIRONMENT}"
    "keycloak:keycloak-${ENVIRONMENT}"
)

# Vérification des ingress
for ingress_info in "${INGRESSES[@]}"; do
    IFS=':' read -r ingress namespace <<< "${ingress_info}"

    echo -e "${GREEN}[INFO]${NC} Vérification de l'ingress ${ingress} dans le namespace ${namespace}..."

    # Vérification du namespace
    if ! kubectl get namespace "${namespace}" &> /dev/null; then
        echo -e "${YELLOW}[WARNING]${NC} Le namespace ${namespace} n'existe pas"
        continue
    fi

    # Vérification de l'ingress
    if ! kubectl get ingress "${ingress}" -n "${namespace}" &> /dev/null; then
        echo -e "${YELLOW}[WARNING]${NC} L'ingress ${ingress} n'existe pas dans le namespace ${namespace}"
    else
        host=$(kubectl get ingress "${ingress}" -n "${namespace}" -o jsonpath='{.spec.rules[0].host}')
        echo -e "${GREEN}[SUCCESS]${NC} Ingress ${ingress} trouvé dans le namespace ${namespace}, accessible à l'adresse: https://${host}"
    fi
done

echo -e "\n${GREEN}[SUCCESS]${NC} Déploiement des services terminé avec succès!"
echo -e "${BLUE}[INFO]${NC} Vous pouvez accéder aux services via les URLs suivantes:"
echo -e "${BLUE}[INFO]${NC} - Site principal: https://lions.dev"
echo -e "${BLUE}[INFO]${NC} - API principale: https://api.lions.dev/portail"
echo -e "${BLUE}[INFO]${NC} - Associations API: https://api.lions.dev/associations"
echo -e "${BLUE}[INFO]${NC} - Associations App: https://associations.lions.dev"
echo -e "${BLUE}[INFO]${NC} - Afterwork API: https://api.lions.dev/afterwork"
echo -e "${BLUE}[INFO]${NC} - Afterwork App: https://afterwork.lions.dev"
echo -e "${BLUE}[INFO]${NC} - BTP API: https://api.lions.dev/btp"
echo -e "${BLUE}[INFO]${NC} - BTP App: https://btp.lions.dev"
echo -e "${BLUE}[INFO]${NC} - Immobilier API: https://api.lions.dev/immobilier"
echo -e "${BLUE}[INFO]${NC} - Immobilier App: https://immobilier.lions.dev"
echo -e "${BLUE}[INFO]${NC} - Mail API: https://api.lions.dev/mail"
echo -e "${BLUE}[INFO]${NC} - Mail Service: https://mail.lions.dev"
echo -e "${BLUE}[INFO]${NC} - Kubernetes Dashboard: https://k8s.lions.dev"
echo -e "${BLUE}[INFO]${NC} - Grafana: https://grafana.lions.dev"
echo -e "${BLUE}[INFO]${NC} - Prometheus: https://prometheus.lions.dev"
echo -e "${BLUE}[INFO]${NC} - pgAdmin: https://pgadmin.lions.dev"
echo -e "${BLUE}[INFO]${NC} - Gitea: https://git.lions.dev"
echo -e "${BLUE}[INFO]${NC} - Keycloak: https://keycloak.lions.dev"
