# Analyse approfondie de l’IPA SprintTimer

Rapport du 3 novembre 2026. Les méthodes ont été recherchées dans les documentations primaires, puis appliquées au fichier fourni. Cette analyse complète la première lecture des guides. Elle ne prétend pas avoir récupéré le projet Xcode commercial ni exécuté l’application originale sur un iPhone.

## Résultat concret

- `ipsw` 3.1.741 installé et exécuté ; publication officielle et empreinte vérifiées.
- Paquet applicatif principal extrait intégralement dans une copie de travail : 527 fichiers, sous-paquets inclus.
- REA et Hopper réellement utilisés sur l’exécutable ARM64.
- **170 fichiers NIB examinés sur 170**, répartis en trois lots pour respecter les limites du décodeur REA. Les versions `runtime.nib` et `objects-13.0+.nib` restent des variantes d’archives, pas des écrans supplémentaires.
- Graphe cumulé : 13 740 nœuds et 3 952 arêtes reconnues. Ces nombres comptent des objets et connexions sérialisés, pas des fonctionnalités.
- 3 catalogues graphiques inventoriés : 659 enregistrements, dont 263 dans le catalogue de l’app principale. Les deux autres catalogues concernent Watch.
- Les images `startModes.png` et `ResultsManager.png`, illisibles lors de la première analyse, sont désormais lisibles après conversion avec le `pngcrush` de Xcode.
- La [carte détaillée des interfaces](INTERFACES.md) décrit les contrôleurs, actions et écarts fonctionnels récupérés.

La couverture des fichiers est complète ; la compréhension de leur contenu reste partielle. REA signale des objets UIKit privés, des archives imbriquées et certains modèles de transitions non décodés. Le graphe statique ne prouve pas l’affichage final, la logique des méthodes ou les changements effectués à l’exécution.

## Identité et chiffrement vérifiés

| Élément | Observation |
| --- | --- |
| IPA fourni | `sprintTimer_430807521_18.ipa`, version 18.0 / build 180 |
| SHA-256 IPA | `16140dc916d3be59d1bc57af8961748081eff7a8b1f5a5c12486e1ed1c26336f` |
| SHA-256 exécutable | `fd37a320e83b869acc437946ee85acaa63e3c79644347a02381817d011613b2f` |
| Architecture | Mach-O ARM64, 2 295 216 octets |
| Commande de chiffrement | `LC_ENCRYPTION_INFO_64`, `cryptid = 1` |
| Plage déclarée chiffrée | `[0x4000, 0x1A8000)`, soit 1 720 320 octets |
| Section des instructions | `__TEXT.__text`, offset 21 148, taille 1 340 060 octets : entièrement comprise dans cette plage |
| Noms et réflexion | `__objc_methname`, `__objc_classname`, `__cstring` et plusieurs sections `__swift5_*` également comprises dans cette plage |

La mesure d’entropie sur la plage déclarée donne environ 7,999879 bits/octet, cohérente avec son caractère chiffré. Cette mesure seule ne constitue pas une identification d’algorithme cryptographique ; la frontière est d’abord celle déclarée par le Mach-O.

Ces observations expliquent la limite rencontrée : les outils peuvent lire le conteneur, les imports et les ressources sans disposer des instructions et chaînes internes en clair.

## Essais de décompilation et limites observées

Hopper a importé l’image ARM64 et établi un inventaire automatique. Les compteurs de procédures candidates et de chaînes issus d’une analyse de ce fichier ne sont pas des preuves de fonctions et textes correctement récupérés dans la plage chiffrée. Une recherche du nom `main` n’a rien trouvé dans cet inventaire ; l’essai ciblé au point d’entrée `0x10004bd54` n’a pas produit de dossier de fonction. Cela ne prouve pas l’absence d’un point d’entrée dans l’application.

La lecture Objective-C par `ipsw class-dump` a produit des noms invalides et échoué. La lecture Swift a échoué dans les descripteurs de champs. L’inspection native de REA a également signalé des noms UTF-8 invalides et des références incomplètes. Les régions correspondantes recoupent les zones protégées : ces sorties n’ont pas été traitées comme des sources ou des descriptions fiables du programme.

