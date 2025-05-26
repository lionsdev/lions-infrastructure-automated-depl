#!/bin/bash
# =============================================================================
# LIONS Infrastructure - Script de désinstallation
# =============================================================================
# Titre: Script de désinstallation de l'infrastructure LIONS
# Description: Supprime tous les composants de l'infrastructure LIONS
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-26
# Version: 1.0.0
# =============================================================================

# Activation du mode strict
set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly LOG_DIR="${PROJECT_ROOT}/logs/uninstall"
readonly LOG_FILE="${LOG_DIR}/uninstall-$(date +%Y%m%d-%H%M%S).log"
readonly ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
readonly DEFAULT_ENV="${LIONS_ENV:-development}"

# Création du répertoire de logs
mkdir -p "${LOG_DIR}"

# Chargement des variables d'environnement
if [ -f "${SCRIPT_DIR}/load-env.sh" ]; then
    source "${SCRIPT_DIR}/load-env.sh"
fi

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

# Fonction de logging
function log() {
    local level="$1"
    local message="$2"
    local timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
    local icon=""
    
    # Sélection de l'icône et de la couleur en fonction du niveau
    local color="${COLOR_RESET}"
    case "${level}" in
        "INFO")     color="${COLOR_BLUE}"; icon="ℹ️ " ;;
        "WARNING")  color="${COLOR_YELLOW}"; icon="⚠️ " ;;
        "ERROR")    color="${COLOR_RED}"; icon="❌ " ;;
        "DEBUG")    color="${COLOR_MAGENTA}"; icon="🔍 " ;;
        "SUCCESS")  color="${COLOR_GREEN}"; icon="✅ " ;;
        "STEP")     color="${COLOR_CYAN}${COLOR_BOLD}"; icon="🔄 " ;;
    esac
    
    # Affichage du message avec formatage
    echo -e "${color}${icon}[${timestamp}] [${level}] ${message}${COLOR_RESET}"
    
    # Enregistrement dans un fichier de log
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Fonction d'affichage de l'aide
function afficher_aide() {
    cat << EOF
Script de Désinstallation de l'Infrastructure LIONS

Ce script supprime tous les composants de l'infrastructure LIONS.

Usage:
    $0 [options]

Options:
    -e, --environment <env>   Environnement cible (production, staging, development)
                             Par défaut: development
    -i, --inventory <file>    Fichier d'inventaire Ansible spécifique
                             Par défaut: inventories/development/hosts.yml
    -f, --force               Ne pas demander de confirmation
    -d, --debug               Active le mode debug
    -h, --help                Affiche cette aide

Exemples:
    $0
    $0 --environment staging
    $0 --force

ATTENTION: Cette opération supprimera toutes les applications et données associées à l'environnement spécifié.
EOF
}

# Fonction pour exécuter des commandes sudo avec demande de mot de passe
function secure_sudo() {
    sudo -k "$@"  # -k force à demander le mot de passe
}

# Fonction pour vérifier si un service est actif
function is_service_active() {
    local service_name="$1"
    systemctl is-active --quiet "${service_name}" 2>/dev/null
    return $?
}

# Fonction pour désinstaller Vault
function uninstall_vault() {
    log "STEP" "Désinstallation de HashiCorp Vault..."
    
    # Vérification que Vault est installé
    if ! command -v vault &> /dev/null; then
        log "INFO" "HashiCorp Vault n'est pas installé, rien à faire"
        return 0
    fi
    
    # Arrêt du service Vault
    if is_service_active "vault"; then
        log "INFO" "Arrêt du service Vault..."
        secure_sudo systemctl stop vault
        secure_sudo systemctl disable vault
        log "SUCCESS" "Service Vault arrêté et désactivé"
    else
        log "INFO" "Le service Vault n'est pas actif"
    fi
    
    # Suppression des fichiers Vault
    log "INFO" "Suppression des fichiers Vault..."
    secure_sudo rm -f /usr/local/bin/vault
    secure_sudo rm -f /etc/systemd/system/vault.service
    secure_sudo rm -rf /etc/vault.d
    secure_sudo rm -rf /opt/vault
    secure_sudo rm -rf /var/log/vault
    
    # Suppression du namespace Vault dans Kubernetes
    if command -v kubectl &> /dev/null; then
        log "INFO" "Suppression du namespace Vault dans Kubernetes..."
        kubectl delete namespace vault --ignore-not-found=true
    fi
    
    log "SUCCESS" "HashiCorp Vault désinstallé avec succès"
}

