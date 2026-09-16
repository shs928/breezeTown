extends SceneTree
## 地图规则/桥梁连通/动态资源障碍/存档迁移的无场景测试。
const MapData := preload("res://scripts/core/map_data.gd")
const Navigation := preload("res://scripts/core/world_navigation.gd")
const Restore := preload("res://scripts/core/map_restore.gd")
var failures: Array[String] = []
var count := 0


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, value: bool) -> void:
	count += 1
	if not value:
		failures.append(label)
	print("MAP_DOMAIN %s %s" % [label, "OK" if value else "FAIL"])


func _world() -> Dictionary:
	return {"bounds": {"half": Vector2(18, 18), "pow": 6}, "landmarks": {"spawn": Vector3(-10, 0, 0)}, "sites": [], "obstacles": [],
		"blocked": {"rects": [], "circles": [], "paths": []}, "pasture": Rect2(-15, 8, 6, 6),
		"definition": {"id": "test", "revision": 2, "farm": Rect2(-15, -14, 8, 8),
		"waters": [{"id": "river", "polygon": PackedVector2Array([Vector2(-2, -18), Vector2(2, -18), Vector2(2, 18), Vector2(-2, 18)])}],
		"bridges": [{"id": "bridge", "rect": Rect2(-4, -9, 8, 4)}], "docks": [{"id": "dock", "rect": Rect2(-4, 4, 3, 3)}]}}


func _run() -> void:
	var world := _world()
	var map := MapData.new()
	map.load_from_world(world)
	check("water-cannot-walk", not map.is_walkable(Vector2.ZERO))
	check("bridge-can-walk", map.is_walkable(Vector2(0, -7)))
	check("bridge-cannot-till", not map.is_open(Vector2i(0, -4)))
	check("dock-can-walk", map.is_walkable(Vector2(-1.6, 5)))
	check("dock-cannot-till", not map.is_open(Vector2i(-1, 3)))
	check("bank-footprint-protected", not map.is_open(Vector2i(-1, 0)))
	check("open-grass-tillable", map.is_open(Vector2i(-5, 0)))
	check("boundary-rejects-outside", not map.is_walkable(Vector2(19, 0)))
	var collisions := map.water_collision_rects()
	check("water-collision-present", collisions.any(func(rect: Rect2): return rect.has_point(Vector2.ZERO)))
	check("bridge-no-water-collision", not collisions.any(func(rect: Rect2): return rect.has_point(Vector2(0, -7))))
	var nav := Navigation.new()
	nav.configure(map)
	var path := nav.find_path(Vector3(-10, 0, 0), Vector3(10, 0, 0))
	check("route-crosses-via-bridge", not path.is_empty() and Array(path).any(func(at: Vector3): return at.z <= -6 and absf(at.x) < 2))
	var valid := true
	for at in path:
		valid = valid and map.is_walkable(Vector2(at.x, at.z), Navigation.RADIUS)
	check("route-never-enters-water", valid)
	map.bridges.clear()
	map.navigation_revision += 1
	check("no-bridge-no-crossing", nav.find_path(Vector3(-10, 0, 0), Vector3(10, 0, 0)).is_empty())
	map.load_from_world(world)
	var at := Vector2(-10, 0)
	map.occupy_resource(91, at, 1.1)
	check("resource-blocks-navigation", not map.is_walkable(at))
	map.release_resource(91)
	check("resource-removal-opens-route", map.is_walkable(at) and not nav.find_path(Vector3(-10, 0, 0), Vector3(10, 0, 0)).is_empty())
	var saved := {"ok": true, "economy": {"coins": 123}, "farm": {"tiles": [
		{"key": [0, 0], "state": "planted", "crop": "pumpkin", "stage": 3, "watered": true},
		{"key": [-6, -5], "state": "planted", "crop": "radish", "stage": 1, "watered": false}]}, "pastures": {"pastures": []}}
	var migrated := Restore.plan(saved, world)
	check("legacy-migration-succeeds", migrated["ok"] and migrated["map"]["revision"] == 2)
	check("migration-conserves-economy-and-crops", migrated["economy"]["coins"] == 123 and migrated["farm"]["tiles"].size() == 2)
	var pumpkin: Dictionary = migrated["farm"]["tiles"].filter(func(entry: Dictionary): return entry["crop"] == "pumpkin")[0]
	check("migration-conserves-growth-water", pumpkin["stage"] == 3 and pumpkin["watered"])
	check("migration-avoids-new-water", map.is_open(Vector2i(pumpkin["key"][0], pumpkin["key"][1])))
	check("migration-does-not-mutate-source", saved["farm"]["tiles"][0]["key"] == [0, 0] and saved["pastures"]["pastures"].is_empty())
	var again := Restore.plan(migrated, world)
	check("migration-idempotent", again["relocated"] == 0 and again["farm"] == migrated["farm"])
	print("MAP_DOMAIN_RESULT %s %d checks" % ["PASS" if failures.is_empty() else "FAIL " + ",".join(failures), count])
	quit(0 if failures.is_empty() else 1)
