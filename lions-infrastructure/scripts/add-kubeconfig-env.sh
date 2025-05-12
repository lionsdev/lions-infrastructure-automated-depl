#!/bin/bash
# Titre: Script d'identification des tâches Ansible k8s sans variable d'environnement KUBECONFIG
# Description: Identifie les tâches k8s et k8s_info qui n'ont pas la variable d'environnement KUBECONFIG
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-12
# Version: 1.0.0

set -euo pipefail

# Configuration
readonly ANSIBLE_ROLES_DIR="../ansible/roles"
readonly ENVIRONMENT_PARAM="  environment:
    KUBECONFIG: /home/{{ ansible_user }}/.kube/config"

# Fonction pour identifier les tâches sans variable d'environnement
function identify_tasks_without_env() {
    local file="$1"
    echo "Analyse du fichier: $file"

    # Utilisation de grep pour trouver les tâches k8s et k8s_info
    local tasks=$(grep -n "^  k8s:" "$file" | cut -d: -f1)
    local info_tasks=$(grep -n "^  k8s_info:" "$file" | cut -d: -f1)

    # Combiner les résultats
    local all_tasks="$tasks $info_tasks"

    # Pour chaque tâche, vérifier si elle a déjà la variable d'environnement
    for line in $all_tasks; do
        # Extraire le nom de la tâche
        local task_name=$(grep -B 1 -A 0 -n "^  k8s" "$file" | grep "^$((line-1))-" | sed 's/.*name: //')

        # Vérifier si la tâche a déjà la variable d'environnement
        local has_env=$(grep -A 10 -n "^  k8s" "$file" | grep -A 10 "^$line:" | grep -m 1 "^  environment:")

        if [ -z "$has_env" ]; then
            echo "  - Ligne $line: Tâche '$task_name' sans variable d'environnement"
        fi
    done
}

# Fonction principale
function main() {
    echo "Identification des tâches Ansible k8s sans variable d'environnement KUBECONFIG..."

    # Recherche de tous les fichiers de tâches dans les rôles
    local task_files=$(find "$ANSIBLE_ROLES_DIR" -path "*/tasks/*.yml")

    # Traitement de chaque fichier
    for file in $task_files; do
        # Vérifier si le fichier contient des tâches k8s ou k8s_info
        if grep -q "k8s:" "$file" || grep -q "k8s_info:" "$file"; then
            echo "Fichier: $file"
            identify_tasks_without_env "$file"
            echo ""
        fi
    done

    echo "Terminé. Voici comment ajouter la variable d'environnement manuellement:"
    echo "1. Pour chaque tâche identifiée, ajoutez les lignes suivantes à la fin de la tâche:"
    echo "$ENVIRONMENT_PARAM"
    echo ""
    echo "Exemple:"
    echo "- name: Ma tâche k8s"
    echo "  k8s:"
    echo "    state: present"
    echo "    src: \"{{ temp_dir.path }}/deployment.yml\""
    echo "  register: deployment_result"
    echo "$ENVIRONMENT_PARAM"
}

# Exécution de la fonction principale
main
