# KI DAS Contrôle

Application Android **Flutter** (écrans animés, sans WebView) qui pilote le bot de la Page Facebook :
publication, commentaires, médias, statistiques, workflows GitHub Actions.

Design « Noir & blanc + » validé en maquette : fond noir (ou blanc selon le réglage
Système/Clair/Sombre), accents bleu Facebook `#1877F2` réservés aux actions principales,
navigation en pilule flottante, retour tactile (vibration + tic de 40 ms, désactivable).

- Le jeton GitHub est saisi dans l'application, chiffré (Android Keystore via flutter_secure_storage)
  et verrouillé par le code ou l'empreinte de l'écran. Migration automatique du coffre de la v1 Java.
- Aucun secret dans ce dépôt. L'APK est compilé par GitHub Actions et publié dans les Releases.
- Secrets requis pour compiler : `KEYSTORE_B64`, `KEYSTORE_PASSWORD` (alias de clé : `kidas`).

## Structure

- `lib/` — application Dart : `core/` (API GitHub, stockage, mises à jour, sons),
  `screens/` (les 10 écrans), `ui/` (design system, graphiques, formulaires), `widgets/` (pilule).
- `android/` — hôte Android + pont natif Kotlin (`kidas/native` : version installée,
  migration du coffre v1, vérification et installation des APK).
- `app/` — code source de la v1 Java, conservé comme référence historique (non compilé).

## Mise à jour de l'application

L'application se met à jour toute seule depuis les Releases GitHub :

- Vérification automatique au démarrage (désactivable dans Réglages) et vérification manuelle dans Réglages > Mise à jour de l'application.
- Le numéro de version suit le numéro de run (tag `v104` = version 1.0.104).
- Téléchargement avec reprise, barre de progression, annulation possible.
- Contrôles avant installation : taille, somme SHA-256 (`kidas-controle.apk.sha256`), paquet, version plus récente, signature identique.
- Installation via PackageInstaller ; Android demande l'autorisation « sources inconnues » la première fois.
- Une note de release contenant `[obligatoire]` rend la mise à jour non refermable.

## Compiler

```bash
flutter pub get
flutter analyze --no-pub --no-fatal-infos
flutter test
flutter build apk --release
```
