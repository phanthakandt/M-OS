extends Control

const NOTE_VIEWER_SCENE := preload("res://scenes/apps/NoteViewer.tscn")
const FILES_APP_SCENE := preload("res://scenes/apps/FilesApp.tscn")

const RULE_01 := preload("res://data/rules/rule_01.tres")
const RULE_02 := preload("res://data/rules/rule_02.tres")
const RULE_03 := preload("res://data/rules/rule_03.tres")
const RULE_04 := preload("res://data/rules/rule_04.tres")

@onready var background: ColorRect = $Background
@onready var window_layer: Control = $WindowLayer
@onready var window_manager: WindowManager = $WindowManager
@onready var drive_icon: DesktopIconUI = $IconGrid/DriveIcon
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

## Single-instance app windows opened from the desktop shell (icons, start
## menu), keyed by an arbitrary app key -> window_id. Reopening a key focuses
## the existing window instead of spawning a duplicate.
var _singleton_windows: Dictionary = {}


func _ready() -> void:
	background.color = Palette.DESKTOP_BG_1

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

	drive_icon.glyph = "▤"
	drive_icon.label_text = "drive"
	drive_icon.activated.connect(_open_files_app)

	_start_menu_items = [
		{"label": "SYSTEM.LOG", "action": Callable(self, "_open_system_log")},
	]
	_build_start_menu()
	_open_readme()

	clock_timer.wait_time = 1.0
	clock_timer.timeout.connect(_update_clock)
	clock_timer.start()
	_update_clock()


func _update_clock() -> void:
	var t := Time.get_time_dict_from_system()
	clock_label.text = "%02d:%02d" % [t.hour, t.minute]


func _open_readme() -> void:
	var content: NoteViewer = NOTE_VIEWER_SCENE.instantiate()
	window_manager.open_window(content, "READ_BEFORE_PROCEEDING.txt", Rect2(134, 29, 128, 147))
	content.show_warning_and_rules(
		"คำเตือน: อย่าพยายามลบ M-OS",
		"ให้ทำตามขั้นตอนต่อไปนี้อย่างเคร่งครัด",
		[RULE_01, RULE_02, RULE_03, RULE_04]
	)


func _open_files_app() -> void:
	if _focus_if_open("drive"):
		return
	var content: FilesApp = FILES_APP_SCENE.instantiate()
	content.window_manager = window_manager
	var win := window_manager.open_window(content, "drive", Rect2(40, 30, 160, 140))
	_singleton_windows["drive"] = win.window_id


func _focus_if_open(key: String) -> bool:
	if not _singleton_windows.has(key):
		return false
	window_manager.focus_window(_singleton_windows[key])
	return true


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
	vbox.add_theme_constant_override("separation", 3)
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
