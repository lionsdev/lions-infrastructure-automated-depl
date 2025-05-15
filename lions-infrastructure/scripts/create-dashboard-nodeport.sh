#!/bin/bash
# Titre: Script de création du service NodePort pour le Kubernetes Dashboard
# Description: Crée le service kubernetes-dashboard-nodeport s'il n'existe pas
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-12
# Version: 1.0.0

set -euo pipefail

# Configuration
readonly LOG_DIR="/var/log/lions/maintenance"
readonly LOG_FILE="${LOG_DIR}/create-dashboard-nodeport-$(date +%Y%m%d-%H%M%S).log"

# Création du répertoire de logs
mkdir -p "${LOG_DIR}"

# Fonction de logging
function log() {
    local level="$1"
    local message="$2"
    local timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
    local icon=""

    # Sélection de l'icône en fonction du niveau
    case "${level}" in
        "INFO")     icon="ℹ️ " ;;
        "WARNING")  icon="⚠️ " ;;
        "ERROR")    icon="❌ " ;;
        "SUCCESS")  icon="✅ " ;;
    esac

    # Affichage du message
    echo -e "${icon}[${timestamp}] [${level}] ${message}"

    # Enregistrement dans un fichier de log
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Vérification de kubectl
if ! command -v kubectl &> /dev/null; then
    log "ERROR" "kubectl n'est pas installé ou n'est pas dans le PATH"
    exit 1
fi

# Vérification de la connexion au cluster Kubernetes
if ! kubectl cluster-info &> /dev/null; then
    log "ERROR" "Impossible de se connecter au cluster Kubernetes"
    log "ERROR" "Vérifiez votre configuration kubectl et le fichier kubeconfig"
    exit 1
fi

# Vérification de l'existence du namespace kubernetes-dashboard
if ! kubectl get namespace kubernetes-dashboard &> /dev/null; then
    log "INFO" "Le namespace kubernetes-dashboard n'existe pas, création..."
    kubectl create namespace kubernetes-dashboard
    log "SUCCESS" "Namespace kubernetes-dashboard créé avec succès"
fi

# Vérification de l'existence du service kubernetes-dashboard
if ! kubectl get service kubernetes-dashboard -n kubernetes-dashboard &> /dev/null; then
    log "WARNING" "Le service kubernetes-dashboard n'existe pas"
    log "INFO" "Vérifiez que le Kubernetes Dashboard est bien déployé"
    log "INFO" "Exécutez: kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml"
    exit 1
fi

# Vérification de l'existence du service kubernetes-dashboard-nodeport
if kubectl get service kubernetes-dashboard-nodeport -n kubernetes-dashboard &> /dev/null; then
    log "INFO" "Le service kubernetes-dashboard-nodeport existe déjà"
else
    log "INFO" "Création du service kubernetes-dashboard-nodeport..."

    # Création du fichier de définition du service
    cat > /tmp/dashboard-nodeport.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-dashboard-nodeport
  namespace: kubernetes-dashboard
spec:
  ports:
  - port: 443
    targetPort: 8443
    nodePort: 30001
  selector:
    k8s-app: kubernetes-dashboard
  type: NodePort
EOF

    # Application du fichier de définition
    kubectl apply -f /tmp/dashboard-nodeport.yaml

    # Nettoyage
    rm -f /tmp/dashboard-nodeport.yaml

    log "SUCCESS" "Service kubernetes-dashboard-nodeport créé avec succès"
fi

# Vérification de l'existence du compte de service dashboard-admin
if ! kubectl get serviceaccount dashboard-admin -n kubernetes-dashboard &> /dev/null; then
    log "INFO" "Création du compte de service dashboard-admin..."

    # Création du compte de service
    kubectl create serviceaccount dashboard-admin -n kubernetes-dashboard

    # Création du ClusterRoleBinding
    kubectl create clusterrolebinding dashboard-admin \
      --clusterrole=cluster-admin \
      --serviceaccount=kubernetes-dashboard:dashboard-admin

    log "SUCCESS" "Compte de service dashboard-admin créé avec succès"
fi

# Création d'un Secret pour le token permanent du Dashboard
log "INFO" "Création d'un token permanent pour l'accès au Dashboard..."

# Vérification de l'existence du secret dashboard-admin-token
if ! kubectl get secret dashboard-admin-token -n kubernetes-dashboard &> /dev/null; then
    # Création du secret pour le token permanent
    cat > /tmp/dashboard-token-secret.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: dashboard-admin-token
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/service-account.name: dashboard-admin
type: kubernetes.io/service-account-token
EOF

    # Application du fichier de définition
    kubectl apply -f /tmp/dashboard-token-secret.yaml

    # Nettoyage
    rm -f /tmp/dashboard-token-secret.yaml

    # Attente que le token soit généré
    log "INFO" "Attente de la génération du token..."
    sleep 5
fi

# Récupération du token permanent
token=$(kubectl get secret dashboard-admin-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 --decode)

log "SUCCESS" "Token permanent généré avec succès"
log "INFO" "Utilisez ce token pour vous connecter au Dashboard: https://<IP_VPS>:30001"
echo
echo "Token: ${token}"
echo

log "SUCCESS" "Opération terminée avec succès"
