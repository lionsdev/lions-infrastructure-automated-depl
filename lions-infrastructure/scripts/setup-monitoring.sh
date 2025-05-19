#!/bin/bash
# Titre: Script de Configuration du Monitoring Avancé
# Description: Configure Prometheus, Grafana et Alertmanager pour surveiller l'infrastructure LIONS
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-18
# Version: 1.0.0

# Activation du mode strict
set -euo pipefail

# Couleurs pour l'affichage
readonly COLOR_RESET="\033[0m"
readonly COLOR_RED="\033[0;31m"
readonly COLOR_GREEN="\033[0;32m"
readonly COLOR_YELLOW="\033[0;33m"
readonly COLOR_BLUE="\033[0;34m"
readonly COLOR_MAGENTA="\033[0;35m"
readonly COLOR_CYAN="\033[0;36m"
readonly COLOR_WHITE="\033[0;37m"
readonly COLOR_BOLD="\033[1m"

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly MONITORING_DIR="${PROJECT_ROOT}/monitoring"
readonly TEMP_DIR="/tmp/lions-monitoring"
readonly NAMESPACE="monitoring"
readonly HELM_TIMEOUT="600s"

# Fonction de logging
function log() {
    local level="$1"
    local message="$2"
    local timestamp="$(date +"%Y-%m-%d %H:%M:%S")"
    local icon=""
    
    # Sélection de l'icône et de la couleur en fonction du niveau
    local color="${COLOR_RESET}"
    case "${level}" in
        "INFO")     color="${COLOR_BLUE}"; icon="ℹ️ " ;;
        "WARNING")  color="${COLOR_YELLOW}"; icon="⚠️ " ;;
        "ERROR")    color="${COLOR_RED}"; icon="❌ " ;;
        "SUCCESS")  color="${COLOR_GREEN}"; icon="✅ " ;;
        "STEP")     color="${COLOR_CYAN}${COLOR_BOLD}"; icon="🔄 " ;;
    esac
    
    # Affichage du message avec formatage
    echo -e "${color}${icon}[${timestamp}] [${level}] ${message}${COLOR_RESET}"
}

# Fonction pour vérifier les prérequis
function check_prerequisites() {
    log "STEP" "Vérification des prérequis"
    
    # Vérification de kubectl
    if ! command -v kubectl &> /dev/null; then
        log "ERROR" "kubectl n'est pas installé ou n'est pas dans le PATH"
        exit 1
    fi
    
    # Vérification de helm
    if ! command -v helm &> /dev/null; then
        log "ERROR" "helm n'est pas installé ou n'est pas dans le PATH"
        exit 1
    fi
    
    # Vérification de la connexion au cluster Kubernetes
    if ! kubectl cluster-info &> /dev/null; then
        log "ERROR" "Impossible de se connecter au cluster Kubernetes"
        exit 1
    fi
    
    log "SUCCESS" "Tous les prérequis sont satisfaits"
}

# Fonction pour créer le namespace de monitoring
function create_namespace() {
    log "STEP" "Création du namespace ${NAMESPACE}"
    
    if kubectl get namespace "${NAMESPACE}" &> /dev/null; then
        log "INFO" "Le namespace ${NAMESPACE} existe déjà"
    else
        kubectl create namespace "${NAMESPACE}"
        log "SUCCESS" "Namespace ${NAMESPACE} créé avec succès"
    fi
}

# Fonction pour installer Prometheus
function install_prometheus() {
    log "STEP" "Installation de Prometheus"
    
    # Ajout du dépôt Helm de Prometheus
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Création du répertoire temporaire pour les valeurs personnalisées
    mkdir -p "${TEMP_DIR}"
    
    # Création du fichier de valeurs personnalisées pour Prometheus
    cat > "${TEMP_DIR}/prometheus-values.yaml" << EOF
server:
  retention: 15d
  resources:
    limits:
      cpu: 1000m
      memory: 2Gi
    requests:
      cpu: 500m
      memory: 1Gi
  persistentVolume:
    size: 50Gi
alertmanager:
  enabled: true
  persistentVolume:
    size: 10Gi
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 256Mi
  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'job']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 12h
      receiver: 'email-notifications'
      routes:
      - match:
          severity: critical
        receiver: 'email-notifications'
    receivers:
    - name: 'email-notifications'
      email_configs:
      - to: 'alerts@lions.dev'
        from: 'prometheus@lions.dev'
        smarthost: 'smtp.lions.dev:587'
        auth_username: 'prometheus@lions.dev'
        auth_password: '${SMTP_PASSWORD:-changeme}'
        send_resolved: true
