# LIONS Infrastructure v5.0

Ce dépôt contient les scripts et configurations pour déployer l'infrastructure LIONS sur un VPS, ainsi que l'outil `lionsctl` pour déployer des applications sur cette infrastructure.

## Table des matières

1. [Introduction](#introduction)
2. [Structure du projet](#structure-du-projet)
3. [Configuration avec variables d'environnement](#configuration-avec-variables-denvironnement)
4. [Installation](#installation)
5. [Utilisation de lionsctl](#utilisation-de-lionsctl)
6. [Déploiement d'applications](#déploiement-dapplications)
7. [Guides](#guides)
8. [Dépannage](#dépannage)

## Introduction

L'infrastructure LIONS est une plateforme Kubernetes complète déployée sur un VPS. Elle inclut:

- K3s comme distribution Kubernetes légère
- Traefik comme Ingress Controller
- Cert-Manager pour la gestion des certificats TLS
- MetalLB pour le LoadBalancer
- Monitoring avec Prometheus et Grafana
- Kubernetes Dashboard pour l'administration
- Vault pour la gestion des secrets
- Registry pour les images Docker
- Keycloak pour l'authentification
- PostgreSQL et Redis pour le stockage de données
- Gitea pour la gestion de code source
- Ollama pour l'IA

## Structure du projet

```
lions-infrastructure-automated-depl/
├── .env                      # Configuration principale avec variables d'environnement
├── .github/                  # Workflows GitHub Actions
├── deployment/               # Scripts de déploiement (obsolète, utilisez lions-infrastructure)
├── lions-infrastructure/     # Infrastructure principale
│   ├── ansible/              # Playbooks et rôles Ansible
│   ├── applications/         # Templates d'applications
│   ├── docs/                 # Documentation
│   ├── kubernetes/           # Configurations Kubernetes
│   ├── monitoring/           # Configurations de monitoring
│   └── scripts/              # Scripts d'installation et de maintenance
└── lionsctl/                 # Outil de déploiement d'applications
    ├── cmd/                  # Commandes CLI
    └── lionsctl/             # Logique de déploiement
```

## Configuration avec variables d'environnement

Toute la configuration de l'infrastructure et de l'outil `lionsctl` est gérée via des variables d'environnement. Le fichier `.env` à la racine du projet contient toutes les variables d'environnement nécessaires avec des valeurs par défaut.

### Principales catégories de variables

- **LIONS_ENVIRONMENT**: Environnement de déploiement (development, staging, production)
- **LIONS_VPS_***: Configuration du VPS (hôte, port, utilisateur)
- **LIONS_K3S_***: Configuration de K3s
- **LIONS_VAULT_***: Configuration de Vault
- **LIONS_GIT_***: Configuration Git pour lionsctl
- **LIONS_DOCKER_***: Configuration Docker pour lionsctl

### Utilisation des variables d'environnement

1. Copiez le fichier `.env` et modifiez les valeurs selon vos besoins
2. Chargez les variables d'environnement avant d'exécuter les scripts:
   ```bash
   source .env
   ```
3. Ou passez-les directement lors de l'exécution:
   ```bash
   LIONS_ENVIRONMENT=production ./lions-infrastructure/scripts/install.sh
   ```

## Installation

### Installation à distance (recommandée)

L'installation à distance est la méthode **recommandée** car elle évite les problèmes de compatibilité, notamment avec WSL2 (Windows Subsystem for Linux).

```bash
# Chargez les variables d'environnement
source .env

# Exécutez le script d'installation à distance
./lions-infrastructure/scripts/remote-install.sh
```

### Installation locale

Si vous préférez exécuter l'installation depuis votre machine locale:

```bash
# Chargez les variables d'environnement
source .env

# Exécutez le script d'installation
./lions-infrastructure/scripts/install.sh
```

## Utilisation de lionsctl

`lionsctl` est un outil de ligne de commande pour construire et déployer des applications sur l'infrastructure LIONS.

### Installation de lionsctl

```bash
# Clonez le dépôt
git clone https://github.com/lionsdev/lionsctl.git

# Construisez lionsctl
cd lionsctl
go build -o lionsctl

# Déplacez l'exécutable dans votre PATH
sudo mv lionsctl /usr/local/bin/
```

### Configuration de lionsctl

`lionsctl` utilise les variables d'environnement avec le préfixe `LIONS_` pour sa configuration. Vous pouvez:

1. Utiliser le fichier `.env` à la racine du projet
2. Définir les variables d'environnement manuellement
3. Utiliser un fichier `.lionsctl.yaml` dans votre répertoire personnel (obsolète, utilisez les variables d'environnement)

## Déploiement d'applications

### Initialiser une application

```bash
# Chargez les variables d'environnement
source .env

# Initialisez une application
lionsctl init -n mon-application -e development -i
```

### Déployer une application

```bash
# Chargez les variables d'environnement
source .env

# Déployez une application
lionsctl pipeline -u https://github.com/lionsdev/mon-application -b main -e development
```

## Guides

- [Guide d'installation à distance](lions-infrastructure/docs/guides/remote-installation.md)
- [Guide d'utilisation](lions-infrastructure/docs/guides/user-guide.md)
- [Guide de maintenance](lions-infrastructure/docs/guides/maintenance-guide.md)

## Dépannage

Si vous rencontrez des problèmes lors de l'installation:

1. Consultez les logs d'installation dans le répertoire `lions-infrastructure/scripts/logs/`
2. Vérifiez que les prérequis sont bien respectés
3. Consultez le [Guide d'installation à distance](lions-infrastructure/docs/guides/remote-installation.md) pour les problèmes spécifiques à WSL2
4. Si le problème persiste, ouvrez une issue sur le dépôt GitHub