class_name KikuChatApp
extends Control

## Password-unlock puzzle, entirely separate from the DevCrack/blob lock
## system (see GameState.get_lock_reason()). ChatThreadData never extends
## FileData and is never touched by anything blob-related — a thread's
## requires_code flag is checked directly against
## GameState.is_app_unlocked_by_code(APP_ID) instead.
const APP_ID := "kikuchat"

const CHAT_LIST := preload("res://data/kikuchat/chat_list.tres")
const PASSWORD_DIALOG_SCENE := preload("res://scenes/ui/PasswordDialog.tscn")

## Message bubbles wrap at this fixed width rather than shrinking to fit
## their own content with a max cap — Godot's container sizing doesn't give
## a reliable "shrink but cap" for autowrapped Labels at this scale, so
## every bubble uses the same wrap width instead, growing vertically for
## longer text.
const BUBBLE_WIDTH := 70.0

var window_manager: WindowManager
var warning_dialog: WarningDialog

## The thread waiting on a correct password before it can be shown (see
## _select_thread/_on_password_submitted). Cleared on both submit and cancel.
var _pending_thread: ChatThreadData

## Whichever thread is currently rendered in the chat pane (null before the
## player has picked one) — drives both message rendering and which
## contacts-list row is highlighted.
var _selected_thread: ChatThreadData

var _password_dialog: PasswordDialog

@onready var sidebar_header: Label = $HBox/Sidebar/SidebarHeader
@onready var contacts_scroll: ScrollContainer = $HBox/Sidebar/ContactsScroll
@onready var contacts_list: VBoxContainer = $HBox/Sidebar/ContactsScroll/ContactsList
@onready var divider: ColorRect = $HBox/Divider
@onready var chat_header: Label = $HBox/ChatPane/ChatBody/ChatHeader
@onready var messages_scroll: ScrollContainer = $HBox/ChatPane/ChatBody/MessagesScroll
@onready var messages_list: VBoxContainer = $HBox/ChatPane/ChatBody/MessagesScroll/MessagesMargin/MessagesList
@onready var input_field: LineEdit = $HBox/ChatPane/ChatBody/InputField


func _ready() -> void:
	# A dedicated node instead of a border on Sidebar's own stylebox — a
	# selected/hovered row's opaque background is a descendant of Sidebar
	# and would otherwise be drawn on top of (and hide) a border baked into
	# Sidebar's own panel. As a later sibling in HBox, this always renders
	# after — on top of — everything inside Sidebar, so it stays visible
	# even across the active row.
	divider.color = Palette.BORDER

	sidebar_header.add_theme_font_override("font", Palette.font_body)
	sidebar_header.add_theme_font_size_override("font_size", 5)
	sidebar_header.add_theme_color_override("font_color", Palette.TEXT_DIM)

	chat_header.add_theme_font_override("font", Palette.font_chrome)
	chat_header.add_theme_font_size_override("font_size", 4)
	chat_header.add_theme_color_override("font_color", Palette.TEXT_MAIN)

	# Permanently editable = false — this app is read-only end to end (see
	# the class-level note above), and this box makes that explicit rather
	# than just absent: the player can see where a reply would go and that
	# it doesn't work, instead of there being no input at all.
	input_field.focus_mode = Control.FOCUS_NONE
	input_field.add_theme_font_override("font", Palette.font_body)
	input_field.add_theme_font_size_override("font_size", 5)
	input_field.add_theme_color_override("font_uneditable_color", Palette.TEXT_FAINT)
	input_field.add_theme_stylebox_override("read_only", Palette.task_item_style())

	_style_scrollbar(contacts_scroll)
	_style_scrollbar(messages_scroll)

	_password_dialog = PASSWORD_DIALOG_SCENE.instantiate()
	add_child(_password_dialog)

	_rebuild_sidebar()
	_render_chat_pane()


## Same thin/reskinned scrollbar as TaskManagerApp — the engine's default
## width reads oversized against this app's tiny fonts/rows too.
func _style_scrollbar(scroll: ScrollContainer) -> void:
	var vscroll := scroll.get_v_scroll_bar()
	vscroll.custom_minimum_size = Vector2(3, 0)
	vscroll.add_theme_stylebox_override("scroll", Palette.make_flat_style(Palette.WINDOW_BG, Palette.BORDER, 0))
	vscroll.add_theme_stylebox_override("grabber", Palette.make_flat_style(Palette.BORDER_LIGHT, Palette.BORDER_LIGHT, 0))
	vscroll.add_theme_stylebox_override("grabber_highlight", Palette.make_flat_style(Palette.TEXT_DIM, Palette.TEXT_DIM, 0))
	vscroll.add_theme_stylebox_override("grabber_pressed", Palette.make_flat_style(Palette.TEXT_MAIN, Palette.TEXT_MAIN, 0))


