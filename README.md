# KI DAS Contrôle

Application Android native de pilotage du bot Facebook, développée en **Kotlin**, **Jetpack Compose** et **Material 3**. L'application ne repose pas sur WebView ni sur des pages HTML.

## Fonctionnalités

- Tableau de bord : état du bot, statistiques, actions rapides et exécutions GitHub Actions.
- Publication : préparation et mise en file de publications.
- Avis : consultation des commentaires et préparation des réponses.
- Médias : consultation des médias du dépôt de données.
- Bot : contrôle des automatisations et de la surveillance.
- Réglages : dépôts GitHub, sécurité, apparence et mises à jour.
- Mise à jour de l'application depuis les Releases GitHub, avec vérification SHA-256 avant installation.

## Architecture

```text
app/src/main/
├── AndroidManifest.xml
├── java/com/kidas/controle/
│   ├── MainActivity.kt
│   ├── data/          # Client GitHub et accès aux dépôts
│   ├── security/      # Coffre Android Keystore et authentification
│   ├── ui/
│   │   ├── bot/
│   │   ├── comments/
│   │   ├── components/
│   │   ├── home/
│   │   ├── media/
│   │   ├── nav/
│   │   ├── publish/
│   │   ├── settings/
│   │   └── theme/
│   └── updater/       # Recherche, téléchargement et validation des mises à jour
└── res/               # Icône adaptative, thème, splash screen et FileProvider
```

Les responsabilités sont séparées entre l'accès aux données, la sécurité, les écrans Compose, la navigation et le système de mise à jour. Les secrets ne doivent jamais être ajoutés au dépôt.

## Configuration technique

- Application ID : `com.kidas.controle`
- Kotlin et Jetpack Compose
- Material 3
- Java 17
- Android : minSdk 26, targetSdk 34, compileSdk 34
- Gradle 8.7
- Android Gradle Plugin 8.5.2

## Compilation et publication

Le workflow GitHub Actions de `.github/workflows/build.yml` exécute les tests JVM, compile l'APK signé, calcule son empreinte SHA-256 et publie une Release sur la branche `main`.

Dans **Settings → Secrets and variables → Actions**, configurer les secrets suivants :

| Secret | Contenu |
|---|---|
| `KEYSTORE_B64` | Keystore Android encodé en Base64 |
| `KEYSTORE_PASSWORD` | Mot de passe du keystore et de la clé |

L'alias attendu est `kidas`. Le keystore doit rester identique à celui des versions déjà installées pour permettre les mises à niveau. Ne jamais commiter le keystore, son mot de passe, un jeton GitHub ou un fichier de configuration contenant des secrets.

## Dépôts pilotés

- `kidasniger/facebook-data` : données JSON et médias de la Page.
- `kidasniger/facebook-manager` : workflows GitHub Actions et variables du bot.

L'application utilise un jeton GitHub fourni par l'utilisateur, protégé par Android Keystore. Les droits du jeton doivent être limités aux dépôts et opérations nécessaires.

## Vérifications avant publication

1. Exécuter `gradle --no-daemon :app:testDebugUnitTest`.
2. Exécuter `gradle --no-daemon assembleDebug`.
3. Vérifier la compilation release et la signature dans GitHub Actions.
4. Installer l'APK sur un téléphone Android 8.0 ou plus récent.
5. Tester l'authentification, les écrans, les opérations GitHub, le mode hors ligne, la rotation, le thème sombre et le parcours de mise à jour.
6. Vérifier qu'aucun jeton ou secret n'est affiché ni écrit dans les journaux.

Consulter [docs/MISE-A-JOUR.md](docs/MISE-A-JOUR.md) pour le fonctionnement détaillé du mécanisme de mise à jour.
