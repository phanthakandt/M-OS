class_name TaskManagerApp
extends Control

const CONTEXT_MENU_SCENE := preload("res://scenes/ui/ContextMenu.tscn")

## Pure flavor rows simulating background OS activity — not backed by any
## real window/state. They render and behave exactly like real app rows
## (same row builder, same right-click menu) so they can't be told apart at
## a glance, but always pass killable = false (see _rebuild_list/
## _add_process_row), which is what disables their "Kill process" item
## instead of hiding the menu entirely. Fixed order is fine since these never
## reshuffle on their own; only where real app/ghost rows get interleaved
## among them shifts, as the open-window list or ghost-process list changes.
## The last several entries are hidden = true — same "no advance hints" rule
## as everywhere else, they just read as background noise until the player
## notices they only show up with "show hidden" on.
const SYSTEM_PROCESSES: Array[Dictionary] = [
	{"name": "mos_kernel", "hidden": false}, {"name": "mos_shell", "hidden": false},
	{"name": "compositor.sys", "hidden": false}, {"name": "inputmgr.sys", "hidden": false},
	{"name": "audio.svc", "hidden": false}, {"name": "netstack.sys", "hidden": false},
	{"name": "diskio.sys", "hidden": false}, {"name": "clock.svc", "hidden": false},
	{"name": "eventlog.svc", "hidden": false}, {"name": "sessionmgr.sys", "hidden": false},
	{"name": "authd", "hidden": false}, {"name": "cryptsvc", "hidden": false},
	{"name": "spooler.svc", "hidden": false}, {"name": "registry.sys", "hidden": false},
	{"name": "power.sys", "hidden": false}, {"name": "thermal.sys", "hidden": false},
	{"name": "update_agent", "hidden": false}, {"name": "telemetry.svc", "hidden": false},
	{"name": "watchdog.sys", "hidden": false}, {"name": "gpu_compositor", "hidden": false},
	{"name": "unlisted_user.sys", "hidden": true}, {"name": "null_shell.daemon", "hidden": true},
	{"name": "watcher_037.sys", "hidden": true}, {"name": "no_owner.pid", "hidden": true},
	{"name": "kernel_whisper.daemon", "hidden": true},
]

var window_manager: WindowManager
var self_window_id: String = ""
var _show_hidden: bool = false
var _context_target_id: String = ""
var _context_target_kind: String = ""

@onready var header_label: Label = $VBox/HeaderBar/HeaderLabel
@onready var hidden_toggle_button: Button = $VBox/HeaderBar/HiddenToggleButton
@onready var scroll: ScrollContainer = $VBox/Scroll
@onready var list: VBoxContainer = $VBox/Scroll/List
@onready var _context_menu: ContextMenu = CONTEXT_MENU_SCENE.instantiate()


func _ready() -> void:
	header_label.add_theme_font_override("font", Palette.font_chrome)
	header_label.add_theme_font_size_override("font_size", 4)
	header_label.add_theme_color_override("font_color", Palette.TEXT_DIM)

	hidden_toggle_button.focus_mode = Control.FOCUS_NONE
	hidden_toggle_button.add_theme_font_override("font", Palette.font_body)
	hidden_toggle_button.add_theme_font_size_override("font_size", 5)
	hidden_toggle_button.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	hidden_toggle_button.add_theme_stylebox_override("normal", Palette.task_item_style())
	hidden_toggle_button.add_theme_stylebox_override("hover", Palette.task_item_style())
	hidden_toggle_button.add_theme_stylebox_override("pressed", Palette.task_item_style())
	hidden_toggle_button.add_theme_stylebox_override("hover_pressed", Palette.task_item_style())
	hidden_toggle_button.toggled.connect(_on_hidden_toggled)
	_update_hidden_toggle_text(hidden_toggle_button.button_pressed)

	Palette.style_scrollbar(scroll)

	if window_manager:
		window_manager.window_opened.connect(_on_window_list_changed)
		window_manager.window_closed.connect(_on_window_list_changed)

	GameState.ghost_processes_changed.connect(_rebuild_list)

	add_child(_context_menu)
	_context_menu.item_selected.connect(_on_context_item_selected)

	_rebuild_list()


func _on_window_list_changed(_window_id: String, _title: String = "") -> void:
	_rebuild_list()


func _on_hidden_toggled(pressed: bool) -> void:
	_show_hidden = pressed
	_update_hidden_toggle_text(pressed)
	_rebuild_list()


func _update_hidden_toggle_text(pressed: bool) -> void:
	hidden_toggle_button.text = "[x] show hidden" if pressed else "[ ] show hidden"


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

	# Background pool: fixed system rows plus live ghost processes
	# (GameState.get_ghost_processes()), both filtered by _show_hidden first.
	# Spread the real app rows evenly among that pool instead of clumping
	# them at the top, so they read as mixed in with background activity
	# rather than a separate "apps" section — same interleave formula as
	# before, just fed from a bigger pool now.
	var rows: Array = []
	for process in SYSTEM_PROCESSES:
		if process.hidden and not _show_hidden:
			continue
		rows.append({"kind": "system", "id": "", "title": process.name, "killable": false})
	for ghost in GameState.get_ghost_processes():
		if ghost.hidden and not _show_hidden:
			continue
		rows.append({"kind": "ghost", "id": ghost.id, "title": ghost.name, "killable": ghost.killable})
	var pool_count := rows.size()
	for i in app_entries.size():
		var pos: int = int(round(float(i + 1) * pool_count / float(app_entries.size() + 1)))
		rows.insert(clamp(pos + i, 0, rows.size()), {"kind": "window", "id": app_entries[i].id, "title": app_entries[i].title, "killable": true})

	for row_data in rows:
		_add_process_row(row_data.id, row_data.kind, row_data.title, row_data.killable)


## kind is "system" (fixed flavor row), "window" (a real open app window), or
## "ghost" (a GameState-tracked ghost process — see
## GameState.kill_ghost_process()). All three render and right-click
## identically; killable is what actually disables "Kill process" (see
## _on_row_gui_input) — a system row is always killable = false the same as
## before, but that's no longer inferred from an empty id, since a ghost row
## can also be unkillable despite having a real one.
func _add_process_row(id: String, kind: String, title: String, killable: bool) -> void:
	# PanelContainer has no built-in hover state (unlike Button), so the box
	# is toggled by hand: invisible at rest, task_item_style only while the
	# mouse is over the row. The rest style reserves the same border/margin
	# as task_item_style (just transparent) so toggling never resizes the
	# row — a plain StyleBoxEmpty here would make the whole list jump on hover.
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", Palette.task_item_style_invisible())
	row.gui_input.connect(_on_row_gui_input.bind(id, kind, killable))
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


func _on_row_gui_input(event: InputEvent, id: String, kind: String, killable: bool) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		if kind == "window":
			window_manager.reveal_window(id)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_context_target_id = id
		_context_target_kind = kind
		_context_menu.open_at(get_global_mouse_position(), [
			{"label": "Kill process", "action": "kill", "disabled": not killable},
		])


## "system" rows never reach here with a live "kill" action (their menu item
## is disabled), but the branch is kept as a no-op guard rather than assumed
## unreachable. "ghost" routes through GameState.kill_ghost_process(), which
## owns the lived.process -> ssecorp.devil cascade itself — nothing extra to
## do here beyond calling it.
func _on_context_item_selected(action: String) -> void:
	if action != "kill":
		return
	match _context_target_kind:
		"window":
			window_manager.close_window(_context_target_id)
		"ghost":
			GameState.kill_ghost_process(_context_target_id)
