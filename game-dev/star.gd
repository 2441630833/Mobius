extends Area2D

signal collected

var _taken := false


func _ready() -> void:
	add_to_group("stars")
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _taken or not (body is CharacterBody2D):
		return
	_taken = true
	remove_from_group("stars")
	hide()
	collected.emit()
