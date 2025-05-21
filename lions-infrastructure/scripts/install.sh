#!/bin/bash
# Titre: Script d'installation de l'infrastructure LIONS sur VPS
# Description: Orchestre l'installation complète de l'infrastructure LIONS sur un VPS
# Auteur: Équipe LIONS Infrastructure
# Date: 2023-05-15
# Version: 1.2.0

# Chargement des variables d'environnement
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Chargement des variables d'environnement depuis le fichier .env
if [ -f "${SCRIPT_DIR}/load-env.sh" ]; then
    source "${SCRIPT_DIR}/load-env.sh"
fi

# Configuration
readonly ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
readonly LOG_DIR="./logs/infrastructure"
readonly LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
readonly DEFAULT_ENV="${LIONS_ENV:-development}"
readonly BACKUP_DIR="${LOG_DIR}/backups"
readonly STATE_FILE="${LOG_DIR}/.installation_state"
readonly LOCK_FILE="/tmp/lions_install.lock"
readonly REQUIRED_SPACE_MB="${LIONS_REQUIRED_SPACE_MB:-5000}"  # 5 Go d'espace disque requis
readonly TIMEOUT_SECONDS="${LIONS_TIMEOUT_SECONDS:-1800}"    # 30 minutes de timeout pour les commandes longues
readonly REQUIRED_PORTS=(${LIONS_VPS_PORT:-22} 80 443 6443 8080 30000 30001)
readonly SUDO_ALWAYS_ASK="${LIONS_SUDO_ALWAYS_ASK:-true}"    # Toujours demander le mot de passe pour sudo

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

# Création des répertoires nécessaires
mkdir -p "${LOG_DIR}"
mkdir -p "${BACKUP_DIR}"

# Activation du mode strict après les vérifications initiales
set -euo pipefail

# Fonction de logging améliorée
function log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
    local caller_info=""
    local log_color="${COLOR_RESET}"
    local log_prefix=""

    # Détermination de la fonction appelante et du numéro de ligne
    if [[ "${debug_mode}" == "true" ]]; then
        # Récupération de la trace d'appel (fonction appelante et numéro de ligne)
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
    esac

    # Affichage du message avec formatage
    # Ajout d'un caractère de retour à la ligne explicite pour éviter les problèmes d'affichage
    echo -e "${log_color}${log_prefix}[${timestamp}] [${level}]${caller_info}${COLOR_RESET} ${message}\n"

    # Enregistrement dans le fichier de log
    echo "[${timestamp}] [${level}]${caller_info} ${message}" >> "${LOG_FILE}"

    # Enregistrement des erreurs dans un fichier séparé pour faciliter le diagnostic
    if [[ "${level}" == "ERROR" ]]; then
        echo "[${timestamp}] [${level}]${caller_info} ${message}" >> "${LOG_DIR}/errors.log"
    fi

    # Enregistrement des avertissements dans un fichier séparé
    if [[ "${level}" == "WARNING" ]]; then
        echo "[${timestamp}] [${level}]${caller_info} ${message}" >> "${LOG_DIR}/warnings.log"
    fi
}

# Fonction pour exécuter une commande avec timeout, avec fallback si la commande timeout n'est pas disponible
function run_with_timeout_fallback() {
    local timeout_seconds="$1"
    shift
    # Utiliser un tableau pour stocker la commande et ses arguments
    local -a cmd_array=("$@")

    # Vérifier si la commande timeout est disponible
    if command -v timeout &>/dev/null; then
        timeout "${timeout_seconds}" "${cmd_array[@]}"
        return $?
    else
        # Fallback: exécuter la commande en arrière-plan et la tuer si elle prend trop de temps
        log "DEBUG" "Commande timeout non disponible, utilisation du fallback"

        # Créer un fichier temporaire pour stocker le PID
        local pid_file
        pid_file=$(mktemp)

        # Exécuter la commande en arrière-plan
        ("${cmd_array[@]}") & echo $! > "${pid_file}" &
        local cmd_pid
        cmd_pid=$(cat "${pid_file}")

        # Attendre que la commande se termine ou que le timeout soit atteint
        local start_time
        start_time=$(date +%s)
        local end_time
        end_time=$((start_time + timeout_seconds))
        local current_time
        current_time=$(date +%s)

        while [[ ${current_time} -lt ${end_time} ]]; do
            # Vérifier si le processus est toujours en cours d'exécution
            if ! kill -0 "${cmd_pid}" 2>/dev/null; then
                # Le processus s'est terminé
                wait "${cmd_pid}"
                local exit_code=$?
                rm -f "${pid_file}"
                return ${exit_code}
            fi

            # Attendre un peu avant de vérifier à nouveau
            sleep 1
            current_time=$(date +%s)
        done

        # Si on arrive ici, c'est que le timeout a été atteint
        log "DEBUG" "Timeout atteint, arrêt forcé de la commande"
        kill -9 "${cmd_pid}" 2>/dev/null || true
        rm -f "${pid_file}"
        return 124  # Code de retour standard pour timeout
    fi
}

# Fonction pour exécuter une commande SSH de manière robuste
function robust_ssh() {
    local timeout=10
    local host="$1"
    local port="$2"
    local user="$3"
    local command="$4"
    local output_var="$5"  # Variable optionnelle pour stocker la sortie
    local silent="${6:-false}"  # Option pour exécuter silencieusement

    # Tentative avec BatchMode (clés SSH uniquement)
    if [[ "${silent}" == "true" ]]; then
        local output=$(ssh -o BatchMode=yes -o ConnectTimeout="${timeout}" -p "${port}" "${user}@${host}" "${command}" 2>/dev/null)
        local exit_code=$?
    else
        local output=$(ssh -o BatchMode=yes -o ConnectTimeout="${timeout}" -p "${port}" "${user}@${host}" "${command}")
        local exit_code=$?
    fi

    # Si la première tentative échoue, essayer avec StrictHostKeyChecking=no
    if [[ ${exit_code} -ne 0 ]]; then
        if [[ "${silent}" == "true" ]]; then
            log "DEBUG" "Tentative SSH avec BatchMode a échoué, essai avec StrictHostKeyChecking=no"
            output=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout="${timeout}" -p "${port}" "${user}@${host}" "${command}" 2>/dev/null)
            exit_code=$?
        else
            log "DEBUG" "Tentative SSH avec BatchMode a échoué, essai avec StrictHostKeyChecking=no"
            output=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout="${timeout}" -p "${port}" "${user}@${host}" "${command}")
            exit_code=$?
        fi
    fi

    # Si une variable de sortie est fournie, y stocker la sortie
    if [[ -n "${output_var}" ]]; then
        # Pour les valeurs numériques, on veut éviter d'échapper les caractères
        # car cela peut interférer avec la conversion en nombres
        if [[ "$output" =~ ^[0-9]+$ ]]; then
            # Si la sortie est un nombre entier, on peut l'assigner directement
            eval "${output_var}=${output}"
        else
            # Nettoyage de la sortie pour extraire uniquement les chiffres si c'est une commande qui devrait retourner un nombre
            if [[ "${command}" == *"nproc"* || "${command}" == *"free -m"* || "${command}" == *"df -m"* ]]; then
                # Pour les commandes qui devraient retourner des nombres, on extrait uniquement les chiffres
                local cleaned_output
                cleaned_output=$(echo "$output" | tr -cd '0-9')
                if [[ -n "$cleaned_output" ]]; then
                    eval "${output_var}=${cleaned_output}"
                else
                    # Si après nettoyage on n'a pas de chiffres, on assigne 0
                    eval "${output_var}=0"
                fi
            else
                # Sinon, on utilise une méthode plus sûre pour gérer les caractères spéciaux
                local escaped_output
                escaped_output=$(printf '%q' "$output")
                eval "${output_var}=${escaped_output}"
            fi
        fi
    fi

    return ${exit_code}
}

# Fonction pour collecter et analyser les logs
function collect_logs() {
    local output_dir
    output_dir="${LOG_DIR}/diagnostic-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${output_dir}"

    log "INFO" "Collecte des logs pour diagnostic dans ${output_dir}..."

    # Copie du log d'installation
    cp "${LOG_FILE}" "${output_dir}/install.log"

    # Collecte des logs du VPS
    if [[ -n "${ansible_host}" && -n "${ansible_port}" && -n "${ansible_user}" ]]; then
        log "INFO" "Collecte des logs du VPS..."

        # Création d'un script temporaire pour collecter les logs sur le VPS
        local tmp_script
        tmp_script=$(mktemp)
        cat > "${tmp_script}" << 'EOF'
#!/bin/bash
# Script de collecte de logs sur le VPS
OUTPUT_DIR="/tmp/lions_logs"
mkdir -p "${OUTPUT_DIR}"

# Logs système
echo "Collecte des logs système..."
dmesg > "${OUTPUT_DIR}/dmesg.log" 2>/dev/null || true
journalctl -n 1000 > "${OUTPUT_DIR}/journalctl.log" 2>/dev/null || true
journalctl -u k3s -n 500 > "${OUTPUT_DIR}/k3s.log" 2>/dev/null || true
journalctl -u kubelet -n 500 > "${OUTPUT_DIR}/kubelet.log" 2>/dev/null || true

# Informations système
echo "Collecte des informations système..."
uname -a > "${OUTPUT_DIR}/uname.log" 2>/dev/null || true
free -h > "${OUTPUT_DIR}/memory.log" 2>/dev/null || true
df -h > "${OUTPUT_DIR}/disk.log" 2>/dev/null || true
top -b -n 1 > "${OUTPUT_DIR}/top.log" 2>/dev/null || true
ps aux > "${OUTPUT_DIR}/ps.log" 2>/dev/null || true
netstat -tuln > "${OUTPUT_DIR}/netstat.log" 2>/dev/null || true
ip addr > "${OUTPUT_DIR}/ip_addr.log" 2>/dev/null || true
ip route > "${OUTPUT_DIR}/ip_route.log" 2>/dev/null || true

# Logs Kubernetes
if command -v kubectl &>/dev/null; then
    echo "Collecte des logs Kubernetes..."
    kubectl get nodes -o wide > "${OUTPUT_DIR}/k8s_nodes.log" 2>/dev/null || true
    kubectl get pods --all-namespaces -o wide > "${OUTPUT_DIR}/k8s_pods.log" 2>/dev/null || true
    kubectl get services --all-namespaces > "${OUTPUT_DIR}/k8s_services.log" 2>/dev/null || true
    kubectl get deployments --all-namespaces > "${OUTPUT_DIR}/k8s_deployments.log" 2>/dev/null || true
    kubectl get events --all-namespaces --sort-by='.lastTimestamp' > "${OUTPUT_DIR}/k8s_events.log" 2>/dev/null || true

    # Logs des pods en erreur
    for pod in $(kubectl get pods --all-namespaces -o jsonpath='{range .items[?(@.status.phase!="Running")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'); do
        ns=$(echo "${pod}" | cut -d/ -f1)
        name=$(echo "${pod}" | cut -d/ -f2)
        kubectl logs -n "${ns}" "${name}" > "${OUTPUT_DIR}/pod_${ns}_${name}.log" 2>/dev/null || true
        kubectl describe pod -n "${ns}" "${name}" > "${OUTPUT_DIR}/pod_${ns}_${name}_describe.log" 2>/dev/null || true
    done
fi

# Compression des logs
tar -czf "/tmp/lions_logs.tar.gz" -C "/tmp" "lions_logs" 2>/dev/null || true
rm -rf "${OUTPUT_DIR}"

echo "Collecte des logs terminée"
EOF

        # Copie et exécution du script sur le VPS
        scp -P "${ansible_port}" "${tmp_script}" "${ansible_user}@${ansible_host}:/tmp/collect_logs.sh" &>/dev/null
        ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "chmod +x /tmp/collect_logs.sh && sudo /tmp/collect_logs.sh" &>/dev/null

        # Récupération des logs
        scp -P "${ansible_port}" "${ansible_user}@${ansible_host}:/tmp/lions_logs.tar.gz" "${output_dir}/vps_logs.tar.gz" &>/dev/null

        # Nettoyage
        ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "rm -f /tmp/collect_logs.sh /tmp/lions_logs.tar.gz" &>/dev/null
        rm -f "${tmp_script}"

        # Extraction des logs
        mkdir -p "${output_dir}/vps_logs"
        tar -xzf "${output_dir}/vps_logs.tar.gz" -C "${output_dir}/vps_logs" &>/dev/null
        rm -f "${output_dir}/vps_logs.tar.gz"
    fi

    # Collecte des logs locaux
    log "INFO" "Collecte des logs locaux..."

    # Informations système locales
    uname -a > "${output_dir}/local_uname.log" 2>/dev/null || true
    df -h > "${output_dir}/local_disk.log" 2>/dev/null || true

    # Logs Kubernetes locaux
    if command_exists kubectl; then
        kubectl version --client > "${output_dir}/local_kubectl_version.log" 2>/dev/null || true
        kubectl config view --minify > "${output_dir}/local_kubectl_config.log" 2>/dev/null || true
    fi

    # Logs Ansible locaux
    if command_exists ansible-playbook; then
        ansible-playbook --version > "${output_dir}/local_ansible_version.log" 2>/dev/null || true
    fi

    # Compression des logs
    log "INFO" "Compression des logs..."
    local archive_file
    archive_file="${LOG_DIR}/diagnostic-$(date +%Y%m%d-%H%M%S).tar.gz"
    tar -czf "${archive_file}" -C "$(dirname "${output_dir}")" "$(basename "${output_dir}")" &>/dev/null
    rm -rf "${output_dir}"

    log "SUCCESS" "Logs collectés et archivés dans ${archive_file}"

    # Analyse des logs
    log "INFO" "Analyse des logs..."

    # Extraction des erreurs courantes
    if tar -xzf "${archive_file}" -C /tmp &>/dev/null; then
        local extracted_dir="/tmp/$(basename "${output_dir}")"

        # Recherche des erreurs courantes
        log "INFO" "Recherche des erreurs courantes..."

        # Erreurs de connexion
        if grep -r "Connection refused" "${extracted_dir}" &>/dev/null; then
            log "WARNING" "Erreurs de connexion détectées - vérifiez que les services sont en cours d'exécution"
        fi

        # Erreurs de permission
        if grep -r "Permission denied" "${extracted_dir}" &>/dev/null; then
            log "WARNING" "Erreurs de permission détectées - vérifiez les droits d'accès"
        fi

        # Erreurs d'espace disque
        if grep -r "No space left on device" "${extracted_dir}" &>/dev/null; then
            log "WARNING" "Erreurs d'espace disque détectées - libérez de l'espace et réessayez"
        fi

        # Erreurs de mémoire
        if grep -r "Out of memory" "${extracted_dir}" &>/dev/null; then
            log "WARNING" "Erreurs de mémoire détectées - augmentez la mémoire disponible"
        fi

        # Erreurs de réseau
        if grep -r "Network is unreachable" "${extracted_dir}" &>/dev/null; then
            log "WARNING" "Erreurs de réseau détectées - vérifiez la connectivité réseau"
        fi

        # Nettoyage
        rm -rf "${extracted_dir}"
    fi

    return 0
}

# Fonction de gestion des erreurs
function handle_error() {
    local exit_code=$?
    local line_number=$1
    local command_name=$2

    # Désactivation du mode strict pour la gestion des erreurs
    set +euo pipefail

    log "ERROR" "Une erreur s'est produite à la ligne ${line_number} (code ${exit_code})"
    log "ERROR" "Dernière commande exécutée: ${LAST_COMMAND}"

    # Collecte d'informations de diagnostic supplémentaires
    local error_details=""
    case ${exit_code} in
        1)   error_details="Erreur générale ou erreur de commande inconnue" ;;
        2)   error_details="Erreur de syntaxe dans l'utilisation de la commande" ;;
        126) error_details="La commande ne peut pas être exécutée (problème de permissions)" ;;
        127) error_details="Commande non trouvée" ;;
        128) error_details="Argument invalide pour exit" ;;
        130) error_details="Script terminé par Ctrl+C" ;;
        137) error_details="Script terminé par SIGKILL (possiblement manque de mémoire)" ;;
        139) error_details="Erreur de segmentation (bug dans un programme)" ;;
        *)   error_details="Code d'erreur non spécifique" ;;
    esac

    log "ERROR" "Détails de l'erreur: ${error_details}"

    # Enregistrement de l'erreur avec plus de détails
    LAST_ERROR="Erreur à la ligne ${line_number} (code ${exit_code}): ${LAST_COMMAND} - ${error_details}"

    # Sauvegarde de l'état actuel et des logs pour analyse
    echo "${INSTALLATION_STEP}" > "${STATE_FILE}"
    cp "${LOG_FILE}" "${BACKUP_DIR}/error-log-$(date +%Y%m%d-%H%M%S).log"

    # Vérification de l'état du système avant de tenter une reprise
    log "INFO" "Vérification de l'état du système avant reprise..."

    # Vérification de la connectivité réseau
    if ! ping -c 1 -W 5 "${ansible_host}" &>/dev/null; then
        log "ERROR" "Connectivité réseau perdue avec le VPS (${ansible_host})"
        log "ERROR" "Impossible de reprendre l'installation sans connectivité réseau"
        cleanup
        exit 1
    fi

    # Vérification de l'espace disque
    if ! check_disk_space; then
        log "ERROR" "Espace disque insuffisant pour continuer l'installation"
        cleanup
        exit 1
    fi

    # Tentative de reprise si possible
    if [[ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]]; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        log "WARNING" "Tentative de reprise (${RETRY_COUNT}/${MAX_RETRIES})..."

        # Suppression du fichier de verrouillage avant la reprise
        if [[ -f "${LOCK_FILE}" ]]; then
            log "INFO" "Suppression du fichier de verrouillage avant la reprise..."
            # Tentative de suppression sans sudo d'abord
            if ! rm -f "${LOCK_FILE}" 2>/dev/null; then
                log "WARNING" "Impossible de supprimer le fichier de verrouillage sans sudo, tentative avec sudo..."
                # Si ça échoue, essayer avec sudo
                if sudo rm -f "${LOCK_FILE}"; then
                    log "SUCCESS" "Fichier de verrouillage supprimé avec succès (sudo)"
                else
                    log "WARNING" "Impossible de supprimer le fichier de verrouillage, même avec sudo"
                fi
            fi
        fi

        # Attente avant la reprise pour permettre au système de se stabiliser
        log "INFO" "Attente de 10 secondes avant reprise..."
        sleep 10

        # Reprise en fonction de l'étape avec gestion spécifique selon la commande qui a échoué
        case "${INSTALLATION_STEP}" in
            "init_vps")
                log "INFO" "Reprise de l'initialisation du VPS..."
                if [[ "${command_name}" == "ansible_playbook" ]]; then
                    log "INFO" "Tentative de reprise avec des options plus sûres..."
                    # Tentative avec des options plus sûres pour Ansible
                    ansible-playbook -i "${ANSIBLE_DIR}/${inventory_file}" "${ANSIBLE_DIR}/playbooks/init-vps.yml" --ask-become-pass --forks=1 --timeout=60
                else
                    initialiser_vps
                fi
                ;;
            "install_k3s")
                log "INFO" "Reprise de l'installation de K3s..."
                if [[ "${command_name}" == "ansible_playbook" ]]; then
                    log "INFO" "Tentative de reprise avec des options plus sûres..."
                    # Tentative avec des options plus sûres pour Ansible
                    ansible-playbook -i "${ANSIBLE_DIR}/${inventory_file}" "${ANSIBLE_DIR}/playbooks/install-k3s.yml" --ask-become-pass --forks=1 --timeout=60
                else
                    installer_k3s
                fi
                ;;
            "deploy_infra")
                log "INFO" "Reprise du déploiement de l'infrastructure de base..."
                if [[ "${command_name}" == "kubectl_apply" ]]; then
                    log "INFO" "Tentative de reprise avec validation désactivée..."
                    kubectl apply -k "${PROJECT_ROOT}/kubernetes/overlays/${environment}" --validate=false --timeout=10m
                else
                    deployer_infrastructure_base
                fi
                ;;
            "deploy_monitoring")
                log "INFO" "Reprise du déploiement du monitoring..."
                if [[ "${command_name}" == "helm_install" ]]; then
                    log "INFO" "Tentative de reprise avec des options plus sûres..."
                    helm upgrade --install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --values "${values_file}" --timeout 15m --atomic
                else
                    deployer_monitoring
                fi
                ;;
            "verify")
                log "INFO" "Reprise de la vérification de l'installation..."
                verifier_installation
                ;;
            "prerequis")
                log "INFO" "Reprise de la vérification des prérequis..."
                verifier_prerequis
                ;;
            *)
                log "ERROR" "Impossible de reprendre à l'étape '${INSTALLATION_STEP}'"
                log "ERROR" "Veuillez consulter les logs pour plus d'informations et corriger manuellement le problème"
                log "INFO" "Vous pouvez ensuite relancer le script avec l'option --skip-init si l'initialisation a déjà été effectuée"
                cleanup
                exit ${exit_code}
                ;;
        esac
    else
        log "ERROR" "Nombre maximal de tentatives atteint (${MAX_RETRIES})"
        log "ERROR" "Dernière erreur: ${LAST_ERROR}"

        # Génération d'un rapport de diagnostic
        generate_diagnostic_report

        log "INFO" "Un rapport de diagnostic a été généré dans ${BACKUP_DIR}/diagnostic-$(date +%Y%m%d-%H%M%S).txt"
        log "INFO" "Veuillez consulter ce rapport pour identifier et corriger le problème"

        cleanup
        exit ${exit_code}
    fi
}

# Fonction de génération de rapport de diagnostic
function generate_diagnostic_report() {
    local report_file
    report_file="${BACKUP_DIR}/diagnostic-$(date +%Y%m%d-%H%M%S).txt"

    log "INFO" "Génération d'un rapport de diagnostic complet..."

    {
        echo "=== RAPPORT DE DIAGNOSTIC LIONS INFRASTRUCTURE ==="
        echo "Date: $(date)"
        echo "Environnement: ${environment}"
        echo "Étape d'installation: ${INSTALLATION_STEP}"
        echo ""

        echo "=== INFORMATIONS SUR L'ERREUR ==="
        echo "Dernière commande: ${LAST_COMMAND}"
        echo "Dernière erreur: ${LAST_ERROR}"
        echo "Nombre de tentatives: ${RETRY_COUNT}/${MAX_RETRIES}"
        echo ""

        echo "=== INFORMATIONS SYSTÈME LOCAL ==="
        echo "Système d'exploitation: $(uname -a)"
        echo "Espace disque disponible: $(df -h . | awk 'NR==2 {print $4}')"
        echo "Mémoire disponible: $(free -h | awk '/^Mem:/ {print $7}')"
        echo ""

        echo "=== INFORMATIONS SUR LE VPS ==="
        if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
            # Exécution locale
            echo "Système d'exploitation: $(uname -a 2>/dev/null)"
            echo "Espace disque disponible: $(df -h / | awk 'NR==2 {print $4}' 2>/dev/null)"
            echo "Mémoire disponible: $(free -h | awk '/^Mem:/ {print $7}' 2>/dev/null)"
            echo "Charge système: $(uptime 2>/dev/null)"
            echo "Services actifs: $(systemctl list-units --state=running --type=service --no-pager | grep -v systemd | head -10 2>/dev/null)"
        else
            # Exécution distante
            if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "uname -a" &>/dev/null; then
                echo "Système d'exploitation: $(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "uname -a" 2>/dev/null)"
                echo "Espace disque disponible: $(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "df -h / | awk 'NR==2 {print \$4}'" 2>/dev/null)"
                echo "Mémoire disponible: $(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "free -h | awk '/^Mem:/ {print \$7}'" 2>/dev/null)"
                echo "Charge système: $(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "uptime" 2>/dev/null)"
                echo "Services actifs: $(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "systemctl list-units --state=running --type=service --no-pager | grep -v systemd | head -10" 2>/dev/null)"
            else
                echo "Impossible de se connecter au VPS pour récupérer les informations"
            fi
        fi
        echo ""

        echo "=== ÉTAT DE KUBERNETES ==="
        if command_exists kubectl && kubectl cluster-info &>/dev/null; then
            echo "Version de Kubernetes: $(kubectl version --short 2>/dev/null)"
            echo "Nœuds: $(kubectl get nodes -o wide 2>/dev/null)"
            echo "Pods par namespace: $(kubectl get pods --all-namespaces -o wide 2>/dev/null)"
            echo "Services: $(kubectl get services --all-namespaces 2>/dev/null)"
            echo "Événements récents: $(kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -n 20 2>/dev/null)"
        else
            echo "Kubernetes n'est pas accessible ou n'est pas installé"
        fi
        echo ""

        echo "=== LOGS PERTINENTS ==="
        echo "Dernières lignes du log d'installation:"
        tail -50 "${LOG_FILE}" 2>/dev/null
        echo ""

        echo "=== VÉRIFICATIONS RÉSEAU ==="
        if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
            # Exécution locale
            echo "Exécution locale détectée, vérification de la connectivité réseau ignorée"
            echo "Ports ouverts sur le VPS (vérification locale):"
            for port in "${REQUIRED_PORTS[@]}"; do
                if ss -tuln | grep -q ":${port} "; then
                    echo "  - Port ${port}: OUVERT"
                else
                    echo "  - Port ${port}: FERMÉ"
                fi
            done
        else
            # Exécution distante
            echo "Ping vers le VPS: $(ping -c 3 "${ansible_host}" 2>&1)"
            echo "Ports ouverts sur le VPS:"
            for port in "${REQUIRED_PORTS[@]}"; do
                if nc -z -w 5 "${ansible_host}" "${port}" &>/dev/null; then
                    echo "  - Port ${port}: OUVERT"
                else
                    echo "  - Port ${port}: FERMÉ"
                fi
            done
        fi
        echo ""

        echo "=== RECOMMANDATIONS ==="
        echo "1. Vérifiez la connectivité réseau avec le VPS"
        echo "2. Assurez-vous que tous les ports requis sont ouverts"
        echo "3. Vérifiez l'espace disque et la mémoire disponibles"
        echo "4. Consultez les logs pour plus de détails sur l'erreur"
        echo "5. Corrigez les problèmes identifiés et relancez le script"
        echo "6. Si nécessaire, utilisez l'option --skip-init pour reprendre après l'initialisation"
        echo ""

        echo "=== FIN DU RAPPORT ==="
    } > "${report_file}"

    log "SUCCESS" "Rapport de diagnostic généré: ${report_file}"
    return 0
}

# Fonction de nettoyage
function cleanup() {
    log "INFO" "Nettoyage des ressources temporaires..."

    # Suppression du fichier de verrouillage
    if [[ -f "${LOCK_FILE}" ]]; then
        # Tentative de suppression sans sudo d'abord
        if ! rm -f "${LOCK_FILE}" 2>/dev/null; then
            log "WARNING" "Impossible de supprimer le fichier de verrouillage sans sudo, tentative avec sudo..."
            # Si ça échoue, essayer avec secure_sudo
            if secure_sudo rm -f "${LOCK_FILE}"; then
                log "SUCCESS" "Fichier de verrouillage supprimé avec succès (sudo)"
            else
                log "WARNING" "Impossible de supprimer le fichier de verrouillage, même avec sudo"
            fi
        fi
    fi

    # Affichage des informations de diagnostic
    log "INFO" "Informations de diagnostic:"
    log "INFO" "- Dernière étape: ${INSTALLATION_STEP}"
    log "INFO" "- Dernière commande: ${LAST_COMMAND}"
    log "INFO" "- Dernière erreur: ${LAST_ERROR}"
    log "INFO" "- Fichier de log: ${LOG_FILE}"

    log "INFO" "Nettoyage terminé"
}

# Configuration du gestionnaire d'erreurs
trap 'handle_error ${LINENO} "${COMMAND_NAME:-unknown}"' ERR

# Configuration du gestionnaire de sortie pour s'assurer que le fichier de verrouillage est toujours supprimé
trap 'if [[ -f "${LOCK_FILE}" ]]; then if ! rm -f "${LOCK_FILE}" 2>/dev/null; then secure_sudo rm -f "${LOCK_FILE}" 2>/dev/null || true; fi; fi' EXIT

# Fonction pour exécuter des commandes sudo avec demande de mot de passe
function secure_sudo() {
    if [[ "${SUDO_ALWAYS_ASK}" == "true" ]]; then
        sudo -k "$@"  # -k force à demander le mot de passe
    else
        sudo "$@"
    fi
}

# Fonction pour vérifier si une commande existe
function command_exists() {
    command -v "$1" &> /dev/null
}

# Fonction pour installer les commandes manquantes
function install_missing_commands() {
    local commands=("$@")
    local os_name=$(uname -s)
    local success=true

    log "INFO" "Détection du système d'exploitation: ${os_name}"

    # Détection du gestionnaire de paquets
    local pkg_manager=""
    local install_cmd=""

    if [[ "${os_name}" == "Linux" ]]; then
        # Détection de la distribution Linux
        if command_exists apt-get; then
            pkg_manager="apt"
            install_cmd="apt-get install -y"
        elif command_exists dnf; then
            pkg_manager="dnf"
            install_cmd="dnf install -y"
        elif command_exists yum; then
            pkg_manager="yum"
            install_cmd="yum install -y"
        elif command_exists pacman; then
            pkg_manager="pacman"
            install_cmd="pacman -S --noconfirm"
        elif command_exists zypper; then
            pkg_manager="zypper"
            install_cmd="zypper install -y"
        else
            log "ERROR" "Gestionnaire de paquets non reconnu sur ce système Linux"
            return 1
        fi
    elif [[ "${os_name}" == "Darwin" ]]; then
        # macOS - vérification de Homebrew
        if command_exists brew; then
            pkg_manager="brew"
            install_cmd="brew install"
        else
            log "ERROR" "Homebrew n'est pas installé sur ce système macOS"
            log "INFO" "Installez Homebrew avec: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            return 1
        fi
    else
        log "ERROR" "Système d'exploitation non supporté pour l'installation automatique: ${os_name}"
        return 1
    fi

    log "INFO" "Utilisation du gestionnaire de paquets: ${pkg_manager}"

    # Mise à jour des dépôts si nécessaire
    if [[ "${pkg_manager}" == "apt" ]]; then
        log "INFO" "Mise à jour des dépôts apt..."
        if ! secure_sudo apt-get update &>/dev/null; then
            log "WARNING" "Impossible de mettre à jour les dépôts apt"
        fi
    elif [[ "${pkg_manager}" == "dnf" || "${pkg_manager}" == "yum" ]]; then
        log "INFO" "Mise à jour des dépôts ${pkg_manager}..."
        if ! secure_sudo ${pkg_manager} check-update &>/dev/null; then
            log "WARNING" "Impossible de mettre à jour les dépôts ${pkg_manager}"
        fi
    fi

    # Installation des commandes manquantes
    for cmd in "${commands[@]}"; do
        log "INFO" "Installation de la commande: ${cmd}"

        # Mapping des noms de commandes aux noms de paquets
        local pkg_name=""
        case "${cmd}" in
            "jq")
                pkg_name="jq"
                ;;
            "ansible-playbook")
                if [[ "${pkg_manager}" == "apt" ]]; then
                    pkg_name="ansible"
                elif [[ "${pkg_manager}" == "brew" ]]; then
                    pkg_name="ansible"
                else
                    pkg_name="ansible"
                fi
                ;;
            "kubectl")
                if [[ "${pkg_manager}" == "apt" ]]; then
                    # Pour Debian/Ubuntu, kubectl peut être installé de deux façons
                    # Méthode 1 (directe): Téléchargement direct du binaire (plus fiable)
                    log "INFO" "Installation de kubectl via téléchargement direct du binaire..."

                    # Vérification de curl
                    if ! command_exists curl; then
                        log "INFO" "Installation de curl..."
                        secure_sudo apt-get install -y curl 2>&1 | tee /tmp/curl_install.log
                        if ! command_exists curl; then
                            log "ERROR" "Échec de l'installation de curl. Voir /tmp/curl_install.log pour plus de détails."
                            return 1
                        fi
                    fi

                    # Téléchargement du binaire kubectl
                    local kubectl_version="v1.28.4"  # Version mise à jour
                    local arch=$(uname -m)
                    local kubectl_arch="amd64"

                    if [[ "${arch}" == "aarch64" || "${arch}" == "arm64" ]]; then
                        kubectl_arch="arm64"
                    elif [[ "${arch}" == "armv7l" ]]; then
                        kubectl_arch="arm"
                    fi

                    log "INFO" "Téléchargement de kubectl ${kubectl_version} pour ${kubectl_arch}..."
                    if curl -LO "https://dl.k8s.io/release/${kubectl_version}/bin/linux/${kubectl_arch}/kubectl" 2>/tmp/kubectl_download.log; then
                        log "SUCCESS" "Téléchargement de kubectl réussi"
                        secure_sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
                        if [[ $? -eq 0 ]]; then
                            log "SUCCESS" "Installation de kubectl réussie via téléchargement direct"
                            rm -f kubectl
                            return 0
                        else
                            log "ERROR" "Échec de l'installation de kubectl dans /usr/local/bin"
                            log "INFO" "Tentative avec méthode alternative..."
                            rm -f kubectl
                        fi
                    else
                        log "ERROR" "Échec du téléchargement de kubectl. Voir /tmp/kubectl_download.log pour plus de détails."
                        log "INFO" "Tentative avec méthode alternative..."
                    fi

                    # Méthode 2 (fallback): Utilisation du dépôt Kubernetes
                    log "INFO" "Tentative d'installation via le dépôt Kubernetes..."

                    # Ajout de la clé GPG
                    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | secure_sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>/tmp/kubectl_key.log
                    if [[ $? -ne 0 ]]; then
                        log "WARNING" "Problème lors de l'ajout de la clé Kubernetes. Voir /tmp/kubectl_key.log pour plus de détails."
                        # Création du répertoire si nécessaire
                        secure_sudo mkdir -p /etc/apt/keyrings
                        # Nouvelle tentative
                        curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | secure_sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>/tmp/kubectl_key_retry.log
                        if [[ $? -ne 0 ]]; then
                            log "ERROR" "Échec de l'ajout de la clé Kubernetes même après nouvelle tentative."
                        fi
                    fi

                    # Ajout du dépôt (nouvelle URL)
                    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | secure_sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

                    log "INFO" "Mise à jour des dépôts apt..."
                    secure_sudo apt-get update 2>/tmp/apt_update.log

                    pkg_name="kubectl"
                elif [[ "${pkg_manager}" == "brew" ]]; then
                    pkg_name="kubernetes-cli"
                else
                    pkg_name="kubectl"
                fi
                ;;
            "helm")
                if [[ "${pkg_manager}" == "apt" ]]; then
                    # Pour Debian/Ubuntu, helm nécessite un dépôt spécial
                    log "INFO" "Configuration du dépôt Helm pour apt..."
                    if ! command_exists curl; then
                        secure_sudo apt-get install -y curl &>/dev/null
                    fi
                    curl https://baltocdn.com/helm/signing.asc | secure_sudo apt-key add - &>/dev/null
                    echo "deb https://baltocdn.com/helm/stable/debian/ all main" | secure_sudo tee /etc/apt/sources.list.d/helm-stable-debian.list &>/dev/null
                    secure_sudo apt-get update &>/dev/null
                    pkg_name="helm"
                elif [[ "${pkg_manager}" == "brew" ]]; then
                    pkg_name="helm"
                else
                    pkg_name="helm"
                fi
                ;;
            "timeout")
                if [[ "${pkg_manager}" == "apt" ]]; then
                    pkg_name="coreutils"
                elif [[ "${pkg_manager}" == "brew" ]]; then
                    pkg_name="coreutils"
                else
                    pkg_name="coreutils"
                fi
                ;;
            "nc")
                if [[ "${pkg_manager}" == "apt" ]]; then
                    pkg_name="netcat"
                elif [[ "${pkg_manager}" == "brew" ]]; then
                    pkg_name="netcat"
                else
                    pkg_name="netcat"
                fi
                ;;
            "ping")
                if [[ "${pkg_manager}" == "apt" ]]; then
                    pkg_name="iputils-ping"
                elif [[ "${pkg_manager}" == "brew" ]]; then
                    pkg_name="inetutils"
                else
                    pkg_name="iputils"
                fi
                ;;
            "ssh"|"scp")
                if [[ "${pkg_manager}" == "apt" ]]; then
                    pkg_name="openssh-client"
                elif [[ "${pkg_manager}" == "brew" ]]; then
                    pkg_name="openssh"
                else
                    pkg_name="openssh"
                fi
                ;;
            *)
                # Si la commande n'est pas dans notre mapping, on utilise le même nom
                pkg_name="${cmd}"
                ;;
        esac

        # Installation du paquet
        log "INFO" "Installation du paquet: ${pkg_name}"
        local install_log="/tmp/${pkg_name}_install.log"
        if ! secure_sudo ${install_cmd} ${pkg_name} 2>&1 | tee "${install_log}"; then
            log "ERROR" "Échec de l'installation de ${pkg_name}. Voir ${install_log} pour plus de détails."

            # Tentative alternative pour kubectl si l'installation via apt a échoué
            if [[ "${cmd}" == "kubectl" && "${pkg_manager}" == "apt" ]]; then
                log "INFO" "Tentative d'installation alternative de kubectl via téléchargement direct..."

                # Vérification de curl
                if ! command_exists curl; then
                    log "INFO" "Installation de curl..."
                    secure_sudo apt-get install -y curl 2>&1 | tee /tmp/curl_install_fallback.log
                    if ! command_exists curl; then
                        log "ERROR" "Échec de l'installation de curl. Voir /tmp/curl_install_fallback.log pour plus de détails."
                        continue
                    fi
                fi

                local kubectl_version="v1.28.4"  # Version mise à jour
                local arch=$(uname -m)
                local kubectl_arch="amd64"

                if [[ "${arch}" == "aarch64" || "${arch}" == "arm64" ]]; then
                    kubectl_arch="arm64"
                elif [[ "${arch}" == "armv7l" ]]; then
                    kubectl_arch="arm"
                fi

                log "INFO" "Téléchargement de kubectl ${kubectl_version} pour ${kubectl_arch}..."
                if curl -LO "https://dl.k8s.io/release/${kubectl_version}/bin/linux/${kubectl_arch}/kubectl" 2>/tmp/kubectl_download_fallback.log; then
                    log "SUCCESS" "Téléchargement de kubectl réussi"
                    secure_sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
                    if [[ $? -eq 0 ]]; then
                        log "SUCCESS" "Installation de kubectl réussie via téléchargement direct (fallback)"
                        rm -f kubectl
                        continue  # Skip the success=false and continue with the next command
                    else
                        log "ERROR" "Échec de l'installation de kubectl dans /usr/local/bin"
                        log "ERROR" "Vérifiez les permissions et l'espace disque"
                        rm -f kubectl
                    fi
                else
                    log "ERROR" "Échec du téléchargement de kubectl. Voir /tmp/kubectl_download_fallback.log pour plus de détails."
                    log "ERROR" "Vérifiez votre connexion Internet et les paramètres proxy"
                fi
            fi

            success=false
        else
            log "SUCCESS" "Installation de ${pkg_name} réussie"
            # Vérification que la commande est maintenant disponible
            if ! command_exists "${cmd}"; then
                log "WARNING" "La commande ${cmd} n'est toujours pas disponible après l'installation"
                success=false
            fi
        fi
    done

    return $( [[ "${success}" == "true" ]] && echo 0 || echo 1 )
}

