# Installer SprintTimer sur l’iPhone de Julien

Le dépôt s’appelle `sprintJulien`. Le projet Xcode, la cible et le nom affiché de l’application sont **SprintTimer**. L’application utilise un identifiant original : `org.sprintjulien.SprintTimer`.

## Préparer le Mac

- Disposer d’un Mac compatible avec Xcode 16 ou plus récent, avec le SDK iOS 17 ou plus récent et Swift 6.
- Installer Xcode depuis le Mac App Store ou [Apple Developer](https://developer.apple.com/xcode/). Ouvrir Xcode une première fois, accepter la licence et installer le composant iOS proposé.
- Le dépôt est privé : le propriétaire doit donner accès au compte GitHub de Julien dans **Settings → Collaborators**. Julien doit accepter l’invitation.
- Dans Xcode, ouvrir **Settings → Accounts**, ajouter son propre compte Apple et sélectionner son équipe. Le compte Apple du propriétaire du dépôt n’est pas nécessaire.

## Récupérer le projet

Depuis Terminal, dans le dossier de votre choix :

```sh
git clone https://github.com/rachid598/sprintJulien.git
cd sprintJulien
open SprintTimer.xcodeproj
```

Il est également possible de cloner le dépôt depuis Xcode. L’authentification GitHub doit être faite avec le compte autorisé de Julien. Aucun jeton n’est inclus dans le projet.

Le projet contient son package Swift local `Packages/SprintTimerCore` : il n’y a ni CocoaPods, ni Carthage, ni téléchargement de dépendance à effectuer. Aucun générateur de projet n’est nécessaire pour l’ouvrir et le compiler.

## Installer sur l’iPhone

1. Brancher l’iPhone au Mac, le déverrouiller et accepter **Faire confiance à cet ordinateur** sur l’iPhone.
2. Sur iOS 16 ou plus récent, activer **Réglages → Confidentialité et sécurité → Mode développeur**, puis redémarrer et confirmer si iOS le demande.
3. Dans Xcode, sélectionner le projet bleu **SprintTimer**, puis la cible **SprintTimer** et l’onglet **Signing & Capabilities**.
4. Laisser **Automatically manage signing** activé. Choisir **Team : l’équipe Apple de Julien**. Aucune équipe n’est imposée par le dépôt.
5. Si Xcode indique que le Bundle Identifier est déjà enregistré par une autre équipe, remplacer `org.sprintjulien.SprintTimer` dans ce même écran par un identifiant personnel unique, par exemple `fr.julien.sprinttimer`. C’est un réglage de projet : aucun fichier Swift n’a besoin d’être modifié.
6. Dans la barre supérieure de Xcode, sélectionner le schéma **SprintTimer** puis l’iPhone de Julien comme destination.
7. Cliquer sur **Run ▶︎** (`⌘R`). La première compilation peut être plus longue.
8. Si iOS demande de faire confiance au développeur, ouvrir **Réglages → Général → VPN et gestion de l’appareil**, sélectionner l’identité Apple de Julien et autoriser l’application.
9. Ouvrir SprintTimer et accepter l’accès à la caméra pour les modes d’arrivée. Le microphone est demandé lors de l’activation du départ au microphone.

Un compte Apple personnel gratuit peut suffire pour **Run** sur ses propres appareils, avec les limites d’Apple et une signature qui expire après sept jours. Il faut alors rebrancher l’iPhone et relancer **Run**. L’export et la distribution d’un IPA peuvent exiger une adhésion Apple Developer payante et un profil adapté. Apple précise ces limites dans son [guide des comptes et équipes personnelles](https://developer.apple.com/help/account/basics/about-your-developer-account).

## Première course sur le terrain

Stabiliser l’iPhone sur un support, l’aligner sur la ligne d’arrivée et vérifier le cadrage de tous les couloirs. Préparer les participants et les réglages, déclencher le chronomètre, puis enregistrer les arrivées. Après la course, analyser les images et attribuer les temps aux participants avant de partager les résultats. Se reporter au README pour le parcours correspondant à chaque mode.

Les mesures réelles dépendent du capteur, de la fréquence effectivement atteinte, du placement, de l’éclairage et du départ. Le nombre de décimales affiché ne certifie pas la précision. Valider le dispositif sur un essai connu avant son utilisation en EPS.

## Résoudre les problèmes de signature Xcode

| Message ou problème | Solution |
| --- | --- |
| `Signing for SprintTimer requires a development team` | Cible SprintTimer → Signing & Capabilities → sélectionner l’équipe de Julien. |
| `Failed to register bundle identifier` | Choisir un identifiant unique dans Signing & Capabilities. Conserver le nom de l’application SprintTimer. |
| `No profiles for … were found` | Activer la signature automatique, vérifier la connexion réseau, puis rechoisir l’équipe. Xcode crée le profil pour l’appareil connecté. |
| `Developer Mode disabled` | Activer le mode développeur sur l’iPhone, redémarrer et confirmer. |
| `Untrusted Developer` ou application refusée par iOS | Faire confiance à l’identité de Julien dans Réglages → Général → VPN et gestion de l’appareil. |
| Profil expiré ou application qui ne s’ouvre plus après quelques jours | Rebrancher l’iPhone puis relancer Run avec le même compte Apple. |
| Appareil absent ou `Preparing debugger support` | Déverrouiller l’iPhone, accepter la confiance et attendre la préparation. Mettre Xcode à jour si la version iOS de l’appareil est plus récente que son support. |
| `xcodebuild requires Xcode` dans Terminal | Sélectionner Xcode dans Settings → Locations → Command Line Tools, ou passer `DEVELOPER_DIR` pour une commande seulement. |
| Caméra ou microphone refusé | Réglages de l’iPhone → Apps → SprintTimer → autoriser le service. Le simulateur ne valide pas la caméra réelle. |

Ne transmettre ni certificat, ni clé privée, ni profil, ni mot de passe Apple dans le dépôt. Chacun utilise ses propres accès dans Xcode.

Documentation Apple : [exécuter une application sur simulateur ou appareil](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) et [activer le mode développeur](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

## Tests et compilation en ligne de commande

Le cœur portable peut être testé sans simulateur :

```sh
swift test --package-path Packages/SprintTimerCore
```

Pour les tests iOS et l’archive Release **non signée**, avec un simulateur iPhone installé :

```sh
bash scripts/ci-ios.sh
```

Avec plusieurs installations de Xcode, sélectionner celle à utiliser uniquement pour cette commande :

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash scripts/ci-ios.sh
```

Le script enregistre les résultats dans `.build-ci/`. La GitHub Action **iOS** exécute les tests Swift, les tests simulateur et l’archive sans certificat Apple. Une archive non signée prouve la compilation pour appareil ; elle n’est pas installable telle quelle sur un iPhone.

## Exporter `dist/SprintTimer.ipa`

La méthode recommandée pour Julien reste **Run** dans Xcode. Pour distribuer un IPA, utiliser **Product → Archive → Distribute App** avec sa propre identité et un profil autorisant les appareils destinataires.

Un script équivalent est fourni pour une équipe déjà configurée dans Xcode :

```sh
SPRINTTIMER_TEAM_ID=VOTRE_EQUIPE bash scripts/export-ipa.sh
```

La valeur `VOTRE_EQUIPE` est l’identifiant de l’équipe Apple de l’utilisateur ; elle n’est pas fournie par le dépôt. Le script utilise la méthode d’export `debugging`. Les autres méthodes récentes disponibles sont `release-testing` et `app-store-connect`, via `SPRINTTIMER_EXPORT_METHOD`. Les droits Apple associés restent nécessaires. Les comptes personnels gratuits peuvent devoir utiliser **Run** au lieu d’un export IPA.

Le script n’annonce de livraison que si Xcode produit réellement `dist/SprintTimer.ipa`. En l’absence d’identité de signature et de profil adaptés, aucun IPA installable ne peut être généré. Le projet et l’archive non signée restent utilisables pour compiler et signer sur le Mac de Julien.