func _rebuild_sidebar() -> void:
	for c in contacts_list.get_children():
		c.queue_free()

	for thread in CHAT_LIST.threads:
		_add_contact_row(thread)


## No visual hint of requires_code here — same "no advance hints" rule
## FilesApp follows for its own locked files.
func _add_contact_row(thread: ChatThreadData) -> void:
	var selected := thread == _selected_thread

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", Palette.chat_contact_row_style(selected))
	row.gui_input.connect(_on_contact_row_gui_input.bind(thread))
	row.mouse_entered.connect(func() -> void:
		if thread != _selected_thread:
			row.add_theme_stylebox_override("panel", Palette.chat_contact_row_style(false, true))
	)
	row.mouse_exited.connect(func() -> void:
		if thread != _selected_thread:
			row.add_theme_stylebox_override("panel", Palette.chat_contact_row_style(false, false))
	)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	row.add_child(hbox)

	# size_flags_horizontal/vertical = SIZE_SHRINK_CENTER pins this to
	# exactly custom_minimum_size regardless of content — a plain SIZE_FILL
	# (the default) still lets a Panel's rect grow past its minimum if
	# there's slack in the row, which read as "sized to content" since
	# different rows' text_box heights differ.
	var avatar := Panel.new()
	avatar.custom_minimum_size = Vector2(9, 9)
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.add_theme_stylebox_override("panel", Palette.icon_glyph_style())
	hbox.add_child(avatar)

	var avatar_label := Label.new()
	avatar_label.text = thread.contact_name.substr(0, 1)
	avatar_label.clip_text = true
	avatar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar_label.add_theme_font_override("font", Palette.font_body)
	avatar_label.add_theme_font_size_override("font_size", 4)
	avatar_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	avatar.add_child(avatar_label)
	avatar_label.set_anchors_preset(Control.PRESET_FULL_RECT)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_theme_constant_override("separation", 0)
	hbox.add_child(text_box)

	var name_label := Label.new()
	name_label.text = thread.contact_name
	name_label.clip_text = true
	name_label.add_theme_font_override("font", Palette.font_body)
	name_label.add_theme_font_size_override("font_size", 5)
	name_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	text_box.add_child(name_label)

	var preview_label := Label.new()
	preview_label.text = thread.last_message_preview
	preview_label.clip_text = true
	preview_label.add_theme_font_override("font", Palette.font_body)
	preview_label.add_theme_font_size_override("font_size", 4)
	preview_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	text_box.add_child(preview_label)

	contacts_list.add_child(row)


func _on_contact_row_gui_input(event: InputEvent, thread: ChatThreadData) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_thread(thread)


func _select_thread(thread: ChatThreadData) -> void:
	if thread.requires_code and not GameState.is_app_unlocked_by_code(APP_ID):
		_pending_thread = thread
		_connect_password_dialog_once()
		_password_dialog.ask("กรุณาใส่รหัสผ่านเพื่อเข้าดูบทสนทนานี้")
		return

	_selected_thread = thread
	_rebuild_sidebar()
	_render_chat_pane()


## _password_dialog is one instance reused across every locked thread this
## app opens, so guard against double-connecting the same signal twice —
## same pattern Desktop._confirm_shutdown uses for its shared ConfirmDialog.
func _connect_password_dialog_once() -> void:
	if not _password_dialog.submitted.is_connected(_on_password_submitted):
		_password_dialog.submitted.connect(_on_password_submitted, CONNECT_ONE_SHOT)
	if not _password_dialog.cancelled.is_connected(_on_password_cancelled):
		_password_dialog.cancelled.connect(_on_password_cancelled, CONNECT_ONE_SHOT)


func _on_password_submitted(text: String) -> void:
	var thread := _pending_thread
	_pending_thread = null

	if text.strip_edges() == CHAT_LIST.access_code:
		GameState.unlock_app_with_code(APP_ID)
		_selected_thread = thread
		_rebuild_sidebar()
		_render_chat_pane()
	elif warning_dialog:
		warning_dialog.show_message("รหัสผ่านไม่ถูกต้อง")


