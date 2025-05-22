#!/bin/bash
# =============================================================================
# Titre: Script de restructuration du dépôt lions-infrastructure
# Description: Réorganise le dépôt selon le plan de restructuration pour améliorer la maintenabilité
# Auteur: Équipe LIONS Infrastructure
# Date de création: 2025-05-22
# Version: 2.0.0
# Usage: ./restructure-repository.sh [options]
# =============================================================================

# Strict mode
set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Répertoire racine du projet
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Fichier de log
LOG_DIR="${PROJECT_ROOT}/scripts/logs"
LOG_FILE="${LOG_DIR}/restructure-repository.log"

# Variables de configuration
BACKUP_DIR="${PROJECT_ROOT}/backup-$(date +%Y%m%d%H%M%S)"
DRY_RUN="false"
VERBOSE="false"

# =============================================================================
# Fonctions
# =============================================================================

# Fonction d'affichage de l'aide
show_help() {
    cat << EOF
Usage: $(basename "$0") [options]

Description:
    Réorganise le dépôt lions-infrastructure selon le plan de restructuration
    pour améliorer la maintenabilité.

Options:
    -h, --help              Affiche cette aide
    -v, --verbose           Mode verbeux
    -d, --dry-run           Mode simulation (n'effectue aucune action)
    -b, --backup-dir DIR    Spécifie le répertoire de sauvegarde (défaut: ${BACKUP_DIR})

Exemples:
    $(basename "$0") --dry-run
    $(basename "$0") --verbose --backup-dir /tmp/lions-backup
EOF
    exit 0
}

# Fonction de journalisation
log() {
    local level=$1
    local message=$2
    local color=$NC

    case $level in
        "INFO") color=$NC ;;
        "SUCCESS") color=$GREEN ;;
        "WARNING") color=$YELLOW ;;
        "ERROR") color=$RED ;;
        "DEBUG") 
            if [[ "${VERBOSE}" != "true" ]]; then
                return
            fi
            color=$BLUE 
            ;;
    esac

    # Création du répertoire de logs si nécessaire
    mkdir -p "${LOG_DIR}"

    # Format de date pour les logs
    local date_format=$(date '+%Y-%m-%d %H:%M:%S')

    # Affichage dans la console
    echo -e "${color}[${date_format}] [${level}] ${message}${NC}"

    # Écriture dans le fichier de log
    echo "[${date_format}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Fonction de nettoyage à la sortie
cleanup() {
    local exit_code=$?

    # Actions de nettoyage
    log "INFO" "Nettoyage des ressources temporaires..."

    # Suppression des fichiers temporaires
    rm -f /tmp/restructure-temp-*

    # Message de fin
    if [ ${exit_code} -eq 0 ]; then
        log "SUCCESS" "Script terminé avec succès"
    else
        log "ERROR" "Script terminé avec des erreurs (code: ${exit_code})"
    fi

    exit ${exit_code}
}

# Fonction de gestion des erreurs
handle_error() {
    local line=$1
    local command=$2
    local code=$3
    log "ERROR" "Erreur à la ligne ${line} (commande: '${command}', code: ${code})"
}

