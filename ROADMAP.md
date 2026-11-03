# Feuille de route

État au 3 novembre 2026. « Implémenté » décrit la présence d’un fonctionnement dans le code ; les essais matériel restent une étape distincte. Les résultats de compilation et de tests établis sont dans le [README](README.md).

## Première version : implémenté

- [x] Projet `SprintTimer.xcodeproj`, cible et nom affiché `SprintTimer`, Swift 6, iOS/iPadOS 17 minimum, package local sans dépendance distante.
- [x] Interface française, modes clair/sombre, dispositions iPhone/iPad et guide intégré.
- [x] Courses nommées, date et heure configurables ; distances prédéfinies et personnalisées.
- [x] Participants avec noms, dossards et couloirs ; classement et correction des résultats.
- [x] Départ manuel, bip programmé, compte à rebours annulable et microphone avec seuil.
- [x] Horloge hôte monotone, décalage de départ réglable et affichage au centième.
- [x] Chronomètre sans caméra avec arrivées manuelles multiples.
- [x] Capture caméra AVFoundation réelle, sélection d’un format et de sa cadence compatible.
- [x] Photo-finish par bandes verticales horodatées et tuiles PNG sans perte, largeur/position réglables avant capture.
- [x] Consultation de la photo : défilement, zoom visuel, curseur, flèches et marquage des participants.
- [x] Vidéo-finish continue H.264, score de mouvement, analyse image par image et ligne d’arrivée.
- [x] Arrivée instantanée estimée : zone réglable, sensibilité, temporisation, réarmement et filtre Vision facultatif.
- [x] Sauvegarde SwiftData et JSON, historique, réouverture, suppression et nouvelle tentative conservant la course précédente.
- [x] Points de reprise de capture et avertissements d’interruption ; finalisation à l’arrêt ou en arrière-plan.
- [x] Export CSV, PDF, aperçu PNG annoté et partage des médias/métadonnées originaux.
- [x] Tests du cœur, tests média/persistance iOS, test d’interface du parcours manuel et GitHub Action de tests/archive sans certificat.
- [x] Documentation d’installation, d’architecture, d’analyse REA et protocole de validation terrain.

## Vérifications logicielles réalisées

- [x] 20 tests du cœur passés localement et en CI.
- [x] 10 tests unitaires iOS et 1 test d’interface passés sur simulateur iPhone 17 Pro / iOS 27 avec Xcode 27.0.
- [x] Extraction de bandes BGRA avec padding, rendu PNG et passage de la limite de 256 bandes vérifiés sur les pixels et dimensions.
- [x] Encodage d’un MOV réel, relecture de trois images à horodatages irréguliers et extraction exacte par temps vérifiés.
- [x] Exports CSV, PDF de 150 participants et PNG/originaux vérifiés par tests automatisés.
- [x] Compilation Debug simulateur et archive Release iPhone non signée réussies.
- [x] Accueil sombre lancé et inspecté sur simulateur iPad (A16) / iOS 27.

CI finale : **Réussie** — [exécution 41591352456](https://github.com/rachid598/sprintJulien/actions/runs/41591352456) : tests Swift et iOS, archive Release et publication des artefacts.

## Validation à terminer avant un usage régulier sur le terrain

- [ ] Installer avec le compte Apple de Julien sur un iPhone réel et compléter [DEVICE_VALIDATION.md](docs/DEVICE_VALIDATION.md).
- [ ] Vérifier l’alignement entre prévisualisation, bande extraite, orientation et tous les couloirs.
- [ ] Mesurer les cadences effectives à 30/60/120/240 i/s selon le matériel et l’éclairage, ainsi que les pertes et l’intervalle maximal.
- [ ] Mesurer les décalages du départ manuel, du microphone et du bip avec une référence connue ; documenter la dérive et l’incertitude.
- [ ] Valider les détections instantanées : passages isolés, concurrents rapprochés, mouvement de fond et changements de lumière.
- [ ] Évaluer mémoire, stockage, température et consommation lors de captures répétées et de 120 secondes.
- [ ] Vérifier les permissions refusées, interruptions, appels, verrouillage, manque de stockage et réouverture après arrêt brutal.
- [ ] Exporter un IPA signé lorsque l’équipe Apple et les profils adaptés sont disponibles. L’installation par **Run** reste le parcours recommandé pour Julien.

## Parité issue de l’analyse approfondie de la référence

La [carte des interfaces](docs/INTERFACES.md) établit des options présentes dans les ressources commerciales ; leurs corps de méthodes restent protégés dans cet IPA.

- [x] Examiner les 170 fichiers NIB, leurs variantes et les catalogues graphiques.
- [x] Installer et vérifier ipsw ; faire fonctionner Hopper via REA ; rendre les captures PNG iOS lisibles.
- [ ] Correction du départ manuel sur une courbe audio conservée (Hand+Mic).
- [ ] Analyse vidéo Dual avec deux images voisines et repères L/R.
- [ ] Pause/reprise de capture et début automatique configurable.
- [ ] Réglages de départ press/release, signal et commandes plus complets.
- [ ] Tri de marquage, passages intermédiaires et options d’export supplémentaires.
- [ ] Comparaison réelle des parcours de l’original sur un iPhone accessible.

## Améliorations prioritaires

- [ ] Capture photo source plus large ou vidéo source facultative pour réextraire des bandes d’une autre largeur ou position après la course. Le zoom actuel ne fait pas ce traitement.
- [ ] Export graphique réalisé hors du chemin d’interface autant que possible, avec progression et annulation.
- [ ] Gestion plus fine de la pression thermique, du débit disque et des réglages d’exposition ; adaptation explicite de la cadence.
- [ ] Capture vidéo sélective autour du mouvement avec tampon préalable. La version actuelle conserve une vidéo continue et son indice de mouvement.
- [ ] Détection du franchissement du torse par suivi, associée à une mesure de fiabilité. Le filtre Vision actuel confirme seulement une présence humaine.
- [ ] Import et restauration d’un ensemble de fichiers de course exportés ; récupération plus robuste d’une vidéo interrompue.
- [ ] Réglage du sens d’affichage de la photo, réglage du cadrage/zoom optique et options de départ automatique de la capture.
- [ ] Validation sur plusieurs modèles iPhone/iPad et versions iOS stables ; enrichissement de l’accessibilité et des parcours au clavier.

## Fonctions avancées

- [ ] Import CSV des participants, avec aperçu et validation du format.
- [ ] Passages intermédiaires et tours pour un même participant.
- [ ] Départ distant depuis un deuxième iPhone et synchronisation des horloges avec estimation de l’erreur.
- [ ] Compagnon Apple Watch et commandes de départ/capture.
- [ ] Export groupé de plusieurs courses et formats d’échange supplémentaires.

Aucune date ni précision chiffrée n’est promise pour ces fonctions. Une synchronisation entre appareils ou un algorithme de franchissement automatique devra être évalué séparément, sans déduire son exactitude des seuls tests de calcul.
