#!/bin/bash
# Script de vérification des configurations d'autoscaling
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-16
# Version: 1.0.0

set -e

echo "Vérification des configurations d'autoscaling..."

# Vérifier la syntaxe des fichiers YAML
echo "Vérification de la syntaxe YAML..."
for file in ../kubernetes/base/autoscaling/*.yaml; do
  echo "Vérification de $file"
  kubectl apply --dry-run=client -f "$file"
done

# Vérifier l'intégration avec kustomize
echo "Vérification de l'intégration avec kustomize..."
kubectl kustomize ../kubernetes/base/autoscaling --dry-run

# Vérifier que les namespaces existent
echo "Vérification des namespaces..."
NAMESPACES=(
  "quarkus-development"
  "primefaces-development"
  "primereact-development"
  "notification-service-development"
  "ollama-development"
  "gitea-development"
  "keycloak-development"
  "registry-development"
)

for ns in "${NAMESPACES[@]}"; do
  if kubectl get namespace "$ns" &>/dev/null; then
    echo "Namespace $ns existe."
  else
    echo "ATTENTION: Namespace $ns n'existe pas. Créez-le avant d'appliquer les configurations d'autoscaling."
  fi
done

# Vérifier que les déploiements cibles existent
echo "Vérification des déploiements cibles..."
DEPLOYMENTS=(
  "quarkus:quarkus-development"
  "primefaces:primefaces-development"
  "primereact:primereact-development"
  "notification-service:notification-service-development"
  "ollama:ollama-development"
  "gitea:gitea-development"
  "keycloak:keycloak-development"
  "registry:registry-development"
)

for deploy_info in "${DEPLOYMENTS[@]}"; do
  IFS=':' read -r deploy_name namespace <<< "$deploy_info"
  if kubectl get deployment "$deploy_name" -n "$namespace" &>/dev/null; then
    echo "Déploiement $deploy_name dans $namespace existe."
  else
    echo "ATTENTION: Déploiement $deploy_name dans $namespace n'existe pas. Assurez-vous qu'il existe avant d'appliquer les configurations d'autoscaling."
  fi
done

echo "Vérification terminée."
echo "Pour appliquer les configurations d'autoscaling, exécutez:"
echo "kubectl apply -k ../kubernetes/base/autoscaling"