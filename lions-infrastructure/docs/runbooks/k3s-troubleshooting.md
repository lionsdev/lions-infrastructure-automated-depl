# Guide de dépannage K3s

Ce document fournit des instructions pour résoudre les problèmes courants avec K3s dans l'infrastructure LIONS.

## Table des matières

1. [Problème avec le flag RemoveSelfLink](#problème-avec-le-flag-removeselflink)
2. [Problèmes de démarrage de K3s](#problèmes-de-démarrage-de-k3s)
3. [Problèmes de connexion à l'API Kubernetes](#problèmes-de-connexion-à-lapi-kubernetes)
4. [Problèmes avec les pods système](#problèmes-avec-les-pods-système)

## Problème avec le flag RemoveSelfLink

### Symptômes

Le service K3s ne démarre pas et les journaux contiennent une erreur similaire à celle-ci :

```
● k3s.service - Lightweight Kubernetes
     Loaded: loaded (/etc/systemd/system/k3s.service; enabled; vendor preset: enabled)
     Active: activating (auto-restart) (Result: exit-code) since Thu 2025-05-22 11:13:43 CEST; 140ms ago
       Docs: https://k3s.io
    Process: 1026612 ExecStart=/usr/local/bin/k3s server --disable traefik --disable servicelb --disable local-storage --write-kubeconfig-mode 644 --kubelet-arg cgroup-driver=systemd --kubelet-arg feature-gates=GracefulNodeShutdown=false --kube-controller-manager-arg feature-gates=RemoveSelfLink=false (code=exited, status=1/FAILURE)
   Main PID: 1026612 (code=exited, status=1/FAILURE)
```

### Cause

Le flag `--kube-controller-manager-arg feature-gates=RemoveSelfLink=false` est déprécié dans les versions récentes de Kubernetes (K3s v1.28.6+k3s2) et cause l'échec du démarrage du service.

### Solution

Exécutez le script `fix-k3s.sh` pour corriger le problème :

```bash
cd /opt/lions-infrastructure-automated-depl/lions-infrastructure/scripts
sudo chmod +x fix-k3s.sh
sudo ./fix-k3s.sh
```

Ce script effectue les opérations suivantes :
1. Arrête le service K3s
2. Sauvegarde le fichier de service K3s
3. Supprime le flag `RemoveSelfLink=false` du fichier de service
4. Recharge la configuration systemd
5. Redémarre le service K3s
6. Vérifie que le service a démarré correctement

### Prévention

Pour éviter que ce problème ne se reproduise lors de futures installations, exécutez le script `update-ansible-playbook.sh` :

```bash
cd /opt/lions-infrastructure-automated-depl/lions-infrastructure/scripts
sudo chmod +x update-ansible-playbook.sh
sudo ./update-ansible-playbook.sh
```

Ce script met à jour le playbook Ansible pour supprimer le flag `RemoveSelfLink=false` des arguments du serveur K3s.

## Problèmes de démarrage de K3s

### Symptômes

Le service K3s ne démarre pas ou redémarre en boucle.

### Diagnostic

Vérifiez les journaux du service K3s :

```bash
sudo journalctl -u k3s -n 100
```

### Solutions courantes

1. **Problèmes de cgroups** :

   ```bash
   # Vérification des cgroups
   mount | grep cgroup
   
   # Correction des cgroups
   sudo mkdir -p /sys/fs/cgroup/systemd
   sudo mount -t cgroup -o none,name=systemd cgroup /sys/fs/cgroup/systemd
   ```

2. **Problèmes de réseau** :

   ```bash
   # Vérification des interfaces réseau
   ip a
   
   # Vérification des règles iptables
   sudo iptables -L
   
   # Réinitialisation des règles iptables
   sudo iptables -F
   ```

3. **Réinstallation propre de K3s** :

   ```bash
   # Désinstallation de K3s
   sudo /usr/local/bin/k3s-uninstall.sh
   
   # Nettoyage des répertoires
   sudo rm -rf /var/lib/rancher/k3s
   sudo rm -rf /etc/rancher/k3s
   
   # Réinstallation de K3s
   curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.28.6+k3s2" INSTALL_K3S_EXEC="server --disable=traefik --disable=servicelb --disable=local-storage --write-kubeconfig-mode 644 --kubelet-arg cgroup-driver=systemd --kubelet-arg feature-gates=GracefulNodeShutdown=false" sh -
   ```

## Problèmes de connexion à l'API Kubernetes

### Symptômes

Impossible de se connecter à l'API Kubernetes avec kubectl.

### Diagnostic

```bash
# Vérification de l'état du service K3s
sudo systemctl status k3s

# Vérification que l'API est accessible
curl -k https://localhost:6443/healthz

# Vérification du fichier kubeconfig
ls -la /etc/rancher/k3s/k3s.yaml
```

### Solutions courantes

1. **Problèmes de permissions** :

   ```bash
   # Correction des permissions du fichier kubeconfig
   sudo chmod 644 /etc/rancher/k3s/k3s.yaml
   ```

2. **Problèmes de certificats** :

   ```bash
   # Vérification des certificats
   ls -la /var/lib/rancher/k3s/server/tls
   
   # Suppression des certificats pour forcer leur régénération
   sudo systemctl stop k3s
   sudo rm -rf /var/lib/rancher/k3s/server/tls
   sudo systemctl start k3s
   ```

## Problèmes avec les pods système

### Symptômes

Les pods système (coredns, metrics-server, etc.) ne démarrent pas ou sont en état d'erreur.

### Diagnostic

```bash
# Vérification des pods système
kubectl get pods -n kube-system

# Vérification des logs des pods
kubectl logs -n kube-system <nom-du-pod>

# Vérification des événements
kubectl get events -n kube-system
```

### Solutions courantes

1. **Problèmes de réseau CNI** :

   ```bash
   # Vérification du CNI
   ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d/
   
   # Redémarrage de K3s pour réinitialiser le CNI
   sudo systemctl restart k3s
   ```

2. **Problèmes de stockage** :

   ```bash
   # Vérification de l'espace disque
   df -h
   
   # Nettoyage des images Docker inutilisées
   sudo k3s crictl rmi --prune
   ```

3. **Problèmes de mémoire** :

   ```bash
   # Vérification de la mémoire disponible
   free -h
   
   # Augmentation du swap si nécessaire
   sudo fallocate -l 2G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

---

Pour toute assistance supplémentaire, contactez l'équipe d'infrastructure LIONS à infrastructure@lions.dev.