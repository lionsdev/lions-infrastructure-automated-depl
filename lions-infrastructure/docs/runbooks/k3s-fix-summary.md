# Résumé des corrections pour le service K3s

## Problème

Le service K3s ne démarrait pas correctement en raison d'un flag déprécié dans la configuration. Les journaux du service montraient l'erreur suivante :

```
● k3s.service - Lightweight Kubernetes
     Loaded: loaded (/etc/systemd/system/k3s.service; enabled; vendor preset: enabled)
     Active: activating (auto-restart) (Result: exit-code) since Thu 2025-05-22 11:13:43 CEST; 140ms ago
       Docs: https://k3s.io
    Process: 1026612 ExecStart=/usr/local/bin/k3s server --disable traefik --disable servicelb --disable local-storage --write-kubeconfig-mode 644 --kubelet-arg cgroup-driver=systemd --kubelet-arg feature-gates=GracefulNodeShutdown=false --kube-controller-manager-arg feature-gates=RemoveSelfLink=false (code=exited, status=1/FAILURE)
   Main PID: 1026612 (code=exited, status=1/FAILURE)
```

Le problème était causé par le flag `--kube-controller-manager-arg feature-gates=RemoveSelfLink=false` qui est déprécié dans les versions récentes de Kubernetes (K3s v1.28.6+k3s2).

## Solution

Pour résoudre ce problème, nous avons créé trois scripts :

1. `fix-k3s.sh` - Corrige le problème sur le VPS en supprimant le flag déprécié du fichier de service K3s
2. `update-ansible-playbook.sh` - Met à jour le playbook Ansible pour éviter que le problème ne se reproduise lors de futures installations
3. `check-k3s-flags.sh` - Vérifie la présence de flags dépréciés dans la configuration K3s

### 1. Script de correction (fix-k3s.sh)

Ce script effectue les opérations suivantes :
- Arrête le service K3s
- Sauvegarde le fichier de service K3s
- Supprime le flag `RemoveSelfLink=false` du fichier de service
- Recharge la configuration systemd
- Redémarre le service K3s
- Vérifie que le service a démarré correctement

### 2. Script de mise à jour du playbook (update-ansible-playbook.sh)

Ce script met à jour le playbook Ansible pour supprimer le flag `RemoveSelfLink=false` des arguments du serveur K3s, afin d'éviter que le problème ne se reproduise lors de futures installations.

### 3. Script de vérification (check-k3s-flags.sh)

Ce script vérifie la présence de flags dépréciés dans la configuration K3s et affiche un rapport détaillé. Il peut être utilisé pour vérifier que les corrections ont été appliquées correctement.

## Documentation

Nous avons également créé un guide de dépannage complet pour K3s dans `docs/runbooks/k3s-troubleshooting.md`. Ce guide couvre :

1. Le problème spécifique avec le flag `RemoveSelfLink`
2. Les problèmes généraux de démarrage de K3s
3. Les problèmes de connexion à l'API Kubernetes
4. Les problèmes avec les pods système

## Vérification

Pour vérifier que les corrections ont été appliquées correctement, exécutez le script de vérification :

```bash
cd /opt/lions-infrastructure-automated-depl/lions-infrastructure/scripts
sudo chmod +x check-k3s-flags.sh
sudo ./check-k3s-flags.sh
```

Si tout est correct, le script affichera un message indiquant qu'aucun flag déprécié n'a été trouvé et que le service K3s est actif.

## Prévention

Pour éviter que ce problème ne se reproduise, nous avons :

1. Mis à jour le playbook Ansible pour supprimer le flag déprécié
2. Créé un guide de dépannage détaillé
3. Ajouté des scripts de vérification et de correction

## Conclusion

Ces modifications garantissent que le service K3s démarre correctement et que l'infrastructure LIONS fonctionne comme prévu. Les scripts et la documentation fournis permettront de résoudre rapidement tout problème similaire à l'avenir.