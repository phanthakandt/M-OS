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

	readme_icon.visible = not GameState.is_readme_deleted()
	GameState.trashed_changed.connect(_on_trashed_changed)

	_start_menu_items = [
		{"label": "my drive", "action": Callable(self, "_open_files_app")},
		{"label": "trash", "action": Callable(self, "_open_trash_app")},
		{"label": "system log", "action": Callable(self, "_open_system_log")},
		{"label": "task manager", "action": Callable(self, "_open_task_manager")},
		{"label": "restart", "action": Callable(self, "_restart_os")},
		{"label": "logout", "action": Callable(self, "_logout")},
		{"label": "shutdown", "action": Callable(self, "_confirm_shutdown")},
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
	var win := window_manager.open_window(content, "drive", Rect2(40, 30, 160, 140))
	_singleton_windows["drive"] = win.window_id


func _open_kikuchat() -> void:
	if _focus_if_open("kikuchat"):
		return
	var content: KikuChatApp = KIKUCHAT_SCENE.instantiate()
	content.window_manager = window_manager
	content.warning_dialog = _warning_dialog
	var win := window_manager.open_window(content, "KikuChat", Rect2(45, 15, 190, 150))
	_singleton_windows["kikuchat"] = win.window_id


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
	vbox.add_theme_constant_override("separation", -1)
	_start_menu_panel.add_child(vbox)

	for item in _start_menu_items:
		var btn := Button.new()
		btn.text = item.label
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_override("font", Palette.font_body)
		btn.add_theme_font_size_override("font_size", 5)
		btn.add_theme_color_override("font_color", Palette.TEXT_MAIN)
		btn.add_theme_stylebox_override("normal", Palette.task_item_style())
		btn.add_theme_stylebox_override("hover", Palette.task_item_style())
		btn.add_theme_stylebox_override("pressed", Palette.task_item_style())
		btn.pressed.connect(_on_start_menu_item_pressed.bind(item.action as Callable))
		vbox.add_child(btn)


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

	var content := Control.new()
	var lbl := Label.new()
	lbl.text = "idle... idle... idle...\nprocess m-os_core: running\nuptime: 041:12:07"
	lbl.add_theme_font_override("font", Palette.font_body)
	lbl.add_theme_font_size_override("font_size", 5)
	lbl.add_theme_color_override("font_color", Palette.TEXT_FAINT)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_child(lbl)

	var win := window_manager.open_window(content, "SYSTEM.LOG", Rect2(204, 23, 109, 70))
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
