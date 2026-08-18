class_name ChatThreadData
extends Resource

## Deliberately does not extend FileData — KikuChat's password unlock is a
## separate mechanic from the DevCrack/blob lock system (see GameState.
## is_app_unlocked_by_code()). A thread is never passed to
## GameState.get_lock_reason() and carries no blobs.
@export var id: String = ""
@export var contact_name: String
@export var last_message_preview: String
@export var requires_code: bool = false
## Untyped, not Array[ChatMessageData] — same as FileData.blobs and for the
## same reason (see KikuChatListData.threads for the specific bug this
## avoids).
@export var messages: Array = []
