extends Node

var has_learned_devcrack: bool = false

## Runtime progress, keyed by FileData.id (falls back to resource_path).
## Never mutate FileData resources directly — preloaded resources are cached
## singletons for the process's lifetime, so in-place mutation would leak
## across sessions/new games.
var repacked_files: Dictionary = {}
var unlocked_files: Dictionary = {}


func _file_key(file: FileData) -> String:
	if file.id != "":
		return file.id
	return file.resource_path


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
