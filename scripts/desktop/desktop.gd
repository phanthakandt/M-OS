extends Control

const NOTE_VIEWER_SCENE := preload("res://scenes/apps/NoteViewer.tscn")
const FILES_APP_SCENE := preload("res://scenes/apps/FilesApp.tscn")
const WINDOW_SCENE := preload("res://scenes/window/Window.tscn")

const RULE_01 := preload("res://data/rules/rule_01.tres")
const RULE_02 := preload("res://data/rules/rule_02.tres")
const RULE_03 := preload("res://data/rules/rule_03.tres")
const RULE_04 := preload("res://data/rules/rule_04.tres")

@onready var background: ColorRect = $Background
@onready var window_layer: Control = $WindowLayer
@onready var window_manager: WindowManager = $WindowManager
@onready var my_pc_icon: DesktopIconUI = $IconGrid/MyPCIcon
@onready var taskbar: Control = $Taskbar
@onready var taskbar_panel: Panel = $Taskbar/Panel
@onready var start_button: Button = $Taskbar/Panel/HBox/StartButton
@onready var open_windows_list: HBoxContainer = $Taskbar/Panel/HBox/OpenWindowsList
@onready var clock_label: Label = $Taskbar/Panel/HBox/Clock
@onready var clock_timer: Timer = $ClockTimer

var _task_items: Dictionary = {}
var _work_area: Rect2 = Rect2()


func _ready() -> void:
	background.color = Palette.DESKTOP_BG_1

	taskbar_panel.add_theme_stylebox_override("panel", Palette.taskbar_style())

	start_button.focus_mode = Control.FOCUS_NONE
	start_button.text = "M-OS"
	start_button.add_theme_font_override("font", Palette.font_chrome)
	start_button.add_theme_font_size_override("font_size", 5)
	start_button.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	start_button.add_theme_stylebox_override("normal", Palette.start_button_style())
	start_button.add_theme_stylebox_override("hover", Palette.start_button_style())
	start_button.add_theme_stylebox_override("pressed", Palette.start_button_style())

	clock_label.add_theme_font_override("font", Palette.font_body)
	clock_label.add_theme_font_size_override("font_size", 6)
	clock_label.add_theme_color_override("font_color", Palette.TEXT_DIM)

	_work_area = Rect2(Vector2.ZERO, window_layer.size - Vector2(0, taskbar.size.y))
	window_manager.window_layer = window_layer
	window_manager.work_area = _work_area
	window_manager.window_opened.connect(_on_window_opened)
	window_manager.window_closed.connect(_on_window_closed)

	my_pc_icon.glyph = "▭"
	my_pc_icon.label_text = "My PC"
	my_pc_icon.activated.connect(_open_files_app)

	_spawn_decorative_system_log()
	_open_readme()

	clock_timer.wait_time = 1.0
	clock_timer.timeout.connect(_update_clock)
	clock_timer.start()
	_update_clock()


func _update_clock() -> void:
	var t := Time.get_time_dict_from_system()
	clock_label.text = "%02d:%02d" % [t.hour, t.minute]


func _spawn_decorative_system_log() -> void:
	var deco: AppWindow = WINDOW_SCENE.instantiate()
	window_layer.add_child(deco)
	deco.setup("SYSTEM.LOG", "sys_log_decor")
	deco.work_area = _work_area
	deco.position = Vector2(204, 23)
	deco.size = Vector2(109, 70)
	deco.modulate.a = 0.6

	var lbl := Label.new()
	lbl.text = "idle... idle... idle...\nprocess m-os_core: running\nuptime: 041:12:07"
	lbl.add_theme_font_override("font", Palette.font_body)
	lbl.add_theme_font_size_override("font_size", 5)
	lbl.add_theme_color_override("font_color", Palette.TEXT_FAINT)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	deco.get_content_slot().add_child(lbl)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)


func _open_readme() -> void:
	var content: NoteViewer = NOTE_VIEWER_SCENE.instantiate()
	window_manager.open_window(content, "READ_BEFORE_PROCEEDING.txt", Rect2(134, 29, 128, 147))
	content.show_warning_and_rules(
		"คำเตือน: อย่าพยายามลบ M-OS",
		"ให้ทำตามขั้นตอนต่อไปนี้อย่างเคร่งครัด",
		[RULE_01, RULE_02, RULE_03, RULE_04]
	)


func _open_files_app() -> void:
	var content: FilesApp = FILES_APP_SCENE.instantiate()
	content.window_manager = window_manager
	window_manager.open_window(content, "my_pc", Rect2(40, 30, 160, 140))


func _on_window_opened(window_id: String, title: String) -> void:
	var btn := Button.new()
	btn.text = title
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_text = true
	btn.custom_minimum_size = Vector2(24, 0)
	btn.add_theme_font_override("font", Palette.font_body)
	btn.add_theme_font_size_override("font_size", 6)
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
