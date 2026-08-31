class_name DevCrackApp
extends Control

signal file_repacked(file_data: FileData)

const CONTEXT_MENU_SCENE := preload("res://scenes/ui/ContextMenu.tscn")

var current_file: FileData
var warning_dialog: WarningDialog
var window_manager: WindowManager
var self_window_id: String = ""
var _context_target_blob: BlobData

@onready var header_label: Label = $VBox/HeaderLabel
@onready var list: VBoxContainer = $VBox/Scroll/List
@onready var repack_button: Button = $VBox/BottomBar/RepackButton
@onready var _context_menu: ContextMenu = CONTEXT_MENU_SCENE.instantiate()


func _ready() -> void:
	header_label.add_theme_font_override("font", Palette.font_chrome)
	header_label.add_theme_font_size_override("font_size", 5)
	header_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)

	repack_button.text = "REPACK"
	repack_button.focus_mode = Control.FOCUS_NONE
	repack_button.add_theme_font_override("font", Palette.font_body)
	repack_button.add_theme_font_size_override("font_size", 6)
	repack_button.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	repack_button.add_theme_stylebox_override("normal", Palette.task_item_style())
	repack_button.add_theme_stylebox_override("hover", Palette.task_item_style())
	repack_button.add_theme_stylebox_override("pressed", Palette.task_item_style())
	repack_button.pressed.connect(_on_repack_pressed)

	add_child(_context_menu)
	_context_menu.item_selected.connect(_on_entry_context_item_selected)

	_show_state("")


## Called by FilesApp._open_devcrack and Desktop._open_readme_devcrack after
## open_window, per the app-configuration convention. The two call sites
## differ in one respect: FilesApp also connects file_repacked (so its file
## list can react to a repack — see _on_file_repacked), while Desktop does
## not, since readme.txt isn't part of any list FilesApp would need to
## refresh. DevCrack is never gated by a file's lock state — it's the tool
## that acts on that state (see _on_entry_context_item_selected/
## _on_repack_pressed), so it must always be enterable regardless of it.
## Only FilesApp._open_file/Desktop._open_readme respect GameState.is_locked(file).
func unpack(file: FileData) -> void:
	current_file = file
	header_label.text = "%s.%s" % [file.filename, file.extension]
	_rebuild_entry_list()
	_show_state("unpack")


func _rebuild_entry_list() -> void:
	for c in list.get_children():
		c.queue_free()

	for blob in current_file.blobs:
		_add_entry_row(blob)


## No styling here may hint which blob is should_remove before the player
## has touched it — every row starts out looking identical (aside from
## whatever last_modified flavor text it carries), and only the player's own
## disable/enable toggling ever changes a row's look, or the puzzle gives
## itself away. The disable/enable toggle lives in a right-click menu (see
## _on_entry_row_gui_input), not as an always-visible button.
func _add_entry_row(blob: BlobData) -> void:
	var base_text: String
	if blob.filename != "":
		base_text = "%s.%s" % [blob.filename, blob.extension]
		if blob.label != "":
			base_text += " (%s)" % blob.label
	else:
		base_text = blob.label

	var is_disabled := GameState.is_archive_entry_disabled(current_file, blob.id)

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", Palette.task_item_style())
	row.modulate.a = 0.5 if is_disabled else 1.0
	row.gui_input.connect(_on_entry_row_gui_input.bind(blob))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 3)
	row.add_child(hbox)

	var name_label := Label.new()
	name_label.text = base_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.add_theme_font_override("font", Palette.font_body)
	name_label.add_theme_font_size_override("font_size", 5)
	name_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	hbox.add_child(name_label)

	var status_label := Label.new()
	status_label.text = "offline" if is_disabled else blob.last_modified
	status_label.add_theme_font_override("font", Palette.font_body)
	status_label.add_theme_font_size_override("font_size", 5)
	status_label.add_theme_color_override("font_color", Palette.TEXT_FAINT)
	hbox.add_child(status_label)

	list.add_child(row)


func _on_entry_row_gui_input(event: InputEvent, blob: BlobData) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_context_target_blob = blob
		var toggle_label := "Enable" if GameState.is_archive_entry_disabled(current_file, blob.id) else "Disable"
		_context_menu.open_at(get_global_mouse_position(), [
			{"label": toggle_label, "action": "toggle"},
		])


func _on_entry_context_item_selected(action: String) -> void:
	if not _context_target_blob:
		return
	if action == "toggle":
		var currently_disabled := GameState.is_archive_entry_disabled(current_file, _context_target_blob.id)
		GameState.set_archive_entry_disabled(current_file, _context_target_blob.id, not currently_disabled)
		_rebuild_entry_list()


## REPACK is never blocked by the current archive state, and never judges
## the outcome either — a real repack tool just performs the operation and
## reports "done," full stop. Whether the resulting file happens to open
## afterward is not REPACK's concern; the player finds that out next time
## they try to open it via FilesApp, not from this button. The
## on_devcrack_repacked() call is the same kind of unconditional side effect —
## a flat per-press chance of spawning a ghost process, regardless of file or
## outcome (see GameState.on_devcrack_repacked()).
func _on_repack_pressed() -> void:
	GameState.on_devcrack_repacked()
	file_repacked.emit(current_file)
	if warning_dialog:
		warning_dialog.show_message("repack เสร็จสิ้น")
	if window_manager and self_window_id != "":
		window_manager.close_window(self_window_id)


func _show_state(state: String) -> void:
	header_label.visible = state == "unpack"
	$VBox/Scroll.visible = state == "unpack"
	$VBox/BottomBar.visible = state == "unpack"
