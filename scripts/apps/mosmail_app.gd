class_name MosMailApp
extends Control

## Password-unlock puzzle, entirely separate from the DevCrack/blob lock
## system (see GameState.get_lock_reason()). EmailData never extends
## FileData and is never touched by anything blob-related — an email's
## requires_code flag is checked directly against
## GameState.is_app_unlocked_by_code(APP_ID) instead, same pattern
## KikuChatApp already established (and the same GameState methods, just a
## different app_id — GameState needed no changes to support this app).
const APP_ID := "mosmail"

const MAIL_LIST := preload("res://data/mosmail/inbox.tres")
const PASSWORD_DIALOG_SCENE := preload("res://scenes/ui/PasswordDialog.tscn")
const CONTEXT_MENU_SCENE := preload("res://scenes/ui/ContextMenu.tscn")
const NOTE_VIEWER_SCENE := preload("res://scenes/apps/NoteViewer.tscn")

const TABS := ["inbox", "spam", "trash"]

## Fixed sender/datetime column widths, same idea as SystemLogApp's
## DATETIME_WIDTH — keeps rows lined up like a table instead of each one's
## text landing at a different offset.
const SENDER_WIDTH := 55.0
const DATETIME_WIDTH := 48.0

var window_manager: WindowManager
var warning_dialog: WarningDialog

## "inbox"/"spam"/"trash" — plain UI state, not player progress, so it lives
## here rather than GameState (reset_progress() doesn't touch it, same as
## FilesApp's _history/_show_hidden).
var _current_tab: String = "inbox"

## The email waiting on a correct password before it can be shown (see
## _open_email()/_on_password_submitted()). Cleared on both submit and cancel.
var _pending_email: EmailData

## Whichever email is currently shown in the detail pane — null while in
## list state.
var _selected_email: EmailData

## Whichever row's context menu is currently open — same single-target
## convention DevCrackApp/TaskManagerApp use for their own single-kind rows.
var _context_target_email: EmailData

var _password_dialog: PasswordDialog
var _note_viewer: NoteViewer

@onready var search_field: LineEdit = $VBox/TopBarMargin/TopBar/SearchField
@onready var avatar_box: Panel = $VBox/TopBarMargin/TopBar/AvatarBox
@onready var avatar_label: Label = $VBox/TopBarMargin/TopBar/AvatarBox/AvatarLabel
@onready var top_bar_divider: ColorRect = $VBox/TopBarDivider
@onready var compose_button: Button = $VBox/Body/SidebarMargin/Sidebar/ComposeButton
@onready var tab_list: VBoxContainer = $VBox/Body/SidebarMargin/Sidebar/TabList
@onready var body_divider: ColorRect = $VBox/Body/BodyDivider
## _show_state() toggles this MarginContainer, not the ScrollContainer
## itself — ListScrollMargin is what actually carries size_flags_vertical = 3
## in MainArea's layout, so leaving it visible while its child is hidden
## still claims half of MainArea's height, squeezing DetailMargin into
## whatever's left (same reasoning as detail_margin below).
@onready var list_scroll_margin: MarginContainer = $VBox/Body/MainArea/ListScrollMargin
@onready var list_scroll: ScrollContainer = $VBox/Body/MainArea/ListScrollMargin/ListScroll
@onready var list: VBoxContainer = $VBox/Body/MainArea/ListScrollMargin/ListScroll/List
## The MarginContainer, not DetailBox itself, is what _show_state() toggles —
## DetailBox's children need the 5px left/right inset DetailMargin provides
## (see MosMailApp.tscn); list rows don't need the same treatment since each
## row already gets its own left padding from _email_row_style()'s content
## margin.
@onready var detail_margin: MarginContainer = $VBox/Body/MainArea/DetailMargin
@onready var back_button: Button = $VBox/Body/MainArea/DetailMargin/DetailBox/BackButton
@onready var detail_subject_label: Label = $VBox/Body/MainArea/DetailMargin/DetailBox/DetailSubjectLabel
@onready var detail_meta_label: Label = $VBox/Body/MainArea/DetailMargin/DetailBox/DetailMetaLabel
@onready var note_viewer_slot: Control = $VBox/Body/MainArea/DetailMargin/DetailBox/NoteViewerSlot
@onready var _context_menu: ContextMenu = CONTEXT_MENU_SCENE.instantiate()


