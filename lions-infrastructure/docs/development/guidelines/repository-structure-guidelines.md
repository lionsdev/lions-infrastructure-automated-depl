# Directives de structure du dépôt lions-infrastructure

## Introduction

Ce document présente les directives à suivre pour maintenir la structure du dépôt `lions-infrastructure`. Il est destiné à tous les développeurs et opérateurs qui travaillent sur ce dépôt.

## Principes généraux

La structure du dépôt `lions-infrastructure` est basée sur les principes suivants :

1. **Modularité** : Chaque composant doit être aussi indépendant que possible.
2. **Cohérence** : Les conventions de nommage et d'organisation doivent être cohérentes dans tout le dépôt.
3. **Documentation** : Chaque répertoire doit contenir un fichier README.md qui explique son contenu et son utilisation.
4. **Testabilité** : Le code doit être facilement testable, avec des tests automatisés quand c'est possible.
5. **Maintenabilité** : La structure doit faciliter la maintenance et l'évolution du code.

## Structure du dépôt

La structure principale du dépôt est organisée comme suit :

```
lions-infrastructure/
├── ansible/              # Playbooks et rôles Ansible
├── applications/         # Templates et catalogue d'applications
├── docs/                 # Documentation complète
├── environments/         # Configurations spécifiques aux environnements
├── kubernetes/           # Configurations Kubernetes
├── monitoring/           # Configurations de monitoring
├── scripts/              # Scripts d'installation et de maintenance
├── tests/                # Tests automatisés
├── tools/                # Outils de développement et utilitaires
└── .github/              # Workflows CI/CD
```

### Ansible

Le répertoire `ansible` est organisé comme suit :

```
ansible/
├── filter_plugins/       # Plugins de filtres personnalisés
├── inventories/          # Inventaires par environnement
├── library/              # Modules Ansible personnalisés
├── playbooks/            # Playbooks organisés par fonction
│   ├── infrastructure/   # Playbooks d'infrastructure
│   ├── applications/     # Playbooks d'applications
│   ├── maintenance/      # Playbooks de maintenance
│   └── security/         # Playbooks de sécurité
├── roles/                # Rôles organisés par catégorie
│   ├── database/         # Rôles liés aux bases de données
│   ├── web/              # Rôles liés aux applications web
│   ├── tools/            # Rôles liés aux outils
│   └── monitoring/       # Rôles liés au monitoring
├── templates/            # Templates partagés
└── vars/                 # Variables partagées
```

#### Directives pour Ansible

- Chaque playbook doit être placé dans le sous-répertoire approprié selon sa fonction.
- Les rôles doivent être placés dans le sous-répertoire correspondant à leur catégorie.
- Chaque rôle doit suivre la structure standard d'Ansible (defaults, handlers, meta, tasks, templates, vars).
- Les variables spécifiques à un environnement doivent être placées dans le répertoire `environments/<environment>/ansible/`.
- Utilisez le template de playbook fourni dans `docs/templates/playbook-template.yml` pour créer de nouveaux playbooks.

### Applications

Le répertoire `applications` est organisé comme suit :

```
applications/
├── catalog/              # Catalogue d'applications
│   ├── database/         # Applications de base de données
│   ├── web/              # Applications web
│   └── tools/            # Outils et utilitaires
├── templates/            # Templates d'applications
│   ├── angular/
│   ├── primefaces/
│   ├── primereact/
│   └── quarkus/
└── examples/             # Exemples d'applications
```

#### Directives pour Applications

- Les nouvelles applications doivent être ajoutées au catalogue dans le sous-répertoire approprié.
- Les templates d'applications doivent suivre une structure cohérente.
- Chaque template doit inclure un README.md qui explique comment l'utiliser.
- Les exemples d'applications doivent être maintenus à jour avec les dernières versions des templates.

### Kubernetes

Le répertoire `kubernetes` est organisé comme suit :

```
kubernetes/
├── base/                 # Configurations de base
│   ├── autoscaling/
│   ├── cert-manager/
│   ├── logging/
│   ├── namespaces/
│   ├── network-policies/
│   ├── pod-security/
│   ├── rbac/
│   ├── resource-quotas/
│   └── storage-classes/
├── components/           # Composants réutilisables
│   ├── databases/
│   ├── ingress/
│   ├── monitoring/
│   └── security/
├── gitops/               # Configurations GitOps
└── overlays/             # Overlays spécifiques aux environnements
    ├── development/
    ├── staging/
    └── production/
```

#### Directives pour Kubernetes

- Utilisez Kustomize pour composer les configurations.
- Les configurations de base doivent être placées dans le répertoire `base`.
- Les composants réutilisables doivent être placés dans le répertoire `components`.
- Les configurations spécifiques à un environnement doivent être placées dans le répertoire `overlays/<environment>`.
- Utilisez le template de manifest Kubernetes fourni dans `docs/templates/kubernetes-manifest-template.yaml` pour créer de nouveaux manifests.

