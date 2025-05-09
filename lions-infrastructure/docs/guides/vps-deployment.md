# Guide de Déploiement de l'Infrastructure LIONS sur VPS

## Spécifications du VPS
- **CPU** : 6 cœurs
- **RAM** : 12 Go
- **Stockage** : 400 Go SSD
- **Bande passante** : 300 Mbit/s

## Modifications apportées à la configuration

Pour adapter l'infrastructure LIONS à ces spécifications, les modifications suivantes ont été effectuées :

### Quotas de ressources pour l'environnement de développement

Le fichier `kubernetes/overlays/development/patches/resource-quotas-patch.yaml` a été modifié pour ajuster les quotas de ressources :

```yaml
# Quotas CPU et mémoire ajustés pour le VPS (6 cores, 12GB RAM)
requests.cpu: "5"
requests.memory: 10Gi
limits.cpu: "6"
limits.memory: 12Gi
```

Ces valeurs ont été réduites par rapport aux valeurs par défaut (8 CPU, 16Gi de mémoire) pour s'adapter aux ressources disponibles sur le VPS, tout en laissant une marge pour les processus système.

## Compatibilité des applications

### Applications Quarkus
- CPU par application : 100m à 500m
- Mémoire par application : 256Mi à 512Mi
- **Compatibilité** : ✅ Excellente

### Applications PrimeFaces
- CPU par application : 200m à 500m
- Mémoire par application : 512Mi à 1Gi
- **Compatibilité** : ✅ Bonne

### Applications PrimeReact
- CPU par application : 100m à 500m
- Mémoire par application : 256Mi à 512Mi
- **Compatibilité** : ✅ Excellente

## Nombre maximal d'applications recommandé

Avec les ressources disponibles et les quotas configurés, voici le nombre approximatif d'applications que vous pouvez déployer simultanément :

- **Applications Quarkus** : 15-20 instances
- **Applications PrimeFaces** : 8-10 instances
- **Applications PrimeReact** : 15-20 instances

Ces estimations supposent que les applications sont déployées avec les ressources par défaut et qu'aucune autre charge de travail importante ne s'exécute sur le VPS.

## Recommandations pour l'optimisation

### Utilisation de K3s au lieu de K8s
Pour un VPS avec ces spécifications, nous recommandons d'utiliser K3s, une distribution légère de Kubernetes :

```bash
curl -sfL https://get.k3s.io | sh -
```

### Désactivation des composants non essentiels
Pour économiser des ressources, vous pouvez désactiver certains composants non essentiels :

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --disable servicelb" sh -
```

### Optimisation de la mémoire
Ajoutez les paramètres suivants au fichier `/etc/sysctl.conf` pour optimiser l'utilisation de la mémoire :

```
vm.swappiness=10
vm.vfs_cache_pressure=50
```

Appliquez les changements avec :
```bash
sudo sysctl -p
```

### Surveillance des ressources
Surveillez régulièrement l'utilisation des ressources pour éviter les problèmes de surcharge :

```bash
kubectl top nodes
kubectl top pods --all-namespaces
```

## Procédure de déploiement

1. **Installation de K3s** :
   ```bash
   curl -sfL https://get.k3s.io | sh -
   ```

2. **Configuration de kubectl** :
   ```bash
   mkdir ~/.kube
   sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
   sudo chown $(id -u):$(id -g) ~/.kube/config
   export KUBECONFIG=~/.kube/config
   ```

3. **Clonage du dépôt LIONS** :
   ```bash
   git clone https://github.com/votre-organisation/lions-infrastructure-automated-depl.git
   cd lions-infrastructure-automated-depl
   ```

4. **Installation de l'infrastructure de base** :
   ```bash
   ./scripts/install.sh --environment development
   ```

5. **Déploiement des applications** :
   ```bash
   ./scripts/deploy.sh --environment development votre-application
   ```

## Conclusion

Avec les modifications apportées, l'infrastructure LIONS est maintenant compatible avec votre VPS de 6 cœurs, 12 Go de RAM et 400 Go de stockage SSD. Vous pouvez déployer un nombre raisonnable d'applications tout en maintenant de bonnes performances.

Pour toute question ou problème, consultez la documentation complète ou contactez l'équipe de support LIONS.