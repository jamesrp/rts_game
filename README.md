# My 2D Game

A 2D Godot 4.6 game prototyped in a Sprite VM and served as a web export.

## Setup

- **Engine:** Godot 4.6 stable, installed at `/usr/local/bin/godot`
- **Export templates:** `~/.local/share/godot/export_templates/4.6.stable/`
- **Renderer:** `gl_compatibility` (required for web/WebGL 2.0)
- **Web server:** Python HTTP server running as a Sprite service (`godot-web`) on port 8080. The Sprite proxy routes external HTTPS (port 443) to port 8080 internally, so you access the game at your Sprite's URL (`https://<name>-<org>.sprites.dev/`) on standard port 80/443.

## Project Structure

```
game/
├── project.godot          # Godot project config (800x600 viewport)
├── main.tscn              # Main scene (Node2D)
├── main.gd                # Game script (arrow-key movement with rainbow trail)
├── export_presets.cfg      # Web export preset (no threads)
├── build/                  # Exported web files (gitignored)
└── .gitignore
```

## Rebooting

The `godot-web` service and the `build/` directory both persist across Sprite restarts. When the Sprite boots back up, the game server auto-starts and serves the existing build — no action needed.

You only need to re-export when you change the game code (see below).

## Development Workflow

1. Edit files in this directory (e.g. `main.gd`, add new scenes)
2. Re-export for web:
   ```bash
   cd /home/sprite/rts_game/game && godot --headless --export-release "Web" build/index.html
   ```
3. Refresh your browser — the HTTP server serves the new files automatically

The export step compiles your GDScript and packs resources into `build/index.pck`. Without re-exporting, code changes won't be reflected in the browser.

## Notes

- The web export uses `thread_support=false`, so no special CORS headers are strictly needed, but the server sends them anyway for compatibility.
- Only the **Compatibility** renderer (`gl_compatibility`) works for web exports. Forward+ and Mobile do not support WebGL.
- Export templates are version-locked — they must match the Godot editor version exactly (4.6.stable).
