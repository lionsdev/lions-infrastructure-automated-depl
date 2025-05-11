#!/bin/bash
# Titre: Script d'installation de l'infrastructure LIONS sur VPS
# Description: Orchestre l'installation complète de l'infrastructure LIONS sur un VPS
# Auteur: Équipe LIONS Infrastructure
# Date: 2023-05-15
# Version: 1.2.0
# Mise à jour: Amélioration des performances, sécurité et robustesse

# Configuration stricte
set -o errexit    # Arrêt sur erreur
set -o pipefail   # Propagation des erreurs dans les pipes
set -o nounset    # Erreur sur variable non définie

# Configuration des chemins et fichiers
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
readonly LOG_DIR="./logs/infrastructure"
readonly LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
readonly DEFAULT_ENV="development"
readonly BACKUP_DIR="${LOG_DIR}/backups"
readonly STATE_FILE="${LOG_DIR}/.installation_state"
readonly LOCK_FILE="/tmp/lions_install.lock"
readonly CACHE_DIR="/tmp/.lions_cache"
readonly SSH_CONTROL_PATH="/tmp/ssh_control_master_${RANDOM}"

# Configuration des ressources
readonly REQUIRED_SPACE_MB=5000  # 5 Go d'espace disque requis
readonly TIMEOUT_SECONDS=1800    # 30 minutes de timeout pour les commandes longues
readonly SSH_TIMEOUT=10          # 10 secondes pour les opérations SSH
readonly PARALLEL_LIMIT=4        # Limite pour les opérations parallèles

# Ports requis
readonly REQUIRED_PORTS=(22 22225 80 443 6443 30000 30001)

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

# Variables globales
INSTALLATION_STEP=""
LAST_COMMAND=""
LAST_ERROR=""
RETRY_COUNT=0
MAX_RETRIES=3
START_TIME=$(date +%s)
SSH_MASTER_STARTED=false

# Tableaux associatifs pour le cache
declare -A CACHE_SSH_COMMANDS
declare -A CACHE_KUBECTL_COMMANDS
declare -A PERFORMANCE_METRICS

# Création des répertoires nécessaires
mkdir -p "${LOG_DIR}" "${BACKUP_DIR}" "${CACHE_DIR}"

# Gestionnaire de signaux amélioré
trap 'handle_signal TERM' TERM
trap 'handle_signal INT' INT
trap 'handle_signal EXIT' EXIT
trap 'handle_error ${LINENO} "${COMMAND_NAME:-unknown}"' ERR

# Fonction de gestion des signaux
function handle_signal() {
    local signal="$1"

    case "${signal}" in
        "TERM"|"INT")
            log "WARNING" "Signal ${signal} reçu, nettoyage en cours..."
            cleanup
            exit 1
            ;;
        "EXIT")
            cleanup
            ;;
    esac
}

# Fonction de nettoyage améliorée
function cleanup() {
    # Désactivation temporaire du mode strict pour le nettoyage
    set +e

    # Fermeture des connexions SSH persistantes
    if [[ "${SSH_MASTER_STARTED}" == "true" ]]; then
        ssh -O exit -S "${SSH_CONTROL_PATH}" dummy 2>/dev/null || true
    fi

    # Nettoyage des fichiers temporaires
    rm -f "${SSH_CONTROL_PATH}"*
    rm -rf "${CACHE_DIR}"

    # Suppression du fichier de verrouillage
    if [[ -f "${LOCK_FILE}" ]]; then
        if ! rm -f "${LOCK_FILE}" 2>/dev/null; then
            sudo rm -f "${LOCK_FILE}" 2>/dev/null || true
        fi
    fi

    # Calcul du temps total d'exécution
    local end_time=$(date +%s)
    local total_time=$((end_time - START_TIME))
    log "INFO" "Durée totale d'exécution: $((total_time / 60)) minutes et $((total_time % 60)) secondes"

    # Affichage des informations de diagnostic
    log "INFO" "Informations de diagnostic:"
    log "INFO" "- Dernière étape: ${INSTALLATION_STEP}"
    log "INFO" "- Dernière commande: ${LAST_COMMAND}"
    log "INFO" "- Dernière erreur: ${LAST_ERROR}"
    log "INFO" "- Fichier de log: ${LOG_FILE}"

    # Affichage des métriques de performance
    if [[ ${#PERFORMANCE_METRICS[@]} -gt 0 ]]; then
        log "INFO" "Métriques de performance:"
        for key in "${!PERFORMANCE_METRICS[@]}"; do
            log "INFO" "  - ${key}: ${PERFORMANCE_METRICS[${key}]}ms"
        done
    fi

    log "INFO" "Nettoyage terminé"

    # Réactivation du mode strict
    set -euo pipefail
}

# Fonction de logging améliorée avec filtrage des informations sensibles
function log() {
    local level="$1"
    local message="$2"
    local timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
    local caller_info=""
    local log_color="${COLOR_RESET}"
    local log_prefix=""

    # Filtrage des informations sensibles
    local filtered_message="${message}"
    filtered_message="${filtered_message//:[0-9]{1,5}@/:****@}"  # Masquage des ports dans les URLs
    filtered_message="${filtered_message//--password [^ ]*/--password ****}"  # Masquage des mots de passe
    filtered_message="${filtered_message//token=[^ ]*/token=****}"  # Masquage des tokens

    # Détermination de la fonction appelante et du numéro de ligne
    if [[ "${debug_mode:-false}" == "true" ]]; then
        local caller_function=$(caller 0 | awk '{print $2}')
        local caller_line=$(caller 0 | awk '{print $1}')

        if [[ -n "${caller_function}" && "${caller_function}" != "main" ]]; then
            caller_info=" [${caller_function}:${caller_line}]"
        else
            caller_info=" [ligne:${caller_line}]"
        fi
    fi

    # Sélection de la couleur et du préfixe en fonction du niveau
    case "${level}" in
        "INFO")     log_color="${COLOR_BLUE}"; log_prefix="ℹ️ " ;;
        "WARNING")  log_color="${COLOR_YELLOW}"; log_prefix="⚠️ " ;;
        "ERROR")    log_color="${COLOR_RED}"; log_prefix="❌ " ;;
        "DEBUG")    log_color="${COLOR_MAGENTA}"; log_prefix="🔍 " ;;
        "SUCCESS")  log_color="${COLOR_GREEN}"; log_prefix="✅ " ;;
        "STEP")     log_color="${COLOR_CYAN}${COLOR_BOLD}"; log_prefix="🔄 " ;;
        "PERF")     log_color="${COLOR_WHITE}"; log_prefix="📊 " ;;
    esac

    # Affichage du message avec formatage
    echo -e "${log_color}${log_prefix}[${timestamp}] [${level}]${caller_info}${COLOR_RESET} ${filtered_message}"

    # Enregistrement dans le fichier de log (sans filtrage pour le diagnostic)
    echo "[${timestamp}] [${level}]${caller_info} ${message}" >> "${LOG_FILE}"

    # Enregistrement des messages importants dans des fichiers séparés
    case "${level}" in
        "ERROR")
            echo "[${timestamp}] [${level}]${caller_info} ${message}" >> "${LOG_DIR}/errors.log"
            ;;
        "WARNING")
            echo "[${timestamp}] [${level}]${caller_info} ${message}" >> "${LOG_DIR}/warnings.log"
            ;;
        "STEP")
            echo "[${timestamp}] [${level}]${caller_info} ${message}" >> "${LOG_DIR}/steps.log"
            ;;
        "PERF")
            echo "[${timestamp}] [${level}]${caller_info} ${message}" >> "${LOG_DIR}/performance.log"
            ;;
    esac
}

# Fonction pour mesurer les performances
function measure_performance() {
    local operation_name="$1"
    local start_time=$(date +%s%3N)

    # Exécuter la commande passée en argument
    shift
    "$@"
    local exit_code=$?

    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))

    PERFORMANCE_METRICS["${operation_name}"]="${duration}"
    log "PERF" "${operation_name}: ${duration}ms"

    return ${exit_code}
}

# Configuration SSH optimisée avec connexions persistantes
function setup_ssh_connection() {
    local host="${ansible_host}"
    local port="${ansible_port}"
    local user="${ansible_user}"

    if [[ -n "${host}" && -n "${port}" && -n "${user}" ]]; then
        log "INFO" "Configuration de la connexion SSH persistante vers ${user}@${host}:${port}"

        # Démarrage du master SSH
        ssh -o ControlMaster=yes \
            -o ControlPath="${SSH_CONTROL_PATH}" \
            -o ControlPersist=10m \
            -o BatchMode=yes \
            -o ConnectTimeout=${SSH_TIMEOUT} \
            -p "${port}" \
            "${user}@${host}" \
            "echo 'Master SSH établi'" &>/dev/null &

        # Attendre que la connexion soit établie
        local retry=0
        while [[ ${retry} -lt 30 ]]; do
            if ssh -o ControlPath="${SSH_CONTROL_PATH}" \
                   -o BatchMode=yes \
                   -p "${port}" \
                   "${user}@${host}" \
                   "exit" &>/dev/null; then
                SSH_MASTER_STARTED=true
                log "SUCCESS" "Connexion SSH persistante établie"
                return 0
            fi
            sleep 0.2
            ((retry++))
        done

        log "WARNING" "Impossible d'établir une connexion SSH persistante"
    fi

    return 1
}

