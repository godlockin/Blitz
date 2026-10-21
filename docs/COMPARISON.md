# Blitz vs other clipboard / launcher tools (2026)

Survey of Mac clipboard-strengthening apps and launcher-bundled history, then where **Blitz** sits. Sources: vendor sites + 2026 roundups ([Maccy](https://maccy.app/), [Paste](https://pasteapp.io/), [Clipy](https://github.com/Clipy/Clipy), [Raycast clipboard](https://manual.raycast.com/clipboard-history), CmdSpace / TypeFire / QuietClip comparisons).

---

## Landscape (horizontal)

Two product shapes:

| Shape | Examples | Job |
|---|---|---|
| **Clipboard specialist** | Maccy, Clipy, Paste, Flycut, CopyQ, CopyClip, CleanClip, ClipBook | History + paste (+ sync / polish) |
| **Launcher + clipboard** | Raycast, Alfred Powerpack, Blitz | Root search + history as one workflow |

Blitz deliberately sits in the **second** row (Raycast-like daily driver) while borrowing **Clipy-depth** clipboard menus — not a Maccy clone.

---

## Feature matrix

| Capability | Blitz | Maccy | Clipy | Paste | Raycast (free) | Alfred Powerpack | CopyQ |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Price | Free OSS | Free OSS | Free OSS | Sub / lifetime | Free (+ Pro) | Paid license | Free OSS |
| Open source | Yes | Yes | Yes | No | No | No | Yes |
| Clipboard search | Yes (panel) | Yes | Weak / menu | Yes | Yes | Yes | Yes |
| Images in history | Yes | Yes (basic) | Limited | Strong | Yes | Yes | Yes |
| OCR / text in images | Yes (on-device) | No | Internal only (1.4) | Yes | Yes (Pro-ish actions) | No | No |
| Pin / favorites | Yes | Yes | No | Pinboards | Yes | Limited | Tags |
| Snippets | Yes (folders + hotkeys) | No | Yes | Shelves | Yes | Yes | Scripts |
| Exclude apps / concealed | Yes | Password-aware | Yes | Yes | Yes | Yes | Rules |
| Menu-bar Clipy-style menus | Yes | Overlay list | Yes | Board UI | Raycast UI | Alfred UI | Qt UI |
| App / file launcher | Yes | No | No | No | Yes | Yes | No |
| Calculator in search | Yes | No | No | No | Yes | Yes | No |
| Window snap | Yes | No | No | No | Yes | Workflows | No |
| Emoji picker | Yes (search) | No | No | No | Yes | Workflows | No |
| Quicklinks / local scripts | Yes | No | No | No | Yes | Workflows | CLI/scripts |
| Extension ecosystem | **Local drop-in** (JSON) | No | No | No | Full store | Workflows | Scripts |
| iCloud / multi-device sync | **iCloud Drive catalogs** | No | No | Pinboards + history | Limited UC | No | No |
| UI polish | Vibrancy panel + motion | Minimal | Menu | Strong | Strong | Functional | Qt |
| Public notarized DMG | No (self-sign / ad-hoc CI) | Yes (MAS/Homebrew) | Yes (Developer ID) | Yes | Yes | Yes | Varies |
| AI / MCP | No (out of scope) | No | No | Paste MCP | Pro AI | No | No |

---

## Vertical slices

### 1. Pure clipboard (Blitz vs Maccy / Clipy / Paste)

| | Strength | Gap vs Blitz |
|---|---|---|
| **Maccy** | Fastest “one job” OSS; tiny; great search; Homebrew | No snippets, no launcher, weak rich types vs Blitz; no OCR |
| **Clipy** | Classic menu + snippets; tiny | Little search; slower maintenance; Blitz aims at Clipy **parity+** (types, pin, OCR, SQLite) **plus** launcher |
| **Paste** | Best polish + full media iCloud + pinboards | Paid, closed; Blitz now has Drive catalog sync + UI polish, still no iOS / full media sync |

**Verdict:** Maccy remains the default *clipboard-only* OSS pick. Blitz is the pick when you want **Clipy menus + OCR + launcher + local extensions + Drive sync**.

### 2. Launcher-bundled clipboard (Blitz vs Raycast / Alfred)

| | Strength | Gap vs Blitz |
|---|---|---|
| **Raycast** | Store ecosystem; polished clipboard; free history (time-capped) | Closed; Pro AI; Blitz has local extensions only |
| **Alfred** | Workflow depth; clipboard tied to Powerpack | Paid; Blitz free but thinner workflows |

**Verdict:** Blitz ≈ **OSS Raycast-shaped daily driver** with local extensions and Drive sync — still behind Raycast Store / Alfred Powerpack depth and notarized install.

### 3. Power / cross-platform (CopyQ)

CopyQ wins on scripting, tabs, encryption options, Linux/Windows. Loses native macOS feel. Blitz stays Mac-native AppKit and does not try to match CopyQ’s script surface.

---

## Where Blitz is ahead (today)

- **Combo:** launcher + Clipy-class clipboard + snippets + window snap + quicklinks/scripts + **local extensions**  
- **Clipboard types:** text / image / RTF / HTML / PDF / files / URL / color + screenshot ingest + OCR + pin  
- **iCloud Drive sync** for snippets / quicklinks / scripts (optional text-clip index) without a paid CloudKit container  
- **UI:** HUD vibrancy panel, inset list, open/close motion  

## Where Blitz is behind

| Gap | Who is better | Notes |
|---|---|---|
| Install trust | Clipy, Maccy, Paste, Raycast | Need Developer ID + notarization |
| Extension *store* / signed packages | Raycast, Alfred | Blitz is local `extension.json` drop-in only |
| Full clipboard media sync | Paste | Blitz syncs catalogs (+ optional text index), not image binaries |
| Visual polish ceiling | Paste, Raycast | Improved, still not App Store marketing UI |
| Cross-platform | CopyQ | macOS only |

---

## Positioning one-liner

> **Blitz = open-source launcher + Clipy-plus clipboard**, with **local extensions** and **iCloud Drive catalog sync** — not a Raycast Store substitute, not Paste’s full media sync.

---

## Sources (checked ~2026)

- https://maccy.app/ · https://github.com/p0deje/Maccy  
- https://github.com/Clipy/Clipy  
- https://pasteapp.io/  
- https://manual.raycast.com/clipboard-history  
- https://cmd-space.app/blog/mac-clipboard-history-options  
- https://typefire.app/blog/best-clipboard-manager-mac  
- https://quietclip.app/blog/clipboard-manager-comparison/
