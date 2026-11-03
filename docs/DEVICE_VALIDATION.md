# Validation sur un iPhone réel

Ce protocole accompagne la première installation et les évolutions du moteur. **Aucun essai sur iPhone réel ni aucune précision globale mesurée ne sont revendiqués dans la livraison initiale.** Les cases ci-dessous restent à remplir après des observations sur appareil. Une compilation et un test sur données synthétiques ne remplacent pas ces essais.

## Fiche d’essai

| Champ | Valeur à relever |
| --- | --- |
| Date / opérateur | À remplir |
| Commit testé | À remplir avec `git rev-parse HEAD` |
| Modèle d’iPhone/iPad | À remplir |
| Version iOS/iPadOS / Xcode | À remplir |
| Batterie / stockage disponible | À remplir |
| Température et conditions d’éclairage | À remplir |
| Support / distance / couloirs cadrés | À remplir |
| Mode, largeur de bande, ligne et paramètres de détection | À remplir |
| Dispositif temporel de référence et son incertitude | À remplir |

Pour chaque scénario, conserver la course, le CSV et les fichiers originaux dans un dossier d’essai. Utiliser des participants et images dont le partage est autorisé ; les données n’ont pas besoin d’être ajoutées au dépôt GitHub.

## 1. Installation, accès et sauvegarde

| Essai | Vérification attendue | Résultat |
| --- | --- | --- |
| Clonage et Run avec l’équipe de Julien | Projet ouvert sans chemin local à modifier ; app appelée SprintTimer sur l’écran d’accueil | À réaliser |
| Premier lancement | Accueil lisible, guide accessible, création d’une course possible | À réaliser |
| Autorisation caméra acceptée | Prévisualisation arrière visible dans un mode caméra | À réaliser |
| Autorisation caméra refusée puis réactivée | Message explicite et reprise via les réglages iOS ; mode chronomètre utilisable sans caméra | À réaliser |
| Autorisation microphone acceptée/refusée | Demande au moment d’armer le départ sonore ; refus géré sans faux départ | À réaliser |
| Course manuelle de trois participants | Trois arrivées sauvegardées, classement, dossards et couloirs corrects | À réaliser |
| Fermeture et relancement | Course rouverte avec les mêmes temps et résultats | À réaliser |
| Correction et nouvelle tentative | Résultat corrigé persistant ; nouvelle tentative distincte, ancienne course conservée | À réaliser |

## 2. Alignement et photo-finish

Placer l’appareil en portrait sur un support fixe, aligné avec une ligne clairement matérialisée. Cadrer toute la hauteur des concurrents et tous les couloirs. Utiliser d’abord un éclairage uniforme et le départ manuel pour isoler le traitement d’images.

1. Demander 30 i/s et une bande de 2 pixels ; préparer puis lancer le chronomètre.
2. Commencer la capture et faire passer un objet présentant des repères de couleurs distincts dans les deux sens. Terminer la capture.
3. Vérifier que la ligne orange de prévisualisation correspond bien à la zone extraite, que le haut et le bas ne sont pas inversés et que les bandes apparaissent dans l’ordre du temps.
4. Refaire le test avec les positions de ligne proche de la gauche et de la droite, puis les largeurs 1 et 16 pixels. Ces paramètres se changent avant la capture.
5. Parcourir la photo, zoomer, sélectionner des bandes, marquer plusieurs arrivées et rouvrir la course. Vérifier que les temps choisis sont inchangés.
6. Exporter le PNG annoté et les originaux. Vérifier la présence des repères et des JSON ; comparer les temps des résultats à `elapsedSeconds` dans `capture.json`.

Noter toute différence de cadrage ou d’orientation. L’aperçu PNG peut être réduit ; les tuiles originales et leur manifeste constituent les données d’analyse conservées. Il n’existe pas de réextraction avec une autre largeur après capture.

## 3. Cadence, lacunes et ressources

Réaliser des captures de 10 secondes, puis de 60 et 120 secondes, en 30/60/120/240 i/s demandées. Certaines cadences ne sont pas disponibles sur tous les appareils : relever la cadence configurée affichée et la moyenne réellement enregistrée, sans supposer qu’elles sont identiques. Vidéo et instantané restent plafonnés à 60 i/s.

| Mode / cadence demandée | Cadence configurée | Images | Moyenne observée | Pertes signalées | Intervalle maximal | Durée / taille / mémoire |
| --- | --- | --- | --- | --- | --- | --- |
| Photo / 30 | À mesurer | — | — | — | — | — |
| Photo / 60 | À mesurer | — | — | — | — | — |
| Photo / 120 | À mesurer | — | — | — | — | — |
| Photo / 240 | À mesurer ou indisponible | — | — | — | — | — |
| Vidéo / 60 | À mesurer | — | — | — | — | — |
| Instantané / 60 | À mesurer | — | — | — | — | — |

La moyenne du manifeste vaut `(nombre_images − 1) / (dernier_temps_hôte − premier_temps_hôte)`. Comparer les différences entre temps consécutifs pour repérer les lacunes : une moyenne satisfaisante peut masquer un intervalle long. Le compteur de pertes reflète les événements signalés par la capture et l’encodeur, pas une preuve d’absence de toute lacune.

Avec Instruments ou les outils Xcode, relever le pic mémoire, la température et l’évolution du débit sur plusieurs courses successives. Vérifier que les tuiles photo sont écrites progressivement et que leur consultation ne charge pas une immense image complète. Tester aussi l’export d’une longue photo et le comportement à faible stockage : l’erreur doit être visible et les courses précédentes doivent rester accessibles. Ne pas remplir volontairement le disque au point de compromettre d’autres données.

