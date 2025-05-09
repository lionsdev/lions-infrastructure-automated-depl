# Guide de Surveillance de l'Infrastructure LIONS

Ce guide explique comment surveiller les applications et l'infrastructure déployées sur la plateforme LIONS.

## Vue d'ensemble

L'infrastructure LIONS intègre une pile de surveillance complète basée sur les outils suivants :

- **Prometheus** : Collecte et stockage des métriques
- **Grafana** : Visualisation des métriques et tableaux de bord
- **Alertmanager** : Gestion des alertes et notifications
- **Loki** : Agrégation et indexation des journaux
- **Jaeger** : Traçage distribué pour les applications

Cette pile de surveillance permet de :
- Détecter proactivement les problèmes avant qu'ils n'affectent les utilisateurs
- Analyser les performances des applications
- Comprendre le comportement du système sous charge
- Recevoir des alertes en cas d'anomalies
- Respecter les SLOs (Service Level Objectives)

## Accès aux interfaces de surveillance

### Grafana

Grafana est l'interface principale pour visualiser les métriques et les tableaux de bord.

**URL** : `https://grafana.<domain_suffix>`

**Identifiants par défaut** :
- Utilisateur : `admin`
- Mot de passe : Récupérable avec la commande suivante :
  ```bash
  kubectl get secret -n monitoring grafana-admin -o jsonpath='{.data.password}' | base64 -d
  ```

### Prometheus

L'interface Prometheus permet d'exécuter des requêtes PromQL et de visualiser les métriques brutes.

**URL** : `https://prometheus.<domain_suffix>`

### Alertmanager

L'interface Alertmanager permet de visualiser et de gérer les alertes actives.

**URL** : `https://alertmanager.<domain_suffix>`

## Tableaux de bord disponibles

L'infrastructure LIONS fournit plusieurs tableaux de bord préconfigurés dans Grafana :

### Tableaux de bord d'infrastructure

- **Vue d'ensemble du cluster** : État général du cluster Kubernetes
- **Nœuds Kubernetes** : Utilisation des ressources par nœud
- **Namespaces** : Utilisation des ressources par namespace
- **Stockage persistant** : État et utilisation du stockage

### Tableaux de bord d'application

- **Vue d'ensemble des applications** : État général de toutes les applications
- **Détails d'application** : Métriques détaillées pour une application spécifique
- **Performances HTTP** : Taux de requêtes, latence et codes de statut
- **JVM (pour Quarkus/PrimeFaces)** : Métriques spécifiques à la JVM
- **Node.js (pour PrimeReact)** : Métriques spécifiques à Node.js

### Tableaux de bord SLO

- **SLOs globaux** : Suivi des objectifs de niveau de service
- **Budget d'erreur** : Suivi de la consommation du budget d'erreur

## Configuration de la surveillance pour les applications

### Exposition des métriques Prometheus

Pour que vos applications soient correctement surveillées, elles doivent exposer des métriques au format Prometheus.

#### Quarkus

Pour les applications Quarkus, ajoutez les dépendances suivantes dans votre `pom.xml` :

```xml
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-micrometer-registry-prometheus</artifactId>
</dependency>
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-smallrye-health</artifactId>
</dependency>
```

Les métriques seront automatiquement exposées sur `/q/metrics`.

#### PrimeFaces

Pour les applications PrimeFaces, utilisez la bibliothèque Micrometer avec Spring Boot :

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

Configurez `application.properties` :

```properties
management.endpoints.web.exposure.include=health,info,prometheus
management.endpoint.health.show-details=always
```

#### PrimeReact

Pour les applications PrimeReact, utilisez le package `prom-client` :

```bash
npm install prom-client
```

Exemple d'implémentation :

```javascript
const express = require('express');
const client = require('prom-client');
const app = express();

// Créer un registre
const register = new client.Registry();

// Ajouter des métriques par défaut
client.collectDefaultMetrics({ register });

// Définir des métriques personnalisées
const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status'],
  registers: [register]
});

// Exposer les métriques
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Middleware pour compter les requêtes
app.use((req, res, next) => {
  const end = res.end;
  res.end = function() {
    httpRequestsTotal.inc({
      method: req.method,
      route: req.route ? req.route.path : req.path,
      status: res.statusCode
    });
    end.apply(res, arguments);
  };
  next();
});
```

