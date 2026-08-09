class_name AppWindow
extends Control

signal closed(window_id: String)
signal focused(window_id: String)

var window_id: String = ""
var work_area: Rect2 = Rect2()

var _is_maximized: bool = false
var _restore_rect: Rect2 = Rect2()

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

@onready var panel: Panel = $Panel
@onready var titlebar_panel: Panel = $Panel/VBox/TitleBar
@onready var title_label: Label = $Panel/VBox/TitleBar/HBox/TitleLabel
@onready var content_slot: Control = $Panel/VBox/ContentSlot
@onready var minimize_button: Button = $Panel/VBox/TitleBar/HBox/Controls/MinimizeButton
@onready var maximize_button: Button = $Panel/VBox/TitleBar/HBox/Controls/MaximizeButton
@onready var close_button: Button = $Panel/VBox/TitleBar/HBox/Controls/CloseButton


func _ready() -> void:
	panel.add_theme_stylebox_override("panel", Palette.window_style())
	title_label.add_theme_font_override("font", Palette.font_chrome)
	title_label.add_theme_font_size_override("font_size", 5)
	title_label.clip_text = true

	_style_titlebar_button(minimize_button, Palette.ACCENT_MINIMIZE)
	_style_titlebar_button(maximize_button, Palette.ACCENT_MAXIMIZE)
	_style_titlebar_button(close_button, Palette.ACCENT_WARN)

	minimize_button.pressed.connect(_on_minimize_pressed)
	maximize_button.pressed.connect(_on_maximize_pressed)
	close_button.pressed.connect(_on_close_pressed)
	panel.gui_input.connect(_on_panel_gui_input)
	content_slot.gui_input.connect(_on_panel_gui_input)
	titlebar_panel.gui_input.connect(_on_titlebar_gui_input)

	set_active(false)


func setup(title: String, id: String) -> void:
	window_id = id
	title_label.text = title


func set_active(active: bool) -> void:
	titlebar_panel.add_theme_stylebox_override("panel", Palette.titlebar_style(active))
	title_label.add_theme_color_override("font_color", Palette.TEXT_MAIN if active else Palette.TEXT_DIM)


func get_content_slot() -> Control:
	return content_slot


func _on_close_pressed() -> void:
	closed.emit(window_id)
	queue_free()


func _on_minimize_pressed() -> void:
	hide()


func _on_maximize_pressed() -> void:
	if _is_maximized:
		position = _restore_rect.position
		size = _restore_rect.size
		_is_maximized = false
		return

	_restore_rect = Rect2(position, size)
	if work_area.size != Vector2.ZERO:
		position = work_area.position
		size = work_area.size
	else:
		position = Vector2.ZERO
		size = get_parent_area_size()
	_is_maximized = true


func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		focused.emit(window_id)


func _on_titlebar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		focused.emit(window_id)
		if not _is_maximized:
			_dragging = true
			_drag_offset = get_global_mouse_position() - global_position


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		var new_pos: Vector2 = get_global_mouse_position() - _drag_offset
		var bounds: Vector2 = get_parent_area_size()
		new_pos.x = clamp(new_pos.x, -(size.x - 20.0), bounds.x - 20.0)
		new_pos.y = clamp(new_pos.y, 0.0, bounds.y - 10.0)
		global_position = new_pos
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false


func _style_titlebar_button(btn: Button, accent: Color) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	var style := Palette.tb_btn_style_accent(accent)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
