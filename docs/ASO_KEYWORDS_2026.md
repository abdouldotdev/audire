# ASO — Audire (septembre 2026)

## Décision de lancement

1. **France (`fr-FR`)** — publier en premier. L’offre est claire : EPUB/PDF, lecture vocale, voix locales et hors ligne.
2. **États-Unis, Royaume-Uni, Canada anglophone, Australie** — deuxième vague avec une seule création anglaise adaptée par storefront (`en-US`, `en-GB`, `en-CA`, `en-AU`).
3. **Canada francophone, Belgique, Suisse romande** — servir la fiche `fr-FR` au lancement ; créer `fr-CA` avec captures dédiées ensuite.
4. **Allemagne** — marché à préparer, mais ne publier la fiche `de-DE` qu’après localisation de l’interface et des captures.

Ce classement est une recommandation éditoriale et concurrentielle. Apple ne publie pas le volume ni la difficulté de mots-clés sans accès Apple Ads, et aucun compte AppTweak/outil ASO équivalent n’est connecté ici. Les chiffres ci-dessous sont donc des **résultats App Store publics** (un proxy de congestion : plus le nombre est faible, moins le terme est encombré), jamais une fausse popularité ou difficulté.

## Benchmark vérifiable — 14 septembre 2026

| Store | Mot-clé | Popularité | Difficulté | Résultats App Store (proxy) | Décision |
|---|---|---:|---:|---:|---|
| FR | `traduire ebook` | non accessible | non accessible | **32** | Retenir : angle différenciant |
| FR | `voix naturelle` | non accessible | non accessible | **36** | Retenir : angle qualité |
| FR | `lecture vocale epub` | non accessible | non accessible | **27** | Retenir dans le titre : meilleure longue traîne mesurée |
| FR | `lire pdf à voix haute` | non accessible | non accessible | 60 | Travailler dans description/captures |
| FR | `écouter epub` | non accessible | non accessible | **47** | Retenir dans la description et les captures |
| FR | `lecture vocale` | non accessible | non accessible | 160 | Retenir dans le titre, pas les mots-clés |
| FR | `synthese vocale` | non accessible | non accessible | 173 | Retenir : intention coeur |
| FR | `lire texte` | non accessible | non accessible | 181 | Retenir : complément |
| FR | `hors ligne` | non accessible | non accessible | 187 | Écarter : trop générique |
| US | `PDF to audiobook` | non accessible | non accessible | **180** | Longue traîne à tester |
| US | `read EPUB aloud` | non accessible | non accessible | 181 | Longue traîne à tester |
| US | `pdf voice reader` | non accessible | non accessible | **177** | Meilleure longue traîne anglaise testée ; retenir dans la description/captures |
| US | `audiobook maker` | non accessible | non accessible | 179 | À tester en Apple Ads, pas dans le titre |
| US | `text to speech` | non accessible | non accessible | 190 | Éviter en titre : très encombré |
| US | `voice reader` | non accessible | non accessible | 190 | Garder en mot-clé |
| GB | `PDF to audiobook` | non accessible | non accessible | **181** | Longue traîne à tester |
| GB | `read EPUB aloud` | non accessible | non accessible | 182 | Longue traîne à tester |
| CA | `text to speech` | non accessible | non accessible | **185** | Moins encombré que US/GB/AU |
| AU | `read aloud` | non accessible | non accessible | **188** | Meilleur générique anglais observé |

La collecte repose sur le nombre de résultats de recherche App Store par pays, limité à 200. C’est utile pour comparer l’encombrement relatif, pas pour estimer le volume de recherche ou la probabilité de rang.

## Validation chiffrée à faire dans Apple Ads

Le lancement organique ne dépend pas d’une campagne payante. En revanche, la seule mesure Apple publique du volume relatif est la **Search Popularity**, affichée de 1 à 5 dans Apple Ads. Lorsqu’un compte Apple Ads sera relié, mesurer ces termes dans chaque storefront avant de modifier les champs publiés :

1. créer un groupe **découverte** avec Search Match ;
2. isoler les longues traînes dans un groupe **exact** ;
3. conserver un groupe **générique** séparé pour comparer coût et conversion ;
4. après 7 à 14 jours, garder les termes avec installation et coût soutenable, puis les intégrer aux métadonnées du prochain cycle.

