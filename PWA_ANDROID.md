# SprintTimer web (PWA) et Android (APK)

Le dossier `web/` contient une version web installable de SprintTimer, avec les quatre modes de l'application iOS : **photo-finish**, **vidéo-finish**, **arrivée instantanée** et **chronomètre**. La même application est empaquetée en **APK Android** grâce à [Capacitor](https://capacitorjs.com) (dossier `android/`).

Elle fonctionne sur Android et sur iPhone sans Mac, sans Xcode et sans compte Apple. Les courses et les captures restent sur l'appareil (IndexedDB) ; rien n'est envoyé à un serveur.

| | PWA (navigateur) | APK Android |
| --- | --- | --- |
| Appareils | Android (Chrome), iPhone/iPad (Safari, iOS 16.4 ou ultérieur conseillé), ordinateur | Android 7 ou ultérieur |
| Installation | « Ajouter à l'écran d'accueil » depuis une adresse HTTPS | Fichier `SprintTimer.apk` à installer |
| Hors ligne | Oui, après la première ouverture | Oui |
| Mises à jour | Automatiques à la publication | Installer le nouvel APK par-dessus l'ancien (les courses sont conservées) |

## Obtenir l'APK

Le workflow GitHub Actions **PWA & Android** (`.github/workflows/android.yml`) se lance à chaque push qui modifie la version web ou Android. Il peut aussi être lancé à la main.

1. Ouvrir l'onglet **Actions** du dépôt, puis la dernière exécution réussie de **PWA & Android**.
2. Dans **Artifacts**, télécharger `SprintTimer-APK-<numéro>`. C'est un zip qui contient `SprintTimer.apk`.
3. Copier `SprintTimer.apk` sur le téléphone Android et l'ouvrir. Android demande d'autoriser l'installation depuis cette source (Fichiers, Chrome…). Accepter, puis **Installer**.
4. Au premier lancement d'une course caméra, autoriser la **caméra**. Pour un départ au son, autoriser le **micro**.

L'APK est signé avec une clé de débogage commune versionnée dans le dépôt (`android/app/debug.keystore`). Chaque nouvel APK s'installe donc par-dessus le précédent sans perdre l'historique. Cette clé n'est pas secrète : elle ne convient pas à une publication sur Google Play, qui demanderait une clé de version privée.

Pour construire l'APK sur un ordinateur avec Android Studio ou le SDK Android et Java 21 :

```bash
npm ci
```

```bash
npm run android:apk
```

L'APK se trouve ensuite dans `android/app/build/outputs/apk/debug/app-debug.apk`. `npx cap open android` ouvre le projet dans Android Studio.

## Publier la PWA

La caméra et le micro n'existent dans un navigateur que sur une adresse **HTTPS**. Le contenu de `web/` est statique, sans étape de compilation : n'importe quel hébergement de fichiers statiques convient.

- **Netlify Drop** (le plus simple, gratuit) : ouvrir <https://app.netlify.com/drop> et y glisser le dossier `web/`. L'adresse HTTPS obtenue peut être ouverte sur le téléphone.
- **Cloudflare Pages** ou **Netlify** relié au dépôt : répertoire de publication `web`, aucune commande de build.
- **GitHub Pages** : possible depuis le dossier `web/`, mais GitHub ne le propose pour un dépôt privé qu'avec un compte payant.

Chaque exécution du workflow publie aussi l'artefact `SprintTimer-PWA-<commit>`, qui contient le dossier `web/` prêt à déposer.

À chaque publication d'une nouvelle version, incrémenter `VERSION` dans `web/sw.js` pour que les téléphones renouvellent le cache hors ligne.

### Installer la PWA

- **Android (Chrome)** : ouvrir l'adresse, puis le bouton **Installer l'application** de l'accueil, ou le menu ⋮ → **Installer l'application**.
- **iPhone/iPad (Safari)** : ouvrir l'adresse, bouton **Partager** → **Sur l'écran d'accueil**. Ouvrir ensuite SprintTimer depuis l'icône.

## Essayer en local

```bash
npm run serve
```

Ouvrir <http://localhost:8080/> dans Chrome sur l'ordinateur. `localhost` est un contexte sécurisé : la webcam fonctionne. Sur un téléphone, il faut l'adresse HTTPS d'une publication.

## Fonctionnement

