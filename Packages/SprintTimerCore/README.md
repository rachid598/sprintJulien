# SprintTimerCore

Bibliothèque Swift 6 sans dépendance, partagée par l'app iOS et ses tests.
Lancer `swift test` dans ce dossier sur un Mac avec Swift 6.

- `TimingEngine` reçoit uniquement des secondes de la même horloge monotone. Un offset positif recule l'origine et ajoute au temps. Un départ répété ne change pas une course en cours. `reset()` autorise une nouvelle course.
- `FrameTimeline` utilise les horodatages réellement capturés. `nearestIndex` retourne une position dans le tableau. `time(atPixel:stripWidth:)` retourne le temps exact de la bande, sans interpolation. Une séquence invalide est signalée par `isValid == false` et ses requêtes retournent `nil`.
- `MotionDetectionService` compare des luminances de même dimension. Une arrivée consomme un front de mouvement; deux trames calmes sont nécessaires au réarmement, en plus du délai entre événements. Ce détecteur ne fournit ni identité ni garantie d'exclusion des ombres.
- `PhotoFinishRaster` extrait des bandes RGBA8 orientées et les compose en ordre chronologique, sous une limite de mémoire. L'adaptateur iOS écrit des tuiles sur disque pour limiter la mémoire des captures longues.
- `ResultsManager` classe les résultats et exporte un CSV RFC 4180 avec protection des formules dans les champs textuels.

Le formatage au centième ne constitue pas une revendication de précision au centième. La précision dépend des horodatages, de la cadence réellement obtenue et du calibrage du départ.
