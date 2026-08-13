class_name FilesApp
extends Control

signal file_opened(file_data: FileData)

const DRIVE := preload("res://data/drive.tres")
const DEVCRACK_SCENE := preload("res://scenes/apps/DevCrackApp.tscn")
const NOTE_VIEWER_SCENE := preload("res://scenes/apps/NoteViewer.tscn")
const CONTEXT_MENU_SCENE := preload("res://scenes/ui/ContextMenu.tscn")

var window_manager: WindowManager

## Each entry is the full path (Array[FolderData]) from root to that entry's
## folder. Navigating never mutates FolderData/FileData; all state lives here.
var _history: Array = []
var _history_index: int = 0
var _show_hidden: bool = false

## Windows opened from this browser, keyed by file key -> window_id, so
## reopening the same file focuses its existing window instead of duplicating it.
var _open_file_windows: Dictionary = {}

## Same idea as _open_file_windows, but for DevCrack windows — kept separate
## since a file can have both an open NoteViewer and an open DevCrack window
## at once, each tracked independently.
var _devcrack_windows: Dictionary = {}

## Whichever row's context menu is currently open — exactly one of the two
## is set at a time — so _on_context_item_selected knows what "Open"/"Delete"
## should act on.
var _context_target_file: FileData
var _context_target_folder: FolderData
var _notice_label: Label

@onready var back_button: Button = $VBox/NavBar/BackButton
@onready var forward_button: Button = $VBox/NavBar/ForwardButton
@onready var header_label: Label = $VBox/NavBar/HeaderLabel
@onready var hidden_toggle_button: Button = $VBox/NavBar/HiddenToggleButton
@onready var list: VBoxContainer = $VBox/Scroll/List
@onready var _context_menu: ContextMenu = CONTEXT_MENU_SCENE.instantiate()


func _ready() -> void:
	header_label.add_theme_font_override("font", Palette.font_chrome)
	header_label.add_theme_font_size_override("font_size", 4)
	header_label.add_theme_color_override("font_color", Palette.TEXT_DIM)

	_style_nav_button(back_button)
	_style_nav_button(forward_button)
	back_button.pressed.connect(_go_back)
	forward_button.pressed.connect(_go_forward)

	hidden_toggle_button.focus_mode = Control.FOCUS_NONE
	hidden_toggle_button.add_theme_font_override("font", Palette.font_body)
	hidden_toggle_button.add_theme_font_size_override("font_size", 5)
	hidden_toggle_button.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	hidden_toggle_button.add_theme_stylebox_override("normal", Palette.task_item_style())
	hidden_toggle_button.add_theme_stylebox_override("hover", Palette.task_item_style())
	hidden_toggle_button.add_theme_stylebox_override("pressed", Palette.task_item_style())
	hidden_toggle_button.add_theme_stylebox_override("hover_pressed", Palette.task_item_style())
	hidden_toggle_button.toggled.connect(_on_hidden_toggled)
	_update_hidden_toggle_text(hidden_toggle_button.button_pressed)

	if window_manager:
		window_manager.window_closed.connect(_on_window_closed)

	GameState.trashed_changed.connect(_rebuild_list)

	add_child(_context_menu)
	_context_menu.item_selected.connect(_on_context_item_selected)

	_history = [[DRIVE]]
	_history_index = 0
	_rebuild_list()


func _style_nav_button(btn: Button) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(12, 0)
	btn.add_theme_font_override("font", Palette.font_body)
	btn.add_theme_font_size_override("font_size", 5)
	btn.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	btn.add_theme_stylebox_override("normal", Palette.task_item_style())
	btn.add_theme_stylebox_override("hover", Palette.task_item_style())
	btn.add_theme_stylebox_override("pressed", Palette.task_item_style())
	btn.add_theme_stylebox_override("disabled", Palette.task_item_style())


func _on_hidden_toggled(pressed: bool) -> void:
	_show_hidden = pressed
	_update_hidden_toggle_text(pressed)
	_rebuild_list()


func _update_hidden_toggle_text(pressed: bool) -> void:
	hidden_toggle_button.text = "[x] show hidden" if pressed else "[ ] show hidden"


func _current_path() -> Array:
	return _history[_history_index]


func _current_folder() -> FolderData:
	var path: Array = _current_path()
	return path[path.size() - 1]


func _enter_folder(folder: FolderData) -> void:
	var new_path: Array = _current_path().duplicate()
	new_path.append(folder)
	_push_history(new_path)


func _push_history(path: Array) -> void:
	_history.resize(_history_index + 1)
	_history.append(path)
	_history_index += 1
	_rebuild_list()


func _go_back() -> void:
	if _history_index <= 0:
		return
	_history_index -= 1
	_rebuild_list()


func _go_forward() -> void:
	if _history_index >= _history.size() - 1:
		return
	_history_index += 1
	_rebuild_list()


func _rebuild_list() -> void:
	back_button.disabled = _history_index <= 0
	forward_button.disabled = _history_index >= _history.size() - 1

	var path: Array = _current_path()
	var names: Array = []
	for folder in path:
		names.append((folder as FolderData).folder_name)
	header_label.text = "/".join(names)

	for c in list.get_children():
		c.queue_free()

	var current: FolderData = _current_folder()

	for subfolder in current.subfolders:
		if subfolder.is_hidden and not _show_hidden:
			continue
		if GameState.is_folder_deleted(subfolder):
			continue
		_add_folder_row(subfolder)

	for file in current.files:
		if file.is_hidden and not _show_hidden:
			continue
		if GameState.is_file_deleted(file):
			continue
		_add_file_row(file)


