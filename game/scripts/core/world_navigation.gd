extends RefCounted
## 由 MapData 驱动的地表路径服务；不依赖场景树，供动物与后续 NPC 共用。
const MapData := preload("res://scripts/core/map_data.gd")
const CELL := 1.0
const RADIUS := 0.4
var map: MapData
var _grid := AStarGrid2D.new()
var _revision := -1
var _cell:=1.0


func configure(data: MapData) -> void:
	map = data
	_revision = -1


func _ensure_grid(from:Vector3 = Vector3.ZERO,to:Vector3 = Vector3.ZERO) -> void:
	if map==null:return
	var area:Rect2
	if map.bounds_half.x<=200:
		area=Rect2(-map.bounds_half,map.bounds_half*2)
	else:
		var a:=Vector2(from.x,from.z)
		var b:=Vector2(to.x,to.z)
		area=Rect2(a,Vector2.ZERO).expand(b).grow(24)
		# Nearby animal routes share a stable local grid instead of rebuilding for
		# each slightly different target. Keep long requests bounded as before.
		if maxf(area.size.x,area.size.y)<120:
			var anchor:Vector2=(a/64.0).floor()*64.0
			var local_area:=Rect2(anchor-Vector2.ONE*48,Vector2.ONE*160)
			if local_area.encloses(Rect2(a,Vector2.ZERO).expand(b).grow(8)):
				area=local_area
		area=area.intersection(Rect2(-map.bounds_half,map.bounds_half*2))
	var cell:=maxf(1.0,ceilf(maxf(area.size.x,area.size.y)/192.0))
	var first:=Vector2i((area.position/cell).floor())
	var end:=Vector2i((area.end/cell).ceil())
	var region:=Rect2i(first,end-first+Vector2i.ONE)
	if _revision==map.navigation_revision and _grid.region==region and is_equal_approx(_cell,cell):return
	_cell=cell
	_grid.region=region
	_grid.cell_size=Vector2.ONE*_cell
	_grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_NEVER
	_grid.update()
	for x in range(region.position.x,region.end.x):
		for y in range(region.position.y,region.end.y):
			_grid.set_point_solid(Vector2i(x,y),not map.is_walkable(Vector2(x,y)*_cell,RADIUS))
	_revision=map.navigation_revision


func nearest_open(at: Vector3, max_distance: float = 8.0) -> Vector3:
	var requested_key:=Vector2i(roundi(at.x/_cell),roundi(at.z/_cell))
	if _revision!=map.navigation_revision or not _grid.region.has_point(requested_key):_ensure_grid(at,at)
	var key := Vector2i(roundi(at.x / _cell), roundi(at.z / _cell))
	var best := Vector3(INF, 0, INF)
	var distance := max_distance + 0.001
	var span := ceili(max_distance / _cell)
	for x in range(-span, span + 1):
		for y in range(-span, span + 1):
			var next := key + Vector2i(x, y)
			if not _grid.is_in_boundsv(next) or _grid.is_point_solid(next):
				continue
			var point := Vector3(next.x * _cell, 0, next.y * _cell)
			if point.distance_to(at) < distance:
				distance = point.distance_to(at)
				best = point
	return best


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	_ensure_grid(from,to)
	var start := nearest_open(from, 2.0)
	var end := nearest_open(to, 2.0)
	var path := PackedVector3Array()
	if not is_finite(start.x) or not is_finite(end.x):
		return path
	# 不把隔着河岸/围栏的“最近格”当作可达入口。
	if not map.segment_is_walkable(Vector2(from.x, from.z), Vector2(start.x, start.z), RADIUS):
		return path
	if not map.segment_is_walkable(Vector2(end.x, end.z), Vector2(to.x, to.z), RADIUS):
		return path
	var points := _grid.get_point_path(Vector2i(roundi(start.x / _cell), roundi(start.z / _cell)), Vector2i(roundi(end.x / _cell), roundi(end.z / _cell)))
	if points.is_empty():
		return path
	path.append(from)
	for point in points:
		var previous := Vector2(path[-1].x, path[-1].z)
		if not map.segment_is_walkable(previous, point, RADIUS):
			return PackedVector3Array()
		path.append(Vector3(point.x, 0, point.y))
	path.append(to)
	return path
