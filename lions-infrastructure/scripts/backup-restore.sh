#!/bin/bash
# =============================================================================
# LIONS Infrastructure - Script de sauvegarde et restauration v5.0
# =============================================================================
# Description: Sauvegarde et restaure les données importantes du cluster Kubernetes
# Version: 5.0.0
# Date: 02/06/2023
# Auteur: LIONS DevOps Team
# =============================================================================

set -euo pipefail

# Chargement des variables d'environnement
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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
readonly BACKUP_DIR="${LIONS_BACKUP_DIR:-${PROJECT_ROOT}/backups}"
readonly KUBE_CONFIG="${LIONS_KUBE_CONFIG_PATH:-${HOME}/.kube/config}"
readonly KUBE_CONTEXT="${LIONS_KUBE_CONTEXT:-${LIONS_CLUSTER_NAME:-lions-k3s-cluster}}"
readonly BACKUP_RETENTION_DAYS="${LIONS_BACKUP_RETENTION_DAYS:-30}"

# Paramètres par défaut ou depuis les arguments
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ENVIRONMENT="${1:-${LIONS_ENVIRONMENT}}"
ACTION="${2:-${LIONS_BACKUP_ACTION:-backup}}"
BACKUP_NAME="${3:-${LIONS_BACKUP_NAME:-${TIMESTAMP}}}"

# Création des répertoires de sauvegarde
mkdir -p "${BACKUP_DIR}/${ENVIRONMENT}"

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
echo -e "║     ██████╗  █████╗  ██████╗██╗  ██╗██╗   ██╗██████╗             ║"
echo -e "║     ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██║   ██║██╔══██╗            ║"
echo -e "║     ██████╔╝███████║██║     █████╔╝ ██║   ██║██████╔╝            ║"
echo -e "║     ██╔══██╗██╔══██║██║     ██╔═██╗ ██║   ██║██╔═══╝             ║"
echo -e "║     ██████╔╝██║  ██║╚██████╗██║  ██╗╚██████╔╝██║                 ║"
echo -e "║     ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝                 ║"
echo -e "║                                                                   ║"
echo -e "╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo -e "${YELLOW}     Sauvegarde et Restauration LIONS - v5.0.0${NC}"
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

# Fonction pour sauvegarder les ressources Kubernetes
backup_kubernetes_resources() {
    local namespace=$1
    local resource_type=$2
    local output_dir="${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}/${namespace}"

    mkdir -p "${output_dir}"

    echo -e "${GREEN}[INFO]${NC} Sauvegarde des ${resource_type} dans le namespace ${namespace}..."

    # Récupération des noms de ressources
    local resources=$(kubectl get ${resource_type} -n ${namespace} -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "${resources}" ]]; then
        echo -e "${YELLOW}[WARNING]${NC} Aucun ${resource_type} trouvé dans le namespace ${namespace}"
        return
    fi

    # Sauvegarde de chaque ressource
    for resource in ${resources}; do
        echo -e "${GREEN}[INFO]${NC} Sauvegarde de ${resource_type}/${resource} dans le namespace ${namespace}..."
        kubectl get ${resource_type} ${resource} -n ${namespace} -o yaml > "${output_dir}/${resource_type}-${resource}.yaml"
    done
}

# Fonction pour sauvegarder les données persistantes
backup_persistent_volumes() {
    local namespace=$1
    local output_dir="${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}/${namespace}/data"

    mkdir -p "${output_dir}"

    echo -e "${GREEN}[INFO]${NC} Sauvegarde des données persistantes dans le namespace ${namespace}..."

    # Récupération des noms de PVC
    local pvcs=$(kubectl get pvc -n ${namespace} -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "${pvcs}" ]]; then
        echo -e "${YELLOW}[WARNING]${NC} Aucun PVC trouvé dans le namespace ${namespace}"
        return
    fi

    # Sauvegarde de chaque PVC
    for pvc in ${pvcs}; do
        echo -e "${GREEN}[INFO]${NC} Sauvegarde du PVC ${pvc} dans le namespace ${namespace}..."

        # Création d'un pod temporaire pour la sauvegarde
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: backup-${pvc}
  namespace: ${namespace}
