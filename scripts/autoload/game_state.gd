extends Node

signal trashed_changed

var has_learned_devcrack: bool = false

## Runtime progress, keyed by FileData.id (falls back to resource_path).
## Never mutate FileData resources directly — preloaded resources are cached
## singletons for the process's lifetime, so in-place mutation would leak
## across sessions/new games.
var repacked_files: Dictionary = {}
var unlocked_files: Dictionary = {}

## Runtime "trash": entries the player has deleted, tracked here rather than
## by mutating FolderData.subfolders/FileData arrays (immutability rule).
## Deleting a folder moves the whole folder — with everything inside it — to
## the trash as a single entry; its contents are not individually trashed.
var _trashed_files: Dictionary = {}
var _trashed_folders: Dictionary = {}

## The "readme.txt" desktop icon is a file too (just not one backed by a
## FileData resource in the drive tree), so it gets its own flag here rather
## than an entry in _trashed_files.
var _readme_deleted: bool = false


func _file_key(file: FileData) -> String:
	if file.id != "":
		return file.id
	return file.resource_path


func _folder_key(folder: FolderData) -> String:
	return folder.resource_path


func is_file_deleted(file: FileData) -> bool:
	return _trashed_files.has(_file_key(file))


func is_folder_deleted(folder: FolderData) -> bool:
	return _trashed_folders.has(_folder_key(folder))


## FileData.is_protected/FolderData.is_protected are read-only initial data
## (e.g. the "user" folder) — never mutated, just checked here.
func can_delete_file(file: FileData) -> bool:
	return not file.is_protected


func can_delete_folder(folder: FolderData) -> bool:
	return not folder.is_protected


## Returns false (and does nothing) if the entry is protected.
func delete_file(file: FileData) -> bool:
	if not can_delete_file(file):
		return false
	_trashed_files[_file_key(file)] = file
	trashed_changed.emit()
	return true


func delete_folder(folder: FolderData) -> bool:
	if not can_delete_folder(folder):
		return false
	_trashed_folders[_folder_key(folder)] = folder
	trashed_changed.emit()
	return true


func get_trashed_files() -> Array:
	return _trashed_files.values()


func get_trashed_folders() -> Array:
	return _trashed_folders.values()


func is_readme_deleted() -> bool:
	return _readme_deleted


func delete_readme() -> void:
	_readme_deleted = true
	trashed_changed.emit()


func is_repacked(file: FileData) -> bool:
	return repacked_files.get(_file_key(file), false)


func is_unlocked(file: FileData) -> bool:
	return unlocked_files.get(_file_key(file), false)


func mark_repacked(file: FileData) -> void:
	repacked_files[_file_key(file)] = true


func mark_unlocked(file: FileData) -> void:
	unlocked_files[_file_key(file)] = true


## Effective lock state: initial data (FileData.is_locked) combined with
## session progress. FileData.is_locked itself is never mutated.
func is_locked(file: FileData) -> bool:
	return file.is_locked and not is_repacked(file) and not is_unlocked(file)


func reset_progress() -> void:
	has_learned_devcrack = false
	repacked_files.clear()
	unlocked_files.clear()
	_trashed_files.clear()
	_trashed_folders.clear()
	_readme_deleted = false
