extends SceneTree
# Headless test runner used by the Godot `godot_test` tool.
# Run: godot --headless --path . --script res://tests/test_runner.gd

var _passed := 0
var _failed := 0
var _assertions := 0


func _initialize() -> void:
	test_sample()
	test_node_creation()
	test_game_state_win()
	test_scripts_load()
	test_main_scene()
	test_star_group()
	test_bonus_star()
	_finish()


func check(cond: bool, label: String) -> void:
	_assertions += 1
	if cond:
		_passed += 1
		print("PASS: " + label)
	else:
		_failed += 1
		printerr("FAIL: " + label)


func _finish() -> void:
	print("TESTS: %d passed, %d failed, %d assertions" % [_passed, _failed, _assertions])
	quit(1 if _failed > 0 else 0)


func test_sample() -> void:
	check(1 + 1 == 2, "sample arithmetic")


func test_node_creation() -> void:
	var n := Node.new()
	check(n != null, "Node.new() returns an instance")
	n.free()


func test_game_state_win() -> void:
	var script = load("res://game_state.gd")
	check(script != null, "game_state.gd loads")
	var state = script.new()
	check(state.score == 0, "score starts at 0")
	check(state.lives == 3, "lives start at 3")
	check(not state.is_won(), "not won at start")
	for i in 5:
		state.collect_star()
	check(state.score == 5, "five collects → score 5")
	check(state.is_won(), "won at WIN_SCORE")
	state.hit()
	check(state.lives == 2, "hit decrements lives")


func test_scripts_load() -> void:
	check(load("res://player.gd") != null, "player.gd loads")
	check(load("res://star.gd") != null, "star.gd loads")
	check(load("res://main.gd") != null, "main.gd loads")
	check(load("res://star.tscn") != null, "star.tscn loads")


func test_main_scene() -> void:
	var packed = load("res://main.tscn")
	check(packed != null, "main.tscn loads")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	check(scene.get_node_or_null("Player") != null, "Player node exists")
	check(scene.get_node_or_null("HUD/Score") != null, "HUD Score label exists")
	scene.free()


func test_star_group() -> void:
	var packed = load("res://star.tscn")
	check(packed != null, "star.tscn loads for group test")
	if packed == null:
		return
	var star: Node = packed.instantiate()
	root.add_child(star)
	check(star.is_in_group("stars"), "star joins stars group")
	star.free()


func test_bonus_star() -> void:
	check(load("res://bonus_star.gd") != null, "bonus_star.gd loads")
	check(load("res://bonus_star.tscn") != null, "bonus_star.tscn loads")
	var script = load("res://game_state.gd")
	var state = script.new()
	state.collect_bonus_star()
	check(state.score == 2, "bonus star adds 2 to score")
	var packed = load("res://bonus_star.tscn")
	if packed == null:
		return
	var bonus: Node = packed.instantiate()
	root.add_child(bonus)
	check(bonus.is_in_group("bonus_stars"), "bonus star joins bonus_stars group")
	check(bonus.is_in_group("stars"), "bonus star joins stars group for autopilot")
	bonus.free()
