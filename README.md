# NoteX

A beautiful, cross-platform desktop notes app built with Flutter.
Rich text editing, Markdown support, daily notes, cloud sync via Supabase, and automatic update notifications — all packaged as a native app for **Windows**, **macOS**, and **Linux**.

---

## Features

| Feature | Description |
|---|---|
| **Rich Text Editor** | Full WYSIWYG editing powered by Flutter Quill (bold, italic, headings, lists, code blocks…) |
| **Markdown Editor** | Toggle to a side-by-side Markdown editor with live preview |
| **Daily Notes** | A note is automatically created each day and opened at startup |
| **Projects / Folders** | Organise notes into colour-coded projects; filter from the sidebar |
| **Pinned Notes** | Pin important notes to a dedicated tab for quick access |
| **Full-Text Search** | Instant search across all titles and content via a floating dropdown |
| **Calendar View** | Browse notes by date on a monthly calendar |
| **Focus Timer** | Built-in Pomodoro-style timer to stay productive |
| **Auto-Save** | Notes are saved automatically 800 ms after you stop typing |
| **Cloud Sync** | Optional sign-in (Google or email) syncs notes across devices via Supabase |
| **Beautiful Theming** | 10+ accent colours, dark / light mode, animated wallpaper backgrounds |
| **Auto-Update** | The app checks GitHub Releases on startup and notifies you when a new version is available |

---

## Architecture

NoteX follows **Hexagonal Architecture** (Ports & Adapters) with Domain-Driven Design principles:

```
lib/
├── domain/          # Entities, repositories (interfaces), domain services
├── application/     # Use cases — orchestrate domain objects
├── infrastructure/  # Adapters: Drift (SQLite), Supabase, GitHub API, …
└── presentation/    # Flutter widgets, pages, state (ChangeNotifier)
```

Dependency injection is handled by **GetIt**; all wiring lives in `lib/injection.dart`.

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel, ≥ 3.11)
- A [Supabase](https://supabase.com) project (free tier works great)

### 1 — Clone

```bash
git clone https://github.com/ismaelosuna7824/noteX.git
cd noteX/notex
```

### 2 — Configure secrets

NoteX reads sensitive credentials from **compile-time defines** — they are never stored in source code.

```bash
# Copy the template
cp dart_defines.json.example dart_defines.json
```

Open `dart_defines.json` and fill in your values:

```json
{
  "SUPABASE_URL": "https://your-project-id.supabase.co",
  "SUPABASE_ANON_KEY": "your-supabase-anon-key"
}
```

> `dart_defines.json` is listed in `.gitignore` and will never be committed.

### 3 — Install dependencies

```bash
flutter pub get
```

### 4 — Run

```bash
# Windows
flutter run -d windows --dart-define-from-file=dart_defines.json

# macOS
flutter run -d macos --dart-define-from-file=dart_defines.json

# Linux
flutter run -d linux --dart-define-from-file=dart_defines.json
```

---

## Building a release

```bash
# Windows
flutter build windows --release --dart-define-from-file=dart_defines.json

# macOS
flutter build macos --release --dart-define-from-file=dart_defines.json

# Linux
flutter build linux --release --dart-define-from-file=dart_defines.json
```

---

## CI / CD — Automated releases

The repository includes a GitHub Actions workflow (`.github/workflows/release.yml`) that:

1. Triggers when you push a tag that matches `v*` (e.g. `v1.1.0`)
2. Builds native binaries for Windows, macOS, and Linux in parallel
3. Creates a GitHub Release and attaches the archives automatically

### How to publish a new version

> ⚠️ The tag version **must match** `currentVersion` in `AppConfig` — otherwise the auto-updater shows a false "update available" banner to users who already have the latest build.

**Step 1 — Bump the two version strings**

`pubspec.yaml`:
```yaml
version: 1.1.0+2   # number before + = public version, after + = build number
```

`lib/infrastructure/config/app_config.dart`:
```dart
static const String currentVersion = '1.1.0';  // must match the tag
```

**Step 2 — Commit and push**

```bash
git add pubspec.yaml lib/infrastructure/config/app_config.dart
git commit -m "chore: bump version to 1.1.0"
git push
```

**Step 3 — Tag and push**

PowerShell (Windows):
```powershell
git tag v1.1.0
git push origin v1.1.0
```

Bash (macOS / Linux):
```bash
git tag v1.1.0 && git push origin v1.1.0
```

The GitHub Actions workflow picks up the tag, builds for all three platforms, and creates the Release automatically.

### Required repository secrets

Go to **Settings → Secrets and variables → Actions** in your GitHub repository and add:

| Secret name | Value |
|---|---|
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_ANON_KEY` | Your Supabase anon/public key |

The workflow passes these to Flutter via `--dart-define` so no secret is embedded in the repository.

---

## Supabase setup

1. Create a new project at [supabase.com](https://supabase.com).
2. Enable **Email** and/or **Google** authentication in **Authentication → Providers**.
3. For Google OAuth, add your OAuth credentials in the Supabase dashboard and configure the redirect URL.
4. Copy your project URL and `anon` key into `dart_defines.json`.

The app uses Row-Level Security (RLS) — each user only sees their own notes.

---

## Key dependencies

| Package | Purpose |
|---|---|
| `flutter_quill` | Rich text editor |
| `flutter_markdown` | Markdown rendering |
| `drift` + `sqlite3_flutter_libs` | Local SQLite persistence |
| `supabase_flutter` | Cloud sync & authentication |
| `get_it` | Dependency injection |
| `window_manager` + `flutter_acrylic` | Frameless window & acrylic blur |
| `url_launcher` | Open links in the system browser |
| `http` | GitHub API calls for update checks |
| `table_calendar` | Calendar view |

---

## Contributing

Pull requests are welcome. For major changes please open an issue first to discuss what you would like to change.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes
4. Push to the branch and open a Pull Request

---

## License

MIT — see [LICENSE](LICENSE) for details.
