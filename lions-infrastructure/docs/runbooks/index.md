# Runbooks pour l'Infrastructure LIONS

Ce répertoire contient les procédures opérationnelles (runbooks) pour gérer l'infrastructure LIONS et résoudre les incidents courants.

## Qu'est-ce qu'un runbook ?

Un runbook est un ensemble documenté de procédures pour répondre à des situations spécifiques, comme des incidents, des alertes ou des tâches opérationnelles courantes. Les runbooks fournissent des instructions étape par étape pour diagnostiquer et résoudre les problèmes, ou pour effectuer des tâches de maintenance.

## Comment utiliser ces runbooks

1. Identifiez le problème ou la tâche à accomplir
2. Trouvez le runbook correspondant dans la liste ci-dessous
3. Suivez les étapes décrites dans le runbook
4. Documentez toute déviation ou amélioration potentielle

## Liste des runbooks

### Incidents et alertes

- [Pod en état CrashLoopBackOff](pod-crashloopbackoff.md)
- [Nœud Kubernetes non disponible](node-unavailable.md)
- [Problèmes de certificats TLS](tls-certificate-issues.md)
- [Problèmes de stockage persistant](persistent-storage-issues.md)
- [Haute utilisation CPU/mémoire](high-resource-usage.md)
- [Taux d'erreur élevé](high-error-rate.md)
- [Latence élevée](high-latency.md)

### Tâches opérationnelles

- [Ajout d'un nouveau nœud Kubernetes](add-kubernetes-node.md)
- [Mise à jour de Kubernetes](upgrade-kubernetes.md)
- [Sauvegarde et restauration](backup-restore.md)
- [Rotation des certificats](certificate-rotation.md)
- [Rotation des secrets](secret-rotation.md)
- [Nettoyage des ressources inutilisées](cleanup-unused-resources.md)

### Maintenance des applications

- [Mise à l'échelle d'une application](scale-application.md)
- [Débogage d'une application](debug-application.md)
- [Analyse des logs d'application](analyze-application-logs.md)
- [Vérification de l'état de santé d'une application](check-application-health.md)

## Contribution aux runbooks

Si vous identifiez un problème qui n'est pas couvert par les runbooks existants, ou si vous avez des améliorations à apporter, veuillez suivre ces étapes :

1. Créez un nouveau runbook en utilisant le [modèle de runbook](template.md)
2. Testez le runbook pour vous assurer qu'il résout efficacement le problème
3. Soumettez une pull request avec votre nouveau runbook
4. Mettez à jour l'index pour inclure le nouveau runbook

## Bonnes pratiques pour les runbooks

- Gardez les instructions claires et concises
- Incluez des commandes spécifiques à exécuter
- Documentez les résultats attendus à chaque étape
- Incluez des étapes de vérification pour confirmer que le problème est résolu
- Ajoutez des informations sur la façon de revenir en arrière si nécessaire
- Mettez à jour les runbooks lorsque l'infrastructure change