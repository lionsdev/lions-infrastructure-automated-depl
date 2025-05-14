# Guide d'utilisation de lionsctl

Ce guide explique comment installer et utiliser lionsctl, l'outil de ligne de commande pour déployer des applications sur l'infrastructure LIONS.

## Table des matières

1. [Installation](#installation)
2. [Configuration](#configuration)
3. [Commandes principales](#commandes-principales)
4. [Exemples d'utilisation](#exemples-dutilisation)
5. [Dépannage](#dépannage)
6. [Bonnes pratiques](#bonnes-pratiques)

## Installation

### Windows

1. Téléchargez le fichier ZIP depuis la page [Releases](https://github.com/lionsdev/lionsctl/releases)
2. Extrayez le contenu dans un dossier de votre choix
3. Ajoutez ce dossier à votre variable d'environnement PATH :
   - Ouvrez le Panneau de configuration > Système et sécurité > Système > Paramètres système avancés
   - Cliquez sur "Variables d'environnement"
   - Modifiez la variable "Path" et ajoutez le chemin vers le dossier contenant lionsctl.exe
4. Vérifiez l'installation en ouvrant une nouvelle invite de commandes et en tapant :
   ```powershell
   lionsctl --version
   ```

### Linux

1. Téléchargez le fichier TAR.GZ depuis la page [Releases](https://github.com/lionsdev/lionsctl/releases)
2. Extrayez le contenu :
   ```bash
   tar -xzvf lionsctl-1.0.0-linux-amd64.tar.gz -C /tmp
   ```
3. Copiez l'exécutable dans un répertoire du PATH :
   ```bash
   sudo cp /tmp/lionsctl /usr/local/bin/
   sudo chmod +x /usr/local/bin/lionsctl
   ```
4. Vérifiez l'installation :
   ```bash
   lionsctl --version
   ```

### macOS

1. Téléchargez le fichier TAR.GZ depuis la page [Releases](https://github.com/lionsdev/lionsctl/releases)
2. Extrayez le contenu :
   ```bash
   tar -xzvf lionsctl-1.0.0-darwin-amd64.tar.gz -C /tmp
   ```
3. Copiez l'exécutable dans un répertoire du PATH :
   ```bash
   sudo cp /tmp/lionsctl /usr/local/bin/
   sudo chmod +x /usr/local/bin/lionsctl
   ```
4. Vérifiez l'installation :
   ```bash
   lionsctl --version
   ```

## Configuration

Avant d'utiliser lionsctl, vous devez configurer les tokens d'accès :

1. Lors de la première exécution, lionsctl crée un fichier de configuration dans votre répertoire personnel :
   - Windows : `C:\Users\<username>\.lionsctl.yaml`
   - Linux/macOS : `~/.lionsctl.yaml`

2. Modifiez ce fichier pour remplacer les tokens placeholders par des tokens réels (voir CONFIG_TOKENS.md pour plus de détails) :
   - GitHub Access Token
   - SMTP Server Token

## Commandes principales

### Afficher l'aide

```bash
lionsctl --help
```

### Initialiser une application

```bash
lionsctl init -n <nom-application> -e <environnement> [-i] [-v]
```

Options :
- `-n, --name` : Nom de l'application (obligatoire)
- `-e, --environment` : Environnement (development, staging, production)
- `-i, --ingress` : Ajouter un ingress pour l'accès externe
- `-v, --volume` : Ajouter un volume persistant

Exemple :
```bash
lionsctl init -n api-service -e development -i
```

### Déployer une application (pipeline complet)

```bash
lionsctl pipeline -u <url-git> -b <branche> -e <environnement> [-j <version-java>] [-p <profile>] [-m <emails>]
```

Options :
- `-u, --url` : URL du dépôt Git (obligatoire)
- `-b, --branch` : Branche à déployer (obligatoire)
- `-e, --environment` : Environnement de déploiement (obligatoire)
- `-j, --java-version` : Version de Java (11 ou 17)
- `-p, --profile` : Profil Maven
- `-m, --mails` : Emails pour les notifications (séparés par des virgules)

Exemple :
```bash
lionsctl pipeline -u https://github.com/lionsdev/api-service -b main -e development -j 17 -m admin@lions.dev
```

### Construire une image Docker

```bash
lionsctl build -u <url-git> -b <branche> [-j <version-java>] [-p <profile>]
```

### Déployer une application existante

```bash
lionsctl deploy -n <nom-application> -e <environnement> -c <cluster>
```

### Supprimer une configuration

```bash
lionsctl delete -n <nom-application> -c <cluster>
```

### Envoyer des notifications

```bash
lionsctl notify -n <nom-application> -e <environnement> -m <emails>
```

## Exemples d'utilisation

### Déployer une application Java/Quarkus

```bash
# Initialiser l'application
lionsctl init -n backend-service -e development -i -v

# Déployer l'application
lionsctl pipeline -u https://github.com/lionsdev/backend-service -b main -e development -j 17 -p dev -m admin@lions.dev
```

### Déployer une application React

```bash
# Initialiser l'application
lionsctl init -n admin-dashboard -e production -i

# Déployer l'application
lionsctl pipeline -u https://github.com/lionsdev/admin-dashboard -b main -e production -m admin@lions.dev,ops@lions.dev
```

### Mettre à jour une application déjà déployée

```bash
# Redéployer avec la dernière version
lionsctl pipeline -u https://github.com/lionsdev/api-service -b main -e development -j 17
```

## Dépannage

### Problèmes courants

1. **Erreur d'authentification GitHub** :
   - Vérifiez que votre token GitHub est valide et a les autorisations nécessaires
   - Assurez-vous que le token est correctement configuré dans `.lionsctl.yaml`

2. **Erreur de compilation** :
   - Vérifiez que le dépôt Git est accessible
   - Assurez-vous que la branche spécifiée existe
   - Vérifiez que le code source peut être compilé localement

3. **Erreur de déploiement** :
   - Vérifiez que le cluster Kubernetes est accessible
   - Assurez-vous que les namespaces et les ressources nécessaires existent
   - Vérifiez les logs pour plus de détails : `kubectl logs -n <namespace> deployment/<nom-application>`

### Logs et débogage

Pour activer le mode verbeux et obtenir plus d'informations de débogage :

```bash
lionsctl pipeline -u <url-git> -b <branche> -e <environnement> --verbose
```

## Bonnes pratiques

1. **Gestion des versions** :
   - Utilisez des tags Git pour marquer les versions stables
   - Suivez le versionnement sémantique (MAJOR.MINOR.PATCH)

2. **Environnements** :
   - Utilisez `development` pour les tests en cours de développement
   - Utilisez `staging` pour les tests de pré-production
   - Utilisez `production` uniquement pour les versions stables

3. **Sécurité** :
   - Ne partagez jamais vos tokens d'accès
   - Utilisez des tokens avec les permissions minimales nécessaires
   - Changez régulièrement vos tokens

4. **Automatisation** :
   - Intégrez lionsctl dans vos pipelines CI/CD
   - Automatisez les tests avant le déploiement
   - Configurez des notifications pour les déploiements réussis et échoués

---

Pour plus d'informations, consultez la [documentation complète](https://github.com/lionsdev/lionsctl/docs) ou contactez l'équipe d'infrastructure à infrastructure@lions.dev.