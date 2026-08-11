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
	win.focused.connect(_on_window_focused)
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
	window_closed.emit(window_id)


func _on_window_focused(window_id: String) -> void:
	_focus(window_id)


func _focus(window_id: String) -> void:
	if not _windows.has(window_id):
		return
	if _active_id != window_id and _windows.has(_active_id):
		_windows[_active_id].set_active(false)
	_active_id = window_id
	window_layer.move_child(_windows[window_id], window_layer.get_child_count() - 1)
	_windows[window_id].set_active(true)
	window_focus_changed.emit(window_id)
