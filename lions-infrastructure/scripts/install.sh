
#!/usr/bin/env bash
# =========================================================================
# LIONS INFRASTRUCTURE 5.0 - SCRIPT D'INSTALLATION PRINCIPAL
# =========================================================================
# Description: Script principal d'installation de l'infrastructure LIONS
# Version: 5.0.0
# Maintainer: DevOps LIONS Team <devops@lions.dev>
# Documentation: https://docs.lions.dev/infrastructure/scripts/install
# =========================================================================

# =========================================================================
# CONFIGURATION ET VARIABLES D'ENVIRONNEMENT
# =========================================================================
set -euo pipefail
IFS=$'\n\t'

# Couleurs pour la sortie console
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_PURPLE='\033[0;35m'
readonly COLOR_CYAN='\033[0;36m'

# Variables de configuration avec valeurs par défaut
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
ENVIRONMENT="development"
UPDATE_ONLY=false
SKIP_CONFIRMATION=false
DRY_RUN=false
DEBUG_MODE=false
COMPONENTS_TO_INSTALL=()
SKIP_PREREQUISITES=false
CONFIG_FILE="${PROJECT_ROOT}/lions-infrastructure/config/installation.yaml"

# Constantes de version et d'identification
readonly SCRIPT_VERSION="5.0.0"
readonly SCRIPT_NAME="LIONS Infrastructure 5.0 Installer"
readonly INSTALLATION_ID="$(date +%s)"

# Variables pour le suivi de progression
declare -A INSTALLATION_STATUS
INSTALLATION_START_TIME=$(date +%s)
INSTALLATION_STEPS_TOTAL=6
INSTALLATION_STEP_CURRENT=0

# =========================================================================
# FONCTIONS UTILITAIRES
# =========================================================================

# Fonction d'affichage de messages
log() {
    local level=$1
    local message=$2
    local color=$COLOR_RESET
    local stderr=false
    
    case $level in
        "INFO")
            color=$COLOR_BLUE
            ;;
        "SUCCESS")
            color=$COLOR_GREEN
            ;;
        "WARN")
            color=$COLOR_YELLOW
            ;;
        "ERROR")
            color=$COLOR_RED
            stderr=true
            ;;
        "DEBUG")
            if [[ "$DEBUG_MODE" != true ]]; then
                return
            fi
            color=$COLOR_PURPLE
            ;;
        *)
            color=$COLOR_RESET
            ;;
    esac

    # Format du timestamp
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Afficher sur le terminal
    if [[ "$stderr" == true ]]; then
        echo -e "${color}[${timestamp}] [${level}] ${message}${COLOR_RESET}" >&2
    else
        echo -e "${color}[${timestamp}] [${level}] ${message}${COLOR_RESET}"
    fi
    
    # Enregistrer dans le fichier journal sans les codes de couleur
    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
}

# Fonction d'affichage de la progression
show_progress() {
    local step=$1
    local description=$2
    local status=${3:-"PENDING"}
    local color=$COLOR_RESET
    
    case $status in
        "SUCCESS")
            color=$COLOR_GREEN
            INSTALLATION_STATUS[$step]="SUCCESS"
            ;;
        "FAILED")
            color=$COLOR_RED
            INSTALLATION_STATUS[$step]="FAILED"
            ;;
        "SKIPPED")
            color=$COLOR_YELLOW
            INSTALLATION_STATUS[$step]="SKIPPED"
            ;;
        *)
            color=$COLOR_BLUE
            INSTALLATION_STATUS[$step]="PENDING"
            ;;
    esac
    
    # Mettre à jour le compteur d'étapes
    INSTALLATION_STEP_CURRENT=$step
    
    # Calculer le pourcentage de progression
    local percent=$((step * 100 / INSTALLATION_STEPS_TOTAL))
    
    # Afficher la barre de progression
    printf "${color}[%3d%%] Étape %d/%d: %s - %s${COLOR_RESET}\n" \
           $percent $step $INSTALLATION_STEPS_TOTAL "$description" "$status"
}

