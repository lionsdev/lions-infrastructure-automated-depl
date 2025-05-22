# Guide de synchronisation des URLs de registre

## Introduction

Ce guide explique comment les URLs du registre Docker sont synchronisées entre les projets `lions-infrastructure` et `lionsctl`. Il fournit également des instructions pour tester et vérifier cette synchronisation.

## Format des URLs de registre

Les URLs du registre Docker suivent désormais un format standardisé qui inclut l'environnement spécifique :

```
registry.<environment>.lions.dev
```

Où `<environment>` peut être :
- `development` (environnement de développement)
- `staging` (environnement de préproduction)
- `production` (environnement de production)

Exemples :
- `registry.development.lions.dev` (pour l'environnement de développement)
- `registry.staging.lions.dev` (pour l'environnement de préproduction)
- `registry.production.lions.dev` (pour l'environnement de production)

## Fichiers concernés

Les URLs de registre sont utilisées dans plusieurs fichiers du projet :

1. **Templates de déploiement** :
   - `ansible/roles/notification-service/templates/deployment.yml.j2`
   - `ansible/roles/primefaces/templates/deployment.yml.j2`
   - `ansible/roles/primereact/templates/deployment.yml.j2`
   - `ansible/roles/quarkus/templates/deployment.yml.j2`

2. **Playbooks Ansible** :
   - `ansible/playbooks/deploy-application.yml`

3. **Documentation et exemples** :
   - `applications/templates/angular/README.md`
   - `applications/templates/angular/deployment.yaml`

4. **Configuration lionsctl** :
   - `lionsctl/lionsctl/base/values.yaml`
   - `lionsctl/cmd/lionsctl.yaml`

## Vérification de la synchronisation

Un script de test a été créé pour vérifier que les URLs de registre sont correctement synchronisées :

```bash
cd lions-infrastructure/scripts
chmod +x test-registry-urls.sh
./test-registry-urls.sh
```

Ce script effectue les vérifications suivantes :
1. Vérifie que tous les templates de déploiement utilisent le format d'URL de registre spécifique à l'environnement
2. Vérifie que la documentation utilise le format d'URL de registre correct
3. Teste l'accès au registre en utilisant l'URL spécifique à l'environnement

## Utilisation des URLs de registre

### Dans les commandes Docker

Pour construire et pousser une image vers le registre :

```bash
# Construction de l'image
docker build -t registry.<environment>.lions.dev/<application>:<version> .

# Envoi de l'image au registre
docker push registry.<environment>.lions.dev/<application>:<version>
```

### Dans les fichiers de déploiement Kubernetes

Pour référencer une image dans un déploiement Kubernetes :

```yaml
containers:
- name: mon-application
  image: registry.<environment>.lions.dev/<application>:<version>
```

### Dans les templates Ansible

Dans les templates Ansible, utilisez les variables d'environnement :

```yaml
image: "registry.{{ app_environment }}.lions.dev/{{ app_name }}:{{ app_version }}"
```

## Résolution des problèmes

Si vous rencontrez des problèmes avec les URLs de registre :

1. **Erreur de connexion au registre** : Vérifiez que le registre est déployé et accessible dans l'environnement spécifié.
2. **Erreur d'authentification** : Assurez-vous d'être connecté au registre avec les bonnes informations d'identification.
3. **Image introuvable** : Vérifiez que l'image a été poussée vers le bon registre avec le bon tag.

Pour plus d'informations, consultez les logs du registre :

```bash
kubectl logs -n registry -l app=registry
```

## Conclusion

La synchronisation des URLs de registre entre les projets `lions-infrastructure` et `lionsctl` garantit une cohérence dans la façon dont les images Docker sont référencées et utilisées dans l'infrastructure LIONS. Cette standardisation facilite la gestion des images dans différents environnements et améliore la maintenabilité du code.