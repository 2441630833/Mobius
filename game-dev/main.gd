extends Node2D

const STAR_SCENE := preload("res://star.tscn")
const BONUS_STAR_SCENE := preload("res://bonus_star.tscn")
const GameStateScript := preload("res://game_state.gd")

var _state
@onready var _hud: Label = $HUD/Score


func _ready() -> void:
	_state = GameStateScript.new()
	_update_hud()
	_spawn_star()
	_spawn_bonus_star()
	print("[Mobius GameDev] Star Catcher ready. Arrow keys to move. Collect %d stars to win." % _state.WIN_SCORE)


func _spawn_star() -> void:
	var star := STAR_SCENE.instantiate()
	var rect := get_viewport_rect().size
	var max_x: float = max(rect.x - 40.0, 80.0)
	var max_y: float = max(rect.y - 40.0, 80.0)
	star.position = Vector2(randf_range(40.0, max_x), randf_range(40.0, max_y))
	star.collected.connect(_on_star_collected)
	add_child(star)


func _spawn_bonus_star() -> void:
	var bonus := BONUS_STAR_SCENE.instantiate()
	var rect := get_viewport_rect().size
	bonus.position = Vector2(rect.x * 0.75, rect.y * 0.25)
	bonus.collected.connect(_on_bonus_star_collected)
	add_child(bonus)


func _on_bonus_star_collected() -> void:
	_state.collect_bonus_star()
	_update_hud()
	print("[Mobius GameDev] Bonus star! Score: %d" % _state.score)
	if _state.is_won():
		print("[Mobius GameDev] YOU WIN")
		_hud.text = "You win! Score: %d" % _state.score
		if DisplayServer.get_name() == "headless":
			get_tree().call_deferred("quit", 0)


func _on_star_collected() -> void:
	_state.collect_star()
	_update_hud()
	print("[Mobius GameDev] Score: %d" % _state.score)
	if _state.is_won():
		print("[Mobius GameDev] YOU WIN")
		_hud.text = "You win! Score: %d" % _state.score
		if DisplayServer.get_name() == "headless":
			get_tree().call_deferred("quit", 0)
	else:
		call_deferred("_spawn_star")


func _update_hud() -> void:
	_hud.text = "Score: %d / %d" % [_state.score, _state.WIN_SCORE]
