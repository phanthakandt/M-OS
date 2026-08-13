class_name DevCrackApp
extends Control

signal file_repacked(file_data: FileData, unlocked: bool)

const CONTEXT_MENU_SCENE := preload("res://scenes/ui/ContextMenu.tscn")

var current_file: FileData
var _context_target_blob: BlobData
var _notice_label: Label

@onready var header_label: Label = $VBox/HeaderLabel
@onready var list: VBoxContainer = $VBox/Scroll/List
@onready var feedback_label: Label = $VBox/FeedbackLabel
@onready var repack_button: Button = $VBox/BottomBar/RepackButton
@onready var _context_menu: ContextMenu = CONTEXT_MENU_SCENE.instantiate()


func _ready() -> void:
	header_label.add_theme_font_override("font", Palette.font_chrome)
	header_label.add_theme_font_size_override("font_size", 5)
	header_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)

	feedback_label.add_theme_font_override("font", Palette.font_body)
	feedback_label.add_theme_font_size_override("font_size", 6)
	feedback_label.add_theme_color_override("font_color", Palette.TEXT_DIM)

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


## Called by FilesApp after open_window, per the app-configuration convention.
## DevCrack is never gated by a file's lock state — it's the tool that acts
## on that state (see _on_entry_context_item_selected/_on_repack_pressed),
## so it must always be enterable regardless of it. Only FilesApp._open_file
## respects GameState.is_locked(file).
func unpack(file: FileData) -> void:
	current_file = file
	feedback_label.text = ""
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
## itself away. copy/paste/disable-enable live in a right-click menu (see
## _on_entry_row_gui_input), not as always-visible buttons.
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
			{"label": "Copy", "action": "copy"},
			{"label": "Paste", "action": "paste"},
			{"label": toggle_label, "action": "toggle"},
		])


func _on_entry_context_item_selected(action: String) -> void:
	if not _context_target_blob:
		return
	if action == "toggle":
		var currently_disabled := GameState.is_archive_entry_disabled(current_file, _context_target_blob.id)
		GameState.set_archive_entry_disabled(current_file, _context_target_blob.id, not currently_disabled)
		_rebuild_entry_list()
	elif action == "copy" or action == "paste":
		_show_notice("ยังไม่รองรับฟังก์ชันนี้")


## REPACK is never blocked by the current data.protected state — the player
## is free to repack anytime, whether or not the archive is currently
## configured to unlock the file. GameState.is_locked(file) (computed live
## from the current disabled-state) decides the actual outcome, not this
## button; REPACK just reports it.
func _on_repack_pressed() -> void:
	var locked := GameState.is_locked(current_file)
	if locked:
		feedback_label.text = "repack เสร็จแล้ว — ไฟล์นี้ยังล็อกอยู่ (data.protected ยัง enabled)"
		feedback_label.add_theme_color_override("font_color", Palette.ACCENT_WARN)
	else:
		feedback_label.text = "repack สำเร็จ — เปิดไฟล์นี้ได้แล้วผ่าน drive"
		# reuse ACCENT_MAXIMIZE (the green already in the palette) rather than add a new color
		feedback_label.add_theme_color_override("font_color", Palette.ACCENT_MAXIMIZE)
	file_repacked.emit(current_file, not locked)


func _show_notice(text: String) -> void:
	if is_instance_valid(_notice_label):
		_notice_label.queue_free()

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", Palette.font_body)
	lbl.add_theme_font_size_override("font_size", 5)
	lbl.add_theme_color_override("font_color", Palette.ACCENT_WARN)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	add_child(lbl)
	_notice_label = lbl

	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(lbl):
		lbl.queue_free()


func _show_state(state: String) -> void:
	header_label.visible = state == "unpack"
	$VBox/Scroll.visible = state == "unpack"
	feedback_label.visible = state == "unpack"
	$VBox/BottomBar.visible = state == "unpack"