# Fonction pour vérifier et installer les collections Ansible requises
function update_ansible() {
    log "INFO" "Mise à jour d'Ansible..."

    # Détection du système d'exploitation
    local os_name
    os_name=$(uname -s)

    # Détection du gestionnaire de paquets et mise à jour d'Ansible
    if [[ "${os_name}" == "Linux" ]]; then
        # Détection de la distribution Linux
        if command_exists apt-get; then
            log "INFO" "Système Debian/Ubuntu détecté, utilisation de apt-get"
            if ! secure_sudo apt-get update &>/dev/null; then
                log "ERROR" "Échec de la mise à jour des dépôts"
                return 1
            fi
            if ! secure_sudo apt-get install -y ansible &>/dev/null; then
                log "ERROR" "Échec de la mise à jour d'Ansible"
                return 1
            fi
        elif command_exists dnf; then
            log "INFO" "Système Fedora détecté, utilisation de dnf"
            if ! secure_sudo dnf update -y ansible &>/dev/null; then
                log "ERROR" "Échec de la mise à jour d'Ansible"
                return 1
            fi
        elif command_exists yum; then
            log "INFO" "Système CentOS/RHEL détecté, utilisation de yum"
            if ! secure_sudo yum update -y ansible &>/dev/null; then
                log "ERROR" "Échec de la mise à jour d'Ansible"
                return 1
            fi
        elif command_exists pacman; then
            log "INFO" "Système Arch Linux détecté, utilisation de pacman"
            if ! secure_sudo pacman -Syu --noconfirm ansible &>/dev/null; then
                log "ERROR" "Échec de la mise à jour d'Ansible"
                return 1
            fi
        elif command_exists zypper; then
            log "INFO" "Système openSUSE détecté, utilisation de zypper"
            if ! secure_sudo zypper update -y ansible &>/dev/null; then
                log "ERROR" "Échec de la mise à jour d'Ansible"
                return 1
            fi
        else
            log "ERROR" "Gestionnaire de paquets non supporté sur ce système Linux"
            log "INFO" "Veuillez mettre à jour Ansible manuellement"
            return 1
        fi
    elif [[ "${os_name}" == "Darwin" ]]; then
        # macOS
        if command_exists brew; then
            log "INFO" "Système macOS détecté, utilisation de Homebrew"
            if ! brew update &>/dev/null; then
                log "ERROR" "Échec de la mise à jour des dépôts Homebrew"
                return 1
            fi
            if ! brew upgrade ansible &>/dev/null; then
                log "ERROR" "Échec de la mise à jour d'Ansible"
                return 1
            fi
        else
            log "ERROR" "Homebrew n'est pas installé sur ce système macOS"
            log "INFO" "Installez Homebrew avec: /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            return 1
        fi
    elif [[ "${os_name}" == *"MINGW"* || "${os_name}" == *"MSYS"* || "${os_name}" == *"CYGWIN"* ]]; then
        # Windows (Git Bash, MSYS2, Cygwin)
        log "ERROR" "Mise à jour automatique d'Ansible non supportée sur Windows"
        log "INFO" "Veuillez mettre à jour Ansible manuellement"
        return 1
    else
        log "ERROR" "Système d'exploitation non supporté pour la mise à jour automatique: ${os_name}"
        log "INFO" "Veuillez mettre à jour Ansible manuellement"
        return 1
    fi

    # Vérification de la mise à jour
    local new_ansible_version
    local new_ansible_version_raw
    new_ansible_version_raw=$(ansible --version | head -n1)
    # Extraction du numéro de version, qu'il soit au format "2.13.13" ou "[core 2.15.0]"
    if [[ "${new_ansible_version_raw}" =~ \[core[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        # Nouveau format: [core X.Y.Z]
        new_ansible_version="${BASH_REMATCH[1]}"
    else
        # Ancien format: juste le numéro de version
        new_ansible_version=$(echo "${new_ansible_version_raw}" | awk '{print $2}')
    fi

    log "INFO" "Nouvelle version d'Ansible: ${new_ansible_version}"

    if version_greater_equal "${new_ansible_version}" "2.14.0"; then
        log "SUCCESS" "Ansible a été mis à jour avec succès vers une version compatible: ${new_ansible_version}"
        return 0
    else
        log "WARNING" "La version d'Ansible après mise à jour est toujours potentiellement incompatible: ${new_ansible_version}"
        log "WARNING" "Vous pouvez installer des versions spécifiques des collections ou mettre à jour Ansible manuellement"
        return 1
    fi
}

function check_ansible_version() {
    log "INFO" "Vérification de la version d'Ansible..."

    # Vérification de l'installation d'Ansible
    if ! command_exists ansible; then
        log "ERROR" "La commande ansible n'est pas disponible"
        log "ERROR" "Assurez-vous qu'Ansible est correctement installé"
        return 1
    fi

    # Récupération de la version d'Ansible
    local ansible_version
    local ansible_version_raw
    ansible_version_raw=$(ansible --version | head -n1)
    # Extraction du numéro de version, qu'il soit au format "2.13.13" ou "[core 2.15.0]"
    if [[ "${ansible_version_raw}" =~ \[core[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        # Nouveau format: [core X.Y.Z]
        ansible_version="${BASH_REMATCH[1]}"
    else
        # Ancien format: juste le numéro de version
        ansible_version=$(echo "${ansible_version_raw}" | awk '{print $2}')
    fi
    log "INFO" "Version d'Ansible détectée: ${ansible_version}"

    # Vérification de la compatibilité
    if version_greater_equal "${ansible_version}" "2.14.0"; then
        log "SUCCESS" "Version d'Ansible compatible: ${ansible_version}"
        return 0
    else
        log "WARNING" "Version d'Ansible potentiellement incompatible: ${ansible_version}"
        log "WARNING" "Certaines collections peuvent nécessiter des versions spécifiques"

        # Demander à l'utilisateur s'il souhaite installer des versions spécifiques ou mettre à jour Ansible
        local response
        read -p "Souhaitez-vous installer des versions spécifiques des collections compatibles avec Ansible ${ansible_version}? (o/N): " response

        if [[ "${response}" =~ ^[oO]$ ]]; then
            log "INFO" "Installation de versions spécifiques des collections..."
            return 2  # Code spécial pour indiquer l'installation de versions spécifiques
        else
            log "INFO" "Tentative de mise à jour d'Ansible..."
            if update_ansible; then
                log "SUCCESS" "Ansible a été mis à jour avec succès"
                return 0
            else
                log "WARNING" "Impossible de mettre à jour Ansible automatiquement"
                log "INFO" "Continuation avec les versions par défaut des collections"
                return 0
            fi
        fi
    fi
}

function check_ansible_collections() {
    log "INFO" "Vérification des collections Ansible requises..."

    # Vérification de la version d'Ansible
    local ansible_version_check
    check_ansible_version
    ansible_version_check=$?

    # Liste des collections requises avec leurs versions spécifiques pour Ansible 2.13.x
    local required_collections=()
    local required_versions=()

    if [[ ${ansible_version_check} -eq 2 ]]; then
        # Versions spécifiques pour Ansible 2.13.x
        required_collections=(
            "community.kubernetes"
            "kubernetes.core"
            "community.general"
            "ansible.posix"
            "community.docker"
        )
        required_versions=(
            "2.0.1"
            "2.3.2"
            "5.8.0"
            "1.4.0"
            "latest"
        )
        log "INFO" "Utilisation de versions spécifiques des collections compatibles avec Ansible 2.13.x"
    else
        # Versions par défaut
        required_collections=(
            "community.kubernetes"
            "kubernetes.core"
            "community.general"
            "ansible.posix"
            "community.docker"
        )
        required_versions=(
            "latest"
            "latest"
            "latest"
            "latest"
            "latest"
        )
    fi

    local missing_collections=()
    local missing_indices=()

    # Vérification de l'installation d'Ansible Galaxy
    if ! command_exists ansible-galaxy; then
        log "ERROR" "La commande ansible-galaxy n'est pas disponible"
        log "ERROR" "Assurez-vous qu'Ansible est correctement installé"
        return 1
    fi

    # Vérification des collections installées
    for i in "${!required_collections[@]}"; do
        local collection="${required_collections[$i]}"
        log "INFO" "Vérification de la collection: ${collection}"

        # Utilisation de ansible-galaxy pour vérifier si la collection est installée
        if ! ansible-galaxy collection list "${collection}" &>/dev/null; then
            log "WARNING" "Collection Ansible manquante: ${collection}"
            missing_collections+=("${collection}")
            missing_indices+=("$i")
        else
            log "SUCCESS" "Collection Ansible trouvée: ${collection}"

            # Si on utilise des versions spécifiques, vérifier si la version installée est correcte
            if [[ ${ansible_version_check} -eq 2 && "${required_versions[$i]}" != "latest" ]]; then
                local installed_version
                installed_version=$(ansible-galaxy collection list "${collection}" | grep "${collection}" | awk '{print $2}')

                if [[ "${installed_version}" != "${required_versions[$i]}" ]]; then
                    log "WARNING" "Version incorrecte de la collection ${collection}: ${installed_version} (attendue: ${required_versions[$i]})"
                    missing_collections+=("${collection}")
                    missing_indices+=("$i")
                fi
            fi
        fi
    done

    # Installation des collections manquantes
    if [[ ${#missing_collections[@]} -gt 0 ]]; then
        log "INFO" "Installation des collections Ansible manquantes ou à mettre à jour: ${missing_collections[*]}"

        for i in "${!missing_collections[@]}"; do
            local collection="${missing_collections[$i]}"
            local index="${missing_indices[$i]}"
            local version="${required_versions[$index]}"

            log "INFO" "Installation de la collection: ${collection}"

            if [[ "${version}" != "latest" ]]; then
                log "INFO" "Version spécifique: ${version}"
                if ! ansible-galaxy collection install "${collection}:${version}" --force &>/dev/null; then
                    log "ERROR" "Échec de l'installation de la collection: ${collection}:${version}"
                    return 1
                else
                    log "SUCCESS" "Installation de la collection réussie: ${collection}:${version}"
                fi
            else
                if ! ansible-galaxy collection install "${collection}" &>/dev/null; then
                    log "ERROR" "Échec de l'installation de la collection: ${collection}"
                    return 1
                else
                    log "SUCCESS" "Installation de la collection réussie: ${collection}"
                fi
            fi
        done
    else
        log "INFO" "Toutes les collections Ansible requises sont déjà installées avec les versions correctes"
    fi

    # Configuration d'Ansible pour ignorer les avertissements de version
    log "INFO" "Configuration d'Ansible pour ignorer les avertissements de version..."

    # Vérifier si le fichier ansible.cfg existe et est accessible en écriture
    local ansible_cfg=""
    local can_write=false

    # Vérifier si le fichier système est accessible en écriture
    if [ -f /etc/ansible/ansible.cfg ] && [ -w /etc/ansible/ansible.cfg ]; then
        ansible_cfg="/etc/ansible/ansible.cfg"
        can_write=true
    # Vérifier si le fichier utilisateur existe
    elif [ -f ~/.ansible.cfg ]; then
        ansible_cfg="~/.ansible.cfg"
        can_write=true
    # Vérifier si le fichier local existe
    elif [ -f ./ansible.cfg ]; then
        ansible_cfg="./ansible.cfg"
        can_write=true
    # Si le fichier système existe mais n'est pas accessible en écriture, utiliser le fichier utilisateur
    elif [ -f /etc/ansible/ansible.cfg ]; then
        log "WARNING" "Le fichier /etc/ansible/ansible.cfg existe mais n'est pas accessible en écriture"
        log "INFO" "Création d'un fichier de configuration utilisateur ~/.ansible.cfg"
        ansible_cfg="$HOME/.ansible.cfg"
        # Copier le contenu du fichier système si possible
        if [ -r /etc/ansible/ansible.cfg ]; then
            cp /etc/ansible/ansible.cfg "$HOME/.ansible.cfg" 2>/dev/null || echo "[defaults]" > "$HOME/.ansible.cfg"
        else
            echo "[defaults]" > "$HOME/.ansible.cfg"
        fi
        can_write=true
    # Sinon, créer un nouveau fichier local
    else
        log "INFO" "Aucun fichier ansible.cfg trouvé, création d'un nouveau fichier..."
        ansible_cfg="./ansible.cfg"
        echo "[defaults]" > "${ansible_cfg}"
        can_write=true
    fi

    if [ "$can_write" = true ]; then
        # Vérifier si le répertoire parent est accessible en écriture
        local parent_dir=$(dirname "${ansible_cfg}")
        if [ ! -w "${parent_dir}" ]; then
            log "WARNING" "Le répertoire parent ${parent_dir} n'est pas accessible en écriture"
            can_write=false
        else
            # Ajouter ou mettre à jour l'option collections_on_ansible_version_mismatch
            if grep -q "collections_on_ansible_version_mismatch" "${ansible_cfg}"; then
                if ! sed -i 's/collections_on_ansible_version_mismatch.*/collections_on_ansible_version_mismatch = ignore/' "${ansible_cfg}" 2>/dev/null; then
                    log "WARNING" "Impossible de modifier ${ansible_cfg} avec sed, tentative avec une autre méthode"
                    # Méthode alternative pour Windows/WSL
                    local temp_file=$(mktemp)
                    grep -v "collections_on_ansible_version_mismatch" "${ansible_cfg}" > "${temp_file}" && \
                    echo "collections_on_ansible_version_mismatch = ignore" >> "${temp_file}" && \
                    cat "${temp_file}" > "${ansible_cfg}" && \
                    rm "${temp_file}" || {
                        log "WARNING" "Impossible de modifier ${ansible_cfg}, utilisation de la variable d'environnement"
                        can_write=false
                    }
                fi
            else
                # Trouver la section [defaults] et ajouter l'option après
                if ! grep -q "\[defaults\]" "${ansible_cfg}"; then
                    echo "[defaults]" >> "${ansible_cfg}" || {
                        log "WARNING" "Impossible d'ajouter la section [defaults] à ${ansible_cfg}"
                        can_write=false
                    }
                fi

                if [ "$can_write" = true ]; then
                    if ! sed -i '/\[defaults\]/a collections_on_ansible_version_mismatch = ignore' "${ansible_cfg}" 2>/dev/null; then
                        log "WARNING" "Impossible de modifier ${ansible_cfg} avec sed, tentative avec une autre méthode"
                        # Méthode alternative pour Windows/WSL
                        echo "collections_on_ansible_version_mismatch = ignore" >> "${ansible_cfg}" || {
                            log "WARNING" "Impossible d'ajouter l'option à ${ansible_cfg}, utilisation de la variable d'environnement"
                            can_write=false
                        }
                    fi
                fi
            fi

            if [ "$can_write" = true ]; then
                log "SUCCESS" "Configuration d'Ansible mise à jour dans ${ansible_cfg}"
            fi
        fi
    fi

    if [ "$can_write" = false ]; then
        log "WARNING" "Impossible d'écrire dans les fichiers de configuration Ansible"
        log "INFO" "Utilisation de la variable d'environnement ANSIBLE_COLLECTIONS_ON_ANSIBLE_VERSION_MISMATCH"
    fi

    # Définir la variable d'environnement comme solution de secours
    export ANSIBLE_COLLECTIONS_ON_ANSIBLE_VERSION_MISMATCH=ignore
    log "SUCCESS" "Variable d'environnement ANSIBLE_COLLECTIONS_ON_ANSIBLE_VERSION_MISMATCH définie sur 'ignore'"

    return 0
}

# Fonction pour vérifier et installer les dépendances Python requises
function check_python_dependencies() {
    log "INFO" "Vérification des dépendances Python requises..."

    # Liste des modules Python requis
    local required_modules=(
        "kubernetes"
        "openshift"
    )

    local missing_modules=()

    # Vérification de l'installation de pip
    if ! command_exists pip || ! command_exists pip3; then
        log "WARNING" "La commande pip/pip3 n'est pas disponible"
        log "INFO" "Tentative d'installation de pip..."

        # Détection du gestionnaire de paquets
        if command_exists apt-get; then
            secure_sudo apt-get update &>/dev/null
            secure_sudo apt-get install -y python3-pip &>/dev/null
        elif command_exists dnf; then
            secure_sudo dnf install -y python3-pip &>/dev/null
        elif command_exists yum; then
            secure_sudo yum install -y python3-pip &>/dev/null
        elif command_exists pacman; then
            secure_sudo pacman -S --noconfirm python-pip &>/dev/null
        elif command_exists zypper; then
            secure_sudo zypper install -y python3-pip &>/dev/null
        else
            log "ERROR" "Impossible d'installer pip automatiquement"
            log "ERROR" "Veuillez installer pip manuellement et réessayer"
            return 1
        fi

        if ! command_exists pip && ! command_exists pip3; then
            log "ERROR" "L'installation de pip a échoué"
            return 1
        else
            log "SUCCESS" "Installation de pip réussie"
        fi
    fi

    # Déterminer la commande pip à utiliser
    local pip_cmd="pip"
    if ! command_exists pip && command_exists pip3; then
        pip_cmd="pip3"
    fi

    # Vérification des modules installés
    for module in "${required_modules[@]}"; do
        log "INFO" "Vérification du module Python: ${module}"

        # Utilisation de pip pour vérifier si le module est installé
        if ! ${pip_cmd} show "${module}" &>/dev/null; then
            log "WARNING" "Module Python manquant: ${module}"
            missing_modules+=("${module}")
        else
            log "SUCCESS" "Module Python trouvé: ${module}"
        fi
    done

    # Installation des modules manquants
    if [[ ${#missing_modules[@]} -gt 0 ]]; then
        log "INFO" "Installation des modules Python manquants: ${missing_modules[*]}"

        for module in "${missing_modules[@]}"; do
            log "INFO" "Installation du module: ${module}"

            # Première tentative: installation standard
            if ! ${pip_cmd} install "${module}" --no-cache-dir; then
                log "WARNING" "Échec de l'installation standard du module: ${module}"
                log "INFO" "Tentative d'installation avec sudo..."

                # Deuxième tentative: installation avec sudo
                if ! secure_sudo ${pip_cmd} install "${module}" --no-cache-dir; then
                    log "WARNING" "Échec de l'installation avec sudo du module: ${module}"
                    log "INFO" "Tentative d'installation avec --user..."

                    # Troisième tentative: installation avec --user
                    if ! ${pip_cmd} install --user "${module}" --no-cache-dir; then
                        log "WARNING" "Échec de l'installation avec --user du module: ${module}"
                        log "INFO" "Tentative d'installation avec pip et le module spécifique..."

                        # Quatrième tentative: installation avec pip et le module spécifique
                        if [[ "${module}" == "kubernetes" ]]; then
                            if ! ${pip_cmd} install kubernetes==26.1.0 --no-cache-dir; then
                                log "WARNING" "Échec de l'installation avec version spécifique du module: ${module}"
                                log "INFO" "Tentative d'installation via le gestionnaire de paquets système..."

                                # Cinquième tentative: installation via le gestionnaire de paquets système
                                local pkg_installed=false
                                if command_exists apt-get; then
                                    if secure_sudo apt-get install -y python3-kubernetes; then
                                        pkg_installed=true
                                    fi
                                elif command_exists dnf; then
                                    if secure_sudo dnf install -y python3-kubernetes; then
                                        pkg_installed=true
                                    fi
                                elif command_exists yum; then
                                    if secure_sudo yum install -y python3-kubernetes; then
                                        pkg_installed=true
                                    fi
                                elif command_exists pacman; then
                                    if secure_sudo pacman -S --noconfirm python-kubernetes; then
                                        pkg_installed=true
                                    fi
                                elif command_exists zypper; then
                                    if secure_sudo zypper install -y python3-kubernetes; then
                                        pkg_installed=true
                                    fi
                                fi

                                if [ "$pkg_installed" = true ]; then
                                    log "SUCCESS" "Installation du module réussie via le gestionnaire de paquets: ${module}"
                                else
                                    log "ERROR" "Échec de toutes les tentatives d'installation du module: ${module}"
                                    return 1
                                fi
                            else
                                log "SUCCESS" "Installation du module réussie avec version spécifique: ${module}"
                            fi
                        elif [[ "${module}" == "openshift" ]]; then
                            if ! ${pip_cmd} install openshift==0.13.2 --no-cache-dir; then
                                log "WARNING" "Échec de l'installation avec version spécifique du module: ${module}"
                                log "INFO" "Tentative d'installation via le gestionnaire de paquets système..."

                                # Cinquième tentative: installation via le gestionnaire de paquets système
                                local pkg_installed=false
                                if command_exists apt-get; then
                                    if secure_sudo apt-get install -y python3-openshift; then
                                        pkg_installed=true
                                    fi
                                elif command_exists dnf; then
                                    if secure_sudo dnf install -y python3-openshift; then
                                        pkg_installed=true
                                    fi
                                elif command_exists yum; then
                                    if secure_sudo yum install -y python3-openshift; then
                                        pkg_installed=true
                                    fi
                                elif command_exists pacman; then
                                    if secure_sudo pacman -S --noconfirm python-openshift; then
                                        pkg_installed=true
                                    fi
                                elif command_exists zypper; then
                                    if secure_sudo zypper install -y python3-openshift; then
                                        pkg_installed=true
                                    fi
                                fi

                                if [ "$pkg_installed" = true ]; then
                                    log "SUCCESS" "Installation du module réussie via le gestionnaire de paquets: ${module}"
                                else
                                    log "ERROR" "Échec de toutes les tentatives d'installation du module: ${module}"
                                    return 1
                                fi
                            else
                                log "SUCCESS" "Installation du module réussie avec version spécifique: ${module}"
                            fi
                        else
                            log "ERROR" "Échec de toutes les tentatives d'installation du module: ${module}"
                            return 1
                        fi
                    else
                        log "SUCCESS" "Installation du module réussie avec --user: ${module}"
                    fi
                else
                    log "SUCCESS" "Installation du module réussie avec sudo: ${module}"
                fi
            else
                log "SUCCESS" "Installation du module réussie: ${module}"
            fi
        done
    else
        log "INFO" "Tous les modules Python requis sont déjà installés"
    fi

    # Vérification finale que tous les modules sont correctement installés
    local verification_failed=false
    for module in "${required_modules[@]}"; do
        log "INFO" "Vérification finale du module Python: ${module}"

        # Tentative d'importation du module pour vérifier qu'il est utilisable
        if ! python3 -c "import ${module}" 2>/dev/null; then
            log "WARNING" "Le module ${module} ne peut pas être importé malgré l'installation"
            verification_failed=true
        else
            log "SUCCESS" "Module ${module} correctement installé et importable"
        fi
    done

    if [ "$verification_failed" = true ]; then
        log "WARNING" "Certains modules Python ne sont pas correctement installés"
        log "WARNING" "L'installation pourrait rencontrer des problèmes ultérieurement"
        # Ne pas échouer ici, car les modules pourraient être disponibles d'une autre manière
    fi

    return 0
}

# Fonction pour vérifier et installer les plugins Helm requis
function check_helm_plugins() {
    log "INFO" "Vérification des plugins Helm requis..."

    # Vérification de l'installation de Helm
    if ! command_exists helm; then
        log "ERROR" "La commande helm n'est pas disponible"
        log "ERROR" "Assurez-vous que Helm est correctement installé"
        return 1
    fi

    # Liste des plugins requis avec leurs versions minimales
    local required_plugins=(
        "diff:3.4.1:https://github.com/databus23/helm-diff"
    )

    local all_plugins_installed=true

    for plugin_info in "${required_plugins[@]}"; do
        # Extraction des informations du plugin
        local plugin_name=$(echo "${plugin_info}" | cut -d':' -f1)
        local min_version=$(echo "${plugin_info}" | cut -d':' -f2)
        # Extraction de l'URL en préservant les ':' dans l'URL
        local repo_url=$(echo "${plugin_info}" | sed -E 's/^[^:]+:[^:]+://')

        # Vérification plus robuste du plugin
        local plugin_exists=false
        local plugin_output=$(helm plugin list 2>/dev/null)

        # Vérifier si le plugin existe déjà
        if echo "${plugin_output}" | grep -q "${plugin_name}"; then
            plugin_exists=true
        # Vérification supplémentaire pour le plugin diff qui peut apparaître comme "diff" ou "helm-diff"
        elif [[ "${plugin_name}" == "diff" ]] && echo "${plugin_output}" | grep -q "helm-diff"; then
            plugin_exists=true
            plugin_name="helm-diff"  # Utiliser le nom correct pour les opérations suivantes
        fi

        if [[ ${plugin_exists} == false ]]; then
            log "WARNING" "Plugin Helm manquant: ${plugin_name}"
            log "INFO" "Installation du plugin ${plugin_name} version ${min_version}..."

            # Tentative d'installation avec gestion des erreurs réseau
            local max_retries=3
            local retry_count=0
            local install_success=false

            while [[ ${retry_count} -lt ${max_retries} && ${install_success} == false ]]; do
                # Vérifier si le plugin existe déjà avant d'essayer de l'installer
                if helm plugin list 2>/dev/null | grep -q "${plugin_name}" || ([[ "${plugin_name}" == "diff" ]] && helm plugin list 2>/dev/null | grep -q "helm-diff"); then
                    log "INFO" "Le plugin ${plugin_name} semble déjà être installé"
                    install_success=true
                    break
                fi

                if helm plugin install "${repo_url}" --version "v${min_version}" &>/dev/null; then
                    install_success=true
                else
                    # Vérifier si l'erreur est due au fait que le plugin existe déjà
                    if helm plugin install "${repo_url}" --version "v${min_version}" 2>&1 | grep -q "plugin already exists"; then
                        log "INFO" "Le plugin ${plugin_name} est déjà installé"
                        install_success=true
                        break
                    fi

                    retry_count=$((retry_count + 1))
                    if [[ ${retry_count} -lt ${max_retries} ]]; then
                        log "WARNING" "Échec de l'installation du plugin ${plugin_name}, nouvelle tentative (${retry_count}/${max_retries})..."
                        sleep 2
                    fi
                fi
            done

            # Vérification de l'installation
            if [[ ${install_success} == true ]]; then
                log "SUCCESS" "Installation du plugin ${plugin_name} réussie ou plugin déjà installé"
            else
                log "ERROR" "Échec de l'installation du plugin ${plugin_name} après ${max_retries} tentatives"
                log "ERROR" "Vérifiez votre connexion Internet et les permissions"
                log "INFO" "Vous pouvez l'installer manuellement avec: helm plugin install ${repo_url} --version v${min_version}"
                all_plugins_installed=false
            fi
        else
            # Vérifier la version du plugin
            local current_version=""

            # Extraire la version en fonction du nom du plugin (diff ou helm-diff)
            if [[ "${plugin_name}" == "diff" ]]; then
                current_version=$(helm plugin list 2>/dev/null | grep -E "(diff|helm-diff)" | awk '{print $2}')
            else
                current_version=$(helm plugin list 2>/dev/null | grep "${plugin_name}" | awk '{print $2}')
            fi

            log "INFO" "Plugin ${plugin_name} trouvé, version: ${current_version}"

            # Extraire le numéro de version sans le 'v' initial
            current_version=${current_version#v}

            # Vérifier si la version est inférieure à la version minimale requise
            if ! version_greater_equal "${current_version}" "${min_version}"; then
                log "WARNING" "Version du plugin ${plugin_name} trop ancienne: ${current_version} (requise: ${min_version} ou supérieure)"
                log "INFO" "Mise à jour du plugin ${plugin_name}..."

                # Supprimer l'ancienne version
                helm plugin uninstall "${plugin_name}" &>/dev/null

                # Installer la nouvelle version avec gestion des erreurs réseau
                local max_retries=3
                local retry_count=0
                local update_success=false

                while [[ ${retry_count} -lt ${max_retries} && ${update_success} == false ]]; do
                    if helm plugin install "${repo_url}" --version "v${min_version}" &>/dev/null; then
                        update_success=true
                    else
                        # Vérifier si l'erreur est due au fait que le plugin existe déjà
                        if helm plugin install "${repo_url}" --version "v${min_version}" 2>&1 | grep -q "plugin already exists"; then
                            log "INFO" "Le plugin ${plugin_name} est déjà installé avec la nouvelle version"
                            update_success=true
                            break
                        fi

                        retry_count=$((retry_count + 1))
                        if [[ ${retry_count} -lt ${max_retries} ]]; then
                            log "WARNING" "Échec de la mise à jour du plugin ${plugin_name}, nouvelle tentative (${retry_count}/${max_retries})..."
                            sleep 2
                        fi
                    fi
                done

                # Vérification de la mise à jour
                if [[ ${update_success} == true ]]; then
                    log "SUCCESS" "Mise à jour du plugin ${plugin_name} réussie"
                else
                    log "ERROR" "Échec de la mise à jour du plugin ${plugin_name} après ${max_retries} tentatives"
                    log "ERROR" "Vérifiez votre connexion Internet et les permissions"
                    log "INFO" "Vous pouvez le mettre à jour manuellement avec: helm plugin install ${repo_url} --version v${min_version}"
                    all_plugins_installed=false
                fi
            else
                log "SUCCESS" "Plugin ${plugin_name} trouvé avec une version compatible: ${current_version}"
            fi
        fi
    done

    if [[ ${all_plugins_installed} == true ]]; then
        return 0
    else
        return 1
    fi
}

# Fonction pour vérifier les ressources système locales
function check_local_resources() {
    log "INFO" "Vérification des ressources système locales..."

    # Vérification de l'espace disque
    local available_space=$(df -m . | awk 'NR==2 {print $4}')

    if [[ ${available_space} -lt ${REQUIRED_SPACE_MB} ]]; then
        log "ERROR" "Espace disque local insuffisant: ${available_space}MB disponible, ${REQUIRED_SPACE_MB}MB requis"
        return 1
    else
        log "INFO" "Espace disque local disponible: ${available_space}MB (minimum requis: ${REQUIRED_SPACE_MB}MB)"
    fi

    # Vérification de la mémoire disponible
    local os_name=$(uname -s)
    local available_memory=0

    if [[ "${os_name}" == "Linux" ]]; then
        available_memory=$(free -m | awk '/^Mem:/ {print $7}')
    elif [[ "${os_name}" == "Darwin" ]]; then
        available_memory=$(vm_stat | awk '/Pages free/ {free=$3} /Pages inactive/ {inactive=$3} END {print (free+inactive)*4096/1048576}' | cut -d. -f1)
    else
        log "WARNING" "Système d'exploitation non reconnu, impossible de vérifier la mémoire disponible"
        available_memory=1024  # Valeur par défaut
    fi

    if [[ ${available_memory} -lt 1024 ]]; then
        log "WARNING" "Mémoire locale disponible limitée: ${available_memory}MB (recommandé: 1024MB minimum)"
        log "WARNING" "Des problèmes de performance peuvent survenir pendant l'installation"
    else
        log "INFO" "Mémoire locale disponible: ${available_memory}MB (minimum recommandé: 1024MB)"
    fi

    # Vérification du nombre de processeurs
    local cpu_count=0

    if [[ "${os_name}" == "Linux" ]]; then
        cpu_count=$(nproc --all 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
    elif [[ "${os_name}" == "Darwin" ]]; then
        cpu_count=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
    else
        log "WARNING" "Système d'exploitation non reconnu, impossible de vérifier le nombre de processeurs"
        cpu_count=1  # Valeur par défaut
    fi

    if [[ ${cpu_count} -lt 2 ]]; then
        log "WARNING" "Nombre de processeurs limité: ${cpu_count} (recommandé: 2 minimum)"
        log "WARNING" "Des problèmes de performance peuvent survenir pendant l'installation"
    else
        log "INFO" "Nombre de processeurs: ${cpu_count} (minimum recommandé: 2)"
    fi

    log "SUCCESS" "Vérification des ressources système locales terminée"
    return 0
}

# Fonction pour vérifier les ressources système du VPS
function check_vps_resources() {
    log "INFO" "Vérification des ressources système du VPS..."

    # Vérification de la connexion SSH (seulement si exécution distante)
    if [[ "${IS_LOCAL_EXECUTION}" != "true" ]]; then
        if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "echo 'Connexion SSH réussie'" &>/dev/null; then
            log "ERROR" "Impossible de se connecter au VPS via SSH pour vérifier les ressources"
            return 1
        fi
    else
        log "INFO" "Exécution locale détectée, pas besoin de vérifier la connexion SSH"
    fi

    # Vérification de l'espace disque
    local vps_disk_total
    local vps_disk_used
    local vps_disk_free
    local vps_disk_use_percent

    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        # Exécution locale
        vps_disk_total=$(df -m / | awk 'NR==2 {print $2}' 2>/dev/null || echo "0")
        vps_disk_used=$(df -m / | awk 'NR==2 {print $3}' 2>/dev/null || echo "0")
        vps_disk_free=$(df -m / | awk 'NR==2 {print $4}' 2>/dev/null || echo "0")
        vps_disk_use_percent=$(df -m / | awk 'NR==2 {print $5}' 2>/dev/null | sed 's/%//' || echo "0")
    else
        # Exécution distante
        # Essayer plusieurs méthodes pour obtenir les informations de disque
        log "DEBUG" "Récupération des informations disque..."
        local disk_cmd="df -m / 2>/dev/null || df -k / 2>/dev/null | awk '{size=\$2/1024; used=\$3/1024; free=\$4/1024; print size,used,free,\$5}' || echo '0 0 0 0%'"
        local disk_output=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "${disk_cmd}" 2>/dev/null)
        log "DEBUG" "Sortie de la commande disque: ${disk_output:-Erreur}"

        # Extraction des valeurs de disque
        vps_disk_total=$(echo "${disk_output}" | awk 'NR==2 {print $2}' 2>/dev/null)
        vps_disk_used=$(echo "${disk_output}" | awk 'NR==2 {print $3}' 2>/dev/null)
        vps_disk_free=$(echo "${disk_output}" | awk 'NR==2 {print $4}' 2>/dev/null)
        vps_disk_use_percent=$(echo "${disk_output}" | awk 'NR==2 {print $5}' 2>/dev/null | sed 's/%//' || echo "0")

        # Si les valeurs sont vides, essayer une autre méthode
        if [[ -z "${vps_disk_total}" ]] || ! [[ "${vps_disk_total}" =~ ^[0-9.]+$ ]]; then
            log "DEBUG" "Tentative alternative pour le disque..."
            local df_cmd="df -k / 2>/dev/null"
            local df_output=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "${df_cmd}" 2>/dev/null)
            log "DEBUG" "Sortie de la commande df -k: ${df_output:-Erreur}"

            # Extraction des valeurs de disque à partir de df -k
            vps_disk_total=$(echo "${df_output}" | awk 'NR==2 {print int($2/1024)}' 2>/dev/null)
            vps_disk_used=$(echo "${df_output}" | awk 'NR==2 {print int($3/1024)}' 2>/dev/null)
            vps_disk_free=$(echo "${df_output}" | awk 'NR==2 {print int($4/1024)}' 2>/dev/null)
            vps_disk_use_percent=$(echo "${df_output}" | awk 'NR==2 {print $5}' 2>/dev/null | sed 's/%//' || echo "0")
        fi

        # Nettoyage des valeurs
        log "DEBUG" "Valeurs brutes après récupération: CPU=${vps_cpu_cores}, RAM=${vps_memory_total}, Disk=${vps_disk_total}"

        # Si toujours pas de valeurs valides, utiliser des valeurs par défaut
        if [[ -z "${vps_disk_total}" ]] || ! [[ "${vps_disk_total}" =~ ^[0-9.]+$ ]]; then
            vps_disk_total="20480"  # 20 GB par défaut
            log "WARNING" "Impossible de déterminer l'espace disque total du VPS, utilisation de la valeur par défaut: ${vps_disk_total}MB"
        fi

        if [[ -z "${vps_disk_used}" ]] || ! [[ "${vps_disk_used}" =~ ^[0-9.]+$ ]]; then
            vps_disk_used="5120"  # 5 GB par défaut
        fi

        if [[ -z "${vps_disk_free}" ]] || ! [[ "${vps_disk_free}" =~ ^[0-9.]+$ ]]; then
            vps_disk_free=$((vps_disk_total - vps_disk_used))
        fi

        if [[ -z "${vps_disk_use_percent}" ]] || ! [[ "${vps_disk_use_percent}" =~ ^[0-9.]+$ ]]; then
            vps_disk_use_percent=$((vps_disk_used * 100 / vps_disk_total))
        fi

        log "DEBUG" "Valeurs après nettoyage: CPU=${vps_cpu_cores}, RAM=${vps_memory_total}, Disk=${vps_disk_total}"
    fi

    log "INFO" "Espace disque du VPS: ${vps_disk_free}MB libre sur ${vps_disk_total}MB total (${vps_disk_use_percent}% utilisé)"

    if [[ ${vps_disk_free} -lt ${REQUIRED_SPACE_MB} ]]; then
        log "ERROR" "Espace disque du VPS insuffisant: ${vps_disk_free}MB disponible, ${REQUIRED_SPACE_MB}MB requis"

        # Vérification des répertoires volumineux
        log "INFO" "Recherche des répertoires volumineux sur le VPS..."
        local large_dirs=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo du -h --max-depth=2 /var /home /opt /usr | sort -hr | head -10" 2>/dev/null || echo "Impossible de déterminer les répertoires volumineux")
        log "INFO" "Répertoires volumineux sur le VPS:"
        echo "${large_dirs}"

        # Suggestion de solution
        log "INFO" "Suggestions:"
        log "INFO" "1. Libérez de l'espace disque sur le VPS"
        log "INFO" "2. Augmentez la taille du disque du VPS"
        log "INFO" "3. Utilisez un autre VPS avec plus d'espace disque"

        return 1
    fi

    # Vérification de la mémoire
    local vps_memory_total
    local vps_memory_used
    local vps_memory_free
    local vps_memory_available

    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        # Exécution locale
        vps_memory_total=$(free -m | awk '/^Mem:/ {print $2}' 2>/dev/null || echo "0")
        vps_memory_used=$(free -m | awk '/^Mem:/ {print $3}' 2>/dev/null || echo "0")
        vps_memory_free=$(free -m | awk '/^Mem:/ {print $4}' 2>/dev/null || echo "0")
        vps_memory_available=$(free -m | awk '/^Mem:/ {print $7}' 2>/dev/null || echo "0")
    else
        # Exécution distante
        # Essayer plusieurs méthodes pour obtenir les informations de mémoire
        log "DEBUG" "Récupération des informations mémoire..."
        local mem_cmd="free -m 2>/dev/null || vmstat -s -S M 2>/dev/null | grep 'total memory' | awk '{print \$1}' || cat /proc/meminfo 2>/dev/null | grep MemTotal | awk '{print \$2/1024}'"
        local mem_output=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "${mem_cmd}" 2>/dev/null)
        log "DEBUG" "Sortie de la commande mémoire: ${mem_output:-Erreur}"

        # Extraction des valeurs de mémoire
        vps_memory_total=$(echo "${mem_output}" | grep -m1 "^Mem:" | awk '{print $2}' 2>/dev/null)
        vps_memory_used=$(echo "${mem_output}" | grep -m1 "^Mem:" | awk '{print $3}' 2>/dev/null)
        vps_memory_free=$(echo "${mem_output}" | grep -m1 "^Mem:" | awk '{print $4}' 2>/dev/null)
        vps_memory_available=$(echo "${mem_output}" | grep -m1 "^Mem:" | awk '{print $7}' 2>/dev/null)

        # Si les valeurs sont vides, essayer une autre méthode
        if [[ -z "${vps_memory_total}" ]] || ! [[ "${vps_memory_total}" =~ ^[0-9]+$ ]]; then
            log "DEBUG" "Tentative alternative pour la mémoire..."
            local meminfo_cmd="cat /proc/meminfo 2>/dev/null"
            local meminfo_output=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "${meminfo_cmd}" 2>/dev/null)
            log "DEBUG" "Sortie de la commande meminfo: ${meminfo_output:-Erreur}"

            # Extraction des valeurs de mémoire à partir de /proc/meminfo
            vps_memory_total=$(echo "${meminfo_output}" | grep "^MemTotal:" | awk '{print int($2/1024)}' 2>/dev/null)
            vps_memory_free=$(echo "${meminfo_output}" | grep "^MemFree:" | awk '{print int($2/1024)}' 2>/dev/null)
            vps_memory_available=$(echo "${meminfo_output}" | grep "^MemAvailable:" | awk '{print int($2/1024)}' 2>/dev/null)

            # Calcul de la mémoire utilisée
            if [[ -n "${vps_memory_total}" ]] && [[ -n "${vps_memory_free}" ]]; then
                vps_memory_used=$((vps_memory_total - vps_memory_free))
            fi

            # Si MemAvailable n'est pas disponible, utiliser MemFree
            if [[ -z "${vps_memory_available}" ]] || ! [[ "${vps_memory_available}" =~ ^[0-9]+$ ]]; then
                vps_memory_available="${vps_memory_free}"
            fi
        fi

        # Si toujours pas de valeurs valides, utiliser des valeurs par défaut
        if [[ -z "${vps_memory_total}" ]] || ! [[ "${vps_memory_total}" =~ ^[0-9]+$ ]]; then
            vps_memory_total="4096"  # 4 GB par défaut
            log "WARNING" "Impossible de déterminer la mémoire totale du VPS, utilisation de la valeur par défaut: ${vps_memory_total}MB"
        fi

        if [[ -z "${vps_memory_used}" ]] || ! [[ "${vps_memory_used}" =~ ^[0-9]+$ ]]; then
            vps_memory_used="1024"  # 1 GB par défaut
        fi

        if [[ -z "${vps_memory_free}" ]] || ! [[ "${vps_memory_free}" =~ ^[0-9]+$ ]]; then
            vps_memory_free=$((vps_memory_total - vps_memory_used))
        fi

        if [[ -z "${vps_memory_available}" ]] || ! [[ "${vps_memory_available}" =~ ^[0-9]+$ ]]; then
            vps_memory_available="${vps_memory_free}"
        fi
    fi

    log "INFO" "Mémoire du VPS: ${vps_memory_available}MB disponible sur ${vps_memory_total}MB total"

    # Vérification du swap
    local vps_swap_total
    local vps_swap_used
    local vps_swap_free

    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        # Exécution locale
        vps_swap_total=$(free -m | awk '/^Swap:/ {print $2}' 2>/dev/null || echo "0")
        vps_swap_used=$(free -m | awk '/^Swap:/ {print $3}' 2>/dev/null || echo "0")
        vps_swap_free=$(free -m | awk '/^Swap:/ {print $4}' 2>/dev/null || echo "0")
    else
        # Exécution distante
        vps_swap_total=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "free -m | awk '/^Swap:/ {print \$2}'" 2>/dev/null || echo "0")
        vps_swap_used=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "free -m | awk '/^Swap:/ {print \$3}'" 2>/dev/null || echo "0")
        vps_swap_free=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "free -m | awk '/^Swap:/ {print \$4}'" 2>/dev/null || echo "0")
    fi

    log "INFO" "Swap du VPS: ${vps_swap_free}MB libre sur ${vps_swap_total}MB total"

    # Vérification des seuils de mémoire
    if [[ ${vps_memory_total} -lt 4096 ]]; then
        log "WARNING" "Mémoire totale du VPS insuffisante: ${vps_memory_total}MB (recommandé: 4096MB minimum)"
        log "WARNING" "Des problèmes de performance peuvent survenir pendant l'installation"

        if [[ ${vps_memory_total} -lt 2048 ]]; then
            log "ERROR" "Mémoire totale du VPS critique: ${vps_memory_total}MB (minimum absolu: 2048MB)"
            log "ERROR" "L'installation risque d'échouer par manque de mémoire"

            # Suggestion de solution
            log "INFO" "Suggestions:"
            log "INFO" "1. Augmentez la mémoire du VPS"
            log "INFO" "2. Ajoutez ou augmentez l'espace swap"
            log "INFO" "3. Utilisez un autre VPS avec plus de mémoire"

            log "INFO" "Voulez-vous continuer malgré tout? (o/N)"
            read -r answer
            if [[ ! "${answer}" =~ ^[Oo]$ ]]; then
                return 1
            fi
        fi
    fi

    # Vérification du nombre de processeurs
    local vps_cpu_cores
    local vps_cpu_load

    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        # Exécution locale
        vps_cpu_cores=$(nproc --all 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "0")
        vps_cpu_load=$(cat /proc/loadavg | awk '{print $1}' 2>/dev/null || echo "0")
    else
        # Exécution distante
        # Essayer plusieurs méthodes pour obtenir le nombre de processeurs
        log "DEBUG" "Récupération des informations CPU..."
        vps_cpu_cores=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "nproc --all 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || lscpu 2>/dev/null | grep '^CPU(s):' | awk '{print \$2}' || echo '0'" 2>/dev/null)
        log "DEBUG" "Sortie de la commande CPU: ${vps_cpu_cores:-Erreur}"

        # Si la valeur est vide ou non numérique, essayer une autre méthode
        if [[ -z "${vps_cpu_cores}" ]] || ! [[ "${vps_cpu_cores}" =~ ^[0-9]+$ ]]; then
            log "DEBUG" "Tentative alternative pour CPU avec nproc..."
            vps_cpu_cores=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "nproc 2>/dev/null || echo '0'" 2>/dev/null)
            log "DEBUG" "Sortie de la commande nproc: ${vps_cpu_cores:-Erreur}"
        fi

        # Si toujours pas de valeur valide, utiliser une valeur par défaut
        if [[ -z "${vps_cpu_cores}" ]] || ! [[ "${vps_cpu_cores}" =~ ^[0-9]+$ ]]; then
            vps_cpu_cores="2"  # Valeur par défaut raisonnable
            log "WARNING" "Impossible de déterminer le nombre de cœurs CPU du VPS, utilisation de la valeur par défaut: ${vps_cpu_cores}"
        fi

        # Récupération de la charge CPU
        vps_cpu_load=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "cat /proc/loadavg 2>/dev/null | awk '{print \$1}' || echo '0'" 2>/dev/null)

        # Si la valeur est vide ou non numérique, utiliser une valeur par défaut
        if [[ -z "${vps_cpu_load}" ]] || ! [[ "${vps_cpu_load}" =~ ^[0-9.]+$ ]]; then
            vps_cpu_load="0.0"  # Valeur par défaut
            log "WARNING" "Impossible de déterminer la charge CPU du VPS, utilisation de la valeur par défaut: ${vps_cpu_load}"
        fi
    fi

    log "INFO" "CPU du VPS: ${vps_cpu_cores} cœurs, charge actuelle: ${vps_cpu_load}"

    if [[ ${vps_cpu_cores} -lt 2 ]]; then
        log "WARNING" "Nombre de cœurs CPU du VPS insuffisant: ${vps_cpu_cores} (recommandé: 2 minimum)"
        log "WARNING" "Des problèmes de performance peuvent survenir pendant l'installation"
    fi

    # Vérification de la charge CPU
    if (( $(echo "${vps_cpu_load} > ${vps_cpu_cores}" | bc -l) )); then
        log "WARNING" "Charge CPU du VPS élevée: ${vps_cpu_load} (nombre de cœurs: ${vps_cpu_cores})"
        log "WARNING" "Le VPS est actuellement sous forte charge, ce qui peut affecter l'installation"

        # Vérification des processus consommant le plus de CPU
        log "INFO" "Processus consommant le plus de CPU sur le VPS:"
        local top_cpu_processes

        if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
            # Exécution locale
            top_cpu_processes=$(ps aux --sort=-%cpu | head -6 2>/dev/null || echo "Impossible de déterminer les processus")
        else
            # Exécution distante
            top_cpu_processes=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "ps aux --sort=-%cpu | head -6" 2>/dev/null || echo "Impossible de déterminer les processus")
        fi
        echo "${top_cpu_processes}"
    fi

    # Vérification des processus consommant le plus de mémoire
    if [[ ${vps_memory_available} -lt 1024 ]]; then
        log "WARNING" "Mémoire disponible du VPS faible: ${vps_memory_available}MB"
        log "INFO" "Processus consommant le plus de mémoire sur le VPS:"
        local top_mem_processes

        if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
            # Exécution locale
            top_mem_processes=$(ps aux --sort=-%mem | head -6 2>/dev/null || echo "Impossible de déterminer les processus")
        else
            # Exécution distante
            top_mem_processes=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "ps aux --sort=-%mem | head -6" 2>/dev/null || echo "Impossible de déterminer les processus")
        fi
        echo "${top_mem_processes}"
    fi

    # Vérification des services en cours d'exécution
    log "INFO" "Vérification des services en cours d'exécution sur le VPS..."
    local running_services

    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        # Exécution locale
        running_services=$(systemctl list-units --type=service --state=running | grep -v systemd | head -10 2>/dev/null || echo "Impossible de déterminer les services")
    else
        # Exécution distante
        running_services=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "systemctl list-units --type=service --state=running | grep -v systemd | head -10" 2>/dev/null || echo "Impossible de déterminer les services")
    fi

    log "INFO" "Services en cours d'exécution sur le VPS (top 10):"
    echo "${running_services}" | grep -v "UNIT\|LOAD\|ACTIVE\|SUB\|DESCRIPTION\|^$\|loaded units listed"

    # Vérification des ports ouverts
    log "INFO" "Vérification des ports ouverts sur le VPS..."
    local open_ports

    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        # Exécution locale
        open_ports=$(ss -tuln | grep LISTEN 2>/dev/null || echo "Impossible de déterminer les ports ouverts")
    else
        # Exécution distante
        open_ports=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "ss -tuln | grep LISTEN" 2>/dev/null || echo "Impossible de déterminer les ports ouverts")
    fi

    log "INFO" "Ports ouverts sur le VPS:"
    echo "${open_ports}"

    # Vérification des conflits potentiels
    for port in "${REQUIRED_PORTS[@]}"; do
        if echo "${open_ports}" | grep -q ":${port} "; then
            log "WARNING" "Le port ${port} est déjà utilisé sur le VPS, ce qui peut causer des conflits"
        fi
    done

    log "SUCCESS" "Vérification des ressources système du VPS terminée"
    return 0
}

# Fonction pour vérifier l'espace disque disponible (pour compatibilité)
function check_disk_space() {
    check_local_resources
    return $?
}

# Fonction pour détecter si le script est exécuté sur le VPS cible
function is_local_execution() {
    local target_host="$1"

    # Si l'hôte cible est localhost ou 127.0.0.1, c'est une exécution locale
    if [[ "${target_host}" == "localhost" || "${target_host}" == "127.0.0.1" ]]; then
        return 0
    fi

    # Récupération des adresses IP locales
    local local_ips=$(ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1 | tr '\n' ' ' 2>/dev/null || echo "")

    # Si l'hôte cible est une des adresses IP locales, c'est une exécution locale
    for ip in ${local_ips}; do
        if [[ "${target_host}" == "${ip}" ]]; then
            return 0
        fi
    done

    # Vérification du nom d'hôte
    local hostname=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "")
    if [[ -n "${hostname}" && "${target_host}" == "${hostname}" ]]; then
        return 0
    fi

    # Ce n'est pas une exécution locale
    return 1
}

# Variable globale pour indiquer si le script est exécuté sur le VPS cible
IS_LOCAL_EXECUTION=false

# Fonction pour extraire les informations d'inventaire
function extraire_informations_inventaire() {
    log "INFO" "Extraction des informations d'inventaire depuis ${inventory_file}..."

    # Vérification de l'existence du fichier d'inventaire
    if [[ ! -f "${ANSIBLE_DIR}/${inventory_file}" ]]; then
        log "ERROR" "Fichier d'inventaire non trouvé: ${ANSIBLE_DIR}/${inventory_file}"
        cleanup
        exit 1
    fi

    # Extraction des informations d'inventaire avec Python
    local python_script=$(cat << 'EOF'
import sys
import yaml
import os

inventory_file = sys.argv[1]

try:
    with open(inventory_file, 'r') as f:
        inventory = yaml.safe_load(f)

    # Recherche du premier hôte VPS
    vps_host = None
    vps_port = None
    vps_user = None

    if 'all' in inventory and 'children' in inventory['all'] and 'vps' in inventory['all']['children']:
        vps_hosts = inventory['all']['children']['vps'].get('hosts', {})
        if vps_hosts:
            first_host = next(iter(vps_hosts))
            host_info = vps_hosts[first_host]
            vps_host = host_info.get('ansible_host')
            default_port = os.environ.get('LIONS_VPS_PORT', '225')
            vps_port = host_info.get('ansible_port', default_port)
            vps_user = host_info.get('ansible_user')

    # Recherche dans les variables globales si non trouvé
    if not vps_user and 'all' in inventory and 'vars' in inventory['all']:
        vps_user = inventory['all']['vars'].get('ansible_user')

    # Affichage des résultats
    if vps_host:
        print(f"ansible_host={vps_host}")
    if vps_port:
        print(f"ansible_port={vps_port}")
    if vps_user:
        print(f"ansible_user={vps_user}")

except Exception as e:
    print(f"error={str(e)}", file=sys.stderr)
    sys.exit(1)
EOF
)

    # Exécution du script Python avec timeout
    log "DEBUG" "Exécution du script Python pour extraire les informations d'inventaire..."

    # Vérification que Python3 est installé
    if ! command_exists python3; then
        log "ERROR" "Python3 n'est pas installé, impossible d'extraire les informations d'inventaire"
        log "ERROR" "Installez Python3 avec: sudo apt-get install python3 (Debian/Ubuntu)"
        log "ERROR" "ou l'équivalent pour votre distribution"

        # Passage directement à la méthode fallback
        log "WARNING" "Tentative de fallback avec grep pour extraire les informations d'inventaire..."

        # Utilisation de grep avec timeout pour éviter les blocages
        ansible_host=$(timeout 5 grep -A10 "hosts:" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_host:" | head -1 | awk -F': ' '{print $2}' | tr -d ' ' 2>/dev/null || echo "")
        ansible_port=$(timeout 5 grep -A10 "hosts:" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_port:" | head -1 | awk -F': ' '{print $2}' | tr -d ' ' 2>/dev/null || echo "${LIONS_VPS_PORT:-22}")
        ansible_user=$(timeout 5 grep -A10 "hosts:" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_user:" | head -1 | awk -F': ' '{print $2}' | tr -d ' ' 2>/dev/null || echo "")

        # Si toujours pas trouvé, chercher dans les variables globales
        if [[ -z "${ansible_user}" ]]; then
            ansible_user=$(timeout 5 grep -A10 "vars:" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_user:" | head -1 | awk -F': ' '{print $2}' | tr -d ' ' 2>/dev/null || echo "")
        fi

        # Vérification des valeurs extraites par fallback
        if [[ -n "${ansible_host}" && -n "${ansible_user}" ]]; then
            log "SUCCESS" "Extraction des informations d'inventaire réussie avec la méthode fallback"
            log "INFO" "Informations d'inventaire extraites (fallback):"
            log "INFO" "- Hôte: ${ansible_host}"
            log "INFO" "- Port: ${ansible_port}"
            log "INFO" "- Utilisateur: ${ansible_user}"
            return 0
        else
            log "ERROR" "Échec de l'extraction des informations d'inventaire, même avec la méthode fallback"
            cleanup
            exit 1
        fi
    fi

    # Affichage du contenu du fichier d'inventaire en mode debug
    if [[ "${debug_mode}" == "true" ]]; then
        log "DEBUG" "Contenu du fichier d'inventaire (${ANSIBLE_DIR}/${inventory_file}):"
        cat "${ANSIBLE_DIR}/${inventory_file}" | while IFS= read -r line; do
            log "DEBUG" "  ${line}"
        done
    fi

    # Exécution avec timeout pour éviter les blocages
    local inventory_info=$(timeout 10 python3 -c "${python_script}" "${ANSIBLE_DIR}/${inventory_file}" 2>&1)
    local exit_code=$?

    if [[ ${exit_code} -eq 124 ]]; then
        log "ERROR" "Timeout lors de l'extraction des informations d'inventaire"
        log "ERROR" "Le script Python a pris trop de temps pour s'exécuter"
        log "ERROR" "Vérifiez le fichier d'inventaire et les dépendances Python"
        cleanup
        exit 1
    elif [[ ${exit_code} -ne 0 ]]; then
        log "ERROR" "Impossible d'extraire les informations d'inventaire (code ${exit_code})"
        log "ERROR" "Erreur: ${inventory_info}"
        log "ERROR" "Vérifiez le format du fichier d'inventaire et les dépendances Python (yaml)"

        # Vérification de la présence du module yaml
        if ! python3 -c "import yaml" &>/dev/null; then
            log "WARNING" "Le module Python 'yaml' n'est pas installé"
            log "INFO" "Tentative d'installation automatique du module yaml..."

            # Vérification de pip
            if ! command_exists pip3 && ! command_exists pip; then
                log "ERROR" "pip n'est pas installé, impossible d'installer le module yaml"
                log "ERROR" "Installez pip avec: sudo apt-get install python3-pip (Debian/Ubuntu)"
                log "ERROR" "ou l'équivalent pour votre distribution"
            else
                # Installation du module yaml
                local pip_cmd="pip3"
                if ! command_exists pip3; then
                    pip_cmd="pip"
                fi

                if secure_sudo ${pip_cmd} install pyyaml &>/dev/null; then
                    log "SUCCESS" "Module yaml installé avec succès"
                    # Réessayer l'extraction après l'installation
                    inventory_info=$(timeout 10 python3 -c "${python_script}" "${ANSIBLE_DIR}/${inventory_file}" 2>&1)
                    exit_code=$?

                    if [[ ${exit_code} -eq 0 ]]; then
                        log "SUCCESS" "Extraction des informations d'inventaire réussie après installation du module yaml"
                    else
                        log "ERROR" "Échec de l'extraction des informations d'inventaire même après installation du module yaml"
                    fi
                else
                    log "ERROR" "Échec de l'installation du module yaml"
                    log "ERROR" "Installez-le manuellement avec: sudo pip3 install pyyaml"
                fi
            fi
        fi

        # Tentative de fallback avec grep si le script Python échoue
        log "WARNING" "Tentative de fallback avec grep pour extraire les informations d'inventaire..."

        # Utilisation de grep avec timeout pour éviter les blocages
        ansible_host=$(timeout 5 grep -A10 "hosts:" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_host:" | head -1 | awk -F': ' '{print $2}' | tr -d ' ' 2>/dev/null || echo "")
        ansible_port=$(timeout 5 grep -A10 "hosts:" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_port:" | head -1 | awk -F': ' '{print $2}' | tr -d ' ' 2>/dev/null || echo "${LIONS_VPS_PORT:-22}")
        ansible_user=$(timeout 5 grep -A10 "hosts:" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_user:" | head -1 | awk -F': ' '{print $2}' | tr -d ' ' 2>/dev/null || echo "")

        # Si toujours pas trouvé, chercher dans les variables globales
        if [[ -z "${ansible_user}" ]]; then
            ansible_user=$(timeout 5 grep -A10 "vars:" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_user:" | head -1 | awk -F': ' '{print $2}' | tr -d ' ' 2>/dev/null || echo "")
        fi

        # Vérification des valeurs extraites par fallback
        if [[ -n "${ansible_host}" && -n "${ansible_user}" ]]; then
            log "SUCCESS" "Extraction des informations d'inventaire réussie avec la méthode fallback"
            log "INFO" "Informations d'inventaire extraites (fallback):"
            log "INFO" "- Hôte: ${ansible_host}"
            log "INFO" "- Port: ${ansible_port}"
            log "INFO" "- Utilisateur: ${ansible_user}"
            return 0
        else
            log "ERROR" "Échec de l'extraction des informations d'inventaire, même avec la méthode fallback"
            cleanup
            exit 1
        fi
    fi

    # Extraction des valeurs
    ansible_host=$(echo "${inventory_info}" | grep "ansible_host=" | cut -d'=' -f2)
    ansible_port=$(echo "${inventory_info}" | grep "ansible_port=" | cut -d'=' -f2)
    ansible_user=$(echo "${inventory_info}" | grep "ansible_user=" | cut -d'=' -f2)

    # Valeurs par défaut si non trouvées
    ansible_host="${ansible_host:-localhost}"
    ansible_port="${ansible_port:-${LIONS_VPS_PORT:-225}}"
    ansible_user="${ansible_user:-$(whoami)}"

    log "INFO" "Informations d'inventaire extraites:"
    log "INFO" "- Hôte: ${ansible_host}"
    log "INFO" "- Port: ${ansible_port}"
    log "INFO" "- Utilisateur: ${ansible_user}"

    # Vérification si le script est exécuté sur le VPS cible
    if is_local_execution "${ansible_host}"; then
        IS_LOCAL_EXECUTION=true
        log "INFO" "Détection d'exécution locale: le script est exécuté directement sur le VPS cible"
        log "INFO" "Les commandes SSH seront remplacées par des commandes locales"
    else
        IS_LOCAL_EXECUTION=false
        log "INFO" "Détection d'exécution distante: le script est exécuté depuis une machine différente du VPS cible"
    fi

    return 0
}

# Fonction pour ouvrir les ports requis sur le VPS
function open_required_ports() {
    local target_host="${ansible_host}"
    local target_port="${ansible_port}"
    local ports_to_open=("$@")
    local timeout=10
    local success=true

    log "INFO" "Tentative d'ouverture des ports requis sur ${target_host}..."

    # Vérification que nous avons des ports à ouvrir
    if [[ ${#ports_to_open[@]} -eq 0 ]]; then
        log "WARNING" "Aucun port à ouvrir spécifié"
        return 0
    fi

    # Vérification si exécution locale ou distante
    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        log "INFO" "Exécution locale détectée, utilisation de commandes locales pour ouvrir les ports"

        # Vérification que UFW est installé et actif
        if ! command -v ufw &>/dev/null || ! systemctl is-active --quiet ufw; then
            log "WARNING" "UFW n'est pas installé ou n'est pas actif sur le VPS"
            log "INFO" "Tentative d'installation et d'activation de UFW..."

            # Installation de UFW si nécessaire
            log "INFO" "Installation de UFW (commande interactive, veuillez entrer votre mot de passe si demandé)..."
            if ! sudo apt-get update && sudo apt-get install -y ufw; then
                log "ERROR" "Impossible d'installer UFW"
                return 1
            fi

            # Activation de UFW
            log "INFO" "Activation de UFW (commande interactive, veuillez entrer votre mot de passe si demandé)..."
            if ! sudo ufw --force enable; then
                log "ERROR" "Impossible d'activer UFW"
                return 1
            fi

            # Vérification que UFW est bien actif
            log "INFO" "Vérification que UFW est bien actif..."
            if ! sudo ufw status | grep -q "Status: active"; then
                log "WARNING" "UFW n'est pas actif malgré la tentative d'activation, nouvelle tentative..."
                # Deuxième tentative avec une approche différente
                if ! (echo 'y' | sudo ufw --force enable && sudo systemctl restart ufw); then
                    log "ERROR" "Impossible d'activer UFW malgré plusieurs tentatives"
                    return 1
                fi

                # Vérification finale
                if ! sudo ufw status | grep -q "Status: active"; then
                    log "ERROR" "Impossible d'activer UFW malgré plusieurs tentatives"
                    return 1
                else
                    log "SUCCESS" "UFW est maintenant actif après la deuxième tentative"
                fi
            else
                log "SUCCESS" "UFW est bien actif"
            fi

            log "SUCCESS" "UFW installé et activé avec succès"
        fi
    else
        # Vérification de la connexion SSH
        if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p "${target_port}" "${ansible_user}@${target_host}" "echo 'Test de connexion'" &>/dev/null; then
            log "ERROR" "Impossible de se connecter au VPS via SSH pour ouvrir les ports"
            return 1
        fi

        # Vérification que UFW est installé et actif
        if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p "${target_port}" "${ansible_user}@${target_host}" "command -v ufw &>/dev/null && systemctl is-active --quiet ufw" &>/dev/null; then
            log "WARNING" "UFW n'est pas installé ou n'est pas actif sur le VPS"
            log "INFO" "Tentative d'installation et d'activation de UFW..."

            # Installation de UFW si nécessaire
            log "INFO" "Installation de UFW sur le VPS (commande interactive, veuillez entrer votre mot de passe si demandé)..."
            local ssh_cmd="ssh -t -o StrictHostKeyChecking=no -o ConnectTimeout=${timeout} -p \"${target_port}\" \"${ansible_user}@${target_host}\" \"sudo apt-get update && sudo apt-get install -y ufw\""
            log "DEBUG" "Exécution de la commande avec eval: ${ssh_cmd}"
            eval "${ssh_cmd}"
            if [ $? -ne 0 ]; then
                log "ERROR" "Impossible d'installer UFW sur le VPS"
                return 1
            fi

            # Activation de UFW
            log "INFO" "Activation de UFW sur le VPS (commande interactive, veuillez entrer votre mot de passe si demandé)..."
            local ssh_cmd="ssh -t -o StrictHostKeyChecking=no -o ConnectTimeout=${timeout} -p \"${target_port}\" \"${ansible_user}@${target_host}\" \"sudo ufw --force enable\""
            log "DEBUG" "Exécution de la commande avec eval: ${ssh_cmd}"
            eval "${ssh_cmd}"
            if [ $? -ne 0 ]; then
                log "ERROR" "Impossible d'activer UFW sur le VPS"
                return 1
            fi

            # Vérification que UFW est bien actif
            log "INFO" "Vérification que UFW est bien actif..."
            local ufw_status_cmd="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=${timeout} -p \"${target_port}\" \"${ansible_user}@${target_host}\" \"sudo ufw status | grep -q 'Status: active' && echo 'active' || echo 'inactive'\""
            local ufw_status=$(eval "${ufw_status_cmd}" 2>/dev/null)

            if [[ "${ufw_status}" != "active" ]]; then
                log "WARNING" "UFW n'est pas actif malgré la tentative d'activation, nouvelle tentative..."
                # Deuxième tentative avec une approche différente
                local ssh_cmd="ssh -t -o StrictHostKeyChecking=no -o ConnectTimeout=${timeout} -p \"${target_port}\" \"${ansible_user}@${target_host}\" \"echo 'y' | sudo ufw --force enable && sudo systemctl restart ufw\""
                log "DEBUG" "Exécution de la commande avec eval: ${ssh_cmd}"
                eval "${ssh_cmd}"

                # Vérification finale
                local ufw_status_cmd="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=${timeout} -p \"${target_port}\" \"${ansible_user}@${target_host}\" \"sudo ufw status | grep -q 'Status: active' && echo 'active' || echo 'inactive'\""
                local ufw_status=$(eval "${ufw_status_cmd}" 2>/dev/null)

                if [[ "${ufw_status}" != "active" ]]; then
                    log "ERROR" "Impossible d'activer UFW sur le VPS malgré plusieurs tentatives"
                    return 1
                else
                    log "SUCCESS" "UFW est maintenant actif après la deuxième tentative"
                fi
            else
                log "SUCCESS" "UFW est bien actif"
            fi

            log "SUCCESS" "UFW installé et activé avec succès"
        fi
    fi

    # Ouverture des ports
    log "INFO" "Ouverture des ports: ${ports_to_open[*]}"

    for port in "${ports_to_open[@]}"; do
        log "INFO" "Ouverture du port ${port}..."

        if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
            # Exécution locale

            # Vérification si le port est déjà ouvert
            log "INFO" "Vérification si le port ${port} est déjà ouvert (commande interactive, veuillez entrer votre mot de passe si demandé)..."
            if sudo ufw status | grep -E "^${port}/(tcp|udp)" &>/dev/null; then
                log "INFO" "Le port ${port} est déjà ouvert dans UFW"
                continue
            fi

            # Validation du port
            if ! [[ "${port}" =~ ^[0-9]+$ ]] || [ "${port}" -lt 1 ] || [ "${port}" -gt 65535 ]; then
                log "WARNING" "Port invalide: ${port}. Les ports doivent être des nombres entre 1 et 65535."
                success=false
                continue
            fi

            # Ouverture du port TCP
            log "INFO" "Ouverture du port ${port}/tcp (commande interactive, veuillez entrer votre mot de passe si demandé)..."
            if ! sudo ufw allow "${port}/tcp"; then
                log "ERROR" "Impossible d'ouvrir le port ${port}/tcp"
                success=false
                continue
            fi

            # Ouverture du port UDP
            log "INFO" "Ouverture du port ${port}/udp (commande interactive, veuillez entrer votre mot de passe si demandé)..."
            if ! sudo ufw allow "${port}/udp"; then
                log "WARNING" "Impossible d'ouvrir le port ${port}/udp"
                # Ne pas échouer pour UDP, car certains services n'utilisent que TCP
            fi
        else
            # Exécution distante

            # Vérification si le port est déjà ouvert
            log "INFO" "Vérification si le port ${port} est déjà ouvert (commande interactive, veuillez entrer votre mot de passe si demandé)..."
            local ssh_cmd="ssh -tt -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p \"${target_port}\" \"${ansible_user}@${target_host}\" \"sudo ufw status | grep -E \\\"^${port}/(tcp|udp)\\\"\""
            log "DEBUG" "Exécution de la commande avec eval: ${ssh_cmd}"
            eval "${ssh_cmd}"
            if [ $? -eq 0 ]; then
                log "INFO" "Le port ${port} est déjà ouvert dans UFW"
                continue
            fi

            # Validation du port
            if ! [[ "${port}" =~ ^[0-9]+$ ]] || [ "${port}" -lt 1 ] || [ "${port}" -gt 65535 ]; then
                log "WARNING" "Port invalide: ${port}. Les ports doivent être des nombres entre 1 et 65535."
                success=false
                continue
            fi

            # Ouverture du port TCP
            log "INFO" "Ouverture du port ${port}/tcp sur le VPS (commande interactive, veuillez entrer votre mot de passe si demandé)..."
            local ssh_cmd="ssh -tt -o StrictHostKeyChecking=no -o ConnectTimeout=${timeout} -p \"${target_port}\" \"${ansible_user}@${target_host}\" \"sudo ufw allow \\\"${port}/tcp\\\"\""
            log "DEBUG" "Exécution de la commande avec eval: ${ssh_cmd}"
            eval "${ssh_cmd}"
            if [ $? -ne 0 ]; then
                log "ERROR" "Impossible d'ouvrir le port ${port}/tcp sur le VPS"
                success=false
                continue
            fi

            # Ouverture du port UDP
            log "INFO" "Ouverture du port ${port}/udp sur le VPS (commande interactive, veuillez entrer votre mot de passe si demandé)..."
            local ssh_cmd="ssh -tt -o StrictHostKeyChecking=no -o ConnectTimeout=${timeout} -p \"${target_port}\" \"${ansible_user}@${target_host}\" \"sudo ufw allow \\\"${port}/udp\\\"\""
            log "DEBUG" "Exécution de la commande avec eval: ${ssh_cmd}"
            eval "${ssh_cmd}"
            if [ $? -ne 0 ]; then
                log "WARNING" "Impossible d'ouvrir le port ${port}/udp sur le VPS"
                # Ne pas échouer pour UDP, car certains services n'utilisent que TCP
            fi
        fi

        log "SUCCESS" "Port ${port} ouvert avec succès"
    done

    # Rechargement des règles UFW
    log "INFO" "Rechargement des règles UFW (commande interactive, veuillez entrer votre mot de passe si demandé)..."

    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        # Exécution locale
        if ! sudo ufw reload; then
            log "WARNING" "Impossible de recharger les règles UFW"
            # Ne pas échouer pour le rechargement, car les règles sont déjà appliquées
        fi
    else
        # Exécution distante
        local ssh_cmd="ssh -tt -o StrictHostKeyChecking=no -o ConnectTimeout=${timeout} -p \"${target_port}\" \"${ansible_user}@${target_host}\" \"sudo ufw reload\""
        log "DEBUG" "Exécution de la commande avec eval: ${ssh_cmd}"
        eval "${ssh_cmd}"
        if [ $? -ne 0 ]; then
            log "WARNING" "Impossible de recharger les règles UFW"
            # Ne pas échouer pour le rechargement, car les règles sont déjà appliquées
        fi
    fi

    # Vérification que les ports sont bien ouverts
    log "INFO" "Vérification que les ports sont bien ouverts..."
    local failed_ports=()

    for port in "${ports_to_open[@]}"; do
        log "INFO" "Vérification que le port ${port} est bien ouvert (commande interactive, veuillez entrer votre mot de passe si demandé)..."

        if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
            # Exécution locale
            if ! sudo ufw status | grep -E "^${port}/(tcp|udp)" &>/dev/null; then
                log "WARNING" "Le port ${port} ne semble pas être correctement ouvert dans UFW"
                failed_ports+=("${port}")
                success=false
            fi
        else
            # Exécution distante
            local ssh_cmd="ssh -tt -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p \"${target_port}\" \"${ansible_user}@${target_host}\" \"sudo ufw status | grep -E \\\"^${port}/(tcp|udp)\\\"\""
            log "DEBUG" "Exécution de la commande avec eval: ${ssh_cmd}"
            eval "${ssh_cmd}"
            if [ $? -ne 0 ]; then
                log "WARNING" "Le port ${port} ne semble pas être correctement ouvert dans UFW"
                failed_ports+=("${port}")
                success=false
            fi
        fi
    done

    if [[ ${#failed_ports[@]} -gt 0 ]]; then
        log "WARNING" "Les ports suivants n'ont pas pu être ouverts: ${failed_ports[*]}"
    fi

    # Affichage du statut UFW
    log "INFO" "Récupération du statut UFW (commande interactive, veuillez entrer votre mot de passe si demandé)..."
    local ufw_status=""

    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        # Exécution locale
        ufw_status=$(sudo ufw status || echo "Impossible de récupérer le statut UFW")
    else
        # Exécution distante
        local ssh_cmd="ssh -tt -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p \"${target_port}\" \"${ansible_user}@${target_host}\" \"sudo ufw status\""
        log "DEBUG" "Exécution de la commande avec eval: ${ssh_cmd}"
        ufw_status=$(eval "${ssh_cmd}" || echo "Impossible de récupérer le statut UFW")
    fi

    log "INFO" "Statut UFW actuel:"
    echo "${ufw_status}"

    # Vérification finale que UFW est bien actif
    if ! echo "${ufw_status}" | grep -q "Status: active"; then
        log "WARNING" "UFW n'est pas actif après toutes les opérations, tentative finale d'activation..."

        if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
            # Exécution locale
            if ! (echo 'y' | sudo ufw --force enable && sudo systemctl restart ufw); then
                log "ERROR" "Impossible d'activer UFW malgré plusieurs tentatives"
            else
                log "SUCCESS" "UFW est maintenant actif après la tentative finale"
                # Affichage du statut mis à jour
                ufw_status=$(sudo ufw status || echo "Impossible de récupérer le statut UFW")
                log "INFO" "Statut UFW mis à jour:"
                echo "${ufw_status}"
            fi
        else
            # Exécution distante
            local ssh_cmd="ssh -t -o StrictHostKeyChecking=no -o ConnectTimeout=${timeout} -p \"${target_port}\" \"${ansible_user}@${target_host}\" \"echo 'y' | sudo ufw --force enable && sudo systemctl restart ufw\""
            log "DEBUG" "Exécution de la commande avec eval: ${ssh_cmd}"
            eval "${ssh_cmd}"

            # Affichage du statut mis à jour
            local ssh_cmd="ssh -tt -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p \"${target_port}\" \"${ansible_user}@${target_host}\" \"sudo ufw status\""
            ufw_status=$(eval "${ssh_cmd}" || echo "Impossible de récupérer le statut UFW")
            log "INFO" "Statut UFW mis à jour:"
            echo "${ufw_status}"

            if ! echo "${ufw_status}" | grep -q "Status: active"; then
                log "ERROR" "Impossible d'activer UFW malgré plusieurs tentatives"
            else
                log "SUCCESS" "UFW est maintenant actif après la tentative finale"
            fi
        fi
    fi

    if [[ "${success}" == "true" ]]; then
        log "SUCCESS" "Tous les ports ont été ouverts avec succès"
        return 0
    else
        log "WARNING" "Certains ports n'ont pas pu être ouverts"
        return 1
    fi
}

# Fonction pour vérifier la connectivité réseau de manière approfondie
function check_network() {
    local target_host="${ansible_host}"
    local target_port="${ansible_port}"
    local retry_count=3
    local timeout=5
    local success=false

    # Si le script est exécuté sur le VPS cible, pas besoin de vérifier la connectivité réseau
    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        log "INFO" "Exécution locale détectée, vérification de la connectivité réseau ignorée"
        return 0
    fi

    log "INFO" "Vérification approfondie de la connectivité réseau vers ${target_host}..."

    if [[ -z "${target_host}" ]]; then
        log "ERROR" "Impossible de déterminer l'adresse du VPS"
        return 1
    fi

    # Vérification de la résolution DNS
    log "INFO" "Vérification de la résolution DNS pour ${target_host}..."
    if [[ "${target_host}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log "INFO" "L'adresse ${target_host} est une adresse IP, pas besoin de résolution DNS"
    else
        # Tentative de résolution DNS
        local resolved_ip=""
        for ((i=1; i<=retry_count; i++)); do
            resolved_ip=$(dig +short "${target_host}" 2>/dev/null || host "${target_host}" 2>/dev/null | grep "has address" | awk '{print $4}' || nslookup "${target_host}" 2>/dev/null | grep "Address:" | tail -n1 | awk '{print $2}')

            if [[ -n "${resolved_ip}" ]]; then
                log "INFO" "Résolution DNS réussie: ${target_host} -> ${resolved_ip}"
                success=true
                break
            else
                log "WARNING" "Tentative ${i}/${retry_count}: Échec de la résolution DNS pour ${target_host}"
                sleep 2
            fi
        done

        if [[ "${success}" != "true" ]]; then
            log "ERROR" "Impossible de résoudre l'adresse DNS pour ${target_host}"
            log "ERROR" "Vérifiez votre connexion Internet et la configuration DNS"

            # Vérification des serveurs DNS
            log "INFO" "Vérification des serveurs DNS..."
            local dns_servers=$(cat /etc/resolv.conf | grep "nameserver" | awk '{print $2}')

            if [[ -z "${dns_servers}" ]]; then
                log "ERROR" "Aucun serveur DNS configuré"
            else
                log "INFO" "Serveurs DNS configurés: ${dns_servers}"

                # Test de connectivité vers les serveurs DNS
                for dns in ${dns_servers}; do
                    if ping -c 1 -W 5 "${dns}" &>/dev/null; then
                        log "INFO" "Serveur DNS ${dns} accessible"
                    else
                        log "WARNING" "Serveur DNS ${dns} inaccessible"
                    fi
                done
            fi

            # Suggestion de solution
            log "INFO" "Suggestions:"
            log "INFO" "1. Vérifiez votre connexion Internet"
            log "INFO" "2. Vérifiez que le nom d'hôte ${target_host} est correct"
            log "INFO" "3. Essayez d'utiliser une adresse IP directement dans le fichier d'inventaire"

            return 1
        fi
    fi

    # Vérification de la connectivité ICMP (ping)
    log "INFO" "Vérification de la connectivité ICMP vers ${target_host}..."
    success=false

    for ((i=1; i<=retry_count; i++)); do
        if ping -c 3 -W ${timeout} "${target_host}" &>/dev/null; then
            log "INFO" "Connectivité ICMP vers ${target_host} vérifiée avec succès"
            success=true
            break
        else
            log "WARNING" "Tentative ${i}/${retry_count}: Échec de la connectivité ICMP vers ${target_host}"
            sleep 2
        fi
    done

    if [[ "${success}" != "true" ]]; then
        log "WARNING" "Impossible de joindre le VPS par ICMP (ping) à l'adresse ${target_host}"
        log "WARNING" "Le pare-feu du VPS bloque peut-être les pings, tentative de connexion TCP..."
    fi

    # Vérification de la connectivité TCP (SSH)
    log "INFO" "Vérification de la connectivité TCP (SSH) vers ${target_host}:${target_port}..."
    success=false

    for ((i=1; i<=retry_count; i++)); do
        if nc -z -w ${timeout} "${target_host}" "${target_port}" &>/dev/null; then
            log "INFO" "Connectivité TCP (SSH) vers ${target_host}:${target_port} vérifiée avec succès"
            success=true
            break
        else
            log "WARNING" "Tentative ${i}/${retry_count}: Échec de la connectivité TCP vers ${target_host}:${target_port}"
            sleep 2
        fi
    done

    if [[ "${success}" != "true" ]]; then
        log "ERROR" "Impossible de joindre le VPS par TCP (SSH) à l'adresse ${target_host}:${target_port}"
        log "ERROR" "Vérifiez que le VPS est en ligne et que le port SSH est ouvert"

        # Vérification de la route réseau
        log "INFO" "Vérification de la route réseau vers ${target_host}..."
        local traceroute_output=$(traceroute -m 15 "${target_host}" 2>/dev/null || tracepath -m 15 "${target_host}" 2>/dev/null || true)

        if [[ -n "${traceroute_output}" ]]; then
            log "INFO" "Route réseau vers ${target_host}:"
            echo "${traceroute_output}" | head -10
        else
            log "WARNING" "Impossible de déterminer la route réseau vers ${target_host}"
        fi

        # Suggestion de solution
        log "INFO" "Suggestions:"
        log "INFO" "1. Vérifiez que le VPS est en ligne"
        log "INFO" "2. Vérifiez que le port SSH (${target_port}) est ouvert sur le VPS"
        log "INFO" "3. Vérifiez les règles de pare-feu sur le VPS et sur votre réseau local"

        return 1
    fi

    # Vérification des ports requis
    log "INFO" "Vérification des ports requis sur ${target_host}..."
    local open_ports=()
    local closed_ports=()

    for port in "${REQUIRED_PORTS[@]}"; do
        # Si le port est le port SSH et que nous avons déjà vérifié la connectivité SSH, le considérer comme ouvert
        if [[ "${port}" == "${target_port}" ]]; then
            log "INFO" "Port ${port} (SSH) accessible sur ${target_host} (déjà vérifié)"
            open_ports+=("${port}")
            continue
        fi

        # Augmenter le timeout pour les vérifications de port
        if nc -z -w $((timeout*2)) "${target_host}" "${port}" &>/dev/null; then
            log "INFO" "Port ${port} accessible sur ${target_host}"
            open_ports+=("${port}")
        else
            # Deuxième tentative avec un délai
            sleep 1
            if nc -z -w $((timeout*2)) "${target_host}" "${port}" &>/dev/null; then
                log "INFO" "Port ${port} accessible sur ${target_host} (deuxième tentative)"
                open_ports+=("${port}")
            else
                log "WARNING" "Port ${port} non accessible sur ${target_host}"
                closed_ports+=("${port}")
            fi
        fi
        # Ajout d'un petit délai entre chaque vérification de port pour éviter les problèmes d'affichage
        sleep 0.1
    done

    # Résumé des ports
    if [[ ${#open_ports[@]} -eq ${#REQUIRED_PORTS[@]} ]]; then
        log "SUCCESS" "Tous les ports requis sont accessibles sur ${target_host}"
    else
        log "WARNING" "Certains ports requis ne sont pas accessibles sur ${target_host}"
        # Utilisation d'IFS pour formater les listes de ports avec des virgules
        local IFS=","
        log "INFO" "Ports ouverts: ${open_ports[*]}"
        # Ajout d'un délai pour s'assurer que les messages sont affichés séparément
        sleep 0.1
        log "WARNING" "Ports fermés: ${closed_ports[*]}"
        # Restauration de l'IFS par défaut
        unset IFS

        # Ouverture automatique des ports requis sans demander à l'utilisateur
        log "INFO" "Des ports requis sont fermés. Ouverture automatique des ports..."

        # Définir answer comme "o" pour toujours ouvrir les ports automatiquement
        answer="o"

        if [[ "${answer}" =~ ^[Oo]$ ]]; then
            # Tentative d'ouverture des ports fermés
            log "INFO" "Tentative d'ouverture automatique des ports fermés..."
            if open_required_ports "${closed_ports[@]}"; then
                log "SUCCESS" "Ports ouverts avec succès"

                # Vérification que les ports sont maintenant accessibles
                local still_closed_ports=()
                for port in "${closed_ports[@]}"; do
                    if ! nc -z -w ${timeout} "${target_host}" "${port}" &>/dev/null; then
                        still_closed_ports+=("${port}")
                    else
                        open_ports+=("${port}")
                    fi
                done

                if [[ ${#still_closed_ports[@]} -eq 0 ]]; then
                    log "SUCCESS" "Tous les ports sont maintenant accessibles"
                    closed_ports=()
                else
                    log "WARNING" "Certains ports sont toujours inaccessibles malgré l'ouverture dans le pare-feu"
                    log "WARNING" "Cela peut être dû à un pare-feu externe ou à des services non démarrés"
                    closed_ports=("${still_closed_ports[@]}")
                    # Utilisation d'IFS pour formater la liste des ports avec des virgules
                    local IFS=","
                    log "INFO" "Ports toujours fermés: ${closed_ports[*]}"
                    # Restauration de l'IFS par défaut
                    unset IFS
                    # Ajout d'un délai pour s'assurer que les messages suivants sont affichés séparément
                    sleep 0.1
                fi
            else
                log "WARNING" "Impossible d'ouvrir automatiquement certains ports"
                log "WARNING" "Vous devrez peut-être les ouvrir manuellement"
            fi
        else
            log "INFO" "Ouverture automatique des ports annulée par l'utilisateur"
        fi

        # Vérification si le port SSH est ouvert (seul port vraiment essentiel)
        if ! nc -z -w ${timeout} "${target_host}" "${target_port}" &>/dev/null; then
            log "ERROR" "Le port SSH (${target_port}) n'est pas accessible, impossible de continuer"
            log "INFO" "Suggestions:"
            log "INFO" "1. Vérifiez les règles de pare-feu sur le VPS"
            log "INFO" "2. Vérifiez que le service SSH est en cours d'exécution sur le VPS"
            return 1
        else
            log "WARNING" "Certains ports non essentiels ne sont pas accessibles, l'installation peut continuer mais certaines fonctionnalités pourraient ne pas fonctionner correctement"
            # Continuer automatiquement si seuls des ports non essentiels sont inaccessibles
            log "INFO" "Continuation automatique de l'installation..."
        fi
    fi

    # Vérification de la latence réseau
    log "INFO" "Vérification de la latence réseau vers ${target_host}..."
    local ping_output=$(ping -c 5 -W ${timeout} "${target_host}" 2>/dev/null || echo "Ping failed")
    local avg_latency=$(echo "${ping_output}" | grep "avg" | awk -F'/' '{print $5}')

    if [[ -n "${avg_latency}" ]]; then
        log "INFO" "Latence moyenne vers ${target_host}: ${avg_latency} ms"

        if (( $(echo "${avg_latency} > 300" | bc -l) )); then
            log "WARNING" "Latence élevée vers ${target_host}, les performances peuvent être dégradées"
        fi
    else
        log "WARNING" "Impossible de mesurer la latence vers ${target_host}"
    fi

    log "SUCCESS" "Vérification de la connectivité réseau terminée avec succès"
    return 0
}

# Fonction pour sauvegarder l'état avant modification
function backup_state() {
    local backup_name="${1:-backup-$(date +%Y%m%d-%H%M%S)}"
    local optional="${2:-false}"  # New parameter to make backup optional
    local backup_file="${BACKUP_DIR}/${backup_name}.tar.gz"
    local metadata_file="${BACKUP_DIR}/${backup_name}.json"

    log "INFO" "Sauvegarde de l'état actuel dans ${backup_file}..."

    # Création du fichier de métadonnées
    cat > "${metadata_file}" << EOF
{
  "backup_name": "${backup_name}",
  "backup_date": "$(date -Iseconds)",
  "environment": "${environment}",
  "installation_step": "${INSTALLATION_STEP}",
  "ansible_host": "${ansible_host}",
  "ansible_port": "${ansible_port}",
  "ansible_user": "${ansible_user}",
  "script_version": "1.0.0",
  "description": "Sauvegarde automatique avant l'étape ${INSTALLATION_STEP}"
}
EOF

    # Liste des répertoires à sauvegarder
    local backup_dirs=(
        "/etc/rancher"
        "/var/lib/rancher/k3s/server/manifests"
        "/home/${ansible_user}/.kube"
        "/etc/systemd/system/k3s.service"
        "/var/log/lions"
    )

    # Liste des fichiers à exclure
    local exclude_patterns=(
        "*.log"
        "*.tmp"
        "*.bak"
        "*.old"
        "*.swp"
    )

    # Construction de la commande d'exclusion
    local exclude_args=""
    for pattern in "${exclude_patterns[@]}"; do
        exclude_args="${exclude_args} --exclude='${pattern}'"
    done

    # Vérification de l'existence des répertoires avant la sauvegarde
    local existing_dirs=()
    for dir in "${backup_dirs[@]}"; do
        log "DEBUG" "Vérification de l'existence du répertoire: ${dir}"

        if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
            # Exécution locale
            if sudo test -d "${dir}" 2>/dev/null; then
                existing_dirs+=("${dir}")
                log "DEBUG" "Répertoire trouvé pour sauvegarde: ${dir}"
            else
                log "DEBUG" "Répertoire non trouvé ou erreur d'accès, ignoré pour la sauvegarde: ${dir}"
            fi
        else
            # Exécution distante
            # Utilisation de run_with_timeout_fallback pour éviter que la commande ne se bloque indéfiniment
            if run_with_timeout_fallback 10 ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo test -d ${dir}" 2>/dev/null; then
                existing_dirs+=("${dir}")
                log "DEBUG" "Répertoire trouvé pour sauvegarde: ${dir}"
            else
                log "DEBUG" "Répertoire non trouvé ou erreur d'accès, ignoré pour la sauvegarde: ${dir}"
            fi
        fi
    done

    # Si aucun répertoire n'existe, log un avertissement et retourne 0 si optionnel
    if [[ ${#existing_dirs[@]} -eq 0 ]]; then
        log "WARNING" "Aucun répertoire à sauvegarder n'existe encore sur le VPS"
        if [[ "${optional}" == "true" ]]; then
            log "INFO" "Sauvegarde ignorée (optionnelle)"
            rm -f "${metadata_file}"
            return 0
        else
            log "WARNING" "Impossible de créer une sauvegarde de l'état actuel sur le VPS"
            rm -f "${metadata_file}"
            return 1
        fi
    fi

    # Construction de la commande de sauvegarde avec les répertoires existants
    local backup_cmd="sudo tar -czf /tmp/${backup_name}.tar.gz ${exclude_args}"
    for dir in "${existing_dirs[@]}"; do
        backup_cmd="${backup_cmd} ${dir}"
    done
    backup_cmd="${backup_cmd} 2>/dev/null || true"

    # Exécution de la commande de sauvegarde
    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        # Exécution locale
        log "DEBUG" "Exécution locale de la commande de sauvegarde: ${backup_cmd}"

        # Création du répertoire temporaire si nécessaire
        mkdir -p /tmp

        # Exécution de la commande de sauvegarde
        if eval "${backup_cmd}"; then
            log "DEBUG" "Commande de sauvegarde exécutée avec succès, copie du fichier..."

            # Copie du fichier de sauvegarde
            if cp "/tmp/${backup_name}.tar.gz" "${backup_file}" 2>/dev/null; then
                log "DEBUG" "Fichier de sauvegarde copié avec succès, nettoyage du fichier temporaire..."
                # Nettoyage du fichier temporaire
                sudo rm -f "/tmp/${backup_name}.tar.gz" 2>/dev/null || log "WARNING" "Impossible de supprimer le fichier temporaire"
            else
                log "ERROR" "Impossible de copier le fichier de sauvegarde"
                rm -f "${metadata_file}"
                return 1
            fi
        else
            log "ERROR" "Échec de la commande de sauvegarde"
            rm -f "${metadata_file}"
            return 1
        fi
    else
        # Exécution distante
        log "DEBUG" "Exécution de la commande de sauvegarde: ${backup_cmd}"
        if run_with_timeout_fallback 60 ssh -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "${backup_cmd}"; then
            log "DEBUG" "Commande de sauvegarde exécutée avec succès, récupération du fichier..."
            # Récupération du fichier de sauvegarde avec timeout
            if run_with_timeout_fallback 60 scp -o ConnectTimeout=10 -P "${ansible_port}" "${ansible_user}@${ansible_host}:/tmp/${backup_name}.tar.gz" "${backup_file}" 2>/dev/null; then
                log "DEBUG" "Fichier de sauvegarde récupéré avec succès, nettoyage du fichier temporaire..."
                # Nettoyage du fichier temporaire sur le VPS
                run_with_timeout_fallback 10 ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo rm -f /tmp/${backup_name}.tar.gz" 2>/dev/null || log "WARNING" "Impossible de supprimer le fichier temporaire sur le VPS"
            else
                log "ERROR" "Impossible de récupérer le fichier de sauvegarde"
                rm -f "${metadata_file}"
                return 1
            fi
        else
            log "ERROR" "Échec de la commande de sauvegarde"
            rm -f "${metadata_file}"
            return 1
        fi
    fi

    # Vérification de la taille du fichier de sauvegarde
    local backup_size=$(du -h "${backup_file}" | awk '{print $1}')

    # Ajout de la taille du fichier aux métadonnées
    local tmp_file=$(mktemp)
    jq ".backup_size = \"${backup_size}\"" "${metadata_file}" > "${tmp_file}" && mv "${tmp_file}" "${metadata_file}"

    log "SUCCESS" "Sauvegarde de l'état créée: ${backup_file} (${backup_size})"

    # Nettoyage des anciennes sauvegardes (garder les 5 plus récentes)
    local old_backups=($(ls -t "${BACKUP_DIR}"/*.tar.gz 2>/dev/null | tail -n +6))
    if [[ ${#old_backups[@]} -gt 0 ]]; then
        log "INFO" "Nettoyage des anciennes sauvegardes..."
        for old_backup in "${old_backups[@]}"; do
            local old_name=$(basename "${old_backup}" .tar.gz)
            rm -f "${old_backup}" "${BACKUP_DIR}/${old_name}.json"
            log "INFO" "Sauvegarde supprimée: ${old_backup}"
        done
    fi

    # Enregistrement du nom de la dernière sauvegarde
    echo "${backup_name}" > "${BACKUP_DIR}/.last_backup"

    return 0
}

# Fonction pour restaurer l'état à partir d'une sauvegarde
function restore_state() {
    local backup_name="$1"

    # Si aucun nom de sauvegarde n'est fourni, utiliser la dernière sauvegarde
    if [[ -z "${backup_name}" && -f "${BACKUP_DIR}/.last_backup" ]]; then
        backup_name=$(cat "${BACKUP_DIR}/.last_backup")
    fi

    # Vérification de l'existence de la sauvegarde
    if [[ -z "${backup_name}" || ! -f "${BACKUP_DIR}/${backup_name}.tar.gz" ]]; then
        log "ERROR" "Sauvegarde non trouvée: ${backup_name}"
        return 1
    fi

    local backup_file="${BACKUP_DIR}/${backup_name}.tar.gz"
    local metadata_file="${BACKUP_DIR}/${backup_name}.json"

    log "INFO" "Restauration de l'état à partir de ${backup_file}..."

    # Lecture des métadonnées
    if [[ -f "${metadata_file}" ]]; then
        local backup_date
        backup_date=$(jq -r '.backup_date' "${metadata_file}")
        local backup_step
        backup_step=$(jq -r '.installation_step' "${metadata_file}")
        local backup_env
        backup_env=$(jq -r '.environment' "${metadata_file}")

        log "INFO" "Sauvegarde du ${backup_date}, étape: ${backup_step}, environnement: ${backup_env}"

        # Vérification de la compatibilité de l'environnement
        if [[ "${backup_env}" != "${environment}" ]]; then
            log "WARNING" "L'environnement de la sauvegarde (${backup_env}) ne correspond pas à l'environnement actuel (${environment})"
            log "INFO" "Voulez-vous continuer malgré tout? (o/N)"
            read -r answer
            if [[ ! "${answer}" =~ ^[Oo]$ ]]; then
                return 1
            fi
        fi
    else
        log "WARNING" "Fichier de métadonnées non trouvé: ${metadata_file}"
        log "INFO" "Voulez-vous continuer malgré tout? (o/N)"
        read -r answer
        if [[ ! "${answer}" =~ ^[Oo]$ ]]; then
            return 1
        fi
    fi

    # Préparation pour la restauration
    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        # Exécution locale - pas besoin de copier le fichier
        log "INFO" "Exécution locale détectée, pas besoin de copier le fichier de sauvegarde"

        # Création d'un lien symbolique vers le fichier de sauvegarde pour simplifier la suite
        if ! ln -sf "${backup_file}" "/tmp/${backup_name}.tar.gz" 2>/dev/null; then
            log "WARNING" "Impossible de créer un lien symbolique, copie du fichier à la place..."
            if ! cp "${backup_file}" "/tmp/${backup_name}.tar.gz" 2>/dev/null; then
                log "ERROR" "Impossible de copier le fichier de sauvegarde localement"
                return 1
            fi
        fi
    else
        # Exécution distante - copie du fichier vers le VPS
        log "INFO" "Copie du fichier de sauvegarde vers le VPS..."
        log "DEBUG" "Taille du fichier de sauvegarde: $(du -h "${backup_file}" | awk '{print $1}')"
        if ! run_with_timeout_fallback 60 scp -o ConnectTimeout=10 -P "${ansible_port}" "${backup_file}" "${ansible_user}@${ansible_host}:/tmp/${backup_name}.tar.gz" 2>/dev/null; then
            log "ERROR" "Impossible de copier le fichier de sauvegarde vers le VPS"
            log "DEBUG" "Vérification de l'espace disque disponible sur le VPS..."
            run_with_timeout_fallback 10 ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "df -h /tmp" 2>/dev/null || log "DEBUG" "Impossible de vérifier l'espace disque sur le VPS"
            return 1
        fi

        # Vérification que le fichier a bien été copié
        log "DEBUG" "Vérification que le fichier a bien été copié sur le VPS..."
        if ! run_with_timeout_fallback 10 ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "ls -la /tmp/${backup_name}.tar.gz" 2>/dev/null; then
            log "ERROR" "Le fichier de sauvegarde n'a pas été correctement copié sur le VPS"
            return 1
        fi
    fi

    # Arrêt des services avant restauration
    log "INFO" "Arrêt des services avant restauration..."
    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        # Exécution locale
        if ! sudo systemctl stop k3s 2>/dev/null; then
            log "WARNING" "Impossible d'arrêter le service K3s, tentative de restauration quand même"
        fi
    else
        # Exécution distante
        if ! run_with_timeout_fallback 30 ssh -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl stop k3s || true" 2>/dev/null; then
            log "WARNING" "Impossible d'arrêter le service K3s, tentative de restauration quand même"
        fi
    fi

    # Restauration des fichiers
    log "INFO" "Restauration des fichiers..."
    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        # Exécution locale
        if ! sudo tar -xzf "/tmp/${backup_name}.tar.gz" -C / 2>/dev/null; then
            log "ERROR" "Échec de la restauration des fichiers"
            log "DEBUG" "Vérification du contenu de l'archive..."
            sudo tar -tvf "/tmp/${backup_name}.tar.gz" | head -10 2>/dev/null || log "DEBUG" "Impossible de lister le contenu de l'archive"

            # Redémarrage des services en cas d'échec
            log "INFO" "Tentative de redémarrage des services après échec..."
            sudo systemctl start k3s 2>/dev/null || true

            return 1
        fi
    else
        # Exécution distante
        if ! run_with_timeout_fallback 60 ssh -o ConnectTimeout=30 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo tar -xzf /tmp/${backup_name}.tar.gz -C / 2>/dev/null"; then
            log "ERROR" "Échec de la restauration des fichiers"
            log "DEBUG" "Vérification du contenu de l'archive..."
            run_with_timeout_fallback 10 ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo tar -tvf /tmp/${backup_name}.tar.gz | head -10" 2>/dev/null || log "DEBUG" "Impossible de lister le contenu de l'archive"

            # Redémarrage des services en cas d'échec
            log "INFO" "Tentative de redémarrage des services après échec..."
            run_with_timeout_fallback 30 ssh -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl start k3s || true" 2>/dev/null

            return 1
        fi
    fi

    # Nettoyage du fichier temporaire
    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        # Exécution locale
        log "DEBUG" "Nettoyage du fichier temporaire local..."
        sudo rm -f "/tmp/${backup_name}.tar.gz" 2>/dev/null || log "WARNING" "Impossible de supprimer le fichier temporaire local"
    else
        # Exécution distante
        log "DEBUG" "Nettoyage du fichier temporaire sur le VPS..."
        run_with_timeout_fallback 10 ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo rm -f /tmp/${backup_name}.tar.gz" 2>/dev/null || log "WARNING" "Impossible de supprimer le fichier temporaire sur le VPS"
    fi

    # Redémarrage des services
    log "INFO" "Redémarrage des services..."
    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        # Exécution locale
        if ! sudo systemctl daemon-reload && sudo systemctl start k3s; then
            log "WARNING" "Échec du redémarrage des services"
            log "DEBUG" "Vérification de l'état du service K3s..."
            sudo systemctl status k3s 2>/dev/null || log "DEBUG" "Impossible de vérifier l'état du service K3s"
            log "WARNING" "Vous devrez peut-être redémarrer manuellement le système"
            return 1
        fi
    else
        # Exécution distante
        if ! run_with_timeout_fallback 60 ssh -o ConnectTimeout=30 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl daemon-reload && sudo systemctl start k3s"; then
            log "WARNING" "Échec du redémarrage des services"
            log "DEBUG" "Vérification de l'état du service K3s..."
            run_with_timeout_fallback 10 ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl status k3s" 2>/dev/null || log "DEBUG" "Impossible de vérifier l'état du service K3s"
            log "WARNING" "Vous devrez peut-être redémarrer manuellement le VPS"
            return 1
        fi
    fi

    # Attente que K3s soit prêt
    log "INFO" "Attente que K3s soit prêt..."
    local k3s_timeout=120  # Augmentation du timeout à 2 minutes
    local start_time
    start_time=$(date +%s)
    local k3s_ready=false
    local check_count=0

    while [[ "${k3s_ready}" == "false" ]]; do
        local current_time
        current_time=$(date +%s)
        local elapsed_time
        elapsed_time=$((current_time - start_time))

        if [[ ${elapsed_time} -gt ${k3s_timeout} ]]; then
            log "WARNING" "Timeout atteint en attendant que K3s soit prêt"
            log "DEBUG" "Vérification des logs de K3s..."

            if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
                # Exécution locale
                sudo journalctl -u k3s --no-pager -n 20 2>/dev/null || log "DEBUG" "Impossible de récupérer les logs de K3s"
            else
                # Exécution distante
                run_with_timeout_fallback 10 ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo journalctl -u k3s --no-pager -n 20" 2>/dev/null || log "DEBUG" "Impossible de récupérer les logs de K3s"
            fi

            break
        fi

        # Toutes les 3 tentatives, afficher plus d'informations de diagnostic
        if [[ $((check_count % 3)) -eq 0 ]]; then
            log "DEBUG" "Vérification de l'état du service K3s (tentative ${check_count})..."

            if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
                # Exécution locale
                sudo systemctl is-active k3s 2>/dev/null || log "DEBUG" "Service K3s non actif"
            else
                # Exécution distante
                run_with_timeout_fallback 10 ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl is-active k3s" 2>/dev/null || log "DEBUG" "Service K3s non actif"
            fi
        fi

        if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
            # Exécution locale
            if sudo kubectl get nodes 2>/dev/null; then
                k3s_ready=true
                log "SUCCESS" "K3s est prêt"
                # Afficher les nœuds pour confirmation
                log "DEBUG" "Nœuds K3s disponibles:"
                sudo kubectl get nodes 2>/dev/null || log "DEBUG" "Impossible de lister les nœuds K3s"
            else
                log "INFO" "En attente que K3s soit prêt... (${elapsed_time}s)"
                check_count=$((check_count + 1))
                sleep 5
            fi
        else
            # Exécution distante
            if run_with_timeout_fallback 15 ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo kubectl get nodes" 2>/dev/null; then
                k3s_ready=true
                log "SUCCESS" "K3s est prêt"
                # Afficher les nœuds pour confirmation
                log "DEBUG" "Nœuds K3s disponibles:"
                run_with_timeout_fallback 10 ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo kubectl get nodes" 2>/dev/null || log "DEBUG" "Impossible de lister les nœuds K3s"
            else
                log "INFO" "En attente que K3s soit prêt... (${elapsed_time}s)"
                check_count=$((check_count + 1))
                sleep 5
            fi
        fi
    done

    log "SUCCESS" "Restauration terminée avec succès"

    # Mise à jour de l'état actuel
    if [[ -f "${metadata_file}" ]]; then
        local backup_step
        backup_step=$(jq -r '.installation_step' "${metadata_file}")
        INSTALLATION_STEP="${backup_step}"
        echo "${INSTALLATION_STEP}" > "${STATE_FILE}"
        log "INFO" "État actuel mis à jour: ${INSTALLATION_STEP}"
    fi

    return 0
}

# Fonction pour exécuter une commande avec timeout
function run_with_timeout() {
    local cmd_str="$1"
    local timeout="${2:-${TIMEOUT_SECONDS}}"
    local cmd_type="${3:-generic}"
    local max_retries=3
    local retry_count=0
    local backoff_time=5
    local interactive=false

    # Vérifier si la commande est interactive (nécessite une entrée utilisateur)
    if [[ "${cmd_str}" == *"--ask-become-pass"* || "${cmd_str}" == *"--ask-pass"* || "${cmd_str}" == *"-K"* || "${cmd_str}" == *"-k"* ]]; then
        interactive=true
        log "INFO" "Commande interactive détectée, l'entrée utilisateur sera requise"
    fi

    log "INFO" "Exécution de la commande avec timeout ${timeout}s: ${cmd_str}"
    LAST_COMMAND="${cmd_str}"

    # Définition du type de commande pour la gestion des erreurs
    COMMAND_NAME="${cmd_type}"

    # Sauvegarde de l'état avant l'exécution pour permettre une reprise
    echo "${INSTALLATION_STEP}" > "${STATE_FILE}"

    # Fonction pour vérifier si l'erreur est liée au réseau
    function is_network_error() {
        local output="$1"
        local exit_code="$2"

        # Codes d'erreur typiques des problèmes réseau
        if [[ ${exit_code} -eq 124 || ${exit_code} -eq 255 ]]; then
            return 0
        fi

        # Messages d'erreur typiques des problèmes réseau
        if echo "${output}" | grep -q -E "Connection refused|Connection timed out|Network is unreachable|Unable to connect|Connection reset by peer|Temporary failure in name resolution|Could not resolve host|Network error"; then
            return 0
        fi

        return 1
    }

    while true; do
        # Vérification de la connectivité avant l'exécution
        if [[ "${cmd_type}" == "ansible_playbook" || "${cmd_type}" == "ssh" ]]; then
            if ! ping -c 1 -W 5 "${ansible_host}" &>/dev/null; then
                if [[ ${retry_count} -lt ${max_retries} ]]; then
                    retry_count=$((retry_count + 1))
                    log "WARNING" "Connectivité réseau perdue avec le VPS (${ansible_host}). Tentative ${retry_count}/${max_retries} dans ${backoff_time} secondes..."
                    sleep ${backoff_time}
                    backoff_time=$((backoff_time * 2))  # Backoff exponentiel
                    continue
                else
                    log "ERROR" "Connectivité réseau perdue avec le VPS (${ansible_host})"
                    log "ERROR" "Impossible d'exécuter la commande sans connectivité réseau après ${max_retries} tentatives"
                    return 1
                fi
            fi
        fi

        # Exécution de la commande avec timeout
        log "DEBUG" "Début de l'exécution de la commande..."

        local exit_code=0
        local command_output=""

        # Détection du système d'exploitation pour adapter la commande
        local os_name=""
        os_name=$(uname -s)

        # Traitement spécial pour Windows/WSL pour toutes les commandes interactives
        if [[ "${os_name}" == *"MINGW"* || "${os_name}" == *"MSYS"* || "${os_name}" == *"CYGWIN"* || "${os_name}" == *"Windows"* || "${os_name}" == *"Linux"*"microsoft"* ]]; then
            log "INFO" "Système Windows/WSL détecté, définition de la variable d'environnement ANSIBLE_BECOME_ASK_PASS"
            export ANSIBLE_BECOME_ASK_PASS=True
        fi

        if [[ "${interactive}" == "true" ]]; then
            # Pour les commandes interactives, exécuter avec un timeout mais permettre l'entrée utilisateur
            log "INFO" "Exécution de la commande interactive, veuillez répondre aux invites si nécessaire..."

            # Exécution directe de la commande avec eval comme dans deploy.sh
            log "DEBUG" "Exécution de la commande avec eval"
            eval "${cmd_str}"
            exit_code=$?
        else
            # Pour les commandes non interactives, capturer la sortie
            local output_file
            output_file=$(mktemp)
            timeout "${timeout}" bash -c "${cmd_str}" > "${output_file}" 2>&1
            exit_code=$?
            command_output=$(cat "${output_file}")
            rm -f "${output_file}"
        fi

        # Journalisation de la sortie si en mode debug et si la commande n'était pas interactive
        if [[ "${debug_mode}" == "true" && -n "${command_output}" ]]; then
            log "DEBUG" "Sortie de la commande:"
            echo "${command_output}" | while IFS= read -r line; do
                log "DEBUG" "  ${line}"
            done
        fi

        # Vérification si l'erreur est liée au réseau et si on doit réessayer
        if [[ ${exit_code} -ne 0 ]]; then
            # Pour les commandes interactives, on ne peut pas analyser la sortie
            if [[ "${interactive}" == "true" ]]; then
                # Si c'est une erreur de timeout, on considère que c'est une erreur réseau
                if [[ ${exit_code} -eq 124 || ${exit_code} -eq 255 ]]; then
                    if [[ ${retry_count} -lt ${max_retries} ]]; then
                        retry_count=$((retry_count + 1))
                        log "WARNING" "Erreur possible de réseau pour la commande interactive (code ${exit_code}). Tentative ${retry_count}/${max_retries} dans ${backoff_time} secondes..."
                        sleep ${backoff_time}
                        backoff_time=$((backoff_time * 2))  # Backoff exponentiel
                        continue
                    fi
                fi
            # Pour les commandes non interactives, on peut analyser la sortie
            elif is_network_error "${command_output}" ${exit_code}; then
                if [[ ${retry_count} -lt ${max_retries} ]]; then
                    retry_count=$((retry_count + 1))
                    log "WARNING" "Erreur réseau détectée (code ${exit_code}). Tentative ${retry_count}/${max_retries} dans ${backoff_time} secondes..."
                    sleep ${backoff_time}
                    backoff_time=$((backoff_time * 2))  # Backoff exponentiel
                    continue
                fi
            fi
        fi

        # Analyse du code de retour
        if [[ ${exit_code} -eq 124 ]]; then
            log "ERROR" "La commande a dépassé le délai d'attente (${timeout}s)"

            # Tentative de diagnostic pour les timeouts
            case "${cmd_type}" in
                "ansible_playbook")
                    log "INFO" "Vérification de la connectivité SSH..."
                    if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "echo 'Test de connexion'" &>/dev/null; then
                        log "INFO" "La connexion SSH fonctionne, le problème pourrait être lié à Ansible ou à une opération longue"
                    else
                        log "ERROR" "La connexion SSH ne fonctionne pas, vérifiez les paramètres de connexion"
                    fi
                    ;;
                "kubectl_apply")
                    log "INFO" "Vérification de l'accès à l'API Kubernetes..."
                    if kubectl cluster-info &>/dev/null; then
                        log "INFO" "L'accès à l'API Kubernetes fonctionne, le problème pourrait être lié à une opération longue"
                    else
                        log "ERROR" "L'accès à l'API Kubernetes ne fonctionne pas, vérifiez la configuration de kubectl"
                    fi
                    ;;
            esac

            return 1
        elif [[ ${exit_code} -ne 0 ]]; then
            log "ERROR" "La commande a échoué avec le code ${exit_code}"

            # Analyse de la sortie pour des erreurs connues (seulement pour les commandes non interactives)
            if [[ "${interactive}" == "false" && -n "${command_output}" ]]; then
                if echo "${command_output}" | grep -q "Connection refused"; then
                    log "ERROR" "Connexion refusée - vérifiez que le service est en cours d'exécution et accessible"
                elif echo "${command_output}" | grep -q "Permission denied"; then
                    log "ERROR" "Permission refusée - vérifiez les droits d'accès"
                elif echo "${command_output}" | grep -q "No space left on device"; then
                    log "ERROR" "Plus d'espace disque disponible - libérez de l'espace et réessayez"
                elif echo "${command_output}" | grep -q "Unable to connect to the server"; then
                    log "ERROR" "Impossible de se connecter au serveur Kubernetes - vérifiez que K3s est en cours d'exécution"
                fi
            elif [[ "${interactive}" == "true" ]]; then
                log "INFO" "La commande interactive a échoué. Vérifiez les erreurs affichées ci-dessus."

                # Suggestions spécifiques pour les commandes interactives
                if [[ "${LAST_COMMAND}" == *"ansible-playbook"* && "${LAST_COMMAND}" == *"--ask-become-pass"* ]]; then
                    log "INFO" "Suggestions pour les erreurs Ansible avec --ask-become-pass:"
                    log "INFO" "1. Vérifiez que vous avez entré le bon mot de passe sudo"
                    log "INFO" "2. Vérifiez que l'utilisateur a les droits sudo sur le VPS"
                    log "INFO" "3. Vérifiez la configuration de sudoers sur le VPS"
                fi
            fi

            return ${exit_code}
        fi

        # Si on arrive ici, c'est que la commande a réussi
        if [[ ${retry_count} -gt 0 ]]; then
            log "SUCCESS" "Commande exécutée avec succès après ${retry_count} tentatives"
        else
            if [[ "${interactive}" == "true" ]]; then
                log "SUCCESS" "Commande interactive exécutée avec succès"
            else
                log "DEBUG" "Commande exécutée avec succès"
            fi
        fi
        return 0
    done
}

# Fonction d'affichage de l'aide
function afficher_aide() {
    cat << EOF
Script d'Installation de l'Infrastructure LIONS sur VPS

Ce script orchestre l'installation complète de l'infrastructure LIONS sur un VPS.

Usage:
    $0 [options]

Options:
    -e, --environment <env>   Environnement cible (production, staging, development)
                             Par défaut: development
    -i, --inventory <file>    Fichier d'inventaire Ansible spécifique
                             Par défaut: inventories/development/hosts.yml
    -s, --skip-init           Ignorer l'initialisation du VPS (si déjà effectuée)
    -d, --debug               Active le mode debug
    -h, --help                Affiche cette aide

Exemples:
    $0
    $0 --environment staging
    $0 --skip-init --debug
EOF
}

# Fonction de vérification des prérequis
function verifier_prerequis() {
    log "INFO" "Vérification des prérequis..."
    INSTALLATION_STEP="prerequis"
    LAST_COMMAND="verifier_prerequis"
    COMMAND_NAME="verifier_prerequis"

    # Vérification du verrouillage
    if [[ -f "${LOCK_FILE}" ]]; then
        log "WARNING" "Une autre instance du script semble être en cours d'exécution"

        # Vérification de l'âge du fichier de verrouillage
        local lock_file_age
        lock_file_age=$(( $(date +%s) - $(stat -c %Y "${LOCK_FILE}" 2>/dev/null || echo $(date +%s)) ))

        # Vérification de l'uptime du système
        local uptime_seconds
        uptime_seconds=$(cat /proc/uptime 2>/dev/null | awk '{print int($1)}' || echo 999999)

        # Vérification des processus en cours d'exécution
        local script_name
        script_name=$(basename "$0")
        local script_count
        script_count=$(ps aux | grep -v grep | grep -c "${script_name}" || echo 1)

        # Si le système a redémarré après la création du fichier de verrouillage
        # ou si le fichier de verrouillage existe depuis plus d'une heure
        # ou si aucun autre processus du script n'est en cours d'exécution
        if [[ ${uptime_seconds} -lt ${lock_file_age} || ${lock_file_age} -gt 3600 || ${script_count} -le 1 ]]; then
            log "INFO" "Le système a redémarré ou le fichier de verrouillage est obsolète (âge: ${lock_file_age}s, uptime: ${uptime_seconds}s) ou aucune autre instance n'est en cours d'exécution"
            log "INFO" "Suppression automatique du fichier de verrouillage obsolète"
            # Tentative de suppression sans sudo d'abord
            if ! rm -f "${LOCK_FILE}" 2>/dev/null; then
                log "WARNING" "Impossible de supprimer le fichier de verrouillage sans sudo, tentative avec sudo..."
                # Si ça échoue, essayer avec secure_sudo
                if secure_sudo rm -f "${LOCK_FILE}"; then
                    log "SUCCESS" "Fichier de verrouillage obsolète supprimé avec succès (sudo)"
                else
                    log "WARNING" "Impossible de supprimer le fichier de verrouillage obsolète, même avec sudo"
                fi
            fi
        else
            log "WARNING" "Si ce n'est pas le cas, tentative de suppression du fichier de verrouillage avec sudo"
            log "INFO" "Exécution de la commande: sudo rm -f ${LOCK_FILE}"
            # Utilisation de secure_sudo pour supprimer le fichier, ce qui demandera le mot de passe
            if secure_sudo rm -f "${LOCK_FILE}"; then
                log "SUCCESS" "Fichier de verrouillage supprimé avec succès"
            else
                log "ERROR" "Impossible de supprimer le fichier de verrouillage, même avec sudo"
                log "ERROR" "Veuillez le supprimer manuellement: sudo rm -f ${LOCK_FILE}"
                exit 1
            fi
        fi
    fi

    # Création du fichier de verrouillage
    touch "${LOCK_FILE}"

    # Vérification de la version du système d'exploitation
    log "INFO" "Vérification du système d'exploitation..."
    local os_name
    os_name=$(uname -s)
    local os_version
    os_version=$(uname -r)

    if [[ "${os_name}" != "Linux" && "${os_name}" != "Darwin" ]]; then
        log "WARNING" "Système d'exploitation non testé: ${os_name} ${os_version}"
        log "WARNING" "Ce script est conçu pour fonctionner sur Linux ou macOS"
        log "INFO" "Voulez-vous continuer malgré tout? (o/N)"
        read -r answer
        if [[ ! "${answer}" =~ ^[Oo]$ ]]; then
            cleanup
            exit 1
        fi
    else
        log "INFO" "Système d'exploitation: ${os_name} ${os_version}"
    fi

    # Détection de WSL2 et avertissement sur les problèmes de compatibilité avec K3s
    if [[ "${os_version}" == *"WSL"* || "${os_version}" == *"Microsoft"* || "${os_version}" == *"microsoft"* ]]; then
        log "WARNING" "Environnement WSL2 détecté: ${os_version}"
        log "WARNING" "⚠️ ATTENTION: K3s peut rencontrer des problèmes de compatibilité dans WSL2 ⚠️"
        log "WARNING" "Problèmes connus:"
        log "WARNING" "  - Erreurs de démarrage du ContainerManager"
        log "WARNING" "  - Problèmes avec les cgroups"
        log "WARNING" "  - Connexions refusées à l'API Kubernetes"
        log "WARNING" "  - Service K3s qui ne démarre jamais complètement"
        log "INFO" "Recommandations:"
        log "INFO" "  1. Exécutez ce script directement sur le VPS cible plutôt que via WSL2"
        log "INFO" "  2. Connectez-vous au VPS via SSH: ssh ${ansible_user}@${ansible_host} -p ${ansible_port}"
        log "INFO" "  3. Clonez le dépôt sur le VPS: git clone https://github.com/votre-repo/lions-infrastructure-automated-depl.git"
        log "INFO" "  4. Exécutez le script d'installation sur le VPS: cd lions-infrastructure-automated-depl/lions-infrastructure/scripts && ./install.sh"
        log "INFO" "Voulez-vous continuer malgré ces avertissements? (o/N)"
        read -r answer
        if [[ ! "${answer}" =~ ^[Oo]$ ]]; then
            log "INFO" "Installation annulée. Exécutez le script directement sur le VPS pour de meilleurs résultats."
            cleanup
            exit 1
        fi
        log "WARNING" "Continuation de l'installation dans WSL2 malgré les risques de problèmes..."
    fi

    # Vérification de l'espace disque
    if ! check_disk_space; then
        log "ERROR" "Vérification de l'espace disque échouée"
        cleanup
        exit 1
    fi

    # Vérification de la mémoire disponible
    log "INFO" "Vérification de la mémoire disponible..."
    local available_memory=0
    if [[ "${os_name}" == "Linux" ]]; then
        available_memory=$(free -m | awk '/^Mem:/ {print $7}')
    elif [[ "${os_name}" == "Darwin" ]]; then
        available_memory=$(vm_stat | awk '/Pages free/ {free=$3} /Pages inactive/ {inactive=$3} END {print (free+inactive)*4096/1048576}' | cut -d. -f1)
    fi

    if [[ ${available_memory} -lt 1024 ]]; then
        log "WARNING" "Mémoire disponible limitée: ${available_memory}MB (recommandé: 1024MB minimum)"
        log "WARNING" "Des problèmes de performance peuvent survenir pendant l'installation"
        log "INFO" "Voulez-vous continuer malgré tout? (o/N)"
        read -r answer
        if [[ ! "${answer}" =~ ^[Oo]$ ]]; then
            cleanup
            exit 1
        fi
    else
        log "INFO" "Mémoire disponible: ${available_memory}MB (minimum recommandé: 1024MB)"
    fi

    # Vérification des commandes requises avec versions minimales
    log "INFO" "Vérification des commandes requises..."
    local required_commands=(
        "ansible-playbook:2.13.13"
        "ssh:7.0"
        "scp:7.0"
        "kubectl:1.20.0"
        "helm:3.5.0"
        "timeout:0"
        "nc:0"
        "ping:0"
        "jq:0"
    )
    local missing_commands=()
    local outdated_commands=()

    for cmd_with_version in "${required_commands[@]}"; do
        local cmd="${cmd_with_version%%:*}"
        local min_version="${cmd_with_version#*:}"

        if ! command_exists "${cmd}"; then
            missing_commands+=("${cmd}")
            continue
        fi

        # Vérification des versions pour les commandes critiques
        if [[ "${min_version}" != "0" ]]; then
            local current_version=""
            case "${cmd}" in
                "ansible-playbook")
                    # Add timeout to prevent hanging and handle errors better
                    current_version=$(timeout 5 ansible-playbook --version 2>/dev/null | head -n1 | awk '{print $2}' | cut -d[ -f1 || echo "${min_version}")
                    ;;
                "kubectl")
                    # Add timeout to prevent hanging and handle errors better
                    current_version=$(timeout 5 kubectl version --client --short 2>/dev/null | awk '{print $3}' | sed 's/v//' || echo "${min_version}")
                    ;;
                "helm")
                    # Add timeout to prevent hanging and handle errors better
                    current_version=$(timeout 5 helm version --short 2>/dev/null | sed 's/v//' | cut -d+ -f1 || echo "${min_version}")
                    ;;
                *)
                    # Pour les autres commandes, on ne vérifie pas la version
                    current_version="${min_version}"
                    ;;
            esac

            if [[ -n "${current_version}" && "${current_version}" != "${min_version}" ]]; then
                if ! version_greater_equal "${current_version}" "${min_version}"; then
                    outdated_commands+=("${cmd} (actuelle: ${current_version}, requise: ${min_version})")
                fi
            fi
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log "WARNING" "Commandes requises non trouvées: ${missing_commands[*]}"
        log "INFO" "Tentative d'installation automatique des commandes manquantes..."

        if install_missing_commands "${missing_commands[@]}"; then
            log "SUCCESS" "Installation des commandes manquantes réussie"
            # Vérifier à nouveau les commandes
            missing_commands=()
            for cmd_with_version in "${required_commands[@]}"; do
                local cmd="${cmd_with_version%%:*}"
                if ! command_exists "${cmd}"; then
                    missing_commands+=("${cmd}")
                fi
            done

            if [[ ${#missing_commands[@]} -gt 0 ]]; then
                log "ERROR" "Certaines commandes n'ont pas pu être installées: ${missing_commands[*]}"
                log "ERROR" "Veuillez installer ces commandes manuellement avant de continuer"
                cleanup
                exit 1
            fi
        else
            log "ERROR" "Échec de l'installation automatique des commandes manquantes"
            log "ERROR" "Veuillez installer ces commandes manuellement avant de continuer"
            cleanup
            exit 1
        fi
    fi

    if [[ ${#outdated_commands[@]} -gt 0 ]]; then
        log "WARNING" "Commandes avec versions obsolètes: ${outdated_commands[*]}"
        log "WARNING" "Il est recommandé de mettre à jour ces commandes avant de continuer"
        log "INFO" "Voulez-vous continuer malgré tout? (o/N)"
        read -r answer
        if [[ ! "${answer}" =~ ^[Oo]$ ]]; then
            cleanup
            exit 1
        fi
    fi

    # Vérification et installation des collections Ansible requises
    if ! check_ansible_collections; then
        log "ERROR" "Échec de la vérification ou de l'installation des collections Ansible requises"
        log "ERROR" "Assurez-vous que les collections nécessaires sont installées avant de continuer"
        log "INFO" "Vous pouvez les installer manuellement avec: ansible-galaxy collection install community.kubernetes"
        cleanup
        exit 1
    fi

    # Vérification et installation des dépendances Python requises
    if ! check_python_dependencies; then
        log "ERROR" "Échec de la vérification ou de l'installation des dépendances Python requises"
        log "ERROR" "Assurez-vous que les modules Python nécessaires sont installés avant de continuer"
        log "INFO" "Vous pouvez les installer manuellement avec: pip install kubernetes openshift"
        cleanup
        exit 1
    fi

    # Vérification et installation des plugins Helm requis
    if ! check_helm_plugins; then
        log "ERROR" "Échec de la vérification ou de l'installation des plugins Helm requis"
        log "ERROR" "Assurez-vous que le plugin helm-diff est installé avant de continuer"
        log "INFO" "Vous pouvez l'installer manuellement avec: helm plugin install https://github.com/databus23/helm-diff --version v3.4.1"
        cleanup
        exit 1
    fi

    # Vérification des fichiers Ansible
    log "INFO" "Vérification des fichiers Ansible..."

    # Adaptation des chemins pour Windows si nécessaire
    local inventory_dir="${ANSIBLE_DIR}/inventories/${environment}"
    local is_windows=false

    if [[ "${os_name}" == *"MINGW"* || "${os_name}" == *"MSYS"* || "${os_name}" == *"CYGWIN"* || "${os_name}" == *"Windows"* || "${os_name}" == *"WSL"* ]]; then
        is_windows=true
        log "DEBUG" "Environnement Windows/WSL détecté, adaptation des chemins"

        # Convertir les chemins pour Windows
        if [[ "${inventory_dir}" == *"/"* && "${inventory_dir}" != *"\\"* ]]; then
            local inventory_dir_win=$(echo "${inventory_dir}" | tr '/' '\\')
            log "DEBUG" "Chemin d'inventaire adapté pour Windows: ${inventory_dir_win}"

            # Vérifier si le chemin converti existe
            if [[ -d "${inventory_dir_win}" ]]; then
                log "DEBUG" "Utilisation du chemin Windows pour le répertoire d'inventaire"
                inventory_dir="${inventory_dir_win}"
            else
                log "DEBUG" "Le chemin Windows n'existe pas, vérification du chemin original"
            fi
        fi
    fi

    if [[ ! -d "${inventory_dir}" ]]; then
        log "INFO" "Le répertoire d'inventaire pour l'environnement ${environment} n'existe pas: ${inventory_dir}"
        log "INFO" "Création du répertoire d'inventaire..."

        # Création du répertoire avec gestion d'erreur améliorée
        if ! mkdir -p "${inventory_dir}" 2>/dev/null; then
            # Tentative avec le chemin original si le chemin Windows échoue
            if [[ "${is_windows}" == "true" && "${inventory_dir}" == *"\\"* ]]; then
                local inventory_dir_unix=$(echo "${inventory_dir}" | tr '\\' '/')
                log "DEBUG" "Tentative avec le chemin Unix: ${inventory_dir_unix}"
                if ! mkdir -p "${inventory_dir_unix}" 2>/dev/null; then
                    log "ERROR" "Impossible de créer le répertoire d'inventaire: ${inventory_dir}"
                    cleanup
                    exit 1
                else
                    inventory_dir="${inventory_dir_unix}"
                fi
            else
                log "ERROR" "Impossible de créer le répertoire d'inventaire: ${inventory_dir}"
                cleanup
                exit 1
            fi
        fi
        log "SUCCESS" "Répertoire d'inventaire créé: ${inventory_dir}"
    fi

    # Adaptation des chemins pour Windows si nécessaire
    local inventory_file_path="${ANSIBLE_DIR}/${inventory_file}"
    if [[ "${os_name}" == *"MINGW"* || "${os_name}" == *"MSYS"* || "${os_name}" == *"CYGWIN"* || "${os_name}" == *"Windows"* ]]; then
        # Convertir les chemins pour Windows
        if [[ "${inventory_file_path}" == *"/"* && "${inventory_file_path}" != *"\\"* ]]; then
            local inventory_file_path_win=$(echo "${inventory_file_path}" | tr '/' '\\')
            log "DEBUG" "Chemin du fichier d'inventaire adapté pour Windows: ${inventory_file_path_win}"

            # Vérifier si le chemin converti existe
            if [[ -f "${inventory_file_path_win}" ]]; then
                log "DEBUG" "Utilisation du chemin Windows pour le fichier d'inventaire"
                inventory_file_path="${inventory_file_path_win}"
            else
                log "DEBUG" "Le chemin Windows n'existe pas, vérification du chemin original"
            fi
        fi
    fi

    if [[ ! -f "${inventory_file_path}" ]]; then
        log "WARNING" "Le fichier d'inventaire n'existe pas: ${inventory_file_path}"
        log "INFO" "Création d'un fichier d'inventaire par défaut..."

        # Créer le répertoire parent si nécessaire
        mkdir -p "$(dirname "${inventory_file_path}")" || {
            log "ERROR" "Impossible de créer le répertoire parent pour le fichier d'inventaire"
            cleanup
            exit 1
        }

        # Créer un fichier d'inventaire par défaut
        cat > "${inventory_file_path}" << EOF
---
all:
  children:
    vps:
      hosts:
        contabo-vps:
          ansible_host: ${LIONS_VPS_HOST:-176.57.150.2}
          ansible_port: ${LIONS_VPS_PORT:-225}
          ansible_user: ${LIONS_VPS_USER:-root}
          ansible_python_interpreter: /usr/bin/python3
          ansible_connection: local
    kubernetes:
      hosts:
        contabo-vps:
          ansible_host: ${LIONS_VPS_HOST:-176.57.150.2}
          ansible_port: ${LIONS_VPS_PORT:-225}
          ansible_connection: local
    databases:
      hosts:
        contabo-vps:
          ansible_host: ${LIONS_VPS_HOST:-176.57.150.2}
          ansible_port: ${LIONS_VPS_PORT:-225}
          ansible_connection: local
    monitoring:
      hosts:
        contabo-vps:
          ansible_host: ${LIONS_VPS_HOST:-176.57.150.2}
          ansible_port: ${LIONS_VPS_PORT:-225}
          ansible_connection: local
  vars:
    ansible_user: ${LIONS_VPS_USER:-lionsdevadmin}
    ansible_become: yes
    environment: ${environment}
    domain_name: ${LIONS_DOMAIN:-dev.lions.dev}
EOF

        log "SUCCESS" "Fichier d'inventaire créé: ${inventory_file_path}"
    fi

    # Vérification des playbooks avec adaptation des chemins pour Windows
    local playbooks=(
        "init-vps.yml"
        "install-k3s.yml"
    )

    for playbook in "${playbooks[@]}"; do
        local playbook_path="${ANSIBLE_DIR}/playbooks/${playbook}"

        # Adaptation des chemins pour Windows si nécessaire
        if [[ "${os_name}" == *"MINGW"* || "${os_name}" == *"MSYS"* || "${os_name}" == *"CYGWIN"* || "${os_name}" == *"Windows"* ]]; then
            # Convertir les chemins pour Windows
            if [[ "${playbook_path}" == *"/"* && "${playbook_path}" != *"\\"* ]]; then
                local playbook_path_win=$(echo "${playbook_path}" | tr '/' '\\')
                log "DEBUG" "Chemin du playbook adapté pour Windows: ${playbook_path_win}"

                # Vérifier si le chemin converti existe
                if [[ -f "${playbook_path_win}" ]]; then
                    log "DEBUG" "Utilisation du chemin Windows pour le playbook"
                    playbook_path="${playbook_path_win}"
                else
                    log "DEBUG" "Le chemin Windows n'existe pas, vérification du chemin original"
                fi
            fi
        fi

        if [[ ! -f "${playbook_path}" ]]; then
            log "ERROR" "Le playbook ${playbook} n'existe pas: ${playbook_path}"
            log "ERROR" "Veuillez vérifier que tous les playbooks nécessaires sont présents dans le répertoire ${ANSIBLE_DIR}/playbooks/"
            cleanup
            exit 1
        fi
    done

    # Vérification des fichiers Kubernetes
    log "INFO" "Vérification des fichiers Kubernetes..."

    # Adaptation des chemins pour Windows si nécessaire
    local k8s_overlay_dir="${PROJECT_ROOT}/kubernetes/overlays/${environment}"
    local is_windows=false

    if [[ "${os_name}" == *"MINGW"* || "${os_name}" == *"MSYS"* || "${os_name}" == *"CYGWIN"* || "${os_name}" == *"Windows"* || "${os_name}" == *"WSL"* ]]; then
        is_windows=true
        log "DEBUG" "Environnement Windows/WSL détecté, adaptation des chemins Kubernetes"

        # Convertir les chemins pour Windows
        if [[ "${k8s_overlay_dir}" == *"/"* && "${k8s_overlay_dir}" != *"\\"* ]]; then
            local k8s_overlay_dir_win=$(echo "${k8s_overlay_dir}" | tr '/' '\\')
            log "DEBUG" "Chemin d'overlay Kubernetes adapté pour Windows: ${k8s_overlay_dir_win}"

            # Vérifier si le chemin converti existe
            if [[ -d "${k8s_overlay_dir_win}" ]]; then
                log "DEBUG" "Utilisation du chemin Windows pour le répertoire d'overlay Kubernetes"
                k8s_overlay_dir="${k8s_overlay_dir_win}"
            else
                log "DEBUG" "Le chemin Windows n'existe pas, vérification du chemin original"
            fi
        fi
    fi

    if [[ ! -d "${k8s_overlay_dir}" ]]; then
        log "INFO" "Le répertoire d'overlay Kubernetes pour l'environnement ${environment} n'existe pas: ${k8s_overlay_dir}"
        log "INFO" "Création du répertoire d'overlay Kubernetes..."

        # Création du répertoire avec gestion d'erreur améliorée
        if ! mkdir -p "${k8s_overlay_dir}" 2>/dev/null; then
            # Tentative avec le chemin original si le chemin Windows échoue
            if [[ "${is_windows}" == "true" && "${k8s_overlay_dir}" == *"\\"* ]]; then
                local k8s_overlay_dir_unix=$(echo "${k8s_overlay_dir}" | tr '\\' '/')
                log "DEBUG" "Tentative avec le chemin Unix: ${k8s_overlay_dir_unix}"
                if ! mkdir -p "${k8s_overlay_dir_unix}" 2>/dev/null; then
                    log "ERROR" "Impossible de créer le répertoire d'overlay Kubernetes: ${k8s_overlay_dir}"
                    cleanup
                    exit 1
                else
                    k8s_overlay_dir="${k8s_overlay_dir_unix}"
                fi
            else
                log "ERROR" "Impossible de créer le répertoire d'overlay Kubernetes: ${k8s_overlay_dir}"
                cleanup
                exit 1
            fi
        fi
        log "SUCCESS" "Répertoire d'overlay Kubernetes créé: ${k8s_overlay_dir}"
    fi

    # Vérification du fichier kustomization.yaml
    local kustomization_file="${k8s_overlay_dir}/kustomization.yaml"

    if [[ "${is_windows}" == "true" ]]; then
        # Convertir les chemins pour Windows
        if [[ "${kustomization_file}" == *"/"* && "${kustomization_file}" != *"\\"* ]]; then
            local kustomization_file_win=$(echo "${kustomization_file}" | tr '/' '\\')
            log "DEBUG" "Chemin du fichier kustomization.yaml adapté pour Windows: ${kustomization_file_win}"

            # Vérifier si le chemin converti existe
            if [[ -f "${kustomization_file_win}" ]]; then
                log "DEBUG" "Utilisation du chemin Windows pour le fichier kustomization.yaml"
                kustomization_file="${kustomization_file_win}"
            else
                log "DEBUG" "Le chemin Windows n'existe pas, vérification du chemin original"
            fi
        fi
    fi

    if [[ ! -f "${kustomization_file}" ]]; then
        log "INFO" "Le fichier kustomization.yaml pour l'environnement ${environment} n'existe pas: ${kustomization_file}"
        log "INFO" "Création d'un fichier kustomization.yaml par défaut..."

        # Tentative de création du fichier avec gestion d'erreur améliorée
        if ! cat > "${kustomization_file}" << EOF 2>/dev/null; then
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base/namespaces
  - ../../base/storage-classes
  - ../../base/network-policies
  - ../../base/resource-quotas

namespace: default

patches:
  - path: patches/namespace-env.yaml
    target:
      kind: Namespace

configMapGenerator:
  - name: environment-config
    namespace: default
    literals:
      - ENVIRONMENT=${environment}
      - DOMAIN=${LIONS_DOMAIN:-dev.lions.dev}
EOF
            # Tentative avec le chemin alternatif si le chemin Windows échoue
            if [[ "${is_windows}" == "true" && "${kustomization_file}" == *"\\"* ]]; then
                local kustomization_file_unix=$(echo "${kustomization_file}" | tr '\\' '/')
                log "DEBUG" "Tentative avec le chemin Unix pour kustomization.yaml: ${kustomization_file_unix}"
                if ! cat > "${kustomization_file_unix}" << EOF 2>/dev/null; then
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base/namespaces
  - ../../base/storage-classes
  - ../../base/network-policies
  - ../../base/resource-quotas

namespace: default

patches:
  - path: patches/namespace-env.yaml
    target:
      kind: Namespace

configMapGenerator:
  - name: environment-config
    namespace: default
    literals:
      - ENVIRONMENT=${environment}
      - DOMAIN=${LIONS_DOMAIN:-dev.lions.dev}
EOF
                    log "ERROR" "Impossible de créer le fichier kustomization.yaml: ${kustomization_file}"
                    cleanup
                    exit 1
                else
                    kustomization_file="${kustomization_file_unix}"
                fi
            else
                log "ERROR" "Impossible de créer le fichier kustomization.yaml: ${kustomization_file}"
                cleanup
                exit 1
            fi
        fi

        # Créer le répertoire patches avec gestion d'erreur améliorée
        local patches_dir="${k8s_overlay_dir}/patches"
        if [[ "${is_windows}" == "true" && "${k8s_overlay_dir}" == *"\\"* ]]; then
            patches_dir="${k8s_overlay_dir}\\patches"
        fi

        if ! mkdir -p "${patches_dir}" 2>/dev/null; then
            # Tentative avec le chemin alternatif
            if [[ "${is_windows}" == "true" ]]; then
                local patches_dir_alt
                if [[ "${patches_dir}" == *"\\"* ]]; then
                    patches_dir_alt=$(echo "${patches_dir}" | tr '\\' '/')
                else
                    patches_dir_alt=$(echo "${patches_dir}" | tr '/' '\\')
                fi
                log "DEBUG" "Tentative avec le chemin alternatif pour patches: ${patches_dir_alt}"
                if ! mkdir -p "${patches_dir_alt}" 2>/dev/null; then
                    log "ERROR" "Impossible de créer le répertoire patches: ${patches_dir}"
                    cleanup
                    exit 1
                else
                    patches_dir="${patches_dir_alt}"
                fi
            else
                log "ERROR" "Impossible de créer le répertoire patches: ${patches_dir}"
                cleanup
                exit 1
            fi
        fi

        # Créer un fichier patch par défaut pour les namespaces
        local namespace_patch="${patches_dir}/namespace-env.yaml"
        if ! cat > "${namespace_patch}" << EOF 2>/dev/null; then
apiVersion: v1
kind: Namespace
metadata:
  name: default
  labels:
    environment: ${environment}
EOF
            # Tentative avec le chemin alternatif
            if [[ "${is_windows}" == "true" ]]; then
                local namespace_patch_alt
                if [[ "${namespace_patch}" == *"\\"* ]]; then
                    namespace_patch_alt=$(echo "${namespace_patch}" | tr '\\' '/')
                else
                    namespace_patch_alt=$(echo "${namespace_patch}" | tr '/' '\\')
                fi
                log "DEBUG" "Tentative avec le chemin alternatif pour namespace-env.yaml: ${namespace_patch_alt}"
                if ! cat > "${namespace_patch_alt}" << EOF 2>/dev/null; then
apiVersion: v1
kind: Namespace
metadata:
  name: default
  labels:
    environment: ${environment}
EOF
                    log "ERROR" "Impossible de créer le fichier namespace-env.yaml: ${namespace_patch}"
                    cleanup
                    exit 1
                fi
            else
                log "ERROR" "Impossible de créer le fichier namespace-env.yaml: ${namespace_patch}"
                cleanup
                exit 1
            fi
        fi

        log "SUCCESS" "Fichier kustomization.yaml créé: ${kustomization_file}"
    fi

    # Extraction des informations de connexion
    log "INFO" "Extraction des informations de connexion..."

    # Utilisation de la fonction robuste d'extraction d'informations d'inventaire
    if ! extraire_informations_inventaire; then
        log "ERROR" "Échec de l'extraction des informations de connexion"
        cleanup
        exit 1
    fi

    if [[ -z "${ansible_host}" || -z "${ansible_port}" || -z "${ansible_user}" ]]; then
        log "ERROR" "Impossible d'extraire les informations de connexion du fichier d'inventaire"
        log "ERROR" "Vérifiez que le fichier d'inventaire contient les variables ansible_host, ansible_port et ansible_user"
        cleanup
        exit 1
    fi

    log "INFO" "Informations de connexion: ${ansible_user}@${ansible_host}:${ansible_port}"

    # Vérification de la connectivité réseau
    log "INFO" "Vérification de la connectivité réseau..."
    if ! check_network; then
        log "ERROR" "Vérification de la connectivité réseau échouée"
        cleanup
        exit 1
    fi

    # Vérification de la connexion SSH (uniquement si exécution distante)
    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        log "INFO" "Exécution locale détectée, vérification de la connexion SSH ignorée"
    else
        log "INFO" "Vérification de la connexion SSH..."

        # Utilisation de la fonction robust_ssh pour la vérification de connexion
        if robust_ssh "${ansible_host}" "${ansible_port}" "${ansible_user}" "echo 'Connexion SSH réussie'" "" "true"; then
            log "SUCCESS" "Connexion SSH réussie"
        else
            log "ERROR" "Impossible de se connecter au VPS via SSH (${ansible_user}@${ansible_host}:${ansible_port})"
            log "ERROR" "Vérifiez vos clés SSH et les paramètres de connexion"

            # Vérification des clés SSH (plus complète)
            local ssh_keys_found=false
            local key_types=("id_rsa" "id_ed25519" "id_ecdsa" "id_dsa")

            for key_type in "${key_types[@]}"; do
                if [[ -f ~/.ssh/${key_type} ]]; then
                    ssh_keys_found=true
                    log "INFO" "Clé SSH trouvée: ~/.ssh/${key_type}"
                fi
            done

            if [[ "${ssh_keys_found}" == "false" ]]; then
                log "ERROR" "Aucune clé SSH trouvée dans ~/.ssh/"

                # Détection de WSL pour des instructions spécifiques
                if [[ "$(uname -r)" == *"WSL"* || "$(uname -r)" == *"Microsoft"* ]]; then
                    log "INFO" "Environnement WSL détecté. Vous pouvez:"
                    log "INFO" "1. Générer une nouvelle clé SSH: ssh-keygen -t ed25519"
                    log "INFO" "2. Copier vos clés Windows: cp /mnt/c/Users/$USER/.ssh/id_rsa* ~/.ssh/"
                    log "INFO" "3. Assurez-vous que les permissions sont correctes: chmod 600 ~/.ssh/id_rsa"
                else
                    log "ERROR" "Générez une paire de clés avec: ssh-keygen -t ed25519"
                fi
            fi

            # Vérification du fichier known_hosts
            if ! grep -q "${ansible_host}" ~/.ssh/known_hosts 2>/dev/null; then
                log "WARNING" "L'hôte ${ansible_host} n'est pas dans le fichier known_hosts"
                log "WARNING" "Essayez d'abord de vous connecter manuellement: ssh -p ${ansible_port} ${ansible_user}@${ansible_host}"
                log "INFO" "Ou ajoutez l'hôte automatiquement: ssh-keyscan -p ${ansible_port} -H ${ansible_host} >> ~/.ssh/known_hosts"
            fi

            # Vérification si l'utilisateur peut se connecter manuellement
            log "INFO" "Pouvez-vous vous connecter manuellement avec: ssh -p ${ansible_port} ${ansible_user}@${ansible_host} ?"
            log "INFO" "Si oui, vérifiez les permissions de vos clés SSH: chmod 600 ~/.ssh/id_*"

            cleanup
            exit 1
        fi
    fi

    # Vérification des ressources du VPS
    log "INFO" "Vérification des ressources du VPS..."
    local vps_cpu_cores
    local vps_memory_total
    local vps_disk_free
    local cmd_output

    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        # Utilisation de commandes locales pour obtenir les ressources
        vps_cpu_cores=$(nproc --all 2>/dev/null || echo "0")
        vps_memory_total=$(free -m | awk '/^Mem:/ {print $2}' 2>/dev/null || echo "0")
        vps_disk_free=$(df -m / | awk 'NR==2 {print $4}' 2>/dev/null || echo "0")
    else
        # Utilisation de commandes SSH directes avec capture complète de la sortie pour le débogage
        log "DEBUG" "Récupération des informations CPU..."
        cmd_output=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "cat /proc/cpuinfo | grep -c processor" 2>/dev/null || echo "Erreur")
        log "DEBUG" "Sortie de la commande CPU: ${cmd_output}"
        if [[ "${cmd_output}" == "Erreur" || ! "${cmd_output}" =~ ^[0-9]+$ ]]; then
            log "DEBUG" "Tentative alternative pour CPU avec nproc..."
            cmd_output=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "nproc --all" 2>/dev/null || echo "Erreur")
            log "DEBUG" "Sortie de la commande nproc: ${cmd_output}"
        fi
        if [[ "${cmd_output}" == "Erreur" || ! "${cmd_output}" =~ ^[0-9]+$ ]]; then
            vps_cpu_cores="0"
        else
            vps_cpu_cores="${cmd_output}"
        fi

        log "DEBUG" "Récupération des informations mémoire..."
        cmd_output=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "free -m | grep Mem | awk '{print \$2}'" 2>/dev/null || echo "Erreur")
        log "DEBUG" "Sortie de la commande mémoire: ${cmd_output}"
        if [[ "${cmd_output}" == "Erreur" || ! "${cmd_output}" =~ ^[0-9]+$ ]]; then
            log "DEBUG" "Tentative alternative pour la mémoire..."
            cmd_output=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "cat /proc/meminfo | grep MemTotal | awk '{print \$2/1024}'" 2>/dev/null || echo "Erreur")
            log "DEBUG" "Sortie de la commande meminfo: ${cmd_output}"
        fi
        if [[ "${cmd_output}" == "Erreur" || ! "${cmd_output}" =~ ^[0-9.]+$ ]]; then
            vps_memory_total="0"
        else
            # Arrondir à l'entier le plus proche si c'est un nombre décimal
            vps_memory_total=$(printf "%.0f" "${cmd_output}" 2>/dev/null || echo "${cmd_output}" | cut -d. -f1)
        fi

        log "DEBUG" "Récupération des informations disque..."
        cmd_output=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "df -m / | grep -v Filesystem | head -1 | awk '{print \$4}'" 2>/dev/null || echo "Erreur")
        log "DEBUG" "Sortie de la commande disque: ${cmd_output}"
        if [[ "${cmd_output}" == "Erreur" || ! "${cmd_output}" =~ ^[0-9]+$ ]]; then
            log "DEBUG" "Tentative alternative pour le disque..."
            cmd_output=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "df -k / | grep -v Filesystem | head -1 | awk '{print \$4/1024}'" 2>/dev/null || echo "Erreur")
            log "DEBUG" "Sortie de la commande df -k: ${cmd_output}"
        fi
        if [[ "${cmd_output}" == "Erreur" || ! "${cmd_output}" =~ ^[0-9.]+$ ]]; then
            vps_disk_free="0"
        else
            # Arrondir à l'entier le plus proche si c'est un nombre décimal
            vps_disk_free=$(printf "%.0f" "${cmd_output}" 2>/dev/null || echo "${cmd_output}" | cut -d. -f1)
        fi
    fi

    # Log des valeurs brutes pour le débogage
    log "DEBUG" "Valeurs brutes après récupération: CPU=${vps_cpu_cores}, RAM=${vps_memory_total}, Disk=${vps_disk_free}"

    # Nettoyage des valeurs pour s'assurer qu'elles sont des nombres entiers valides
    if [[ ! "${vps_cpu_cores}" =~ ^[0-9]+$ ]]; then
        log "DEBUG" "Nettoyage de la valeur CPU non numérique: ${vps_cpu_cores}"
        vps_cpu_cores=$(echo "${vps_cpu_cores}" | tr -cd '0-9' || echo "0")
    fi

    if [[ ! "${vps_memory_total}" =~ ^[0-9]+$ ]]; then
        log "DEBUG" "Nettoyage de la valeur RAM non numérique: ${vps_memory_total}"
        vps_memory_total=$(echo "${vps_memory_total}" | tr -cd '0-9' || echo "0")
    fi

    if [[ ! "${vps_disk_free}" =~ ^[0-9]+$ ]]; then
        log "DEBUG" "Nettoyage de la valeur disque non numérique: ${vps_disk_free}"
        vps_disk_free=$(echo "${vps_disk_free}" | tr -cd '0-9' || echo "0")
    fi

    # Log des valeurs nettoyées pour le débogage
    log "DEBUG" "Valeurs après nettoyage: CPU=${vps_cpu_cores}, RAM=${vps_memory_total}, Disk=${vps_disk_free}"

    # Vérification que les valeurs sont des nombres valides et non nuls
    if [[ -z "${vps_cpu_cores}" || "${vps_cpu_cores}" == "0" ]]; then
        log "WARNING" "Impossible de déterminer le nombre de cœurs CPU du VPS"
        vps_cpu_cores=0
    fi

    if [[ -z "${vps_memory_total}" || "${vps_memory_total}" == "0" ]]; then
        log "WARNING" "Impossible de déterminer la mémoire totale du VPS"
        vps_memory_total=0
    fi

    if [[ -z "${vps_disk_free}" || "${vps_disk_free}" == "0" ]]; then
        log "WARNING" "Impossible de déterminer l'espace disque libre du VPS"
        vps_disk_free=0
    fi

    # Affichage des ressources après nettoyage des valeurs
    log "INFO" "Ressources du VPS (valeurs finales): ${vps_cpu_cores} cœurs CPU, ${vps_memory_total}MB RAM, ${vps_disk_free}MB espace disque libre"

    # Log supplémentaire pour le débogage des valeurs finales
    log "DEBUG" "Valeurs finales pour comparaison: CPU=${vps_cpu_cores}, RAM=${vps_memory_total}, Disk=${vps_disk_free}"

    if [[ ${vps_cpu_cores} -lt 2 && ${vps_cpu_cores} -ne 0 ]]; then
        log "WARNING" "Le VPS a moins de 2 cœurs CPU (${vps_cpu_cores}), ce qui peut affecter les performances"
    fi

    if [[ ${vps_memory_total} -lt 4096 && ${vps_memory_total} -ne 0 ]]; then
        log "WARNING" "Le VPS a moins de 4GB de RAM (${vps_memory_total}MB), ce qui peut affecter les performances"
    fi

    if [[ ${vps_disk_free} -lt 20000 && ${vps_disk_free} -ne 0 ]]; then
        log "WARNING" "Le VPS a moins de 20GB d'espace disque libre (${vps_disk_free}MB), ce qui peut être insuffisant"
    fi

    log "SUCCESS" "Tous les prérequis sont satisfaits"

    # Vérification de l'état précédent
    if [[ -f "${STATE_FILE}" ]]; then
        local previous_step
        previous_step=$(cat "${STATE_FILE}")
        log "INFO" "État précédent détecté: ${previous_step}"
        log "INFO" "Voulez-vous reprendre à partir de cette étape? (o/N)"

        read -r answer
        if [[ "${answer}" =~ ^[Oo]$ ]]; then
            log "INFO" "Reprise à partir de l'étape: ${previous_step}"

            case "${previous_step}" in
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
                "verify")
                    verifier_installation
                    ;;
                *)
                    log "WARNING" "Étape inconnue: ${previous_step}, reprise depuis le début"
                    ;;
            esac

            # Nettoyage et sortie
            cleanup
            exit 0
        else
            log "INFO" "Démarrage d'une nouvelle installation"
            rm -f "${STATE_FILE}"
        fi
    fi
}

# Fonction pour comparer des versions
function version_greater_equal() {
    local version1=$1
    local version2=$2

    # Normalisation des versions pour la comparaison
    local v1_parts=(${version1//./ })
    local v2_parts=(${version2//./ })

    # Compléter les tableaux avec des zéros si nécessaire
    local max_length=$(( ${#v1_parts[@]} > ${#v2_parts[@]} ? ${#v1_parts[@]} : ${#v2_parts[@]} ))
    for ((i=${#v1_parts[@]}; i<max_length; i++)); do
        v1_parts[i]=0
    done
    for ((i=${#v2_parts[@]}; i<max_length; i++)); do
        v2_parts[i]=0
    done

    # Comparaison des parties de version
    for ((i=0; i<max_length; i++)); do
        if [[ ${v1_parts[i]} -gt ${v2_parts[i]} ]]; then
            return 0  # version1 > version2
        elif [[ ${v1_parts[i]} -lt ${v2_parts[i]} ]]; then
            return 1  # version1 < version2
        fi
    done

    return 0  # version1 == version2
}

# Fonction d'initialisation du VPS
function initialiser_vps() {
    log "INFO" "Initialisation du VPS..."
    INSTALLATION_STEP="init_vps"

    # Sauvegarde de l'état actuel
    echo "${INSTALLATION_STEP}" > "${STATE_FILE}"

    # Sauvegarde de l'état du VPS avant modification (optionnelle)
    backup_state "pre-init-vps" "true"

    # Construction de la commande Ansible
    # Utilisation de chemins absolus pour éviter les problèmes de résolution de chemin
    local inventory_path="${ANSIBLE_DIR}/${inventory_file}"
    local playbook_path="${ANSIBLE_DIR}/playbooks/init-vps.yml"

    # Vérification que les fichiers existent
    if [[ ! -f "${inventory_path}" ]]; then
        log "ERROR" "Fichier d'inventaire non trouvé: ${inventory_path}"
        log "ERROR" "Vérifiez que le chemin est correct et que le fichier existe"
        return 1
    fi

    if [[ ! -f "${playbook_path}" ]]; then
        log "ERROR" "Fichier de playbook non trouvé: ${playbook_path}"
        log "ERROR" "Vérifiez que le chemin est correct et que le fichier existe"
        return 1
    fi

    # Détection du système d'exploitation pour le formatage des chemins
    local os_name
    os_name=$(uname -s)
    if [[ "${os_name}" == *"MINGW"* || "${os_name}" == *"MSYS"* || "${os_name}" == *"CYGWIN"* || "${os_name}" == *"Windows"* ]]; then
        # Windows: convertir les chemins Unix en chemins Windows
        log "DEBUG" "Système Windows détecté, conversion des chemins"

        # Vérifier si les chemins contiennent déjà des backslashes
        if [[ "${inventory_path}" != *"\\"* ]]; then
            # Remplacer les slashes par des backslashes pour Windows
            inventory_path=$(echo "${inventory_path}" | tr '/' '\\')
            log "DEBUG" "Chemin d'inventaire converti: ${inventory_path}"
        fi

        if [[ "${playbook_path}" != *"\\"* ]]; then
            # Remplacer les slashes par des backslashes pour Windows
            playbook_path=$(echo "${playbook_path}" | tr '/' '\\')
            log "DEBUG" "Chemin de playbook converti: ${playbook_path}"
        fi

        # Vérifier si les chemins existent après conversion
        if [[ ! -f "${inventory_path}" ]]; then
            log "WARNING" "Le chemin d'inventaire converti n'existe pas: ${inventory_path}"
            log "DEBUG" "Tentative d'utilisation du chemin original"
            inventory_path="${ANSIBLE_DIR}/${inventory_file}"
        fi

        if [[ ! -f "${playbook_path}" ]]; then
            log "WARNING" "Le chemin de playbook converti n'existe pas: ${playbook_path}"
            log "DEBUG" "Tentative d'utilisation du chemin original"
            playbook_path="${ANSIBLE_DIR}/playbooks/init-vps.yml"
        fi
    fi

    local ansible_cmd="ansible-playbook -i \"${inventory_path}\" \"${playbook_path}\" --ask-become-pass"

    if [[ "${debug_mode}" == "true" ]]; then
        ansible_cmd="${ansible_cmd} -vvv"
    fi

    log "INFO" "Exécution de la commande: ${ansible_cmd}"
    LAST_COMMAND="${ansible_cmd}"

    # Exécution de la commande avec timeout
    if run_with_timeout "${ansible_cmd}" "${TIMEOUT_SECONDS}" "ansible_playbook"; then
        log "SUCCESS" "Initialisation du VPS terminée avec succès"

        # Vérification de l'état du VPS après initialisation
        if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl is-active --quiet sshd && sudo systemctl is-active --quiet fail2ban && sudo systemctl is-active --quiet ufw" &>/dev/null; then
            log "WARNING" "Certains services essentiels ne sont pas actifs après l'initialisation"
            log "WARNING" "Vérifiez manuellement l'état des services sur le VPS"
        else
            log "INFO" "Services essentiels actifs et fonctionnels"
        fi
    else
        log "ERROR" "Échec de l'initialisation du VPS"

        # Vérification des erreurs courantes
        if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo grep -i 'failed=' /var/log/ansible.log 2>/dev/null | tail -10" &>/dev/null; then
            log "INFO" "Dernières erreurs Ansible sur le VPS:"
            ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo grep -i 'failed=' /var/log/ansible.log 2>/dev/null | tail -10" 2>/dev/null || true
        fi

        # Tentative de diagnostic
        log "INFO" "Tentative de diagnostic des problèmes..."

        # Vérification des droits sudo
        if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo -n true" &>/dev/null; then
            log "ERROR" "L'utilisateur ${ansible_user} n'a pas les droits sudo sans mot de passe"
            log "ERROR" "Assurez-vous que l'utilisateur est configuré correctement dans le fichier sudoers"
        fi

        # Vérification de l'espace disque sur le VPS
        local disk_info
        disk_info=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo df -h /" 2>/dev/null || echo "Impossible de vérifier l'espace disque")
        log "INFO" "Espace disque sur le VPS:"
        echo "${disk_info}"

        cleanup
        exit 1
    fi
}

# Fonction d'installation de K3s
function check_k3s_logs() {
    log "INFO" "Vérification des journaux du service K3s..."

    # Vérifier si on peut accéder au VPS
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "echo 'Connexion réussie'" &>/dev/null; then
        log "ERROR" "Impossible de se connecter au VPS pour vérifier les journaux K3s"
        return 1
    fi

    # Afficher les 20 dernières lignes des journaux K3s
    local k3s_logs
    k3s_logs=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo journalctl -u k3s -n 20 --no-pager" 2>/dev/null || echo "Impossible de récupérer les journaux")
    log "INFO" "Dernières lignes des journaux K3s:"
    echo "${k3s_logs}"

    # Rechercher des erreurs spécifiques
    local error_logs
    error_logs=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo journalctl -u k3s -n 100 | grep -i 'error\|failed\|fatal'" 2>/dev/null || echo "")

    if [[ -n "${error_logs}" ]]; then
        log "WARNING" "Des erreurs ont été détectées dans les journaux K3s"
        log "WARNING" "Voici les erreurs détectées:"
        echo "${error_logs}"
        return 1
    else
        log "SUCCESS" "Aucune erreur majeure détectée dans les journaux K3s"
        return 0
    fi
}

function check_k3s_system_resources() {
    log "INFO" "Vérification des ressources système pour K3s..."

    # Vérifier si on peut accéder au VPS
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "echo 'Connexion réussie'" &>/dev/null; then
        log "ERROR" "Impossible de se connecter au VPS pour vérifier les ressources système"
        return 1
    fi

    # Vérifier l'espace disque
    local disk_usage
    disk_usage=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "df -h / | awk 'NR==2 {print \$5}' | sed 's/%//'" 2>/dev/null || echo "Erreur")

    if [[ "${disk_usage}" == "Erreur" ]]; then
        log "ERROR" "Impossible de vérifier l'espace disque"
    elif [[ "${disk_usage}" -gt 90 ]]; then
        log "ERROR" "Espace disque critique: ${disk_usage}%"
    elif [[ "${disk_usage}" -gt 80 ]]; then
        log "WARNING" "Espace disque faible: ${disk_usage}%"
    else
        log "SUCCESS" "Espace disque suffisant: ${disk_usage}%"
    fi

    # Vérifier la mémoire
    local free_mem
    free_mem=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "free -m | awk 'NR==2 {print \$4}'" 2>/dev/null || echo "Erreur")

    if [[ "${free_mem}" == "Erreur" ]]; then
        log "ERROR" "Impossible de vérifier la mémoire disponible"
    elif [[ "${free_mem}" -lt 512 ]]; then
        log "ERROR" "Mémoire disponible critique: ${free_mem} MB"
    elif [[ "${free_mem}" -lt 1024 ]]; then
        log "WARNING" "Mémoire disponible faible: ${free_mem} MB"
    else
        log "SUCCESS" "Mémoire disponible suffisante: ${free_mem} MB"
    fi

    # Vérifier la charge CPU
    local load_avg
    load_avg=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "cat /proc/loadavg | awk '{print \$1}'" 2>/dev/null || echo "Erreur")

    if [[ "${load_avg}" == "Erreur" ]]; then
        log "ERROR" "Impossible de vérifier la charge CPU"
    elif (( $(echo "${load_avg} > 2.0" | bc -l) )); then
        log "WARNING" "Charge CPU élevée: ${load_avg}"
    else
        log "SUCCESS" "Charge CPU normale: ${load_avg}"
    fi

    return 0
}

function restart_k3s_service() {
    log "INFO" "Redémarrage du service K3s..."

    # Vérifier si on peut accéder au VPS
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "echo 'Connexion réussie'" &>/dev/null; then
        log "ERROR" "Impossible de se connecter au VPS pour redémarrer K3s"
        return 1
    fi

    # Vérifier l'état actuel du service K3s
    local k3s_status
    k3s_status=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl status k3s" 2>/dev/null || echo "Impossible de récupérer l'état du service")
    log "DEBUG" "État actuel du service K3s avant redémarrage:"
    echo "${k3s_status}" | head -10

    # Vérifier les ressources système avant le redémarrage
    check_k3s_system_resources

    # Vérifier et corriger les drapeaux dépréciés avant le redémarrage
    log "INFO" "Vérification et correction des drapeaux dépréciés avant le redémarrage..."
    fix_k3s_deprecated_flags

    # Recharger le daemon systemd après correction des drapeaux dépréciés
    ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl daemon-reload" &>/dev/null

    # Redémarrer le service K3s avec capture des erreurs
    local restart_output
    restart_output=$(ssh -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl restart k3s 2>&1" || echo "Échec du redémarrage")

    if [[ "${restart_output}" == *"failed"* || "${restart_output}" == *"Échec"* ]]; then
        log "ERROR" "Échec du redémarrage du service K3s"
        log "ERROR" "Message d'erreur: ${restart_output}"

        # Récupérer les journaux du service pour diagnostiquer le problème
        local journal_output
        journal_output=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo journalctl -u k3s -n 20 --no-pager" 2>/dev/null || echo "Impossible de récupérer les journaux")
        log "DEBUG" "Journaux récents du service K3s:"
        echo "${journal_output}"

        # Vérifier les problèmes courants
        if [[ "${journal_output}" == *"port is already allocated"* ]]; then
            log "WARNING" "Un port requis par K3s est déjà utilisé"
            log "INFO" "Tentative de libération des ports..."
            ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo netstat -tulpn | grep 6443" 2>/dev/null
        elif [[ "${journal_output}" == *"insufficient memory"* || "${journal_output}" == *"cannot allocate memory"* ]]; then
            log "WARNING" "Mémoire insuffisante pour démarrer K3s"
            log "INFO" "Vérification de la mémoire disponible..."
            ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "free -m" 2>/dev/null
        elif [[ "${journal_output}" == *"permission denied"* ]]; then
            log "WARNING" "Problème de permissions détecté"
            log "INFO" "Tentative de correction des permissions..."
            ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo chmod -R 755 /var/lib/rancher/k3s 2>/dev/null || true" &>/dev/null
            ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo chmod 600 /etc/rancher/k3s/k3s.yaml 2>/dev/null || true" &>/dev/null
            # Nouvelle tentative après correction des permissions
            log "INFO" "Nouvelle tentative de redémarrage après correction des permissions..."
            ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl daemon-reload && sudo systemctl restart k3s" &>/dev/null
        fi

        return 1
    fi

    # Attendre que le service démarre
    log "INFO" "Attente du démarrage du service K3s..."
    local max_wait=30
    local waited=0
    local is_active=false

    while [[ "${waited}" -lt "${max_wait}" && "${is_active}" == "false" ]]; do
        if ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl is-active --quiet k3s" &>/dev/null; then
            is_active=true
        else
            sleep 2
            waited=$((waited + 2))
            log "INFO" "En attente du démarrage de K3s... (${waited}/${max_wait}s)"
        fi
    done

    # Vérifier si le service est actif après le redémarrage
    if [[ "${is_active}" == "false" ]]; then
        log "ERROR" "Le service K3s n'est pas actif après le redémarrage (timeout après ${max_wait}s)"

        # Récupérer l'état actuel du service pour diagnostiquer le problème
        local current_status
        current_status=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl status k3s" 2>/dev/null || echo "Impossible de récupérer l'état du service")
        log "DEBUG" "État actuel du service K3s après tentative de redémarrage:"
        echo "${current_status}" | head -10

        return 1
    else
        log "SUCCESS" "Le service K3s a été redémarré avec succès"

        # Vérifier que les composants essentiels sont en cours d'exécution
        log "INFO" "Vérification des composants K3s..."
        local pods_status
        pods_status=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo kubectl get pods -n kube-system" 2>/dev/null || echo "Impossible de vérifier les pods")
        log "DEBUG" "État des pods système:"
        echo "${pods_status}" | head -10

        return 0
    fi
}

function fix_k3s_deprecated_flags() {
    log "INFO" "Vérification et correction des drapeaux dépréciés dans la configuration K3s..."

    # Vérifier si on peut accéder au VPS
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "echo 'Connexion réussie'" &>/dev/null; then
        log "ERROR" "Impossible de se connecter au VPS pour corriger les drapeaux dépréciés"
        return 1
    fi

    # Vérifier l'existence du fichier de service K3s
    local service_exists
    service_exists=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "test -f /etc/systemd/system/k3s.service && echo 'true' || echo 'false'" 2>/dev/null)

    if [[ "${service_exists}" == "true" ]]; then
        log "INFO" "Fichier de service K3s trouvé, vérification des drapeaux dépréciés..."

        # Vérifier si le fichier contient des drapeaux dépréciés
        local contains_deprecated
        contains_deprecated=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "grep -q -- '--no-deploy' /etc/systemd/system/k3s.service && echo 'true' || echo 'false'" 2>/dev/null)

        if [[ "${contains_deprecated}" == "true" ]]; then
            log "WARNING" "Drapeaux dépréciés trouvés dans le fichier de service K3s"
            log "INFO" "Remplacement des drapeaux dépréciés..."

            # Remplacer les drapeaux dépréciés (plusieurs formats possibles)
            ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo sed -i 's/--no-deploy /--disable=/g; s/--no-deploy=/--disable=/g; s/--no-deploy\([[:space:]]\+\)\([[:alnum:]]\+\)/--disable=\2/g' /etc/systemd/system/k3s.service" &>/dev/null

            # Recharger le daemon systemd
            ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl daemon-reload" &>/dev/null

            log "SUCCESS" "Drapeaux dépréciés remplacés avec succès"
            return 0
        else
            log "INFO" "Aucun drapeau déprécié trouvé dans le fichier de service K3s"
        fi
    else
        log "WARNING" "Fichier de service K3s non trouvé (/etc/systemd/system/k3s.service)"

        # Vérifier s'il existe dans un autre emplacement
        local alt_service_exists
        alt_service_exists=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "find /etc/systemd/system -name 'k3s*.service' | wc -l" 2>/dev/null)

        if [[ "${alt_service_exists}" -gt 0 ]]; then
            log "INFO" "Fichiers de service K3s alternatifs trouvés, vérification des drapeaux dépréciés..."

            # Obtenir la liste des fichiers de service K3s
            local service_files
            service_files=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "find /etc/systemd/system -name 'k3s*.service'" 2>/dev/null)

            # Pour chaque fichier, vérifier et remplacer les drapeaux dépréciés
            echo "${service_files}" | while read -r service_file; do
                log "INFO" "Vérification du fichier ${service_file}..."

                local file_contains_deprecated
                file_contains_deprecated=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "grep -q -- '--no-deploy' \"${service_file}\" && echo 'true' || echo 'false'" 2>/dev/null)

                if [[ "${file_contains_deprecated}" == "true" ]]; then
                    log "WARNING" "Drapeaux dépréciés trouvés dans ${service_file}"
                    log "INFO" "Remplacement des drapeaux dépréciés..."

                    # Remplacer les drapeaux dépréciés (plusieurs formats possibles)
                    ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo sed -i 's/--no-deploy /--disable=/g; s/--no-deploy=/--disable=/g; s/--no-deploy\([[:space:]]\+\)\([[:alnum:]]\+\)/--disable=\2/g' \"${service_file}\"" &>/dev/null

                    log "SUCCESS" "Drapeaux dépréciés remplacés avec succès dans ${service_file}"
                else
                    log "INFO" "Aucun drapeau déprécié trouvé dans ${service_file}"
                fi
            done

            # Recharger le daemon systemd
            ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl daemon-reload" &>/dev/null

            log "SUCCESS" "Vérification et correction des drapeaux dépréciés terminées"
            return 0
        else
            log "WARNING" "Aucun fichier de service K3s trouvé sur le système"
        fi
    fi

    return 0
}

function repair_k3s() {
    log "INFO" "Tentative de réparation de l'installation K3s..."

    # Vérifier si on peut accéder au VPS
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "echo 'Connexion réussie'" &>/dev/null; then
        log "ERROR" "Impossible de se connecter au VPS pour réparer K3s"
        return 1
    fi

    # Vérifier les fichiers de configuration
    local config_exists
    config_exists=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "test -f /etc/rancher/k3s/k3s.yaml && echo 'true' || echo 'false'" 2>/dev/null)

    if [[ "${config_exists}" == "false" ]]; then
        log "ERROR" "Fichier de configuration K3s manquant"
    fi

    # Vérifier les permissions des répertoires
    log "INFO" "Vérification et correction des permissions des répertoires K3s..."
    ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo chmod 755 /var/lib/rancher/k3s 2>/dev/null || true" &>/dev/null
    ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo chmod 600 /etc/rancher/k3s/k3s.yaml 2>/dev/null || true" &>/dev/null

    # Vérifier et corriger les problèmes de réseau
    log "INFO" "Vérification de la configuration réseau..."
    local cni_exists
    cni_exists=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "ip addr show | grep -q 'cni0' && echo 'true' || echo 'false'" 2>/dev/null)

    if [[ "${cni_exists}" == "false" ]]; then
        log "WARNING" "Interface CNI non détectée"
    fi

    # Corriger les drapeaux dépréciés dans la configuration K3s
    fix_k3s_deprecated_flags

    # Redémarrer le service après les réparations
    restart_k3s_service
    return $?
}

function reinstall_k3s() {
    log "WARNING" "La réinstallation de K3s est une opération destructive"
    log "WARNING" "Toutes les données Kubernetes seront perdues"
    log "WARNING" "Assurez-vous d'avoir des sauvegardes avant de continuer"

    # Demander confirmation
    local confirm
    read -p "Êtes-vous sûr de vouloir réinstaller K3s? (oui/NON): " confirm
    if [[ "${confirm}" != "oui" ]]; then
        log "INFO" "Réinstallation annulée"
        return 1
    fi

    # Vérifier si on peut accéder au VPS
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "echo 'Connexion réussie'" &>/dev/null; then
        log "ERROR" "Impossible de se connecter au VPS pour réinstaller K3s"
        return 1
    fi

    log "INFO" "Désinstallation de K3s..."
    if ! ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo /usr/local/bin/k3s-uninstall.sh" &>/dev/null; then
        log "ERROR" "Échec de la désinstallation de K3s"
        return 1
    fi

    log "INFO" "Réinstallation de K3s..."
    # Utiliser le playbook Ansible pour réinstaller K3s
    local inventory_path="${ANSIBLE_DIR}/${inventory_file}"
    local playbook_path="${ANSIBLE_DIR}/playbooks/install-k3s.yml"

    # Vérification que les fichiers existent
    if [[ ! -f "${inventory_path}" ]]; then
        log "ERROR" "Fichier d'inventaire non trouvé: ${inventory_path}"
        return 1
    fi

    if [[ ! -f "${playbook_path}" ]]; then
        log "ERROR" "Fichier de playbook non trouvé: ${playbook_path}"
        return 1
    fi

    local ansible_cmd="ansible-playbook -i \"${inventory_path}\" \"${playbook_path}\" --ask-become-pass"

    if [[ "${debug_mode}" == "true" ]]; then
        ansible_cmd="${ansible_cmd} -vvv"
    fi

    log "INFO" "Exécution de la commande: ${ansible_cmd}"
    LAST_COMMAND="${ansible_cmd}"

    # Exécution de la commande avec timeout
    if ! run_with_timeout "${ansible_cmd}" 3600 "ansible_playbook"; then
        log "ERROR" "Échec de la réinstallation de K3s"
        return 1
    fi

    # Correction des drapeaux dépréciés après la réinstallation
    log "INFO" "Vérification et correction des drapeaux dépréciés après la réinstallation..."
    fix_k3s_deprecated_flags

    # Redémarrage du service K3s après correction des drapeaux dépréciés
    log "INFO" "Redémarrage du service K3s après correction des drapeaux dépréciés..."
    ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl daemon-reload && sudo systemctl restart k3s" &>/dev/null

    # Attente que le service K3s soit prêt
    log "INFO" "Attente que le service K3s soit prêt..."
    sleep 10

    # Vérifier si le service est actif après la réinstallation
    if ! ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl is-active --quiet k3s" &>/dev/null; then
        log "ERROR" "Le service K3s n'est pas actif après la réinstallation"
        return 1
    else
        log "SUCCESS" "K3s a été réinstallé avec succès"

        # Configuration de kubectl pour l'utilisateur courant
        log "INFO" "Configuration de kubectl pour l'utilisateur courant..."
        mkdir -p "${HOME}/.kube"

        if ! scp -P "${ansible_port}" "${ansible_user}@${ansible_host}:/etc/rancher/k3s/k3s.yaml" "${HOME}/.kube/config" &>/dev/null; then
            log "WARNING" "Impossible de récupérer le fichier kubeconfig"
            log "WARNING" "Vous devrez configurer kubectl manuellement"
        else
            # Remplacer localhost par l'adresse IP du VPS
            sed -i "s/127.0.0.1/${ansible_host}/g" "${HOME}/.kube/config"
            log "SUCCESS" "kubectl configuré avec succès"
        fi

        return 0
    fi
}

function check_fix_k3s() {
    log "INFO" "Vérification et réparation du service K3s..."

    # Vérifier si on peut accéder au VPS
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "echo 'Connexion réussie'" &>/dev/null; then
        log "ERROR" "Impossible de se connecter au VPS pour vérifier K3s"
        return 1
    fi

    # Vérifier l'état du service K3s
    local k3s_active
    k3s_active=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl is-active k3s" 2>/dev/null || echo "unknown")

    # Vérifier et corriger les drapeaux dépréciés, même si le service est actif
    log "INFO" "Vérification des drapeaux dépréciés dans la configuration K3s..."
    fix_k3s_deprecated_flags

    if [[ "${k3s_active}" == "active" ]]; then
        log "SUCCESS" "Le service K3s est actif et en cours d'exécution"
        return 0
    else
        log "WARNING" "Le service K3s n'est pas actif (état: ${k3s_active})"

        # Vérifier les journaux et les ressources
        check_k3s_logs
        check_k3s_system_resources

        # Demander à l'utilisateur quelle action entreprendre
        log "INFO" "Que souhaitez-vous faire?"
        echo "1. Redémarrer le service K3s"
        echo "2. Tenter de réparer l'installation K3s"
        echo "3. Réinstaller K3s (destructif)"
        echo "4. Quitter sans action"

        local choice
        read -p "Votre choix (1-4): " choice

        case $choice in
            1)
                restart_k3s_service
                ;;
            2)
                repair_k3s
                ;;
            3)
                reinstall_k3s
                ;;
            4)
                log "INFO" "Aucune action entreprise"
                return 1
                ;;
            *)
                log "ERROR" "Choix invalide"
                return 1
                ;;
        esac

        # Vérification finale
        k3s_active=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl is-active k3s" 2>/dev/null || echo "unknown")

        if [[ "${k3s_active}" == "active" ]]; then
            log "SUCCESS" "Le service K3s est maintenant actif et en cours d'exécution"
            return 0
        else
            log "ERROR" "Le service K3s présente toujours des problèmes (état: ${k3s_active})"
            log "WARNING" "Consultez les journaux système pour plus d'informations"
            log "WARNING" "Vous pouvez également essayer une réinstallation complète"
            return 1
        fi
    fi
}

function installer_k3s() {
    log "INFO" "Installation de K3s..."
    INSTALLATION_STEP="install_k3s"

    # Sauvegarde de l'état actuel
    echo "${INSTALLATION_STEP}" > "${STATE_FILE}"

    # Sauvegarde de l'état du VPS avant modification (optionnelle)
    backup_state "pre-install-k3s" "true"

    # Construction de la commande Ansible
    # Utilisation de chemins absolus pour éviter les problèmes de résolution de chemin
    local inventory_path="${ANSIBLE_DIR}/${inventory_file}"
    local playbook_path="${ANSIBLE_DIR}/playbooks/install-k3s.yml"

    # Vérification que les fichiers existent
    if [[ ! -f "${inventory_path}" ]]; then
        log "ERROR" "Fichier d'inventaire non trouvé: ${inventory_path}"
        log "ERROR" "Vérifiez que le chemin est correct et que le fichier existe"
        return 1
    fi

    if [[ ! -f "${playbook_path}" ]]; then
        log "ERROR" "Fichier de playbook non trouvé: ${playbook_path}"
        log "ERROR" "Vérifiez que le chemin est correct et que le fichier existe"
        return 1
    fi

    # Détection du système d'exploitation pour le formatage des chemins
    local os_name
    os_name=$(uname -s)
    if [[ "${os_name}" == *"MINGW"* || "${os_name}" == *"MSYS"* || "${os_name}" == *"CYGWIN"* || "${os_name}" == *"Windows"* ]]; then
        # Windows: convertir les chemins Unix en chemins Windows
        log "DEBUG" "Système Windows détecté, conversion des chemins"

        # Vérifier si les chemins contiennent déjà des backslashes
        if [[ "${inventory_path}" != *"\\"* ]]; then
            # Remplacer les slashes par des backslashes pour Windows
            inventory_path=$(echo "${inventory_path}" | tr '/' '\\')
            log "DEBUG" "Chemin d'inventaire converti: ${inventory_path}"
        fi

        if [[ "${playbook_path}" != *"\\"* ]]; then
            # Remplacer les slashes par des backslashes pour Windows
            playbook_path=$(echo "${playbook_path}" | tr '/' '\\')
            log "DEBUG" "Chemin de playbook converti: ${playbook_path}"
        fi

        # Vérifier si les chemins existent après conversion
        if [[ ! -f "${inventory_path}" ]]; then
            log "WARNING" "Le chemin d'inventaire converti n'existe pas: ${inventory_path}"
            log "DEBUG" "Tentative d'utilisation du chemin original"
            inventory_path="${ANSIBLE_DIR}/${inventory_file}"
        fi

        if [[ ! -f "${playbook_path}" ]]; then
            log "WARNING" "Le chemin de playbook converti n'existe pas: ${playbook_path}"
            log "DEBUG" "Tentative d'utilisation du chemin original"
            playbook_path="${ANSIBLE_DIR}/playbooks/install-k3s.yml"
        fi
    fi

    local ansible_cmd="ansible-playbook -i \"${inventory_path}\" \"${playbook_path}\" --ask-become-pass"

    if [[ "${debug_mode}" == "true" ]]; then
        ansible_cmd="${ansible_cmd} -vvv"
    fi

    log "INFO" "Exécution de la commande: ${ansible_cmd}"
    LAST_COMMAND="${ansible_cmd}"

    # Exécution de la commande avec timeout
    if run_with_timeout "${ansible_cmd}" 3600 "ansible_playbook"; then  # Timeout plus long (1h) pour l'installation de K3s
        log "SUCCESS" "Installation de K3s terminée avec succès"

        # Correction des drapeaux dépréciés dans la configuration K3s
        log "INFO" "Vérification et correction des drapeaux dépréciés dans la configuration K3s..."
        fix_k3s_deprecated_flags

        # Redémarrage du service K3s après correction des drapeaux dépréciés
        log "INFO" "Redémarrage du service K3s après correction des drapeaux dépréciés..."
        ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl daemon-reload && sudo systemctl restart k3s" &>/dev/null

        # Attente que le service K3s soit prêt
        log "INFO" "Attente que le service K3s soit prêt..."
        sleep 10

        # Vérification de l'installation de K3s
        if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl is-active --quiet k3s" &>/dev/null; then
            log "WARNING" "Le service K3s ne semble pas être actif après l'installation"
            log "WARNING" "Vérifiez manuellement l'état du service sur le VPS"
        else
            log "INFO" "Service K3s actif et fonctionnel"

            # Vérification des pods système
            local pods_status
            pods_status=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo kubectl get pods -n kube-system -o wide" 2>/dev/null || echo "Impossible de vérifier les pods")
            log "INFO" "État des pods système:"
            echo "${pods_status}"

            # Vérification de l'accès au cluster depuis la machine locale
            if ! kubectl cluster-info &>/dev/null; then
                log "WARNING" "Impossible d'accéder au cluster K3s depuis la machine locale"
                log "WARNING" "Vérifiez votre configuration kubectl et le fichier kubeconfig"

                # Tentative de récupération du fichier kubeconfig
                local kubeconfig_dir="${HOME}/.kube"
                mkdir -p "${kubeconfig_dir}"

                if scp -P "${ansible_port}" "${ansible_user}@${ansible_host}:/home/${ansible_user}/.kube/config" "${kubeconfig_dir}/config.k3s" &>/dev/null; then
                    log "INFO" "Fichier kubeconfig récupéré dans ${kubeconfig_dir}/config.k3s"
                    log "INFO" "Utilisez la commande: export KUBECONFIG=${kubeconfig_dir}/config.k3s"
                else
                    log "ERROR" "Impossible de récupérer le fichier kubeconfig"
                fi
            else
                log "INFO" "Accès au cluster K3s depuis la machine locale vérifié avec succès"
            fi
        fi
    else
        log "ERROR" "Échec de l'installation de K3s"

        # Vérification des erreurs courantes
        if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo grep -i 'failed=' /var/log/ansible.log 2>/dev/null | tail -10" &>/dev/null; then
            log "INFO" "Dernières erreurs Ansible sur le VPS:"
            ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo grep -i 'failed=' /var/log/ansible.log 2>/dev/null | tail -10" 2>/dev/null || true
        fi

        # Vérification des logs de K3s
        local k3s_logs
        k3s_logs=$(ssh -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo journalctl -u k3s --no-pager -n 50" 2>/dev/null || echo "Impossible de récupérer les logs de K3s")
        log "INFO" "Derniers logs de K3s:"
        echo "${k3s_logs}"

        # Vérification des ports requis pour K3s
        log "INFO" "Vérification des ports requis pour K3s..."
        local k3s_ports=(6443 10250 10251 10252 8472 4789 51820 51821)

        for port in "${k3s_ports[@]}"; do
            if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "ss -tuln | grep :${port}" &>/dev/null; then
                log "WARNING" "Le port ${port} n'est pas ouvert sur le VPS, ce qui peut causer des problèmes avec K3s"
            fi
        done

        # Vérification des prérequis système pour K3s
        log "INFO" "Vérification des prérequis système pour K3s..."
        local system_info
        system_info=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "uname -a && cat /etc/os-release | grep PRETTY_NAME && free -h && df -h / && sysctl -a | grep -E 'vm.max_map_count|net.ipv4.ip_forward'" 2>/dev/null || echo "Impossible de récupérer les informations système")
        log "INFO" "Informations système:"
        echo "${system_info}"

        cleanup
        exit 1
    fi
}

# Fonction de déploiement de l'infrastructure de base
function deployer_infrastructure_base() {
    log "INFO" "Déploiement de l'infrastructure de base..."
    INSTALLATION_STEP="deploy_infra"

    # Sauvegarde de l'état actuel
    echo "${INSTALLATION_STEP}" > "${STATE_FILE}"

    # Attente que les CRDs de cert-manager soient prêts
    log "INFO" "Vérification que les CRDs de cert-manager sont prêts..."
    local max_attempts=30
    local attempt=0
    local crds_ready=false

    while [[ "${crds_ready}" == "false" && ${attempt} -lt ${max_attempts} ]]; do
        attempt=$((attempt + 1))
        log "INFO" "Tentative ${attempt}/${max_attempts} de vérification des CRDs de cert-manager..."

        if kubectl get crd | grep -q "clusterissuers.cert-manager.io"; then
            log "SUCCESS" "Les CRDs de cert-manager sont prêts"
            crds_ready=true
        else
            log "INFO" "Les CRDs de cert-manager ne sont pas encore prêts, attente de 10 secondes..."
            sleep 10
        fi
    done

    if [[ "${crds_ready}" == "false" ]]; then
        log "WARNING" "Les CRDs de cert-manager ne semblent pas être installés après ${max_attempts} tentatives"
        log "WARNING" "Le déploiement des ClusterIssuers pourrait échouer"
        log "INFO" "Tentative d'installation manuelle des CRDs de cert-manager..."

        # Tentative d'installation manuelle des CRDs
        if run_with_timeout "kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.crds.yaml" 300; then
            log "SUCCESS" "Installation manuelle des CRDs de cert-manager réussie"
        else
            log "WARNING" "Échec de l'installation manuelle des CRDs de cert-manager"
            log "WARNING" "Le déploiement des ClusterIssuers pourrait échouer"
        fi
    fi

    # Vérification de l'accès au cluster Kubernetes
    if ! kubectl cluster-info &>/dev/null; then
        log "ERROR" "Impossible d'accéder au cluster Kubernetes"
        log "ERROR" "Vérifiez votre configuration kubectl et le fichier kubeconfig"

        # Tentative de récupération du fichier kubeconfig
        local kubeconfig_dir="${HOME}/.kube"
        mkdir -p "${kubeconfig_dir}"

        if scp -P "${ansible_port}" "${ansible_user}@${ansible_host}:/home/${ansible_user}/.kube/config" "${kubeconfig_dir}/config.k3s" &>/dev/null; then
            log "INFO" "Fichier kubeconfig récupéré dans ${kubeconfig_dir}/config.k3s"
            log "INFO" "Tentative d'utilisation du nouveau fichier kubeconfig..."

            # Sauvegarde du KUBECONFIG actuel
            local old_kubeconfig="${KUBECONFIG}"
            export KUBECONFIG="${kubeconfig_dir}/config.k3s"

            if ! kubectl cluster-info &>/dev/null; then
                log "ERROR" "Impossible d'accéder au cluster Kubernetes même avec le nouveau fichier kubeconfig"
                # Restauration du KUBECONFIG
                if [[ -n "${old_kubeconfig}" ]]; then
                    export KUBECONFIG="${old_kubeconfig}"
                else
                    unset KUBECONFIG
                fi
                cleanup
                exit 1
            else
                log "SUCCESS" "Accès au cluster Kubernetes rétabli avec le nouveau fichier kubeconfig"
            fi
        else
            log "ERROR" "Impossible de récupérer le fichier kubeconfig"
            cleanup
            exit 1
        fi
    fi

    # Création du namespace pour l'infrastructure
    log "INFO" "Création du namespace lions-infrastructure..."
    LAST_COMMAND="kubectl create namespace lions-infrastructure --dry-run=client -o yaml | kubectl apply -f -"

    if ! run_with_timeout "kubectl create namespace lions-infrastructure --dry-run=client -o yaml | kubectl apply -f -"; then
        log "ERROR" "Échec de la création du namespace lions-infrastructure"

        # Vérification si le namespace existe déjà
        if kubectl get namespace lions-infrastructure &>/dev/null; then
            log "WARNING" "Le namespace lions-infrastructure existe déjà"
        else
            # Tentative de diagnostic
            log "INFO" "Tentative de diagnostic des problèmes..."
            kubectl get namespaces
            kubectl describe namespace lions-infrastructure 2>/dev/null || true

            cleanup
            exit 1
        fi
    fi

    # Déploiement des composants de base via kustomize
    log "INFO" "Déploiement des composants de base via kustomize..."
    LAST_COMMAND="kubectl apply -k \"${PROJECT_ROOT}/kubernetes/overlays/${environment}\""

    # Vérification préalable de la configuration kustomize
    log "INFO" "Vérification de la configuration kustomize..."
    if ! run_with_timeout "kubectl kustomize \"${PROJECT_ROOT}/kubernetes/overlays/${environment}\" > /dev/null"; then
        log "ERROR" "La configuration kustomize contient des erreurs"

        # Affichage des erreurs de kustomize
        kubectl kustomize "${PROJECT_ROOT}/kubernetes/overlays/${environment}" 2>&1 || true

        # Tentative de diagnostic
        log "INFO" "Tentative de diagnostic des problèmes de kustomize..."

        # Vérification des fichiers référencés
        log "INFO" "Vérification des fichiers référencés dans kustomization.yaml..."
        grep -r "resources:" "${PROJECT_ROOT}/kubernetes/overlays/${environment}" --include="*.yaml" -A 10

        cleanup
        exit 1
    fi

    # Application de la configuration kustomize
    if ! run_with_timeout "kubectl apply -k \"${PROJECT_ROOT}/kubernetes/overlays/${environment}\" --timeout=5m"; then
        log "ERROR" "Échec du déploiement des composants de base via kustomize"

        # Tentative de diagnostic
        log "INFO" "Tentative de diagnostic des problèmes..."

        # Vérification des erreurs courantes
        log "INFO" "Vérification des erreurs courantes..."

        # Vérification des ressources déployées
        kubectl get all -n "${environment}" 2>/dev/null || true

        # Vérification des événements
        kubectl get events --sort-by='.lastTimestamp' --field-selector type=Warning -n "${environment}" 2>/dev/null || true

        # Tentative de déploiement avec validation désactivée
        log "INFO" "Tentative de déploiement avec validation désactivée..."
        if ! run_with_timeout "kubectl apply -k \"${PROJECT_ROOT}/kubernetes/overlays/${environment}\" --validate=false --timeout=5m"; then
            log "ERROR" "Échec du déploiement même avec validation désactivée"
            cleanup
            exit 1
        else
            log "WARNING" "Déploiement réussi avec validation désactivée, mais des problèmes peuvent subsister"
        fi
    fi

    # Vérification du déploiement
    log "INFO" "Vérification du déploiement..."

    # Vérification des namespaces
    if ! kubectl get namespace "${environment}" &>/dev/null; then
        log "WARNING" "Le namespace ${environment} n'a pas été créé"
    else
        log "INFO" "Namespace ${environment} créé avec succès"
    fi

    # Vérification des quotas de ressources
    if ! kubectl get resourcequotas -n "${environment}" &>/dev/null; then
        log "WARNING" "Les quotas de ressources n'ont pas été créés dans le namespace ${environment}"
    else
        log "INFO" "Quotas de ressources créés avec succès dans le namespace ${environment}"
    fi

    # Vérification des politiques réseau
    if ! kubectl get networkpolicies -n "${environment}" &>/dev/null; then
        log "WARNING" "Les politiques réseau n'ont pas été créées dans le namespace ${environment}"
    else
        log "INFO" "Politiques réseau créées avec succès dans le namespace ${environment}"
    fi

    # Vérification et attente des StorageClasses
    log "INFO" "Vérification des StorageClasses..."
    local max_sc_attempts=30
    local sc_attempt=0
    local sc_ready=false

    while [[ "${sc_ready}" == "false" && ${sc_attempt} -lt ${max_sc_attempts} ]]; do
        sc_attempt=$((sc_attempt + 1))
        log "INFO" "Tentative ${sc_attempt}/${max_sc_attempts} de vérification des StorageClasses..."

        if kubectl get storageclass standard &>/dev/null; then
            log "SUCCESS" "StorageClass 'standard' est prête"
            sc_ready=true
        else
            log "INFO" "StorageClass 'standard' n'est pas encore prête, attente de 10 secondes..."
            sleep 10
        fi
    done

    if [[ "${sc_ready}" == "false" ]]; then
        log "WARNING" "StorageClass 'standard' n'est pas disponible après ${max_sc_attempts} tentatives"
        log "WARNING" "Les déploiements qui dépendent de cette StorageClass pourraient échouer"
    fi

    # Vérification et attente de Traefik
    # Note: Traefik peut être déployé de différentes manières (K3s, Helm, etc.) avec différentes étiquettes
    # Cette vérification prend en charge plusieurs méthodes de détection
    log "INFO" "Vérification de Traefik..."
    local max_traefik_attempts=30
    local traefik_attempt=0
    local traefik_ready=false

    while [[ "${traefik_ready}" == "false" && ${traefik_attempt} -lt ${max_traefik_attempts} ]]; do
        traefik_attempt=$((traefik_attempt + 1))
        log "INFO" "Tentative ${traefik_attempt}/${max_traefik_attempts} de vérification de Traefik..."

        # Vérification avec le label app=traefik (méthode standard)
        if kubectl get pods -n kube-system -l app=traefik -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q "Running"; then
            log "SUCCESS" "Traefik est en cours d'exécution (label app=traefik)"

            # Vérification que Traefik est prêt
            if kubectl get pods -n kube-system -l app=traefik -o jsonpath='{.items[*].status.containerStatuses[0].ready}' 2>/dev/null | grep -q "true"; then
                log "SUCCESS" "Traefik est prêt"
                traefik_ready=true
            else
                log "INFO" "Traefik est en cours d'exécution mais n'est pas encore prêt, attente de 10 secondes..."
                sleep 10
            fi
        # Vérification alternative avec le nom du pod commençant par "traefik-"
        elif kubectl get pods -n kube-system -o name 2>/dev/null | grep -q "pod/traefik-"; then
            log "SUCCESS" "Traefik est en cours d'exécution (pod commençant par traefik-)"

            # Récupération du nom du pod Traefik
            local traefik_pod_name=$(kubectl get pods -n kube-system -o name 2>/dev/null | grep "pod/traefik-" | head -n 1 | sed 's|pod/||')

            # Vérification que Traefik est prêt
            if kubectl get pod -n kube-system "${traefik_pod_name}" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null | grep -q "true"; then
                log "SUCCESS" "Traefik est prêt"
                traefik_ready=true
            else
                log "INFO" "Traefik est en cours d'exécution mais n'est pas encore prêt, attente de 10 secondes..."
                sleep 10
            fi
        else
            log "INFO" "Traefik n'est pas encore en cours d'exécution, attente de 10 secondes..."
            sleep 10
        fi
    done

    if [[ "${traefik_ready}" == "false" ]]; then
        log "WARNING" "Traefik n'est pas prêt après ${max_traefik_attempts} tentatives"
        log "INFO" "Tentative de déploiement manuel de Traefik..."

        # Vérification si Traefik est déjà installé mais pas en cours d'exécution
        if kubectl get deployment -n kube-system traefik &>/dev/null; then
            log "INFO" "Traefik est déjà installé mais n'est pas en cours d'exécution"
            log "INFO" "Tentative de redémarrage de Traefik..."
            kubectl rollout restart deployment traefik -n kube-system
        else
            log "INFO" "Traefik n'est pas installé, tentative d'installation via Helm..."

            # Ajout du dépôt Helm de Traefik
            if ! helm repo list | grep -q "traefik"; then
                helm repo add traefik https://helm.traefik.io/traefik
                helm repo update
            fi

            # Installation de Traefik via Helm
            helm upgrade --install traefik traefik/traefik \
                --namespace kube-system \
                --set ports.web.port=80 \
                --set ports.websecure.port=443 \
                --set service.type=LoadBalancer \
                --set ports.web.expose=true \
                --set ports.websecure.expose=true \
                --set hostNetwork=true \
                --set ingressClass.enabled=true \
                --set ingressClass.isDefaultClass=true
        fi

        # Attente que Traefik soit prêt après l'installation manuelle
        # Note: Traefik peut être déployé de différentes manières (K3s, Helm, etc.) avec différentes étiquettes
        # Cette vérification prend en charge plusieurs méthodes de détection
        log "INFO" "Attente que Traefik soit prêt après l'installation manuelle..."
        local manual_max_attempts=15
        local manual_attempt=0
        local manual_traefik_ready=false

        while [[ "${manual_traefik_ready}" == "false" && ${manual_attempt} -lt ${manual_max_attempts} ]]; do
            manual_attempt=$((manual_attempt + 1))
            log "INFO" "Tentative ${manual_attempt}/${manual_max_attempts} de vérification de Traefik après installation manuelle..."

            # Vérification avec le label app=traefik (méthode standard)
            if kubectl get pods -n kube-system -l app=traefik -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q "Running"; then
                log "SUCCESS" "Traefik est en cours d'exécution après installation manuelle (label app=traefik)"

                # Vérification que Traefik est prêt
                if kubectl get pods -n kube-system -l app=traefik -o jsonpath='{.items[*].status.containerStatuses[0].ready}' 2>/dev/null | grep -q "true"; then
                    log "SUCCESS" "Traefik est prêt après installation manuelle"
                    manual_traefik_ready=true
                else
                    log "INFO" "Traefik est en cours d'exécution mais n'est pas encore prêt, attente de 10 secondes..."
                    sleep 10
                fi
            # Vérification alternative avec le nom du pod commençant par "traefik-"
            elif kubectl get pods -n kube-system -o name 2>/dev/null | grep -q "pod/traefik-"; then
                log "SUCCESS" "Traefik est en cours d'exécution après installation manuelle (pod commençant par traefik-)"

                # Récupération du nom du pod Traefik
                local traefik_pod_name=$(kubectl get pods -n kube-system -o name 2>/dev/null | grep "pod/traefik-" | head -n 1 | sed 's|pod/||')

                # Vérification que Traefik est prêt
                if kubectl get pod -n kube-system "${traefik_pod_name}" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null | grep -q "true"; then
                    log "SUCCESS" "Traefik est prêt après installation manuelle"
                    manual_traefik_ready=true
                else
                    log "INFO" "Traefik est en cours d'exécution mais n'est pas encore prêt, attente de 10 secondes..."
                    sleep 10
                fi
            else
                log "INFO" "Traefik n'est pas encore en cours d'exécution après installation manuelle, attente de 10 secondes..."
                sleep 10
            fi
        done

        if [[ "${manual_traefik_ready}" == "false" ]]; then
            log "WARNING" "Traefik n'est pas prêt même après installation manuelle"
            log "WARNING" "Les services qui dépendent de Traefik pourraient ne pas être accessibles"
            log "WARNING" "Vérifiez l'installation de K3s et les logs"
        else
            log "SUCCESS" "Traefik a été installé manuellement avec succès"
            traefik_ready=true
        fi
    fi

    log "SUCCESS" "Déploiement de l'infrastructure de base terminé avec succès"
}

# Fonction de déploiement du monitoring
function deployer_monitoring() {
    log "INFO" "Déploiement du système de monitoring..."
    INSTALLATION_STEP="deploy_monitoring"

    # Sauvegarde de l'état actuel
    echo "${INSTALLATION_STEP}" > "${STATE_FILE}"

    # Vérification de l'accès au cluster Kubernetes
    if ! kubectl cluster-info &>/dev/null; then
        log "ERROR" "Impossible d'accéder au cluster Kubernetes"
        log "ERROR" "Vérifiez votre configuration kubectl et le fichier kubeconfig"
        cleanup
        exit 1
    fi

    # Création du namespace pour le monitoring
    log "INFO" "Création du namespace monitoring..."
    LAST_COMMAND="kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -"

    if ! run_with_timeout "kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -"; then
        log "ERROR" "Échec de la création du namespace monitoring"

        # Vérification si le namespace existe déjà
        if kubectl get namespace monitoring &>/dev/null; then
            log "WARNING" "Le namespace monitoring existe déjà"
        else
            # Tentative de diagnostic
            log "INFO" "Tentative de diagnostic des problèmes..."
            kubectl get namespaces
            kubectl describe namespace monitoring 2>/dev/null || true

            cleanup
            exit 1
        fi
    fi

    # Déploiement de Prometheus et Grafana via Helm
    log "INFO" "Déploiement de Prometheus et Grafana..."

    # Vérification de Helm
    if ! command_exists "helm"; then
        log "ERROR" "Helm n'est pas installé ou n'est pas dans le PATH"
        cleanup
        exit 1
    fi

    # Ajout du dépôt Helm de Prometheus
    LAST_COMMAND="helm repo add prometheus-community https://prometheus-community.github.io/helm-charts"
    if ! run_with_timeout "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts"; then
        log "ERROR" "Échec de l'ajout du dépôt Helm de Prometheus"

        # Tentative de diagnostic
        log "INFO" "Tentative de diagnostic des problèmes..."
        helm repo list

        cleanup
        exit 1
    fi

    LAST_COMMAND="helm repo update"
    if ! run_with_timeout "helm repo update"; then
        log "ERROR" "Échec de la mise à jour des dépôts Helm"
        cleanup
        exit 1
    fi

    # Création d'un fichier de valeurs temporaire pour Prometheus
    local values_file=$(mktemp)
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
EOF

    # Déploiement de Prometheus
    LAST_COMMAND="helm upgrade --install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --values ${values_file}"

    if ! run_with_timeout "helm upgrade --install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --values ${values_file}" 1800; then
        log "ERROR" "Échec du déploiement de Prometheus et Grafana"

        # Tentative de diagnostic
        log "INFO" "Tentative de diagnostic des problèmes..."

        # Vérification des pods
        kubectl get pods -n monitoring

        # Vérification des événements
        kubectl get events --sort-by='.lastTimestamp' --field-selector type=Warning -n monitoring

        # Vérification des logs des pods en erreur
        local failed_pods=$(kubectl get pods -n monitoring --field-selector status.phase!=Running,status.phase!=Succeeded -o jsonpath='{.items[*].metadata.name}')
        if [[ -n "${failed_pods}" ]]; then
            for pod in ${failed_pods}; do
                log "INFO" "Logs du pod ${pod}:"
                kubectl logs -n monitoring "${pod}" --tail=50 || true
            done
        fi

        # Vérification des ressources disponibles
        kubectl describe nodes

        # Nettoyage du fichier de valeurs temporaire
        rm -f "${values_file}"

        cleanup
        exit 1
    fi

    # Nettoyage du fichier de valeurs temporaire
    rm -f "${values_file}"

    # Vérification du déploiement
    log "INFO" "Vérification du déploiement du monitoring..."

    # Attente que les pods soient prêts
    log "INFO" "Attente que les pods de monitoring soient prêts..."
    local timeout=300  # 5 minutes
    local start_time
    start_time=$(date +%s)
    local all_pods_ready=false

    while [[ "${all_pods_ready}" == "false" ]]; do
        local current_time
        current_time=$(date +%s)
        local elapsed_time
        elapsed_time=$((current_time - start_time))

        if [[ ${elapsed_time} -gt ${timeout} ]]; then
            log "WARNING" "Timeout atteint en attendant que les pods de monitoring soient prêts"
            break
        fi

        local not_ready_pods=$(kubectl get pods -n monitoring --field-selector status.phase!=Running,status.phase!=Succeeded -o jsonpath='{.items[*].metadata.name}')
        if [[ -z "${not_ready_pods}" ]]; then
            all_pods_ready=true
            log "SUCCESS" "Tous les pods de monitoring sont prêts"
        else
            log "INFO" "En attente que les pods suivants soient prêts: ${not_ready_pods}"
            sleep 10
        fi
    done

    # Vérification de l'accès à Grafana
    log "INFO" "Vérification de l'accès à Grafana..."
    local grafana_service=$(kubectl get service -n monitoring prometheus-grafana -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)

    if [[ -n "${grafana_service}" ]]; then
        log "INFO" "Grafana est accessible à l'adresse: http://${ansible_host}:${grafana_service}"
        log "INFO" "Identifiant: admin"
        log "INFO" "Mot de passe: admin"
    else
        log "WARNING" "Impossible de déterminer l'adresse d'accès à Grafana"
    fi

    log "SUCCESS" "Déploiement du système de monitoring terminé avec succès"
}

# Fonction de vérification finale
function verifier_installation() {
    log "INFO" "Vérification de l'installation..."
    INSTALLATION_STEP="verify"

    # Vérification de l'accès au cluster Kubernetes
    if ! kubectl cluster-info &>/dev/null; then
        log "ERROR" "Impossible d'accéder au cluster Kubernetes"
        log "ERROR" "Vérifiez votre configuration kubectl et le fichier kubeconfig"
        cleanup
        exit 1
    fi

    # Vérification des nœuds
    log "INFO" "Vérification des nœuds Kubernetes..."
    LAST_COMMAND="kubectl get nodes -o wide"

    local nodes_output
    nodes_output=$(kubectl get nodes -o wide 2>&1)
    echo "${nodes_output}"

    # Vérification de l'état des nœuds
    if ! echo "${nodes_output}" | grep -q "Ready"; then
        log "WARNING" "Aucun nœud n'est en état 'Ready'"
        log "WARNING" "Vérifiez l'état des nœuds et les logs de K3s"
    else
        log "SUCCESS" "Au moins un nœud est en état 'Ready'"
    fi

    # Vérification des namespaces
    log "INFO" "Vérification des namespaces..."
    LAST_COMMAND="kubectl get namespaces"

    local namespaces_output
    namespaces_output=$(kubectl get namespaces 2>&1)
    echo "${namespaces_output}"

    # Vérification des namespaces requis
    local required_namespaces=("kube-system" "lions-infrastructure" "${environment}" "monitoring")
    local missing_namespaces=()

    for ns in "${required_namespaces[@]}"; do
        if ! echo "${namespaces_output}" | grep -q "${ns}"; then
            missing_namespaces+=("${ns}")
        fi
    done

    if [[ ${#missing_namespaces[@]} -gt 0 ]]; then
        log "WARNING" "Namespaces requis manquants: ${missing_namespaces[*]}"
    else
        log "SUCCESS" "Tous les namespaces requis sont présents"
    fi

    # Vérification des pods système
    log "INFO" "Vérification des pods système..."
    LAST_COMMAND="kubectl get pods -n kube-system"

    local system_pods_output
    system_pods_output=$(kubectl get pods -n kube-system 2>&1)
    echo "${system_pods_output}"

    # Vérification des pods système essentiels
    local essential_system_pods=("coredns" "metrics-server" "local-path-provisioner")
    local missing_system_pods=()

    for pod in "${essential_system_pods[@]}"; do
        if ! echo "${system_pods_output}" | grep -q "${pod}"; then
            missing_system_pods+=("${pod}")
        fi
    done

    if [[ ${#missing_system_pods[@]} -gt 0 ]]; then
        log "WARNING" "Pods système essentiels manquants: ${missing_system_pods[*]}"
    else
        log "SUCCESS" "Tous les pods système essentiels sont présents"
    fi

    # Vérification des pods d'infrastructure
    log "INFO" "Vérification des pods d'infrastructure..."
    LAST_COMMAND="kubectl get pods -n lions-infrastructure"

    local infra_pods_output
    infra_pods_output=$(kubectl get pods -n lions-infrastructure 2>&1)
    echo "${infra_pods_output}"

    # Vérification des pods de monitoring
    log "INFO" "Vérification des pods de monitoring..."
    LAST_COMMAND="kubectl get pods -n monitoring"

    local monitoring_pods_output
    monitoring_pods_output=$(kubectl get pods -n monitoring 2>&1)
    echo "${monitoring_pods_output}"

    # Vérification des pods de monitoring essentiels
    local essential_monitoring_pods=("prometheus" "grafana" "alertmanager")
    local missing_monitoring_pods=()

    for pod in "${essential_monitoring_pods[@]}"; do
        if ! echo "${monitoring_pods_output}" | grep -q "${pod}"; then
            missing_monitoring_pods+=("${pod}")
        fi
    done

    if [[ ${#missing_monitoring_pods[@]} -gt 0 ]]; then
        log "WARNING" "Pods de monitoring essentiels manquants: ${missing_monitoring_pods[*]}"
    else
        log "SUCCESS" "Tous les pods de monitoring essentiels sont présents"
    fi

    # Vérification des pods du Kubernetes Dashboard
    log "INFO" "Vérification des pods du Kubernetes Dashboard..."
    LAST_COMMAND="kubectl get pods -n kubernetes-dashboard"

    local dashboard_pods_output
    dashboard_pods_output=$(kubectl get pods -n kubernetes-dashboard 2>&1)
    echo "${dashboard_pods_output}"

    # Vérification des services
    log "INFO" "Vérification des services exposés..."

    # Vérification de Grafana
    local grafana_service
    grafana_service=$(kubectl get service -n monitoring prometheus-grafana -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    if [[ -n "${grafana_service}" ]]; then
        log "INFO" "Grafana est exposé sur le port ${grafana_service}"

        # Tentative de connexion à Grafana
        if command_exists "curl"; then
            local host_to_check="${ansible_host}"
            if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
                host_to_check="localhost"
            fi
            if curl -s -o /dev/null -w "%{http_code}" "http://${host_to_check}:${grafana_service}" | grep -q "200\|302"; then
                log "SUCCESS" "Grafana est accessible à l'adresse: http://${host_to_check}:${grafana_service}"
            else
                log "WARNING" "Grafana n'est pas accessible à l'adresse: http://${host_to_check}:${grafana_service}"
                log "WARNING" "Vérifiez les règles de pare-feu et l'état du service"
            fi
        fi
    else
        log "WARNING" "Service Grafana non trouvé ou non exposé"
    fi

    # Vérification du Kubernetes Dashboard
    local dashboard_service=$(kubectl get service -n kubernetes-dashboard kubernetes-dashboard-nodeport -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    if [[ -n "${dashboard_service}" ]]; then
        log "INFO" "Kubernetes Dashboard est exposé sur le port ${dashboard_service}"

        # Tentative de connexion au Dashboard
        if command_exists "curl"; then
            local host_to_check="${ansible_host}"
            if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
                host_to_check="localhost"
            fi
            if curl -s -k -o /dev/null -w "%{http_code}" "https://${host_to_check}:${dashboard_service}" | grep -q "200\|302\|401"; then
                log "SUCCESS" "Kubernetes Dashboard est accessible à l'adresse: https://${host_to_check}:${dashboard_service}"
            else
                log "WARNING" "Kubernetes Dashboard n'est pas accessible à l'adresse: https://${host_to_check}:${dashboard_service}"
                log "WARNING" "Vérifiez les règles de pare-feu et l'état du service"
            fi
        fi
    else
        log "WARNING" "Service Kubernetes Dashboard non trouvé ou non exposé"
    fi

    # Vérification de Traefik
    # Note: Traefik peut être déployé de différentes manières (K3s, Helm, etc.) avec différentes étiquettes
    # Cette vérification prend en charge plusieurs méthodes de détection
    log "INFO" "Vérification de Traefik..."
    local traefik_pods=""

    # Vérification avec le label app=traefik (méthode standard)
    traefik_pods=$(kubectl get pods -n kube-system -l app=traefik -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

    # Si aucun pod n'est trouvé avec le label app=traefik, essayer de trouver des pods commençant par "traefik-"
    if [[ -z "${traefik_pods}" ]]; then
        traefik_pods=$(kubectl get pods -n kube-system -o name 2>/dev/null | grep "pod/traefik-" | sed 's|pod/||')
    fi

    if [[ -n "${traefik_pods}" ]]; then
        log "SUCCESS" "Traefik est installé et en cours d'exécution"

        # Vérification des services Traefik
        local traefik_service=""

        # Essayer d'abord avec le service nommé "traefik"
        traefik_service=$(kubectl get service -n kube-system traefik -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}' 2>/dev/null)

        # Si aucun service n'est trouvé, essayer de trouver un service contenant "traefik" dans son nom
        if [[ -z "${traefik_service}" ]]; then
            local traefik_service_name=$(kubectl get services -n kube-system -o name 2>/dev/null | grep "service/traefik" | head -n 1 | sed 's|service/||')
            if [[ -n "${traefik_service_name}" ]]; then
                traefik_service=$(kubectl get service -n kube-system "${traefik_service_name}" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
            fi
        fi

        if [[ -n "${traefik_service}" ]]; then
            log "INFO" "Traefik est exposé sur le port ${traefik_service}"

            # Tentative de connexion à Traefik
            if command_exists "curl"; then
                local host_to_check="${ansible_host}"
                if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
                    host_to_check="localhost"
                fi
                if curl -s -o /dev/null -w "%{http_code}" "http://${host_to_check}:${traefik_service}" | grep -q "200\|302\|404"; then
                    log "SUCCESS" "Traefik est accessible à l'adresse: http://${host_to_check}:${traefik_service}"
                else
                    log "WARNING" "Traefik n'est pas accessible à l'adresse: http://${host_to_check}:${traefik_service}"
                    log "WARNING" "Vérifiez les règles de pare-feu et l'état du service"
                fi
            fi
        else
            log "WARNING" "Service Traefik non trouvé ou non exposé"
        fi
    else
        log "WARNING" "Traefik n'est pas installé ou n'est pas en cours d'exécution"
        log "WARNING" "Vérifiez l'installation de K3s et les logs"
    fi

    # Vérification des quotas de ressources
    log "INFO" "Vérification des quotas de ressources..."
    LAST_COMMAND="kubectl get resourcequotas --all-namespaces"

    local quotas_output=$(kubectl get resourcequotas --all-namespaces 2>&1)
    echo "${quotas_output}"

    if ! echo "${quotas_output}" | grep -q "compute-resources"; then
        log "WARNING" "Quotas de ressources non configurés"
        log "WARNING" "Vérifiez la configuration des quotas de ressources"
    else
        log "SUCCESS" "Quotas de ressources configurés correctement"
    fi

    # Vérification des politiques réseau
    log "INFO" "Vérification des politiques réseau..."
    LAST_COMMAND="kubectl get networkpolicies --all-namespaces"

    local netpol_output=$(kubectl get networkpolicies --all-namespaces 2>&1)
    echo "${netpol_output}"

    local essential_netpols=("default-network-policy" "allow-dns" "allow-monitoring")
    local missing_netpols=()

    for netpol in "${essential_netpols[@]}"; do
        if ! echo "${netpol_output}" | grep -q "${netpol}"; then
            missing_netpols+=("${netpol}")
        fi
    done

    if [[ ${#missing_netpols[@]} -gt 0 ]]; then
        log "WARNING" "Politiques réseau essentielles manquantes: ${missing_netpols[*]}"
    else
        log "SUCCESS" "Toutes les politiques réseau essentielles sont présentes"
    fi

    # Vérification des classes de stockage
    log "INFO" "Vérification des classes de stockage..."
    LAST_COMMAND="kubectl get storageclasses"

    local sc_output=$(kubectl get storageclasses 2>&1)
    echo "${sc_output}"

    if ! echo "${sc_output}" | grep -q "local-path"; then
        log "WARNING" "Classe de stockage local-path non trouvée"
        log "WARNING" "Vérifiez l'installation du provisioner de stockage local"
    else
        log "SUCCESS" "Classe de stockage local-path trouvée"
    fi

    # Vérification des CRDs
    log "INFO" "Vérification des définitions de ressources personnalisées (CRDs)..."
    LAST_COMMAND="kubectl get crds"

    local crd_output=$(kubectl get crds 2>&1)

    local essential_crds=("servicemonitors.monitoring.coreos.com" "prometheusrules.monitoring.coreos.com" "ingressroutes.traefik.containo.us")
    local missing_crds=()

    for crd in "${essential_crds[@]}"; do
        if ! echo "${crd_output}" | grep -q "${crd}"; then
            missing_crds+=("${crd}")
        fi
    done

    if [[ ${#missing_crds[@]} -gt 0 ]]; then
        log "WARNING" "CRDs essentielles manquantes: ${missing_crds[*]}"
    else
        log "SUCCESS" "Toutes les CRDs essentielles sont présentes"
    fi

    # Vérification des rôles RBAC
    log "INFO" "Vérification des rôles RBAC..."
    LAST_COMMAND="kubectl get clusterroles | grep lions"

    local rbac_output=$(kubectl get clusterroles | grep lions 2>&1)
    echo "${rbac_output}"

    local essential_roles=("lions-admin" "lions-developer" "lions-monitoring")
    local missing_roles=()

    for role in "${essential_roles[@]}"; do
        if ! echo "${rbac_output}" | grep -q "${role}"; then
            missing_roles+=("${role}")
        fi
    done

    if [[ ${#missing_roles[@]} -gt 0 ]]; then
        log "WARNING" "Rôles RBAC essentiels manquants: ${missing_roles[*]}"
    else
        log "SUCCESS" "Tous les rôles RBAC essentiels sont présents"
    fi

    # Vérification des volumes persistants
    log "INFO" "Vérification des volumes persistants..."
    LAST_COMMAND="kubectl get pv"

    local pv_output=$(kubectl get pv 2>&1)
    echo "${pv_output}"

    # Résumé de l'installation
    log "INFO" "Résumé de l'installation:"

    # Vérification des pods non prêts
    local not_ready_pods=$(kubectl get pods --all-namespaces --field-selector status.phase!=Running,status.phase!=Succeeded -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null)

    if [[ -n "${not_ready_pods}" ]]; then
        log "WARNING" "Pods non prêts:"
        echo "${not_ready_pods}"
    else
        log "SUCCESS" "Tous les pods sont prêts"
    fi

    # Vérification des pods en état d'erreur
    local error_pods=$(kubectl get pods --all-namespaces | grep -v "Running\|Completed\|NAME" 2>/dev/null)

    if [[ -n "${error_pods}" ]]; then
        log "WARNING" "Pods en état d'erreur:"
        echo "${error_pods}"

        # Récupération des logs des pods en erreur
        log "INFO" "Logs des pods en état d'erreur:"
        echo "${error_pods}" | while read -r line; do
            local ns=$(echo "${line}" | awk '{print $1}')
            local pod=$(echo "${line}" | awk '{print $2}')

            log "INFO" "Logs du pod ${ns}/${pod}:"
            kubectl logs -n "${ns}" "${pod}" --tail=20 2>/dev/null || echo "Impossible de récupérer les logs"
            echo "---"
        done
    else
        log "SUCCESS" "Aucun pod en état d'erreur"
    fi

    # Vérification des événements récents
    log "INFO" "Événements récents (dernières 5 minutes):"
    # Using a more compatible approach without --since flag
    kubectl get events --all-namespaces --sort-by='.lastTimestamp' --field-selector type=Warning | head -n 20

    # Vérification de la connectivité externe
    log "INFO" "Vérification de la connectivité externe..."

    # Vérification de l'accès aux services exposés
    local host_to_check="${ansible_host}"
    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        host_to_check="localhost"
    fi

    local services_to_check=(
        "http://${host_to_check}:30000|Grafana"
        "https://${host_to_check}:30001|Kubernetes Dashboard"
        "http://${host_to_check}:80|Traefik HTTP"
        "https://${host_to_check}:443|Traefik HTTPS"
    )

    for service_info in "${services_to_check[@]}"; do
        local service_url=$(echo "${service_info}" | cut -d'|' -f1)
        local service_name=$(echo "${service_info}" | cut -d'|' -f2)

        if command_exists "curl"; then
            local protocol=$(echo "${service_url}" | cut -d':' -f1)
            local curl_opts="-s -o /dev/null -w %{http_code} --connect-timeout 5"

            if [[ "${protocol}" == "https" ]]; then
                curl_opts="${curl_opts} -k"
            fi

            local status=$(curl ${curl_opts} "${service_url}" 2>/dev/null || echo "000")

            if [[ "${status}" =~ ^(200|301|302|401|403)$ ]]; then
                log "SUCCESS" "${service_name} est accessible à l'adresse ${service_url} (code ${status})"
            else
                log "WARNING" "${service_name} n'est pas accessible à l'adresse ${service_url} (code ${status})"
                log "WARNING" "Vérifiez les règles de pare-feu et l'état du service"
            fi
        else
            log "WARNING" "curl n'est pas installé, impossible de vérifier l'accès à ${service_name}"
        fi
    done

    log "SUCCESS" "Vérification de l'installation terminée avec succès"

    # Génération d'un rapport de vérification
    local report_file
    report_file="${LOG_DIR}/verification-report-$(date +%Y%m%d-%H%M%S).txt"

    {
        echo "=== RAPPORT DE VÉRIFICATION DE L'INFRASTRUCTURE LIONS ==="
        echo "Date: $(date)"
        echo "Environnement: ${environment}"
        echo ""

        echo "=== NŒUDS KUBERNETES ==="
        kubectl get nodes -o wide
        echo ""

        echo "=== NAMESPACES ==="
        kubectl get namespaces
        echo ""

        echo "=== PODS PAR NAMESPACE ==="
        kubectl get pods --all-namespaces
        echo ""

        echo "=== SERVICES EXPOSÉS ==="
        kubectl get services --all-namespaces -o wide | grep NodePort
        echo ""

        echo "=== INGRESS ==="
        kubectl get ingress --all-namespaces
        echo ""

        echo "=== ÉVÉNEMENTS RÉCENTS ==="
        kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -n 20
        echo ""

        echo "=== UTILISATION DES RESSOURCES ==="
        kubectl top nodes 2>/dev/null || echo "Metrics-server non disponible"
        echo ""
        kubectl top pods --all-namespaces 2>/dev/null || echo "Metrics-server non disponible"
        echo ""

        echo "=== ÉTAT DE SANTÉ GLOBAL ==="
        if [[ -n "${not_ready_pods}" ]] || [[ -n "${error_pods}" ]]; then
            echo "⚠️ Des problèmes ont été détectés, consultez les logs pour plus de détails."
        else
            echo "✅ L'infrastructure semble être en bon état."
        fi
        echo ""

        echo "=== INSTRUCTIONS D'ACCÈS ==="
        echo "Grafana: http://${ansible_host}:30000 (admin/admin)"
        echo "Kubernetes Dashboard: https://${ansible_host}:30001 (token requis)"
        echo ""

        echo "=== FIN DU RAPPORT ==="
    } > "${report_file}"

    log "INFO" "Rapport de vérification généré: ${report_file}"

    # Nettoyage du fichier de verrouillage et d'état
    # Suppression du fichier d'état (toujours local)
    rm -f "${STATE_FILE}"

    # Suppression du fichier de verrouillage
    if [[ -f "${LOCK_FILE}" ]]; then
        # Tentative de suppression sans sudo d'abord
        if ! rm -f "${LOCK_FILE}" 2>/dev/null; then
            log "WARNING" "Impossible de supprimer le fichier de verrouillage sans sudo, tentative avec sudo..."
            # Si ça échoue, essayer avec sudo
            if sudo rm -f "${LOCK_FILE}"; then
                log "SUCCESS" "Fichier de verrouillage supprimé avec succès (sudo)"
            else
                log "WARNING" "Impossible de supprimer le fichier de verrouillage, même avec sudo"
            fi
        fi
    fi
}

# Fonction pour tester la robustesse du script
function test_robustesse() {
    log "INFO" "Exécution des tests de robustesse..."

    # Sauvegarde de l'état actuel (optionnelle)
    backup_state "pre-test-robustesse" "true"

    # Test 1: Simulation d'une erreur de connexion SSH
    log "INFO" "Test 1: Simulation d'une erreur de connexion SSH..."
    local original_host="${ansible_host}"
    ansible_host="invalid.host.example.com"

    # Tentative d'exécution d'une commande qui nécessite SSH
    if ! check_vps_resources; then
        log "SUCCESS" "Test 1 réussi: L'erreur de connexion SSH a été correctement détectée et gérée"
    else
        log "ERROR" "Test 1 échoué: L'erreur de connexion SSH n'a pas été correctement détectée"
    fi

    # Restauration de l'hôte original
    ansible_host="${original_host}"

    # Test 2: Simulation d'une erreur de commande kubectl
    log "INFO" "Test 2: Simulation d'une erreur de commande kubectl..."
    local original_kubeconfig="${KUBECONFIG}"
    export KUBECONFIG="/tmp/invalid_kubeconfig_file"

    # Tentative d'exécution d'une commande kubectl
    if ! kubectl get nodes &>/dev/null; then
        log "SUCCESS" "Test 2 réussi: L'erreur de commande kubectl a été correctement détectée"
    else
        log "ERROR" "Test 2 échoué: L'erreur de commande kubectl n'a pas été correctement détectée"
    fi

    # Restauration du kubeconfig original
    export KUBECONFIG="${original_kubeconfig}"

    # Test 3: Simulation d'une erreur de timeout
    log "INFO" "Test 3: Simulation d'une erreur de timeout..."
    local original_timeout="${TIMEOUT_SECONDS}"
    TIMEOUT_SECONDS=1

    # Tentative d'exécution d'une commande avec un timeout très court
    if ! run_with_timeout "sleep 5" 1 "sleep"; then
        log "SUCCESS" "Test 3 réussi: L'erreur de timeout a été correctement détectée et gérée"
    else
        log "ERROR" "Test 3 échoué: L'erreur de timeout n'a pas été correctement détectée"
    fi

    # Restauration du timeout original
    TIMEOUT_SECONDS="${original_timeout}"

    # Test 4: Test du mécanisme de retry pour les erreurs réseau
    log "INFO" "Test 4: Test du mécanisme de retry pour les erreurs réseau..."

    # Création d'un script temporaire qui échoue les premières fois puis réussit
    local temp_script
    temp_script=$(mktemp)
    cat > "${temp_script}" << 'EOF'
#!/bin/bash
COUNTER_FILE="/tmp/retry_test_counter"

# Initialiser le compteur s'il n'existe pas
if [[ ! -f "${COUNTER_FILE}" ]]; then
    echo "0" > "${COUNTER_FILE}"
fi

# Lire le compteur actuel
COUNTER=$(cat "${COUNTER_FILE}")

# Incrémenter le compteur
COUNTER=$((COUNTER + 1))
echo "${COUNTER}" > "${COUNTER_FILE}"

# Échouer les 2 premières fois avec une erreur réseau
if [[ ${COUNTER} -le 2 ]]; then
    echo "Connection timed out"
    exit 1
fi

# Réussir la 3ème fois
echo "Opération réussie"
exit 0
EOF

    chmod +x "${temp_script}"

    # Réinitialiser le compteur
    echo "0" > "/tmp/retry_test_counter"

    # Exécuter la commande avec le mécanisme de retry
    if run_with_timeout "${temp_script}" 10 "network_test"; then
        # Vérifier que le compteur est à 3 (2 échecs + 1 succès)
        local final_counter
        final_counter=$(cat "/tmp/retry_test_counter")
        if [[ "${final_counter}" -eq 3 ]]; then
            log "SUCCESS" "Test 4 réussi: Le mécanisme de retry a fonctionné correctement (${final_counter} tentatives)"
        else
            log "ERROR" "Test 4 échoué: Le nombre de tentatives (${final_counter}) ne correspond pas à l'attendu (3)"
        fi
    else
        log "ERROR" "Test 4 échoué: La commande n'a pas réussi malgré le mécanisme de retry"
    fi

    # Nettoyage
    rm -f "${temp_script}" "/tmp/retry_test_counter"

    # Test 5: Simulation d'une erreur de ressources insuffisantes
    log "INFO" "Test 5: Simulation d'une erreur de ressources insuffisantes..."
    local original_required_space="${REQUIRED_SPACE_MB}"
    REQUIRED_SPACE_MB=999999999

    # Tentative de vérification des ressources
    if ! check_disk_space; then
        log "SUCCESS" "Test 4 réussi: L'erreur de ressources insuffisantes a été correctement détectée et gérée"
    else
        log "ERROR" "Test 4 échoué: L'erreur de ressources insuffisantes n'a pas été correctement détectée"
    fi

    # Restauration de l'espace requis original
    REQUIRED_SPACE_MB="${original_required_space}"

    # Test 5: Test de la fonction de restauration
    log "INFO" "Test 5: Test de la fonction de restauration..."

    # Tentative de restauration de l'état sauvegardé
    if restore_state; then
        log "SUCCESS" "Test 5 réussi: La restauration de l'état a fonctionné correctement"
    else
        log "WARNING" "Test 5 échoué: La restauration de l'état n'a pas fonctionné correctement"
    fi

    log "INFO" "Tests de robustesse terminés"
    return 0
}

# Parsing des arguments
environment="${LIONS_ENV:-${DEFAULT_ENV}}"
inventory_file="inventories/${environment}/hosts.yml"
skip_init="${LIONS_SKIP_INIT:-false}"
debug_mode="${LIONS_DEBUG_MODE:-false}"
test_mode="${LIONS_TEST_MODE:-false}"

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

# Détection du système d'exploitation pour le formatage des chemins
os_name=""
os_name=$(uname -s)
if [[ "${os_name}" == *"MINGW"* || "${os_name}" == *"MSYS"* || "${os_name}" == *"CYGWIN"* || "${os_name}" == *"Windows"* ]]; then
    log "DEBUG" "Système Windows détecté, adaptation des chemins..."

    # Convertir les chemins de fichiers pour Windows si nécessaire
    if [[ "${inventory_file}" == *"/"* && "${inventory_file}" != *"\\"* ]]; then
        # Remplacer les slashes par des backslashes pour Windows
        inventory_file_win=$(echo "${inventory_file}" | tr '/' '\\')
        log "DEBUG" "Chemin d'inventaire adapté pour Windows: ${inventory_file_win}"

        # Vérifier si le chemin converti existe
        if [[ -f "${inventory_file_win}" ]]; then
            log "DEBUG" "Utilisation du chemin Windows pour l'inventaire"
            inventory_file="${inventory_file_win}"
        else
            log "DEBUG" "Le chemin Windows n'existe pas, conservation du chemin original"
        fi
    fi
fi

# Affichage du titre
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
    echo -e "╚═══════════════════════════════════════════════════════════════════╝${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}     Infrastructure de Déploiement Automatisé - v2.0.0${COLOR_RESET}"
    echo -e "${COLOR_CYAN}  ════════════════════════════════════════════════════════${COLOR_RESET}\n"

# Affichage des paramètres
log "INFO" "Environnement: ${environment}"
log "INFO" "Fichier d'inventaire: ${inventory_file}"
log "INFO" "Ignorer l'initialisation: ${skip_init}"
log "INFO" "Mode debug: ${debug_mode}"
log "INFO" "Mode test: ${test_mode}"
log "INFO" "Fichier de log: ${LOG_FILE}"

# La vérification du fichier de verrouillage est déjà effectuée dans la fonction verifier_prerequis
# Ne pas créer de fichier de verrouillage ici pour éviter les conflits

# Exécution des tests de robustesse si demandé
if [[ "${test_mode}" == "true" ]]; then
    log "INFO" "Exécution en mode test..."

    # Vérification des prérequis
    log "INFO" "Vérification des prérequis..."
    verifier_prerequis

    # Extraction des informations d'inventaire
    extraire_informations_inventaire

    # Exécution des tests de robustesse
    test_robustesse

    log "INFO" "Mode test terminé"

    # Suppression du fichier de verrouillage
    if [[ -f "${LOCK_FILE}" ]]; then
        # Tentative de suppression sans sudo d'abord
        if ! rm -f "${LOCK_FILE}" 2>/dev/null; then
            log "WARNING" "Impossible de supprimer le fichier de verrouillage sans sudo, tentative avec sudo..."
            # Si ça échoue, essayer avec sudo
            if sudo rm -f "${LOCK_FILE}"; then
                log "SUCCESS" "Fichier de verrouillage supprimé avec succès (sudo)"
            else
                log "WARNING" "Impossible de supprimer le fichier de verrouillage, même avec sudo"
            fi
        fi
    fi

    exit 0
fi

# Exécution des étapes d'installation
if ! verifier_prerequis; then
    log "ERROR" "Échec de la vérification des prérequis"
    cleanup
    exit 1
fi

# Extraction des informations d'inventaire
if ! extraire_informations_inventaire; then
    log "ERROR" "Échec de l'extraction des informations d'inventaire"
    cleanup
    exit 1
fi

# Sauvegarde de l'état initial (optionnelle)
backup_state "pre-installation" "true"

# Initialisation du VPS si nécessaire
if [[ "${skip_init}" == "false" ]]; then
    if ! initialiser_vps; then
        log "ERROR" "Échec de l'initialisation du VPS"
        log "INFO" "Vous pouvez réessayer avec l'option --skip-init si le VPS a déjà été initialisé"
        cleanup
        exit 1
    fi
else
    log "INFO" "Initialisation du VPS ignorée"
fi

# Installation de K3s
if ! installer_k3s; then
    log "ERROR" "Échec de l'installation de K3s"
    log "INFO" "Tentative de diagnostic et réparation automatique..."

    # Demander à l'utilisateur s'il souhaite tenter une réparation automatique
    local repair_response
    read -p "Souhaitez-vous tenter une réparation automatique de K3s? (o/N): " repair_response

    if [[ "${repair_response}" =~ ^[oO]$ ]]; then
        if check_fix_k3s; then
            log "SUCCESS" "K3s a été réparé avec succès"
        else
            log "ERROR" "Impossible de réparer K3s automatiquement"
            log "INFO" "Vérifiez les logs pour plus d'informations"
            cleanup
            exit 1
        fi
    else
        log "INFO" "Réparation automatique ignorée"
        log "INFO" "Vérifiez les logs pour plus d'informations"
        cleanup
        exit 1
    fi
fi

# Sauvegarde de l'état après installation de K3s (optionnelle)
backup_state "post-k3s" "true"

# Déploiement de l'infrastructure de base
if ! deployer_infrastructure_base; then
    log "ERROR" "Échec du déploiement de l'infrastructure de base"
    log "INFO" "Vérifiez les logs pour plus d'informations"
    cleanup
    exit 1
fi

# Sauvegarde de l'état après déploiement de l'infrastructure (optionnelle)
backup_state "post-infrastructure" "true"

# Déploiement du monitoring
if ! deployer_monitoring; then
    log "ERROR" "Échec du déploiement du monitoring"
    log "WARNING" "Le monitoring n'est pas essentiel, l'installation peut continuer"
fi

# Sauvegarde de l'état après déploiement du monitoring (optionnelle)
backup_state "post-monitoring" "true"

# Déploiement des services d'infrastructure (PostgreSQL, PgAdmin, Gitea, Keycloak)
log "INFO" "Déploiement des services d'infrastructure..."
INSTALLATION_STEP="deploy_services"

# Sauvegarde de l'état actuel
echo "${INSTALLATION_STEP}" > "${STATE_FILE}"

# Construction de la commande Ansible
# Utilisation de chemins absolus pour éviter les problèmes de résolution de chemin
playbook_path="${ANSIBLE_DIR}/playbooks/deploy-infrastructure-services.yml"

# Vérification que le fichier existe
if [[ ! -f "${playbook_path}" ]]; then
    log "ERROR" "Fichier de playbook non trouvé: ${playbook_path}"
    log "ERROR" "Vérifiez que le chemin est correct et que le fichier existe"
    log "WARNING" "Déploiement des services d'infrastructure ignoré"
else
    # Détection du système d'exploitation pour le formatage des chemins
    os_name=""
    os_name=$(uname -s)
    if [[ "${os_name}" == *"MINGW"* || "${os_name}" == *"MSYS"* || "${os_name}" == *"CYGWIN"* || "${os_name}" == *"Windows"* ]]; then
        # Windows: convertir les chemins Unix en chemins Windows
        log "DEBUG" "Système Windows détecté, conversion des chemins"

        # Vérifier si le chemin contient déjà des backslashes
        if [[ "${playbook_path}" != *"\\"* ]]; then
            # Remplacer les slashes par des backslashes pour Windows
            playbook_path=$(echo "${playbook_path}" | tr '/' '\\')
            log "DEBUG" "Chemin de playbook converti: ${playbook_path}"
        fi

        # Vérifier si le chemin existe après conversion
        if [[ ! -f "${playbook_path}" ]]; then
            log "WARNING" "Le chemin de playbook converti n'existe pas: ${playbook_path}"
            log "DEBUG" "Tentative d'utilisation du chemin original"
            playbook_path="${ANSIBLE_DIR}/playbooks/deploy-infrastructure-services.yml"
        fi
    fi

    ansible_cmd="ansible-playbook -i \"${ANSIBLE_DIR}/${inventory_file}\" \"${playbook_path}\" --extra-vars \"target_env=${environment}\" --ask-become-pass"

    if [[ "${debug_mode}" == "true" ]]; then
        ansible_cmd="${ansible_cmd} -vvv"
    fi

    log "INFO" "Exécution de la commande: ${ansible_cmd}"
    LAST_COMMAND="${ansible_cmd}"

    # Exécution directe de la commande avec eval
    if eval "${ansible_cmd}"; then
        log "SUCCESS" "Déploiement des services d'infrastructure terminé avec succès"

        # Attente que les pods soient prêts
        log "INFO" "Vérification de l'état des pods après déploiement..."

        # Liste des namespaces à vérifier
        namespaces_to_check=(
            "postgres-${environment}"
            "pgadmin-${environment}"
            "gitea-${environment}"
            "keycloak-${environment}"
            "ollama-${environment}"
        )

        for ns in "${namespaces_to_check[@]}"; do
            if kubectl get namespace "${ns}" &>/dev/null; then
                log "INFO" "Attente que les pods dans le namespace ${ns} soient prêts..."
                local timeout=300  # 5 minutes
                local start_time
                start_time=$(date +%s)
                local all_pods_ready=false

                while [[ "${all_pods_ready}" == "false" ]]; do
                    local current_time
                    current_time=$(date +%s)
                    local elapsed_time
                    elapsed_time=$((current_time - start_time))

                    if [[ ${elapsed_time} -gt ${timeout} ]]; then
                        log "WARNING" "Timeout atteint en attendant que les pods dans ${ns} soient prêts"
                        break
                    fi

                    local not_ready_pods=$(kubectl get pods -n "${ns}" --field-selector status.phase!=Running,status.phase!=Succeeded -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
                    if [[ -z "${not_ready_pods}" ]]; then
                        all_pods_ready=true
                        log "SUCCESS" "Tous les pods dans ${ns} sont prêts"
                    else
                        log "INFO" "En attente que les pods suivants dans ${ns} soient prêts: ${not_ready_pods}"
                        sleep 10
                    fi
                done
            else
                log "INFO" "Namespace ${ns} non trouvé, ignoré"
            fi
        done

        # Vérification des services
        log "INFO" "Vérification des services déployés..."
        for ns in "${namespaces_to_check[@]}"; do
            if kubectl get namespace "${ns}" &>/dev/null; then
                local services=$(kubectl get services -n "${ns}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
                if [[ -n "${services}" ]]; then
                    log "INFO" "Services dans ${ns}: ${services}"
                else
                    log "WARNING" "Aucun service trouvé dans ${ns}"
                fi
            fi
        done

        log "SUCCESS" "Vérification des services terminée"
    else
        log "WARNING" "Échec du déploiement des services d'infrastructure"
        log "WARNING" "Vous pouvez les déployer manuellement plus tard avec la commande:"
        log "WARNING" "ansible-playbook ${ANSIBLE_DIR}/playbooks/deploy-infrastructure-services.yml --extra-vars \"target_env=${environment}\" --ask-become-pass"
    fi
fi

# Sauvegarde de l'état après déploiement des services (optionnelle)
backup_state "post-services" "true"

# Vérification finale de l'installation
if ! verifier_installation; then
    log "WARNING" "La vérification finale de l'installation a échoué"
    log "WARNING" "Certains composants peuvent ne pas fonctionner correctement"
    log "INFO" "Consultez les logs pour plus d'informations et effectuez les corrections nécessaires"
fi

# Affichage du résumé
echo -e "\n${COLOR_GREEN}${COLOR_BOLD}===========================================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}${COLOR_BOLD}  Installation de l'infrastructure LIONS terminée avec succès !${COLOR_RESET}"
echo -e "${COLOR_GREEN}${COLOR_BOLD}===========================================================${COLOR_RESET}\n"

log "INFO" "Pour accéder à Grafana, utilisez l'URL: http://${ansible_host}:30000"
log "INFO" "Identifiant: admin"
log "INFO" "Mot de passe: admin"

log "INFO" "Pour accéder au Kubernetes Dashboard, utilisez l'URL: https://${ansible_host}:30001"
log "INFO" "Utilisez le token permanent affiché dans les logs d'installation pour vous connecter"
log "INFO" "Vous pouvez également récupérer le token permanent avec: kubectl get secret dashboard-admin-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 --decode"
log "INFO" "Ce token est permanent et ne nécessite pas d'être régénéré à chaque connexion"

log "INFO" "Pour déployer des applications, utilisez le script deploy.sh"

# Génération d'un rapport final
report_file="${LOG_DIR}/installation-report-$(date +%Y%m%d-%H%M%S).txt"

{
    echo "=== RAPPORT D'INSTALLATION DE L'INFRASTRUCTURE LIONS ==="
    echo "Date: $(date)"
    echo "Environnement: ${environment}"
    echo ""

    echo "=== RÉSUMÉ DE L'INSTALLATION ==="
    echo "✅ Initialisation du VPS: Réussie"
    echo "✅ Installation de K3s: Réussie"
    echo "✅ Déploiement de l'infrastructure de base: Réussie"
    echo "✅ Déploiement du monitoring: Réussie"
    echo "✅ Vérification de l'installation: Réussie"
    echo ""

    echo "=== INFORMATIONS D'ACCÈS ==="
    access_host="${ansible_host}"
    if [[ "${IS_LOCAL_EXECUTION}" == "true" ]]; then
        access_host="localhost"
    fi
    echo "Grafana: http://${access_host}:30000 (admin/admin)"
    echo "Kubernetes Dashboard: https://${access_host}:30001 (token requis)"
    echo ""

    echo "=== PROCHAINES ÉTAPES ==="
    echo "1. Changer le mot de passe par défaut de Grafana"
    echo "2. Configurer les alertes dans Prometheus/Alertmanager"
    echo "3. Déployer vos applications avec le script deploy.sh"
    echo ""

    echo "=== FIN DU RAPPORT ==="
} > "${report_file}"

log "INFO" "Rapport d'installation généré: ${report_file}"

# Suppression du fichier de verrouillage
if [[ -f "${LOCK_FILE}" ]]; then
    # Tentative de suppression sans sudo d'abord
    if ! rm -f "${LOCK_FILE}" 2>/dev/null; then
        log "WARNING" "Impossible de supprimer le fichier de verrouillage sans sudo, tentative avec sudo..."
        # Si ça échoue, essayer avec sudo
        if sudo rm -f "${LOCK_FILE}"; then
            log "SUCCESS" "Fichier de verrouillage supprimé avec succès (sudo)"
        else
            log "WARNING" "Impossible de supprimer le fichier de verrouillage, même avec sudo"
        fi
    fi
fi

exit 0
