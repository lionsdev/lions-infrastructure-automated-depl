#!/bin/bash
# =============================================================================
# LIONS Infrastructure - Script de vérification de santé du VPS v5.0
# =============================================================================
# Description: Vérifie l'état de santé et l'utilisation des ressources du VPS
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
readonly ANSIBLE_DIR="${LIONS_ANSIBLE_DIR:-${PROJECT_ROOT}/ansible}"
readonly LOG_DIR="${LIONS_MAINTENANCE_LOG_DIR:-${PROJECT_ROOT}/scripts/logs/maintenance}"
readonly LOG_FILE="${LOG_DIR}/health-check-$(date +%Y%m%d-%H%M%S).log"
readonly REPORT_FILE="${LOG_DIR}/health-report-$(date +%Y%m%d).html"
readonly DEFAULT_ENV="${LIONS_ENVIRONMENT}"

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

# Création du répertoire de logs
mkdir -p "${LOG_DIR}"

# Fonction de logging
function log() {
    local level="$1"
    local message="$2"
    local timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
    local color="${COLOR_RESET}"

    case "${level}" in
        "INFO")     color="${COLOR_BLUE}" ;;
        "SUCCESS")  color="${COLOR_GREEN}" ;;
        "WARNING")  color="${COLOR_YELLOW}" ;;
        "ERROR")    color="${COLOR_RED}" ;;
    esac

    echo -e "${color}${COLOR_BOLD}[${timestamp}] [${level}]${COLOR_RESET} ${message}"
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Fonction d'affichage de l'aide
function afficher_aide() {
    cat << EOF
Script de Vérification de Santé du VPS - Infrastructure LIONS

Ce script vérifie l'état de santé et l'utilisation des ressources du VPS.

Usage:
    $0 [options]

Options:
    -e, --environment <env>   Environnement cible (production, staging, development)
                             Par défaut: development
    -i, --inventory <file>    Fichier d'inventaire Ansible spécifique
                             Par défaut: inventories/development/hosts.yml
    -r, --report              Génère un rapport HTML
    -d, --debug               Active le mode debug
    -h, --help                Affiche cette aide

Exemples:
    $0
    $0 --environment staging
    $0 --report
EOF
}

# Fonction de vérification des prérequis
function verifier_prerequis() {
    log "INFO" "Vérification des prérequis..."

    # Vérification d'Ansible
    if ! command -v ansible &> /dev/null; then
        log "ERROR" "ansible n'est pas installé ou n'est pas dans le PATH"
        exit 1
    fi

    # Vérification de kubectl
    if ! command -v kubectl &> /dev/null; then
        log "ERROR" "kubectl n'est pas installé ou n'est pas dans le PATH"
        exit 1
    fi

    # Vérification des fichiers Ansible
    if [[ ! -f "${ANSIBLE_DIR}/${inventory_file}" ]]; then
        log "ERROR" "Le fichier d'inventaire n'existe pas: ${ANSIBLE_DIR}/${inventory_file}"
        exit 1
    fi

    log "SUCCESS" "Tous les prérequis sont satisfaits"
}

