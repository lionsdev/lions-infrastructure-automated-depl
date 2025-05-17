# Guide d'Optimisation des Ressources pour LIONS Infrastructure

## Introduction

Ce document présente les stratégies d'optimisation des ressources mises en place pour l'infrastructure LIONS. L'optimisation des ressources est essentielle pour garantir la performance, la stabilité et la rentabilité de l'infrastructure.

## Stratégies d'Optimisation des Ressources

L'infrastructure LIONS utilise plusieurs stratégies complémentaires pour optimiser l'utilisation des ressources :

1. **Quotas de Ressources** : Limites au niveau des namespaces pour contrôler la consommation globale
2. **Limites de Ressources** : Contraintes au niveau des conteneurs pour garantir une utilisation équitable
3. **Autoscaling** : Ajustement dynamique du nombre de réplicas en fonction de la charge
4. **Optimisation des Demandes et Limites** : Configuration précise des ressources requises par chaque service

## Quotas de Ressources

Les quotas de ressources définissent les limites maximales de ressources qu'un namespace peut consommer. Ils sont configurés dans `kubernetes/base/resource-quotas/default-resource-quotas.yaml`.

### Quotas par Environnement

#### Environnement de Développement
- CPU Requests: 4 cores
- CPU Limits: 8 cores
- Memory Requests: 8Gi
- Memory Limits: 16Gi

#### Environnement de Staging
- CPU Requests: 8 cores
- CPU Limits: 16 cores
- Memory Requests: 16Gi
- Memory Limits: 32Gi

#### Environnement de Production
- CPU Requests: 20 cores
- CPU Limits: 40 cores
- Memory Requests: 40Gi
- Memory Limits: 80Gi

### Quotas d'Objets

Des quotas sont également définis pour limiter le nombre d'objets Kubernetes :
- Pods: 50
- Services: 30
- ConfigMaps: 50
- Secrets: 100
- PersistentVolumeClaims: 20

## Limites de Ressources

Les limites de ressources définissent les contraintes par défaut pour les conteneurs dans chaque namespace. Elles sont configurées dans `kubernetes/base/resource-quotas/default-limit-ranges.yaml`.

### Limites par Type de Service

#### Services Génériques
- Default CPU: 500m
- Default Memory: 512Mi
- Default Request CPU: 100m
- Default Request Memory: 128Mi

#### Services de Base de Données (PostgreSQL)
- Default CPU: 1 core
- Default Memory: 1Gi
- Default Request CPU: 500m
- Default Request Memory: 512Mi
- Max CPU: 2 cores
- Max Memory: 4Gi

#### Services ML (Ollama)
- Default CPU: 2 cores
- Default Memory: 4Gi
- Default Request CPU: 1 core
- Default Request Memory: 2Gi
- Max CPU: 4 cores
- Max Memory: 8Gi

## Autoscaling

L'autoscaling permet d'ajuster automatiquement le nombre de réplicas en fonction de la charge. Voir le [Guide d'Autoscaling](autoscaling-guide.md) pour plus de détails.

## Optimisation des Demandes et Limites

### Principes Généraux

1. **Demandes (Requests)** : Représentent les ressources garanties pour un conteneur
2. **Limites (Limits)** : Représentent les ressources maximales qu'un conteneur peut utiliser

### Bonnes Pratiques

1. **Analyse des Besoins Réels** : Basez les demandes et limites sur l'utilisation réelle observée
2. **Ratio Limite/Demande** : Maintenez un ratio raisonnable entre les limites et les demandes (généralement 2:1 ou 3:1)
3. **Évitez l'Over-Commitment** : Ne demandez pas plus de ressources que nécessaire
4. **Évitez l'Under-Commitment** : Assurez-vous que les demandes sont suffisantes pour éviter les problèmes de performance

### Processus d'Optimisation

1. **Surveillance** : Utilisez les tableaux de bord Grafana pour surveiller l'utilisation des ressources
2. **Analyse** : Identifiez les tendances et les modèles d'utilisation
3. **Ajustement** : Modifiez les demandes et limites en fonction de l'analyse
4. **Validation** : Testez les nouveaux paramètres et surveillez les performances
5. **Itération** : Répétez le processus régulièrement pour maintenir l'optimisation

## Surveillance et Analyse

### Métriques Clés

1. **Utilisation CPU** : `container_cpu_usage_seconds_total`
2. **Utilisation Mémoire** : `container_memory_usage_bytes`
3. **Saturation CPU** : `node_cpu_saturation_ratio`
4. **Saturation Mémoire** : `node_memory_saturation_ratio`

### Tableaux de Bord

Utilisez les tableaux de bord Grafana suivants pour surveiller l'utilisation des ressources :

1. **Dashboard par défaut** : Vue d'ensemble de l'utilisation des ressources
2. **Dashboard par service** : Utilisation détaillée par service (Quarkus, PrimeFaces, etc.)
3. **Dashboard de coûts** : Analyse des coûts liés à l'utilisation des ressources

## Recommandations Spécifiques par Service

### Services Stateless (Quarkus, PrimeFaces, PrimeReact)

- Privilégiez l'autoscaling horizontal
- Utilisez des demandes modérées et des limites plus élevées
- Configurez des règles d'autoscaling réactives

### Services Stateful (PostgreSQL, Redis)

- Évitez l'autoscaling horizontal (utilisez plutôt le scaling vertical)
- Définissez des demandes proches des besoins réels
- Configurez des limites avec une marge raisonnable
- Utilisez des classes de stockage appropriées

### Services Intensifs (Ollama)

- Utilisez des nœuds dédiés si possible
- Définissez des demandes et limites généreuses
- Limitez le nombre de réplicas
- Surveillez étroitement l'utilisation des ressources

## Dépannage

### Problèmes Courants

1. **OOMKilled** : Le conteneur dépasse sa limite de mémoire
   - Solution : Augmentez la limite de mémoire ou optimisez l'application

2. **CPU Throttling** : Le conteneur est limité en CPU
   - Solution : Augmentez la demande de CPU ou optimisez l'application

3. **Pending Pods** : Les pods ne peuvent pas être planifiés
   - Solution : Vérifiez les quotas de ressources et la capacité des nœuds

### Commandes Utiles

```bash
# Vérifier l'utilisation des ressources par pod
kubectl top pods -n <namespace>

# Vérifier l'utilisation des ressources par nœud
kubectl top nodes

# Vérifier les quotas de ressources
kubectl describe resourcequota -n <namespace>

# Vérifier les limites de ressources
kubectl describe limitrange -n <namespace>
```

## Conclusion

L'optimisation des ressources est un processus continu qui nécessite une surveillance, une analyse et des ajustements réguliers. En suivant les stratégies et les bonnes pratiques décrites dans ce document, vous pouvez garantir une utilisation efficace des ressources tout en maintenant la performance et la stabilité de l'infrastructure LIONS.

Pour toute question ou suggestion d'amélioration, veuillez contacter l'équipe LIONS Infrastructure.
