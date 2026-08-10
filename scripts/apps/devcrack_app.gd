class_name DevCrackApp
extends Control

signal file_unpacked(file_data: FileData, blobs: Array)
signal file_repacked(file_data: FileData, success: bool)

var current_file: FileData
var _blob_rows: Dictionary = {}

@onready var gate_label: Label = $VBox/GateLabel
@onready var header_label: Label = $VBox/HeaderLabel
@onready var hint_label: Label = $VBox/HintLabel
@onready var blob_list: VBoxContainer = $VBox/BlobList
@onready var feedback_label: Label = $VBox/FeedbackLabel
@onready var repack_button: Button = $VBox/RepackButton
@onready var reveal_label: Label = $VBox/RevealLabel


func _ready() -> void:
	_style_label(gate_label, Palette.font_body, 7, Palette.ACCENT_WARN)
	_style_label(header_label, Palette.font_chrome, 5, Palette.TEXT_MAIN)
	_style_label(hint_label, Palette.font_body, 6, Palette.TEXT_DIM)
	_style_label(feedback_label, Palette.font_body, 6, Palette.ACCENT_WARN)
	_style_label(reveal_label, Palette.font_body, 7, Palette.TEXT_MAIN)
	gate_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	reveal_label.autowrap_mode = TextServer.AUTOWRAP_WORD

	repack_button.text = "REPACK"
	repack_button.focus_mode = Control.FOCUS_NONE
	repack_button.pressed.connect(_on_repack_pressed)
	_style_button(repack_button)

	_show_state("empty")


func unpack(file: FileData) -> void:
	current_file = file
	feedback_label.text = ""
	_clear_blob_rows()

	if GameState.is_repacked(file):
		reveal_label.text = file.content
		_show_state("reveal")
		return

	if file.is_locked and not GameState.has_learned_devcrack:
		gate_label.text = "ไม่สามารถเปิดไฟล์นี้ได้"
		_show_state("gate")
		return

	header_label.text = "%s.%s" % [file.filename, file.extension]
	hint_label.text = file.reveals_clue
	for blob in file.blobs:
		var row := Button.new()
		row.toggle_mode = true
		row.text = blob.label
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.focus_mode = Control.FOCUS_NONE
		_style_blob_toggle(row)
		row.toggled.connect(_on_blob_toggled.bind(row, blob))
		blob_list.add_child(row)
		_blob_rows[blob.id] = row
	_show_state("unpack")
	file_unpacked.emit(file, file.blobs)


func repack() -> void:
	if current_file == null:
		return
	var success := _validate_repack()
	if success:
		GameState.mark_repacked(current_file)
		GameState.has_learned_devcrack = true
	else:
		feedback_label.text = "ยังไม่ถูก ลองใหม่"
	file_repacked.emit(current_file, success)
	if success:
		unpack(current_file)


func _validate_repack() -> bool:
	for blob in current_file.blobs:
		var removed: bool = _blob_rows[blob.id].button_pressed
		if removed != blob.should_remove:
			return false
	return true


func _on_blob_toggled(pressed: bool, row: Button, blob: BlobData) -> void:
	row.text = ("[ลบ] " if pressed else "") + blob.label


func _on_repack_pressed() -> void:
	repack()


func _clear_blob_rows() -> void:
	for child in blob_list.get_children():
		child.queue_free()
	_blob_rows.clear()


func _show_state(state: String) -> void:
	gate_label.visible = state == "gate"
	header_label.visible = state == "unpack"
	hint_label.visible = state == "unpack"
	blob_list.visible = state == "unpack"
	repack_button.visible = state == "unpack"
	feedback_label.visible = state == "unpack"
	reveal_label.visible = state == "reveal"


func _style_label(lbl: Label, font: Font, size: int, color: Color) -> void:
	lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)


func _style_button(btn: Button) -> void:
	btn.add_theme_font_override("font", Palette.font_body)
	btn.add_theme_font_size_override("font_size", 6)
	btn.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	btn.add_theme_stylebox_override("normal", Palette.task_item_style())
	btn.add_theme_stylebox_override("hover", Palette.task_item_style())
	btn.add_theme_stylebox_override("pressed", Palette.task_item_style())


func _style_blob_toggle(btn: Button) -> void:
	btn.add_theme_font_override("font", Palette.font_body)
	btn.add_theme_font_size_override("font_size", 6)
	btn.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	btn.add_theme_stylebox_override("normal", Palette.task_item_style())
	btn.add_theme_stylebox_override("hover", Palette.task_item_style())
	btn.add_theme_stylebox_override("pressed", Palette.blob_marked_style())
	btn.add_theme_stylebox_override("hover_pressed", Palette.blob_marked_style())
