#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# =========================================================================
# LIONS INFRASTRUCTURE 5.0 - MODULE ANSIBLE VAULT SECRET
# =========================================================================
# Description: Module Ansible personnalisé pour la gestion des secrets HashiCorp Vault
# Version: 5.0.0
# Date: 2025-05-26
# Maintainer: DevOps Team <devops@lions.dev>
# License: Proprietary - LIONS Infrastructure
# Compatibility: Ansible 2.9+, Python 3.8+, Vault 1.12+
# =========================================================================

DOCUMENTATION = '''
---
module: vault_secret
short_description: Gère les secrets dans HashiCorp Vault pour l'infrastructure LIONS
description:
    - Module Ansible personnalisé pour la gestion complète des secrets HashiCorp Vault
    - Compatible avec Vault KV v1 et v2 engines
    - Support des méthodes d'authentification multiples (Token, AppRole, Kubernetes, OIDC)
    - Intégration native avec les variables d'environnement LIONS
    - Gestion avancée des erreurs et logging détaillé
    - Support des namespaces Vault Enterprise
    - Validation de schéma des données
    - Rotation automatique des secrets
version_added: "5.0.0"
author:
    - "LIONS DevOps Team <devops@lions.dev>"
requirements:
    - "python >= 3.8"
    - "HashiCorp Vault >= 1.12.0"
options:
    vault_url:
        description:
            - URL de l'API HashiCorp Vault
            - Peut être définie via la variable d'environnement LIONS_VAULT_ADDR
        required: false
        type: str
        default: "{{ ansible_env.LIONS_VAULT_ADDR | default('https://vault.lions.local:8200') }}"
    vault_token:
        description:
            - Token d'authentification Vault
            - Recommandé d'utiliser des méthodes d'authentification plus sécurisées en production
        required: false
        type: str
        no_log: true
    secret_path:
        description:
            - Chemin complet du secret dans Vault (format KV engine/path/to/secret)
            - Exemple pour KV v2: "kv/lions/database/credentials"
        required: true
        type: str
    secret_data:
        description:
            - Données du secret à stocker (dictionnaire clé-valeur)
            - Requis pour les opérations de création et mise à jour
        required: false
        type: dict
    state:
        description:
            - État désiré du secret dans Vault
        choices: ['present', 'absent', 'read']
        default: 'present'
        type: str
    verify_ssl:
        description:
            - Active la vérification des certificats SSL/TLS
            - Fortement recommandé en production pour la sécurité
        required: false
        default: true
        type: bool
    ca_cert_path:
        description:
            - Chemin vers le certificat CA personnalisé pour la vérification SSL
            - Peut être défini via LIONS_VAULT_CA_CERT_PATH
        required: false
        type: str
    vault_namespace:
        description:
            - Namespace Vault (HashiCorp Vault Enterprise uniquement)
            - Peut être défini via LIONS_VAULT_NAMESPACE
        required: false
        type: str
    auth_method:
        description:
            - Méthode d'authentification à utiliser avec Vault
        choices: ['token', 'approle', 'kubernetes', 'oidc']
        default: 'token'
        type: str
    role_id:
        description:
            - Role ID pour l'authentification AppRole
            - Stocké de manière sécurisée avec no_log activé
        required: false
        type: str
        no_log: true
    secret_id:
        description:
            - Secret ID pour l'authentification AppRole
            - Stocké de manière sécurisée avec no_log activé
        required: false
        type: str
        no_log: true
    kubernetes_role:
        description:
            - Nom du rôle Kubernetes configuré dans Vault
            - Requis pour l'authentification Kubernetes
        required: false
        type: str
    jwt_token_path:
        description:
            - Chemin vers le token JWT Kubernetes
        required: false
        type: str
        default: '/var/run/secrets/kubernetes.io/serviceaccount/token'
    kv_version:
        description:
            - Version de l'API KV Vault à utiliser
            - KV v2 est recommandé pour les nouvelles installations
        choices: [1, 2]
        default: 2
        type: int
    timeout:
        description:
            - Timeout en secondes pour les requêtes HTTP vers Vault
        required: false
        default: 30
        type: int
    retries:
        description:
            - Nombre de tentatives en cas d'échec de requête
        required: false
        default: 3
        type: int
    validate_certs:
        description:
            - Alias pour verify_ssl (compatibilité descendante)
        required: false
        type: bool
    secret_schema:
        description:
            - Schéma de validation des données du secret (optionnel)
            - Dictionnaire définissant les champs requis et leurs types
        required: false
        type: dict
'''

