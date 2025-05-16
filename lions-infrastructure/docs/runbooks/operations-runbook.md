# Runbook des Opérations LIONS

## Introduction

Ce runbook contient les procédures opérationnelles pour la maintenance, le dépannage et la gestion de l'infrastructure LIONS. Il est destiné aux administrateurs et opérateurs responsables de l'infrastructure.

## Procédures de Maintenance Régulière

### Mise à Jour de l'Infrastructure

**Fréquence recommandée**: Mensuelle

**Procédure**:

1. Créez une sauvegarde complète avant la mise à jour:
   ```bash
   ./lions-infrastructure/scripts/backup-restore.sh development backup pre-update-$(date +%Y%m%d)
   ```

2. Mettez à jour le dépôt Git:
   ```bash
   cd /lions-infrastructure-automated-depl
   git pull
   ```

3. Exécutez le script d'installation avec l'option de mise à jour:
   ```bash
   ./lions-infrastructure/scripts/install.sh --environment development --update-only
   ```

4. Vérifiez que tous les services sont opérationnels:
   ```bash
   kubectl get pods --all-namespaces
   ```

### Rotation des Certificats

**Fréquence recommandée**: Automatique (90 jours), vérification mensuelle

**Procédure**:

1. Vérifiez l'état des certificats:
   ```bash
   kubectl get certificates --all-namespaces
   ```

2. Pour les certificats qui expirent bientôt (moins de 30 jours), forcez le renouvellement:
   ```bash
   kubectl delete certificate <nom_certificat> -n <namespace>
   ```

3. Vérifiez que le nouveau certificat a été émis:
   ```bash
   kubectl get certificates <nom_certificat> -n <namespace>
   kubectl get secrets <nom_certificat>-tls -n <namespace>
   ```

### Nettoyage des Ressources Inutilisées

**Fréquence recommandée**: Hebdomadaire

**Procédure**:

1. Nettoyage des pods terminés:
   ```bash
   kubectl delete pods --field-selector=status.phase==Succeeded --all-namespaces
   kubectl delete pods --field-selector=status.phase==Failed --all-namespaces
   ```

2. Nettoyage des images Docker inutilisées:
   ```bash
   ssh root@localhost "crictl rmi --prune"
   ```

3. Nettoyage des volumes persistants orphelins:
   ```bash
   # Identifiez les PVCs sans pods associés
   for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
     echo "Namespace: $ns"
     kubectl get pvc -n $ns -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.volumeName}{"\n"}{end}' | while read pvc pv; do
       if [ -n "$pv" ]; then
         if ! kubectl get pod -n $ns -o jsonpath='{range .items[*]}{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{"\n"}{end}{end}' | grep -q "^$pvc$"; then
           echo "PVC $pvc dans $ns n'est pas utilisé par un pod"
         fi
       fi
     done
   done
   ```

### Sauvegarde des Données

**Fréquence recommandée**: Quotidienne (automatisée), hebdomadaire (manuelle)

**Procédure**:

1. Sauvegarde automatique quotidienne:
   ```bash
   # Ajoutez cette ligne à crontab
   0 2 * * * /lions-infrastructure-automated-depl/lions-infrastructure/scripts/backup-restore.sh development backup daily-$(date +\%Y\%m\%d) >> /var/log/lions/backups.log 2>&1
   ```

2. Sauvegarde manuelle hebdomadaire:
   ```bash
   ./lions-infrastructure/scripts/backup-restore.sh development backup weekly-$(date +%Y%m%d)
   ```

3. Vérification des sauvegardes:
   ```bash
   ls -la /lions-infrastructure-automated-depl/lions-infrastructure/backups/development/
   ```

4. Rotation des sauvegardes (conserver les 7 dernières quotidiennes et les 4 dernières hebdomadaires):
   ```bash
   find /lions-infrastructure-automated-depl/lions-infrastructure/backups/development/daily-* -mtime +7 -delete
   find /lions-infrastructure-automated-depl/lions-infrastructure/backups/development/weekly-* -mtime +28 -delete
   ```

## Procédures de Dépannage

### Problèmes de Nœuds Kubernetes

#### Nœud en État NotReady

**Symptômes**: Un nœud est en état `NotReady` dans `kubectl get nodes`

**Procédure**:

