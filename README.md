# Blitz

Clean-room macOS **launcher + clipboard** (Swift / AppKit).

Developed under a local Reverse workspace; this directory is the **standalone** Git repo ([godlockin/Blitz](https://github.com/godlockin/Blitz), branch `miao`).

| | |
|---|---|
| App | **Blitz** → `~/Applications/Blitz.app` |
| Bundle ID | `research.reversedir.blitz` |
| URL scheme | `blitz://` |
| Signing | **Blitz Dev** (local self-signed; no paid Developer ID) |
| Data | `~/Library/Application Support/Blitz/` |
| Log | `~/Library/Logs/Blitz.log` |
| License | [MIT](./LICENSE) |

## Build / install

```bash
make signing-cert   # once
make install        # ~/Applications/Blitz.app
make doctor
make clean
```

If codesign asks for a keychain password every time: `make signing-allow-codesign` once.

**Permissions:** Accessibility (paste / snap); Automation may prompt for System Events.

## Features

| Need | Behavior |
|---|---|
| Clipboard | Text, images, RTF/HTML/PDF/files/URLs/colors; OCR; pin (**⌘P** / menu **⌃**+select) |
| Clipy-parity | Exclude apps, concealed/Universal ignore, type toggles, clear policies, screenshot ingest, menu modifiers |
| Snippets | Folders, keywords, import/export, `⇧⌘B` |
| Quicklinks / scripts | Launcher search + Settings editor (`{Query}`) |
| Window snap | `left` / `right` / `center` / `max` … |
| Files / calc | Prefix-ranked file search; expressions copy result |

### Hotkeys (defaults)

| Action | Shortcut |
|---|---|
| Launcher | **⌃⌥Space** |
| Clipboard panel | **⌃⌥V** |
| Main menu | **⌥⌘V** (at mouse) |
| History menu | **⌃⌘V** / menu-bar left click |
| Snippets | **⇧⌘B** |
| Settings | **⌃⌥⇧⌘V** |

## Distribution

Stays **self-signed** while unpaid. Clipy’s one-click Open comes from **Developer ID + notarization**, not from being open source. See [docs/COMPARISON.md](./docs/COMPARISON.md).

## Architecture

```
Swift AppKit agent
  ├── NSPanel launcher / clipboard UI
  ├── ClipboardStore / SnippetStore / SearchService / WindowManager
  └── SQLite: ~/Library/Application Support/Blitz/blitz.sqlite
```

Acceptance: `Reconstruction/` · Contributing: [CONTRIBUTING.md](./CONTRIBUTING.md)

## Releases (GitHub Actions)

```bash
git tag v0.4.0 && git push origin v0.4.0
```

Workflow: [`.github/workflows/release.yml`](./.github/workflows/release.yml). Artifact is **ad-hoc** signed. Day-to-day: `make install` + **Blitz Dev**.

Comparison: [docs/COMPARISON.md](./docs/COMPARISON.md).