Apple décrit la popularité sur une échelle de 1 à 5 et recommande de séparer découverte, génériques et marque dans des groupes distincts. Voir [définitions Apple Ads](https://ads.apple.com/app-store/help/reporting/0023-reporting-options-and-definitions) et [organisation des mots-clés](https://ads.apple.com/app-store/help/keywords/0014-add-and-manage-keywords).

## Priorités observées

| Priorité | Storefronts | Intention qui convertit | Concurrence observée | Angle Audire |
|---|---|---|---|---|
| 1 | France / Belgique / Suisse romande | `lecture vocale EPUB`, `lire un PDF à voix haute` | Moyenne, nouveaux concurrents spécialisés | Lecteur de livres personnel, pas une simple app TTS |
| 2 | États-Unis | `read EPUB aloud`, `PDF to audiobook` | Forte, mais forte intention et paiement déjà établi | Vos propres livres, lecture + écoute locale |
| 3 | Royaume-Uni / Canada anglophone / Australie | `read aloud PDF`, `text to speech reader` | Forte mais moins polarisée qu’aux US | Lecture longue, hors ligne, reprise précise |
| 4 | Canada francophone | `lecture vocale`, `livre audio`, `hors ligne` | Moyenne ; extension naturelle de la fiche FR | Même promesse que France, vocabulaire canadien |
| 5 | Allemagne | `Bücher vorlesen`, `EPUB vorlesen` | Forte et concurrent très proche | Attendre UI allemande ; éviter le générique `Text zu Sprache` |

### Marchés volontairement différés

Le Japon est bien un marché iOS à forte valeur (14,5 Md$ de biens et services numériques facilités par l’écosystème App Store en 2024, selon Apple), mais une fiche japonaise sans interface et captures japonaises ferait baisser la confiance : **ne pas ouvrir `ja-JP` avant une vraie localisation**. La même règle vaut pour la Corée et la Chine. Pour la seconde vague déjà prête, les États-Unis et le Royaume-Uni combinent marché iOS important et fiche anglaise cohérente ; Apple estime 5,4 Md$ de biens et services numériques pour le Royaume-Uni en 2024, contre 2,1 Md$ pour la France. Ces chiffres décrivent l’écosystème, pas le revenu potentiel d’Audire.

Sources : [rapport Apple 2025 sur l’écosystème App Store](https://www.apple.com/newsroom/pdfs/2024-Apple-Global-Ecosystem-Report-June2025.pdf) ; [répartition iOS 2025 d’AppTweak](https://www.apptweak.com/en/reports/app-downloads-by-country). L’anglais est donc la prochaine extension rationnelle ; l’allemand suit une fois le produit localisé, et le Japon est une opportunité ultérieure de plus grande ampleur.

### Ce que nous ne ciblons pas

- `livres audio` seul : intention souvent liée à un catalogue/streaming, alors qu’Audire lit les fichiers de l’utilisateur.
- `text to speech` / `Text zu Sprache` seul : volume probablement élevé mais concurrence très large (documents, scan, web, IA) et conversion moins qualifiée.
- Marques concurrentes : non retenues ; elles dégradent la promesse premium et peuvent créer un risque éditorial sans données de rang vérifiables.

## France — publié dans App Store Connect

**Titre** : `Audire : lecture vocale EPUB`  
**Sous-titre** : `PDF, livres à votre rythme`  
**Champ mots-clés (69 caractères)** :

```text
synthese vocale,lire texte,voix naturelle,traduire ebook,a voix haute
```

### Longue traîne à travailler dans la description et les captures

- lecture vocale EPUB
- écouter un EPUB
- lire un PDF à voix haute
- synthèse vocale hors ligne
- transformer un livre en audio
- suivre le texte pendant la lecture
- traduire un ebook anglais en français

## Anglais — pack prêt (`en-US`, puis `en-GB`, `en-CA`, `en-AU`)

**Title** : `Audire: Read EPUB & PDF`  
**Subtitle** : `Listen to your own books`  
**Keyword field** :

```text
read aloud,text to speech,voice reader,offline,ebook narrator,natural voice
```

### Longue traîne

- read EPUB aloud
- PDF to audiobook
- PDF voice reader
- text to speech reader
- listen to books offline
- voice reader for PDF
- private ebook library

## Allemand — pack à activer après localisation UI (`de-DE`)

**Titel** : `Audire: Bücher vorlesen`  
**Untertitel** : `EPUB, PDF & Übersetzung`  
**Keyword-Feld** :

```text
offline,Sprachausgabe,Vorleser,natürliche Stimme,Text hören,ebook
```

### Longue traîne

- EPUB vorlesen
- PDF vorlesen lassen
- Bücher offline hören
- natürliche Stimme
- Text hören

## Ce que montre la concurrence

Les fiches qui décrivent exactement l’action dès le titre et le sous-titre dominent ce créneau : import EPUB/PDF, lecture à voix haute, voix naturelles, suivi à l’écran et écoute hors ligne. Le positionnement distinctif d’Audire doit rester : **vos propres livres, traitement local, lecture et écoute dans la même expérience**.

- [Audia — lecture vocale EPUB/PDF](https://apps.apple.com/fr/app/audia-lecture-vocale-epub-pdf/id6796007521)
- [ReadAloud — EPUB/PDF, voix locales et confidentialité](https://apps.apple.com/us/app/readaloud-text-to-speech-pdf/id6765783837)
- [Murmur — EPUB/PDF lus localement](https://apps.apple.com/us/app/murmur-epub-pdf-reader/id6787502394)
- [OraReader — PDF/EPUB, surlignage et lecture audio](https://apps.apple.com/us/app/orareader-pdf-to-audiobook/id6770490699)
- [Readest — EPUB/PDF, traduction et lecture à voix haute](https://apps.apple.com/ca/app/readest-ebook-reader/id6738622779)
- [Local TTS — lecture locale EPUB/PDF et voix neuronales](https://apps.apple.com/de/app/local-tts-pdf-vorlesen-app/id6779664222)

## Règle de publication

Ne créez une nouvelle langue dans App Store Connect qu’avec son jeu de captures : Apple bloque la soumission lorsqu’une localisation ne possède pas de captures. Le prochain lot utile est donc : six captures réelles iPhone 6,7 pouces pour `fr-FR`, puis la même séquence adaptée en anglais.
