class_name FolderData
extends Resource

@export var folder_name: String
@export var is_hidden: bool = false
@export var subfolders: Array[FolderData] = []
@export var files: Array[FileData] = []
