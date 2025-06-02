#!/bin/bash
# =============================================================================
# LIONS Infrastructure - Script d'installation principal v5.1
# =============================================================================
# Description: Script d'installation simplifié et robuste pour l'infrastructure LIONS
# Version: 5.1.0
# Date: 01/06/2025
# Auteur: LIONS DevOps Team
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION GLOBALE
# =============================================================================

# Répertoires et chemins
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
readonly LOG_DIR="./logs/infrastructure"
readonly BACKUP_DIR="${LOG_DIR}/backups"
readonly STATE_FILE="${LOG_DIR}/.installation_state"
readonly LOCK_FILE="/tmp/lions_install.lock"

# Configuration par défaut
readonly DEFAULT_ENVIRONMENT="development"
readonly DEFAULT_TIMEOUT=1800
readonly DEFAULT_SSH_TIMEOUT=30
readonly DEFAULT_RETRIES=3

# Variables d'environnement
ENVIRONMENT="${LIONS_ENV:-${DEFAULT_ENVIRONMENT}}"
DEBUG_MODE="${LIONS_DEBUG_MODE:-false}"
SKIP_INIT="${LIONS_SKIP_INIT:-false}"
VPS_HOST="${LIONS_VPS_HOST:-}"
VPS_PORT="${LIONS_VPS_PORT:-225}"
VPS_USER="${LIONS_VPS_USER:-root}"

# Variables globales
INSTALLATION_STEP=""
ANSIBLE_HOST=""
ANSIBLE_PORT=""
ANSIBLE_USER=""
IS_LOCAL_EXECUTION="false"

# Couleurs pour l'affichage
readonly RED="\033[0;31m"
readonly GREEN="\033[0;32m"
readonly YELLOW="\033[0;33m"
readonly BLUE="\033[0;34m"
readonly CYAN="\033[0;36m"
readonly BOLD="\033[1m"
readonly RESET="\033[0m"

# Création des répertoires
mkdir -p "${LOG_DIR}" "${BACKUP_DIR}"

# Fichier de log avec timestamp
readonly LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"

# =============================================================================
# FONCTIONS UTILITAIRES
# =============================================================================

# Fonction de logging
log() {
    local level="$1"
    local message="$2"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local color=""
    local icon=""

    case "${level}" in
        "INFO")    color="${BLUE}";   icon="ℹ️ " ;;
        "SUCCESS") color="${GREEN}";  icon="✅ " ;;
        "WARNING") color="${YELLOW}"; icon="⚠️ " ;;
        "ERROR")   color="${RED}";    icon="❌ " ;;
        "DEBUG")   color="${CYAN}";   icon="🔍 " ;;
    esac

    # Affichage console
    echo -e "${color}${icon}[${timestamp}] [${level}]${RESET} ${message}"

    # Écriture dans le log
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Fonction pour vérifier si une commande existe
command_exists() {
    command -v "$1" &>/dev/null
}

# Fonction pour exécuter une commande avec timeout
run_command() {
    local cmd="$1"
    local timeout="${2:-${DEFAULT_TIMEOUT}}"
    local description="${3:-Commande}"

    log "INFO" "Exécution: ${description}"

    if [[ "${DEBUG_MODE}" == "true" ]]; then
        log "DEBUG" "Commande: ${cmd}"
    fi

    if timeout "${timeout}" bash -c "${cmd}"; then
        log "SUCCESS" "${description} réussie"
        return 0
    else
        local exit_code=$?
        log "ERROR" "${description} échouée (code: ${exit_code})"
        return ${exit_code}
    fi
}

# Fonction pour gérer les erreurs
handle_error() {
    local exit_code=$?
    local line_number=$1

    log "ERROR" "Erreur à la ligne ${line_number} (code: ${exit_code})"
    log "ERROR" "Étape: ${INSTALLATION_STEP}"

    # Sauvegarde de l'état pour reprise
    echo "${INSTALLATION_STEP}" > "${STATE_FILE}"

    cleanup
    exit ${exit_code}
}

