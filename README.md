# OpenMailbox

<p align="center">
  <img src="assets/icon/app_icon.png" width="128" alt="OpenMailbox">
</p>

Client email cross-platform (macOS + Android) en Flutter/Dart, compatible avec n'importe quel service email via IMAP/SMTP (Mailo, Gmail, Outlook, etc.). Interface moderne inspirée de ProtonMail.

## Fonctionnalités

**Comptes**
- Multi-comptes IMAP/SMTP avec switcher, credentials chiffrés (Keychain/Keystore)
- Signature par compte, test de connexion intégré

**Lecture**
- Rendu HTML fidèle (WebView native, JavaScript désactivé)
- Images distantes bloquées par défaut (anti-tracking), chargement à la demande
- Liens cliquables, corps de mails mis en cache (réouverture instantanée)

**Tri & navigation**
- Liste en cartes flottantes, recherche locale instantanée + recherche serveur (IMAP SEARCH)
- Raccourcis clavier : `J`/`K` naviguer, `R` répondre, `F` transférer, `U` lu/non-lu, `⌫` supprimer, `⌘Z` annuler
- Drag & drop des mails vers les dossiers, sélection multiple avec actions groupées
- Étoiles (\Flagged), compteurs par dossier (total + non lus), suppression = corbeille avec annulation

**Écriture**
- Pièces jointes multiples (10 Mo max), Cc/Cci repliables
- Réponses avec citation du message d'origine
- Envoi différé annulable (délai configurable 0–30 s)

**Confort**
- Notifications natives + badge de nouveaux messages
- Panneaux redimensionnables, volet de lecture masquable (lecture plein écran)
- Personnalisation synchronisée entre appareils via IMAP : thème clair/sombre/système, 6 couleurs d'accent, densité, police, taille de texte

## Stack

- **UI :** Flutter (Material 3) · **State :** Riverpod
- **IMAP/SMTP :** [enough_mail](https://github.com/enough-software/enough_mail)
- **Stockage local :** sqflite · **Credentials :** flutter_secure_storage
- **HTML :** webview_flutter (WebKit)

## Développement

```bash
flutter pub get
dart run build_runner build   # génération freezed/json
flutter run -d macos          # ou -d <device-android>
```

macOS nécessite Xcode complet (pas seulement les Command Line Tools) et une identité de signature de développement (Keychain).

## Releases

Un tag `vX.Y.Z` déclenche les builds GitHub Actions : APK Android et DMG macOS attachés à la release.

## Architecture

```
lib/
├── models/       # Email, Folder, MailAccount, AppPrefs (freezed)
├── providers/    # Riverpod : comptes, emails, dossiers, prefs, undo, watcher
├── services/     # imap_service, smtp_service, storage_service, notifications
├── screens/      # home, setup (+ settings), compose, apparence
└── widgets/      # sidebar, tuile email, lecteur
```
