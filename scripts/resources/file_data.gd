class_name FileData
extends Resource

@export var id: String = ""
@export var filename: String
@export var extension: String
@export var is_hidden: bool = false
## Gates delete permission only (see GameState.can_delete_file) — whether the
## file can be *opened* is a separate concern, derived live from its blobs'
## should_remove state via GameState.get_lock_reason(), not this flag.
@export var is_protected: bool = false
@export var content: String
@export var blobs: Array = []