# Configuration du gestionnaire d'erreurs
trap 'handle_error ${LINENO}' ERR

# Fonction de nettoyage
cleanup() {
    log "INFO" "Nettoyage des ressources temporaires..."
    rm -f "${LOCK_FILE}" 2>/dev/null || true
}

# Configuration du gestionnaire de sortie
trap cleanup EXIT

# =============================================================================
# FONCTIONS DE VÉRIFICATION
# =============================================================================

# Vérification des prérequis
check_prerequisites() {
    log "INFO" "Vérification des prérequis..."
    INSTALLATION_STEP="check_prerequisites"

    # Vérification du verrouillage
    if [[ -f "${LOCK_FILE}" ]]; then
        local lock_age=$(($(date +%s) - $(stat -c %Y "${LOCK_FILE}" 2>/dev/null || echo 0)))
        if [[ ${lock_age} -gt 3600 ]]; then
            log "WARNING" "Suppression du verrou obsolète"
            rm -f "${LOCK_FILE}"
        else
            log "ERROR" "Une autre instance est en cours d'exécution"
            exit 1
        fi
    fi

    # Création du verrou
    touch "${LOCK_FILE}"

    # Vérification des commandes requises
    local required_commands=("ansible-playbook" "kubectl" "helm" "ssh" "scp")
    local missing_commands=()

    for cmd in "${required_commands[@]}"; do
        if ! command_exists "${cmd}"; then
            missing_commands+=("${cmd}")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log "ERROR" "Commandes manquantes: ${missing_commands[*]}"
        log "INFO" "Installez les dépendances et réessayez"
        exit 1
    fi

    # Vérification de l'espace disque (minimum 5GB)
    local available_space=$(df -BG . | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ ${available_space} -lt 5 ]]; then
        log "ERROR" "Espace disque insuffisant: ${available_space}GB (minimum: 5GB)"
        exit 1
    fi

    log "SUCCESS" "Prérequis validés"
}

# Chargement de la configuration
load_configuration() {
    log "INFO" "Chargement de la configuration..."

    # Chargement du fichier .env si présent
    local env_file="${PROJECT_ROOT}/.env"
    if [[ -f "${env_file}" ]]; then
        log "INFO" "Chargement des variables depuis ${env_file}"
        # Chargement sécurisé des variables d'environnement
        set -a
        source "${env_file}"
        set +a

        # Mise à jour des variables
        VPS_HOST="${LIONS_VPS_HOST:-${VPS_HOST}}"
        VPS_PORT="${LIONS_VPS_PORT:-${VPS_PORT}}"
        VPS_USER="${LIONS_VPS_USER:-${VPS_USER}}"
        ENVIRONMENT="${LIONS_ENV:-${ENVIRONMENT}}"
    fi

    # Validation des variables obligatoires
    if [[ -z "${VPS_HOST}" ]]; then
        log "ERROR" "LIONS_VPS_HOST non défini"
        log "INFO" "Définissez LIONS_VPS_HOST dans le fichier .env ou en variable d'environnement"
        exit 1
    fi

    # Définition des variables Ansible
    ANSIBLE_HOST="${VPS_HOST}"
    ANSIBLE_PORT="${VPS_PORT}"
    ANSIBLE_USER="${VPS_USER}"

    log "INFO" "Configuration chargée: ${ANSIBLE_USER}@${ANSIBLE_HOST}:${ANSIBLE_PORT}"
}