spec:
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: ${pvc}
  - name: backup
    emptyDir: {}
  containers:
  - name: backup
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
    - name: backup
      mountPath: /backup
EOF

        # Attente que le pod soit prêt
        echo -e "${GREEN}[INFO]${NC} Attente que le pod de sauvegarde soit prêt..."
        kubectl wait --for=condition=Ready pod/backup-${pvc} -n ${namespace} --timeout=60s

        # Création de l'archive
        echo -e "${GREEN}[INFO]${NC} Création de l'archive pour le PVC ${pvc}..."
        kubectl exec -n ${namespace} backup-${pvc} -- tar -czf /backup/${pvc}.tar.gz -C /data .

        # Copie de l'archive
        echo -e "${GREEN}[INFO]${NC} Copie de l'archive pour le PVC ${pvc}..."
        kubectl cp ${namespace}/backup-${pvc}:/backup/${pvc}.tar.gz "${output_dir}/${pvc}.tar.gz"

        # Suppression du pod temporaire
        echo -e "${GREEN}[INFO]${NC} Suppression du pod temporaire..."
        kubectl delete pod backup-${pvc} -n ${namespace}
    done
}

# Fonction pour restaurer les ressources Kubernetes
restore_kubernetes_resources() {
    local backup_path="${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}"

    if [[ ! -d "${backup_path}" ]]; then
        echo -e "${RED}[ERROR]${NC} Sauvegarde ${BACKUP_NAME} non trouvée dans ${BACKUP_DIR}/${ENVIRONMENT}"
        exit 1
    fi

    echo -e "${GREEN}[INFO]${NC} Restauration des ressources Kubernetes depuis ${backup_path}..."

    # Parcours des namespaces
    for namespace_dir in "${backup_path}"/*; do
        if [[ ! -d "${namespace_dir}" ]]; then
            continue
        fi

        local namespace=$(basename "${namespace_dir}")

        echo -e "${GREEN}[INFO]${NC} Restauration des ressources dans le namespace ${namespace}..."

        # Création du namespace s'il n'existe pas
        kubectl create namespace ${namespace} --dry-run=client -o yaml | kubectl apply -f -

        # Restauration des ressources
        for resource_file in "${namespace_dir}"/*.yaml; do
            if [[ ! -f "${resource_file}" ]]; then
                continue
            fi

            echo -e "${GREEN}[INFO]${NC} Restauration de $(basename ${resource_file})..."
            kubectl apply -f "${resource_file}"
        done
    done
}

# Fonction pour restaurer les données persistantes
restore_persistent_volumes() {
    local backup_path="${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}"

    if [[ ! -d "${backup_path}" ]]; then
        echo -e "${RED}[ERROR]${NC} Sauvegarde ${BACKUP_NAME} non trouvée dans ${BACKUP_DIR}/${ENVIRONMENT}"
        exit 1
    fi

    echo -e "${GREEN}[INFO]${NC} Restauration des données persistantes depuis ${backup_path}..."

    # Parcours des namespaces
    for namespace_dir in "${backup_path}"/*; do
        if [[ ! -d "${namespace_dir}" ]]; then
            continue
        fi

        local namespace=$(basename "${namespace_dir}")
        local data_dir="${namespace_dir}/data"

        if [[ ! -d "${data_dir}" ]]; then
            echo -e "${YELLOW}[WARNING]${NC} Aucune donnée persistante trouvée pour le namespace ${namespace}"
            continue
        fi

        echo -e "${GREEN}[INFO]${NC} Restauration des données persistantes dans le namespace ${namespace}..."

        # Restauration des PVC
        for data_file in "${data_dir}"/*.tar.gz; do
            if [[ ! -f "${data_file}" ]]; then
                continue
            fi

            local pvc=$(basename "${data_file}" .tar.gz)

            echo -e "${GREEN}[INFO]${NC} Restauration du PVC ${pvc} dans le namespace ${namespace}..."

            # Vérification que le PVC existe
            if ! kubectl get pvc ${pvc} -n ${namespace} &>/dev/null; then
                echo -e "${YELLOW}[WARNING]${NC} Le PVC ${pvc} n'existe pas dans le namespace ${namespace}"
                continue
            fi

            # Création d'un pod temporaire pour la restauration
            cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: restore-${pvc}
  namespace: ${namespace}
spec:
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: ${pvc}
  - name: backup
    emptyDir: {}
  containers:
  - name: restore
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
    - name: backup
      mountPath: /backup
EOF

            # Attente que le pod soit prêt
            echo -e "${GREEN}[INFO]${NC} Attente que le pod de restauration soit prêt..."
            kubectl wait --for=condition=Ready pod/restore-${pvc} -n ${namespace} --timeout=60s

            # Copie de l'archive
            echo -e "${GREEN}[INFO]${NC} Copie de l'archive pour le PVC ${pvc}..."
            kubectl cp "${data_file}" ${namespace}/restore-${pvc}:/backup/${pvc}.tar.gz

            # Extraction de l'archive
            echo -e "${GREEN}[INFO]${NC} Extraction de l'archive pour le PVC ${pvc}..."
            kubectl exec -n ${namespace} restore-${pvc} -- sh -c "rm -rf /data/* && tar -xzf /backup/${pvc}.tar.gz -C /data"

            # Suppression du pod temporaire
            echo -e "${GREEN}[INFO]${NC} Suppression du pod temporaire..."
            kubectl delete pod restore-${pvc} -n ${namespace}
        done
    done
}

# Exécution de l'action demandée
case "${ACTION}" in
    backup)
        echo -e "${GREEN}[INFO]${NC} Démarrage de la sauvegarde pour l'environnement ${ENVIRONMENT}..."

        # Liste des namespaces à sauvegarder
        NAMESPACES=(${LIONS_BACKUP_NAMESPACES:-
            "postgres-${ENVIRONMENT}"
            "pgadmin-${ENVIRONMENT}"
            "gitea-${ENVIRONMENT}"
            "keycloak-${ENVIRONMENT}"
            "ollama-${ENVIRONMENT}"
            "monitoring"
            "cert-manager"
            "kubernetes-dashboard"
            "lions-infrastructure"
            "development"
        })

        # Sauvegarde des ressources dans chaque namespace
        for namespace in "${NAMESPACES[@]}"; do
            if kubectl get namespace ${namespace} &>/dev/null; then
                # Sauvegarde des différents types de ressources
                backup_kubernetes_resources ${namespace} "configmap"
                backup_kubernetes_resources ${namespace} "secret"
                backup_kubernetes_resources ${namespace} "deployment"
                backup_kubernetes_resources ${namespace} "statefulset"
                backup_kubernetes_resources ${namespace} "service"
                backup_kubernetes_resources ${namespace} "ingress"
                backup_kubernetes_resources ${namespace} "pvc"

                # Sauvegarde des données persistantes
                backup_persistent_volumes ${namespace}
            else
                echo -e "${YELLOW}[WARNING]${NC} Le namespace ${namespace} n'existe pas, ignoré"
            fi
        done

        # Sauvegarde des ressources cluster-wide
        echo -e "${GREEN}[INFO]${NC} Sauvegarde des ressources cluster-wide..."
        mkdir -p "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}/cluster-wide"

        # Sauvegarde des StorageClasses
        kubectl get storageclass -o yaml > "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}/cluster-wide/storageclasses.yaml"

        # Sauvegarde des ClusterRoles et ClusterRoleBindings
        kubectl get clusterrole -o yaml > "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}/cluster-wide/clusterroles.yaml"
        kubectl get clusterrolebinding -o yaml > "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}/cluster-wide/clusterrolebindings.yaml"

        # Sauvegarde des CRDs
        kubectl get crd -o yaml > "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}/cluster-wide/crds.yaml"

        # Compression de la sauvegarde
        echo -e "${GREEN}[INFO]${NC} Compression de la sauvegarde..."
        tar -czf "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}.tar.gz" -C "${BACKUP_DIR}/${ENVIRONMENT}" "${BACKUP_NAME}"

        # Nettoyage des fichiers temporaires
        rm -rf "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}"

        # Rotation des sauvegardes
        if [[ "${LIONS_BACKUP_ROTATION_ENABLED:-true}" == "true" ]]; then
            echo -e "${GREEN}[INFO]${NC} Rotation des sauvegardes..."

            # Suppression des sauvegardes plus anciennes que X jours
            find "${BACKUP_DIR}/${ENVIRONMENT}" -name "*.tar.gz" -type f -mtime +${BACKUP_RETENTION_DAYS} -delete || echo -e "${YELLOW}[WARNING]${NC} Échec de la rotation des sauvegardes"

            echo -e "${GREEN}[INFO]${NC} Rotation des sauvegardes terminée"
        fi

        # Création d'un fichier de métadonnées
        echo -e "${GREEN}[INFO]${NC} Création du fichier de métadonnées..."
        cat > "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}.json" << EOF
{
  "backup_name": "${BACKUP_NAME}",
  "backup_date": "$(date -Iseconds)",
  "environment": "${ENVIRONMENT}",
  "backup_size": "$(du -h "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}.tar.gz" | awk '{print $1}')",
  "kubernetes_version": "$(kubectl version --short | grep Server | awk '{print $3}')",
  "namespaces": [$(kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{", "}{end}' | sed 's/, $//')],
  "created_by": "${USER:-unknown}"
}
EOF

        echo -e "${GREEN}[SUCCESS]${NC} Sauvegarde terminée avec succès: ${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}.tar.gz"
        echo -e "${GREEN}[INFO]${NC} Taille de la sauvegarde: $(du -h "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}.tar.gz" | awk '{print $1}')"
        ;;

    restore)
        echo -e "${GREEN}[INFO]${NC} Démarrage de la restauration pour l'environnement ${ENVIRONMENT} depuis la sauvegarde ${BACKUP_NAME}..."

        # Vérification que la sauvegarde existe
        if [[ ! -f "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}.tar.gz" ]]; then
            echo -e "${RED}[ERROR]${NC} Sauvegarde ${BACKUP_NAME} non trouvée dans ${BACKUP_DIR}/${ENVIRONMENT}"
            exit 1
        fi

        # Extraction de la sauvegarde
        echo -e "${GREEN}[INFO]${NC} Extraction de la sauvegarde..."
        mkdir -p "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}"
        tar -xzf "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}.tar.gz" -C "${BACKUP_DIR}/${ENVIRONMENT}"

        # Restauration des ressources cluster-wide
        echo -e "${GREEN}[INFO]${NC} Restauration des ressources cluster-wide..."

        # Restauration des StorageClasses
        kubectl apply -f "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}/cluster-wide/storageclasses.yaml"

        # Restauration des CRDs
        kubectl apply -f "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}/cluster-wide/crds.yaml"

        # Restauration des ClusterRoles et ClusterRoleBindings
        kubectl apply -f "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}/cluster-wide/clusterroles.yaml"
        kubectl apply -f "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}/cluster-wide/clusterrolebindings.yaml"

        # Restauration des ressources par namespace
        restore_kubernetes_resources

        # Restauration des données persistantes
        restore_persistent_volumes

        # Nettoyage des fichiers temporaires
        rm -rf "${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}"

        echo -e "${GREEN}[SUCCESS]${NC} Restauration terminée avec succès depuis ${BACKUP_DIR}/${ENVIRONMENT}/${BACKUP_NAME}.tar.gz"

        # Vérification de l'état du cluster après restauration
        if [[ "${LIONS_POST_RESTORE_CHECK:-true}" == "true" ]]; then
            echo -e "${GREEN}[INFO]${NC} Vérification de l'état du cluster après restauration..."

            # Vérification des pods
            echo -e "${GREEN}[INFO]${NC} Vérification des pods..."
            kubectl get pods --all-namespaces | grep -v "Running\|Completed" || echo -e "${GREEN}[SUCCESS]${NC} Tous les pods sont en état Running ou Completed"

            # Vérification des services
            echo -e "${GREEN}[INFO]${NC} Vérification des services..."
            kubectl get services --all-namespaces

            # Vérification des PVCs
            echo -e "${GREEN}[INFO]${NC} Vérification des PVCs..."
            kubectl get pvc --all-namespaces | grep -v "Bound" || echo -e "${GREEN}[SUCCESS]${NC} Tous les PVCs sont liés"
        fi
        ;;

    *)
        echo -e "${RED}[ERROR]${NC} Action non reconnue: ${ACTION}"
        echo -e "${YELLOW}[TIP]${NC} Actions disponibles: backup, restore"
        exit 1
        ;;
esac
