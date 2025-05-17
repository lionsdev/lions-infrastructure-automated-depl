#!/usr/bin/python
# -*- coding: utf-8 -*-

DOCUMENTATION = '''
---
module: vault_secret
short_description: Gère les secrets dans HashiCorp Vault
description:
    - Ce module permet de créer, lire, mettre à jour et supprimer des secrets dans HashiCorp Vault.
options:
    url:
        description:
            - URL de l'API Vault
        required: true
        type: str
    token:
        description:
            - Token d'authentification Vault
        required: true
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

from ansible.module_utils.basic import AnsibleModule

def main():
    module = AnsibleModule(
        argument_spec=dict(
            url=dict(type='str', required=True),
            token=dict(type='str', required=True, no_log=True),
            path=dict(type='str', required=True),
            data=dict(type='dict', required=False),
            state=dict(type='str', default='present', choices=['present', 'absent']),
        ),
        supports_check_mode=True
    )

    url = module.params['url']
    token = module.params['token']
    path = module.params['path']
    data = module.params['data']
    state = module.params['state']

    # Création du contexte SSL pour ignorer la vérification des certificats
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    headers = {
        'X-Vault-Token': token,
        'Content-Type': 'application/json'
    }

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