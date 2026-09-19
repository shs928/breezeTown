extends SceneTree

const FishingSession := preload("res://scripts/domain/fishing_session.gd")
const FishDB := preload("res://scripts/data/fish_db.gd")

var failures: Array[String] = []
var count := 0


func _initialize() -> void:
	_check_pools()
	_check_conditions()
	_check_timing()
	_check_fights()
	_check_behaviors_and_skill()
	print("FISHING_DOMAIN_RESULT %s %d checks" % ["PASS" if failures.is_empty() else "FAIL " + ",".join(failures), count])
	quit(0 if failures.is_empty() else 1)


func _check_pools() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6082
	for water in ["lake", "river"]:
		_check("supported-" + water, FishDB.supports_water(water))
		var observed := {}
		var allowed := true
		for i in range(1000):
			var fish: String = FishDB.roll(water, rng)
			allowed = allowed and FishDB.FISH.has(fish) and water in FishDB.FISH[fish]["waters"]
			observed[fish] = true
		_check("pool-restricts-" + water, allowed)
		var complete := true
		for fish in FishDB.ORDER:
			if water in FishDB.FISH[fish]["waters"]:
				complete = complete and observed.has(fish)
		_check("pool-includes-rare-" + water, complete)
	for water in ["", "sea", "invalid"]:
		_check("unsupported-pool-" + water, not FishDB.supports_water(water) and FishDB.roll(water, rng) == "")
	rng.seed = 4401
	var first := FishDB.roll("lake", rng)
	rng.seed = 4401
	_check("pool-seed-reproducible", FishDB.roll("lake", rng) == first)