# Fonction de sauvegarde du dépôt
backup_repository() {
    log "INFO" "Sauvegarde du dépôt dans ${BACKUP_DIR}..."

    if [ "${DRY_RUN}" = "true" ]; then
        log "DEBUG" "Simulation: mkdir -p ${BACKUP_DIR}"
        log "DEBUG" "Simulation: cp -r --exclude=\"$(basename ${BACKUP_DIR})\" ${PROJECT_ROOT}/* ${BACKUP_DIR}/"
    else
        mkdir -p "${BACKUP_DIR}"
        cp -r --exclude="$(basename ${BACKUP_DIR})" "${PROJECT_ROOT}"/* "${BACKUP_DIR}/"
        log "SUCCESS" "Sauvegarde terminée"
    fi
}

# Fonction de création de répertoire
create_directory() {
    local dir=$1
    local description=$2

    log "DEBUG" "Création du répertoire: ${dir} (${description})"

    if [ "${DRY_RUN}" = "true" ]; then
        log "DEBUG" "Simulation: mkdir -p ${PROJECT_ROOT}/${dir}"
    else
        mkdir -p "${PROJECT_ROOT}/${dir}"
    fi
}

# Fonction de création de README
create_readme() {
    local dir=$1
    local title=$2
    local description=$3

    log "DEBUG" "Création du README pour: ${dir}"

    if [ "${DRY_RUN}" = "true" ]; then
        log "DEBUG" "Simulation: Création de ${PROJECT_ROOT}/${dir}/README.md"
    else
        cat > "${PROJECT_ROOT}/${dir}/README.md" << EOF
# ${title}

## Description

${description}

## Structure

\`\`\`
${dir}/
$(find "${PROJECT_ROOT}/${dir}" -type d -mindepth 1 -maxdepth 1 2>/dev/null | sort | sed 's|'"${PROJECT_ROOT}/${dir}/"'|├── |' || echo "# Aucun sous-répertoire trouvé")
\`\`\`

## Utilisation

Consultez la documentation spécifique à chaque composant pour plus de détails.
EOF
    fi
}

# Fonction de déplacement de fichiers
move_files() {
    local source_pattern=$1
    local destination=$2

    log "DEBUG" "Déplacement des fichiers: ${source_pattern} -> ${destination}"

    if [ "${DRY_RUN}" = "true" ]; then
        log "DEBUG" "Simulation: mkdir -p ${PROJECT_ROOT}/${destination}"
        log "DEBUG" "Simulation: mv ${PROJECT_ROOT}/${source_pattern} ${PROJECT_ROOT}/${destination}/"
    else
        mkdir -p "${PROJECT_ROOT}/${destination}"

        # Utilisation de find pour gérer les wildcards
        find "${PROJECT_ROOT}" -path "${PROJECT_ROOT}/${source_pattern}" -type f -print0 | 
        while IFS= read -r -d '' file; do
            mv "$file" "${PROJECT_ROOT}/${destination}/"
        done
    fi
}

# Fonction de restructuration des répertoires principaux
restructure_main_directories() {
    log "INFO" "Restructuration des répertoires principaux..."

    # Création des nouveaux répertoires
    create_directory "environments" "Configurations spécifiques aux environnements"
    create_directory "tests" "Tests automatisés"
    create_directory "tools" "Outils de développement et utilitaires"

    # Création des READMEs
    create_readme "environments" "Environnements" "Ce répertoire contient les configurations spécifiques à chaque environnement (development, staging, production)."
    create_readme "tests" "Tests" "Ce répertoire contient les tests automatisés pour valider le fonctionnement de l'infrastructure."
    create_readme "tools" "Outils" "Ce répertoire contient les outils de développement et utilitaires pour faciliter le travail avec l'infrastructure."

    log "SUCCESS" "Restructuration des répertoires principaux terminée"
}

# Fonction de restructuration du répertoire ansible
restructure_ansible() {
    log "INFO" "Restructuration du répertoire ansible..."

    # Création des répertoires principaux
    create_directory "ansible/playbooks/infrastructure" "Playbooks d'infrastructure"
    create_directory "ansible/playbooks/applications" "Playbooks d'applications"
    create_directory "ansible/playbooks/maintenance" "Playbooks de maintenance"
    create_directory "ansible/playbooks/security" "Playbooks de sécurité"
    create_directory "ansible/playbooks/networking" "Playbooks de réseau"
    create_directory "ansible/playbooks/monitoring" "Playbooks de monitoring"
    create_directory "ansible/playbooks/backup" "Playbooks de sauvegarde"

    # Création des sous-répertoires de playbooks plus spécifiques
    create_directory "ansible/playbooks/infrastructure/initialization" "Playbooks d'initialisation de l'infrastructure"
    create_directory "ansible/playbooks/infrastructure/kubernetes" "Playbooks de déploiement Kubernetes"
    create_directory "ansible/playbooks/infrastructure/storage" "Playbooks de gestion du stockage"
    create_directory "ansible/playbooks/infrastructure/compute" "Playbooks de gestion des ressources de calcul"

    create_directory "ansible/playbooks/applications/frontend" "Playbooks pour les applications frontend"
    create_directory "ansible/playbooks/applications/backend" "Playbooks pour les applications backend"
    create_directory "ansible/playbooks/applications/database" "Playbooks pour les bases de données"
    create_directory "ansible/playbooks/applications/microservices" "Playbooks pour les microservices"

    create_directory "ansible/playbooks/maintenance/updates" "Playbooks de mise à jour"
    create_directory "ansible/playbooks/maintenance/cleanup" "Playbooks de nettoyage"
    create_directory "ansible/playbooks/maintenance/health-checks" "Playbooks de vérification de santé"

    create_directory "ansible/playbooks/security/hardening" "Playbooks de renforcement de la sécurité"
    create_directory "ansible/playbooks/security/compliance" "Playbooks de conformité"
    create_directory "ansible/playbooks/security/certificates" "Playbooks de gestion des certificats"
    create_directory "ansible/playbooks/security/authentication" "Playbooks de gestion de l'authentification"

    # Création des répertoires de rôles principaux
    create_directory "ansible/roles/database" "Rôles liés aux bases de données"
    create_directory "ansible/roles/web" "Rôles liés aux applications web"
    create_directory "ansible/roles/tools" "Rôles liés aux outils"
    create_directory "ansible/roles/monitoring" "Rôles liés au monitoring"
    create_directory "ansible/roles/security" "Rôles liés à la sécurité"
    create_directory "ansible/roles/networking" "Rôles liés au réseau"
    create_directory "ansible/roles/storage" "Rôles liés au stockage"
    create_directory "ansible/roles/common" "Rôles communs réutilisables"

    # Création des sous-répertoires de rôles plus spécifiques
    create_directory "ansible/roles/database/relational" "Rôles pour les bases de données relationnelles"
    create_directory "ansible/roles/database/nosql" "Rôles pour les bases de données NoSQL"
    create_directory "ansible/roles/database/caching" "Rôles pour les systèmes de cache"

    create_directory "ansible/roles/web/frontend" "Rôles pour les frameworks frontend"
    create_directory "ansible/roles/web/backend" "Rôles pour les frameworks backend"
    create_directory "ansible/roles/web/api" "Rôles pour les API"

    create_directory "ansible/roles/tools/ci-cd" "Rôles pour les outils CI/CD"
    create_directory "ansible/roles/tools/development" "Rôles pour les outils de développement"
    create_directory "ansible/roles/tools/collaboration" "Rôles pour les outils de collaboration"

    create_directory "ansible/roles/monitoring/metrics" "Rôles pour la collecte de métriques"
    create_directory "ansible/roles/monitoring/logging" "Rôles pour la gestion des logs"
    create_directory "ansible/roles/monitoring/alerting" "Rôles pour les alertes"
    create_directory "ansible/roles/monitoring/dashboards" "Rôles pour les tableaux de bord"

    # Création des répertoires pour les modules et plugins personnalisés
    create_directory "ansible/modules/custom" "Modules Ansible personnalisés"
    create_directory "ansible/filter_plugins/custom" "Plugins de filtres personnalisés"
    create_directory "ansible/callback_plugins/custom" "Plugins de callback personnalisés"
    create_directory "ansible/lookup_plugins/custom" "Plugins de lookup personnalisés"

    # Création d'un répertoire pour les templates réutilisables
    create_directory "ansible/templates/common" "Templates communs réutilisables"
    create_directory "ansible/templates/applications" "Templates pour les applications"
    create_directory "ansible/templates/infrastructure" "Templates pour l'infrastructure"
    create_directory "ansible/templates/monitoring" "Templates pour le monitoring"

    # Création d'un répertoire pour les variables globales
    create_directory "ansible/vars/global" "Variables globales"
    create_directory "ansible/vars/applications" "Variables pour les applications"
    create_directory "ansible/vars/infrastructure" "Variables pour l'infrastructure"

    # Déplacement des rôles
    if [ "${DRY_RUN}" = "true" ]; then
        log "DEBUG" "Simulation: Déplacement des rôles de base de données"
        log "DEBUG" "Simulation: Déplacement des rôles d'applications web"
        log "DEBUG" "Simulation: Déplacement des rôles d'outils"
    else
        # Bases de données
        if [ -d "${PROJECT_ROOT}/ansible/roles/postgres" ]; then
            mv "${PROJECT_ROOT}/ansible/roles/postgres" "${PROJECT_ROOT}/ansible/roles/database/relational/"
        fi
        if [ -d "${PROJECT_ROOT}/ansible/roles/redis" ]; then
            mv "${PROJECT_ROOT}/ansible/roles/redis" "${PROJECT_ROOT}/ansible/roles/database/caching/"
        fi

        # Applications web
        if [ -d "${PROJECT_ROOT}/ansible/roles/primefaces" ]; then
            mv "${PROJECT_ROOT}/ansible/roles/primefaces" "${PROJECT_ROOT}/ansible/roles/web/frontend/"
        fi
        if [ -d "${PROJECT_ROOT}/ansible/roles/primereact" ]; then
            mv "${PROJECT_ROOT}/ansible/roles/primereact" "${PROJECT_ROOT}/ansible/roles/web/frontend/"
        fi
        if [ -d "${PROJECT_ROOT}/ansible/roles/quarkus" ]; then
            mv "${PROJECT_ROOT}/ansible/roles/quarkus" "${PROJECT_ROOT}/ansible/roles/web/backend/"
        fi

        # Outils
        if [ -d "${PROJECT_ROOT}/ansible/roles/gitea" ]; then
            mv "${PROJECT_ROOT}/ansible/roles/gitea" "${PROJECT_ROOT}/ansible/roles/tools/ci-cd/"
        fi
        if [ -d "${PROJECT_ROOT}/ansible/roles/keycloak" ]; then
            mv "${PROJECT_ROOT}/ansible/roles/keycloak" "${PROJECT_ROOT}/ansible/roles/security/"
        fi
        if [ -d "${PROJECT_ROOT}/ansible/roles/registry" ]; then
            mv "${PROJECT_ROOT}/ansible/roles/registry" "${PROJECT_ROOT}/ansible/roles/tools/ci-cd/"
        fi

        # Monitoring
        if [ -d "${PROJECT_ROOT}/ansible/roles/pgadmin" ]; then
            mv "${PROJECT_ROOT}/ansible/roles/pgadmin" "${PROJECT_ROOT}/ansible/roles/monitoring/dashboards/"
        fi

        # Notification
        if [ -d "${PROJECT_ROOT}/ansible/roles/notification-service" ]; then
            mv "${PROJECT_ROOT}/ansible/roles/notification-service" "${PROJECT_ROOT}/ansible/roles/web/api/"
        fi
    fi

    # Déplacement des playbooks
    if [ "${DRY_RUN}" = "true" ]; then
        log "DEBUG" "Simulation: Déplacement des playbooks d'infrastructure"
        log "DEBUG" "Simulation: Déplacement des playbooks d'applications"
        log "DEBUG" "Simulation: Déplacement des playbooks de maintenance"
    else
        # Infrastructure
        if [ -f "${PROJECT_ROOT}/ansible/playbooks/init-vps.yml" ]; then
            mv "${PROJECT_ROOT}/ansible/playbooks/init-vps.yml" "${PROJECT_ROOT}/ansible/playbooks/infrastructure/initialization/"
        fi
        if [ -f "${PROJECT_ROOT}/ansible/playbooks/install-k3s.yml" ]; then
            mv "${PROJECT_ROOT}/ansible/playbooks/install-k3s.yml" "${PROJECT_ROOT}/ansible/playbooks/infrastructure/kubernetes/"
        fi
        if [ -f "${PROJECT_ROOT}/ansible/playbooks/deploy-infrastructure-services.yml" ]; then
            mv "${PROJECT_ROOT}/ansible/playbooks/deploy-infrastructure-services.yml" "${PROJECT_ROOT}/ansible/playbooks/infrastructure/"
        fi

        # Applications
        if [ -f "${PROJECT_ROOT}/ansible/playbooks/deploy-application.yml" ]; then
            mv "${PROJECT_ROOT}/ansible/playbooks/deploy-application.yml" "${PROJECT_ROOT}/ansible/playbooks/applications/"
        fi
        if [ -f "${PROJECT_ROOT}/ansible/playbooks/deploy-application-services.yml" ]; then
            mv "${PROJECT_ROOT}/ansible/playbooks/deploy-application-services.yml" "${PROJECT_ROOT}/ansible/playbooks/applications/"
        fi

        # Maintenance
        if [ -f "${PROJECT_ROOT}/ansible/playbooks/backup.yml" ]; then
            mv "${PROJECT_ROOT}/ansible/playbooks/backup.yml" "${PROJECT_ROOT}/ansible/playbooks/backup/"
        fi
        if [ -f "${PROJECT_ROOT}/ansible/playbooks/restore.yml" ]; then
            mv "${PROJECT_ROOT}/ansible/playbooks/restore.yml" "${PROJECT_ROOT}/ansible/playbooks/backup/"
        fi
        if [ -f "${PROJECT_ROOT}/ansible/playbooks/maintenance.yml" ]; then
            mv "${PROJECT_ROOT}/ansible/playbooks/maintenance.yml" "${PROJECT_ROOT}/ansible/playbooks/maintenance/"
        fi
    fi

    # Création des READMEs pour les répertoires principaux
    create_readme "ansible/playbooks" "Playbooks Ansible" "Ce répertoire contient tous les playbooks Ansible organisés par catégorie."
    create_readme "ansible/roles" "Rôles Ansible" "Ce répertoire contient tous les rôles Ansible organisés par catégorie."
    create_readme "ansible/modules" "Modules Ansible" "Ce répertoire contient les modules Ansible personnalisés."
    create_readme "ansible/filter_plugins" "Plugins de filtres Ansible" "Ce répertoire contient les plugins de filtres Ansible personnalisés."
    create_readme "ansible/templates" "Templates Ansible" "Ce répertoire contient les templates Jinja2 réutilisables pour Ansible."
    create_readme "ansible/vars" "Variables Ansible" "Ce répertoire contient les fichiers de variables Ansible globales."

    # Création des READMEs pour les sous-répertoires de playbooks
    create_readme "ansible/playbooks/infrastructure" "Playbooks d'infrastructure" "Ce répertoire contient les playbooks Ansible pour déployer et configurer l'infrastructure de base."
    create_readme "ansible/playbooks/applications" "Playbooks d'applications" "Ce répertoire contient les playbooks Ansible pour déployer et configurer les applications."
    create_readme "ansible/playbooks/maintenance" "Playbooks de maintenance" "Ce répertoire contient les playbooks Ansible pour la maintenance de l'infrastructure."
    create_readme "ansible/playbooks/security" "Playbooks de sécurité" "Ce répertoire contient les playbooks Ansible pour la sécurité de l'infrastructure."
    create_readme "ansible/playbooks/networking" "Playbooks de réseau" "Ce répertoire contient les playbooks Ansible pour la configuration réseau."
    create_readme "ansible/playbooks/monitoring" "Playbooks de monitoring" "Ce répertoire contient les playbooks Ansible pour le monitoring."
    create_readme "ansible/playbooks/backup" "Playbooks de sauvegarde" "Ce répertoire contient les playbooks Ansible pour les sauvegardes et restaurations."

    # Création des READMEs pour les sous-répertoires de rôles
    create_readme "ansible/roles/database" "Rôles de base de données" "Ce répertoire contient les rôles Ansible pour les bases de données."
    create_readme "ansible/roles/web" "Rôles d'applications web" "Ce répertoire contient les rôles Ansible pour les applications web."
    create_readme "ansible/roles/tools" "Rôles d'outils" "Ce répertoire contient les rôles Ansible pour les outils d'infrastructure."
    create_readme "ansible/roles/monitoring" "Rôles de monitoring" "Ce répertoire contient les rôles Ansible pour le monitoring de l'infrastructure."
    create_readme "ansible/roles/security" "Rôles de sécurité" "Ce répertoire contient les rôles Ansible pour la sécurité de l'infrastructure."
    create_readme "ansible/roles/networking" "Rôles de réseau" "Ce répertoire contient les rôles Ansible pour la configuration réseau."
    create_readme "ansible/roles/storage" "Rôles de stockage" "Ce répertoire contient les rôles Ansible pour la gestion du stockage."
    create_readme "ansible/roles/common" "Rôles communs" "Ce répertoire contient les rôles Ansible communs et réutilisables."

    # Création d'un fichier de métadonnées pour le répertoire ansible
    if [ "${DRY_RUN}" = "true" ]; then
        log "DEBUG" "Simulation: Création du fichier de métadonnées pour ansible"
    else
        cat > "${PROJECT_ROOT}/ansible/METADATA.md" << EOF
# Métadonnées du répertoire Ansible

## Version
2.0.0

## Description
Ce répertoire contient les playbooks, rôles et configurations Ansible pour déployer et gérer l'infrastructure LIONS.

## Structure
La structure de ce répertoire suit les meilleures pratiques Ansible avec une organisation fine et modulaire:

- **playbooks/**: Playbooks organisés par catégorie fonctionnelle
- **roles/**: Rôles organisés par type de service
- **modules/**: Modules personnalisés
- **filter_plugins/**: Plugins de filtres personnalisés
- **templates/**: Templates Jinja2 réutilisables
- **vars/**: Variables globales

## Conventions de nommage
- Playbooks: \`<action>-<cible>.yml\` (ex: deploy-application.yml)
- Rôles: Nom du service en minuscules (ex: postgres, keycloak)
- Variables: \`<préfixe>_<nom>\` (ex: db_user, app_version)

## Bonnes pratiques
- Utiliser des rôles pour la réutilisabilité
- Documenter chaque playbook et rôle
- Utiliser des tags pour l'exécution sélective
- Séparer les variables par environnement
EOF
    fi

    log "SUCCESS" "Restructuration du répertoire ansible terminée"
}

# Fonction de restructuration du répertoire applications
restructure_applications() {
    log "INFO" "Restructuration du répertoire applications..."

    # Création des nouveaux répertoires
    create_directory "applications/catalog/database" "Applications de base de données"
    create_directory "applications/catalog/web" "Applications web"
    create_directory "applications/catalog/tools" "Outils et utilitaires"
    create_directory "applications/examples" "Exemples d'applications"

    # Création des READMEs
    create_readme "applications/catalog/database" "Catalogue d'applications de base de données" "Ce répertoire contient le catalogue des applications de base de données disponibles."
    create_readme "applications/catalog/web" "Catalogue d'applications web" "Ce répertoire contient le catalogue des applications web disponibles."
    create_readme "applications/catalog/tools" "Catalogue d'outils et utilitaires" "Ce répertoire contient le catalogue des outils et utilitaires disponibles."
    create_readme "applications/examples" "Exemples d'applications" "Ce répertoire contient des exemples d'applications pour illustrer les bonnes pratiques."

    log "SUCCESS" "Restructuration du répertoire applications terminée"
}

# Fonction de restructuration du répertoire kubernetes
restructure_kubernetes() {
    log "INFO" "Restructuration du répertoire kubernetes..."

    # Création des répertoires principaux
    create_directory "kubernetes/components" "Composants réutilisables"
    create_directory "kubernetes/manifests" "Manifests Kubernetes bruts"
    create_directory "kubernetes/helm-charts" "Charts Helm"
    create_directory "kubernetes/kustomize" "Configurations Kustomize"
    create_directory "kubernetes/operators" "Opérateurs Kubernetes"
    create_directory "kubernetes/policies" "Politiques Kubernetes"
    create_directory "kubernetes/templates" "Templates de ressources"

    # Création des sous-répertoires pour les composants
    create_directory "kubernetes/components/databases" "Composants de bases de données"
    create_directory "kubernetes/components/databases/relational" "Bases de données relationnelles"
    create_directory "kubernetes/components/databases/nosql" "Bases de données NoSQL"
    create_directory "kubernetes/components/databases/caching" "Systèmes de cache"

    create_directory "kubernetes/components/ingress" "Composants d'ingress"
    create_directory "kubernetes/components/ingress/traefik" "Configuration Traefik"
    create_directory "kubernetes/components/ingress/nginx" "Configuration NGINX"
    create_directory "kubernetes/components/ingress/certificates" "Gestion des certificats"

    create_directory "kubernetes/components/monitoring" "Composants de monitoring"
    create_directory "kubernetes/components/monitoring/prometheus" "Configuration Prometheus"
    create_directory "kubernetes/components/monitoring/grafana" "Configuration Grafana"
    create_directory "kubernetes/components/monitoring/alertmanager" "Configuration AlertManager"
    create_directory "kubernetes/components/monitoring/loki" "Configuration Loki"

    create_directory "kubernetes/components/security" "Composants de sécurité"
    create_directory "kubernetes/components/security/authentication" "Authentification"
    create_directory "kubernetes/components/security/authorization" "Autorisation"
    create_directory "kubernetes/components/security/secrets" "Gestion des secrets"
    create_directory "kubernetes/components/security/policies" "Politiques de sécurité"

    create_directory "kubernetes/components/storage" "Composants de stockage"
    create_directory "kubernetes/components/storage/persistent-volumes" "Volumes persistants"
    create_directory "kubernetes/components/storage/storage-classes" "Classes de stockage"
    create_directory "kubernetes/components/storage/backup" "Solutions de sauvegarde"

    create_directory "kubernetes/components/networking" "Composants réseau"
    create_directory "kubernetes/components/networking/cni" "Plugins CNI"
    create_directory "kubernetes/components/networking/dns" "Configuration DNS"
    create_directory "kubernetes/components/networking/load-balancing" "Équilibrage de charge"
    create_directory "kubernetes/components/networking/service-mesh" "Service Mesh"

    create_directory "kubernetes/components/applications" "Composants d'applications"
    create_directory "kubernetes/components/applications/frontend" "Applications frontend"
    create_directory "kubernetes/components/applications/backend" "Applications backend"
    create_directory "kubernetes/components/applications/microservices" "Microservices"

    # Création des sous-répertoires pour les manifests
    create_directory "kubernetes/manifests/namespaces" "Définitions de namespaces"
    create_directory "kubernetes/manifests/deployments" "Déploiements"
    create_directory "kubernetes/manifests/services" "Services"
    create_directory "kubernetes/manifests/configmaps" "ConfigMaps"
    create_directory "kubernetes/manifests/secrets" "Secrets"
    create_directory "kubernetes/manifests/rbac" "RBAC"

    # Création des sous-répertoires pour les charts Helm
    create_directory "kubernetes/helm-charts/infrastructure" "Charts pour l'infrastructure"
    create_directory "kubernetes/helm-charts/applications" "Charts pour les applications"
    create_directory "kubernetes/helm-charts/monitoring" "Charts pour le monitoring"
    create_directory "kubernetes/helm-charts/security" "Charts pour la sécurité"
    create_directory "kubernetes/helm-charts/templates" "Templates de charts"
    create_directory "kubernetes/helm-charts/values" "Fichiers de valeurs par environnement"

    # Création des sous-répertoires pour Kustomize
    create_directory "kubernetes/kustomize/base" "Configurations de base"
    create_directory "kubernetes/kustomize/overlays/development" "Overlays pour l'environnement de développement"
    create_directory "kubernetes/kustomize/overlays/staging" "Overlays pour l'environnement de staging"
    create_directory "kubernetes/kustomize/overlays/production" "Overlays pour l'environnement de production"
    create_directory "kubernetes/kustomize/components" "Composants Kustomize réutilisables"

    # Création des sous-répertoires pour les opérateurs
    create_directory "kubernetes/operators/custom" "Opérateurs personnalisés"
    create_directory "kubernetes/operators/third-party" "Opérateurs tiers"
    create_directory "kubernetes/operators/crds" "Définitions de ressources personnalisées"

    # Création des sous-répertoires pour les politiques
    create_directory "kubernetes/policies/network" "Politiques réseau"
    create_directory "kubernetes/policies/pod-security" "Politiques de sécurité des pods"
    create_directory "kubernetes/policies/resource-quotas" "Quotas de ressources"
    create_directory "kubernetes/policies/limit-ranges" "Limites de ressources"

    # Création des sous-répertoires pour les templates
    create_directory "kubernetes/templates/applications" "Templates d'applications"
    create_directory "kubernetes/templates/microservices" "Templates de microservices"
    create_directory "kubernetes/templates/databases" "Templates de bases de données"
    create_directory "kubernetes/templates/common" "Templates communs"

    # Création des READMEs pour les répertoires principaux
    create_readme "kubernetes/components" "Composants Kubernetes réutilisables" "Ce répertoire contient des composants Kubernetes réutilisables pour différentes parties de l'infrastructure."
    create_readme "kubernetes/manifests" "Manifests Kubernetes" "Ce répertoire contient les manifests Kubernetes bruts pour les différentes ressources."
    create_readme "kubernetes/helm-charts" "Charts Helm" "Ce répertoire contient les charts Helm pour déployer les applications et l'infrastructure."
    create_readme "kubernetes/kustomize" "Configurations Kustomize" "Ce répertoire contient les configurations Kustomize pour personnaliser les déploiements par environnement."
    create_readme "kubernetes/operators" "Opérateurs Kubernetes" "Ce répertoire contient les opérateurs Kubernetes personnalisés et tiers."
    create_readme "kubernetes/policies" "Politiques Kubernetes" "Ce répertoire contient les politiques Kubernetes pour la sécurité et la gestion des ressources."
    create_readme "kubernetes/templates" "Templates de ressources" "Ce répertoire contient les templates pour générer des ressources Kubernetes."

    # Création des READMEs pour les sous-répertoires de composants
    create_readme "kubernetes/components/databases" "Composants de bases de données" "Ce répertoire contient des composants Kubernetes pour les bases de données."
    create_readme "kubernetes/components/ingress" "Composants d'ingress" "Ce répertoire contient des composants Kubernetes pour les ingress."
    create_readme "kubernetes/components/monitoring" "Composants de monitoring" "Ce répertoire contient des composants Kubernetes pour le monitoring."
    create_readme "kubernetes/components/security" "Composants de sécurité" "Ce répertoire contient des composants Kubernetes pour la sécurité."
    create_readme "kubernetes/components/storage" "Composants de stockage" "Ce répertoire contient des composants Kubernetes pour le stockage."
    create_readme "kubernetes/components/networking" "Composants réseau" "Ce répertoire contient des composants Kubernetes pour le réseau."
    create_readme "kubernetes/components/applications" "Composants d'applications" "Ce répertoire contient des composants Kubernetes pour les applications."

    # Création d'un fichier de métadonnées pour le répertoire kubernetes
    if [ "${DRY_RUN}" = "true" ]; then
        log "DEBUG" "Simulation: Création du fichier de métadonnées pour kubernetes"
    else
        cat > "${PROJECT_ROOT}/kubernetes/METADATA.md" << EOF
# Métadonnées du répertoire Kubernetes

## Version
2.0.0

## Description
Ce répertoire contient les configurations Kubernetes pour déployer et gérer l'infrastructure LIONS.

## Structure
La structure de ce répertoire suit les meilleures pratiques Kubernetes avec une organisation fine et modulaire:

- **components/**: Composants réutilisables organisés par type
- **manifests/**: Manifests Kubernetes bruts
- **helm-charts/**: Charts Helm pour les déploiements
- **kustomize/**: Configurations Kustomize pour la personnalisation par environnement
- **operators/**: Opérateurs Kubernetes personnalisés et tiers
- **policies/**: Politiques Kubernetes pour la sécurité et la gestion des ressources
- **templates/**: Templates pour générer des ressources Kubernetes

## Conventions de nommage
- Ressources: \`<application>-<type>-<environnement>.yaml\` (ex: postgres-deployment-prod.yaml)
- Namespaces: Utiliser des namespaces pour isoler les environnements et les applications
- Labels: Toujours inclure \`app\`, \`component\`, \`environment\` comme labels

## Bonnes pratiques
- Utiliser Kustomize pour la personnalisation par environnement
- Définir des limites de ressources pour tous les conteneurs
- Appliquer des politiques de sécurité à tous les pods
- Utiliser des ConfigMaps et Secrets pour la configuration
- Documenter chaque composant avec un README
EOF
    fi

    # Création d'un fichier de conventions pour les ressources Kubernetes
    if [ "${DRY_RUN}" = "true" ]; then
        log "DEBUG" "Simulation: Création du fichier de conventions pour kubernetes"
    else
        cat > "${PROJECT_ROOT}/kubernetes/CONVENTIONS.md" << EOF
# Conventions pour les ressources Kubernetes

## Namespaces
- \`infrastructure\`: Services d'infrastructure (monitoring, logging, etc.)
- \`applications\`: Applications métier
- \`security\`: Services de sécurité
- \`database\`: Services de bases de données
- \`tools\`: Outils de développement et d'administration

## Labels
Chaque ressource doit avoir au minimum les labels suivants:
- \`app\`: Nom de l'application
- \`component\`: Composant de l'application (frontend, backend, database, etc.)
- \`environment\`: Environnement (development, staging, production)
- \`managed-by\`: Outil de gestion (helm, kustomize, manual)
- \`version\`: Version de l'application

## Annotations
Utiliser les annotations pour:
- Documentation: \`description\`, \`owner\`, \`documentation-url\`
- Configuration: \`config-checksum\`, \`last-applied-configuration\`
- Monitoring: \`prometheus.io/scrape\`, \`prometheus.io/port\`

## Ressources
- Toujours définir des limites et requêtes de ressources
- Utiliser des HorizontalPodAutoscalers pour les applications avec charge variable
- Définir des liveness et readiness probes appropriées

## Sécurité
- Utiliser des ServiceAccounts dédiés avec RBAC minimal
- Appliquer des PodSecurityPolicies à tous les pods
- Utiliser des NetworkPolicies pour limiter les communications
- Stocker les secrets dans des Secrets Kubernetes ou un gestionnaire externe

## Stockage
- Utiliser des StorageClasses appropriées selon les besoins
- Définir des stratégies de sauvegarde pour les PersistentVolumes
- Utiliser des VolumeSnapshots pour les sauvegardes

## Déploiement
- Utiliser des stratégies de déploiement appropriées (RollingUpdate, Recreate)
- Définir des règles d'affinité pour optimiser le placement des pods
- Utiliser des PodDisruptionBudgets pour les services critiques
EOF
    fi

    log "SUCCESS" "Restructuration du répertoire kubernetes terminée"
}

# Fonction de restructuration du répertoire monitoring
restructure_monitoring() {
    log "INFO" "Restructuration du répertoire monitoring..."

    # Création des répertoires principaux
    create_directory "monitoring/alerts" "Configurations d'alertes"
    create_directory "monitoring/dashboards" "Tableaux de bord"
    create_directory "monitoring/exporters" "Exporters Prometheus"
    create_directory "monitoring/configs" "Fichiers de configuration"
    create_directory "monitoring/rules" "Règles de monitoring"
    create_directory "monitoring/scripts" "Scripts de monitoring"
    create_directory "monitoring/templates" "Templates réutilisables"
    create_directory "monitoring/documentation" "Documentation de monitoring"

    # Création des sous-répertoires pour les alertes
    create_directory "monitoring/alerts/infrastructure" "Alertes d'infrastructure"
    create_directory "monitoring/alerts/infrastructure/network" "Alertes réseau"
    create_directory "monitoring/alerts/infrastructure/compute" "Alertes de ressources de calcul"
    create_directory "monitoring/alerts/infrastructure/storage" "Alertes de stockage"
    create_directory "monitoring/alerts/infrastructure/kubernetes" "Alertes Kubernetes"

    create_directory "monitoring/alerts/applications" "Alertes d'applications"
    create_directory "monitoring/alerts/applications/frontend" "Alertes frontend"
    create_directory "monitoring/alerts/applications/backend" "Alertes backend"
    create_directory "monitoring/alerts/applications/database" "Alertes de bases de données"
    create_directory "monitoring/alerts/applications/microservices" "Alertes de microservices"

    create_directory "monitoring/alerts/security" "Alertes de sécurité"
    create_directory "monitoring/alerts/security/authentication" "Alertes d'authentification"
    create_directory "monitoring/alerts/security/authorization" "Alertes d'autorisation"
    create_directory "monitoring/alerts/security/vulnerabilities" "Alertes de vulnérabilités"

    create_directory "monitoring/alerts/business" "Alertes métier"
    create_directory "monitoring/alerts/business/kpis" "Alertes sur les KPIs"
    create_directory "monitoring/alerts/business/slas" "Alertes sur les SLAs"

    # Création des sous-répertoires pour les tableaux de bord
    create_directory "monitoring/dashboards/infrastructure" "Tableaux de bord d'infrastructure"
    create_directory "monitoring/dashboards/infrastructure/overview" "Vue d'ensemble de l'infrastructure"
    create_directory "monitoring/dashboards/infrastructure/kubernetes" "Tableaux de bord Kubernetes"
    create_directory "monitoring/dashboards/infrastructure/network" "Tableaux de bord réseau"
    create_directory "monitoring/dashboards/infrastructure/storage" "Tableaux de bord stockage"

    create_directory "monitoring/dashboards/applications" "Tableaux de bord d'applications"
    create_directory "monitoring/dashboards/applications/frontend" "Tableaux de bord frontend"
    create_directory "monitoring/dashboards/applications/backend" "Tableaux de bord backend"
    create_directory "monitoring/dashboards/applications/database" "Tableaux de bord bases de données"
    create_directory "monitoring/dashboards/applications/microservices" "Tableaux de bord microservices"

    create_directory "monitoring/dashboards/business" "Tableaux de bord métier"
    create_directory "monitoring/dashboards/business/kpis" "Tableaux de bord KPIs"
    create_directory "monitoring/dashboards/business/slas" "Tableaux de bord SLAs"
    create_directory "monitoring/dashboards/business/usage" "Tableaux de bord d'utilisation"

    create_directory "monitoring/dashboards/security" "Tableaux de bord de sécurité"
    create_directory "monitoring/dashboards/security/audit" "Tableaux de bord d'audit"
    create_directory "monitoring/dashboards/security/threats" "Tableaux de bord de menaces"

    # Création des sous-répertoires pour les exporters
    create_directory "monitoring/exporters/system" "Exporters système"
    create_directory "monitoring/exporters/database" "Exporters de bases de données"
    create_directory "monitoring/exporters/application" "Exporters d'applications"
    create_directory "monitoring/exporters/custom" "Exporters personnalisés"
    create_directory "monitoring/exporters/third-party" "Exporters tiers"

    # Création des sous-répertoires pour les configurations
    create_directory "monitoring/configs/prometheus" "Configurations Prometheus"
    create_directory "monitoring/configs/prometheus/global" "Configuration globale"
    create_directory "monitoring/configs/prometheus/scrape-configs" "Configurations de scraping"
    create_directory "monitoring/configs/prometheus/recording-rules" "Règles d'enregistrement"

    create_directory "monitoring/configs/grafana" "Configurations Grafana"
    create_directory "monitoring/configs/grafana/datasources" "Sources de données"
    create_directory "monitoring/configs/grafana/provisioning" "Provisionnement"
    create_directory "monitoring/configs/grafana/plugins" "Plugins"

    create_directory "monitoring/configs/alertmanager" "Configurations AlertManager"
    create_directory "monitoring/configs/alertmanager/templates" "Templates de notifications"
    create_directory "monitoring/configs/alertmanager/receivers" "Récepteurs d'alertes"
    create_directory "monitoring/configs/alertmanager/routes" "Routes d'alertes"

    create_directory "monitoring/configs/loki" "Configurations Loki"
    create_directory "monitoring/configs/loki/rules" "Règles Loki"
    create_directory "monitoring/configs/loki/alerts" "Alertes Loki"

    # Création des sous-répertoires pour les règles
    create_directory "monitoring/rules/recording" "Règles d'enregistrement"
    create_directory "monitoring/rules/alerting" "Règles d'alerte"
    create_directory "monitoring/rules/templates" "Templates de règles"

    # Création des sous-répertoires pour les scripts
    create_directory "monitoring/scripts/installation" "Scripts d'installation"
    create_directory "monitoring/scripts/maintenance" "Scripts de maintenance"
    create_directory "monitoring/scripts/backup" "Scripts de sauvegarde"
    create_directory "monitoring/scripts/custom-checks" "Scripts de vérifications personnalisées"

    # Création des sous-répertoires pour les templates
    create_directory "monitoring/templates/dashboards" "Templates de tableaux de bord"
    create_directory "monitoring/templates/alerts" "Templates d'alertes"
    create_directory "monitoring/templates/exporters" "Templates d'exporters"
    create_directory "monitoring/templates/documentation" "Templates de documentation"

    # Création des sous-répertoires pour la documentation
    create_directory "monitoring/documentation/guides" "Guides de monitoring"
    create_directory "monitoring/documentation/architecture" "Architecture de monitoring"
    create_directory "monitoring/documentation/runbooks" "Runbooks pour les alertes"
    create_directory "monitoring/documentation/slos" "Objectifs de niveau de service"

    # Création des répertoires pour les SLOs
    create_directory "monitoring/slos/definitions" "Définitions des SLOs"
    create_directory "monitoring/slos/reports" "Rapports de SLOs"
    create_directory "monitoring/slos/templates" "Templates de SLOs"

    # Création des READMEs pour les répertoires principaux
    create_readme "monitoring/alerts" "Configurations d'alertes" "Ce répertoire contient les configurations d'alertes pour différents composants de l'infrastructure."
    create_readme "monitoring/dashboards" "Tableaux de bord" "Ce répertoire contient les tableaux de bord pour visualiser les métriques de l'infrastructure."
    create_readme "monitoring/exporters" "Exporters Prometheus" "Ce répertoire contient les configurations des exporters Prometheus pour collecter des métriques."
    create_readme "monitoring/configs" "Fichiers de configuration" "Ce répertoire contient les fichiers de configuration pour les différents outils de monitoring."
    create_readme "monitoring/rules" "Règles de monitoring" "Ce répertoire contient les règles de monitoring pour Prometheus et autres outils."
    create_readme "monitoring/scripts" "Scripts de monitoring" "Ce répertoire contient les scripts pour l'installation et la maintenance du monitoring."
    create_readme "monitoring/templates" "Templates réutilisables" "Ce répertoire contient des templates réutilisables pour le monitoring."
    create_readme "monitoring/documentation" "Documentation de monitoring" "Ce répertoire contient la documentation relative au monitoring."
    create_readme "monitoring/slos" "Objectifs de niveau de service" "Ce répertoire contient les définitions et rapports des objectifs de niveau de service (SLOs)."

    # Création des READMEs pour les sous-répertoires d'alertes
    create_readme "monitoring/alerts/infrastructure" "Alertes d'infrastructure" "Ce répertoire contient les configurations d'alertes pour l'infrastructure."
    create_readme "monitoring/alerts/applications" "Alertes d'applications" "Ce répertoire contient les configurations d'alertes pour les applications."
    create_readme "monitoring/alerts/security" "Alertes de sécurité" "Ce répertoire contient les configurations d'alertes pour la sécurité."
    create_readme "monitoring/alerts/business" "Alertes métier" "Ce répertoire contient les configurations d'alertes pour les métriques métier."

    # Création des READMEs pour les sous-répertoires de tableaux de bord
    create_readme "monitoring/dashboards/infrastructure" "Tableaux de bord d'infrastructure" "Ce répertoire contient les tableaux de bord pour l'infrastructure."
    create_readme "monitoring/dashboards/applications" "Tableaux de bord d'applications" "Ce répertoire contient les tableaux de bord pour les applications."
    create_readme "monitoring/dashboards/business" "Tableaux de bord métier" "Ce répertoire contient les tableaux de bord métier."
    create_readme "monitoring/dashboards/security" "Tableaux de bord de sécurité" "Ce répertoire contient les tableaux de bord pour la sécurité."

    # Création d'un fichier de métadonnées pour le répertoire monitoring
    if [ "${DRY_RUN}" = "true" ]; then
        log "DEBUG" "Simulation: Création du fichier de métadonnées pour monitoring"
    else
        cat > "${PROJECT_ROOT}/monitoring/METADATA.md" << EOF
# Métadonnées du répertoire Monitoring

## Version
2.0.0

## Description
Ce répertoire contient les configurations et outils pour le monitoring de l'infrastructure LIONS.

## Structure
La structure de ce répertoire suit les meilleures pratiques de monitoring avec une organisation fine et modulaire:

- **alerts/**: Configurations d'alertes organisées par domaine
- **dashboards/**: Tableaux de bord organisés par domaine
- **exporters/**: Exporters Prometheus pour la collecte de métriques
- **configs/**: Configurations des outils de monitoring
- **rules/**: Règles de monitoring pour Prometheus
- **scripts/**: Scripts d'installation et de maintenance
- **templates/**: Templates réutilisables
- **documentation/**: Documentation de monitoring
- **slos/**: Objectifs de niveau de service

## Outils de monitoring
- **Prometheus**: Collecte et stockage de métriques
- **Grafana**: Visualisation de métriques
- **AlertManager**: Gestion des alertes
- **Loki**: Agrégation de logs
- **Exporters**: Collecte de métriques spécifiques

## Conventions de nommage
- Dashboards: \`<domaine>-<composant>-dashboard.json\` (ex: infrastructure-kubernetes-dashboard.json)
- Alertes: \`<domaine>-<composant>-alerts.yml\` (ex: applications-frontend-alerts.yml)
- Règles: \`<domaine>-<composant>-rules.yml\` (ex: infrastructure-kubernetes-rules.yml)

## Bonnes pratiques
- Documenter chaque alerte avec un runbook
- Définir des seuils d'alerte basés sur des SLOs
- Utiliser des templates pour la cohérence
- Organiser les tableaux de bord par domaine et composant
- Versionner toutes les configurations
EOF
    fi

    # Création d'un guide de bonnes pratiques pour le monitoring
    if [ "${DRY_RUN}" = "true" ]; then
        log "DEBUG" "Simulation: Création du guide de bonnes pratiques pour monitoring"
    else
        cat > "${PROJECT_ROOT}/monitoring/documentation/BEST_PRACTICES.md" << EOF
# Bonnes pratiques de monitoring

## Collecte de métriques
- Collecter uniquement les métriques utiles
- Utiliser des labels cohérents pour faciliter les requêtes
- Définir une politique de rétention adaptée aux besoins
- Utiliser des intervalles de scraping appropriés selon la criticité

## Alertes
- Créer des alertes actionnables (qui nécessitent une action)
- Éviter les faux positifs en ajustant les seuils et les délais
- Documenter chaque alerte avec un runbook
- Définir des niveaux de sévérité cohérents
- Regrouper les alertes connexes pour éviter les tempêtes d'alertes

## Tableaux de bord
- Concevoir des tableaux de bord pour des cas d'utilisation spécifiques
- Inclure des informations contextuelles (documentation, liens)
- Utiliser des variables pour rendre les tableaux de bord réutilisables
- Organiser les panneaux de manière logique (du général au spécifique)
- Standardiser les unités, les couleurs et les seuils

## SLOs (Objectifs de niveau de service)
- Définir des SLIs (indicateurs) mesurables
- Établir des SLOs réalistes basés sur les besoins métier
- Mesurer les SLOs sur des périodes glissantes
- Utiliser des budgets d'erreur pour gérer les incidents
- Réviser régulièrement les SLOs en fonction de l'évolution des besoins

## Architecture de monitoring
- Séparer la collecte, le stockage et la visualisation
- Mettre en place une haute disponibilité pour les composants critiques
- Surveiller le système de monitoring lui-même
- Automatiser le déploiement et la configuration
- Sécuriser l'accès aux outils de monitoring

## Logs
- Centraliser la collecte de logs
- Structurer les logs en format JSON quand c'est possible
- Définir des niveaux de log cohérents
- Corréler les logs avec les métriques
- Définir une politique de rétention adaptée aux besoins

## Gestion des incidents
- Définir des procédures claires pour chaque type d'alerte
- Documenter les étapes de résolution dans des runbooks
- Analyser les incidents pour améliorer le monitoring
- Mettre en place un processus post-mortem
- Automatiser les actions correctives quand c'est possible
EOF
    fi

    # Déplacement des fichiers existants vers la nouvelle structure
    if [ "${DRY_RUN}" = "true" ]; then
        log "DEBUG" "Simulation: Déplacement des fichiers de monitoring existants"
    else
        # Déplacement des tableaux de bord
        if [ -d "${PROJECT_ROOT}/monitoring/dashboards/ollama" ]; then
            mkdir -p "${PROJECT_ROOT}/monitoring/dashboards/applications/ai"
            mv "${PROJECT_ROOT}/monitoring/dashboards/ollama" "${PROJECT_ROOT}/monitoring/dashboards/applications/ai/"
        fi

        if [ -d "${PROJECT_ROOT}/monitoring/dashboards/primefaces" ]; then
            mkdir -p "${PROJECT_ROOT}/monitoring/dashboards/applications/frontend"
            mv "${PROJECT_ROOT}/monitoring/dashboards/primefaces" "${PROJECT_ROOT}/monitoring/dashboards/applications/frontend/"
        fi

        if [ -d "${PROJECT_ROOT}/monitoring/dashboards/primereact" ]; then
            mkdir -p "${PROJECT_ROOT}/monitoring/dashboards/applications/frontend"
            mv "${PROJECT_ROOT}/monitoring/dashboards/primereact" "${PROJECT_ROOT}/monitoring/dashboards/applications/frontend/"
        fi

        if [ -d "${PROJECT_ROOT}/monitoring/dashboards/quarkus" ]; then
            mkdir -p "${PROJECT_ROOT}/monitoring/dashboards/applications/backend"
            mv "${PROJECT_ROOT}/monitoring/dashboards/quarkus" "${PROJECT_ROOT}/monitoring/dashboards/applications/backend/"
        fi

        # Déplacement des alertes
        if [ -d "${PROJECT_ROOT}/monitoring/alerts/primefaces" ]; then
            mkdir -p "${PROJECT_ROOT}/monitoring/alerts/applications/frontend"
            mv "${PROJECT_ROOT}/monitoring/alerts/primefaces" "${PROJECT_ROOT}/monitoring/alerts/applications/frontend/"
        fi

        if [ -d "${PROJECT_ROOT}/monitoring/alerts/primereact" ]; then
            mkdir -p "${PROJECT_ROOT}/monitoring/alerts/applications/frontend"
            mv "${PROJECT_ROOT}/monitoring/alerts/primereact" "${PROJECT_ROOT}/monitoring/alerts/applications/frontend/"
        fi

        if [ -d "${PROJECT_ROOT}/monitoring/alerts/quarkus" ]; then
            mkdir -p "${PROJECT_ROOT}/monitoring/alerts/applications/backend"
            mv "${PROJECT_ROOT}/monitoring/alerts/quarkus" "${PROJECT_ROOT}/monitoring/alerts/applications/backend/"
        fi

        # Déplacement des SLOs
        if [ -d "${PROJECT_ROOT}/monitoring/slos/primefaces" ]; then
            mkdir -p "${PROJECT_ROOT}/monitoring/slos/definitions/frontend"
            mv "${PROJECT_ROOT}/monitoring/slos/primefaces" "${PROJECT_ROOT}/monitoring/slos/definitions/frontend/"
        fi

        if [ -d "${PROJECT_ROOT}/monitoring/slos/primereact" ]; then
            mkdir -p "${PROJECT_ROOT}/monitoring/slos/definitions/frontend"
            mv "${PROJECT_ROOT}/monitoring/slos/primereact" "${PROJECT_ROOT}/monitoring/slos/definitions/frontend/"
        fi

        if [ -d "${PROJECT_ROOT}/monitoring/slos/quarkus" ]; then
            mkdir -p "${PROJECT_ROOT}/monitoring/slos/definitions/backend"
            mv "${PROJECT_ROOT}/monitoring/slos/quarkus" "${PROJECT_ROOT}/monitoring/slos/definitions/backend/"
        fi
    fi

    log "SUCCESS" "Restructuration du répertoire monitoring terminée"
}

# Fonction de restructuration du répertoire scripts
restructure_scripts() {
    log "INFO" "Restructuration du répertoire scripts..."

    # Création des répertoires principaux
    create_directory "scripts/installation" "Scripts d'installation"
    create_directory "scripts/maintenance" "Scripts de maintenance"
    create_directory "scripts/deployment" "Scripts de déploiement"
    create_directory "scripts/monitoring" "Scripts de monitoring"
    create_directory "scripts/security" "Scripts de sécurité"
    create_directory "scripts/utilities" "Scripts utilitaires"
    create_directory "scripts/testing" "Scripts de test"
    create_directory "scripts/automation" "Scripts d'automatisation"
    create_directory "scripts/templates" "Templates de scripts"
    create_directory "scripts/documentation" "Documentation des scripts"

    # Création des sous-répertoires pour l'installation
    create_directory "scripts/installation/local" "Scripts d'installation locale"
    create_directory "scripts/installation/remote" "Scripts d'installation à distance"
    create_directory "scripts/installation/prerequisites" "Scripts de vérification des prérequis"
    create_directory "scripts/installation/post-install" "Scripts post-installation"
    create_directory "scripts/installation/validation" "Scripts de validation d'installation"

    # Création des sous-répertoires pour la maintenance
    create_directory "scripts/maintenance/backup" "Scripts de sauvegarde"
    create_directory "scripts/maintenance/restore" "Scripts de restauration"
    create_directory "scripts/maintenance/update" "Scripts de mise à jour"
    create_directory "scripts/maintenance/cleanup" "Scripts de nettoyage"
    create_directory "scripts/maintenance/health-checks" "Scripts de vérification de santé"
    create_directory "scripts/maintenance/logs" "Scripts de gestion des logs"
    create_directory "scripts/maintenance/performance" "Scripts d'optimisation des performances"

    # Création des sous-répertoires pour le déploiement
    create_directory "scripts/deployment/applications" "Scripts de déploiement d'applications"
    create_directory "scripts/deployment/infrastructure" "Scripts de déploiement d'infrastructure"
    create_directory "scripts/deployment/kubernetes" "Scripts de déploiement Kubernetes"
    create_directory "scripts/deployment/database" "Scripts de déploiement de bases de données"
    create_directory "scripts/deployment/rollback" "Scripts de rollback"
    create_directory "scripts/deployment/canary" "Scripts de déploiement canary"

    # Création des sous-répertoires pour le monitoring
    create_directory "scripts/monitoring/setup" "Scripts d'installation du monitoring"
    create_directory "scripts/monitoring/alerts" "Scripts de gestion des alertes"
    create_directory "scripts/monitoring/dashboards" "Scripts de gestion des tableaux de bord"
    create_directory "scripts/monitoring/exporters" "Scripts de gestion des exporters"
    create_directory "scripts/monitoring/custom-checks" "Scripts de vérifications personnalisées"

    # Création des sous-répertoires pour la sécurité
    create_directory "scripts/security/hardening" "Scripts de renforcement de la sécurité"
    create_directory "scripts/security/audit" "Scripts d'audit de sécurité"
    create_directory "scripts/security/certificates" "Scripts de gestion des certificats"
    create_directory "scripts/security/compliance" "Scripts de conformité"
    create_directory "scripts/security/kubernetes" "Scripts de sécurité Kubernetes"

    # Création des sous-répertoires pour les utilitaires
    create_directory "scripts/utilities/environment" "Scripts de gestion de l'environnement"
    create_directory "scripts/utilities/networking" "Scripts de gestion réseau"
    create_directory "scripts/utilities/kubernetes" "Scripts utilitaires Kubernetes"
    create_directory "scripts/utilities/database" "Scripts utilitaires de bases de données"
    create_directory "scripts/utilities/logging" "Scripts de journalisation"

    # Création des sous-répertoires pour les tests
    create_directory "scripts/testing/unit" "Scripts de tests unitaires"
    create_directory "scripts/testing/integration" "Scripts de tests d'intégration"
    create_directory "scripts/testing/performance" "Scripts de tests de performance"
    create_directory "scripts/testing/security" "Scripts de tests de sécurité"
    create_directory "scripts/testing/validation" "Scripts de validation"

    # Création des sous-répertoires pour l'automatisation
    create_directory "scripts/automation/ci-cd" "Scripts d'intégration continue"
    create_directory "scripts/automation/scheduled-tasks" "Scripts de tâches planifiées"
    create_directory "scripts/automation/event-driven" "Scripts basés sur les événements"
    create_directory "scripts/automation/self-healing" "Scripts d'auto-réparation"

    # Création des sous-répertoires pour les templates
    create_directory "scripts/templates/installation" "Templates de scripts d'installation"
    create_directory "scripts/templates/deployment" "Templates de scripts de déploiement"
    create_directory "scripts/templates/maintenance" "Templates de scripts de maintenance"
    create_directory "scripts/templates/common" "Templates communs"

    # Déplacement des scripts
    if [ "${DRY_RUN}" = "true" ]; then
        log "DEBUG" "Simulation: Déplacement des scripts d'installation"
        log "DEBUG" "Simulation: Déplacement des scripts de maintenance"
        log "DEBUG" "Simulation: Déplacement des scripts de monitoring"
    else
        # Installation
        if [ -f "${PROJECT_ROOT}/scripts/install.sh" ]; then
            mv "${PROJECT_ROOT}/scripts/install.sh" "${PROJECT_ROOT}/scripts/installation/local/"
        fi
        if [ -f "${PROJECT_ROOT}/scripts/remote-install.sh" ]; then
            mv "${PROJECT_ROOT}/scripts/remote-install.sh" "${PROJECT_ROOT}/scripts/installation/remote/"
        fi

        # Maintenance
        if [ -f "${PROJECT_ROOT}/scripts/backup-restore.sh" ]; then
            cp "${PROJECT_ROOT}/scripts/backup-restore.sh" "${PROJECT_ROOT}/scripts/maintenance/backup/backup.sh"
            cp "${PROJECT_ROOT}/scripts/backup-restore.sh" "${PROJECT_ROOT}/scripts/maintenance/restore/restore.sh"
            rm "${PROJECT_ROOT}/scripts/backup-restore.sh"
        fi
        if [ -f "${PROJECT_ROOT}/scripts/optimize-vps.sh" ]; then
            mv "${PROJECT_ROOT}/scripts/optimize-vps.sh" "${PROJECT_ROOT}/scripts/maintenance/performance/"
        fi

        # Déploiement
        if [ -f "${PROJECT_ROOT}/scripts/deploy.sh" ]; then
            mv "${PROJECT_ROOT}/scripts/deploy.sh" "${PROJECT_ROOT}/scripts/deployment/applications/"
        fi
        if [ -f "${PROJECT_ROOT}/scripts/deploy-services.sh" ]; then
            mv "${PROJECT_ROOT}/scripts/deploy-services.sh" "${PROJECT_ROOT}/scripts/deployment/infrastructure/"
        fi
        if [ -f "${PROJECT_ROOT}/scripts/rollback.sh" ]; then
            mv "${PROJECT_ROOT}/scripts/rollback.sh" "${PROJECT_ROOT}/scripts/deployment/rollback/"
        fi

        # Monitoring
        if [ -f "${PROJECT_ROOT}/scripts/setup-monitoring.sh" ]; then
            mv "${PROJECT_ROOT}/scripts/setup-monitoring.sh" "${PROJECT_ROOT}/scripts/monitoring/setup/"
        fi
        if [ -f "${PROJECT_ROOT}/scripts/create-dashboard-nodeport.sh" ]; then
            mv "${PROJECT_ROOT}/scripts/create-dashboard-nodeport.sh" "${PROJECT_ROOT}/scripts/monitoring/dashboards/"
        fi

        # Sécurité
        if [ -f "${PROJECT_ROOT}/scripts/fix-k3s.sh" ]; then
            mv "${PROJECT_ROOT}/scripts/fix-k3s.sh" "${PROJECT_ROOT}/scripts/security/kubernetes/"
        fi
        if [ -f "${PROJECT_ROOT}/scripts/check-k3s-flags.sh" ]; then
            mv "${PROJECT_ROOT}/scripts/check-k3s-flags.sh" "${PROJECT_ROOT}/scripts/security/kubernetes/"
        fi

        # Utilitaires
        if [ -f "${PROJECT_ROOT}/scripts/load-env.sh" ]; then
            mv "${PROJECT_ROOT}/scripts/load-env.sh" "${PROJECT_ROOT}/scripts/utilities/environment/"
        fi
        if [ -f "${PROJECT_ROOT}/scripts/add-kubeconfig-env.sh" ]; then
            mv "${PROJECT_ROOT}/scripts/add-kubeconfig-env.sh" "${PROJECT_ROOT}/scripts/utilities/kubernetes/"
        fi
        if [ -f "${PROJECT_ROOT}/scripts/configure-dns.sh" ]; then
            mv "${PROJECT_ROOT}/scripts/configure-dns.sh" "${PROJECT_ROOT}/scripts/utilities/networking/"
        fi

        # Restructuration
        if [ -f "${PROJECT_ROOT}/scripts/restructure-repository.sh" ]; then
            mkdir -p "${PROJECT_ROOT}/scripts/automation/maintenance"
            cp "${PROJECT_ROOT}/scripts/restructure-repository.sh" "${PROJECT_ROOT}/scripts/automation/maintenance/"
        fi

        # Vérification
        if [ -f "${PROJECT_ROOT}/scripts/verify-autoscaling.sh" ]; then
            mv "${PROJECT_ROOT}/scripts/verify-autoscaling.sh" "${PROJECT_ROOT}/scripts/testing/validation/"
        fi
        if [ -f "${PROJECT_ROOT}/scripts/test-registry-urls.sh" ]; then
            mv "${PROJECT_ROOT}/scripts/test-registry-urls.sh" "${PROJECT_ROOT}/scripts/testing/integration/"
        fi
    fi

    # Création des READMEs pour les répertoires principaux
    create_readme "scripts/installation" "Scripts d'installation" "Ce répertoire contient les scripts pour installer l'infrastructure."
    create_readme "scripts/maintenance" "Scripts de maintenance" "Ce répertoire contient les scripts pour maintenir l'infrastructure."
    create_readme "scripts/deployment" "Scripts de déploiement" "Ce répertoire contient les scripts pour déployer les applications et l'infrastructure."
    create_readme "scripts/monitoring" "Scripts de monitoring" "Ce répertoire contient les scripts pour le monitoring de l'infrastructure."
    create_readme "scripts/security" "Scripts de sécurité" "Ce répertoire contient les scripts pour la sécurité de l'infrastructure."
    create_readme "scripts/utilities" "Scripts utilitaires" "Ce répertoire contient des scripts utilitaires pour l'infrastructure."
    create_readme "scripts/testing" "Scripts de test" "Ce répertoire contient les scripts pour tester l'infrastructure et les applications."
    create_readme "scripts/automation" "Scripts d'automatisation" "Ce répertoire contient les scripts pour automatiser les tâches récurrentes."
    create_readme "scripts/templates" "Templates de scripts" "Ce répertoire contient des templates pour créer de nouveaux scripts."
    create_readme "scripts/documentation" "Documentation des scripts" "Ce répertoire contient la documentation des scripts."

    # Création des READMEs pour les sous-répertoires d'installation
    create_readme "scripts/installation/local" "Scripts d'installation locale" "Ce répertoire contient les scripts pour installer l'infrastructure localement."
    create_readme "scripts/installation/remote" "Scripts d'installation à distance" "Ce répertoire contient les scripts pour installer l'infrastructure à distance."
    create_readme "scripts/installation/prerequisites" "Scripts de vérification des prérequis" "Ce répertoire contient les scripts pour vérifier les prérequis avant l'installation."

    # Création des READMEs pour les sous-répertoires de maintenance
    create_readme "scripts/maintenance/backup" "Scripts de sauvegarde" "Ce répertoire contient les scripts pour sauvegarder l'infrastructure."
    create_readme "scripts/maintenance/restore" "Scripts de restauration" "Ce répertoire contient les scripts pour restaurer l'infrastructure."
    create_readme "scripts/maintenance/update" "Scripts de mise à jour" "Ce répertoire contient les scripts pour mettre à jour l'infrastructure."

    # Création d'un fichier de métadonnées pour le répertoire scripts
    if [ "${DRY_RUN}" = "true" ]; then
        log "DEBUG" "Simulation: Création du fichier de métadonnées pour scripts"
    else
        cat > "${PROJECT_ROOT}/scripts/METADATA.md" << EOF
# Métadonnées du répertoire Scripts

## Version
2.0.0

## Description
Ce répertoire contient les scripts d'automatisation pour déployer, gérer et maintenir l'infrastructure LIONS.

## Structure
La structure de ce répertoire suit une organisation fine et modulaire par fonction:

- **installation/**: Scripts pour installer l'infrastructure
- **maintenance/**: Scripts pour maintenir l'infrastructure
- **deployment/**: Scripts pour déployer les applications et services
- **monitoring/**: Scripts pour le monitoring
- **security/**: Scripts pour la sécurité
- **utilities/**: Scripts utilitaires
- **testing/**: Scripts de test
- **automation/**: Scripts d'automatisation
- **templates/**: Templates de scripts
- **documentation/**: Documentation des scripts

## Conventions de nommage
- Noms de scripts: \`<action>-<cible>.sh\` (ex: install-k3s.sh)
- Variables: Utiliser des majuscules pour les constantes (ex: CONFIG_DIR)
- Fonctions: Utiliser des minuscules avec tirets (ex: setup-environment)

## Bonnes pratiques
- Inclure un en-tête avec description, auteur et date
- Documenter les paramètres et options
- Utiliser set -euo pipefail pour le mode strict
- Gérer les erreurs et le nettoyage
- Journaliser les actions importantes
- Utiliser des fonctions pour le code réutilisable
EOF
    fi

    # Création d'un guide de style pour les scripts
    if [ "${DRY_RUN}" = "true" ]; then
        log "DEBUG" "Simulation: Création du guide de style pour scripts"
    else
        cat > "${PROJECT_ROOT}/scripts/documentation/STYLE_GUIDE.md" << EOF
# Guide de style pour les scripts

## Structure des scripts

Chaque script doit suivre cette structure:

\`\`\`bash
#!/bin/bash
# =============================================================================
# Titre: [Titre du script]
# Description: [Description détaillée]
# Auteur: [Auteur]
# Date de création: [Date]
# Version: [Version]
# Usage: [Commande d'utilisation]
# =============================================================================

# Mode strict
set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Variables et constantes

# =============================================================================
# Fonctions
# =============================================================================

# Fonction d'affichage de l'aide
show_help() {
    # ...
}

# Autres fonctions...

# =============================================================================
# Traitement des arguments
# =============================================================================

# Analyse des arguments

# =============================================================================
# Initialisation
# =============================================================================

# Vérifications préliminaires

# =============================================================================
# Exécution
# =============================================================================

# Fonction principale
main() {
    # ...
}

# Exécution de la fonction principale
main
\`\`\`

## Conventions de nommage

- **Scripts**: Utiliser des noms descriptifs en minuscules avec des tirets (ex: \`deploy-application.sh\`)
- **Variables**: 
  - Constantes en majuscules avec tirets bas (ex: \`CONFIG_DIR\`)
  - Variables locales en minuscules avec tirets bas (ex: \`user_name\`)
- **Fonctions**: Utiliser des noms descriptifs en minuscules avec des tirets (ex: \`setup-environment\`)

## Indentation et formatage

- Utiliser 4 espaces pour l'indentation (pas de tabulations)
- Limiter les lignes à 80 caractères quand c'est possible
- Utiliser des espaces autour des opérateurs
- Utiliser des accolades pour toutes les variables (ex: \`${variable}\`)

## Documentation

- Chaque script doit avoir un en-tête complet
- Documenter toutes les fonctions avec leur objectif, paramètres et valeur de retour
- Ajouter des commentaires pour les sections complexes
- Inclure des exemples d'utilisation dans l'aide

## Gestion des erreurs

- Utiliser \`set -euo pipefail\` pour le mode strict
- Implémenter une fonction de gestion des erreurs
- Utiliser des codes de retour significatifs
- Journaliser les erreurs avec des messages clairs

## Journalisation

- Utiliser une fonction de journalisation cohérente
- Inclure la date, l'heure et le niveau de log
- Définir différents niveaux de log (INFO, WARNING, ERROR, DEBUG)
- Écrire les logs dans un fichier et les afficher dans la console

## Tests

- Créer des tests pour les fonctions critiques
- Vérifier les cas limites et les erreurs
- Documenter les procédures de test
EOF
    fi

    # Création d'un template de script
    if [ "${DRY_RUN}" = "true" ]; then
        log "DEBUG" "Simulation: Création du template de script"
    else
        # Utilisation d'un heredoc avec des quotes pour éviter l'expansion des variables
        cat > "${PROJECT_ROOT}/scripts/templates/common/script-template.sh" << 'EOFSCRIPT'
#!/bin/bash
# =============================================================================
# Titre: [TITRE DU SCRIPT]
# Description: [DESCRIPTION DÉTAILLÉE]
# Auteur: Équipe LIONS Infrastructure
# Date de création: $(date +%Y-%m-%d)
# Version: 1.0.0
# Usage: ./$(basename "$0") [options]
# =============================================================================

# Mode strict
set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Répertoire racine du projet
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Fichier de log
LOG_DIR="${PROJECT_ROOT}/scripts/logs"
LOG_FILE="${LOG_DIR}/$(basename "$0" .sh).log"

# Variables de configuration
DRY_RUN="false"
VERBOSE="false"

# =============================================================================
# Fonctions
# =============================================================================

# Fonction d'affichage de l'aide
show_help() {
    cat << EOF
Usage: $(basename "$0") [options]

Description:
    [DESCRIPTION COURTE]

Options:
    -h, --help              Affiche cette aide
    -v, --verbose           Mode verbeux
    -d, --dry-run           Mode simulation (n'effectue aucune action)

Exemples:
    $(basename "$0") --dry-run
    $(basename "$0") --verbose
EOF
    exit 0
}

# Fonction de journalisation
log() {
    local level=$1
    local message=$2
    local color=$NC

    case $level in
        "INFO") color=$NC ;;
        "SUCCESS") color=$GREEN ;;
        "WARNING") color=$YELLOW ;;
        "ERROR") color=$RED ;;
        "DEBUG") 
            if [[ "${VERBOSE}" != "true" ]]; then
                return
            fi
            color=$BLUE 
            ;;
    esac

    # Création du répertoire de logs si nécessaire
    mkdir -p "${LOG_DIR}"

    # Format de date pour les logs
    local date_format=$(date '+%Y-%m-%d %H:%M:%S')

    # Affichage dans la console
    echo -e "${color}[${date_format}] [${level}] ${message}${NC}"

    # Écriture dans le fichier de log
    echo "[${date_format}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Fonction de nettoyage à la sortie
cleanup() {
    local exit_code=$?

    # Actions de nettoyage
    log "INFO" "Nettoyage des ressources temporaires..."

    # Suppression des fichiers temporaires
    rm -f /tmp/$(basename "$0" .sh)-temp-*

    # Message de fin
    if [ ${exit_code} -eq 0 ]; then
        log "SUCCESS" "Script terminé avec succès"
    else
        log "ERROR" "Script terminé avec des erreurs (code: ${exit_code})"
    fi

    exit ${exit_code}
}

# Fonction de gestion des erreurs
handle_error() {
    local line=$1
    local command=$2
    local code=$3
    log "ERROR" "Erreur à la ligne ${line} (commande: '${command}', code: ${code})"
}

# Fonction principale
main() {
    log "INFO" "Début de l'exécution..."

    # Votre code ici

    log "SUCCESS" "Exécution terminée avec succès"
}

# =============================================================================
# Traitement des arguments
# =============================================================================

# Analyse des arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -v|--verbose)
            VERBOSE="true"
            shift
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        *)
            log "ERROR" "Option inconnue: $1"
            show_help
            ;;
    esac
done

# =============================================================================
# Initialisation
# =============================================================================

# Enregistrement des gestionnaires de signaux
trap 'cleanup' EXIT
trap 'handle_error ${LINENO} "$BASH_COMMAND" $?' ERR

# =============================================================================
# Exécution
# =============================================================================

# Exécution de la fonction principale
main
EOFSCRIPT
    fi

    log "SUCCESS" "Restructuration du répertoire scripts terminée"
}

# Fonction de restructuration du répertoire docs
restructure_docs() {
    log "INFO" "Restructuration du répertoire docs..."

    # Création des nouveaux répertoires
    create_directory "docs/architecture/decisions" "Documents de décisions d'architecture"
    create_directory "docs/architecture/patterns" "Patterns d'architecture utilisés"

    create_directory "docs/changes/releases" "Notes de version"
    create_directory "docs/changes/migrations" "Guides de migration"

    create_directory "docs/development" "Documentation pour les développeurs"
    create_directory "docs/development/setup" "Configuration de l'environnement de développement"
    create_directory "docs/development/guidelines" "Directives de développement"
    create_directory "docs/development/workflows" "Workflows de développement"

    create_directory "docs/guides/installation" "Guides d'installation"
    create_directory "docs/guides/configuration" "Guides de configuration"
    create_directory "docs/guides/deployment" "Guides de déploiement"
    create_directory "docs/guides/troubleshooting" "Guides de dépannage"

    create_directory "docs/operations" "Documentation pour les opérations"
    create_directory "docs/operations/monitoring" "Guides de monitoring"
    create_directory "docs/operations/backup" "Guides de sauvegarde"
    create_directory "docs/operations/scaling" "Guides de mise à l'échelle"

    create_directory "docs/runbooks/incidents" "Gestion des incidents"
    create_directory "docs/runbooks/maintenance" "Maintenance planifiée"
    create_directory "docs/runbooks/recovery" "Procédures de récupération"

    # Création des READMEs
    create_readme "docs/architecture/decisions" "Documents de décisions d'architecture" "Ce répertoire contient les documents de décisions d'architecture (ADRs)."
    create_readme "docs/architecture/patterns" "Patterns d'architecture" "Ce répertoire contient les patterns d'architecture utilisés dans le projet."

    create_readme "docs/changes/releases" "Notes de version" "Ce répertoire contient les notes de version du projet."
    create_readme "docs/changes/migrations" "Guides de migration" "Ce répertoire contient les guides de migration entre les versions."

    create_readme "docs/development" "Documentation pour les développeurs" "Ce répertoire contient la documentation destinée aux développeurs."
    create_readme "docs/development/setup" "Configuration de l'environnement" "Ce répertoire contient les guides de configuration de l'environnement de développement."
    create_readme "docs/development/guidelines" "Directives de développement" "Ce répertoire contient les directives de développement à suivre."
    create_readme "docs/development/workflows" "Workflows de développement" "Ce répertoire contient les workflows de développement à suivre."

    create_readme "docs/guides/installation" "Guides d'installation" "Ce répertoire contient les guides d'installation de l'infrastructure."
    create_readme "docs/guides/configuration" "Guides de configuration" "Ce répertoire contient les guides de configuration de l'infrastructure."
    create_readme "docs/guides/deployment" "Guides de déploiement" "Ce répertoire contient les guides de déploiement des applications."
    create_readme "docs/guides/troubleshooting" "Guides de dépannage" "Ce répertoire contient les guides de dépannage de l'infrastructure."

    create_readme "docs/operations" "Documentation pour les opérations" "Ce répertoire contient la documentation destinée aux opérateurs."
    create_readme "docs/operations/monitoring" "Guides de monitoring" "Ce répertoire contient les guides de monitoring de l'infrastructure."
    create_readme "docs/operations/backup" "Guides de sauvegarde" "Ce répertoire contient les guides de sauvegarde de l'infrastructure."
    create_readme "docs/operations/scaling" "Guides de mise à l'échelle" "Ce répertoire contient les guides de mise à l'échelle de l'infrastructure."

    create_readme "docs/runbooks/incidents" "Gestion des incidents" "Ce répertoire contient les runbooks pour la gestion des incidents."
    create_readme "docs/runbooks/maintenance" "Maintenance planifiée" "Ce répertoire contient les runbooks pour la maintenance planifiée."
    create_readme "docs/runbooks/recovery" "Procédures de récupération" "Ce répertoire contient les runbooks pour les procédures de récupération."

    log "SUCCESS" "Restructuration du répertoire docs terminée"
}

# Fonction de création du répertoire tests
create_tests_directory() {
    log "INFO" "Création du répertoire tests..."

    # Création des nouveaux répertoires
    create_directory "tests/ansible" "Tests des playbooks et rôles Ansible"
    create_directory "tests/applications" "Tests des templates d'applications"
    create_directory "tests/infrastructure" "Tests d'infrastructure"
    create_directory "tests/integration" "Tests d'intégration"
    create_directory "tests/kubernetes" "Tests des configurations Kubernetes"
    create_directory "tests/scripts" "Tests des scripts"

    # Création des READMEs
    create_readme "tests/ansible" "Tests Ansible" "Ce répertoire contient les tests pour les playbooks et rôles Ansible."
    create_readme "tests/applications" "Tests des applications" "Ce répertoire contient les tests pour les templates d'applications."
    create_readme "tests/infrastructure" "Tests d'infrastructure" "Ce répertoire contient les tests pour l'infrastructure."
    create_readme "tests/integration" "Tests d'intégration" "Ce répertoire contient les tests d'intégration."
    create_readme "tests/kubernetes" "Tests Kubernetes" "Ce répertoire contient les tests pour les configurations Kubernetes."
    create_readme "tests/scripts" "Tests des scripts" "Ce répertoire contient les tests pour les scripts."

    log "SUCCESS" "Création du répertoire tests terminée"
}

# Fonction de création du répertoire environments
create_environments_directory() {
    log "INFO" "Création du répertoire environments..."

    # Création des nouveaux répertoires
    create_directory "environments/development/ansible" "Variables Ansible spécifiques à l'environnement de développement"
    create_directory "environments/development/kubernetes" "Configurations Kubernetes spécifiques à l'environnement de développement"
    create_directory "environments/development/terraform" "Configurations Terraform spécifiques à l'environnement de développement"

    create_directory "environments/staging/ansible" "Variables Ansible spécifiques à l'environnement de staging"
    create_directory "environments/staging/kubernetes" "Configurations Kubernetes spécifiques à l'environnement de staging"
    create_directory "environments/staging/terraform" "Configurations Terraform spécifiques à l'environnement de staging"

    create_directory "environments/production/ansible" "Variables Ansible spécifiques à l'environnement de production"
    create_directory "environments/production/kubernetes" "Configurations Kubernetes spécifiques à l'environnement de production"
    create_directory "environments/production/terraform" "Configurations Terraform spécifiques à l'environnement de production"

    # Création des READMEs
    create_readme "environments/development" "Environnement de développement" "Ce répertoire contient les configurations spécifiques à l'environnement de développement."
    create_readme "environments/development/ansible" "Variables Ansible" "Ce répertoire contient les variables Ansible spécifiques à l'environnement de développement."
    create_readme "environments/development/kubernetes" "Configurations Kubernetes" "Ce répertoire contient les configurations Kubernetes spécifiques à l'environnement de développement."
    create_readme "environments/development/terraform" "Configurations Terraform" "Ce répertoire contient les configurations Terraform spécifiques à l'environnement de développement."

    create_readme "environments/staging" "Environnement de staging" "Ce répertoire contient les configurations spécifiques à l'environnement de staging."
    create_readme "environments/staging/ansible" "Variables Ansible" "Ce répertoire contient les variables Ansible spécifiques à l'environnement de staging."
    create_readme "environments/staging/kubernetes" "Configurations Kubernetes" "Ce répertoire contient les configurations Kubernetes spécifiques à l'environnement de staging."
    create_readme "environments/staging/terraform" "Configurations Terraform" "Ce répertoire contient les configurations Terraform spécifiques à l'environnement de staging."

    create_readme "environments/production" "Environnement de production" "Ce répertoire contient les configurations spécifiques à l'environnement de production."
    create_readme "environments/production/ansible" "Variables Ansible" "Ce répertoire contient les variables Ansible spécifiques à l'environnement de production."
    create_readme "environments/production/kubernetes" "Configurations Kubernetes" "Ce répertoire contient les configurations Kubernetes spécifiques à l'environnement de production."
    create_readme "environments/production/terraform" "Configurations Terraform" "Ce répertoire contient les configurations Terraform spécifiques à l'environnement de production."

    log "SUCCESS" "Création du répertoire environments terminée"
}

# Fonction de création du répertoire tools
create_tools_directory() {
    log "INFO" "Création du répertoire tools..."

    # Création des nouveaux répertoires
    create_directory "tools/development/linters" "Linters et formateurs de code"
    create_directory "tools/development/generators" "Générateurs de code"
    create_directory "tools/deployment" "Outils de déploiement"
    create_directory "tools/validation" "Outils de validation"

    # Création des READMEs
    create_readme "tools/development" "Outils de développement" "Ce répertoire contient les outils de développement."
    create_readme "tools/development/linters" "Linters et formateurs" "Ce répertoire contient les linters et formateurs de code."
    create_readme "tools/development/generators" "Générateurs de code" "Ce répertoire contient les générateurs de code."
    create_readme "tools/deployment" "Outils de déploiement" "Ce répertoire contient les outils de déploiement."
    create_readme "tools/validation" "Outils de validation" "Ce répertoire contient les outils de validation."

    log "SUCCESS" "Création du répertoire tools terminée"
}

# Fonction de mise à jour des workflows CI/CD
update_ci_cd_workflows() {
    log "INFO" "Mise à jour des workflows CI/CD..."

    if [ "${DRY_RUN}" = "true" ]; then
        log "DEBUG" "Simulation: Création des nouveaux workflows CI/CD"
    else
        # Création du répertoire .github/workflows s'il n'existe pas
        mkdir -p "${PROJECT_ROOT}/.github/workflows"

        # Création des workflows de linting
        cat > "${PROJECT_ROOT}/.github/workflows/ansible-lint.yml" << EOF
name: Ansible Lint

on:
  push:
    branches: [ main, develop ]
    paths:
      - 'ansible/**'
  pull_request:
    branches: [ main, develop ]
    paths:
      - 'ansible/**'

jobs:
  ansible-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run ansible-lint
        uses: ansible/ansible-lint-action@main
EOF

        cat > "${PROJECT_ROOT}/.github/workflows/shell-lint.yml" << EOF
name: Shell Lint

on:
  push:
    branches: [ main, develop ]
    paths:
      - 'scripts/**/*.sh'
  pull_request:
    branches: [ main, develop ]
    paths:
      - 'scripts/**/*.sh'

jobs:
  shell-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run ShellCheck
        uses: ludeeus/action-shellcheck@master
        with:
          scandir: './scripts'
          severity: 'error'
EOF

        cat > "${PROJECT_ROOT}/.github/workflows/kubernetes-lint.yml" << EOF
name: Kubernetes Lint

on:
  push:
    branches: [ main, develop ]
    paths:
      - 'kubernetes/**/*.yaml'
      - 'kubernetes/**/*.yml'
  pull_request:
    branches: [ main, develop ]
    paths:
      - 'kubernetes/**/*.yaml'
      - 'kubernetes/**/*.yml'

jobs:
  kubernetes-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run kubeval
        uses: instrumenta/kubeval-action@master
        with:
          files: kubernetes
EOF
    fi

    log "SUCCESS" "Mise à jour des workflows CI/CD terminée"
}

