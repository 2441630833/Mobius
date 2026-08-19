extends Area2D

signal collected

const SPIN_SPEED := 4.0

var _taken := false


func _ready() -> void:
	add_to_group("stars")
	add_to_group("bonus_stars")
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _taken:
		return
	rotation += SPIN_SPEED * delta


func _on_body_entered(body: Node) -> void:
	if _taken or not (body is CharacterBody2D):
		return
	_taken = true
	remove_from_group("stars")
	remove_from_group("bonus_stars")
	hide()
	collected.emit()
