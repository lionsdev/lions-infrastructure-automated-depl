# Solution pour le problème des drapeaux dépréciés dans K3s

## Problème identifié

Lors du redémarrage du service K3s, l'erreur suivante apparaît :

```
time="2025-05-18T14:02:26+02:00" level=fatal msg="no-deploy flag is deprecated. Use --disable instead."
```

Cette erreur indique que le format du drapeau `--no-deploy` est déprécié et doit être remplacé par le format `--disable=`.

## Cause du problème

Bien que le fichier de configuration Ansible `install-k3s.yml` utilise déjà le format correct avec `--disable=traefik`, l'erreur persiste. Cela suggère qu'il existe une configuration existante sur le serveur qui utilise encore l'ancien format de drapeau `--no-deploy`.

Le problème vient du fait que même si le fichier `install-k3s.yml` utilise le format correct, le fichier de service systemd existant sur le serveur contient probablement encore l'ancien format. Lorsque K3s est installé, il crée un fichier de service systemd à `/etc/systemd/system/k3s.service` qui contient les arguments de démarrage. Si ce fichier a été créé avec une version antérieure de K3s ou avec une configuration qui utilisait l'ancien format, il continuera à utiliser ce format jusqu'à ce qu'il soit explicitement modifié.

## Solution implémentée

Pour résoudre ce problème, nous avons ajouté une nouvelle fonction `fix_k3s_deprecated_flags()` au script `install.sh` qui :

1. Vérifie l'existence du fichier de service K3s (`/etc/systemd/system/k3s.service`)
2. Si le fichier existe, vérifie s'il contient des drapeaux dépréciés (`--no-deploy`)
3. Si des drapeaux dépréciés sont trouvés, les remplace par le format correct (`--disable=`)
4. Si le fichier de service principal n'existe pas, recherche d'autres fichiers de service K3s dans le répertoire `/etc/systemd/system` et applique la même correction
5. Recharge le daemon systemd après les modifications

Cette fonction est appelée à deux endroits dans le script :

1. Dans la fonction `repair_k3s()` qui est utilisée pour réparer une installation K3s défectueuse
2. Dans la fonction `check_fix_k3s()` qui vérifie l'état du service K3s et propose des options de réparation

## Modifications apportées

### 1. Ajout de la fonction `fix_k3s_deprecated_flags()`

Cette nouvelle fonction vérifie et corrige les drapeaux dépréciés dans la configuration K3s.

### 2. Mise à jour de la fonction `repair_k3s()`

La fonction `repair_k3s()` a été mise à jour pour appeler la nouvelle fonction `fix_k3s_deprecated_flags()` avant de redémarrer le service K3s.

### 3. Mise à jour de la fonction `check_fix_k3s()`

La fonction `check_fix_k3s()` a été mise à jour pour appeler la nouvelle fonction `fix_k3s_deprecated_flags()` même si le service K3s est actif, afin de s'assurer que les drapeaux dépréciés sont corrigés dans tous les cas.

### 4. Amélioration de la commande sed pour la correction des drapeaux dépréciés

La commande sed utilisée pour remplacer les drapeaux dépréciés a été améliorée pour gérer différents formats possibles du drapeau `--no-deploy` :

```bash
sed -i 's/--no-deploy /--disable=/g; s/--no-deploy=/--disable=/g; s/--no-deploy\([[:space:]]\+\)\([[:alnum:]]\+\)/--disable=\2/g' /etc/systemd/system/k3s.service
```

Cette commande gère maintenant les cas suivants :
- `--no-deploy ` (avec un espace) -> `--disable=`
- `--no-deploy=` (avec un signe égal) -> `--disable=`
- `--no-deploy COMPONENT` (avec un espace suivi du nom du composant) -> `--disable=COMPONENT`

### 5. Ajout de ports supplémentaires dans la configuration UFW

Les ports suivants ont été ajoutés à la configuration UFW dans le playbook `init-vps.yml` pour assurer le bon fonctionnement de K3s :

- 10250/tcp - K3s kubelet
- 10251/tcp - K3s kube-scheduler
- 10252/tcp - K3s kube-controller
- 8472/udp - K3s flannel VXLAN
- 4789/udp - K3s flannel VXLAN (alternative)
- 51820/udp - K3s Wireguard
- 51821/udp - K3s Wireguard (alternative)

### 6. Amélioration de la vérification de l'état de UFW

Une tâche supplémentaire a été ajoutée au playbook `init-vps.yml` pour s'assurer que UFW est bien actif après son activation :

```yaml
- name: Vérification que UFW est bien actif
  shell: |
    ufw status | grep -q "Status: active" || (echo 'y' | ufw --force enable)
  register: ufw_status_check
  changed_when: false
  failed_when: false
```

Cette tâche vérifie si UFW est actif et l'active si ce n'est pas le cas, assurant ainsi que le pare-feu est toujours correctement configuré.

## Résultat attendu

Avec ces modifications, le service K3s devrait maintenant démarrer correctement sans l'erreur "no-deploy flag is deprecated". Le service désactivera correctement les composants spécifiés (traefik et servicelb le cas échéant) en utilisant le format de drapeau correct.

## Remarques supplémentaires

Cette solution est robuste car elle :

1. Vérifie l'existence du fichier de service avant de tenter de le modifier
2. Recherche des fichiers de service alternatifs si le fichier principal n'existe pas
3. Vérifie si les drapeaux dépréciés sont présents avant de les remplacer
4. Recharge le daemon systemd après les modifications
5. Est intégrée dans les fonctions de réparation existantes

La solution est également non destructive, car elle ne modifie que les drapeaux dépréciés sans affecter les autres configurations du service K3s.
