# Infrastructure LIONS

Ce dépôt contient les scripts et configurations pour déployer l'infrastructure LIONS sur un VPS.

## Table des matières

1. [Introduction](#introduction)
2. [Prérequis](#prérequis)
3. [Installation](#installation)
   - [Installation à distance (recommandée)](#installation-à-distance-recommandée)
   - [Installation locale](#installation-locale)
4. [Structure du projet](#structure-du-projet)
5. [Guides](#guides)
6. [Dépannage](#dépannage)

## Introduction

L'infrastructure LIONS est une plateforme Kubernetes complète déployée sur un VPS. Elle inclut:

- K3s comme distribution Kubernetes légère
- Traefik comme Ingress Controller
- Cert-Manager pour la gestion des certificats TLS
- MetalLB pour le LoadBalancer
- Monitoring avec Prometheus et Grafana
- Kubernetes Dashboard pour l'administration

## Prérequis

- Un VPS avec au moins 2 CPU, 4 Go de RAM et 20 Go d'espace disque
- Ubuntu 20.04 LTS ou plus récent
- Accès SSH au VPS avec privilèges root
- Ports ouverts: 22 (SSH), 80 (HTTP), 443 (HTTPS), 6443 (Kubernetes API)

## Installation

### Installation à distance (recommandée)

L'installation à distance est la méthode **recommandée** car elle évite les problèmes de compatibilité, notamment avec WSL2 (Windows Subsystem for Linux).

Nous fournissons un script `remote-install.sh` qui automatise le processus d'installation à distance:

```bash
cd lions-infrastructure/scripts
chmod +x remote-install.sh
./remote-install.sh --host <IP_DU_VPS> --port <PORT_SSH> --user <UTILISATEUR_SSH> --environment <ENVIRONNEMENT>
```

Exemple:
```bash
./remote-install.sh --host 176.57.150.2 --port 225 --user root --environment development
```

Pour plus de détails, consultez le [Guide d'installation à distance](docs/guides/remote-installation.md).

### Installation locale

Si vous préférez exécuter l'installation depuis votre machine locale, vous pouvez utiliser le script `install.sh`:

```bash
cd lions-infrastructure/scripts
chmod +x install.sh
./install.sh --environment <ENVIRONNEMENT>
```

**Note importante**: L'installation locale peut rencontrer des problèmes de compatibilité, en particulier si vous utilisez WSL2 sous Windows. Nous recommandons fortement l'installation à distance.

## Structure du projet

```
lions-infrastructure/
├── ansible/              # Playbooks et rôles Ansible
├── applications/         # Templates d'applications
├── docs/                 # Documentation
├── kubernetes/           # Configurations Kubernetes
│   ├── base/             # Configurations de base
│   └── overlays/         # Overlays spécifiques aux environnements
├── monitoring/           # Configurations de monitoring
└── scripts/              # Scripts d'installation et de maintenance
```

## Guides

- [Guide d'installation à distance](docs/guides/remote-installation.md)
- [Guide d'utilisation](docs/guides/user-guide.md)
- [Guide de maintenance](docs/guides/maintenance-guide.md)

## Dépannage

Si vous rencontrez des problèmes lors de l'installation:

1. Consultez les logs d'installation dans le répertoire `scripts/logs/`
2. Vérifiez que les prérequis sont bien respectés
3. Consultez le [Guide d'installation à distance](docs/guides/remote-installation.md) pour les problèmes spécifiques à WSL2
4. Si le problème persiste, ouvrez une issue sur le dépôt GitHub