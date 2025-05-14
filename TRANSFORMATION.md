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
├── cmd/
│   ├── lionsctl.yaml    # Configuration embarquée
│   └── root.go          # Commande racine
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

3. **Documentation**
   - Création d'un nouveau README.md avec des exemples spécifiques à LIONS
   - Ajout d'instructions d'installation pour Linux, Windows et macOS
   - Mise à jour des exemples de commandes pour refléter l'infrastructure LIONS

## Prochaines étapes

1. **Finalisation de la transformation**
   - Adaptation des sous-commandes (init, pipeline, etc.)
   - Mise à jour des templates Kubernetes
   - Tests complets de l'outil

2. **Intégration avec l'infrastructure LIONS**
   - Tests de déploiement avec la registry
   - Intégration avec les environnements development, staging et production
   - Configuration des notifications

3. **Publication**
   - Création des releases pour différentes plateformes
   - Documentation complète
   - Formation des utilisateurs