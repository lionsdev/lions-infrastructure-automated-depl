# Rapport de correction du service K3s

**Date:** 22 mai 2025  
**Auteur:** Équipe LIONS Infrastructure  
**Version:** 1.0.0

## Résumé exécutif

Ce rapport détaille les actions entreprises pour résoudre un problème critique avec le service K3s dans l'infrastructure LIONS. Le service ne démarrait pas en raison d'un flag déprécié dans sa configuration. Nous avons créé des scripts de correction, mis à jour la documentation, et implémenté des mesures préventives pour éviter que ce problème ne se reproduise.

## Problème identifié

Le service K3s ne démarrait pas et entrait dans une boucle de redémarrage automatique. L'analyse des journaux a révélé que le problème était causé par le flag déprécié `--kube-controller-manager-arg feature-gates=RemoveSelfLink=false` qui n'est plus supporté dans les versions récentes de Kubernetes (K3s v1.28.6+k3s2).

## Impact

L'échec du démarrage de K3s a eu les conséquences suivantes :
- Impossibilité de déployer de nouvelles applications
- Indisponibilité des services existants
- Échec des scripts d'installation automatisée
- Impossibilité d'accéder au tableau de bord Kubernetes

## Solution implémentée

### 1. Scripts de correction

Nous avons créé trois scripts pour résoudre le problème et éviter qu'il ne se reproduise :

#### a. Script de correction immédiate (fix-k3s.sh)

Ce script effectue les opérations suivantes :
- Arrête le service K3s
- Sauvegarde le fichier de service K3s
- Supprime le flag déprécié du fichier de service
- Recharge la configuration systemd
- Redémarre le service K3s
- Vérifie que le service a démarré correctement

```bash
# Extrait du script fix-k3s.sh
echo -e "${GREEN}[INFO]${NC} Suppression du flag RemoveSelfLink=false du fichier de service K3s..."
sed -i 's/--kube-controller-manager-arg feature-gates=RemoveSelfLink=false//' /etc/systemd/system/k3s.service
```

#### b. Script de mise à jour du playbook Ansible (update-ansible-playbook.sh)

Ce script met à jour le playbook Ansible pour supprimer le flag déprécié des arguments du serveur K3s, afin d'éviter que le problème ne se reproduise lors de futures installations.

```bash
# Extrait du script update-ansible-playbook.sh
sed -i 's/--kubelet-arg feature-gates=GracefulNodeShutdown=false --kube-controller-manager-arg feature-gates=RemoveSelfLink=false/--kubelet-arg feature-gates=GracefulNodeShutdown=false/g' "${PLAYBOOK_PATH}"
```

#### c. Script de vérification (check-k3s-flags.sh)

Ce script vérifie la présence de flags dépréciés dans la configuration K3s et affiche un rapport détaillé. Il peut être utilisé pour vérifier que les corrections ont été appliquées correctement et pour détecter d'autres problèmes potentiels.

```bash
# Extrait du script check-k3s-flags.sh
# Liste des flags dépréciés à vérifier
DEPRECATED_FLAGS=(
    "RemoveSelfLink=false"
    "--no-deploy"
)

# Vérification de chaque flag déprécié
for flag in "${DEPRECATED_FLAGS[@]}"; do
    if grep -q "$flag" /etc/systemd/system/k3s.service; then
        echo -e "${RED}[ALERTE]${NC} Flag déprécié trouvé: ${flag}"
        FOUND_DEPRECATED_FLAGS=true
    else
        echo -e "${GREEN}[OK]${NC} Flag déprécié non trouvé: ${flag}"
    fi
done
```

### 2. Documentation

Nous avons créé une documentation complète pour aider les administrateurs à résoudre ce problème et d'autres problèmes similaires à l'avenir :

#### a. Guide de dépannage K3s (k3s-troubleshooting.md)

Ce guide couvre :
- Le problème spécifique avec le flag `RemoveSelfLink`
- Les problèmes généraux de démarrage de K3s
- Les problèmes de connexion à l'API Kubernetes
- Les problèmes avec les pods système

#### b. Résumé des corrections (k3s-fix-summary.md)

Ce document résume les corrections apportées et explique comment vérifier qu'elles ont été appliquées correctement.

### 3. Modifications du playbook Ansible

Nous avons vérifié que le playbook Ansible `install-k3s.yml` ne contenait pas le flag déprécié dans la définition de la variable `k3s_server_args`. Nous avons également confirmé que le playbook contient déjà une tâche pour supprimer ce flag s'il est présent dans le fichier de service K3s.

## Tests et validation

Pour valider notre solution, nous avons effectué les tests suivants :

1. Exécution du script `fix-k3s.sh` sur le VPS
2. Vérification que le service K3s démarre correctement
3. Exécution du script `check-k3s-flags.sh` pour confirmer l'absence de flags dépréciés
4. Vérification de l'accès à l'API Kubernetes
5. Déploiement d'une application test pour confirmer que l'infrastructure fonctionne correctement

## Mesures préventives

Pour éviter que ce problème ne se reproduise, nous avons mis en place les mesures suivantes :

1. Ajout de vérifications automatiques des flags dépréciés dans le script d'installation
2. Création d'un script de vérification qui peut être exécuté régulièrement
3. Documentation détaillée du problème et de sa solution
4. Mise à jour du playbook Ansible pour supprimer automatiquement les flags dépréciés

## Leçons apprises

Cette expérience nous a permis de tirer plusieurs leçons importantes :

1. **Importance des mises à jour de documentation** : Les flags dépréciés doivent être documentés et supprimés rapidement.
2. **Tests automatisés** : Des tests automatisés pour vérifier la configuration du service auraient pu détecter ce problème plus tôt.
3. **Surveillance proactive** : Une surveillance plus proactive des journaux système aurait permis de détecter ce problème avant qu'il n'affecte les utilisateurs.

## Recommandations

Sur la base de cette expérience, nous recommandons les actions suivantes :

1. **Mise en place d'une surveillance proactive** : Configurer des alertes pour détecter les échecs de démarrage des services critiques.
2. **Tests réguliers** : Exécuter régulièrement le script `check-k3s-flags.sh` pour détecter les problèmes potentiels.
3. **Revue des playbooks Ansible** : Effectuer une revue complète des playbooks Ansible pour identifier et supprimer d'autres flags dépréciés.
4. **Formation** : Former l'équipe sur l'importance de suivre les changements dans les versions de Kubernetes et de mettre à jour la configuration en conséquence.

## Conclusion

Grâce aux actions entreprises, le service K3s fonctionne maintenant correctement, et l'infrastructure LIONS est pleinement opérationnelle. Les scripts et la documentation créés permettront de résoudre rapidement tout problème similaire à l'avenir et d'éviter que ce problème spécifique ne se reproduise.

---

## Annexes

### A. Scripts créés

- `fix-k3s.sh` - Script de correction du service K3s
- `update-ansible-playbook.sh` - Script de mise à jour du playbook Ansible
- `check-k3s-flags.sh` - Script de vérification des flags dépréciés

### B. Documentation créée

- `k3s-troubleshooting.md` - Guide de dépannage K3s
- `k3s-fix-summary.md` - Résumé des corrections

### C. Références

- [Documentation K3s](https://docs.k3s.io/)
- [Notes de version Kubernetes 1.28](https://kubernetes.io/blog/2023/08/15/kubernetes-v1-28-release/)
- [Guide des flags dépréciés Kubernetes](https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/)