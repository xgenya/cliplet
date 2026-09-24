<p align="center">
  <img src="Sources/ClipletKit/Resources/AppIcon.png" width="96" alt="Cliplet icon">
</p>

<h1 align="center">Cliplet — Clipboard Manager for macOS</h1>

<p align="center"><a href="README.md">简体中文</a> · English</p>

<p align="center">A lightweight, open-source Mac clipboard history app.<br>Keep what you copy, find it quickly, and paste it again.</p>

<p align="center">
  <a href="https://github.com/xgenya/cliplet/actions/workflows/ci.yml"><img src="https://github.com/xgenya/cliplet/actions/workflows/ci.yml/badge.svg" alt="macOS CI"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Apple_Silicon-arm64-111111?logo=apple" alt="Apple Silicon">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-00897B" alt="MIT License"></a>
</p>

<p align="center">
  <a href="#why-cliplet">Why Cliplet?</a> ·
  <a href="#design-philosophy">Design philosophy</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#usage">Usage</a> ·
  <a href="#development">Development</a> ·
  <a href="CONTRIBUTING.md">Contributing</a> ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

Cliplet (拾片) is a free, open-source **clipboard manager for macOS** that saves and searches your **clipboard history**. Built with SwiftUI and AppKit, it lives in your menu bar. Press **⌥V** to browse copied text, links, images, and files, search your copy-and-paste history, and paste into the app you are working in. No account required; your history stays on your Mac.

**Focused on the clipboard. No third-party dependencies. A small app.** Every feature supports saving, finding, and reusing copied content. Cliplet uses macOS system frameworks and requires no additional runtime or background service to install.

![Cliplet clipboard history window](assets/screenshots/history.png)

## Why Cliplet?

Cliplet started with a simple need: **I liked Raycast’s clipboard feature, but only wanted a clipboard app.**

Inspired by the experience of Raycast Clipboard History, Cliplet brings keyboard access, history search, previews, and pasting into a small, standalone macOS app. If you are looking for an **open-source alternative to Raycast’s clipboard feature** and want an app dedicated to copy-and-paste history, that is exactly why Cliplet exists.

Cliplet is an independent project and is not affiliated with Raycast. The inspiration is the user experience; the app is implemented with Swift and Apple’s native frameworks.

## Features

- **Clipboard history**: Capture text, links, email addresses, colors, images, files, and RTF / HTML rich text, with deduplication and time-based grouping.
- **Search and organization**: Search content, filter by type, and pin or rename frequently used entries.
- **Content previews**: Inspect images, file previews, source apps, and entry details.
- **Keyboard controls**: Open history with a global shortcut, navigate with arrow keys, and access more actions through the action panel.
- **Image recognition**: Recognize text and QR codes locally with Apple Vision, then search or copy the results.
- **Recording controls**: Pause recording, exclude apps, configure retention and entry limits, and launch at login.
- **Native interface**: Chinese and English localization, light and dark appearances, Liquid Glass on macOS 26+, and native material fallbacks on earlier systems.

<details>
<summary>More screenshots</summary>

| File previews | Quick actions |
| :---: | :---: |
| ![Multiple-file preview](assets/screenshots/files.png) | ![Action panel](assets/screenshots/actions.png) |

![Cliplet settings window](assets/screenshots/settings.png)

</details>

Screenshots use synthetic data in an isolated preview mode. Materials vary with the macOS version, system appearance, and desktop background.

## Design philosophy

The Chinese name “拾片” means picking up fragments. Cliplet makes the things you copy available as reusable pieces of your work, so finding and pasting them feels like a natural continuation of copying.

- **Focused on the clipboard**: Recording, finding, organizing, and reusing copied content define the scope. Each feature serves that workflow.
- **Small, with no third-party dependencies**: Swift and system frameworks handle the interface, storage, and image recognition. There are no third-party Swift packages or bundled browser runtime. A local Release app bundle occupies approximately **5.5 MiB** on disk, measured with `du -sh build/Cliplet.app`. This covers the app itself, excludes history data, and varies by build.
- **Fewer interruptions**: Stay in the menu bar until needed. Search, select, and paste from one compact floating window, then return to your work.
- **Content first**: Summaries and previews help identify entries; source, type, and time provide context. Visual hierarchy supports finding content, and common actions are available from the keyboard.
- **At home on macOS**: SwiftUI, AppKit, and native controls provide familiar windows, menus, and shortcuts, with an appearance that evolves with the system.
- **Local and controllable**: History storage and image recognition run on your Mac. You control recording, retention, and pauses. A focused scope also keeps the implementation easier to understand and maintain.

### Liquid Glass

On macOS 26 and later, Cliplet uses native Liquid Glass for the history window and action panel. Translucent surfaces retain a visual connection to the desktop and current app, while rounded corners, edges, and depth distinguish the temporary controls from the work behind them.

Glass primarily supports the window and action surfaces, with text, images, and list content arranged for clear reading. The design prioritizes recognition and efficient interaction, using material layers sparingly to suit a compact clipboard workflow.

The history window uses AppKit’s `NSGlassEffectView`; the action panel uses SwiftUI’s `glassEffect`. On macOS 14–15, both fall back to native `NSVisualEffectView` materials while retaining the same core features and interactions. The system renders these materials, so their appearance changes with light or dark mode and the background.