### Configuration dans le fichier de déploiement

Dans votre fichier `lions-deploy.yaml`, configurez la section monitoring :

```yaml
monitoring:
  prometheus:
    enabled: true
    path: "/metrics"  # ou "/q/metrics" pour Quarkus
    port: 8080
  
  healthcheck:
    liveness:
      path: "/health/live"  # ou "/q/health/live" pour Quarkus
      port: 8080
      initialDelaySeconds: 30
      periodSeconds: 10
    readiness:
      path: "/health/ready"  # ou "/q/health/ready" pour Quarkus
      port: 8080
      initialDelaySeconds: 10
      periodSeconds: 5
```

## Alertes

### Alertes par défaut

L'infrastructure LIONS configure automatiquement plusieurs alertes par défaut :

- **InstanceDown** : Une instance d'application est indisponible
- **HighCPUUsage** : Utilisation CPU élevée
- **HighMemoryUsage** : Utilisation mémoire élevée
- **HighErrorRate** : Taux d'erreur HTTP élevé
- **HighLatency** : Latence élevée des requêtes
- **PodCrashLooping** : Pod en état CrashLoopBackOff
- **PodNotReady** : Pod non prêt pendant une période prolongée

### Configuration des notifications

Les alertes peuvent être envoyées à différents canaux de notification :

#### Email

Configurez les destinataires email dans le fichier `config/environment.yaml` :

```yaml
monitoring:
  alerting:
    email:
      enabled: true
      recipients: "team@example.com,oncall@example.com"
```

#### Slack

Configurez l'intégration Slack :

```yaml
monitoring:
  alerting:
    slack:
      enabled: true
      webhook_url: "https://hooks.slack.com/services/XXX/YYY/ZZZ"
      channel: "#alerts"
```

#### PagerDuty

Configurez l'intégration PagerDuty :

```yaml
monitoring:
  alerting:
    pagerduty:
      enabled: true
      service_key: "your-pagerduty-service-key"
      severity_map:
        critical: critical
        warning: warning
```

### Création d'alertes personnalisées

Pour créer des alertes personnalisées, créez un fichier `custom-alerts.yaml` :

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: custom-alerts
  namespace: monitoring
spec:
  groups:
    - name: custom.rules
      rules:
        - alert: CustomMetricThreshold
          expr: custom_metric > 100
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Custom metric threshold exceeded"
            description: "Custom metric value is {{ $value }}, which exceeds the threshold of 100."
```

Appliquez-le avec :

```bash
kubectl apply -f custom-alerts.yaml
```

## Journalisation (Logs)

### Accès aux logs

#### Via Kubectl

Accédez aux logs d'un pod spécifique :

```bash
kubectl logs -n <namespace> <pod-name>

# Suivre les logs en temps réel
kubectl logs -n <namespace> <pod-name> -f

# Afficher les logs d'un conteneur spécifique dans un pod
kubectl logs -n <namespace> <pod-name> -c <container-name>
```

#### Via Grafana/Loki

1. Accédez à Grafana
2. Sélectionnez l'explorateur Loki
3. Utilisez le sélecteur de libellés pour filtrer les logs :
   - `namespace=<namespace>`
   - `pod=<pod-name>`
   - `container=<container-name>`

### Configuration de la journalisation

Pour optimiser la journalisation de vos applications :

#### Quarkus

Configurez `application.properties` :

```properties
quarkus.log.console.format=%d{yyyy-MM-dd HH:mm:ss,SSS} %-5p [%c{2.}] (%t) %s%e%n
quarkus.log.level=INFO
quarkus.log.category."io.quarkus".level=WARN
quarkus.log.category."com.yourcompany".level=DEBUG
```

#### PrimeFaces/Spring Boot

Configurez `application.properties` :

```properties
logging.pattern.console=%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level %logger{36} - %msg%n
logging.level.root=INFO
logging.level.org.springframework=WARN
logging.level.com.yourcompany=DEBUG
```

#### PrimeReact/Node.js

Utilisez une bibliothèque comme Winston :

```javascript
const winston = require('winston');

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  defaultMeta: { service: 'your-service-name' },
  transports: [
    new winston.transports.Console()
  ]
});
```

## Traçage distribué

Le traçage distribué permet de suivre le parcours d'une requête à travers plusieurs services.

### Configuration du traçage

#### Quarkus

Ajoutez la dépendance :

```xml
<dependency>
    <groupId>io.quarkus</groupId>
    <artifactId>quarkus-opentelemetry</artifactId>