Modifier le champ `cryptid` ne déchiffre pas les octets. De même, faire interpréter par un modèle de langage un désassemblage de ces octets ne permettrait pas d’en déduire les algorithmes d’origine. La [méthode REA](https://github.com/morluto/rea/blob/main/docs/native-investigation.md) demande de préserver cette frontière.

## Ce qui permet déjà d’améliorer la fidélité

Les archives d’interface fournissent des contrôleurs, des libellés et des connexions réels. Elles révèlent notamment des réglages et actions plus détaillés que ceux de la première réimplémentation : correction du départ sur l’audio, analyse vidéo Dual, capture automatique et options de marquage, de tours et de tri. Leur présence sérialisée ne prouve pas encore le comportement interne de chaque commande.

Les illustrations embarquées montrent aussi les écrans de départ bleus, le bouton central de départ et l’accès aux réglages, à la prévisualisation et aux résultats. Elles constituent des exemples fournis avec l’application ; elles ne remplacent pas des captures de son utilisation réelle.

La prochaine reconstruction peut s’appuyer sur la carte d’interface pour conserver les parcours et options tout en écrivant les moteurs et ressources de manière originale. Les ressources commerciales ne sont pas intégrées au nouveau produit ni publiées avec son code.

## Prérequis restant pour les algorithmes protégés

Pour analyser les corps de fonctions contenus dans la zone chiffrée, il faut une image exécutable en clair provenant d’un accès approprié à l’application, ou une version de développement fournie par son auteur. Une observation de l’original sur un appareil accessible permettrait aussi de vérifier ses parcours, réactions et résultats, même sans récupérer les sources.

Le matériel physique inventorié est actuellement indisponible. Les essais sur simulateur de la reconstruction ne constituent pas une exécution de l’IPA commercial. Aucune modification d’iPhone, installation de jailbreak ou capture de mémoire sur appareil n’a été effectuée.

## Preuves conservées

| Preuve REA | Portée |
| --- | --- |
| `ev_666d7ae0497b5c2b4463e620eba1027c1dcfa3c38794f2990532e02ba4f14fb2` | Premier lot de 64 documents d’interface |
| `ev_55ef350c0987e6213e6c01de9fed5e6147b19e5fd5f58d34cafeede98c575188` | Deuxième lot de 64 documents |
| `ev_ee7d36b792e2e2adcbd2904c7ed41d4270f52de1fb18526a2fa420a54d129e8c` | Dernier lot de 42 documents |
| `ev_c11a874b201ebe27aad8aa26da2d12932988b914524e37e57371f07c22b460f6` | Inventaire des catalogues graphiques |
| `ev_4f85d11f041dfcffca24cf5fcade15df81de7463250c6267e3a7b5328787c36c` | Structure Mach-O et provenance des commandes natives |
| `ev_984771810cfe74643249cea8a2412fd42901ce99225e053eae4225b4df3be19f` | Import et inventaire Hopper, avec limites |
| `ev_a4ef76ee25229510ebcba32c27dd76b689f880cc7838091b26ed12d6454828a3` | Inspection des métadonnées natives, partielle et avec erreurs explicites |

Les exports complets et les fichiers extraits restent dans le dossier de travail privé de cette analyse. Les rapports livrés résument les faits et les limites, sans redistribuer les ressources commerciales.

## Sources primaires et outils

- [REA : enquête native et frontière de chiffrement](https://github.com/morluto/rea/blob/main/docs/native-investigation.md).
- [ipsw : documentation Mach-O](https://blacktop.github.io/ipsw/docs/guides/macho/) et [publication utilisée](https://github.com/blacktop/ipsw/releases/tag/v3.1.741).
- [Hopper Disassembler](https://www.hopperapp.com/).
- [Apple : conversion des PNG optimisés iOS](https://developer.apple.com/library/archive/qa/qa1681/).
- [Installation et versions Ghidra compatibles avec REA](https://github.com/morluto/rea/blob/main/docs/installation.md).

Voir [OUTILS.md](OUTILS_ANALYSE.md) pour l’installation effectuée et les commandes reproductibles.