# Fonction SSH optimisée avec cache et réutilisation des connexions
function ssh_exec() {
    local command="$1"
    local cache_key="${command:0:50}"
    local use_cache="${2:-true}"
    local timeout="${3:-${SSH_TIMEOUT}}"

    # Vérification du cache si demandé
    if [[ "${use_cache}" == "true" && -n "${CACHE_SSH_COMMANDS[${cache_key}]}" ]]; then
        log "DEBUG" "Utilisation du cache pour: ${cache_key}"
        echo "${CACHE_SSH_COMMANDS[${cache_key}]}"
        return 0
    fi

    # Configuration SSH optimisée
    local ssh_opts=(
        "-o" "ControlPath=${SSH_CONTROL_PATH}"
        "-o" "BatchMode=yes"
        "-o" "ConnectTimeout=${timeout}"
        "-o" "ServerAliveInterval=30"
        "-o" "ServerAliveCountMax=3"
        "-p" "${ansible_port}"
    )

    # Exécution avec gestion d'erreur
    local output
    local exit_code

    if [[ "${SSH_MASTER_STARTED}" == "true" ]]; then
        # Utilisation de la connexion persistante
        output=$(ssh "${ssh_opts[@]}" "${ansible_user}@${ansible_host}" "${command}" 2>/dev/null)
        exit_code=$?
    else
        # Fallback sans connexion persistante
        output=$(ssh "${ssh_opts[@]}" "${ansible_user}@${ansible_host}" "${command}" 2>/dev/null)
        exit_code=$?
    fi

    # Mise en cache du résultat si succès
    if [[ ${exit_code} -eq 0 && "${use_cache}" == "true" ]]; then
        CACHE_SSH_COMMANDS[${cache_key}]="${output}"
    fi

    echo "${output}"
    return ${exit_code}
}

# Fonction pour exécuter des commandes en parallèle avec limite
function parallel_exec() {
    local limit="${1:-${PARALLEL_LIMIT}}"
    local pids=()
    local commands=("${@:2}")
    local count=0

    for cmd in "${commands[@]}"; do
        # Exécution en arrière-plan
        eval "${cmd}" &
        pids+=($!)

        ((count++))

        # Vérification de la limite de processus parallèles
        if [[ ${count} -ge ${limit} ]]; then
            # Attendre qu'au moins un processus se termine
            wait -n

            # Nettoyage des PID terminés
            local new_pids=()
            for pid in "${pids[@]}"; do
                if kill -0 "${pid}" 2>/dev/null; then
                    new_pids+=("${pid}")
                fi
            done
            pids=("${new_pids[@]}")

            count=${#pids[@]}
        fi
    done

    # Attendre que tous les processus se terminent
    for pid in "${pids[@]}"; do
        wait "${pid}" || log "WARNING" "Processus ${pid} a échoué"
    done
}

# Fonction optimisée pour vérifier si une commande existe
function command_exists() {
    local cmd="$1"
    command -v "${cmd}" &>/dev/null
}

# Fonction améliorée pour installer les commandes manquantes avec parallélisation
function install_missing_commands() {
    local commands=("$@")
    local os_name=$(uname -s)
    local success=true

    log "INFO" "Détection du système d'exploitation: ${os_name}"

    # Détection du gestionnaire de paquets avec cache
    local pkg_manager
    local install_cmd

    # Utilisation du cache pour la détection du gestionnaire de paquets
    if [[ -f "${CACHE_DIR}/pkg_manager" ]]; then
        pkg_manager=$(cat "${CACHE_DIR}/pkg_manager")
        install_cmd=$(cat "${CACHE_DIR}/install_cmd")
    else
        # Détection et mise en cache
        if [[ "${os_name}" == "Linux" ]]; then
            for manager in "apt-get" "dnf" "yum" "pacman" "zypper"; do
                if command_exists "${manager}"; then
                    case "${manager}" in
                        "apt-get") pkg_manager="apt"; install_cmd="apt-get install -y" ;;
                        "dnf") pkg_manager="dnf"; install_cmd="dnf install -y" ;;
                        "yum") pkg_manager="yum"; install_cmd="yum install -y" ;;
                        "pacman") pkg_manager="pacman"; install_cmd="pacman -S --noconfirm" ;;
                        "zypper") pkg_manager="zypper"; install_cmd="zypper install -y" ;;
                    esac
                    echo "${pkg_manager}" > "${CACHE_DIR}/pkg_manager"
                    echo "${install_cmd}" > "${CACHE_DIR}/install_cmd"
                    break
                fi
            done
        elif [[ "${os_name}" == "Darwin" ]]; then
            if command_exists brew; then
                pkg_manager="brew"
                install_cmd="brew install"
                echo "${pkg_manager}" > "${CACHE_DIR}/pkg_manager"
                echo "${install_cmd}" > "${CACHE_DIR}/install_cmd"
            fi
        fi

        if [[ -z "${pkg_manager}" ]]; then
            log "ERROR" "Gestionnaire de paquets non reconnu sur ce système"
            return 1
        fi
    fi

    log "INFO" "Utilisation du gestionnaire de paquets: ${pkg_manager}"

    # Mise à jour des dépôts avec cache
    if [[ ! -f "${CACHE_DIR}/repos_updated" ]]; then
        log "INFO" "Mise à jour des dépôts ${pkg_manager}..."
        case "${pkg_manager}" in
            "apt")
                sudo apt-get update &>/dev/null
                ;;
            "dnf"|"yum")
                sudo ${pkg_manager} check-update &>/dev/null || true
                ;;
            "brew")
                brew update &>/dev/null
                ;;
        esac
        touch "${CACHE_DIR}/repos_updated"
    fi

    # Installation des commandes manquantes avec parallélisation limitée
    local install_commands=()
    for cmd in "${commands[@]}"; do
        local pkg_name=$(get_package_name "${cmd}" "${pkg_manager}")

        log "INFO" "Préparation de l'installation de: ${pkg_name}"
        install_commands+=("sudo ${install_cmd} ${pkg_name} &>/dev/null")
    done

    # Exécution parallèle avec limite
    parallel_exec 2 "${install_commands[@]}"

    # Vérification post-installation
    for cmd in "${commands[@]}"; do
        if ! command_exists "${cmd}"; then
            log "ERROR" "Échec de l'installation de ${cmd}"
            success=false
        else
            log "SUCCESS" "Installation de ${cmd} réussie"
        fi
    done

    return $( [[ "${success}" == "true" ]] && echo 0 || echo 1 )
}

# Fonction pour obtenir le nom du paquet selon le gestionnaire
function get_package_name() {
    local cmd="$1"
    local pkg_manager="$2"

    case "${cmd}" in
        "jq") echo "jq" ;;
        "ansible-playbook") echo "ansible" ;;
        "kubectl")
            if [[ "${pkg_manager}" == "apt" ]]; then
                # Configuration du dépôt Kubernetes pour apt
                if [[ ! -f "${CACHE_DIR}/kubectl_repo_configured" ]]; then
                    sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
                    echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
                    sudo apt-get update
                    touch "${CACHE_DIR}/kubectl_repo_configured"
                fi
                echo "kubectl"
            elif [[ "${pkg_manager}" == "brew" ]]; then
                echo "kubernetes-cli"
            else
                echo "kubectl"
            fi
            ;;
        "helm")
            if [[ "${pkg_manager}" == "apt" ]]; then
                # Configuration du dépôt Helm pour apt
                if [[ ! -f "${CACHE_DIR}/helm_repo_configured" ]]; then
                    curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
                    echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
                    sudo apt-get update
                    touch "${CACHE_DIR}/helm_repo_configured"
                fi
                echo "helm"
            else
                echo "helm"
            fi
            ;;
        "timeout") echo "coreutils" ;;
        "nc") echo "netcat" ;;
        "ping")
            if [[ "${pkg_manager}" == "apt" ]]; then
                echo "iputils-ping"
            else
                echo "iputils"
            fi
            ;;
        "ssh"|"scp") echo "openssh-client" ;;
        *) echo "${cmd}" ;;
    esac
}

