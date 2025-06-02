#!/bin/bash
# =============================================================================
# LIONS Infrastructure - Script d'optimisation des ressources v5.0
# =============================================================================
# Description: Analyse l'utilisation des ressources et suggère des optimisations
# Version: 5.0.0
# Date: 02/06/2023
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

# Couleurs
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Configuration depuis variables d'environnement
readonly LIONS_ENVIRONMENT="${LIONS_ENVIRONMENT:-development}"
readonly LOG_DIR="${LIONS_MAINTENANCE_LOG_DIR:-${PROJECT_ROOT}/scripts/logs/maintenance}"
readonly REPORT_DIR="${LOG_DIR}/resource-reports"
readonly KUBE_CONFIG="${LIONS_KUBE_CONFIG_PATH:-${HOME}/.kube/config}"
readonly KUBE_CONTEXT="${LIONS_KUBE_CONTEXT:-${LIONS_CLUSTER_NAME:-lions-k3s-cluster}}"

# Paramètres par défaut ou depuis les arguments
ENVIRONMENT="${1:-${LIONS_ENVIRONMENT}}"
NAMESPACE="${2:-${LIONS_NAMESPACE:-all}}"
DURATION="${3:-${LIONS_RESOURCE_ANALYSIS_DURATION:-1h}}"
APPLY="${4:-${LIONS_APPLY_RECOMMENDATIONS:-false}}"

# Création des répertoires de logs
mkdir -p "${LOG_DIR}"
mkdir -p "${REPORT_DIR}"

# Affichage du logo
echo -e "${BLUE}"
echo -e "╔═══════════════════════════════════════════════════════════════════╗"
echo -e "║                                                                   ║"
echo -e "║      ██╗     ██╗ ██████╗ ███╗   ██╗███████╗    ██╗███╗   ██╗      ║"
echo -e "║      ██║     ██║██╔═══██╗████╗  ██║██╔════╝    ██║████╗  ██║      ║"
echo -e "║      ██║     ██║██║   ██║██╔██╗ ██║███████╗    ██║██╔██╗ ██║      ║"
echo -e "║      ██║     ██║██║   ██║██║╚██╗██║╚════██║    ██║██║╚██╗██║      ║"
echo -e "║      ███████╗██║╚██████╔╝██║ ╚████║███████║    ██║██║ ╚████║      ║"
echo -e "║      ╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝    ╚═╝╚═╝  ╚═══╝      ║"
echo -e "║                                                                   ║"
echo -e "║     ██████╗ ██████╗ ████████╗██╗███╗   ███╗██╗███████╗███████╗   ║"
echo -e "║    ██╔═══██╗██╔══██╗╚══██╔══╝██║████╗ ████║██║╚══███╔╝██╔════╝   ║"
echo -e "║    ██║   ██║██████╔╝   ██║   ██║██╔████╔██║██║  ███╔╝ █████╗     ║"
echo -e "║    ██║   ██║██╔═══╝    ██║   ██║██║╚██╔╝██║██║ ███╔╝  ██╔══╝     ║"
echo -e "║    ╚██████╔╝██║        ██║   ██║██║ ╚═╝ ██║██║███████╗███████╗   ║"
echo -e "║     ╚═════╝ ╚═╝        ╚═╝   ╚═╝╚═╝     ╚═╝╚═╝╚══════╝╚══════╝   ║"
echo -e "║                                                                   ║"
echo -e "╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo -e "${YELLOW}     Optimisation des Ressources LIONS - v5.0.0${NC}"
echo -e "${BLUE}  ════════════════════════════════════════════════════════${NC}\n"

# Vérification des prérequis
echo -e "${GREEN}[INFO]${NC} Vérification des prérequis..."

# Vérification de kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} kubectl n'est pas installé ou n'est pas dans le PATH"
    exit 1
fi

# Configuration de kubectl avec le bon contexte
export KUBECONFIG="${KUBE_CONFIG}"
if [[ -n "${KUBE_CONTEXT}" ]]; then
    kubectl config use-context "${KUBE_CONTEXT}" &> /dev/null || echo -e "${YELLOW}[WARNING]${NC} Impossible de définir le contexte ${KUBE_CONTEXT}, utilisation du contexte par défaut"
fi

# Vérification de l'accès au cluster Kubernetes
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Impossible d'accéder au cluster Kubernetes"
    echo -e "${YELLOW}[TIP]${NC} Vérifiez votre configuration kubectl et le fichier kubeconfig"
    exit 1
