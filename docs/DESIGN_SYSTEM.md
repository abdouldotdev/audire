# Design system — Lisière

## Intention

Un lieu de lecture calme, chaleureux et précis. Le texte est prioritaire ; les contrôles restent disponibles sans simuler un studio audio. L’accent vert signale l’action et la lecture en cours. La couleur terre cuite est réservée aux avertissements. Aucun effet décoratif ne doit suggérer une fonctionnalité inexistante.

## Fondations présentes dans le code

| Jeton sémantique | Clair | Sombre |
|---|---|---|
| Papier | `#F7F5EF` | `#151D19` |
| Surface | `#FFFEFA` | `#202C25` |
| Texte principal | `#203B30` | `#EEEFE7` |
| Texte secondaire | `#5D6C61` | `#B1BFB2` |
| Accent | `#28553F` | `#B3D7B8` |
| Mot surligné | `#D5EABF` | `#B5DDA5` |
| Texte sur mot surligné | `#173620` | `#173620` |

Les jetons de `lib/ui/design_system.dart` sont la source de vérité.

Échelle d’espacement : 4, 8, 12, 16, 24, 32, 48. Marges usuelles de pages : 24. Cartes : rayon 24 ; tuiles de choix : 18. Boutons icônes : cible 48 ; commande de lecture principale : 64. Aucune certification complète d’accessibilité n’est revendiquée.

Titres éditoriaux autour de 34–36 pt, texte d’interface 14–17 pt, étiquettes 10–12 pt. La lecture varie de 17 à 32 pt avec hauteur de ligne 1,7. Police demandée : Georgia ; replis : Iowan Old Style, Noto Serif, serif. Les caractères réels dépendent du système ; aucune police n’est téléchargée par l’app. Une édition avec identité typographique strictement identique sur les plateformes devra choisir et licencier une police embarquée.

## Écrans

**Bibliothèque.** Titre « Vos livres, à votre rythme », import visible, couvertures et résumé des chapitres, recherche pour les bibliothèques plus grandes, reprise de lecture et suppression confirmée. Les couvertures manquantes utilisent une composition typographique dessinée en Flutter.

**Lecteur.** Texte à largeur maximale de 680, sommaire, apparence, mot ou phrase surligné selon le niveau réel de synchronisation, notes distinguées. Le défilement manuel suspend le suivi ; « Revenir à la voix » le réactive. Le pied contient les commandes et une progression en passages.

**Voix.** Choix Téléphone/Neuronales, extraits, voix françaises présentes, installation explicite, progression, erreurs et réglage d’alignement. Les dix styles gardent leur identifiant F1–F5/M1–M5 : aucune description de timbre non écouté n’est inventée.

**Réglages.** Thème, confort, ce qui est prononcé, gestion des données et accès aux licences de dépendances.

## Adaptation native

`AdaptiveApp`, `AdaptiveScaffold`, barres, boutons, cartes, dialogues, sélecteurs, sliders et switches proviennent du package demandé. Les couleurs sémantiques sont partagées entre les thèmes Material et Cupertino. Les surfaces éditoriales restent en Flutter ; le package choisit ses implémentations de contrôles en fonction de la plateforme/version. Le projet ne prétend donc pas que chaque paragraphe est une vue UIKit native.

## États et accessibilité

Les états préparation, lecture, pause, erreur et vide ont un libellé visible. Une synchronisation par phrase n’est pas représentée comme « mot à mot ». La navigation et les boutons portent des libellés sémantiques ; un paragraphe peut être activé via une action sémantique. Les animations de suivi sont évitées quand la préférence système correspondante est présente.

Deux tests Flutter sont rédigés pour le contraste principal et un en-tête à largeur étroite/texte agrandi. Ils ne sont pas exécutés dans l’environnement de préparation, et ne couvrent pas l’ensemble des écrans. Tester VoiceOver/TalkBack, zoom de texte, orientation, troncatures et contrôles natifs reste obligatoire.
