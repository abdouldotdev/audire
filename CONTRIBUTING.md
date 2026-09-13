# Contribuer à Audire

Merci de votre intérêt pour Audire 🙌

## Comment contribuer

1. Ouvrez une issue pour expliquer l’usage ou le bug.
2. Créez une branche dédiée.
3. Implémentez votre correction avec tests (là où c’est possible).
4. Ouvrez une Pull Request claire avec capture / preuve fonctionnelle.

## Exécuter localement

```sh
python3 tool/bootstrap.py
flutter pub get
dart format lib test packages/lisiere_native_tts/lib
flutter analyze --no-fatal-infos
flutter test
```

## Règles de code

- Respecter l’architecture existante (`core`, `data`, `audio`, `ui`).
- Éviter les modifications destructrices des données utilisateur.
- Documenter les choix produit quand la UX change.
- Ajouter des messages d’erreur explicites et compréhensibles.

## Commits

- PR courtes, dédiées à une seule intention.
- Mentionner impact (performance, mémoire, stabilité, UX).

## Sécurité

Si vous trouvez un vulnérabilité, suivez `SECURITY.md` et ne publiez pas de détails public.
