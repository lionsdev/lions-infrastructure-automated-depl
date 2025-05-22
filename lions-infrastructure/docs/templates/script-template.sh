#!/bin/bash
# =============================================================================
# Titre: Nom du Script
# Description: Description détaillée du script et de son objectif
# Auteur: Nom de l'auteur
# Date de création: YYYY-MM-DD
# Version: 1.0.0
# Usage: ./script-template.sh [options]
# =============================================================================

# Strict mode
set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Répertoire racine du projet
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Fichier de log
LOG_DIR="${PROJECT_ROOT}/scripts/logs"
LOG_FILE="${LOG_DIR}/$(basename "$0").log"

# Variables de configuration
CONFIG_FILE="${PROJECT_ROOT}/.env"
DEFAULT_ENVIRONMENT="development"
DEFAULT_TIMEOUT=30

# =============================================================================
# Fonctions
# =============================================================================

# Fonction d'affichage de l'aide
show_help() {
    cat << EOF
Usage: $(basename "$0") [options]

Description:
    Description détaillée du script et de son objectif.

Options:
    -h, --help              Affiche cette aide
    -e, --environment ENV   Spécifie l'environnement (development, staging, production)
    -v, --verbose           Mode verbeux
    -d, --dry-run           Mode simulation (n'effectue aucune action)
    -t, --timeout SEC       Délai d'attente en secondes (défaut: ${DEFAULT_TIMEOUT})

Exemples:
    $(basename "$0") --environment production
    $(basename "$0") --verbose --timeout 60
EOF
    exit 0
}

# Fonction de journalisation
log() {
    local level=$1
    local message=$2
    local color=$NC
    
    case $level in
        "INFO") color=$NC ;;
        "SUCCESS") color=$GREEN ;;
        "WARNING") color=$YELLOW ;;
        "ERROR") color=$RED ;;
        "DEBUG") 
            if [[ "${VERBOSE}" != "true" ]]; then
                return
            fi
            color=$BLUE 
            ;;
    esac
    
    # Création du répertoire de logs si nécessaire
    mkdir -p "${LOG_DIR}"
    
    # Format de date pour les logs
    local date_format=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Affichage dans la console
    echo -e "${color}[${date_format}] [${level}] ${message}${NC}"
    
    # Écriture dans le fichier de log
    echo "[${date_format}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Fonction de nettoyage à la sortie
cleanup() {
    local exit_code=$?
    
    # Actions de nettoyage
    log "INFO" "Nettoyage des ressources temporaires..."
    
    # Suppression des fichiers temporaires
    rm -f /tmp/script-temp-*
    
    # Message de fin
    if [ ${exit_code} -eq 0 ]; then
        log "SUCCESS" "Script terminé avec succès"
    else
        log "ERROR" "Script terminé avec des erreurs (code: ${exit_code})"
    fi
    
    exit ${exit_code}
}

# Fonction de gestion des erreurs
handle_error() {
    local line=$1
    local command=$2
    local code=$3
    log "ERROR" "Erreur à la ligne ${line} (commande: '${command}', code: ${code})"
}

# Fonction de vérification des prérequis
check_prerequisites() {
    log "INFO" "Vérification des prérequis..."
    
    # Vérification des commandes requises
    for cmd in kubectl jq curl; do
        if ! command -v ${cmd} &> /dev/null; then
            log "ERROR" "La commande '${cmd}' est requise mais n'est pas installée"
            exit 1
        fi
    done
    
    # Vérification des variables d'environnement
    if [ -f "${CONFIG_FILE}" ]; then
        source "${CONFIG_FILE}"
    else
        log "WARNING" "Fichier de configuration ${CONFIG_FILE} non trouvé"
    fi
    
    # Vérification des droits d'accès
    if [ ! -w "${LOG_DIR}" ]; then
        log "WARNING" "Droits d'écriture insuffisants pour le répertoire de logs"
        LOG_FILE="/tmp/$(basename "$0").log"
        log "INFO" "Les logs seront écrits dans ${LOG_FILE}"
    fi
}

# Fonction principale
main() {
    log "INFO" "Démarrage du script..."
    
    # Logique principale du script
    log "INFO" "Exécution dans l'environnement: ${ENVIRONMENT}"
    
    if [ "${DRY_RUN}" = "true" ]; then
        log "WARNING" "Mode simulation activé, aucune action ne sera effectuée"
        # Simuler les actions sans les exécuter
        log "DEBUG" "Simulation: Action 1"
        log "DEBUG" "Simulation: Action 2"
    else
        # Exécution des actions réelles
        log "INFO" "Exécution de l'action 1..."
        # Action 1
        
        log "INFO" "Exécution de l'action 2..."
        # Action 2
    fi
    
    log "SUCCESS" "Opérations terminées avec succès"
}

# =============================================================================
# Traitement des arguments
# =============================================================================

# Valeurs par défaut
ENVIRONMENT="${DEFAULT_ENVIRONMENT}"
VERBOSE="false"
DRY_RUN="false"
TIMEOUT="${DEFAULT_TIMEOUT}"

# Analyse des arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE="true"
            shift
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Option inconnue: $1"
            show_help
            ;;
    esac
done

# Validation des arguments
if [[ ! "${ENVIRONMENT}" =~ ^(development|staging|production)$ ]]; then
    log "ERROR" "Environnement invalide: ${ENVIRONMENT}"
    log "INFO" "Les environnements valides sont: development, staging, production"
    exit 1
fi

if ! [[ "${TIMEOUT}" =~ ^[0-9]+$ ]]; then
    log "ERROR" "Le délai d'attente doit être un nombre entier"
    exit 1
fi

# =============================================================================
# Initialisation
# =============================================================================

# Enregistrement des gestionnaires de signaux
trap 'cleanup' EXIT
trap 'handle_error ${LINENO} "$BASH_COMMAND" $?' ERR

# Vérification des prérequis
check_prerequisites

# =============================================================================
# Exécution
# =============================================================================

# Exécution de la fonction principale
main