# Architecture de l'Infrastructure LIONS

## Vue d'Ensemble

L'infrastructure LIONS est une plateforme complète basée sur Kubernetes (K3s) qui fournit un environnement de déploiement automatisé pour les applications et services. Cette infrastructure est conçue pour être robuste, sécurisée, évolutive et facile à maintenir.

## Composants Principaux

### Couche d'Infrastructure de Base

#### K3s
- **Description** : Distribution légère de Kubernetes
- **Rôle** : Orchestration des conteneurs et gestion du cluster
- **Composants clés** : 
  - API Server
  - Controller Manager
  - Scheduler
  - etcd (base de données de configuration)
  - Kubelet
  - Kube-proxy

#### Traefik
- **Description** : Contrôleur d'Ingress et proxy inverse
- **Rôle** : Routage du trafic HTTP/HTTPS vers les services appropriés
- **Fonctionnalités** :
  - Terminaison TLS
  - Routage basé sur les hôtes et les chemins
  - Middleware pour la transformation des requêtes
  - Load balancing

#### Cert-Manager
- **Description** : Gestionnaire de certificats TLS
- **Rôle** : Automatisation de l'émission et du renouvellement des certificats TLS
- **Intégrations** :
  - Let's Encrypt (ACME)
  - ClusterIssuers pour la gestion des certificats à l'échelle du cluster

### Couche de Stockage

#### StorageClasses
- **Description** : Classes de stockage pour les volumes persistants
- **Types** :
  - `standard` : Stockage par défaut basé sur local-path
  - `local-path` : Stockage local sur le nœud

### Couche de Sécurité

#### RBAC (Role-Based Access Control)
- **Description** : Contrôle d'accès basé sur les rôles
- **Rôles définis** :
  - `lions-admin` : Accès complet à toutes les ressources
  - `lions-developer` : Accès limité pour les développeurs
  - `lions-operator` : Accès pour les opérations de maintenance
  - `lions-monitoring` : Accès en lecture seule pour le monitoring

#### Network Policies
- **Description** : Politiques de sécurité réseau
- **Politiques définies** :
  - `default-deny-ingress` : Bloque tout trafic entrant par défaut
  - `allow-same-namespace` : Autorise le trafic au sein du même namespace
  - `allow-monitoring` : Autorise le trafic depuis le namespace monitoring
  - Politiques spécifiques pour chaque type d'application

#### Pod Security Standards
- **Description** : Standards de sécurité pour les pods
- **Niveaux** :
  - `baseline` : Niveau de sécurité par défaut
  - `restricted` : Niveau de sécurité élevé pour les audits

### Couche de Monitoring et Logging

#### Prometheus
- **Description** : Système de collecte et de stockage de métriques
- **Composants** :
  - Prometheus Server
  - AlertManager
  - Node Exporter
  - Kube State Metrics

#### Grafana
- **Description** : Plateforme de visualisation et d'analyse
- **Fonctionnalités** :
  - Tableaux de bord personnalisés
  - Alertes
  - Annotations

#### Loki
- **Description** : Système de collecte et d'indexation de logs
- **Composants** :
  - Loki Server
  - Promtail (agent de collecte de logs)

### Couche de Services d'Infrastructure

#### PostgreSQL
- **Description** : Base de données relationnelle
- **Utilisation** : Stockage des données persistantes pour les applications
- **Déploiement** : StatefulSet avec volume persistant

#### PgAdmin
- **Description** : Interface d'administration pour PostgreSQL
- **Utilisation** : Gestion des bases de données PostgreSQL
- **Accès** : https://pgadmin.lions.dev

#### Gitea
- **Description** : Serveur Git auto-hébergé
- **Utilisation** : Gestion des dépôts de code source
- **Accès** : https://git.lions.dev

#### Keycloak
- **Description** : Gestionnaire d'identité et d'accès
- **Utilisation** : Authentification et autorisation centralisées
- **Accès** : https://keycloak.lions.dev

#### Ollama
- **Description** : Plateforme d'IA pour l'exécution de modèles de langage
- **Utilisation** : Services d'IA pour les applications
- **Accès** : https://ollama.lions.dev

### Couche d'Applications

#### Applications Quarkus
- **Description** : Applications backend basées sur Quarkus
- **Déploiement** : Deployments avec ConfigMaps et Secrets
- **Exposition** : Via Ingress Traefik

#### Applications Web
- **Description** : Applications frontend
- **Types** :
  - PrimeFaces (JSF)
  - PrimeReact (React)
- **Déploiement** : Deployments avec ConfigMaps
- **Exposition** : Via Ingress Traefik

## Architecture Réseau

### Ingress
- Tout le trafic externe entre par Traefik
- Terminaison TLS au niveau de Traefik
- Routage basé sur les hôtes et les chemins vers les services appropriés