# Fonction principale
main() {
    log "INFO" "Début de la restructuration du dépôt lions-infrastructure..."

    # Sauvegarde du dépôt
    backup_repository

    # Restructuration des répertoires principaux
    restructure_main_directories

    # Restructuration des répertoires spécifiques
    restructure_ansible
    restructure_applications
    restructure_kubernetes
    restructure_monitoring
    restructure_scripts
    restructure_docs

    # Création des nouveaux répertoires
    create_tests_directory
    create_environments_directory
    create_tools_directory

    # Mise à jour des workflows CI/CD
    update_ci_cd_workflows

    log "SUCCESS" "Restructuration du dépôt lions-infrastructure terminée avec succès"
    log "INFO" "Une sauvegarde du dépôt original a été créée dans ${BACKUP_DIR}"
    log "INFO" "Consultez le fichier de log ${LOG_FILE} pour plus de détails"
}

# =============================================================================
# Traitement des arguments
# =============================================================================

# Analyse des arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -v|--verbose)
            VERBOSE="true"
            shift
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -b|--backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Option inconnue: $1"
            show_help
            ;;
    esac
done

# =============================================================================
# Initialisation
# =============================================================================

# Enregistrement des gestionnaires de signaux
trap 'cleanup' EXIT
trap 'handle_error ${LINENO} "$BASH_COMMAND" $?' ERR

# =============================================================================
# Exécution
# =============================================================================

# Exécution de la fonction principale
main
