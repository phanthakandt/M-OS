extends Control

const NOTE_VIEWER_SCENE := preload("res://scenes/apps/NoteViewer.tscn")
const FILES_APP_SCENE := preload("res://scenes/apps/FilesApp.tscn")
const DEVCRACK_SCENE := preload("res://scenes/apps/DevCrackApp.tscn")
const CONFIRM_DIALOG_SCENE := preload("res://scenes/ui/ConfirmDialog.tscn")
const WARNING_DIALOG_SCENE := preload("res://scenes/ui/WarningDialog.tscn")
const CONTEXT_MENU_SCENE := preload("res://scenes/ui/ContextMenu.tscn")
const TASK_MANAGER_SCENE := preload("res://scenes/apps/TaskManagerApp.tscn")
const TRASH_APP_SCENE := preload("res://scenes/apps/TrashApp.tscn")
const KIKUCHAT_SCENE := preload("res://scenes/apps/KikuChatApp.tscn")
const SYSTEM_LOG_SCENE := preload("res://scenes/apps/SystemLogApp.tscn")
const MOSMAIL_SCENE := preload("res://scenes/apps/MosMailApp.tscn")

## readme.txt is a file like any other — not an app — so it's backed by a
## real FileData (with blobs) instead of being a hardcoded special case.
## This is what lets it be unpacked through DevCrack the same as anything
## in FilesApp; whether it's actually locked is derived from its blobs, per
## the immutability rule (never mutated here).
const README_FILE := preload("res://data/files/readme.tres")

@onready var background: ColorRect = $Background
@onready var corruption_modulate: CanvasModulate = $CorruptionModulate
@onready var window_layer: Control = $WindowLayer
@onready var window_manager: WindowManager = $WindowManager
@onready var drive_icon: DesktopIconUI = $IconGrid/DriveIcon
@onready var readme_icon: DesktopIconUI = $TopRightIconGrid/ReadmeIcon
@onready var trash_icon: DesktopIconUI = $IconGrid/TrashIcon
@onready var kikuchat_icon: DesktopIconUI = $IconGrid/KikuChatIcon
@onready var mosmail_icon: DesktopIconUI = $IconGrid/MosMailIcon
@onready var taskbar: Control = $Taskbar
@onready var taskbar_panel: Panel = $Taskbar/Panel
@onready var start_button: Button = $Taskbar/Panel/HBox/StartButton
@onready var open_windows_list: HBoxContainer = $Taskbar/Panel/HBox/OpenWindowsList
@onready var clock_label: Label = $Taskbar/Panel/HBox/Clock
@onready var clock_timer: Timer = $ClockTimer

var _task_items: Dictionary = {}
var _work_area: Rect2 = Rect2()

var _start_menu_items: Array = []
var _start_menu_layer: Control
var _start_menu_panel: PanelContainer
var _start_menu_scrim: Control
var _confirm_dialog: ConfirmDialog
var _warning_dialog: WarningDialog
var _context_menu: ContextMenu

## The desktop icon's own open/delete/unpack actions, remembered between
## showing its right-click menu and the player picking an item from it.
## _context_target_delete_action/_context_target_unpack_action are left
## invalid for icons with no delete/unpack option (see _wire_icon).
var _context_target_open_action: Callable
var _context_target_delete_action: Callable
var _context_target_unpack_action: Callable

## Single-instance app windows opened from the desktop shell (icons, start
## menu), keyed by an arbitrary app key -> window_id. Reopening a key focuses
## the existing window instead of spawning a duplicate.
var _singleton_windows: Dictionary = {}


