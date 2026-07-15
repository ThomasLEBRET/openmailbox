# Changelog

## [Unreleased] — 0.1.0

### Ajouté
- Client IMAP/SMTP complet : sync des dossiers avec compteurs, lecture HTML (WebView), composition avec pièces jointes (≤ 10 Mo)
- Multi-comptes avec switcher, credentials chiffrés par compte
- Recherche locale instantanée + recherche serveur (IMAP SEARCH)
- Raccourcis clavier (J/K, R, F, U, ⌫, ⌘Z), drag & drop vers les dossiers
- Sélection multiple et actions groupées, étoiles (\Flagged)
- Réponses avec citation, signature par compte, envoi différé annulable (0–30 s)
- Notifications natives + badge, blocage des images distantes
- Personnalisation synchronisée via IMAP : thème, accent, densité, police, taille, largeurs de panneaux, volet de lecture masquable
- Annulation (⌘Z) des actions : lu/non-lu, étoile, déplacement, suppression
- Icône d'app, fenêtre maximisée au lancement (macOS)
- CI/CD GitHub Actions : APK + DMG sur tag `v*`

### Notes techniques
- Connexions IMAP persistantes (interactive + arrière-plan) avec keepalive, timeouts et sérialisation des opérations
- Cache SQLite scopé par compte (métadonnées, corps, dossiers)
- Migration automatique depuis le format mono-compte
