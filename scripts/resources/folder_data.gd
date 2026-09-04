class_name FolderData
extends Resource

@export var folder_name: String
@export var is_hidden: bool = false
@export var is_protected: bool = false
## Password gate for entering this folder in FilesApp — a mechanic entirely
## separate from GameState.get_lock_reason()'s DevCrack/blob system, which
## only ever applies to files. Reuses GameState.is_app_unlocked_by_code()/
## unlock_app_with_code() the same way KikuChatApp/MosMailApp do for their
## own password gates, but keyed by this folder's own resource_path rather
## than one shared app-wide code — a future second locked folder should get
## its own independent code, not share this one.
@export var requires_code: bool = false
@export var access_code: String = ""
## Untyped, not Array[FolderData]/Array[FileData] — same as FileData.blobs/
## KikuChatListData.threads. A typed array of a custom class_name Resource
## whose elements are loaded through a .tres -> .tres reference chain (a
## subfolder saved as its own file and referenced from here, rather than
## embedded as a sub-resource) trips a Godot type-validation bug where an
## element resolves to its own attached Script instead of an instance
## ("argument should be FolderData but is
## res://scripts/resources/folder_data.gd"); untyped sidesteps it entirely.
@export var subfolders: Array = []
@export var files: Array = []
