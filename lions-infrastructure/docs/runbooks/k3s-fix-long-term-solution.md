# Solution à long terme pour les drapeaux dépréciés dans K3s

## Résumé

Ce document explique la solution à long terme mise en place pour résoudre les problèmes liés aux drapeaux dépréciés dans K3s, en particulier le flag `RemoveSelfLink=false` qui causait des erreurs de démarrage du service.

## Contexte du problème

Le service K3s ne démarrait pas correctement en raison d'un flag déprécié dans sa configuration. Les journaux du service montraient l'erreur suivante :

```
● k3s.service - Lightweight Kubernetes
     Loaded: loaded (/etc/systemd/system/k3s.service; enabled; vendor preset: enabled)
     Active: activating (auto-restart) (Result: exit-code) since Thu 2025-05-22 11:13:43 CEST; 140ms ago
       Docs: https://k3s.io
    Process: 1026612 ExecStart=/usr/local/bin/k3s server --disable traefik --disable servicelb --disable local-storage --write-kubeconfig-mode 644 --kubelet-arg cgroup-driver=systemd --kubelet-arg feature-gates=GracefulNodeShutdown=false --kube-controller-manager-arg feature-gates=RemoveSelfLink=false (code=exited, status=1/FAILURE)
   Main PID: 1026612 (code=exited, status=1/FAILURE)
```

Le problème était causé par le flag `--kube-controller-manager-arg feature-gates=RemoveSelfLink=false` qui est déprécié dans les versions récentes de Kubernetes (K3s v1.28.6+k3s2).

## Approche précédente (réactive)

Initialement, deux scripts avaient été créés pour résoudre ce problème :

1. `fix-k3s.sh` - Un script qui corrige le problème sur les installations existantes en supprimant le flag déprécié du fichier de service K3s
2. `update-ansible-playbook.sh` - Un script qui met à jour le playbook Ansible pour supprimer le flag déprécié des arguments du serveur K3s

Cette approche était réactive : elle ne corrigeait le problème qu'après qu'il se soit manifesté, ou nécessitait une intervention manuelle pour mettre à jour le playbook.

De plus, le playbook Ansible contenait une tâche pour supprimer le flag déprécié, mais cette tâche n'était exécutée que lorsque le service avait déjà échoué à démarrer, ce qui n'était pas une solution préventive.

## Solution à long terme (proactive)

La solution à long terme mise en place est proactive et comprend les éléments suivants :

### 1. Centralisation de la définition des drapeaux dépréciés

Une nouvelle variable `deprecated_flags` a été ajoutée au playbook Ansible pour centraliser la définition des drapeaux dépréciés :

```yaml
deprecated_flags:
  - name: "RemoveSelfLink=false"
    regexp: "--kube-controller-manager-arg feature-gates=RemoveSelfLink=false"
    replace: ""
  - name: "no-deploy"
    regexp: "--no-deploy ([a-zA-Z0-9-]+)"
    replace: "--disable=\\1"
```

Cette approche permet de facilement ajouter ou modifier la liste des drapeaux dépréciés à l'avenir.

### 2. Vérification proactive des drapeaux dépréciés

Un nouveau bloc de tâches a été ajouté au début du playbook pour vérifier et corriger les drapeaux dépréciés avant même que le service K3s ne soit démarré :

```yaml
- name: Vérification et correction proactive des drapeaux dépréciés
  block:
    - name: Lecture du contenu du fichier de service K3s
      shell: cat /etc/systemd/system/k3s.service
      register: k3s_service_content
      changed_when: false
      ignore_errors: true

    - name: Correction des drapeaux dépréciés
      replace:
        path: /etc/systemd/system/k3s.service
        regexp: "{{ item.regexp }}"
        replace: "{{ item.replace }}"
      loop: "{{ deprecated_flags }}"
      when: k3s_service_content.stdout is defined and item.regexp in k3s_service_content.stdout
      register: k3s_flags_fixed
      ignore_errors: true

    - name: Rechargement du daemon systemd si des drapeaux ont été corrigés
      systemd:
        daemon_reload: yes
      when: k3s_flags_fixed.changed
      ignore_errors: true
```

Cette approche permet de détecter et corriger les drapeaux dépréciés avant qu'ils ne causent des problèmes, évitant ainsi les échecs de démarrage du service.

### 3. Mise à jour des scripts existants

Les scripts existants ont été mis à jour pour refléter la nouvelle approche :

- `fix-k3s.sh` - Ajout d'une note indiquant que le script est destiné aux installations existantes, tandis que les nouvelles installations utilisent l'approche proactive
- `update-ansible-playbook.sh` - Ajout de vérifications pour s'assurer que les tâches de vérification proactive sont présentes dans le playbook

### 4. Documentation complète

Une documentation complète a été créée pour expliquer la solution et fournir des instructions pour la tester :

- `k3s-fix-test-plan.md` - Un plan de test détaillé pour vérifier que la solution fonctionne correctement
- `k3s-fix-long-term-solution.md` (ce document) - Une explication de la solution à long terme

## Avantages de cette approche

1. **Proactive plutôt que réactive** - Les problèmes sont détectés et corrigés avant qu'ils ne causent des erreurs
2. **Centralisée** - La liste des drapeaux dépréciés est définie à un seul endroit et peut être facilement mise à jour
3. **Extensible** - De nouveaux drapeaux dépréciés peuvent être ajoutés facilement à la liste
4. **Robuste** - Inclut une gestion des erreurs pour assurer que le playbook continue même en cas de problèmes
5. **Bien documentée** - Inclut une documentation complète pour comprendre et tester la solution

## Conclusion

Cette solution à long terme assure que les problèmes liés aux drapeaux dépréciés dans K3s sont détectés et corrigés de manière proactive, évitant ainsi les échecs de démarrage du service. Elle est robuste, extensible et bien documentée, ce qui en fait une solution durable pour l'infrastructure LIONS.

En combinant une approche proactive dans le playbook Ansible avec des scripts de correction pour les installations existantes, nous assurons que tous les systèmes, qu'ils soient nouveaux ou existants, fonctionnent correctement sans être affectés par les drapeaux dépréciés.