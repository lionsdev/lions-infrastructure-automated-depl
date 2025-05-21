# Résolution du problème de démarrage du service K3s lié au flag RemoveSelfLink

## Problème initial

Le service K3s ne démarrait pas correctement et affichait une erreur avec un code de sortie 1 (FAILURE). L'erreur se produisait lors de l'exécution de la commande suivante :

```
/usr/local/bin/k3s server --disable traefik --disable servicelb --disable local-storage --write-kubeconfig-mode 644 --kubelet-arg cgroup-driver=systemd --kubelet-arg feature-gates=GracefulNodeShutdown=false --kube-controller-manager-arg feature-gates=RemoveSelfLink=false (code=exited, status=1/FAILURE)
```

## Cause identifiée

Une incohérence a été détectée entre les arguments du serveur K3s définis dans le playbook Ansible et ceux utilisés dans le fichier de service systemd. La variable `k3s_server_args` dans le playbook ne contenait pas le flag `--kube-controller-manager-arg feature-gates=RemoveSelfLink=false`, alors que ce flag était présent dans le fichier de service systemd.

Cette incohérence a été introduite lors de la résolution d'un problème précédent lié au ContainerManager de K3s, où le flag a été ajouté au fichier de service mais pas à la variable `k3s_server_args` dans le playbook.

## Modifications effectuées

1. Mise à jour de la variable `k3s_server_args` dans le fichier `install-k3s.yml` pour inclure le flag manquant :

```yaml
k3s_server_args: "server --disable traefik --disable servicelb --disable local-storage --write-kubeconfig-mode 644 --kubelet-arg cgroup-driver=systemd --kubelet-arg feature-gates=GracefulNodeShutdown=false --kube-controller-manager-arg feature-gates=RemoveSelfLink=false"
```

2. Mise à jour de la commande d'installation d'urgence de K3s à la ligne 338 pour inclure le même flag :

```yaml
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="{{ k3s_version }}" INSTALL_K3S_EXEC="server --disable traefik --disable servicelb --disable local-storage --write-kubeconfig-mode 644 --kubelet-arg cgroup-driver=systemd --kubelet-arg feature-gates=GracefulNodeShutdown=false --kube-controller-manager-arg feature-gates=RemoveSelfLink=false" sh -
```

## Importance du flag `--kube-controller-manager-arg feature-gates=RemoveSelfLink=false`

Ce flag est important car il désactive la fonctionnalité `RemoveSelfLink` qui peut causer des problèmes de compatibilité avec certaines applications ou opérateurs Kubernetes qui dépendent des liens `selfLink` dans les réponses de l'API.

La fonctionnalité `RemoveSelfLink` a été activée par défaut dans les versions récentes de Kubernetes, mais elle peut causer des problèmes avec certaines applications ou opérateurs qui dépendent encore des liens `selfLink` dans les réponses de l'API.

En désactivant cette fonctionnalité avec `feature-gates=RemoveSelfLink=false`, nous assurons une meilleure compatibilité avec les applications existantes qui pourraient dépendre des liens `selfLink`.

## Résultat attendu

Avec ces modifications, le service K3s devrait maintenant démarrer correctement sans erreur. Tous les arguments du serveur K3s sont cohérents dans l'ensemble du playbook et correspondent à ceux utilisés dans le fichier de service systemd.

La commande `systemctl status k3s` devrait maintenant afficher que le service est actif et en cours d'exécution, sans erreur de démarrage.

## Conclusion

Cette solution assure la cohérence entre la configuration définie dans le playbook Ansible et celle utilisée dans le fichier de service systemd. Elle permet de résoudre le problème de démarrage du service K3s en s'assurant que tous les arguments nécessaires sont correctement spécifiés.