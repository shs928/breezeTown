extends Node3D
## Nearby forest chunks, with shared imported GLB meshes. No scene-wide dense mesh grid.
## WORLD-01：分块森林是可砍伐资源。稳定 ID 决定同一棵树跨区块加载/存档后仍是同一棵；
## 只有玩家造成的差异（已移除）进入存档，生成默认值保持确定性。
const D:=preload("res://scripts/data/first_map_definition.gd")
const Trees:=preload("res://scripts/art/tree_models.gd")
const M:=preload("res://scripts/art/art_mesh.gd")
const CHUNK:=64.0
const TREE_HP:=36
const AXE_DAMAGE:=18
const REACH:=2.4
signal tree_broken(species:String,at:Vector3)
var player:Node3D
var map:RefCounted
var definition:Dictionary
var farm_tiles  # FarmState；环境树不得覆盖已保存耕地
var removed:Dictionary={}  # 稳定 ID（字符串）-> true；JSON 往返安全
var _mask:Image
var _orchard:=Rect2()
var _chunks:Dictionary={}
var _registry:Dictionary={}  # int 稳定 ID -> {position,chunk,species,hp}
var _sector:=Vector2i(2147483647,2147483647)
var _queue:Array[Vector2i]=[]  # PERF-02：待建区块队列（近处优先，每帧最多一个）
var _needed_keys:Dictionary={}
var _parts:Dictionary={}
var _timer:=0.0
var _focus_ring:MeshInstance3D

func configure(actor:Node3D,spatial:RefCounted,layout:Dictionary)->void:
	player=actor;map=spatial;definition=layout
	_mask=load("res://resources/maps/forest_mask.png").get_image()
	for region:Dictionary in layout.get("regions",[]):
		if region["id"]=="orchard":_orchard=region["rect"]
	for species in ["pine","oak","apple"]:
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
	# PERF-02：待建区块每帧最多建一个，把跨区传送的重建尖峰摊平。
	if not _queue.is_empty():
		var key:Vector2i=_queue.pop_front()
		if _needed_keys.has(key) and not _chunks.has(key):_chunks[key]=_build_chunk(key)
	_timer-=delta
	if _timer>0 or not is_instance_valid(player):return
	_timer=.4
	_refresh()
func _refresh(force_all:bool=false)->void:
	var sector:=Vector2i(floori(player.position.x/CHUNK),floori(player.position.z/CHUNK))
	if sector==_sector and _queue.is_empty():return
	_sector=sector
	var needed:Dictionary={}
	for z in range(-1,2):
		for x in range(-1,2):needed[sector+Vector2i(x,z)]=true
	for key:Vector2i in _chunks.keys():
		if not needed.has(key):_free_chunk(key)
	_needed_keys=needed
	var missing:Array=[]
	for key:Vector2i in needed:
		if not _chunks.has(key):missing.append(key)
	missing.sort_custom(func(a:Vector2i,b:Vector2i)->bool:
		var center:=Vector3((float(sector.x)+.5)*CHUNK,0,(float(sector.y)+.5)*CHUNK)
		var da:Vector3=Vector3((a.x+.5)*CHUNK,0,(a.y+.5)*CHUNK)-center
		var db:Vector3=Vector3((b.x+.5)*CHUNK,0,(b.y+.5)*CHUNK)-center
		return da.length_squared()<db.length_squared())
	_queue.clear()
	# 无头测试与显式 force_all 保持同步整建；交互模式先建玩家所在块，其余排队。
	if force_all or DisplayServer.get_name()=="headless":
		for key:Vector2i in missing:_chunks[key]=_build_chunk(key)
	elif not missing.is_empty():
		_chunks[missing[0]]=_build_chunk(missing[0])
		for index in range(1,missing.size()):_queue.append(missing[index])
func _free_chunk(key:Vector2i)->void:
	var chunk:Node3D=_chunks.get(key)
	if chunk==null:return
	for id:int in chunk.get_meta("occupancy",[]):
		map.release_resource(id)
		_registry.erase(id)
	chunk.queue_free()
	_chunks.erase(key)
func _build_chunk(key:Vector2i)->Node3D:
	var root:=Node3D.new();root.name="Forest_%d_%d"%[key.x,key.y]
	root.position=Vector3(key.x*CHUNK,0,key.y*CHUNK);add_child(root)
	var transforms:Dictionary={"pine":[],"oak":[],"apple":[]}
	var ids:Array[int]=[]
	var rng:=RandomNumberGenerator.new();rng.seed=hash(key)
	var collision:=StaticBody3D.new();root.add_child(collision)
	for z in range(8):
		for x in range(8):
			var at:=Vector2(key)*CHUNK+Vector2(x*8+rng.randf_range(1,7),z*8+rng.randf_range(1,7))
			if _orchard.has_point(at):continue
			var pixel:=at/D.METERS_PER_PIXEL+D.ORIGIN
			var uv:=pixel/Vector2(1312,1199)
			if uv.x<0 or uv.x>=1 or uv.y<0 or uv.y>=1:continue
			if _mask.get_pixel(clampi(int(uv.x*_mask.get_width()),0,_mask.get_width()-1),clampi(int(uv.y*_mask.get_height()),0,_mask.get_height()-1)).r<.28:continue
			_register_tree(root,collision,transforms,ids,rng,key,at,"pine" if rng.randf()<.63 else "oak",rng.randf_range(.90,1.55),"forest:%s:%d:%d"%[key,x,z])
	# 果园行栽：世界对齐 13 米网格让相邻区块接缝整齐，行内轻抖动保持手绘感。
	if _orchard.intersects(Rect2(Vector2(key)*CHUNK,Vector2.ONE*CHUNK)):
		var area:=_orchard.intersection(Rect2(Vector2(key)*CHUNK,Vector2.ONE*CHUNK))
		var gx0:=ceilf(area.position.x/13.0)*13.0
		var gz0:=ceilf(area.position.y/13.0)*13.0
		for gx in range(int(gx0),int(area.end.x)+1,13):
			for gz in range(int(gz0),int(area.end.y)+1,13):
				var at:=Vector2(gx+rng.randf_range(-.9,.9),gz+rng.randf_range(-.9,.9))
				if not _orchard.grow(-1.5).has_point(at):continue
				_register_tree(root,collision,transforms,ids,rng,key,at,"apple",rng.randf_range(.92,1.22),"orchard:%d:%d"%[int(round(at.x/13.0)),int(round(at.y/13.0))])
	for species:String in transforms:
		if transforms[species].is_empty():continue
		for part:Dictionary in _parts[species]:
			var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=part["mesh"];multi.instance_count=transforms[species].size()
			for index in range(multi.instance_count):multi.set_instance_transform(index,transforms[species][index]*part["transform"])
			var instance:=MultiMeshInstance3D.new();instance.multimesh=multi;root.add_child(instance)
	root.set_meta("occupancy",ids)
	return root

