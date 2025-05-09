# Runbook: Résolution des pods en état CrashLoopBackOff

## Description du problème

Un pod en état `CrashLoopBackOff` indique que le conteneur démarre, puis se bloque ou se termine de manière inattendue, et Kubernetes tente de le redémarrer de façon répétée. Ce cycle de redémarrage continu empêche l'application de fonctionner correctement.

## Symptômes

- Alerte Prometheus : `KubernetesPodCrashLooping`
- Le pod apparaît avec le statut `CrashLoopBackOff` dans la sortie de `kubectl get pods`
- L'application n'est pas disponible ou fonctionne de manière intermittente
- Les logs montrent des redémarrages fréquents

## Impact potentiel

- Indisponibilité de l'application
- Dégradation des performances du système
- Consommation excessive de ressources due aux redémarrages constants

## Prérequis

- Accès au cluster Kubernetes avec les droits suffisants
- Connaissance de l'application concernée

## Étapes de diagnostic

### 1. Identifier le pod problématique

```bash
# Lister tous les pods dans tous les namespaces avec leur statut
kubectl get pods --all-namespaces | grep CrashLoopBackOff

# Ou dans un namespace spécifique
kubectl get pods -n <namespace> | grep CrashLoopBackOff
```

### 2. Examiner les détails du pod

```bash
kubectl describe pod <pod-name> -n <namespace>
```

Recherchez dans la sortie :
- La section `Events` pour voir l'historique des redémarrages
- La section `Containers` pour voir les détails de configuration
- Les limites de ressources qui pourraient être trop restrictives

### 3. Examiner les logs du conteneur

```bash
# Logs du conteneur actuel
kubectl logs <pod-name> -n <namespace>

# Logs du conteneur précédent (qui a crashé)
kubectl logs <pod-name> -n <namespace> --previous

# Si le pod contient plusieurs conteneurs, spécifiez le conteneur
kubectl logs <pod-name> -c <container-name> -n <namespace> --previous
```

Recherchez dans les logs :
- Messages d'erreur explicites
- Exceptions non gérées
- Problèmes de connexion à des services externes
- Problèmes de permissions ou d'accès aux fichiers

### 4. Vérifier l'utilisation des ressources

```bash
# Vérifier l'utilisation des ressources du pod
kubectl top pod <pod-name> -n <namespace>

# Vérifier l'utilisation des ressources du nœud
kubectl top node <node-name>
```

## Solutions courantes

### Problème 1: Erreurs d'application

Si les logs montrent des erreurs d'application (exceptions, erreurs de code) :

1. Corrigez le code de l'application si possible
2. Déployez une version antérieure fonctionnelle en attendant :
   ```bash
   kubectl rollout undo deployment/<deployment-name> -n <namespace>
   ```

### Problème 2: Problèmes de configuration

Si l'application ne peut pas démarrer en raison de problèmes de configuration :

1. Vérifiez les ConfigMaps et Secrets utilisés par l'application :
   ```bash
   kubectl get configmap -n <namespace>
   kubectl get secret -n <namespace>
   ```

2. Vérifiez que les variables d'environnement sont correctement définies :
   ```bash
   kubectl set env deployment/<deployment-name> -n <namespace> --list
   ```

3. Corrigez la configuration si nécessaire :
   ```bash
   kubectl edit configmap <configmap-name> -n <namespace>
   ```

### Problème 3: Limites de ressources

Si le pod est terminé en raison de limites de ressources (OOMKilled) :

1. Augmentez les limites de ressources dans le déploiement :
   ```bash
   kubectl edit deployment/<deployment-name> -n <namespace>
   ```

   Modifiez les sections suivantes :
   ```yaml
   resources:
     requests:
       memory: "256Mi"  # Augmentez cette valeur
       cpu: "100m"      # Augmentez cette valeur si nécessaire
     limits:
       memory: "512Mi"  # Augmentez cette valeur
       cpu: "500m"      # Augmentez cette valeur si nécessaire
   ```

2. Appliquez les modifications :
   ```bash
   kubectl rollout restart deployment/<deployment-name> -n <namespace>
   ```

### Problème 4: Problèmes de dépendances externes

Si l'application ne peut pas se connecter à des services externes (base de données, API, etc.) :

1. Vérifiez que les services dépendants sont disponibles :
   ```bash
   kubectl get svc -n <namespace>
   ```

2. Testez la connectivité depuis le pod :
   ```bash
   kubectl exec -it <pod-name> -n <namespace> -- curl -v <service-url>
   ```

3. Vérifiez les politiques réseau qui pourraient bloquer les connexions :
   ```bash
   kubectl get networkpolicies -n <namespace>
   ```

### Problème 5: Problèmes de stockage

Si l'application ne peut pas accéder au stockage persistant :

1. Vérifiez l'état des PersistentVolumeClaims :
   ```bash
   kubectl get pvc -n <namespace>
   kubectl describe pvc <pvc-name> -n <namespace>
   ```

2. Vérifiez l'état des PersistentVolumes :
   ```bash
   kubectl get pv
   kubectl describe pv <pv-name>
   ```

## Vérification

Après avoir appliqué une solution, vérifiez que le pod fonctionne correctement :

```bash
# Vérifier le statut du pod
kubectl get pod <pod-name> -n <namespace>

# Vérifier les logs pour confirmer que l'application fonctionne
kubectl logs <pod-name> -n <namespace>

# Vérifier que l'application répond aux requêtes
kubectl port-forward <pod-name> -n <namespace> <local-port>:<container-port>
```

Puis, dans un autre terminal :
```bash
curl localhost:<local-port>/health
```

## Prévention

Pour éviter les problèmes de CrashLoopBackOff à l'avenir :

1. Implémentez des health checks appropriés dans l'application
2. Définissez des limites de ressources réalistes
3. Testez l'application avec des charges similaires à la production
4. Mettez en place une surveillance proactive des métriques d'application
5. Utilisez des déploiements progressifs (rolling updates) avec des tests de santé

## Escalade

Si vous ne parvenez pas à résoudre le problème après avoir suivi ce runbook, escaladez comme suit :

1. Contactez l'équipe de développement responsable de l'application
2. Ouvrez un ticket d'incident avec les informations suivantes :
   - Nom du pod et namespace
   - Logs complets du pod
   - Description des étapes de diagnostic déjà effectuées
   - Résultats des commandes `kubectl describe pod` et `kubectl get events`

## Références

- [Documentation Kubernetes sur le débogage des pods](https://kubernetes.io/docs/tasks/debug-application-cluster/debug-application/)
- [Guide de dépannage des applications Kubernetes](https://kubernetes.io/docs/tasks/debug-application-cluster/debug-running-pod/)
- [Documentation LIONS sur les limites de ressources](../guides/resource-management.md)