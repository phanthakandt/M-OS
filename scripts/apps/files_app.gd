class_name FilesApp
extends Control

signal file_opened(file_data: FileData)

const DRIVE := preload("res://data/drive.tres")
const DEVCRACK_SCENE := preload("res://scenes/apps/DevCrackApp.tscn")
const NOTE_VIEWER_SCENE := preload("res://scenes/apps/NoteViewer.tscn")
const CONTEXT_MENU_SCENE := preload("res://scenes/ui/ContextMenu.tscn")

## Fixed width for both the "kind" column header and every row's kind label,
## so the two line up — set on both from here rather than hardcoded twice.
const KIND_COLUMN_WIDTH := 40

var window_manager: WindowManager
var warning_dialog: WarningDialog

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

@onready var back_button: Button = $VBox/NavBarMargin/NavBar/BackButton
@onready var forward_button: Button = $VBox/NavBarMargin/NavBar/ForwardButton
@onready var breadcrumb_bar: HBoxContainer = $VBox/NavBarMargin/NavBar/BreadcrumbBar
@onready var hidden_toggle_button: Button = $VBox/NavBarMargin/NavBar/HiddenToggleButton
@onready var nav_bar_divider: ColorRect = $VBox/NavBarDivider
@onready var name_header_label: Label = $VBox/Body/MainColumn/MainMargin/MainInner/ColumnHeader/NameHeaderLabel
@onready var kind_header_label: Label = $VBox/Body/MainColumn/MainMargin/MainInner/ColumnHeader/KindHeaderLabel
@onready var list: VBoxContainer = $VBox/Body/MainColumn/MainMargin/MainInner/Scroll/List
@onready var status_bar: PanelContainer = $VBox/Body/MainColumn/StatusBarMargin/StatusBar
@onready var status_label: Label = $VBox/Body/MainColumn/StatusBarMargin/StatusBar/StatusLabel
@onready var sidebar_list: VBoxContainer = $VBox/Body/SidebarMargin/Sidebar/SidebarScroll/SidebarList
@onready var divider: ColorRect = $VBox/Body/Divider
@onready var _context_menu: ContextMenu = CONTEXT_MENU_SCENE.instantiate()


func _ready() -> void:
	divider.color = Palette.BORDER
	nav_bar_divider.color = Palette.BORDER

	_style_nav_button(back_button)
	_style_nav_button(forward_button)
	back_button.pressed.connect(_go_back)
	forward_button.pressed.connect(_go_forward)

	# Plain text, no box at all — matches the mockup, which draws
	# "[ ] show hidden" as bare text with no border/fill and no hover state
	# (unlike the sidebar/breadcrumb/row hovers, which the mockup does give a
	# distinct hover rule). All four button states share one fully
	# transparent stylebox rather than relying on Button.flat, since every
	# other button in this codebase explicitly overrides all four states.
	var toggle_style := Palette.make_flat_style(Palette.TRANSPARENT, Palette.TRANSPARENT, 0)
	hidden_toggle_button.focus_mode = Control.FOCUS_NONE
	hidden_toggle_button.add_theme_font_override("font", Palette.font_body)
	hidden_toggle_button.add_theme_font_size_override("font_size", 4)
	hidden_toggle_button.add_theme_color_override("font_color", Palette.TEXT_DIM)
	hidden_toggle_button.add_theme_stylebox_override("normal", toggle_style)
	hidden_toggle_button.add_theme_stylebox_override("hover", toggle_style)
	hidden_toggle_button.add_theme_stylebox_override("pressed", toggle_style)
	hidden_toggle_button.add_theme_stylebox_override("hover_pressed", toggle_style)
	hidden_toggle_button.toggled.connect(_on_hidden_toggled)
	_update_hidden_toggle_text(hidden_toggle_button.button_pressed)

	name_header_label.add_theme_font_override("font", Palette.font_body)
	name_header_label.add_theme_font_size_override("font_size", 4)
	name_header_label.add_theme_color_override("font_color", Palette.TEXT_FAINT)

	kind_header_label.custom_minimum_size = Vector2(KIND_COLUMN_WIDTH, 0)
	kind_header_label.add_theme_font_override("font", Palette.font_body)
	kind_header_label.add_theme_font_size_override("font_size", 4)
	kind_header_label.add_theme_color_override("font_color", Palette.TEXT_FAINT)

	status_bar.add_theme_stylebox_override("panel", _status_bar_style())
	status_label.add_theme_font_override("font", Palette.font_body)
	status_label.add_theme_font_size_override("font_size", 4)
	status_label.add_theme_color_override("font_color", Palette.TEXT_FAINT)

	if window_manager:
		window_manager.window_closed.connect(_on_window_closed)

	GameState.trashed_changed.connect(_rebuild_list)
	GameState.trashed_changed.connect(_rebuild_sidebar)

	add_child(_context_menu)
	_context_menu.item_selected.connect(_on_context_item_selected)

	_history = [[DRIVE]]
	_history_index = 0
	_rebuild_sidebar()
	_rebuild_list()


