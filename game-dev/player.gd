extends CharacterBody2D

const SPEED := 280.0

var _autoplay := false


func _ready() -> void:
	_autoplay = "--autoplay" in OS.get_cmdline_user_args()
	if _autoplay:
		print("[Mobius GameDev] Autopilot on — collecting stars.")


func _physics_process(_delta: float) -> void:
	var dir := Vector2.ZERO
	if _autoplay:
		dir = _autoplay_dir()
	else:
		dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = dir * SPEED
	move_and_slide()


func _autoplay_dir() -> Vector2:
	var nearest: Node2D = null
	var nearest_d := INF
	for n in get_tree().get_nodes_in_group("stars"):
		if n is Node2D:
			var d := global_position.distance_squared_to((n as Node2D).global_position)
			if d < nearest_d:
				nearest_d = d
				nearest = n as Node2D
	if nearest == null:
		return Vector2.ZERO
	return global_position.direction_to(nearest.global_position)
