# Changements pour la synchronisation des URLs de registre

## Résumé

Ce document résume les changements effectués pour synchroniser les URLs du registre Docker entre les projets `lions-infrastructure` et `lionsctl`. L'objectif était d'assurer que toutes les références au registre Docker utilisent un format cohérent qui inclut l'environnement spécifique.

## Problème initial

Il y avait une incohérence dans la façon dont le registre Docker était référencé dans les différents projets :

- Dans `lions-infrastructure`, le registre était déployé avec un domaine spécifique à l'environnement (`registry.{{ deploy_environment }}.lions.dev`), mais certains fichiers utilisaient une URL hardcodée sans le préfixe d'environnement (`registry.lions.dev`).
- Dans `lionsctl`, le registre était référencé avec différentes URLs, ce qui créait des confusions et des erreurs lors du déploiement d'applications.

## Changements effectués

### 1. Mise à jour des templates de déploiement

Les templates de déploiement suivants ont été mis à jour pour utiliser le format d'URL de registre spécifique à l'environnement :

- `ansible/roles/notification-service/templates/deployment.yml.j2`
- `ansible/roles/primefaces/templates/deployment.yml.j2`
- `ansible/roles/primereact/templates/deployment.yml.j2`
- `ansible/roles/quarkus/templates/deployment.yml.j2`

Format utilisé :
```yaml
image: "registry.{{ app_environment }}.lions.dev/{{ app_name }}:{{ app_version }}"
```

### 2. Mise à jour du playbook de déploiement d'application

Le playbook `ansible/playbooks/deploy-application.yml` a été mis à jour pour utiliser le format d'URL de registre spécifique à l'environnement :

```yaml
image_name: "registry.{{ environment }}.lions.dev/{{ application_name }}:{{ version }}"
```

### 3. Mise à jour de la documentation et des exemples

Les exemples dans la documentation ont été mis à jour pour utiliser le format d'URL de registre spécifique à l'environnement :

- `applications/templates/angular/README.md`
- `applications/templates/angular/deployment.yaml`

### 4. Création d'un script de test

Un script de test a été créé pour vérifier que les URLs de registre sont correctement synchronisées :

- `scripts/test-registry-urls.sh`

Ce script vérifie que tous les fichiers pertinents utilisent le format d'URL de registre spécifique à l'environnement et teste l'accès au registre.

### 5. Création d'une documentation explicative

Une documentation complète a été créée pour expliquer le format des URLs de registre et comment les utiliser :

- `docs/guides/registry-url-synchronization.md`

## Vérification des changements

Les changements ont été vérifiés en exécutant le script de test `test-registry-urls.sh`, qui a confirmé que tous les fichiers pertinents utilisent désormais le format d'URL de registre spécifique à l'environnement.

## Impact des changements

Ces changements garantissent que :

1. Toutes les références au registre Docker utilisent un format cohérent qui inclut l'environnement spécifique.
2. Les applications peuvent être déployées correctement dans différents environnements sans avoir à modifier manuellement les URLs du registre.
3. La documentation et les exemples reflètent correctement le format des URLs du registre.

## Prochaines étapes

1. **Tests de validation** : Tester le déploiement d'applications dans différents environnements pour s'assurer qu'elles peuvent correctement récupérer les images depuis l'URL du registre appropriée.
2. **Communication aux équipes** : Informer les équipes de développement des changements apportés à l'infrastructure.
3. **Surveillance** : Surveiller les déploiements pendant les prochains jours pour détecter d'éventuels problèmes liés aux modifications.