fi

# Vérification de jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} jq n'est pas installé ou n'est pas dans le PATH"
    echo -e "${YELLOW}[TIP]${NC} Installez jq avec 'apt-get install jq' ou 'yum install jq'"
    exit 1
fi

# Vérification de bc
if ! command -v bc &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} bc n'est pas installé ou n'est pas dans le PATH"
    echo -e "${YELLOW}[TIP]${NC} Installez bc avec 'apt-get install bc' ou 'yum install bc'"
    exit 1
fi

# Fonction pour convertir les unités de ressources en valeurs numériques
convert_resource_to_number() {
    local value=$1

    if [[ -z "$value" ]]; then
        echo "0"
        return
    fi

    # Extraction du nombre et de l'unité
    local number=$(echo "$value" | sed -E 's/([0-9.]+).*/\1/')
    local unit=$(echo "$value" | sed -E 's/[0-9.]+//' | tr -d '[:space:]')

    # Conversion en fonction de l'unité
    case "$unit" in
        m)
            # Millicores
            echo "$number"
            ;;
        "")
            # Cores
            echo "$(echo "$number * 1000" | bc)"
            ;;
        Mi)
            # Mebibytes
            echo "$number"
            ;;
        Gi)
            # Gibibytes
            echo "$(echo "$number * 1024" | bc)"
            ;;
        Ki)
            # Kibibytes
            echo "$(echo "$number / 1024" | bc)"
            ;;
        *)
            echo "0"
            ;;
    esac
}

# Fonction pour convertir les valeurs numériques en unités de ressources
convert_number_to_resource() {
    local value=$1
    local type=$2

    if [[ "$type" == "cpu" ]]; then
        if (( $(echo "$value >= 1000" | bc -l) )); then
            # Convertir en cores si >= 1000m
            echo "$(echo "scale=1; $value / 1000" | bc)$(if (( $(echo "$value % 1000" | bc -l) == 0 )); then echo ""; else echo ""; fi)"
        else
            # Garder en millicores
            echo "${value}m"
        fi
    elif [[ "$type" == "memory" ]]; then
        if (( $(echo "$value >= 1024" | bc -l) )); then
            # Convertir en Gi si >= 1024Mi
            echo "$(echo "scale=1; $value / 1024" | bc)Gi"
        else
            # Garder en Mi
            echo "${value}Mi"
        fi
    else
        echo "$value"
    fi
}

# Fonction pour calculer les recommandations de ressources
calculate_recommendations() {
    local current_usage=$1
    local current_request=$2
    local current_limit=$3
    local resource_type=$4

    # Convertir en valeurs numériques
    local usage_num=$(convert_resource_to_number "$current_usage")
    local request_num=$(convert_resource_to_number "$current_request")
    local limit_num=$(convert_resource_to_number "$current_limit")

    # Calculer les recommandations
    local recommended_request
    local recommended_limit

    if [[ "$resource_type" == "cpu" ]]; then
        # Facteurs de multiplication configurables via variables d'environnement
        local cpu_request_factor="${LIONS_CPU_REQUEST_FACTOR:-1.5}"
        local cpu_limit_factor="${LIONS_CPU_LIMIT_FACTOR:-2.5}"
        local cpu_min_request="${LIONS_CPU_MIN_REQUEST:-50}"
        local cpu_min_limit="${LIONS_CPU_MIN_LIMIT:-100}"

        # Pour le CPU, on recommande request = usage * factor, limit = usage * factor
        recommended_request=$(echo "scale=0; $usage_num * $cpu_request_factor / 1" | bc)
        recommended_limit=$(echo "scale=0; $usage_num * $cpu_limit_factor / 1" | bc)

        # Minimum configurable pour request et limit
        if (( $(echo "$recommended_request < $cpu_min_request" | bc -l) )); then
            recommended_request=$cpu_min_request
        fi
        if (( $(echo "$recommended_limit < $cpu_min_limit" | bc -l) )); then
            recommended_limit=$cpu_min_limit
        fi
    elif [[ "$resource_type" == "memory" ]]; then
        # Facteurs de multiplication configurables via variables d'environnement
        local memory_request_factor="${LIONS_MEMORY_REQUEST_FACTOR:-1.2}"
        local memory_limit_factor="${LIONS_MEMORY_LIMIT_FACTOR:-2.0}"
        local memory_min_request="${LIONS_MEMORY_MIN_REQUEST:-64}"
        local memory_min_limit="${LIONS_MEMORY_MIN_LIMIT:-128}"

        # Pour la mémoire, on recommande request = usage * factor, limit = usage * factor
        recommended_request=$(echo "scale=0; $usage_num * $memory_request_factor / 1" | bc)
        recommended_limit=$(echo "scale=0; $usage_num * $memory_limit_factor / 1" | bc)

        # Minimum configurable pour request et limit
        if (( $(echo "$recommended_request < $memory_min_request" | bc -l) )); then
            recommended_request=$memory_min_request
        fi
        if (( $(echo "$recommended_limit < $memory_min_limit" | bc -l) )); then
            recommended_limit=$memory_min_limit
        fi
    fi

    # Convertir en unités de ressources
    local recommended_request_str=$(convert_number_to_resource "$recommended_request" "$resource_type")
    local recommended_limit_str=$(convert_number_to_resource "$recommended_limit" "$resource_type")

    echo "$recommended_request_str $recommended_limit_str"
}

