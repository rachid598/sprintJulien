# Outils d’analyse installés et vérifiés

Vérification du 3 novembre 2026 sur le Mac de cette tâche.

| Outil | État vérifié | Usage |
| --- | --- | --- |
| REA | Serveur connecté, outils réellement appelés | Lecture Mach-O, décodage des interfaces et conservation des preuves |
| Hopper Disassembler | Installation existante opérationnelle via REA ; import ARM64 effectué | Analyse native des portions lisibles ; aucun code Swift original récupéré |
| ipsw 3.1.741 | Installé dans `/opt/homebrew/bin/ipsw`, commande `ipsw version` exécutée | Structure Mach-O, imports, symboles et métadonnées accessibles |
| Xcode Beta 27 | Installation existante ; `pngcrush` et `assetutil` utilisés | Conversion des PNG iOS et inventaire des catalogues graphiques |

`ipsw` provient exclusivement de la [publication officielle v3.1.741](https://github.com/blacktop/ipsw/releases/tag/v3.1.741). L’archive ARM64 a été comparée au fichier officiel `checksums.txt` avant installation :

```text
Archive ipsw_3.1.741_macOS_arm64.tar.gz
SHA-256 546af036b81c957ac7ddc71098ef65d2a8efebb70c81cce65bac4b9499091e8a
Binaire installé
SHA-256 c3ae23e24c817c2b4a24e9b908ec2be6f5cd544d91986f4f77ea23c3aaa0d9fc
```

Le fichier original fourni et les résultats complets de travail restent séparés du projet Swift. Aucune modification de configuration REA, de profil du shell ou de l’iPhone n’a été faite. L’installation ajoute seulement la commande `ipsw` ; les outils existants ont été réutilisés.

## Commandes reproductibles

Après extraction d’une copie de l’IPA dans un dossier de travail, remplacer le chemin ci-dessous par celui de son exécutable :

```sh
ipsw version
ipsw macho info /chemin/SprintTimer.app/SprintTimer --json
ipsw macho info /chemin/SprintTimer.app/SprintTimer --symbols --demangle
```

Les essais `class-dump` et de lecture Swift ont été réalisés sur cet IPA. Ils ont produit des noms invalides ou une erreur de lecture, car leurs structures renvoient à des données comprises dans la plage déclarée chiffrée. Les faux en-têtes obtenus n’ont pas été conservés comme du code valable.

Pour les images optimisées iOS, la commande Apple a réellement rendu lisibles `startModes.png` et `ResultsManager.png` :

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcrun -sdk iphoneos pngcrush -revert-iphone-optimizations -q \
  entree.png sortie-standard.png
```

Source : [Apple QA1681](https://developer.apple.com/library/archive/qa/qa1681/).

## Choix des décompilateurs

Hopper est déjà utilisable. Ghidra constitue une autre possibilité pour corroborer l’analyse d’un exécutable lisible. La version REA connectée demande Ghidra 12.1.x ; la recherche identifie le couple Ghidra 12.1.4 et JDK 21 ARM64, avec décompilateur natif adapté au Mac. Ce second moteur n’a pas été ajouté : le moteur Hopper fonctionne déjà et le verrou rencontré sur ce fichier est le contenu chiffré. Une installation supplémentaire ne restituerait pas ces octets en clair.

Sources : [installation REA](https://github.com/morluto/rea/blob/main/docs/installation.md), [Hopper](https://www.hopperapp.com/), [documentation Mach-O d’ipsw](https://blacktop.github.io/ipsw/docs/guides/macho/).

## Complément Reddit

UnfairPlay v0.2.0 a été préparé et son diagnostic du fichier exécuté, sans collecte administrateur du modèle de compte. Voir [METHODES_REDDIT.md](METHODES_REDDIT.md).
