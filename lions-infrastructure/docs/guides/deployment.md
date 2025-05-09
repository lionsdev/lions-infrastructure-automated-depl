# Guide de Déploiement d'Applications sur l'Infrastructure LIONS

Ce guide explique comment déployer des applications sur l'infrastructure LIONS en utilisant l'outil de déploiement automatisé.

## Prérequis

Avant de commencer, assurez-vous de disposer des éléments suivants :

- Accès à l'infrastructure LIONS (voir le [Guide d'installation](installation.md))
- Droits suffisants pour déployer des applications dans l'environnement cible
- Code source de l'application à déployer
- Connaissance de la technologie utilisée par l'application (Quarkus, PrimeFaces ou PrimeReact)

## Préparation de l'application

### Structure de projet recommandée

Pour un déploiement optimal, votre application devrait suivre la structure de projet recommandée pour sa technologie :

#### Quarkus

```
my-quarkus-app/
├── src/
│   ├── main/
│   │   ├── java/
│   │   ├── resources/
│   │   │   ├── application.properties
│   │   │   └── application.yaml
│   ├── test/
├── pom.xml
└── lions-deploy.yaml  # Configuration de déploiement LIONS
```

#### PrimeFaces

```
my-primefaces-app/
├── src/
│   ├── main/
│   │   ├── java/
│   │   ├── resources/
│   │   ├── webapp/
│   │   │   ├── WEB-INF/
│   │   │   └── resources/
│   ├── test/
├── pom.xml
└── lions-deploy.yaml  # Configuration de déploiement LIONS
```

#### PrimeReact

```
my-primereact-app/
├── public/
├── src/
│   ├── components/
│   ├── pages/
│   ├── App.js
│   └── index.js
├── package.json
└── lions-deploy.yaml  # Configuration de déploiement LIONS
```

### Configuration de déploiement

Créez un fichier `lions-deploy.yaml` à la racine de votre projet pour configurer le déploiement :

```yaml
# Configuration de déploiement LIONS
application:
  name: "my-application"  # Nom de l'application
  version: "1.0.0"        # Version de l'application
  technology: "quarkus"   # Technologie (quarkus, primefaces, primereact)
  description: "Ma super application"  # Description

# Configuration des environnements
environments:
  development:
    enabled: true
    replicas: 1
    resources:
      requests:
        cpu: "100m"
        memory: "256Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
    env:
      LOG_LEVEL: "DEBUG"
      FEATURE_X_ENABLED: "true"

  staging:
    enabled: true
    replicas: 2
    resources:
      requests:
        cpu: "200m"
        memory: "512Mi"
      limits:
        cpu: "1000m"
        memory: "1Gi"
    env:
      LOG_LEVEL: "INFO"
      FEATURE_X_ENABLED: "true"

  production:
    enabled: true
    replicas: 3
    resources:
      requests:
        cpu: "500m"
        memory: "1Gi"
      limits:
        cpu: "2000m"
        memory: "2Gi"
    env:
      LOG_LEVEL: "WARN"
      FEATURE_X_ENABLED: "true"

# Configuration des dépendances
dependencies:
  services:
    - name: "database"
      type: "postgresql"
      version: "13"
    - name: "redis"
      type: "redis"
      version: "6"

  applications:
    - name: "auth-service"
      version: "latest"

# Configuration du réseau
network:
  ingress:
    enabled: true
    path: "/"
    cors:
      enabled: true
      origins: ["*"]

  ports:
    - name: "http"
      port: 8080
      targetPort: 8080
    - name: "management"
      port: 8081
      targetPort: 8081

# Configuration de la persistance
persistence:
  enabled: false
  # Si enabled est true, configurez les volumes
  volumes:
    - name: "data"
      mountPath: "/app/data"
      size: "1Gi"
      storageClass: "standard"

# Configuration du monitoring
monitoring:
  prometheus:
    enabled: true
    path: "/metrics"
    port: 8080

  healthcheck:
    liveness:
      path: "/health/live"
      port: 8080
      initialDelaySeconds: 30
      periodSeconds: 10
    readiness:
      path: "/health/ready"
      port: 8080
      initialDelaySeconds: 10
      periodSeconds: 5

# Configuration de la sécurité
security:
  networkPolicies: true
  serviceAccount:
    create: true
    annotations: {}
  secrets:
    - name: "app-secrets"
      keys:
        - "DB_PASSWORD"
        - "API_KEY"
```

## Déploiement de l'application

### Utilisation de l'outil de déploiement

L'infrastructure LIONS fournit un outil de déploiement simplifié qui automatise le processus de déploiement.

#### Déploiement en environnement de développement

```bash
cd my-application
lions-infrastructure/scripts/deploy.sh
```

Par défaut, l'application sera déployée dans l'environnement de développement.

#### Déploiement dans un environnement spécifique

```bash
lions-infrastructure/scripts/deploy.sh --environment staging
```

#### Déploiement d'une version spécifique

