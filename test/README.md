# Tests de Baxa

Deux familles de tests, à lancer depuis la racine du projet (terminal de VS Code).

## 1. Règles métier de l'app — `test/business/`

```
flutter test
```

Réservations (limites, écarts entre créneaux, fermeture des files), calculs de
l'agenda, génération des créneaux. Firebase est **simulé en mémoire** : aucune
donnée réelle n'est touchée. Durée : quelques secondes.

## 2. Règles de sécurité Firestore — `test/firestore_rules/`

```
node test/firestore_rules/run.mjs
```

Vérifie qui peut lire ou modifier quoi (visiteur, client, admin, staff) sur un
**émulateur local** avec des données fictives. À relancer après chaque
modification de `firestore.rules`. Durée : environ 1 minute (le premier
lancement télécharge l'émulateur).

Prérequis : Java 17 ou plus. L'outil Firebase est volontairement épinglé en
version 13 (la dernière compatible Java 17).

## Lire les résultats

- **Test réussi** : le comportement est celui attendu.
- **Test échoué** : un changement a cassé quelque chose, à corriger.
- **Test marqué `skip` (Flutter) ou `todo` (sécurité)** : un **défaut connu**,
  décrit dans le message du test, pas encore corrigé. Il est affiché mais ne
  fait pas échouer la suite. Une fois le défaut corrigé, retirer la mention
  `skip` / `todo` pour que le test protège la correction.
