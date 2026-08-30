class_name ChatMessageData
extends Resource

@export var sender: String
@export var text: String
@export var date: String
@export var timestamp: String

## Optional — most messages are text-only and leave this null.
@export var image: Texture2D