func _ready() -> void:
	body_divider.color = Palette.BORDER
	top_bar_divider.color = Palette.BORDER

	# Decorative only — no filter logic wired up in this version. Same
	# permanently-editable=false + font_uneditable_color convention
	# KikuChatApp's InputField uses for its own inert box.
	search_field.focus_mode = Control.FOCUS_NONE
	search_field.add_theme_font_override("font", Palette.font_body)
	search_field.add_theme_font_size_override("font_size", 5)
	search_field.add_theme_color_override("font_uneditable_color", Palette.TEXT_FAINT)
	search_field.add_theme_stylebox_override("read_only", Palette.task_item_style())

	avatar_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	avatar_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar_box.add_theme_stylebox_override("panel", Palette.icon_glyph_style())
	avatar_label.text = PlayerIdentity.player_name.substr(0, 1) if PlayerIdentity.player_name != "" else "?"
	avatar_label.add_theme_font_override("font", Palette.font_body)
	avatar_label.add_theme_font_size_override("font_size", 5)
	avatar_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)

	# Permanently disabled — this build has no compose flow at all. Same
	# half-opacity/no-handler convention ContextMenu's disabled items and
	# TaskManagerApp's unkillable rows use.
	compose_button.disabled = true
	compose_button.modulate.a = 0.5
	compose_button.focus_mode = Control.FOCUS_NONE
	compose_button.add_theme_font_override("font", Palette.font_body)
	compose_button.add_theme_font_size_override("font_size", 5)
	compose_button.add_theme_color_override("font_color", Palette.TEXT_DIM)
	compose_button.add_theme_color_override("font_disabled_color", Palette.TEXT_DIM)
	compose_button.add_theme_stylebox_override("normal", Palette.task_item_style())
	compose_button.add_theme_stylebox_override("disabled", Palette.task_item_style())

	back_button.focus_mode = Control.FOCUS_NONE
	back_button.add_theme_font_override("font", Palette.font_body)
	back_button.add_theme_font_size_override("font_size", 5)
	back_button.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	back_button.add_theme_stylebox_override("normal", Palette.task_item_style())
	back_button.add_theme_stylebox_override("hover", Palette.task_item_style())
	back_button.add_theme_stylebox_override("pressed", Palette.task_item_style())
	back_button.pressed.connect(_on_back_pressed)

	# font_body, not font_chrome: font_chrome (Press Start 2P) is a Latin-only
	# pixel font with no Thai glyph coverage, so Thai vowel/tone marks fell
	# back to a different font and mis-stacked instead of positioning
	# correctly — every subject in inbox.tres is Thai, so this hit every
	# email. font_body (VT323) is what every other Thai string in the game
	# already renders through. autowrap since the bigger size makes a long
	# subject more likely to run past the detail pane's width.
	detail_subject_label.add_theme_font_override("font", Palette.font_body)
	detail_subject_label.add_theme_font_size_override("font_size", 7)
	detail_subject_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	detail_subject_label.autowrap_mode = TextServer.AUTOWRAP_WORD

	detail_meta_label.add_theme_font_override("font", Palette.font_body)
	detail_meta_label.add_theme_font_size_override("font_size", 5)
	detail_meta_label.add_theme_color_override("font_color", Palette.TEXT_DIM)

	Palette.style_scrollbar(list_scroll)

	_note_viewer = NOTE_VIEWER_SCENE.instantiate()
	note_viewer_slot.add_child(_note_viewer)
	_note_viewer.set_anchors_preset(Control.PRESET_FULL_RECT)

	_password_dialog = PASSWORD_DIALOG_SCENE.instantiate()
	add_child(_password_dialog)

	add_child(_context_menu)
	_context_menu.item_selected.connect(_on_context_item_selected)

	_rebuild_tabs()
	_rebuild_email_list()
	_show_state("list")


## Two mutually-exclusive states, like DevCrackApp._show_state — not a
## persistent split-pane like KikuChatApp, since a list/detail toggle is
## exactly what a Gmail-style inbox reads as.
func _show_state(state: String) -> void:
	list_scroll_margin.visible = state == "list"
	detail_margin.visible = state == "detail"