func _check_conditions() -> void:
	var context := {"season": "spring", "weather": "sunny", "hour": 12.0}
	_check("day-lake-pool", FishDB.available("lake", context) == ["sardine", "carp", "koi"])
	_check("day-river-pool", FishDB.available("river", context) == ["sardine", "perch"])
	_check("empty-context-unfiltered", FishDB.available("lake").size() == 4 and FishDB.available("river").size() == 4)
	_check("unknown-fish-ineligible", not FishDB.eligible("unknown", "lake", context))
	_check("unknown-water-empty", FishDB.available("sea", context).is_empty())
	_check("carp-day-start", FishDB.eligible("carp", "lake", {"hour": 6.0}))
	_check("carp-before-day-start", not FishDB.eligible("carp", "lake", {"hour": 5.999}))
	_check("carp-before-day-end", FishDB.eligible("carp", "lake", {"hour": 19.999}))
	_check("carp-day-end-exclusive", not FishDB.eligible("carp", "lake", {"hour": 20.0}))
	_check("perch-end-exclusive", not FishDB.eligible("perch", "river", {"hour": 19.0}))
	_check("perch-no-winter", not FishDB.eligible("perch", "river", {"season": "winter"}))
	_check("catfish-evening-start", FishDB.eligible("catfish", "lake", {"season": "autumn", "weather": "rain", "hour": 18.0}))
	_check("catfish-before-evening", not FishDB.eligible("catfish", "lake", {"hour": 17.999}))
	_check("catfish-storm-river", FishDB.eligible("catfish", "river", {"season": "summer", "weather": "storm", "hour": 23.5}))
	for hour in [0.0, 1.0, 1.999, 24.0, 25.0, 25.999]:
		_check("catfish-midnight-wrap-" + str(hour), FishDB.eligible("catfish", "lake", {"hour": hour}))
	for hour in [2.0, 6.0, 26.0]:
		_check("catfish-night-end-" + str(hour), not FishDB.eligible("catfish", "lake", {"hour": hour}))
	_check("catfish-requires-wet-weather", not FishDB.eligible("catfish", "lake", {"weather": "cloudy"}))
	_check("catfish-no-winter", not FishDB.eligible("catfish", "lake", {"season": "winter"}))
	_check("trout-autumn-start", FishDB.eligible("rainbow_trout", "river", {"season": "autumn", "hour": 6.0}))
	_check("trout-winter-snow", FishDB.eligible("rainbow_trout", "river", {"season": "winter", "weather": "snow", "hour": 17.999}))
	_check("trout-summer-excluded", not FishDB.eligible("rainbow_trout", "river", {"season": "summer"}))
	_check("trout-end-exclusive", not FishDB.eligible("rainbow_trout", "river", {"hour": 18.0}))
	_check("koi-start", FishDB.eligible("koi", "lake", {"season": "spring", "weather": "sunny", "hour": 9.0}))
	_check("koi-before-start", not FishDB.eligible("koi", "lake", {"hour": 8.999}))
	_check("koi-before-end", FishDB.eligible("koi", "lake", {"season": "summer", "weather": "cloudy", "hour": 16.999}))
	_check("koi-end-exclusive", not FishDB.eligible("koi", "lake", {"hour": 17.0}))
	_check("koi-autumn-excluded", not FishDB.eligible("koi", "lake", {"season": "autumn"}))
	_check("koi-rain-excluded", not FishDB.eligible("koi", "lake", {"weather": "rain"}))
	var common_always := true
	for season in FishDB.GameClock.SEASON_KEYS:
		for weather in FishDB.GameClock.WEATHERS:
			for hour in [0.0, 6.0, 12.0, 18.0, 24.0, 25.0, 26.0]:
				for water in ["lake", "river"]:
					var conditions := {"season": season, "weather": weather, "hour": hour}
					common_always = common_always and FishDB.available(water, conditions).has("sardine")
	_check("common-pool-every-clock-season-weather-hour", common_always)
	var invalid: Array[Dictionary] = [{"unknown": 1}, {"season": "fall"}, {"weather": "clear"}, {"season": null}, {"hour": "12"}, {"hour": true}, {"hour": -1}, {"hour": 27.0}, {"hour": INF}, {"hour": NAN}]
	var rng := RandomNumberGenerator.new()
	for index in range(invalid.size()):
		_check("invalid-context-%d" % index, FishDB.available("lake", invalid[index]).is_empty() and FishDB.roll("lake", rng, invalid[index]) == "")
	context = {"season": "winter", "weather": "snow", "hour": 24.0}
	_check("winter-night-fallback-only", FishDB.available("lake", context) == ["sardine"])
	context = {"season": "autumn", "weather": "rain", "hour": 25.0}
	var valid_rolls := true
	var seen := {}
	rng.seed = 9306
	for i in range(500):
		var fish := FishDB.roll("river", rng, context)
		valid_rolls = valid_rolls and FishDB.eligible(fish, "river", context)
		seen[fish] = true
	_check("filtered-roll-pool", valid_rolls and seen.has("catfish") and seen.size() == 2)
	rng.seed = 771
	var first := FishDB.roll("river", rng, context)
	rng.seed = 771
	_check("filtered-roll-reproducible", FishDB.roll("river", rng, context) == first)
	_check("catalog-behaviors", FishDB.behavior("carp") == "steady" and FishDB.behavior("perch") == "dart" and FishDB.behavior("koi") == "surge")


