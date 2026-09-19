extends RefCounted

const STEP_SECONDS := 0.025
const FIGHT_SECONDS := 24.0
const BREAK_TENSION := 0.92
const BREAK_SECONDS := 0.55
const SLACK_TENSION := 0.04
const SLACK_SECONDS := 1.0

var phase := "idle"
var remaining := 0.0
var tension := 0.0
var progress := 0.0
var elapsed := 0.0

var _difficulty := 1
var _behavior := "steady"
var _bite_bonus := 0.0
var _progress_factor := 1.0
var _tension_factor := 1.0
var _fight_elapsed := 0.0
var _controlled_seconds := 0.0
var _break_elapsed := 0.0
var _slack_elapsed := 0.0


func start(difficulty: int, wait_seconds: float, behavior: String = "steady", skill_level: int = 1) -> void:
	cancel()
	_difficulty = clampi(difficulty, 1, 3)
	_behavior = behavior if behavior in ["steady", "dart", "surge"] else "steady"
	var skill_steps := float(clampi(skill_level, 1, 10) - 1)
	_bite_bonus = skill_steps * 0.05
	_progress_factor = 1.0 + 0.18 * skill_steps / 9.0
	_tension_factor = 1.0 - 0.15 * skill_steps / 9.0
	remaining = clampf(wait_seconds, 0.0, 10.0) if is_finite(wait_seconds) else 2.0
	phase = "cast"


func reel() -> bool:
	if phase != "bite":
		return false
	phase = "fight"
	remaining = FIGHT_SECONDS
	tension = 0.32
	progress = 0.10
	return true


func tick(delta: float, reeling: bool) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	# A complete encounter lasts less than 36 seconds; this also bounds a stalled frame.
	var pending := minf(delta, 60.0)
	while pending > 0.0 and phase in ["cast", "bite", "fight"]:
		if phase == "cast" and remaining <= 0.000001:
			phase = "bite"
			remaining = 1.6 - 0.2 * _difficulty + _bite_bonus
			continue
		var step := minf(pending, STEP_SECONDS)
		step = minf(step, remaining)
		elapsed += step
		remaining = maxf(0.0, remaining - step)
		pending = maxf(0.0, pending - step)
		match phase:
			"cast":
				if remaining <= 0.000001:
					phase = "bite"
					remaining = 1.6 - 0.2 * _difficulty + _bite_bonus
			"bite":
				if remaining <= 0.000001:
					phase = "escaped"
			"fight":
				_tick_fight(step, reeling)


func _tick_fight(delta: float, reeling: bool) -> void:
	_fight_elapsed += delta
	var difficulty_offset := float(_difficulty - 1)
	var pull := _pull_strength()
	if reeling:
		tension += delta * (0.30 + difficulty_offset * 0.055 + pull) * _tension_factor
		progress += delta * (0.27 - difficulty_offset * 0.025) * _progress_factor
	else:
		tension -= delta * 0.44
		progress -= delta * (0.04 + difficulty_offset * 0.01)
	tension = clampf(tension, 0.0, 1.0)
	progress = clampf(progress, 0.0, 1.0)
	if tension >= 0.2 and tension <= 0.8:
		_controlled_seconds += delta
	_break_elapsed = _break_elapsed + delta if tension >= BREAK_TENSION else 0.0
	_slack_elapsed = _slack_elapsed + delta if tension <= SLACK_TENSION else 0.0
	if _break_elapsed >= BREAK_SECONDS or _slack_elapsed >= SLACK_SECONDS or remaining <= 0.000001:
		phase = "escaped"
	elif progress >= 1.0:
		phase = "caught"


func _pull_strength() -> float:
	match _behavior:
		"dart":
			return 0.015 + 0.16 * pow(maxf(0.0, sin(_fight_elapsed * (5.2 + 0.6 * _difficulty))), 6.0)
		"surge":
			return 0.018 + 0.10 * pow(0.5 + 0.5 * sin(_fight_elapsed * (1.25 + 0.15 * _difficulty) - PI * 0.5), 2.0)
	return 0.03 * (1.0 + sin(_fight_elapsed * (1.8 + 0.3 * _difficulty)))


func control_score() -> float:
	return clampf(_controlled_seconds / _fight_elapsed, 0.0, 1.0) if _fight_elapsed > 0.0 else 0.0


func cancel() -> void:
	phase = "idle"
	remaining = 0.0
	tension = 0.0
	progress = 0.0
	elapsed = 0.0
	_fight_elapsed = 0.0
	_controlled_seconds = 0.0
	_break_elapsed = 0.0
	_slack_elapsed = 0.0