1. Vérifiez l'état du nœud:
   ```bash
   kubectl describe node <nom_nœud>
   ```

2. Vérifiez les logs du service k3s:
   ```bash
   sudo journalctl -u k3s
   ```

3. Redémarrez le service k3s:
   ```bash
   sudo systemctl restart k3s
   ```

4. Si le problème persiste, vérifiez les ressources système:
   ```bash
   free -h
   df -h
   top
   ```

5. Si nécessaire, redémarrez le nœud:
   ```bash
   sudo reboot
   ```

### Problèmes de Pods

#### Pods en État CrashLoopBackOff

**Symptômes**: Un pod est en état `CrashLoopBackOff` dans `kubectl get pods`

**Procédure**:

1. Vérifiez les logs du pod:
   ```bash
   kubectl logs <nom_pod> -n <namespace>
   ```

2. Vérifiez les événements du pod:
   ```bash
   kubectl describe pod <nom_pod> -n <namespace>
   ```

3. Vérifiez les limites de ressources:
   ```bash
   kubectl get pod <nom_pod> -n <namespace> -o yaml | grep -A 10 resources
   ```

4. Si le problème est lié aux ressources, augmentez les limites:
   ```bash
   kubectl edit deployment <nom_deployment> -n <namespace>
   # Modifiez les sections resources.requests et resources.limits
   ```

5. Si le problème est lié à la configuration, vérifiez les ConfigMaps et Secrets:
   ```bash
   kubectl get configmap -n <namespace>
   kubectl get secret -n <namespace>
   ```

#### Pods en État ImagePullBackOff

**Symptômes**: Un pod est en état `ImagePullBackOff` dans `kubectl get pods`

**Procédure**:

1. Vérifiez les événements du pod:
   ```bash
   kubectl describe pod <nom_pod> -n <namespace>
   ```

2. Vérifiez que l'image existe et est accessible:
   ```bash
   # Sur le nœud
   crictl pull <image>
   ```

3. Si l'image est dans un registre privé, vérifiez les secrets d'authentification:
   ```bash
   kubectl get secret -n <namespace>
   kubectl describe secret <nom_secret> -n <namespace>
   ```

4. Corrigez le nom de l'image ou les secrets d'authentification:
   ```bash
   kubectl edit deployment <nom_deployment> -n <namespace>
   # Modifiez la section spec.template.spec.containers[].image
   # ou ajoutez/corrigez spec.template.spec.imagePullSecrets
   ```

### Problèmes de Réseau

#### Problèmes d'Ingress

**Symptômes**: Impossible d'accéder aux services via leurs URLs

**Procédure**:

1. Vérifiez l'état des Ingress:
   ```bash
   kubectl get ingress --all-namespaces
   ```

2. Vérifiez les détails de l'Ingress problématique:
   ```bash
   kubectl describe ingress <nom_ingress> -n <namespace>
   ```

3. Vérifiez que Traefik fonctionne correctement:
   ```bash
   kubectl get pods -n kube-system -l app=traefik
   kubectl logs -n kube-system -l app=traefik
   ```

4. Vérifiez les règles de routage Traefik:
   ```bash
   kubectl get ingressroute --all-namespaces
   kubectl get middleware --all-namespaces
   ```

5. Vérifiez que le service cible est accessible:
   ```bash
   kubectl get service <nom_service> -n <namespace>
   kubectl describe service <nom_service> -n <namespace>
   ```

6. Testez l'accès direct au service depuis un pod temporaire:
   ```bash
   kubectl run -it --rm debug --image=busybox -n <namespace> -- wget -O- <nom_service>:<port>
   ```

#### Problèmes de DNS

**Symptômes**: Les pods ne peuvent pas résoudre les noms de domaine

**Procédure**:

