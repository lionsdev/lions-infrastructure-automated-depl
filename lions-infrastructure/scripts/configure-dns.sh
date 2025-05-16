#!/bin/bash
# Titre: Script de configuration DNS pour LIONS Infrastructure
# Description: Configure les enregistrements DNS pour tous les services LIONS
# Auteur: Équipe LIONS Infrastructure
# Date: 2025-05-16
# Version: 1.0.0

set -euo pipefail

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs/dns"
ENVIRONMENT="${1:-development}"
DNS_PROVIDER="${2:-cloudflare}"
VPS_IP="176.57.150.2"  # IP du VPS

# Création des répertoires de logs
mkdir -p "${LOG_DIR}"

# Affichage du logo
echo -e "${BLUE}"
echo -e "╔═══════════════════════════════════════════════════════════════════╗"
echo -e "║                                                                   ║"
echo -e "║      ██╗     ██╗ ██████╗ ███╗   ██╗███████╗    ██╗███╗   ██╗      ║"
echo -e "║      ██║     ██║██╔═══██╗████╗  ██║██╔════╝    ██║████╗  ██║      ║"
echo -e "║      ██║     ██║██║   ██║██╔██╗ ██║███████╗    ██║██╔██╗ ██║      ║"
echo -e "║      ██║     ██║██║   ██║██║╚██╗██║╚════██║    ██║██║╚██╗██║      ║"
echo -e "║      ███████╗██║╚██████╔╝██║ ╚████║███████║    ██║██║ ╚████║      ║"
echo -e "║      ╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝    ╚═╝╚═╝  ╚═══╝      ║"
echo -e "║                                                                   ║"
echo -e "║     ██████╗ ███╗   ██╗███████╗     ██████╗ ██████╗ ███╗   ██╗███████╗ ║"
echo -e "║     ██╔══██╗████╗  ██║██╔════╝    ██╔════╝██╔═══██╗████╗  ██║██╔════╝ ║"
echo -e "║     ██║  ██║██╔██╗ ██║███████╗    ██║     ██║   ██║██╔██╗ ██║█████╗   ║"
echo -e "║     ██║  ██║██║╚██╗██║╚════██║    ██║     ██║   ██║██║╚██╗██║██╔══╝   ║"
echo -e "║     ██████╔╝██║ ╚████║███████║    ╚██████╗╚██████╔╝██║ ╚████║██║      ║"
echo -e "║     ╚═════╝ ╚═╝  ╚═══╝╚══════╝     ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝      ║"
echo -e "║                                                                   ║"
echo -e "╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo -e "${YELLOW}     Configuration DNS LIONS - v1.0.0${NC}"
echo -e "${BLUE}  ════════════════════════════════════════════════════════${NC}\n"

# Vérification des prérequis
echo -e "${GREEN}[INFO]${NC} Vérification des prérequis..."

# Vérification des variables d'environnement pour le fournisseur DNS
case "${DNS_PROVIDER}" in
  cloudflare)
    if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
      echo -e "${RED}[ERROR]${NC} Variable d'environnement CLOUDFLARE_API_TOKEN non définie"
      echo -e "${YELLOW}[TIP]${NC} Exportez votre token API Cloudflare avec: export CLOUDFLARE_API_TOKEN=votre_token"
      exit 1
    fi
    if [[ -z "${CLOUDFLARE_ZONE_ID:-}" ]]; then
      echo -e "${RED}[ERROR]${NC} Variable d'environnement CLOUDFLARE_ZONE_ID non définie"
      echo -e "${YELLOW}[TIP]${NC} Exportez l'ID de zone Cloudflare avec: export CLOUDFLARE_ZONE_ID=votre_zone_id"
      exit 1
    fi
    ;;
  route53)
    if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
      echo -e "${RED}[ERROR]${NC} Variable d'environnement AWS_ACCESS_KEY_ID non définie"
      echo -e "${YELLOW}[TIP]${NC} Configurez vos identifiants AWS avec: aws configure"
      exit 1
    fi
    if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
      echo -e "${RED}[ERROR]${NC} Variable d'environnement AWS_SECRET_ACCESS_KEY non définie"
      echo -e "${YELLOW}[TIP]${NC} Configurez vos identifiants AWS avec: aws configure"
      exit 1
    fi
    if [[ -z "${AWS_HOSTED_ZONE_ID:-}" ]]; then
      echo -e "${RED}[ERROR]${NC} Variable d'environnement AWS_HOSTED_ZONE_ID non définie"
      echo -e "${YELLOW}[TIP]${NC} Exportez l'ID de zone hébergée AWS avec: export AWS_HOSTED_ZONE_ID=votre_zone_id"
      exit 1
    fi
    ;;
  *)
    echo -e "${RED}[ERROR]${NC} Fournisseur DNS non pris en charge: ${DNS_PROVIDER}"
    echo -e "${YELLOW}[TIP]${NC} Fournisseurs DNS pris en charge: cloudflare, route53"
    exit 1
    ;;
