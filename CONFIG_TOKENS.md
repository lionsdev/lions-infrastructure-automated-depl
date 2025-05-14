# Configuration des tokens pour lionsctl

Ce document explique comment remplacer les tokens placeholders dans le fichier `lionsctl.yaml` par des valeurs réelles pour permettre le bon fonctionnement de lionsctl.

## Tokens à remplacer

Dans le fichier `lionsctl\cmd\lionsctl.yaml`, les tokens suivants doivent être remplacés :

1. `ACCESS_TOKENS: "your-github-access-token"`
2. `CONFIG_REPO_TOKEN: "your-github-access-token"`
3. `SERVER_TOKEN: "your-smtp-server-token"`

## Obtention d'un token d'accès GitHub

Pour remplacer `your-github-access-token` :

1. Connectez-vous à votre compte GitHub
2. Accédez à Paramètres (Settings) > Paramètres développeur (Developer settings) > Tokens d'accès personnels (Personal access tokens) > Tokens (classic)
3. Cliquez sur "Générer un nouveau token" (Generate new token)
4. Donnez un nom descriptif au token (ex: "lionsctl-access")
5. Sélectionnez les autorisations suivantes :
   - `repo` (accès complet aux dépôts)
   - `admin:org` (pour gérer les organisations)
   - `admin:repo_hook` (pour les webhooks)
   - `delete_repo` (si vous avez besoin de supprimer des dépôts)
6. Cliquez sur "Générer un token" (Generate token)
7. Copiez le token généré (il ne sera affiché qu'une seule fois)

Remplacez les valeurs dans le fichier `lionsctl.yaml` :
```yaml
GIT:
   ACCESS_TOKENS: "ghp_votre_token_github_ici"
HELM:
   CONFIG_REPO_TOKEN: "ghp_votre_token_github_ici"
```

## Configuration du token SMTP

Pour remplacer `your-smtp-server-token` :

1. Contactez l'administrateur de votre serveur SMTP pour obtenir un token d'authentification
2. Si vous utilisez un service SMTP comme SendGrid, Mailgun, ou Postmark :
   - Créez un compte sur le service
   - Générez une clé API ou un token d'authentification
   - Utilisez cette clé comme token SMTP

Remplacez la valeur dans le fichier `lionsctl.yaml` :
```yaml
NOTIFICATION:
   SERVER_TOKEN: "votre_token_smtp_ici"
```

## Vérification des autres paramètres

Assurez-vous que les autres paramètres de configuration sont corrects pour votre environnement :

1. URL du registre Docker : `REGISTRY_URL: "registry.lions.dev"`
2. Informations GitHub :
   - `DOMAIN: "github.com"`
   - `BASE_URL: "https://github.com"`
   - `ENV_URL: https://github.com/lionsdev/`
3. Configuration SMTP :
   - `FROM_URL: notifications@lions.dev`
   - `SMTP_URL: "smtp://smtp.lions.dev:587"`

## Application des modifications

Après avoir remplacé les tokens, vous devez recompiler le projet pour que les modifications prennent effet :

```powershell
cd lionsctl
go build
```

## Sécurité des tokens

Important : Ne partagez jamais vos tokens d'accès et ne les committez pas dans le dépôt Git. Considérez l'utilisation de variables d'environnement ou d'un gestionnaire de secrets pour une solution plus sécurisée en production.