1. Vérifiez que CoreDNS fonctionne correctement:
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   kubectl logs -n kube-system -l k8s-app=kube-dns
   ```

2. Testez la résolution DNS depuis un pod:
   ```bash
   kubectl run -it --rm debug --image=busybox -- nslookup kubernetes.default.svc.cluster.local
   ```

3. Vérifiez la configuration DNS du pod:
   ```bash
   kubectl exec -it <nom_pod> -n <namespace> -- cat /etc/resolv.conf
   ```

4. Redémarrez CoreDNS si nécessaire:
   ```bash
   kubectl rollout restart deployment coredns -n kube-system
   ```

### Problèmes de Stockage

#### Volumes Persistants en État Pending

**Symptômes**: Un PVC reste en état `Pending` dans `kubectl get pvc`

**Procédure**:

1. Vérifiez l'état du PVC:
   ```bash
   kubectl describe pvc <nom_pvc> -n <namespace>
   ```

2. Vérifiez les StorageClasses disponibles:
   ```bash
   kubectl get storageclass
   ```

3. Vérifiez que la StorageClass spécifiée existe et est correctement configurée:
   ```bash
   kubectl describe storageclass <nom_storageclass>
   ```

4. Vérifiez l'espace disque disponible sur les nœuds:
   ```bash
   df -h
   ```

5. Si nécessaire, créez manuellement un PV pour le PVC:
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: PersistentVolume
   metadata:
     name: <nom_pv>
   spec:
     capacity:
       storage: <taille>
     accessModes:
       - ReadWriteOnce
     persistentVolumeReclaimPolicy: Retain
     storageClassName: <nom_storageclass>
     local:
       path: /mnt/data/<nom_pv>
     nodeAffinity:
       required:
         nodeSelectorTerms:
         - matchExpressions:
           - key: kubernetes.io/hostname
             operator: In
             values:
             - <nom_nœud>
   EOF
   ```

### Problèmes de Certificats

#### Échec de l'Émission de Certificats

**Symptômes**: Un certificat reste en état `False` pour `Ready` dans `kubectl get certificates`

**Procédure**:

1. Vérifiez l'état du certificat:
   ```bash
   kubectl describe certificate <nom_certificat> -n <namespace>
   ```

2. Vérifiez les CertificateRequests associés:
   ```bash
   kubectl get certificaterequests -n <namespace>
   kubectl describe certificaterequest <nom_certificaterequest> -n <namespace>
   ```

3. Vérifiez les logs de cert-manager:
   ```bash
   kubectl logs -n cert-manager -l app=cert-manager
   ```

4. Vérifiez que le ClusterIssuer est correctement configuré:
   ```bash
   kubectl describe clusterissuer <nom_clusterissuer>
   ```

5. Si le problème est lié à la validation HTTP01, vérifiez que Traefik est correctement configuré pour gérer les challenges ACME:
   ```bash
   kubectl get ingressroute -n cert-manager
   ```

6. Supprimez et recréez le certificat si nécessaire:
   ```bash
   kubectl delete certificate <nom_certificat> -n <namespace>
   # Recréez le certificat ou attendez que l'Ingress le recrée
   ```

### Problèmes de Base de Données

#### PostgreSQL ne Démarre Pas

**Symptômes**: Les pods PostgreSQL sont en état `CrashLoopBackOff` ou `Error`

**Procédure**:

1. Vérifiez les logs du pod PostgreSQL:
   ```bash
   kubectl logs <nom_pod_postgres> -n postgres-<environment>
   ```

2. Vérifiez les événements du pod:
   ```bash
   kubectl describe pod <nom_pod_postgres> -n postgres-<environment>
   ```

3. Vérifiez l'état du volume persistant:
   ```bash
   kubectl describe pvc postgres-data -n postgres-<environment>
   kubectl describe pv <nom_pv>
   ```

4. Si le problème est lié à la corruption de données, restaurez à partir d'une sauvegarde:
   ```bash
   ./lions-infrastructure/scripts/backup-restore.sh <environment> restore <nom_sauvegarde>
   ```

5. Si nécessaire, réinitialisez complètement PostgreSQL (attention: perte de données):
   ```bash
   kubectl delete statefulset postgres -n postgres-<environment>
   kubectl delete pvc postgres-data-postgres-0 -n postgres-<environment>
   # Redéployez PostgreSQL
   ./lions-infrastructure/scripts/deploy.sh --environment <environment> --component postgres
   ```

## Procédures de Récupération d'Urgence

### Restauration Complète du Cluster

**Scénario**: Le cluster K3s est corrompu ou irrécupérable

**Procédure**:

1. Arrêtez tous les services K3s:
   ```bash
   sudo systemctl stop k3s
   ```

2. Désinstallez K3s:
   ```bash
   /usr/local/bin/k3s-uninstall.sh
   ```