esac

# Vérification de curl
if ! command -v curl &> /dev/null; then
  echo -e "${RED}[ERROR]${NC} curl n'est pas installé ou n'est pas dans le PATH"
  exit 1
fi

# Vérification de jq
if ! command -v jq &> /dev/null; then
  echo -e "${RED}[ERROR]${NC} jq n'est pas installé ou n'est pas dans le PATH"
  exit 1
fi

# Détermination du domaine principal en fonction de l'environnement
case "${ENVIRONMENT}" in
  production)
    BASE_DOMAIN="lions.dev"
    ;;
  staging)
    BASE_DOMAIN="staging.lions.dev"
    ;;
  development)
    BASE_DOMAIN="dev.lions.dev"
    ;;
  *)
    echo -e "${RED}[ERROR]${NC} Environnement non pris en charge: ${ENVIRONMENT}"
    echo -e "${YELLOW}[TIP]${NC} Environnements pris en charge: production, staging, development"
    exit 1
    ;;
esac

echo -e "${GREEN}[INFO]${NC} Configuration DNS pour l'environnement: ${ENVIRONMENT}"
echo -e "${GREEN}[INFO]${NC} Domaine principal: ${BASE_DOMAIN}"
echo -e "${GREEN}[INFO]${NC} IP du VPS: ${VPS_IP}"

# Liste des sous-domaines à configurer
SUBDOMAINS=(
  # Domaine principal
  "@"
  # Sous-domaines pour les API
  "api"
  # Sous-domaines pour les applications
  "afterwork"
  "associations"
  "btp"
  "immobilier"
  # Sous-domaines pour les services
  "mail"
  "k8s"
  "grafana"
  "prometheus"
  "pgadmin"
  "git"
  "keycloak"
  "ollama"
  "registry"
)

# Fonction pour configurer les enregistrements DNS avec Cloudflare
configure_cloudflare_dns() {
  local domain="$1"
  local record_name="$2"
  local record_type="A"
  local ttl=3600

  echo -e "${GREEN}[INFO]${NC} Configuration de l'enregistrement DNS pour ${record_name}.${domain} -> ${VPS_IP}"

  # Vérification si l'enregistrement existe déjà
  local existing_record
  existing_record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?type=${record_type}&name=${record_name}.${domain}" \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json")

  local record_id
  record_id=$(echo "${existing_record}" | jq -r '.result[0].id // empty')

  if [[ -n "${record_id}" ]]; then
    # Mise à jour de l'enregistrement existant
    echo -e "${YELLOW}[INFO]${NC} L'enregistrement existe déjà, mise à jour..."
    
    local update_result
    update_result=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${record_id}" \
      -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"${record_type}\",\"name\":\"${record_name}\",\"content\":\"${VPS_IP}\",\"ttl\":${ttl},\"proxied\":true}")
    
    if echo "${update_result}" | jq -e '.success' &>/dev/null; then
      echo -e "${GREEN}[SUCCESS]${NC} Enregistrement DNS mis à jour avec succès: ${record_name}.${domain} -> ${VPS_IP}"
    else
      echo -e "${RED}[ERROR]${NC} Échec de la mise à jour de l'enregistrement DNS: ${record_name}.${domain}"
      echo -e "${RED}[ERROR]${NC} Détails: $(echo "${update_result}" | jq -r '.errors[0].message')"
    fi
  else
    # Création d'un nouvel enregistrement
    echo -e "${YELLOW}[INFO]${NC} L'enregistrement n'existe pas, création..."
    
    local create_result
    create_result=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
      -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "{\"type\":\"${record_type}\",\"name\":\"${record_name}\",\"content\":\"${VPS_IP}\",\"ttl\":${ttl},\"proxied\":true}")
    
    if echo "${create_result}" | jq -e '.success' &>/dev/null; then
      echo -e "${GREEN}[SUCCESS]${NC} Enregistrement DNS créé avec succès: ${record_name}.${domain} -> ${VPS_IP}"
    else
      echo -e "${RED}[ERROR]${NC} Échec de la création de l'enregistrement DNS: ${record_name}.${domain}"
      echo -e "${RED}[ERROR]${NC} Détails: $(echo "${create_result}" | jq -r '.errors[0].message')"
    fi
  fi
}