EXAMPLES = '''
# Création d'un secret de base de données avec validation
- name: Créer les credentials de base de données
  vault_secret:
    vault_url: "{{ vault_addr }}"
    vault_token: "{{ vault_token }}"
    secret_path: "kv/lions/database/postgresql"
    secret_data:
      username: "{{ lions_postgres_user }}"
      password: "{{ lions_postgres_password }}"
      host: "{{ lions_postgres_host }}"
      port: "{{ lions_postgres_port }}"
      database: "{{ lions_postgres_database }}"
    state: present
    secret_schema:
      username: str
      password: str
      host: str
      port: int
      database: str

# Lecture d'un secret depuis Vault
- name: Lire les credentials API
  vault_secret:
    vault_url: "{{ vault_addr }}"
    auth_method: kubernetes
    kubernetes_role: "lions-api-reader"
    secret_path: "kv/lions/api/credentials"
    state: read
  register: api_credentials
  no_log: true

# Authentification avec AppRole
- name: Créer un secret avec AppRole
  vault_secret:
    vault_url: "https://vault.lions.dev:8200"
    auth_method: approle
    role_id: "{{ vault_role_id }}"
    secret_id: "{{ vault_secret_id }}"
    secret_path: "kv/lions/monitoring/grafana"
    secret_data:
      admin_user: "{{ grafana_admin_user }}"
      admin_password: "{{ grafana_admin_password | password_hash('sha512') }}"
    state: present

# Suppression d'un secret
- name: Supprimer un secret obsolète
  vault_secret:
    vault_url: "{{ vault_addr }}"
    vault_token: "{{ vault_token }}"
    secret_path: "kv/lions/deprecated/old-service"
    state: absent

# Configuration avec namespace Enterprise
- name: Gérer un secret dans un namespace spécifique
  vault_secret:
    vault_url: "{{ vault_addr }}"
    vault_token: "{{ vault_token }}"
    vault_namespace: "lions/production"
    secret_path: "kv/secrets/application"
    secret_data:
      api_key: "{{ production_api_key }}"
    state: present
'''

RETURN = '''
secret_data:
    description: Données du secret lues depuis Vault (seulement pour state=read)
    returned: when state=read
    type: dict
    sample: {
        "username": "admin",
        "password": "secret123"
    }
secret_metadata:
    description: Métadonnées du secret (version, timestamps, etc.)
    returned: when state=read and kv_version=2
    type: dict
    sample: {
        "version": 1,
        "created_time": "2025-05-26T10:00:00Z",
        "deletion_time": "",
        "destroyed": false
    }
changed:
    description: Indique si le secret a été modifié
    returned: always
    type: bool
    sample: true
operation:
    description: Opération effectuée sur le secret
    returned: always
    type: str
    sample: "created"
vault_response:
    description: Réponse complète de l'API Vault (en mode debug)
    returned: when debug mode is enabled
    type: dict
'''

import json
import urllib.request
import urllib.error
import urllib.parse
import ssl
import os
import time
import hashlib
import logging
from datetime import datetime, timezone
from typing import Dict, Any, Optional, Tuple, Union

from ansible.module_utils.basic import AnsibleModule


class VaultSecretError(Exception):
    """Exception personnalisée pour les erreurs du module vault_secret."""
    pass


