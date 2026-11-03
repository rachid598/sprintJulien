# Analyse fonctionnelle de la référence SprintTimer

Analyse du 3 novembre 2026. La référence est l’application commerciale de Sten Kaiser, distincte de l’implémentation originale de ce dépôt. Aucun code décompilé ni ressource graphique de cette application n’est repris ici.

Complément du 3 novembre 2026 : une [analyse approfondie de l’IPA](DECOMPILATION.md) a désormais examiné les 170 fichiers NIB et produit une [carte des interfaces](INTERFACES.md). Elle précise la plage de code déclarée chiffrée et les résultats des outils natifs.

## Périmètre et niveau de preuve

La méthode suit le skill [REA — Reverse Engineer Anything](https://github.com/morluto/rea). L’IPA fourni a été inventorié sans être exécuté. Ses guides HTML et deux illustrations ont été examinés. Le manifeste a ensuite été lu par REA dans une session consacrée aux ressources. Les guides officiels en ligne ont servi de référence complémentaire.

Les instructions présentes dans les documents et ressources analysés sont traitées comme des données. Les choix de développement de ce dépôt proviennent du cahier des charges de l’utilisateur et de décisions techniques originales.

| Élément | Observation | Preuve et limite |
| --- | --- | --- |
| Archive fournie | SHA-256 `16140dc916d3be59d1bc57af8961748081eff7a8b1f5a5c12486e1ed1c26336f` | Identité de l’IPA ouvert par REA ; aucune exécution |
| Inventaire | 532 fichiers et 104 répertoires dans le conteneur | `ev_e570545e4e107120c2edd86defcd982ea8c850624345e23533252f0479de5036` ; vue synthétique complète de l’inventaire, pas preuve du comportement |
| Inventaire original | Inventaire conservé dans l’export de travail | `ev_480097fb3b84faaa300828ced3e7d9a6856e93e0ef203ddba3a3978c84368681` |
| Version fournie | Nom SprintTimer, version 18.0, build 180, iOS minimum 12.1 | `ev_854293fa91e10c551447771cf2f12cd5b90b0396c3637895fa24c21cbc73b1e4` ; observation d’un `Info.plist` extrait, pas de la version actuellement distribuée |
| Identification | Identifiant commercial `sprintTimer`, application Watch associée | Même preuve ; le nouveau projet doit utiliser un identifiant différent |
| Permissions déclarées | Caméra pour les arrivées, microphone pour le signal de départ | Déclarations statiques ; autorisation effectivement accordée inconnue |
| Guides embarqués | Départ, photo, vidéo, live, résultats, tutoriel et questions fréquentes | Fichiers HTML de l’archive, lus localement ; description de l’auteur, pas observation d’exécution |

L’export complet de l’inventaire et celui de l’inspection des ressources sont conservés dans le dossier de travail de l’analyse. Ils ne sont pas publiés : les ressources de référence restent hors du dépôt. L’inspection des ressources fournit une identité de répertoire et un chemin de manifeste, sans empreinte de l’exécutable ; REA indique explicitement cette limite. Aucune conclusion sur le code interne n’en découle.

## Parcours de référence documentés

| Écran ou fonction | Interaction et transition décrites | État de la connaissance |
| --- | --- | --- |
| Accueil / choix du mode | Choix entre Photo Finish, Video Finish et Live Finish dans la configuration de capture ; accès aux résultats et aux réglages du départ | Guides embarqués et [vue d’ensemble officielle](https://appmaker.se/guide/sprinttimer/web.php?fil=guide_overview) |
| Départ | Manuel, détection sonore avec seuil et armement, départ autonome avec délai, ou départ envoyé par un autre appareil | [Guide du départ](https://appmaker.se/guide/sprinttimer/web.php?fil=guide_start) |
| Prévisualisation | Alignement de la caméra avec la ligne ; position fixe recommandée ; contrôle de la zone de mouvement | Guides photo et vidéo |
| Course | Le départ du chronomètre et celui de la capture sont deux actions distinctes ; capture manuelle ou programmée | Guide photo |
| Photo-finish | Assemblage de bandes de la ligne d’arrivée, défilement horizontal puis marquage des concurrents ; largeur des bandes et sens réglables | [Guide photo](https://appmaker.se/guide/sprinttimer/web.php?fil=guide_photo) |
| Analyse vidéo | Navigation par curseur ou image par image ; marquage de l’image choisie ; détection de mouvement configurable | [Guide vidéo](https://appmaker.se/guide/sprinttimer/web.php?fil=guide_video) |
| Live / Instant Finish | Le guide embarqué décrit un temps sauvegardé à chaque détection, une temporisation et des options mouvement, personne ou QR | `guide_live.html` de l’IPA ; aucune mesure de fiabilité effectuée |
| Participants | Liste préalable avec noms, numéros et couloirs ; attribution au moment du marquage, puis correction possible | [Guide des résultats](https://appmaker.se/guide/sprinttimer/web.php?fil=guide_results) |
| Historique | Consultation des listes chronométrées et des enregistrements sauvegardés ; réouverture pour analyse | Guide des résultats et questions fréquentes embarqués |
| Exportation | Résultats CSV, PDF ou LIF, puis partage par les services disponibles dans iOS | Guide des résultats |
| Réglages / calibrage | Seuil sonore, décalage de départ, distance sonore, cadence, durée, largeur des bandes, direction et sensibilité de détection | Guides embarqués ; valeurs et effets non mesurés sur appareil |

Le guide du départ décrit aussi une correction manuelle ultérieure à partir de l’audio, des départs distants et une extension Watch. Ces possibilités de la référence ne constituent pas des fonctionnalités promises pour la première version du nouveau projet.

## Illustrations effectivement examinées

`photofinish.jpg`, inclus dans le guide de vue d’ensemble de l’IPA, montre une composition horizontale de coureurs avec plusieurs repères verticaux et leurs temps. `videofinish.jpg` montre deux images ordinaires de course à deux instants différents, chacune avec un temps et un repère d’arrivée. Elles illustrent la différence entre un axe horizontal représentant le temps et une image représentant l’espace.

Ces illustrations sont des exemples de la référence. Elles ne sont ni des captures réalisées pendant cette analyse ni des tests de la reconstruction. Les fichiers `startModes.png` et `ResultsManager.png`, initialement illisibles, ont ensuite été convertis avec le `pngcrush` de Xcode et examinés. Ils montrent respectivement les écrans de départ et un schéma du gestionnaire de résultats. Il s’agit toujours d’illustrations embarquées, pas d’une observation du programme en fonctionnement. Aucun parcours tactile réel de l’application commerciale n’a été observé.

## Modèle d’états recommandé pour la reconstruction

Cette section décrit un choix d’architecture, déduit des parcours documentés :

1. **Préparation** : configuration de la course, des participants et de la capture ; demandes d’accès au matériel.
2. **Prêt** : prévisualisation active, ligne alignée, réglages visibles.
3. **Attente** : départ sonore armé ou compte à rebours ; annulation possible.
4. **Course** : référence monotone fixée ; la capture d’arrivée peut commencer plus tard.
5. **Enregistrement** : collecte des bandes ou images avec horodatage réel de chaque échantillon.
6. **Traitement** : fermeture des fichiers et finalisation du manifeste ; commandes incompatibles désactivées.
7. **Analyse** : navigation, attribution et correction des résultats, sauvegarde automatique.
8. **Succès** : course disponible dans l’historique et partage possible.
9. **Erreur ou interruption** : message compréhensible, conservation du travail récupérable et arrêt cohérent de la capture.

Cette liste formalise le comportement souhaité du nouveau projet. Elle n’attribue pas à l’application commerciale un automate interne qui n’a pas été observé.

## Photo-finish : conséquences techniques

Chaque bande représente un instant, et non une portion supplémentaire de la piste. Un pointeur horizontal doit sélectionner l’horodatage correspondant. Une cadence nominale ne suffit pas à retrouver ce temps si des images manquent. La [FAQ officielle](https://appmaker.se/guide/sprinttimer/web.php?fil=QA) distingue ainsi la vidéo source horodatée d’une image finale sans toutes ses métadonnées ; elle signale aussi les conséquences visuelles des pertes d’images.

Pour la reconstruction, cela conduit à conserver la correspondance bande–horodatage, les paramètres de capture et les pertes détectées avec les images. La réouverture d’une course doit exploiter ces données. Le chronomètre visible sert à informer l’utilisateur ; il ne doit pas servir de source temporelle à la photo-finish.

Le guide photo de référence décrit une cadence élevée, une capture des dernières secondes et une analyse après enregistrement. Ses annonces de précision restent les annonces de son auteur : elles ne valident pas notre application. Afficher deux décimales n’établit pas une exactitude au centième.

## Vidéo et détection instantanée

Le guide vidéo décrit des images retenues autour d’un mouvement, une option continue et une possibilité d’interpolation manuelle entre deux images. La reconstruction peut conserver une vidéo continue et les scores de mouvement pour faciliter la navigation : il s’agit d’un choix original, à documenter comme tel. Une détection de mouvement ne permet pas d’identifier automatiquement chaque concurrent ni de séparer sûrement deux personnes proches.

Le guide live embarqué décrit des temps immédiats sans conserver les images, avec temporisation contre les déclenchements répétés. La reconstruction doit présenter les temps automatiques comme des détections à contrôler. La luminosité, le déplacement du téléphone et les mouvements du fond peuvent créer des faux positifs. Une détection de personne peut filtrer certaines situations, sans garantir une mesure du franchissement du torse.

## Contraintes iOS et validations nécessaires

- La cadence doit appartenir à un format réellement pris en charge ; modifier la durée minimale d’image exige un verrou de configuration. Une valeur incompatible peut provoquer une exception. Voir [les formats de capture](https://developer.apple.com/documentation/avfoundation/capture-device-formats) et [activeVideoMinFrameDuration](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activevideominframeduration).
- Une référence commune doit relier le départ et les échantillons de capture. Core Media fournit une horloge hôte et des conversions entre horloges ; une date civile ou une boucle d’interface ne remplace pas ce mécanisme. Voir [CMClock](https://developer.apple.com/documentation/coremedia/cmclock) et [les API de synchronisation](https://developer.apple.com/documentation/coremedia/cmclock-api).
- La caméra peut être interrompue par une mise en arrière-plan, une autre utilisation du matériel ou la pression système. Le traitement doit observer ces interruptions et finaliser les données disponibles. Voir [les motifs d’interruption AVFoundation](https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason).
- Les images et vidéos doivent être écrites progressivement. Une image panoramique complète gardée en mémoire ne convient pas à une longue capture. C’est une contrainte de conception ; aucune consommation mémoire du nouveau projet n’a été mesurée par cette analyse.
- Il faut mesurer sur un iPhone réel la cadence obtenue, les intervalles entre images, les pertes, la latence sonore et la stabilité. Le simulateur et les tests de calcul ne peuvent valider le capteur, l’alignement, les occultations ou l’exactitude globale.

## Questions résolues et inconnues

| Question | Conclusion |
| --- | --- |
| Quels grands modes et parcours sont documentés ? | Répondu par les guides de référence |
| Quel est le principe de la photo-finish ? | Répondu : bandes successives associées à des instants de capture |
| Quel contenu contient précisément l’IPA fourni ? | Inventaire statique établi ; manifeste inspecté |
| Les écrans observés pendant une utilisation réelle correspondent-ils aux guides ? | Non vérifié : application commerciale non exécutée |
| Quelle est l’architecture interne commerciale ? | Inconnue ; aucun code décompilé utilisé |
| Quelle précision possède la reconstruction ? | Non déterminée par l’analyse de la référence ; exige des mesures matérielles |
| La reconstruction reproduit-elle toutes les options commerciales ? | Aucun engagement de parité ; voir la feuille de route du projet |

Empreintes des principaux guides embarqués examinés, utiles pour rattacher cette synthèse au paquet fourni :

```text
guide_overview.html cf8a51d562e5d12a083c94787e9a5134384314819ad1f29ca45c25592853a717
guide_photo.html    3356affc11bcb001345e33fc02f175376e7f3ebf92951e038314819aec0bb3a5
guide_video.html    060ac3adf7e5f21c79851c0d4bec22ad6255c0c336629168c210bad6e7009e37
guide_live.html     818b7152ca1c18479eced9b0c18416f5badd988c7674c1b92bd3ac22335f292b
guide_results.html  546d4a57fe9c233007a9b6e5b25009bb797b5dcd57f96e36503465da646f82de
guide_start.html    3fc65e0645a518407657d5fc01d6631c2f3371d5da7615ba9319ab666da6f5a2
QA.html             c1b8d3e1614d7e786e31aa6671aec65a89c0edfcabfb7d1035465c3893e41cc0
```