### Monitoring

Le répertoire `monitoring` est organisé comme suit :

```
monitoring/
├── alerts/               # Configurations d'alertes
│   ├── infrastructure/   # Alertes d'infrastructure
│   ├── applications/     # Alertes d'applications
│   └── security/         # Alertes de sécurité
├── dashboards/           # Tableaux de bord
│   ├── infrastructure/   # Tableaux de bord d'infrastructure
│   ├── applications/     # Tableaux de bord d'applications
│   └── business/         # Tableaux de bord métier
├── exporters/            # Exporters Prometheus
├── grafana/              # Configurations Grafana
├── prometheus/           # Configurations Prometheus
└── slos/                 # Objectifs de niveau de service
```

#### Directives pour Monitoring

- Les alertes doivent être placées dans le sous-répertoire approprié selon leur type.
- Les tableaux de bord doivent être placés dans le sous-répertoire approprié selon leur type.
- Les configurations Prometheus et Grafana doivent être placées dans leurs répertoires respectifs.
- Les SLOs doivent être définis dans le répertoire `slos`.

### Scripts

Le répertoire `scripts` est organisé comme suit :

```
scripts/
├── installation/         # Scripts d'installation
│   ├── local/            # Installation locale
│   └── remote/           # Installation à distance
├── maintenance/          # Scripts de maintenance
│   ├── backup/           # Sauvegarde
│   ├── restore/          # Restauration
│   └── update/           # Mise à jour
├── monitoring/           # Scripts de monitoring
├── security/             # Scripts de sécurité
├── utilities/            # Utilitaires divers
└── logs/                 # Logs des scripts
```

#### Directives pour Scripts

- Les scripts doivent être placés dans le sous-répertoire approprié selon leur fonction.
- Chaque script doit inclure un en-tête avec une description, un auteur, une date et une version.
- Utilisez le template de script fourni dans `docs/templates/script-template.sh` pour créer de nouveaux scripts.
- Les scripts doivent inclure une gestion des erreurs et une journalisation appropriées.
- Les scripts doivent être testés dans le répertoire `tests/scripts`.

### Documentation

Le répertoire `docs` est organisé comme suit :

```
docs/
├── architecture/         # Documentation d'architecture
│   ├── diagrams/         # Diagrammes d'architecture
│   ├── decisions/        # Documents de décisions d'architecture (ADRs)
│   └── patterns/         # Patterns d'architecture utilisés
├── changes/              # Documentation des changements
│   ├── releases/         # Notes de version
│   └── migrations/       # Guides de migration
├── development/          # Documentation pour les développeurs
│   ├── setup/            # Configuration de l'environnement de développement
│   ├── guidelines/       # Directives de développement
│   └── workflows/        # Workflows de développement
├── guides/               # Guides d'utilisation
│   ├── installation/     # Guides d'installation
│   ├── configuration/    # Guides de configuration
│   ├── deployment/       # Guides de déploiement
│   └── troubleshooting/  # Guides de dépannage
├── operations/           # Documentation pour les opérations
│   ├── monitoring/       # Guides de monitoring
│   ├── backup/           # Guides de sauvegarde
│   └── scaling/          # Guides de mise à l'échelle
└── runbooks/             # Runbooks opérationnels
    ├── incidents/        # Gestion des incidents
    ├── maintenance/      # Maintenance planifiée
    └── recovery/         # Procédures de récupération
```

#### Directives pour Documentation

- La documentation doit être écrite en Markdown.
- Chaque document doit avoir un titre, une introduction et une table des matières si nécessaire.
- Les diagrammes doivent être créés avec un outil comme PlantUML ou Mermaid et inclus dans la documentation.
- Les ADRs doivent suivre le format standard (titre, contexte, décision, conséquences).
- Les guides doivent inclure des exemples concrets et des captures d'écran si nécessaire.
- Les runbooks doivent inclure des procédures étape par étape et des commandes spécifiques.

### Tests

Le répertoire `tests` est organisé comme suit :

```
tests/
├── ansible/              # Tests des playbooks et rôles Ansible
├── applications/         # Tests des templates d'applications
├── infrastructure/       # Tests d'infrastructure
├── integration/          # Tests d'intégration
├── kubernetes/           # Tests des configurations Kubernetes
└── scripts/              # Tests des scripts
```

#### Directives pour Tests

- Chaque composant doit avoir des tests associés dans le répertoire approprié.
- Les tests doivent être automatisés autant que possible.
- Les tests doivent être exécutés dans le cadre du pipeline CI/CD.
- Les tests doivent couvrir les cas normaux et les cas d'erreur.
- Les tests d'intégration doivent vérifier que les composants fonctionnent ensemble correctement.

### Environnements

Le répertoire `environments` est organisé comme suit :

