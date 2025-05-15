# Solution pour l'erreur de récupération du token permanent

## Problème identifié

Lors de l'exécution du script d'installation `./lions-infrastructure/scripts/install.sh --environment development`, une erreur se produit à l'étape "Récupération du token permanent" :

```
fatal: [contabo-vps]: FAILED! => {"changed": false, "cmd": ["k3s", "kubectl", "get", "secret", "dashboard-admin-token", "-n", "kubernetes-dashboard", "-o", "jsonpath={.data.token}", "|", "base64", "--decode"], "delta": "0:00:00.120310", "end": "2025-05-15 23:24:59.955197", "msg": "non-zero return code", "rc": 1, "start": "2025-05-15 23:24:59.834887", "stderr": "error: unknown flag: --decode\nSee 'kubectl get --help' for usage.", "stderr_lines": ["error: unknown flag: --decode", "See 'kubectl get --help' for usage."], "stdout": "", "stdout_lines": []}
```

Cette erreur se produit car le module `command` d'Ansible ne gère pas correctement les pipes (`|`). Lorsqu'on utilise le module `command`, Ansible traite l'ensemble de la chaîne comme une seule commande avec des arguments, donc il essaie de passer `|` et `base64 --decode` comme arguments à la commande kubectl, ce qui provoque l'erreur.

## Solution implémentée

La solution consiste à remplacer le module `command` par le module `shell` dans la tâche "Récupération du token permanent" :

```yaml
# Avant
- name: Récupération du token permanent
  command: k3s kubectl get secret dashboard-admin-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 --decode
  register: dashboard_token
  changed_when: false
  environment:
    KUBECONFIG: /home/{{ ansible_user }}/.kube/config

# Après
- name: Récupération du token permanent
  shell: k3s kubectl get secret dashboard-admin-token -n kubernetes-dashboard -o jsonpath='{.data.token}' | base64 --decode
  register: dashboard_token
  changed_when: false
  environment:
    KUBECONFIG: /home/{{ ansible_user }}/.kube/config
```

Le module `shell` d'Ansible exécute la commande dans un shell, ce qui permet d'utiliser des fonctionnalités de shell comme les pipes (`|`), les redirections (`>`, `<`), etc. Ainsi, la commande est correctement interprétée et le token peut être récupéré et décodé.

## Comment utiliser cette solution

Aucune action supplémentaire n'est requise de la part de l'utilisateur. Le script d'installation fonctionnera désormais correctement lors de l'exécution de la tâche "Récupération du token permanent".

## Vérification

J'ai vérifié qu'il n'y a pas d'autres tâches dans les playbooks Ansible qui utilisent le module `command` avec des pipes. Les autres instances de `command` trouvées dans le projet n'utilisent pas de pipes et fonctionnent correctement.

Les autres occurrences de `base64 --decode` dans le projet sont soit dans des scripts shell (où les pipes fonctionnent correctement), soit dans de la documentation.

## Impact

Cette modification permet au script d'installation de s'exécuter sans erreur et de récupérer correctement le token permanent pour l'accès au Kubernetes Dashboard. L'utilisateur pourra ainsi accéder au Dashboard en utilisant ce token.