class_name SystemLogApp
extends Control

const LOG_LIST := preload("res://data/system_log/log.tres")

## Keeps the datetime column a consistent width so entries read as a table
## rather than each row's text landing at a different offset. Wide enough
## that "YYYY-MM-DD HH:MM:SS" never clips — the reference mockup never
## truncates a datetime either.
const DATETIME_WIDTH := 70.0

## Floor width for a row's message Label — see _add_log_row()'s comment on
## why HFlowContainer needs this instead of SIZE_EXPAND_FILL. Sized so the
## longest entries in log.tres still fit on one line at the window's default
## size, matching the reference mockup (which shows every row unwrapped);
## HFlowContainer still wraps it if the window is ever narrower than this.
const MESSAGE_MIN_WIDTH := 130.0

## Floor width for a row's actor Label. Without this, a clip_text Label's
## reported minimum size shrinks to near zero, which tricked HFlowContainer
## into squeezing it into whatever sliver of space was left on the crowded
## line instead of wrapping it to a fresh one — clipping almost the entire
## name away right at the row's edge instead of wrapping to a new line like
## it should. Sized for the longest actor string in log.tres ("· by
## nattapong.w").
const ACTOR_WIDTH := 65.0

@onready var header_label: Label = $VBox/HeaderLabel
@onready var scroll: ScrollContainer = $VBox/Scroll
@onready var list: VBoxContainer = $VBox/Scroll/List


func _ready() -> void:
	header_label.add_theme_font_override("font", Palette.font_chrome)
	header_label.add_theme_font_size_override("font_size", 4)
	header_label.add_theme_color_override("font_color", Palette.TEXT_DIM)

	_style_scrollbar(scroll)

	# LOG_LIST is static content only — nothing here is tied to GameState yet,
	# so there's no signal to subscribe for a live rebuild (unlike TrashApp's
	# GameState.trashed_changed.connect(_rebuild_list)). If this ever grows a
	# dynamic source (e.g. entries generated from GameState events), add the
	# equivalent signal subscription here too.
	_rebuild_list()


## Same thin/reskinned scrollbar as TaskManagerApp/KikuChatApp — copied
## directly rather than factored into a shared helper, out of scope here.
func _style_scrollbar(target: ScrollContainer) -> void:
	var vscroll := target.get_v_scroll_bar()
	vscroll.custom_minimum_size = Vector2(3, 0)
	vscroll.add_theme_stylebox_override("scroll", Palette.make_flat_style(Palette.WINDOW_BG, Palette.BORDER, 0))
	vscroll.add_theme_stylebox_override("grabber", Palette.make_flat_style(Palette.BORDER_LIGHT, Palette.BORDER_LIGHT, 0))
	vscroll.add_theme_stylebox_override("grabber_highlight", Palette.make_flat_style(Palette.TEXT_DIM, Palette.TEXT_DIM, 0))
	vscroll.add_theme_stylebox_override("grabber_pressed", Palette.make_flat_style(Palette.TEXT_MAIN, Palette.TEXT_MAIN, 0))


func _rebuild_list() -> void:
	for c in list.get_children():
		c.queue_free()

	for entry in LOG_LIST.entries:
		_add_log_row(entry)

	_scroll_to_latest_entry()


