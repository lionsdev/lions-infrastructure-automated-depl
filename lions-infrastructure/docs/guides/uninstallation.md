# Guide de Désinstallation de l'Infrastructure LIONS

Ce guide détaille les étapes nécessaires pour désinstaller l'infrastructure LIONS et nettoyer tous les composants associés.

## Avertissement

**ATTENTION**: La désinstallation de l'infrastructure LIONS est une opération irréversible qui supprimera toutes les applications et données associées à l'environnement spécifié. Assurez-vous de sauvegarder toutes les données importantes avant de procéder.

## Prérequis

- Accès SSH au serveur où l'infrastructure LIONS est déployée
- Droits sudo sur le serveur
- Le dépôt `lions-infrastructure-automated-depl` cloné sur le serveur

## Procédure de Désinstallation

### 1. Sauvegarde des Données (Recommandé)

Avant de désinstaller l'infrastructure, il est fortement recommandé de sauvegarder toutes les données importantes :

```bash
./lions-infrastructure/scripts/backup-restore.sh <environment> backup pre-uninstall-$(date +%Y%m%d)
```

Cela créera une sauvegarde complète de l'environnement spécifié dans le répertoire `lions-infrastructure/backups/`.

### 2. Exécution du Script de Désinstallation

Pour désinstaller l'infrastructure LIONS, utilisez le script `uninstall.sh` :

```bash
./lions-infrastructure/scripts/uninstall.sh --environment <environment>
```

Remplacez `<environment>` par l'environnement que vous souhaitez désinstaller (`development`, `staging` ou `production`).

### 3. Options du Script

Le script `uninstall.sh` accepte les options suivantes :

- `-e, --environment <env>` : Environnement cible (production, staging, development). Par défaut : development
- `-i, --inventory <file>` : Fichier d'inventaire Ansible spécifique. Par défaut : inventories/development/hosts.yml
- `-f, --force` : Ne pas demander de confirmation (utile pour les scripts automatisés)
- `-d, --debug` : Active le mode debug pour afficher plus d'informations
- `-h, --help` : Affiche l'aide du script

### 4. Confirmation

Par défaut, le script demandera une confirmation avant de procéder à la désinstallation. Vous devrez taper `oui` pour confirmer.

Si vous utilisez l'option `--force`, aucune confirmation ne sera demandée, et la désinstallation commencera immédiatement.

## Composants Désinstallés

Le script de désinstallation supprime les composants suivants dans l'ordre inverse de leur installation :

1. **Applications Kubernetes** :
   - Gitea
   - Keycloak
   - PostgreSQL
   - PgAdmin
   - Registry
   - Ollama
   - Monitoring (Prometheus, Grafana)
   - Cert-Manager
   - Traefik

2. **HashiCorp Vault** :
   - Service Vault
   - Fichiers de configuration
   - Données stockées
   - Namespace Kubernetes

3. **K3s** :
   - Service K3s
   - Répertoires persistants
   - Interfaces réseau CNI
   - Règles iptables

4. **Données Persistantes** :
   - Répertoires de données
   - Logs
   - Sauvegardes

## Vérification de la Désinstallation

Après l'exécution du script, vous pouvez vérifier que tous les composants ont été correctement désinstallés :

```bash
# Vérification des services systemd
systemctl status k3s
systemctl status vault

# Vérification des répertoires
ls -la /var/lib/rancher/k3s
ls -la /etc/rancher/k3s
ls -la /etc/vault.d
ls -la /opt/vault
ls -la /var/log/lions
```

## Réinstallation

Si vous souhaitez réinstaller l'infrastructure LIONS après une désinstallation, vous pouvez utiliser le script d'installation standard :

```bash
./lions-infrastructure/scripts/install.sh --environment <environment>
```

## Journaux de Désinstallation

Les journaux de désinstallation sont stockés dans le répertoire `lions-infrastructure/logs/uninstall/`. Ils peuvent être utiles pour diagnostiquer d'éventuels problèmes lors de la désinstallation.

## Problèmes Courants

### Erreur "Permission Denied"

Si vous rencontrez des erreurs de permission lors de la désinstallation, assurez-vous d'avoir les droits sudo sur le serveur.

### Composants Non Désinstallés

Si certains composants ne sont pas correctement désinstallés, vous pouvez exécuter à nouveau le script avec l'option `--debug` pour obtenir plus d'informations sur les erreurs.

### Interfaces Réseau Persistantes

Si des interfaces réseau CNI persistent après la désinstallation, vous pouvez les supprimer manuellement :

```bash
sudo ip link delete <nom_interface>
```

## Support

Pour toute assistance supplémentaire, contactez l'équipe d'infrastructure LIONS à infrastructure@lions.dev.