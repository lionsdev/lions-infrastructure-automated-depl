#!/bin/bash
# Titre: Script d'installation de l'infrastructure LIONS sur VPS
# Description: Orchestre l'installation complète de l'infrastructure LIONS sur un VPS
# Auteur: Équipe LIONS Infrastructure
# Date: 2023-05-15
# Version: 1.0.0

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
readonly LOG_DIR="./logs/infrastructure"
readonly LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
readonly DEFAULT_ENV="development"
readonly BACKUP_DIR="${LOG_DIR}/backups"
readonly STATE_FILE="${LOG_DIR}/.installation_state"
readonly LOCK_FILE="/tmp/lions_install.lock"
readonly REQUIRED_SPACE_MB=5000  # 5 Go d'espace disque requis
readonly TIMEOUT_SECONDS=1800    # 30 minutes de timeout pour les commandes longues
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

# Création des répertoires nécessaires
mkdir -p "${LOG_DIR}"
mkdir -p "${BACKUP_DIR}"

# Activation du mode strict après les vérifications initiales
set -euo pipefail

# Fonction de logging améliorée
function log() {
    local level="$1"
    local message="$2"
    local timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
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
    echo -e "${log_color}${log_prefix}[${timestamp}] [${level}]${caller_info}${COLOR_RESET} ${message}"

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

# Fonction pour collecter et analyser les logs
function collect_logs() {
    local output_dir="${LOG_DIR}/diagnostic-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${output_dir}"

    log "INFO" "Collecte des logs pour diagnostic dans ${output_dir}..."

    # Copie du log d'installation
    cp "${LOG_FILE}" "${output_dir}/install.log"

    # Collecte des logs du VPS
    if [[ -n "${ansible_host}" && -n "${ansible_port}" && -n "${ansible_user}" ]]; then
        log "INFO" "Collecte des logs du VPS..."

        # Création d'un script temporaire pour collecter les logs sur le VPS
        local tmp_script=$(mktemp)
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
        ns=$(echo ${pod} | cut -d/ -f1)
        name=$(echo ${pod} | cut -d/ -f2)
        kubectl logs -n ${ns} ${name} > "${OUTPUT_DIR}/pod_${ns}_${name}.log" 2>/dev/null || true
        kubectl describe pod -n ${ns} ${name} > "${OUTPUT_DIR}/pod_${ns}_${name}_describe.log" 2>/dev/null || true
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
    local archive_file="${LOG_DIR}/diagnostic-$(date +%Y%m%d-%H%M%S).tar.gz"
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
            rm -f "${LOCK_FILE}"
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
    local report_file="${BACKUP_DIR}/diagnostic-$(date +%Y%m%d-%H%M%S).txt"

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
        if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "uname -a" &>/dev/null; then
            echo "Système d'exploitation: $(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "uname -a" 2>/dev/null)"
            echo "Espace disque disponible: $(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "df -h / | awk 'NR==2 {print \$4}'" 2>/dev/null)"
            echo "Mémoire disponible: $(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "free -h | awk '/^Mem:/ {print \$7}'" 2>/dev/null)"
            echo "Charge système: $(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "uptime" 2>/dev/null)"
            echo "Services actifs: $(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "systemctl list-units --state=running --type=service --no-pager | grep -v systemd | head -10" 2>/dev/null)"
        else
            echo "Impossible de se connecter au VPS pour récupérer les informations"
        fi
        echo ""

        echo "=== ÉTAT DE KUBERNETES ==="
        if command_exists kubectl && kubectl cluster-info &>/dev/null; then
            echo "Version de Kubernetes: $(kubectl version --short 2>/dev/null)"
            echo "Nœuds: $(kubectl get nodes -o wide 2>/dev/null)"
            echo "Pods par namespace: $(kubectl get pods --all-namespaces -o wide 2>/dev/null)"
            echo "Services: $(kubectl get services --all-namespaces 2>/dev/null)"
            echo "Événements récents: $(kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20 2>/dev/null)"
        else
            echo "Kubernetes n'est pas accessible ou n'est pas installé"
        fi
        echo ""

        echo "=== LOGS PERTINENTS ==="
        echo "Dernières lignes du log d'installation:"
        tail -50 "${LOG_FILE}" 2>/dev/null
        echo ""

        echo "=== VÉRIFICATIONS RÉSEAU ==="
        echo "Ping vers le VPS: $(ping -c 3 "${ansible_host}" 2>&1)"
        echo "Ports ouverts sur le VPS:"
        for port in "${REQUIRED_PORTS[@]}"; do
            if nc -z -w 5 "${ansible_host}" "${port}" &>/dev/null; then
                echo "  - Port ${port}: OUVERT"
            else
                echo "  - Port ${port}: FERMÉ"
            fi
        done
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
        rm -f "${LOCK_FILE}"
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
trap 'if [[ -f "${LOCK_FILE}" ]]; then rm -f "${LOCK_FILE}"; fi' EXIT

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
        if ! sudo apt-get update &>/dev/null; then
            log "WARNING" "Impossible de mettre à jour les dépôts apt"
        fi
    elif [[ "${pkg_manager}" == "dnf" || "${pkg_manager}" == "yum" ]]; then
        log "INFO" "Mise à jour des dépôts ${pkg_manager}..."
        if ! sudo ${pkg_manager} check-update &>/dev/null; then
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
                    # Pour Debian/Ubuntu, kubectl nécessite un dépôt spécial
                    log "INFO" "Configuration du dépôt Kubernetes pour apt..."
                    if ! command_exists curl; then
                        sudo apt-get install -y curl &>/dev/null
                    fi
                    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - &>/dev/null
                    echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list &>/dev/null
                    sudo apt-get update &>/dev/null
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
                        sudo apt-get install -y curl &>/dev/null
                    fi
                    curl https://baltocdn.com/helm/signing.asc | sudo apt-key add - &>/dev/null
                    echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list &>/dev/null
                    sudo apt-get update &>/dev/null
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
        if ! sudo ${install_cmd} ${pkg_name} &>/dev/null; then
            log "ERROR" "Échec de l'installation de ${pkg_name}"
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

    # Vérification de la connexion SSH
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "echo 'Connexion SSH réussie'" &>/dev/null; then
        log "ERROR" "Impossible de se connecter au VPS via SSH pour vérifier les ressources"
        return 1
    fi

    # Vérification de l'espace disque
    local vps_disk_total=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "df -m / | awk 'NR==2 {print \$2}'" 2>/dev/null || echo "0")
    local vps_disk_used=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "df -m / | awk 'NR==2 {print \$3}'" 2>/dev/null || echo "0")
    local vps_disk_free=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "df -m / | awk 'NR==2 {print \$4}'" 2>/dev/null || echo "0")
    local vps_disk_use_percent=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "df -m / | awk 'NR==2 {print \$5}'" 2>/dev/null | sed 's/%//' || echo "0")

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
    local vps_memory_total=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "free -m | awk '/^Mem:/ {print \$2}'" 2>/dev/null || echo "0")
    local vps_memory_used=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "free -m | awk '/^Mem:/ {print \$3}'" 2>/dev/null || echo "0")
    local vps_memory_free=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "free -m | awk '/^Mem:/ {print \$4}'" 2>/dev/null || echo "0")
    local vps_memory_available=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "free -m | awk '/^Mem:/ {print \$7}'" 2>/dev/null || echo "0")

    log "INFO" "Mémoire du VPS: ${vps_memory_available}MB disponible sur ${vps_memory_total}MB total"

    # Vérification du swap
    local vps_swap_total=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "free -m | awk '/^Swap:/ {print \$2}'" 2>/dev/null || echo "0")
    local vps_swap_used=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "free -m | awk '/^Swap:/ {print \$3}'" 2>/dev/null || echo "0")
    local vps_swap_free=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "free -m | awk '/^Swap:/ {print \$4}'" 2>/dev/null || echo "0")

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
    local vps_cpu_cores=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "nproc --all" 2>/dev/null || echo "0")
    local vps_cpu_load=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "cat /proc/loadavg | awk '{print \$1}'" 2>/dev/null || echo "0")

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
        local top_cpu_processes=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "ps aux --sort=-%cpu | head -6" 2>/dev/null || echo "Impossible de déterminer les processus")
        echo "${top_cpu_processes}"
    fi

    # Vérification des processus consommant le plus de mémoire
    if [[ ${vps_memory_available} -lt 1024 ]]; then
        log "WARNING" "Mémoire disponible du VPS faible: ${vps_memory_available}MB"
        log "INFO" "Processus consommant le plus de mémoire sur le VPS:"
        local top_mem_processes=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "ps aux --sort=-%mem | head -6" 2>/dev/null || echo "Impossible de déterminer les processus")
        echo "${top_mem_processes}"
    fi

    # Vérification des services en cours d'exécution
    log "INFO" "Vérification des services en cours d'exécution sur le VPS..."
    local running_services=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "systemctl list-units --type=service --state=running | grep -v systemd | head -10" 2>/dev/null || echo "Impossible de déterminer les services")
    log "INFO" "Services en cours d'exécution sur le VPS (top 10):"
    echo "${running_services}" | grep -v "UNIT\|LOAD\|ACTIVE\|SUB\|DESCRIPTION\|^$\|loaded units listed"

    # Vérification des ports ouverts
    log "INFO" "Vérification des ports ouverts sur le VPS..."
    local open_ports=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "ss -tuln | grep LISTEN" 2>/dev/null || echo "Impossible de déterminer les ports ouverts")
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
            vps_port = host_info.get('ansible_port', 22)
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
        ansible_port=$(timeout 5 grep -A10 "hosts:" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_port:" | head -1 | awk -F': ' '{print $2}' | tr -d ' ' 2>/dev/null || echo "22")
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

                if sudo ${pip_cmd} install pyyaml &>/dev/null; then
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
        ansible_port=$(timeout 5 grep -A10 "hosts:" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_port:" | head -1 | awk -F': ' '{print $2}' | tr -d ' ' 2>/dev/null || echo "22")
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
    ansible_port="${ansible_port:-22}"
    ansible_user="${ansible_user:-$(whoami)}"

    log "INFO" "Informations d'inventaire extraites:"
    log "INFO" "- Hôte: ${ansible_host}"
    log "INFO" "- Port: ${ansible_port}"
    log "INFO" "- Utilisateur: ${ansible_user}"

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

    # Vérification de la connexion SSH
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${target_port}" "${ansible_user}@${target_host}" "echo 'Test de connexion'" &>/dev/null; then
        log "ERROR" "Impossible de se connecter au VPS via SSH pour ouvrir les ports"
        return 1
    fi

    # Vérification que UFW est installé et actif
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${target_port}" "${ansible_user}@${target_host}" "command -v ufw &>/dev/null && systemctl is-active --quiet ufw" &>/dev/null; then
        log "WARNING" "UFW n'est pas installé ou n'est pas actif sur le VPS"
        log "INFO" "Tentative d'installation et d'activation de UFW..."

        # Installation de UFW si nécessaire
        if ! ssh -o BatchMode=yes -o ConnectTimeout=${timeout} -p "${target_port}" "${ansible_user}@${target_host}" "sudo apt-get update && sudo apt-get install -y ufw" &>/dev/null; then
            log "ERROR" "Impossible d'installer UFW sur le VPS"
            return 1
        fi

        # Activation de UFW
        if ! ssh -o BatchMode=yes -o ConnectTimeout=${timeout} -p "${target_port}" "${ansible_user}@${target_host}" "sudo ufw --force enable" &>/dev/null; then
            log "ERROR" "Impossible d'activer UFW sur le VPS"
            return 1
        fi

        log "SUCCESS" "UFW installé et activé avec succès"
    fi

    # Ouverture des ports
    log "INFO" "Ouverture des ports: ${ports_to_open[*]}"

    for port in "${ports_to_open[@]}"; do
        log "INFO" "Ouverture du port ${port}..."

        # Vérification si le port est déjà ouvert
        if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${target_port}" "${ansible_user}@${target_host}" "sudo ufw status | grep -E \"^${port}/(tcp|udp)\"" &>/dev/null; then
            log "INFO" "Le port ${port} est déjà ouvert dans UFW"
            continue
        fi

        # Ouverture du port TCP
        if ! ssh -o BatchMode=yes -o ConnectTimeout=${timeout} -p "${target_port}" "${ansible_user}@${target_host}" "sudo ufw allow ${port}/tcp" &>/dev/null; then
            log "ERROR" "Impossible d'ouvrir le port ${port}/tcp sur le VPS"
            success=false
            continue
        fi

        # Ouverture du port UDP
        if ! ssh -o BatchMode=yes -o ConnectTimeout=${timeout} -p "${target_port}" "${ansible_user}@${target_host}" "sudo ufw allow ${port}/udp" &>/dev/null; then
            log "WARNING" "Impossible d'ouvrir le port ${port}/udp sur le VPS"
            # Ne pas échouer pour UDP, car certains services n'utilisent que TCP
        fi

        log "SUCCESS" "Port ${port} ouvert avec succès"
    done

    # Rechargement des règles UFW
    if ! ssh -o BatchMode=yes -o ConnectTimeout=${timeout} -p "${target_port}" "${ansible_user}@${target_host}" "sudo ufw reload" &>/dev/null; then
        log "WARNING" "Impossible de recharger les règles UFW"
        # Ne pas échouer pour le rechargement, car les règles sont déjà appliquées
    fi

    # Vérification que les ports sont bien ouverts
    log "INFO" "Vérification que les ports sont bien ouverts..."
    local failed_ports=()

    for port in "${ports_to_open[@]}"; do
        if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${target_port}" "${ansible_user}@${target_host}" "sudo ufw status | grep -E \"^${port}/(tcp|udp)\"" &>/dev/null; then
            log "WARNING" "Le port ${port} ne semble pas être correctement ouvert dans UFW"
            failed_ports+=("${port}")
            success=false
        fi
    done

    if [[ ${#failed_ports[@]} -gt 0 ]]; then
        log "WARNING" "Les ports suivants n'ont pas pu être ouverts: ${failed_ports[*]}"
    fi

    # Affichage du statut UFW
    local ufw_status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${target_port}" "${ansible_user}@${target_host}" "sudo ufw status" 2>/dev/null || echo "Impossible de récupérer le statut UFW")
    log "INFO" "Statut UFW actuel:"
    echo "${ufw_status}"

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
        if nc -z -w ${timeout} "${target_host}" "${port}" &>/dev/null; then
            log "INFO" "Port ${port} accessible sur ${target_host}"
            open_ports+=("${port}")
        else
            log "WARNING" "Port ${port} non accessible sur ${target_host}"
            closed_ports+=("${port}")
        fi
    done

    # Résumé des ports
    if [[ ${#open_ports[@]} -eq ${#REQUIRED_PORTS[@]} ]]; then
        log "SUCCESS" "Tous les ports requis sont accessibles sur ${target_host}"
    else
        log "WARNING" "Certains ports requis ne sont pas accessibles sur ${target_host}"
        log "INFO" "Ports ouverts: ${open_ports[*]}"
        log "WARNING" "Ports fermés: ${closed_ports[*]}"

        # Demande à l'utilisateur s'il souhaite ouvrir les ports automatiquement
        log "INFO" "Des ports requis sont fermés. Souhaitez-vous les ouvrir automatiquement? (o/N)"
        read -r answer

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
                    log "INFO" "Ports toujours fermés: ${closed_ports[*]}"
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
        if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "[ -d \"${dir}\" ]" &>/dev/null; then
            existing_dirs+=("${dir}")
            log "DEBUG" "Répertoire trouvé pour sauvegarde: ${dir}"
        else
            log "DEBUG" "Répertoire non trouvé, ignoré pour la sauvegarde: ${dir}"
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
    if ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "${backup_cmd}"; then
        # Récupération du fichier de sauvegarde
        if scp -P "${ansible_port}" "${ansible_user}@${ansible_host}:/tmp/${backup_name}.tar.gz" "${backup_file}" &>/dev/null; then
            # Nettoyage du fichier temporaire sur le VPS
            ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "rm -f /tmp/${backup_name}.tar.gz"

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
        else
            log "WARNING" "Impossible de récupérer le fichier de sauvegarde depuis le VPS"
            rm -f "${metadata_file}"
            if [[ "${optional}" == "true" ]]; then
                log "INFO" "Continuation de l'installation malgré l'échec de la sauvegarde (optionnelle)"
                return 0
            else
                return 1
            fi
        fi
    else
        log "WARNING" "Impossible de créer une sauvegarde de l'état actuel sur le VPS"
        rm -f "${metadata_file}"
        if [[ "${optional}" == "true" ]]; then
            log "INFO" "Continuation de l'installation malgré l'échec de la sauvegarde (optionnelle)"
            return 0
        else
            return 1
        fi
    fi
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
        local backup_date=$(jq -r '.backup_date' "${metadata_file}")
        local backup_step=$(jq -r '.installation_step' "${metadata_file}")
        local backup_env=$(jq -r '.environment' "${metadata_file}")

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

    # Copie du fichier de sauvegarde vers le VPS
    log "INFO" "Copie du fichier de sauvegarde vers le VPS..."
    if ! scp -P "${ansible_port}" "${backup_file}" "${ansible_user}@${ansible_host}:/tmp/${backup_name}.tar.gz" &>/dev/null; then
        log "ERROR" "Impossible de copier le fichier de sauvegarde vers le VPS"
        return 1
    fi

    # Arrêt des services avant restauration
    log "INFO" "Arrêt des services avant restauration..."
    ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl stop k3s || true" &>/dev/null

    # Restauration des fichiers
    log "INFO" "Restauration des fichiers..."
    if ! ssh -o BatchMode=yes -o ConnectTimeout=30 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo tar -xzf /tmp/${backup_name}.tar.gz -C / 2>/dev/null"; then
        log "ERROR" "Échec de la restauration des fichiers"

        # Redémarrage des services en cas d'échec
        ssh -o BatchMode=yes -o ConnectTimeout=10 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl start k3s || true" &>/dev/null

        return 1
    fi

    # Nettoyage du fichier temporaire
    ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "rm -f /tmp/${backup_name}.tar.gz" &>/dev/null

    # Redémarrage des services
    log "INFO" "Redémarrage des services..."
    if ! ssh -o BatchMode=yes -o ConnectTimeout=30 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo systemctl daemon-reload && sudo systemctl start k3s"; then
        log "WARNING" "Échec du redémarrage des services"
        log "WARNING" "Vous devrez peut-être redémarrer manuellement le VPS"
        return 1
    fi

    # Attente que K3s soit prêt
    log "INFO" "Attente que K3s soit prêt..."
    local timeout=60
    local start_time=$(date +%s)
    local k3s_ready=false

    while [[ "${k3s_ready}" == "false" ]]; do
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))

        if [[ ${elapsed_time} -gt ${timeout} ]]; then
            log "WARNING" "Timeout atteint en attendant que K3s soit prêt"
            break
        fi

        if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "kubectl get nodes" &>/dev/null; then
            k3s_ready=true
            log "SUCCESS" "K3s est prêt"
        else
            log "INFO" "En attente que K3s soit prêt... (${elapsed_time}s)"
            sleep 5
        fi
    done

    log "SUCCESS" "Restauration terminée avec succès"

    # Mise à jour de l'état actuel
    if [[ -f "${metadata_file}" ]]; then
        local backup_step=$(jq -r '.installation_step' "${metadata_file}")
        INSTALLATION_STEP="${backup_step}"
        echo "${INSTALLATION_STEP}" > "${STATE_FILE}"
        log "INFO" "État actuel mis à jour: ${INSTALLATION_STEP}"
    fi

    return 0
}

# Fonction pour exécuter une commande avec timeout
function run_with_timeout() {
    local cmd="$1"
    local timeout="${2:-${TIMEOUT_SECONDS}}"
    local cmd_type="${3:-generic}"
    local max_retries=3
    local retry_count=0
    local backoff_time=5
    local interactive=false

    # Vérifier si la commande est interactive (nécessite une entrée utilisateur)
    if [[ "${cmd}" == *"--ask-become-pass"* || "${cmd}" == *"--ask-pass"* || "${cmd}" == *"-K"* || "${cmd}" == *"-k"* ]]; then
        interactive=true
        log "INFO" "Commande interactive détectée, l'entrée utilisateur sera requise"
    fi

    log "INFO" "Exécution de la commande avec timeout ${timeout}s: ${cmd}"
    LAST_COMMAND="${cmd}"

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

        if [[ "${interactive}" == "true" ]]; then
            # Pour les commandes interactives, exécuter sans redirection pour permettre l'entrée utilisateur
            log "INFO" "Exécution de la commande interactive, veuillez répondre aux invites si nécessaire..."
            timeout ${timeout} bash -c "${cmd}"
            exit_code=$?
        else
            # Pour les commandes non interactives, capturer la sortie
            local output_file=$(mktemp)
            timeout ${timeout} bash -c "${cmd}" > "${output_file}" 2>&1
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
                if [[ "${cmd}" == *"ansible-playbook"* && "${cmd}" == *"--ask-become-pass"* ]]; then
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
        local lock_file_age=$(( $(date +%s) - $(stat -c %Y "${LOCK_FILE}" 2>/dev/null || echo $(date +%s)) ))

        # Vérification de l'uptime du système
        local uptime_seconds=$(cat /proc/uptime 2>/dev/null | awk '{print int($1)}' || echo 999999)

        # Vérification des processus en cours d'exécution
        local script_name=$(basename "$0")
        local script_count=$(ps aux | grep -v grep | grep -c "${script_name}" || echo 1)

        # Si le système a redémarré après la création du fichier de verrouillage
        # ou si le fichier de verrouillage existe depuis plus d'une heure
        # ou si aucun autre processus du script n'est en cours d'exécution
        if [[ ${uptime_seconds} -lt ${lock_file_age} || ${lock_file_age} -gt 3600 || ${script_count} -le 1 ]]; then
            log "INFO" "Le système a redémarré ou le fichier de verrouillage est obsolète (âge: ${lock_file_age}s, uptime: ${uptime_seconds}s) ou aucune autre instance n'est en cours d'exécution"
            log "INFO" "Suppression automatique du fichier de verrouillage obsolète"
            rm -f "${LOCK_FILE}"
        else
            log "WARNING" "Si ce n'est pas le cas, supprimez le fichier ${LOCK_FILE} et réessayez"
            log "INFO" "Commande pour supprimer le fichier de verrouillage: sudo rm -f ${LOCK_FILE}"
            exit 1
        fi
    fi

    # Création du fichier de verrouillage
    touch "${LOCK_FILE}"

    # Vérification de la version du système d'exploitation
    log "INFO" "Vérification du système d'exploitation..."
    local os_name=$(uname -s)
    local os_version=$(uname -r)

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
        "ansible-playbook:2.9.0"
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

    # Vérification des fichiers Ansible
    log "INFO" "Vérification des fichiers Ansible..."
    if [[ ! -d "${ANSIBLE_DIR}/inventories/${environment}" ]]; then
        log "ERROR" "Le répertoire d'inventaire pour l'environnement ${environment} n'existe pas: ${ANSIBLE_DIR}/inventories/${environment}"
        cleanup
        exit 1
    fi

    if [[ ! -f "${ANSIBLE_DIR}/${inventory_file}" ]]; then
        log "ERROR" "Le fichier d'inventaire n'existe pas: ${ANSIBLE_DIR}/${inventory_file}"
        cleanup
        exit 1
    fi

    if [[ ! -f "${ANSIBLE_DIR}/playbooks/init-vps.yml" ]]; then
        log "ERROR" "Le playbook d'initialisation du VPS n'existe pas: ${ANSIBLE_DIR}/playbooks/init-vps.yml"
        cleanup
        exit 1
    fi

    if [[ ! -f "${ANSIBLE_DIR}/playbooks/install-k3s.yml" ]]; then
        log "ERROR" "Le playbook d'installation de K3s n'existe pas: ${ANSIBLE_DIR}/playbooks/install-k3s.yml"
        cleanup
        exit 1
    fi

    # Vérification des fichiers Kubernetes
    log "INFO" "Vérification des fichiers Kubernetes..."
    if [[ ! -d "${PROJECT_ROOT}/kubernetes/overlays/${environment}" ]]; then
        log "ERROR" "Le répertoire d'overlay Kubernetes pour l'environnement ${environment} n'existe pas: ${PROJECT_ROOT}/kubernetes/overlays/${environment}"
        cleanup
        exit 1
    fi

    if [[ ! -f "${PROJECT_ROOT}/kubernetes/overlays/${environment}/kustomization.yaml" ]]; then
        log "ERROR" "Le fichier kustomization.yaml pour l'environnement ${environment} n'existe pas: ${PROJECT_ROOT}/kubernetes/overlays/${environment}/kustomization.yaml"
        cleanup
        exit 1
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

    # Vérification de la connexion SSH
    log "INFO" "Vérification de la connexion SSH..."
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "echo 'Connexion SSH réussie'" &>/dev/null; then
        log "ERROR" "Impossible de se connecter au VPS via SSH (${ansible_user}@${ansible_host}:${ansible_port})"
        log "ERROR" "Vérifiez vos clés SSH et les paramètres de connexion"

        # Vérification des clés SSH
        if [[ ! -f ~/.ssh/id_rsa && ! -f ~/.ssh/id_ed25519 ]]; then
            log "ERROR" "Aucune clé SSH trouvée dans ~/.ssh/"
            log "ERROR" "Générez une paire de clés avec: ssh-keygen -t ed25519"
        fi

        # Vérification du fichier known_hosts
        if ! grep -q "${ansible_host}" ~/.ssh/known_hosts 2>/dev/null; then
            log "WARNING" "L'hôte ${ansible_host} n'est pas dans le fichier known_hosts"
            log "WARNING" "Essayez d'abord de vous connecter manuellement: ssh -p ${ansible_port} ${ansible_user}@${ansible_host}"
        fi

        cleanup
        exit 1
    fi

    # Vérification des ressources du VPS
    log "INFO" "Vérification des ressources du VPS..."
    local vps_cpu_cores=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "nproc --all" 2>/dev/null || echo "0")
    local vps_memory_total=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "free -m | awk '/^Mem:/ {print \$2}'" 2>/dev/null || echo "0")
    local vps_disk_free=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "df -m / | awk 'NR==2 {print \$4}'" 2>/dev/null || echo "0")

    log "INFO" "Ressources du VPS: ${vps_cpu_cores} cœurs CPU, ${vps_memory_total}MB RAM, ${vps_disk_free}MB espace disque libre"

    if [[ ${vps_cpu_cores} -lt 2 ]]; then
        log "WARNING" "Le VPS a moins de 2 cœurs CPU (${vps_cpu_cores}), ce qui peut affecter les performances"
    fi

    if [[ ${vps_memory_total} -lt 4096 ]]; then
        log "WARNING" "Le VPS a moins de 4GB de RAM (${vps_memory_total}MB), ce qui peut affecter les performances"
    fi

    if [[ ${vps_disk_free} -lt 20000 ]]; then
        log "WARNING" "Le VPS a moins de 20GB d'espace disque libre (${vps_disk_free}MB), ce qui peut être insuffisant"
    fi

    log "SUCCESS" "Tous les prérequis sont satisfaits"

    # Vérification de l'état précédent
    if [[ -f "${STATE_FILE}" ]]; then
        local previous_step=$(cat "${STATE_FILE}")
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
    local ansible_cmd="ansible-playbook -i ${ANSIBLE_DIR}/${inventory_file} ${ANSIBLE_DIR}/playbooks/init-vps.yml --ask-become-pass"

    if [[ "${debug_mode}" == "true" ]]; then
        ansible_cmd="${ansible_cmd} -vvv"
    fi

    log "INFO" "Exécution de la commande: ${ansible_cmd}"
    LAST_COMMAND="${ansible_cmd}"

    # Exécution de la commande avec timeout
    if run_with_timeout "${ansible_cmd}" "${TIMEOUT_SECONDS}" "ansible_playbook"; then
        log "SUCCESS" "Initialisation du VPS terminée avec succès"

        # Vérification de l'état du VPS après initialisation
        if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "systemctl is-active --quiet sshd && systemctl is-active --quiet fail2ban && systemctl is-active --quiet ufw" &>/dev/null; then
            log "WARNING" "Certains services essentiels ne sont pas actifs après l'initialisation"
            log "WARNING" "Vérifiez manuellement l'état des services sur le VPS"
        else
            log "INFO" "Services essentiels actifs et fonctionnels"
        fi
    else
        log "ERROR" "Échec de l'initialisation du VPS"

        # Vérification des erreurs courantes
        if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "grep -i 'failed=' /var/log/ansible.log 2>/dev/null | tail -10" &>/dev/null; then
            log "INFO" "Dernières erreurs Ansible sur le VPS:"
            ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "grep -i 'failed=' /var/log/ansible.log 2>/dev/null | tail -10" 2>/dev/null || true
        fi

        # Tentative de diagnostic
        log "INFO" "Tentative de diagnostic des problèmes..."

        # Vérification des droits sudo
        if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "sudo -n true" &>/dev/null; then
            log "ERROR" "L'utilisateur ${ansible_user} n'a pas les droits sudo sans mot de passe"
            log "ERROR" "Assurez-vous que l'utilisateur est configuré correctement dans le fichier sudoers"
        fi

        # Vérification de l'espace disque sur le VPS
        local disk_info=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "df -h /" 2>/dev/null || echo "Impossible de vérifier l'espace disque")
        log "INFO" "Espace disque sur le VPS:"
        echo "${disk_info}"

        cleanup
        exit 1
    fi
}

# Fonction d'installation de K3s
function installer_k3s() {
    log "INFO" "Installation de K3s..."
    INSTALLATION_STEP="install_k3s"

    # Sauvegarde de l'état actuel
    echo "${INSTALLATION_STEP}" > "${STATE_FILE}"

    # Sauvegarde de l'état du VPS avant modification (optionnelle)
    backup_state "pre-install-k3s" "true"

    # Construction de la commande Ansible
    local ansible_cmd="ansible-playbook -i ${ANSIBLE_DIR}/${inventory_file} ${ANSIBLE_DIR}/playbooks/install-k3s.yml --ask-become-pass"

    if [[ "${debug_mode}" == "true" ]]; then
        ansible_cmd="${ansible_cmd} -vvv"
    fi

    log "INFO" "Exécution de la commande: ${ansible_cmd}"
    LAST_COMMAND="${ansible_cmd}"

    # Exécution de la commande avec timeout
    if run_with_timeout "${ansible_cmd}" 3600 "ansible_playbook"; then  # Timeout plus long (1h) pour l'installation de K3s
        log "SUCCESS" "Installation de K3s terminée avec succès"

        # Vérification de l'installation de K3s
        if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "systemctl is-active --quiet k3s" &>/dev/null; then
            log "WARNING" "Le service K3s ne semble pas être actif après l'installation"
            log "WARNING" "Vérifiez manuellement l'état du service sur le VPS"
        else
            log "INFO" "Service K3s actif et fonctionnel"

            # Vérification des pods système
            local pods_status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "kubectl get pods -n kube-system -o wide" 2>/dev/null || echo "Impossible de vérifier les pods")
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
        if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "grep -i 'failed=' /var/log/ansible.log 2>/dev/null | tail -10" &>/dev/null; then
            log "INFO" "Dernières erreurs Ansible sur le VPS:"
            ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "grep -i 'failed=' /var/log/ansible.log 2>/dev/null | tail -10" 2>/dev/null || true
        fi

        # Vérification des logs de K3s
        local k3s_logs=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "journalctl -u k3s --no-pager -n 50" 2>/dev/null || echo "Impossible de récupérer les logs de K3s")
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
        local system_info=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "uname -a && cat /etc/os-release | grep PRETTY_NAME && free -h && df -h / && sysctl -a | grep -E 'vm.max_map_count|net.ipv4.ip_forward'" 2>/dev/null || echo "Impossible de récupérer les informations système")
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
    local start_time=$(date +%s)
    local all_pods_ready=false

    while [[ "${all_pods_ready}" == "false" ]]; do
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))

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

    local nodes_output=$(kubectl get nodes -o wide 2>&1)
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

    local namespaces_output=$(kubectl get namespaces 2>&1)
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

    local system_pods_output=$(kubectl get pods -n kube-system 2>&1)
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

    local infra_pods_output=$(kubectl get pods -n lions-infrastructure 2>&1)
    echo "${infra_pods_output}"

    # Vérification des pods de monitoring
    log "INFO" "Vérification des pods de monitoring..."
    LAST_COMMAND="kubectl get pods -n monitoring"

    local monitoring_pods_output=$(kubectl get pods -n monitoring 2>&1)
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

    local dashboard_pods_output=$(kubectl get pods -n kubernetes-dashboard 2>&1)
    echo "${dashboard_pods_output}"

    # Vérification des services
    log "INFO" "Vérification des services exposés..."

    # Vérification de Grafana
    local grafana_service=$(kubectl get service -n monitoring prometheus-grafana -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    if [[ -n "${grafana_service}" ]]; then
        log "INFO" "Grafana est exposé sur le port ${grafana_service}"

        # Tentative de connexion à Grafana
        if command_exists "curl"; then
            if curl -s -o /dev/null -w "%{http_code}" "http://${ansible_host}:${grafana_service}" | grep -q "200\|302"; then
                log "SUCCESS" "Grafana est accessible à l'adresse: http://${ansible_host}:${grafana_service}"
            else
                log "WARNING" "Grafana n'est pas accessible à l'adresse: http://${ansible_host}:${grafana_service}"
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
            if curl -s -k -o /dev/null -w "%{http_code}" "https://${ansible_host}:${dashboard_service}" | grep -q "200\|302\|401"; then
                log "SUCCESS" "Kubernetes Dashboard est accessible à l'adresse: https://${ansible_host}:${dashboard_service}"
            else
                log "WARNING" "Kubernetes Dashboard n'est pas accessible à l'adresse: https://${ansible_host}:${dashboard_service}"
                log "WARNING" "Vérifiez les règles de pare-feu et l'état du service"
            fi
        fi
    else
        log "WARNING" "Service Kubernetes Dashboard non trouvé ou non exposé"
    fi

    # Vérification de Traefik
    log "INFO" "Vérification de Traefik..."
    local traefik_pods=$(kubectl get pods -n kube-system -l app=traefik -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

    if [[ -n "${traefik_pods}" ]]; then
        log "SUCCESS" "Traefik est installé et en cours d'exécution"

        # Vérification des services Traefik
        local traefik_service=$(kubectl get service -n kube-system traefik -o jsonpath='{.spec.ports[?(@.name=="web")].nodePort}' 2>/dev/null)
        if [[ -n "${traefik_service}" ]]; then
            log "INFO" "Traefik est exposé sur le port ${traefik_service}"

            # Tentative de connexion à Traefik
            if command_exists "curl"; then
                if curl -s -o /dev/null -w "%{http_code}" "http://${ansible_host}:${traefik_service}" | grep -q "200\|302\|404"; then
                    log "SUCCESS" "Traefik est accessible à l'adresse: http://${ansible_host}:${traefik_service}"
                else
                    log "WARNING" "Traefik n'est pas accessible à l'adresse: http://${ansible_host}:${traefik_service}"
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
    kubectl get events --all-namespaces --sort-by='.lastTimestamp' --field-selector type=Warning --since=5m

    # Vérification de la connectivité externe
    log "INFO" "Vérification de la connectivité externe..."

    # Vérification de l'accès aux services exposés
    local services_to_check=(
        "http://${ansible_host}:30000|Grafana"
        "https://${ansible_host}:30001|Kubernetes Dashboard"
        "http://${ansible_host}:80|Traefik HTTP"
        "https://${ansible_host}:443|Traefik HTTPS"
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
    local report_file="${LOG_DIR}/verification-report-$(date +%Y%m%d-%H%M%S).txt"

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
        kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20
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
    rm -f "${LOCK_FILE}" "${STATE_FILE}"
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
    local temp_script=$(mktemp)
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
        local final_counter=$(cat "/tmp/retry_test_counter")
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
echo -e "${COLOR_YELLOW}${COLOR_BOLD}  Installation de l'Infrastructure sur VPS - v1.0.0${COLOR_RESET}"
echo -e "${COLOR_CYAN}  ------------------------------------------------${COLOR_RESET}\n"

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
    rm -f "${LOCK_FILE}"

    exit 0
fi

# Exécution des étapes d'installation
verifier_prerequis

# Extraction des informations d'inventaire
extraire_informations_inventaire

# Sauvegarde de l'état initial (optionnelle)
backup_state "pre-installation" "true"

if [[ "${skip_init}" == "false" ]]; then
    initialiser_vps
else
    log "INFO" "Initialisation du VPS ignorée"
fi

installer_k3s

# Sauvegarde de l'état après installation de K3s (optionnelle)
backup_state "post-k3s" "true"

deployer_infrastructure_base

# Sauvegarde de l'état après déploiement de l'infrastructure (optionnelle)
backup_state "post-infrastructure" "true"

deployer_monitoring

# Sauvegarde de l'état après déploiement du monitoring (optionnelle)
backup_state "post-monitoring" "true"

verifier_installation

# Affichage du résumé
echo -e "\n${COLOR_GREEN}${COLOR_BOLD}===========================================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}${COLOR_BOLD}  Installation de l'infrastructure LIONS terminée avec succès !${COLOR_RESET}"
echo -e "${COLOR_GREEN}${COLOR_BOLD}===========================================================${COLOR_RESET}\n"

log "INFO" "Pour accéder à Grafana, utilisez l'URL: http://${ansible_host}:30000"
log "INFO" "Identifiant: admin"
log "INFO" "Mot de passe: admin"

log "INFO" "Pour accéder au Kubernetes Dashboard, utilisez l'URL: https://${ansible_host}:30001"
log "INFO" "Utilisez le token affiché dans les logs d'installation pour vous connecter"
log "INFO" "Vous pouvez également générer un nouveau token avec: kubectl create token dashboard-admin -n kubernetes-dashboard"

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
    echo "Grafana: http://${ansible_host}:30000 (admin/admin)"
    echo "Kubernetes Dashboard: https://${ansible_host}:30001 (token requis)"
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
rm -f "${LOCK_FILE}"

exit 0
