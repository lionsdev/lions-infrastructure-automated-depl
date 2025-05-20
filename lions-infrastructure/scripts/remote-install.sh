#!/bin/bash
# Titre: Script d'installation à distance pour l'infrastructure LIONS
# Description: Facilite l'installation directe sur le VPS cible
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-20
# Version: 1.0.0

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
    local timestamp
    timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
    local log_color="${COLOR_RESET}"
    local log_prefix=""

    # Sélection de la couleur et du préfixe en fonction du niveau
    case "${level}" in
        "INFO")     log_color="${COLOR_BLUE}"; log_prefix="ℹ️ " ;;
        "WARNING")  log_color="${COLOR_YELLOW}"; log_prefix="⚠️ " ;;
        "ERROR")    log_color="${COLOR_RED}"; log_prefix="❌ " ;;
        "DEBUG")    log_color="${COLOR_MAGENTA}"; log_prefix="🔍 " ;;
        "SUCCESS")  log_color="${COLOR_GREEN}"; log_prefix="✅ " ;;
        "STEP")     log_color="${COLOR_CYAN}${COLOR_BOLD}"; log_prefix="🔄 " ;;
    esac

    # Affichage du message avec formatage
    echo -e "${log_color}${log_prefix}[${timestamp}] [${level}]${COLOR_RESET} ${message}"
}

# Fonction pour afficher l'aide
function show_help() {
    echo -e "${COLOR_BOLD}Script d'installation à distance pour l'infrastructure LIONS${COLOR_RESET}"
    echo -e "Ce script facilite l'installation de l'infrastructure LIONS directement sur le VPS cible."
    echo -e "Il se connecte au VPS via SSH, clone le dépôt et exécute le script d'installation."
    echo
    echo -e "${COLOR_BOLD}Usage:${COLOR_RESET}"
    echo -e "  $0 [options]"
    echo
    echo -e "${COLOR_BOLD}Options:${COLOR_RESET}"
    echo -e "  -h, --help                Affiche cette aide"
    echo -e "  -u, --user USER           Nom d'utilisateur SSH (défaut: root)"
    echo -e "  -H, --host HOST           Adresse IP ou nom d'hôte du VPS"
    echo -e "  -p, --port PORT           Port SSH (défaut: 22)"
    echo -e "  -r, --repo URL            URL du dépôt Git (défaut: https://github.com/votre-repo/lions-infrastructure-automated-depl.git)"
    echo -e "  -e, --environment ENV     Environnement à déployer (défaut: development)"
    echo -e "  -b, --branch BRANCH       Branche Git à utiliser (défaut: main)"
    echo
    echo -e "${COLOR_BOLD}Exemples:${COLOR_RESET}"
    echo -e "  $0 --host 176.57.150.2 --port 225 --user root"
    echo -e "  $0 -H 176.57.150.2 -p 225 -u root -e production"
}

# Valeurs par défaut
SSH_USER="root"
SSH_PORT="22"
SSH_HOST=""
GIT_REPO="https://github.com/votre-repo/lions-infrastructure-automated-depl.git"
ENVIRONMENT="development"
GIT_BRANCH="main"

# Traitement des arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -u|--user)
            SSH_USER="$2"
            shift 2
            ;;
        -H|--host)
            SSH_HOST="$2"
            shift 2
            ;;
        -p|--port)
            SSH_PORT="$2"
            shift 2
            ;;
        -r|--repo)
            GIT_REPO="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -b|--branch)
            GIT_BRANCH="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Option inconnue: $1"
            show_help
            exit 1
            ;;
    esac
done

# Vérification des paramètres obligatoires
if [[ -z "${SSH_HOST}" ]]; then
    log "ERROR" "L'adresse du VPS est requise. Utilisez --host ou -H pour la spécifier."
    show_help
    exit 1
fi

