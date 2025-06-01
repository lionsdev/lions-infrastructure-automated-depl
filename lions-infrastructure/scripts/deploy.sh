#!/bin/bash
# =============================================================================
# LIONS Infrastructure - Script de déploiement principal v5.0
# =============================================================================
# Description: Script de déploiement avec variables d'environnement pour l'environnement ${LIONS_ENVIRONMENT:-development}
# Version: 5.0.0
# Date: 01/06/2025
# Auteur: LIONS DevOps Team
# =============================================================================

# Activation du mode strict
set -euo pipefail

# =============================================================================
# CONFIGURATION DEPUIS VARIABLES D'ENVIRONNEMENT
# =============================================================================
# Configuration de base
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIONS_ENVIRONMENT="${LIONS_ENVIRONMENT:-development}"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration des chemins
readonly CONFIG_DIR="${LIONS_CONFIG_DIR:-${SCRIPT_DIR}/../config}"
readonly LOG_DIR="${LIONS_DEPLOY_LOG_DIR:-/var/log/lions/deployments}"
readonly LOG_FILE="${LOG_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"
readonly ANSIBLE_DIR="${LIONS_ANSIBLE_DIR:-${PROJECT_ROOT}/ansible}"
readonly ANSIBLE_PLAYBOOK="${LIONS_DEPLOY_PLAYBOOK:-${ANSIBLE_DIR}/playbooks/deploy-application.yml}"
readonly APPLICATIONS_CATALOG="${LIONS_APPLICATIONS_CATALOG:-${PROJECT_ROOT}/applications/catalog}"
readonly LOG_HISTORY_DIR="${LIONS_LOG_HISTORY_DIR:-${LOG_DIR}/history}"
readonly BACKUP_DIR="${LIONS_DEPLOY_BACKUP_DIR:-${LOG_DIR}/backups}"

# Configuration des environnements et technologies
readonly DEFAULT_ENVIRONMENT="${LIONS_DEFAULT_ENVIRONMENT:-development}"
readonly ENVIRONMENTS="${LIONS_SUPPORTED_ENVIRONMENTS:-production,staging,development}"
readonly TECHNOLOGIES="${LIONS_SUPPORTED_TECHNOLOGIES:-quarkus,primefaces,primereact,angular,nodejs,python}"

# Configuration du déploiement
readonly DEFAULT_VERSION="${LIONS_DEFAULT_VERSION:-latest}"
readonly DEFAULT_REGISTRY="${LIONS_DEFAULT_REGISTRY:-registry.lions.dev}"
readonly REGISTRY_NAMESPACE="${LIONS_REGISTRY_NAMESPACE:-lions}"
readonly DEPLOYMENT_TIMEOUT="${LIONS_DEPLOYMENT_TIMEOUT:-600}"
readonly ROLLBACK_ENABLED="${LIONS_ROLLBACK_ENABLED:-true}"
readonly AUTO_SCALING_ENABLED="${LIONS_AUTO_SCALING_ENABLED:-true}"

# Configuration de sécurité
readonly SECURITY_SCANNING="${LIONS_SECURITY_SCANNING:-true}"
readonly VULNERABILITY_THRESHOLD="${LIONS_VULNERABILITY_THRESHOLD:-high}"
readonly FORCE_HTTPS="${LIONS_FORCE_HTTPS:-true}"
readonly ENABLE_RBAC="${LIONS_ENABLE_RBAC:-true}"

# Configuration de monitoring
readonly MONITORING_ENABLED="${LIONS_MONITORING_ENABLED:-true}"
readonly METRICS_ENABLED="${LIONS_METRICS_ENABLED:-true}"
readonly ALERTS_ENABLED="${LIONS_ALERTS_ENABLED:-true}"
readonly HEALTH_CHECK_ENABLED="${LIONS_HEALTH_CHECK_ENABLED:-true}"

