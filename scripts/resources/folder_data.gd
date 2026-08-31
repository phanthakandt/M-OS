class_name FolderData
extends Resource

@export var folder_name: String
@export var is_hidden: bool = false
@export var is_protected: bool = false
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
