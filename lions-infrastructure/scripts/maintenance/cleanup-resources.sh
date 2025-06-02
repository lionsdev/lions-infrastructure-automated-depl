#!/bin/bash
# =============================================================================
# LIONS Infrastructure - Script de nettoyage des ressources v5.0
# =============================================================================
# Description: Nettoie les ressources inutilisées dans le cluster Kubernetes
# Version: 5.0.0
# Date: 01/06/2025
# Auteur: LIONS DevOps Team
# =============================================================================

set -euo pipefail

# Chargement des variables d'environnement
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Chargement des variables d'environnement depuis le fichier .env
if [ -f "${PROJECT_ROOT}/.env" ]; then
    source "${PROJECT_ROOT}/.env"
fi

# Configuration depuis variables d'environnement
readonly LIONS_ENVIRONMENT="${LIONS_ENVIRONMENT:-development}"
readonly LOG_DIR="${LIONS_MAINTENANCE_LOG_DIR:-${PROJECT_ROOT}/scripts/logs/maintenance}"
readonly LOG_FILE="${LOG_DIR}/cleanup-$(date +%Y%m%d-%H%M%S).log"
readonly KUBE_CONFIG="${LIONS_KUBE_CONFIG_PATH:-${HOME}/.kube/config}"
readonly KUBE_CONTEXT="${LIONS_KUBE_CONTEXT:-${LIONS_CLUSTER_NAME:-lions-k3s-cluster}}"

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
Script de Nettoyage des Ressources - Infrastructure LIONS

Ce script nettoie les ressources inutilisées dans le cluster Kubernetes.

Usage:
    $0 [options]

Options:
    -n, --namespace <namespace>   Namespace spécifique à nettoyer
                                 Par défaut: tous les namespaces
    -d, --dry-run                 Mode simulation (n'effectue aucune suppression)
    -f, --force                   Mode forcé (ne demande pas de confirmation)
    -h, --help                    Affiche cette aide

Exemples:
    $0
    $0 --namespace mon-api-backend-development
    $0 --dry-run
EOF
}

# Parsing des arguments
namespace="${LIONS_NAMESPACE:-}"
dry_run="${LIONS_DRY_RUN:-false}"
force="${LIONS_FORCE_CLEANUP:-false}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--namespace)
            namespace="$2"
            shift 2
            ;;
        -d|--dry-run)
            dry_run=true
            shift
            ;;
        -f|--force)
            force=true
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

log "INFO" "Démarrage du nettoyage des ressources Kubernetes..."

# Vérification de kubectl
if ! command -v kubectl &> /dev/null; then
    log "ERROR" "kubectl n'est pas installé ou n'est pas dans le PATH"
    exit 1
fi

# Configuration de kubectl avec le bon contexte
export KUBECONFIG="${KUBE_CONFIG}"
if [[ -n "${KUBE_CONTEXT}" ]]; then
    kubectl config use-context "${KUBE_CONTEXT}" &> /dev/null || log "WARNING" "Impossible de définir le contexte ${KUBE_CONTEXT}, utilisation du contexte par défaut"
fi

# Vérification de la connexion au cluster Kubernetes
if ! kubectl cluster-info &> /dev/null; then
    log "ERROR" "Impossible de se connecter au cluster Kubernetes"
    exit 1
fi

# Vérification de jq
if ! command -v jq &> /dev/null; then
    log "ERROR" "jq n'est pas installé ou n'est pas dans le PATH"
    exit 1
fi

# Confirmation si pas en mode forcé
if [[ "${force}" == "false" && "${dry_run}" == "false" ]]; then
    read -p "Êtes-vous sûr de vouloir nettoyer les ressources inutilisées? (oui/NON): " confirmation
    if [[ "${confirmation}" != "oui" ]]; then
        log "INFO" "Nettoyage annulé par l'utilisateur"
        exit 0
    fi
fi

# Construction de la commande de base
namespace_option=""
if [[ -n "${namespace}" ]]; then
    namespace_option="-n ${namespace}"
    log "INFO" "Nettoyage limité au namespace: ${namespace}"
