extends Node3D
## Nearby forest chunks, with shared imported GLB meshes. No scene-wide dense mesh grid.
const D:=preload("res://scripts/data/first_map_definition.gd")
const Trees:=preload("res://scripts/art/tree_models.gd")
const CHUNK:=64.0
var player:Node3D
var map:RefCounted
var definition:Dictionary
var _mask:Image
var _chunks:Dictionary={}
var _sector:=Vector2i(2147483647,2147483647)
var _parts:Dictionary={}
var _timer:=0.0
func configure(actor:Node3D,spatial:RefCounted,layout:Dictionary)->void:
	player=actor;map=spatial;definition=layout
	_mask=load("res://resources/maps/forest_mask.png").get_image()
	for species in ["pine","oak"]:
		var model:=Trees.build(species)
		var parts:Array=[]
		for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			var transform:=mesh.transform
			var parent:=mesh.get_parent()
			while parent!=model:
				transform=parent.transform*transform;parent=parent.get_parent()
			parts.append({"mesh":mesh.mesh,"transform":transform})
		_parts[species]=parts;model.free()
	_refresh()
func _process(delta:float)->void:
	if not is_visible_in_tree():return
	_timer-=delta
	if _timer>0 or not is_instance_valid(player):return
	_timer=.4
	_refresh()
func _refresh()->void:
	var sector:=Vector2i(floori(player.position.x/CHUNK),floori(player.position.z/CHUNK))
	if sector==_sector:return
	_sector=sector
	var needed:Dictionary={}
	for z in range(-1,2):
		for x in range(-1,2):needed[sector+Vector2i(x,z)]=true
	for key:Vector2i in _chunks.keys():
		if not needed.has(key):
			for id:int in _chunks[key].get_meta("occupancy",[]):map.release_resource(id)
			_chunks[key].queue_free();_chunks.erase(key)
	for key:Vector2i in needed:
		if not _chunks.has(key):_chunks[key]=_build_chunk(key)
func _build_chunk(key:Vector2i)->Node3D:
	var root:=Node3D.new();root.name="Forest_%d_%d"%[key.x,key.y]
	root.position=Vector3(key.x*CHUNK,0,key.y*CHUNK);add_child(root)
	var transforms:Dictionary={"pine":[],"oak":[]}
	var ids:Array[int]=[]
	var rng:=RandomNumberGenerator.new();rng.seed=hash(key)
	var collision:=StaticBody3D.new();root.add_child(collision)
	for z in range(8):
		for x in range(8):
			var at:=Vector2(key)*CHUNK+Vector2(x*8+rng.randf_range(1,7),z*8+rng.randf_range(1,7))
			var pixel:=at/D.METERS_PER_PIXEL+D.ORIGIN
			var uv:=pixel/Vector2(1312,1199)
			if uv.x<0 or uv.x>=1 or uv.y<0 or uv.y>=1:continue
			if _mask.get_pixel(clampi(int(uv.x*_mask.get_width()),0,_mask.get_width()-1),clampi(int(uv.y*_mask.get_height()),0,_mask.get_height()-1)).r<.28:continue
			if map.is_water(at,2.5) or not map.is_walkable(at,2.0):continue
			var on_road:=false
			for path:Dictionary in map.blocked_paths:
				if at.distance_to(Geometry2D.get_closest_point_to_segment(at,path["from"],path["to"]))<path["width"]*.5+2.0:on_road=true;break
			if on_road:continue
			var species:="pine" if rng.randf()<.63 else "oak"
			var local:=Vector3(at.x-key.x*CHUNK,0,at.y-key.y*CHUNK)
			var transform:=Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*rng.randf_range(.90,1.55)),local)
			transforms[species].append(transform)
			var shape:=CollisionShape3D.new();var capsule:=CylinderShape3D.new();capsule.radius=.32;capsule.height=2.0
			shape.shape=capsule;shape.position=local+Vector3(0,1,0);collision.add_child(shape)
			var id:int=hash("forest:%s:%d:%d"%[key,x,z]);ids.append(id);map.occupy_resource(id,at,.35)
	for species:String in transforms:
		if transforms[species].is_empty():continue
		for part:Dictionary in _parts[species]:
			var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=part["mesh"];multi.instance_count=transforms[species].size()
			for index in range(multi.instance_count):multi.set_instance_transform(index,transforms[species][index]*part["transform"])
			var instance:=MultiMeshInstance3D.new();instance.multimesh=multi;root.add_child(instance)
	root.set_meta("occupancy",ids)
	return root

func reset()->void:
	for chunk:Node3D in _chunks.values():
		for id:int in chunk.get_meta("occupancy",[]):map.release_resource(id)
		chunk.free()
	_chunks.clear()
	_sector=Vector2i(2147483647,2147483647)
	_refresh()
