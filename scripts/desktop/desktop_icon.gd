class_name DesktopIconUI
extends VBoxContainer

signal activated

@export var glyph: String = "▭"
@export var label_text: String = "Icon"

@onready var glyph_box: Panel = $GlyphWrap/GlyphBox
@onready var glyph_label: Label = $GlyphWrap/GlyphBox/Glyph
@onready var name_label: Label = $NameLabel


func _ready() -> void:
	glyph_box.add_theme_stylebox_override("panel", Palette.icon_glyph_style())
	glyph_label.text = glyph
	glyph_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	glyph_label.add_theme_font_size_override("font_size", 8)
	glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	name_label.text = label_text
	name_label.add_theme_font_override("font", Palette.font_body)
	name_label.add_theme_font_size_override("font_size", 6)
	name_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.double_click:
		activated.emit()
