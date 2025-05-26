#!/bin/bash
# =============================================================================
# LIONS Infrastructure - Script de configuration de HashiCorp Vault
# =============================================================================
# Titre: Script de configuration et d'initialisation de HashiCorp Vault
# Description: Configure Vault après son installation, initialise les moteurs de secrets,
#              crée les politiques et configure l'authentification Kubernetes
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-25
# Version: 1.0.0
# =============================================================================

# Chargement des variables d'environnement
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Chargement des variables d'environnement depuis le fichier .env
if [ -f "${PROJECT_ROOT}/.env" ]; then
    source "${PROJECT_ROOT}/.env"
fi

# Configuration
readonly VAULT_ADDR="${LIONS_VAULT_ADDR:-https://vault.dev.lions.dev:8200}"
readonly VAULT_TOKEN_FILE="${HOME}/.vault-token"
readonly VAULT_INIT_FILE="${HOME}/.vault-init.json"
readonly VAULT_KEYS_FILE="${HOME}/.vault-keys"
readonly VAULT_CONFIG_DIR="${PROJECT_ROOT}/vault/config"
readonly VAULT_POLICIES_DIR="${PROJECT_ROOT}/vault/policies"
readonly VAULT_SECRETS_DIR="${PROJECT_ROOT}/vault/secrets"
readonly LOG_DIR="${PROJECT_ROOT}/scripts/logs/vault"
readonly LOG_FILE="${LOG_DIR}/configure-$(date +%Y%m%d-%H%M%S).log"
readonly BACKUP_DIR="${LOG_DIR}/backups"

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

# Création des répertoires nécessaires
mkdir -p "${LOG_DIR}"
mkdir -p "${BACKUP_DIR}"
mkdir -p "${VAULT_CONFIG_DIR}"
mkdir -p "${VAULT_POLICIES_DIR}"
mkdir -p "${VAULT_SECRETS_DIR}"

# Activation du mode strict
set -euo pipefail

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

    # Enregistrement dans le fichier de log
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Fonction de gestion des erreurs
function handle_error() {
    local exit_code=$?
    local line_number=$1
    local command=$2

    log "ERROR" "Une erreur s'est produite à la ligne ${line_number} (code ${exit_code})"
    log "ERROR" "Commande: ${command}"

    exit ${exit_code}
}

# Configuration du gestionnaire d'erreurs
trap 'handle_error ${LINENO} "${BASH_COMMAND}"' ERR

# Fonction pour vérifier si Vault est initialisé
function is_vault_initialized() {
    local initialized
    initialized=$(vault status -format=json | jq -r '.initialized')
    echo "${initialized}"
}