# Fonction pour désinstaller K3s
function uninstall_k3s() {
    log "STEP" "Désinstallation de K3s..."
    
    # Vérification que K3s est installé
    if [ ! -f /usr/local/bin/k3s-uninstall.sh ]; then
        log "INFO" "K3s n'est pas installé, rien à faire"
        return 0
    fi
    
    # Exécution du script de désinstallation K3s
    log "INFO" "Exécution du script de désinstallation K3s..."
    secure_sudo /usr/local/bin/k3s-uninstall.sh
    
    # Nettoyage des répertoires persistants
    log "INFO" "Nettoyage des répertoires persistants..."
    secure_sudo rm -rf /var/lib/rancher/k3s
    secure_sudo rm -rf /etc/rancher/k3s
    secure_sudo rm -rf /var/lib/kubelet
    secure_sudo rm -rf /var/lib/cni
    secure_sudo rm -rf /var/log/pods
    secure_sudo rm -rf /var/log/containers
    
    # Suppression des interfaces réseau CNI
    log "INFO" "Suppression des interfaces réseau CNI..."
    for iface in $(ip -o link show | grep -E 'cni|flannel|calico' | awk -F': ' '{print $2}'); do
        secure_sudo ip link delete "$iface" 2>/dev/null || true
    done
    
    # Nettoyage des règles iptables
    log "INFO" "Nettoyage des règles iptables..."
    secure_sudo iptables -F
    secure_sudo iptables -X
    secure_sudo iptables -t nat -F
    secure_sudo iptables -t nat -X
    secure_sudo iptables -t mangle -F
    secure_sudo iptables -t mangle -X
    secure_sudo iptables -P INPUT ACCEPT
    secure_sudo iptables -P FORWARD ACCEPT
    secure_sudo iptables -P OUTPUT ACCEPT
    
    log "SUCCESS" "K3s désinstallé avec succès"
}

# Fonction pour nettoyer les données persistantes
function cleanup_data() {
    log "STEP" "Nettoyage des données persistantes..."
    
    # Suppression des données persistantes
    log "INFO" "Suppression des données persistantes..."
    secure_sudo rm -rf /opt/lions-data
    secure_sudo rm -rf /var/lib/lions
    
    # Suppression des logs
    log "INFO" "Suppression des logs..."
    secure_sudo rm -rf /var/log/lions
    
    # Suppression des backups
    log "INFO" "Suppression des backups..."
    secure_sudo rm -rf "${PROJECT_ROOT}/backups"
    
    log "SUCCESS" "Données persistantes nettoyées avec succès"
}