```
environments/
├── development/          # Configuration de l'environnement de développement
│   ├── ansible/          # Variables Ansible spécifiques
│   ├── kubernetes/       # Configurations Kubernetes spécifiques
│   └── terraform/        # Configurations Terraform spécifiques
├── staging/              # Configuration de l'environnement de staging
└── production/           # Configuration de l'environnement de production
```

#### Directives pour Environnements

- Les configurations spécifiques à un environnement doivent être placées dans le sous-répertoire approprié.
- Les variables sensibles doivent être gérées avec un outil comme Vault ou des secrets Kubernetes.
- Les différences entre les environnements doivent être documentées.
- Les configurations doivent être testées dans chaque environnement avant d'être déployées en production.

### Outils

Le répertoire `tools` est organisé comme suit :

```
tools/
├── development/          # Outils de développement
│   ├── linters/          # Linters et formateurs de code
│   └── generators/       # Générateurs de code
├── deployment/           # Outils de déploiement
└── validation/           # Outils de validation
```

#### Directives pour Outils

- Les outils doivent être documentés avec des instructions d'utilisation.
- Les outils doivent être testés avant d'être ajoutés au dépôt.
- Les outils doivent être maintenus à jour avec les dernières versions des dépendances.
- Les outils doivent être compatibles avec les systèmes d'exploitation utilisés par l'équipe.

## Conventions de nommage

### Fichiers et répertoires

- Utilisez des noms en minuscules avec des tirets pour séparer les mots (kebab-case).
- Les noms doivent être descriptifs et indiquer clairement le contenu.
- Les fichiers de configuration doivent avoir l'extension appropriée (.yml, .yaml, .json, etc.).
- Les scripts shell doivent avoir l'extension .sh.
- Les fichiers de documentation doivent avoir l'extension .md.

### Variables

- Utilisez des noms en snake_case pour les variables dans les scripts shell et les playbooks Ansible.
- Utilisez des noms en camelCase pour les variables dans les fichiers JSON et JavaScript.
- Les noms doivent être descriptifs et indiquer clairement l'usage de la variable.
- Évitez les abréviations obscures.

### Ressources Kubernetes

- Utilisez des noms en kebab-case pour les ressources Kubernetes.
- Incluez le nom de l'application et le type de ressource dans le nom.
- Utilisez des labels cohérents pour faciliter la sélection et le filtrage.
- Suivez les recommandations de Kubernetes pour les labels (app.kubernetes.io/name, app.kubernetes.io/instance, etc.).

## Workflows de développement

### Ajout de nouvelles fonctionnalités

1. Créez une branche à partir de `develop` avec un nom descriptif (feature/nom-de-la-fonctionnalité).
2. Développez la fonctionnalité en suivant les directives de ce document.
3. Ajoutez des tests pour la nouvelle fonctionnalité.
4. Mettez à jour la documentation si nécessaire.
5. Soumettez une pull request vers `develop`.
6. Après revue et approbation, la pull request sera fusionnée.

### Correction de bugs

1. Créez une branche à partir de `develop` avec un nom descriptif (fix/description-du-bug).
2. Corrigez le bug en suivant les directives de ce document.
3. Ajoutez un test qui reproduit le bug et vérifie la correction.
4. Mettez à jour la documentation si nécessaire.
5. Soumettez une pull request vers `develop`.
6. Après revue et approbation, la pull request sera fusionnée.

### Releases

1. Créez une branche à partir de `develop` avec un nom basé sur la version (release/vX.Y.Z).
2. Effectuez les derniers ajustements et corrections de bugs.
3. Mettez à jour les numéros de version et les notes de version.
4. Soumettez une pull request vers `main`.
5. Après revue et approbation, la pull request sera fusionnée.
6. Créez un tag pour la nouvelle version.
7. Fusionnez `main` vers `develop` pour synchroniser les branches.

## Validation et vérification

### Linting

- Le code YAML doit être validé avec yamllint.
- Les scripts shell doivent être validés avec shellcheck.
- Les playbooks Ansible doivent être validés avec ansible-lint.
- Les manifests Kubernetes doivent être validés avec kubeval.

### Tests

- Les tests unitaires doivent être exécutés avant chaque commit.
- Les tests d'intégration doivent être exécutés dans le pipeline CI/CD.
- Les tests de validation doivent être exécutés avant chaque déploiement en production.

### Revue de code

- Chaque pull request doit être revue par au moins un autre développeur.
- Les commentaires doivent être constructifs et spécifiques.
- Les problèmes identifiés doivent être corrigés avant la fusion.

## Conclusion

En suivant ces directives, nous pouvons maintenir une structure de dépôt cohérente, modulaire et maintenable. Cela facilitera le travail de tous les membres de l'équipe et améliorera la qualité du code.

Si vous avez des questions ou des suggestions d'amélioration pour ces directives, n'hésitez pas à ouvrir une issue ou une pull request.