# Affichage du logo
echo -e "${COLOR_CYAN}${COLOR_BOLD}"
echo -e "╔═══════════════════════════════════════════════════════════════════╗"
echo -e "║                                                                   ║"
echo -e "║      ██╗     ██╗ ██████╗ ███╗   ██╗███████╗    ██╗███╗   ██╗      ║"
echo -e "║      ██║     ██║██╔═══██╗████╗  ██║██╔════╝    ██║████╗  ██║      ║"
echo -e "║      ██║     ██║██║   ██║██╔██╗ ██║███████╗    ██║██╔██╗ ██║      ║"
echo -e "║      ██║     ██║██║   ██║██║╚██╗██║╚════██║    ██║██║╚██╗██║      ║"
echo -e "║      ███████╗██║╚██████╔╝██║ ╚████║███████║    ██║██║ ╚████║      ║"
echo -e "║      ╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝    ╚═╝╚═╝  ╚═══╝      ║"
echo -e "║                                                                   ║"
echo -e "║     ███████╗ ██████╗    █████╗ ██╗   ██╗████████╗ ██████╗         ║"
echo -e "║     ██╔════╝██╔═══██╗  ██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗        ║"
echo -e "║     █████╗  ██║   ██║  ███████║██║   ██║   ██║   ██║   ██║        ║"
echo -e "║     ██╔══╝  ██║   ██║  ██╔══██║██║   ██║   ██║   ██║   ██║        ║"
echo -e "║     ██║     ╚██████╔╝  ██║  ██║╚██████╔╝   ██║   ╚██████╔╝        ║"
echo -e "║     ╚═╝      ╚═════╝   ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝         ║"
echo -e "║                                                                   ║"
echo -e "╚═══════════════════════════════════════════════════════════════════╝"
echo -e "     Installation à Distance de l'Infrastructure LIONS"
echo -e "  ════════════════════════════════════════════════════════${COLOR_RESET}"
echo

# Affichage des informations de connexion
log "INFO" "Connexion au VPS: ${SSH_USER}@${SSH_HOST}:${SSH_PORT}"
log "INFO" "Environnement: ${ENVIRONMENT}"
log "INFO" "Dépôt Git: ${GIT_REPO} (branche: ${GIT_BRANCH})"

# Vérification de la connectivité SSH
log "INFO" "Vérification de la connectivité SSH..."
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${SSH_PORT}" "${SSH_USER}@${SSH_HOST}" "echo 'Connexion SSH réussie'" &>/dev/null; then
    log "ERROR" "Impossible de se connecter au VPS via SSH. Vérifiez vos paramètres de connexion."
    log "INFO" "Assurez-vous que:"
    log "INFO" "1. L'adresse IP et le port sont corrects"
    log "INFO" "2. Votre clé SSH est configurée correctement"
    log "INFO" "3. Le serveur SSH est en cours d'exécution sur le VPS"
    exit 1
fi
log "SUCCESS" "Connexion SSH réussie"

# Création de la commande SSH à exécuter sur le VPS
SSH_COMMAND="ssh -p ${SSH_PORT} ${SSH_USER}@${SSH_HOST}"

# Vérification des prérequis sur le VPS
log "INFO" "Vérification des prérequis sur le VPS..."
$SSH_COMMAND "command -v git >/dev/null 2>&1 || { echo 'Git non installé'; exit 1; }"
if [ $? -ne 0 ]; then
    log "INFO" "Installation de Git sur le VPS..."
    $SSH_COMMAND "apt-get update && apt-get install -y git"
    if [ $? -ne 0 ]; then
        log "ERROR" "Impossible d'installer Git sur le VPS"
        exit 1
    fi
fi
log "SUCCESS" "Git est installé sur le VPS"

# Clonage du dépôt sur le VPS
log "INFO" "Clonage du dépôt sur le VPS..."
$SSH_COMMAND "rm -rf lions-infrastructure-automated-depl && git clone ${GIT_REPO} --branch ${GIT_BRANCH} lions-infrastructure-automated-depl"
if [ $? -ne 0 ]; then
    log "ERROR" "Impossible de cloner le dépôt sur le VPS"
    exit 1
fi
log "SUCCESS" "Dépôt cloné avec succès"

# Exécution du script d'installation sur le VPS
log "INFO" "Exécution du script d'installation sur le VPS..."
log "INFO" "Cette opération peut prendre plusieurs minutes..."
$SSH_COMMAND "cd lions-infrastructure-automated-depl/lions-infrastructure/scripts && chmod +x install.sh && ./install.sh --environment ${ENVIRONMENT}"
INSTALL_RESULT=$?

if [ $INSTALL_RESULT -eq 0 ]; then
    log "SUCCESS" "Installation terminée avec succès"
else
    log "ERROR" "L'installation a échoué avec le code de sortie ${INSTALL_RESULT}"
    log "INFO" "Consultez les logs sur le VPS pour plus d'informations"
fi

log "INFO" "Pour vous connecter au VPS et vérifier l'installation, utilisez:"
log "INFO" "ssh -p ${SSH_PORT} ${SSH_USER}@${SSH_HOST}"

exit $INSTALL_RESULT