# Fonction pour désinstaller l'infrastructure complète
function uninstall_infrastructure() {
    local environment="$1"
    local inventory_file="$2"
    local force="$3"
    
    log "STEP" "Désinstallation de l'infrastructure LIONS pour l'environnement ${environment}..."
    
    # Demande de confirmation si --force n'est pas spécifié
    if [ "${force}" != "true" ]; then
        echo -e "${COLOR_RED}${COLOR_BOLD}ATTENTION: Cette opération va supprimer toutes les applications et données associées à l'environnement ${environment}.${COLOR_RESET}"
        echo -e "${COLOR_RED}${COLOR_BOLD}Cette action est IRRÉVERSIBLE.${COLOR_RESET}"
        echo ""
        read -p "Êtes-vous sûr de vouloir continuer? (tapez 'oui' pour confirmer): " confirmation
        if [ "${confirmation}" != "oui" ]; then
            log "INFO" "Désinstallation annulée par l'utilisateur"
            exit 0
        fi
    fi
    
    # Désinstallation des composants dans l'ordre inverse d'installation
    
    # 1. Désinstallation des applications
    log "INFO" "Désinstallation des applications..."
    if command -v kubectl &> /dev/null; then
        # Suppression des namespaces d'applications
        kubectl delete namespace gitea-${environment} --ignore-not-found=true
        kubectl delete namespace keycloak-${environment} --ignore-not-found=true
        kubectl delete namespace postgres-${environment} --ignore-not-found=true
        kubectl delete namespace pgadmin-${environment} --ignore-not-found=true
        kubectl delete namespace registry-${environment} --ignore-not-found=true
        kubectl delete namespace ollama-${environment} --ignore-not-found=true
        kubectl delete namespace monitoring --ignore-not-found=true
        kubectl delete namespace cert-manager --ignore-not-found=true
        kubectl delete namespace traefik --ignore-not-found=true
    fi
    
    # 2. Désinstallation de Vault
    uninstall_vault
    
    # 3. Désinstallation de K3s
    uninstall_k3s
    
    # 4. Nettoyage des données persistantes
    cleanup_data
    
    log "SUCCESS" "Désinstallation de l'infrastructure LIONS terminée avec succès"
    log "INFO" "Journal de désinstallation: ${LOG_FILE}"
}

# Parsing des arguments
environment="${DEFAULT_ENV}"
inventory_file="inventories/${environment}/hosts.yml"
force="false"
debug_mode="false"

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
        -f|--force)
            force="true"
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
echo -e "${COLOR_RED}${COLOR_BOLD}"
echo -e "╔═══════════════════════════════════════════════════════════════════╗"
echo -e "║                                                                   ║"
echo -e "║      ██╗     ██╗ ██████╗ ███╗   ██╗███████╗                      ║"
echo -e "║      ██║     ██║██╔═══██╗████╗  ██║██╔════╝                      ║"
echo -e "║      ██║     ██║██║   ██║██╔██╗ ██║███████╗                      ║"
echo -e "║      ██║     ██║██║   ██║██║╚██╗██║╚════██║                      ║"
echo -e "║      ███████╗██║╚██████╔╝██║ ╚████║███████║                      ║"
echo -e "║      ╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝                      ║"
echo -e "║                                                                   ║"
echo -e "║     ██████╗ ███████╗███████╗██╗███╗   ██╗███████╗████████╗       ║"
echo -e "║     ██╔══██╗██╔════╝██╔════╝██║████╗  ██║██╔════╝╚══██╔══╝       ║"
echo -e "║     ██║  ██║█████╗  ███████╗██║██╔██╗ ██║███████╗   ██║          ║"
echo -e "║     ██║  ██║██╔══╝  ╚════██║██║██║╚██╗██║╚════██║   ██║          ║"
echo -e "║     ██████╔╝███████╗███████║██║██║ ╚████║███████║   ██║          ║"
echo -e "║     ╚═════╝ ╚══════╝╚══════╝╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝          ║"
echo -e "║                                                                   ║"
echo -e "╚═══════════════════════════════════════════════════════════════════╝${COLOR_RESET}"
echo -e "${COLOR_YELLOW}${COLOR_BOLD}     Script de Désinstallation - v1.0.0${COLOR_RESET}"
echo -e "${COLOR_RED}  ════════════════════════════════════════════════════════${COLOR_RESET}\n"

# Affichage des paramètres
log "INFO" "Environnement: ${environment}"
log "INFO" "Fichier d'inventaire: ${inventory_file}"
log "INFO" "Mode force: ${force}"
log "INFO" "Mode debug: ${debug_mode}"
log "INFO" "Fichier de log: ${LOG_FILE}"

# Exécution de la désinstallation
uninstall_infrastructure "${environment}" "${inventory_file}" "${force}"

exit 0