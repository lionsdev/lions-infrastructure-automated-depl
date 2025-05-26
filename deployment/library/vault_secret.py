#!/usr/bin/python
# -*- coding: utf-8 -*-

DOCUMENTATION = '''
---
module: vault_secret
short_description: Gère les secrets dans HashiCorp Vault
description:
    - Ce module permet de créer, lire, mettre à jour et supprimer des secrets dans HashiCorp Vault.
    - Compatible avec Vault KV v1 et v2.
    - Supporte l'authentification par token, AppRole, et Kubernetes.
options:
    url:
        description:
            - URL de l'API Vault
        required: true
        type: str
    token:
        description:
            - Token d'authentification Vault
        required: false
        type: str
    path:
        description:
            - Chemin du secret dans Vault
        required: true
        type: str
    data:
        description:
            - Données du secret (pour create/update)
        required: false
        type: dict
    state:
        description:
            - État désiré du secret
        choices: ['present', 'absent']
        default: present
        type: str
    verify_ssl:
        description:
            - Vérifie les certificats SSL lors des requêtes
            - Pour la sécurité en production, définir à true
        required: false
        default: true
        type: bool
    ca_cert:
        description:
            - Chemin vers un certificat CA personnalisé pour la vérification SSL
        required: false
        type: str
    namespace:
        description:
            - Namespace Vault (fonctionnalité Enterprise)
        required: false
        type: str
    auth_method:
        description:
            - Méthode d'authentification à utiliser
        choices: ['token', 'approle', 'kubernetes']
        default: 'token'
        type: str
    role_id:
        description:
            - Role ID pour l'authentification AppRole
        required: false
        type: str
    secret_id:
        description:
            - Secret ID pour l'authentification AppRole
        required: false
        type: str
    kv_version:
        description:
            - Version de l'API KV Vault (1 ou 2)
        choices: [1, 2]
        default: 2
        type: int
'''

EXAMPLES = '''
- name: Créer un secret dans Vault
  vault_secret:
    url: https://vault.example.com:8200
    token: s.xxxxxxxxxxxxxxxx
    path: kv/data/lions/database
    data:
      username: admin
      password: secret123
    state: present

- name: Lire un secret depuis Vault
  vault_secret:
    url: https://vault.example.com:8200
    token: s.xxxxxxxxxxxxxxxx
    path: kv/data/lions/database
  register: db_credentials

- name: Supprimer un secret de Vault
  vault_secret:
    url: https://vault.example.com:8200
    token: s.xxxxxxxxxxxxxxxx
    path: kv/data/lions/database
    state: absent
'''

import json
import urllib.request
import urllib.error
import ssl
import os
import tempfile
import base64

from ansible.module_utils.basic import AnsibleModule

def get_token_from_approle(url, role_id, secret_id, ctx):
    """Obtient un token Vault en utilisant l'authentification AppRole."""
    try:
        payload = json.dumps({
            'role_id': role_id,
            'secret_id': secret_id
        }).encode('utf-8')

        headers = {'Content-Type': 'application/json'}
        req = urllib.request.Request(f"{url}/v1/auth/approle/login", 
                                    data=payload, 
                                    headers=headers, 
                                    method='POST')
        response = urllib.request.urlopen(req, context=ctx)
        result = json.loads(response.read().decode('utf-8'))

        return result['auth']['client_token']
    except urllib.error.HTTPError as e:
        error_msg = f"Erreur lors de l'authentification AppRole: {str(e)}"
        if e.code == 400:
            error_msg = "Role ID ou Secret ID invalide"
        elif e.code == 403:
            error_msg = "Permissions insuffisantes pour l'authentification AppRole"
        return None, error_msg
    except Exception as e:
        return None, f"Erreur inattendue lors de l'authentification AppRole: {str(e)}"

def get_token_from_kubernetes(url, role, jwt_token, ctx):
    """Obtient un token Vault en utilisant l'authentification Kubernetes."""
    try:
        payload = json.dumps({
            'role': role,
            'jwt': jwt_token
        }).encode('utf-8')

        headers = {'Content-Type': 'application/json'}
        req = urllib.request.Request(f"{url}/v1/auth/kubernetes/login", 
                                    data=payload, 
                                    headers=headers, 
                                    method='POST')
        response = urllib.request.urlopen(req, context=ctx)
        result = json.loads(response.read().decode('utf-8'))

        return result['auth']['client_token']
    except urllib.error.HTTPError as e:
        error_msg = f"Erreur lors de l'authentification Kubernetes: {str(e)}"
        if e.code == 400:
            error_msg = "JWT token ou rôle invalide"
        elif e.code == 403:
            error_msg = "Permissions insuffisantes pour l'authentification Kubernetes"
        return None, error_msg
    except Exception as e:
        return None, f"Erreur inattendue lors de l'authentification Kubernetes: {str(e)}"

def format_path_for_kv_version(path, kv_version):
    """Formate le chemin du secret en fonction de la version de l'API KV."""
    if kv_version == 1:
        return path

    # Pour KV v2, le chemin doit inclure /data/ s'il n'est pas déjà présent
    if '/data/' not in path:
        # Séparation du moteur et du chemin
        parts = path.split('/', 1)
        if len(parts) == 2:
            engine, secret_path = parts
            return f"{engine}/data/{secret_path}"
        else:
            return f"{path}/data"

    return path

