#!/bin/bash
# Titre: Script d'Optimisation pour VPS
# Description: Applique les optimisations recommandées pour l'infrastructure LIONS sur VPS
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-15
# Version: 1.0.0

# Activation du mode strict
set -euo pipefail

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
        "SUCCESS")  color="${COLOR_GREEN}"; icon="✅ " ;;
        "STEP")     color="${COLOR_CYAN}${COLOR_BOLD}"; icon="🔄 " ;;
    esac
    
    # Affichage du message avec formatage
    echo -e "${color}${icon}[${timestamp}] [${level}] ${message}${COLOR_RESET}"
}

# Fonction pour vérifier si l'utilisateur a les droits sudo
function check_sudo() {
    log "STEP" "Vérification des droits sudo"
    if ! sudo -n true 2>/dev/null; then
        log "WARNING" "Ce script nécessite des droits sudo pour fonctionner correctement"
        log "INFO" "Veuillez entrer votre mot de passe lorsque demandé"
        if ! sudo true; then
            log "ERROR" "Impossible d'obtenir les droits sudo. Arrêt du script."
            exit 1
        fi
    fi
    log "SUCCESS" "Droits sudo vérifiés"
}

# Fonction pour vérifier les ressources du système
function check_system_resources() {
    log "STEP" "Vérification des ressources système"
    
    # Vérification du CPU
    local cpu_cores=$(nproc)
    log "INFO" "Nombre de cœurs CPU détectés: ${cpu_cores}"
    
    # Vérification de la RAM
    local total_memory=$(free -m | awk '/^Mem:/{print $2}')
    log "INFO" "Mémoire totale détectée: ${total_memory} MB"
    
    # Vérification de l'espace disque
    local disk_space=$(df -h / | awk 'NR==2 {print $4}')
    log "INFO" "Espace disque disponible: ${disk_space}"
    
    # Recommandations basées sur les ressources détectées
    if [ "${cpu_cores}" -lt 4 ]; then
        log "WARNING" "Le nombre de cœurs CPU (${cpu_cores}) est inférieur à la recommandation minimale (4)"
        log "WARNING" "Les performances peuvent être dégradées"
    fi
    
    if [ "${total_memory}" -lt 8192 ]; then
        log "WARNING" "La mémoire totale (${total_memory} MB) est inférieure à la recommandation minimale (8 GB)"
        log "WARNING" "Les performances peuvent être dégradées"
    fi
    
    log "SUCCESS" "Vérification des ressources système terminée"
}

# Fonction pour installer K3s avec les optimisations recommandées
function install_optimized_k3s() {
    log "STEP" "Installation de K3s optimisé pour VPS"
    
    # Vérification si K3s est déjà installé
    if command -v k3s &> /dev/null; then
        log "WARNING" "K3s est déjà installé sur ce système"
        log "INFO" "Voulez-vous réinstaller K3s avec les optimisations recommandées? (o/N)"
        read -r response
        if [[ ! "${response}" =~ ^[oO]$ ]]; then
            log "INFO" "Installation de K3s annulée"
            return
        fi
        
        # Désinstallation de K3s existant
        log "INFO" "Désinstallation de K3s existant"
        if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
            sudo /usr/local/bin/k3s-uninstall.sh
        else
            log "WARNING" "Script de désinstallation de K3s non trouvé"
            log "WARNING" "Veuillez désinstaller K3s manuellement avant de continuer"
            return
        fi
    fi
    
    # Installation de K3s avec les optimisations recommandées
    log "INFO" "Installation de K3s avec les optimisations recommandées"
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik --disable=servicelb --kube-controller-manager-arg bind-address=0.0.0.0 --kube-scheduler-arg bind-address=0.0.0.0" sh -
    
    # Vérification de l'installation
    if [ $? -eq 0 ]; then
        log "SUCCESS" "K3s installé avec succès"
    else
        log "ERROR" "Échec de l'installation de K3s"
        return
    fi
    
    # Configuration de kubectl
    log "INFO" "Configuration de kubectl"
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
    export KUBECONFIG=~/.kube/config
    
    # Ajout de l'export KUBECONFIG au .bashrc
    if ! grep -q "export KUBECONFIG=~/.kube/config" ~/.bashrc; then
        echo "export KUBECONFIG=~/.kube/config" >> ~/.bashrc
        log "INFO" "Export KUBECONFIG ajouté au .bashrc"
    fi
    
    log "SUCCESS" "Configuration de kubectl terminée"
}

