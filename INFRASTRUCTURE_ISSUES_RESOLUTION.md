# Résolution des Problèmes d'Infrastructure LIONS

## Problèmes Identifiés

Après analyse du code et des logs d'erreur, j'ai identifié plusieurs problèmes dans le déploiement de l'infrastructure LIONS :

1. **Registry Docker** : Problèmes de probe de santé (erreur 401 Unauthorized)
2. **PostgreSQL** : Échec du déploiement avec une erreur de variable non définie
3. **Ollama** : Pod en état d'erreur (CrashLoopBackOff) avec un problème de permission
4. **Traefik** : Non accessible sur les ports standard 80 et 443

## Solutions Appliquées

### 1. Correction de l'Erreur de Variable Non Définie dans PostgreSQL

Le problème se situait dans le fichier `lions-infrastructure/ansible/roles/postgres/tasks/deploy.yml` où la tâche "Affichage du statut de la réplication" tentait d'accéder à `replication_check.stdout` même lorsque la variable `replication_check` n'était pas définie ou n'avait pas d'attribut `stdout`.

**Solution** : J'ai modifié les conditions pour vérifier l'existence de la variable et de son attribut avant d'y accéder :

```yaml
- name: Affichage du statut de la réplication
  debug:
    msg: "Statut de la réplication PostgreSQL: {{ replication_check.stdout }}"
  when: replication_check is defined and replication_check.stdout is defined

- name: Avertissement si la réplication n'est pas configurée correctement
  debug:
    msg: "AVERTISSEMENT: La réplication PostgreSQL n'est pas configurée correctement. Vérifiez les logs pour plus d'informations."
  when: postgres_ha_enabled | bool and pods_info_after_init.resources | length > 1 and replication_check is defined and replication_check is failed
```

### 2. Résolution des Problèmes de Probe de Santé de la Registry

Les probes de santé de la registry échouent avec une erreur 401 Unauthorized car ils tentent d'accéder à un endpoint protégé par authentification.

**Solution** : Le template de déploiement de la registry (`lions-infrastructure/ansible/roles/registry/templates/deployment.yml.j2`) est déjà correctement configuré pour utiliser des probes TCP au lieu de probes HTTP :

```yaml
readinessProbe:
  tcpSocket:
    port: http
  initialDelaySeconds: 10
  timeoutSeconds: 5
  periodSeconds: 10
livenessProbe:
  tcpSocket:
    port: http
  initialDelaySeconds: 20
  timeoutSeconds: 5
  periodSeconds: 10
```

Pour appliquer ces changements au déploiement existant, il faut redéployer la registry :

```bash
kubectl delete deployment -n registry registry
ansible-playbook /lions-infrastructure-automated-depl/lions-infrastructure/ansible/playbooks/deploy-infrastructure-services.yml --extra-vars "target_env=development" --tags registry
```

### 3. Résolution des Problèmes de Permission d'Ollama

Le pod Ollama est en état d'erreur CrashLoopBackOff avec le message d'erreur :
```
Couldn't find '/.ollama/id_ed25519'. Generating new private key.
Error: could not create directory mkdir /.ollama: permission denied
```

**Solution** : Le template de déploiement d'Ollama (`lions-infrastructure/ansible/roles/ollama/templates/deployment.yml.j2`) est déjà correctement configuré avec les variables d'environnement et les montages de volume nécessaires :

```yaml
env:
  - name: OLLAMA_HOME
    value: "/var/lib/ollama"
  - name: OLLAMA_MODELS
    value: "/var/lib/ollama/models"

volumeMounts:
  - name: data-volume
    mountPath: /var/lib/ollama
```

Pour appliquer ces changements au déploiement existant, il faut redéployer Ollama :

```bash
kubectl delete deployment -n ollama-development ollama
ansible-playbook /lions-infrastructure-automated-depl/lions-infrastructure/ansible/playbooks/deploy-infrastructure-services.yml --extra-vars "target_env=development" --tags ollama
```

### 4. Accessibilité de Traefik sur les Ports 80 et 443

Traefik n'est pas accessible sur les ports standard 80 et 443, mais sur le port NodePort 30080.

**Explication** : Dans une installation K3s standard, Traefik est déployé en tant que service de type NodePort, ce qui signifie qu'il est exposé sur des ports élevés (comme 30080) plutôt que sur les ports standard (80/443). Ceci est le comportement attendu pour un déploiement Kubernetes sur un seul nœud.

**Solutions possibles** :

1. **Configurer un port-forwarding** : Rediriger le trafic des ports 80/443 vers les ports NodePort de Traefik :
   ```bash
   sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 30080
   sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 30443
   ```

2. **Configurer Traefik pour utiliser HostNetwork** : Modifier la configuration de Traefik pour qu'il utilise directement les interfaces réseau de l'hôte :
   ```yaml
   # Dans le fichier de configuration de Traefik
   spec:
     hostNetwork: true
   ```

3. **Utiliser MetalLB** : Configurer MetalLB pour fournir des services de type LoadBalancer qui peuvent être exposés sur les ports standard.

## Recommandations pour Éviter ces Problèmes à l'Avenir

1. **Ajouter des Vérifications de Variables** : Toujours vérifier l'existence des variables et de leurs attributs avant d'y accéder dans les playbooks Ansible.

2. **Utiliser des Probes TCP pour les Services Authentifiés** : Pour les services qui nécessitent une authentification, utiliser des probes TCP au lieu de probes HTTP pour éviter les erreurs 401.

3. **Configurer Correctement les Chemins de Stockage** : S'assurer que les applications conteneurisées utilisent des chemins avec les permissions appropriées, en particulier pour les applications qui écrivent des données.

4. **Documentation Claire sur l'Exposition des Services** : Documenter clairement comment les services sont exposés (NodePort, LoadBalancer, etc.) et quels ports sont utilisés.

5. **Tests Automatisés** : Mettre en place des tests automatisés pour vérifier que les déploiements fonctionnent correctement avant de les mettre en production.

## Conclusion

Les problèmes identifiés ont été résolus ou expliqués. La plupart des problèmes étaient liés à des configurations qui n'étaient pas appliquées aux déploiements existants, plutôt qu'à des erreurs dans les templates eux-mêmes. En redéployant les services avec les configurations correctes, ces problèmes devraient être résolus.