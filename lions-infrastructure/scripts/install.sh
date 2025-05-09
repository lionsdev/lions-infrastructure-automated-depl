#!/bin/bash
# Titre: Script d'installation de l'infrastructure LIONS sur VPS
# Description: Orchestre l'installation complète de l'infrastructure LIONS sur un VPS
# Auteur: Équipe LIONS Infrastructure
# Date: 2023-05-15
# Version: 1.0.0

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
readonly LOG_DIR="./logs/infrastructure"
readonly LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
readonly DEFAULT_ENV="development"

# Couleurs pour l'affichage
readonly COLOR_RESET="\033[0m"
readonly COLOR_RED="\033[0;31m"
readonly COLOR_GREEN="\033[0;32m"
readonly COLOR_YELLOW="\033[0;33m"
readonly COLOR_BLUE="\033[0;34m"
readonly COLOR_MAGENTA="\033[0;35m"
readonly COLOR_CYAN="\033[0;36m"
readonly COLOR_WHITE="\033[0;37m"
readonly COLOR_BOLD="\033[1m"

# Création du répertoire de logs
mkdir -p "${LOG_DIR}"

# Fonction de logging
function log() {
    local level="$1"
    local message="$2"
    local timestamp="$(date +"%Y-%m-%d %H:%M:%S")"

    echo -e "${COLOR_BOLD}[${timestamp}] [${level}]${COLOR_RESET} ${message}"
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Fonction d'affichage de l'aide
function afficher_aide() {
    cat << EOF
Script d'Installation de l'Infrastructure LIONS sur VPS

Ce script orchestre l'installation complète de l'infrastructure LIONS sur un VPS.

Usage:
    $0 [options]

Options:
    -e, --environment <env>   Environnement cible (production, staging, development)
                             Par défaut: development
    -i, --inventory <file>    Fichier d'inventaire Ansible spécifique
                             Par défaut: inventories/development/hosts.yml
    -s, --skip-init           Ignorer l'initialisation du VPS (si déjà effectuée)
    -d, --debug               Active le mode debug
    -h, --help                Affiche cette aide

Exemples:
    $0
    $0 --environment staging
    $0 --skip-init --debug
EOF
}

# Fonction de vérification des prérequis
function verifier_prerequis() {
    log "INFO" "Vérification des prérequis..."

    # Vérification d'Ansible
    if ! command -v ansible-playbook &> /dev/null; then
        log "ERROR" "ansible-playbook n'est pas installé ou n'est pas dans le PATH"
        exit 1
    fi

    # Vérification de SSH
    if ! command -v ssh &> /dev/null; then
        log "ERROR" "ssh n'est pas installé ou n'est pas dans le PATH"
        exit 1
    fi

    # Vérification des fichiers Ansible
    if [[ ! -d "${ANSIBLE_DIR}/inventories/${environment}" ]]; then
        log "ERROR" "Le répertoire d'inventaire pour l'environnement ${environment} n'existe pas"
        exit 1
    fi

    if [[ ! -f "${ANSIBLE_DIR}/${inventory_file}" ]]; then
        log "ERROR" "Le fichier d'inventaire n'existe pas: ${ANSIBLE_DIR}/${inventory_file}"
        exit 1
    fi

    if [[ ! -f "${ANSIBLE_DIR}/playbooks/init-vps.yml" ]]; then
        log "ERROR" "Le playbook d'initialisation du VPS n'existe pas"
        exit 1
    fi

    if [[ ! -f "${ANSIBLE_DIR}/playbooks/install-k3s.yml" ]]; then
        log "ERROR" "Le playbook d'installation de K3s n'existe pas"
        exit 1
    fi

    log "SUCCESS" "Tous les prérequis sont satisfaits"
}

# Fonction d'initialisation du VPS
function initialiser_vps() {
    log "INFO" "Initialisation du VPS..."

    local ansible_cmd="ansible-playbook -i ${ANSIBLE_DIR}/${inventory_file} ${ANSIBLE_DIR}/playbooks/init-vps.yml --ask-become-pass"

    if [[ "${debug_mode}" == "true" ]]; then
        ansible_cmd="${ansible_cmd} -vvv"
    fi

    log "INFO" "Exécution de la commande: ${ansible_cmd}"

    if eval "${ansible_cmd}"; then
        log "SUCCESS" "Initialisation du VPS terminée avec succès"
    else
        log "ERROR" "Échec de l'initialisation du VPS"
        exit 1
    fi
}

# Fonction d'installation de K3s
function installer_k3s() {
    log "INFO" "Installation de K3s..."

    local ansible_cmd="ansible-playbook -i ${ANSIBLE_DIR}/${inventory_file} ${ANSIBLE_DIR}/playbooks/install-k3s.yml --ask-become-pass"

    if [[ "${debug_mode}" == "true" ]]; then
        ansible_cmd="${ansible_cmd} -vvv"
    fi

    log "INFO" "Exécution de la commande: ${ansible_cmd}"

    if eval "${ansible_cmd}"; then
        log "SUCCESS" "Installation de K3s terminée avec succès"
    else
        log "ERROR" "Échec de l'installation de K3s"
        exit 1
    fi
}

# Fonction de déploiement de l'infrastructure de base
function deployer_infrastructure_base() {
    log "INFO" "Déploiement de l'infrastructure de base..."

    # Création du namespace pour l'infrastructure
    log "INFO" "Création du namespace lions-infrastructure..."
    kubectl create namespace lions-infrastructure --dry-run=client -o yaml | kubectl apply -f -

    # Déploiement des composants de base via kustomize
    log "INFO" "Déploiement des composants de base via kustomize..."
    kubectl apply -k "${PROJECT_ROOT}/kubernetes/overlays/${environment}"

    log "SUCCESS" "Déploiement de l'infrastructure de base terminé avec succès"
}

# Fonction de déploiement du monitoring
function deployer_monitoring() {
    log "INFO" "Déploiement du système de monitoring..."

    # Création du namespace pour le monitoring
    log "INFO" "Création du namespace monitoring..."
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

    # Déploiement de Prometheus et Grafana via Helm
    log "INFO" "Déploiement de Prometheus et Grafana..."

    # Ajout du dépôt Helm de Prometheus
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update

    # Déploiement de Prometheus
    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --set grafana.adminPassword=admin \
        --set prometheus.prometheusSpec.retention=15d \
        --set prometheus.prometheusSpec.resources.requests.cpu=200m \
        --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
        --set prometheus.prometheusSpec.resources.limits.cpu=500m \
        --set prometheus.prometheusSpec.resources.limits.memory=1Gi

    log "SUCCESS" "Déploiement du système de monitoring terminé avec succès"
}

# Fonction de vérification finale
function verifier_installation() {
    log "INFO" "Vérification de l'installation..."

    # Vérification des nœuds
    log "INFO" "Vérification des nœuds Kubernetes..."
    kubectl get nodes

    # Vérification des namespaces
    log "INFO" "Vérification des namespaces..."
    kubectl get namespaces

    # Vérification des pods système
    log "INFO" "Vérification des pods système..."
    kubectl get pods -n kube-system

    # Vérification des pods d'infrastructure
    log "INFO" "Vérification des pods d'infrastructure..."
    kubectl get pods -n lions-infrastructure

    # Vérification des pods de monitoring
    log "INFO" "Vérification des pods de monitoring..."
    kubectl get pods -n monitoring

    # Vérification des pods du Kubernetes Dashboard
    log "INFO" "Vérification des pods du Kubernetes Dashboard..."
    kubectl get pods -n kubernetes-dashboard

    log "SUCCESS" "Vérification de l'installation terminée avec succès"
}

# Parsing des arguments
environment="${DEFAULT_ENV}"
inventory_file="inventories/${DEFAULT_ENV}/hosts.yml"
skip_init="false"
debug_mode="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--environment)
            environment="$2"
            inventory_file="inventories/${environment}/hosts.yml"
            shift 2
            ;;
        -i|--inventory)
            inventory_file="$2"
            shift 2
            ;;
        -s|--skip-init)
            skip_init="true"
            shift
            ;;
        -d|--debug)
            debug_mode="true"
            shift
            ;;
        -h|--help)
            afficher_aide
            exit 0
            ;;
        *)
            log "ERROR" "Argument inconnu: $1"
            afficher_aide
            exit 1
            ;;
    esac
