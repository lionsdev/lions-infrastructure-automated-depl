# Autoscaling pour LIONS Infrastructure

Ce répertoire contient les configurations d'autoscaling horizontal (HorizontalPodAutoscaler) pour les services de l'infrastructure LIONS.

## Contenu

- `kustomization.yaml` : Configuration Kustomize pour l'autoscaling
- `quarkus-hpa.yaml` : Configuration d'autoscaling pour les services Quarkus
- `primefaces-hpa.yaml` : Configuration d'autoscaling pour les services PrimeFaces
- `primereact-hpa.yaml` : Configuration d'autoscaling pour les services PrimeReact
- `notification-service-hpa.yaml` : Configuration d'autoscaling pour le service de notification
- `ollama-hpa.yaml` : Configuration d'autoscaling pour le service Ollama (ML)
- `gitea-hpa.yaml` : Configuration d'autoscaling pour le service Gitea
- `keycloak-hpa.yaml` : Configuration d'autoscaling pour le service Keycloak
- `registry-hpa.yaml` : Configuration d'autoscaling pour le service Registry

## Utilisation

Ces configurations sont automatiquement appliquées lors du déploiement de l'infrastructure via Kustomize.

Pour appliquer manuellement ces configurations :

```bash
kubectl apply -k .
```

## Vérification

Pour vérifier les configurations avant de les appliquer, utilisez le script de vérification :

```bash
../../scripts/verify-autoscaling.sh
```

## Documentation

Pour plus d'informations sur l'autoscaling et l'optimisation des ressources, consultez :

- [Guide d'Autoscaling](../../docs/guides/resource-optimization/autoscaling-guide.md)
- [Guide d'Optimisation des Ressources](../../docs/guides/resource-optimization/resource-optimization.md)