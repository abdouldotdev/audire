# Architecture de Lisière

## Chaîne de lecture

```text
EPUB → ZIP/OPF/spine → chapitres et blocs canoniques → segments français
                                     ↓                     ↓
                               texte affiché       NarrationText + SourceRange
                                                           ↓
                   ┌── système : AVSpeechSynthesizer / Android TextToSpeech
                   │                       ↓ événements de plages
ReaderController ─┤
                   └── worker local : Supertonic → WAV ───────────→ just_audio
                                              ↓ optionnel               ↓
                                      Wav2Vec2 CTC + Viterbi       position média
                                              ↓                        ↓
                                       WordCue[] ───────────→ plage surlignée
```

Le texte canonique conserve une séparation en blocs, titres et notes. Le frontal français produit une chaîne prononcée et deux listes d’offsets UTF-16. Une expansion de texte ne modifie donc pas les positions du livre affiché. La segmentation privilégie la phrase, puis les pauses de ponctuation, avec une limite souple pour borner le coût de synthèse.

## Responsabilités

`ReaderController` est l’unique propriétaire de l’intention de lecture, du choix de moteur, du chapitre, des segments et de la session audio. Les commandes courtes sont sérialisées. Les synthèses longues ne bloquent pas cette file. Les événements d’un moteur non sélectionné ou d’une ancienne lecture sont ignorés. Le flux `readingTick` isole les mises à jour de mots des reconstructions complètes de navigation.

`NativeSpeechEngine` gère les identifiants d’énoncé et la base d’offset après pause/reprise. Le plugin ne fournit pas de timer de mots : ses événements proviennent des callbacks natifs. Une plateforme ou une voix ne donnant pas ces plages n’est pas déclarée synchronisée mot à mot.

`NeuralWorker` possède les sessions ONNX dans un isolate de fond avec messagerie Flutter initialisée. Il exécute un travail à la fois, réutilise les sessions et styles de voix et libère les valeurs ONNX. Cette isolation de la boucle Flutter ne constitue ni une garantie de latence, ni une annulation immédiate des opérations natives. Une terminaison inattendue de l’isolate peut se traduire par l’expiration de la requête.

`SupertonicRuntime` assemble l’encodeur de texte, le prédicteur de durée, l’estimateur vectoriel et le vocodeur selon le contrat du dépôt officiel. Il normalise en NFKD pour le frontal, utilise la langue française et refuse un caractère non pris en charge plutôt que de l’ignorer silencieusement. L’audio produit est écrit en WAV PCM16.

`AcousticAligner` rééchantillonne l’audio à 16 kHz, calcule des émissions CTC et aligne le texte connu. L’algorithme Viterbi tient compte du symbole blanc et des caractères répétés. La confiance de chemin et la distance avec le décodage glouton filtrent les alignements manifestement fragiles. Les seuils doivent être calibrés ; ils ne prouvent pas l’exactitude temporelle. Toute absence de modèle ou de résultat fiable entraîne le suivi par phrase.

`NeuralSpeechEngine` lit le WAV, conserve les `WordCue`, cherche le mot selon la position média et gère le cache. La vitesse ne multiplie pas naïvement un chronomètre externe. La prélecture prépare au plus un passage d’avance en fonctionnement normal. Des requêtes de déplacement rapides peuvent cependant attendre un calcul antérieur déjà lancé.

`LisiereAudioHandler` publie les métadonnées et commandes système. Les contrôles précédent/suivant déplacent entre passages, pas arbitrairement de quinze secondes. Le focus, les interruptions et la déconnexion audio passent par `audio_session` et le contrôleur. Ces chemins nécessitent une validation matérielle.

## Stockage et intégrité

La bibliothèque est persistée en JSON dans le stockage de support applicatif, avec couvertures séparées et identifiant issu du SHA-256 de l’EPUB importé. Les préférences et positions sont écrites séquentiellement via un fichier temporaire. Le chargement de l’ensemble des livres en mémoire convient à un prototype ; une grande collection demandera indexation et chargement à la demande.

Le gestionnaire de modèles fixe un dépôt et une révision. Les grands fichiers sont vérifiés par SHA-256 LFS ; les petits fichiers par l’empreinte Git attendue, avec son en-tête de blob. La confiance reste celle du catalogue HTTPS reçu. La validation n’est pas une signature indépendante. Un marqueur installé n’est créé qu’après validation et renommage du répertoire préparatoire.

Le pack CTC n’autorise que cinq noms de fichiers plats. Son manifeste contient des empreintes SHA-256 ; les archives trop grandes, doublons, liens symboliques et noms inattendus sont rejetés. Cette vérification ne remplace pas l’audit d’un modèle ONNX avant exécution.

L’importeur EPUB borne les tailles et ne déploie pas l’arborescence ZIP arbitraire sur disque. Il ne constitue pas un durcissement complet contre toutes les archives malveillantes : certains chemins du décodeur peuvent allouer ou décompresser avant les contrôles applicatifs. Une version de production doit ajouter des tests de fuzzing et mesurer les allocations maximales.

## Décisions et compromis

Le modèle de voix n’est pas soumis à une reconnaissance libre qui remplacerait le livre : l’alignement contraint un texte connu. Le mode système demeure utile sans téléchargement et quand le coût du modèle neuronal est trop élevé. Aucun LLM n’invente une version « nettoyée » du livre. Le système retire des éléments explicitement identifiés, pas des passages littéraires selon une appréciation opaque.

Les limites choisies privilégient une lecture fidèle et un état de synchronisation honnête. Une version ultérieure pourrait proposer un pack CTC plus petit, dûment validé et licencié, ou un modèle vocal disposant lui-même de durées de mots calibrées. Rien dans cette livraison ne présume que ces améliorations sont déjà réalisées.
