# Étapes d'implémentation pour résoudre le problème de validation du ContainerManager dans K3s

Ce document fournit les étapes détaillées pour implémenter la solution décrite dans le fichier `CONTAINER_MANAGER_FIX.md`.

## Contexte

Le service K3s échoue au démarrage avec l'erreur suivante :
```
E0520 20:24:48.258398   54392 kubelet.go:1397] "Failed to start ContainerManager" err="system validation failed - wrong number of fields (expected 6, got 7)"
```

Cette erreur est liée à la configuration des cgroups sur le système, qui ne correspond pas à ce que K3s attend.

## Étapes d'implémentation

### 1. Modifier le playbook install-k3s.yml

Ouvrez le fichier `lions-infrastructure/ansible/playbooks/install-k3s.yml` et apportez les modifications suivantes :

#### a. Mettre à jour la tâche "Correction des problèmes système pour K3s"

Localisez la tâche "Correction des problèmes système pour K3s" (vers la ligne 135) et assurez-vous qu'elle contient le code suivant pour la détection et la correction des problèmes de cgroups :

```yaml
- name: Correction des problèmes système pour K3s
  shell: |
    # Fix potential cgroups issues
    if [ ! -d /sys/fs/cgroup/systemd ]; then
      mkdir -p /sys/fs/cgroup/systemd
    fi

    # Ensure proper cgroup configuration
    echo 'GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1"' >> /etc/default/grub || true

    # Fix cgroups v2 issues (for system validation errors)
    if [ -f /sys/fs/cgroup/unified ] || [ -d /sys/fs/cgroup/unified ]; then
      echo "Cgroups v2 detected, applying fixes for system validation errors..."
      mkdir -p /etc/systemd/system/k3s.service.d/
      cat > /etc/systemd/system/k3s.service.d/override.conf << 'EOF'
      [Service]
      Delegate=yes
      KillMode=mixed
      LimitNOFILE=infinity
      LimitNPROC=infinity
      LimitCORE=infinity
      TasksMax=infinity
      EOF
    fi

    # Fix systemd issues
    systemctl daemon-reload
    systemctl reset-failed || true
```

#### b. Mettre à jour la tâche "Réinstallation propre de K3s avec configuration système corrigée"

Localisez la tâche "Réinstallation propre de K3s avec configuration système corrigée" (vers la ligne 164) et mettez à jour la commande d'installation pour inclure les arguments supplémentaires :

```yaml
- name: Réinstallation propre de K3s avec configuration système corrigée
  shell: |
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="{{ k3s_version }}" INSTALL_K3S_EXEC="server --disable traefik --disable servicelb --disable local-storage --write-kubeconfig-mode 644 --kubelet-arg cgroup-driver=systemd --kubelet-arg feature-gates=GracefulNodeShutdown=false --kube-controller-manager-arg feature-gates=RemoveSelfLink=false" sh -
  environment:
    K3S_KUBECONFIG_MODE: "644"
```

#### c. Mettre à jour la condition pour inclure la vérification de l'erreur de validation du système

Localisez la condition qui détermine quand exécuter le bloc de correction (vers la ligne 170) et ajoutez une vérification pour l'erreur "system validation failed" :

```yaml
when: "'--no-deploy' in k3s_service_content.stdout or 'ContainerManager' in k3s_logs.stdout or 'system validation failed' in k3s_logs.stdout"
```

### 2. Modifier le playbook init-vps.yml (optionnel)

Si vous rencontrez toujours des problèmes après avoir modifié le playbook install-k3s.yml, vous pouvez également ajouter une tâche de préparation du système dans le playbook init-vps.yml pour configurer correctement les cgroups avant même l'installation de K3s.

Ouvrez le fichier `lions-infrastructure/ansible/playbooks/init-vps.yml` et ajoutez la tâche suivante à la fin, juste avant la tâche "Vérification de l'état du système après initialisation" :

```yaml
- name: Préparation du système pour K3s (configuration des cgroups)
  shell: |
    # Ensure cgroup v2 compatibility
    if [ -f /sys/fs/cgroup/unified ] || [ -d /sys/fs/cgroup/unified ]; then
      echo "Preparing system for K3s with cgroups v2..."

      # Create systemd directory if it doesn't exist
      if [ ! -d /sys/fs/cgroup/systemd ]; then
        mkdir -p /sys/fs/cgroup/systemd
      fi

      # Update kernel parameters for cgroups
      echo 'GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1"' >> /etc/default/grub || true

      # Apply changes
      if command -v update-grub &> /dev/null; then
        update-grub || true
      fi
    fi
  args:
    executable: /bin/bash
  register: cgroup_prep
  changed_when: false
  ignore_errors: yes
```

## Vérification

Après avoir appliqué ces modifications, exécutez le script d'installation avec la commande suivante :

```bash
sudo ./install.sh --environment development
```

Vérifiez que le service K3s démarre correctement sans l'erreur "Failed to start ContainerManager".

## Dépannage

Si vous rencontrez toujours des problèmes après avoir appliqué ces modifications, voici quelques étapes de dépannage supplémentaires :

1. Vérifiez les journaux K3s pour identifier d'autres erreurs potentielles :
    ```bash
    sudo journalctl -u k3s -n 100
    ```

2. Vérifiez la configuration des cgroups sur le système :
    ```bash
    ls -la /sys/fs/cgroup/
    ```

3. Vérifiez si le système utilise cgroups v1 ou v2 :
    ```bash
    mount | grep cgroup
    ```

4. Si vous utilisez WSL2, assurez-vous que votre fichier .wslconfig est correctement configuré pour prendre en charge les cgroups :
    ```
    [wsl2]
    kernelCommandLine = cgroup_enable=memory swapaccount=1
    ```

5. Essayez de désinstaller complètement K3s et de le réinstaller :
    ```bash
    sudo /usr/local/bin/k3s-uninstall.sh
    ```
   Puis réexécutez le script d'installation.
