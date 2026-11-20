# Refonte progressive — KI DAS Contrôle

## Décisions produit
- Direction visuelle : moderne, sobre, claire, avec accent bleu réservé aux actions principales.
- Livraison progressive : chaque phase doit rester compilable et testable.
- Compatibilité : conserver applicationId `com.kidas.controle`, signature de publication, versionnement, migration du coffre Java v1 et données distantes.
- Fonctions demandées : notifications, conversations, rapports, diagnostics, recherche globale, sauvegarde/restauration.

## Architecture cible
- Présentation : écrans Flutter, composants partagés, navigation et thèmes.
- Domaine : modèles, cas d'utilisation, validation et règles de statut.
- Données : client GitHub existant, dépôts de données, cache local et stockage sécurisé.
- Intégration : bot central dans `kidasniger/facebook-manager`; l'APK observe son état et ses résultats, sans prétendre exécuter les actions Facebook localement.

## Phases
### 0 — Préservation et audit
- Branche de sauvegarde immuable et branche de travail isolée.
- Vérifier l'identifiant Android, la signature, les versions, le coffre et les workflows.
- Ne supprimer aucun code Java historique avant d'avoir prouvé qu'il n'est plus nécessaire.

### 1 — Fondations et diagnostic
- Centraliser les contrôles de connectivité, authentification GitHub, accès au dépôt du bot et état du dernier workflow.
- Afficher les résultats horodatés, avec distinction entre succès, avertissement et échec.
- Ne jamais journaliser ni afficher le jeton GitHub.

### 2 — Notifications
- Regrouper les alertes locales (jeton, urgences, erreurs, fin de session).
- Historique local, déduplication, préférences par catégorie et gestion des permissions Android.
- Les notifications ne doivent jamais bloquer les opérations principales.

### 3 — Recherche et conversations
- Recherche unifiée dans les commentaires, conversations et publications déjà synchronisés.
- Filtres par type, état, période et publication.
- Vue conversation avec chronologie et réponses imbriquées quand les données source les fournissent.
- Respecter les limites de l'API et signaler la date de fraîcheur des données.

### 4 — Rapports
- Bilans journaliers/hebdomadaires calculés uniquement à partir des événements et statistiques disponibles.
- Distinguer les actions tentées, confirmées par le bot et confirmées par Facebook.
- Export partageable, avec données sensibles exclues.

### 5 — Sauvegarde/restauration
- Sauvegarder les préférences et références de dépôts.
- Exclure par défaut les jetons, mots de passe, clés et secrets.
- Valider le format et la version du fichier avant restauration.
- Ne jamais écraser les identifiants sécurisés existants.

### 6 — Qualité et publication
- Tests unitaires des services et modèles, tests de widgets et analyse Flutter.
- Build Android debug puis release signé.
- Vérifier installation par-dessus la version publiée, conservation des données et mécanisme d'update.
- Publier uniquement après validation des workflows et de la signature.

## Critères d'acceptation
- Aucun changement de package Android ou de clé de signature.
- Aucun secret inclus dans une sauvegarde, un rapport ou un log.
- Les états du bot sont dérivés des réponses GitHub, avec date et erreurs explicites.
- Les fonctions réseau tolèrent timeout, absence de réseau et droits insuffisants.
- Chaque phase dispose de tests reproductibles et d'un APK de contrôle si elle modifie l'interface.