def main():
    module = AnsibleModule(
        argument_spec=dict(
            url=dict(type='str', required=True),
            token=dict(type='str', required=False, no_log=True),
            path=dict(type='str', required=True),
            data=dict(type='dict', required=False),
            state=dict(type='str', default='present', choices=['present', 'absent']),
            verify_ssl=dict(type='bool', default=True),
            ca_cert=dict(type='str', required=False),
            namespace=dict(type='str', required=False),
            auth_method=dict(type='str', default='token', choices=['token', 'approle', 'kubernetes']),
            role_id=dict(type='str', required=False, no_log=True),
            secret_id=dict(type='str', required=False, no_log=True),
            kubernetes_role=dict(type='str', required=False),
            jwt_file=dict(type='str', required=False, default='/var/run/secrets/kubernetes.io/serviceaccount/token'),
            kv_version=dict(type='int', default=2, choices=[1, 2]),
        ),
        supports_check_mode=True,
        required_if=[
            ('auth_method', 'approle', ['role_id', 'secret_id']),
            ('auth_method', 'kubernetes', ['kubernetes_role']),
        ]
    )

    url = module.params['url']
    token = module.params['token']
    path = module.params['path']
    data = module.params['data']
    state = module.params['state']
    verify_ssl = module.params['verify_ssl']
    ca_cert = module.params['ca_cert']
    namespace = module.params['namespace']
    auth_method = module.params['auth_method']
    role_id = module.params['role_id']
    secret_id = module.params['secret_id']
    kubernetes_role = module.params['kubernetes_role']
    jwt_file = module.params['jwt_file']
    kv_version = module.params['kv_version']

    # Configuration du contexte SSL
    ctx = ssl.create_default_context()

    if not verify_ssl:
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    elif ca_cert:
        # Si un certificat CA personnalisé est fourni
        if os.path.isfile(ca_cert):
            ctx.load_verify_locations(cafile=ca_cert)
        else:
            module.fail_json(msg=f"Le fichier de certificat CA spécifié n'existe pas: {ca_cert}")

    # Obtention du token en fonction de la méthode d'authentification
    if auth_method == 'approle':
        if not (role_id and secret_id):
            module.fail_json(msg="role_id et secret_id sont requis pour l'authentification AppRole")

        token = get_token_from_approle(url, role_id, secret_id, ctx)
        if not token:
            module.fail_json(msg="Échec de l'authentification AppRole")

    elif auth_method == 'kubernetes':
        if not kubernetes_role:
            module.fail_json(msg="kubernetes_role est requis pour l'authentification Kubernetes")

        # Lecture du token JWT depuis le fichier
        try:
            with open(jwt_file, 'r') as f:
                jwt_token = f.read().strip()
        except Exception as e:
            module.fail_json(msg=f"Impossible de lire le token JWT depuis {jwt_file}: {str(e)}")

        token = get_token_from_kubernetes(url, kubernetes_role, jwt_token, ctx)
        if not token:
            module.fail_json(msg="Échec de l'authentification Kubernetes")

    elif auth_method == 'token':
        if not token:
            module.fail_json(msg="token est requis pour l'authentification par token")

    # Formatage du chemin en fonction de la version de l'API KV
    path = format_path_for_kv_version(path, kv_version)

    # En-têtes HTTP
    headers = {
        'X-Vault-Token': token,
        'Content-Type': 'application/json'
    }

    # Ajout du namespace si spécifié (fonctionnalité Enterprise)
    if namespace:
        headers['X-Vault-Namespace'] = namespace

    if state == 'present':
        if not data:
            # Lecture du secret
            try:
                req = urllib.request.Request(f"{url}/v1/{path}", headers=headers)
                response = urllib.request.urlopen(req, context=ctx)
                result = json.loads(response.read().decode('utf-8'))
                module.exit_json(changed=False, data=result['data']['data'])
            except urllib.error.HTTPError as e:
                if e.code == 404:
                    module.fail_json(msg=f"Secret not found at {path}")
                else:
                    module.fail_json(msg=f"Error reading secret: {str(e)}")
        else:
            # Création ou mise à jour du secret
            try:
                # Vérifier si le secret existe déjà
                req = urllib.request.Request(f"{url}/v1/{path}", headers=headers)
                try:
                    response = urllib.request.urlopen(req, context=ctx)
                    existing_data = json.loads(response.read().decode('utf-8'))['data']['data']
                    changed = existing_data != data
                except urllib.error.HTTPError as e:
                    if e.code == 404:
                        changed = True
                    else:
                        module.fail_json(msg=f"Error checking if secret exists: {str(e)}")

                if module.check_mode:
                    module.exit_json(changed=changed)

                # Créer ou mettre à jour le secret
                payload = json.dumps({'data': data}).encode('utf-8')
                req = urllib.request.Request(f"{url}/v1/{path}", data=payload, headers=headers, method='POST')
                response = urllib.request.urlopen(req, context=ctx)
                module.exit_json(changed=changed)
            except urllib.error.HTTPError as e:
                module.fail_json(msg=f"Error creating/updating secret: {str(e)}")
    else:
        # Suppression du secret
        try:
            # Vérifier si le secret existe
            req = urllib.request.Request(f"{url}/v1/{path}", headers=headers)
            try:
                urllib.request.urlopen(req, context=ctx)
                exists = True
            except urllib.error.HTTPError as e:
                if e.code == 404:
                    exists = False
                else:
                    module.fail_json(msg=f"Error checking if secret exists: {str(e)}")

            if not exists:
                module.exit_json(changed=False)

            if module.check_mode:
                module.exit_json(changed=True)

            # Supprimer le secret
            req = urllib.request.Request(f"{url}/v1/{path}", headers=headers, method='DELETE')
            urllib.request.urlopen(req, context=ctx)
            module.exit_json(changed=True)
        except urllib.error.HTTPError as e:
            module.fail_json(msg=f"Error deleting secret: {str(e)}")

if __name__ == '__main__':
    main()
