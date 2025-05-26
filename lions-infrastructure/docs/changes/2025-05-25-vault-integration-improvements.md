# Améliorations de l'intégration HashiCorp Vault

## Date: 2025-05-25
## Auteur: Équipe LIONS Infrastructure
## Version: 1.0.0

## Résumé

Ce document décrit les améliorations apportées à l'intégration de HashiCorp Vault dans l'infrastructure LIONS. Ces modifications visent à renforcer la sécurité et la fiabilité de la gestion des secrets dans l'infrastructure.

## Modifications apportées

### 1. Amélioration de la sécurité pour le stockage des données d'initialisation de Vault

Les données d'initialisation de Vault (clés de déverrouillage et token root) sont désormais stockées dans un répertoire sécurisé avec des permissions restreintes :

- Création d'un répertoire dédié `/etc/vault.d/secure` avec permissions 0700 (lecture/écriture/exécution uniquement pour le propriétaire)
- Stockage du fichier `vault-init.json` dans ce répertoire avec permissions 0600 (lecture/écriture uniquement pour le propriétaire)
- Mise à jour de toutes les références dans les playbooks pour utiliser ce nouveau chemin

Cette modification réduit considérablement le risque d'accès non autorisé aux informations sensibles de Vault.

### 2. Vérification de l'état de Vault avant l'installation de K3s

Le script d'installation vérifie désormais l'état de Vault avant de procéder à l'installation de K3s :

- Vérification que le service Vault est actif et accessible
- Vérification que Vault est initialisé et déverrouillé
- Avertissements appropriés si Vault n'est pas correctement configuré
- Option pour l'utilisateur de continuer ou d'annuler l'installation si Vault n'est pas accessible

Cette vérification permet d'éviter les échecs d'installation de K3s dus à l'indisponibilité de Vault lorsque des secrets sont nécessaires.

## Fichiers modifiés

1. `ansible/playbooks/install-vault.yml` - Amélioration de la sécurité pour le stockage des données d'initialisation
2. `scripts/install.sh` - Ajout de vérifications de l'état de Vault avant l'installation de K3s

## Utilisation

Aucune modification des procédures d'installation n'est nécessaire. Les améliorations sont automatiquement appliquées lors de l'exécution du script d'installation.

## Considérations de sécurité

Bien que ces modifications améliorent la sécurité de l'intégration de Vault, il est important de noter que :

1. Le fichier `vault-init.json` contient des informations très sensibles et doit être sauvegardé de manière sécurisée en dehors du serveur pour la récupération en cas de désastre.
2. Dans un environnement de production, il est recommandé d'utiliser un système de gestion des secrets externe (comme un HSM) pour stocker les clés de déverrouillage de Vault.
3. La configuration actuelle utilise l'authentification par token, qui devrait être remplacée par des méthodes d'authentification plus sécurisées (comme AppRole ou Kubernetes) dans un environnement de production.

## Prochaines étapes

Pour améliorer davantage l'intégration de Vault, les actions suivantes sont recommandées :

1. Implémenter l'auto-unseal de Vault avec un KMS externe (AWS KMS, GCP KMS, Azure Key Vault)
2. Configurer la réplication de Vault pour la haute disponibilité
3. Mettre en place une rotation automatique des secrets
4. Développer des procédures de récupération en cas de désastre détaillées