```bash
lions-infrastructure/scripts/deploy.sh --environment production --version 1.2.3
```

#### Options de déploiement avancées

```bash
lions-infrastructure/scripts/deploy.sh --environment production --version 1.2.3 --file custom-config.yaml --params '{"feature_flag": true, "debug": false}'
```

### Options de l'outil de déploiement

L'outil de déploiement accepte les options suivantes :

| Option | Description | Valeur par défaut |
|--------|-------------|-------------------|
| `-e, --environment` | Environnement cible (development, staging, production) | development |
| `-t, --technology` | Technologie utilisée (quarkus, primefaces, primereact) | Auto-détection |
| `-v, --version` | Version spécifique à déployer | latest |
| `-f, --file` | Fichier de configuration spécifique | ./lions-deploy.yaml |
| `-p, --params` | Paramètres additionnels (format JSON) | {} |
| `-d, --debug` | Active le mode debug | false |
| `-h, --help` | Affiche l'aide | - |

## Vérification du déploiement

### Processus de vérification automatique

Pendant le déploiement, l'infrastructure LIONS effectue automatiquement plusieurs vérifications pour s'assurer que l'application est correctement déployée et fonctionnelle :

1. **Vérification du déploiement** : Attente que tous les pods soient en état "Running" et prêts
2. **Initialisation de l'application** : Pause pour permettre à l'application de s'initialiser complètement
3. **Vérification des logs** : Analyse des logs pour détecter d'éventuelles erreurs
4. **Vérification de l'API** : Test de l'endpoint de santé pour confirmer que l'application répond correctement

Ces vérifications sont adaptées à chaque technologie (Quarkus, PrimeFaces, PrimeReact) pour tenir compte de leurs spécificités.

### Vérification du statut

Après le déploiement, l'outil affiche un résumé du déploiement, incluant :

- URL d'accès à l'application
- Statut des pods
- Informations sur les services et ingress
- Résultats des vérifications automatiques
- Commandes utiles pour le dépannage

### Vérification manuelle

Vous pouvez également vérifier manuellement le statut du déploiement :

```bash
# Vérifier les pods
kubectl get pods -n <application-name>-<environment>

# Vérifier les services
kubectl get services -n <application-name>-<environment>

# Vérifier les ingress
kubectl get ingress -n <application-name>-<environment>

# Vérifier les logs
kubectl logs -n <application-name>-<environment> deployment/<application-name>
```

## Gestion du cycle de vie de l'application

### Mise à jour de l'application

Pour mettre à jour une application déjà déployée :

```bash
lions-infrastructure/scripts/deploy.sh --environment production --version 1.2.4
```

### Rollback à une version précédente

En cas de problème, vous pouvez revenir à une version précédente :

```bash
lions-infrastructure/scripts/rollback.sh --environment production --version 1.2.3
```

### Suppression de l'application

Pour supprimer une application d'un environnement :

```bash
lions-infrastructure/scripts/undeploy.sh --environment development --application my-application
```

## Bonnes pratiques

### Gestion des versions

- Utilisez un système de versionnement sémantique (SemVer) pour vos applications
- En production, spécifiez toujours une version explicite (pas de `latest`)
- Conservez un historique des déploiements pour faciliter les rollbacks

### Configuration

- Externalisez la configuration spécifique à l'environnement
- Utilisez des secrets pour les informations sensibles
- Définissez des limites de ressources appropriées pour chaque environnement

### Surveillance

- Exposez des métriques Prometheus pour permettre la surveillance
- Implémentez des endpoints de santé (health checks)
- Configurez des alertes pour les métriques critiques

### Sécurité

- Limitez les privilèges des applications au minimum nécessaire
- Utilisez des politiques réseau pour isoler les applications
- Scannez régulièrement les images pour détecter les vulnérabilités

## Dépannage

### Problèmes courants

#### L'application ne démarre pas

Vérifiez les logs de l'application :

```bash
kubectl logs -n <application-name>-<environment> deployment/<application-name>
```

#### L'application n'est pas accessible

Vérifiez l'état de l'ingress et des services :

```bash
kubectl describe ingress -n <application-name>-<environment> <application-name>
kubectl describe service -n <application-name>-<environment> <application-name>
```

#### Erreurs de ressources

Si les pods sont en état `Pending` ou `CrashLoopBackOff`, vérifiez les ressources disponibles :

```bash
kubectl describe pod -n <application-name>-<environment> <pod-name>
```

### Obtenir de l'aide

Si vous rencontrez des problèmes que vous ne pouvez pas résoudre, consultez :

- La documentation des runbooks : [Runbooks](../runbooks/index.md)
- Le canal Slack de support : #lions-support
- L'équipe d'infrastructure : infrastructure@lions.dev

## Ressources supplémentaires

- [Guide d'installation](installation.md)
- [Guide d'administration](administration.md)
- [Guide de surveillance](monitoring.md)
- [Architecture de référence](../architecture/overview.md)
