# ASO — Audire (septembre 2026)

## Décision de lancement

1. **France (`fr-FR`)** — publier en premier. L’offre est claire : EPUB/PDF, lecture vocale, voix locales et hors ligne.
2. **États-Unis, Royaume-Uni, Canada anglophone, Australie** — deuxième vague avec une seule création anglaise adaptée par storefront (`en-US`, `en-GB`, `en-CA`, `en-AU`).
3. **Canada francophone, Belgique, Suisse romande** — servir la fiche `fr-FR` au lancement ; créer `fr-CA` avec captures dédiées ensuite.
4. **Allemagne** — marché à préparer, mais ne publier la fiche `de-DE` qu’après localisation de l’interface et des captures.

Ce classement est une recommandation éditoriale et concurrentielle : le connecteur de données ASO donnant popularité/difficulté par mot-clé n’est pas disponible dans cet environnement. Les champs ci-dessous évitent les doublons titre/sous-titre et tiennent sous la limite App Store de 100 caractères.

## Priorités observées

| Priorité | Storefronts | Intention qui convertit | Concurrence observée | Angle Audire |
|---|---|---|---|---|
| 1 | France / Belgique / Suisse romande | `lecture vocale EPUB`, `lire un PDF à voix haute` | Moyenne, nouveaux concurrents spécialisés | Lecteur de livres personnel, pas une simple app TTS |
| 2 | États-Unis | `read EPUB aloud`, `PDF to audiobook` | Forte, mais forte intention et paiement déjà établi | Vos propres livres, lecture + écoute locale |
| 3 | Royaume-Uni / Canada anglophone / Australie | `read aloud PDF`, `text to speech reader` | Forte mais moins polarisée qu’aux US | Lecture longue, hors ligne, reprise précise |
| 4 | Canada francophone | `lecture vocale`, `livre audio`, `hors ligne` | Moyenne ; extension naturelle de la fiche FR | Même promesse que France, vocabulaire canadien |
| 5 | Allemagne | `Bücher vorlesen`, `EPUB vorlesen` | Forte et concurrent très proche | Attendre UI allemande ; éviter le générique `Text zu Sprache` |

### Ce que nous ne ciblons pas

- `livres audio` seul : intention souvent liée à un catalogue/streaming, alors qu’Audire lit les fichiers de l’utilisateur.
- `text to speech` / `Text zu Sprache` seul : volume probablement élevé mais concurrence très large (documents, scan, web, IA) et conversion moins qualifiée.
- Marques concurrentes : non retenues ; elles dégradent la promesse premium et peuvent créer un risque éditorial sans données de rang vérifiables.

## France — publié dans App Store Connect

**Titre** : `Audire : EPUB & PDF audio`  
**Sous-titre** : `Vos livres, à votre rythme`  
**Champ mots-clés (78 caractères)** :

```text
lecture vocale,synthese vocale,lire texte,voix naturelle,traduire ebook,hors ligne
```

### Longue traîne à travailler dans la description et les captures

- lecture vocale EPUB
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