func _register_tree(root:Node3D,collision:StaticBody3D,transforms:Dictionary,ids:Array[int],rng:RandomNumberGenerator,key:Vector2i,at:Vector2,species:String,scale_value:float,stable:String)->void:
	var id:int=hash(stable)
	if removed.has(stable):return
	if map.is_water(at,2.5) or not map.is_walkable(at,2.0):return
	for path:Dictionary in map.blocked_paths:
		if at.distance_to(Geometry2D.get_closest_point_to_segment(at,path["from"],path["to"]))<path["width"]*.5+2.0:return
	# 环境树不覆盖已保存耕地：树冠半径避让 3×3 耕格。
	if farm_tiles!=null:
		var tile_key:=Vector2i(roundi(at.x/2.0),roundi(at.y/2.0))
		for d in [Vector2i.ZERO,Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1),Vector2i(1,1),Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1)]:
			if farm_tiles.tiles.has(tile_key+d):return
	for site:Dictionary in definition.get("buildings",[]):
		if at.distance_to(site["position"])<14.0 and species=="apple":return
	var local:=Vector3(at.x-key.x*CHUNK,0,at.y-key.y*CHUNK)
	var transform:=Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale_value),local)
	transforms[species].append(transform)
	var shape:=CollisionShape3D.new();var capsule:=CylinderShape3D.new();capsule.radius=.32;capsule.height=2.0
	shape.shape=capsule;shape.position=local+Vector3(0,1,0);collision.add_child(shape)
	ids.append(id)
	_registry[id]={"position":at,"chunk":key,"species":species,"stable":stable,"hp":TREE_HP}
	map.occupy_resource(id,at,.35)

## ---- 砍伐：注册表驱动，命中/破坏与 surface 资源同一套手感 ----

func swing(tool:String,from:Vector3,facing:Vector3,power:float=1.0)->int:
	if tool!="axe":return 0
	var dmg:=maxi(1,roundi(AXE_DAMAGE*power))
	var best_id:=-1
	var best:=REACH+0.01
	for id:int in _registry:
		var entry:Dictionary=_registry[id]
		var delta:Vector3=Vector3(entry["position"].x,0,entry["position"].y)-from
		var length:=delta.length()
		if length<best and (length<0.3 or facing.dot(delta.normalized())>=0.57):
			best_id=id;best=length
	if best_id<0:return 0
	var entry:Dictionary=_registry[best_id]
	entry["hp"]=int(entry.get("hp",TREE_HP))-dmg
	if entry["hp"]>0:return dmg
	var species:String=entry["species"]
	var at:Vector3=Vector3(entry["position"].x,0,entry["position"].y)
	removed[str(entry["stable"])]=true
	map.release_resource(best_id)
	_registry.erase(best_id)
	var key:Vector2i=entry["chunk"]
	if _chunks.has(key):
		_free_chunk(key)
		_chunks[key]=_build_chunk(key)
	tree_broken.emit(species,at)
	return dmg

func target_at(at:Vector3,tool:String)->Dictionary:
	clear_focus()
	var best_id:=-1
	var best:=REACH+0.01
	for id:int in _registry:
		var entry:Dictionary=_registry[id]
		var distance:float=at.distance_to(Vector3(entry["position"].x,0,entry["position"].y))
		if distance<best:best_id=id;best=distance
	if best_id<0:return {}
	var entry:Dictionary=_registry[best_id]
	var position:=Vector3(entry["position"].x,0,entry["position"].y)
	if _focus_ring==null:
		_focus_ring=M.torus(self,Vector3.ZERO,0.88,0.022,"#ebd99a","ForestFocus")
		_focus_ring.hide()
	_focus_ring.position=position+Vector3(0,0.055,0)
	_focus_ring.show()
	var hint:="8 换斧头 · 森林大树" if tool!="axe" else "E / 空格 / 左键 砍伐森林大树 · 2 下"
	return {"kind":"chunk_tree","id":best_id,"position":position,"hint":hint}

func clear_focus()->void:
	if _focus_ring!=null:_focus_ring.hide()

func to_dict()->Dictionary:
	return {"removed":removed.keys()}

func apply_state(data:Dictionary)->void:
	removed.clear()
	for stable in data.get("removed",[]):removed[str(stable)]=true
	reset()

func reset()->void:
	for key:Vector2i in _chunks.keys():
		_free_chunk(key)
	_chunks.clear()
	_sector=Vector2i(2147483647,2147483647)
	_refresh()