# Configuration des logs
readonly LOG_LEVEL="${LIONS_LOG_LEVEL:-INFO}"
readonly LOG_RETENTION_DAYS="${LIONS_LOG_RETENTION_DAYS:-30}"
readonly DEBUG_MODE="${LIONS_DEBUG_MODE:-false}"
readonly VERBOSE_MODE="${LIONS_VERBOSE_MODE:-false}"

# Configuration réseau
readonly INGRESS_CLASS="${LIONS_INGRESS_CLASS:-nginx}"
readonly TLS_ENABLED="${LIONS_TLS_ENABLED:-true}"
readonly CERT_MANAGER_ENABLED="${LIONS_CERT_MANAGER_ENABLED:-true}"
readonly LOAD_BALANCER_TYPE="${LIONS_LOAD_BALANCER_TYPE:-ClusterIP}"

# Configuration de base de données
readonly DB_MIGRATION_ENABLED="${LIONS_DB_MIGRATION_ENABLED:-true}"
readonly DB_BACKUP_BEFORE_DEPLOY="${LIONS_DB_BACKUP_BEFORE_DEPLOY:-true}"
readonly DB_CONNECTION_TIMEOUT="${LIONS_DB_CONNECTION_TIMEOUT:-30}"

# Configuration de notification
readonly NOTIFICATION_ENABLED="${LIONS_NOTIFICATION_ENABLED:-false}"
readonly WEBHOOK_URL="${LIONS_WEBHOOK_URL:-}"
readonly SLACK_CHANNEL="${LIONS_SLACK_CHANNEL:-#deployments}"
readonly EMAIL_NOTIFICATIONS="${LIONS_EMAIL_NOTIFICATIONS:-false}"

# Conversion des chaînes séparées par des virgules en tableaux
IFS=',' read -ra ENVIRONMENTS_ARRAY <<< "${ENVIRONMENTS}"
IFS=',' read -ra TECHNOLOGIES_ARRAY <<< "${TECHNOLOGIES}"

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
readonly COLOR_UNDERLINE="\033[4m"
readonly COLOR_BG_BLACK="\033[40m"
readonly COLOR_BG_RED="\033[41m"
readonly COLOR_BG_GREEN="\033[42m"
readonly COLOR_BG_YELLOW="\033[43m"
readonly COLOR_BG_BLUE="\033[44m"
readonly COLOR_BG_MAGENTA="\033[45m"
readonly COLOR_BG_CYAN="\033[46m"
readonly COLOR_BG_WHITE="\033[47m"

# Création des répertoires de logs et de backups
mkdir -p "${LOG_DIR}"
mkdir -p "${LOG_HISTORY_DIR}"
mkdir -p "${BACKUP_DIR}"

# Fonction d'affichage du logo
function afficher_logo() {
    # Définir des couleurs pour un effet gradient
    local GRADIENT1="\033[38;5;45m"  # Bleu clair
    local GRADIENT2="\033[38;5;39m"  # Bleu moyen
    local GRADIENT3="\033[38;5;33m"  # Bleu foncé

    echo -e "${COLOR_BOLD}"
    echo -e "${GRADIENT1}    ╔══════════════════════════════════════════════════════════════════╗"
    echo -e "${GRADIENT1}    ║    ${GRADIENT2}█     █ ████ ████ █   █ ████   ███ █   █ ████ ████${GRADIENT1}   ║"
    echo -e "${GRADIENT2}    ║    ${GRADIENT2}█     █ █  █ █  █ ██  █ █       █  ██  █ █    █  █${GRADIENT1}   ║"
    echo -e "${GRADIENT2}    ║    ${GRADIENT3}█     █ █  █ █  █ █ █ █ ████    █  █ █ █ ████ █  █${GRADIENT2}   ║"
    echo -e "${GRADIENT3}    ║    ${GRADIENT3}█     █ █  █ █  █ █  ██    █    █  █  ██ █    █  █${GRADIENT2}   ║"
    echo -e "${GRADIENT3}    ║    ${GRADIENT3}█████ █ ████ ████ █   █ ████   ███ █   █ █    ████${GRADIENT1}   ║"
    echo -e "${GRADIENT1}    ╚══════════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}        Infrastructure de Déploiement Automatisé v5.0.0${COLOR_RESET}"
    echo -e "${GRADIENT2}       ─────────────────────────────────────────────────${COLOR_RESET}\n"
}

