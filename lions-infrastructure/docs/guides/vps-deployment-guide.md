# Guide de Déploiement de l'Infrastructure LIONS sur VPS

Ce guide détaille les étapes nécessaires pour déployer l'infrastructure LIONS sur un VPS (Virtual Private Server) unique, optimisé pour les environnements avec des ressources limitées.

## Prérequis

### Configuration minimale du VPS

- **CPU** : 6 cœurs
- **RAM** : 12 Go
- **Stockage** : 400 Go SSD
- **Système d'exploitation** : Ubuntu 20.04 LTS
- **Bande passante** : 300 Mbit/s minimum recommandé

### Logiciels requis sur la machine de contrôle

- Ansible v2.12+
- SSH client
- kubectl v1.24+
- Helm v3.8+
- Git v2.30+

## Préparation de l'environnement

### 1. Cloner le dépôt

```bash
git clone https://github.com/lions-org/lions-infrastructure-automated-depl.git
cd lions-infrastructure-automated-depl
```

### 2. Configuration de l'accès SSH

Assurez-vous que votre clé SSH est configurée pour accéder au VPS :

```bash
# Générer une paire de clés si vous n'en avez pas
ssh-keygen -t ed25519 -C "votre_email@domaine.com"

# Copier la clé sur le serveur
ssh-copy-id -p <port_ssh> lionsdevadmin@<ip_vps>

# Tester la connexion
ssh -p <port_ssh> lionsdevadmin@<ip_vps>
```

### 3. Configuration de l'inventaire Ansible

L'inventaire Ansible pour le VPS a déjà été configuré dans le fichier `ansible/inventories/development/hosts.yml`. Vérifiez et modifiez ce fichier si nécessaire :

```yaml
---
all:
  children:
    vps:
      hosts:
        contabo-vps:
          ansible_host: <ip_vps>
          ansible_port: <port_ssh>
          ansible_user: lionsdevadmin
          ansible_python_interpreter: /usr/bin/python3
    kubernetes:
      hosts:
        contabo-vps:
          ansible_host: <ip_vps>
          ansible_port: <port_ssh>
    databases:
      hosts:
        contabo-vps:
          ansible_host: <ip_vps>
          ansible_port: <port_ssh>
    monitoring:
      hosts:
        contabo-vps:
          ansible_host: <ip_vps>
          ansible_port: <port_ssh>
  vars:
    ansible_user: lionsdevadmin
    ansible_ssh_private_key_file: ~/.ssh/id_ed25519
    ansible_become: yes
    environment: development
    domain_name: dev.lions.dev
```

Remplacez `<ip_vps>` par l'adresse IP de votre VPS et `<port_ssh>` par le port SSH configuré.

## Déploiement de l'infrastructure

### 1. Exécution du script d'installation

Le script `install.sh` orchestre l'ensemble du processus de déploiement :

```bash
# Rendre le script exécutable
chmod +x lions-infrastructure/scripts/install.sh

# Exécuter le script
./lions-infrastructure/scripts/install.sh
```

Options disponibles :

```
-e, --environment <env>   Environnement cible (production, staging, development)
                         Par défaut: development
-i, --inventory <file>    Fichier d'inventaire Ansible spécifique
                         Par défaut: inventories/development/hosts.yml
-s, --skip-init           Ignorer l'initialisation du VPS (si déjà effectuée)
-d, --debug               Active le mode debug
-h, --help                Affiche l'aide
```

### 2. Étapes du déploiement

Le script d'installation exécute les étapes suivantes :

1. **Vérification des prérequis** : S'assure que tous les outils nécessaires sont installés.
2. **Initialisation du VPS** : Configure le système d'exploitation, installe les dépendances, configure le pare-feu, etc.
3. **Installation de K3s** : Déploie K3s, une distribution légère de Kubernetes adaptée aux environnements avec ressources limitées.
4. **Installation des composants essentiels** : Déploie MetalLB, cert-manager, Nginx Ingress Controller et Kubernetes Dashboard.
5. **Déploiement de l'infrastructure de base** : Configure les namespaces, les quotas de ressources, etc.
6. **Déploiement du monitoring** : Installe Prometheus et Grafana pour la surveillance.
7. **Vérification finale** : S'assure que tous les composants sont correctement déployés.

## Quotas de ressources

Les quotas de ressources ont été ajustés pour s'adapter à la configuration du VPS (6 cœurs, 12 Go RAM) :