## Installation

### Requirements

| Item | Requirement |
| --- | --- |
| System | macOS 14 or later |
| Hardware | Apple Silicon Mac (M1 or later); Intel Macs are not supported |
| Build tools | Xcode 26+ with Swift 6.2+ and command-line tools |

### Build from source

Cliplet uses Swift Package Manager with no third-party Swift package dependencies. On a Mac with the tools above installed, run:

```bash
git clone https://github.com/xgenya/cliplet.git
cd cliplet
make app
open build/Cliplet.app
```

The resulting app is at `build/Cliplet.app`. You can copy it to your Applications folder. Local builds use ad-hoc signing by default, require no Apple Developer certificate, and are not automatically notarized by Apple.

## Usage

1. Launch Cliplet. It stays in the menu bar and records content you copy afterward.
2. Press **⌥V** in any app to open history, or open it from the menu bar.
3. Type to search, select an entry with **↑ / ↓**, and press **↩** to paste.
4. Press **⌘K** to open the action panel and pin or rename frequently used entries.

Automatic pasting requires granting Cliplet access in **System Settings → Privacy & Security → Accessibility**. Without this permission, you can still press **⌘↩** to copy an entry, switch to the destination app, and press **⌘V** to paste manually.

The global shortcut, app exclusions, and history retention policy are configurable in Cliplet settings.

### Keyboard shortcuts

Except for the global shortcut, these shortcuts apply within the history window.

| Shortcut | Action |
| --- | --- |
| `⌥V` | Show / hide history; customizable in settings |
| `↑` / `↓` | Select an entry |
| `↩` | Paste the selected entry |
| `⌘↩` | Copy to the clipboard without pasting |
| `⌘K` | Open / close the action panel |
| `⌘.` | Pin / unpin |
| `⌘E` | Rename |
| `⌘O` | Open a link / reveal files in Finder |
| `⌃X` | Delete the selected entry |
| `⌘P` | Switch content type |
| `Esc` | Close the action panel or history window |

## Privacy and data

Cliplet does not upload clipboard content or provide cloud sync. Text and QR code recognition runs entirely on your device.

Apple Passwords, Keychain Access, 1Password, Bitwarden, and LastPass are excluded by default. Cliplet also skips clipboard data carrying supported sensitive-type markers. You can add excluded apps in settings or pause recording at any time. Exclusion rules cannot identify every piece of sensitive content.

The production app stores history metadata and attachments at:

```text
~/Library/Application Support/Cliplet/
```

**History files are not separately encrypted.** Configure retention and entry limits to suit your needs, and delete content you do not want to keep.

When upgrading from an older version, Cliplet attempts to migrate data from `~/Library/Application Support/ClipboardNative/`. If migration fails, it continues using the old directory.

## Development

The project is a Swift package. Open `Package.swift` in Xcode or build from the command line. The development app uses a separate app identity and data directory.

```bash
make dev-app
open "build/Cliplet Dev.app"
```

Common commands:

| Command | Purpose |
| --- | --- |
| `make build` | Build the Debug executable |
| `make format` | Format Swift source files |
| `make check` | Run formatting checks, repository checks, and regression tests |
| `make package-test` | Build the app and verify packaging and launch after relocation |
| `make performance` | Run performance tests in Release mode |
| `make app` | Build and package the Release app |
| `make run-app` / `make run-dev-app` | Build and launch the app, replacing a running older copy |

For interface work, use preview mode. It uses synthetic data, does not read your real history, and does not monitor the system clipboard:

```bash
"build/Cliplet Dev.app/Contents/MacOS/Cliplet" --ui-preview --light
# Append --settings-preview to preview the settings window.
```

### Project structure

```text
Sources/Cliplet/      # Executable entry point; contains only main.swift
Sources/ClipletKit/
├── Animation/    # Panel open animation presets and playback
├── App/          # App lifecycle, windows, and dependency setup
├── Domain/       # History retention, sorting, and search rules
├── Models/       # Clipboard entry models
├── Persistence/  # History and attachment storage, data migration
├── Services/     # Clipboard monitoring, recognition, shortcuts, and pasting
├── UI/           # SwiftUI views and presentation logic
└── Resources/    # Icons and localization
Tests/            # Regression and performance tests
scripts/          # Build, packaging, and validation scripts
```

CI runs formatting checks, regression tests, arm64 app packaging, and performance tests. It also checks that the packaged app launches on macOS 14.

## Contributing

Bug reports, feature suggestions, documentation improvements, and code contributions are welcome.

- **Report a problem**: Open an [issue](https://github.com/xgenya/cliplet/issues) with your macOS version, reproduction steps, and expected versus actual behavior. Remove private information from screenshots.
- **Submit code**: Read the [contribution guide](CONTRIBUTING.md) and run `make format` and `make check` before submitting. Packaging or resource changes also require `make package-test`.
- **Explore the project**: See the [architecture notes](docs/ARCHITECTURE.md), [roadmap](docs/ROADMAP.md), and [changelog](CHANGELOG.md). These supporting documents are currently in Chinese.

Do not include real clipboard content in issues, logs, test data, or commits.

## License

Cliplet is open source under the [MIT License](LICENSE).

Copyright © 2026 Cliplet contributors.