done

# Affichage du titre
echo -e "${COLOR_CYAN}${COLOR_BOLD}"
echo -e "  _     ___ ___  _   _ ___    ___ _   _ _____ ___    _    "
echo -e " | |   |_ _/ _ \| \ | / __|  |_ _| \ | |  ___/ _ \  / \   "
echo -e " | |    | | | | |  \| \__ \   | ||  \| | |_ | | | |/ _ \  "
echo -e " | |___ | | |_| | |\  |__) |  | || |\  |  _|| |_| / ___ \ "
echo -e " |_____|___\___/|_| \_|____/  |___|_| \_|_|   \___/_/   \_\\"
echo -e "${COLOR_RESET}"
echo -e "${COLOR_YELLOW}${COLOR_BOLD}  Installation de l'Infrastructure sur VPS - v1.0.0${COLOR_RESET}"
echo -e "${COLOR_CYAN}  ------------------------------------------------${COLOR_RESET}\n"

# Affichage des paramètres
log "INFO" "Environnement: ${environment}"
log "INFO" "Fichier d'inventaire: ${inventory_file}"
log "INFO" "Ignorer l'initialisation: ${skip_init}"
log "INFO" "Mode debug: ${debug_mode}"
log "INFO" "Fichier de log: ${LOG_FILE}"

# Exécution des étapes d'installation
verifier_prerequis

if [[ "${skip_init}" == "false" ]]; then
    initialiser_vps
fi

installer_k3s
deployer_infrastructure_base
deployer_monitoring
verifier_installation

# Affichage du résumé
echo -e "\n${COLOR_GREEN}${COLOR_BOLD}===========================================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}${COLOR_BOLD}  Installation de l'infrastructure LIONS terminée avec succès !${COLOR_RESET}"
echo -e "${COLOR_GREEN}${COLOR_BOLD}===========================================================${COLOR_RESET}\n"

log "INFO" "Pour accéder à Grafana, utilisez l'URL: http://<IP_VPS>:30000"
log "INFO" "Identifiant: admin"
log "INFO" "Mot de passe: admin"

log "INFO" "Pour accéder au Kubernetes Dashboard, utilisez l'URL: https://<IP_VPS>:30001"
log "INFO" "Utilisez le token affiché dans les logs d'installation pour vous connecter"
log "INFO" "Vous pouvez également générer un nouveau token avec: kubectl create token dashboard-admin -n kubernetes-dashboard"

log "INFO" "Pour déployer des applications, utilisez le script deploy.sh"

exit 0
