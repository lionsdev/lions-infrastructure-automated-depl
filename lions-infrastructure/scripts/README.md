# Explication de la correction du script `restructure-repository.sh`

## Problème initial

Le script `restructure-repository.sh` présentait une erreur de syntaxe à la ligne 1371 près d'un token `}` inattendu. Cette erreur était causée par un problème dans la gestion des heredocs (documents intégrés) dans le script.

## Cause technique

Le problème se situait dans la section où le script crée un template de script (lignes 1307-1481). Le script utilisait un heredoc avec le délimiteur `EOF` non quoté :

```bash
cat > "${PROJECT_ROOT}/scripts/templates/common/script-template.sh" << EOF
```

Avec un heredoc non quoté, Bash effectue l'expansion des variables et des substitutions de commandes à l'intérieur du heredoc. Cela posait problème car le template lui-même contenait des variables et des substitutions de commandes qui ne devaient pas être évaluées lors de la création du template, mais seulement lors de l'exécution du template.

En particulier, la ligne problématique était :

```bash
rm -f /tmp/$(basename "$0" .sh)-temp-*
```

Cette ligne était interprétée lors de la création du template, ce qui provoquait l'erreur de syntaxe.

## Solution

La solution a été d'utiliser un heredoc quoté en ajoutant des quotes simples autour du délimiteur :

```bash
cat > "${PROJECT_ROOT}/scripts/templates/common/script-template.sh" << 'EOFSCRIPT'
```

Avec un heredoc quoté, Bash traite tout le contenu comme du texte littéral, sans effectuer d'expansion de variables ou de substitutions de commandes. Cela permet de créer correctement le template avec les variables et substitutions de commandes intactes.

## Comment utiliser le script corrigé

Le script original a été corrigé et peut maintenant être utilisé normalement :

```bash
cd lions-infrastructure/scripts
chmod +x restructure-repository.sh
./restructure-repository.sh [options]
```

Options disponibles :
- `-h, --help` : Affiche l'aide
- `-v, --verbose` : Mode verbeux
- `-d, --dry-run` : Mode simulation (n'effectue aucune action)
- `-b, --backup-dir DIR` : Spécifie le répertoire de sauvegarde

Exemple d'utilisation en mode simulation :
```bash
./restructure-repository.sh --dry-run --verbose
```

## Pourquoi un nouveau fichier a été créé

Lors de la correction, un fichier `restructure-repository-fixed.sh` a été créé comme sauvegarde et pour tester la solution avant de modifier le fichier original. Maintenant que le fichier original a été corrigé, vous pouvez utiliser directement `restructure-repository.sh` et supprimer le fichier `restructure-repository-fixed.sh` si vous le souhaitez.

```bash
# Pour supprimer le fichier de sauvegarde si vous n'en avez plus besoin
rm restructure-repository-fixed.sh
```