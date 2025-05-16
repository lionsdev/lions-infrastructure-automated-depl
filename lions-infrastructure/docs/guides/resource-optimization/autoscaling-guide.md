# Guide d'Autoscaling pour LIONS Infrastructure

## Introduction

Ce document décrit la configuration d'autoscaling mise en place pour les services de l'infrastructure LIONS. L'autoscaling permet d'ajuster automatiquement le nombre de réplicas de chaque service en fonction de la charge, optimisant ainsi l'utilisation des ressources et assurant la disponibilité des services pendant les périodes de forte demande.

## Architecture d'Autoscaling

L'autoscaling dans Kubernetes est géré par les ressources `HorizontalPodAutoscaler` (HPA). Ces ressources surveillent les métriques des pods (comme l'utilisation CPU et mémoire) et ajustent automatiquement le nombre de réplicas en fonction des seuils définis.

### Métriques Surveillées

Les HPA configurés dans l'infrastructure LIONS surveillent les métriques suivantes :

- **Utilisation CPU** : Pourcentage d'utilisation du CPU par rapport aux limites définies
- **Utilisation Mémoire** : Pourcentage d'utilisation de la mémoire par rapport aux limites définies

### Comportement d'Autoscaling

Chaque HPA définit un comportement spécifique pour la mise à l'échelle :

- **Scale Up** : Comment et à quelle vitesse augmenter le nombre de réplicas
- **Scale Down** : Comment et à quelle vitesse réduire le nombre de réplicas
- **Stabilization Window** : Période pendant laquelle les conditions doivent être maintenues avant de déclencher une action de mise à l'échelle

## Configuration par Service

### Services Applicatifs

#### Quarkus (Backend)

- **Namespace** : quarkus-development
- **Min Replicas** : 2
- **Max Replicas** : 6
- **CPU Target** : 70%
- **Memory Target** : 80%
- **Scale Up** : 100% d'augmentation ou 2 pods toutes les 15 secondes
- **Scale Down** : 10% de réduction toutes les 60 secondes avec une fenêtre de stabilisation de 300 secondes

#### PrimeFaces (Frontend)

- **Namespace** : primefaces-development
- **Min Replicas** : 2
- **Max Replicas** : 5
- **CPU Target** : 75%
- **Memory Target** : 80%
- **Scale Up** : 100% d'augmentation ou 2 pods toutes les 15 secondes
- **Scale Down** : 10% de réduction toutes les 60 secondes avec une fenêtre de stabilisation de 300 secondes

#### PrimeReact (Frontend)

- **Namespace** : primereact-development
- **Min Replicas** : 2
- **Max Replicas** : 5
- **CPU Target** : 75%
- **Memory Target** : 80%
- **Scale Up** : 100% d'augmentation ou 2 pods toutes les 15 secondes
- **Scale Down** : 10% de réduction toutes les 60 secondes avec une fenêtre de stabilisation de 300 secondes

#### Service de Notification

- **Namespace** : notification-service-development
- **Min Replicas** : 2
- **Max Replicas** : 6
- **CPU Target** : 70%
- **Memory Target** : 80%
- **Scale Up** : 100% d'augmentation ou 2 pods toutes les 15 secondes
- **Scale Down** : 10% de réduction toutes les 60 secondes avec une fenêtre de stabilisation de 300 secondes

#### Ollama (Service ML)

- **Namespace** : ollama-development
- **Min Replicas** : 1
- **Max Replicas** : 3
- **CPU Target** : 80%
- **Memory Target** : 85%
- **Scale Up** : 100% d'augmentation ou 1 pod toutes les 30 secondes avec une fenêtre de stabilisation de 60 secondes
- **Scale Down** : 10% de réduction toutes les 120 secondes avec une fenêtre de stabilisation de 600 secondes

### Services d'Infrastructure

#### Gitea (Serveur Git)

- **Namespace** : gitea-development
- **Min Replicas** : 1
- **Max Replicas** : 3
- **CPU Target** : 75%
- **Memory Target** : 80%
- **Scale Up** : 100% d'augmentation ou 1 pod toutes les 15 secondes
- **Scale Down** : 10% de réduction toutes les 60 secondes avec une fenêtre de stabilisation de 300 secondes

#### Keycloak (Authentification)

- **Namespace** : keycloak-development
- **Min Replicas** : 2
- **Max Replicas** : 5
- **CPU Target** : 70%
- **Memory Target** : 80%
- **Scale Up** : 100% d'augmentation ou 2 pods toutes les 15 secondes
- **Scale Down** : 10% de réduction toutes les 60 secondes avec une fenêtre de stabilisation de 300 secondes

#### Registry (Registre de Conteneurs)

- **Namespace** : registry-development
- **Min Replicas** : 1
- **Max Replicas** : 3
- **CPU Target** : 75%
- **Memory Target** : 80%
- **Scale Up** : 100% d'augmentation ou 1 pod toutes les 15 secondes
- **Scale Down** : 10% de réduction toutes les 60 secondes avec une fenêtre de stabilisation de 300 secondes

## Bonnes Pratiques

### Surveillance et Ajustement

1. **Surveillance Continue** : Utilisez les tableaux de bord Grafana pour surveiller l'utilisation des ressources et le comportement d'autoscaling
2. **Ajustement Itératif** : Ajustez les seuils et les comportements en fonction des observations et des besoins spécifiques
3. **Tests de Charge** : Effectuez régulièrement des tests de charge pour valider le comportement d'autoscaling

### Optimisation des Ressources

1. **Définition Précise des Limites** : Assurez-vous que les limites de ressources sont correctement définies pour chaque service
2. **Équilibre entre Réactivité et Stabilité** : Trouvez le bon équilibre entre la réactivité aux pics de charge et la stabilité du système
3. **Considération des Coûts** : Tenez compte des implications en termes de coûts lors de la définition des stratégies d'autoscaling

## Dépannage

### Problèmes Courants

1. **Autoscaling Trop Lent** : Si l'autoscaling ne répond pas assez rapidement aux pics de charge, réduisez la fenêtre de stabilisation pour le scale up
2. **Oscillations** : Si le nombre de réplicas oscille fréquemment, augmentez la fenêtre de stabilisation
3. **Limites de Ressources Atteintes** : Vérifiez les quotas de ressources au niveau du namespace si l'autoscaling ne peut pas créer de nouveaux pods

### Commandes Utiles

```bash
# Vérifier l'état des HPA
kubectl get hpa -n <namespace>

# Voir les détails d'un HPA spécifique
kubectl describe hpa <nom-hpa> -n <namespace>

# Vérifier l'utilisation des ressources
kubectl top pods -n <namespace>
```

## Conclusion

La configuration d'autoscaling mise en place pour l'infrastructure LIONS permet d'optimiser l'utilisation des ressources tout en assurant la disponibilité et la performance des services. Cette approche équilibrée prend en compte les spécificités de chaque service et permet une adaptation dynamique à la charge.

Pour toute question ou suggestion d'amélioration, veuillez contacter l'équipe LIONS Infrastructure.