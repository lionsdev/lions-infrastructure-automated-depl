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

# Fonction de logging
function log() {
    local level="$1"
    local message="$2"
    local timestamp="$(date +"%Y-%m-%d %H:%M:%S")"

    echo -e "${COLOR_BOLD}[${timestamp}] [${level}]${COLOR_RESET} ${message}"
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Fonction de gestion des erreurs
function handle_error() {
    local exit_code=$?
    local line_number=$1

    # Désactivation du mode strict pour la gestion des erreurs
    set +euo pipefail

    log "ERROR" "Une erreur s'est produite à la ligne ${line_number} (code ${exit_code})"
    log "ERROR" "Dernière commande exécutée: ${LAST_COMMAND}"

    # Enregistrement de l'erreur
    LAST_ERROR="Erreur à la ligne ${line_number} (code ${exit_code}): ${LAST_COMMAND}"

    # Tentative de reprise si possible
    if [[ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]]; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        log "WARNING" "Tentative de reprise (${RETRY_COUNT}/${MAX_RETRIES})..."

        # Sauvegarde de l'état actuel
        echo "${INSTALLATION_STEP}" > "${STATE_FILE}"

        # Reprise en fonction de l'étape
        case "${INSTALLATION_STEP}" in
            "init_vps")
                log "INFO" "Reprise de l'initialisation du VPS..."
                initialiser_vps
                ;;
            "install_k3s")
                log "INFO" "Reprise de l'installation de K3s..."
                installer_k3s
                ;;
            "deploy_infra")
                log "INFO" "Reprise du déploiement de l'infrastructure de base..."
                deployer_infrastructure_base
                ;;
            "deploy_monitoring")
                log "INFO" "Reprise du déploiement du monitoring..."
                deployer_monitoring
                ;;
            *)
                log "ERROR" "Impossible de reprendre à l'étape '${INSTALLATION_STEP}'"
                cleanup
                exit ${exit_code}
                ;;
        esac
    else
        log "ERROR" "Nombre maximal de tentatives atteint (${MAX_RETRIES})"
        log "ERROR" "Dernière erreur: ${LAST_ERROR}"
        cleanup
        exit ${exit_code}
    fi
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
trap 'handle_error ${LINENO}' ERR

# Fonction pour vérifier si une commande existe
function command_exists() {
    command -v "$1" &> /dev/null
}

# Fonction pour vérifier l'espace disque disponible
function check_disk_space() {
    local available_space=$(df -m . | awk 'NR==2 {print $4}')

    if [[ ${available_space} -lt ${REQUIRED_SPACE_MB} ]]; then
        log "ERROR" "Espace disque insuffisant: ${available_space}MB disponible, ${REQUIRED_SPACE_MB}MB requis"
        return 1
    else
        log "INFO" "Espace disque disponible: ${available_space}MB (minimum requis: ${REQUIRED_SPACE_MB}MB)"
        return 0
    fi
}

