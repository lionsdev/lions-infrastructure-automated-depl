#!/bin/bash
# Titre: Script de nettoyage des ressources
# Description: Nettoie les ressources inutilisées dans le cluster Kubernetes
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-08
# Version: 1.0.0

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DIR="/var/log/lions/maintenance"
readonly LOG_FILE="${LOG_DIR}/cleanup-$(date +%Y%m%d-%H%M%S).log"

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
namespace=""
dry_run=false
force=false

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
terminated_pods=$(kubectl get pods ${namespace_option} -o json | jq -r '.items[] | select(.status.phase == "Succeeded" or .status.phase == "Failed") | .metadata.namespace + "/" + .metadata.name')

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

log "SUCCESS" "Nettoyage des ressources terminé avec succès"
log "INFO" "Journal de nettoyage: ${LOG_FILE}"

exit 0