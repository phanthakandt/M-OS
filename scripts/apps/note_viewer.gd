class_name NoteViewer
extends Control

@onready var rich_text: RichTextLabel = $RichText


func _ready() -> void:
	rich_text.bbcode_enabled = true
	rich_text.scroll_active = true
	rich_text.add_theme_font_override("normal_font", Palette.font_body)
	rich_text.add_theme_font_size_override("normal_font_size", 4)
	rich_text.add_theme_color_override("default_color", Palette.TEXT_DIM)


func show_plain(text: String) -> void:
	rich_text.text = "[color=#cdd8e2]%s[/color]" % text