func _ready() -> void:
	GameState.ghost_processes_changed.connect(_update_corruption_tint)
	_update_corruption_tint()

	taskbar_panel.add_theme_stylebox_override("panel", Palette.taskbar_style())

	start_button.focus_mode = Control.FOCUS_NONE
	start_button.text = "M-OS"
	start_button.add_theme_font_override("font", Palette.font_chrome)
	start_button.add_theme_font_size_override("font_size", 4)
	start_button.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	start_button.add_theme_stylebox_override("normal", Palette.start_button_style())
	start_button.add_theme_stylebox_override("hover", Palette.start_button_style())
	start_button.add_theme_stylebox_override("pressed", Palette.start_button_style())
	start_button.pressed.connect(_toggle_start_menu)

	clock_label.add_theme_font_override("font", Palette.font_body)
	clock_label.add_theme_font_size_override("font_size", 5)
	clock_label.add_theme_color_override("font_color", Palette.TEXT_DIM)

	_work_area = Rect2(Vector2.ZERO, window_layer.size - Vector2(0, taskbar.size.y))
	window_manager.window_layer = window_layer
	window_manager.work_area = _work_area
	window_manager.window_opened.connect(_on_window_opened)
	window_manager.window_closed.connect(_on_window_closed)

	_wire_icon(drive_icon, "D", "drive", Callable(self, "_open_files_app"))
	_wire_icon(readme_icon, "T", "readme.txt", Callable(self, "_open_readme"), Callable(self, "_delete_readme"), Callable(self, "_open_readme_devcrack"))
	_wire_icon(trash_icon, "X", "trash", Callable(self, "_open_trash_app"))
	_wire_icon(kikuchat_icon, "K", "KikuChat", Callable(self, "_open_kikuchat"))
	_wire_icon(mosmail_icon, "@", "MosMail", Callable(self, "_open_mosmail"))

	readme_icon.visible = not GameState.is_readme_deleted()
	GameState.trashed_changed.connect(_on_trashed_changed)

	# group 0 = navigation, group 1 = power — _build_start_menu() inserts a
	# divider wherever this changes between consecutive items, so adding or
	# removing an entry never needs a hardcoded divider position.
	_start_menu_items = [
		{"label": "my drive", "action": Callable(self, "_open_files_app"), "glyph": "D", "group": 0},
		{"label": "trash", "action": Callable(self, "_open_trash_app"), "glyph": "X", "group": 0},
		{"label": "system log", "action": Callable(self, "_open_system_log"), "glyph": "L", "group": 0},
		{"label": "task manager", "action": Callable(self, "_open_task_manager"), "glyph": "T", "group": 0},
		{"label": "restart", "action": Callable(self, "_restart_os"), "glyph": "R", "group": 1},
		{"label": "logout", "action": Callable(self, "_logout"), "glyph": "O", "group": 1},
		{"label": "shutdown", "action": Callable(self, "_confirm_shutdown"), "glyph": "!", "group": 1},
	]
	_build_start_menu()

	_confirm_dialog = CONFIRM_DIALOG_SCENE.instantiate()
	add_child(_confirm_dialog)

	_warning_dialog = WARNING_DIALOG_SCENE.instantiate()
	add_child(_warning_dialog)

	_context_menu = CONTEXT_MENU_SCENE.instantiate()
	add_child(_context_menu)
	_context_menu.item_selected.connect(_on_icon_context_item_selected)

	clock_timer.wait_time = 1.0
	clock_timer.timeout.connect(_update_clock)
	clock_timer.start()
	_update_clock()


func _update_clock() -> void:
	var t := Time.get_time_dict_from_system()
	clock_label.text = "%02d:%02d" % [t.hour, t.minute]


## Bleeds both the desktop background and the whole screen toward red as the
## number of live ghost processes (GameState.get_ghost_process_count())
## climbs. background.color only tints Background itself (see
## Palette.desktop_corruption_color()); corruption_modulate.color is
## Desktop.tscn's single CanvasModulate, which multiplies against every
## already-rendered pixel on screen — windows, taskbar, icons, text — so
## that's what makes the whole screen corrupt together, not just the desktop
## behind everything (see Palette.corruption_modulate()). Called once up
## front in _ready() (in case the count is ever nonzero at boot) and again
## every time GameState.ghost_processes_changed fires.
func _update_corruption_tint() -> void:
	var ghost_count := GameState.get_ghost_process_count()
	background.color = Palette.desktop_corruption_color(ghost_count)
	corruption_modulate.color = Palette.corruption_modulate(ghost_count)


