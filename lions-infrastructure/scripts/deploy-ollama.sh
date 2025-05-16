#!/bin/bash
# Titre: Script de déploiement direct Ollama avec kubectl
# Description: Déploie Ollama directement avec kubectl
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-14
# Version: 1.0.0

set -euo pipefail

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variables
ENVIRONMENT="${1:-production}"
VERSION="${2:-latest}"
NAMESPACE="ollama-${ENVIRONMENT}"

# Configuration selon l'environnement
case "$ENVIRONMENT" in
    production)
        DOMAIN="ollama.lions.dev"
        CPU_REQUEST="4"
        MEMORY_REQUEST="8Gi"
        CPU_LIMIT="4"
        MEMORY_LIMIT="10Gi"
        STORAGE_SIZE="100Gi"
        ;;
    staging)
        DOMAIN="ollama.staging.lions.dev"
        CPU_REQUEST="3"
        MEMORY_REQUEST="6Gi"
        CPU_LIMIT="4"
        MEMORY_LIMIT="8Gi"
        STORAGE_SIZE="50Gi"
        ;;
    development)
        DOMAIN="ollama.dev.lions.dev"
        CPU_REQUEST="2"
        MEMORY_REQUEST="4Gi"
        CPU_LIMIT="4"
        MEMORY_LIMIT="6Gi"
        STORAGE_SIZE="30Gi"
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} Environnement inconnu: $ENVIRONMENT"
        exit 1
        ;;
esac

echo -e "${GREEN}[INFO]${NC} Déploiement d'Ollama en ${ENVIRONMENT}..."

# Créer le namespace
echo -e "${GREEN}[INFO]${NC} Création du namespace..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    name: ${NAMESPACE}
    environment: ${ENVIRONMENT}
    managed-by: kubectl
EOF

# Créer le ServiceAccount
echo -e "${GREEN}[INFO]${NC} Création du ServiceAccount..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ollama
  namespace: ${NAMESPACE}
  labels:
    app: ollama
    environment: ${ENVIRONMENT}
automountServiceAccountToken: true
EOF

# Créer le ConfigMap
echo -e "${GREEN}[INFO]${NC} Création du ConfigMap..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ollama-config
  namespace: ${NAMESPACE}
  labels:
    app: ollama
    environment: ${ENVIRONMENT}
data:
  OLLAMA_API_URL: "https://${DOMAIN}"
  OLLAMA_ENV: "${ENVIRONMENT}"
  OLLAMA_LOG_LEVEL: "info"
  OLLAMA_DEFAULT_MODELS: |
    - phi3
    - llama3:7b
    - mistral
    - neural-chat
  OLLAMA_MAX_LOADED_MODELS: "2"
  OLLAMA_NUM_THREADS: "4"
  OLLAMA_GPU_ENABLED: "false"
EOF

# Créer le PVC
echo -e "${GREEN}[INFO]${NC} Création du PersistentVolumeClaim..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ollama-pvc
  namespace: ${NAMESPACE}
  labels:
    app: ollama
    environment: ${ENVIRONMENT}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard
  resources:
    requests:
      storage: ${STORAGE_SIZE}
EOF

# Créer le Service
echo -e "${GREEN}[INFO]${NC} Création du Service..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ollama
  namespace: ${NAMESPACE}
  labels:
    app: ollama
    environment: ${ENVIRONMENT}
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/path: "/metrics"
    prometheus.io/port: "11434"
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
  selector:
    app: ollama
EOF

# Créer le Deployment
echo -e "${GREEN}[INFO]${NC} Création du Deployment..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama
  namespace: ${NAMESPACE}
  labels:
    app: ollama
    version: ${VERSION}
    environment: ${ENVIRONMENT}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ollama
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: ollama
        version: ${VERSION}
        environment: ${ENVIRONMENT}
    spec:
      serviceAccountName: ollama
      securityContext:
        runAsNonRoot: false
        fsGroup: 1000
      containers:
        - name: ollama
          image: ollama/ollama:${VERSION}
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 11434
              protocol: TCP
          env:
            - name: OLLAMA_HOST
              value: "0.0.0.0:11434"
            - name: OLLAMA_ORIGINS
              value: "*"
            - name: KUBERNETES_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          envFrom:
            - configMapRef:
                name: ollama-config
          resources:
            requests:
              cpu: "${CPU_REQUEST}"
              memory: "${MEMORY_REQUEST}"
            limits:
              cpu: "${CPU_LIMIT}"
              memory: "${MEMORY_LIMIT}"
          readinessProbe:
            httpGet:
              path: /api/tags
              port: http
            initialDelaySeconds: 30
            periodSeconds: 10
            timeoutSeconds: 15
          livenessProbe:
            httpGet:
              path: /api/tags
              port: http
            initialDelaySeconds: 60
            periodSeconds: 30
            timeoutSeconds: 15
          volumeMounts:
            - name: data-volume
              mountPath: /root/.ollama
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            readOnlyRootFilesystem: false
      volumes:
        - name: data-volume
          persistentVolumeClaim:
            claimName: ollama-pvc
      terminationGracePeriodSeconds: 60
EOF

# Créer l'Ingress
echo -e "${GREEN}[INFO]${NC} Création de l'Ingress..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ollama
  namespace: ${NAMESPACE}
  labels:
    app: ollama
    environment: ${ENVIRONMENT}
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    traefik.ingress.kubernetes.io/router.entrypoints: "websecure"
    traefik.ingress.kubernetes.io/router.tls: "true"
    traefik.ingress.kubernetes.io/request-timeout: "600"
    traefik.ingress.kubernetes.io/proxy-body-size: "500m"
spec:
  ingressClassName: traefik
  tls:
    - hosts:
        - ${DOMAIN}
      secretName: ollama-tls
  rules:
    - host: ${DOMAIN}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ollama
                port:
                  name: http
EOF

# Attendre que le deployment soit prêt
echo -e "${GREEN}[INFO]${NC} Attente du déploiement..."
kubectl wait --for=condition=available --timeout=300s deployment/ollama -n ${NAMESPACE}

# Vérifier le statut
echo -e "${GREEN}[INFO]${NC} Vérification du déploiement..."
kubectl get pods -n ${NAMESPACE} -l app=ollama
kubectl get ingress -n ${NAMESPACE}

echo -e "${GREEN}[INFO]${NC} ✅ Déploiement terminé!"
echo -e "${GREEN}[INFO]${NC} 🌐 URL: https://${DOMAIN}"

# Pré-charger les modèles
echo -e "${GREEN}[INFO]${NC} Pré-chargement des modèles..."
POD=$(kubectl get pods -n ${NAMESPACE} -l app=ollama -o jsonpath='{.items[0].metadata.name}')

for model in "phi3" "llama3:7b"; do
    echo -e "${GREEN}[INFO]${NC} Chargement du modèle ${model}..."
    kubectl exec -n ${NAMESPACE} ${POD} -- ollama pull ${model} || true
done

# Test final
echo -e "${GREEN}[INFO]${NC} Test de l'API..."
sleep 10
curl -s https://${DOMAIN}/api/tags | jq .