# Détection de l'exécution locale
detect_local_execution() {
    log "INFO" "Détection du mode d'exécution..."

    # Vérification si l'hôte cible est local
    if [[ "${ANSIBLE_HOST}" == "localhost" || "${ANSIBLE_HOST}" == "127.0.0.1" ]]; then
        IS_LOCAL_EXECUTION="true"
    else
        # Vérification des IP locales
        local local_ips=$(ip route get 1 2>/dev/null | awk '{print $7; exit}' || echo "")
        if [[ "${ANSIBLE_HOST}" == "${local_ips}" ]]; then
            IS_LOCAL_EXECUTION="true"
        fi
    fi

    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        log "INFO" "Exécution locale détectée"
    else
        log "INFO" "Exécution distante détectée"
    fi
}

# Test de connectivité
test_connectivity() {
    log "INFO" "Test de connectivité..."

    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        log "INFO" "Connectivité locale validée"
        return 0
    fi

    # Test SSH
    if ! ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ANSIBLE_PORT}" "${ANSIBLE_USER}@${ANSIBLE_HOST}" "echo 'Connexion SSH réussie'" &>/dev/null; then
        log "ERROR" "Impossible de se connecter via SSH"
        log "INFO" "Vérifiez vos clés SSH et les paramètres de connexion"
        exit 1
    fi

    log "SUCCESS" "Connectivité SSH validée"
}

# =============================================================================
# FONCTIONS D'INSTALLATION
# =============================================================================

# Initialisation du VPS
init_vps() {
    log "INFO" "Initialisation du VPS..."
    INSTALLATION_STEP="init_vps"

    if [[ "${SKIP_INIT}" == "true" ]]; then
        log "INFO" "Initialisation ignorée (--skip-init)"
        return 0
    fi

    local inventory_file="${ANSIBLE_DIR}/inventories/${ENVIRONMENT}/hosts.yml"
    local playbook_file="${ANSIBLE_DIR}/playbooks/init-vps.yml"

    # Vérification des fichiers
    if [[ ! -f "${inventory_file}" ]]; then
        log "ERROR" "Fichier d'inventaire non trouvé: ${inventory_file}"
        exit 1
    fi

    if [[ ! -f "${playbook_file}" ]]; then
        log "ERROR" "Playbook non trouvé: ${playbook_file}"
        exit 1
    fi

    # Configuration pour l'exécution locale
    local extra_vars=""
    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        extra_vars="-e ansible_connection=local -e ansible_user=${ANSIBLE_USER} -e ansible_become=true"
    fi

    # Commande Ansible
    local cmd="ansible-playbook -i '${inventory_file}' '${playbook_file}' ${extra_vars}"
    if [[ "${IS_LOCAL_EXECUTION}" != "true" ]]; then
        cmd="${cmd} --ask-become-pass"
    fi

    run_command "${cmd}" 1800 "Initialisation du VPS"
}

# Installation de K3s
install_k3s() {
    log "INFO" "Installation de K3s..."
    INSTALLATION_STEP="install_k3s"

    local inventory_file="${ANSIBLE_DIR}/inventories/${ENVIRONMENT}/hosts.yml"
    local playbook_file="${ANSIBLE_DIR}/playbooks/install-k3s.yml"

    # Configuration pour l'exécution locale
    local extra_vars=""
    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        extra_vars="-e ansible_connection=local -e ansible_user=${ANSIBLE_USER} -e ansible_become=true"
    fi

    # Commande Ansible
    local cmd="ansible-playbook -i '${inventory_file}' '${playbook_file}' ${extra_vars}"
    if [[ "${IS_LOCAL_EXECUTION}" != "true" ]]; then
        cmd="${cmd} --ask-become-pass"
    fi

    run_command "${cmd}" 3600 "Installation de K3s"

    # Configuration de kubectl pour l'exécution locale
    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        if [[ -f "/etc/rancher/k3s/k3s.yaml" ]]; then
            export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
            log "INFO" "KUBECONFIG configuré pour K3s local"
        fi
    else
        # Récupération du kubeconfig pour l'exécution distante
        mkdir -p "${HOME}/.kube"
        if scp -P "${ANSIBLE_PORT}" "${ANSIBLE_USER}@${ANSIBLE_HOST}:/etc/rancher/k3s/k3s.yaml" "${HOME}/.kube/config-k3s" &>/dev/null; then
            # Remplacement de l'IP locale par l'IP du VPS
            sed -i "s/127.0.0.1/${ANSIBLE_HOST}/g" "${HOME}/.kube/config-k3s"
            export KUBECONFIG="${HOME}/.kube/config-k3s"
            log "INFO" "KUBECONFIG configuré depuis le VPS"
        fi
    fi

    # Vérification de K3s
    sleep 30
    if ! kubectl get nodes &>/dev/null; then
        log "ERROR" "K3s n'est pas accessible"
        exit 1
    fi

    log "SUCCESS" "K3s installé et accessible"
}