# Fonction d'affichage de l'en-tête
show_header() {
    local width=80
    local line=$(printf "%${width}s" | tr ' ' '=')
    
    echo -e "${COLOR_CYAN}${line}${COLOR_RESET}"
    echo -e "${COLOR_CYAN}= %-$((width-4))s =${COLOR_RESET}" "${SCRIPT_NAME} v${SCRIPT_VERSION}"
    echo -e "${COLOR_CYAN}= %-$((width-4))s =${COLOR_RESET}" "Installation ID: ${INSTALLATION_ID}"
    echo -e "${COLOR_CYAN}= %-$((width-4))s =${COLOR_RESET}" "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${COLOR_CYAN}= %-$((width-4))s =${COLOR_RESET}" "Environnement: ${ENVIRONMENT}"
    echo -e "${COLOR_CYAN}${line}${COLOR_RESET}"
}

# Fonction de nettoyage à la sortie
cleanup() {
    local exit_code=$?
    local duration=$(($(date +%s) - INSTALLATION_START_TIME))
    
    if [[ $exit_code -eq 0 ]]; then
        log "SUCCESS" "Installation terminée avec succès en ${duration} secondes"
    else
        log "ERROR" "Installation terminée avec des erreurs (code ${exit_code}) en ${duration} secondes"
    fi
    
    # Enregistrer le rapport d'installation
    generate_installation_report
    
    log "INFO" "Journal d'installation enregistré dans: ${LOG_FILE}"
    
    exit $exit_code
}

# Fonction de gestion des erreurs
handle_error() {
    local line=$1
    local command=$2
    local exit_code=$3
    
    log "ERROR" "Erreur à la ligne ${line}, commande '${command}' a échoué avec le code ${exit_code}"
    
    # Mettre à jour le statut de l'étape actuelle
    if [[ $INSTALLATION_STEP_CURRENT -gt 0 ]]; then
        show_progress $INSTALLATION_STEP_CURRENT "Étape en cours" "FAILED"
    fi
    
    cleanup
}

# Générer un rapport d'installation
generate_installation_report() {
    local report_file="${LOG_DIR}/installation-report-${INSTALLATION_ID}.json"
    local duration=$(($(date +%s) - INSTALLATION_START_TIME))
    local status="SUCCESS"
    
    # Déterminer le statut global
    for key in "${!INSTALLATION_STATUS[@]}"; do
        if [[ "${INSTALLATION_STATUS[$key]}" == "FAILED" ]]; then
            status="FAILED"
            break
        fi
    done
    
    # Générer le rapport en JSON
    cat > "$report_file" << EOF
{
  "installationId": "${INSTALLATION_ID}",
  "scriptVersion": "${SCRIPT_VERSION}",
  "environment": "${ENVIRONMENT}",
  "startTime": "$(date -d @${INSTALLATION_START_TIME} '+%Y-%m-%d %H:%M:%S')",
  "endTime": "$(date '+%Y-%m-%d %H:%M:%S')",
  "duration": ${duration},
  "status": "${status}",
  "stepStatus": {
EOF

    # Ajouter le statut de chaque étape
    local first=true
    for key in $(echo "${!INSTALLATION_STATUS[@]}" | tr ' ' '\n' | sort -n); do
        if [[ "$first" != true ]]; then
            echo "," >> "$report_file"
        fi
        first=false
        printf "    \"step%d\": \"%s\"" "$key" "${INSTALLATION_STATUS[$key]}" >> "$report_file"
    done

    # Finaliser le JSON
    cat >> "$report_file" << EOF

  },
  "components": [
EOF
    
    # Ajouter les composants installés
    first=true
    for component in "${COMPONENTS_TO_INSTALL[@]}"; do
        if [[ "$first" != true ]]; then
            echo "," >> "$report_file"
        fi
        first=false
        printf "    \"%s\"" "$component" >> "$report_file"
    done
    
    # Finaliser le JSON
    cat >> "$report_file" << EOF

  ],
  "updateOnly": ${UPDATE_ONLY},
  "dryRun": ${DRY_RUN}
}
EOF

    log "INFO" "Rapport d'installation généré: ${report_file}"
}

# Fonction d'affichage de l'aide
show_help() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}

Description:
    Script principal d'installation de l'infrastructure LIONS 5.0

Usage:
    $(basename "$0") [options]

Options:
    -h, --help              Affiche cette aide
    -e, --environment       Spécifie l'environnement (development, staging, production)
                            Défaut: development
    -c, --components        Liste de composants à installer (séparés par des virgules)
                            Exemple: --components=k3s,monitoring,vault
    -u, --update-only       Met à jour les composants existants sans réinstallation
    -y, --yes               Ignore les confirmations utilisateur
    -d, --dry-run           Simule l'installation sans appliquer les changements
    --debug                 Active le mode debug avec logs détaillés
    --skip-prerequisites    Ignore la vérification des prérequis

