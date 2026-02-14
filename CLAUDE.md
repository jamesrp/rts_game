# CLAUDE.md

## Project Overview

Single-player RTS game built with Godot 4.6, exported to web. Player captures neutral buildings by selecting buildings and sending units.

## Key Architecture

- **All game code lives in `game/main.gd`** — single-file architecture, no other scripts or scenes to find.
- **Godot project root is `game/`**, not the repo root. All Godot commands must reference this path.
- Rendering uses Godot's immediate-mode `_draw()` API — no sprites, textures, or asset files.

## Critical: Web Export Step

**Code changes are NOT visible in the browser until you re-export.** The browser serves pre-built files from `game/build/`. After any code change:

```bash
cd /home/sprite/rts_game/game && godot --headless --export-release "Web" build/index.html
```

Then refresh the browser. Without this, the old `.pck` is served.

## Validation

Check for parse errors without a display:

```bash
godot --headless --quit
```

This loads the project and exits. Errors will print to stderr.

## Constraints

- Renderer: `gl_compatibility` (required for WebGL 2.0)
- Export templates are version-locked to Godot 4.6.stable
- Web export uses `thread_support=false`
