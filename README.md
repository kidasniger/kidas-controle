# KI DAS Contrôle

Application Android native (écrans animés, sans WebView) qui pilote le bot de la Page Facebook :
publication, commentaires, médias, workflows GitHub Actions.

- Le jeton GitHub est saisi dans l'application, chiffré (AES-GCM, Android Keystore) et verrouillé par le code ou l'empreinte de l'écran.
- Aucun secret dans ce dépôt. L'APK est compilé par GitHub Actions et publié dans les Releases.
- Secrets requis pour compiler : `KEYSTORE_B64`, `KEYSTORE_PASSWORD` (alias de clé : `kidas`).

## Mise à jour de l'application

L'application se met à jour toute seule depuis les Releases GitHub :

- Vérification automatique au démarrage (désactivable dans Réglages) et vérification manuelle dans Réglages > Mise à jour de l'application.
- Le numéro de version suit le numéro de run (tag `v104` = version 1.0.104).
- Téléchargement avec reprise, barre de progression, annulation possible.
- Contrôles avant installation : taille, somme SHA-256 (`kidas-controle.apk.sha256`), paquet, version plus récente, signature identique.
- Installation via PackageInstaller ; Android demande l'autorisation « sources inconnues » la première fois.
- Une note de release contenant `[obligatoire]` rend la mise à jour non refermable.