```yaml
requests.cpu: '5'
requests.memory: 10Gi
limits.cpu: '6'
limits.memory: 12Gi
```

Ces valeurs laissent une marge pour les processus système tout en maximisant l'utilisation des ressources disponibles.

## Accès aux interfaces

Une fois le déploiement terminé, vous pouvez accéder aux interfaces suivantes :

- **Grafana** : `http://<ip_vps>:30000`
  - Identifiant : `admin`
  - Mot de passe : `admin` (à changer après la première connexion)

- **Kubernetes Dashboard** :
  - Via NodePort : `https://<ip_vps>:30001`
  - Via domaine (production) : `https://k3s.lions.dev`
  - Via domaine (développement) : `https://k3s.dev.lions.dev`
  - Pour vous connecter, utilisez le token permanent affiché dans les logs d'installation
  - Vous pouvez également récupérer le token permanent avec la commande :
    ```bash
    kubectl get secret dashboard-admin-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 --decode
    ```
  - Ce token est permanent et ne nécessite pas d'être régénéré à chaque connexion

  > **Note** : L'accès via les domaines nécessite que vos enregistrements DNS soient correctement configurés pour pointer vers l'adresse IP de votre VPS.

## Déploiement d'applications

Pour déployer des applications sur l'infrastructure, utilisez le script `deploy.sh` :

```bash
./lions-infrastructure/scripts/deploy.sh --environment development <nom_application>
```

Consultez le [Guide de Déploiement d'Applications](deployment.md) pour plus de détails.

## Optimisations pour VPS

Plusieurs optimisations ont été appliquées pour adapter l'infrastructure à un environnement VPS :

1. **Utilisation de K3s** au lieu de K8s standard, avec désactivation des composants non essentiels :
   - Traefik (remplacé par Nginx Ingress)
   - ServiceLB (remplacé par MetalLB)
   - Cloud Controller

2. **Optimisation de la mémoire** :
   - Configuration du swap (4 Go)
   - Réglage de `vm.swappiness=10` et `vm.vfs_cache_pressure=50`

3. **Ajustement des quotas de ressources** pour les applications :
   - Quarkus : 100m-500m CPU, 256Mi-512Mi mémoire
   - PrimeFaces : 200m-500m CPU, 512Mi-1Gi mémoire
   - PrimeReact : 100m-500m CPU, 256Mi-512Mi mémoire

## Surveillance des ressources

Pour surveiller l'utilisation des ressources sur votre VPS :

```bash
# Utilisation des ressources des nœuds
kubectl top nodes

# Utilisation des ressources des pods
kubectl top pods --all-namespaces

# Vérification de l'état des pods
kubectl get pods --all-namespaces
```

## Maintenance

### Mise à jour du système

Pour mettre à jour le système d'exploitation du VPS :

```bash
ansible-playbook -i ansible/inventories/development/hosts.yml ansible/playbooks/maintenance.yml --tags "system-update"
```

### Sauvegarde de l'état de Kubernetes

Pour sauvegarder l'état actuel de Kubernetes :

```bash
./lions-infrastructure/scripts/maintenance/backup-k8s.sh
```

### Redémarrage des services

En cas de problème, vous pouvez redémarrer les services K3s :

```bash
ansible-playbook -i ansible/inventories/development/hosts.yml ansible/playbooks/maintenance.yml --tags "restart-k3s"
```

## Dépannage

### Problèmes courants

#### Échec de l'initialisation du VPS

Vérifiez les logs d'initialisation :

```bash
cat /var/log/lions/infrastructure/install-*.log
```

Assurez-vous que l'utilisateur `lionsdevadmin` a les droits sudo et que la clé SSH est correctement configurée.

#### Échec de l'installation de K3s

Vérifiez les logs de K3s :

```bash
sudo journalctl -u k3s
```

Assurez-vous que les ports nécessaires (6443, 80, 443) sont ouverts dans le pare-feu.

#### Problèmes de ressources

Si les pods restent en état "Pending" :

```bash
kubectl describe pod <nom_pod> -n <namespace>
```

Vérifiez si le problème est lié aux ressources et ajustez les quotas si nécessaire.

## Ressources supplémentaires

- [Guide d'installation standard](installation.md)
- [Guide d'administration](administration.md)
- [Guide de déploiement](deployment.md)
- [Guide de surveillance](monitoring.md)
- [Architecture de référence](../architecture/overview.md)
