extends Control

signal login_submitted(player_name: String)

@onready var name_input: LineEdit = $VBox/NameInput
@onready var enter_button: Button = $VBox/EnterButton
@onready var title_label: Label = $VBox/TitleLabel


func _ready() -> void:
	title_label.text = "M-OS"
	title_label.add_theme_font_override("font", Palette.font_chrome)
	title_label.add_theme_font_size_override("font_size", 8)
	title_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)

	name_input.placeholder_text = "username"
	name_input.add_theme_font_override("font", Palette.font_body)
	name_input.add_theme_font_size_override("font_size", 7)
	name_input.text_submitted.connect(_on_submitted)

	enter_button.text = "LOGIN"
	enter_button.focus_mode = Control.FOCUS_NONE
	enter_button.add_theme_font_override("font", Palette.font_body)
	enter_button.add_theme_font_size_override("font_size", 6)
	enter_button.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	_on_submitted(name_input.text)


func _on_submitted(text: String) -> void:
	var final_name := text.strip_edges()
	if final_name.is_empty():
		final_name = "user"
	PlayerIdentity.player_name = final_name
	login_submitted.emit(final_name)
