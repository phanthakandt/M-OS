class_name TrashApp
extends Control

@onready var header_label: Label = $VBox/HeaderLabel
@onready var list: VBoxContainer = $VBox/Scroll/List


func _ready() -> void:
	header_label.add_theme_font_override("font", Palette.font_chrome)
	header_label.add_theme_font_size_override("font_size", 4)
	header_label.add_theme_color_override("font_color", Palette.TEXT_DIM)

	GameState.trashed_changed.connect(_rebuild_list)
	_rebuild_list()


func _rebuild_list() -> void:
	for c in list.get_children():
		c.queue_free()

	for folder in GameState.get_trashed_folders():
		_add_row("▸ %s" % (folder as FolderData).folder_name, Palette.TEXT_MAIN)

	if GameState.is_readme_deleted():
		_add_row("readme.txt", Palette.TEXT_MAIN)

	for file in GameState.get_trashed_files():
		var f := file as FileData
		_add_row("%s.%s" % [f.filename, f.extension], Palette.TEXT_MAIN)

	if list.get_child_count() == 0:
		_add_row("(empty)", Palette.TEXT_FAINT)


func _add_row(text: String, color: Color) -> void:
	var row := Label.new()
	row.text = text
	row.add_theme_font_override("font", Palette.font_body)
	row.add_theme_font_size_override("font_size", 5)
	row.add_theme_color_override("font_color", color)
	list.add_child(row)
