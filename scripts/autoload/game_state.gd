extends Node

signal trashed_changed
signal ghost_processes_changed

## Runtime progress, keyed by FileData.id (falls back to resource_path).
## Never mutate FileData resources directly — preloaded resources are cached
## singletons for the process's lifetime, so in-place mutation would leak
## across sessions/new games.
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

## DevCrack archive-entry on/off state, keyed by file_key -> {entry_id: true}
## meaning "currently disabled". A toggle, not a one-way flag — re-enabling a
## should_remove entry re-locks the file (see is_locked()). Session state
## only — never mutates BlobData/FileData.
var _disabled_archive_entries: Dictionary = {}

## Password-unlock state for apps like KikuChat (see kikuchat_app.gd) — a
## completely separate mechanic from the DevCrack/blob lock system above.
## Keyed by an app_id String (e.g. "kikuchat") -> true once that app's code
## has been entered correctly once. GameState never knows the actual code or
## compares it — it only remembers that an app has been unlocked; the app
## itself owns its access code (see KikuChatListData.access_code) and does
## the comparison. Keying by app_id from the start means a second app (e.g.
## MosMail) can reuse is_app_unlocked_by_code()/unlock_app_with_code() with
## its own app_id and get a fully independent unlock state for free.
var _code_unlocked_apps: Dictionary = {}

## "Ghost process" cascade, driven entirely from here (not DevCrackApp or
## TaskManagerApp, which just call in and render — see on_devcrack_repacked()/
## kill_ghost_process()). Session state only, like everything else in this
## file: cleared on reset_progress(), never persisted, never backed by a
## resource. Each entry is {id: String, name: String, hidden: bool,
## killable: bool}. Entries are never capped — accumulation without limit is
## the intended pressure mechanic, not an oversight.
var _ghost_processes: Array = []
var _next_ghost_id: int = 0


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


## Restore has no protected/undeletable equivalent — anything that was
## successfully trashed can always be restored.
func restore_file(file: FileData) -> void:
	var key := _file_key(file)
	if _trashed_files.has(key):
		_trashed_files.erase(key)
		trashed_changed.emit()


func restore_folder(folder: FolderData) -> void:
	var key := _folder_key(folder)
	if _trashed_folders.has(key):
		_trashed_folders.erase(key)
		trashed_changed.emit()


func is_readme_deleted() -> bool:
	return _readme_deleted


func delete_readme() -> void:
	_readme_deleted = true
	trashed_changed.emit()


func restore_readme() -> void:
	if _readme_deleted:
		_readme_deleted = false
		trashed_changed.emit()


func is_archive_entry_disabled(file: FileData, entry_id: String) -> bool:
	var key := _file_key(file)
	return _disabled_archive_entries.get(key, {}).get(entry_id, false)


func set_archive_entry_disabled(file: FileData, entry_id: String, disabled: bool) -> void:
	var key := _file_key(file)
	if not _disabled_archive_entries.has(key):
		_disabled_archive_entries[key] = {}
	_disabled_archive_entries[key][entry_id] = disabled


func is_unlocked(file: FileData) -> bool:
	return unlocked_files.get(_file_key(file), false)


func mark_unlocked(file: FileData) -> void:
	unlocked_files[_file_key(file)] = true


enum LockReason { UNLOCKED, PROTECTED, CORRUPTED }

## Computes *why* a file is locked, not just whether. PROTECTED means a
## should_remove entry (e.g. data.protected) is still enabled — the
## intended block. CORRUPTED means any non-should_remove entry (essential
## data) has been disabled instead — an unintended, self-inflicted break.
## Unlike PROTECTED, CORRUPTED doesn't require the file to have a
## should_remove blob at all: disabling essential data breaks *any* file
## that carries it, puzzle file or not (e.g. readme.txt, which has no
## should_remove blob but still corrupts if its one blob gets disabled).
## Both conditions are reversible: re-enabling the relevant entry clears
## them, same as everything else in this dictionary-backed session state.
func get_lock_reason(file: FileData) -> int:
	if is_unlocked(file):
		return LockReason.UNLOCKED

	var protected_active := false
	var corrupted := false
	for blob in file.blobs:
		var disabled := is_archive_entry_disabled(file, blob.id)
		if blob.should_remove:
			if not disabled:
				protected_active = true
		elif disabled:
			corrupted = true

	if corrupted:
		return LockReason.CORRUPTED
	if protected_active:
		return LockReason.PROTECTED
	return LockReason.UNLOCKED


## Effective lock state: whether the file has any should_remove blob still
## enabled or any essential (non-should_remove) blob disabled (see
## get_lock_reason()). Nothing on FileData/BlobData is ever mutated — this
## is computed live every call.
func is_locked(file: FileData) -> bool:
	return get_lock_reason(file) != LockReason.UNLOCKED


func is_app_unlocked_by_code(app_id: String) -> bool:
	return _code_unlocked_apps.get(app_id, false)


func unlock_app_with_code(app_id: String) -> void:
	_code_unlocked_apps[app_id] = true


## Called by DevCrackApp unconditionally on every REPACK press, regardless of
## which file or what the repack's outcome is (REPACK never branches on
## outcome — see DevCrackApp._on_repack_pressed). It's a flat per-repack
## chance, not tied to solving or breaking anything. Emits
## ghost_processes_changed only when the roll actually spawns something —
## unlike kill_ghost_process(), a miss here is a true no-op, so there's
## nothing for TaskManagerApp/Desktop to react to.
func on_devcrack_repacked() -> void:
	if randf() < 0.7:
		_spawn_ghost_process("lived.process", false, true)
		ghost_processes_changed.emit()


## Kills a ghost process by id. Only killing a "lived.process" entry can
## cascade into spawning a "ssecorp.devil" in its place (hidden, and only a
## 40% chance killable) — killing (or failing to kill) a "ssecorp.devil"
## never cascades further. ghost_processes_changed always fires, whether or
## not a cascade spawn happened, so TaskManagerApp's list stays live either way.
func kill_ghost_process(id: String) -> void:
	var killed_name := ""
	for i in _ghost_processes.size():
		if _ghost_processes[i].id == id:
			killed_name = _ghost_processes[i].name
			_ghost_processes.remove_at(i)
			break
	if killed_name == "lived.process" and randf() < 0.7:
		_spawn_ghost_process("ssecorp.devil", true, randf() >= 0.6)
	ghost_processes_changed.emit()


## Read-only — TaskManagerApp renders straight from this, never mutates it.
func get_ghost_processes() -> Array:
	return _ghost_processes


## _ghost_processes only ever holds entries that haven't been killed yet
## (killing one removes it — see kill_ghost_process()), so its size already
## is exactly "how many lived.process/ssecorp.devil are currently alive."
func get_ghost_process_count() -> int:
	return _ghost_processes.size()


## Shared by on_devcrack_repacked() and kill_ghost_process()'s cascade, so
## id-assignment and the entry shape only live in one place.
func _spawn_ghost_process(process_name: String, hidden: bool, killable: bool) -> void:
	_ghost_processes.append({
		"id": "ghost_%d" % _next_ghost_id,
		"name": process_name,
		"hidden": hidden,
		"killable": killable,
	})
	_next_ghost_id += 1


func reset_progress() -> void:
	unlocked_files.clear()
	_trashed_files.clear()
	_trashed_folders.clear()
	_readme_deleted = false
	_disabled_archive_entries.clear()
	_code_unlocked_apps.clear()
	_ghost_processes.clear()
	_next_ghost_id = 0
