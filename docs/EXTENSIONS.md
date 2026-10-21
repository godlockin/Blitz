# Blitz local extensions

Drop-in packages under:

`~/Library/Application Support/Blitz/Extensions/<id>/extension.json`

## Manifest

```json
{
  "id": "com.example.demo",
  "name": "Demo",
  "author": "you",
  "commands": [
    {
      "id": "ping",
      "title": "Ping",
      "subtitle": "Notify",
      "mode": "run",
      "command": "osascript -e 'display notification \"pong\" with title \"Blitz\"'"
    },
    {
      "id": "site",
      "title": "Open Example",
      "mode": "open",
      "url": "https://example.com"
    }
  ]
}
```

| `mode` | Behavior |
|---|---|
| `run` | `/bin/zsh -lc <command>` (cwd = extension folder) |
| `open` | Open `url`, or `command` as a filesystem path |

Reload: launcher → **Reload Extensions**, or restart Blitz.

This is a **local** ecosystem (no remote marketplace / notarized store). Good for personal scripts and team-shared folders via iCloud Drive sync of Application Support mirrors.
