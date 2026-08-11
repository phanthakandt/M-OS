class_name ConfirmDialog
extends Control

signal confirmed
signal cancelled

@onready var scrim: ColorRect = $Scrim
@onready var panel: PanelContainer = $Panel
@onready var message_label: Label = $Panel/Margin/VBox/MessageLabel
@onready var confirm_button: Button = $Panel/Margin/VBox/ButtonRow/ConfirmButton
@onready var cancel_button: Button = $Panel/Margin/VBox/ButtonRow/CancelButton


func _ready() -> void:
	scrim.color = Palette.SCRIM
	panel.add_theme_stylebox_override("panel", Palette.window_style())

	message_label.add_theme_font_override("font", Palette.font_body)
	message_label.add_theme_font_size_override("font_size", 6)
	message_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)

	_style_button(confirm_button, Palette.blob_marked_style(), Palette.TEXT_MAIN)
	_style_button(cancel_button, Palette.task_item_style(), Palette.TEXT_DIM)

	scrim.gui_input.connect(_on_scrim_gui_input)
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)


func _style_button(btn: Button, style: StyleBoxFlat, font_color: Color) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_override("font", Palette.font_body)
	btn.add_theme_font_size_override("font_size", 5)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)


func ask(message: String) -> void:
	message_label.text = message
	scrim.visible = true
	panel.visible = true
	panel.reset_size()
	panel.position = (size - panel.size) / 2.0


func _close() -> void:
	scrim.visible = false
	panel.visible = false


func _on_scrim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()
		cancelled.emit()


func _on_cancel_pressed() -> void:
	_close()
	cancelled.emit()


func _on_confirm_pressed() -> void:
	_close()
	confirmed.emit()
