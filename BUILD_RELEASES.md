# Création des releases pour lionsctl

Ce document explique comment créer des releases de lionsctl pour différentes plateformes (Windows, Linux, macOS).

## Prérequis

- Go 1.19 installé (voir INSTALL_GO.md)
- Tokens de configuration configurés (voir CONFIG_TOKENS.md)
- Git installé

## Préparation de l'environnement

1. Assurez-vous que votre environnement Go est correctement configuré :
   ```powershell
   go version  # Doit afficher Go 1.19.x
   ```

2. Naviguez vers le répertoire du projet :
   ```powershell
   cd C:\Users\dadyo\PersonalProjects\lions-infrastructure-automated-depl\lionsctl
   ```

3. Assurez-vous que toutes les dépendances sont à jour :
   ```powershell
   go mod tidy
   ```

## Compilation pour Windows (64-bit)

1. Compilez l'exécutable pour Windows :
   ```powershell
   $env:GOOS="windows"; $env:GOARCH="amd64"; go build -o lionsctl.exe
   ```

2. Créez un répertoire pour la release :
   ```powershell
   mkdir -p releases\windows-amd64
   ```

3. Copiez l'exécutable et les fichiers nécessaires :
   ```powershell
   Copy-Item lionsctl.exe releases\windows-amd64\
   Copy-Item ..\README.md releases\windows-amd64\
   Copy-Item ..\INSTALL_GO.md releases\windows-amd64\
   Copy-Item ..\CONFIG_TOKENS.md releases\windows-amd64\
   ```

4. Créez une archive ZIP :
   ```powershell
   Compress-Archive -Path releases\windows-amd64\* -DestinationPath releases\lionsctl-1.0.0-windows-amd64.zip
   ```

## Compilation pour Linux (64-bit)

1. Compilez l'exécutable pour Linux :
   ```powershell
   $env:GOOS="linux"; $env:GOARCH="amd64"; go build -o lionsctl
   ```

2. Créez un répertoire pour la release :
   ```powershell
   mkdir -p releases\linux-amd64
   ```

3. Copiez l'exécutable et les fichiers nécessaires :
   ```powershell
   Copy-Item lionsctl releases\linux-amd64\
   Copy-Item ..\README.md releases\linux-amd64\
   Copy-Item ..\INSTALL_GO.md releases\linux-amd64\
   Copy-Item ..\CONFIG_TOKENS.md releases\linux-amd64\
   ```

4. Créez une archive TAR.GZ (nécessite 7-Zip ou un outil similaire) :
   ```powershell
   # Si vous avez 7-Zip installé
   & 'C:\Program Files\7-Zip\7z.exe' a -ttar releases\temp.tar releases\linux-amd64\*
   & 'C:\Program Files\7-Zip\7z.exe' a -tgzip releases\lionsctl-1.0.0-linux-amd64.tar.gz releases\temp.tar
   Remove-Item releases\temp.tar
   ```

## Compilation pour macOS (64-bit)

1. Compilez l'exécutable pour macOS :
   ```powershell
   $env:GOOS="darwin"; $env:GOARCH="amd64"; go build -o lionsctl
   ```

2. Créez un répertoire pour la release :
   ```powershell
   mkdir -p releases\darwin-amd64
   ```

3. Copiez l'exécutable et les fichiers nécessaires :
   ```powershell
   Copy-Item lionsctl releases\darwin-amd64\
   Copy-Item ..\README.md releases\darwin-amd64\
   Copy-Item ..\INSTALL_GO.md releases\darwin-amd64\
   Copy-Item ..\CONFIG_TOKENS.md releases\darwin-amd64\
   ```

4. Créez une archive TAR.GZ (nécessite 7-Zip ou un outil similaire) :
   ```powershell
   # Si vous avez 7-Zip installé
   & 'C:\Program Files\7-Zip\7z.exe' a -ttar releases\temp.tar releases\darwin-amd64\*
   & 'C:\Program Files\7-Zip\7z.exe' a -tgzip releases\lionsctl-1.0.0-darwin-amd64.tar.gz releases\temp.tar
   Remove-Item releases\temp.tar
   ```

## Vérification des releases

Vérifiez que les archives ont été créées correctement :
```powershell
Get-ChildItem releases\*.zip, releases\*.tar.gz
```

## Publication des releases

Pour publier les releases sur GitHub :

1. Créez un tag Git pour la version :
   ```powershell
   git tag -a v1.0.0 -m "Version 1.0.0"
   git push origin v1.0.0
   ```

2. Créez une nouvelle release sur GitHub :
   - Accédez à https://github.com/lionsdev/lionsctl/releases
   - Cliquez sur "Draft a new release"
   - Sélectionnez le tag v1.0.0
   - Ajoutez un titre et une description pour la release
   - Téléversez les fichiers ZIP et TAR.GZ
   - Publiez la release

## Notes supplémentaires

- Assurez-vous que les exécutables ont les permissions d'exécution appropriées, surtout pour Linux et macOS
- Pour les versions futures, incrémentez le numéro de version dans les noms de fichiers
- Considérez l'automatisation de ce processus avec un script ou un pipeline CI/CD