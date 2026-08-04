class_name AppWindow
extends Control

signal closed(window_id: String)
signal focused(window_id: String)

var window_id: String = ""

@onready var panel: Panel = $Panel
@onready var titlebar_panel: Panel = $Panel/VBox/TitleBar
@onready var title_label: Label = $Panel/VBox/TitleBar/HBox/TitleLabel
@onready var content_slot: Control = $Panel/VBox/ContentSlot
@onready var close_button: Button = $Panel/VBox/TitleBar/HBox/Controls/CloseButton


func _ready() -> void:
	panel.add_theme_stylebox_override("panel", Palette.window_style())
	title_label.add_theme_font_override("font", Palette.font_chrome)
	title_label.add_theme_font_size_override("font_size", 5)
	title_label.clip_text = true

	for btn in [$Panel/VBox/TitleBar/HBox/Controls/Btn1, $Panel/VBox/TitleBar/HBox/Controls/Btn2, close_button]:
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_stylebox_override("normal", Palette.tb_btn_style())
		btn.add_theme_stylebox_override("hover", Palette.tb_btn_style())
		btn.add_theme_stylebox_override("pressed", Palette.tb_btn_style())

	close_button.pressed.connect(_on_close_pressed)
	panel.gui_input.connect(_on_panel_gui_input)
	content_slot.gui_input.connect(_on_panel_gui_input)

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


func _on_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		focused.emit(window_id)
