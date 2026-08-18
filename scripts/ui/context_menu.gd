class_name ContextMenu
extends Control

signal item_selected(action: String)

const MIN_ITEM_WIDTH := 56.0

@onready var catcher: Control = $Catcher
@onready var panel: PanelContainer = $Panel
@onready var vbox: VBoxContainer = $Panel/Margin/VBox


func _ready() -> void:
	panel.add_theme_stylebox_override("panel", Palette.window_style())
	catcher.gui_input.connect(_on_catcher_gui_input)


## items: Array of {"label": String, "action": String, "disabled": bool}.
## "disabled" is optional (defaults false) — a disabled item renders at half
## opacity and never fires item_selected, same modulate.a = 0.5 convention
## DevCrackApp uses for its own disabled archive entries. global_pos is
## clamped so the menu never renders outside this control's own rect.
func open_at(global_pos: Vector2, items: Array) -> void:
	# free(), not queue_free(): the old buttons must be gone *before*
	# reset_size() below, or their still-alive minimum size gets counted
	# too and the panel ends up taller than the new item count.
	for c in vbox.get_children():
		c.free()

	for item in items:
		var btn := Button.new()
		btn.text = item.label
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(MIN_ITEM_WIDTH, 0)
		btn.add_theme_font_override("font", Palette.font_body)
		btn.add_theme_font_size_override("font_size", 5)
		btn.add_theme_color_override("font_color", Palette.TEXT_MAIN)
		btn.add_theme_stylebox_override("normal", Palette.task_item_style())
		btn.add_theme_stylebox_override("hover", Palette.task_item_style())
		btn.add_theme_stylebox_override("pressed", Palette.task_item_style())
		btn.add_theme_stylebox_override("disabled", Palette.task_item_style())
		if item.get("disabled", false):
			btn.disabled = true
			btn.modulate.a = 0.5
		else:
			btn.pressed.connect(_on_item_pressed.bind(item.action as String))
		vbox.add_child(btn)

	catcher.visible = true
	panel.visible = true
	panel.reset_size()

	var local_pos: Vector2 = global_pos - global_position
	local_pos.x = clamp(local_pos.x, 0.0, max(0.0, size.x - panel.size.x))
	local_pos.y = clamp(local_pos.y, 0.0, max(0.0, size.y - panel.size.y))
	panel.position = local_pos


func _close() -> void:
	catcher.visible = false
	panel.visible = false


func _on_catcher_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()


func _on_item_pressed(action: String) -> void:
	_close()
	item_selected.emit(action)
