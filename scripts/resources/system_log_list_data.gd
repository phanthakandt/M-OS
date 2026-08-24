class_name SystemLogListData
extends Resource

## Plain Array, not Array[LogEntryData] — see kikuchat_list_data.gd/
## chat_thread_data.gd for the same call: a typed array of a custom
## class_name Resource resolves its elements to their own attached Script
## instead of an instance at runtime, on freshly hand-authored script files
## that haven't been through the editor's UID assignment yet. Untyped
## sidesteps it entirely.
@export var entries: Array = []
