extends SceneTree
# Headless test runner used by the Godot MCP `godot_test` tool.
# Run: godot --headless --path . --script res://tests/test_runner.gd
# Agent: add more `test_*` functions here and call them from _initialize().

var _passed := 0
var _failed := 0
var _assertions := 0


func _initialize() -> void:
	test_sample()
	test_node_creation()
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
