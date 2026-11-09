# Changelog

All notable changes to BRASSPLATES are documented here.

## [1.2.0] - 2026-11-09

- Restore the diagrams module: canvas, shapes, connectors, templates, export,
  and its own database table (schema v3 upgrade keeps existing notes/tasks).
- Show the formatting toolbar at every window size, with headings, font size,
  bold/italic/underline/strike, colours, lists, checklists, quotes, code,
  links, alignment and indentation.
- The window close button now actually closes the app; the tray icon toggles
  the window, and the tray menu can show or quit it.

## [1.1.1] - 2026-11-09

- Fix the Linux package failing to start on Fedora: the RPM now requires
  `libayatana-appindicator-gtk3` (the package that actually provides
  `libayatana-appindicator3.so.1`) instead of `libappindicator-gtk3`.

## [1.1.0] - 2026-11-09

### Changed

- The app is now focused on notes and to-dos only. Server inventory, how-tos,
  project planning and diagrams have been removed, along with their tables.
- New note-and-check logo across the app, tray, Android launcher and Windows icon.
- Sync is now a folder you already sync (Google Drive, OneDrive, Dropbox,
  Syncthing); the in-app WebDAV/Nextcloud and Google sign-in integrations are gone.
- Demo notes, tasks and company-specific example content are no longer seeded;
  existing untouched demo rows are removed on first start.
- Backup format includes note pictures.

### Added

- Attach pictures to a note, view them full size and remove them.
- Share a note as one self-contained HTML file (pictures embedded) and open an
  email draft with the note text.

### Fixed

- Sync changes made within the same second no longer create needless conflict copies.
- Attachment metadata and files now sync between devices.

## [1.0.0] - 2026-11-07

### Added

- Encrypted local vault (Argon2id + AES-256-GCM) with recovery key, auto-lock and biometric unlock.
- Notes with Quill rich text, folders, tags, pinning, autosave, revision history and Markdown export.
- How-Tos with code steps, categories, difficulty and tested tracking.
- Kanban tasks with priorities, due dates, subtasks and reminders.
- Project planning with milestones and progress.
- Server inventory with encrypted secrets, TCP checks and CSV import/export.
- Diagrams Studio with templates, shape stencils, connectors, undo/redo and PNG/SVG/PDF export.
- Full-text search (FTS5), trash with restore, daily snapshots and encrypted backup/restore.
- Optional encrypted sync: WebDAV/Nextcloud, Google Drive app data folder, local folder.
- Responsive desktop/mobile UI, system tray, global hotkey and launch at startup.
- GitHub Actions release pipeline for Android, Windows and Linux (deb/rpm).
