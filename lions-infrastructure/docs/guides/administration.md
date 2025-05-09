# Guide d'Administration de l'Infrastructure LIONS

Ce guide détaille les tâches d'administration courantes pour gérer l'infrastructure LIONS.

## Gestion des utilisateurs et des droits d'accès

### Ajout d'un nouvel utilisateur

Pour ajouter un nouvel utilisateur à l'infrastructure LIONS :

```bash
./scripts/manage-users.sh --add-user <username> --role <role> --environments <env1,env2>
```

Exemple :
```bash
./scripts/manage-users.sh --add-user john.doe --role developer --environments development,staging
```

### Rôles disponibles

L'infrastructure LIONS définit plusieurs rôles avec différents niveaux d'accès :

| Rôle | Description | Droits |
|------|-------------|--------|
| `viewer` | Lecture seule | Peut voir les ressources mais ne peut pas les modifier |
| `developer` | Développeur | Peut déployer et gérer ses propres applications |
| `operator` | Opérateur | Peut gérer toutes les applications et certaines ressources d'infrastructure |
| `admin` | Administrateur | Accès complet à toutes les ressources |

### Modification des droits d'un utilisateur

Pour modifier les droits d'un utilisateur existant :

```bash
./scripts/manage-users.sh --update-user <username> --role <new-role> --environments <env1,env2>
```

### Suppression d'un utilisateur

Pour supprimer un utilisateur :

```bash
./scripts/manage-users.sh --remove-user <username>
```

### Audit des accès

Pour auditer les accès et les actions des utilisateurs :

```bash
./scripts/audit-access.sh --user <username> --start-date <YYYY-MM-DD> --end-date <YYYY-MM-DD>
```

## Gestion des environnements

### Création d'un nouvel environnement

Pour créer un nouvel environnement personnalisé (en plus des environnements standard) :

```bash
./scripts/manage-environments.sh --create --name <environment-name> --domain <domain-suffix>
```

Exemple :
```bash
./scripts/manage-environments.sh --create --name testing --domain test.lions.dev
```

### Configuration d'un environnement

Pour modifier la configuration d'un environnement existant :

```bash
./scripts/manage-environments.sh --update --name <environment-name> --set <key=value> [--set <key=value> ...]
```

Exemple :
```bash
./scripts/manage-environments.sh --update --name development --set resource_quota_cpu=8 --set resource_quota_memory=16Gi
```

### Suppression d'un environnement

Pour supprimer un environnement personnalisé :

```bash
./scripts/manage-environments.sh --delete --name <environment-name>
```

## Gestion du cluster Kubernetes

### Ajout d'un nouveau nœud

Pour ajouter un nouveau nœud au cluster Kubernetes :

```bash
./scripts/manage-nodes.sh --add --hostname <hostname> --ip <ip-address> --role <worker|control-plane>
```

### Maintenance d'un nœud

Pour mettre un nœud en mode maintenance :

```bash
./scripts/manage-nodes.sh --drain --hostname <hostname>
```

Pour réactiver un nœud après maintenance :

```bash
./scripts/manage-nodes.sh --uncordon --hostname <hostname>
```

### Suppression d'un nœud

Pour supprimer un nœud du cluster :

```bash
./scripts/manage-nodes.sh --remove --hostname <hostname>
```

### Mise à jour de Kubernetes

Pour mettre à jour la version de Kubernetes :

```bash
./scripts/upgrade-kubernetes.sh --version <version>
```

## Gestion du stockage

### Ajout d'une nouvelle classe de stockage

Pour ajouter une nouvelle classe de stockage :

```bash
./scripts/manage-storage.sh --add-class --name <class-name> --provisioner <provisioner> [--parameters <key=value> ...]
```

Exemple :
```bash
./scripts/manage-storage.sh --add-class --name fast-ssd --provisioner kubernetes.io/aws-ebs --parameters type=gp3,iopsPerGB=3000
```

### Gestion des volumes persistants

Pour lister les volumes persistants :

```bash
./scripts/manage-storage.sh --list-volumes
```

Pour supprimer un volume persistant :

```bash
./scripts/manage-storage.sh --delete-volume <pv-name>
```

### Configuration des sauvegardes

Pour configurer les sauvegardes automatiques :

```bash
./scripts/configure-backups.sh --storage-class <class-name> --schedule "0 2 * * *" --retention 7d
```

## Gestion de la surveillance

### Ajout d'un tableau de bord Grafana

Pour ajouter un tableau de bord Grafana personnalisé :

```bash
./scripts/manage-monitoring.sh --add-dashboard --file <path-to-dashboard.json> [--folder <folder-name>]
```

### Configuration des alertes

Pour ajouter des règles d'alerte personnalisées :