## TEMPORARY DEBUG TOOL — Ctrl+Shift+G forces the ghost-process count to max
## so corruption-tint readability (background + CanvasModulate stacked at
## full saturation) can be checked against real app windows without dozens
## of REPACK presses. Deliberately NOT a bare function key: F5-F8 are
## Godot's own play/pause/stop shortcuts and F9-F11 are the script editor's
## breakpoint/step shortcuts — pressing one of those while the editor (not
## the running game) has focus toggles a breakpoint instead, which can pause
## the entire engine the next time execution reaches that line and looks
## exactly like the game freezing. `not event.echo` stops holding the combo
## from re-triggering this on every OS key-repeat tick. OS.has_feature
## ("debug") is true in editor runs and debug exports only, never in a
## release export, but that alone isn't a reason to leave this in — remove
## this whole function (and the debug method it calls,
## GameState.debug_max_out_ghost_processes()) before shipping.
func _input(event: InputEvent) -> void:
	if not OS.has_feature("debug"):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_G and event.ctrl_pressed and event.shift_pressed:
			GameState.debug_max_out_ghost_processes()


func _open_readme() -> void:
	if _focus_if_open("readme"):
		return

	var reason := GameState.get_lock_reason(README_FILE)
	if reason != GameState.LockReason.UNLOCKED:
		if _warning_dialog:
			if reason == GameState.LockReason.CORRUPTED:
				_warning_dialog.show_message("ไม่สามารถเปิดไฟล์นี้ได้เนื่องจากไฟล์เสียหาย")
			else:
				_warning_dialog.show_message("ไม่สามารถเปิดไฟล์นี้ได้")
		return

	var content: NoteViewer = NOTE_VIEWER_SCENE.instantiate()
	var win := window_manager.open_window(content, "README.txt", Rect2(134, 29, 128, 147))
	_singleton_windows["readme"] = win.window_id
	content.show_plain(README_FILE.content)


## Same "Unpack through DevCrack" flow as FilesApp._open_devcrack, just
## opened from the desktop icon instead of a file-browser row — readme.txt
## isn't part of the browsable data/drive.tres tree, so there's no FilesApp
## instance to reuse here.
func _open_readme_devcrack() -> void:
	if _focus_if_open("readme_devcrack"):
		return

	var content: DevCrackApp = DEVCRACK_SCENE.instantiate()
	content.warning_dialog = _warning_dialog
	content.window_manager = window_manager
	var win := window_manager.open_window(
		content, "devcrack — README.txt", Rect2(50, 20, 190, 150)
	)
	_singleton_windows["readme_devcrack"] = win.window_id
	content.self_window_id = win.window_id
	content.unpack(README_FILE)


func _open_files_app() -> void:
	if _focus_if_open("drive"):
		return
	var content: FilesApp = FILES_APP_SCENE.instantiate()
	content.window_manager = window_manager
	content.warning_dialog = _warning_dialog
	# Widened from the original 160x140 — the sidebar, breadcrumb, kind
	# column, and status bar all need more horizontal/vertical room than the
	# old single-column plain-list layout did, same reason SystemLogApp's
	# window was widened for its own multi-column layout.
	var win := window_manager.open_window(content, "drive", Rect2(25, 15, 230, 175))
	_singleton_windows["drive"] = win.window_id


func _open_kikuchat() -> void:
	if _focus_if_open("kikuchat"):
		return
	var content: KikuChatApp = KIKUCHAT_SCENE.instantiate()
	content.window_manager = window_manager
	content.warning_dialog = _warning_dialog
	var win := window_manager.open_window(content, "KikuChat", Rect2(45, 15, 190, 150))
	_singleton_windows["kikuchat"] = win.window_id