func _on_password_cancelled() -> void:
	_pending_thread = null


func _render_chat_pane() -> void:
	for c in messages_list.get_children():
		c.queue_free()

	if not _selected_thread:
		chat_header.text = ""
		var placeholder := Label.new()
		placeholder.text = "เลือกรายชื่อผู้ติดต่อเพื่อดูข้อความ"
		placeholder.add_theme_font_override("font", Palette.font_body)
		placeholder.add_theme_font_size_override("font_size", 5)
		placeholder.add_theme_color_override("font_color", Palette.TEXT_FAINT)
		messages_list.add_child(placeholder)
		return

	chat_header.text = _selected_thread.contact_name
	var previous_date := ""
	var is_first_message := true
	for message in _selected_thread.messages:
		if is_first_message or message.date != previous_date:
			_add_date_divider(message.date)
			previous_date = message.date
			is_first_message = false
		_add_message_bubble(message)

	_scroll_to_latest_message()


## Opening/switching a thread should land on its most recent message, like
## any real chat app, not leave the view sitting at the oldest one.
## MessagesScroll's scrollable range isn't valid until the ScrollContainer
## has processed the new bubbles' layout — and on this pane's very first
## render that can take more than a single frame (minimum-size propagation
## through MessagesMargin -> MessagesList -> each bubble's autowrapped Label
## settles gradually, unlike later re-renders where most of that sizing is
## already warm), so a single `await process_frame` scrolled to a still-too-
## small max_value and landed short of the bottom. Instead this reapplies
## scroll_vertical every frame until max_value stops changing (or a small
## frame cap is hit, so a layout that never settles can't loop forever).
func _scroll_to_latest_message() -> void:
	var vscroll := messages_scroll.get_v_scroll_bar()
	var previous_max := -1.0
	for _i in 5:
		await get_tree().process_frame
		messages_scroll.scroll_vertical = int(vscroll.max_value)
		if vscroll.max_value == previous_max:
			break
		previous_max = vscroll.max_value


## Full-width "— 19 สิงหาคม 2569 —" separator row, inserted whenever a
## message's date differs from the previous message's (or for the thread's
## very first message) — see _render_chat_pane(). This is its own row, not a
## bubble: it must stay out of _add_message_bubble's spacer-based left/right
## alignment trick below, which only makes sense for sender-aligned bubbles.
func _add_date_divider(date_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var left_line := ColorRect.new()
	left_line.color = Palette.BORDER
	left_line.custom_minimum_size = Vector2(0, 1)
	left_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(left_line)

	var date_label := Label.new()
	date_label.text = date_text
	date_label.add_theme_font_override("font", Palette.font_body)
	date_label.add_theme_font_size_override("font_size", 4)
	date_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	row.add_child(date_label)

	var right_line := ColorRect.new()
	right_line.color = Palette.BORDER
	right_line.custom_minimum_size = Vector2(0, 1)
	right_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(right_line)

	messages_list.add_child(row)


func _add_message_bubble(message: ChatMessageData) -> void:
	var is_me := message.sender == "me"

	var bubble_box := VBoxContainer.new()
	bubble_box.add_theme_constant_override("separation", 1)

	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", Palette.chat_bubble_style(is_me))

	var text_label := Label.new()
	text_label.text = message.text
	text_label.custom_minimum_size = Vector2(BUBBLE_WIDTH, 0)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	text_label.add_theme_font_override("font", Palette.font_body)
	text_label.add_theme_font_size_override("font_size", 5)
	text_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	bubble.add_child(text_label)
	bubble_box.add_child(bubble)

	var timestamp_label := Label.new()
	timestamp_label.text = message.timestamp
	timestamp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if is_me else HORIZONTAL_ALIGNMENT_LEFT
	timestamp_label.add_theme_font_override("font", Palette.font_body)
	timestamp_label.add_theme_font_size_override("font_size", 4)
	timestamp_label.add_theme_color_override("font_color", Palette.TEXT_FAINT)
	bubble_box.add_child(timestamp_label)

	# Pushes the bubble to whichever side matches its sender — the spacer
	# takes all remaining width, so the bubble never stretches past its own
	# content/wrap width.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	if is_me:
		row.add_child(spacer)
		row.add_child(bubble_box)
	else:
		row.add_child(bubble_box)
		row.add_child(spacer)

	messages_list.add_child(row)