else
    namespace_option="--all-namespaces"
    log "INFO" "Nettoyage de tous les namespaces"
fi

dry_run_option=""
if [[ "${dry_run}" == "true" ]]; then
    dry_run_option="--dry-run=client"
    log "INFO" "Mode simulation activé (aucune suppression ne sera effectuée)"
fi

# Nettoyage des pods terminés
log "INFO" "Nettoyage des pods terminés..."
# Définir le délai de rétention des pods terminés (en heures)
pod_retention_hours="${LIONS_POD_RETENTION_HOURS:-24}"
retention_timestamp=$(date -d "${pod_retention_hours} hours ago" +%s)

terminated_pods=$(kubectl get pods ${namespace_option} -o json | jq -r --arg timestamp "$retention_timestamp" '.items[] | select((.status.phase == "Succeeded" or .status.phase == "Failed") and ((.status.startTime | fromdateiso8601) < ($timestamp | tonumber))) | .metadata.namespace + "/" + .metadata.name')

if [[ -n "${terminated_pods}" ]]; then
    log "INFO" "Pods terminés trouvés:"
    echo "${terminated_pods}" | while read -r pod; do
        if [[ -n "${pod}" ]]; then
            ns=$(echo "${pod}" | cut -d'/' -f1)
            name=$(echo "${pod}" | cut -d'/' -f2)
            log "INFO" "  - ${pod}"

            if [[ "${dry_run}" == "false" ]]; then
                kubectl delete pod "${name}" -n "${ns}" || log "WARNING" "Échec de la suppression du pod ${pod}"
            fi
        fi
    done
else
    log "INFO" "Aucun pod terminé trouvé"
fi

# Nettoyage des déploiements sans réplicas
log "INFO" "Nettoyage des déploiements sans réplicas..."
zero_replica_deployments=$(kubectl get deployments ${namespace_option} -o json | jq -r '.items[] | select(.spec.replicas == 0) | .metadata.namespace + "/" + .metadata.name')

if [[ -n "${zero_replica_deployments}" ]]; then
    log "INFO" "Déploiements sans réplicas trouvés:"
    echo "${zero_replica_deployments}" | while read -r deployment; do
        if [[ -n "${deployment}" ]]; then
            ns=$(echo "${deployment}" | cut -d'/' -f1)
            name=$(echo "${deployment}" | cut -d'/' -f2)
            log "INFO" "  - ${deployment}"

            if [[ "${dry_run}" == "false" ]]; then
                kubectl delete deployment "${name}" -n "${ns}" ${dry_run_option} || log "WARNING" "Échec de la suppression du déploiement ${deployment}"
            fi
        fi
    done
else
    log "INFO" "Aucun déploiement sans réplicas trouvé"
fi

# Nettoyage des PVCs non utilisés
log "INFO" "Nettoyage des PVCs non utilisés..."
released_pvcs=$(kubectl get pvc ${namespace_option} -o json | jq -r '.items[] | select(.status.phase == "Released") | .metadata.namespace + "/" + .metadata.name')

if [[ -n "${released_pvcs}" ]]; then
    log "INFO" "PVCs non utilisés trouvés:"
    echo "${released_pvcs}" | while read -r pvc; do
        if [[ -n "${pvc}" ]]; then
            ns=$(echo "${pvc}" | cut -d'/' -f1)
            name=$(echo "${pvc}" | cut -d'/' -f2)
            log "INFO" "  - ${pvc}"

            if [[ "${dry_run}" == "false" ]]; then
                kubectl delete pvc "${name}" -n "${ns}" ${dry_run_option} || log "WARNING" "Échec de la suppression du PVC ${pvc}"
            fi
        fi
    done
else
    log "INFO" "Aucun PVC non utilisé trouvé"
fi

# Nettoyage des services sans endpoints
log "INFO" "Nettoyage des services sans endpoints..."
services=$(kubectl get services ${namespace_option} -o json | jq -r '.items[] | select(.spec.type != "LoadBalancer" and .spec.clusterIP != "None") | .metadata.namespace + "/" + .metadata.name')

