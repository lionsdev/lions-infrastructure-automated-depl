#!/bin/bash
# Titre: Test de synchronisation des URLs de registre
# Description: Vérifie que les URLs de registre sont correctement synchronisées entre les projets

set -e

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fonction de journalisation
log() {
  local level=$1
  local message=$2
  local color=$NC
  
  case $level in
    "INFO") color=$NC ;;
    "SUCCESS") color=$GREEN ;;
    "WARNING") color=$YELLOW ;;
    "ERROR") color=$RED ;;
  esac
  
  echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}${NC}"
}

# Fonction pour vérifier les templates de déploiement
check_deployment_templates() {
  log "INFO" "Vérification des templates de déploiement..."
  
  local templates=(
    "../ansible/roles/notification-service/templates/deployment.yml.j2"
    "../ansible/roles/primefaces/templates/deployment.yml.j2"
    "../ansible/roles/primereact/templates/deployment.yml.j2"
    "../ansible/roles/quarkus/templates/deployment.yml.j2"
  )
  
  local errors=0
  
  for template in "${templates[@]}"; do
    if [ ! -f "$template" ]; then
      log "WARNING" "Template non trouvé: $template"
      continue
    fi
    
    if grep -q "registry\.{{ app_environment }}\.lions\.dev" "$template"; then
      log "SUCCESS" "Template correct: $template"
    else
      log "ERROR" "Template incorrect: $template - URL de registre non synchronisée"
      errors=$((errors + 1))
    fi
  done
  
  # Vérification du playbook deploy-application.yml
  local playbook="../ansible/playbooks/deploy-application.yml"
  if [ -f "$playbook" ]; then
    if grep -q "registry\.{{ environment }}\.lions\.dev" "$playbook"; then
      log "SUCCESS" "Playbook correct: $playbook"
    else
      log "ERROR" "Playbook incorrect: $playbook - URL de registre non synchronisée"
      errors=$((errors + 1))
    fi
  else
    log "WARNING" "Playbook non trouvé: $playbook"
  fi
  
  return $errors
}

# Fonction pour vérifier la documentation
check_documentation() {
  log "INFO" "Vérification de la documentation..."
  
  local docs=(
    "../applications/templates/angular/README.md"
    "../applications/templates/angular/deployment.yaml"
  )
  
  local errors=0
  
  for doc in "${docs[@]}"; do
    if [ ! -f "$doc" ]; then
      log "WARNING" "Document non trouvé: $doc"
      continue
    fi
    
    if grep -q "registry\.ENVIRONMENT\.lions\.dev" "$doc"; then
      log "SUCCESS" "Documentation correcte: $doc"
    else
      log "ERROR" "Documentation incorrecte: $doc - URL de registre non synchronisée"
      errors=$((errors + 1))
    fi
  done
  
  return $errors
}

# Fonction pour tester l'accès au registre
test_registry_access() {
  log "INFO" "Test d'accès au registre..."
  
  # Vérifier si kubectl est disponible
  if ! command -v kubectl &> /dev/null; then
    log "WARNING" "kubectl n'est pas disponible, impossible de tester l'accès au registre"
    return 0
  fi
  
  # Vérifier si le registre est déployé
  if ! kubectl get deployment -n registry registry &> /dev/null; then
    log "WARNING" "Le registre n'est pas déployé, impossible de tester l'accès"
    return 0
  fi
  
  # Vérifier l'accès au registre
  local environment=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.namespace}' | sed 's/-.*$//')
  local registry_url="registry.${environment}.lions.dev"
  
  if curl -s -f -o /dev/null "https://${registry_url}/v2/" &> /dev/null; then
    log "SUCCESS" "Accès au registre réussi: ${registry_url}"
    return 0
  else
    log "ERROR" "Impossible d'accéder au registre: ${registry_url}"
    return 1
  fi
}

# Fonction principale
main() {
  log "INFO" "Début des tests de synchronisation des URLs de registre..."
  
  local errors=0
  
  # Vérifier les templates de déploiement
  check_deployment_templates
  errors=$((errors + $?))
  
  # Vérifier la documentation
  check_documentation
  errors=$((errors + $?))
  
  # Tester l'accès au registre
  test_registry_access
  errors=$((errors + $?))
  
  if [ $errors -eq 0 ]; then
    log "SUCCESS" "Tous les tests ont réussi! Les URLs de registre sont correctement synchronisées."
  else
    log "ERROR" "Des erreurs ont été détectées. Veuillez corriger les problèmes mentionnés ci-dessus."
  fi
  
  return $errors
}

# Exécution du script
main