# Fonction pour extraire les informations d'inventaire avec cache
function extraire_informations_inventaire() {
    local inventory_path="${ANSIBLE_DIR}/${inventory_file}"
    local cache_file="${CACHE_DIR}/inventory_info_${inventory_file//\//_}"

    log "INFO" "Extraction des informations d'inventaire depuis ${inventory_file}..."

    # Vérification du cache
    if [[ -f "${cache_file}" && "${inventory_path}" -ot "${cache_file}" ]]; then
        log "DEBUG" "Utilisation du cache pour les informations d'inventaire"
        source "${cache_file}"
        log "INFO" "Informations d'inventaire extraites (cache):"
        log "INFO" "- Hôte: ${ansible_host}"
        log "INFO" "- Port: ${ansible_port}"
        log "INFO" "- Utilisateur: ${ansible_user}"
        return 0
    fi

    # Vérification de l'existence du fichier d'inventaire
    if [[ ! -f "${inventory_path}" ]]; then
        log "ERROR" "Fichier d'inventaire non trouvé: ${inventory_path}"
        cleanup
        exit 1
    fi

    # Extraction optimisée avec Python
    local python_script=$(cat << 'EOF'
import sys
import yaml
import json

try:
    with open(sys.argv[1], 'r') as f:
        inventory = yaml.safe_load(f)

    result = {"ansible_host": None, "ansible_port": 22, "ansible_user": None}

    # Recherche dans la structure d'inventaire
    if 'all' in inventory:
        if 'children' in inventory['all'] and 'vps' in inventory['all']['children']:
            vps_hosts = inventory['all']['children']['vps'].get('hosts', {})
            if vps_hosts:
                first_host = next(iter(vps_hosts))
                host_info = vps_hosts[first_host]
                result["ansible_host"] = host_info.get('ansible_host')
                result["ansible_port"] = host_info.get('ansible_port', 22)
                result["ansible_user"] = host_info.get('ansible_user')

        # Variables globales
        if 'vars' in inventory['all'] and not result["ansible_user"]:
            result["ansible_user"] = inventory['all']['vars'].get('ansible_user')

    # Sortie formatée pour le cache
    for key, value in result.items():
        if value:
            print(f"{key}={value}")

except Exception as e:
    print(f"error={str(e)}", file=sys.stderr)
    sys.exit(1)
EOF
)

    # Exécution avec gestion d'erreur améliorée
    local output
    if command_exists python3; then
        output=$(timeout 10 python3 -c "${python_script}" "${inventory_path}" 2>/dev/null)
    else
        # Fallback avec grep et awk
        log "WARNING" "Python3 non disponible, utilisation du fallback grep/awk"
        output="ansible_host=$(grep -A10 'hosts:' "${inventory_path}" | grep 'ansible_host:' | head -1 | awk -F': ' '{print $2}' | tr -d ' ')
ansible_port=$(grep -A10 'hosts:' "${inventory_path}" | grep 'ansible_port:' | head -1 | awk -F': ' '{print $2}' | tr -d ' ')
ansible_user=$(grep -A10 'hosts:' "${inventory_path}" | grep 'ansible_user:' | head -1 | awk -F': ' '{print $2}' | tr -d ' ')"
    fi

    # Traitement de la sortie
    eval "${output}"

    # Valeurs par défaut
    ansible_host="${ansible_host:-localhost}"
    ansible_port="${ansible_port:-22}"
    ansible_user="${ansible_user:-$(whoami)}"

    # Mise en cache
    cat > "${cache_file}" << EOF
ansible_host="${ansible_host}"
ansible_port="${ansible_port}"
ansible_user="${ansible_user}"
EOF

    log "INFO" "Informations d'inventaire extraites:"
    log "INFO" "- Hôte: ${ansible_host}"
    log "INFO" "- Port: ${ansible_port}"
    log "INFO" "- Utilisateur: ${ansible_user}"

    return 0
}

# Fonction pour exécuter une commande avec timeout et retry amélioré
function run_with_timeout() {
    local cmd="$1"
    local timeout="${2:-${TIMEOUT_SECONDS}}"
    local cmd_type="${3:-generic}"
    local max_retries=3
    local retry_count=0
    local backoff_time=5
    local interactive=false

    # Détection des commandes interactives
    if [[ "${cmd}" =~ (--(ask-become-pass|ask-pass)|[-]K|[-]k) ]]; then
        interactive=true
        log "INFO" "Commande interactive détectée"
    fi

    log "INFO" "Exécution de la commande avec timeout ${timeout}s: $(echo "${cmd}" | head -c 100)..."
    LAST_COMMAND="${cmd}"
    COMMAND_NAME="${cmd_type}"

    # Sauvegarde de l'état
    echo "${INSTALLATION_STEP}" > "${STATE_FILE}"

    # Fonction de vérification des erreurs réseau
    function is_network_error() {
        local output="$1"
        local exit_code="$2"

        [[ ${exit_code} -eq 124 || ${exit_code} -eq 255 ]] && return 0
        echo "${output}" | grep -qE "(Connection (refused|timed out|reset by peer)|Network is unreachable|Unable to connect|Temporary failure in name resolution|Could not resolve host|Network error)"
    }

    # Boucle avec retry
    while true; do
        # Vérification de la connectivité avant l'exécution pour les commandes SSH/Ansible
        if [[ "${cmd_type}" =~ (ansible_playbook|ssh) ]]; then
            if ! measure_performance "network_check" ping -c 1 -W 5 "${ansible_host}" &>/dev/null; then
                if [[ ${retry_count} -lt ${max_retries} ]]; then
                    ((retry_count++))
                    log "WARNING" "Connectivité réseau perdue avec le VPS. Tentative ${retry_count}/${max_retries} dans ${backoff_time}s..."
                    sleep ${backoff_time}
                    backoff_time=$((backoff_time * 2))
                    continue
                else
                    log "ERROR" "Connectivité réseau perdue après ${max_retries} tentatives"
                    return 1
                fi
            fi
        fi

        # Exécution de la commande
        log "DEBUG" "Début de l'exécution..."

        local exit_code=0
        local command_output=""

        # Mesure de performance
        local start_time=$(date +%s%3N)

        if [[ "${interactive}" == "true" ]]; then
            # Commandes interactives
            log "INFO" "Exécution de la commande interactive..."
            timeout ${timeout} bash -c "${cmd}"
            exit_code=$?
        else
            # Commandes non-interactives
            local temp_output=$(mktemp)
            timeout ${timeout} bash -c "${cmd}" &> "${temp_output}"
            exit_code=$?
            command_output=$(cat "${temp_output}")
            rm -f "${temp_output}"
        fi

        local end_time=$(date +%s%3N)
        local duration=$((end_time - start_time))
        PERFORMANCE_METRICS["${cmd_type}_execution"]="${duration}"

        # Logging de la sortie en mode debug
        if [[ "${debug_mode:-false}" == "true" && -n "${command_output}" ]]; then
            log "DEBUG" "Sortie de la commande:"
            echo "${command_output}" | while IFS= read -r line; do
                log "DEBUG" "  ${line}"
            done
        fi

        # Gestion des erreurs avec retry pour les erreurs réseau
        if [[ ${exit_code} -ne 0 ]]; then
            if [[ "${interactive}" == "false" && $(is_network_error "${command_output}" ${exit_code}) ]]; then
                if [[ ${retry_count} -lt ${max_retries} ]]; then
                    ((retry_count++))
                    log "WARNING" "Erreur réseau détectée (code ${exit_code}). Tentative ${retry_count}/${max_retries} dans ${backoff_time}s..."
                    sleep ${backoff_time}
                    backoff_time=$((backoff_time * 2))
                    continue
                fi
            fi

            # Analyse des erreurs
            case ${exit_code} in
                124)
                    log "ERROR" "Timeout atteint (${timeout}s)"
                    ;;
                *)
                    log "ERROR" "Commande échouée avec le code ${exit_code}"

                    # Diagnostic spécifique pour les commandes non-interactives
                    if [[ "${interactive}" == "false" && -n "${command_output}" ]]; then
                        case "${command_output}" in
                            *"Connection refused"*)
                                log "ERROR" "Service non accessible"
                                ;;
                            *"Permission denied"*)
                                log "ERROR" "Permissions insuffisantes"
                                ;;
                            *"No space left on device"*)
                                log "ERROR" "Espace disque insuffisant"
                                ;;
                            *"Unable to connect to the server"*)
                                log "ERROR" "Serveur Kubernetes inaccessible"
                                ;;
                        esac
                    fi
                    ;;
            esac

            return ${exit_code}
        fi

        # Succès
        if [[ ${retry_count} -gt 0 ]]; then
            log "SUCCESS" "Commande réussie après ${retry_count} tentatives"
        else
            log "DEBUG" "Commande réussie"
        fi

        return 0
    done
}