Exemples:
    $(basename "$0") --environment development
    $(basename "$0") -e production -c k3s,monitoring,vault -y
    $(basename "$0") --update-only --environment staging

Documentation:
    https://docs.lions.dev/infrastructure/scripts/install
EOF
    exit 0
}

# Fonction de vérification des prérequis
check_prerequisites() {
    log "INFO" "Vérification des prérequis système..."
    
    # Vérifier la version de Bash
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        log "ERROR" "Bash 4.0 ou supérieur est requis (version actuelle: ${BASH_VERSION})"
        return 1
    fi
    
    # Vérifier les commandes requises
    local required_commands=("curl" "kubectl" "ansible" "ansible-playbook" "jq" "openssl" "ssh")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log "ERROR" "Commandes requises manquantes: ${missing_commands[*]}"
        log "INFO" "Installez les commandes manquantes avant de continuer."
        return 1
    fi
    
    # Vérifier la connexion Internet
    if ! curl -s --connect-timeout 5 https://docs.lions.dev &> /dev/null; then
        log "WARN" "Impossible de se connecter à Internet, certaines fonctionnalités peuvent être limitées"
    fi
    
    # Vérifier l'accès aux répertoires nécessaires
    if [[ ! -d "$PROJECT_ROOT" ]]; then
        log "ERROR" "Répertoire racine du projet introuvable: $PROJECT_ROOT"
        return 1
    fi
    
    # Vérifier les permissions d'exécution
    if [[ ! -x "$0" ]]; then
        log "ERROR" "Le script n'a pas les permissions d'exécution"
        return 1
    fi
    
    # Créer le répertoire de logs s'il n'existe pas
    mkdir -p "$LOG_DIR"
    
    log "SUCCESS" "Vérification des prérequis système terminée"
    return 0
}

# Fonction de chargement de la configuration
load_configuration() {
    log "INFO" "Chargement de la configuration..."
    
    # Vérifier si le fichier de configuration existe
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "WARN" "Fichier de configuration non trouvé: $CONFIG_FILE, utilisation des valeurs par défaut"
        return 0
    fi
    
    # Vérifier si jq est disponible pour le parsing JSON/YAML
    if command -v jq &> /dev/null && command -v yq &> /dev/null; then
        # Charger et traiter la configuration avec yq/jq
        local env_config
        env_config=$(yq eval ".environments.${ENVIRONMENT}" "$CONFIG_FILE" -j)
        
        # Extraire les composants si spécifiés
        if [[ -z "${COMPONENTS_TO_INSTALL[*]}" ]]; then
            readarray -t COMPONENTS_TO_INSTALL < <(echo "$env_config" | jq -r '.components[]? // empty')
        fi
        
        log "DEBUG" "Composants chargés depuis la configuration: ${COMPONENTS_TO_INSTALL[*]}"
    else
        log "WARN" "yq/jq non disponibles, impossible de charger la configuration avancée"
    fi
    
    log "SUCCESS" "Configuration chargée avec succès"
    return 0
}

# Fonction de confirmation utilisateur
confirm() {
    local message=$1
    local default=${2:-"n"}
    
    if [[ "$SKIP_CONFIRMATION" == true ]]; then
        return 0
    fi
    
    local prompt
    
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi
    
    read -r -p "$message $prompt " response
    response=${response,,}  # Convertir en minuscules
    
    if [[ -z "$response" ]]; then
        response=$default
    fi
    
    if [[ "$response" =~ ^(yes|y)$ ]]; then
        return 0
    else
        return 1
    fi
}

# Fonction d'installation d'un composant
install_component() {
    local component=$1
    local action=${2:-"install"}
    
    log "INFO" "Début de ${action} du composant: $component"
    
    # Vérifier si le script d'installation du composant existe
    local component_script="${SCRIPT_DIR}/components/${component}.sh"
    
    if [[ ! -f "$component_script" ]]; then
        log "ERROR" "Script d'installation non trouvé pour le composant: $component"
        return 1
    fi
    
    # Exécuter le script avec les paramètres appropriés
    local cmd=(
        "bash" "$component_script"
        "--environment" "$ENVIRONMENT"
        "--action" "$action"
        "--installation-id" "$INSTALLATION_ID"
    )
    
    if [[ "$DRY_RUN" == true ]]; then
        cmd+=("--dry-run")
    fi
    
    if [[ "$DEBUG_MODE" == true ]]; then
        cmd+=("--debug")
    fi
    
    if [[ "$SKIP_CONFIRMATION" == true ]]; then
        cmd+=("--yes")
    fi
    
    log "DEBUG" "Exécution de la commande: ${cmd[*]}"
    
    if "${cmd[@]}"; then
        log "SUCCESS" "${action^} du composant $component terminé avec succès"
        return 0
    else
        local exit_code=$?
        log "ERROR" "${action^} du composant $component a échoué avec le code $exit_code"
        return $exit_code
    fi
}

