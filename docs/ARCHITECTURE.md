# Architecture d’Audire

## Chaîne de lecture

```text
EPUB → ZIP/OPF/spine ─┐
                      ├→ chapitres et blocs canoniques → segments source
PDF  → PDFium/pages ──┘
                                     ↓                     ↓
                               texte affiché     EN→FR local (optionnel)
                                                           ↓
                                                  NarrationText + SourceRange
                                                           ↓
                   ┌── système : AVSpeechSynthesizer / Android TextToSpeech
                   │                       ↓ événements de plages
ReaderController ─┤
                   └── worker local : Supertonic/Kokoro → WAV ───→ just_audio
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

`SupertonicRuntime` assemble l’encodeur de texte, le prédicteur de durée, l’estimateur vectoriel et le vocodeur selon le contrat du dépôt officiel. Il normalise en NFKD, applique le marqueur FR ou EN et adapte ligatures et signes courants. `KokoroRuntime` fournit l’alternative anglaise compacte avec phonémisation locale et inférence ONNX réelle sur iOS/Android. Les glyphes décoratifs inconnus sont filtrés dans la narration sans modifier le texte affiché. Les textes devenus trop longs après traduction ou expansion des nombres sont divisés pour la synthèse. L’audio produit est écrit en WAV PCM16 ; seul l’excès de silence aux extrémités est retiré.

`AcousticAligner` rééchantillonne l’audio à 16 kHz, calcule des émissions CTC et aligne le texte connu. L’algorithme Viterbi tient compte du symbole blanc et des caractères répétés. Sans alignement exploitable, `estimateWordCues` répartit des poids syllabiques sur les zones vocalisées du WAV. Ce repli est explicitement marqué `estimatedWord` : il ne constitue pas une synchronisation acoustique exacte. Les offsets sont ceux de la narration prononcée, puis sont remappés une seule fois vers le livre. Pour une traduction, le suivi mot à mot concerne le français affiché dans les commandes ; l’anglais source reste suivi par phrase.

`NeuralSpeechEngine` alimente une playlist native continue. La réserve s’adapte à la vitesse, aux durées mesurées, au coût réel d’inférence, aux sous-alimentations, à la mémoire résidente, à la batterie, au mode économie d’énergie et à l’état thermique. La traduction suivante peut s’exécuter pendant la synthèse courante. La source traverse les chapitres sans arrêt/rechargement du lecteur. Les métadonnées des éléments de playlist pilotent le chapitre, le passage et les plages surlignées. Une pause conserve la réserve ; un déplacement ou changement de voix invalide les tâches obsolètes par génération. Un calcul ONNX déjà commencé peut encore finir et alimenter le cache.

`NativeSpeechEngine` précharge dix énoncés dans la file d’AVSpeechSynthesizer ou de TextToSpeech, avec délais inter-énoncés nuls. Les callbacks identifiés pilotent le texte courant. Une pause native reconstruit la file au dernier mot connu avec de nouveaux identifiants pour rejeter les callbacks tardifs.

Le mode audio d’arrière-plan reste actif pendant la lecture. Une tâche iOS à durée limitée couvre la préparation initiale si l’utilisateur verrouille l’écran avant le début du son ; elle n’est pas utilisée pour simuler une lecture permanente. Une interruption audio reste prioritaire. Le comportement audible prolongé doit être vérifié sur appareil, notamment en économie d’énergie.

`LivePageFlip` réutilise le peintre du package `page_flip`. Il monte uniquement la page visible et sa voisine et capture à la densité de l’écran pendant l’animation. Au repos, le texte est toujours un widget vivant, sélectionnable et actualisé par les événements vocaux. Le lecteur de commandes flotte en bas à droite, se déplie au toucher et se replie après sept secondes d’inactivité (sauf navigation accessible).

`LisiereAudioHandler` publie les métadonnées et commandes système. Les contrôles précédent/suivant déplacent entre passages, pas arbitrairement de quinze secondes. Le focus, les interruptions et la déconnexion audio passent par `audio_session` et le contrôleur. Ces chemins nécessitent une validation matérielle.

## Stockage et intégrité

La bibliothèque est persistée en JSON dans le stockage de support applicatif, avec couvertures séparées et identifiant issu du SHA-256 du document importé. Pour un PDF, PDFium extrait le texte page par page et rend la première page en PNG afin de conserver la vraie couverture. Les préférences et positions sont écrites séquentiellement via un fichier temporaire. Le chargement de l’ensemble des livres en mémoire convient à un prototype ; une grande collection demandera indexation et chargement à la demande.

Les caches WAV et traduction sont dans Application Support, avec migration des anciens répertoires temporaires. Chaque livre possède un manifeste persistant, un checkpoint audio et une option de conservation. La préparation peut viser le chapitre ou le livre complet, avec estimation, progression, interruption, suppression et régénération. Une éviction LRU globale vise 512 Mio en protégeant la file active et les livres conservés. La position audio est sauvegardée chaque seconde et aux transitions. Fermer le processus n’efface pas le cache ; désinstaller l’application supprime ses données.

Le gestionnaire de modèles fixe un dépôt et une révision. Les grands fichiers sont vérifiés par SHA-256 LFS ; les petits fichiers par l’empreinte Git attendue, avec son en-tête de blob. La confiance reste celle du catalogue HTTPS reçu. La validation n’est pas une signature indépendante. Un marqueur installé n’est créé qu’après validation et renommage du répertoire préparatoire.

Le pack CTC n’autorise que cinq noms de fichiers plats. Son manifeste contient des empreintes SHA-256 ; les archives trop grandes, doublons, liens symboliques et noms inattendus sont rejetés. Cette vérification ne remplace pas l’audit d’un modèle ONNX avant exécution.

L’importeur EPUB borne les tailles et ne déploie pas l’arborescence ZIP arbitraire sur disque. Il ne constitue pas un durcissement complet contre toutes les archives malveillantes : certains chemins du décodeur peuvent allouer ou décompresser avant les contrôles applicatifs. Une version de production doit ajouter des tests de fuzzing et mesurer les allocations maximales.

L’importeur PDF borne la taille du fichier, le nombre de pages et le volume de texte extrait. Il reconstruit l’ordre des colonnes, retire les marges répétées, ressoude les mots coupés et lance localement Vision sur iOS ou ML Kit sur Android pour les pages scannées. Chaque page devient une unité source qui peut ensuite être repaginée selon l’écran sans tronquer son contenu.

## Décisions et compromis

Le modèle de voix n’est pas soumis à une reconnaissance libre qui remplacerait le livre : l’alignement contraint un texte connu. Le mode système demeure utile sans téléchargement et quand le coût du modèle neuronal est trop élevé. Aucun LLM n’invente une version « nettoyée » du livre. Le système retire des éléments explicitement identifiés, pas des passages littéraires selon une appréciation opaque.

Les limites choisies privilégient une lecture fidèle et un état de synchronisation honnête. Une version ultérieure pourrait proposer un pack CTC plus petit, dûment validé et licencié, ou un modèle vocal disposant lui-même de durées de mots calibrées. Rien dans cette livraison ne présume que ces améliorations sont déjà réalisées.


## Traduction locale EN → FR

`LocalTranslationEngine` s’intercale avant le TTS uniquement pour les livres déclarés anglais quand le mode Français ou Bilingue est actif. Le texte est traduit passage par passage et mis en cache avec une clé SHA-256 dérivée de la révision du bundle et du contenu source. Le runtime natif Bergamot/Marian reste à lier ; les stubs Android/iOS échouent explicitement avec `BERGAMOT_NOT_LINKED`. Voir `docs/TRANSLATION_EN_FR.md`.

La traduction casse l’identité caractère-à-caractère entre source anglaise et parole française. L’interface force donc un suivi par phrase sur le texte anglais. Le mode bilingue affiche la traduction française du passage actif séparément.
