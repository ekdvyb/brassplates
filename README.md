# BRASSPLATES

**Local-first. Encrypted. Yours.**

BRASSPLATES is a personal IT workspace for notes, how-tos, tasks, project planning, server inventory and diagrams. Everything lives in a local encrypted vault first; cloud sync is optional and end-to-end encrypted.

Publisher: **ZEROBUG INC** · Package: `com.zerobug.brassplates` · Version: `1.0.0`

## Highlights

- **Notes** with rich text (Quill), folders, tags, pinning, autosave, version history and Markdown export.
- **How-Tos** with step-by-step instructions, code blocks, difficulty, categories and "last tested" tracking.
- **Tasks** Kanban board (To Do / Doing / Done), priorities, due dates, subtasks and reminders.
- **Planning** projects with milestones, progress and status.
- **Servers** inventory with encrypted secrets, TCP reachability checks and CSV import/export.
- **Diagrams Studio** with network, database, ERD, FDMS, trading and troubleshooting templates; PNG, SVG and PDF export.
- **Search** across every entity using SQLite FTS5.
- **Never lose data:** soft delete + trash, revision history, automatic snapshots, encrypted backup/restore.
- **Optional sync:** WebDAV / Nextcloud (end-to-end encrypted), Google Drive app-data folder (encrypted), or a local folder.
- Responsive desktop/mobile shell with keyboard shortcuts (`Ctrl+K`, `Ctrl+N`, `Ctrl+D`).

## Security model

- Vault setup derives a 256-bit key with **Argon2id**; data is encrypted with **AES-256-GCM**.
- The vault key is held in memory only and can be locked manually or after an idle timeout.
- Sync payloads are encrypted client-side; sync providers never receive plaintext.
- Server passwords are encrypted with the vault key.
- A recovery key is generated at setup. Store it somewhere safe: without it a forgotten master password cannot be recovered.

## Requirements

- Flutter `3.47.9` (stable) / Dart `3.13.7`
- Desktop builds: Windows 10+ or a Linux distribution with GTK 3.
- Android builds: Android SDK / JDK 17.

## Development

```bash
export PATH=/path/to/flutter/bin:$PATH
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after Drift schema changes
flutter analyze
flutter test
flutter run -d linux      # or windows / an Android device
```

Linux packages for local builds: `clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev libx11-dev libxi-dev`.

## Build artifacts

```bash
flutter build apk --release
flutter build appbundle --release
flutter build windows --release
flutter build linux --release
```

Packaging metadata lives in `windows/installer/brassplates.iss` (Inno Setup) and `linux/nfpm.yaml` (deb/rpm).

## CI / Releases

`.github/workflows/build.yml` runs on pushes, pull requests and tags:

1. `flutter analyze` and `flutter test`.
2. Android APK + AAB.
3. Windows portable zip + Inno Setup installer.
4. Linux tar.gz + `.deb` + `.rpm`.
5. On a `v*` tag, all artifacts are attached to a GitHub Release.

Create a release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

### Android signing

Release builds are signed with the debug key unless a signing config is supplied. To ship a signed APK/AAB, add these repository secrets and configure `android/app/build.gradle.kts` with a `release` signing config:

- `ANDROID_KEYSTORE_BASE64` — base64 of your `.jks` file
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

## Backups

Use **Settings → Backup** to export an encrypted `.bpbackup` file. Restore supports merge or replace (a snapshot is taken first). Automatic snapshots run daily and before destructive operations.

## License

Proprietary — © 2026 ZEROBUG INC. All rights reserved. See `LICENSE`.
