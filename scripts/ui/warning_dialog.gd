class_name WarningDialog
extends Control

signal acknowledged

@onready var scrim: ColorRect = $Scrim
@onready var panel: PanelContainer = $Panel
@onready var message_label: Label = $Panel/Margin/VBox/MessageLabel
@onready var ok_button: Button = $Panel/Margin/VBox/OkButton


func _ready() -> void:
	scrim.color = Palette.SCRIM
	panel.add_theme_stylebox_override("panel", Palette.window_style())

	message_label.add_theme_font_override("font", Palette.font_body)
	message_label.add_theme_font_size_override("font_size", 6)
	message_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)

	ok_button.focus_mode = Control.FOCUS_NONE
	ok_button.add_theme_font_override("font", Palette.font_body)
	ok_button.add_theme_font_size_override("font_size", 5)
	ok_button.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	ok_button.add_theme_stylebox_override("normal", Palette.task_item_style())
	ok_button.add_theme_stylebox_override("hover", Palette.task_item_style())
	ok_button.add_theme_stylebox_override("pressed", Palette.task_item_style())
	ok_button.pressed.connect(_on_ok_pressed)
	# scrim ตั้งใจไม่ต่อ gui_input ปิดให้ — mouse_filter = STOP ของมัน (ตั้งไว้
	# ใน .tscn) พอแล้วสำหรับกันคลิกทะลุไปโดนของข้างหลัง โดยไม่ทำให้ปิด modal


func show_message(message: String) -> void:
	message_label.text = message
	scrim.visible = true
	panel.visible = true
	panel.reset_size()
	panel.position = (size - panel.size) / 2.0


func _close() -> void:
	scrim.visible = false
	panel.visible = false


func _on_ok_pressed() -> void:
	_close()
	acknowledged.emit()
