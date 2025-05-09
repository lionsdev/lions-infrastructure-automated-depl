#!/bin/bash
# Titre: Script de génération de documentation
# Description: Génère la documentation à partir des fichiers source
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-08
# Version: 1.0.0

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DOCS_DIR="${SCRIPT_DIR}/../docs"
readonly OUTPUT_DIR="${DOCS_DIR}/generated"

# Création du répertoire de sortie
mkdir -p "${OUTPUT_DIR}"

echo "Génération de la documentation..."

# Génération de la documentation des rôles Ansible
echo "Génération de la documentation des rôles Ansible..."
for role_dir in "${SCRIPT_DIR}"/../ansible/roles/*; do
    if [ -d "${role_dir}" ]; then
        role_name=$(basename "${role_dir}")
        echo "  - Rôle: ${role_name}"
        
        # Création du fichier de documentation pour le rôle
        mkdir -p "${OUTPUT_DIR}/ansible/roles/${role_name}"
        
        # Extraction des informations du rôle
        if [ -f "${role_dir}/meta/main.yml" ]; then
            echo "# Rôle Ansible: ${role_name}" > "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "## Description" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "$(grep -A2 "description:" "${role_dir}/meta/main.yml" | tail -n1 | sed "s/^[ ]*//g")" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
        else
            echo "# Rôle Ansible: ${role_name}" > "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "## Description" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "Aucune description disponible." >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
        fi
        
        # Ajout des variables
        if [ -d "${role_dir}/defaults" ]; then
            echo "## Variables par défaut" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "\`\`\`yaml" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            cat "${role_dir}/defaults/main.yml" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "\`\`\`" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
        fi
        
        # Ajout des tâches
        if [ -f "${role_dir}/tasks/main.yml" ]; then
            echo "## Tâches principales" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "\`\`\`yaml" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            cat "${role_dir}/tasks/main.yml" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "\`\`\`" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
            echo "" >> "${OUTPUT_DIR}/ansible/roles/${role_name}/README.md"
        fi
    fi
done