func _check_timing() -> void:
	var session := FishingSession.new()
	_check("idle-reel-rejected", not session.reel())
	session.start(1, 2.0)
	_check("cast-reel-rejected", not session.reel() and session.phase == "cast")
	session.tick(0.0, true)
	session.tick(-1.0, true)
	session.tick(INF, true)
	_check("invalid-delta-no-change", session.remaining == 2.0 and session.elapsed == 0.0)
	session.tick(1.0, false)
	_check("cast-waits", session.phase == "cast" and is_equal_approx(session.remaining, 1.0))
	session.tick(1.1, false)
	_check("cast-enters-bite-with-remainder", session.phase == "bite" and absf(session.remaining - 1.3) < 0.0001)
	session.tick(1.31, false)
	_check("bite-timeout", session.phase == "escaped")
	var ended := session.elapsed
	session.tick(1000.0, true)
	_check("escaped-terminal", session.phase == "escaped" and session.elapsed == ended and not session.reel())
	session.cancel()
	_check("cancel-resets", session.phase == "idle" and session.remaining == 0.0 and session.elapsed == 0.0 and session.tension == 0.0 and session.progress == 0.0)
	session.start(999, -4.0)
	session.tick(0.01, false)
	_check("start-bounds-input", session.phase == "bite" and absf(session.remaining - 0.99) < 0.0001)
	session.start(1, INF)
	_check("invalid-wait-falls-back", session.remaining == 2.0)
	session.tick(1.0e12, false)
	_check("large-delta-times-out", session.phase == "escaped" and session.elapsed < 4.0)


func _check_fights() -> void:
	for difficulty in range(1, 4):
		var session := _hook(difficulty)
		_check("reel-fight-once-%d" % difficulty, session.phase == "fight" and not session.reel())
		var hold := true
		var fight_seconds := 0.0
		var valid := true
		while session.phase == "fight" and fight_seconds < 20.0:
			if session.tension >= 0.72:
				hold = false
			elif session.tension <= 0.45:
				hold = true
			session.tick(0.025, hold)
			fight_seconds += 0.025
			valid = valid and session.tension >= 0.0 and session.tension <= 1.0 and session.progress >= 0.0 and session.progress <= 1.0
		_check("controlled-reeling-wins-%d" % difficulty, session.phase == "caught" and session.progress == 1.0)
		_check("catch-takes-5-to-12-seconds-%d" % difficulty, fight_seconds >= 5.0 and fight_seconds <= 12.0)
		_check("fight-values-bounded-%d" % difficulty, valid)
		print("FISHING_CATCH difficulty=%d seconds=%.2f" % [difficulty, fight_seconds])
		var ended := session.elapsed
		session.tick(100.0, true)
		_check("caught-terminal-%d" % difficulty, session.phase == "caught" and session.elapsed == ended and not session.reel())
		session.start(difficulty, 1.0)
		_check("restart-clears-outcome-%d" % difficulty, session.phase == "cast" and session.progress == 0.0 and session.tension == 0.0 and session.elapsed == 0.0)
		session = _hook(difficulty)
		session.tick(100.0, true)
		_check("held-line-breaks-%d" % difficulty, session.phase == "escaped" and session.tension >= FishingSession.BREAK_TENSION and session.progress < 1.0)
		session = _hook(difficulty)
		session.tick(100.0, false)
		_check("slack-line-loses-%d" % difficulty, session.phase == "escaped" and session.tension <= FishingSession.SLACK_TENSION)
		session = _hook(difficulty)
		var fine_steps := _hook(difficulty)
		session.tick(1.1, true)
		for i in range(110):
			fine_steps.tick(0.01, true)
		_check("coarse-frame-preserves-fight-%d" % difficulty, session.phase == fine_steps.phase and absf(session.tension - fine_steps.tension) < 0.001 and absf(session.progress - fine_steps.progress) < 0.001)
		var paused_elapsed := session.elapsed
		var paused_tension := session.tension
		session.tick(0.0, false)
		_check("zero-delta-preserves-fight-%d" % difficulty, session.elapsed == paused_elapsed and session.tension == paused_tension)
		session = _hook(difficulty)
		session.tick(0.5, true)
		var before_tension := session.tension
		var before_progress := session.progress
		session.tick(0.2, false)
		_check("release-recovers-tension-costs-progress-%d" % difficulty, session.phase == "fight" and session.tension < before_tension and session.progress < before_progress)
		session.cancel()
		_check("cancel-fight-cleans-state-%d" % difficulty, session.phase == "idle" and session.elapsed == 0.0 and session.tension == 0.0 and session.progress == 0.0)


