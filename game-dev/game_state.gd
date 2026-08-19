extends RefCounted
## Pure game rules so headless tests can exercise win/lose without Input.
class_name GameState

const WIN_SCORE := 5
const START_LIVES := 3

var score: int = 0
var lives: int = START_LIVES


func collect_star() -> void:
	score += 1


func collect_bonus_star() -> void:
	score += 2


func hit() -> void:
	lives = max(lives - 1, 0)


func is_won() -> bool:
	return score >= WIN_SCORE


func is_lost() -> bool:
	return lives <= 0
