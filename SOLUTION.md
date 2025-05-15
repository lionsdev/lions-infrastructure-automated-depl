# Solution pour l'erreur de redémarrage lors de l'exécution locale

## Problème identifié

Lors de l'exécution du script d'installation `./lions-infrastructure/scripts/install.sh --environment development`, une erreur se produit à l'étape "Redémarrage si nécessaire après mise à jour" :

```
fatal: [contabo-vps]: FAILED! => {"changed": false, "elapsed": 0, "msg": "Running reboot with local connection would reboot the control node.", "rebooted": false}
```

Cette erreur se produit car le script est exécuté directement sur le VPS cible (avec `ansible_connection: local` dans l'inventaire), et la tâche de redémarrage tente de redémarrer la machine locale, ce qui interromprait l'exécution du script.

## Solution implémentée

La solution consiste à modifier le playbook `init-vps.yml` pour gérer différemment la tâche de redémarrage lorsqu'elle est exécutée avec une connexion locale :

1. La tâche de redémarrage originale a été modifiée pour ne s'exécuter que lorsque la connexion n'est pas locale :
   ```yaml
   - name: Redémarrage si nécessaire après mise à jour (connexion distante)
     reboot:
       reboot_timeout: 600
     when: system_updated.changed and ansible_connection != 'local'
   ```

2. Une nouvelle tâche a été ajoutée pour afficher un message recommandant un redémarrage manuel lorsque la connexion est locale :
   ```yaml
   - name: Notification de redémarrage manuel nécessaire (connexion locale)
     debug:
       msg: "Des mises à jour système ont été appliquées. Un redémarrage manuel du serveur est recommandé après la fin de l'installation."
     when: system_updated.changed and ansible_connection == 'local'
   ```

Ces modifications permettent au script d'installation de continuer son exécution même lorsqu'il est exécuté directement sur le VPS cible, tout en informant l'utilisateur qu'un redémarrage manuel peut être nécessaire après l'installation.

## Comment utiliser cette solution

Aucune action supplémentaire n'est requise de la part de l'utilisateur. Le script d'installation fonctionnera désormais correctement lorsqu'il est exécuté directement sur le VPS cible.

Si des mises à jour système sont appliquées pendant l'installation, un message s'affichera pour recommander un redémarrage manuel après la fin de l'installation.

## Vérification

J'ai vérifié qu'il n'y a pas d'autres tâches dans les playbooks Ansible qui pourraient avoir des problèmes similaires avec l'exécution locale. La tâche de redémarrage dans `init-vps.yml` était la seule qui nécessitait une modification.