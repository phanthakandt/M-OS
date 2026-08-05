class_name FilesApp
extends Control

signal file_opened(file_data: FileData)

const DEF_MOS := preload("res://data/files/def_mos.tres")
const FORBIDDEN_FILE := preload("res://data/files/forbidden_file.tres")
const DEVCRACK_SCENE := preload("res://scenes/apps/DevCrackApp.tscn")
const NOTE_VIEWER_SCENE := preload("res://scenes/apps/NoteViewer.tscn")

var window_manager: WindowManager

@onready var header_label: Label = $VBox/HeaderLabel
@onready var list: VBoxContainer = $VBox/Scroll/List


func _ready() -> void:
	header_label.text = "drive://C"
	header_label.add_theme_font_override("font", Palette.font_chrome)
	header_label.add_theme_font_size_override("font_size", 5)
	header_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_rebuild_list()


func _rebuild_list() -> void:
	for c in list.get_children():
		c.queue_free()
	for file in [DEF_MOS, FORBIDDEN_FILE]:
		var locked: bool = file.is_locked and not file.is_repacked
		var row := Button.new()
		row.text = "%s.%s%s" % [file.filename, file.extension, ("  (locked)" if locked else "")]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.focus_mode = Control.FOCUS_NONE
		row.add_theme_font_override("font", Palette.font_body)
		row.add_theme_font_size_override("font_size", 6)
		row.add_theme_color_override("font_color", Palette.ACCENT_WARN if locked else Palette.TEXT_MAIN)
		row.add_theme_stylebox_override("normal", Palette.task_item_style())
		row.add_theme_stylebox_override("hover", Palette.task_item_style())
		row.add_theme_stylebox_override("pressed", Palette.task_item_style())
		row.gui_input.connect(_on_row_gui_input.bind(file))
		list.add_child(row)


func _on_row_gui_input(event: InputEvent, file: FileData) -> void:
	if event is InputEventMouseButton and event.pressed and event.double_click:
		_open_file(file)


func _open_file(file: FileData) -> void:
	file_opened.emit(file)
	if not window_manager:
		return
	# หมายเหตุ: DevCrack puzzle logic (unpack/repack/validation) ถูกถอดสายไว้ชั่วคราว
	# ไฟล์ DevCrackApp.tscn / devcrack_app.gd ยังอยู่ในโปรเจกต์เหมือนเดิม แค่ยังไม่ถูกเรียกใช้
	# เมื่อพร้อมทำเฟสปริศนา ให้เปลี่ยนโค้ดส่วนนี้กลับไปเป็นแบบเดิม
	var content: NoteViewer = NOTE_VIEWER_SCENE.instantiate()
	window_manager.open_window(content, "%s.%s" % [file.filename, file.extension], Rect2(60, 20, 180, 140))
	if file.extension == "mos":
		content.show_plain("[devcrack.exe — ยังไม่เปิดใช้งานในบิลด์นี้]")
	else:
		content.show_plain(file.content)
