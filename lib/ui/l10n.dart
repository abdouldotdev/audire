import 'package:flutter/widgets.dart';

import '../domain/settings.dart';

/// Small, dependency-free copy layer. The reader only ships French and English
/// content today, so keeping translations next to the product copy makes gaps
/// obvious instead of silently falling back to a machine translation.
class AppCopy {
  const AppCopy._(this.english);

  final bool english;

  static AppCopy of(BuildContext context) => AppCopy._(
    Localizations.localeOf(context).languageCode.toLowerCase() == 'en',
  );

  String text(String french) => english ? (_english[french] ?? french) : french;

  String language(ReaderLanguage value) => switch (value) {
    ReaderLanguage.french => english ? 'French' : 'Français',
    ReaderLanguage.english => english ? 'English' : 'Anglais',
  };

  String interfaceLanguage(AppLanguage value) => switch (value) {
    AppLanguage.system => english ? 'System' : 'Système',
    AppLanguage.french => 'Français',
    AppLanguage.english => 'English',
  };
}

extension LocalizedText on String {
  String tr(BuildContext context) => AppCopy.of(context).text(this);
}

extension LocalizedReaderLanguage on ReaderLanguage {
  String localized(BuildContext context) => AppCopy.of(context).language(this);
}

const Map<String, String> _english = {
  'Bibliothèque': 'Library',
  'Voix': 'Voices',
  'Profil': 'Profile',
  'Préférences': 'Preferences',
  'Lecture': 'Reading',
  'Claire': 'Light',
  'Sombre': 'Dark',
  'Système': 'System',
  'Langues': 'Languages',
  'Langue de l’app': 'App language',
  'Langue source': 'Book language',
  'Langue de la voix': 'Listening language',
  'Retour': 'Back',
  'Lire': 'Read',
  'Écouter': 'Listen',
  'Traduire': 'Translate',
  'Le plaisir de lire.\nLa liberté d’écouter.':
      'The joy of reading.\nThe freedom to listen.',
  'Vos livres vous suivent.\nMême quand vos yeux font une pause.':
      'Your books stay with you.\nEven when your eyes take a break.',
  'Dans votre langue.': 'In your language.',
  'Un livre à lire. Une voix à retrouver.':
      'A book to read. A voice to return to.',
  'La langue de vos livres': 'Your books’ language',
  'La langue de votre écoute': 'Your listening language',
  'Vous pourrez ajuster ces choix pour chaque livre.':
      'You can fine-tune these choices for every book.',
  'Le pack de traduction pourra être téléchargé à l’étape suivante.':
      'The translation pack can be downloaded in the next step.',
  'La lecture en anglais d’un livre français n’est pas encore disponible.':
      'Reading a French book in English is not available yet.',
  'Une voix.\nTout un univers.': 'One voice.\nA whole world.',
  'Trouvez votre voix.': 'Find your voice.',
  'L’écoute, à votre façon.': 'Listening, your way.',
  'Voix anglaise du téléphone': 'English phone voice',
  'Utilise la voix intégrée à votre iPhone':
      'Uses the voice built into your iPhone',
  'Voix françaises': 'French voices',
  '10 voix disponibles': '10 voices available',
  'Prêtes à écouter': 'Ready to listen',
  'Téléchargement inclus dans votre configuration':
      'Download included with your setup',
  'Traduction anglais → français': 'English → French translation',
  'Lire et écouter vos livres anglais en français':
      'Read and listen to your English books in French',
  'Déjà téléchargée': 'Already downloaded',
  'Annulation…': 'Cancelling…',
  'Annuler le téléchargement': 'Cancel download',
  'Téléchargement en cours': 'Downloading',
  'Préparation': 'Preparing',
  'Commencer mon voyage': 'Start my journey',
  'Choisir mes téléchargements': 'Choose my downloads',
  'Préparation en cours…': 'Getting things ready…',
  'Téléchargement en cours…': 'Downloading…',
  'Télécharger et commencer': 'Download and start',
  'Réessayer le téléchargement': 'Try download again',
  'Ouvrir ma bibliothèque': 'Open my library',
  'Impossible de terminer. Réessayez.': 'Could not finish. Please try again.',
  'Téléchargement annulé. Touchez pour réessayer.':
      'Download cancelled. Tap to try again.',
  'La traduction n’a pas pu être téléchargée. Touchez pour réessayer.':
      'The translation could not be downloaded. Tap to try again.',
  'Les voix françaises n’ont pas pu être téléchargées. Touchez pour réessayer.':
      'The French voices could not be downloaded. Tap to try again.',
  'Typographie et vitesse': 'Type and speed',
  'Vos livres': 'Your books',
  'Importer un document': 'Import a document',
  'Import du document…': 'Importing document…',
  'EPUB ou PDF': 'EPUB or PDF',
  'Livres': 'Books',
  'Un titre, un auteur…': 'A title, an author…',
  'Aucun livre ne correspond.': 'No matching books.',
  'Aucun livre importé.': 'No books imported yet.',
  'chapitres': 'chapters',
  'pages': 'pages',
  'Reprendre': 'Resume',
  'Ouvrir': 'Open',
  'Retirer': 'Remove',
  'Annuler': 'Cancel',
  'Retirer ce livre ?': 'Remove this book?',
  'Packs locaux': 'On-device packs',
  'Afficher le bilingue': 'Show both languages',
  'Garder le texte anglais visible et afficher la traduction française du passage actif.':
      'Keep the English text visible and show the French translation for the active passage.',
  'Moteur': 'Engine',
  'Langue du livre': 'Book language',
  'Recommandé · rapide · français et anglais':
      'Recommended · fast · French and English',
  'Voix premium · français et anglais': 'Premium voices · French and English',
  'Incompatible avec ce modèle détecté': 'Not compatible with this device',
  'Très efficace · voix anglaises': 'Very efficient · English voices',
  'Uniquement pour la voix anglaise': 'English voice only',
  'Voix du téléphone': 'Phone voices',
  'Sans téléchargement · qualité variable': 'No download · variable quality',
  'Recherche…': 'Searching…',
  'Recharger': 'Refresh',
  'Voix locales': 'On-device voices',
  'Aperçu de la voix': 'Voice preview',
  'Préparation locale…': 'Preparing on device…',
  'Ouvrir le lecteur': 'Open reader',
  'Mettre en pause': 'Pause',
  'Arrêter l’aperçu': 'Stop preview',
  'Choisissez un livre dans la bibliothèque.':
      'Choose a book from your library.',
  'Aucun passage à afficher.': 'Nothing to display.',
  'Réglages audio': 'Audio settings',
  'Vitesse de lecture': 'Playback speed',
  'Passage précédent': 'Previous passage',
  'Passage suivant': 'Next passage',
  'Préparer': 'Prepare',
  'Audio': 'Audio',
  'Chapitres': 'Chapters',
  'Chapitre': 'Chapter',
  'Page du document': 'Document page',
  'Confort de lecture': 'Reading comfort',
  'Taille du texte': 'Text size',
  'Vitesse de la voix': 'Voice speed',
  'Suivre la voix': 'Follow the voice',
  'Le texte avance avec la narration. Un défilement manuel reste possible.':
      'The text follows narration. You can still scroll manually.',
  'Traduction du passage sélectionné': 'Selected passage translation',
  'Fermer la traduction': 'Close translation',
  'Traduction en cours…': 'Translating…',
  'La traduction n’a pas abouti.': 'Translation did not complete.',
  'Réessayer': 'Try again',
  'Copié': 'Copied',
  'Copier la traduction': 'Copy translation',
};