```bash
./scripts/manage-monitoring.sh --add-alerts --file <path-to-alerts.yaml>
```

### Configuration des notifications

Pour configurer les canaux de notification :

```bash
./scripts/manage-monitoring.sh --configure-notifications --type <email|slack|pagerduty> --config <key=value> [--config <key=value> ...]
```

Exemple :
```bash
./scripts/manage-monitoring.sh --configure-notifications --type slack --config webhook_url=https://hooks.slack.com/services/XXX/YYY/ZZZ --config channel=#alerts
```

## Gestion des applications

### Liste des applications déployées

Pour lister toutes les applications déployées :

```bash
./scripts/list-applications.sh [--environment <environment>]
```

### Suppression d'une application

Pour supprimer complètement une application :

```bash
./scripts/undeploy.sh --application <app-name> --environment <environment>
```

### Mise à l'échelle d'une application

Pour ajuster le nombre de réplicas d'une application :

```bash
./scripts/scale-application.sh --application <app-name> --environment <environment> --replicas <count>
```

## Gestion des certificats TLS

### Renouvellement manuel d'un certificat

Bien que cert-manager renouvelle automatiquement les certificats, vous pouvez forcer le renouvellement :

```bash
./scripts/manage-certificates.sh --renew --domain <domain>
```

### Ajout d'un certificat personnalisé

Pour utiliser un certificat personnalisé au lieu de Let's Encrypt :

```bash
./scripts/manage-certificates.sh --add-custom --domain <domain> --cert-file <path-to-cert> --key-file <path-to-key>
```

## Maintenance du système

### Nettoyage des ressources inutilisées

Pour nettoyer les ressources inutilisées et libérer de l'espace :

```bash
./scripts/cleanup.sh [--dry-run]
```

Options disponibles :
- `--images` : Nettoie les images Docker inutilisées
- `--volumes` : Nettoie les volumes persistants orphelins
- `--namespaces` : Supprime les namespaces vides
- `--all` : Nettoie tous les types de ressources

### Vérification de l'état du système

Pour vérifier l'état général du système :

```bash
./scripts/system-check.sh
```

Cette commande vérifie :
- L'état des nœuds Kubernetes
- L'utilisation des ressources
- L'état des composants critiques
- Les certificats expirant prochainement
- Les problèmes de stockage

### Rotation des logs

Pour configurer la rotation des logs :

```bash
./scripts/configure-log-rotation.sh --max-size <size> --max-files <count>
```

Exemple :
```bash
./scripts/configure-log-rotation.sh --max-size 500M --max-files 10
```

## Gestion des secrets

### Rotation des secrets

Pour effectuer une rotation des secrets :

```bash
./scripts/rotate-secrets.sh --namespace <namespace> --secret <secret-name>
```

### Intégration avec un gestionnaire de secrets externe

Pour configurer l'intégration avec HashiCorp Vault :

```bash
./scripts/configure-vault.sh --url <vault-url> --token <vault-token> --path <secret-path>
```

## Mise à jour de l'infrastructure LIONS

### Vérification des mises à jour disponibles

Pour vérifier si des mises à jour sont disponibles :

```bash
./scripts/check-updates.sh
```

### Application des mises à jour

Pour mettre à jour l'infrastructure LIONS :

```bash
./scripts/update-infrastructure.sh [--version <version>]
```

## Dépannage

### Collecte des informations de diagnostic

Pour collecter des informations de diagnostic en cas de problème :

```bash
./scripts/collect-diagnostics.sh [--output-dir <directory>]
```

Cette commande collecte :
- Les logs des composants système
- L'état des ressources Kubernetes
- Les métriques de performance
- Les événements récents

### Restauration après un incident

Pour restaurer le système après un incident majeur :

```bash
./scripts/disaster-recovery.sh --backup <backup-name>
```

## Bonnes pratiques

### Sécurité

- Effectuez régulièrement des audits de sécurité
- Mettez à jour les composants dès que des correctifs de sécurité sont disponibles
- Utilisez le principe du moindre privilège pour les droits d'accès
- Activez l'authentification à deux facteurs pour tous les utilisateurs

### Performance

- Surveillez l'utilisation des ressources et ajustez les limites si nécessaire
- Utilisez l'autoscaling pour gérer les pics de charge
- Optimisez les requêtes de base de données et les appels API

### Fiabilité

- Testez régulièrement les procédures de sauvegarde et de restauration
- Mettez en place des tests de chaos pour vérifier la résilience
- Documentez les incidents et les solutions dans les runbooks

## Ressources supplémentaires

- [Guide d'installation](installation.md)
- [Guide de déploiement](deployment.md)
- [Guide de surveillance](monitoring.md)
- [Architecture de référence](../architecture/overview.md)
- [Runbooks opérationnels](../runbooks/index.md)