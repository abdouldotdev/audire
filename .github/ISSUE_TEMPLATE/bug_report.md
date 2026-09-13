name: Bug report
description: Signaler un bug reproductible
title: "[Bug] "
labels: [bug]
assignees: []

body:
  - type: markdown
    attributes:
      value: |
        Merci de décrire précisément le problème.
  - type: textarea
    id: description
    attributes:
      label: Description
      description: Ce qui se passe et ce qui est attendu.
      required: true
  - type: input
    id: device
    attributes:
      label: Appareil / OS
      description: Exemple iPhone 15 Pro, iOS 18.5.1
      required: true
  - type: input
    id: version
    attributes:
      label: Version de l’app
      required: true
  - type: textarea
    id: steps
    attributes:
      label: Étapes pour reproduire
      required: true
  - type: textarea
    id: logs
    attributes:
      label: Logs
      description: Collez les logs utiles (si possible).