func _style_nav_button(btn: Button) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(9, 6)
	# Button's default size_flags_vertical (FILL) stretches it to NavBar's
	# full row height — which is set by the tallest sibling (BreadcrumbBar's
	# text), taller than the button itself — so its bottom edge was flush
	# against NavBarDivider with zero breathing room. SHRINK_CENTER keeps it
	# at its own small height and centers it in that taller row instead.
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_override("font", Palette.font_body)
	btn.add_theme_font_size_override("font_size", 4)
	btn.add_theme_color_override("font_color", Palette.TEXT_FAINT)
	btn.add_theme_stylebox_override("normal", _nav_button_style())
	btn.add_theme_stylebox_override("hover", _nav_button_style())
	btn.add_theme_stylebox_override("pressed", _nav_button_style())
	btn.add_theme_stylebox_override("disabled", _nav_button_style())


## task_item_style()'s uniform 2px content margin is what was actually
## holding BackButton/ForwardButton's height up — custom_minimum_size.y alone
## only sets a floor, not a cap, so shrinking it without also shrinking the
## stylebox's own vertical margin had no visible effect. Left/right margin
## stays the same as task_item_style(); only top/bottom shrinks, since only
## height was asked to come down.
func _nav_button_style() -> StyleBoxFlat:
	var style := Palette.make_flat_style(Palette.WINDOW_BG, Palette.BORDER, 1)
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style


## Top-border-only row, matching the mockup's status bar — same
## make_flat_style()-then-tweak-one-side idiom titlebar_style() already uses
## in Palette, just kept local since it's specific to this one row. StatusBar
## sits flush against the vertical Divider (no MainMargin inset — see
## MainColumn in the scene), so unlike before, its own content margin is
## what gives StatusLabel its left/right breathing room now.
func _status_bar_style() -> StyleBoxFlat:
	var style := Palette.make_flat_style(Palette.WINDOW_BG, Palette.BORDER, 0)
	style.border_width_top = 1
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


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


## Shared by the sidebar's shortcut rows and the breadcrumb's segment clicks —
## both just need "jump straight to this exact path," unlike _enter_folder()
## which always appends one level onto whatever path is current. Skips
## pushing a redundant history entry when already at that exact path (e.g.
## clicking the current folder's own sidebar shortcut, or its last breadcrumb
## segment), the same way a browser doesn't add a history entry for
## navigating to the page already showing.
func _navigate_to_path(path: Array) -> void:
	if _paths_equal(path, _current_path()):
		return
	_push_history(path.duplicate())


func _paths_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


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


## Root's top-level subfolders only, filtered by FolderData.is_hidden alone —
## a deliberately separate, always-on filter from the main list's
## _show_hidden toggle. A hidden root folder (e.g. "system") is an
## intentional puzzle element the player is meant to discover by turning on
## "show hidden" themselves in the main list; if the sidebar offered it as a
## direct shortcut it would let players skip that step. Keys off is_hidden
## alone — never a hardcoded folder name — so any future hidden root folder
## is excluded the same way, automatically. Also drops any top-level folder
## that's been trashed, so the sidebar never offers a shortcut into a folder
## FilesApp's own main list would refuse to show. No root ("drive:") shortcut
## row — this list is folders only, and "go to root" is already covered by
## the breadcrumb's own first segment.
func _rebuild_sidebar() -> void:
	for c in sidebar_list.get_children():
		c.queue_free()

	for subfolder in DRIVE.subfolders:
		if subfolder.is_hidden:
			continue
		if GameState.is_folder_deleted(subfolder):
			continue
		_add_sidebar_row(subfolder, [DRIVE, subfolder])