| Mode | Version web |
| --- | --- |
| **Photo-finish** | À chaque image de la caméra, une bande verticale de 1 à 16 px est copiée à la position de la ligne dans des tuiles PNG sans perte de 1 024 px de large. Chaque bande garde l'horodatage réel de son image. L'analyse propose défilement, zoom horizontal, curseur, navigation image par image et marquage. |
| **Vidéo-finish** | Chaque image est enregistrée en JPEG (480, 640 ou 960 px de haut) avec son horodatage et son score de mouvement. La revue se fait image par image, avec la ligne d'arrivée et un graphe de mouvement cliquable. En option, la vidéo complète est aussi enregistrée pour l'export. |
| **Arrivée instantanée** | Même capture que la vidéo, plus la détection de variation dans la zone autour de la ligne : seuil, temporisation et réarmement après deux images calmes, comme sur iOS. Les temps sont estimés et vérifiables dans les images. |
| **Chronomètre** | Départ, arrivées marquées à la main, arrêt. Aucune caméra. |

Les quatre modes partagent les départs **manuel**, **bip programmé**, **compte à rebours** suivi d'un bip, et **détection du son** au micro, avec le décalage de départ. Un décalage positif ajoute du temps.

On retrouve aussi les participants (nom, dossard, couloir), le classement, la correction et l'attribution des résultats, l'historique, la **nouvelle tentative** et les exports **CSV** (six décimales), **PDF**, **PNG annoté** du photo-finish, **fichiers de capture** (manifeste JSON, tuiles PNG, vidéo) et **JSON** de la course. Le JSON reprend la structure `RaceDocument` de l'application iOS.

### Horodatage

Tous les instants viennent de la même horloge monotone, `performance.now()` :

- **Images** : `requestVideoFrameCallback`. L'application utilise `captureTime`, l'instant de capture du capteur, quand le navigateur le fournit. C'est le cas de Chrome et de la WebView Android. Sinon elle utilise l'instant de présentation et l'indique dans la capture : le retard de traitement de la caméra n'est alors pas compensé et doit être calibré avec le décalage de départ.
- **Bip** : instant programmé dans Web Audio, converti avec `AudioContext.getOutputTimestamp()`. Ce n'est pas l'instant où le son atteint le coureur.
- **Micro** : un `AudioWorklet` repère le premier échantillon au-dessus du seuil. La latence d'entrée du micro n'est pas compensée.

Comme sur iOS, aucun temps n'est calculé à partir d'une cadence théorique. Une image perdue laisse un trou dans la chronologie. L'analyse affiche la cadence mesurée, l'écart maximal entre deux images, les images perdues et la source de l'horodatage.

## Limites par rapport à l'application iOS

- **Cadence** : les navigateurs fournissent en général 30 ou 60 i/s, rarement plus, même si 120 ou 240 i/s sont demandés. La cadence obtenue est affichée. Le photo-finish web départage donc moins finement que l'application native à 240 i/s.
- **Filtre de présence humaine** (Vision) : non disponible. L'arrivée instantanée ne distingue pas une personne d'une ombre.
- **Arrière-plan** : la capture s'arrête si l'application passe en arrière-plan ou si l'écran se verrouille. L'APK garde l'écran allumé ; la PWA demande un verrou d'écran (`Wake Lock`) quand le navigateur le permet.
- **Stockage** : les images de contrôle occupent de la place, environ 1 à 2 Mo par seconde de capture vidéo à 60 i/s. L'accueil affiche l'espace utilisé ; supprimer les anciennes courses pour le libérer. Sur iPhone, Safari peut effacer les données d'une PWA inutilisée pendant plusieurs semaines : exporter les résultats importants.
- **Encodage** : si le téléphone n'encode pas les images assez vite, des images sont ignorées et comptées comme perdues, sans jamais être inventées.
- Comme l'application iOS, ce n'est **pas un système de chronométrage certifié**. Les précisions et les cadences doivent être mesurées sur chaque téléphone.

## Structure

```
web/                  application (HTML, CSS, modules JavaScript sans compilation)
  js/core/            logique pure, portée de Packages/SprintTimerCore
  js/services/        caméra, signaux de départ, stockage IndexedDB, exports
  js/views/           écrans (Preact + htm, fournis dans js/vendor)
  sw.js               cache hors ligne
android/              projet Android Capacitor (généré, puis permissions, icônes et signature)
tests-web/            tests unitaires Node (temps, chronologie, détection, CSV, PDF, cache)
scripts/serve-web.mjs serveur local
scripts/e2e-web.mjs   parcours complet dans Chromium avec caméra et micro simulés
```

Vérifications :

```bash
npm test
```

```bash
npm run e2e
```

`npm run e2e` exige Playwright et Chromium. Il passe par les quatre modes, l'export CSV, le PNG annoté, la réouverture et la correction d'un résultat, puis le démarrage hors ligne.

Après une modification de `web/`, `npx cap sync android` recopie l'application dans le projet Android. Le workflow le fait automatiquement.