# =========================================================================
# FONCTIONS PRINCIPALES D'INSTALLATION
# =========================================================================

# Étape 1: Préparation de l'environnement
prepare_environment() {
    show_progress 1 "Préparation de l'environnement" "PENDING"
    
    log "INFO" "Préparation de l'environnement d'installation..."
    
    # Charger les variables d'environnement spécifiques
    if [[ -f "${SCRIPT_DIR}/load-env.sh" ]]; then
        log "DEBUG" "Chargement des variables d'environnement depuis load-env.sh"
        source "${SCRIPT_DIR}/load-env.sh" "$ENVIRONMENT"
    fi
    
    # Vérifier l'accès SSH si nécessaire pour les déploiements distants
    if [[ "$ENVIRONMENT" != "local" && "$ENVIRONMENT" != "development" ]]; then
        log "INFO" "Vérification de l'accès SSH pour l'environnement $ENVIRONMENT"
        # Logique de vérification SSH ici
    fi
    
    # Créer les répertoires nécessaires
    mkdir -p "${PROJECT_ROOT}/lions-infrastructure/tmp/${ENVIRONMENT}"
    
    show_progress 1 "Préparation de l'environnement" "SUCCESS"
    return 0
}

# Étape 2: Installation des composants de base
install_base_components() {
    show_progress 2 "Installation des composants de base" "PENDING"
    
    log "INFO" "Installation des composants de base..."
    
    local base_components=("k3s" "helm" "ingress")
    local action="install"
    
    if [[ "$UPDATE_ONLY" == true ]]; then
        action="update"
    fi
    
    for component in "${base_components[@]}"; do
        if [[ "${#COMPONENTS_TO_INSTALL[@]}" -eq 0 ]] || [[ " ${COMPONENTS_TO_INSTALL[*]} " == *" $component "* ]]; then
            if ! install_component "$component" "$action"; then
                show_progress 2 "Installation des composants de base" "FAILED"
                return 1
            fi
        else
            log "INFO" "Composant $component ignoré (non spécifié dans la liste des composants)"
        fi
    done
    
    show_progress 2 "Installation des composants de base" "SUCCESS"
    return 0
}

# Étape 3: Installation des services d'infrastructure
install_infrastructure_services() {
    show_progress 3 "Installation des services d'infrastructure" "PENDING"
    
    log "INFO" "Installation des services d'infrastructure..."
    
    local infra_components=("monitoring" "logging" "vault" "certmanager")
    local action="install"
    
    if [[ "$UPDATE_ONLY" == true ]]; then
        action="update"
    fi
    
    for component in "${infra_components[@]}"; do
        if [[ "${#COMPONENTS_TO_INSTALL[@]}" -eq 0 ]] || [[ " ${COMPONENTS_TO_INSTALL[*]} " == *" $component "* ]]; then
            if ! install_component "$component" "$action"; then
                show_progress 3 "Installation des services d'infrastructure" "FAILED"
                return 1
            fi
        else
            log "INFO" "Composant $component ignoré (non spécifié dans la liste des composants)"
        fi
    done
    
    show_progress 3 "Installation des services d'infrastructure" "SUCCESS"
    return 0
}

# Étape 4: Configuration des services métier
configure_business_services() {
    show_progress 4 "Configuration des services métier" "PENDING"
    
    log "INFO" "Configuration des services métier..."
    
    local business_components=("database" "messaging" "cache" "storage" "ai")
    local action="install"
    
    if [[ "$UPDATE_ONLY" == true ]]; then
        action="update"
    fi
    
    for component in "${business_components[@]}"; do
        if [[ "${#COMPONENTS_TO_INSTALL[@]}" -eq 0 ]] || [[ " ${COMPONENTS_TO_INSTALL[*]} " == *" $component "* ]]; then
            if ! install_component "$component" "$action"; then
                log "WARN" "Installation du composant $component a échoué, mais l'installation continue"
                # Ne pas échouer l'étape complète pour les services métier non critiques
            fi
        else
            log "INFO" "Composant $component ignoré (non spécifié dans la liste des composants)"
        fi
    done
    
    show_progress 4 "Configuration des services métier" "SUCCESS"
    return 0
}

