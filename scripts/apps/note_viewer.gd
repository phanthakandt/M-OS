class_name NoteViewer
extends Control

const CHROME_FONT_PATH := "res://assets/fonts/PressStart2P-Regular.ttf"

@onready var rich_text: RichTextLabel = $RichText


func _ready() -> void:
	rich_text.bbcode_enabled = true
	rich_text.scroll_active = true
	rich_text.add_theme_font_override("normal_font", Palette.font_body)
	rich_text.add_theme_font_size_override("normal_font_size", 4)
	rich_text.add_theme_color_override("default_color", Palette.TEXT_DIM)


func show_warning_and_rules(warning_title: String, rules: Array) -> void:
	var bb := "[color=#FF0000]%s[/color]\n\n" % [warning_title]
	for rule in rules:
		bb += "[font=%s][color=#cdd8e2]%02d[/color][/font]\n[color=#7d8b9a]%s[/color]\n\n" % [CHROME_FONT_PATH, rule.rule_number, rule.text]
	rich_text.text = bb


func show_plain(text: String) -> void:
	rich_text.text = "[color=#cdd8e2]%s[/color]" % text
