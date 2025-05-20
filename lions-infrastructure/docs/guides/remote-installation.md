# Guide d'installation à distance de l'infrastructure LIONS

## Introduction

Ce guide explique comment installer l'infrastructure LIONS directement sur le VPS cible, plutôt que d'exécuter le script d'installation depuis votre machine locale. Cette approche est **fortement recommandée** car elle évite plusieurs problèmes de compatibilité, notamment avec WSL2 (Windows Subsystem for Linux).

## Problèmes connus avec l'installation depuis WSL2

L'exécution du script d'installation depuis WSL2 peut entraîner plusieurs problèmes:

1. **Erreurs de démarrage du ContainerManager**: K3s peut rencontrer des problèmes avec le gestionnaire de conteneurs dans WSL2.
2. **Problèmes avec les cgroups**: WSL2 a une implémentation limitée des cgroups Linux, ce qui peut causer des erreurs comme `system validation failed - wrong number of fields`.
3. **Connexions refusées à l'API Kubernetes**: L'API Kubernetes peut ne pas être accessible correctement.
4. **Service K3s qui ne démarre jamais complètement**: Le service K3s peut rester bloqué en état "activating" sans jamais atteindre l'état "active".

## Solution: Installation directe sur le VPS

Pour éviter ces problèmes, nous recommandons d'exécuter le script d'installation directement sur le VPS cible. Deux méthodes sont proposées:

### Méthode 1: Utilisation du script d'installation à distance

Nous fournissons un script `remote-install.sh` qui automatise le processus d'installation à distance:

1. Assurez-vous que vous pouvez vous connecter au VPS via SSH avec une clé SSH.
2. Exécutez le script `remote-install.sh` avec les paramètres appropriés:

```bash
cd lions-infrastructure/scripts
chmod +x remote-install.sh
./remote-install.sh --host <IP_DU_VPS> --port <PORT_SSH> --user <UTILISATEUR_SSH> --environment <ENVIRONNEMENT>
```

Exemple:
```bash
./remote-install.sh --host 176.57.150.2 --port 225 --user root --environment development
```

Le script va:
- Se connecter au VPS via SSH
- Installer Git si nécessaire
- Cloner le dépôt sur le VPS
- Exécuter le script d'installation directement sur le VPS

### Méthode 2: Installation manuelle sur le VPS

Si vous préférez effectuer l'installation manuellement:

1. Connectez-vous au VPS via SSH:
   ```bash
   ssh -p <PORT_SSH> <UTILISATEUR_SSH>@<IP_DU_VPS>
   ```

2. Installez Git si nécessaire:
   ```bash
   apt-get update && apt-get install -y git
   ```

3. Clonez le dépôt:
   ```bash
   git clone https://github.com/votre-repo/lions-infrastructure-automated-depl.git
   ```

4. Exécutez le script d'installation:
   ```bash
   cd lions-infrastructure-automated-depl/lions-infrastructure/scripts
   chmod +x install.sh
   ./install.sh --environment <ENVIRONNEMENT>
   ```

## Avantages de l'installation directe sur le VPS

- **Élimination des problèmes de compatibilité WSL2**: Tous les problèmes liés à WSL2 sont évités.
- **Simplification de l'architecture réseau**: Plus de problèmes de connexion refusée ou de ports inaccessibles.
- **Performances améliorées**: Pas de surcharge due à la virtualisation WSL2.
- **Utilisation directe des ressources du VPS**: Les services s'exécutent directement sur la machine où ils doivent être déployés.

## Dépannage

Si vous rencontrez des problèmes lors de l'installation à distance:

1. **Problèmes de connexion SSH**:
   - Vérifiez que vous pouvez vous connecter manuellement au VPS avec `ssh -p <PORT_SSH> <UTILISATEUR_SSH>@<IP_DU_VPS>`.
   - Assurez-vous que votre clé SSH est correctement configurée.

2. **Problèmes de clonage du dépôt**:
   - Vérifiez que l'URL du dépôt est correcte.
   - Assurez-vous que la branche spécifiée existe.

3. **Problèmes d'installation**:
   - Consultez les logs d'installation sur le VPS dans le répertoire `lions-infrastructure/scripts/logs/`.
   - Vérifiez que le VPS dispose de ressources suffisantes (CPU, RAM, espace disque).

## Conclusion

L'installation directe sur le VPS est la méthode recommandée pour déployer l'infrastructure LIONS. Elle évite de nombreux problèmes de compatibilité et simplifie le processus d'installation.

Pour toute question ou problème, veuillez consulter la documentation complète ou contacter l'équipe de support.