# Déploiement de l'infrastructure de base
deploy_infrastructure() {
    log "INFO" "Déploiement de l'infrastructure de base..."
    INSTALLATION_STEP="deploy_infrastructure"

    # Vérification de kubectl
    if ! kubectl cluster-info &>/dev/null; then
        log "ERROR" "Cluster Kubernetes non accessible"
        exit 1
    fi

    # Création des namespaces de base
    kubectl create namespace lions-infrastructure --dry-run=client -o yaml | kubectl apply -f -

    # Déploiement via kustomize si disponible
    local kustomize_dir="${PROJECT_ROOT}/kubernetes/overlays/${ENVIRONMENT}"
    if [[ -d "${kustomize_dir}" && -f "${kustomize_dir}/kustomization.yaml" ]]; then
        run_command "kubectl apply -k '${kustomize_dir}'" 600 "Déploiement Kustomize"
    else
        log "WARNING" "Configuration Kustomize non trouvée, ignorée"
    fi

    log "SUCCESS" "Infrastructure de base déployée"
}

# Déploiement du monitoring
deploy_monitoring() {
    log "INFO" "Déploiement du monitoring..."
    INSTALLATION_STEP="deploy_monitoring"

    # Création du namespace monitoring
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

    # Ajout du dépôt Helm Prometheus
    run_command "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts" 60 "Ajout dépôt Helm"
    run_command "helm repo update" 60 "Mise à jour dépôts Helm"

    # Création du fichier de valeurs pour Prometheus
    local values_file=$(mktemp)
    cat > "${values_file}" << 'EOF'
alertmanager:
  enabled: false

grafana:
  enabled: true
  adminPassword: admin
  service:
    type: NodePort
    nodePort: 30000
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi
  persistence:
    enabled: false

prometheus:
  enabled: true
  prometheusSpec:
    retention: 7d
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
    storageSpec: {}

kubeStateMetrics:
  enabled: true
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi

nodeExporter:
  enabled: true
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi

kubeEtcd:
  enabled: false
kubeControllerManager:
  enabled: false
kubeScheduler:
  enabled: false
kubeProxy:
  enabled: false
EOF

    # Installation de Prometheus/Grafana
    local cmd="helm upgrade --install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --values '${values_file}' --wait --timeout 10m"

    if run_command "${cmd}" 1200 "Installation Prometheus/Grafana"; then
        log "SUCCESS" "Monitoring déployé avec succès"
        log "INFO" "Grafana accessible sur: http://${ANSIBLE_HOST}:30000 (admin/admin)"
    else
        log "WARNING" "Échec du déploiement du monitoring"
    fi

    rm -f "${values_file}"
}

