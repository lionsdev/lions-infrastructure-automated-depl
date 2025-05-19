# Template pour Applications Angular

Ce répertoire contient les templates nécessaires pour déployer des applications Angular sur l'infrastructure LIONS.

## Contenu

- `Dockerfile` : Configuration pour construire l'image Docker de l'application Angular
- `nginx.conf` : Configuration Nginx optimisée pour servir des applications Angular
- `deployment.yaml` : Template Kubernetes pour le déploiement de l'application
- `service.yaml` : Template Kubernetes pour exposer l'application
- `ingress.yaml` : Template Kubernetes pour configurer l'accès externe à l'application

## Prérequis

- Une application Angular fonctionnelle
- Docker installé pour la construction de l'image
- Accès à l'infrastructure LIONS (kubectl configuré)
- Accès au registre Docker de LIONS

## Utilisation

### 1. Préparation de l'application

Assurez-vous que votre application Angular est configurée pour une construction en production :

```typescript
// environment.prod.ts
export const environment = {
  production: true,
  apiUrl: 'https://api.ENVIRONMENT.lions.dev'
};
```

### 2. Ajout des fichiers de configuration

Copiez les fichiers suivants dans votre projet Angular :

- `Dockerfile`
- `nginx.conf`

### 3. Construction de l'image Docker

```bash
# À la racine de votre projet Angular
docker build -t registry.lions.dev/mon-application:latest .
docker push registry.lions.dev/mon-application:latest
```

### 4. Déploiement sur Kubernetes

Utilisez l'outil `lionsctl` pour déployer votre application :

```bash
# Initialisation de l'application
lionsctl init -n mon-application -e development -i

# Déploiement de l'application
lionsctl pipeline -u https://github.com/lionsdev/mon-application -b main -e development -m admin@lions.dev
```

Alternativement, vous pouvez utiliser les templates Kubernetes directement :

```bash
# Créez un répertoire pour votre application
mkdir -p kubernetes/mon-application

# Copiez les templates
cp lions-infrastructure/applications/templates/angular/*.yaml kubernetes/mon-application/

# Remplacez les placeholders
sed -i 's/APP_NAME/mon-application/g' kubernetes/mon-application/*.yaml
sed -i 's/APP_NAMESPACE/mon-application-development/g' kubernetes/mon-application/*.yaml
sed -i 's/ENVIRONMENT/development/g' kubernetes/mon-application/*.yaml

# Appliquez les configurations
kubectl apply -f kubernetes/mon-application/
```

## Personnalisation

### Ressources

Vous pouvez ajuster les ressources allouées à votre application en modifiant les sections `resources` dans le fichier `deployment.yaml` :

```yaml
resources:
  limits:
    cpu: 500m     # 0.5 CPU
    memory: 512Mi # 512 Mo de RAM
  requests:
    cpu: 100m     # 0.1 CPU
    memory: 256Mi # 256 Mo de RAM
```

### Variables d'environnement

Ajoutez des variables d'environnement supplémentaires dans la section `env` du fichier `deployment.yaml` :

```yaml
env:
- name: NODE_ENV
  value: "production"
- name: API_URL
  value: "https://api.development.lions.dev"
- name: FEATURE_FLAGS
  value: "feature1=true,feature2=false"
```

### Configuration Nginx

Personnalisez la configuration Nginx en modifiant le fichier `nginx.conf`. Par exemple, pour ajouter des en-têtes de sécurité :

```nginx
# Ajoutez dans la section server
add_header X-Frame-Options "SAMEORIGIN";
add_header X-XSS-Protection "1; mode=block";
add_header X-Content-Type-Options "nosniff";
```

## Monitoring

Les applications déployées avec ce template sont automatiquement configurées pour être surveillées par Prometheus et Grafana. Les métriques sont exposées sur le port 9113 et sont collectées par le système de monitoring de l'infrastructure LIONS.

Vous pouvez accéder aux tableaux de bord Grafana à l'adresse suivante :
```
https://grafana.lions.dev
```

## Support

Pour toute question ou problème, contactez l'équipe d'infrastructure LIONS à infrastructure@lions.dev.