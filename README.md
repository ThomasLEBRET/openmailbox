# OpenMailbox

Client email cross-platform (macOS + Android) en Flutter/Dart, compatible avec n'importe quel service email via IMAP/SMTP (Gmail, Outlook, ProtonMail, etc.).

## Scope MVP

Une seule boîte email, pas de multi-account, focus sur sync IMAP et composition/lecture.

## Stack

- **UI:** Flutter
- **IMAP/SMTP:** [enough_mail](https://github.com/enough-software/enough_mail)
- **State management:** Riverpod
- **Stockage local:** Isar
- **Credentials:** flutter_secure_storage

## Getting started

```bash
flutter pub get
flutter run -d macos    # ou -d <device-android>
```

## Structure

```
lib/
├── models/       # Email, Folder, IMAPConfig/SMTPConfig
├── providers/    # State management (Riverpod)
├── services/     # imap_service, smtp_service, storage_service
├── screens/      # setup_screen, home_screen, compose_screen
└── widgets/      # email_list_tile, email_reader, folder_sidebar
```

## CI/CD

Tag `vX.Y.Z` déclenche les builds Android (APK) et macOS (DMG) via GitHub Actions, avec release automatique.

## Roadmap post-MVP

Multi-account, recherche full-text, labels, sync incrémental + push, threading, drafts auto-save, pièces jointes, éditeur HTML, dark mode, signature macOS.
