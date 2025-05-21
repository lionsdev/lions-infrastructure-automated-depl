#!/bin/bash
# Fonction améliorée de vérification des prérequis pour le script install.sh

function verifier_prerequis() {
  echo "🔍 Vérification des prérequis du système..."
  
  # Vérification de l'OS
  if ! grep -q "Ubuntu\|Debian" /etc/os-release; then
    echo "❌ Ce script nécessite Ubuntu ou Debian. Système actuel: $(cat /etc/os-release | grep PRETTY_NAME | cut -d '=' -f2 | tr -d '"')"
    return 1
  fi
  
  # Vérification WSL2
  if grep -i microsoft /proc/version > /dev/null; then
    echo "⚠️ Environnement WSL2 détecté. Installation directe non recommandée."
    echo "📝 Utilisez plutôt le script remote-install.sh pour une installation directe sur le VPS."
    read -p "Voulez-vous continuer malgré les risques? (o/N): " confirm
    if [[ "$confirm" != "o" && "$confirm" != "O" ]]; then
      echo "📋 Installation annulée. Utilisez le script remote-install.sh."
      return 1
    fi
  fi
  
  # Vérification de l'espace disque
  disk_space=$(df -h / | awk 'NR==2 {print $4}')
  disk_space_gb=${disk_space%G*}
  # Si format est en M, convertir en fraction de GB
  if [[ "$disk_space" == *"M"* ]]; then
    disk_space_gb=$(echo "${disk_space%M*} / 1024" | bc -l | awk '{printf "%.2f", $0}')
  fi
  
  if (( $(echo "$disk_space_gb < 10" | bc -l) )); then
    echo "❌ Espace disque insuffisant: $disk_space disponible. Minimum 10GB requis."
    return 1
  fi
  
  # Vérification de la RAM
  mem_total=$(free -m | awk 'NR==2 {print $2}')
  if [[ $mem_total -lt 3800 ]]; then
    echo "❌ RAM insuffisante: ${mem_total}M disponible. Minimum 4GB requis."
    return 1
  fi
  
  # Vérification des CPU
  cpu_count=$(nproc)
  if [[ $cpu_count -lt 2 ]]; then
    echo "❌ CPUs insuffisants: $cpu_count disponible. Minimum 2 requis."
    return 1
  fi
  
  # Vérification des ports
  required_ports=(22 80 443 6443)
  busy_ports=()
  
  # Installer netstat si nécessaire
  if ! command -v netstat &> /dev/null; then
    echo "Installation de net-tools pour la vérification des ports..."
    apt-get update -qq && apt-get install -qq -y net-tools
  fi
  
  for port in "${required_ports[@]}"; do
    if netstat -tuln | grep -q ":$port "; then
      busy_ports+=($port)
    fi
  done
  
  if [[ ${#busy_ports[@]} -gt 0 ]]; then
    echo "⚠️ Les ports suivants sont déjà utilisés: ${busy_ports[*]}"
    echo "Ces ports sont nécessaires pour le fonctionnement de l'infrastructure LIONS."
    read -p "Voulez-vous continuer malgré ce conflit potentiel? (o/N): " confirm
    if [[ "$confirm" != "o" && "$confirm" != "O" ]]; then
      echo "📋 Installation annulée. Libérez ces ports avant de réessayer."
      return 1
    fi
  fi
  
  # Vérification des dépendances essentielles
  dependencies=(curl wget git)
  missing_deps=()
  
  for dep in "${dependencies[@]}"; do
    if ! command -v $dep &> /dev/null; then
      missing_deps+=($dep)
    fi
  done
  
  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo "Installation des dépendances manquantes: ${missing_deps[*]}"
    apt-get update -qq && apt-get install -y ${missing_deps[*]}
    if [[ $? -ne 0 ]]; then
      echo "❌ Échec de l'installation des dépendances. Vérifiez votre connexion internet et les droits d'administration."
      return 1
    fi
  fi
  
  # Vérification d'accès internet
  if ! ping -c 1 github.com > /dev/null 2>&1 && ! ping -c 1 get.k3s.io > /dev/null 2>&1; then
    echo "❌ Pas d'accès à Internet. Vérifiez votre connexion."
    return 1
  fi
  
  # Vérification de permissions sudo
  if ! sudo -n true 2>/dev/null; then
    echo "❌ Permissions sudo requises pour l'installation."
    return 1
  fi
  
  echo "✅ Tous les prérequis sont satisfaits."
  return 0
}

# Cette fonction doit être intégrée dans le script install.sh
echo "Fonction de vérification des prérequis pour le script install.sh"
echo "Intégrez cette fonction dans le script install.sh pour remplacer la fonction existante."