# Fonction pour analyser les ressources d'un namespace
analyze_namespace_resources() {
    local namespace=$1
    local report_file="${REPORT_DIR}/${namespace}-resources-$(date +%Y%m%d-%H%M%S).txt"

    echo -e "${GREEN}[INFO]${NC} Analyse des ressources dans le namespace ${namespace}..."
    echo "=== Rapport d'Utilisation des Ressources pour ${namespace} ===" > "$report_file"
    echo "Date: $(date)" >> "$report_file"
    echo "Environnement: ${ENVIRONMENT}" >> "$report_file"
    echo "Durée d'analyse: ${DURATION}" >> "$report_file"
    echo "" >> "$report_file"
    echo "=== Déploiements ===" >> "$report_file"

    # Récupération des déploiements
    local deployments=$(kubectl get deployments -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$deployments" ]]; then
        echo -e "${YELLOW}[WARNING]${NC} Aucun déploiement trouvé dans le namespace ${namespace}"
        echo "Aucun déploiement trouvé." >> "$report_file"
    else
        for deployment in $deployments; do
            echo -e "${GREEN}[INFO]${NC} Analyse du déploiement ${deployment}..."
            echo "Déploiement: ${deployment}" >> "$report_file"

            # Récupération des pods du déploiement
            local pods=$(kubectl get pods -n "$namespace" -l "app=${deployment}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

            if [[ -z "$pods" ]]; then
                echo -e "${YELLOW}[WARNING]${NC} Aucun pod trouvé pour le déploiement ${deployment}"
                echo "  Aucun pod trouvé." >> "$report_file"
                continue
            fi

            # Analyse de chaque pod
            for pod in $pods; do
                echo "  Pod: ${pod}" >> "$report_file"

                # Récupération des conteneurs du pod
                local containers=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null || echo "")

                for container in $containers; do
                    echo "    Conteneur: ${container}" >> "$report_file"

                    # Récupération des ressources actuelles
                    local cpu_request=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath="{.spec.containers[?(@.name==\"$container\")].resources.requests.cpu}" 2>/dev/null || echo "")
                    local cpu_limit=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath="{.spec.containers[?(@.name==\"$container\")].resources.limits.cpu}" 2>/dev/null || echo "")
                    local memory_request=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath="{.spec.containers[?(@.name==\"$container\")].resources.requests.memory}" 2>/dev/null || echo "")
                    local memory_limit=$(kubectl get pod "$pod" -n "$namespace" -o jsonpath="{.spec.containers[?(@.name==\"$container\")].resources.limits.memory}" 2>/dev/null || echo "")

                    echo "      Ressources actuelles:" >> "$report_file"
                    echo "        CPU Request: ${cpu_request:-Non défini}" >> "$report_file"
                    echo "        CPU Limit: ${cpu_limit:-Non défini}" >> "$report_file"
                    echo "        Memory Request: ${memory_request:-Non défini}" >> "$report_file"
                    echo "        Memory Limit: ${memory_limit:-Non défini}" >> "$report_file"

                    # Récupération de l'utilisation des ressources
                    local cpu_usage=$(kubectl top pod "$pod" -n "$namespace" --containers | grep "$container" | awk '{print $2}')
                    local memory_usage=$(kubectl top pod "$pod" -n "$namespace" --containers | grep "$container" | awk '{print $3}')

                    echo "      Utilisation actuelle:" >> "$report_file"
                    echo "        CPU: ${cpu_usage:-Non disponible}" >> "$report_file"
                    echo "        Memory: ${memory_usage:-Non disponible}" >> "$report_file"

                    # Calcul des recommandations
                    if [[ -n "$cpu_usage" && -n "$memory_usage" ]]; then
                        local cpu_recommendations=$(calculate_recommendations "$cpu_usage" "$cpu_request" "$cpu_limit" "cpu")
                        local memory_recommendations=$(calculate_recommendations "$memory_usage" "$memory_request" "$memory_limit" "memory")

                        local recommended_cpu_request=$(echo "$cpu_recommendations" | awk '{print $1}')
                        local recommended_cpu_limit=$(echo "$cpu_recommendations" | awk '{print $2}')
                        local recommended_memory_request=$(echo "$memory_recommendations" | awk '{print $1}')
                        local recommended_memory_limit=$(echo "$memory_recommendations" | awk '{print $2}')

                        echo "      Recommandations:" >> "$report_file"
                        echo "        CPU Request: ${recommended_cpu_request}" >> "$report_file"
                        echo "        CPU Limit: ${recommended_cpu_limit}" >> "$report_file"
                        echo "        Memory Request: ${recommended_memory_request}" >> "$report_file"
                        echo "        Memory Limit: ${recommended_memory_limit}" >> "$report_file"

                        # Appliquer les recommandations si demandé
                        if [[ "$APPLY" == "true" ]]; then
                            echo -e "${GREEN}[INFO]${NC} Application des recommandations pour ${deployment}/${container}..."

                            # Création du patch pour les ressources
                            local patch=$(cat <<EOF
{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "${container}",
            "resources": {
              "requests": {
                "cpu": "${recommended_cpu_request}",
                "memory": "${recommended_memory_request}"
              },
              "limits": {
                "cpu": "${recommended_cpu_limit}",
                "memory": "${recommended_memory_limit}"
              }
            }
          }
        ]
      }
    }
  }
}
EOF
)

                            # Application du patch
                            echo "$patch" > /tmp/resource-patch.json
                            kubectl patch deployment "$deployment" -n "$namespace" --patch "$(cat /tmp/resource-patch.json)"
                            rm /tmp/resource-patch.json

                            echo "      Recommandations appliquées." >> "$report_file"
                        fi
                    else
                        echo "      Recommandations: Non disponibles (données d'utilisation manquantes)" >> "$report_file"
                    fi

                    echo "" >> "$report_file"
                done
            done

            echo "" >> "$report_file"
        done
    fi

    echo -e "${GREEN}[INFO]${NC} Rapport généré: ${report_file}"
}

