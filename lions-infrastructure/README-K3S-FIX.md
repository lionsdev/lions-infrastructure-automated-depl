# Correction du service K3s - Instructions d'application

## Contexte

Le service K3s ne démarre pas correctement en raison d'un flag déprécié (`--kube-controller-manager-arg feature-gates=RemoveSelfLink=false`) dans sa configuration. Ce document fournit des instructions pour appliquer la solution sur le VPS.

## Fichiers créés

Nous avons créé les fichiers suivants pour résoudre le problème :

### Scripts

1. `scripts/fix-k3s.sh` - Script pour corriger le problème sur le VPS
2. `scripts/update-ansible-playbook.sh` - Script pour mettre à jour le playbook Ansible
3. `scripts/check-k3s-flags.sh` - Script pour vérifier la présence de flags dépréciés

### Documentation

1. `docs/runbooks/k3s-troubleshooting.md` - Guide de dépannage K3s
2. `docs/runbooks/k3s-fix-summary.md` - Résumé des corrections
3. `docs/runbooks/k3s-fix-report.md` - Rapport détaillé de la correction

## Instructions d'application

### 1. Préparation

Connectez-vous au VPS via SSH :

```bash
ssh root@176.57.150.2 -p 225
```

Naviguez vers le répertoire du projet :

```bash
cd /opt/lions-infrastructure-automated-depl
```

### 2. Application de la correction

Rendez les scripts exécutables :

```bash
chmod +x lions-infrastructure/scripts/fix-k3s.sh
chmod +x lions-infrastructure/scripts/update-ansible-playbook.sh
chmod +x lions-infrastructure/scripts/check-k3s-flags.sh
```

Exécutez le script de vérification pour confirmer le problème :

```bash
./lions-infrastructure/scripts/check-k3s-flags.sh
```

Si le script détecte le flag déprécié, exécutez le script de correction :

```bash
./lions-infrastructure/scripts/fix-k3s.sh
```

Mettez à jour le playbook Ansible pour éviter que le problème ne se reproduise :

```bash
./lions-infrastructure/scripts/update-ansible-playbook.sh
```

### 3. Vérification

Exécutez à nouveau le script de vérification pour confirmer que le problème est résolu :

```bash
./lions-infrastructure/scripts/check-k3s-flags.sh
```

Vérifiez que le service K3s est actif :

```bash
systemctl status k3s
```

Vérifiez que l'API Kubernetes est accessible :

```bash
kubectl get nodes
```

### 4. Déploiement d'une application test

Pour confirmer que l'infrastructure fonctionne correctement, déployez une application test :

```bash
kubectl create deployment nginx-test --image=nginx
kubectl expose deployment nginx-test --port=80 --type=NodePort
```

Vérifiez que le pod est en cours d'exécution :

```bash
kubectl get pods
```

Nettoyez après le test :

```bash
kubectl delete deployment nginx-test
kubectl delete service nginx-test
```

## Résolution des problèmes

Si vous rencontrez des problèmes lors de l'application de la solution, consultez le guide de dépannage K3s :

```bash
less lions-infrastructure/docs/runbooks/k3s-troubleshooting.md
```

Pour plus d'informations sur les corrections apportées, consultez le rapport détaillé :

```bash
less lions-infrastructure/docs/runbooks/k3s-fix-report.md
```

## Conclusion

Après avoir appliqué ces corrections, le service K3s devrait démarrer correctement et l'infrastructure LIONS devrait être pleinement opérationnelle. Les scripts et la documentation créés permettront de résoudre rapidement tout problème similaire à l'avenir.

Pour toute question ou problème, contactez l'équipe d'infrastructure LIONS à infrastructure@lions.dev.