# Fonction de logging améliorée
function log() {
    local level="$1"
    local message="$2"
    local timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
    local icon=""

    # Sélection de l'icône et de la couleur en fonction du niveau
    local color="${COLOR_RESET}"
    case "${level}" in
        "INFO")     color="${COLOR_GREEN}"; icon="ℹ️ " ;;
        "WARNING")  color="${COLOR_YELLOW}"; icon="⚠️ " ;;
        "ERROR")    color="${COLOR_RED}"; icon="❌ " ;;
        "DEBUG")    color="${COLOR_BLUE}"; icon="🔍 " ;;
        "SUCCESS")  color="${COLOR_GREEN}"; icon="✅ " ;;
        "STEP")     color="${COLOR_CYAN}${COLOR_BOLD}"; icon="🔄 " ;;
    esac

    # Affichage du message avec formatage
    echo -e "${color}${icon}[${timestamp}] [${level}] ${message}${COLOR_RESET}"

    # Enregistrement dans un fichier de log
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Fonction d'affichage de la progression
function afficher_progression() {
    local etape="$1"
    local total="$2"
    local description="$3"
    local pourcentage=$((etape * 100 / total))
    local barre=""
    local longueur=50
    local rempli=$((pourcentage * longueur / 100))

    for ((i=0; i<longueur; i++)); do
        if [ $i -lt $rempli ]; then
            barre+="█"
        else
            barre+="░"
        fi
    done

    echo -e "\n${COLOR_CYAN}${COLOR_BOLD}Étape ${etape}/${total}: ${description}${COLOR_RESET}"
    echo -e "${COLOR_BLUE}[${barre}] ${pourcentage}%${COLOR_RESET}\n"
}

# Fonction d'affichage de l'aide
function afficher_aide() {
    afficher_logo

    cat << EOF

${COLOR_CYAN}${COLOR_BOLD}Script de Déploiement Unifié - Infrastructure LIONS${COLOR_RESET}

Ce script permet de déployer facilement n'importe quelle application vers l'infrastructure LIONS.

${COLOR_YELLOW}${COLOR_BOLD}Usage:${COLOR_RESET}
    $0 [options] <nom_application>

${COLOR_YELLOW}${COLOR_BOLD}Options:${COLOR_RESET}
    ${COLOR_GREEN}-e, --environment <env>${COLOR_RESET}   Environnement cible (${ENVIRONMENTS})
                             Par défaut: ${DEFAULT_ENVIRONMENT}
    ${COLOR_GREEN}-t, --technology <tech>${COLOR_RESET}   Technologie utilisée (${TECHNOLOGIES})
                             Par défaut: détection automatique
    ${COLOR_GREEN}-v, --version <version>${COLOR_RESET}   Version spécifique à déployer
                             Par défaut: ${DEFAULT_VERSION}
    ${COLOR_GREEN}-f, --file <fichier>${COLOR_RESET}      Fichier de configuration spécifique
                             Par défaut: application.yaml dans le répertoire courant
    ${COLOR_GREEN}-p, --params <params>${COLOR_RESET}     Paramètres additionnels pour le déploiement (format JSON)
    ${COLOR_GREEN}-d, --debug${COLOR_RESET}               Active le mode debug
    ${COLOR_GREEN}-h, --help${COLOR_RESET}                Affiche cette aide

${COLOR_YELLOW}${COLOR_BOLD}Exemples:${COLOR_RESET}
    $0 mon-api-backend
    $0 --environment staging --technology quarkus mon-api-backend
    $0 -e production -v 1.2.3 mon-application-frontend

EOF
}