func _add_sidebar_row(folder: FolderData, target_path: Array) -> void:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", Palette.drive_sidebar_item_style(false))
	row.mouse_entered.connect(func(): row.add_theme_stylebox_override("panel", Palette.drive_sidebar_item_style(true)))
	row.mouse_exited.connect(func(): row.add_theme_stylebox_override("panel", Palette.drive_sidebar_item_style(false)))
	row.gui_input.connect(_on_sidebar_row_gui_input.bind(target_path))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 3)
	row.add_child(hbox)

	var icon_box := _make_icon_box(folder.folder_name.substr(0, 1).to_upper())
	hbox.add_child(icon_box)

	var name_label := Label.new()
	name_label.text = folder.folder_name
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_override("font", Palette.font_body)
	name_label.add_theme_font_size_override("font_size", 5)
	name_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	hbox.add_child(name_label)

	sidebar_list.add_child(row)


func _on_sidebar_row_gui_input(event: InputEvent, target_path: Array) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_navigate_to_path(target_path)


## Small glyph box shared by sidebar rows and main-list rows (folder/file
## icon) — same Panel + icon_glyph_style() + centered Label pattern
## DesktopIconUI/KikuChatApp's avatar/MosMailApp's avatar all already use.
## Children are MOUSE_FILTER_IGNORE so a click anywhere on the box still
## reaches the row's own gui_input.
func _make_icon_box(glyph: String) -> Panel:
	var icon_box := Panel.new()
	icon_box.custom_minimum_size = Vector2(9, 9)
	icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_theme_stylebox_override("panel", Palette.icon_glyph_style())

	var icon_label := Label.new()
	icon_label.text = glyph
	icon_label.clip_text = true
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_override("font", Palette.font_body)
	icon_label.add_theme_font_size_override("font_size", 4)
	icon_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	icon_box.add_child(icon_label)
	icon_label.set_anchors_preset(Control.PRESET_FULL_RECT)

	return icon_box


## Rebuilds the breadcrumb from the current path — every segment is
## clickable (via the shared _navigate_to_path(), same as the sidebar), the
## last segment (current folder) just renders already-TEXT_MAIN with no
## hover recolor since it's already "active" styling.
func _rebuild_breadcrumb() -> void:
	for c in breadcrumb_bar.get_children():
		c.queue_free()

	var path: Array = _current_path()
	for i in path.size():
		var folder: FolderData = path[i]
		var is_last := i == path.size() - 1
		var target_path: Array = path.slice(0, i + 1)

		var segment := Label.new()
		segment.text = folder.folder_name
		segment.clip_text = true
		segment.add_theme_font_override("font", Palette.font_body)
		segment.add_theme_font_size_override("font_size", 5)
		segment.add_theme_color_override("font_color", Palette.TEXT_MAIN if is_last else Palette.TEXT_DIM)
		segment.gui_input.connect(_on_breadcrumb_segment_gui_input.bind(target_path))
		if not is_last:
			segment.mouse_entered.connect(func(): segment.add_theme_color_override("font_color", Palette.TEXT_MAIN))
			segment.mouse_exited.connect(func(): segment.add_theme_color_override("font_color", Palette.TEXT_DIM))
		breadcrumb_bar.add_child(segment)

		if not is_last:
			var sep := Label.new()
			sep.text = "›"
			sep.add_theme_font_override("font", Palette.font_body)
			sep.add_theme_font_size_override("font_size", 5)
			sep.add_theme_color_override("font_color", Palette.TEXT_FAINT)
			breadcrumb_bar.add_child(sep)


func _on_breadcrumb_segment_gui_input(event: InputEvent, target_path: Array) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_navigate_to_path(target_path)


