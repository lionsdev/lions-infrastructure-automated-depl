# Transformation de sigctlv2 vers lionsctl

Ce document décrit les changements effectués pour transformer sigctlv2 en lionsctl, un outil adapté à l'infrastructure LIONS.

## Mise en place de la Registry Docker

### Modifications apportées

1. **Ajout de la Registry dans le playbook d'infrastructure**
   - Modification du playbook `deploy-infrastructure-services.yml` pour inclure le déploiement de la registry Docker
   - Configuration de la registry pour qu'elle soit accessible via `registry.lions.dev`
   - Utilisation du rôle Ansible existant pour la registry

### Configuration de la Registry

La registry Docker est configurée avec les paramètres suivants:
- Nom: registry
- Namespace: registry
- Domaine: registry.{environment}.lions.dev
- Stockage persistant: 10Gi
- Réplicas: variable selon l'environnement (1 pour development, 2 pour staging, 3 pour production)

## Transformation de sigctlv2 vers lionsctl

### Structure du projet

Création d'une nouvelle structure de projet pour lionsctl:
```
lionsctl/
├── cmd/                 # Commandes CLI
│   ├── build.go         # Commande de construction d'image
│   ├── clear.go         # Commande de nettoyage
│   ├── clone.go         # Commande de clonage de dépôt
│   ├── delete.go        # Commande de suppression
│   ├── deploy.go        # Commande de déploiement
│   ├── flags.go         # Définition des flags
│   ├── init.go          # Commande d'initialisation
│   ├── lionsctl.yaml    # Configuration embarquée
│   ├── notify.go        # Commande de notification
│   ├── pipeline.go      # Commande de pipeline complet
│   └── root.go          # Commande racine
├── lionsctl/            # Fonctionnalités principales
│   ├── add-ons/         # Templates additionnels
│   │   ├── deployment-with-volume.yaml
│   │   ├── deployment.yaml
│   │   ├── ingress-k1.yaml
│   │   ├── ingress-k2.yaml
│   │   └── pvc.yaml
│   ├── base/            # Templates de base
│   │   ├── Chart.yaml
│   │   ├── templates/
│   │   │   ├── config-map.yaml
│   │   │   └── service.yaml
│   │   └── values.yaml
│   ├── build.go         # Construction d'images Docker
│   ├── clear.go         # Nettoyage de répertoires
│   ├── clone.go         # Clonage de dépôts Git
│   ├── delete.go        # Suppression de configurations
│   ├── deploy.go        # Déploiement sur Kubernetes
│   ├── init.go          # Initialisation d'applications
│   ├── notify.go        # Notifications par email
│   ├── package.go       # Packaging d'applications
│   ├── pipeline.go      # Orchestration du pipeline
│   ├── update.go        # Mise à jour de configurations
│   └── utils.go         # Fonctions utilitaires
├── go.mod               # Définition du module Go
├── main.go              # Point d'entrée
└── README.md            # Documentation
```

### Modifications apportées

1. **Configuration**
   - Création d'un nouveau fichier de configuration `lionsctl.yaml`
   - Mise à jour des URLs pour pointer vers les ressources LIONS
   - Mise à jour de la registry Docker pour utiliser `registry.lions.dev`

2. **Commande racine**
   - Renommage de la commande de `sigctlv2` à `lionsctl`
   - Mise à jour des descriptions et de l'aide
   - Mise à jour du fichier de configuration utilisateur de `.sigctlv2.yaml` à `.lionsctl.yaml`

3. **Fonctionnalités principales**
   - Adaptation des fonctionnalités pour l'infrastructure LIONS
   - Mise à jour des chemins d'importation
   - Amélioration de la gestion des erreurs
   - Support des environnements LIONS (development, staging, production)

4. **Templates Kubernetes**
   - Mise à jour des templates pour utiliser les conventions LIONS
   - Ajout de labels et annotations standards
   - Configuration des ingress pour les domaines LIONS
   - Support des volumes persistants

5. **Documentation**
   - Création d'un nouveau README.md avec des exemples spécifiques à LIONS
   - Ajout d'instructions d'installation pour Linux, Windows et macOS
   - Mise à jour des exemples de commandes pour refléter l'infrastructure LIONS

## Travail réalisé

1. **Structure du projet**
   - Création de la structure complète du projet lionsctl
   - Adaptation de tous les fichiers source
   - Mise à jour des imports et dépendances

2. **Templates Kubernetes**
   - Adaptation des templates pour l'infrastructure LIONS
   - Mise à jour des domaines et des configurations
   - Support des différents environnements

3. **Configuration**
   - Mise à jour des fichiers de configuration
   - Adaptation pour la registry LIONS
   - Support des environnements LIONS

## Prochaines étapes

1. **Finalisation de la transformation**
   - Tests unitaires et d'intégration
   - Correction des bugs éventuels
   - Optimisation des performances

2. **Intégration avec l'infrastructure LIONS**
   - Tests de déploiement avec la registry
   - Intégration avec les environnements development, staging et production
   - Configuration des notifications

3. **Publication**
   - Création des releases pour différentes plateformes
   - Documentation complète
   - Formation des utilisateurs