# Fonction pour créer une sauvegarde avant déploiement
function creer_sauvegarde() {
    local app_name="$1"
    local environment="$2"
    local namespace="${app_name}-${environment}"
    local backup_timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="${BACKUP_DIR}/${app_name}-${environment}-${backup_timestamp}.tar.gz"

    log "STEP" "Création d'une sauvegarde avant déploiement"

    # Vérification si l'application existe déjà
    if kubectl get namespace "${namespace}" &>/dev/null; then
        log "INFO" "Sauvegarde des ressources Kubernetes pour ${app_name} dans l'environnement ${environment}"

        # Création d'un répertoire temporaire pour la sauvegarde
        local temp_dir=$(mktemp -d)

        # Sauvegarde des différentes ressources Kubernetes
        kubectl get all -n "${namespace}" -o yaml > "${temp_dir}/all-resources.yaml" 2>/dev/null || true
        kubectl get configmap -n "${namespace}" -o yaml > "${temp_dir}/configmaps.yaml" 2>/dev/null || true
        kubectl get secret -n "${namespace}" -o yaml > "${temp_dir}/secrets.yaml" 2>/dev/null || true
        kubectl get ingress -n "${namespace}" -o yaml > "${temp_dir}/ingress.yaml" 2>/dev/null || true
        kubectl get pvc -n "${namespace}" -o yaml > "${temp_dir}/pvcs.yaml" 2>/dev/null || true

        # Sauvegarde des logs des pods
        mkdir -p "${temp_dir}/logs"
        for pod in $(kubectl get pods -n "${namespace}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
            kubectl logs -n "${namespace}" "${pod}" > "${temp_dir}/logs/${pod}.log" 2>/dev/null || true
        done

        # Compression de la sauvegarde
        tar -czf "${backup_file}" -C "${temp_dir}" . &>/dev/null

        # Nettoyage
        rm -rf "${temp_dir}"

        log "SUCCESS" "Sauvegarde créée avec succès: ${backup_file}"

        # Enregistrement du chemin de la sauvegarde pour référence future
        echo "${backup_file}" > "${BACKUP_DIR}/${app_name}-${environment}-latest.txt"
    else
        log "INFO" "Aucune sauvegarde nécessaire - l'application n'existe pas encore dans cet environnement"
    fi
}

# Fonction de vérification des prérequis
function verifier_prerequis() {
    log "STEP" "Vérification des prérequis pour le déploiement"

    # Vérification d'Ansible
    if ! command -v ansible-playbook &> /dev/null; then
        log "ERROR" "ansible-playbook n'est pas installé ou n'est pas dans le PATH"
        exit 1
    fi

    # Vérification du playbook Ansible
    if [[ ! -f "${ANSIBLE_PLAYBOOK}" ]]; then
        log "ERROR" "Le playbook Ansible n'existe pas: ${ANSIBLE_PLAYBOOK}"
        exit 1
    fi

    # Vérification de kubectl
    if ! command -v kubectl &> /dev/null; then
        log "ERROR" "kubectl n'est pas installé ou n'est pas dans le PATH"
        exit 1
    fi

    # Vérification de la connexion au cluster Kubernetes
    if ! kubectl cluster-info &> /dev/null; then
        log "ERROR" "Impossible de se connecter au cluster Kubernetes"
        exit 1
    fi

    # Vérification des droits d'accès
    if [[ "${environment}" == "production" ]]; then
        log "INFO" "Vérification des droits d'accès pour l'environnement de production"

        # Vérification des droits d'administrateur pour la production
        if ! kubectl auth can-i create deployments --namespace=kube-system &> /dev/null; then
            log "ERROR" "Droits insuffisants pour déployer en production. Contactez l'équipe d'infrastructure."
            exit 1
        fi
    fi

    log "SUCCESS" "Vérification des prérequis terminée avec succès"
}

# Fonction de détection automatique de la technologie
function detecter_technologie() {
    local app_dir="$1"

    log "STEP" "Détection automatique de la technologie pour ${app_dir}"

    # Vérification Quarkus
    if [[ -f "${app_dir}/pom.xml" ]] && grep -q "quarkus" "${app_dir}/pom.xml"; then
        log "SUCCESS" "Technologie détectée: quarkus"
        echo "quarkus"
        return
    fi

    # Vérification PrimeFaces
    if [[ -f "${app_dir}/pom.xml" ]] && grep -q "primefaces" "${app_dir}/pom.xml"; then
        log "SUCCESS" "Technologie détectée: primefaces"
        echo "primefaces"
        return
    fi

    # Vérification PrimeReact
    if [[ -f "${app_dir}/package.json" ]] && grep -q "primereact" "${app_dir}/package.json"; then
        log "SUCCESS" "Technologie détectée: primereact"
        echo "primereact"
        return
    fi

    # Vérification supplémentaire pour Quarkus
    if [[ -f "${app_dir}/src/main/resources/application.properties" ]] || [[ -f "${app_dir}/src/main/resources/application.yml" ]]; then
        log "SUCCESS" "Technologie détectée: quarkus (basé sur la structure du projet)"
        echo "quarkus"
        return
    fi

    # Vérification supplémentaire pour PrimeFaces
    if [[ -f "${app_dir}/src/main/webapp/WEB-INF/web.xml" ]] && grep -q "javax.faces" "${app_dir}/src/main/webapp/WEB-INF/web.xml"; then
        log "SUCCESS" "Technologie détectée: primefaces (basé sur la structure du projet)"
        echo "primefaces"
        return
    fi

    # Vérification supplémentaire pour PrimeReact
    if [[ -f "${app_dir}/src/App.js" ]] || [[ -f "${app_dir}/src/App.jsx" ]]; then
        log "SUCCESS" "Technologie détectée: primereact (basé sur la structure du projet)"
        echo "primereact"
        return
    fi

    log "ERROR" "Impossible de détecter automatiquement la technologie. Veuillez spécifier la technologie avec l'option --technology."
    exit 1
}

# Fonction de validation de la configuration
function valider_configuration() {
    local app_name="$1"
    local environment="$2"
    local technology="$3"

    log "STEP" "Validation de la configuration de déploiement"

    # Vérification spécifique pour la production
    if [[ "${environment}" == "production" ]]; then
        # Vérification de la présence d'un tag de version explicite
        if [[ "${version}" == "latest" ]]; then
            log "ERROR" "Le déploiement en production nécessite une version explicite (--version)"
            exit 1
        fi

        # Vérification de la présence d'un fichier de configuration
        if [[ ! -f "${config_file}" ]]; then
            log "ERROR" "Le déploiement en production nécessite un fichier de configuration valide"
            exit 1
        fi

        # Demande de confirmation pour le déploiement en production
        echo -e "\n${COLOR_BG_RED}${COLOR_WHITE}${COLOR_BOLD} ATTENTION: DÉPLOIEMENT EN PRODUCTION ${COLOR_RESET}\n"
        echo -e "${COLOR_YELLOW}Vous êtes sur le point de déployer l'application ${COLOR_BOLD}${app_name}${COLOR_RESET}${COLOR_YELLOW} en ${COLOR_BOLD}PRODUCTION${COLOR_RESET}${COLOR_YELLOW}.${COLOR_RESET}"
        echo -e "${COLOR_YELLOW}Version: ${COLOR_BOLD}${version}${COLOR_RESET}"
        echo -e "${COLOR_YELLOW}Technologie: ${COLOR_BOLD}${technology}${COLOR_RESET}\n"

        read -p "Êtes-vous sûr de vouloir continuer? (oui/NON): " confirmation
        if [[ "${confirmation}" != "oui" ]]; then
            log "INFO" "Déploiement en production annulé par l'utilisateur"
            exit 0
        fi
    fi

    log "SUCCESS" "Configuration validée avec succès"
}

# Fonction principale de déploiement
function deployer_application() {
    local app_name="$1"
    local environment="$2"
    local technology="$3"
    local version="$4"
    local config_file="$5"
    local extra_params="$6"
    local debug_mode="$7"

    # Affichage du logo
    afficher_logo

    # Validation de la configuration
    valider_configuration "${app_name}" "${environment}" "${technology}"

    # Affichage de la progression
    afficher_progression 1 5 "Préparation du déploiement"

    log "INFO" "Démarrage du déploiement de l'application ${app_name}"
    log "INFO" "Environnement: ${environment}"
    log "INFO" "Technologie: ${technology}"
    log "INFO" "Version: ${version}"

    # Création d'une sauvegarde avant déploiement
    creer_sauvegarde "${app_name}" "${environment}"

    # Création d'un fichier de variables temporaire pour Ansible
    local vars_file=$(mktemp)
    cat > "${vars_file}" << EOF
---
application_name: "${app_name}"
environment: "${environment}"
technology: "${technology}"
version: "${version}"
config_file: "${config_file}"
extra_params: ${extra_params}
deployment_timestamp: "$(date +%Y%m%d%H%M%S)"
deployment_user: "$(whoami)"
EOF

    # Affichage de la progression
    afficher_progression 2 5 "Exécution du playbook Ansible"

    # Détection de WSL pour résoudre le problème de mot de passe invisible
    local os_name=$(uname -s)
    if [[ "${os_name}" == *"MINGW"* || "${os_name}" == *"MSYS"* || "${os_name}" == *"CYGWIN"* || "${os_name}" == *"Windows"* || "${os_name}" == *"Linux"*"microsoft"* ]]; then
        log "INFO" "Système Windows/WSL détecté, définition de la variable d'environnement ANSIBLE_BECOME_ASK_PASS"
        export ANSIBLE_BECOME_ASK_PASS=True
    fi

    # Commande Ansible avec les options appropriées
    local ansible_cmd="ansible-playbook ${ANSIBLE_PLAYBOOK} --extra-vars @${vars_file} --ask-become-pass"

    # Activation du mode verbeux si debug est activé
    if [[ "${debug_mode}" == "true" ]]; then
        ansible_cmd="${ansible_cmd} -vvv"
    fi

    log "INFO" "Exécution de la commande Ansible: ${ansible_cmd}"

    # Exécution de la commande Ansible
    if eval "${ansible_cmd}"; then
        # Affichage de la progression
        afficher_progression 3 5 "Vérification du déploiement"

        log "SUCCESS" "Déploiement terminé avec succès"

        # Affichage de la progression
        afficher_progression 4 5 "Récupération des informations sur le déploiement"

        # Récupération de l'URL d'accès
        local app_url=""
        local domain_suffix=""
        case "${environment}" in
            "production")
                domain_suffix="lions.dev"
                ;;
            "staging")
                domain_suffix="staging.lions.dev"
                ;;
            "development")
                domain_suffix="dev.lions.dev"
                ;;
        esac

        app_url="https://${app_name}.${domain_suffix}"

        # Récupération des informations sur les pods
        local pods_info=$(kubectl get pods -n "${app_name}-${environment}" -o wide 2>/dev/null || echo "Aucun pod trouvé")

        # Récupération des informations sur les services
        local services_info=$(kubectl get services -n "${app_name}-${environment}" 2>/dev/null || echo "Aucun service trouvé")

        # Récupération des informations sur les ingress
        local ingress_info=$(kubectl get ingress -n "${app_name}-${environment}" 2>/dev/null || echo "Aucun ingress trouvé")

        # Affichage de la progression
        afficher_progression 5 5 "Finalisation du déploiement"

        # Affichage des informations de déploiement
        cat << EOF