### Services
- Services ClusterIP pour la communication interne
- Services NodePort pour l'exposition externe (Grafana, Kubernetes Dashboard)

### Network Policies
- Isolation réseau entre les namespaces
- Communication contrôlée entre les services
- Accès externe limité aux services exposés

## Déploiement et CI/CD

### GitOps avec Flux CD
- **Description** : Approche GitOps pour la gestion de l'infrastructure
- **Composants** :
  - Flux Controllers
  - Source Controller
  - Kustomize Controller
- **Workflow** :
  - Les changements sont poussés vers le dépôt Git
  - Flux détecte les changements et les applique au cluster
  - Réconciliation continue entre l'état souhaité et l'état réel

### Sauvegarde et Restauration
- **Description** : Mécanismes de sauvegarde et de restauration
- **Composants** :
  - Script de sauvegarde et restauration
  - Sauvegarde des ressources Kubernetes
  - Sauvegarde des données persistantes

## Namespaces

L'infrastructure est organisée en plusieurs namespaces pour isoler les différentes parties du système :

- `kube-system` : Composants système de Kubernetes
- `cert-manager` : Cert-Manager et ressources associées
- `monitoring` : Prometheus, Grafana et autres outils de monitoring
- `logging` : Loki et Promtail
- `lions-infrastructure` : Services d'infrastructure communs
- `flux-system` : Composants de Flux CD
- `postgres-<env>` : Base de données PostgreSQL
- `pgadmin-<env>` : Interface d'administration PgAdmin
- `gitea-<env>` : Serveur Git Gitea
- `keycloak-<env>` : Serveur d'authentification Keycloak
- `ollama-<env>` : Service d'IA Ollama
- Namespaces spécifiques pour chaque application

## Environnements

L'infrastructure supporte plusieurs environnements :

- `development` : Environnement de développement
- `staging` : Environnement de pré-production
- `production` : Environnement de production

Chaque environnement a ses propres ressources et configurations, gérées via Kustomize.

## Diagramme d'Architecture

```
                                   ┌─────────────────────┐
                                   │     Internet        │
                                   └──────────┬──────────┘
                                              │
                                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                               VPS                                        │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                        K3s Cluster                               │    │
│  │                                                                  │    │
│  │  ┌────────────┐    ┌────────────┐    ┌────────────────────────┐ │    │
│  │  │   Traefik   │◄───┤ Cert-Manager│    │    Flux CD            │ │    │
│  │  └─────┬──────┘    └────────────┘    └────────────────────────┘ │    │
│  │        │                                                         │    │
│  │        ▼                                                         │    │
│  │  ┌─────────────────────────────────────────────────────────┐    │    │
│  │  │                   Services                               │    │    │
│  │  │                                                          │    │    │
│  │  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐    │    │    │
│  │  │  │PostgreSQL│ │ PgAdmin  │ │  Gitea   │ │ Keycloak │    │    │    │
│  │  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘    │    │    │
│  │  │                                                          │    │    │
│  │  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐    │    │    │
│  │  │  │ Ollama   │ │Prometheus│ │ Grafana  │ │   Loki   │    │    │    │
│  │  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘    │    │    │
│  │  │                                                          │    │    │
│  │  │  ┌──────────────────────────────────────────────────┐   │    │    │
│  │  │  │              Applications                         │   │    │    │
│  │  │  │                                                   │   │    │    │
│  │  │  │  ┌──────────┐ ┌──────────┐ ┌──────────┐          │   │    │    │
│  │  │  │  │  API     │ │Frontend  │ │ Services │          │   │    │    │
│  │  │  │  └──────────┘ └──────────┘ └──────────┘          │   │    │    │
│  │  │  └──────────────────────────────────────────────────┘   │    │    │
│  │  └─────────────────────────────────────────────────────────┘    │    │
│  │                                                                  │    │
│  │  ┌─────────────────────────────────────────────────────────┐    │    │
│  │  │                   Storage                                │    │    │
│  │  │                                                          │    │    │
│  │  │  ┌──────────────────┐  ┌──────────────────────────────┐ │    │    │
│  │  │  │ Persistent Volumes│  │      ConfigMaps & Secrets     │ │    │    │
│  │  │  └──────────────────┘  └──────────────────────────────┘ │    │    │
│  │  └─────────────────────────────────────────────────────────┘    │    │
│  └──────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

## Conclusion

L'architecture de l'infrastructure LIONS est conçue pour être modulaire, évolutive et sécurisée. Elle fournit tous les composants nécessaires pour déployer et gérer des applications dans un environnement Kubernetes, avec une approche GitOps pour la gestion de l'infrastructure comme code.