func _rebuild_list() -> void:
	back_button.disabled = _history_index <= 0
	forward_button.disabled = _history_index >= _history.size() - 1

	_rebuild_breadcrumb()

	for c in list.get_children():
		c.queue_free()

	var current: FolderData = _current_folder()
	var visible_count := 0

	for subfolder in current.subfolders:
		if subfolder.is_hidden and not _show_hidden:
			continue
		if GameState.is_folder_deleted(subfolder):
			continue
		_add_folder_row(subfolder)
		visible_count += 1

	for file in current.files:
		if file.is_hidden and not _show_hidden:
			continue
		if GameState.is_file_deleted(file):
			continue
		_add_file_row(file)
		visible_count += 1

	status_label.text = "%d item%s" % [visible_count, "" if visible_count == 1 else "s"]


func _add_folder_row(folder: FolderData) -> void:
	var name_text := folder.folder_name
	var color := Palette.TEXT_MAIN
	if folder.is_hidden:
		name_text += "  (hidden)"
		color = Palette.TEXT_FAINT

	var row := _make_row("▸", name_text, "folder", color)
	row.gui_input.connect(_on_folder_row_gui_input.bind(folder))
	list.add_child(row)


func _add_file_row(file: FileData) -> void:
	var name_text := "%s.%s" % [file.filename, file.extension]
	var color := Palette.TEXT_MAIN
	if file.is_hidden:
		name_text += "  (hidden)"
		color = Palette.TEXT_FAINT

	var icon_glyph := file.extension.substr(0, 1).to_upper() if file.extension != "" else "?"
	var row := _make_row(icon_glyph, name_text, "%s file" % file.extension, color)
	row.gui_input.connect(_on_file_row_gui_input.bind(file))
	list.add_child(row)


## Locked files/folders (GameState.is_locked) get no different treatment here
## at all — neither icon box nor color nor kind label ever varies with lock
## state — same "no advance hints" rule as everywhere else in the game.
func _make_row(icon_glyph: String, name_text: String, kind_text: String, color: Color) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", Palette.task_item_style())

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	row.add_child(hbox)

	var icon_box := _make_icon_box(icon_glyph)
	hbox.add_child(icon_box)

	var name_label := Label.new()
	name_label.text = name_text
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_override("font", Palette.font_body)
	name_label.add_theme_font_size_override("font_size", 5)
	name_label.add_theme_color_override("font_color", color)
	hbox.add_child(name_label)

	var kind_label := Label.new()
	kind_label.text = kind_text
	kind_label.clip_text = true
	kind_label.custom_minimum_size = Vector2(KIND_COLUMN_WIDTH, 0)
	kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kind_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kind_label.add_theme_font_override("font", Palette.font_body)
	kind_label.add_theme_font_size_override("font_size", 5)
	kind_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	hbox.add_child(kind_label)

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
			_close_all_windows_for(file)
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
		_close_all_windows_for(file)
	for subfolder in folder.subfolders:
		_close_open_windows_under(subfolder)


## A file can have both a NoteViewer and a DevCrack window open on it at
## once (_open_file_windows/_devcrack_windows are tracked separately) — this
## closes whichever of the two are actually open, so deleting a file never
## leaves either kind dangling.
func _close_all_windows_for(file: FileData) -> void:
	var key := _file_window_key(file)
	if _open_file_windows.has(key):
		window_manager.close_window(_open_file_windows[key])
	if _devcrack_windows.has(key):
		window_manager.close_window(_devcrack_windows[key])


func _open_file(file: FileData) -> void:
	file_opened.emit(file)
	if not window_manager:
		return

	var reason := GameState.get_lock_reason(file)
	if reason != GameState.LockReason.UNLOCKED:
		if warning_dialog:
			if reason == GameState.LockReason.CORRUPTED:
				warning_dialog.show_message("ไม่สามารถเปิดไฟล์นี้ได้เนื่องจากไฟล์เสียหาย")
			else:
				warning_dialog.show_message("ไม่สามารถเปิดไฟล์นี้ได้")
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
	content.warning_dialog = warning_dialog
	content.window_manager = window_manager
	content.file_repacked.connect(_on_file_repacked)
	var win := window_manager.open_window(
		content, "devcrack — %s.%s" % [file.filename, file.extension],
		Rect2(50, 20, 190, 150)
	)
	_devcrack_windows[key] = win.window_id
	content.self_window_id = win.window_id
	content.unpack(file)


func _on_file_repacked(_file: FileData) -> void:
	_rebuild_list()


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