${COLOR_BG_GREEN}${COLOR_BLACK}${COLOR_BOLD} DÉPLOIEMENT RÉUSSI ${COLOR_RESET}

${COLOR_CYAN}${COLOR_BOLD}Informations sur l'application:${COLOR_RESET}
${COLOR_CYAN}Application:${COLOR_RESET} ${app_name}
${COLOR_CYAN}Version:${COLOR_RESET} ${version}
${COLOR_CYAN}Environnement:${COLOR_RESET} ${environment}
${COLOR_CYAN}Technologie:${COLOR_RESET} ${technology}

${COLOR_CYAN}${COLOR_BOLD}Accès:${COLOR_RESET}
${COLOR_CYAN}URL d'accès:${COLOR_RESET} ${app_url}

${COLOR_CYAN}${COLOR_BOLD}Ressources Kubernetes:${COLOR_RESET}
${COLOR_CYAN}Namespace:${COLOR_RESET} ${app_name}-${environment}

${COLOR_CYAN}${COLOR_BOLD}Pods:${COLOR_RESET}
${pods_info}

${COLOR_CYAN}${COLOR_BOLD}Services:${COLOR_RESET}
${services_info}

${COLOR_CYAN}${COLOR_BOLD}Ingress:${COLOR_RESET}
${ingress_info}

