# BRASSPLATES

**Notes and tasks. Local-first. Yours.**

BRASSPLATES is a small personal app for notes and to-dos. It works offline,
keeps everything in a local encrypted vault, and syncs between your own devices
through a folder you choose — no account, no company server, no telemetry.

Package: `com.zerobug.brassplates` · Version: `1.2.0`

## What it does

- **Notes** with rich text (Quill), pinning, tags, version history and Markdown export.
- **Pictures** attached to a note, stored with the note and included in email/share copies.
- **Tasks** on a simple board (To Do / Doing / Done) with priorities, due dates and subtasks.
- **Search** across notes and tasks (SQLite FTS5).
- **Trash** with restore, plus daily local snapshots.
- **Encrypted backups** you can copy to Google Drive, OneDrive, a USB drive or anywhere else.
- **Sync between laptop and phone** through a folder that a cloud client already syncs
  (Google Drive, OneDrive, Dropbox, Syncthing, a network share). BRASSPLATES only
  writes encrypted files; the provider never sees readable notes.

## Security model

- Vault setup derives a 256-bit key with **Argon2id**; data is encrypted with **AES-256-GCM**.
- The vault key is held in memory only and can be locked manually or after an idle timeout.
- Sync payloads and backups are encrypted on the device before they leave it.
- No network code and no third-party analytics are bundled.

## Requirements

- Flutter `3.47.9` (stable) / Dart `3.13.7`
- Desktop: Windows 10+ or a Linux distribution with GTK 3.
- Android: Android SDK / JDK 17.

## Development

```bash
flutter pub get
dart run build_runner build          # after Drift schema changes
flutter analyze
flutter test
flutter run -d linux                 # or windows / an Android device
```

Linux packages needed for local builds: `clang cmake ninja-build pkg-config libgtk-3-dev
liblzma-dev libstdc++-12-dev libx11-dev libxi-dev libayatana-appindicator3-dev`.

## Build artifacts

```bash
flutter build linux --release
flutter build apk --release
flutter build windows --release
```

Packaging metadata lives in `windows/installer/brassplates.iss` (Inno Setup) and
`linux/nfpm.yaml` (deb/rpm).

### RPM / DEB

The CI job uses [nfpm](https://nfpm.goreleaser.com). To build the RPM locally:

```bash
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //; s/+.*//')
sed "s/\${VERSION}/$VERSION/" linux/nfpm.yaml > /tmp/nfpm.yaml
nfpm package --config /tmp/nfpm.yaml --packager rpm --target dist/
sudo dnf install dist/brassplates-$VERSION-1.x86_64.rpm   # Fedora
```

The RPM requires `gtk3` and `libayatana-appindicator-gtk3` (the Fedora package
that provides `libayatana-appindicator3.so.1`), so use `dnf` rather than
`rpm -i --nodeps` on a clean machine. The package installs to
`/opt/brassplates` with a `/usr/bin/brassplates` symlink, a desktop entry and
the app icon.

## Syncing two devices

1. Install a folder-sync client on both devices (for example Google Drive desktop,
   OneDrive, Dropbox or Syncthing).
2. Create one folder for BRASSPLATES, e.g. `BRASSPLATES`.
3. In the app open **Settings → Sync between devices**, choose **Synced folder**,
   point it at that folder and save.
4. Repeat on the other device, pointing at the same synced folder, then press
   **Sync now** on both.

Notes, tasks and pictures travel as encrypted files. If the same note changed on
both devices, the newer change wins and a conflict copy is kept.

## CI / Releases

`.github/workflows/build.yml` runs on pushes, pull requests and tags:

1. `flutter analyze` and `flutter test`.
2. Android APK + AAB.
3. Windows portable zip + Inno Setup installer.
4. Linux tar.gz + `.deb` + `.rpm`.
5. On a `v*` tag, all artifacts are attached to a GitHub Release.

## License

Proprietary — © 2026. All rights reserved. See `LICENSE`.
