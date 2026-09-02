extends Node

static var font_body: FontFile = preload("res://assets/fonts/VT323-Regular.ttf")
static var font_chrome: FontFile = preload("res://assets/fonts/PressStart2P-Regular.ttf")

const DESKTOP_BG_1 := Color("#161c22")
const DESKTOP_BG_2 := Color("#1c2530")
## Endpoint of the desktop's ghost-process corruption tint (see
## desktop_corruption_color()) — deliberately darker/dimmer than ACCENT_WARN,
## which is sized for a small accent, not a full-screen background wash.
const DESKTOP_BG_DANGER := Color("#3a1417")
## CanvasModulate endpoints for corruption_modulate() — Desktop.tscn's single
## CanvasModulate multiplies these against every already-drawn pixel on
## screen (windows, taskbar, icons, text, not just the desktop background),
## so this is what makes the *whole screen* bleed red as ghost processes pile
## up, not just Background. NORMAL is identity (no tint); DANGER only pulls
## green/blue down (hard, for a vivid/saturated red at full corruption rather
## than a muddy one) — red is left at 1.0 rather than boosted above it, since
## a Color channel above 1.0 just clamps to no-op on an LDR (Compatibility
## renderer) backbuffer.
const CANVAS_MODULATE_NORMAL := Color(1, 1, 1, 1)
const CANVAS_MODULATE_DANGER := Color(1.0, 0.15, 0.2, 1)
const WINDOW_BG := Color("#232d38")
const TITLEBAR_BG := Color("#2c3948")
const TITLEBAR_BG_ACTIVE := Color("#354658")
const BORDER := Color("#3d4d5e")
const BORDER_LIGHT := Color("#51647a")
const TEXT_MAIN := Color("#cdd8e2")
const TEXT_DIM := Color("#7d8b9a")
const TEXT_FAINT := Color("#4d5a68")
const ACCENT_WARN := Color("#a8484a")
const ACCENT_WARN_DIM := Color("#6b3234")
const ACCENT_MINIMIZE := Color("#a89448")
const ACCENT_MAXIMIZE := Color("#4a8a5a")
const SCRIM := Color(0, 0, 0, 0.55)
const VOID := Color(0, 0, 0, 1)
const TRANSPARENT := Color(0, 0, 0, 0)

