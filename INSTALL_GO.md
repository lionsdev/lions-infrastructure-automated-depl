# Installation de Go 1.19 pour le projet lionsctl

Ce document fournit les instructions pour installer Go 1.19 sur Windows, nécessaire pour compiler et tester le projet lionsctl.

## Téléchargement et installation de Go 1.19

1. Visitez la page de téléchargement des anciennes versions de Go : https://go.dev/dl/

2. Recherchez et téléchargez Go 1.19.x pour Windows (la dernière version de la série 1.19, actuellement 1.19.13)
   - Fichier : `go1.19.13.windows-amd64.msi` pour les systèmes 64-bit

3. Exécutez le fichier MSI téléchargé et suivez les instructions d'installation
   - L'installateur ajoutera automatiquement Go au PATH système
   - L'emplacement d'installation par défaut est `C:\Program Files\Go`

4. Redémarrez votre terminal PowerShell ou invite de commandes pour que les changements de PATH prennent effet

5. Vérifiez l'installation en exécutant :
   ```powershell
   go version
   ```
   Vous devriez voir : `go version go1.19.13 windows/amd64` (ou similaire)

## Configuration de l'environnement Go

1. Créez un répertoire pour votre espace de travail Go (si ce n'est pas déjà fait) :
   ```powershell
   mkdir $HOME\go
   ```

2. Configurez les variables d'environnement Go (optionnel, car l'installateur MSI le fait généralement) :
   - GOPATH : `$HOME\go`
   - Ajoutez `$HOME\go\bin` à votre PATH

3. Vérifiez la configuration en exécutant :
   ```powershell
   go env
   ```

## Compilation du projet lionsctl

Une fois Go installé, vous pouvez compiler le projet lionsctl :

1. Naviguez vers le répertoire du projet :
   ```powershell
   cd C:\Users\dadyo\PersonalProjects\lions-infrastructure-automated-depl\lionsctl
   ```

2. Téléchargez les dépendances :
   ```powershell
   go mod tidy
   ```

3. Compilez le projet :
   ```powershell
   go build
   ```

4. Si la compilation réussit, vous obtiendrez un exécutable `lionsctl.exe` dans le répertoire courant.

## Dépannage

Si vous rencontrez des problèmes lors de l'installation ou de la compilation :

1. Vérifiez que Go est correctement installé et dans votre PATH :
   ```powershell
   where go
   ```

2. Assurez-vous que la version de Go est correcte :
   ```powershell
   go version
   ```

3. Vérifiez les erreurs de compilation et assurez-vous que toutes les dépendances sont disponibles :
   ```powershell
   go mod tidy
   go build -v
   ```

4. Si vous rencontrez des problèmes avec les dépendances, essayez de nettoyer le cache Go :
   ```powershell
   go clean -modcache
   ```