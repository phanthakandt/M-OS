class_name KikuChatListData
extends Resource

## The single app-wide password (not per-thread — see ChatThreadData.
## requires_code). KikuChatApp compares a player-entered code against this
## field itself; GameState only remembers whether that comparison has ever
## succeeded (GameState.is_app_unlocked_by_code("kikuchat")).
@export var access_code: String
## Untyped, not Array[ChatThreadData] — same as FileData.blobs. A typed
## array of a custom class_name Resource whose elements are loaded through a
## .tres -> .tres reference chain (this file -> each thread's own .tres,
## rather than embedded sub-resources) trips a Godot type-validation bug
## where an element resolves to its own attached Script instead of an
## instance ("argument should be ChatThreadData but is
## res://.../chat_thread_data.gd"); untyped sidesteps it entirely.
@export var threads: Array = []