3. Nettoyez les répertoires persistants:
   ```bash
   sudo rm -rf /var/lib/rancher/k3s
   sudo rm -rf /etc/rancher/k3s
   ```

4. Réinstallez K3s:
   ```bash
   ./lions-infrastructure/scripts/install.sh --environment <environment>
   ```

5. Restaurez les données à partir de la dernière sauvegarde:
   ```bash
   ./lions-infrastructure/scripts/backup-restore.sh <environment> restore <nom_sauvegarde>
   ```

### Récupération après Perte de Données

**Scénario**: Perte de données dans un volume persistant

**Procédure**:

1. Identifiez le PVC et le namespace concernés:
   ```bash
   kubectl get pvc --all-namespaces
   ```

2. Arrêtez les pods qui utilisent le PVC:
   ```bash
   kubectl scale deployment <nom_deployment> --replicas=0 -n <namespace>
   # ou pour un StatefulSet
   kubectl scale statefulset <nom_statefulset> --replicas=0 -n <namespace>
   ```

3. Restaurez les données à partir d'une sauvegarde:
   ```bash
   ./lions-infrastructure/scripts/backup-restore.sh <environment> restore-pvc <nom_sauvegarde> <namespace> <nom_pvc>
   ```

4. Redémarrez les pods:
   ```bash
   kubectl scale deployment <nom_deployment> --replicas=<nombre_replicas> -n <namespace>
   # ou pour un StatefulSet
   kubectl scale statefulset <nom_statefulset> --replicas=<nombre_replicas> -n <namespace>
   ```

### Récupération après Compromission de Sécurité

**Scénario**: Compromission de sécurité suspectée ou confirmée

**Procédure**:

1. Isolez le cluster en restreignant l'accès réseau:
   ```bash
   # Désactivez temporairement les services exposés
   kubectl scale deployment traefik --replicas=0 -n kube-system
   ```

2. Identifiez l'étendue de la compromission:
   ```bash
   # Vérifiez les pods non autorisés
   kubectl get pods --all-namespaces
   
   # Vérifiez les services exposés
   kubectl get services --all-namespaces
   
   # Vérifiez les ingress
   kubectl get ingress --all-namespaces
   ```

3. Changez tous les secrets et mots de passe:
   ```bash
   # Pour chaque secret
   kubectl delete secret <nom_secret> -n <namespace>
   # Recréez le secret avec de nouvelles valeurs
   ```

4. Mettez à jour les certificats TLS:
   ```bash
   kubectl delete certificates --all --all-namespaces
   ```

5. Redéployez les composants critiques:
   ```bash
   ./lions-infrastructure/scripts/install.sh --environment <environment> --components security
   ```

6. Restaurez l'accès réseau:
   ```bash
   kubectl scale deployment traefik --replicas=1 -n kube-system
   ```

7. Surveillez attentivement les logs et les métriques pour détecter toute activité suspecte:
   ```bash
   # Configurez des alertes spécifiques dans Grafana
   ```

## Procédures d'Optimisation

### Optimisation des Ressources

**Fréquence recommandée**: Mensuelle

**Procédure**:

1. Analysez l'utilisation des ressources:
   ```bash
   kubectl top nodes
   kubectl top pods --all-namespaces
   ```

2. Identifiez les pods qui surconsomment ou sous-consomment des ressources:
   ```bash
   # Créez un script pour comparer l'utilisation réelle avec les requests/limits
   for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
     echo "Namespace: $ns"
     kubectl top pods -n $ns | tail -n +2 | while read pod cpu mem; do
       requests_cpu=$(kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.requests.cpu}')
       limits_cpu=$(kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.limits.cpu}')
       requests_mem=$(kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.requests.memory}')
       limits_mem=$(kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.limits.memory}')
       echo "$pod: CPU $cpu (req: $requests_cpu, lim: $limits_cpu), Mem $mem (req: $requests_mem, lim: $limits_mem)"
     done
   done
   ```

3. Ajustez les requests et limits en fonction de l'utilisation réelle:
   ```bash
   kubectl edit deployment <nom_deployment> -n <namespace>
   # Modifiez les sections resources.requests et resources.limits
   ```

### Configuration de l'Autoscaling

**Procédure**:

1. Activez l'autoscaling horizontal pour les déploiements appropriés:
   ```bash
   kubectl autoscale deployment <nom_deployment> -n <namespace> --min=1 --max=5 --cpu-percent=80
   ```

2. Vérifiez la configuration de l'autoscaling:
   ```bash
   kubectl get hpa --all-namespaces
   ```

3. Testez l'autoscaling:
   ```bash
   # Générez une charge sur le service
   kubectl run -it --rm load-generator --image=busybox -- /bin/sh -c "while true; do wget -q -O- http://<service>; done"
   
   # Observez le comportement de l'autoscaler
   kubectl get hpa -n <namespace> -w
   ```

## Procédures de Mise à Niveau

### Mise à Niveau de K3s

**Procédure**:

1. Vérifiez la version actuelle de K3s:
   ```bash
   k3s --version
   ```

2. Créez une sauvegarde complète:
   ```bash
   ./lions-infrastructure/scripts/backup-restore.sh <environment> backup pre-k3s-upgrade-$(date +%Y%m%d)
   ```

3. Mettez à jour K3s:
   ```bash
   curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=<nouvelle_version> sh -
   ```

4. Vérifiez que la mise à jour a réussi:
   ```bash
   k3s --version
   kubectl get nodes
   ```

5. Vérifiez que tous les pods sont en état Running:
   ```bash
   kubectl get pods --all-namespaces
   ```

### Mise à Niveau des Applications

**Procédure**:

1. Créez une sauvegarde avant la mise à niveau:
   ```bash
   ./lions-infrastructure/scripts/backup-restore.sh <environment> backup pre-app-upgrade-$(date +%Y%m%d)
   ```

2. Mettez à jour l'application:
   ```bash
   ./lions-infrastructure/scripts/deploy.sh --environment <environment> --application <nom_application> --version <nouvelle_version>
   ```

3. Vérifiez que la mise à jour a réussi:
   ```bash
   kubectl get pods -n <namespace>
   kubectl logs -n <namespace> -l app=<nom_application>
   ```

4. Testez l'application:
   ```bash
   # Effectuez des tests fonctionnels
   curl -s https://<url_application>/health
   ```

5. En cas de problème, effectuez un rollback:
   ```bash
   kubectl rollout undo deployment/<nom_deployment> -n <namespace>
   # ou
   ./lions-infrastructure/scripts/deploy.sh --environment <environment> --application <nom_application> --version <ancienne_version>
   ```

## Annexes

### Commandes Utiles

#### Commandes Kubernetes

```bash
# Obtenir des informations sur les ressources
kubectl get <resource> --all-namespaces
kubectl describe <resource> <name> -n <namespace>

# Exécuter des commandes dans un pod
kubectl exec -it <pod> -n <namespace> -- <command>

# Copier des fichiers depuis/vers un pod
kubectl cp <namespace>/<pod>:/path/to/file /local/path
kubectl cp /local/path <namespace>/<pod>:/path/to/file

# Redémarrer un déploiement
kubectl rollout restart deployment/<name> -n <namespace>

# Voir l'historique des déploiements
kubectl rollout history deployment/<name> -n <namespace>

# Revenir à une version précédente
kubectl rollout undo deployment/<name> -n <namespace> [--to-revision=<revision>]

# Créer un port-forward vers un service
kubectl port-forward service/<name> <local_port>:<service_port> -n <namespace>
```

#### Commandes Système

```bash
# Vérifier l'utilisation des ressources
top
htop
free -h
df -h

# Vérifier les logs système
journalctl -u k3s
journalctl -u k3s-agent

# Vérifier les connexions réseau
netstat -tulpn
ss -tulpn

# Vérifier les processus
ps aux | grep <process>
```

### Contacts d'Urgence

- **Équipe Infrastructure**: infrastructure@lions.dev
- **Équipe Sécurité**: security@lions.dev
- **Support Technique**: support@lions.dev

### Références

- [Documentation K3s](https://docs.k3s.io/)
- [Documentation Kubernetes](https://kubernetes.io/docs/)
- [Documentation Traefik](https://doc.traefik.io/traefik/)
- [Documentation Cert-Manager](https://cert-manager.io/docs/)
- [Documentation Prometheus](https://prometheus.io/docs/)
- [Documentation Grafana](https://grafana.com/docs/)