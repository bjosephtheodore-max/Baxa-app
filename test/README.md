# Tests de Baxa

Deux familles de tests, à lancer depuis la racine du projet (terminal de VS Code).

## 1. Règles métier de l'app — `test/business/`

```
flutter test
```

Réservations (limites, écarts entre créneaux, fermeture des files), calculs de
l'agenda, règles des plages. Firebase est **simulé en mémoire** : aucune
donnée réelle n'est touchée. Durée : quelques secondes.

## 2. Règles de sécurité Firestore et fonctions serveur — `test/firestore_rules/`, `test/server/`

```
node test/firestore_rules/run.mjs
```

Vérifie qui peut lire ou modifier quoi (visiteur, client, admin, staff), puis
les fonctions serveur qui écrivent réservations, créneaux et compteurs :
`booking` (client), `companyAccount` (inscription et rôle de la structure),
`companyBooking` (guichet, blocage, fermetures, départ) et `companySchedule`
(plages, créneaux, génération). Tout tourne sur un **émulateur local** avec
des données fictives. À relancer après chaque modification de
`firestore.rules` ou de `functions/`. Durée : environ 1 minute (le premier
lancement télécharge l'émulateur).

Les petits tests propres au dossier `functions/` (fuseaux, réveils…) se
lancent avec `npm test` depuis `functions/`.

Prérequis : Java 17 ou plus. L'outil Firebase est volontairement épinglé en
version 13 (la dernière compatible Java 17).

## Lire les résultats

- **Test réussi** : le comportement est celui attendu.
- **Test échoué** : un changement a cassé quelque chose, à corriger.
- **Test marqué `skip` (Flutter) ou `todo` (sécurité)** : un **défaut connu**,
  décrit dans le message du test, pas encore corrigé. Il est affiché mais ne
  fait pas échouer la suite. Une fois le défaut corrigé, retirer la mention
  `skip` / `todo` pour que le test protège la correction.
