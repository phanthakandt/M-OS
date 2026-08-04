# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

A point-and-click desktop-simulator horror game built in Godot 4.6 (GL Compatibility renderer). The player interacts entirely through a fake retro OS UI (windows, a taskbar, a Files app, a "DevCrack" unpack/repack tool) — no 3D, no physics. This repo currently holds an early MVP slice: boot into a desktop, read a rules note, open a normal file in DevCrack, solve its data-blob puzzle, and use what was learned to unlock a second, initially-locked file.

## Running the project

There is no CLI build, lint, or test tooling in this repo — GDScript projects don't have one by default and none has been added here. Development happens in the Godot editor:

- Open `project.godot` in **Godot 4.6**, then run `scenes/Main.tscn` (F5) — it's already set as `run/main_scene`.
- New or changed asset files (fonts, `.tres`, scenes) are only auto-imported when the Godot editor regains OS focus or you trigger it manually (FileSystem dock → right-click → Reimport). If you edit project files from outside the editor (e.g. a headless agent), the editor won't pick them up until it's focused again — don't assume a change is live just because the file was saved.
- Do not launch a second Godot process against this project directory while the editor already has it open — both processes writing to `.godot/` concurrently can corrupt the import cache.

## Architecture

### Display settings (`project.godot`)

Base resolution is 384×216, window override 1536×864 (exact ×4). `window/stretch/mode` is set to `"canvas_items"` — layout code still thinks in the small 384×216 coordinate space, but Godot draws text and UI chrome natively at full window resolution rather than rendering small and upscaling the whole frame. This was deliberately changed from the initial `"viewport"` mode because that mode bakes the whole scene into a tiny raster image before scaling it up, which blurs text; don't switch back without knowing that tradeoff. `textures/canvas_textures/default_texture_filter` is Nearest, which matters once actual pixel-art sprite textures are added — right now the whole UI is `StyleBoxFlat` fills plus text, no image sprites, so it's currently inert.

### Autoloads

- **`Palette`** (`scripts/autoload/palette.gd`) is the single source of truth for the color palette and for `StyleBoxFlat` construction (`window_style()`, `titlebar_style(active)`, `task_item_style()`, `blob_marked_style()`, etc.), plus the two pixel fonts (`font_body` = VT323, `font_chrome` = Press Start 2P). Never hardcode a color or build a `StyleBoxFlat` elsewhere — call a `Palette` builder from a node's `_ready()` and apply it via `add_theme_*_override`.
- **`GameState`** (`scripts/autoload/game_state.gd`) holds minimal session flags — currently just `has_learned_devcrack`.

### Window system (`scripts/window/`, `scenes/window/Window.tscn`)

`AppWindow` (`window.gd`) is the reusable chrome (Panel + TitleBar + ContentSlot), emitting `closed(window_id)` / `focused(window_id)`. `WindowManager` (`window_manager.gd`) is a plain `Node` — one lives under each `Desktop`, it is not an autoload — exposing `open_window(content: Control, title: String, rect: Rect2) -> AppWindow`. Callers instantiate their own app scene, then hand it to `open_window`, which reparents it into the new window's `ContentSlot` and handles focus/z-order/taskbar sync. Apps never touch `AppWindow` directly, only this API plus their own signals.

### Data-driven content (`scripts/resources/`, `data/`)

`FileData`, `RuleData`, `BlobData` are `Resource` subclasses (declared with `class_name`, no autoload needed) saved as `.tres` files under `data/files/` and `data/rules/`. Puzzle content (rule text, file metadata, which blob is correct to remove) lives entirely in these `.tres` files, not in scripts.

Runtime-state gotcha: `FileData.is_locked` and `FileData.is_repacked` are mutated **in place** on the loaded `.tres` Resource at runtime (Godot resources loaded via `preload`/`load` are cached singletons for the process's lifetime). This is intentional — it's how puzzle progress persists across separately-opened windows in one session — but it means these resource instances are not safe to treat as read-only/immutable data.

### Apps (`scripts/apps/`, `scenes/apps/`)

Each app (`NoteViewer`, `FilesApp`, `DevCrackApp`) is a standalone `Control` scene, instantiated by whoever wants to open it (`Desktop`, or another app) and handed to `WindowManager.open_window`. Only call an app's configuration methods (e.g. `unpack(file)`, `show_plain(text)`) **after** `open_window` has added it to the tree — its `@onready` references aren't valid before that.

`DevCrackApp.unpack(file)` / `.repack()` implement the core puzzle loop: unpacking renders one toggle row per `BlobData` on the file, and `repack()` only succeeds if the exact set of toggled-on blob ids matches the blobs with `should_remove = true`. `GameState.has_learned_devcrack` gates unpacking any `is_locked` file until the player has successfully repacked a non-locked file first.

### Desktop shell (`scripts/desktop/`, `scenes/desktop/Desktop.tscn`)

`Desktop` (`desktop.gd`) wires everything together: owns the `WindowManager`, opens the boot-time README window and a decorative always-behind-other-windows "SYSTEM.LOG" window, and builds taskbar entries from `WindowManager`'s `window_opened`/`window_closed` signals. `DesktopIconUI` (`desktop_icon.gd`) is a generic double-click-to-activate icon; `Desktop` wires its `activated` signal to whichever app it should open (currently only the "My PC" icon, opening `FilesApp`).
