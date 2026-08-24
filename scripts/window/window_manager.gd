class_name WindowManager
extends Node

signal window_opened(window_id: String, title: String)
signal window_closed(window_id: String)
signal window_focus_changed(window_id: String)

const WINDOW_SCENE := preload("res://scenes/window/Window.tscn")

var window_layer: Control
var work_area: Rect2 = Rect2()
var _windows: Dictionary = {}
var _next_id: int = 0
var _active_id: String = ""


func open_window(content: Control, title: String, rect: Rect2) -> AppWindow:
	_next_id += 1
	var id := "win_%d" % _next_id
	var win: AppWindow = WINDOW_SCENE.instantiate()
	window_layer.add_child(win)
	win.setup(title, id)
	win.work_area = work_area
	win.position = rect.position
	win.size = rect.size
	win.closed.connect(_on_window_closed)
	win.get_content_slot().add_child(content)
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_windows[id] = win
	window_opened.emit(id, title)
	_focus(id)
	return win


func focus_window(window_id: String) -> void:
	if not _windows.has(window_id):
		return
	var win: AppWindow = _windows[window_id]
	if win.visible and _active_id == window_id:
		win.hide()
		return
	win.show()
	_focus(window_id)


## Shows and focuses a window without the toggle-minimize branch of
## focus_window(). Use this for "open/bring to front" actions (desktop
## icons, start menu, reopening an already-open file) — focus_window is
## reserved for the taskbar button's intentional toggle-minimize behavior.
func reveal_window(window_id: String) -> void:
	if not _windows.has(window_id):
		return
	_windows[window_id].show()
	_focus(window_id)


func get_open_windows() -> Array:
	var result: Array = []
	for id in _windows:
		var win: AppWindow = _windows[id]
		result.append({"id": id, "title": win.window_title, "visible": win.visible})
	return result


## Closes a window the same way its own close button does — emits closed()
## then frees it — so callers other than the titlebar (e.g. a task manager)
## can terminate a window through the same path.
func close_window(window_id: String) -> void:
	if not _windows.has(window_id):
		return
	var win: AppWindow = _windows[window_id]
	win.closed.emit(window_id)
	win.queue_free()


func _on_window_closed(window_id: String) -> void:
	_windows.erase(window_id)
	if _active_id == window_id:
		_active_id = ""
		_focus_topmost_visible()
	window_closed.emit(window_id)


## Closing the active window otherwise leaves nothing focused until the
## player clicks something themselves — bring the next topmost *visible*
## window forward instead (skip minimized ones). Topmost = last child of
## window_layer, same convention _focus() itself uses when raising a
## window; _windows.has(...) guards against the just-closed window's node,
## which is still in the tree (queue_free is deferred) but already erased
## from _windows above.
func _focus_topmost_visible() -> void:
	var children := window_layer.get_children()
	for i in range(children.size() - 1, -1, -1):
		var win: AppWindow = children[i]
		if win.visible and _windows.has(win.window_id):
			_focus(win.window_id)
			return


## Real-OS-style click-to-focus: a click anywhere on a window (not just its
## titlebar) should raise it — but only the window actually drawn on top at
## that point, not any other window whose rect happens to also cover it.
## This has to be decided centrally, here, rather than by each AppWindow
## independently checking "does this click fall within my own rect": if two
## windows overlap and both perform that check, both would call to focus
## themselves for the same click, and whichever's _input() happened to run
## last (an ordering Godot doesn't guarantee matches visual stacking) would
## win — occasionally focusing the window *behind* the one actually clicked.
## Iterating window_layer's children topmost-first (same "last child =
## topmost" convention _focus_topmost_visible() uses) and stopping at the
## first match guarantees the visually topmost window under the cursor is
## always the one that wins, matching how a real desktop OS resolves this.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var children := window_layer.get_children()
	for i in range(children.size() - 1, -1, -1):
		var win: AppWindow = children[i]
		if win.visible and Rect2(win.global_position, win.size).has_point(event.global_position):
			_focus(win.window_id)
			return


func _focus(window_id: String) -> void:
	if not _windows.has(window_id):
		return
	if _active_id != window_id and _windows.has(_active_id):
		_windows[_active_id].set_active(false)
	_active_id = window_id
	window_layer.move_child(_windows[window_id], window_layer.get_child_count() - 1)
	_windows[window_id].set_active(true)
	window_focus_changed.emit(window_id)
