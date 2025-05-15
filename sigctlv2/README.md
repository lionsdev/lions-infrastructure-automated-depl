# SIGOBE cicd pipepline

**sigctl**  permet de construire et de deployer les applications.

## Installer `sigctl`

Telechager l'executable correspondant au système d'exploitation:

* Linux

  - télécharger le fichier **tar.gz** à la page https://git.dgbf.ci/florent/sigctlv2/releases
  - Extraire sigctl.tar.gz dans le PATH (example. /usr/local/bin)
  `ex: sudo tar -xzvf sigctl-1.0.0-Linux-x86-64.tar.gz -C /usr/local/bin/ sigctl`

* Windows

  - Télécharger le fichier **zip** à la page https://git.dgbf.ci/florent/sigctlv2/releases
  - Décompresser le fichier.
  - Ajouter l'exécutable dans son le PATH `opening Control Panel>System and Security>System>Advanced System Settings`.

  
## Prerequis
 Docker

## Commandes utiles
* `sigctl -h:` Affiche la liste des commandes.

* Configurer une application
  * Initialiser la configuration <br>
    ex: **`sigctl init -n mic-classification-fonctionnelle -c k1 -i`** <br>
    **Paramètres:**<br>
    -n: Le nom de l'application à initialiser<br>
    -c: Le cluster de deploiement (k1 pour le siib et k2 pour sigobe-elab)<br>
    -i: L'application est accessible de l'extérieur (a un ingress) ?<br>
    -v: L'application a un volume ?<br>
  * Supprimer la configuration<br>
    ex: sigctl delete -n mic-classification-fonctionnelle<br>
    **paramètres:**<br>
      -n: Le nom de l'application à initialiser<br>


* Deployer une application<br>
  * ex: **`sigctl pipeline -u http://10.3.4.18:3001/richard/mic-budgetisation-api -b develop -j 17 -e dev -c k2 -m florent.skynet@gmail.com`**<br>
  **Paramètres:**<br>
  -u: URL du repo git de l'application<br>
  -b: La branche à déployer<br>
  -j: La version du JDK 11 ou 17<br>
  -p: Le profile maven à utiliser
  -d: Les propiétés maven au format nom=valeur
  -e: L'environement de deploiement (default, dev, preproduction, debug pour le siib) (prod, preprod, dev, debug pour le sigobe-elab)<br>
  -c: Le cluster de deploiement (k1 pour le siib et k2 pour sigobe-elab)<br>
  -m: La liste des mails qui doivent recevoir la notification (les mails sont séparés par des virgules)<br>
 