static func make_flat_style(bg: Color, border_color: Color, border_width: int = 1, margin: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_border_width_all(border_width)
	style.border_color = border_color
	style.set_corner_radius_all(0)
	style.set_content_margin_all(margin)
	return style

## Thins and reskins a scrollable node's VScrollBar with flat Palette styles —
## the engine's default width reads oversized against this game's tiny
## 384x216-space pixel fonts/rows. Was duplicated near-identically across
## TaskManagerApp/KikuChatApp/SystemLogApp/MosMailApp before being pulled
## here; every caller just does `Palette.style_scrollbar(scroll)` in its own
## _ready() now. Deliberately untyped rather than `ScrollContainer` — a
## RichTextLabel (see NoteViewer) also exposes get_v_scroll_bar() but isn't a
## ScrollContainer subclass, and there's no shared base class to type this
## against instead; untyped just resolves the call at runtime for either.
static func style_scrollbar(scroll) -> void:
	var vscroll: VScrollBar = scroll.get_v_scroll_bar()
	vscroll.custom_minimum_size = Vector2(3, 0)
	vscroll.add_theme_stylebox_override("scroll", make_flat_style(WINDOW_BG, BORDER, 0))
	vscroll.add_theme_stylebox_override("grabber", make_flat_style(BORDER_LIGHT, BORDER_LIGHT, 0))
	vscroll.add_theme_stylebox_override("grabber_highlight", make_flat_style(TEXT_DIM, TEXT_DIM, 0))
	vscroll.add_theme_stylebox_override("grabber_pressed", make_flat_style(TEXT_MAIN, TEXT_MAIN, 0))

static func window_style() -> StyleBoxFlat:
	return make_flat_style(WINDOW_BG, BORDER_LIGHT, 1)

static func titlebar_style(active: bool) -> StyleBoxFlat:
	var style := make_flat_style(TITLEBAR_BG_ACTIVE if active else TITLEBAR_BG, BORDER, 0)
	style.border_width_bottom = 1
	return style

static func icon_glyph_style() -> StyleBoxFlat:
	return make_flat_style(WINDOW_BG, BORDER_LIGHT, 1)

static func taskbar_style() -> StyleBoxFlat:
	var style := make_flat_style(TITLEBAR_BG, BORDER_LIGHT, 0)
	style.border_width_top = 1
	return style

static func task_item_style() -> StyleBoxFlat:
	return make_flat_style(WINDOW_BG, BORDER, 1, 2)

## Same border width/content margin as task_item_style() but fully
## transparent — for rows that only show their box on hover (see
## TaskManagerApp): swapping straight from a borderless StyleBoxEmpty to
## task_item_style() changes the row's minimum size and makes the whole list
## jump, since border width and margin suddenly appear. Reserving the same
## space at rest, just invisibly, keeps hover from changing layout at all.
static func task_item_style_invisible() -> StyleBoxFlat:
	return make_flat_style(TRANSPARENT, TRANSPARENT, 1, 2)

static func start_button_style() -> StyleBoxFlat:
	return make_flat_style(WINDOW_BG, BORDER_LIGHT, 1, 3)

## Start menu row hover: a flat left-accent-bar indicator, unlike
## task_item_style()'s all-around box — background fill plus a border
## reserved only on the left edge. TRANSPARENT (not 0 width) at rest, same
## reason task_item_style_invisible() stays transparent instead of
## borderless: border_width_left must stay the same 3px whether hovered or
## not, or the row's minimum size (and the whole menu's layout) would shift
## on hover.
static func start_menu_item_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = TITLEBAR_BG if hovered else TRANSPARENT
	style.border_width_left = 3
	style.border_color = BORDER_LIGHT if hovered else TRANSPARENT
	style.set_corner_radius_all(0)
	style.content_margin_left = 10
	style.content_margin_top = 2
	style.content_margin_right = 24
	style.content_margin_bottom = 2
	return style

static func tb_btn_style_accent(accent: Color) -> StyleBoxFlat:
	return make_flat_style(accent, BORDER, 1)

static func blob_marked_style() -> StyleBoxFlat:
	return make_flat_style(Color(ACCENT_WARN.r, ACCENT_WARN.g, ACCENT_WARN.b, 0.15), ACCENT_WARN, 1, 2)

## KikuChat contact row: a flat list row (bottom-divider only, not a boxed
## item like task_item_style()) that highlights on hover and stays
## highlighted while selected — selected always wins over hovered.
static func chat_contact_row_style(selected: bool, hovered: bool = false) -> StyleBoxFlat:
	var bg := TITLEBAR_BG_ACTIVE if selected else (TITLEBAR_BG if hovered else WINDOW_BG)
	var style := make_flat_style(bg, BORDER, 0, 2)
	style.border_width_bottom = 1
	return style

## KikuChat message bubble: same bordered-box shape as task_item_style(),
## just a different fill per sender ("me" vs. the contact) and a bit more
## padding, matching a chat bubble's proportions rather than a list row's.
static func chat_bubble_style(is_me: bool) -> StyleBoxFlat:
	return make_flat_style(TITLEBAR_BG if is_me else DESKTOP_BG_2, BORDER, 1, 3)

## MosMail sidebar tab (inbox/spam/trash): same left-accent-bar shape as
## start_menu_item_style() (background fill + a border reserved only on the
## left edge, held at a constant width so hover/selection never shifts
## layout), but kept as its own builder rather than reused/parameterized:
## start_menu_item_style() only has a hovered bool since start menu items
## never stay selected, while a sidebar tab needs a persistent selected
## state independent of hover (selected always wins, same tri-state
## priority chat_contact_row_style() already uses) — and its content margins
## are tuned for a ~46px sidebar column, not the start menu's much wider
## rows. Overloading one signature to cover both would've meant every
## existing start_menu_item_style() call site also having to pass a
## meaningless selected argument.
static func sidebar_tab_style(selected: bool, hovered: bool = false) -> StyleBoxFlat:
	var bg := TITLEBAR_BG_ACTIVE if selected else (TITLEBAR_BG if hovered else TRANSPARENT)
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_left = 2
	style.border_color = BORDER_LIGHT if selected else TRANSPARENT
	style.set_corner_radius_all(0)
	style.content_margin_left = 6
	style.content_margin_top = 5
	style.content_margin_right = 6
	style.content_margin_bottom = 5
	return style

## FilesApp sidebar shortcut row: same hover-only left-accent-bar shape as
## start_menu_item_style() (background fill + a border reserved only on the
## left edge, held at a constant width so hover never shifts layout), but
## with no persistent "selected" state at all — a sidebar click navigates
## away immediately, so nothing about it should look "active" — and a
## narrower 2px border/content margin tuned for this app's slim sidebar
## column rather than the start menu's much wider rows. Doesn't reuse
## sidebar_tab_style(): that builder's border reacts to `selected`, not
## `hovered`, which is the opposite of what a selectionless hover-only row
## needs.
static func drive_sidebar_item_style(hovered: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = TITLEBAR_BG if hovered else TRANSPARENT
	style.border_width_left = 2
	style.border_color = BORDER_LIGHT if hovered else TRANSPARENT
	style.set_corner_radius_all(0)
	style.content_margin_left = 5
	style.content_margin_top = 4
	style.content_margin_right = 5
	style.content_margin_bottom = 4
	return style

## Shared 0..1 corruption progress for both desktop_corruption_color() and
## corruption_modulate(), so the eased curve is only written once. Eased
## (quadratic, t*t) rather than linear, and deliberately ease-*in* rather
## than ease-out — the first several ghost processes should read as almost
## no change at all, with the shift only becoming obvious as count climbs
## toward max_count, so the corruption creeps up on the player instead of
## announcing itself immediately.
static func _corruption_t(ghost_count: int, max_count: int) -> float:
	var t: float = clamp(float(ghost_count) / float(max_count), 0.0, 1.0)
	return t * t

## Desktop.background's color as a function of how many ghost processes
## (GameState.get_ghost_process_count()) are currently alive — an eased lerp
## from the normal desktop background toward DESKTOP_BG_DANGER, fully
## saturated at max_count. The one place this lerp is written; callers (just
## Desktop so far) always go through here instead of repeating it.
static func desktop_corruption_color(ghost_count: int, max_count: int = 15) -> Color:
	return DESKTOP_BG_1.lerp(DESKTOP_BG_DANGER, _corruption_t(ghost_count, max_count))

## Desktop.tscn's single CanvasModulate node's color, same ghost-count
## progress as desktop_corruption_color() but eased against
## CANVAS_MODULATE_NORMAL/CANVAS_MODULATE_DANGER instead — this is what tints
## every already-rendered pixel on screen (windows, taskbar, icons, text),
## not just the desktop background. See Desktop._update_corruption_tint().
static func corruption_modulate(ghost_count: int, max_count: int = 15) -> Color:
	return CANVAS_MODULATE_NORMAL.lerp(CANVAS_MODULATE_DANGER, _corruption_t(ghost_count, max_count))