func _open_mosmail() -> void:
	if _focus_if_open("mosmail"):
		return
	var content: MosMailApp = MOSMAIL_SCENE.instantiate()
	content.window_manager = window_manager
	content.warning_dialog = _warning_dialog
	var win := window_manager.open_window(content, "MosMail", Rect2(30, 15, 260, 170))
	_singleton_windows["mosmail"] = win.window_id


func _focus_if_open(key: String) -> bool:
	if not _singleton_windows.has(key):
		return false
	window_manager.reveal_window(_singleton_windows[key])
	return true


## Most desktop icons (drive, trash) are apps with no FileData/FolderData
## behind them, so their right-click menu only ever offers "Open" — pass
## delete_action/unpack_action for icons that represent an actual file
## (currently just readme.txt) to also offer "Delete"/"Unpack through
## DevCrack", same options a file gets in FilesApp.
func _wire_icon(icon: DesktopIconUI, glyph: String, label: String, open_action: Callable, delete_action: Callable = Callable(), unpack_action: Callable = Callable()) -> void:
	icon.configure(glyph, label)
	icon.activated.connect(open_action)
	icon.context_requested.connect(_show_icon_context_menu.bind(open_action, delete_action, unpack_action))


func _show_icon_context_menu(open_action: Callable, delete_action: Callable, unpack_action: Callable) -> void:
	_context_target_open_action = open_action
	_context_target_delete_action = delete_action
	_context_target_unpack_action = unpack_action

	var items: Array = [{"label": "Open", "action": "open"}]
	if unpack_action.is_valid():
		items.append({"label": "Unpack through DevCrack", "action": "unpack"})
	if delete_action.is_valid():
		items.append({"label": "Delete", "action": "delete"})
	_context_menu.open_at(get_global_mouse_position(), items)


func _on_icon_context_item_selected(action: String) -> void:
	if action == "open" and _context_target_open_action.is_valid():
		_context_target_open_action.call()
	elif action == "unpack" and _context_target_unpack_action.is_valid():
		_context_target_unpack_action.call()
	elif action == "delete" and _context_target_delete_action.is_valid():
		_context_target_delete_action.call()


func _delete_readme() -> void:
	GameState.delete_readme()
	if _singleton_windows.has("readme"):
		window_manager.close_window(_singleton_windows["readme"])


## GameState.trashed_changed also fires for file/folder trash in FilesApp,
## which readme_icon doesn't care about — re-deriving visibility from
## is_readme_deleted() every time is simpler than a readme-specific signal.
func _on_trashed_changed() -> void:
	readme_icon.visible = not GameState.is_readme_deleted()


func _on_window_opened(window_id: String, title: String) -> void:
	var btn := Button.new()
	btn.text = title
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_text = true
	btn.custom_minimum_size = Vector2(20, 0)
	btn.add_theme_font_override("font", Palette.font_body)
	btn.add_theme_font_size_override("font_size", 5)
	btn.add_theme_color_override("font_color", Palette.TEXT_DIM)
	btn.add_theme_stylebox_override("normal", Palette.task_item_style())
	btn.add_theme_stylebox_override("hover", Palette.task_item_style())
	btn.add_theme_stylebox_override("pressed", Palette.task_item_style())
	btn.pressed.connect(func() -> void: window_manager.focus_window(window_id))
	open_windows_list.add_child(btn)
	_task_items[window_id] = btn


func _on_window_closed(window_id: String) -> void:
	if _task_items.has(window_id):
		_task_items[window_id].queue_free()
		_task_items.erase(window_id)
	for key in _singleton_windows.keys():
		if _singleton_windows[key] == window_id:
			_singleton_windows.erase(key)
			break


## -- Start menu --------------------------------------------------------