## -- Sidebar tabs ----------------------------------------------------------

func _rebuild_tabs() -> void:
	for c in tab_list.get_children():
		c.queue_free()

	for tab_key in TABS:
		_add_tab_row(tab_key)


func _add_tab_row(tab_key: String) -> void:
	var selected := tab_key == _current_tab

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", Palette.sidebar_tab_style(selected))
	row.gui_input.connect(_on_tab_row_gui_input.bind(tab_key))
	row.mouse_entered.connect(func() -> void:
		if tab_key != _current_tab:
			row.add_theme_stylebox_override("panel", Palette.sidebar_tab_style(false, true))
	)
	row.mouse_exited.connect(func() -> void:
		if tab_key != _current_tab:
			row.add_theme_stylebox_override("panel", Palette.sidebar_tab_style(false, false))
	)

	var label := Label.new()
	label.text = tab_key
	label.add_theme_font_override("font", Palette.font_body)
	label.add_theme_font_size_override("font_size", 5)
	label.add_theme_color_override("font_color", Palette.TEXT_MAIN if selected else Palette.TEXT_DIM)
	row.add_child(label)

	tab_list.add_child(row)


## Switching tabs always drops back to list state for the new tab, even if
## the player was mid-read in detail state — there's no "remember where I
## was per tab" behavior here.
func _on_tab_row_gui_input(event: InputEvent, tab_key: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_current_tab = tab_key
		_rebuild_tabs()
		_rebuild_email_list()
		_show_state("list")


## -- Email list --------------------------------------------------------

func _rebuild_email_list() -> void:
	for c in list.get_children():
		c.queue_free()

	for email in MAIL_LIST.emails:
		if _email_matches_current_tab(email):
			_add_email_row(email)


func _email_matches_current_tab(email: EmailData) -> bool:
	match _current_tab:
		"inbox":
			return not email.is_spam and not GameState.is_email_deleted(email)
		"spam":
			return email.is_spam and not GameState.is_email_deleted(email)
		"trash":
			return GameState.is_email_deleted(email)
	return false


## No visual hint of requires_code here — same "no advance hints" rule
## FilesApp/KikuChatApp follow for their own locked content. In the trash
## tab a row also grows a [restore] button on the right, same pattern as
## TrashApp._add_row. The row itself is a flat bottom-divider row (see
## _email_row_style), not a task_item_style()-boxed one — matching the
## reference mockup's contiguous list-with-hover look rather than the
## all-sides-bordered box convention DevCrackApp/TaskManagerApp rows use.
func _add_email_row(email: EmailData) -> void:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _email_row_style(false))
	row.gui_input.connect(_on_email_row_gui_input.bind(email))
	row.mouse_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", _email_row_style(true)))
	row.mouse_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", _email_row_style(false)))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	row.add_child(hbox)

	var sender_label := Label.new()
	sender_label.text = email.sender
	sender_label.clip_text = true
	sender_label.custom_minimum_size = Vector2(SENDER_WIDTH, 0)
	sender_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sender_label.add_theme_font_override("font", Palette.font_body)
	sender_label.add_theme_font_size_override("font_size", 5)
	sender_label.add_theme_color_override("font_color", Palette.TEXT_MAIN)
	hbox.add_child(sender_label)

	var preview_label := Label.new()
	preview_label.text = "%s — %s" % [email.subject, email.snippet]
	preview_label.clip_text = true
	preview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_label.add_theme_font_override("font", Palette.font_body)
	preview_label.add_theme_font_size_override("font_size", 5)
	preview_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	hbox.add_child(preview_label)

	var datetime_label := Label.new()
	datetime_label.text = email.datetime
	datetime_label.clip_text = true
	datetime_label.custom_minimum_size = Vector2(DATETIME_WIDTH, 0)
	datetime_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	datetime_label.add_theme_font_override("font", Palette.font_body)
	datetime_label.add_theme_font_size_override("font_size", 4)
	datetime_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	hbox.add_child(datetime_label)

	if _current_tab == "trash":
		var restore_button := Button.new()
		restore_button.text = "[restore]"
		restore_button.focus_mode = Control.FOCUS_NONE
		restore_button.add_theme_font_override("font", Palette.font_body)
		restore_button.add_theme_font_size_override("font_size", 5)
		restore_button.add_theme_color_override("font_color", Palette.TEXT_MAIN)
		restore_button.add_theme_stylebox_override("normal", Palette.task_item_style())
		restore_button.add_theme_stylebox_override("hover", Palette.task_item_style())
		restore_button.add_theme_stylebox_override("pressed", Palette.task_item_style())
		restore_button.pressed.connect(_on_restore_pressed.bind(email))
		hbox.add_child(restore_button)

	list.add_child(row)


