class_name MosMailListData
extends Resource

@export var access_code: String

## Plain Array, not Array[EmailData]. Same-file sub-resource embedding (all
## EmailData live directly in inbox.tres, like blobs in a FileData) was
## assumed safe from the KikuChatListData.threads/ChatThreadData.messages
## cross-file bug (see KikuChatApp/SystemLogApp above) — SystemLogListData
## hit the exact same failure anyway, most likely because email_data.gd/
## mosmail_list_data.gd are freshly hand-authored scripts with no uid://
## yet. Untyped sidesteps it the same way it did there.
@export var emails: Array = []
