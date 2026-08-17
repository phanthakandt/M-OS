class_name TaskManagerApp
extends Control

const CONTEXT_MENU_SCENE := preload("res://scenes/ui/ContextMenu.tscn")

## Pure flavor rows simulating background OS activity — not backed by any
## real window/state. They render and behave exactly like real app rows
## (same row builder, same right-click menu) so they can't be told apart at
## a glance, but pass window_id = "" (see _add_process_row), which is the
## sentinel _on_row_gui_input/_rebuild_list use to disable their
## "Kill process" item instead of hiding the menu entirely. Fixed order is
## fine since these never reshuffle on their own; only where real app rows
## get interleaved among them shifts, as the open-window list changes.
const SYSTEM_PROCESSES: Array[String] = [
	"mos_kernel", "mos_shell", "compositor.sys", "inputmgr.sys", "audio.svc",
	"netstack.sys", "diskio.sys", "clock.svc", "eventlog.svc", "sessionmgr.sys",
	"authd", "cryptsvc", "spooler.svc", "registry.sys", "power.sys",
	"thermal.sys", "update_agent", "telemetry.svc", "watchdog.sys", "gpu_compositor",
]

var window_manager: WindowManager
var self_window_id: String = ""
var _context_target_window_id: String = ""

@onready var header_label: Label = $VBox/HeaderLabel
@onready var scroll: ScrollContainer = $VBox/Scroll
@onready var list: VBoxContainer = $VBox/Scroll/List
@onready var _context_menu: ContextMenu = CONTEXT_MENU_SCENE.instantiate()


func _ready() -> void:
	header_label.add_theme_font_override("font", Palette.font_chrome)
	header_label.add_theme_font_size_override("font_size", 4)
	header_label.add_theme_color_override("font_color", Palette.TEXT_DIM)

	# The engine's default VScrollBar width is sized for a normal-DPI UI, not
	# this 384x216-space pixel UI — left alone it reads as oversized next to
	# the tiny font/rows, so it's thinned and reskinned with flat Palette
	# styles to match everything else here (see task_item_style() callers).
	var vscroll := scroll.get_v_scroll_bar()
	vscroll.custom_minimum_size = Vector2(3, 0)
	vscroll.add_theme_stylebox_override("scroll", Palette.make_flat_style(Palette.WINDOW_BG, Palette.BORDER, 0))
	vscroll.add_theme_stylebox_override("grabber", Palette.make_flat_style(Palette.BORDER_LIGHT, Palette.BORDER_LIGHT, 0))
	vscroll.add_theme_stylebox_override("grabber_highlight", Palette.make_flat_style(Palette.TEXT_DIM, Palette.TEXT_DIM, 0))
	vscroll.add_theme_stylebox_override("grabber_pressed", Palette.make_flat_style(Palette.TEXT_MAIN, Palette.TEXT_MAIN, 0))

	if window_manager:
		window_manager.window_opened.connect(_on_window_list_changed)
		window_manager.window_closed.connect(_on_window_list_changed)

	add_child(_context_menu)
	_context_menu.item_selected.connect(_on_context_item_selected)

	_rebuild_list()


func _on_window_list_changed(_window_id: String, _title: String = "") -> void:
	_rebuild_list()


## Called by whoever opened this window once self_window_id is set, so the
## initial list excludes this task manager's own row.
func refresh_list() -> void:
	_rebuild_list()


func _rebuild_list() -> void:
	for c in list.get_children():
		c.queue_free()

	var app_entries: Array = []
	if window_manager:
		for entry in window_manager.get_open_windows():
			if entry.id == self_window_id:
				continue
			app_entries.append(entry)

	# Spread the real app rows evenly among the fixed system rows instead of
	# clumping them at the top, so they read as mixed in with background
	# activity rather than a separate "apps" section.
	var rows: Array = []
	for process_name in SYSTEM_PROCESSES:
		rows.append({"app": false, "title": process_name})
	var system_count := rows.size()
	for i in app_entries.size():
		var pos: int = int(round(float(i + 1) * system_count / float(app_entries.size() + 1)))
		rows.insert(clamp(pos + i, 0, rows.size()), {"app": true, "id": app_entries[i].id, "title": app_entries[i].title})

	for row_data in rows:
		_add_process_row(row_data.id if row_data.app else "", row_data.title)


## window_id == "" marks a fake system row (see SYSTEM_PROCESSES) — it still
## renders and right-clicks identically to a real app row, just with its
## "Kill process" item disabled (see _on_row_gui_input), so it can't be told
## apart from a real one without trying to kill it.
func _add_process_row(window_id: String, title: String) -> void:
	# PanelContainer has no built-in hover state (unlike Button), so the box
	# is toggled by hand: invisible at rest, task_item_style only while the
	# mouse is over the row. The rest style reserves the same border/margin
	# as task_item_style (just transparent) so toggling never resizes the
	# row — a plain StyleBoxEmpty here would make the whole list jump on hover.
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", Palette.task_item_style_invisible())
	row.gui_input.connect(_on_row_gui_input.bind(window_id))
	row.mouse_entered.connect(func(): row.add_theme_stylebox_override("panel", Palette.task_item_style()))
	row.mouse_exited.connect(func(): row.add_theme_stylebox_override("panel", Palette.task_item_style_invisible()))

	# task_item_style()'s own content margin (2, same on every side) is fine
	# for the row's left/top/bottom, but leaves "running..." reading as flush
	# against the row's right edge — this margin only pads the right further.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_right", 4)
	row.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 3)
	margin.add_child(hbox)

	var name_label := Label.new()
	name_label.text = title
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.add_theme_font_override("font", Palette.font_body)
	name_label.add_theme_font_size_override("font_size", 5)
	name_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	hbox.add_child(name_label)

	var status_label := Label.new()
	status_label.text = "running..."
	status_label.add_theme_font_override("font", Palette.font_body)
	status_label.add_theme_font_size_override("font_size", 5)
	status_label.add_theme_color_override("font_color", Palette.TEXT_FAINT)
	hbox.add_child(status_label)

	list.add_child(row)


func _on_row_gui_input(event: InputEvent, window_id: String) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		if window_id != "":
			window_manager.reveal_window(window_id)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_context_target_window_id = window_id
		_context_menu.open_at(get_global_mouse_position(), [
			{"label": "Kill process", "action": "kill", "disabled": window_id == ""},
		])


func _on_context_item_selected(action: String) -> void:
	if action == "kill" and _context_target_window_id != "":
		window_manager.close_window(_context_target_window_id)
