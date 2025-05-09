#!/bin/bash
# Titre: Script de vérification de santé
# Description: Vérifie la santé du cluster Kubernetes et des applications
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-08
# Version: 1.0.0

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DIR="/var/log/lions/maintenance"
readonly LOG_FILE="${LOG_DIR}/health-check-$(date +%Y%m%d-%H%M%S).log"
readonly REPORT_FILE="${LOG_DIR}/health-report-$(date +%Y%m%d).html"

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
Script de Vérification de Santé - Infrastructure LIONS

Ce script vérifie la santé du cluster Kubernetes et des applications.

Usage:
    $0 [options]

Options:
    -n, --namespace <namespace>   Namespace spécifique à vérifier
                                 Par défaut: tous les namespaces
    -r, --report                  Génère un rapport HTML
    -h, --help                    Affiche cette aide

Exemples:
    $0
    $0 --namespace mon-api-backend-development
    $0 --report
EOF
}

# Parsing des arguments
namespace=""
generate_report=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--namespace)
            namespace="$2"
            shift 2
            ;;
        -r|--report)
            generate_report=true
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

log "INFO" "Démarrage de la vérification de santé..."

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

# Construction de la commande de base
namespace_option=""
if [[ -n "${namespace}" ]]; then
    namespace_option="-n ${namespace}"
    log "INFO" "Vérification limitée au namespace: ${namespace}"
else
    namespace_option="--all-namespaces"
    log "INFO" "Vérification de tous les namespaces"
fi

# Fonction pour vérifier l'état des nœuds
function verifier_noeuds() {
    log "INFO" "Vérification de l'état des nœuds..."
    
    # Récupération de l'état des nœuds
    nodes_status=$(kubectl get nodes -o wide)
    log "INFO" "État des nœuds:"
    echo "${nodes_status}" | while read -r line; do
        log "INFO" "  ${line}"
    done
    
    # Vérification des nœuds non prêts
    not_ready_nodes=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.conditions[] | select(.type == "Ready" and .status != "True")) | .metadata.name')
    
    if [[ -n "${not_ready_nodes}" ]]; then
        log "WARNING" "Nœuds non prêts trouvés:"
        echo "${not_ready_nodes}" | while read -r node; do
            log "WARNING" "  - ${node}"
        done
    else
        log "SUCCESS" "Tous les nœuds sont prêts"
    fi
    
    # Vérification de la pression sur les nœuds
    pressure_nodes=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.conditions[] | select(.type == "MemoryPressure" or .type == "DiskPressure" or .type == "PIDPressure" or .type == "NetworkUnavailable") | select(.status == "True")) | .metadata.name + " (" + (.status.conditions[] | select(.status == "True") | .type) + ")"')
    
    if [[ -n "${pressure_nodes}" ]]; then
        log "WARNING" "Nœuds sous pression trouvés:"
        echo "${pressure_nodes}" | while read -r node; do
            log "WARNING" "  - ${node}"
        done
    else
        log "SUCCESS" "Aucun nœud sous pression"
    fi
}

# Fonction pour vérifier l'état des pods système
function verifier_pods_systeme() {
    log "INFO" "Vérification de l'état des pods système..."
    
    # Récupération de l'état des pods système
    system_pods_status=$(kubectl get pods -n kube-system)
    log "INFO" "État des pods système:"
    echo "${system_pods_status}" | while read -r line; do
        log "INFO" "  ${line}"
    done
    
    # Vérification des pods système non prêts
    not_ready_system_pods=$(kubectl get pods -n kube-system -o json | jq -r '.items[] | select(.status.phase != "Running" and .status.phase != "Succeeded") | .metadata.name + " (" + .status.phase + ")"')
    
    if [[ -n "${not_ready_system_pods}" ]]; then
        log "WARNING" "Pods système non prêts trouvés:"
        echo "${not_ready_system_pods}" | while read -r pod; do
            log "WARNING" "  - ${pod}"
        done
    else
        log "SUCCESS" "Tous les pods système sont prêts"
    fi
}

