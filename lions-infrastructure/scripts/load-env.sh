#!/bin/bash
# Titre: Script de chargement des variables d'environnement
# Description: Charge les variables d'environnement depuis le fichier .env
# Auteur: Équipe LIONS Infrastructure
# Date: 18/05/2025
# Version: 1.0.0

# Chemin du fichier .env
ENV_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.env"

# Fonction pour charger les variables d'environnement
function load_env_vars() {
    if [ -f "$ENV_FILE" ]; then
        echo "Chargement des variables d'environnement depuis $ENV_FILE"

        # Lecture du fichier .env ligne par ligne
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Ignorer les lignes vides et les commentaires
            if [[ -z "$line" || "$line" =~ ^# ]]; then
                continue
            fi

            # Extraction de la variable et de sa valeur
            if [[ "$line" =~ ^([A-Za-z0-9_]+)=(.*)$ ]]; then
                var_name="${BASH_REMATCH[1]}"
                var_value="${BASH_REMATCH[2]}"

                # Suppression des guillemets si présents
                var_value="${var_value%\"}"
                var_value="${var_value#\"}"

                # Expansion des variables dans la valeur
                # Méthode plus robuste pour l'expansion des variables
                if [[ "$var_value" == *'$'* ]]; then
                    # Échappement des guillemets pour éviter les erreurs d'évaluation
                    escaped_value=$(echo "$var_value" | sed 's/"/\\"/g')
                    # Utilisation d'une méthode plus sûre pour l'évaluation
                    eval "expanded_value=\"$escaped_value\""
                    var_value="$expanded_value"
                fi

                # Export de la variable
                export "$var_name=$var_value"

                # Affichage de la variable chargée (sauf pour les variables sensibles)
                if [[ ! "$var_name" =~ PASSWORD|SECRET|TOKEN ]]; then
                    echo "  $var_name=$var_value"
                else
                    echo "  $var_name=********"
                fi
            fi
        done < "$ENV_FILE"

        echo "Variables d'environnement chargées avec succès"
    else
        echo "Erreur: Fichier .env non trouvé à $ENV_FILE"
        return 1
    fi
}

# Chargement des variables d'environnement
load_env_vars