nodeExporter:
  enabled: true
pushgateway:
  enabled: true
kubeStateMetrics:
  enabled: true
EOF
    
    # Installation de Prometheus avec Helm
    helm upgrade --install prometheus prometheus-community/prometheus \
        --namespace "${NAMESPACE}" \
        --values "${TEMP_DIR}/prometheus-values.yaml" \
        --timeout "${HELM_TIMEOUT}" \
        --wait
    
    log "SUCCESS" "Prometheus installé avec succès"
}

# Fonction pour installer Grafana
function install_grafana() {
    log "STEP" "Installation de Grafana"
    
    # Ajout du dépôt Helm de Grafana
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    
    # Création du fichier de valeurs personnalisées pour Grafana
    cat > "${TEMP_DIR}/grafana-values.yaml" << EOF
persistence:
  enabled: true
  size: 10Gi
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 256Mi
adminPassword: "${GRAFANA_PASSWORD:-admin}"
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server.${NAMESPACE}.svc.cluster.local
      access: proxy
      isDefault: true
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
    - name: 'default'
      orgId: 1
      folder: ''
      type: file
      disableDeletion: false
      editable: true
      options:
        path: /var/lib/grafana/dashboards/default
dashboards:
  default:
    kubernetes-cluster:
      gnetId: 6417
      revision: 1
      datasource: Prometheus
    node-exporter:
      gnetId: 1860
      revision: 23
      datasource: Prometheus
    prometheus-stats:
      gnetId: 2
      revision: 2
      datasource: Prometheus
    quarkus-micrometer:
      gnetId: 14370
      revision: 1
      datasource: Prometheus
    spring-boot:
      gnetId: 6756
      revision: 3
      datasource: Prometheus
    jvm:
      gnetId: 4701
      revision: 4
      datasource: Prometheus
ingress:
  enabled: true
  annotations:
    kubernetes.io/ingress.class: traefik
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - grafana.lions.dev
  tls:
    - secretName: grafana-tls
      hosts:
        - grafana.lions.dev
EOF
    
    # Installation de Grafana avec Helm
    helm upgrade --install grafana grafana/grafana \
        --namespace "${NAMESPACE}" \
        --values "${TEMP_DIR}/grafana-values.yaml" \
        --timeout "${HELM_TIMEOUT}" \
        --wait
    
    log "SUCCESS" "Grafana installé avec succès"
}

# Fonction pour configurer les règles d'alerte Prometheus
function configure_alert_rules() {
    log "STEP" "Configuration des règles d'alerte Prometheus"
    
    # Création du fichier ConfigMap pour les règles d'alerte
    cat > "${TEMP_DIR}/prometheus-alert-rules.yaml" << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-alert-rules
  namespace: ${NAMESPACE}
data:
  infrastructure-alerts.yaml: |
    groups:
    - name: infrastructure
      rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ \$labels.instance }}"
          description: "CPU usage is above 80% for 5 minutes on {{ \$labels.instance }}"
      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ \$labels.instance }}"
          description: "Memory usage is above 85% for 5 minutes on {{ \$labels.instance }}"
      - alert: HighDiskUsage
        expr: 100 - ((node_filesystem_avail_bytes{mountpoint="/"} * 100) / node_filesystem_size_bytes{mountpoint="/"}) > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High disk usage on {{ \$labels.instance }}"
          description: "Disk usage is above 85% for 5 minutes on {{ \$labels.instance }}"
      - alert: KubernetesPodCrashLooping
        expr: kube_pod_container_status_restarts_total > 5
        for: 15m
        labels:
          severity: critical
        annotations:
          summary: "Pod {{ \$labels.pod }} is crash looping"
          description: "Pod {{ \$labels.pod }} in namespace {{ \$labels.namespace }} is crash looping ({{ \$value }} restarts in 15 minutes)"
  application-alerts.yaml: |
    groups:
    - name: applications
      rules:
      - alert: HighResponseTime
        expr: http_server_requests_seconds_sum / http_server_requests_seconds_count > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High response time for {{ \$labels.instance }}"
          description: "Average response time is above 1 second for 5 minutes on {{ \$labels.instance }}"
      - alert: HighErrorRate
        expr: sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m])) / sum(rate(http_server_requests_seconds_count[5m])) * 100 > 5
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate for {{ \$labels.instance }}"
          description: "Error rate is above 5% for 5 minutes on {{ \$labels.instance }}"
      - alert: JVMHighMemoryUsage
        expr: sum(jvm_memory_used_bytes) / sum(jvm_memory_max_bytes) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High JVM memory usage for {{ \$labels.instance }}"
          description: "JVM memory usage is above 85% for 5 minutes on {{ \$labels.instance }}"