# Fonction pour vérifier l'état des pods
function verifier_pods() {
    log "INFO" "Vérification de l'état des pods..."
    
    # Récupération de l'état des pods
    if [[ -n "${namespace}" ]]; then
        pods_status=$(kubectl get pods -n "${namespace}")
    else
        pods_status=$(kubectl get pods --all-namespaces)
    fi
    
    log "INFO" "État des pods:"
    echo "${pods_status}" | while read -r line; do
        log "INFO" "  ${line}"
    done
    
    # Vérification des pods non prêts
    if [[ -n "${namespace}" ]]; then
        not_ready_pods=$(kubectl get pods -n "${namespace}" -o json | jq -r '.items[] | select(.status.phase != "Running" and .status.phase != "Succeeded") | .metadata.name + " (" + .status.phase + ")"')
    else
        not_ready_pods=$(kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.status.phase != "Running" and .status.phase != "Succeeded") | .metadata.namespace + "/" + .metadata.name + " (" + .status.phase + ")"')
    fi
    
    if [[ -n "${not_ready_pods}" ]]; then
        log "WARNING" "Pods non prêts trouvés:"
        echo "${not_ready_pods}" | while read -r pod; do
            log "WARNING" "  - ${pod}"
        done
    else
        log "SUCCESS" "Tous les pods sont prêts"
    fi
    
    # Vérification des pods en état CrashLoopBackOff
    if [[ -n "${namespace}" ]]; then
        crashloop_pods=$(kubectl get pods -n "${namespace}" -o json | jq -r '.items[] | select(.status.containerStatuses != null) | select(.status.containerStatuses[] | select(.state.waiting != null) | select(.state.waiting.reason == "CrashLoopBackOff")) | .metadata.name')
    else
        crashloop_pods=$(kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.status.containerStatuses != null) | select(.status.containerStatuses[] | select(.state.waiting != null) | select(.state.waiting.reason == "CrashLoopBackOff")) | .metadata.namespace + "/" + .metadata.name')
    fi
    
    if [[ -n "${crashloop_pods}" ]]; then
        log "ERROR" "Pods en état CrashLoopBackOff trouvés:"
        echo "${crashloop_pods}" | while read -r pod; do
            log "ERROR" "  - ${pod}"
        done
    else
        log "SUCCESS" "Aucun pod en état CrashLoopBackOff"
    fi
}

# Fonction pour vérifier l'utilisation des ressources
function verifier_ressources() {
    log "INFO" "Vérification de l'utilisation des ressources..."
    
    # Vérification de l'utilisation des ressources des nœuds
    nodes_resources=$(kubectl top nodes 2>/dev/null || echo "Impossible de récupérer l'utilisation des ressources des nœuds")
    log "INFO" "Utilisation des ressources des nœuds:"
    echo "${nodes_resources}" | while read -r line; do
        log "INFO" "  ${line}"
    done
    
    # Vérification de l'utilisation des ressources des pods
    if [[ -n "${namespace}" ]]; then
        pods_resources=$(kubectl top pods -n "${namespace}" 2>/dev/null || echo "Impossible de récupérer l'utilisation des ressources des pods")
    else
        pods_resources=$(kubectl top pods --all-namespaces 2>/dev/null || echo "Impossible de récupérer l'utilisation des ressources des pods")
    fi
    
    log "INFO" "Utilisation des ressources des pods:"
    echo "${pods_resources}" | while read -r line; do
        log "INFO" "  ${line}"
    done
}

# Fonction pour vérifier les services
function verifier_services() {
    log "INFO" "Vérification des services..."
    
    # Récupération de l'état des services
    if [[ -n "${namespace}" ]]; then
        services_status=$(kubectl get services -n "${namespace}")
    else
        services_status=$(kubectl get services --all-namespaces)
    fi
    
    log "INFO" "État des services:"
    echo "${services_status}" | while read -r line; do
        log "INFO" "  ${line}"
    done
}

# Fonction pour vérifier les déploiements
function verifier_deployments() {
    log "INFO" "Vérification des déploiements..."
    
    # Récupération de l'état des déploiements
    if [[ -n "${namespace}" ]]; then
        deployments_status=$(kubectl get deployments -n "${namespace}")
    else
        deployments_status=$(kubectl get deployments --all-namespaces)
    fi
    
    log "INFO" "État des déploiements:"
    echo "${deployments_status}" | while read -r line; do
        log "INFO" "  ${line}"
    done
    
    # Vérification des déploiements non disponibles
    if [[ -n "${namespace}" ]]; then
        unavailable_deployments=$(kubectl get deployments -n "${namespace}" -o json | jq -r '.items[] | select(.status.availableReplicas < .status.replicas or .status.availableReplicas == null) | .metadata.name + " (" + (.status.availableReplicas | tostring) + "/" + (.status.replicas | tostring) + ")"')
    else
        unavailable_deployments=$(kubectl get deployments --all-namespaces -o json | jq -r '.items[] | select(.status.availableReplicas < .status.replicas or .status.availableReplicas == null) | .metadata.namespace + "/" + .metadata.name + " (" + (.status.availableReplicas | tostring) + "/" + (.status.replicas | tostring) + ")"')
    fi
    
    if [[ -n "${unavailable_deployments}" ]]; then
        log "WARNING" "Déploiements non disponibles trouvés:"
        echo "${unavailable_deployments}" | while read -r deployment; do
            log "WARNING" "  - ${deployment}"
        done
    else
        log "SUCCESS" "Tous les déploiements sont disponibles"
    fi
}

