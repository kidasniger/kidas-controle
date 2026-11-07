# Système de mise à jour KI DAS Contrôle

## Fonctionnement

Au démarrage, l'application consulte l'API publique :
`https://api.github.com/repos/kidasniger/kidas-controle/releases/latest`

Le tag distant est comparé à la version installée avec SemVer 2.0.0. Une version identique ou inférieure ne déclenche aucune proposition. Une release sans APK est signalée comme erreur.

Le téléchargement se fait à la demande, dans le cache privé de l'application. Les octets reçus alimentent la progression. Le fichier temporaire `.part` n'est renommé en APK qu'après vérification de la taille et du SHA-256. Le SHA-256 est lu depuis le champ `digest` de GitHub ou depuis `SHA256SUMS.txt`. Un téléchargement déjà présent n'est réutilisé qu'après contrôle de sa taille et de son empreinte.

L'installation utilise `FileProvider` et l'installateur Android. Android exige l'autorisation d'installer des applications provenant de KI DAS et la confirmation de l'utilisateur. Android conserve les données de l'application lorsqu'il s'agit d'une mise à niveau du même package signée par la même clé.

## Secrets GitHub

Dans Settings > Secrets and variables > Actions :

- `KEYSTORE_B64` : keystore Android encodé en Base64.
- `KEYSTORE_PASSWORD` : mot de passe du keystore et de la clé.

L'alias de clé attendu est `kidas`. Le keystore doit être identique à celui qui a signé la version installée, sinon Android refusera la mise à niveau. Aucun keystore ni mot de passe ne doit être commité dans le dépôt.

## Publication

Chaque push sur `main` déclenche les tests JVM, la compilation signée et, uniquement si les étapes précédentes réussissent, la publication d'une release. Le numéro de version `1.0.N` utilise le numéro d'exécution GitHub Actions. Le workflow vérifie que le tag n'existe pas, crée `v1.0.N`, génère les notes de release, publie l'APK et `SHA256SUMS.txt`.

Une seule exécution est autorisée à publier à la fois : un push plus récent annule le travail précédent sur la branche.

## Validation

Les tests JVM vérifient l'ordre numérique des versions, l'égalité, les versions inférieures et la priorité des préversions. Les scénarios réseau, téléchargement interrompu, empreinte corrompue, autorisation système, annulation de l'installation et conservation des données nécessitent une validation sur appareil/émulateur Android avec une release signée.
