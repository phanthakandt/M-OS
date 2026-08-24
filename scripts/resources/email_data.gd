class_name EmailData
extends Resource

@export var id: String = ""
@export var sender: String
@export var subject: String
@export var snippet: String
@export var content: String
@export var datetime: String
@export var is_spam: bool = false
@export var requires_code: bool = false
