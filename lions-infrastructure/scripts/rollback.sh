#!/bin/bash
# Titre: Script de rollback
# Description: Permet de revenir à une version précédente d'une application
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-08
# Version: 1.0.0

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DIR="/var/log/lions/deployments"
readonly LOG_FILE="${LOG_DIR}/rollback-$(date +%Y%m%d-%H%M%S).log"

# Création du répertoire de logs
mkdir -p "${LOG_DIR}"

# Fonction de logging
function log() {
    local level="$1"
    local message="$2"
    local timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
    
    echo "[${timestamp}] [${level}] ${message}"
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Fonction d'affichage de l'aide
function afficher_aide() {
    cat << EOF
Script de Rollback - Infrastructure LIONS

Ce script permet de revenir à une version précédente d'une application.

Usage:
    $0 [options] <nom_application>

Options:
    -e, --environment <env>   Environnement cible (production, staging, development)
                             Par défaut: development
    -v, --version <version>   Version spécifique à restaurer
                             Par défaut: version précédente
    -h, --help                Affiche cette aide

Exemples:
    $0 mon-api-backend
    $0 --environment production --version 1.2.3 mon-application-frontend
EOF
}

# Parsing des arguments
app_name=""
environment="development"
version=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--environment)
            environment="$2"
            shift 2
            ;;
        -v|--version)
            version="$2"
            shift 2
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
if [[ ! "${environment}" =~ ^(production|staging|development)$ ]]; then
    log "ERROR" "Environnement non valide: ${environment}"
    log "ERROR" "Valeurs autorisées: production, staging, development"
    exit 1
fi

# Si aucune version n'est spécifiée, récupérer la version précédente
if [[ -z "${version}" ]]; then
    log "INFO" "Récupération de la version précédente..."
    
    # Récupération de l'historique des déploiements
    rollout_history=$(kubectl rollout history deployment/${app_name} -n ${app_name}-${environment})
    
    # Extraction de la version précédente
    previous_revision=$(echo "${rollout_history}" | grep -A1 "REVISION" | tail -n1 | awk '{print $1}')
    
    if [[ -z "${previous_revision}" ]]; then
        log "ERROR" "Impossible de récupérer la version précédente"
        exit 1
    fi
    
    log "INFO" "Version précédente trouvée: ${previous_revision}"
    version="${previous_revision}"
fi

# Confirmation du rollback
read -p "Êtes-vous sûr de vouloir revenir à la version ${version} de l'application ${app_name} en environnement ${environment}? (oui/NON): " confirmation
if [[ "${confirmation}" != "oui" ]]; then
    log "INFO" "Rollback annulé par l'utilisateur"
    exit 0
fi

# Exécution du rollback
log "INFO" "Exécution du rollback de l'application ${app_name} vers la version ${version}..."

if kubectl rollout undo deployment/${app_name} -n ${app_name}-${environment} --to-revision=${version}; then
    log "SUCCESS" "Rollback réussi vers la version ${version}"
    
    # Vérification du statut du rollback
    log "INFO" "Vérification du statut du rollback..."
    kubectl rollout status deployment/${app_name} -n ${app_name}-${environment}
    
    log "SUCCESS" "Rollback terminé avec succès"
else
    log "ERROR" "Le rollback a échoué"
    exit 1
fi

exit 0