# Étape 5: Configuration des outils de déploiement
configure_deployment_tools() {
    show_progress 5 "Configuration des outils de déploiement" "PENDING"
    
    log "INFO" "Configuration des outils de déploiement..."
    
    local deployment_components=("argocd" "tekton" "harbor")
    local action="install"
    
    if [[ "$UPDATE_ONLY" == true ]]; then
        action="update"
    fi
    
    for component in "${deployment_components[@]}"; do
        if [[ "${#COMPONENTS_TO_INSTALL[@]}" -eq 0 ]] || [[ " ${COMPONENTS_TO_INSTALL[*]} " == *" $component "* ]]; then
            if ! install_component "$component" "$action"; then
                show_progress 5 "Configuration des outils de déploiement" "FAILED"
                return 1
            fi
        else
            log "INFO" "Composant $component ignoré (non spécifié dans la liste des composants)"
        fi
    done
    
    show_progress 5 "Configuration des outils de déploiement" "SUCCESS"
    return 0
}

# Étape 6: Validation et tests
validate_installation() {
    show_progress 6 "Validation et tests" "PENDING"
    
    log "INFO" "Validation de l'installation..."
    
    # Vérifier le statut du cluster Kubernetes
    if ! kubectl get nodes &> /dev/null; then
        log "ERROR" "Impossible d'accéder au cluster Kubernetes"
        show_progress 6 "Validation et tests" "FAILED"
        return 1
    fi
    
    # Vérifier les pods système
    local system_namespaces=("kube-system" "monitoring" "cert-manager" "ingress-nginx")
    
    for ns in "${system_namespaces[@]}"; do
        if kubectl get namespace "$ns" &> /dev/null; then
            log "INFO" "Vérification des pods dans le namespace $ns"
            local unhealthy_pods
            unhealthy_pods=$(kubectl get pods -n "$ns" -o json | jq -r '.items[] | select(.status.phase != "Running" and .status.phase != "Succeeded") | .metadata.name')
            
            if [[ -n "$unhealthy_pods" ]]; then
                log "WARN" "Pods non sains détectés dans $ns: $unhealthy_pods"
            else
                log "SUCCESS" "Tous les pods sont sains dans le namespace $ns"
            fi
        else
            log "WARN" "Namespace $ns non trouvé, ignoré"
        fi
    done
    
    # Exécuter les tests spécifiques à l'environnement
    if [[ -f "${SCRIPT_DIR}/tests/test-${ENVIRONMENT}.sh" ]]; then
        log "INFO" "Exécution des tests spécifiques à l'environnement ${ENVIRONMENT}"
        if bash "${SCRIPT_DIR}/tests/test-${ENVIRONMENT}.sh"; then
            log "SUCCESS" "Tests spécifiques à l'environnement réussis"
        else
            log "WARN" "Certains tests spécifiques à l'environnement ont échoué"
        fi
    fi
    
    # Enregistrer les informations d'accès
    local access_info_file="${LOG_DIR}/access-info-${INSTALLATION_ID}.txt"
    
    {
        echo "==========================================="
        echo "INFORMATIONS D'ACCÈS À L'INFRASTRUCTURE"
        echo "==========================================="
        echo "Environnement: ${ENVIRONMENT}"
        echo "Date d'installation: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "ID d'installation: ${INSTALLATION_ID}"
        echo "-------------------------------------------"
        echo "URL du dashboard: https://dashboard.${ENVIRONMENT}.lions.dev"
        
        if kubectl get namespace argocd &> /dev/null; then
            echo "URL ArgoCD: https://argocd.${ENVIRONMENT}.lions.dev"
        fi
        
        if kubectl get namespace monitoring &> /dev/null; then
            echo "URL Grafana: https://grafana.${ENVIRONMENT}.lions.dev"
            echo "URL Prometheus: https://prometheus.${ENVIRONMENT}.lions.dev"
        fi
        
        echo "-------------------------------------------"
        echo "Pour plus d'informations, consultez:"
        echo "https://docs.lions.dev/infrastructure/access"
        echo "==========================================="
    } > "$access_info_file"
    
    log "INFO" "Informations d'accès enregistrées dans: $access_info_file"
    
    show_progress 6 "Validation et tests" "SUCCESS"
    return 0
}