# Vérification finale
verify_installation() {
    log "INFO" "Vérification de l'installation..."
    INSTALLATION_STEP="verify"

    # Vérification des nœuds
    if ! kubectl get nodes | grep -q "Ready"; then
        log "ERROR" "Aucun nœud Kubernetes prêt"
        return 1
    fi

    # Vérification des pods système
    local system_pods=$(kubectl get pods -n kube-system --field-selector=status.phase!=Running -o name 2>/dev/null | wc -l)
    if [[ ${system_pods} -gt 0 ]]; then
        log "WARNING" "${system_pods} pods système non prêts"
    fi

    # Vérification des services
    local services=(
        "monitoring:prometheus-grafana:30000"
    )

    for service_info in "${services[@]}"; do
        IFS=':' read -r namespace service port <<< "${service_info}"
        if kubectl get service -n "${namespace}" "${service}" &>/dev/null; then
            log "SUCCESS" "Service ${service} accessible sur le port ${port}"
        else
            log "WARNING" "Service ${service} non trouvé"
        fi
    done

    log "SUCCESS" "Vérification terminée"
}

# =============================================================================
# FONCTIONS PRINCIPALES
# =============================================================================

# Affichage de l'aide
show_help() {
    cat << EOF
Script d'Installation LIONS Infrastructure

Usage: $0 [options]

Options:
    -e, --environment ENV    Environnement (development, staging, production)
    -s, --skip-init         Ignorer l'initialisation du VPS
    -d, --debug             Mode debug
    -h, --help              Afficher cette aide

Variables d'environnement requises:
    LIONS_VPS_HOST          Adresse IP du VPS
    LIONS_VPS_PORT          Port SSH (défaut: 225)
    LIONS_VPS_USER          Utilisateur SSH (défaut: root)

Exemple:
    export LIONS_VPS_HOST=176.57.150.2
    $0 --environment development
EOF
}

# Affichage du banner
show_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║      ██╗     ██╗ ██████╗ ███╗   ██╗███████╗    ██╗███╗   ██╗      ║"
    echo "║      ██║     ██║██╔═══██╗████╗  ██║██╔════╝    ██║████╗  ██║      ║"
    echo "║      ██║     ██║██║   ██║██╔██╗ ██║███████╗    ██║██╔██╗ ██║      ║"
    echo "║      ██║     ██║██║   ██║██║╚██╗██║╚════██║    ██║██║╚██╗██║      ║"
    echo "║      ███████╗██║╚██████╔╝██║ ╚████║███████║    ██║██║ ╚████║      ║"
    echo "║      ╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝    ╚═╝╚═╝  ╚═══╝      ║"
    echo "║                                                                   ║"
    echo "║         Infrastructure de Déploiement Automatisé v5.1            ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}\n"
}

# Fonction principale
main() {
    # Parsing des arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -s|--skip-init)
                SKIP_INIT="true"
                shift
                ;;
            -d|--debug)
                DEBUG_MODE="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "Option inconnue: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Affichage du banner
    show_banner

    # Étapes d'installation
    log "INFO" "Démarrage de l'installation LIONS"
    log "INFO" "Environnement: ${ENVIRONMENT}"
    log "INFO" "Debug: ${DEBUG_MODE}"
    log "INFO" "Fichier de log: ${LOG_FILE}"

    # Vérification des prérequis
    check_prerequisites

    # Chargement de la configuration
    load_configuration

    # Détection du mode d'exécution
    detect_local_execution

    # Test de connectivité
    test_connectivity

    # Installation
    init_vps
    install_k3s
    deploy_infrastructure
    deploy_monitoring
    verify_installation

    # Rapport final
    log "SUCCESS" "Installation terminée avec succès!"
    echo
    log "INFO" "Services disponibles:"
    log "INFO" "- Grafana: http://${ANSIBLE_HOST}:30000 (admin/admin)"
    log "INFO" "- Kubernetes Dashboard: https://${ANSIBLE_HOST}:30001"
    echo
    log "INFO" "Logs d'installation: ${LOG_FILE}"
    log "INFO" "Configuration kubectl: ${KUBECONFIG:-défaut}"
}

# =============================================================================
# POINT D'ENTRÉE
# =============================================================================

# Vérification que le script n'est pas sourcé
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
else
    log "ERROR" "Ce script doit être exécuté, pas sourcé"
    exit 1
fi