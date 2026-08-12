class_name DesktopIconUI
extends VBoxContainer

signal activated
signal context_requested

@export var glyph: String = ""
@export var label_text: String = ""

@onready var glyph_box: Panel = $GlyphWrap/GlyphBox
@onready var glyph_label: Label = $GlyphWrap/GlyphBox/Glyph
@onready var name_label: Label = $NameLabel


func _ready() -> void:
	glyph_box.add_theme_stylebox_override("panel", Palette.icon_glyph_style())
	glyph_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	glyph_label.add_theme_font_size_override("font_size", 6)
	glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	name_label.add_theme_font_override("font", Palette.font_body)
	name_label.add_theme_font_size_override("font_size", 6)
	name_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD

	configure(glyph, label_text)


## A parent's _ready() always runs after its children's, so a parent that
## just assigns .glyph/.label_text after instancing this scene is too late
## to affect the labels set above — call this instead (safe any time after
## this node has entered the tree, since it needs the @onready refs).
func configure(new_glyph: String, new_label_text: String) -> void:
	glyph = new_glyph
	label_text = new_label_text
	glyph_label.text = glyph
	name_label.text = label_text


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		activated.emit()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		context_requested.emit()