func _check_behaviors_and_skill() -> void:
	for behavior in ["steady", "dart", "surge"]:
		for difficulty in range(1, 4):
			for level in [1, 10]:
				var suffix := "%s-d%d-lv%d" % [behavior, difficulty, level]
				var session := _hook(difficulty, behavior, level)
				_check("new-fight-no-control-time-" + suffix, session.control_score() == 0.0)
				var hold := true
				var fight_seconds := 0.0
				while session.phase == "fight" and fight_seconds < 24.0:
					if session.tension >= 0.72:
						hold = false
					elif session.tension <= 0.45:
						hold = true
					session.tick(0.025, hold)
					fight_seconds += 0.025
				_check("behavior-controllable-" + suffix, session.phase == "caught")
				_check("controlled-score-" + suffix, session.control_score() > 0.99 and session.control_score() <= 1.0)
				var score := session.control_score()
				session.tick(30.0, false)
				_check("caught-retains-score-" + suffix, session.control_score() == score)
				print("FISHING_BEHAVIOR behavior=%s difficulty=%d level=%d seconds=%.2f score=%.3f" % [behavior, difficulty, level, fight_seconds, score])
				session.start(difficulty, 2.0, behavior, level)
				_check("restart-resets-control-score-" + suffix, session.control_score() == 0.0)
				session.tick(1.0, false)
				_check("cast-excluded-from-control-score-" + suffix, session.control_score() == 0.0)
				session = _hook(difficulty, behavior, level)
				session.tick(100.0, true)
				_check("behavior-always-hold-breaks-" + suffix, session.phase == "escaped" and session.progress < 1.0)
				_check("reckless-control-score-lower-" + suffix, session.control_score() >= 0.0 and session.control_score() < 0.9)
				session.cancel()
				_check("cancel-resets-control-score-" + suffix, session.control_score() == 0.0)
	var novice := FishingSession.new()
	var skilled := FishingSession.new()
	novice.start(3, 0.0)
	skilled.start(3, 0.0, "steady", 10)
	novice.tick(0.01, false)
	skilled.tick(0.01, false)
	_check("skill-widens-bite-window", absf(skilled.remaining - novice.remaining - 0.45) < 0.0001)
	novice.reel()
	skilled.reel()
	novice.tick(1.0, true)
	skilled.tick(1.0, true)
	_check("skill-improves-control", skilled.tension < novice.tension and skilled.progress > novice.progress)
	var maximum := _hook(3, "steady", 999)
	maximum.tick(1.0, true)
	_check("skill-bonuses-capped", is_equal_approx(maximum.tension, skilled.tension) and is_equal_approx(maximum.progress, skilled.progress))
	var unknown := _hook(3, "invalid", -1)
	unknown.tick(1.0, true)
	_check("unknown-behavior-and-low-skill-default", is_equal_approx(unknown.tension, novice.tension) and is_equal_approx(unknown.progress, novice.progress))
	var steady := _hook(2, "steady")
	var dart := _hook(2, "dart")
	var surge := _hook(2, "surge")
	steady.tick(0.25, true)
	dart.tick(0.25, true)
	surge.tick(0.25, true)
	_check("behavior-pulls-distinct", absf(steady.tension - dart.tension) > 0.005 and absf(steady.tension - surge.tension) > 0.005 and absf(dart.tension - surge.tension) > 0.005)
	var partly_controlled := _hook(2)
	partly_controlled.tick(0.7, false)
	_check("control-score-measures-safe-fraction", partly_controlled.control_score() > 0.2 and partly_controlled.control_score() < 0.6)


func _hook(difficulty: int, behavior: String = "steady", level: int = 1) -> FishingSession:
	var session := FishingSession.new()
	session.start(difficulty, 0.0, behavior, level)
	session.tick(0.01, false)
	session.reel()
	return session


func _check(label: String, condition: bool) -> void:
	count += 1
	if not condition:
		failures.append(label)
		push_error("FISHING_DOMAIN_CHECK failed: " + label)