# Fonction pour vérifier les ressources système (optimisée)
function check_system_resources() {
    local system_type="$1"  # "local" ou "vps"
    local host="${ansible_host:-localhost}"

    log "INFO" "Vérification des ressources ${system_type}..."

    # Fonction pour exécuter des commandes selon le système
    function exec_command() {
        local cmd="$1"
        if [[ "${system_type}" == "local" ]]; then
            eval "${cmd}"
        else
            ssh_exec "${cmd}" false 5
        fi
    }

    # Vérification des ressources en parallèle
    local checks=(
        "memory_check"
        "disk_check"
        "cpu_check"
    )

    for check in "${checks[@]}"; do
        case "${check}" in
            "memory_check")
                local memory_info=$(exec_command "free -m")
                local total_memory=$(echo "${memory_info}" | awk '/^Mem:/ {print $2}')
                local available_memory=$(echo "${memory_info}" | awk '/^Mem:/ {print $7}')

                log "INFO" "Mémoire ${system_type}: ${available_memory}MB disponible sur ${total_memory}MB total"

                # Seuils adaptés selon le système
                local min_memory=$( [[ "${system_type}" == "local" ]] && echo 1024 || echo 2048 )

                if [[ ${available_memory} -lt ${min_memory} ]]; then
                    log "WARNING" "Mémoire ${system_type} insuffisante: ${available_memory}MB (minimum: ${min_memory}MB)"
                fi
                ;;

            "disk_check")
                local disk_info=$(exec_command "df -m /")
                local available_disk=$(echo "${disk_info}" | awk 'NR==2 {print $4}')

                log "INFO" "Espace disque ${system_type}: ${available_disk}MB disponible"

                if [[ ${available_disk} -lt ${REQUIRED_SPACE_MB} ]]; then
                    log "ERROR" "Espace disque ${system_type} insuffisant: ${available_disk}MB (minimum: ${REQUIRED_SPACE_MB}MB)"
                    return 1
                fi
                ;;

            "cpu_check")
                local cpu_count=$(exec_command "nproc --all")
                local cpu_load=$(exec_command "cat /proc/loadavg | awk '{print \$1}'")

                log "INFO" "CPU ${system_type}: ${cpu_count} cœurs, charge: ${cpu_load}"

                if [[ ${cpu_count} -lt 2 ]]; then
                    log "WARNING" "Nombre de cœurs ${system_type} insuffisant: ${cpu_count}"
                fi

                # Vérification de la charge CPU
                if (( $(echo "${cpu_load} > ${cpu_count}" | bc -l) )); then
                    log "WARNING" "Charge CPU ${system_type} élevée: ${cpu_load}"
                fi
                ;;
        esac
    done &

    wait

    log "SUCCESS" "Vérification des ressources ${system_type} terminée"
    return 0
}

