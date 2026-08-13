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
		var f := folder as FolderData
		_add_row("▸ %s" % f.folder_name, Callable(GameState, "restore_folder").bind(f))

	if GameState.is_readme_deleted():
		_add_row("readme.txt", Callable(GameState, "restore_readme"))

	for file in GameState.get_trashed_files():
		var f := file as FileData
		_add_row("%s.%s" % [f.filename, f.extension], Callable(GameState, "restore_file").bind(f))

	if list.get_child_count() == 0:
		_add_empty_row()


func _add_row(text: String, restore_action: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)

	var name_label := Label.new()
	name_label.text = text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.add_theme_font_override("font", Palette.font_body)
	name_label.add_theme_font_size_override("font_size", 5)
	name_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	row.add_child(name_label)

	var restore_button := Button.new()
	restore_button.text = "[restore]"
	restore_button.focus_mode = Control.FOCUS_NONE
	restore_button.add_theme_font_override("font", Palette.font_body)
	restore_button.add_theme_font_size_override("font_size", 5)
	restore_button.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	restore_button.add_theme_stylebox_override("normal", Palette.task_item_style())
	restore_button.add_theme_stylebox_override("hover", Palette.task_item_style())
	restore_button.add_theme_stylebox_override("pressed", Palette.task_item_style())
	restore_button.pressed.connect(restore_action)
	row.add_child(restore_button)

	list.add_child(row)


func _add_empty_row() -> void:
	var row := Label.new()
	row.text = "(empty)"
	row.add_theme_font_override("font", Palette.font_body)
	row.add_theme_font_size_override("font_size", 5)
	row.add_theme_color_override("font_color", Palette.TEXT_FAINT)
	list.add_child(row)