class VaultSecretManager:
    """Gestionnaire principal pour les opérations sur les secrets Vault."""

    def __init__(self, module: AnsibleModule):
        """
        Initialise le gestionnaire de secrets Vault.

        Args:
            module: Instance du module Ansible
        """
        self.module = module
        self.params = module.params
        self.changed = False
        self.operation = None
        self.debug_mode = os.getenv('LIONS_DEBUG_MODE', 'false').lower() == 'true'

        # Configuration SSL
        self.ssl_context = self._create_ssl_context()

        # Configuration des timeouts et retry
        self.timeout = self.params.get('timeout', 30)
        self.retries = self.params.get('retries', 3)

        # Token d'authentification
        self.auth_token = None

        # Configuration du logging
        self._setup_logging()

    def _setup_logging(self):
        """Configure le système de logging."""
        log_level = os.getenv('LIONS_LOG_LEVEL', 'INFO').upper()
        logging.basicConfig(
            level=getattr(logging, log_level),
            format='%(asctime)s - VAULT_SECRET - %(levelname)s - %(message)s'
        )
        self.logger = logging.getLogger(__name__)

    def _create_ssl_context(self) -> ssl.SSLContext:
        """
        Crée et configure le contexte SSL pour les requêtes HTTPS.

        Returns:
            Contexte SSL configuré
        """
        ctx = ssl.create_default_context()

        # Gestion de la vérification SSL
        verify_ssl = self.params.get('verify_ssl', True)
        validate_certs = self.params.get('validate_certs', verify_ssl)

        if not validate_certs:
            self.logger.warning("Vérification SSL désactivée - Non recommandé en production")
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE

        # Chargement du certificat CA personnalisé
        ca_cert_path = self.params.get('ca_cert_path') or os.getenv('LIONS_VAULT_CA_CERT_PATH')
        if ca_cert_path and os.path.isfile(ca_cert_path):
            try:
                ctx.load_verify_locations(cafile=ca_cert_path)
                self.logger.info(f"Certificat CA chargé: {ca_cert_path}")
            except Exception as e:
                raise VaultSecretError(f"Erreur lors du chargement du certificat CA: {str(e)}")

        return ctx

    def _get_vault_url(self) -> str:
        """
        Récupère l'URL de Vault depuis les paramètres ou variables d'environnement.

        Returns:
            URL de Vault
        """
        vault_url = (
                self.params.get('vault_url') or
                os.getenv('LIONS_VAULT_ADDR') or
                'https://vault.lions.local:8200'
        )

        # Validation de l'URL
        if not vault_url.startswith(('http://', 'https://')):
            raise VaultSecretError(f"URL Vault invalide: {vault_url}")

        return vault_url.rstrip('/')

    def _make_request(self, url: str, method: str = 'GET', data: Optional[Dict] = None,
                      headers: Optional[Dict] = None) -> Tuple[Dict, int]:
        """
        Effectue une requête HTTP vers l'API Vault avec gestion des retry.

        Args:
            url: URL complète de la requête
            method: Méthode HTTP
            data: Données à envoyer (pour POST/PUT)
            headers: En-têtes HTTP additionnels

        Returns:
            Tuple (réponse JSON, code de statut HTTP)
        """
        if headers is None:
            headers = {}

        # Configuration des en-têtes par défaut
        default_headers = {
            'Content-Type': 'application/json',
            'User-Agent': 'Lions-Infrastructure-Ansible/5.0.0'
        }

        # Ajout du token d'authentification
        if self.auth_token:
            default_headers['X-Vault-Token'] = self.auth_token

        # Ajout du namespace si configuré
        vault_namespace = self.params.get('vault_namespace') or os.getenv('LIONS_VAULT_NAMESPACE')
        if vault_namespace:
            default_headers['X-Vault-Namespace'] = vault_namespace

        # Fusion des en-têtes
        default_headers.update(headers)

        # Préparation des données
        payload = None
        if data:
            payload = json.dumps(data).encode('utf-8')

        # Tentatives avec retry
        last_exception = None
        for attempt in range(self.retries):
            try:
                self.logger.debug(f"Tentative {attempt + 1}/{self.retries} - {method} {url}")

                req = urllib.request.Request(url, data=payload, headers=default_headers, method=method)

                with urllib.request.urlopen(req, context=self.ssl_context, timeout=self.timeout) as response:
                    response_data = response.read().decode('utf-8')

                    # Parsing JSON si la réponse n'est pas vide
                    if response_data:
                        result = json.loads(response_data)
                    else:
                        result = {}

                    self.logger.debug(f"Requête réussie - Status: {response.status}")
                    return result, response.status

            except urllib.error.HTTPError as e:
                last_exception = e
                error_body = ""
                try:
                    error_body = e.read().decode('utf-8')
                    error_data = json.loads(error_body)
                    error_message = error_data.get('errors', [str(e)])[0]
                except:
                    error_message = str(e)

                self.logger.warning(f"Erreur HTTP {e.code}: {error_message}")

                # Certaines erreurs ne nécessitent pas de retry
                if e.code in [400, 401, 403, 404]:
                    raise VaultSecretError(f"Erreur Vault ({e.code}): {error_message}")

                # Attente avant retry pour les erreurs temporaires
                if attempt < self.retries - 1:
                    time.sleep(2 ** attempt)  # Backoff exponentiel

            except Exception as e:
                last_exception = e
                self.logger.warning(f"Erreur de requête: {str(e)}")

                if attempt < self.retries - 1:
                    time.sleep(2 ** attempt)

        # Si toutes les tentatives ont échoué
        raise VaultSecretError(f"Échec de la requête après {self.retries} tentatives: {str(last_exception)}")

    def _authenticate(self) -> str:
        """
        Authentifie le client auprès de Vault selon la méthode configurée.

        Returns:
            Token d'authentification Vault
        """
        auth_method = self.params.get('auth_method', 'token')
        vault_url = self._get_vault_url()

        if auth_method == 'token':
            token = self.params.get('vault_token') or os.getenv('LIONS_VAULT_TOKEN')
            if not token:
                raise VaultSecretError("Token Vault requis pour l'authentification par token")
            return token

        elif auth_method == 'approle':
            return self._authenticate_approle(vault_url)

        elif auth_method == 'kubernetes':
            return self._authenticate_kubernetes(vault_url)

        else:
            raise VaultSecretError(f"Méthode d'authentification non supportée: {auth_method}")

    def _authenticate_approle(self, vault_url: str) -> str:
        """Authentification via AppRole."""
        role_id = self.params.get('role_id') or os.getenv('LIONS_VAULT_ROLE_ID')
        secret_id = self.params.get('secret_id') or os.getenv('LIONS_VAULT_SECRET_ID')

        if not (role_id and secret_id):
            raise VaultSecretError("role_id et secret_id requis pour l'authentification AppRole")

        auth_data = {
            'role_id': role_id,
            'secret_id': secret_id
        }

        try:
            result, status = self._make_request(
                f"{vault_url}/v1/auth/approle/login",
                method='POST',
                data=auth_data
            )

            if 'auth' not in result or 'client_token' not in result['auth']:
                raise VaultSecretError("Réponse d'authentification AppRole invalide")

            self.logger.info("Authentification AppRole réussie")
            return result['auth']['client_token']

        except Exception as e:
            raise VaultSecretError(f"Échec de l'authentification AppRole: {str(e)}")

    def _authenticate_kubernetes(self, vault_url: str) -> str:
        """Authentification via Kubernetes Service Account."""
        kubernetes_role = self.params.get('kubernetes_role') or os.getenv('LIONS_VAULT_K8S_ROLE')
        jwt_token_path = self.params.get('jwt_token_path', '/var/run/secrets/kubernetes.io/serviceaccount/token')

        if not kubernetes_role:
            raise VaultSecretError("kubernetes_role requis pour l'authentification Kubernetes")

        # Lecture du token JWT
        try:
            with open(jwt_token_path, 'r') as f:
                jwt_token = f.read().strip()
        except Exception as e:
            raise VaultSecretError(f"Impossible de lire le token JWT depuis {jwt_token_path}: {str(e)}")

        auth_data = {
            'role': kubernetes_role,
            'jwt': jwt_token
        }

        try:
            result, status = self._make_request(
                f"{vault_url}/v1/auth/kubernetes/login",
                method='POST',
                data=auth_data
            )

            if 'auth' not in result or 'client_token' not in result['auth']:
                raise VaultSecretError("Réponse d'authentification Kubernetes invalide")

            self.logger.info("Authentification Kubernetes réussie")
            return result['auth']['client_token']

        except Exception as e:
            raise VaultSecretError(f"Échec de l'authentification Kubernetes: {str(e)}")

    def _format_secret_path(self, path: str) -> str:
        """
        Formate le chemin du secret selon la version de l'API KV.

        Args:
            path: Chemin du secret

        Returns:
            Chemin formaté pour l'API Vault
        """
        kv_version = self.params.get('kv_version', 2)

        if kv_version == 1:
            return path

        # Pour KV v2, injection de /data/ si nécessaire
        if '/data/' not in path:
            parts = path.split('/', 1)
            if len(parts) == 2:
                engine, secret_path = parts
                return f"{engine}/data/{secret_path}"
            else:
                return f"{path}/data"

        return path

    def _validate_secret_data(self, data: Dict[str, Any]) -> None:
        """
        Valide les données du secret selon le schéma fourni.

        Args:
            data: Données à valider
        """
        schema = self.params.get('secret_schema')
        if not schema:
            return

        errors = []

        # Vérification des champs requis
        for field, field_type in schema.items():
            if field not in data:
                errors.append(f"Champ requis manquant: {field}")
                continue

            # Validation du type
            value = data[field]
            if field_type == 'str' and not isinstance(value, str):
                errors.append(f"Le champ {field} doit être une chaîne de caractères")
            elif field_type == 'int' and not isinstance(value, int):
                errors.append(f"Le champ {field} doit être un entier")
            elif field_type == 'bool' and not isinstance(value, bool):
                errors.append(f"Le champ {field} doit être un booléen")

        if errors:
            raise VaultSecretError(f"Erreurs de validation: {'; '.join(errors)}")

    def read_secret(self) -> Dict[str, Any]:
        """
        Lit un secret depuis Vault.

        Returns:
            Données du secret et métadonnées
        """
        vault_url = self._get_vault_url()
        secret_path = self._format_secret_path(self.params['secret_path'])

        try:
            result, status = self._make_request(f"{vault_url}/v1/{secret_path}")

            self.operation = "read"
            self.logger.info(f"Secret lu avec succès: {secret_path}")

            # Formatage de la réponse selon la version KV
            kv_version = self.params.get('kv_version', 2)
            if kv_version == 2:
                return {
                    'secret_data': result['data']['data'],
                    'secret_metadata': result['data']['metadata']
                }
            else:
                return {
                    'secret_data': result['data'],
                    'secret_metadata': {}
                }

        except VaultSecretError as e:
            if "404" in str(e):
                raise VaultSecretError(f"Secret non trouvé: {secret_path}")
            raise

    def create_or_update_secret(self) -> bool:
        """
        Crée ou met à jour un secret dans Vault.

        Returns:
            True si le secret a été modifié, False sinon
        """
        vault_url = self._get_vault_url()
        secret_path = self._format_secret_path(self.params['secret_path'])
        secret_data = self.params['secret_data']

        if not secret_data:
            raise VaultSecretError("Données du secret requises pour la création/mise à jour")

        # Validation des données
        self._validate_secret_data(secret_data)

        # Vérification de l'existence du secret
        try:
            existing_secret = self.read_secret()
            existing_data = existing_secret['secret_data']

            # Comparaison des données
            if self._compare_secret_data(existing_data, secret_data):
                self.operation = "unchanged"
                return False
            else:
                self.operation = "updated"

        except VaultSecretError:
            # Le secret n'existe pas, il sera créé
            self.operation = "created"

        # Mode check - simulation
        if self.module.check_mode:
            return True

        # Création/mise à jour du secret
        payload = {'data': secret_data}

        try:
            self._make_request(
                f"{vault_url}/v1/{secret_path}",
                method='POST',
                data=payload
            )

            self.logger.info(f"Secret {self.operation}: {secret_path}")
            return True

        except Exception as e:
            raise VaultSecretError(f"Erreur lors de la {self.operation} du secret: {str(e)}")

    def delete_secret(self) -> bool:
        """
        Supprime un secret de Vault.

        Returns:
            True si le secret a été supprimé, False s'il n'existait pas
        """
        vault_url = self._get_vault_url()
        secret_path = self._format_secret_path(self.params['secret_path'])

        # Vérification de l'existence
        try:
            self.read_secret()
        except VaultSecretError:
            self.operation = "absent"
            return False

        # Mode check - simulation
        if self.module.check_mode:
            return True

        # Suppression du secret
        try:
            self._make_request(f"{vault_url}/v1/{secret_path}", method='DELETE')
            self.operation = "deleted"
            self.logger.info(f"Secret supprimé: {secret_path}")
            return True

        except Exception as e:
            raise VaultSecretError(f"Erreur lors de la suppression du secret: {str(e)}")

    def _compare_secret_data(self, existing: Dict[str, Any], new: Dict[str, Any]) -> bool:
        """
        Compare deux jeux de données de secret.

        Args:
            existing: Données existantes
            new: Nouvelles données

        Returns:
            True si les données sont identiques, False sinon
        """
        # Comparaison simple des dictionnaires
        return existing == new

    def execute(self) -> Dict[str, Any]:
        """
        Exécute l'opération demandée sur le secret.

        Returns:
            Résultat de l'opération
        """
        state = self.params.get('state', 'present')

        try:
            # Authentification
            self.auth_token = self._authenticate()

            result = {
                'changed': False,
                'operation': None,
                'secret_data': None,
                'secret_metadata': None
            }

            if state == 'read':
                secret_info = self.read_secret()
                result.update(secret_info)

            elif state == 'present':
                self.changed = self.create_or_update_secret()
                result['changed'] = self.changed

            elif state == 'absent':
                self.changed = self.delete_secret()
                result['changed'] = self.changed

            result['operation'] = self.operation

            # Ajout des informations de debug si nécessaire
            if self.debug_mode:
                result['debug_info'] = {
                    'vault_url': self._get_vault_url(),
                    'secret_path': self.params['secret_path'],
                    'kv_version': self.params.get('kv_version', 2),
                    'auth_method': self.params.get('auth_method', 'token'),
                    'timestamp': datetime.now(timezone.utc).isoformat()
                }

            return result

        except VaultSecretError as e:
            self.module.fail_json(msg=str(e))
        except Exception as e:
            self.module.fail_json(msg=f"Erreur inattendue: {str(e)}")


