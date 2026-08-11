class_name TaskManagerApp
extends Control

var window_manager: WindowManager
var self_window_id: String = ""

@onready var header_label: Label = $VBox/HeaderLabel
@onready var list: VBoxContainer = $VBox/Scroll/List


func _ready() -> void:
	header_label.add_theme_font_override("font", Palette.font_chrome)
	header_label.add_theme_font_size_override("font_size", 4)
	header_label.add_theme_color_override("font_color", Palette.TEXT_DIM)

	if window_manager:
		window_manager.window_opened.connect(_on_window_list_changed)
		window_manager.window_closed.connect(_on_window_list_changed)

	_rebuild_list()


func _on_window_list_changed(_window_id: String, _title: String = "") -> void:
	_rebuild_list()


## Called by whoever opened this window once self_window_id is set, so the
## initial list excludes this task manager's own row.
func refresh_list() -> void:
	_rebuild_list()


func _rebuild_list() -> void:
	for c in list.get_children():
		c.queue_free()

	if not window_manager:
		return

	for entry in window_manager.get_open_windows():
		if entry.id == self_window_id:
			continue
		_add_process_row(entry.id, entry.title)


func _add_process_row(window_id: String, title: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)

	var name_button := Button.new()
	name_button.text = title
	name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_button.focus_mode = Control.FOCUS_NONE
	name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_button.clip_text = true
	name_button.add_theme_font_override("font", Palette.font_body)
	name_button.add_theme_font_size_override("font_size", 5)
	name_button.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	name_button.add_theme_stylebox_override("normal", Palette.task_item_style())
	name_button.add_theme_stylebox_override("hover", Palette.task_item_style())
	name_button.add_theme_stylebox_override("pressed", Palette.task_item_style())
	name_button.gui_input.connect(_on_name_button_gui_input.bind(window_id))
	row.add_child(name_button)

	var close_button := Button.new()
	close_button.text = "[x]"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.add_theme_font_override("font", Palette.font_body)
	close_button.add_theme_font_size_override("font_size", 5)
	close_button.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	close_button.add_theme_stylebox_override("normal", Palette.task_item_style())
	close_button.add_theme_stylebox_override("hover", Palette.task_item_style())
	close_button.add_theme_stylebox_override("pressed", Palette.task_item_style())
	close_button.pressed.connect(_on_close_button_pressed.bind(window_id))
	row.add_child(close_button)

	list.add_child(row)


func _on_name_button_gui_input(event: InputEvent, window_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.double_click:
		window_manager.reveal_window(window_id)


func _on_close_button_pressed(window_id: String) -> void:
	window_manager.close_window(window_id)
