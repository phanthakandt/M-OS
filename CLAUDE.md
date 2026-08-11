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

Gotcha: built-in Godot controls that draw their own theme icon (e.g. `CheckBox`'s check glyph) size that icon in fixed absolute units of this same 384×216 coordinate space, completely independent of any `font_size`/`custom_minimum_size` override — on this tiny canvas that icon reads as oversized next to the pixel fonts, and there's no cheap per-node fix short of overriding the theme icon itself. Prefer a plain toggle `Button` with a bracket-style text prefix instead (see `FilesApp`'s hidden-file toggle, or `DevCrackApp`'s blob rows) — it stays entirely font-driven like everything else in the UI.

### Autoloads

- **`Palette`** (`scripts/autoload/palette.gd`) is the single source of truth for the color palette (including one-off colors like `SCRIM` and `VOID` — even a plain color used once, e.g. a modal's scrim or a blackout overlay, should be a named `Palette` constant, not an inline `Color(...)`) and for `StyleBoxFlat` construction (`window_style()`, `titlebar_style(active)`, `task_item_style()`, `blob_marked_style()`, etc.), plus the two pixel fonts (`font_body` = VT323, `font_chrome` = Press Start 2P). Never hardcode a color or build a `StyleBoxFlat` elsewhere — call a `Palette` builder/constant from a node's `_ready()` and apply it via `add_theme_*_override`.
- **`GameState`** (`scripts/autoload/game_state.gd`) holds session flags (`has_learned_devcrack`) plus per-file runtime progress (`repacked_files`, `unlocked_files`, keyed by `FileData.id`/`resource_path`) via `is_repacked(file)`, `is_unlocked(file)`, `mark_repacked(file)`, `mark_unlocked(file)`, `is_locked(file)` (effective lock state), and `reset_progress()`.

### Window system (`scripts/window/`, `scenes/window/Window.tscn`)

`AppWindow` (`window.gd`) is the reusable chrome (Panel + TitleBar + ContentSlot), tracking `window_id`/`window_title` (both set by `setup(title, id)`) and emitting `closed(window_id)` / `focused(window_id)`. `WindowManager` (`window_manager.gd`) is a plain `Node` — one lives under each `Desktop`, it is not an autoload — exposing:

- `open_window(content: Control, title: String, rect: Rect2) -> AppWindow` — callers instantiate their own app scene, then hand it to `open_window`, which reparents it into the new window's `ContentSlot` and handles focus/z-order/taskbar sync.
- `focus_window(window_id)` — **toggles**: if the window is already the active, visible one, it hides (minimizes) instead of re-focusing. This is the taskbar button's intentional click-to-minimize behavior (`Desktop._on_window_opened`) and should not be reused elsewhere.
- `reveal_window(window_id)` — show + focus only, no minimize branch. Use this for every "open/bring to front" action (desktop icons, start menu, reopening an already-open file/singleton window) — `Desktop._focus_if_open`, `FilesApp._open_file`, and `TaskManagerApp` all call this, never `focus_window`.
- `get_open_windows() -> Array` — snapshot of `{id, title, visible}` per open window, used by `TaskManagerApp` to render its process list.
- `close_window(window_id)` — closes a window the same way its own titlebar close button does (emits `closed`, then `queue_free`s it); no-ops if the id is unknown.

Apps never touch `AppWindow` directly, only this API plus their own signals.

### Data-driven content (`scripts/resources/`, `data/`)

`FileData`, `FolderData`, `RuleData`, `BlobData` are `Resource` subclasses (declared with `class_name`, no autoload needed) saved as `.tres` files under `data/files/` and `data/rules/`, plus the file/folder tree root `data/drive_c.tres`. Puzzle content (rule text, file metadata, which blob is correct to remove) lives entirely in these `.tres` files, not in scripts.

Resource immutability rule: preloaded/loaded `Resource` instances (including everything under `data/`) are cached singletons for the process's lifetime — **never mutate a `Resource` field at runtime** (e.g. `FileData.is_locked`). `FileData.is_locked` is read-only initial data. All runtime/session progress (repacked, unlocked) lives in the `GameState` autoload instead, keyed off `FileData.id`, and callers compute effective state via `GameState.is_locked(file)` / `GameState.is_repacked(file)` rather than reading mutated resource fields. File-browser navigation state (history, current folder, show-hidden) similarly lives entirely in `FilesApp`, never on `FolderData`/`FileData`.

### Apps (`scripts/apps/`, `scenes/apps/`)

Each app (`NoteViewer`, `FilesApp`, `DevCrackApp`, `TaskManagerApp`) is a standalone `Control` scene, instantiated by whoever wants to open it (`Desktop`, or another app) and handed to `WindowManager.open_window`. Only call an app's configuration methods (e.g. `unpack(file)`, `show_plain(text)`, `TaskManagerApp.self_window_id = ...` / `.refresh_list()`) **after** `open_window` has added it to the tree — its `@onready` references aren't valid before that.

`FilesApp` is a full file browser over the `FolderData`/`FileData` tree rooted at `data/drive_c.tres`. Back/forward navigation, the current path, and the hidden-files toggle are all plain state on the `FilesApp` instance (`_history`, `_history_index`, `_show_hidden`) — never on the resources themselves, per the immutability rule above. Entering a new folder truncates any forward history, like a browser. Folders sort before files, hidden entries (`is_hidden`) are omitted unless the toggle is on, and locked files are shown but not gated from opening (DevCrack gating happens only inside `DevCrackApp`). Double-clicking a file that already has an open window calls `WindowManager.reveal_window` instead of opening a duplicate (`_open_file_windows`, keyed by `FileData.id`); `Desktop` does the same thing for the single-instance apps it launches itself (drive icon, README, SYSTEM.LOG, task manager) via its own `_singleton_windows` map keyed by an arbitrary app key (see `_focus_if_open`).

`DevCrackApp.unpack(file)` / `.repack()` implement the core puzzle loop: unpacking renders one toggle row per `BlobData` on the file, and `repack()` only succeeds if the exact set of toggled-on blob ids matches the blobs with `should_remove = true`; on success it calls `GameState.mark_repacked(file)` rather than mutating the resource. `GameState.has_learned_devcrack` gates unpacking any `is_locked` file until the player has successfully repacked a non-locked file first.

`TaskManagerApp` (`task_manager_app.gd`) lists every open window as a process row (name button + `[x]` close button), driven entirely by `WindowManager.get_open_windows()`. It re-subscribes to `window_opened`/`window_closed` to rebuild the list live, and takes a `self_window_id` (set by `Desktop._open_task_manager` right after `open_window` returns, followed by an explicit `refresh_list()` call) so it can filter its own row out — it can't rely on the window-opened signal alone, since that fires for it before `self_window_id` is assigned.

### UI components (`scripts/ui/`, `scenes/ui/`)

`ConfirmDialog` (`confirm_dialog.gd`) is a reusable modal: scrim (`Palette.SCRIM`) + `window_style` `PanelContainer` with a message label and `[ ยืนยัน ]` (`blob_marked_style`) / `[ ยกเลิก ]` (`task_item_style`) buttons. Call `ask(message: String)` to show it; it emits `confirmed` or `cancelled` (clicking the scrim outside the panel also cancels). One instance lives on `Desktop` (`_confirm_dialog`, added after the start-menu layer so it renders on top of everything) and is reused across callers — since it's shared, always connect to `confirmed` with `CONNECT_ONE_SHOT` and guard against double-connecting if the same flow can be triggered again before the dialog resolves (see `Desktop._confirm_shutdown`).

### Desktop shell (`scripts/desktop/`, `scenes/desktop/Desktop.tscn`)

`Desktop` (`desktop.gd`) wires everything together: owns the `WindowManager`, builds taskbar entries from `WindowManager`'s `window_opened`/`window_closed` signals, and builds a start menu (scrim + `PanelContainer`, opened by left-clicking the `start_button`/"M-OS" taskbar button; entries are data in `_start_menu_items`, so adding one is just appending a `{"label": ..., "action": Callable}` before `_build_start_menu()` runs). Current entries: drive, SYSTEM.LOG, task manager, restart, logout, shutdown. `restart`/`logout` both just call `GameState.reset_progress()` then `get_tree().reload_current_scene()` — the duplication is intentional (they read differently to the player but there's currently no state that needs to diverge between them); don't merge them into one function. `shutdown` goes through `ConfirmDialog` (`_confirm_shutdown` → `_do_shutdown`, which shows a black `Palette.VOID` overlay with a "process terminated" message before `get_tree().quit()`).

`DesktopIconUI` (`desktop_icon.gd`) is a generic double-click-to-activate icon. **Configure it via `configure(glyph, label_text)`, never by assigning the `.glyph`/`.label_text` export vars directly** — Godot runs a child's `_ready()` before its parent's, so by the time `Desktop._ready()` would assign those properties, the icon has already copied its (empty-string default) export values into its labels; the assignment is silently too late. `Desktop` wires each icon's `activated` signal to whichever app it should open — currently the "drive" icon (`FilesApp` on `data/drive_c.tres`) and the "readme" icon (the rules-note `NoteViewer`, opened as the `"readme"` singleton window; it is **not** opened automatically at boot anymore, the player must double-click the icon).
