# Déclaration App Privacy — Audire

## Proposition pour App Store Connect

**Réponse proposée : aucune donnée collectée.**

Cette réponse est fondée sur l’inspection du projet le 14 septembre 2026 : aucun SDK d’analytics, de publicité, de tracking, de crash reporting distant, de compte utilisateur, de microphone ou de synchronisation cloud applicative n’est déclaré. Les livres, les réglages, le cache audio et la progression sont conservés dans le stockage privé de l’appareil.

## Ce qui ne doit pas être déclaré comme collecte

- Import EPUB/PDF : le fichier reste local ; son texte n’est pas téléversé pour lecture ou traduction.
- Synthèse vocale : l’audio est généré sur l’appareil.
- Modèles de voix et de traduction : un téléchargement volontaire contacte un dépôt de modèles public, sans envoyer le livre, le passage lu ou un compte utilisateur.
- Journaux locaux : ils restent locaux tant qu’aucune fonction d’envoi de diagnostic n’est ajoutée.

## Vérification obligatoire avant validation Apple

1. Sur une installation propre, activer l’enregistrement réseau système.
2. Importer un EPUB/PDF, lancer la lecture et la traduction locale.
3. Installer puis supprimer un modèle.
4. Vérifier qu’aucun contenu de livre, identifiant publicitaire, identifiant utilisateur ou événement analytique n’est envoyé.
5. Vérifier que les seules destinations sortantes sont les téléchargements explicites de modèles : Mozilla Translations / Hugging Face, selon le choix de l’utilisateur.

Si l’un de ces contrôles révèle un envoi de contenu, de diagnostic distant ou d’identifiant persistant, ne pas sélectionner « aucune donnée collectée » : mettre à jour la déclaration et la politique de confidentialité avant de soumettre.

## Réponses App Review à conserver

- Aucun compte requis.
- Aucun suivi inter-apps ou sites tiers.
- Aucun microphone requis.
- Les modèles sont optionnels et déclenchés par l’utilisateur.

Cette fiche est une préparation produit et ne remplace pas la revue d’un conseil juridique ou la vérification finale dans App Store Connect.