# =========================================================================
# TRAITEMENT DES ARGUMENTS DE LIGNE DE COMMANDE
# =========================================================================
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -e=*|--environment=*)
                ENVIRONMENT="${1#*=}"
                shift
                ;;
            -c|--components)
                IFS=',' read -ra COMPONENTS_TO_INSTALL <<< "$2"
                shift 2
                ;;
            -c=*|--components=*)
                IFS=',' read -ra COMPONENTS_TO_INSTALL <<< "${1#*=}"
                shift
                ;;
            -u|--update-only)
                UPDATE_ONLY=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --debug)
                DEBUG_MODE=true
                shift
                ;;
            --skip-prerequisites)
                SKIP_PREREQUISITES=true
                shift
                ;;
            *)
                log "ERROR" "Option non reconnue: $1"
                show_help
                ;;
        esac
    done
    
    # Validation de l'environnement
    case $ENVIRONMENT in
        development|staging|production|local)
            ;;
        *)
            log "ERROR" "Environnement non valide: $ENVIRONMENT. Utilisez development, staging, production ou local."
            exit 1
            ;;
    esac
    
    # Mise à jour du fichier de log avec l'environnement
    LOG_FILE="${LOG_DIR}/install-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).log"
    
    return 0
}

# =========================================================================
# FONCTION PRINCIPALE
# =========================================================================
main() {
    # Configurer le gestionnaire d'erreurs
    trap 'handle_error ${LINENO} "$BASH_COMMAND" $?' ERR
    # Configurer le nettoyage à la sortie
    trap cleanup EXIT
    
    # Créer le répertoire de logs
    mkdir -p "$LOG_DIR"
    
    # Analyser les arguments
    parse_arguments "$@"
    
    # Afficher l'en-tête
    show_header
    
    # Mode dry-run
    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "Mode DRY RUN activé - aucune modification ne sera apportée"
    fi
    
    # Vérifier les prérequis sauf si ignorés
    if [[ "$SKIP_PREREQUISITES" != true ]]; then
        if ! check_prerequisites; then
            log "ERROR" "La vérification des prérequis a échoué"
            exit 1
        fi
    else
        log "WARN" "Vérification des prérequis ignorée"
    fi
    
    # Charger la configuration
    load_configuration
    
    # Afficher le résumé avant l'installation
    log "INFO" "===== RÉSUMÉ DE L'INSTALLATION ====="
    log "INFO" "Environnement: $ENVIRONMENT"
    log "INFO" "Mode: $(if [[ "$UPDATE_ONLY" == true ]]; then echo "Mise à jour"; else echo "Installation"; fi)"
    log "INFO" "Composants: $(if [[ ${#COMPONENTS_TO_INSTALL[@]} -eq 0 ]]; then echo "Tous"; else echo "${COMPONENTS_TO_INSTALL[*]}"; fi)"
    log "INFO" "================================="
    
    # Demander confirmation avant de continuer
    if ! confirm "Voulez-vous continuer avec l'installation ?" "y"; then
        log "INFO" "Installation annulée par l'utilisateur"
        exit 0
    fi
    
    # Exécuter les étapes d'installation
    if ! prepare_environment; then
        log "ERROR" "Échec de la préparation de l'environnement"
        exit 1
    fi
    
    if ! install_base_components; then
        log "ERROR" "Échec de l'installation des composants de base"
        exit 1
    fi
    
    if ! install_infrastructure_services; then
        log "ERROR" "Échec de l'installation des services d'infrastructure"
        exit 1
    fi
    
    if ! configure_business_services; then
        log "WARN" "Des problèmes sont survenus lors de la configuration des services métier"
        # Ne pas quitter, continuer avec les étapes suivantes
    fi
    
    if ! configure_deployment_tools; then
        log "ERROR" "Échec de la configuration des outils de déploiement"
        exit 1
    fi
    
    if ! validate_installation; then
        log "WARN" "Des problèmes ont été détectés lors de la validation"
        # Continuer mais avec un avertissement
    fi
    
    # Afficher le résumé final
    log "SUCCESS" "===== INSTALLATION TERMINÉE ====="
    log "SUCCESS" "Environnement: $ENVIRONMENT"
    log "SUCCESS" "ID d'installation: $INSTALLATION_ID"
    log "SUCCESS" "Journal: $LOG_FILE"
    log "SUCCESS" "================================="
    
    return 0
}

# Exécuter la fonction principale avec tous les arguments
main "$@"