# Fonction de vérification de la connectivité
function verifier_connectivite() {
    log "INFO" "Vérification de la connectivité au VPS..."

    # Récupération de l'adresse IP du VPS
    local vps_ip=$(grep -A1 "contabo-vps" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_host" | awk -F': ' '{print $2}')
    local vps_port=$(grep -A2 "contabo-vps" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_port" | awk -F': ' '{print $2}')

    # Vérification de la connectivité SSH
    local vps_user="${LIONS_VPS_USER:-lionsdevadmin}"
    local ssh_timeout="${LIONS_VPS_SSH_TIMEOUT:-5}"

    if ssh -q -o BatchMode=yes -o ConnectTimeout=${ssh_timeout} -p "${vps_port}" "${vps_user}@${vps_ip}" exit &>/dev/null; then
        log "SUCCESS" "Connexion SSH au VPS réussie (${vps_ip}:${vps_port})"
    else
        log "ERROR" "Impossible de se connecter au VPS via SSH (${vps_ip}:${vps_port})"
        exit 1
    fi

    # Vérification de la connectivité HTTP
    local grafana_port="${LIONS_GRAFANA_PORT:-30000}"
    local grafana_protocol="${LIONS_GRAFANA_PROTOCOL:-http}"

    if curl -s --head --request GET "${grafana_protocol}://${vps_ip}:${grafana_port}" | grep "200 OK" > /dev/null; then
        log "SUCCESS" "Connexion HTTP à Grafana réussie (${grafana_protocol}://${vps_ip}:${grafana_port})"
    else
        log "WARNING" "Impossible de se connecter à Grafana via HTTP (${grafana_protocol}://${vps_ip}:${grafana_port})"
    fi
}

# Fonction de vérification des ressources système
function verifier_ressources_systeme() {
    log "INFO" "Vérification des ressources système du VPS..."

    # Exécution de la commande de vérification des ressources via Ansible
    ansible -i "${ANSIBLE_DIR}/${inventory_file}" contabo-vps -m shell -a "echo '=== CPU ==='; top -bn1 | grep 'Cpu(s)'; echo '=== MÉMOIRE ==='; free -h; echo '=== DISQUE ==='; df -h; echo '=== PROCESSUS ==='; ps aux --sort=-%cpu | head -10" > /tmp/vps_resources.txt

    # Affichage des résultats
    echo -e "\n${COLOR_CYAN}${COLOR_BOLD}=== RESSOURCES SYSTÈME DU VPS ===${COLOR_RESET}"
    cat /tmp/vps_resources.txt | grep -v "SUCCESS" | sed 's/^/  /'
    echo -e "${COLOR_CYAN}${COLOR_BOLD}===================================${COLOR_RESET}\n"

    # Analyse des résultats
    local cpu_usage=$(grep "Cpu(s)" /tmp/vps_resources.txt | awk '{print $2}' | sed 's/,/./g')
    local mem_usage=$(grep "Mem:" /tmp/vps_resources.txt | awk '{print $3}')
    local mem_total=$(grep "Mem:" /tmp/vps_resources.txt | awk '{print $2}')
    local disk_usage=$(grep "/dev/sda" /tmp/vps_resources.txt | head -1 | awk '{print $5}' | sed 's/%//')

    # Évaluation de l'utilisation des ressources
    local cpu_threshold="${LIONS_CPU_THRESHOLD:-80}"
    local disk_threshold="${LIONS_DISK_THRESHOLD:-80}"

    if (( $(echo "${cpu_usage} > ${cpu_threshold}" | bc -l) )); then
        log "WARNING" "Utilisation CPU élevée: ${cpu_usage}% (seuil: ${cpu_threshold}%)"
    else
        log "SUCCESS" "Utilisation CPU normale: ${cpu_usage}% (seuil: ${cpu_threshold}%)"
    fi

    log "INFO" "Utilisation mémoire: ${mem_usage} / ${mem_total}"

    if (( disk_usage > ${disk_threshold} )); then
        log "WARNING" "Utilisation disque élevée: ${disk_usage}% (seuil: ${disk_threshold}%)"
    else
        log "SUCCESS" "Utilisation disque normale: ${disk_usage}% (seuil: ${disk_threshold}%)"
    fi
}

# Fonction de vérification de Kubernetes
function verifier_kubernetes() {
    log "INFO" "Vérification de l'état de Kubernetes..."

    # Vérification des nœuds
    log "INFO" "Vérification des nœuds Kubernetes..."
    kubectl get nodes -o wide

    # Vérification des pods système
    log "INFO" "Vérification des pods système..."
    kubectl get pods -n kube-system

    # Vérification des pods du Kubernetes Dashboard
    log "INFO" "Vérification des pods du Kubernetes Dashboard..."
    kubectl get pods -n kubernetes-dashboard

    # Vérification des pods en état d'erreur
    log "INFO" "Vérification des pods en état d'erreur..."
    local error_pods=$(kubectl get pods --all-namespaces | grep -v "Running\|Completed" | grep -v "NAME")

    if [[ -n "${error_pods}" ]]; then
        log "WARNING" "Pods en état d'erreur détectés:"
        echo "${error_pods}" | sed 's/^/  /'
    else
        log "SUCCESS" "Aucun pod en état d'erreur détecté"
    fi

    # Vérification de l'utilisation des ressources
    log "INFO" "Vérification de l'utilisation des ressources Kubernetes..."
    kubectl top nodes
    kubectl top pods --all-namespaces | sort -k4 -hr | head -10
}

# Fonction de vérification des services
function verifier_services() {
    log "INFO" "Vérification des services critiques..."

    # Vérification du service K3s
    ansible -i "${ANSIBLE_DIR}/${inventory_file}" contabo-vps -m shell -a "systemctl status k3s | grep Active" > /tmp/k3s_status.txt

    if grep -q "active (running)" /tmp/k3s_status.txt; then
        log "SUCCESS" "Service K3s: actif et en cours d'exécution"
    else
        log "ERROR" "Service K3s: inactif ou en erreur"
    fi

    # Vérification du service fail2ban
    ansible -i "${ANSIBLE_DIR}/${inventory_file}" contabo-vps -m shell -a "systemctl status fail2ban | grep Active" > /tmp/fail2ban_status.txt

    if grep -q "active (running)" /tmp/fail2ban_status.txt; then
        log "SUCCESS" "Service fail2ban: actif et en cours d'exécution"
    else
        log "WARNING" "Service fail2ban: inactif ou en erreur"
    fi

    # Vérification du pare-feu UFW
    ansible -i "${ANSIBLE_DIR}/${inventory_file}" contabo-vps -m shell -a "ufw status | grep Status" > /tmp/ufw_status.txt

    if grep -q "Status: active" /tmp/ufw_status.txt; then
        log "SUCCESS" "Pare-feu UFW: actif"
    else
        log "WARNING" "Pare-feu UFW: inactif"
    fi
}

# Fonction de génération de rapport HTML
function generer_rapport_html() {
    log "INFO" "Génération du rapport HTML..."

    # Récupération des informations
    local vps_ip=$(grep -A1 "contabo-vps" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_host" | awk -F': ' '{print $2}')
    local date_rapport=$(date +"%Y-%m-%d %H:%M:%S")

    # Création du rapport HTML
    cat > "${REPORT_FILE}" << EOF
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Rapport de Santé VPS - Infrastructure LIONS</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; color: #333; }
        h1, h2, h3 { color: #2c3e50; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { background-color: #3498db; color: white; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        .section { background-color: #f9f9f9; padding: 15px; border-radius: 5px; margin-bottom: 20px; border-left: 5px solid #3498db; }
        .success { color: #27ae60; }
        .warning { color: #f39c12; }
        .error { color: #e74c3c; }
        table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
        th, td { padding: 12px 15px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f2f2f2; }
        tr:hover { background-color: #f5f5f5; }
        .footer { text-align: center; margin-top: 30px; font-size: 0.8em; color: #7f8c8d; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Rapport de Santé VPS - Infrastructure LIONS</h1>
            <p>Date du rapport: ${date_rapport}</p>
            <p>Adresse IP du VPS: ${vps_ip}</p>
        </div>

        <div class="section">
            <h2>Ressources Système</h2>
            <pre>$(ansible -i "${ANSIBLE_DIR}/${inventory_file}" contabo-vps -m shell -a "echo '=== CPU ==='; top -bn1 | grep 'Cpu(s)'; echo '=== MÉMOIRE ==='; free -h; echo '=== DISQUE ==='; df -h;" | grep -v "SUCCESS")</pre>
        </div>

        <div class="section">
            <h2>État des Services</h2>
            <table>
                <tr>
                    <th>Service</th>
                    <th>État</th>
                </tr>
                <tr>
                    <td>K3s</td>
                    <td class="$(grep -q "active (running)" /tmp/k3s_status.txt && echo 'success' || echo 'error')">
                        $(grep -q "active (running)" /tmp/k3s_status.txt && echo 'Actif' || echo 'Inactif/Erreur')
                    </td>
                </tr>
                <tr>
                    <td>fail2ban</td>
                    <td class="$(grep -q "active (running)" /tmp/fail2ban_status.txt && echo 'success' || echo 'warning')">
                        $(grep -q "active (running)" /tmp/fail2ban_status.txt && echo 'Actif' || echo 'Inactif/Erreur')
                    </td>
                </tr>
                <tr>
                    <td>UFW</td>
                    <td class="$(grep -q "Status: active" /tmp/ufw_status.txt && echo 'success' || echo 'warning')">
                        $(grep -q "Status: active" /tmp/ufw_status.txt && echo 'Actif' || echo 'Inactif')
                    </td>
                </tr>
            </table>
        </div>

        <div class="section">
            <h2>État de Kubernetes</h2>
            <h3>Nœuds</h3>
            <pre>$(kubectl get nodes -o wide)</pre>

            <h3>Pods Système</h3>
            <pre>$(kubectl get pods -n kube-system)</pre>

            <h3>Kubernetes Dashboard</h3>
            <pre>$(kubectl get pods -n kubernetes-dashboard)</pre>

            <h3>Pods en Erreur</h3>
            <pre>$(kubectl get pods --all-namespaces | grep -v "Running\|Completed" | grep -v "NAME" || echo "Aucun pod en erreur")</pre>

            <h3>Utilisation des Ressources</h3>
            <pre>$(kubectl top nodes 2>/dev/null || echo "Métriques non disponibles")</pre>
            <pre>$(kubectl top pods --all-namespaces 2>/dev/null | sort -k4 -hr | head -10 || echo "Métriques non disponibles")</pre>
        </div>

        <div class="footer">
            <p>Rapport généré par le script de vérification de santé de l'infrastructure LIONS</p>
        </div>
    </div>
</body>
</html>
EOF

    log "SUCCESS" "Rapport HTML généré: ${REPORT_FILE}"
}

# Parsing des arguments
environment="${LIONS_ENVIRONMENT:-${DEFAULT_ENV}}"
inventory_file="${LIONS_INVENTORY_FILE:-inventories/${environment}/hosts.yml}"
generate_report="${LIONS_GENERATE_REPORT:-false}"
debug_mode="${LIONS_DEBUG_MODE:-false}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--environment)
            environment="$2"
            inventory_file="inventories/${environment}/hosts.yml"
            shift 2
            ;;
        -i|--inventory)
            inventory_file="$2"
            shift 2
            ;;
        -r|--report)
            generate_report="true"
            shift
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
            log "ERROR" "Argument inconnu: $1"
            afficher_aide
            exit 1
            ;;
    esac
done

# Affichage du titre
echo -e "${COLOR_CYAN}${COLOR_BOLD}"
echo -e "  _     ___ ___  _   _ ___    ___ _   _ _____ ___    _    "
echo -e " | |   |_ _/ _ \| \ | / __|  |_ _| \ | |  ___/ _ \  / \   "
echo -e " | |    | | | | |  \| \__ \   | ||  \| | |_ | | | |/ _ \  "
echo -e " | |___ | | |_| | |\  |__) |  | || |\  |  _|| |_| / ___ \ "
echo -e " |_____|___\___/|_| \_|____/  |___|_| \_|_|   \___/_/   \_\\"
echo -e "${COLOR_RESET}"
echo -e "${COLOR_YELLOW}${COLOR_BOLD}  Vérification de Santé du VPS - v5.0.0${COLOR_RESET}"
echo -e "${COLOR_CYAN}  ------------------------------------------------${COLOR_RESET}\n"

# Affichage des paramètres
log "INFO" "Environnement: ${environment}"
log "INFO" "Fichier d'inventaire: ${inventory_file}"
log "INFO" "Génération de rapport: ${generate_report}"
log "INFO" "Mode debug: ${debug_mode}"
log "INFO" "Fichier de log: ${LOG_FILE}"

# Exécution des vérifications
verifier_prerequis
verifier_connectivite
verifier_ressources_systeme
verifier_kubernetes
verifier_services

# Génération du rapport HTML si demandé
if [[ "${generate_report}" == "true" ]]; then
    generer_rapport_html
fi

# Affichage du résumé
echo -e "\n${COLOR_GREEN}${COLOR_BOLD}===========================================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}${COLOR_BOLD}  Vérification de santé du VPS terminée !${COLOR_RESET}"
echo -e "${COLOR_GREEN}${COLOR_BOLD}===========================================================${COLOR_RESET}\n"

log "INFO" "Pour plus de détails, consultez le fichier de log: ${LOG_FILE}"
if [[ "${generate_report}" == "true" ]]; then
    log "INFO" "Rapport HTML disponible: ${REPORT_FILE}"
fi

exit 0