${COLOR_CYAN}${COLOR_BOLD}Logs:${COLOR_RESET}
${COLOR_CYAN}Journal de déploiement:${COLOR_RESET} ${LOG_FILE}

${COLOR_CYAN}${COLOR_BOLD}Commandes utiles:${COLOR_RESET}
${COLOR_GREEN}Afficher les logs:${COLOR_RESET} kubectl logs -n ${app_name}-${environment} deployment/${app_name}
${COLOR_GREEN}Redémarrer l'application:${COLOR_RESET} kubectl rollout restart -n ${app_name}-${environment} deployment/${app_name}
${COLOR_GREEN}Supprimer l'application:${COLOR_RESET} kubectl delete -n ${app_name}-${environment} deployment/${app_name}

${COLOR_GREEN}${COLOR_BOLD}===========================================================${COLOR_RESET}

EOF
    else
        log "ERROR" "Le déploiement a échoué"
        exit 1
    fi

    # Nettoyage du fichier temporaire
    rm -f "${vars_file}"
}

# =============================================================================
# VARIABLES GLOBALES ET PARSING DES ARGUMENTS
# =============================================================================
# Variables par défaut (peuvent être surchargées par les arguments en ligne de commande)
app_name=""
environment="${DEFAULT_ENVIRONMENT}"
technology=""
version="${DEFAULT_VERSION}"
config_file="${LIONS_DEFAULT_CONFIG_FILE:-./application.yaml}"
extra_params="${LIONS_DEFAULT_EXTRA_PARAMS:-{}}"
debug_mode="${DEBUG_MODE}"
verbose_mode="${VERBOSE_MODE}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--environment)
            environment="$2"
            shift 2
            ;;
        -t|--technology)
            technology="$2"
            shift 2
            ;;
        -v|--version)
            version="$2"
            shift 2
            ;;
        -f|--file)
            config_file="$2"
            shift 2
            ;;
        -p|--params)
            extra_params="$2"
            shift 2
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
            if [[ -z "${app_name}" ]]; then
                app_name="$1"
            else
                log "ERROR" "Argument inconnu: $1"
                afficher_aide
                exit 1
            fi
            shift
            ;;
    esac
done

# Vérification de l'application
if [[ -z "${app_name}" ]]; then
    log "ERROR" "Nom d'application non spécifié"
    afficher_aide
    exit 1
fi

# Vérification de l'environnement
if [[ ! " ${ENVIRONMENTS[*]} " =~ " ${environment} " ]]; then
    log "ERROR" "Environnement non valide: ${environment}"
    log "ERROR" "Valeurs autorisées: ${ENVIRONMENTS[*]}"
    exit 1
fi

# Détection automatique de la technologie si non spécifiée
if [[ -z "${technology}" ]]; then
    technology=$(detecter_technologie ".")
fi

# Vérification de la technologie
if [[ ! " ${TECHNOLOGIES[*]} " =~ " ${technology} " ]]; then
    log "ERROR" "Technologie non valide: ${technology}"
    log "ERROR" "Valeurs autorisées: ${TECHNOLOGIES[*]}"
    exit 1
fi

# Vérification des prérequis
verifier_prerequis

# Lancement du déploiement
deployer_application "${app_name}" "${environment}" "${technology}" "${version}" "${config_file}" "${extra_params}" "${debug_mode}"

exit 0
