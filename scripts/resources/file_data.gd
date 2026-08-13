class_name FileData
extends Resource

@export var id: String = ""
@export var filename: String
@export var extension: String
@export var is_locked: bool = false
@export var is_hidden: bool = false
@export var is_protected: bool = false
@export var is_corrupted: bool = false
@export var content: String
@export var blobs: Array = []
@export var last_modified_date: String
@export var last_modified_by: String