func _build_start_menu() -> void:
	_start_menu_layer = Control.new()
	_start_menu_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_start_menu_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_start_menu_layer)

	_start_menu_scrim = Control.new()
	_start_menu_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_start_menu_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_start_menu_scrim.visible = false
	_start_menu_scrim.gui_input.connect(_on_scrim_gui_input)
	_start_menu_layer.add_child(_start_menu_scrim)

	_start_menu_panel = PanelContainer.new()
	_start_menu_panel.add_theme_stylebox_override("panel", Palette.window_style())
	_start_menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_start_menu_panel.visible = false
	_start_menu_layer.add_child(_start_menu_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	_start_menu_panel.add_child(vbox)

	_build_start_menu_header(vbox)

	var previous_group := -1
	for item in _start_menu_items:
		if previous_group != -1 and item.group != previous_group:
			_add_start_menu_divider(vbox)
		previous_group = item.group
		_add_start_menu_item(vbox, item)


## "signed in as" / PlayerIdentity.player_name, with a divider below
## separating it from the item list — PlayerIdentity is set once at login
## (see login_screen.gd) and never touched again here.
func _build_start_menu_header(vbox: VBoxContainer) -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 4)
	vbox.add_child(margin)

	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	margin.add_child(lines)

	var signed_in_label := Label.new()
	signed_in_label.text = "signed in as"
	signed_in_label.add_theme_font_override("font", Palette.font_body)
	signed_in_label.add_theme_font_size_override("font_size", 4)
	signed_in_label.add_theme_color_override("font_color", Palette.TEXT_FAINT)
	lines.add_child(signed_in_label)

	var player_name_label := Label.new()
	player_name_label.text = PlayerIdentity.player_name
	player_name_label.add_theme_font_override("font", Palette.font_body)
	player_name_label.add_theme_font_size_override("font_size", 6)
	player_name_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	lines.add_child(player_name_label)

	_add_start_menu_divider(vbox)


## Plain 1px Palette.BORDER line — used both below the header and between
## the navigation/power item groups (see _build_start_menu()'s group check).
func _add_start_menu_divider(vbox: VBoxContainer) -> void:
	var divider := ColorRect.new()
	divider.color = Palette.BORDER
	divider.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(divider)


## One start menu row: a glyph box (same icon_glyph_style() box DesktopIconUI
## uses, just sized for a menu row instead of a desktop icon) plus a label,
## in a PanelContainer whose own stylebox is the left-accent-bar hover state
## (see Palette.start_menu_item_style()) — same "swap stylebox on
## mouse_entered/exited" pattern TaskManagerApp's rows use. "shutdown" is the
## one row styled differently: ACCENT_WARN on both the glyph border and the
## label, signaling it's the destructive action, same color TaskManagerApp/
## ConfirmDialog already use for danger — never a hardcoded Color(...).
func _add_start_menu_item(vbox: VBoxContainer, item: Dictionary) -> void:
	var is_shutdown: bool = item.label == "shutdown"

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", Palette.start_menu_item_style(false))
	row.gui_input.connect(_on_start_menu_row_gui_input.bind(item.action as Callable))
	row.mouse_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", Palette.start_menu_item_style(true)))
	row.mouse_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", Palette.start_menu_item_style(false)))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	row.add_child(hbox)

	var glyph_box := Panel.new()
	glyph_box.custom_minimum_size = Vector2(10, 10)
	glyph_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	glyph_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var glyph_style := Palette.make_flat_style(Palette.WINDOW_BG, Palette.ACCENT_WARN, 1) if is_shutdown else Palette.icon_glyph_style()
	glyph_box.add_theme_stylebox_override("panel", glyph_style)
	hbox.add_child(glyph_box)

	var glyph_label := Label.new()
	glyph_label.text = item.glyph
	glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph_label.add_theme_font_override("font", Palette.font_body)
	glyph_label.add_theme_font_size_override("font_size", 4)
	# TEXT_DIM reads fine against icon_glyph_style()'s WINDOW_BG fill — same
	# pairing DesktopIconUI's own glyph already uses.
	glyph_label.add_theme_color_override("font_color", Palette.ACCENT_WARN if is_shutdown else Palette.TEXT_DIM)
	glyph_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph_box.add_child(glyph_label)

	var label := Label.new()
	label.text = item.label
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", Palette.font_body)
	label.add_theme_font_size_override("font_size", 5)
	label.add_theme_color_override("font_color", Palette.ACCENT_WARN if is_shutdown else Palette.TEXT_MAIN)
	hbox.add_child(label)

	vbox.add_child(row)