## One log line — not a clickable list row, so unlike task_item_style() rows
## elsewhere in the app there's no box/hover state at all, just plain text
## flowing like a real log file. HFlowContainer instead of HBoxContainer:
## at the window's default (small) size, or if the window ever gets resized
## narrower than a row's full content, HFlowContainer wraps whichever
## label(s) don't fit onto a new line instead of clipping/overlapping them —
## the same responsive behavior the reference mockup gets from CSS
## flex-wrap on each row.
func _add_log_row(entry: LogEntryData) -> void:
	var is_warn := entry.level == "WARN"

	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 1)

	var datetime_label := Label.new()
	datetime_label.text = entry.datetime
	datetime_label.clip_text = true
	datetime_label.custom_minimum_size = Vector2(DATETIME_WIDTH, 0)
	datetime_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	datetime_label.add_theme_font_override("font", Palette.font_body)
	datetime_label.add_theme_font_size_override("font_size", 4)
	datetime_label.add_theme_color_override("font_color", Palette.TEXT_FAINT)
	row.add_child(datetime_label)

	var level_box := PanelContainer.new()
	level_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level_box.add_theme_stylebox_override("panel", _log_level_style(entry.level))
	row.add_child(level_box)

	var level_label := Label.new()
	level_label.text = entry.level
	level_label.add_theme_font_override("font", Palette.font_body)
	level_label.add_theme_font_size_override("font_size", 4)
	level_label.add_theme_color_override("font_color", Palette.ACCENT_WARN if is_warn else Palette.TEXT_DIM)
	level_box.add_child(level_label)

	var message_label := Label.new()
	message_label.text = entry.message
	# FlowContainer doesn't stretch children to fill a line's leftover width
	# the way BoxContainer's EXPAND flag does — without a fixed floor here, an
	# autowrapped Label's minimum width shrinks to just its longest single
	# word, which read as far too narrow/tall. MESSAGE_MIN_WIDTH gives it a
	# stable wrap width instead, same idea as KikuChatApp's BUBBLE_WIDTH.
	message_label.custom_minimum_size = Vector2(MESSAGE_MIN_WIDTH, 0)
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	message_label.add_theme_font_override("font", Palette.font_body)
	message_label.add_theme_font_size_override("font_size", 5)
	message_label.add_theme_color_override("font_color", Palette.TEXT_MAIN if is_warn else Palette.TEXT_DIM)
	row.add_child(message_label)

	if entry.actor != "":
		var actor_label := Label.new()
		actor_label.text = "· by %s" % entry.actor
		actor_label.clip_text = true
		actor_label.custom_minimum_size = Vector2(ACTOR_WIDTH, 0)
		actor_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		actor_label.add_theme_font_override("font", Palette.font_body)
		actor_label.add_theme_font_size_override("font_size", 4)
		actor_label.add_theme_color_override("font_color", Palette.TEXT_FAINT)
		row.add_child(actor_label)

	list.add_child(row)


## Border-only box around the level tag (no solid fill, unlike
## task_item_style()'s boxed rows elsewhere) — BORDER for INFO, ACCENT_WARN
## for WARN, so an anomaly's tag reads as visually distinct from routine
## lines even before the message text itself is read. Built by hand rather
## than through make_flat_style()'s uniform-margin signature, since matching
## the reference mockup's tight "padding: 0 3px" tag needs horizontal-only
## content margin — same "one-off asymmetric StyleBoxFlat, colors still only
## from Palette" precedent as Desktop's start-menu shutdown row.
func _log_level_style(level: String) -> StyleBoxFlat:
	var border_color := Palette.ACCENT_WARN if level == "WARN" else Palette.BORDER
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.TRANSPARENT
	style.set_border_width_all(1)
	style.border_color = border_color
	style.set_corner_radius_all(0)
	style.content_margin_left = 3
	style.content_margin_right = 3
	return style


## Opening the log should land on its most recent entry, the same reasoning
## as KikuChatApp._scroll_to_latest_message(): ScrollContainer's scrollable
## range isn't valid until this frame's new rows have been laid out, and
## settling that layout can take more than one frame — so this reapplies
## scroll_vertical every frame until max_value stops changing (capped at 5
## frames so a layout that never settles can't loop forever).
func _scroll_to_latest_entry() -> void:
	var vscroll := scroll.get_v_scroll_bar()
	var previous_max := -1.0
	for _i in 5:
		await get_tree().process_frame
		scroll.scroll_vertical = int(vscroll.max_value)
		if vscroll.max_value == previous_max:
			break
		previous_max = vscroll.max_value