# Fonction pour générer un rapport HTML
function generer_rapport() {
    log "INFO" "Génération du rapport HTML..."
    
    # Création du rapport HTML
    cat > "${REPORT_FILE}" << EOF
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Rapport de Santé - Infrastructure LIONS</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            color: #333;
        }
        h1, h2, h3 {
            color: #2c3e50;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        .header {
            background-color: #3498db;
            color: white;
            padding: 20px;
            text-align: center;
            margin-bottom: 20px;
            border-radius: 5px;
        }
        .section {
            background-color: #f9f9f9;
            padding: 15px;
            margin-bottom: 20px;
            border-radius: 5px;
            border-left: 5px solid #3498db;
        }
        .success {
            color: #27ae60;
            font-weight: bold;
        }
        .warning {
            color: #f39c12;
            font-weight: bold;
        }
        .error {
            color: #e74c3c;
            font-weight: bold;
        }
        pre {
            background-color: #f1f1f1;
            padding: 10px;
            border-radius: 5px;
            overflow-x: auto;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
        }
        th, td {
            padding: 12px 15px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background-color: #3498db;
            color: white;
        }
        tr:nth-child(even) {
            background-color: #f2f2f2;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Rapport de Santé - Infrastructure LIONS</h1>
            <p>Généré le $(date +"%Y-%m-%d à %H:%M:%S")</p>
        </div>
        
        <div class="section">
            <h2>État des Nœuds</h2>
            <pre>$(kubectl get nodes -o wide)</pre>
            
            <h3>Nœuds Non Prêts</h3>
            <ul>
EOF
    
    # Ajout des nœuds non prêts
    not_ready_nodes=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.conditions[] | select(.type == "Ready" and .status != "True")) | .metadata.name')
    if [[ -n "${not_ready_nodes}" ]]; then
        echo "${not_ready_nodes}" | while read -r node; do
            echo "                <li class=\"error\">${node}</li>" >> "${REPORT_FILE}"
        done
    else
        echo "                <li class=\"success\">Tous les nœuds sont prêts</li>" >> "${REPORT_FILE}"
    fi
    
    cat >> "${REPORT_FILE}" << EOF
            </ul>
            
            <h3>Nœuds Sous Pression</h3>
            <ul>
EOF
    
    # Ajout des nœuds sous pression
    pressure_nodes=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.conditions[] | select(.type == "MemoryPressure" or .type == "DiskPressure" or .type == "PIDPressure" or .type == "NetworkUnavailable") | select(.status == "True")) | .metadata.name + " (" + (.status.conditions[] | select(.status == "True") | .type) + ")"')
    if [[ -n "${pressure_nodes}" ]]; then
        echo "${pressure_nodes}" | while read -r node; do
            echo "                <li class=\"warning\">${node}</li>" >> "${REPORT_FILE}"
        done
    else
        echo "                <li class=\"success\">Aucun nœud sous pression</li>" >> "${REPORT_FILE}"
    fi
    
    cat >> "${REPORT_FILE}" << EOF
            </ul>
        </div>
        
        <div class="section">
            <h2>État des Pods Système</h2>
            <pre>$(kubectl get pods -n kube-system)</pre>
            
            <h3>Pods Système Non Prêts</h3>
            <ul>
EOF
    
    # Ajout des pods système non prêts
    not_ready_system_pods=$(kubectl get pods -n kube-system -o json | jq -r '.items[] | select(.status.phase != "Running" and .status.phase != "Succeeded") | .metadata.name + " (" + .status.phase + ")"')
    if [[ -n "${not_ready_system_pods}" ]]; then
        echo "${not_ready_system_pods}" | while read -r pod; do
            echo "                <li class=\"warning\">${pod}</li>" >> "${REPORT_FILE}"
        done
    else
        echo "                <li class=\"success\">Tous les pods système sont prêts</li>" >> "${REPORT_FILE}"
    fi
    
    cat >> "${REPORT_FILE}" << EOF
            </ul>
        </div>
        
        <div class="section">
            <h2>État des Pods</h2>
            <pre>$(kubectl get pods ${namespace_option})</pre>
            
            <h3>Pods Non Prêts</h3>
            <ul>
