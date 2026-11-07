# Système de mise à jour KI DAS Contrôle

## Fonctionnement

L'application interroge au démarrage l'API publique :

`https://api.github.com/repos/kidasniger/kidas-controle/releases/latest`

La version du tag est comparée à `versionName` avec SemVer 2.0.0. Une version identique ou inférieure ne déclenche jamais une proposition de mise à jour.

Lorsqu'une version supérieure est publiée, l'écran Paramètres affiche la version, la date, les notes et la taille de l'APK. Le téléchargement est déclenché par l'utilisateur, écrit dans le cache privé de l'application et passe d'abord par un fichier `.part`. La taille et le SHA-256 sont contrôlés avant de rendre l'APK installable.

Le lancement de l'installation passe par Android `FileProvider` et l'installateur système. Android conserve les données de l'application lors d'une mise à niveau signée avec la même clé et le même identifiant de package. L'utilisateur doit autoriser les installations pour cette application et confirmer l'installation.

## Secrets GitHub requis

Dans Settings > Secrets and variables > Actions, configurer :

- `KEYSTORE_B64` : keystore Android encodé en Base64.
- `KEYSTORE_PASSWORD` : mot de passe du keystore et de la clé (ce workflow conserve l'alias historique `kidas`).

Le fichier de signature et les mots de passe ne sont jamais stockés dans le dépôt. Le keystore doit être exactement celui qui a signé l'APK déjà distribué, sinon Android refusera la mise à niveau.

## Publication automatique

Chaque push sur `main` déclenche les tests unitaires, puis la compilation signée. Si les étapes réussissent, le workflow crée un tag `v1.0.N`, publie l'APK et `SHA256SUMS.txt` dans une GitHub Release. Le numéro `N` provient du numéro d'exécution GitHub Actions, et une vérification empêche de réutiliser un tag existant.

La concurrence est limitée à une exécution par branche : un nouveau push annule l'exécution précédente afin que seule la dernière version de `main` puisse être publiée.

## Tests

Les tests unitaires vérifient les comparaisons SemVer numériques, l'égalité, les versions inférieures et la priorité des préversions. Les tests réseau réels, le flux de l'installateur Android et la conservation des données doivent être validés sur un appareil ou émulateur Android ; ils ne peuvent pas être prouvés par les seuls tests unitaires JVM.
