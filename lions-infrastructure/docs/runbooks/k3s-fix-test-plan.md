# Plan de test pour la correction des drapeaux dépréciés dans K3s

## Objectif

Ce document décrit les étapes à suivre pour tester la solution mise en place pour corriger les problèmes liés aux drapeaux dépréciés dans K3s, en particulier le flag `RemoveSelfLink=false`.

## Prérequis

- Accès au VPS avec les privilèges root
- Ansible installé sur la machine locale ou sur le VPS
- Le dépôt lions-infrastructure cloné sur la machine locale ou sur le VPS

## Scénarios de test

### 1. Test de la vérification proactive dans le playbook Ansible

Ce test vérifie que les nouvelles tâches de vérification proactive fonctionnent correctement lors d'une nouvelle installation ou d'une mise à jour.

#### Étapes

1. Créer un fichier de service K3s avec le flag déprécié :
   ```bash
   sudo bash -c 'cat > /etc/systemd/system/k3s.service.test << EOF
   [Unit]
   Description=Lightweight Kubernetes
   Documentation=https://k3s.io
   
   [Service]
   ExecStart=/usr/local/bin/k3s server --disable traefik --disable servicelb --disable local-storage --write-kubeconfig-mode 644 --kubelet-arg cgroup-driver=systemd --kubelet-arg feature-gates=GracefulNodeShutdown=false --kube-controller-manager-arg feature-gates=RemoveSelfLink=false
   
   [Install]
   WantedBy=multi-user.target
   EOF'
   ```

2. Renommer le fichier pour simuler une installation existante :
   ```bash
   sudo mv /etc/systemd/system/k3s.service.test /etc/systemd/system/k3s.service
   ```

3. Exécuter le playbook Ansible :
   ```bash
   cd /opt/lions-infrastructure-automated-depl/lions-infrastructure
   ansible-playbook -i ansible/inventories/development/hosts.yml ansible/playbooks/install-k3s.yml
   ```

4. Vérifier que le flag a été supprimé du fichier de service :
   ```bash
   grep -q "RemoveSelfLink=false" /etc/systemd/system/k3s.service || echo "Flag supprimé avec succès"
   ```

#### Résultat attendu

Le playbook doit s'exécuter sans erreur et le flag `RemoveSelfLink=false` doit être supprimé du fichier de service K3s.

### 2. Test du script fix-k3s.sh

Ce test vérifie que le script `fix-k3s.sh` fonctionne correctement sur une installation existante.

#### Étapes

1. Créer un fichier de service K3s avec le flag déprécié :
   ```bash
   sudo bash -c 'cat > /etc/systemd/system/k3s.service.test << EOF
   [Unit]
   Description=Lightweight Kubernetes
   Documentation=https://k3s.io
   
   [Service]
   ExecStart=/usr/local/bin/k3s server --disable traefik --disable servicelb --disable local-storage --write-kubeconfig-mode 644 --kubelet-arg cgroup-driver=systemd --kubelet-arg feature-gates=GracefulNodeShutdown=false --kube-controller-manager-arg feature-gates=RemoveSelfLink=false
   
   [Install]
   WantedBy=multi-user.target
   EOF'
   ```

2. Renommer le fichier pour simuler une installation existante :
   ```bash
   sudo mv /etc/systemd/system/k3s.service.test /etc/systemd/system/k3s.service
   ```

3. Exécuter le script fix-k3s.sh :
   ```bash
   cd /opt/lions-infrastructure-automated-depl/lions-infrastructure/scripts
   sudo ./fix-k3s.sh
   ```

4. Vérifier que le flag a été supprimé du fichier de service :
   ```bash
   grep -q "RemoveSelfLink=false" /etc/systemd/system/k3s.service || echo "Flag supprimé avec succès"
   ```

#### Résultat attendu

Le script doit s'exécuter sans erreur et le flag `RemoveSelfLink=false` doit être supprimé du fichier de service K3s.

### 3. Test du script update-ansible-playbook.sh

Ce test vérifie que le script `update-ansible-playbook.sh` met correctement à jour un ancien playbook Ansible.

#### Étapes

1. Créer une copie du playbook Ansible sans les nouvelles tâches :
   ```bash
   cd /opt/lions-infrastructure-automated-depl/lions-infrastructure
   cp ansible/playbooks/install-k3s.yml ansible/playbooks/install-k3s.yml.old
   ```

2. Modifier la copie pour supprimer les tâches de vérification proactive et la variable deprecated_flags :
   ```bash
   sed -i '/deprecated_flags:/,/replace: "--disable=\\1"/d' ansible/playbooks/install-k3s.yml.old
   sed -i '/# Vérification proactive des drapeaux dépréciés/,/ignore_errors: true/d' ansible/playbooks/install-k3s.yml.old
   ```

3. Exécuter le script update-ansible-playbook.sh sur la copie :
   ```bash
   cd /opt/lions-infrastructure-automated-depl/lions-infrastructure/scripts
   PLAYBOOK_PATH="../ansible/playbooks/install-k3s.yml.old" ./update-ansible-playbook.sh
   ```

4. Vérifier que les tâches de vérification proactive ont été ajoutées :
   ```bash
   grep -q "Vérification et correction proactive des drapeaux dépréciés" ../ansible/playbooks/install-k3s.yml.old && echo "Tâches ajoutées avec succès"
   ```

#### Résultat attendu

Le script doit s'exécuter sans erreur et les tâches de vérification proactive doivent être ajoutées au playbook Ansible.

## Vérification du service K3s

Après chaque test, vérifiez que le service K3s démarre correctement :

```bash
sudo systemctl start k3s
sudo systemctl status k3s
```

Le service doit être en état "active (running)" et non "activating (auto-restart)".

## Nettoyage

Après les tests, nettoyez les fichiers créés :

```bash
sudo rm -f /etc/systemd/system/k3s.service.test
sudo rm -f /opt/lions-infrastructure-automated-depl/lions-infrastructure/ansible/playbooks/install-k3s.yml.old
```

## Conclusion

Ces tests permettent de vérifier que la solution mise en place pour corriger les problèmes liés aux drapeaux dépréciés dans K3s fonctionne correctement dans différents scénarios. Si tous les tests passent, la solution peut être considérée comme robuste et prête à être déployée en production.