EOF
    
    # Ajout des pods non prêts
    if [[ -n "${namespace}" ]]; then
        not_ready_pods=$(kubectl get pods -n "${namespace}" -o json | jq -r '.items[] | select(.status.phase != "Running" and .status.phase != "Succeeded") | .metadata.name + " (" + .status.phase + ")"')
    else
        not_ready_pods=$(kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.status.phase != "Running" and .status.phase != "Succeeded") | .metadata.namespace + "/" + .metadata.name + " (" + .status.phase + ")"')
    fi
    
    if [[ -n "${not_ready_pods}" ]]; then
        echo "${not_ready_pods}" | while read -r pod; do
            echo "                <li class=\"warning\">${pod}</li>" >> "${REPORT_FILE}"
        done
    else
        echo "                <li class=\"success\">Tous les pods sont prêts</li>" >> "${REPORT_FILE}"
    fi
    
    cat >> "${REPORT_FILE}" << EOF
            </ul>
            
            <h3>Pods en état CrashLoopBackOff</h3>
            <ul>
EOF
    
    # Ajout des pods en état CrashLoopBackOff
    if [[ -n "${namespace}" ]]; then
        crashloop_pods=$(kubectl get pods -n "${namespace}" -o json | jq -r '.items[] | select(.status.containerStatuses != null) | select(.status.containerStatuses[] | select(.state.waiting != null) | select(.state.waiting.reason == "CrashLoopBackOff")) | .metadata.name')
    else
        crashloop_pods=$(kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.status.containerStatuses != null) | select(.status.containerStatuses[] | select(.state.waiting != null) | select(.state.waiting.reason == "CrashLoopBackOff")) | .metadata.namespace + "/" + .metadata.name')
    fi
    
    if [[ -n "${crashloop_pods}" ]]; then
        echo "${crashloop_pods}" | while read -r pod; do
            echo "                <li class=\"error\">${pod}</li>" >> "${REPORT_FILE}"
        done
    else
        echo "                <li class=\"success\">Aucun pod en état CrashLoopBackOff</li>" >> "${REPORT_FILE}"
    fi
    
    cat >> "${REPORT_FILE}" << EOF
            </ul>
        </div>
        
        <div class="section">
            <h2>Utilisation des Ressources</h2>
            <h3>Ressources des Nœuds</h3>
            <pre>$(kubectl top nodes 2>/dev/null || echo "Impossible de récupérer l'utilisation des ressources des nœuds")</pre>
            
            <h3>Ressources des Pods</h3>
            <pre>$(kubectl top pods ${namespace_option} 2>/dev/null || echo "Impossible de récupérer l'utilisation des ressources des pods")</pre>
        </div>
        
        <div class="section">
            <h2>État des Déploiements</h2>
            <pre>$(kubectl get deployments ${namespace_option})</pre>
            
            <h3>Déploiements Non Disponibles</h3>
            <ul>
EOF
    
    # Ajout des déploiements non disponibles
    if [[ -n "${namespace}" ]]; then
        unavailable_deployments=$(kubectl get deployments -n "${namespace}" -o json | jq -r '.items[] | select(.status.availableReplicas < .status.replicas or .status.availableReplicas == null) | .metadata.name + " (" + (.status.availableReplicas | tostring) + "/" + (.status.replicas | tostring) + ")"')
    else
        unavailable_deployments=$(kubectl get deployments --all-namespaces -o json | jq -r '.items[] | select(.status.availableReplicas < .status.replicas or .status.availableReplicas == null) | .metadata.namespace + "/" + .metadata.name + " (" + (.status.availableReplicas | tostring) + "/" + (.status.replicas | tostring) + ")"')
    fi
    
    if [[ -n "${unavailable_deployments}" ]]; then
        echo "${unavailable_deployments}" | while read -r deployment; do
            echo "                <li class=\"warning\">${deployment}</li>" >> "${REPORT_FILE}"
        done
    else
        echo "                <li class=\"success\">Tous les déploiements sont disponibles</li>" >> "${REPORT_FILE}"
    fi
    
    cat >> "${REPORT_FILE}" << EOF
            </ul>
        </div>
        
        <div class="section">
            <h2>Résumé</h2>
            <p>Rapport généré le $(date +"%Y-%m-%d à %H:%M:%S")</p>
            <p>Journal de vérification: ${LOG_FILE}</p>
        </div>
    </div>
</body>
</html>
EOF
    
    log "SUCCESS" "Rapport HTML généré: ${REPORT_FILE}"
}

# Exécution des vérifications
verifier_noeuds
verifier_pods_systeme
verifier_pods
verifier_ressources
verifier_services
verifier_deployments

# Génération du rapport HTML si demandé
if [[ "${generate_report}" == "true" ]]; then
    generer_rapport
fi

log "SUCCESS" "Vérification de santé terminée avec succès"
log "INFO" "Journal de vérification: ${LOG_FILE}"

exit 0