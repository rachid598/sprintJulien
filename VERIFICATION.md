# Rapport de vérification de SprintTimer

Rapport du 3 novembre 2026. Version applicative archivée : [`8a1f4da`](https://github.com/rachid598/sprintJulien/commit/8a1f4dab54b8544d16e9bd963c8f2150fa62949f). Le dépôt privé cible est [rachid598/sprintJulien](https://github.com/rachid598/sprintJulien). Le projet est une application native originale, avec capture AVFoundation, traitement d’images, stockage et exports implémentés. Les vérifications décrites ci-dessous distinguent le logiciel exécuté sur simulateur des essais qui exigent un capteur réel.

## Résultat de la livraison logicielle

Le projet **SprintTimer.xcodeproj**, le schéma partagé et la cible **SprintTimer** sont présents. L’application affiche **SprintTimer** sous l’icône. L’identifiant `org.sprintjulien.SprintTimer` est distinct de celui de la référence commerciale. Le code est en Swift 6, avec iOS/iPadOS 17 minimum et un package Swift local, sans dépendance distante ni chemin propre à un Mac.

La compilation Debug pour simulateur et l’archive Release pour appareil ont réussi. La dernière archive, construite depuis la source `8a1f4da`, a terminé avec `ARCHIVE SUCCEEDED` ; son absence de signature a été vérifiée avec `codesign`. **31 tests distincts ont passé : 20 tests du cœur, 10 tests unitaires iOS et 1 test d’interface.** La CI du commit `33abc6b` valide les mêmes sources applicatives, avec publication vérifiée des résultats et de l’archive. Une archive non signée est disponible localement dans `dist/SprintTimer.xcarchive`, avec une copie ZIP livrée séparément du dépôt. **`dist/SprintTimer.ipa` n’a pas été produit et aucun IPA installable n’est revendiqué.** Le premier contrôle ne permettait pas de conclure à l’absence de certificat : un contrôle avec l’accès système a depuis détecté une identité Apple Development. Aucun profil de provisionnement local compatible n’a été trouvé ; l’export signé reste à vérifier.

**CI finale :** **Réussie** — [exécution 41591352456](https://github.com/rachid598/sprintJulien/actions/runs/41591352456) : tests Swift et iOS, archive Release et publication des artefacts. La [GitHub Action iOS](https://github.com/rachid598/sprintJulien/actions/workflows/ios.yml) exécute les tests et l’archive sans certificat.

## Fonctionnalités livrées

| Domaine | Comportement implémenté | Vérification et limite |
| --- | --- | --- |
| Courses et participants | Nom, date/heure, distance, noms, dossards, couloirs, classement et modification des résultats | Modèles et persistance testés ; parcours manuel exécuté sur simulateur |
| Chronométrage | Horloge monotone hôte, départ, arrêt, décalage et nouvelle tentative distincte | Tests de calcul ; le parcours manuel sauvegarde et rouvre une arrivée |
| Départs | Manuel, bip programmé, compte à rebours et seuil microphone horodaté par échantillon | Implémentation réelle ; latence acoustique et microphone non validés sur appareil |
| Photo-finish | Extraction de bandes verticales caméra, tuiles PNG sans perte, temps réel de chaque bande et consultation/marquage | Extraction BGRA, padding, pixels, tuiles et exports testés avec des buffers synthétiques |
| Vidéo-finish | Enregistrement H.264 continu, chronologie des images et marquage par temps | MOV réellement encodé et relu dans les tests ; la caméra réelle reste à tester |
| Instant Finish | Variation de luminance dans une zone, seuil, temporisation, réarmement, filtre Vision facultatif et vidéo de contrôle | Détecteur testé sur données synthétiques ; performance de détection réelle non mesurée |
| Historique | SwiftData, copie JSON, points de reprise et réouverture | Sauvegarde, mise à jour, récupération et suppression testées |
| Exports | CSV UTF-8, PDF paginé, PNG annoté et partage des médias/métadonnées originaux | Fichiers et contenu vérifiés par tests iOS ; feuille de partage implémentée |
| Interface | Français, clair/sombre, iPhone/iPad, guide intégré | Parcours manuel iPhone automatisé ; accueil iPad sombre lancé et inspecté |

La capture et le chronomètre ont des départs distincts : il faut toucher **Capturer les arrivées** à l’approche des concurrents. Les données fictives restent cantonnées aux tests ; l’application utilise AVFoundation pour les modes caméra.

## Tests exécutés

| Ensemble | Environnement | Résultat |
| --- | --- | --- |
| `SprintTimerCoreTests` | Swift 6 sur Mac, et étape dédiée en CI | 20 tests, 0 échec |
| `BuildSmokeTests` | Simulateur iPhone 17 Pro, iOS 27, Xcode 27.0 | 1 test, 0 échec |
| `ExportTests` | Même environnement iOS | 3 tests, 0 échec |
| `MediaPersistenceTests` | Même environnement iOS | 4 tests, 0 échec |
| `VideoFinishEngineTests` | Même environnement iOS | 2 tests, 0 échec |
| `SprintTimerUITests` | Même environnement iOS | 1 test, 0 échec |

Les 10 tests unitaires iOS et le test d’interface ont terminé avec `TEST SUCCEEDED`. Les journaux locaux de la validation comprennent `work/ios-delivery-test.log` et le résultat Xcode `DeliveryTests.xcresult` dans l’espace de travail de livraison ; les exécutions GitHub Actions produisent leurs propres journaux et artefacts.

Vérifications significatives :

- Le moteur photo reçoit de vrais `CVPixelBuffer` BGRA synthétiques, avec padding de ligne. Les PNG produits sont relus pour vérifier pixels, dimensions et ordre des bandes. Le passage à une deuxième tuile après 256 bandes est couvert.
- Le moteur vidéo reçoit trois images synthétiques aux PTS 1000,000, 1000,020 et 1000,070 s. Le MOV est réellement écrit avec `AVAssetWriter`, puis relu avec `AVAssetReader`. Les dimensions, le nombre d’images et les écarts irréguliers sont vérifiés. `AVAssetImageGenerator` extrait ensuite les images aux temps relatifs 0,000, 0,020 et 0,070 s, à tolérance de recherche nulle.
- Les exports vérifient les accents et guillemets du CSV, la présence de 150 participants dans un PDF à plusieurs pages, le PNG et les fichiers originaux avec métadonnées.
- Le test d’interface crée une course manuelle, démarre, marque une arrivée, arrête, ferme et rouvre la course depuis l’historique ; il vérifie le maintien du temps et du résultat.

Le marquage vidéo est désactivé pendant le décodage ou si l’image retournée diffère de plus de 3 ms du temps demandé. Ce contrôle porte sur la correspondance image–horodatage du fichier et ne constitue pas une mesure de précision physique.

### Reproduire les vérifications

Depuis la racine du dépôt, avec Swift 6 :

```sh
swift test --package-path Packages/SprintTimerCore
```

Avec Xcode complet et un simulateur iPhone disponible :

```sh
bash scripts/ci-ios.sh
```

Le script choisit un simulateur disponible, lance les tests iOS puis crée une archive Release non signée. Ses produits sont placés dans `.build-ci/`, dont `TestResults.xcresult`, les journaux et `SprintTimer-unsigned.xcarchive.zip`. Aucun certificat Apple n’est requis pour cette vérification.

Pour compiler seulement la version destinée à un appareil :

```sh
xcodebuild -project SprintTimer.xcodeproj -scheme SprintTimer \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath dist/SprintTimer.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive
```

## Captures de l’application exécutée

Les fichiers suivants proviennent des simulateurs ; ils ne sont pas des maquettes ni des images d’un essai caméra sur iPhone réel.

| Capture | Observation |
| --- | --- |
| [Course iPhone rouverte](docs/screenshots/iphone-race-reopened.png) | Chronomètre arrêté, arrivée manuelle persistée et nouvelle tentative disponible |
| [Accueil iPad sombre](docs/screenshots/ipad-home-dark.png) | Application lancée sur simulateur iPad (A16) / iOS 27 ; accueil et création de course visibles |

## Précision et matériel : non mesurés

Aucun iPhone réel utilisable n’était disponible pour les essais. La caméra, le microphone, le cadrage réel, la cadence 240 i/s, la température, l’autonomie, la charge mémoire sur le terrain et la précision temporelle globale n’ont pas été validés sur appareil.

L’application utilise les horodatages caméra convertis vers l’horloge hôte ; les lacunes ne sont pas remplacées par des temps calculés à cadence constante. Cette méthode ne supprime pas l’exposition, le rolling shutter, les erreurs d’alignement, les occultations, la latence sonore ou la réaction humaine. L’affichage au centième et les décimales du CSV ne prouvent aucune exactitude physique chiffrée.

**Limites de précision mesurées : aucune mesure terrain disponible.** Le [protocole de validation sur appareil](docs/DEVICE_VALIDATION.md) permet de relever cadence, pertes, décalage, dérive, faux positifs, interruptions et ressources avec une référence connue. Les résultats restent à remplir après de vrais essais.

## Fonctions incomplètes ou différées

- Recalcul de la photo avec une autre largeur ou position de bande après capture : absent. Le zoom est visuel ; le mode photo conserve les bandes, sans vidéo pleine source.
- Vidéo déclenchée sélectivement par mouvement : absente. La version actuelle enregistre en continu et conserve les scores de mouvement.
- Franchissement automatique du torse et identification des personnes : absents. Instant Finish estime l’entrée d’un mouvement dans une zone ; le filtre Vision confirme une présence.
- Départ distant, synchronisation entre appareils, Apple Watch, tours, import CSV et restauration des originaux partagés : à développer.
- Récupération après arrêt brutal : partielle. Les tuiles finalisées peuvent être récupérées ; un MOV non finalisé peut rester illisible. Le passage normal en arrière-plan arrête la course et finalise les données disponibles.

La [feuille de route](ROADMAP.md) sépare les améliorations fonctionnelles des validations matérielles restantes.

## Fichiers livrés et installation par Julien

| Élément | Chemin relatif au dépôt |
| --- | --- |
| Projet Xcode | `SprintTimer.xcodeproj` |
| Sources iOS | `SprintTimer/` |
| Cœur et tests Swift | `Packages/SprintTimerCore/` |
| Tests unitaires / interface iOS | `SprintTimerTests/` et `SprintTimerUITests/` |
| Archive locale pour appareil | `dist/SprintTimer.xcarchive` — non signée, exclue de Git |
| IPA installable | `dist/SprintTimer.ipa` — **non produit** |
| Export signé sur le Mac de Julien | `scripts/export-ipa.sh`, avec sa propre équipe Apple |

Le dépôt étant privé, Julien doit disposer d’un accès GitHub à celui-ci avant le clonage. Il peut ensuite ouvrir le projet, choisir son équipe dans **Signing & Capabilities**, brancher son appareil, le sélectionner et utiliser **Run**. Aucun changement du code source n’est nécessaire. Si l’identifiant initial n’est pas enregistrable par son équipe, il peut choisir un identifiant unique dans les réglages de signature tout en gardant le nom **SprintTimer**.

Les instructions détaillées et les solutions aux problèmes de signature sont dans [INSTALLATION.md](INSTALLATION.md). Une archive non signée n’est pas installable directement ; Run effectue la compilation et la signature avec les accès de Julien.

## Référence et documentation

L’analyse de la documentation officielle et de l’IPA fourni a été menée avec [REA](https://github.com/morluto/rea). Le [rapport de référence](docs/REFERENCE_ANALYSIS.md) indique les preuves, sources et inconnues. Aucun code ou ressource graphique propriétaire de l’application commerciale n’est publié dans ce dépôt.

La documentation comprend [README.md](README.md), [INSTALLATION.md](INSTALLATION.md), [ARCHITECTURE.md](ARCHITECTURE.md), [ROADMAP.md](ROADMAP.md) et le présent rapport. Les données de test média sont synthétiques ; les captures d’interface montrent l’application développée dans ce dépôt exécutée sur simulateur.