## 4. Départ et calibrage temporel

Faire au moins 20 répétitions par mode avec une référence externe adaptée au niveau d’incertitude recherché. Une autre horloge d’affichage ou un déclenchement manuel non contrôlé ne suffit pas à établir une précision au centième. Consigner la méthode exacte et l’incertitude de la référence.

| Départ | Points à observer | Résultat |
| --- | --- | --- |
| Manuel | Réaction humaine, répétabilité et départs répétés ignorés | À mesurer |
| Bip programmé | Instant prévu contre son réellement produit/entendu ; haut-parleur interne puis sortie filaire si utilisée | À mesurer |
| Compte à rebours | Annulation, durée configurée, bip et origine du chronomètre | À mesurer |
| Microphone | Seuil supérieur au bruit ambiant, premier pic, signal faible, bruit parasite, armement et annulation | À mesurer |
| Décalage positif et négatif | Un décalage de +0,100 s augmente le résultat de 0,100 s ; signe inverse avec −0,100 s | À mesurer |
| Course longue | Comparaison après 1, 5 et 15 minutes avant capture des arrivées | À mesurer |

Le bip est daté par sa lecture programmée ; le microphone par son échantillon horodaté. Ces références ne mesurent pas toute la chaîne acoustique. Refaire les essais lorsque le trajet sonore, le matériel ou les conditions changent. Une sortie Bluetooth peut ajouter une latence variable : elle exige une évaluation propre au dispositif utilisé.

Consigner pour chaque série la moyenne des écarts, leur dispersion, l’écart absolu maximal et les valeurs extrêmes. Distinguer l’erreur du départ, l’espacement des images, le flou et l’incertitude du repérage du franchissement. Aucun décalage unique ne corrige une variation aléatoire.

## 5. Vidéo-finish et arrivée instantanée

Pour la vidéo-finish, enregistrer un passage lent puis rapide. Parcourir toutes les images autour de la ligne, vérifier leur ordre, les temps et la ligne superposée. Revenir dans l’historique et contrôler le même marquage. Si l’image décodée ne correspond pas exactement à l’instant demandé, le message prévu doit être visible ; ne pas valider ce temps sans examiner les images voisines.

Pour l’arrivée instantanée, compter manuellement les passages attendus et comparer les événements produits dans ces situations :

- Personne isolée, vitesses et tailles différentes, près puis loin de la caméra.
- Deux concurrents espacés de moins, puis de plus que la temporisation.
- Concurrents côte à côte, passages dans plusieurs couloirs et personnes qui restent dans la zone.
- Ombres, déplacement du fond, variation d’éclairage, mouvement du téléphone, personne hors de la zone.
- Filtre Vision activé puis désactivé, sensibilité basse/haute et zone étroite/large.

| Série | Passages attendus | Détectés corrects | Manqués | Supplémentaires | Écart temporel observé | Paramètres |
| --- | --- | --- | --- | --- | --- | --- |
| À compléter | — | — | — | — | — | — |

Vérifier le réarmement après deux images calmes et la temporisation. L’événement estime une entrée dans la zone, pas un franchissement certifié du torse. Contrôler l’attribution aux participants : la détection ne reconnaît pas leur identité.

## 6. Interruptions et récupération

| Situation | Contrôle attendu | Résultat |
| --- | --- | --- |
| Passage en arrière-plan ou verrouillage pendant la capture | Arrêt de la course, message et finalisation des données disponibles | À réaliser |
| Appel ou autre interruption de la caméra | État cohérent, médias déjà écrits conservés, course réouvrable si possible | À réaliser |
| Retour au premier plan avant le départ | Prévisualisation réinitialisable ; aucun départ accidentel | À réaliser |
| Arrêt forcé pendant une capture photo de test | Récupération des seules tuiles finalisées et de leurs temps ; capture signalée interrompue | À réaliser |
| Arrêt forcé pendant une capture vidéo de test | Résultats déjà sauvegardés présents ; comportement explicite si le MOV est illisible | À réaliser |
| Espace insuffisant pendant une course de test | Erreur de sauvegarde visible, possibilité de réessayer après avoir libéré de l’espace | À réaliser |
| Suppression d’une course de test | Confirmation et retrait de l’entrée d’historique et de ses médias | À réaliser |

La récupération est partielle : une tuile en attente ou un fichier en cours d’écriture peut manquer. La présence de `capture.json` ne répare pas un conteneur vidéo non finalisé. Faire les essais d’arrêt forcé uniquement sur des courses jetables et exporter auparavant les données utiles.

## 7. Exports et compte rendu

Ouvrir le CSV dans un tableur en choisissant UTF-8 et le séparateur virgule si nécessaire. Vérifier accents, virgules et guillemets dans les noms, ordre des résultats, dossards, couloirs et temps. Ouvrir le PDF à plusieurs pages ; contrôler que tous les participants sont présents. Partager le PNG et les originaux vers Fichiers, puis vérifier qu’ils s’ouvrent et contiennent les fichiers attendus.

Terminer par un compte rendu comprenant la fiche d’essai, les paramètres, les mesures brutes, les erreurs observées, les captures ou exports pertinents et une conclusion bornée au matériel testé. Mettre à jour le README uniquement avec les vérifications réellement achevées. Si le centième n’est pas démontré, indiquer l’incertitude obtenue ou conserver la mention **précision non mesurée**.