# Fonction pour optimiser la mémoire du système
function optimize_memory() {
    log "STEP" "Optimisation de la mémoire système"
    
    # Vérification si les optimisations sont déjà appliquées
    if grep -q "vm.swappiness=10" /etc/sysctl.conf && grep -q "vm.vfs_cache_pressure=50" /etc/sysctl.conf; then
        log "INFO" "Les optimisations de mémoire sont déjà appliquées"
        return
    fi
    
    # Sauvegarde du fichier sysctl.conf
    sudo cp /etc/sysctl.conf /etc/sysctl.conf.bak
    log "INFO" "Sauvegarde de /etc/sysctl.conf créée: /etc/sysctl.conf.bak"
    
    # Ajout des paramètres d'optimisation
    log "INFO" "Ajout des paramètres d'optimisation de la mémoire"
    echo "# Optimisations pour l'infrastructure LIONS sur VPS" | sudo tee -a /etc/sysctl.conf
    echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf
    echo "vm.vfs_cache_pressure=50" | sudo tee -a /etc/sysctl.conf
    
    # Application des changements
    log "INFO" "Application des changements"
    sudo sysctl -p
    
    log "SUCCESS" "Optimisation de la mémoire système terminée"
}

# Fonction pour configurer les quotas de ressources Kubernetes
function configure_resource_quotas() {
    log "STEP" "Configuration des quotas de ressources Kubernetes"
    
    # Vérification si kubectl est disponible
    if ! command -v kubectl &> /dev/null; then
        log "ERROR" "kubectl n'est pas installé ou n'est pas dans le PATH"
        log "ERROR" "Impossible de configurer les quotas de ressources"
        return
    fi
    
    # Vérification de la connexion au cluster
    if ! kubectl cluster-info &> /dev/null; then
        log "ERROR" "Impossible de se connecter au cluster Kubernetes"
        log "ERROR" "Vérifiez que K3s est installé et que KUBECONFIG est correctement configuré"
        return
    fi
    
    # Création du répertoire temporaire
    local temp_dir=$(mktemp -d)
    log "INFO" "Création du répertoire temporaire: ${temp_dir}"
    
    # Création du fichier de quotas de ressources pour l'environnement de développement
    cat > "${temp_dir}/resource-quotas-development.yaml" << EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-resources
spec:
  hard:
    requests.cpu: "5"
    requests.memory: 10Gi
    limits.cpu: "6"
    limits.memory: 12Gi
    pods: "50"
EOF
    
    # Application des quotas de ressources
    log "INFO" "Application des quotas de ressources pour l'environnement de développement"
    kubectl apply -f "${temp_dir}/resource-quotas-development.yaml" --namespace=development
    
    # Nettoyage
    rm -rf "${temp_dir}"
    
    log "SUCCESS" "Configuration des quotas de ressources Kubernetes terminée"
}

# Fonction pour installer les outils de surveillance
function install_monitoring_tools() {
    log "STEP" "Installation des outils de surveillance"
    
    # Vérification si kubectl est disponible
    if ! command -v kubectl &> /dev/null; then
        log "ERROR" "kubectl n'est pas installé ou n'est pas dans le PATH"
        log "ERROR" "Impossible d'installer les outils de surveillance"
        return
    fi
    
    # Installation de metrics-server
    log "INFO" "Installation de metrics-server"
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    
    # Vérification de l'installation
    log "INFO" "Vérification de l'installation de metrics-server"
    kubectl -n kube-system rollout status deployment metrics-server
    
    log "SUCCESS" "Installation des outils de surveillance terminée"
    log "INFO" "Vous pouvez maintenant utiliser 'kubectl top nodes' et 'kubectl top pods' pour surveiller l'utilisation des ressources"
}

# Fonction principale
function main() {
    log "INFO" "Démarrage du script d'optimisation pour VPS"
    
    # Vérification des droits sudo
    check_sudo
    
    # Vérification des ressources système
    check_system_resources
    
    # Menu d'optimisation
    echo -e "\n${COLOR_CYAN}${COLOR_BOLD}=== Menu d'Optimisation pour VPS ===${COLOR_RESET}\n"
    echo -e "1. Installer K3s optimisé pour VPS"
    echo -e "2. Optimiser la mémoire système"
    echo -e "3. Configurer les quotas de ressources Kubernetes"
    echo -e "4. Installer les outils de surveillance"
    echo -e "5. Appliquer toutes les optimisations"
    echo -e "0. Quitter"
    
    echo -e "\nVeuillez choisir une option (0-5): "
    read -r choice
    
    case "${choice}" in
        1)
            install_optimized_k3s
            ;;
        2)
            optimize_memory
            ;;
        3)
            configure_resource_quotas
            ;;
        4)
            install_monitoring_tools
            ;;
        5)
            install_optimized_k3s
            optimize_memory
            configure_resource_quotas
            install_monitoring_tools
            ;;
        0)
            log "INFO" "Fin du script d'optimisation pour VPS"
            exit 0
            ;;
        *)
            log "ERROR" "Option invalide: ${choice}"
            ;;
    esac
    
    log "INFO" "Fin du script d'optimisation pour VPS"
}

# Exécution de la fonction principale
main