# LIONS Infrastructure Deployment Tool

**lionsctl** est un outil de ligne de commande pour construire et déployer des applications sur l'infrastructure LIONS.

## Installation de `lionsctl`

Téléchargez l'exécutable correspondant à votre système d'exploitation:

### Linux

- Téléchargez le fichier **tar.gz** depuis la page [https://github.com/lionsdev/lionsctl/releases](https://github.com/lionsdev/lionsctl/releases)
- Extrayez lionsctl.tar.gz dans votre PATH (exemple: /usr/local/bin)
  ```bash
  sudo tar -xzvf lionsctl-1.0.0-Linux-x86-64.tar.gz -C /usr/local/bin/ lionsctl
  ```

### Windows

- Téléchargez le fichier **zip** depuis la page [https://github.com/lionsdev/lionsctl/releases](https://github.com/lionsdev/lionsctl/releases)
- Décompressez le fichier
- Ajoutez l'exécutable dans votre PATH via `Panneau de configuration > Système et sécurité > Système > Paramètres système avancés > Variables d'environnement`

### macOS

- Téléchargez le fichier **tar.gz** depuis la page [https://github.com/lionsdev/lionsctl/releases](https://github.com/lionsdev/lionsctl/releases)
- Extrayez lionsctl.tar.gz dans votre PATH (exemple: /usr/local/bin)
  ```bash
  sudo tar -xzvf lionsctl-1.0.0-Darwin-x86-64.tar.gz -C /usr/local/bin/ lionsctl
  ```

## Prérequis

- Docker
- Accès à l'infrastructure LIONS (VPN ou réseau autorisé)
- Identifiants GitHub pour accéder aux dépôts LIONS

## Commandes principales

### Afficher l'aide

```bash
lionsctl -h
```

### Configurer une application

#### Initialiser la configuration

```bash
lionsctl init -n mon-application -e development -i
```

**Paramètres:**
- `-n, --name`: Nom de l'application à initialiser
- `-e, --environment`: Environnement cible (development, staging, production)
- `-i, --ingress`: L'application est accessible de l'extérieur (a un ingress)
- `-v, --volume`: L'application a besoin d'un volume persistant

#### Supprimer la configuration

```bash
lionsctl delete -n mon-application -e development
```

**Paramètres:**
- `-n, --name`: Nom de l'application à supprimer
- `-e, --environment`: Environnement cible

### Déployer une application

```bash
lionsctl pipeline -u https://github.com/lionsdev/mon-application -b main -j 17 -e development -m admin@lions.dev
```

**Paramètres:**
- `-u, --url`: URL du dépôt Git de l'application
- `-b, --branch`: Branche à déployer (main, develop, feature/*)
- `-j, --java-version`: Version du JDK (11 ou 17)
- `-p, --profile`: Profil Maven à utiliser
- `-d, --define`: Propriétés Maven au format nom=valeur
- `-e, --environment`: Environnement de déploiement (development, staging, production)
- `-m, --mails`: Liste des emails qui doivent recevoir la notification (séparés par des virgules)

## Exemples d'utilisation

### Gestion des environnements

LIONS Infrastructure supporte trois environnements principaux:

- **development**: Environnement de développement pour les tests et le développement continu
- **staging**: Environnement de pré-production pour les tests d'intégration et de validation
- **production**: Environnement de production pour les applications en exploitation

Vous pouvez spécifier l'environnement cible avec le paramètre `-e` ou `--environment` dans les commandes `init` et `pipeline`.

### Initialiser une application pour différents environnements

```bash
# Initialiser pour l'environnement de développement (par défaut)
lionsctl init -n mon-application -e development -i

# Initialiser pour l'environnement de staging
lionsctl init -n mon-application -e staging -i

# Initialiser pour l'environnement de production
lionsctl init -n mon-application -e production -i -v
```

### Déployer une application Java/Quarkus

```bash
# Déployer en environnement de développement
lionsctl pipeline -u https://github.com/lionsdev/api-service -b develop -j 17 -e development -m dev-team@lions.dev

# Déployer en environnement de staging
lionsctl pipeline -u https://github.com/lionsdev/api-service -b release -j 17 -e staging -m dev-team@lions.dev,qa@lions.dev
```

### Déployer une application React

```bash
# Déployer en environnement de développement
lionsctl pipeline -u https://github.com/lionsdev/admin-dashboard -b develop -e development -m admin@lions.dev

# Déployer en environnement de production
lionsctl pipeline -u https://github.com/lionsdev/admin-dashboard -b main -e production -m admin@lions.dev,ops@lions.dev
```

### Déployer avec des paramètres spécifiques

```bash
# Déployer avec des paramètres spécifiques en environnement de staging
lionsctl pipeline -u https://github.com/lionsdev/backend-service -b develop -j 17 -p dev -d "quarkus.log.level=DEBUG" -e staging -m dev-team@lions.dev

# Déployer avec des paramètres spécifiques en environnement de production
lionsctl pipeline -u https://github.com/lionsdev/backend-service -b main -j 17 -p prod -d "quarkus.log.level=INFO" -e production -m ops@lions.dev
```

### Stratégies de branche recommandées par environnement

- **development**: Utilisez la branche `develop` ou des branches de fonctionnalités (`feature/*`)
- **staging**: Utilisez la branche `release` ou `staging`
- **production**: Utilisez la branche `main` ou `master`

## Support

Pour toute question ou problème, veuillez contacter l'équipe d'infrastructure LIONS à infrastructure@lions.dev ou ouvrir une issue sur le dépôt GitHub.