## Flat list row with a bottom divider only, not a boxed task_item_style()
## row — same shape as Palette.chat_contact_row_style() (WINDOW_BG at rest,
## TITLEBAR_BG on hover, Palette.BORDER bottom line), but built locally
## rather than reused directly: chat_contact_row_style()'s content margin is
## tuned for KikuChat's narrow sidebar rows, while these need the reference
## mockup's roomier "8px 12px" padding. No "selected" state, unlike
## chat_contact_row_style() — an email row never stays highlighted once
## you've clicked into it, you've simply left the list.
func _email_row_style(hovered: bool) -> StyleBoxFlat:
	var style := Palette.make_flat_style(Palette.TITLEBAR_BG if hovered else Palette.WINDOW_BG, Palette.BORDER, 0)
	style.border_width_bottom = 1
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _on_restore_pressed(email: EmailData) -> void:
	GameState.restore_email(email)
	_rebuild_email_list()


## Double-click (not single-click like KikuChatApp's contact rows) — MosMail
## is a temporary list/detail toggle the same way FilesApp's file rows are,
## not a persistent split-pane that benefits from single-click's extra
## responsiveness, so this follows FilesApp._on_file_row_gui_input's
## convention instead. Right-click only offers "Delete" outside the trash
## tab — restoring a trashed email happens through the row's own [restore]
## button instead, so no context menu is wired up at all while in trash.
func _on_email_row_gui_input(event: InputEvent, email: EmailData) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		_open_email(email)
	elif event.button_index == MOUSE_BUTTON_RIGHT and _current_tab != "trash":
		_context_target_email = email
		_context_menu.open_at(get_global_mouse_position(), [
			{"label": "Delete", "action": "delete"},
		])


func _on_context_item_selected(action: String) -> void:
	if action == "delete" and _context_target_email:
		GameState.delete_email(_context_target_email)
		_rebuild_email_list()


func _open_email(email: EmailData) -> void:
	if email.requires_code and not GameState.is_app_unlocked_by_code(APP_ID):
		_pending_email = email
		_connect_password_dialog_once()
		_password_dialog.ask("กรุณาใส่รหัสผ่านเพื่อเปิดอ่านอีเมลนี้")
		return

	_show_email_detail(email)


## _password_dialog is one instance reused across every locked email this
## app opens, so guard against double-connecting the same signal twice —
## same pattern KikuChatApp._connect_password_dialog_once/
## Desktop._confirm_shutdown use for their own shared dialogs.
func _connect_password_dialog_once() -> void:
	if not _password_dialog.submitted.is_connected(_on_password_submitted):
		_password_dialog.submitted.connect(_on_password_submitted, CONNECT_ONE_SHOT)
	if not _password_dialog.cancelled.is_connected(_on_password_cancelled):
		_password_dialog.cancelled.connect(_on_password_cancelled, CONNECT_ONE_SHOT)


func _on_password_submitted(text: String) -> void:
	var email := _pending_email
	_pending_email = null

	if text.strip_edges() == MAIL_LIST.access_code:
		GameState.unlock_app_with_code(APP_ID)
		_show_email_detail(email)
	elif warning_dialog:
		warning_dialog.show_message("รหัสผ่านไม่ถูกต้อง")


func _on_password_cancelled() -> void:
	_pending_email = null


func _show_email_detail(email: EmailData) -> void:
	_selected_email = email
	detail_subject_label.text = email.subject
	detail_meta_label.text = "%s · %s" % [email.sender, email.datetime]
	_note_viewer.show_plain(email.content)
	_show_state("detail")


## Returns to "list" for _current_tab as it stands now, not always "inbox" —
## _current_tab is never touched by opening/closing an email.
func _on_back_pressed() -> void:
	_selected_email = null
	_show_state("list")
