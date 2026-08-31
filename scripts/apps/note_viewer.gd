class_name NoteViewer
extends Control

@onready var rich_text: RichTextLabel = $RichText


func _ready() -> void:
	rich_text.bbcode_enabled = true
	rich_text.scroll_active = true
	rich_text.add_theme_font_override("normal_font", Palette.font_body)
	rich_text.add_theme_font_size_override("normal_font_size", 4)
	rich_text.add_theme_color_override("default_color", Palette.TEXT_DIM)


## MosMailApp reuses a single NoteViewer instance across every email
## (FilesApp/Desktop, by contrast, always instantiate a fresh one per file,
## so they're already at scroll 0 here and this line is a no-op for them) —
## without resetting scroll here, reading a long email, scrolling down, then
## opening a short one left the RichTextLabel sitting at its previous scroll
## position instead of the top. Setting the VScrollBar's value directly to 0
## rather than scroll_to_line(0): 0 is always a valid Range value regardless
## of whether this frame's layout has finished being measured yet, unlike
## scrolling to the *bottom* (see KikuChatApp._scroll_to_latest_message()/
## SystemLogApp._scroll_to_latest_entry()), which has to wait several frames
## for max_value to actually settle first.
func show_plain(text: String) -> void:
	rich_text.text = "[color=#cdd8e2]%s[/color]" % text
	rich_text.get_v_scroll_bar().value = 0
