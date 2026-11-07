# KI DAS Contrôle

Application Android (WebView) qui pilote le bot de la Page Facebook :
publication, commentaires, médias, workflows GitHub Actions.

- Le jeton GitHub est saisi dans l'application, chiffré (AES-GCM, Android Keystore) et verrouillé par le code ou l'empreinte de l'écran.
- Aucun secret dans ce dépôt. L'APK est compilé par GitHub Actions et publié dans les Releases.
- Secrets requis pour compiler : `KEYSTORE_B64`, `KEYSTORE_PASSWORD` (alias de clé : `kidas`).