if [[ -n "${services}" ]]; then
    echo "${services}" | while read -r service; do
        if [[ -n "${service}" ]]; then
            ns=$(echo "${service}" | cut -d'/' -f1)
            name=$(echo "${service}" | cut -d'/' -f2)

            # Vérification des endpoints
            endpoints=$(kubectl get endpoints "${name}" -n "${ns}" -o json | jq -r '.subsets[] | .addresses[]' 2>/dev/null)

            if [[ -z "${endpoints}" ]]; then
                log "INFO" "Service sans endpoints trouvé: ${service}"

                if [[ "${dry_run}" == "false" ]]; then
                    kubectl delete service "${name}" -n "${ns}" ${dry_run_option} || log "WARNING" "Échec de la suppression du service ${service}"
                fi
            fi
        fi
    done
else
    log "INFO" "Aucun service trouvé"
fi

# Nettoyage des ConfigMaps orphelins
log "INFO" "Nettoyage des ConfigMaps orphelins..."
if [[ -n "${namespace}" ]]; then
    # Récupération des ConfigMaps qui ne sont pas utilisés par des pods
    configmaps=$(kubectl get configmaps -n "${namespace}" -o json | jq -r '.items[] | select(.metadata.name | test(".*-config$")) | .metadata.name')

    if [[ -n "${configmaps}" ]]; then
        echo "${configmaps}" | while read -r cm; do
            if [[ -n "${cm}" ]]; then
                # Extraction du nom de l'application à partir du nom du ConfigMap
                app_name=$(echo "${cm}" | sed 's/-config$//')

                # Vérification si un déploiement existe pour cette application
                deployment_exists=$(kubectl get deployments -n "${namespace}" "${app_name}" 2>/dev/null)

                if [[ -z "${deployment_exists}" ]]; then
                    log "INFO" "ConfigMap orphelin trouvé: ${namespace}/${cm}"

                    if [[ "${dry_run}" == "false" ]]; then
                        kubectl delete configmap "${cm}" -n "${namespace}" ${dry_run_option} || log "WARNING" "Échec de la suppression du ConfigMap ${namespace}/${cm}"
                    fi
                fi
            fi
        done
    else
        log "INFO" "Aucun ConfigMap orphelin trouvé dans le namespace ${namespace}"
    fi
else
    log "INFO" "Vérification des ConfigMaps orphelins ignorée en mode tous namespaces"
fi

# Nettoyage des images Docker inutilisées si activé
if [[ "${LIONS_CLEANUP_DOCKER_IMAGES:-false}" == "true" && "${dry_run}" == "false" ]]; then
    log "INFO" "Nettoyage des images Docker inutilisées..."

    # Exécution de la commande de nettoyage des images Docker sur le nœud
    if [[ -n "${namespace}" ]]; then
        log "INFO" "Nettoyage des images Docker ignoré en mode namespace spécifique"
    else
        # Récupération des nœuds
        nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

        for node in ${nodes}; do
            log "INFO" "Nettoyage des images Docker sur le nœud ${node}..."

            # Exécution de la commande de nettoyage via SSH
            kubectl debug node/${node} -it --image=docker:stable -- sh -c "docker image prune -a -f" || log "WARNING" "Échec du nettoyage des images Docker sur le nœud ${node}"
        done
    fi
fi

# Rotation des logs si activée
if [[ "${LIONS_LOG_ROTATION_ENABLED:-true}" == "true" ]]; then
    log "INFO" "Rotation des logs..."

    # Suppression des logs plus anciens que X jours
    log_retention_days="${LIONS_LOG_RETENTION_DAYS:-7}"
    find "${LOG_DIR}" -name "cleanup-*.log" -type f -mtime +${log_retention_days} -delete || log "WARNING" "Échec de la rotation des logs"

    log "INFO" "Rotation des logs terminée"
fi

log "SUCCESS" "Nettoyage des ressources terminé avec succès"
log "INFO" "Journal de nettoyage: ${LOG_FILE}"

exit 0