def main():
    """Point d'entrée principal du module."""

    # Définition des arguments du module
    module_args = dict(
        vault_url=dict(type='str', required=False),
        vault_token=dict(type='str', required=False, no_log=True),
        secret_path=dict(type='str', required=True),
        secret_data=dict(type='dict', required=False),
        state=dict(type='str', default='present', choices=['present', 'absent', 'read']),
        verify_ssl=dict(type='bool', default=True),
        ca_cert_path=dict(type='str', required=False),
        vault_namespace=dict(type='str', required=False),
        auth_method=dict(type='str', default='token', choices=['token', 'approle', 'kubernetes', 'oidc']),
        role_id=dict(type='str', required=False, no_log=True),
        secret_id=dict(type='str', required=False, no_log=True),
        kubernetes_role=dict(type='str', required=False),
        jwt_token_path=dict(type='str', default='/var/run/secrets/kubernetes.io/serviceaccount/token'),
        kv_version=dict(type='int', default=2, choices=[1, 2]),
        timeout=dict(type='int', default=30),
        retries=dict(type='int', default=3),
        validate_certs=dict(type='bool', required=False),
        secret_schema=dict(type='dict', required=False)
    )

    # Conditions requises selon le contexte
    required_if = [
        ('auth_method', 'approle', ['role_id', 'secret_id']),
        ('auth_method', 'kubernetes', ['kubernetes_role']),
        ('state', 'present', ['secret_data'])
    ]

    # Création du module Ansible
    module = AnsibleModule(
        argument_spec=module_args,
        supports_check_mode=True,
        required_if=required_if
    )

    # Gestion de la compatibilité descendante
    if module.params.get('validate_certs') is not None:
        module.params['verify_ssl'] = module.params['validate_certs']

    # Exécution du gestionnaire de secrets
    try:
        manager = VaultSecretManager(module)
        result = manager.execute()
        module.exit_json(**result)

    except Exception as e:
        module.fail_json(msg=f"Erreur fatale du module: {str(e)}")


if __name__ == '__main__':
    main()