extends Node

const LOGIN_SCENE := preload("res://scenes/LoginScreen.tscn")
const DESKTOP_SCENE := preload("res://scenes/desktop/Desktop.tscn")


func _ready() -> void:
	var login: Control = LOGIN_SCENE.instantiate()
	add_child(login)
	login.login_submitted.connect(_on_login_submitted.bind(login))


func _on_login_submitted(_name: String, login_node: Control) -> void:
	login_node.queue_free()
	var desktop: Control = DESKTOP_SCENE.instantiate()
	add_child(desktop)