# Fonction optimisée pour vérifier la connectivité réseau
function check_network() {
    local target_host="${ansible_host}"
    local target_port="${ansible_port}"
    local retry_count=3
    local timeout=5

    log "INFO" "Vérification de la connectivité réseau vers ${target_host}:${target_port}"

    # Vérifications en parallèle
    declare -A network_checks
    network_checks["dns"]=""
    network_checks["icmp"]=""
    network_checks["tcp"]=""

    # Résolution DNS
    if [[ ! "${target_host}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        for ((i=1; i<=retry_count; i++)); do
            if resolved_ip=$(dig +short "${target_host}" 2>/dev/null) && [[ -n "${resolved_ip}" ]]; then
                network_checks["dns"]="OK - ${target_host} -> ${resolved_ip}"
                break
            else
                if [[ ${i} -eq ${retry_count} ]]; then
                    network_checks["dns"]="FAILED - Unable to resolve ${target_host}"
                fi
                sleep 2
            fi
        done
    else
        network_checks["dns"]="SKIPPED - IP address used"
    fi

    # Test ICMP en parallèle
    {
        for ((i=1; i<=retry_count; i++)); do
            if ping -c 1 -W ${timeout} "${target_host}" &>/dev/null; then
                network_checks["icmp"]="OK"
                break
            else
                if [[ ${i} -eq ${retry_count} ]]; then
                    network_checks["icmp"]="FAILED"
                fi
                sleep 1
            fi
        done
    } &

    # Test TCP en parallèle
    {
        for ((i=1; i<=retry_count; i++)); do
            if nc -z -w ${timeout} "${target_host}" "${target_port}" &>/dev/null; then
                network_checks["tcp"]="OK"
                break
            else
                if [[ ${i} -eq ${retry_count} ]]; then
                    network_checks["tcp"]="FAILED"
                fi
                sleep 1
            fi
        done
    } &

    wait

    # Vérification des ports requis en parallèle
    declare -a port_checks=()
    for port in "${REQUIRED_PORTS[@]}"; do
        {
            if nc -z -w ${timeout} "${target_host}" "${port}" &>/dev/null; then
                port_checks[${port}]="OK"
            else
                port_checks[${port}]="FAILED"
            fi
        } &
    done

    wait

    # Rapport des résultats
    log "INFO" "Résultats des vérifications réseau:"
    log "INFO" "  - DNS: ${network_checks["dns"]}"
    log "INFO" "  - ICMP: ${network_checks["icmp"]}"
    log "INFO" "  - TCP SSH: ${network_checks["tcp"]}"

    # Vérification des ports
    local failed_ports=()
    for port in "${REQUIRED_PORTS[@]}"; do
        if [[ "${port_checks[${port}]}" == "FAILED" ]]; then
            failed_ports+=("${port}")
        fi
    done

    if [[ ${#failed_ports[@]} -gt 0 ]]; then
        log "WARNING" "Ports fermés: ${failed_ports[*]}"

        # Proposition d'ouverture automatique
        log "INFO" "Souhaitez-vous ouvrir automatiquement ces ports? (o/N)"
        read -r answer
        if [[ "${answer}" =~ ^[Oo]$ ]]; then
            open_required_ports "${failed_ports[@]}"
        fi
    fi

    # Vérification du port SSH (critique)
    if [[ "${network_checks["tcp"]}" == "FAILED" ]]; then
        log "ERROR" "Port SSH (${target_port}) inaccessible - impossible de continuer"
        return 1
    fi

    log "SUCCESS" "Vérification de la connectivité réseau terminée"
    return 0
}

# Fonction améliorée pour sauvegarder l'état
function backup_state() {
    local backup_name="${1:-backup-$(date +%Y%m%d-%H%M%S)}"
    local optional="${2:-false}"
    local backup_file="${BACKUP_DIR}/${backup_name}.tar.gz"
    local metadata_file="${BACKUP_DIR}/${backup_name}.json"

    log "INFO" "Sauvegarde de l'état actuel dans ${backup_file}..."

    # Création des métadonnées détaillées
    cat > "${metadata_file}" << EOF
{
  "backup_name": "${backup_name}",
  "backup_date": "$(date -Iseconds)",
  "environment": "${environment}",
  "installation_step": "${INSTALLATION_STEP}",
  "ansible_host": "${ansible_host}",
  "ansible_port": "${ansible_port}",
  "ansible_user": "${ansible_user}",
  "script_version": "1.2.0",
  "description": "Sauvegarde automatique avant l'étape ${INSTALLATION_STEP}",
  "performance_metrics": $(echo "${PERFORMANCE_METRICS[@]}" | jq -R -s -c 'split(" ") | map(select(length > 0))')
}
EOF

    # Liste des répertoires à sauvegarder avec priorités
    local backup_items=(
        "/etc/rancher:high"
        "/var/lib/rancher/k3s/server/manifests:high"
        "/home/${ansible_user}/.kube:medium"
        "/etc/systemd/system/k3s.service:medium"
        "/var/log/lions:low"
    )

    # Patterns d'exclusion optimisés
    local exclude_args=(
        "--exclude=*.log"
        "--exclude=*.tmp"
        "--exclude=*.swp"
        "--exclude=*/cache/*"
        "--exclude=*/temp/*"
    )

    # Vérification de l'existence des répertoires de manière optimisée
    local existing_items=()
    local total_size=0

    for item in "${backup_items[@]}"; do
        local path="${item%%:*}"
        local priority="${item##*:}"

        # Vérification en parallèle
        {
            if ssh_exec "sudo test -d ${path}" false 5; then
                local size=$(ssh_exec "sudo du -s ${path} | awk '{print \$1}'" false 5)
                existing_items+=("${path}:${priority}:${size}")
                ((total_size+=size))
            fi
        } &
    done

    wait

    # Tri des items par priorité et taille
    IFS=$'\n' sorted_items=($(sort -t: -k2,2r -k3,3nr <<<"${existing_items[*]}"))
    unset IFS

    # Construction de la commande de sauvegarde optimisée
    local backup_cmd="sudo tar ${exclude_args[*]} -czf /tmp/${backup_name}.tar.gz"
    for item in "${sorted_items[@]}"; do
        backup_cmd="${backup_cmd} ${item%%:*}"
    done

    # Ajout d'informations complémentaires
    backup_cmd="${backup_cmd} && sudo tar -rf /tmp/${backup_name}.tar.gz --transform 's,^,metadata/,' ${metadata_file}"

    # Estimation du temps de sauvegarde
    local estimated_time=$((total_size / 1000 / 10))  # ~10MB/s
    log "INFO" "Estimation: ~${estimated_time}s pour ${total_size}KB"

    # Exécution de la sauvegarde avec barre de progression
    if measure_performance "backup_create" ssh_exec "${backup_cmd}" false 120; then
        # Transfert du fichier avec optimisation
        log "INFO" "Transfert du fichier de sauvegarde..."

        if measure_performance "backup_transfer" scp -C -P "${ansible_port}" \
           "${ansible_user}@${ansible_host}:/tmp/${backup_name}.tar.gz" "${backup_file}" 2>/dev/null; then

            # Vérification de l'intégrité
            local local_checksum=$(sha256sum "${backup_file}" | awk '{print $1}')
            local remote_checksum=$(ssh_exec "sha256sum /tmp/${backup_name}.tar.gz" false 5 | awk '{print $1}')

            if [[ "${local_checksum}" == "${remote_checksum}" ]]; then
                log "SUCCESS" "Sauvegarde créée et vérifiée: ${backup_file}"

                # Nettoyage du fichier temporaire
                ssh_exec "sudo rm -f /tmp/${backup_name}.tar.gz" false 5

                # Ajout de la taille du fichier aux métadonnées
                local backup_size=$(du -h "${backup_file}" | awk '{print $1}')
                jq ".backup_size = \"${backup_size}\"" "${metadata_file}" > "${metadata_file}.tmp" && mv "${metadata_file}.tmp" "${metadata_file}"

                # Nettoyage des anciennes sauvegardes (garder les 10 plus récentes)
                local old_backups=($(ls -t "${BACKUP_DIR}"/*.tar.gz 2>/dev/null | tail -n +11))
                if [[ ${#old_backups[@]} -gt 0 ]]; then
                    for old_backup in "${old_backups[@]}"; do
                        rm -f "${old_backup}" "${old_backup%.tar.gz}.json"
                    done
                    log "INFO" "Nettoyage de ${#old_backups[@]} anciennes sauvegardes"
                fi

                echo "${backup_name}" > "${BACKUP_DIR}/.last_backup"
                return 0
            else
                log "ERROR" "Corruption détectée lors du transfert"
            fi
        fi
    fi

    # Nettoyage en cas d'erreur
    ssh_exec "sudo rm -f /tmp/${backup_name}.tar.gz" false 5
    rm -f "${backup_file}" "${metadata_file}"

    if [[ "${optional}" == "true" ]]; then
        log "WARNING" "Sauvegarde optionnelle échouée, continuation"
        return 0
    else
        return 1
    fi
}

# Fonction de vérification des prérequis (optimisée)
function verifier_prerequis() {
    log "STEP" "Vérification des prérequis..."
    INSTALLATION_STEP="prerequis"

    # Gestion du verrouillage avec PID
    if [[ -f "${LOCK_FILE}" ]]; then
        local lock_pid=$(cat "${LOCK_FILE}" 2>/dev/null || echo "")

        if [[ -n "${lock_pid}" ]] && kill -0 "${lock_pid}" 2>/dev/null; then
            log "ERROR" "Une autre instance est en cours d'exécution (PID: ${lock_pid})"
            exit 1
        else
            log "INFO" "Fichier de verrouillage obsolète, suppression"
            sudo rm -f "${LOCK_FILE}" 2>/dev/null || rm -f "${LOCK_FILE}"
        fi
    fi

    # Création du fichier de verrouillage avec PID
    echo $$ > "${LOCK_FILE}"

    # Vérifications système locales
    check_system_resources "local"

    # Vérification des commandes requises avec versions
    local required_commands=(
        "ansible-playbook:2.9.0"
        "ssh:7.0"
        "kubectl:1.20.0"
        "helm:3.5.0"
        "jq:1.6"
        "timeout"
        "nc"
        "ping"
    )

    local missing_commands=()
    for cmd_spec in "${required_commands[@]}"; do
        local cmd="${cmd_spec%%:*}"
        if ! command_exists "${cmd}"; then
            missing_commands+=("${cmd}")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log "WARNING" "Commandes manquantes: ${missing_commands[*]}"
        install_missing_commands "${missing_commands[@]}"
    fi

    # Extraction des informations d'inventaire avec cache
    extraire_informations_inventaire

    # Configuration de la connexion SSH persistante
    setup_ssh_connection

    # Vérification de la connectivité réseau
    check_network

    # Vérification des ressources du VPS
    check_system_resources "vps"

    # Gestion de la reprise
    if [[ -f "${STATE_FILE}" ]]; then
        local previous_step=$(cat "${STATE_FILE}")
        log "INFO" "État précédent détecté: ${previous_step}"
        log "INFO" "Voulez-vous reprendre à partir de cette étape? (o/N)"

        read -r answer
        if [[ "${answer}" =~ ^[Oo]$ ]]; then
            log "INFO" "Reprise à partir de l'étape: ${previous_step}"
            resume_installation "${previous_step}"
        else
            log "INFO" "Nouvelle installation"
            rm -f "${STATE_FILE}"
        fi
    fi

    log "SUCCESS" "Prérequis vérifiés avec succès"
}

# Fonction pour reprendre l'installation
function resume_installation() {
    local step="$1"

    case "${step}" in
        "init_vps")
            initialiser_vps
            installer_k3s
            deployer_infrastructure_base
            deployer_monitoring
            verifier_installation
            ;;
        "install_k3s")
            installer_k3s
            deployer_infrastructure_base
            deployer_monitoring
            verifier_installation
            ;;
        "deploy_infra")
            deployer_infrastructure_base
            deployer_monitoring
            verifier_installation
            ;;
        "deploy_monitoring")
            deployer_monitoring
            verifier_installation
            ;;
        "deploy_services")
            deployer_services_infrastructure
            verifier_installation
            ;;
        "verify")
            verifier_installation
            ;;
        *)
            log "WARNING" "Étape inconnue: ${step}, reprise depuis le début"
            ;;
    esac

    exit 0
}

# Fonction d'initialisation du VPS (optimisée)
function initialiser_vps() {
    log "STEP" "Initialisation du VPS..."
    INSTALLATION_STEP="init_vps"
    echo "${INSTALLATION_STEP}" > "${STATE_FILE}"

    # Sauvegarde de l'état actuel
    backup_state "pre-init-vps" "true"

    # Construction et exécution de la commande Ansible
    local ansible_cmd="ansible-playbook -i ${ANSIBLE_DIR}/${inventory_file} ${ANSIBLE_DIR}/playbooks/init-vps.yml --ask-become-pass"

    [[ "${debug_mode:-false}" == "true" ]] && ansible_cmd="${ansible_cmd} -vvv"

    log "INFO" "Exécution: ${ansible_cmd}"
    LAST_COMMAND="${ansible_cmd}"

    if measure_performance "vps_init" run_with_timeout "${ansible_cmd}" "${TIMEOUT_SECONDS}" "ansible_playbook"; then
        log "SUCCESS" "Initialisation du VPS terminée avec succès"

        # Vérification post-installation
        local services_to_check=("sshd" "fail2ban" "ufw")
        local failed_services=()

        for service in "${services_to_check[@]}"; do
            if ! ssh_exec "sudo systemctl is-active --quiet ${service}" false 5; then
                failed_services+=("${service}")
            fi
        done

        if [[ ${#failed_services[@]} -gt 0 ]]; then
            log "WARNING" "Services non actifs: ${failed_services[*]}"
        else
            log "SUCCESS" "Tous les services essentiels sont actifs"
        fi
    else
        log "ERROR" "Échec de l'initialisation du VPS"
        collect_logs
        exit 1
    fi
}

# Fonction d'installation de K3s (optimisée)
function installer_k3s() {
    log "STEP" "Installation de K3s..."
    INSTALLATION_STEP="install_k3s"
    echo "${INSTALLATION_STEP}" > "${STATE_FILE}"

    # Sauvegarde de l'état actuel
    backup_state "pre-install-k3s" "true"

    # Construction et exécution de la commande Ansible
    local ansible_cmd="ansible-playbook -i ${ANSIBLE_DIR}/${inventory_file} ${ANSIBLE_DIR}/playbooks/install-k3s.yml --ask-become-pass"

    [[ "${debug_mode:-false}" == "true" ]] && ansible_cmd="${ansible_cmd} -vvv"

    log "INFO" "Exécution: ${ansible_cmd}"
    LAST_COMMAND="${ansible_cmd}"

    if measure_performance "k3s_install" run_with_timeout "${ansible_cmd}" 3600 "ansible_playbook"; then
        log "SUCCESS" "Installation de K3s terminée avec succès"

        # Vérification de K3s
        if ssh_exec "sudo systemctl is-active --quiet k3s" false 5; then
            log "SUCCESS" "Service K3s actif"

            # Récupération du kubeconfig si nécessaire
            local kubeconfig_dir="${HOME}/.kube"
            mkdir -p "${kubeconfig_dir}"

            if ! kubectl cluster-info &>/dev/null; then
                log "INFO" "Récupération du fichier kubeconfig..."
                if scp -C -P "${ansible_port}" "${ansible_user}@${ansible_host}:/home/${ansible_user}/.kube/config" "${kubeconfig_dir}/config.k3s" &>/dev/null; then
                    export KUBECONFIG="${kubeconfig_dir}/config.k3s"
                    log "SUCCESS" "Kubeconfig configuré"
                else
                    log "WARNING" "Impossible de récupérer le kubeconfig"
                fi
            fi
        else
            log "ERROR" "Service K3s inactif"
            ssh_exec "sudo journalctl -u k3s --no-pager -n 50"
            exit 1
        fi
    else
        log "ERROR" "Échec de l'installation de K3s"
        collect_logs
        exit 1
    fi
}

# Fonction de déploiement de l'infrastructure de base (optimisée)
function deployer_infrastructure_base() {
    log "STEP" "Déploiement de l'infrastructure de base..."
    INSTALLATION_STEP="deploy_infra"
    echo "${INSTALLATION_STEP}" > "${STATE_FILE}"

    # Vérification de l'accès à Kubernetes
    if ! kubectl cluster-info &>/dev/null; then
        log "ERROR" "Impossible d'accéder au cluster Kubernetes"
        exit 1
    fi

    # Création du namespace
    kubectl create namespace lions-infrastructure --dry-run=client -o yaml | kubectl apply -f - || true

    # Validation et application de kustomize
    log "INFO" "Validation de la configuration kustomize..."
    if kubectl kustomize "${PROJECT_ROOT}/kubernetes/overlays/${environment}" > /dev/null; then
        log "INFO" "Déploiement des ressources..."

        if measure_performance "infra_deploy" kubectl apply -k "${PROJECT_ROOT}/kubernetes/overlays/${environment}" --timeout=5m; then
            log "SUCCESS" "Infrastructure de base déployée"

            # Vérification des ressources essentielles
            local essential_resources=(
                "namespace/${environment}"
                "resourcequota/compute-resources"
                "networkpolicy/default-network-policy"
            )

            for resource in "${essential_resources[@]}"; do
                if kubectl get "${resource}" &>/dev/null; then
                    log "SUCCESS" "Ressource ${resource} créée"
                else
                    log "WARNING" "Ressource ${resource} manquante"
                fi
            done
        else
            log "ERROR" "Échec du déploiement de l'infrastructure"
            exit 1
        fi
    else
        log "ERROR" "Configuration kustomize invalide"
        exit 1
    fi
}

# Fonction de déploiement du monitoring (optimisée)
function deployer_monitoring() {
    log "STEP" "Déploiement du système de monitoring..."
    INSTALLATION_STEP="deploy_monitoring"
    echo "${INSTALLATION_STEP}" > "${STATE_FILE}"

    # Création du namespace monitoring
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - || true

    # Ajout du dépôt Helm
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
    helm repo update

    # Configuration Prometheus optimisée
    local values_file="${CACHE_DIR}/prometheus-values.yaml"
    cat > "${values_file}" << EOF
grafana:
  adminPassword: admin
  service:
    type: NodePort
    nodePort: 30000
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 200m
      memory: 512Mi
  persistence:
    enabled: true
    size: 2Gi

prometheus:
  prometheusSpec:
    retention: 15d
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 500m
        memory: 1Gi
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi

alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        cpu: 50m
        memory: 128Mi
      limits:
        cpu: 100m
        memory: 256Mi
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 2Gi
EOF

    # Déploiement de Prometheus
    log "INFO" "Déploiement de Prometheus/Grafana..."

    if measure_performance "monitoring_deploy" helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
       --namespace monitoring \
       --values "${values_file}" \
       --timeout=20m \
       --atomic; then

        log "SUCCESS" "Monitoring déployé avec succès"

        # Attente que les pods soient prêts avec timeout
        log "INFO" "Attente que les pods soient prêts..."

        if kubectl wait --for=condition=Ready pod -l app=prometheus -n monitoring --timeout=300s && \
           kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=300s; then

            # Récupération des informations d'accès
            local grafana_port=$(kubectl get service -n monitoring prometheus-grafana -o jsonpath='{.spec.ports[0].nodePort}')

            log "SUCCESS" "Monitoring prêt"
            log "INFO" "Grafana: http://${ansible_host}:${grafana_port} (admin/admin)"
        else
            log "WARNING" "Certains pods ne sont pas prêts, mais le déploiement est terminé"
        fi
    else
        log "ERROR" "Échec du déploiement du monitoring"
        exit 1
    fi
}

# Fonction de déploiement des services infrastructure (optimisée)
function deployer_services_infrastructure() {
    log "STEP" "Déploiement des services d'infrastructure..."
    INSTALLATION_STEP="deploy_services"
    echo "${INSTALLATION_STEP}" > "${STATE_FILE}"

    # Construction et exécution de la commande Ansible
    local ansible_cmd="ansible-playbook ${ANSIBLE_DIR}/playbooks/deploy-infrastructure-services.yml --extra-vars \"environment=${environment}\" --ask-become-pass"

    [[ "${debug_mode:-false}" == "true" ]] && ansible_cmd="${ansible_cmd} -vvv"

    log "INFO" "Exécution: ${ansible_cmd}"
    LAST_COMMAND="${ansible_cmd}"

    if measure_performance "services_deploy" run_with_timeout "${ansible_cmd}" 1800 "ansible_playbook"; then
        log "SUCCESS" "Services d'infrastructure déployés"
    else
        log "WARNING" "Échec partiel du déploiement des services"
        log "INFO" "Vous pouvez les déployer manuellement plus tard avec:"
        log "INFO" "${ansible_cmd}"
    fi
}

# Fonction de vérification finale (optimisée)
function verifier_installation() {
    log "STEP" "Vérification de l'installation..."
    INSTALLATION_STEP="verify"

    # Vérification des nœuds
    log "INFO" "Vérification des nœuds Kubernetes..."
    local nodes_status=$(kubectl get nodes -o wide 2>&1)

    if echo "${nodes_status}" | grep -q "Ready"; then
        log "SUCCESS" "Nœuds Kubernetes opérationnels"
    else
        log "WARNING" "Problèmes détectés sur les nœuds"
    fi

    # Vérification des namespaces
    local required_namespaces=("kube-system" "lions-infrastructure" "${environment}" "monitoring")
    local missing_namespaces=()

    for ns in "${required_namespaces[@]}"; do
        if ! kubectl get namespace "${ns}" &>/dev/null; then
            missing_namespaces+=("${ns}")
        fi
    done

    if [[ ${#missing_namespaces[@]} -eq 0 ]]; then
        log "SUCCESS" "Tous les namespaces requis sont présents"
    else
        log "WARNING" "Namespaces manquants: ${missing_namespaces[*]}"
    fi

    # Vérification des pods en parallèle
    declare -A pod_stats
    pod_stats["total"]=0
    pod_stats["running"]=0
    pod_stats["failed"]=0

    # Comptage des pods par statut
    while IFS= read -r line; do
        ((pod_stats["total"]++))
        if echo "${line}" | grep -q "Running"; then
            ((pod_stats["running"]++))
        elif echo "${line}" | grep -qE "Error|CrashLoopBackOff|ImagePullBackOff"; then
            ((pod_stats["failed"]++))
        fi
    done < <(kubectl get pods --all-namespaces --no-headers)

    log "INFO" "Statistiques des pods: ${pod_stats["running"]}/${pod_stats["total"]} en cours d'exécution"

    if [[ ${pod_stats["failed"]} -gt 0 ]]; then
        log "WARNING" "${pod_stats["failed"]} pods en erreur détectés"
    fi

    # Vérification des services exposés
    local service_checks=(
        "http://${ansible_host}:30000|Grafana"
        "https://${ansible_host}:30001|Kubernetes Dashboard"
    )

    for service in "${service_checks[@]}"; do
        local url="${service%%|*}"
        local name="${service##*|}"

        if curl -s --connect-timeout 5 "${url}" | grep -q "200\|302"; then
            log "SUCCESS" "${name} accessible"
        else
            log "WARNING" "${name} non accessible"
        fi
    done &

    wait

    # Génération du rapport final
    local report_file="${LOG_DIR}/verification-report-$(date +%Y%m%d-%H%M%S).txt"
    generate_verification_report "${report_file}"

    log "SUCCESS" "Vérification terminée - Rapport: ${report_file}"

    # Nettoyage final
    rm -f "${STATE_FILE}"
}

# Fonction de génération du rapport de vérification
function generate_verification_report() {
    local report_file="$1"

    {
        echo "=== RAPPORT DE VÉRIFICATION DE L'INFRASTRUCTURE LIONS ==="
        echo "Date: $(date)"
        echo "Environnement: ${environment}"
        echo "Durée d'installation: $(($(date +%s) - START_TIME)) secondes"
        echo ""

        echo "=== MÉTRIQUES DE PERFORMANCE ==="
        for key in "${!PERFORMANCE_METRICS[@]}"; do
            echo "- ${key}: ${PERFORMANCE_METRICS[${key}]}ms"
        done
        echo ""

        echo "=== RÉSUMÉ DES COMPOSANTS ==="
        kubectl get nodes -o wide
        echo ""

        echo "=== PODS PAR NAMESPACE ==="
        kubectl get pods --all-namespaces -o wide
        echo ""

        echo "=== SERVICES EXPOSÉS ==="
        kubectl get services --all-namespaces -o wide | grep NodePort
        echo ""

        echo "=== ÉTAT DE SANTÉ GLOBAL ==="
        local health_score=$(kubectl get pods --all-namespaces -o json | jq '[.items[] | select(.status.phase=="Running")] | length')
        local total_pods=$(kubectl get pods --all-namespaces -o json | jq '.items | length')
        local health_percentage=$((health_score * 100 / total_pods))

        echo "Score de santé: ${health_percentage}% (${health_score}/${total_pods} pods en cours d'exécution)"

        if [[ ${health_percentage} -ge 90 ]]; then
            echo "✅ Infrastructure en excellent état"
        elif [[ ${health_percentage} -ge 70 ]]; then
            echo "⚠️ Infrastructure opérationnelle avec problèmes mineurs"
        else
            echo "❌ Infrastructure nécessite une attention immédiate"
        fi

        echo ""
        echo "=== INFORMATIONS D'ACCÈS ==="
        echo "Grafana: http://${ansible_host}:30000 (admin/admin)"
        echo "Kubernetes Dashboard: https://${ansible_host}:30001"
        echo ""

        echo "=== FIN DU RAPPORT ==="
    } > "${report_file}"
}

# Fonction pour collecter les logs de manière optimisée
function collect_logs() {
    local output_dir="${LOG_DIR}/diagnostic-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${output_dir}"

    log "INFO" "Collecte optimisée des logs pour diagnostic..."

    # Collecte en parallèle
    {
        # Logs locaux
        cp "${LOG_FILE}" "${output_dir}/install.log"
        uname -a > "${output_dir}/local_system.log"
        df -h > "${output_dir}/local_disk.log"

        # Logs Kubernetes
        if command_exists kubectl; then
            kubectl get all --all-namespaces > "${output_dir}/k8s_all_resources.log"
            kubectl get events --all-namespaces --sort-by='.lastTimestamp' > "${output_dir}/k8s_events.log"

            # Logs des pods problématiques
            kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.status.phase!="Running") | "\(.metadata.namespace) \(.metadata.name)"' | while read -r ns pod; do
                kubectl logs -n "${ns}" "${pod}" --tail=50 > "${output_dir}/pod_${ns}_${pod}.log" 2>/dev/null || true
            done
        fi
    } &

    {
        # Logs du VPS
        if [[ -n "${ansible_host}" ]]; then
            ssh_exec "sudo journalctl -u k3s --no-pager -n 100" false 10 > "${output_dir}/vps_k3s.log"
            ssh_exec "sudo systemctl status k3s" false 10 > "${output_dir}/vps_k3s_status.log"
            ssh_exec "free -m" false 10 > "${output_dir}/vps_memory.log"
            ssh_exec "df -h" false 10 > "${output_dir}/vps_disk.log"
        fi
    } &

    wait

    # Compression avec optimisation
    local archive_file="${LOG_DIR}/diagnostic-$(date +%Y%m%d-%H%M%S).tar.gz"
    tar -czf "${archive_file}" -C "$(dirname "${output_dir}")" "$(basename "${output_dir}")"
    rm -rf "${output_dir}"

    log "SUCCESS" "Logs collectés: ${archive_file}"
}

# Gestion des erreurs améliorée
function handle_error() {
    local exit_code=$?
    local line_number=$1
    local command_name=${2:-unknown}

    # Désactivation temporaire du mode strict
    set +euo pipefail

    log "ERROR" "Erreur à la ligne ${line_number} (code ${exit_code})"
    log "ERROR" "Commande: ${LAST_COMMAND}"

    # Diagnostic de l'erreur
    case ${exit_code} in
        1)   log "ERROR" "Erreur générale" ;;
        2)   log "ERROR" "Erreur de syntaxe" ;;
        126) log "ERROR" "Permission refusée" ;;
        127) log "ERROR" "Commande non trouvée" ;;
        137) log "ERROR" "Processus terminé (manque de mémoire?)" ;;
        *)   log "ERROR" "Code d'erreur: ${exit_code}" ;;
    esac

    # Sauvegarde de l'état d'erreur
    LAST_ERROR="Ligne ${line_number}: ${LAST_COMMAND} (code ${exit_code})"
    echo "${INSTALLATION_STEP}" > "${STATE_FILE}"
    cp "${LOG_FILE}" "${BACKUP_DIR}/error-$(date +%Y%m%d-%H%M%S).log"

    # Collecte automatique des logs
    collect_logs

    # Tentative de reprise pour certaines erreurs
    if [[ ${RETRY_COUNT} -lt ${MAX_RETRIES} && ${exit_code} -ne 2 ]]; then
        ((RETRY_COUNT++))
        log "WARNING" "Tentative ${RETRY_COUNT}/${MAX_RETRIES} de reprise..."
        sleep $((RETRY_COUNT * 5))

        # Tentative de reprise selon le contexte
        case "${command_name}" in
            "ansible_playbook")
                # Reprise avec des options plus sûres
                LAST_COMMAND="${LAST_COMMAND} --forks=1 --timeout=60"
                eval "${LAST_COMMAND}"
                ;;
            "kubectl_apply")
                # Reprise avec validation désactivée
                LAST_COMMAND="${LAST_COMMAND} --validate=false"
                eval "${LAST_COMMAND}"
                ;;
            *)
                # Reprise standard de la fonction
                case "${INSTALLATION_STEP}" in
                    "init_vps") initialiser_vps ;;
                    "install_k3s") installer_k3s ;;
                    "deploy_infra") deployer_infrastructure_base ;;
                    "deploy_monitoring") deployer_monitoring ;;
                    "deploy_services") deployer_services_infrastructure ;;
                    "verify") verifier_installation ;;
                esac
                ;;
        esac
    else
        log "ERROR" "Nombre maximum de tentatives atteint"
        log "INFO" "Rapport de diagnostic généré. Consultez ${LOG_DIR} pour plus de détails."

        # Génération du rapport de diagnostic final
        generate_diagnostic_report

        cleanup
        exit ${exit_code}
    fi

    # Réactivation du mode strict
    set -euo pipefail
}

# Fonction de génération du rapport de diagnostic
function generate_diagnostic_report() {
    local report_file="${BACKUP_DIR}/diagnostic-$(date +%Y%m%d-%H%M%S).txt"

    {
        echo "=== RAPPORT DE DIAGNOSTIC LIONS INFRASTRUCTURE ==="
        echo "Date: $(date)"
        echo "Environnement: ${environment}"
        echo "Étape d'échec: ${INSTALLATION_STEP}"
        echo "Erreur: ${LAST_ERROR}"
        echo ""

        echo "=== MÉTRIQUES DE PERFORMANCE ==="
        for key in "${!PERFORMANCE_METRICS[@]}"; do
            echo "- ${key}: ${PERFORMANCE_METRICS[${key}]}ms"
        done
        echo ""

        echo "=== RECOMMANDATIONS ==="
        case "${INSTALLATION_STEP}" in
            "init_vps")
                echo "1. Vérifiez la connectivité SSH"
                echo "2. Vérifiez les droits sudo de l'utilisateur"
                echo "3. Vérifiez les ressources système du VPS"
                ;;
            "install_k3s")
                echo "1. Vérifiez l'espace disque disponible"
                echo "2. Vérifiez la mémoire disponible (minimum 2GB)"
                echo "3. Vérifiez les ports kubernetes (6443, 10250)"
                ;;
            "deploy_infra")
                echo "1. Vérifiez le fichier kubeconfig"
                echo "2. Vérifiez les ressources kubernetes"
                echo "3. Vérifiez les permissions RBAC"
                ;;
            "deploy_monitoring")
                echo "1. Vérifiez l'installation de Helm"
                echo "2. Vérifiez l'espace de stockage disponible"
                echo "3. Vérifiez les ressources pods"
                ;;
        esac
        echo ""

        echo "=== FIN DU RAPPORT ==="
    } > "${report_file}"

    log "SUCCESS" "Rapport de diagnostic: ${report_file}"
}

# Fonction d'affichage de l'aide
function afficher_aide() {
    cat << EOF
Script d'Installation de l'Infrastructure LIONS sur VPS (v1.2.0)

Ce script orchestre l'installation complète de l'infrastructure LIONS sur un VPS.

Usage:
    $0 [options]

Options:
    -e, --environment <env>   Environnement cible (production, staging, development)
                             Par défaut: development
    -i, --inventory <file>    Fichier d'inventaire Ansible spécifique
                             Par défaut: inventories/<environment>/hosts.yml
    -s, --skip-init           Ignorer l'initialisation du VPS (si déjà effectuée)
    -d, --debug               Active le mode debug
    -t, --test                Execute les tests de robustesse
    -h, --help                Affiche cette aide

Exemples:
    $0                                   # Installation standard
    $0 --environment staging             # Installation pour l'environnement staging
    $0 --skip-init --debug              # Reprise avec debug activé
    $0 --test                           # Tests de robustesse

Notes:
    - Les logs sont stockés dans ${LOG_DIR}
    - Les sauvegardes automatiques sont créées dans ${BACKUP_DIR}
    - Le script peut être repris après une interruption
EOF
}

# Fonction de test de robustesse optimisée
function test_robustesse() {
    log "STEP" "Tests de robustesse de l'infrastructure..."

    # Série de tests avec mesure de performance
    local tests=(
        "test_ssh_robustesse"
        "test_kubectl_robustesse"
        "test_timeout_robustesse"
        "test_network_robustesse"
        "test_backup_robustesse"
    )

    local passed=0
    local failed=0

    for test in "${tests[@]}"; do
        log "INFO" "Exécution du test: ${test}"

        if measure_performance "${test}" ${test}; then
            ((passed++))
            log "SUCCESS" "Test ${test} réussi"
        else
            ((failed++))
            log "ERROR" "Test ${test} échoué"
        fi
    done

    log "INFO" "Tests terminés: ${passed} réussi(s), ${failed} échoué(s)"
    return $((failed > 0 ? 1 : 0))
}

# Tests de robustesse individuels
function test_ssh_robustesse() {
    local original_host="${ansible_host}"
    ansible_host="invalid.host.example.com"

    # Le test doit échouer
    if ! ssh_exec "echo test" false 5 &>/dev/null; then
        ansible_host="${original_host}"
        return 0
    else
        ansible_host="${original_host}"
        return 1
    fi
}

function test_kubectl_robustesse() {
    local original_config="${KUBECONFIG}"
    export KUBECONFIG="/tmp/invalid_kubeconfig"

    # Le test doit échouer
    if ! kubectl get nodes &>/dev/null; then
        export KUBECONFIG="${original_config}"
        return 0
    else
        export KUBECONFIG="${original_config}"
        return 1
    fi
}

function test_timeout_robustesse() {
    # Test avec timeout court
    if ! run_with_timeout "sleep 5" 1 "test"; then
        return 0
    else
        return 1
    fi
}

function test_network_robustesse() {
    # Test de connectivité réseau avec retry
    local retry_count=0
    local max_retries=3

    while [[ ${retry_count} -lt ${max_retries} ]]; do
        if ping -c 1 -W 2 "8.8.8.8" &>/dev/null; then
            return 0
        fi
        ((retry_count++))
        sleep 1
    done

    return 1
}

function test_backup_robustesse() {
    # Test de sauvegarde/restauration
    if backup_state "test-backup" "true"; then
        if [[ -f "${BACKUP_DIR}/.last_backup" ]]; then
            rm -f "${BACKUP_DIR}/test-backup.tar.gz" "${BACKUP_DIR}/test-backup.json"
            return 0
        fi
    fi

    return 1
}

# Point d'entrée principal
function main() {
    # Parsing des arguments
    environment="${DEFAULT_ENV}"
    inventory_file="inventories/${DEFAULT_ENV}/hosts.yml"
    skip_init="false"
    debug_mode="false"
    test_mode="false"

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
            -s|--skip-init)
                skip_init="true"
                shift
                ;;
            -d|--debug)
                debug_mode="true"
                shift
                ;;
            -t|--test)
                test_mode="true"
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
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}  Installation de l'Infrastructure sur VPS - v1.2.0${COLOR_RESET}"
    echo -e "${COLOR_CYAN}  ------------------------------------------------${COLOR_RESET}\n"

    # Affichage des paramètres
    log "INFO" "Configuration:"
    log "INFO" "  - Environnement: ${environment}"
    log "INFO" "  - Inventaire: ${inventory_file}"
    log "INFO" "  - Ignorer l'initialisation: ${skip_init}"
    log "INFO" "  - Mode debug: ${debug_mode}"
    log "INFO" "  - Mode test: ${test_mode}"
    log "INFO" "  - Fichier de log: ${LOG_FILE}"
    echo ""

    # Mode test
    if [[ "${test_mode}" == "true" ]]; then
        log "INFO" "Exécution en mode test..."
        verifier_prerequis
        test_robustesse
        log "INFO" "Mode test terminé"
        exit 0
    fi

    # Installation normale
    verifier_prerequis

    # Sauvegarde de l'état initial
    backup_state "pre-installation" "true"

    # Exécution des étapes
    if [[ "${skip_init}" == "false" ]]; then
        initialiser_vps
    else
        log "INFO" "Initialisation du VPS ignorée"
    fi

    installer_k3s
    backup_state "post-k3s" "true"

    deployer_infrastructure_base
    backup_state "post-infrastructure" "true"

    deployer_monitoring
    backup_state "post-monitoring" "true"

    deployer_services_infrastructure
    backup_state "post-services" "true"

    verifier_installation

    # Affichage du résumé final
    echo -e "\n${COLOR_GREEN}${COLOR_BOLD}===========================================================${COLOR_RESET}"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}  Installation de l'infrastructure LIONS terminée avec succès !${COLOR_RESET}"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}===========================================================${COLOR_RESET}\n"

    log "SUCCESS" "Installation terminée avec succès"
    log "INFO" "Durée totale: $(($(date +%s) - START_TIME)) secondes"

    echo ""
    log "INFO" "Informations d'accès:"
    log "INFO" "  - Grafana: http://${ansible_host}:30000 (admin/admin)"
    log "INFO" "  - Kubernetes Dashboard: https://${ansible_host}:30001"
    echo ""

    # Génération du rapport final
    local report_file="${LOG_DIR}/installation-report-$(date +%Y%m%d-%H%M%S).txt"
    generate_final_report "${report_file}"

    log "INFO" "Rapport d'installation: ${report_file}"
    log "INFO" "Pour déployer des applications, utilisez: deploy.sh"
}

# Fonction de génération du rapport final
function generate_final_report() {
    local report_file="$1"

    {
        echo "=== RAPPORT D'INSTALLATION DE L'INFRASTRUCTURE LIONS ==="
        echo "Date: $(date)"
        echo "Version: 1.2.0"
        echo "Environnement: ${environment}"
        echo "Durée d'installation: $(($(date +%s) - START_TIME)) secondes"
        echo ""

        echo "=== MÉTRIQUES DE PERFORMANCE ==="
        for key in "${!PERFORMANCE_METRICS[@]}"; do
            echo "- ${key}: ${PERFORMANCE_METRICS[${key}]}ms"
        done
        echo ""

        echo "=== RÉSUMÉ DE L'INSTALLATION ==="
        echo "✅ Initialisation du VPS: Réussie"
        echo "✅ Installation de K3s: Réussie"
        echo "✅ Déploiement de l'infrastructure: Réussie"
        echo "✅ Déploiement du monitoring: Réussie"
        echo "✅ Déploiement des services: Réussie"
        echo "✅ Vérification: Réussie"
        echo ""

        echo "=== INFORMATIONS D'ACCÈS ==="
        echo "- Grafana: http://${ansible_host}:30000 (admin/admin)"
        echo "- Kubernetes Dashboard: https://${ansible_host}:30001"
        echo ""

        echo "=== PROCHAINES ÉTAPES ==="
        echo "1. Modifier le mot de passe par défaut de Grafana"
        echo "2. Configurer les alertes dans Prometheus"
        echo "3. Déployer vos applications avec deploy.sh"
        echo "4. Configurer les sauvegardes régulières"
        echo ""

        echo "=== FICHIERS IMPORTANTS ==="
        echo "- Logs: ${LOG_FILE}"
        echo "- Sauvegardes: ${BACKUP_DIR}"
        echo "- Configuration: ${ANSIBLE_DIR}/${inventory_file}"
        echo ""

        echo "=== FIN DU RAPPORT ==="
    } > "${report_file}"
}

# Exécution du script principal
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi