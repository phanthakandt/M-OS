class_name FileData
extends Resource

@export var filename: String
@export var extension: String
@export var is_locked: bool = false
@export var is_corrupted: bool = false
@export var content: String
@export var reveals_clue: String
@export var blobs: Array = []
@export var last_modified_date: String
@export var last_modified_by: String

## Runtime-only: whether this file's DevCrack puzzle has been solved this session.
var is_repacked: bool = false