func _on_start_menu_row_gui_input(event: InputEvent, action: Callable) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_start_menu_item_pressed(action)


func _on_start_menu_item_pressed(action: Callable) -> void:
	_close_start_menu()
	action.call()


func _on_scrim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_start_menu()


func _toggle_start_menu() -> void:
	if _start_menu_panel.visible:
		_close_start_menu()
	else:
		_open_start_menu()


func _open_start_menu() -> void:
	_start_menu_scrim.visible = true
	_start_menu_panel.visible = true
	_start_menu_panel.reset_size()
	var menu_size: Vector2 = _start_menu_panel.size
	var btn_pos: Vector2 = start_button.global_position
	_start_menu_panel.global_position = Vector2(btn_pos.x, btn_pos.y - menu_size.y)


func _close_start_menu() -> void:
	_start_menu_scrim.visible = false
	_start_menu_panel.visible = false


func _open_system_log() -> void:
	if _focus_if_open("sys_log"):
		return

	var content: SystemLogApp = SYSTEM_LOG_SCENE.instantiate()
	# Was Rect2(204, 23, 109, 70) back when this opened a single 3-line Label —
	# far too small for a real multi-column log (datetime + level tag +
	# message + actor per row). 220, then 310, were still narrow enough that
	# rows wrapped onto a second line via HFlowContainer, unlike the
	# reference mockup where every row fits on one line — widened again to
	# fit DATETIME_WIDTH + a level tag + MESSAGE_MIN_WIDTH + ACTOR_WIDTH side
	# by side at the window's default size, now that actor also has a fixed
	# floor width (see SystemLogApp.ACTOR_WIDTH).
	var win := window_manager.open_window(content, "SYSTEM.LOG", Rect2(20, 15, 340, 180))
	_singleton_windows["sys_log"] = win.window_id


func _open_task_manager() -> void:
	if _focus_if_open("task_mgr"):
		return

	var content: TaskManagerApp = TASK_MANAGER_SCENE.instantiate()
	content.window_manager = window_manager
	var win := window_manager.open_window(content, "task manager", Rect2(70, 40, 150, 120))
	_singleton_windows["task_mgr"] = win.window_id
	content.self_window_id = win.window_id
	content.refresh_list()


func _open_trash_app() -> void:
	if _focus_if_open("trash"):
		return

	var content: TrashApp = TRASH_APP_SCENE.instantiate()
	var win := window_manager.open_window(content, "trash", Rect2(90, 45, 150, 120))
	_singleton_windows["trash"] = win.window_id


## -- Power actions -------------------------------------------------------

func _restart_os() -> void:
	GameState.reset_progress()
	get_tree().reload_current_scene()


func _logout() -> void:
	GameState.reset_progress()
	get_tree().reload_current_scene()


func _confirm_shutdown() -> void:
	if not _confirm_dialog.confirmed.is_connected(_do_shutdown):
		_confirm_dialog.confirmed.connect(_do_shutdown, CONNECT_ONE_SHOT)
	_confirm_dialog.ask("ต้องการปิดระบบ M-OS?")


func _do_shutdown() -> void:
	var overlay := ColorRect.new()
	overlay.color = Palette.VOID
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var label := Label.new()
	label.text = "M-OS: process terminated"
	label.add_theme_font_override("font", Palette.font_chrome)
	label.add_theme_font_size_override("font_size", 5)
	label.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	label.set_anchors_preset(Control.PRESET_CENTER)
	overlay.add_child(label)

	await get_tree().create_timer(1.5).timeout
	get_tree().quit()
