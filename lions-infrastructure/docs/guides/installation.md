# Guide d'Installation de l'Infrastructure LIONS

Ce guide détaille les étapes nécessaires pour installer et configurer l'infrastructure LIONS sur un environnement Kubernetes.

## Prérequis

### Matériel recommandé

- **Environnement de développement** : Au moins 1 nœud avec 4 CPU, 8 Go de RAM et 50 Go de stockage
- **Environnement de staging** : Au moins 3 nœuds avec 4 CPU, 16 Go de RAM et 100 Go de stockage par nœud
- **Environnement de production** : Au moins 5 nœuds avec 8 CPU, 32 Go de RAM et 200 Go de stockage par nœud

### Logiciels requis

- Kubernetes v1.24+ (K3s, K8s, EKS, AKS ou GKE)
- Helm v3.8+
- kubectl v1.24+
- Ansible v2.12+
- Git v2.30+
- Docker v20.10+ ou Podman v3.4+

## Étapes d'installation

### 1. Cloner le dépôt

```bash
git clone https://github.com/lions-org/lions-infrastructure-automated-depl.git
cd lions-infrastructure-automated-depl
```

### 2. Configuration de l'environnement

Créez un fichier de configuration pour votre environnement en copiant et modifiant le modèle fourni :

```bash
cp config/environment.yaml.example config/environment.yaml
```

Éditez le fichier `config/environment.yaml` pour configurer les paramètres spécifiques à votre environnement :

```yaml
# Configuration générale
general:
  domain_name: "lions.dev"  # Domaine principal
  organization: "LIONS"     # Nom de l'organisation
  contact_email: "admin@lions.dev"  # Email de contact

# Configuration Kubernetes
kubernetes:
  context: "lions-cluster"  # Contexte kubectl
  config_path: "~/.kube/config"  # Chemin vers le fichier kubeconfig

# Configuration des environnements
environments:
  development:
    enabled: true
    domain_suffix: "dev.lions.dev"
    resources:
      cpu_limit: "4"
      memory_limit: "8Gi"
  staging:
    enabled: true
    domain_suffix: "staging.lions.dev"
    resources:
      cpu_limit: "8"
      memory_limit: "16Gi"
  production:
    enabled: true
    domain_suffix: "lions.dev"
    resources:
      cpu_limit: "16"
      memory_limit: "32Gi"

# Configuration du stockage
storage:
  class_name: "standard"  # Classe de stockage par défaut
  backup:
    enabled: true
    schedule: "0 2 * * *"  # Tous les jours à 2h du matin
    retention: "7d"        # Conservation pendant 7 jours

# Configuration de la surveillance
monitoring:
  prometheus:
    retention: "15d"
  grafana:
    admin_password: "changeme"  # À modifier !
  alerting:
    email:
      enabled: true
      recipients: "alerts@lions.dev"
    slack:
      enabled: false
      webhook_url: ""
      channel: "#alerts"

# Configuration de la sécurité
security:
  network_policies: true
  pod_security_policies: true
  rbac:
    strict: true
```

### 3. Vérification des prérequis

Exécutez le script de vérification des prérequis pour vous assurer que votre environnement est correctement configuré :

```bash
./scripts/check-prerequisites.sh
```

### 4. Installation de l'infrastructure de base

Utilisez le script d'installation pour déployer l'infrastructure de base :

```bash
./scripts/install.sh --environment development
```

Pour un environnement de production :

```bash
./scripts/install.sh --environment production
```

Ce script va :
- Créer les namespaces nécessaires
- Déployer les composants de base (ingress, cert-manager, etc.)
- Configurer le stockage persistant
- Déployer le système de surveillance (Prometheus, Grafana, etc.)
- Configurer les politiques de sécurité

### 5. Vérification de l'installation

Vérifiez que tous les composants sont correctement déployés :

```bash
kubectl get pods --all-namespaces
```

Vérifiez l'accès à l'interface Grafana :

```bash
echo "URL Grafana: https://grafana.$(kubectl get cm -n kube-system lions-config -o jsonpath='{.data.domain_suffix}')"
echo "Identifiant: admin"
echo "Mot de passe: $(kubectl get secret -n monitoring grafana-admin -o jsonpath='{.data.password}' | base64 -d)"
```

### 6. Configuration des utilisateurs et des droits d'accès

Créez les utilisateurs et configurez les droits d'accès :

```bash
./scripts/configure-users.sh --config users.yaml
```

Exemple de fichier `users.yaml` :

```yaml
users:
  - name: "dev-team"
    role: "developer"
    environments: ["development"]
  - name: "ops-team"
    role: "operator"
    environments: ["development", "staging", "production"]
```

### 7. Installation des applications de base (optionnel)

Déployez les applications de base (registre Docker, CI/CD, etc.) :

```bash
./scripts/install-apps.sh --apps "registry,cicd,vault"
```

## Configuration avancée

### Configuration de la haute disponibilité

Pour configurer la haute disponibilité en production :

```bash
./scripts/configure-ha.sh --environment production
```

### Configuration des sauvegardes

Pour configurer les sauvegardes automatiques :

```bash
./scripts/configure-backups.sh --schedule "0 2 * * *" --retention "7d"
```

### Configuration du monitoring avancé

Pour configurer des tableaux de bord et des alertes personnalisés :

```bash
./scripts/configure-monitoring.sh --dashboards custom-dashboards/ --alerts custom-alerts/
```

## Dépannage

### Problèmes courants

#### Les pods restent en état "Pending"

Vérifiez les ressources disponibles sur les nœuds :

```bash
kubectl describe nodes
```

#### Erreurs de certificat TLS

Vérifiez l'état de cert-manager :

```bash
kubectl get pods -n cert-manager
kubectl describe certificate -n <namespace>
```

#### Problèmes de réseau

Vérifiez les politiques réseau et l'état du CNI :

```bash
kubectl get networkpolicies --all-namespaces
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

### Journaux de débogage

Pour obtenir les journaux détaillés de l'installation :

```bash
./scripts/install.sh --environment development --debug
```

Les journaux sont également disponibles dans le répertoire `logs/` :

```bash
cat logs/install-$(date +%Y%m%d).log
```

## Mise à jour de l'infrastructure

Pour mettre à jour l'infrastructure vers une nouvelle version :

```bash
git pull
./scripts/upgrade.sh --environment production
```

## Désinstallation

Pour désinstaller l'infrastructure :

```bash
./scripts/uninstall.sh --environment development
```

**Attention** : Cette opération supprimera toutes les applications et données associées à l'environnement spécifié.

## Ressources supplémentaires

- [Guide d'administration](administration.md)
- [Guide de déploiement](deployment.md)
- [Guide de surveillance](monitoring.md)
- [Architecture de référence](../architecture/overview.md)