EOF
    
    # Application du ConfigMap
    kubectl apply -f "${TEMP_DIR}/prometheus-alert-rules.yaml"
    
    log "SUCCESS" "Règles d'alerte configurées avec succès"
}

# Fonction pour configurer les ServiceMonitors pour les applications
function configure_service_monitors() {
    log "STEP" "Configuration des ServiceMonitors pour les applications"
    
    # Création du fichier ServiceMonitor pour les applications Quarkus
    cat > "${TEMP_DIR}/quarkus-service-monitor.yaml" << EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: quarkus-apps
  namespace: ${NAMESPACE}
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/part-of: quarkus
  namespaceSelector:
    any: true
  endpoints:
  - port: metrics
    interval: 15s
    path: /q/metrics
EOF
    
    # Création du fichier ServiceMonitor pour les applications Spring Boot
    cat > "${TEMP_DIR}/spring-service-monitor.yaml" << EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: spring-apps
  namespace: ${NAMESPACE}
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/part-of: spring
  namespaceSelector:
    any: true
  endpoints:
  - port: actuator
    interval: 15s
    path: /actuator/prometheus
EOF
    
    # Application des ServiceMonitors
    kubectl apply -f "${TEMP_DIR}/quarkus-service-monitor.yaml"
    kubectl apply -f "${TEMP_DIR}/spring-service-monitor.yaml"
    
    log "SUCCESS" "ServiceMonitors configurés avec succès"
}

# Fonction pour afficher les informations d'accès
function display_access_info() {
    log "STEP" "Récupération des informations d'accès"
    
    # Récupération du mot de passe admin de Grafana
    local grafana_password
    if [[ -n "${GRAFANA_PASSWORD:-}" ]]; then
        grafana_password="${GRAFANA_PASSWORD}"
    else
        grafana_password=$(kubectl get secret --namespace "${NAMESPACE}" grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
    fi
    
    # Affichage des informations d'accès
    echo -e "\n${COLOR_GREEN}${COLOR_BOLD}=== Informations d'accès au monitoring ===${COLOR_RESET}\n"
    echo -e "${COLOR_CYAN}Prometheus:${COLOR_RESET}"
    echo -e "  URL: http://prometheus-server.${NAMESPACE}.svc.cluster.local"
    echo -e "  Port-forward: kubectl port-forward -n ${NAMESPACE} svc/prometheus-server 9090:80"
    echo -e "  Accès externe: http://prometheus.lions.dev (si configuré)\n"
    
    echo -e "${COLOR_CYAN}Grafana:${COLOR_RESET}"
    echo -e "  URL: http://grafana.${NAMESPACE}.svc.cluster.local"
    echo -e "  Port-forward: kubectl port-forward -n ${NAMESPACE} svc/grafana 3000:80"
    echo -e "  Accès externe: https://grafana.lions.dev"
    echo -e "  Utilisateur: admin"
    echo -e "  Mot de passe: ${grafana_password}\n"
    
    echo -e "${COLOR_CYAN}Alertmanager:${COLOR_RESET}"
    echo -e "  URL: http://prometheus-alertmanager.${NAMESPACE}.svc.cluster.local"
    echo -e "  Port-forward: kubectl port-forward -n ${NAMESPACE} svc/prometheus-alertmanager 9093:80"
    echo -e "  Accès externe: http://alertmanager.lions.dev (si configuré)\n"
    
    log "SUCCESS" "Installation et configuration du monitoring terminées avec succès"
}

# Fonction principale
function main() {
    log "INFO" "Démarrage de l'installation du monitoring avancé"
    
    # Vérification des prérequis
    check_prerequisites
    
    # Création du namespace
    create_namespace
    
    # Installation de Prometheus
    install_prometheus
    
    # Installation de Grafana
    install_grafana
    
    # Configuration des règles d'alerte
    configure_alert_rules
    
    # Configuration des ServiceMonitors
    configure_service_monitors
    
    # Affichage des informations d'accès
    display_access_info
}

# Exécution de la fonction principale
main