# Fonction pour vérifier si Vault est déverrouillé
function is_vault_unsealed() {
    local sealed
    sealed=$(vault status -format=json | jq -r '.sealed')
    if [ "${sealed}" == "false" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# Fonction pour initialiser Vault
function initialize_vault() {
    log "STEP" "Initialisation de Vault"
    
    if [ "$(is_vault_initialized)" == "true" ]; then
        log "INFO" "Vault est déjà initialisé"
        return 0
    fi
    
    log "INFO" "Initialisation de Vault avec 5 clés et un seuil de 3"
    vault operator init -key-shares=5 -key-threshold=3 -format=json > "${VAULT_INIT_FILE}"
    
    # Extraction des clés et du token root
    jq -r '.unseal_keys_b64[]' "${VAULT_INIT_FILE}" > "${VAULT_KEYS_FILE}"
    local root_token
    root_token=$(jq -r '.root_token' "${VAULT_INIT_FILE}")
    
    # Sauvegarde du token root
    echo "${root_token}" > "${VAULT_TOKEN_FILE}"
    chmod 600 "${VAULT_TOKEN_FILE}"
    chmod 600 "${VAULT_KEYS_FILE}"
    chmod 600 "${VAULT_INIT_FILE}"
    
    log "SUCCESS" "Vault initialisé avec succès"
    log "WARNING" "Les clés de déverrouillage et le token root ont été sauvegardés dans ${VAULT_KEYS_FILE} et ${VAULT_TOKEN_FILE}"
    log "WARNING" "IMPORTANT: Sauvegardez ces fichiers dans un endroit sécurisé et supprimez-les de ce serveur"
    
    return 0
}

# Fonction pour déverrouiller Vault
function unseal_vault() {
    log "STEP" "Déverrouillage de Vault"
    
    if [ "$(is_vault_unsealed)" == "true" ]; then
        log "INFO" "Vault est déjà déverrouillé"
        return 0
    fi
    
    if [ ! -f "${VAULT_KEYS_FILE}" ]; then
        log "ERROR" "Fichier de clés ${VAULT_KEYS_FILE} introuvable"
        return 1
    fi
    
    log "INFO" "Déverrouillage de Vault avec 3 clés"
    local keys
    keys=($(cat "${VAULT_KEYS_FILE}"))
    
    # Utilisation des 3 premières clés pour déverrouiller
    for i in {0..2}; do
        vault operator unseal "${keys[$i]}"
    done
    
    if [ "$(is_vault_unsealed)" == "true" ]; then
        log "SUCCESS" "Vault déverrouillé avec succès"
    else
        log "ERROR" "Échec du déverrouillage de Vault"
        return 1
    fi
    
    return 0
}

# Fonction pour configurer l'authentification
function configure_auth() {
    log "STEP" "Configuration des méthodes d'authentification"
    
    # Authentification par token
    log "INFO" "Configuration de l'authentification par token"
    vault auth enable token
    
    # Authentification AppRole
    log "INFO" "Configuration de l'authentification AppRole"
    vault auth enable approle
    
    # Authentification Kubernetes
    log "INFO" "Configuration de l'authentification Kubernetes"
    vault auth enable kubernetes
    
    # Configuration de l'authentification Kubernetes
    log "INFO" "Configuration de l'intégration avec Kubernetes"
    vault write auth/kubernetes/config \
        kubernetes_host="https://kubernetes.default.svc:443" \
        token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
        kubernetes_ca_cert="$(cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)" \
        issuer="https://kubernetes.default.svc.cluster.local"
    
    log "SUCCESS" "Méthodes d'authentification configurées avec succès"
    
    return 0
}

# Fonction pour configurer les moteurs de secrets
function configure_secrets_engines() {
    log "STEP" "Configuration des moteurs de secrets"
    
    # Moteur KV version 2
    log "INFO" "Activation du moteur KV version 2"
    vault secrets enable -version=2 kv
    
    # Moteur de gestion des certificats PKI
    log "INFO" "Activation du moteur PKI"
    vault secrets enable pki
    vault secrets tune -max-lease-ttl=87600h pki
    
    # Moteur de gestion des bases de données
    log "INFO" "Activation du moteur de gestion des bases de données"
    vault secrets enable database
    
    # Moteur de gestion des clés de chiffrement Transit
    log "INFO" "Activation du moteur Transit pour le chiffrement"
    vault secrets enable transit
    
    log "SUCCESS" "Moteurs de secrets configurés avec succès"
    
    return 0
}

# Fonction pour créer les politiques
function create_policies() {
    log "STEP" "Création des politiques"
    
    # Politique pour les applications
    cat > "${VAULT_POLICIES_DIR}/app-policy.hcl" << EOF
# Politique pour les applications
path "kv/data/lions/*" {
  capabilities = ["read"]
}
EOF
    
    # Politique pour les administrateurs
    cat > "${VAULT_POLICIES_DIR}/admin-policy.hcl" << EOF
# Politique pour les administrateurs
path "kv/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "pki/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "database/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "transit/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}
path "sys/policies/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
    
    # Politique pour les opérateurs
    cat > "${VAULT_POLICIES_DIR}/operator-policy.hcl" << EOF
# Politique pour les opérateurs
path "kv/data/lions/*" {
  capabilities = ["read", "list"]
}
path "pki/issue/*" {
  capabilities = ["create", "update"]
}
path "database/creds/*" {
  capabilities = ["read"]
}
EOF
    
    # Application des politiques
    log "INFO" "Application des politiques"
    vault policy write app-policy "${VAULT_POLICIES_DIR}/app-policy.hcl"
    vault policy write admin-policy "${VAULT_POLICIES_DIR}/admin-policy.hcl"
    vault policy write operator-policy "${VAULT_POLICIES_DIR}/operator-policy.hcl"
    
    log "SUCCESS" "Politiques créées avec succès"
    
    return 0
}

# Fonction pour créer les rôles Kubernetes
function create_kubernetes_roles() {
    log "STEP" "Création des rôles Kubernetes"
    
    # Rôle pour les applications
    log "INFO" "Création du rôle pour les applications"
    vault write auth/kubernetes/role/app \
        bound_service_account_names="*" \
        bound_service_account_namespaces="default,app,lions" \
        policies=app-policy \
        ttl=1h
    
    # Rôle pour les opérateurs
    log "INFO" "Création du rôle pour les opérateurs"
    vault write auth/kubernetes/role/operator \
        bound_service_account_names="operator" \
        bound_service_account_namespaces="kube-system,monitoring" \
        policies=operator-policy \
        ttl=4h
    
    log "SUCCESS" "Rôles Kubernetes créés avec succès"
    
    return 0
}

# Fonction pour stocker les secrets initiaux
function store_initial_secrets() {
    log "STEP" "Stockage des secrets initiaux"
    
    # Génération d'une clé SSH pour l'utilisateur lions-admin
    if [ ! -f "${HOME}/.ssh/id_ed25519" ]; then
        log "INFO" "Génération d'une clé SSH pour l'utilisateur lions-admin"
        mkdir -p "${HOME}/.ssh"
        ssh-keygen -t ed25519 -f "${HOME}/.ssh/id_ed25519" -N "" -C "lions-admin@$(hostname)"
        chmod 600 "${HOME}/.ssh/id_ed25519"
    fi
    
    # Stockage de la clé SSH privée dans Vault
    log "INFO" "Stockage de la clé SSH privée dans Vault"
    vault kv put kv/lions/ssh private_key="$(cat ${HOME}/.ssh/id_ed25519)" \
        public_key="$(cat ${HOME}/.ssh/id_ed25519.pub)" \
        sudo_password="$(openssl rand -base64 16)"
    
    # Stockage des informations de base de données
    log "INFO" "Stockage des informations de base de données"
    vault kv put kv/lions/database \
        username="lions_admin" \
        password="$(openssl rand -base64 16)" \
        host="postgres.lions.svc.cluster.local" \
        port="5432" \
        database="lions"
    
    # Stockage des informations d'API
    log "INFO" "Stockage des informations d'API"
    vault kv put kv/lions/api \
        jwt_secret="$(openssl rand -base64 32)" \
        api_key="$(openssl rand -hex 24)"
    
    log "SUCCESS" "Secrets initiaux stockés avec succès"
    
    return 0
}

# Fonction pour configurer l'auto-unseal avec un KMS
function configure_auto_unseal() {
    log "STEP" "Configuration de l'auto-unseal avec un KMS"
    
    # Cette fonction est un placeholder pour l'implémentation future
    # L'auto-unseal nécessite un KMS externe (AWS KMS, GCP KMS, Azure Key Vault)
    # ou un HSM compatible avec Vault
    
    log "WARNING" "La configuration de l'auto-unseal n'est pas implémentée dans cette version"
    log "INFO" "Pour configurer l'auto-unseal, consultez la documentation de HashiCorp Vault"
    
    return 0
}

# Fonction pour configurer la haute disponibilité
function configure_ha() {
    log "STEP" "Configuration de la haute disponibilité"
    
    # Cette fonction est un placeholder pour l'implémentation future
    # La haute disponibilité nécessite plusieurs nœuds Vault et un backend de stockage
    # compatible avec la haute disponibilité (Consul, etcd, etc.)
    
    log "WARNING" "La configuration de la haute disponibilité n'est pas implémentée dans cette version"
    log "INFO" "Pour configurer la haute disponibilité, consultez la documentation de HashiCorp Vault"
    
    return 0
}

# Fonction principale
function main() {
    log "STEP" "Démarrage de la configuration de Vault"
    
    # Vérification de la disponibilité de Vault
    log "INFO" "Vérification de la disponibilité de Vault"
    if ! vault status &>/dev/null; then
        log "ERROR" "Vault n'est pas accessible à l'adresse ${VAULT_ADDR}"
        log "INFO" "Vérifiez que Vault est installé et en cours d'exécution"
        exit 1
    fi
    
    # Initialisation de Vault
    initialize_vault
    
    # Déverrouillage de Vault
    unseal_vault
    
    # Authentification avec le token root
    if [ -f "${VAULT_TOKEN_FILE}" ]; then
        export VAULT_TOKEN=$(cat "${VAULT_TOKEN_FILE}")
    else
        log "ERROR" "Token root introuvable dans ${VAULT_TOKEN_FILE}"
        exit 1
    fi
    
    # Configuration des moteurs de secrets
    configure_secrets_engines
    
    # Configuration des méthodes d'authentification
    configure_auth
    
    # Création des politiques
    create_policies
    
    # Création des rôles Kubernetes
    create_kubernetes_roles
    
    # Stockage des secrets initiaux
    store_initial_secrets
    
    # Configuration de l'auto-unseal (placeholder)
    configure_auto_unseal
    
    # Configuration de la haute disponibilité (placeholder)
    configure_ha
    
    log "SUCCESS" "Configuration de Vault terminée avec succès"
    
    return 0
}

# Exécution de la fonction principale
main "$@"