# Fonction pour vérifier la connectivité réseau
function check_network() {
    local target_host=$(grep -A1 "contabo-vps" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_host" | awk -F': ' '{print $2}')
    local target_port=$(grep -A1 "contabo-vps" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_port" | awk -F': ' '{print $2}')

    if [[ -z "${target_host}" ]]; then
        log "ERROR" "Impossible de déterminer l'adresse du VPS dans le fichier d'inventaire"
        return 1
    fi

    if ! ping -c 3 "${target_host}" &> /dev/null; then
        log "ERROR" "Impossible de joindre le VPS à l'adresse ${target_host}"
        return 1
    fi

    log "INFO" "Connectivité réseau vers ${target_host} vérifiée avec succès"

    # Vérification des ports requis
    for port in "${REQUIRED_PORTS[@]}"; do
        if ! nc -z -w 5 "${target_host}" "${port}" &> /dev/null; then
            log "WARNING" "Le port ${port} n'est pas accessible sur ${target_host}"
        else
            log "INFO" "Port ${port} accessible sur ${target_host}"
        fi
    done

    return 0
}

# Fonction pour sauvegarder l'état avant modification
function backup_state() {
    local backup_name="backup-$(date +%Y%m%d-%H%M%S)"
    local backup_file="${BACKUP_DIR}/${backup_name}.tar.gz"

    log "INFO" "Sauvegarde de l'état actuel dans ${backup_file}..."

    # Sauvegarde des fichiers de configuration
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "tar -czf /tmp/${backup_name}.tar.gz /etc/rancher /var/lib/rancher/k3s/server/manifests /home/${ansible_user}/.kube 2>/dev/null || true"; then
        scp -P "${ansible_port}" "${ansible_user}@${ansible_host}:/tmp/${backup_name}.tar.gz" "${backup_file}" &>/dev/null
        ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "rm -f /tmp/${backup_name}.tar.gz"
        log "SUCCESS" "Sauvegarde de l'état créée: ${backup_file}"
    else
        log "WARNING" "Impossible de créer une sauvegarde de l'état actuel"
    fi
}

# Fonction pour exécuter une commande avec timeout
function run_with_timeout() {
    local cmd="$1"
    local timeout="${2:-${TIMEOUT_SECONDS}}"

    log "INFO" "Exécution de la commande avec timeout ${timeout}s: ${cmd}"
    LAST_COMMAND="${cmd}"

    # Exécution de la commande avec timeout
    timeout ${timeout} bash -c "${cmd}"
    local exit_code=$?

    if [[ ${exit_code} -eq 124 ]]; then
        log "ERROR" "La commande a dépassé le délai d'attente (${timeout}s)"
        return 1
    elif [[ ${exit_code} -ne 0 ]]; then
        log "ERROR" "La commande a échoué avec le code ${exit_code}"
        return ${exit_code}
    fi

    return 0
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

    # Vérification du verrouillage
    if [[ -f "${LOCK_FILE}" ]]; then
        log "WARNING" "Une autre instance du script semble être en cours d'exécution"
        log "WARNING" "Si ce n'est pas le cas, supprimez le fichier ${LOCK_FILE} et réessayez"
        exit 1
    fi

    # Création du fichier de verrouillage
    touch "${LOCK_FILE}"

    # Vérification de l'espace disque
    if ! check_disk_space; then
        log "ERROR" "Vérification de l'espace disque échouée"
        cleanup
        exit 1
    fi

    # Vérification des commandes requises
    local required_commands=("ansible-playbook" "ssh" "scp" "kubectl" "helm" "timeout" "nc" "ping")
    local missing_commands=()

    for cmd in "${required_commands[@]}"; do
        if ! command_exists "${cmd}"; then
            missing_commands+=("${cmd}")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log "ERROR" "Commandes requises non trouvées: ${missing_commands[*]}"
        log "ERROR" "Veuillez installer ces commandes avant de continuer"
        cleanup
        exit 1
    fi

    # Vérification des fichiers Ansible
    if [[ ! -d "${ANSIBLE_DIR}/inventories/${environment}" ]]; then
        log "ERROR" "Le répertoire d'inventaire pour l'environnement ${environment} n'existe pas"
        cleanup
        exit 1
    fi

    if [[ ! -f "${ANSIBLE_DIR}/${inventory_file}" ]]; then
        log "ERROR" "Le fichier d'inventaire n'existe pas: ${ANSIBLE_DIR}/${inventory_file}"
        cleanup
        exit 1
    fi

    if [[ ! -f "${ANSIBLE_DIR}/playbooks/init-vps.yml" ]]; then
        log "ERROR" "Le playbook d'initialisation du VPS n'existe pas"
        cleanup
        exit 1
    fi

    if [[ ! -f "${ANSIBLE_DIR}/playbooks/install-k3s.yml" ]]; then
        log "ERROR" "Le playbook d'installation de K3s n'existe pas"
        cleanup
        exit 1
    fi

    # Extraction des informations de connexion
    ansible_host=$(grep -A1 "contabo-vps" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_host" | awk -F': ' '{print $2}')
    ansible_port=$(grep -A1 "contabo-vps" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_port" | awk -F': ' '{print $2}')
    ansible_user=$(grep -A1 "contabo-vps" "${ANSIBLE_DIR}/${inventory_file}" | grep "ansible_user" | awk -F': ' '{print $2}')

    if [[ -z "${ansible_host}" || -z "${ansible_port}" || -z "${ansible_user}" ]]; then
        log "ERROR" "Impossible d'extraire les informations de connexion du fichier d'inventaire"
        cleanup
        exit 1
    fi

    # Vérification de la connectivité réseau
    if ! check_network; then
        log "ERROR" "Vérification de la connectivité réseau échouée"
        cleanup
        exit 1
    fi

    # Vérification de la connexion SSH
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${ansible_port}" "${ansible_user}@${ansible_host}" "echo 'Connexion SSH réussie'" &>/dev/null; then
        log "ERROR" "Impossible de se connecter au VPS via SSH (${ansible_user}@${ansible_host}:${ansible_port})"
        log "ERROR" "Vérifiez vos clés SSH et les paramètres de connexion"
        cleanup
        exit 1
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

# Fonction d'initialisation du VPS
function initialiser_vps() {
    log "INFO" "Initialisation du VPS..."
    INSTALLATION_STEP="init_vps"

    # Sauvegarde de l'état actuel
    echo "${INSTALLATION_STEP}" > "${STATE_FILE}"

    # Sauvegarde de l'état du VPS avant modification
    backup_state

    # Construction de la commande Ansible
    local ansible_cmd="ansible-playbook -i ${ANSIBLE_DIR}/${inventory_file} ${ANSIBLE_DIR}/playbooks/init-vps.yml --ask-become-pass"

    if [[ "${debug_mode}" == "true" ]]; then
        ansible_cmd="${ansible_cmd} -vvv"
    fi

    log "INFO" "Exécution de la commande: ${ansible_cmd}"
    LAST_COMMAND="${ansible_cmd}"

    # Exécution de la commande avec timeout
    if run_with_timeout "${ansible_cmd}"; then
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

    # Sauvegarde de l'état du VPS avant modification
    backup_state

    # Construction de la commande Ansible
    local ansible_cmd="ansible-playbook -i ${ANSIBLE_DIR}/${inventory_file} ${ANSIBLE_DIR}/playbooks/install-k3s.yml --ask-become-pass"

    if [[ "${debug_mode}" == "true" ]]; then
        ansible_cmd="${ansible_cmd} -vvv"
    fi

    log "INFO" "Exécution de la commande: ${ansible_cmd}"
    LAST_COMMAND="${ansible_cmd}"

    # Exécution de la commande avec timeout
    if run_with_timeout "${ansible_cmd}" 3600; then  # Timeout plus long (1h) pour l'installation de K3s
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

    # Vérification des événements récents
    log "INFO" "Événements récents (dernières 5 minutes):"
    kubectl get events --all-namespaces --sort-by='.lastTimestamp' --field-selector type=Warning --since=5m

    log "SUCCESS" "Vérification de l'installation terminée avec succès"

    # Nettoyage du fichier de verrouillage et d'état
    rm -f "${LOCK_FILE}" "${STATE_FILE}"
}

# Parsing des arguments
environment="${DEFAULT_ENV}"
inventory_file="inventories/${DEFAULT_ENV}/hosts.yml"
skip_init="false"
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
        -s|--skip-init)
            skip_init="true"
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
echo -e "${COLOR_YELLOW}${COLOR_BOLD}  Installation de l'Infrastructure sur VPS - v1.0.0${COLOR_RESET}"
echo -e "${COLOR_CYAN}  ------------------------------------------------${COLOR_RESET}\n"

# Affichage des paramètres
log "INFO" "Environnement: ${environment}"
log "INFO" "Fichier d'inventaire: ${inventory_file}"
log "INFO" "Ignorer l'initialisation: ${skip_init}"
log "INFO" "Mode debug: ${debug_mode}"
log "INFO" "Fichier de log: ${LOG_FILE}"

# Exécution des étapes d'installation
verifier_prerequis

if [[ "${skip_init}" == "false" ]]; then
    initialiser_vps
fi

installer_k3s
deployer_infrastructure_base
deployer_monitoring
verifier_installation

# Affichage du résumé
echo -e "\n${COLOR_GREEN}${COLOR_BOLD}===========================================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}${COLOR_BOLD}  Installation de l'infrastructure LIONS terminée avec succès !${COLOR_RESET}"
echo -e "${COLOR_GREEN}${COLOR_BOLD}===========================================================${COLOR_RESET}\n"

log "INFO" "Pour accéder à Grafana, utilisez l'URL: http://<IP_VPS>:30000"
log "INFO" "Identifiant: admin"
log "INFO" "Mot de passe: admin"

log "INFO" "Pour accéder au Kubernetes Dashboard, utilisez l'URL: https://<IP_VPS>:30001"
log "INFO" "Utilisez le token affiché dans les logs d'installation pour vous connecter"
log "INFO" "Vous pouvez également générer un nouveau token avec: kubectl create token dashboard-admin -n kubernetes-dashboard"

log "INFO" "Pour déployer des applications, utilisez le script deploy.sh"

exit 0