# Génération de la documentation des playbooks Ansible
echo "Génération de la documentation des playbooks Ansible..."
mkdir -p "${OUTPUT_DIR}/ansible/playbooks"
for playbook_file in "${SCRIPT_DIR}"/../ansible/playbooks/*.yml; do
    if [ -f "${playbook_file}" ]; then
        playbook_name=$(basename "${playbook_file}" .yml)
        echo "  - Playbook: ${playbook_name}"
        
        # Création du fichier de documentation pour le playbook
        echo "# Playbook Ansible: ${playbook_name}" > "${OUTPUT_DIR}/ansible/playbooks/${playbook_name}.md"
        echo "" >> "${OUTPUT_DIR}/ansible/playbooks/${playbook_name}.md"
        echo "## Description" >> "${OUTPUT_DIR}/ansible/playbooks/${playbook_name}.md"
        echo "" >> "${OUTPUT_DIR}/ansible/playbooks/${playbook_name}.md"
        
        # Extraction de la description du playbook
        description=$(grep -A2 "# Description:" "${playbook_file}" | tail -n1 | sed "s/^# //g")
        if [ -n "${description}" ]; then
            echo "${description}" >> "${OUTPUT_DIR}/ansible/playbooks/${playbook_name}.md"
        else
            echo "Aucune description disponible." >> "${OUTPUT_DIR}/ansible/playbooks/${playbook_name}.md"
        fi
        echo "" >> "${OUTPUT_DIR}/ansible/playbooks/${playbook_name}.md"
        
        # Ajout du contenu du playbook
        echo "## Contenu" >> "${OUTPUT_DIR}/ansible/playbooks/${playbook_name}.md"
        echo "" >> "${OUTPUT_DIR}/ansible/playbooks/${playbook_name}.md"
        echo "\`\`\`yaml" >> "${OUTPUT_DIR}/ansible/playbooks/${playbook_name}.md"
        cat "${playbook_file}" >> "${OUTPUT_DIR}/ansible/playbooks/${playbook_name}.md"
        echo "\`\`\`" >> "${OUTPUT_DIR}/ansible/playbooks/${playbook_name}.md"
        echo "" >> "${OUTPUT_DIR}/ansible/playbooks/${playbook_name}.md"
    fi
done

# Génération de la documentation des configurations Kubernetes
echo "Génération de la documentation des configurations Kubernetes..."
mkdir -p "${OUTPUT_DIR}/kubernetes"

# Documentation des configurations de base
echo "  - Configurations de base"
mkdir -p "${OUTPUT_DIR}/kubernetes/base"
for base_dir in "${SCRIPT_DIR}"/../kubernetes/base/*; do
    if [ -d "${base_dir}" ]; then
        base_name=$(basename "${base_dir}")
        echo "    - ${base_name}"
        
        # Création du fichier de documentation pour la configuration de base
        mkdir -p "${OUTPUT_DIR}/kubernetes/base/${base_name}"
        echo "# Configuration Kubernetes de base: ${base_name}" > "${OUTPUT_DIR}/kubernetes/base/${base_name}/README.md"
        echo "" >> "${OUTPUT_DIR}/kubernetes/base/${base_name}/README.md"
        echo "## Fichiers" >> "${OUTPUT_DIR}/kubernetes/base/${base_name}/README.md"
        echo "" >> "${OUTPUT_DIR}/kubernetes/base/${base_name}/README.md"
        
        # Liste des fichiers
        for file in "${base_dir}"/*; do
            if [ -f "${file}" ]; then
                file_name=$(basename "${file}")
                echo "- ${file_name}" >> "${OUTPUT_DIR}/kubernetes/base/${base_name}/README.md"
            fi
        done
        echo "" >> "${OUTPUT_DIR}/kubernetes/base/${base_name}/README.md"
        
        # Contenu des fichiers
        for file in "${base_dir}"/*; do
            if [ -f "${file}" ]; then
                file_name=$(basename "${file}")
                echo "### ${file_name}" >> "${OUTPUT_DIR}/kubernetes/base/${base_name}/README.md"
                echo "" >> "${OUTPUT_DIR}/kubernetes/base/${base_name}/README.md"
                echo "\`\`\`yaml" >> "${OUTPUT_DIR}/kubernetes/base/${base_name}/README.md"
                cat "${file}" >> "${OUTPUT_DIR}/kubernetes/base/${base_name}/README.md"
                echo "\`\`\`" >> "${OUTPUT_DIR}/kubernetes/base/${base_name}/README.md"
                echo "" >> "${OUTPUT_DIR}/kubernetes/base/${base_name}/README.md"
            fi
        done
    fi
done

# Documentation des overlays
echo "  - Overlays"
mkdir -p "${OUTPUT_DIR}/kubernetes/overlays"
for overlay_dir in "${SCRIPT_DIR}"/../kubernetes/overlays/*; do
    if [ -d "${overlay_dir}" ]; then
        overlay_name=$(basename "${overlay_dir}")
        echo "    - ${overlay_name}"
        
        # Création du fichier de documentation pour l'overlay
        mkdir -p "${OUTPUT_DIR}/kubernetes/overlays/${overlay_name}"
        echo "# Overlay Kubernetes: ${overlay_name}" > "${OUTPUT_DIR}/kubernetes/overlays/${overlay_name}/README.md"
        echo "" >> "${OUTPUT_DIR}/kubernetes/overlays/${overlay_name}/README.md"
        echo "## Patches" >> "${OUTPUT_DIR}/kubernetes/overlays/${overlay_name}/README.md"
        echo "" >> "${OUTPUT_DIR}/kubernetes/overlays/${overlay_name}/README.md"
        
        # Liste des patches
        if [ -d "${overlay_dir}/patches" ]; then
            for patch_file in "${overlay_dir}/patches"/*; do
                if [ -f "${patch_file}" ]; then
                    patch_name=$(basename "${patch_file}")
                    echo "- ${patch_name}" >> "${OUTPUT_DIR}/kubernetes/overlays/${overlay_name}/README.md"
                fi
            done
            echo "" >> "${OUTPUT_DIR}/kubernetes/overlays/${overlay_name}/README.md"
            
            # Contenu des patches
            for patch_file in "${overlay_dir}/patches"/*; do
                if [ -f "${patch_file}" ]; then
                    patch_name=$(basename "${patch_file}")
                    echo "### ${patch_name}" >> "${OUTPUT_DIR}/kubernetes/overlays/${overlay_name}/README.md"
                    echo "" >> "${OUTPUT_DIR}/kubernetes/overlays/${overlay_name}/README.md"
                    echo "\`\`\`yaml" >> "${OUTPUT_DIR}/kubernetes/overlays/${overlay_name}/README.md"
                    cat "${patch_file}" >> "${OUTPUT_DIR}/kubernetes/overlays/${overlay_name}/README.md"
                    echo "\`\`\`" >> "${OUTPUT_DIR}/kubernetes/overlays/${overlay_name}/README.md"
                    echo "" >> "${OUTPUT_DIR}/kubernetes/overlays/${overlay_name}/README.md"
                fi
            done
        else
            echo "Aucun patch trouvé." >> "${OUTPUT_DIR}/kubernetes/overlays/${overlay_name}/README.md"
            echo "" >> "${OUTPUT_DIR}/kubernetes/overlays/${overlay_name}/README.md"
        fi
    fi
done

# Génération de la documentation des scripts
echo "Génération de la documentation des scripts..."
mkdir -p "${OUTPUT_DIR}/scripts"
for script_file in "${SCRIPT_DIR}"/*.sh; do
    if [ -f "${script_file}" ]; then
        script_name=$(basename "${script_file}" .sh)
        echo "  - Script: ${script_name}"
        
        # Création du fichier de documentation pour le script
        echo "# Script: ${script_name}" > "${OUTPUT_DIR}/scripts/${script_name}.md"
        echo "" >> "${OUTPUT_DIR}/scripts/${script_name}.md"
        echo "## Description" >> "${OUTPUT_DIR}/scripts/${script_name}.md"
        echo "" >> "${OUTPUT_DIR}/scripts/${script_name}.md"
        
        # Extraction de la description du script
        description=$(grep -A2 "# Description:" "${script_file}" | tail -n1 | sed "s/^# //g")
        if [ -n "${description}" ]; then
            echo "${description}" >> "${OUTPUT_DIR}/scripts/${script_name}.md"
        else
            echo "Aucune description disponible." >> "${OUTPUT_DIR}/scripts/${script_name}.md"
        fi
        echo "" >> "${OUTPUT_DIR}/scripts/${script_name}.md"
        
        # Extraction de l'aide du script
        echo "## Utilisation" >> "${OUTPUT_DIR}/scripts/${script_name}.md"
        echo "" >> "${OUTPUT_DIR}/scripts/${script_name}.md"
        if grep -q "function afficher_aide" "${script_file}"; then
            help_text=$(grep -A20 "cat << EOF" "${script_file}" | grep -B20 "EOF" | grep -v "cat\|EOF")
            echo "\`\`\`" >> "${OUTPUT_DIR}/scripts/${script_name}.md"
            echo "${help_text}" >> "${OUTPUT_DIR}/scripts/${script_name}.md"
            echo "\`\`\`" >> "${OUTPUT_DIR}/scripts/${script_name}.md"
        else
            echo "Aucune aide disponible." >> "${OUTPUT_DIR}/scripts/${script_name}.md"
        fi
        echo "" >> "${OUTPUT_DIR}/scripts/${script_name}.md"
    fi
done

# Génération de l'index de la documentation
echo "Génération de l'index de la documentation..."
echo "# Documentation générée de l'infrastructure LIONS" > "${OUTPUT_DIR}/index.md"
echo "" >> "${OUTPUT_DIR}/index.md"
echo "Documentation générée automatiquement le $(date +"%Y-%m-%d à %H:%M:%S")." >> "${OUTPUT_DIR}/index.md"
echo "" >> "${OUTPUT_DIR}/index.md"

echo "## Rôles Ansible" >> "${OUTPUT_DIR}/index.md"
echo "" >> "${OUTPUT_DIR}/index.md"
for role_dir in "${SCRIPT_DIR}"/../ansible/roles/*; do
    if [ -d "${role_dir}" ]; then
        role_name=$(basename "${role_dir}")
        echo "- [${role_name}](ansible/roles/${role_name}/README.md)" >> "${OUTPUT_DIR}/index.md"
    fi
done
echo "" >> "${OUTPUT_DIR}/index.md"

echo "## Playbooks Ansible" >> "${OUTPUT_DIR}/index.md"
echo "" >> "${OUTPUT_DIR}/index.md"
for playbook_file in "${SCRIPT_DIR}"/../ansible/playbooks/*.yml; do
    if [ -f "${playbook_file}" ]; then
        playbook_name=$(basename "${playbook_file}" .yml)
        echo "- [${playbook_name}](ansible/playbooks/${playbook_name}.md)" >> "${OUTPUT_DIR}/index.md"
    fi
done
echo "" >> "${OUTPUT_DIR}/index.md"

echo "## Configurations Kubernetes" >> "${OUTPUT_DIR}/index.md"
echo "" >> "${OUTPUT_DIR}/index.md"
echo "### Base" >> "${OUTPUT_DIR}/index.md"
echo "" >> "${OUTPUT_DIR}/index.md"
for base_dir in "${SCRIPT_DIR}"/../kubernetes/base/*; do
    if [ -d "${base_dir}" ]; then
        base_name=$(basename "${base_dir}")
        echo "- [${base_name}](kubernetes/base/${base_name}/README.md)" >> "${OUTPUT_DIR}/index.md"
    fi
done
echo "" >> "${OUTPUT_DIR}/index.md"

echo "### Overlays" >> "${OUTPUT_DIR}/index.md"
echo "" >> "${OUTPUT_DIR}/index.md"
for overlay_dir in "${SCRIPT_DIR}"/../kubernetes/overlays/*; do
    if [ -d "${overlay_dir}" ]; then
        overlay_name=$(basename "${overlay_dir}")
        echo "- [${overlay_name}](kubernetes/overlays/${overlay_name}/README.md)" >> "${OUTPUT_DIR}/index.md"
    fi
done
echo "" >> "${OUTPUT_DIR}/index.md"

echo "## Scripts" >> "${OUTPUT_DIR}/index.md"
echo "" >> "${OUTPUT_DIR}/index.md"
for script_file in "${SCRIPT_DIR}"/*.sh; do
    if [ -f "${script_file}" ]; then
        script_name=$(basename "${script_file}" .sh)
        echo "- [${script_name}](scripts/${script_name}.md)" >> "${OUTPUT_DIR}/index.md"
    fi
done
echo "" >> "${OUTPUT_DIR}/index.md"

echo "Documentation générée avec succès dans ${OUTPUT_DIR}"
echo "Vous pouvez consulter l'index à ${OUTPUT_DIR}/index.md"