# Fonction pour analyser les ressources de tous les namespaces
analyze_all_namespaces() {
    echo -e "${GREEN}[INFO]${NC} Analyse des ressources dans tous les namespaces..."

    # Récupération des namespaces
    local namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')

    for ns in $namespaces; do
        analyze_namespace_resources "$ns"
    done
}

# Fonction principale
main() {
    echo -e "${GREEN}[INFO]${NC} Démarrage de l'analyse des ressources pour l'environnement ${ENVIRONMENT}..."

    # Création d'un rapport global
    local global_report="${REPORT_DIR}/global-resources-$(date +%Y%m%d-%H%M%S).txt"
    echo "=== Rapport Global d'Utilisation des Ressources ===" > "$global_report"
    echo "Date: $(date)" >> "$global_report"
    echo "Environnement: ${ENVIRONMENT}" >> "$global_report"
    echo "" >> "$global_report"

    # Analyse des ressources du cluster
    echo -e "${GREEN}[INFO]${NC} Analyse des ressources du cluster..."
    echo "=== Ressources du Cluster ===" >> "$global_report"

    # Récupération des ressources des nœuds
    local nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

    echo "Nœuds:" >> "$global_report"
    for node in $nodes; do
        echo "  ${node}:" >> "$global_report"

        # Capacité du nœud
        local cpu_capacity=$(kubectl get node "$node" -o jsonpath='{.status.capacity.cpu}')
        local memory_capacity=$(kubectl get node "$node" -o jsonpath='{.status.capacity.memory}')

        echo "    Capacité:" >> "$global_report"
        echo "      CPU: ${cpu_capacity}" >> "$global_report"
        echo "      Memory: ${memory_capacity}" >> "$global_report"

        # Utilisation du nœud
        local node_usage=$(kubectl top node "$node" | tail -n 1)
        local cpu_usage=$(echo "$node_usage" | awk '{print $3}')
        local memory_usage=$(echo "$node_usage" | awk '{print $5}')

        echo "    Utilisation:" >> "$global_report"
        echo "      CPU: ${cpu_usage}" >> "$global_report"
        echo "      Memory: ${memory_usage}" >> "$global_report"

        echo "" >> "$global_report"
    done

    # Analyse des namespaces
    if [[ "$NAMESPACE" == "all" ]]; then
        analyze_all_namespaces
    else
        analyze_namespace_resources "$NAMESPACE"
    fi

    # Résumé des recommandations
    echo -e "${GREEN}[INFO]${NC} Génération du résumé des recommandations..."
    echo "=== Résumé des Recommandations ===" >> "$global_report"

    # Parcours des rapports générés
    for report in "${REPORT_DIR}"/*-resources-*.txt; do
        if [[ -f "$report" && "$report" != "$global_report" ]]; then
            local ns=$(basename "$report" | cut -d'-' -f1)
            echo "Namespace: ${ns}" >> "$global_report"

            # Extraction des recommandations
            grep -A 4 "Recommandations:" "$report" | grep -v "Recommandations:" >> "$global_report"

            echo "" >> "$global_report"
        fi
    done

    echo -e "${GREEN}[SUCCESS]${NC} Analyse des ressources terminée avec succès!"
    echo -e "${GREEN}[INFO]${NC} Rapport global généré: ${global_report}"

    # Rotation des rapports si activée
    if [[ "${LIONS_LOG_ROTATION_ENABLED:-true}" == "true" ]]; then
        echo -e "${GREEN}[INFO]${NC} Rotation des rapports..."

        # Suppression des rapports plus anciens que X jours
        log_retention_days="${LIONS_LOG_RETENTION_DAYS:-7}"
        find "${REPORT_DIR}" -name "*-resources-*.txt" -type f -mtime +${log_retention_days} -delete || echo -e "${YELLOW}[WARNING]${NC} Échec de la rotation des rapports"

        echo -e "${GREEN}[INFO]${NC} Rotation des rapports terminée"
    fi

    if [[ "$APPLY" == "true" ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} Les recommandations ont été appliquées aux déploiements."
    else
        echo -e "${YELLOW}[INFO]${NC} Les recommandations n'ont pas été appliquées. Utilisez --apply pour appliquer les recommandations."
    fi

    # Ouverture automatique du rapport si configuré
    if [[ "${LIONS_AUTO_OPEN_REPORT:-false}" == "true" ]]; then
        if command -v xdg-open &> /dev/null; then
            xdg-open "${global_report}" &> /dev/null || echo -e "${YELLOW}[WARNING]${NC} Impossible d'ouvrir automatiquement le rapport"
        elif command -v open &> /dev/null; then
            open "${global_report}" &> /dev/null || echo -e "${YELLOW}[WARNING]${NC} Impossible d'ouvrir automatiquement le rapport"
        elif command -v start &> /dev/null; then
            start "${global_report}" &> /dev/null || echo -e "${YELLOW}[WARNING]${NC} Impossible d'ouvrir automatiquement le rapport"
        else
            echo -e "${YELLOW}[WARNING]${NC} Impossible d'ouvrir automatiquement le rapport (aucune commande d'ouverture trouvée)"
        fi
    fi
}

# Affichage de l'aide
show_help() {
    echo "Usage: $0 [environment] [namespace] [duration] [apply]"
    echo ""
    echo "Arguments:"
    echo "  environment  Environnement à analyser (development, staging, production). Par défaut: development"
    echo "  namespace    Namespace à analyser. Utilisez 'all' pour tous les namespaces. Par défaut: all"
    echo "  duration     Durée d'analyse (1h, 24h, 7d). Par défaut: 1h"
    echo "  apply        Appliquer les recommandations (true, false). Par défaut: false"
    echo ""
    echo "Exemples:"
    echo "  $0                                  # Analyse tous les namespaces dans l'environnement development"
    echo "  $0 production                       # Analyse tous les namespaces dans l'environnement production"
    echo "  $0 development postgres-development # Analyse uniquement le namespace postgres-development"
    echo "  $0 development all 24h              # Analyse tous les namespaces avec une durée de 24h"
    echo "  $0 development all 1h true          # Analyse et applique les recommandations"
    exit 0
}

# Traitement des arguments
if [[ "$#" -gt 0 && "$1" == "--help" ]]; then
    show_help
fi

# Exécution du script
main
