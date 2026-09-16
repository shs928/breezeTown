extends RefCounted
## World X/Z height contract shared by visual bridges and walking actors.
static func deck_height(at: Vector2, bridges: Array, ramps: Array = []) -> float:
	for bridge: Dictionary in bridges:
		var rect: Rect2 = bridge["rect"]
		if not rect.has_point(at):
			continue
		if not bridge.get("stone", false):
			return 0.14
		var along_x: bool = bridge.get("axis", "x" if rect.size.x >= rect.size.y else "z") == "x"
		var t: float = (at.x - rect.position.x) / rect.size.x if along_x else (at.y - rect.position.y) / rect.size.y
		return 0.09 + sin(t * PI) * float(bridge.get("rise", 0.52))
	for ramp: Dictionary in ramps:
		var rect: Rect2 = ramp["rect"]
		if rect.has_point(at):
			return clampf((rect.end.y - at.y) / rect.size.y, 0, 1) * float(ramp["rise"])
	return 0.0
