extends Node

static var font_body: FontFile = preload("res://assets/fonts/VT323-Regular.ttf")
static var font_chrome: FontFile = preload("res://assets/fonts/PressStart2P-Regular.ttf")

const DESKTOP_BG_1 := Color("#161c22")
const DESKTOP_BG_2 := Color("#1c2530")
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

static func make_flat_style(bg: Color, border_color: Color, border_width: int = 1, margin: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_border_width_all(border_width)
	style.border_color = border_color
	style.set_corner_radius_all(0)
	style.set_content_margin_all(margin)
	return style

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

static func start_button_style() -> StyleBoxFlat:
	return make_flat_style(WINDOW_BG, BORDER_LIGHT, 1, 3)

static func tb_btn_style_accent(accent: Color) -> StyleBoxFlat:
	return make_flat_style(accent, BORDER, 1)

static func blob_marked_style() -> StyleBoxFlat:
	return make_flat_style(Color(ACCENT_WARN.r, ACCENT_WARN.g, ACCENT_WARN.b, 0.15), ACCENT_WARN, 1, 2)
