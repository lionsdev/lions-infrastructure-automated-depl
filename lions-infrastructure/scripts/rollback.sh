#!/bin/bash
# Titre: Script de rollback
# Description: Permet de revenir à une version précédente d'une application
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-08
# Version: 1.1.0

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DIR="/var/log/lions/deployments"
readonly LOG_FILE="${LOG_DIR}/rollback-$(date +%Y%m%d-%H%M%S).log"
readonly BACKUP_DIR="${LOG_DIR}/backups"

# Création des répertoires de logs et de backups
mkdir -p "${LOG_DIR}"
mkdir -p "${BACKUP_DIR}"

# Fonction de logging
function log() {
    local level="$1"
    local message="$2"
    local timestamp="$(date +"%Y-%m-%d %H:%M:%S")"

    echo "[${timestamp}] [${level}] ${message}"
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Fonction pour créer une sauvegarde avant rollback
function creer_sauvegarde() {
    local app_name="$1"
    local environment="$2"
    local namespace="${app_name}-${environment}"
    local backup_timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="${BACKUP_DIR}/${app_name}-${environment}-pre-rollback-${backup_timestamp}.tar.gz"

    log "INFO" "Création d'une sauvegarde avant rollback"

    # Vérification si l'application existe
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
        echo "${backup_file}" > "${BACKUP_DIR}/${app_name}-${environment}-pre-rollback-latest.txt"
    else
        log "WARNING" "L'application n'existe pas dans cet environnement, impossible de créer une sauvegarde"
    fi
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

# Création d'une sauvegarde avant rollback
creer_sauvegarde "${app_name}" "${environment}"

# Exécution du rollback
log "INFO" "Exécution du rollback de l'application ${app_name} vers la version ${version}..."

# Ajout d'un mécanisme de reprise en cas d'erreur
set +e  # Désactivation du mode strict pour gérer les erreurs
if kubectl rollout undo deployment/${app_name} -n ${app_name}-${environment} --to-revision=${version}; then
    log "SUCCESS" "Rollback réussi vers la version ${version}"

    # Vérification du statut du rollback
    log "INFO" "Vérification du statut du rollback..."
    if kubectl rollout status deployment/${app_name} -n ${app_name}-${environment} --timeout=5m; then
        log "SUCCESS" "Rollback terminé avec succès"

        # Sauvegarde des informations sur la version actuelle après rollback
        current_revision=$(kubectl rollout history deployment/${app_name} -n ${app_name}-${environment} | grep -A1 "REVISION" | tail -n1 | awk '{print $1}')
        echo "${current_revision}" > "${BACKUP_DIR}/${app_name}-${environment}-current-revision.txt"

        # Vérification de l'état des pods après rollback
        log "INFO" "Vérification de l'état des pods après rollback..."
        kubectl get pods -n ${app_name}-${environment}
    else
        log "ERROR" "Le déploiement après rollback n'est pas stable"
        log "WARNING" "Vérifiez manuellement l'état de l'application"
        exit 1
    fi
else
    log "ERROR" "Le rollback a échoué"

    # Tentative de diagnostic
    log "INFO" "Tentative de diagnostic de l'échec..."
    log "INFO" "État actuel du déploiement:"
    kubectl describe deployment/${app_name} -n ${app_name}-${environment} || true

    log "INFO" "Événements récents dans le namespace:"
    kubectl get events -n ${app_name}-${environment} --sort-by='.lastTimestamp' | tail -10 || true

    log "ERROR" "Le rollback a échoué. Veuillez vérifier les logs pour plus d'informations."
    exit 1
fi
set -e  # Réactivation du mode strict

exit 0
