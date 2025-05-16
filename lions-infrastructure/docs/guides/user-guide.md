# Guide Utilisateur de l'Infrastructure LIONS

## Introduction

Ce guide est destiné aux utilisateurs de l'infrastructure LIONS. Il explique comment utiliser les différentes fonctionnalités de l'infrastructure, déployer des applications, accéder aux services, et effectuer des tâches courantes.

## Prérequis

Avant de commencer à utiliser l'infrastructure LIONS, assurez-vous d'avoir les éléments suivants :

- Accès au VPS (identifiants SSH)
- Accès au dépôt Git (identifiants Gitea)
- Accès au Kubernetes Dashboard (token d'authentification)
- kubectl installé sur votre machine locale (optionnel)
- Helm installé sur votre machine locale (optionnel)

## Accès aux Services

### Kubernetes Dashboard

Le Kubernetes Dashboard vous permet de visualiser et de gérer les ressources Kubernetes de l'infrastructure.

- URL : https://k8s.lions.dev
- Authentification : Token

Pour obtenir un token d'authentification :

```bash
# Sur le VPS
kubectl get secret dashboard-admin-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 --decode
```

### Grafana

Grafana vous permet de visualiser les métriques et les tableaux de bord de monitoring.

- URL : https://grafana.lions.dev
- Identifiant par défaut : admin
- Mot de passe par défaut : admin

### PgAdmin

PgAdmin vous permet de gérer les bases de données PostgreSQL.

- URL : https://pgadmin.lions.dev
- Identifiant : admin@lions.dev
- Mot de passe : Voir le secret dans Kubernetes

Pour obtenir le mot de passe :

```bash
# Sur le VPS
kubectl get secret pgadmin-admin-password -n pgadmin-development -o jsonpath='{.data.password}' | base64 --decode
```

### Gitea

Gitea est un serveur Git auto-hébergé qui vous permet de gérer vos dépôts de code source.

- URL : https://git.lions.dev
- Identifiant : Créez votre compte ou utilisez un compte existant

### Keycloak

Keycloak est un gestionnaire d'identité et d'accès qui centralise l'authentification pour les applications.

- URL : https://keycloak.lions.dev
- Identifiant administrateur : admin
- Mot de passe administrateur : Voir le secret dans Kubernetes

Pour obtenir le mot de passe :

```bash
# Sur le VPS
kubectl get secret keycloak-admin-password -n keycloak-development -o jsonpath='{.data.password}' | base64 --decode
```

## Déploiement d'Applications

### Utilisation du Script de Déploiement

L'infrastructure LIONS fournit un script de déploiement qui simplifie le processus de déploiement des applications.

```bash
# Sur le VPS
cd /lions-infrastructure-automated-depl
./lions-infrastructure/scripts/deploy.sh --environment development --application <nom_application>
```

Options disponibles :
- `--environment` : Environnement de déploiement (development, staging, production)
- `--application` : Nom de l'application à déployer
- `--version` : Version de l'application à déployer (par défaut : latest)
- `--replicas` : Nombre de réplicas à déployer (par défaut : 1)

### Déploiement Manuel via kubectl

Si vous préférez déployer manuellement vos applications, vous pouvez utiliser kubectl :

```bash
# Sur le VPS ou sur votre machine locale avec le bon contexte kubectl
kubectl apply -f <fichier_yaml>
```

### Déploiement via GitOps (Flux CD)

Pour un déploiement automatisé via GitOps :

1. Poussez vos changements vers le dépôt Git surveillé par Flux CD
2. Flux CD détectera automatiquement les changements et les appliquera au cluster

## Gestion des Applications

### Vérification de l'État des Applications

Pour vérifier l'état de vos applications :

```bash
# Sur le VPS ou sur votre machine locale avec le bon contexte kubectl
kubectl get pods -n <namespace>
kubectl get deployments -n <namespace>
kubectl get services -n <namespace>
kubectl get ingress -n <namespace>
```

### Consultation des Logs

Pour consulter les logs de vos applications :

```bash
# Sur le VPS ou sur votre machine locale avec le bon contexte kubectl
kubectl logs -f deployment/<nom_deployment> -n <namespace>
```

Vous pouvez également utiliser Grafana et Loki pour une consultation centralisée des logs :

1. Accédez à Grafana (https://grafana.lions.dev)
2. Naviguez vers le tableau de bord "Loki Logs"
3. Sélectionnez le namespace, le pod et le conteneur dont vous souhaitez consulter les logs

### Mise à l'Échelle des Applications

Pour mettre à l'échelle vos applications :

```bash
# Sur le VPS ou sur votre machine locale avec le bon contexte kubectl
kubectl scale deployment/<nom_deployment> --replicas=<nombre_replicas> -n <namespace>
```

### Redémarrage des Applications

Pour redémarrer vos applications :

```bash
# Sur le VPS ou sur votre machine locale avec le bon contexte kubectl
kubectl rollout restart deployment/<nom_deployment> -n <namespace>
```

## Gestion des Bases de Données

### Accès à PostgreSQL

Pour accéder à PostgreSQL :

1. Accédez à PgAdmin (https://pgadmin.lions.dev)
2. Connectez-vous avec vos identifiants
3. Ajoutez un nouveau serveur avec les informations suivantes :
   - Nom : PostgreSQL
   - Hôte : postgres.postgres-development.svc.cluster.local
   - Port : 5432
   - Base de données : postgres
   - Utilisateur : postgres
   - Mot de passe : Voir le secret dans Kubernetes

Pour obtenir le mot de passe :

```bash
# Sur le VPS
kubectl get secret postgres-password -n postgres-development -o jsonpath='{.data.password}' | base64 --decode
```

### Création d'une Nouvelle Base de Données

Pour créer une nouvelle base de données :

1. Accédez à PgAdmin
2. Cliquez avec le bouton droit sur "Databases" dans le serveur PostgreSQL
3. Sélectionnez "Create" > "Database..."
4. Entrez le nom de la base de données et les autres paramètres
5. Cliquez sur "Save"

### Sauvegarde et Restauration des Bases de Données

Pour sauvegarder une base de données :

```bash
# Sur le VPS
./lions-infrastructure/scripts/backup-restore.sh development backup
```

Pour restaurer une base de données :

```bash
# Sur le VPS
./lions-infrastructure/scripts/backup-restore.sh development restore <nom_sauvegarde>
```

## Gestion des Certificats TLS

Les certificats TLS sont gérés automatiquement par cert-manager. Cependant, vous pouvez vérifier l'état des certificats :

```bash
# Sur le VPS ou sur votre machine locale avec le bon contexte kubectl
kubectl get certificates -A
kubectl get certificaterequests -A
```

Pour forcer le renouvellement d'un certificat :

```bash
# Sur le VPS ou sur votre machine locale avec le bon contexte kubectl
kubectl delete certificate <nom_certificat> -n <namespace>
```

## Configuration DNS

Pour configurer les enregistrements DNS pour vos applications :

```bash
# Sur le VPS
./lions-infrastructure/scripts/configure-dns.sh development cloudflare
```

Options disponibles :
- Premier argument : Environnement (development, staging, production)
- Deuxième argument : Fournisseur DNS (cloudflare, route53)

Assurez-vous d'avoir configuré les variables d'environnement appropriées pour votre fournisseur DNS.

## Surveillance et Alertes

### Consultation des Métriques

Pour consulter les métriques de vos applications :

1. Accédez à Grafana (https://grafana.lions.dev)
2. Naviguez vers le tableau de bord correspondant à votre application

### Configuration des Alertes

Pour configurer des alertes :

1. Accédez à Grafana (https://grafana.lions.dev)
2. Naviguez vers "Alerting" > "Alert rules"
3. Cliquez sur "New alert rule"
4. Configurez les conditions d'alerte et les canaux de notification

## Résolution des Problèmes Courants

### Pods en État "Pending"

Si vos pods restent en état "Pending" :

1. Vérifiez les ressources disponibles sur le cluster :
   ```bash
   kubectl describe nodes
   ```

2. Vérifiez les événements du pod :
   ```bash
   kubectl describe pod <nom_pod> -n <namespace>
   ```

### Pods en État "CrashLoopBackOff"

Si vos pods sont en état "CrashLoopBackOff" :

1. Consultez les logs du pod :
   ```bash
   kubectl logs <nom_pod> -n <namespace>
   ```

2. Vérifiez les événements du pod :
   ```bash
   kubectl describe pod <nom_pod> -n <namespace>
   ```

### Problèmes d'Accès aux Services

Si vous ne pouvez pas accéder à vos services :

1. Vérifiez que l'Ingress est correctement configuré :
   ```bash
   kubectl get ingress -n <namespace>
   kubectl describe ingress <nom_ingress> -n <namespace>
   ```

2. Vérifiez que le service est en cours d'exécution :
   ```bash
   kubectl get service <nom_service> -n <namespace>
   ```

3. Vérifiez que les pods sont en cours d'exécution :
   ```bash
   kubectl get pods -n <namespace>
   ```

4. Vérifiez les logs de Traefik :
   ```bash
   kubectl logs -n kube-system -l app=traefik
   ```

## Maintenance

### Mise à Jour de l'Infrastructure

Pour mettre à jour l'infrastructure :

```bash
# Sur le VPS
cd /lions-infrastructure-automated-depl
git pull
./lions-infrastructure/scripts/install.sh --environment development
```

### Nettoyage des Ressources Inutilisées

Pour nettoyer les ressources inutilisées :

```bash
# Sur le VPS
./lions-infrastructure/scripts/maintenance/cleanup.sh
```

## Conclusion

Ce guide couvre les opérations de base pour utiliser l'infrastructure LIONS. Pour des informations plus détaillées, consultez la documentation technique ou contactez l'équipe d'infrastructure.

## Ressources Supplémentaires

- [Architecture de l'Infrastructure](../architecture/infrastructure-overview.md)
- [Runbooks pour les Opérations Courantes](../runbooks/README.md)
- [Documentation Kubernetes](https://kubernetes.io/docs/)
- [Documentation Traefik](https://doc.traefik.io/traefik/)
- [Documentation Helm](https://helm.sh/docs/)