</dependency>
```

Configurez `application.properties` :

```properties
quarkus.opentelemetry.enabled=true
quarkus.opentelemetry.tracer.exporter.otlp.endpoint=http://jaeger-collector.monitoring:4317
```

#### PrimeFaces/Spring Boot

Ajoutez les dépendances :

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
</dependency>
```

#### PrimeReact/Node.js

Utilisez la bibliothèque OpenTelemetry :

```bash
npm install @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node @opentelemetry/exporter-trace-otlp-http
```

Exemple de configuration :

```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: 'http://jaeger-collector.monitoring:4318/v1/traces',
  }),
  instrumentations: [getNodeAutoInstrumentations()]
});

sdk.start();
```

### Accès à l'interface Jaeger

Accédez à l'interface Jaeger pour visualiser les traces :

**URL** : `https://jaeger.<domain_suffix>`

## Bonnes pratiques

### Métriques

- Exposez des métriques significatives pour votre application
- Utilisez des libellés (labels) pour segmenter les métriques
- Suivez les quatre signaux d'or : latence, trafic, erreurs, saturation
- Évitez la cardinalité excessive des métriques

### Journalisation

- Utilisez des niveaux de log appropriés (ERROR, WARN, INFO, DEBUG)
- Structurez vos logs en JSON pour faciliter l'analyse
- Incluez des identifiants de corrélation dans les logs
- Évitez de logger des informations sensibles

### Alertes

- Créez des alertes actionnables (qui nécessitent une action)
- Évitez les alertes trop bruyantes ou les faux positifs
- Définissez des seuils appropriés basés sur l'historique
- Documentez les procédures de réponse aux alertes

## Dépannage

### Prometheus ne collecte pas les métriques

1. Vérifiez que le pod expose correctement les métriques :
   ```bash
   kubectl port-forward -n <namespace> <pod-name> 8080:8080
   curl localhost:8080/metrics
   ```

2. Vérifiez les annotations du pod :
   ```bash
   kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 5 annotations
   ```

3. Vérifiez l'état du ServiceMonitor :
   ```bash
   kubectl get servicemonitor -n <namespace>
   kubectl describe servicemonitor <name> -n <namespace>
   ```

### Grafana n'affiche pas de données

1. Vérifiez que la source de données Prometheus est configurée correctement
2. Vérifiez que les requêtes PromQL sont valides
3. Ajustez la plage de temps pour inclure des données

### Alertes non déclenchées

1. Vérifiez l'état des règles d'alerte dans Prometheus :
   ```bash
   kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
   ```
   Puis accédez à `http://localhost:9090/rules`

2. Vérifiez la configuration d'Alertmanager :
   ```bash
   kubectl get secret -n monitoring alertmanager-main -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d
   ```

## Ressources supplémentaires

- [Documentation Prometheus](https://prometheus.io/docs/introduction/overview/)
- [Documentation Grafana](https://grafana.com/docs/grafana/latest/)
- [Documentation Loki](https://grafana.com/docs/loki/latest/)
- [Documentation Jaeger](https://www.jaegertracing.io/docs/latest/)
- [Guide d'installation](installation.md)
- [Guide de déploiement](deployment.md)
- [Architecture de référence](../architecture/overview.md)