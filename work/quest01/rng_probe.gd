extends SceneTree
const GameState := preload("res://scripts/game_state.gd")
func _initialize() -> void:
	var a := GameState.new()
	var b := GameState.new()
	var seq_a := []
	var seq_b := []
	for i in range(6):
		seq_a.append(a.roll_harvest_quality(true))
		seq_b.append(b.roll_harvest_quality(true))
	print("RNG_PROBE a=", seq_a, " b=", seq_b, " same=", seq_a == seq_b)
	quit(0)