# Fonction pour configurer les enregistrements DNS avec Route53
configure_route53_dns() {
  local domain="$1"
  local record_name="$2"
  local record_type="A"
  local ttl=3600

  echo -e "${GREEN}[INFO]${NC} Configuration de l'enregistrement DNS pour ${record_name}.${domain} -> ${VPS_IP}"

  # Préparation du nom complet de l'enregistrement
  local full_record_name
  if [[ "${record_name}" == "@" ]]; then
    full_record_name="${domain}."
  else
    full_record_name="${record_name}.${domain}."
  fi

  # Création du fichier de changement
  local change_file="/tmp/route53-change-$(date +%s).json"
  cat > "${change_file}" << EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${full_record_name}",
        "Type": "${record_type}",
        "TTL": ${ttl},
        "ResourceRecords": [
          {
            "Value": "${VPS_IP}"
          }
        ]
      }
    }
  ]
}
EOF

  # Exécution de la commande AWS CLI
  local aws_result
  aws_result=$(aws route53 change-resource-record-sets --hosted-zone-id "${AWS_HOSTED_ZONE_ID}" --change-batch "file://${change_file}")

  if echo "${aws_result}" | jq -e '.ChangeInfo.Status' &>/dev/null; then
    echo -e "${GREEN}[SUCCESS]${NC} Enregistrement DNS configuré avec succès: ${full_record_name} -> ${VPS_IP}"
  else
    echo -e "${RED}[ERROR]${NC} Échec de la configuration de l'enregistrement DNS: ${full_record_name}"
    echo -e "${RED}[ERROR]${NC} Détails: ${aws_result}"
  fi

  # Nettoyage du fichier temporaire
  rm -f "${change_file}"
}

# Configuration des enregistrements DNS
echo -e "${GREEN}[INFO]${NC} Configuration des enregistrements DNS pour le domaine ${BASE_DOMAIN}..."

for subdomain in "${SUBDOMAINS[@]}"; do
  case "${DNS_PROVIDER}" in
    cloudflare)
      configure_cloudflare_dns "${BASE_DOMAIN}" "${subdomain}"
      ;;
    route53)
      configure_route53_dns "${BASE_DOMAIN}" "${subdomain}"
      ;;
  esac
done

echo -e "\n${GREEN}[SUCCESS]${NC} Configuration DNS terminée avec succès!"
echo -e "${YELLOW}[INFO]${NC} Les modifications DNS peuvent prendre jusqu'à 24 heures pour se propager complètement."
echo -e "${YELLOW}[INFO]${NC} Vous pouvez vérifier la propagation DNS avec: dig +short <domaine>"

# Génération d'un rapport de configuration
REPORT_FILE="${LOG_DIR}/dns-configuration-report-$(date +%Y%m%d-%H%M%S).txt"
echo "=== Rapport de Configuration DNS LIONS ===" > "${REPORT_FILE}"
echo "Date: $(date)" >> "${REPORT_FILE}"
echo "Environnement: ${ENVIRONMENT}" >> "${REPORT_FILE}"
echo "Domaine principal: ${BASE_DOMAIN}" >> "${REPORT_FILE}"
echo "IP du VPS: ${VPS_IP}" >> "${REPORT_FILE}"
echo "Fournisseur DNS: ${DNS_PROVIDER}" >> "${REPORT_FILE}"
echo "" >> "${REPORT_FILE}"
echo "Enregistrements DNS configurés:" >> "${REPORT_FILE}"
for subdomain in "${SUBDOMAINS[@]}"; do
  if [[ "${subdomain}" == "@" ]]; then
    echo "- ${BASE_DOMAIN} -> ${VPS_IP}" >> "${REPORT_FILE}"
  else
    echo "- ${subdomain}.${BASE_DOMAIN} -> ${VPS_IP}" >> "${REPORT_FILE}"
  fi
done

echo -e "${GREEN}[INFO]${NC} Rapport de configuration généré: ${REPORT_FILE}"