func _add_folder_row(folder: FolderData) -> void:
	var text := "▸ %s" % folder.folder_name
	var color := Palette.TEXT_MAIN
	if folder.is_hidden:
		text += "  (hidden)"
		color = Palette.TEXT_FAINT

	var row := _make_row(text, color)
	row.gui_input.connect(_on_folder_row_gui_input.bind(folder))
	list.add_child(row)


func _add_file_row(file: FileData) -> void:
	var text := "%s.%s" % [file.filename, file.extension]
	var color := Palette.TEXT_MAIN
	if file.is_hidden:
		text += "  (hidden)"
		color = Palette.TEXT_FAINT
	elif GameState.is_locked(file):
		text += "  (locked)"
		color = Palette.ACCENT_WARN

	var row := _make_row(text, color)
	row.gui_input.connect(_on_file_row_gui_input.bind(file))
	list.add_child(row)


func _make_row(text: String, color: Color) -> Button:
	var row := Button.new()
	row.text = text
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.focus_mode = Control.FOCUS_NONE
	row.add_theme_font_override("font", Palette.font_body)
	row.add_theme_font_size_override("font_size", 5)
	row.add_theme_color_override("font_color", color)
	row.add_theme_stylebox_override("normal", Palette.task_item_style())
	row.add_theme_stylebox_override("hover", Palette.task_item_style())
	row.add_theme_stylebox_override("pressed", Palette.task_item_style())
	return row


func _on_folder_row_gui_input(event: InputEvent, folder: FolderData) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		_enter_folder(folder)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_context_target_folder = folder
		_context_target_file = null
		var items: Array = [{"label": "Open", "action": "open"}]
		if GameState.can_delete_folder(folder):
			items.append({"label": "Delete", "action": "delete"})
		_context_menu.open_at(get_global_mouse_position(), items)


func _on_file_row_gui_input(event: InputEvent, file: FileData) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		_open_file(file)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_context_target_file = file
		_context_target_folder = null
		var items: Array = [{"label": "Open", "action": "open"}]
		items.append({"label": "Unpack through DevCrack", "action": "unpack"})
		if GameState.can_delete_file(file):
			items.append({"label": "Delete", "action": "delete"})
		_context_menu.open_at(get_global_mouse_position(), items)


func _on_context_item_selected(action: String) -> void:
	if _context_target_file:
		var file := _context_target_file
		if action == "open":
			_open_file(file)
		elif action == "unpack":
			_open_devcrack(file)
		elif action == "delete":
			GameState.delete_file(file)
			var key := _file_window_key(file)
			if _open_file_windows.has(key):
				window_manager.close_window(_open_file_windows[key])
	elif _context_target_folder:
		var folder := _context_target_folder
		if action == "open":
			_enter_folder(folder)
		elif action == "delete":
			GameState.delete_folder(folder)
			_close_open_windows_under(folder)


## Deleting a folder trashes it as one entry (see GameState.delete_folder) —
## its contents are never individually walked for that — but any windows
## already open on files inside it would otherwise dangle, so this walks
## the (now-trashed) subtree just to close those.
func _close_open_windows_under(folder: FolderData) -> void:
	for file in folder.files:
		var key := _file_window_key(file)
		if _open_file_windows.has(key):
			window_manager.close_window(_open_file_windows[key])
	for subfolder in folder.subfolders:
		_close_open_windows_under(subfolder)


func _open_file(file: FileData) -> void:
	file_opened.emit(file)
	if not window_manager:
		return

	if GameState.is_locked(file):
		_show_notice("ไม่สามารถเปิดไฟล์นี้ได้ — ลองคลิกขวา > Unpack through DevCrack")
		return

	var key := _file_window_key(file)
	if _open_file_windows.has(key):
		window_manager.reveal_window(_open_file_windows[key])
		return

	var content: NoteViewer = NOTE_VIEWER_SCENE.instantiate()
	var win := window_manager.open_window(content, "%s.%s" % [file.filename, file.extension], Rect2(60, 20, 180, 140))
	_open_file_windows[key] = win.window_id
	content.show_plain(file.content)


func _open_devcrack(file: FileData) -> void:
	if not window_manager:
		return

	var key := _file_window_key(file)
	if _devcrack_windows.has(key):
		window_manager.reveal_window(_devcrack_windows[key])
		return

	var content: DevCrackApp = DEVCRACK_SCENE.instantiate()
	var win := window_manager.open_window(
		content, "devcrack — %s.%s" % [file.filename, file.extension],
		Rect2(50, 20, 190, 150)
	)
	_devcrack_windows[key] = win.window_id
	content.unpack(file)


func _show_notice(text: String) -> void:
	if is_instance_valid(_notice_label):
		_notice_label.queue_free()

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", Palette.font_body)
	lbl.add_theme_font_size_override("font_size", 5)
	lbl.add_theme_color_override("font_color", Palette.ACCENT_WARN)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	add_child(lbl)
	_notice_label = lbl

	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(lbl):
		lbl.queue_free()


func _file_window_key(file: FileData) -> String:
	return file.id if file.id != "" else file.resource_path


func _on_window_closed(window_id: String) -> void:
	for key in _open_file_windows.keys():
		if _open_file_windows[key] == window_id:
			_open_file_windows.erase(key)
			break
	for key in _devcrack_windows.keys():
		if _devcrack_windows[key] == window_id:
			_devcrack_windows.erase(key)
			break
