extends RefCounted
## First playable scale map. Geometry positions come exclusively from the calibrated blueprint.
const D:=preload("res://scripts/data/first_map_definition.gd")
const M:=preload("res://scripts/art/art_mesh.gd")
const L:=preload("res://scripts/art/landscape_models.gd")
const B:=preload("res://scripts/art/building_models.gd")
const Town:=preload("res://scripts/art/town_models.gd")
const Ranch:=preload("res://scripts/ranch_models.gd")
const Assets:=preload("res://scripts/art/authored_assets.gd")
const StoneBridge := preload("res://scripts/art/stone_bridge.gd")

## ---- PERF-02：世界缓存 ----
## root 场景（地形/水系/建筑/装饰/静态合并）按指纹缓存；任何影响构建产物的
## 源文件（脚本/蓝图/GLB/着色器）变化都会使指纹失效并触发重建。
## 数据字典本身很便宜，与场景一起走 var_to_str 往返，保持读档路径一致。

static func _cache_root()->String:
	var override:=OS.get_environment("BREEZETOWN_CACHE_ROOT")
	if not override.is_empty():return override.path_join("willow_creek_valley_v1")
	return "user://cache/willow_creek_valley_v1"

static func _scan_inputs(dir_path:String,exts:Array,out:Array)->void:
	var dir:=DirAccess.open(dir_path)
	if dir==null:return
	dir.list_dir_begin()
	var name:=dir.get_next()
	while name!="":
		var path:=dir_path+"/"+name
		if dir.current_is_dir():
			if not name.begins_with("."):_scan_inputs(path,exts,out)
		else:
			for ext:String in exts:
				if name.ends_with(ext):out.append(path);break
		name=dir.get_next()

static func _fingerprint()->String:
	var paths:=[]
	_scan_inputs("res://scripts",[".gd",".gdshader"],paths)
	_scan_inputs("res://resources/models",[".glb"],paths)
	_scan_inputs("res://resources/maps",[".json"],paths)
	paths.sort()
	var lines:=PackedStringArray()
	for path in paths:lines.append(path+":"+FileAccess.get_md5(path))
	return "\n".join(lines).sha256_text().substr(0,32)

static func build()->Dictionary:
	var fingerprint:=_fingerprint()
	var cached:=_load_cache(fingerprint)
	if not cached.is_empty():
		print("WORLD_CACHE HIT ",cached["root"].get_child_count()," top nodes")
		return cached
	print("WORLD_CACHE MISS")
	var data:=_build_world()
	_store_cache(fingerprint,data)
	return data

static func _load_cache(fingerprint:String)->Dictionary:
	var cache:=_cache_root()
	var mark:=FileAccess.open(cache+"/fingerprint.txt",FileAccess.READ)
	if mark==null or mark.get_as_text().strip_edges()!=fingerprint:return {}
	if not FileAccess.file_exists(cache+"/world.scn") or not FileAccess.file_exists(cache+"/data.var"):return {}
	var scene:PackedScene=load(cache+"/world.scn")
	if scene==null:return {}
	var root:=scene.instantiate()
	if root==null or not root is Node3D:
		if root!=null:root.free()
		return {}
	var payload:Dictionary=str_to_var(FileAccess.open(cache+"/data.var",FileAccess.READ).get_as_text())
	if payload==null or payload.is_empty() or not payload.has("sites"):
		root.free()
		return {}
	payload["root"]=root
	return payload

static func _store_cache(fingerprint:String,data:Dictionary)->void:
	var root:Node3D=data["root"]
	_set_owners(root,root)  # pack() 只收录 owner 指向场景根的节点
	var scene:=PackedScene.new()
	if scene.pack(root)!=OK:return
	var payload:={}
	for key: String in data:
		if key!="root":payload[key]=data[key]
	var dir:=_cache_root()
	DirAccess.make_dir_recursive_absolute(dir)
	ResourceSaver.save(scene,dir+"/world.scn")
	FileAccess.open(dir+"/data.var",FileAccess.WRITE).store_string(var_to_str(payload))
	FileAccess.open(dir+"/fingerprint.txt",FileAccess.WRITE).store_string(fingerprint)
	print("WORLD_CACHE STORED")

static func _set_owners(node:Node,owner_root:Node)->void:
	for child in node.get_children():
		child.owner=owner_root
		_set_owners(child,owner_root)

static func _build_world()->Dictionary:
	var definition:=D.create()
	var root:=Node3D.new();root.name="WillowCreekValley"
	var data:Dictionary={"root":root,"definition":definition,"obstacles":[],"sites":[],"roads":[],"lights":[],"resources":[],"blocked":{"rects":[],"circles":[],"paths":[],"polygons":[]},"reserved":definition["reserved"].duplicate(),"bounds":definition["bounds"],"landmarks":definition["landmarks"],"pasture":definition["pasture"]}
	# NPC ownership protects northeast land from player tilling, planting and fencing.
	# This is a land-use restriction; visitors can still walk through the farm.
	data["blocked"]["rects"].append(definition["ranch"])
	root.add_child(preload("res://scripts/art/first_map_terrain.gd").build(definition))
	for lane:Dictionary in definition["roads"]:
		data["roads"].append(lane)
		root.add_child(preload("res://scripts/art/painted_paths.gd").build(lane["points"],lane["width"],lane["paved"],lane["id"].hash()))
		for i in range(lane["points"].size()-1):data["blocked"]["paths"].append({"from":lane["points"][i],"to":lane["points"][i+1],"width":lane["width"]})
	for building:Dictionary in definition["buildings"]:
		var model:Node3D
		match building["kind"]:
			"cottage":model=Assets.instantiate("res://resources/models/cottage.glb")
			"shop":model=Assets.instantiate("res://resources/models/seed_shop.glb")
			"barn":model=Assets.instantiate("res://resources/models/barn.glb")
			"coop":model=Assets.instantiate("res://resources/models/coop.glb")
			_:model=Town.building(building["kind"])
		model.name=building["id"]
		model.scale*=Vector3(building["factor"],minf(building["factor"],1.75),building["factor"])
		var at:Vector2=building["position"]
		model.position=Vector3(at.x,0,at.y);root.add_child(model)
		data["sites"].append(building)
		data["obstacles"].append({"shape":"box","position":Vector3(at.x,4,at.y),"size":Vector3(building["size"].x,8,building["size"].y)})
		data["blocked"]["rects"].append(Rect2(at-building["size"]*.5,building["size"]))
		data["lights"].append(Vector3(building["door"].x,3,building["door"].y))
	_configure_bridge_openings(definition)
	var waterways := preload("res://scripts/art/water_models.gd").build(definition)
	root.add_child(waterways)
	_build_bridge_collisions(data)
	for water:Dictionary in definition["waters"]:data["blocked"]["polygons"].append(water["polygon"])
	var mine:=preload("res://scripts/art/mine_models.gd").entrance()
	mine.position=definition["landmarks"]["mine_door"]+Vector3(0,0,-4);root.add_child(mine)
	data["obstacles"].append({"shape":"box","position":mine.position+Vector3(0,3,-1),"size":Vector3(11,6,5)})
	data["blocked"]["rects"].append(Rect2(Vector2(mine.position.x-6,mine.position.z-4),Vector2(12,8)))
	_build_square(root,data)
	_build_fields(root,definition)
	_build_landmarks(root,definition)
	_build_farm_garden(root,data)
	_build_town_square_details(root,data)
	_build_harbor_props(root,data)
	_build_npc_homestead(root,data)
	data["navigation"]={"half":definition["bounds"]["half"],"power":definition["bounds"]["pow"],"sites":data["sites"],"roads":data["roads"],"farm":definition["farm"],"ranch":definition["ranch"],"lake_center":definition["lake_center"],"lake_radius":definition["lake_radius"],"mine":Vector2(mine.position.x,mine.position.z),"waters":definition["waters"],"bridges":definition["bridges"],"regions":definition["regions"],"forests":definition["forests"],"docks":definition["docks"],"bounds":definition["bounds"],"map_id":definition["id"],"revision":definition["revision"]}
	preload("res://scripts/art/static_geometry.gd").bake(root)
	return data
static func _build_square(root:Node3D,data:Dictionary)->void:
	var rect:Rect2=data["definition"]["square"]
	var at:=rect.get_center()
	data["blocked"]["rects"].append(rect)
	M.box(root,Vector3(at.x,.018,at.y),Vector3(rect.size.x,.032,rect.size.y),"#aaa18b","TownSquare",0)
	M.cylinder(root,Vector3(at.x,.25,at.y),5.5,5.5,.5,"#aba58f","FountainBase",32)
	M.cylinder(root,Vector3(at.x,.56,at.y),4.9,4.9,.10,"#327f91","FountainWater",32)
	M.torus(root,Vector3(at.x,.70,at.y),5.2,.26,"#c4bda4","FountainRim")
	M.cylinder(root,Vector3(at.x,1.5,at.y),.62,.35,3,"#b7b19b","FountainPillar",16)
	M.cylinder(root,Vector3(at.x,2.8,at.y),1.9,2.0,.26,"#c5bca5","FountainBowl",24)
	data["obstacles"].append({"shape":"sphere","position":Vector3(at.x,.7,at.y),"radius":5.5})
static func _build_fields(root:Node3D,definition:Dictionary)->void:
	for index in range(definition["fields"].size()):
		var field:Rect2=definition["fields"][index]
		var at:=field.get_center()
		var surface:=M.box(root,Vector3(at.x,.025,at.y),Vector3(field.size.x,.04,field.size.y),"#806641","AgriculturalParcel",0)
		surface.material_override=_field_material(field,index)
static func _field_material(field:Rect2,seed_value:int)->ShaderMaterial:
	# 大块农田用世界空间犁地条纹着色：同一平面读出垄向、土块与边缘磨损，不增加面数。
	var material:=ShaderMaterial.new()
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
uniform sampler2D earth;
uniform vec2 dir;
uniform vec2 origin;
uniform vec2 extent;
uniform float seed;
varying vec3 world;
float hash21(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7))+seed)*43758.5453); }
float noise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y); }
void vertex(){ world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
 vec2 p=world.xz;
 float along=dot(p-origin,dir);
 float across=dot(p-origin,vec2(-dir.y,dir.x));
 float rows=sin(across*2.35+seed)*0.5+0.5;
 float clod=noise(p*0.85)*0.6+noise(p*3.2+seed)*0.4;
 vec3 soil=texture(earth,p*0.05).rgb;
 vec3 furrow=soil*vec3(0.58,0.50,0.44);
 vec3 crest=soil*vec3(1.22,1.12,0.98);
 vec3 base=mix(furrow,crest,clamp(rows*(0.5+0.5*clod)+clod*0.18,0.0,1.0));
 float length_along=extent.x*abs(dir.x)+extent.y*abs(dir.y);
 float length_across=extent.x*abs(dir.y)+extent.y*abs(dir.x);
 float edge=min(min(along,length_along-along),min(across,length_across-across));
 base*=mix(0.78,1.0,clamp(edge/1.8,0.0,1.0));
 ALBEDO=base*(0.92+0.16*noise(p*6.5));
 ROUGHNESS=1.0; SPECULAR=0.04;
}
"""
	material.shader=shader
	material.set_shader_parameter("earth",preload("res://resources/materials/terrain/earth.png"))
	material.set_shader_parameter("dir",Vector2(1,0) if field.size.x>=field.size.y else Vector2(0,1))
	material.set_shader_parameter("origin",field.position)
	material.set_shader_parameter("extent",field.size)
	material.set_shader_parameter("seed",float(seed_value%7)*1.37)
	return material
static func _build_farm_garden(root:Node3D,data:Dictionary)->void:
	var at:Vector2=data["definition"]["buildings"][0]["position"]
	var garden:Rect2=data["definition"]["starter_garden"]
	# Keep the depicted north/south fence rows; the garden gate and driveway are real openings.
	data["farm_fences"] = []
	for side in [0, 1]:
		var start := at + Vector2(-25.2, 12 + side * 30)
		var finish := at + Vector2(3.6, 12 + side * 30)
		_build_farm_fence_line(root, data, start, finish, garden.get_center().x)
	for i in range(12):
		var flower:=L.flowers(i%3,true)
		flower.position=Vector3(at.x-25,0,at.y+14+i*2.3);root.add_child(flower)
	for i in range(12):
		var position:=at+Vector2(-30+(i%3)*18,-16-(i/3)*7)
		if i>=9:position=at+Vector2(-31,13+(i-9)*13)
		data["resources"].append({"category":"tree","position":position,"species":"pine" if i%2 else "oak","variant":i%2})
	var well:=L.well();well.position=Vector3(at.x+6,0,at.y+13);well.scale*=1.4;root.add_child(well)
	data["obstacles"].append({"shape":"sphere","position":well.position+Vector3(0,1,0),"radius":1.1})
	data["blocked"]["circles"].append({"position":Vector2(well.position.x,well.position.z),"radius":1.1})

	var garden_art:=preload("res://scripts/art/cozy_landscape.gd")
	var rng:=RandomNumberGenerator.new();rng.seed=732
	for relative in [Vector2(-9,-7),Vector2(8,-6),Vector2(-12,0),Vector2(12,3),Vector2(-25,14),Vector2(-25,23),Vector2(-25,33),Vector2(0,42),Vector2(-15,42),Vector2(17,10),Vector2(16,31)]:
		garden_art._bush(root,at+relative,rng)
	var grass:=SurfaceTool.new();grass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var flowers:=SurfaceTool.new();flowers.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(680):
		var local:=Vector2(rng.randf_range(-29,20),rng.randf_range(-12,46))
		var border:=absf(local.x+25)<2 or absf(local.y-43)<2 or (local.y<0 and absf(local.x)>7)
		if not border:continue
		garden_art._grass(grass,at+local,rng,rng.randf_range(.15,.36))
		if i%3==0:garden_art._flower(grass,flowers,at+local,rng,i%4)
	M.mesh_node(root,grass.commit(),Vector3.ZERO,M.paint("#ffffff"),"FarmBorderGrass")
	M.mesh_node(root,flowers.commit(),Vector3.ZERO,M.paint("#ffffff"),"FarmBorderFlowers")
	_build_farm_homestead(root,data,data["definition"],at,garden)


static func _build_farm_homestead(root:Node3D,data:Dictionary,definition:Dictionary,at:Vector2,garden:Rect2)->void:
	# ART-01：把农舍周边从空旷草坪补成有层次的庭院——成片草花、花境、
	# 农具道具与背景树。纯装饰不设障碍的部分不进 blocked，实心道具走 _place_prop。
	var garden_art:=preload("res://scripts/art/cozy_landscape.gd")
	var trees:=preload("res://scripts/art/tree_models.gd")
	var forest_mask:Image=load("res://resources/maps/forest_mask.png").get_image()
	var rng:=RandomNumberGenerator.new();rng.seed=911
	var yard:=Rect2(at+Vector2(-96,-48),Vector2(200,124))
	var meadow:=SurfaceTool.new();meadow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var petals:=SurfaceTool.new();petals.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(5600):
		var spot:=yard.position+Vector2(rng.randf(),rng.randf())*yard.size
		if sin(spot.x*0.31)+cos(spot.y*0.27)+sin((spot.x+spot.y)*0.11)<-0.5:continue
		if _near_road(data,spot,0.75) or _in_forest(forest_mask,spot):continue
		if garden.grow(-0.7).has_point(spot):continue
		var near_building:=false
		for building:Dictionary in definition["buildings"]:
			if (Rect2(building["position"]-(building["size"] as Vector2)*0.5,building["size"]) as Rect2).grow(0.8).has_point(spot):
				near_building=true;break
		if near_building:continue
		var in_field:=false
		for field:Rect2 in definition["fields"]:
			if field.grow(0.3).has_point(spot):in_field=true;break
		if in_field:continue
		garden_art._grass(meadow,spot,rng,rng.randf_range(0.13,0.34 if spot.distance_to(at+Vector2(0,10))<55.0 else 0.25))
		if i%4==0:garden_art._flower(meadow,petals,spot,rng,i%6)
	# 家门口、井边与围栏转角的花境，让生活区域一眼可读。
	for bed:Rect2 in [Rect2(at+Vector2(-8.6,5.8),Vector2(4.2,1.9)),Rect2(at+Vector2(3.8,5.8),Vector2(4.4,1.9)),Rect2(at+Vector2(-7.4,-3.2),Vector2(1.7,7.6)),Rect2(at+Vector2(-16.8,38.2),Vector2(14.0,1.9)),Rect2(at+Vector2(-17.6,8.8),Vector2(2.2,4.6)),Rect2(at+Vector2(9.0,16.5),Vector2(2.4,5.6))]:
		for k in range(int(bed.get_area()*2.8)):
			var spot:=bed.position+Vector2(rng.randf(),rng.randf())*bed.size
			if _near_road(data,spot,0.55):continue
			garden_art._grass(meadow,spot,rng,rng.randf_range(0.2,0.42))
			garden_art._flower(meadow,petals,spot,rng,k%6)
	var well_at:=Vector2(at.x+6,at.y+13)
	for i in range(12):
		var angle:=i*TAU/12.0+0.26
		var ring:=well_at+Vector2(cos(angle),sin(angle))*2.1
		if _near_road(data,ring,0.5):continue
		garden_art._grass(meadow,ring,rng,rng.randf_range(0.2,0.38))
		garden_art._flower(meadow,petals,ring,rng,(i+2)%6)
	M.mesh_node(root,meadow.commit(),Vector3.ZERO,M.paint("#ffffff"),"FarmMeadowGrass")
	M.mesh_node(root,petals.commit(),Vector3.ZERO,M.paint("#ffffff"),"FarmMeadowFlowers")
	# 围栏转角与畜舍旁的灌木群。
	var barn_at:=Vector2.ZERO;var coop_at:=Vector2.ZERO
	for building:Dictionary in definition["buildings"]:
		if building["id"]=="player_barn":barn_at=building["position"]
		elif building["id"]=="player_coop":coop_at=building["position"]
	for cluster:Vector2 in [at+Vector2(-24.5,13.0),at+Vector2(2.5,13.0),at+Vector2(-24.5,41.0),at+Vector2(3.0,41.0),at+Vector2(-13.0,42.8),at+Vector2(1.5,42.8),at+Vector2(12.5,8.0),coop_at+Vector2(-4.5,-4.0),coop_at+Vector2(5.0,-3.0),coop_at+Vector2(0.5,6.5),barn_at+Vector2(-9.5,-5.5),barn_at+Vector2(8.5,-5.0)]:
		if not _near_road(data,cluster,0.9):garden_art._bush(root,cluster,rng)
	# 生活道具：柴堆、木桶板条箱、邮箱、灯柱、干草捆、水壶与踏石。
	_place_prop(root,data,L.firewood_pile(3),at+Vector2(6.9,0.9),0.75,1.1,-PI/2)
	_place_prop(root,data,L.barrel(),at+Vector2(7.8,3.6),0.42,1.0)
	_place_prop(root,data,L.watering_can(),Vector2(garden.get_center().x-1.6,garden.end.y+1.3),0.0,0.6,2.3)
	var crate:=_place_prop(root,data,L.crate(true),at+Vector2(-6.6,7.9),0.55,1.1,-0.2)
	if crate!=null:
		var extra:=L.crate(false)
		extra.position=Vector3(0.03,0.515,-0.02);extra.rotation.y=0.38
		crate.add_child(extra)
	var gate_x:=garden.get_center().x
	_place_prop(root,data,L.mailbox(),Vector2(gate_x+2.8,at.y+12.6),0.3,1.2)
	for lamp_at:Vector2 in [at+Vector2(3.4,15.9),at+Vector2(1.2,24.5)]:
		var lamp:=_place_prop(root,data,L.lantern_post(),lamp_at,0.3,1.35)
		if lamp!=null:data["lights"].append(Vector3(lamp_at.x,2.4,lamp_at.y))
	if coop_at!=Vector2.ZERO:
		var bale:=_place_prop(root,data,L.hay_bale(5),coop_at+Vector2(4.8,5.8),0.72,1.5,0.35)
		if bale!=null:
			var top:=L.hay_bale(6)
			top.position=Vector3(0.12,1.21,0.04);top.rotation.y=0.5
			bale.add_child(top)
		_place_prop(root,data,L.barrel(),coop_at+Vector2(-3.6,6.2),0.42,1.2)
	if barn_at!=Vector2.ZERO:
		_place_prop(root,data,L.barrel(),barn_at+Vector2(-5.2,7.4),0.42,1.2)
		var second:=L.barrel()
		if _place_prop(root,data,second,barn_at+Vector2(-3.8,8.4),0.42,1.2):second.rotation.y=0.7
	for i in range(6):
		var stone_spot:Vector2=[at+Vector2(-13.6,13.8),at+Vector2(-8.9,15.6),at+Vector2(4.6,18.2),at+Vector2(-12.4,30.5),at+Vector2(6.4,10.6),Vector2(gate_x+1.6,at.y+14.6)][i]
		if _near_road(data,stone_spot,0.6):continue
		var stone:=L.stone(40+i,Vector3(rng.randf_range(0.3,0.5),rng.randf_range(0.12,0.2),rng.randf_range(0.24,0.4)))
		stone.position=Vector3(stone_spot.x,0.02,stone_spot.y)
		root.add_child(stone)
	# 背景树：庭院边缘的高大轮廓，避开森林分块遮罩以免重叠。
	# ART-02：农舍门前与井边补两株开花果树作近景点缀。
	var grove:=[[Vector2(-12.5,7.0),"blossom",1.0],[Vector2(7,31),"blossom",1.05],[Vector2(-36,-20),"pine",1.3],[Vector2(-29,-27),"oak",1.15],[Vector2(16,-18),"oak",1.0],[Vector2(25,-26),"pine",1.25],[Vector2(-58,4),"pine",1.35],[Vector2(-65,13),"oak",1.1],[Vector2(70,8),"pine",1.3],[Vector2(79,17),"oak",1.05],[Vector2(95,1),"pine",1.2],[Vector2(-50,55),"oak",1.2],[Vector2(34,53),"pine",1.15],[Vector2(-13,59),"oak",1.0],[Vector2(-88,40),"pine",1.2],[Vector2(88,42),"oak",1.1]]
	for index in range(grove.size()):
		var entry:Array=grove[index]
		var spot:Vector2=at+(entry[0] as Vector2)
		if _in_forest(forest_mask,spot) or _near_road(data,spot,2.2):continue
		var tree:=trees.build(entry[1],index%6)
		_place_prop(root,data,tree,spot,0.55,2.0,rng.randf()*TAU)
		tree.scale*=entry[2] as float


static func _in_forest(mask:Image,at:Vector2)->bool:
	# 与森林分块同一张遮罩：遮罩内交给分块树，装饰树不与其重叠。
	var pixel:=at/D.METERS_PER_PIXEL+D.ORIGIN
	var uv:=pixel/Vector2(1312,1199)
	if uv.x<0 or uv.x>=1 or uv.y<0 or uv.y>=1:return false
	return mask.get_pixel(clampi(int(uv.x*mask.get_width()),0,mask.get_width()-1),clampi(int(uv.y*mask.get_height()),0,mask.get_height()-1)).r>=0.28


static func _place_prop(root:Node3D,data:Dictionary,node:Node3D,at:Vector2,radius:float,clearance:float=1.2,yaw:float=0.0)->Node3D:
	# 道具统一入口：避让道路、建筑与菜园，登记碰撞；位置冲突时放弃而不挤占通道。
	if _near_road(data,at,clearance):return null
	for building:Dictionary in data["definition"]["buildings"]:
		if (Rect2(building["position"]-(building["size"] as Vector2)*0.5,building["size"]) as Rect2).grow(1.0).has_point(at):return null
	if (data["definition"]["starter_garden"] as Rect2).grow(0.9).has_point(at):return null
	node.position=Vector3(at.x,0,at.y)
	node.rotation.y=yaw
	root.add_child(node)
	if radius>0.0:
		data["obstacles"].append({"shape":"sphere","position":Vector3(at.x,radius*0.9,at.y),"radius":radius})
		data["blocked"]["circles"].append({"position":at,"radius":radius})
	return node

static func _build_farm_fence_line(root: Node3D, data: Dictionary, start: Vector2, finish: Vector2, gate_x: float) -> void:
	# Sample only this short fence, with a generous shoulder beyond every road surface.
	# The resulting segments drive both meshes and physical/domain obstacles.
	var steps := maxi(1, ceili(start.distance_to(finish) / 0.20))
	var beginning := -1
	for index in range(steps + 1):
		var keep := false
		if index < steps:
			var sample := start.lerp(finish, (index + 0.5) / float(steps))
			keep = absf(sample.x - gate_x) > 2.25 and not _near_road(data, sample, 0.85)
		if keep and beginning < 0:
			beginning = index
		elif not keep and beginning >= 0:
			var from := start.lerp(finish, beginning / float(steps))
			var to := start.lerp(finish, index / float(steps))
			var length := from.distance_to(to)
			if length >= 0.45:
				var panels := maxi(1, ceili(length / 2.4))
				for panel in range(panels):
					var center := from.lerp(to, (panel + 0.5) / float(panels))
					var fence := L.fence(length / panels)
					fence.position = Vector3(center.x, 0, center.y)
					fence.rotation.y = -atan2(to.y - from.y, to.x - from.x)
					root.add_child(fence)
				var center := (from + to) * 0.5
				_register_box(data, Vector3(center.x, 0.50, center.y), Vector3(absf(to.x - from.x) + 0.29, 1.06, absf(to.y - from.y) + 0.29), "farm_fence")
				data["farm_fences"].append({"from": from, "to": to, "width": 0.29})
			beginning = -1


static func _near_road(data: Dictionary, at: Vector2, shoulder: float) -> bool:
	for road: Dictionary in data["blocked"]["paths"]:
		if Geometry2D.get_closest_point_to_segment(at, road["from"], road["to"]).distance_to(at) < float(road["width"]) * 0.5 + shoulder:
			return true
	return false


static func _configure_bridge_openings(definition: Dictionary) -> void:
	# Some traced paths join an abutment from the side (the mine path in particular).
	# Record that real junction before drawing the bridge or registering collisions.
	for bridge: Dictionary in definition["bridges"]:
		if not bridge.get("stone", false):
			continue
		var rect: Rect2 = bridge["rect"]
		var along_x: bool = bridge.get("axis", "x" if rect.size.x >= rect.size.y else "z") == "x"
		var along := Vector2.RIGHT if along_x else Vector2.DOWN
		var cross_axis := Vector2.DOWN if along_x else Vector2.RIGHT
		var span := rect.size.x if along_x else rect.size.y
		var width := rect.size.y if along_x else rect.size.x
		bridge["rail_openings"] = []
		for side in [-1.0, 1.0]:
			var side_center: Vector2 = rect.get_center() + cross_axis * side * (width * 0.5 - 0.16)
			for road: Dictionary in definition["roads"]:
				for index in range(road["points"].size() - 1):
					var a: Vector2 = road["points"][index]
					var b: Vector2 = road["points"][index + 1]
					var hit: Variant = Geometry2D.segment_intersects_segment(side_center - along * span * 0.5, side_center + along * span * 0.5, a, b)
					if hit == null:
						continue
					var projected: float = absf((b - a).normalized().dot(cross_axis))
					var opening_half: float = (float(road["width"]) * 0.5 + 0.8) / maxf(projected, 0.1)
					var offset: float = ((hit as Vector2) - rect.get_center()).dot(along)
					bridge["rail_openings"].append({"side": side, "from": maxf(-span * 0.5, offset - opening_half), "to": minf(span * 0.5, offset + opening_half)})


static func _build_bridge_collisions(data: Dictionary) -> void:
	for bridge: Dictionary in data["definition"]["bridges"]:
		if not bridge.get("stone", false):
			continue
		var rect: Rect2 = bridge["rect"]
		var along_x: bool = bridge.get("axis", "x" if rect.size.x >= rect.size.y else "z") == "x"
		var span := rect.size.x if along_x else rect.size.y
		var width := rect.size.y if along_x else rect.size.x
		var center := rect.get_center()
		# Match the nineteen visual vault stones, following the arch vertically.
		# No transverse obstacle is created at either end of the bridge.
		for index in range(19):
			var t0 := index / 19.0
			var t1 := (index + 1) / 19.0
			var t := (t0 + t1) * 0.5
			var rise: float = bridge.get("rise", 0.52)
			var h0 := 0.09 + sin(t0 * PI) * rise
			var h1 := 0.09 + sin(t1 * PI) * rise
			var h := 0.09 + sin(t * PI) * rise
			for side in [-1.0, 1.0]:
				if StoneBridge.rail_is_open(side, (t0 - 0.5) * span, (t1 - 0.5) * span, bridge.get("rail_openings", [])):
					continue
				var across: float = side * (width * 0.5 - 0.16)
				var at := center + (Vector2((t - 0.5) * span, across) if along_x else Vector2(across, (t - 0.5) * span))
				var size := Vector3(span / 19.0 + 0.02, 0.97 + absf(h1 - h0), 0.54)
				if not along_x:
					size = Vector3(size.z, size.y, size.x)
				_register_box(data, Vector3(at.x, h + 0.40, at.y), size, "bridge_parapet:" + bridge["id"])


static func _register_box(data: Dictionary, at: Vector3, size: Vector3, source: String) -> void:
	data["obstacles"].append({"shape": "box", "position": at, "size": size, "source": source})
	data["blocked"]["rects"].append(Rect2(Vector2(at.x, at.z) - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z)))


static func _build_landmarks(root:Node3D,definition:Dictionary)->void:
	var lighthouse:Vector3=definition["landmarks"]["lighthouse"]
	for i in range(6):
		var rock:=L.stone(21+i,Vector3(3.5+i%2,1.5+i%3*.3,3.0))
		rock.position=lighthouse+Vector3(sin(i*2.399)*4.2,-.5,cos(i*2.399)*4.2)
		root.add_child(rock)
	var beacon:=Node3D.new();beacon.name="SouthCoastLighthouse";beacon.position=lighthouse;root.add_child(beacon)
	M.cylinder(beacon,Vector3(0,1,0),3.2,2.8,2,"#8f8b7d","StoneFooting",18)
	for floor in range(5):M.cylinder(beacon,Vector3(0,2.8+floor*1.8,0),2.3-floor*.08,2.22-floor*.08,1.8,"#d9d5c0" if floor%2==0 else "#a55e47","LighthouseStripe",24)
	M.cylinder(beacon,Vector3(0,11.2,0),2.25,2.25,.3,"#8d7653","LanternGallery",24)
	M.cylinder(beacon,Vector3(0,12.1,0),1.4,1.4,1.6,"#7eaaac","LanternGlazing",16)
	for i in range(8):M.beam(beacon,Vector3(cos(i*TAU/8)*1.45,11.3,sin(i*TAU/8)*1.45),Vector3(cos(i*TAU/8)*1.45,12.9,sin(i*TAU/8)*1.45),.12,"#5c6256","LanternFrame")
	M.cylinder(beacon,Vector3(0,13.4,0),2.0,.07,1.3,"#a56b4c","BeaconRoof",16)
	for location in [[592,1049],[636,1045]]:
		var at:=D.point(location)
		var boat:=Node3D.new();boat.position=Vector3(at.x,-.05,at.y);boat.rotation.y=.17;root.add_child(boat)
		M.ellipsoid(boat,Vector3(0,.24,0),Vector3(1.65,.70,4.2),"#815a35","BoatHull",16,8)
		M.ellipsoid(boat,Vector3(0,.63,0),Vector3(1.38,.12,3.83),"#b38f59","BoatDeck",16,5)
		for i in range(8):M.box(boat,Vector3(0,.71,-2.8+i*.75),Vector3(2.5,.055,.055),"#705136","DeckPlankSeam",0)
		M.beam(boat,Vector3(0,.7,0),Vector3(0,7,0),.17,"#95754b","Mast")
		M.beam(boat,Vector3(0,1.2,0),Vector3(0,1.2,3.0),.13,"#95754b","Boom")
		var sail:=SurfaceTool.new();sail.begin(Mesh.PRIMITIVE_TRIANGLES)
		M.polygon(sail,[Vector3(.03,1.4,.2),Vector3(.03,6.6,.2),Vector3(.03,1.4,3)],Vector3.RIGHT,Color("#e5d4aa"))
		M.mesh_node(boat,sail.commit(),Vector3.ZERO,M.paint("#ffffff"),"CanvasSail")
	# 湖畔观景码头尽头系一条小划艇。
	if definition["landmarks"].has("lake_view"):
		var pier:Vector3=definition["landmarks"]["lake_view"]
		var rowboat:=Node3D.new();rowboat.position=Vector3(pier.x+23.0,-.08,pier.z+5.5);rowboat.rotation.y=.6;root.add_child(rowboat)
		M.ellipsoid(rowboat,Vector3(0,.18,0),Vector3(.72,.30,1.75),"#7c5633","RowBoatHull",12,6)
		M.ellipsoid(rowboat,Vector3(0,.33,0),Vector3(.58,.05,1.55),"#a5824f","RowBoatBench",12,4)
		M.beam(rowboat,Vector3(0,.3,.6),Vector3(0,.3,2.3),.05,"#b08f57","Oar")


static func _build_town_square_details(root:Node3D,data:Dictionary)->void:
	# MAP-01：镇广场的家具层——长椅、街灯、市集棚与告示板围合喷泉。
	var rect:Rect2=data["definition"]["square"]
	var center:=rect.get_center()
	var rng:=RandomNumberGenerator.new();rng.seed=4477
	for entry in [[Vector2(center.x,rect.position.y+3.4),0.0],[Vector2(center.x,rect.end.y-3.4),PI],[Vector2(rect.position.x+3.4,center.y),PI*.5],[Vector2(rect.end.x-3.4,center.y),-PI*.5]]:
		var bench:=preload("res://scripts/art/town_models.gd").bench()
		bench.position=Vector3(entry[0].x,0,entry[0].y)
		bench.rotation.y=entry[1]
		root.add_child(bench)
		var along_x:bool=absf(cos(float(entry[1])))<0.5
		data["obstacles"].append({"shape":"box","position":Vector3(entry[0].x,0.4,entry[0].y),"size":Vector3(1.0 if along_x else 2.0,0.8,2.0 if along_x else 1.0)})
	for corner in [rect.position+Vector2(2.2,2.2),rect.position+Vector2(rect.size.x-2.2,2.2),rect.position+Vector2(2.2,rect.size.y-2.2),rect.position+Vector2(rect.size.x-2.2,rect.size.y-2.2)]:
		var lamp:=L.lantern_post()
		lamp.position=Vector3(corner.x,0,corner.y);root.add_child(lamp)
		data["lights"].append(Vector3(corner.x,2.4,corner.y))
		data["blocked"]["circles"].append({"position":corner,"radius":0.32})
	# 西侧两座市集棚；屋棚条纹与货品按种子变化。
	for i in range(2):
		var stall_at:=rect.position+Vector2(6.0+i*9.0,rect.size.y-5.2)
		_market_stall(root,data,stall_at,PI if i%2==0 else PI*0.92,rng,i)
	var board:=preload("res://scripts/art/town_models.gd").noticeboard()
	var board_at:=Vector2(rect.end.x-4.0,rect.position.y+4.5)
	board.position=Vector3(board_at.x,0,board_at.y);board.rotation.y=-PI*.5
	root.add_child(board)
	data["obstacles"].append({"shape":"sphere","position":Vector3(board_at.x,1.0,board_at.y),"radius":0.8})


static func _market_stall(root:Node3D,data:Dictionary,at:Vector2,yaw:float,rng:RandomNumberGenerator,kind:int)->void:
	# 木架条纹布篷的市场摊位；正面开口朝向广场，货物按 kind 换色。
	var stall:=Node3D.new();stall.name="MarketStall"
	stall.position=Vector3(at.x,0,at.y);stall.rotation.y=yaw
	root.add_child(stall)
	M.box(stall,Vector3(0,0.55,0),Vector3(2.9,0.10,1.7),"#9a774d","StallCounter",0.04)
	for x in [-1.32,1.32]:
		for z in [-0.72,0.72]:
			M.box(stall,Vector3(x,0.27,z),Vector3(0.12,0.55,0.12),"#7c5c3b","StallLeg")
			M.beam(stall,Vector3(x,0,z),Vector3(x,2.35,z),0.07,"#8a6a43","StallPost")
	var canopy:=Node3D.new();canopy.position=Vector3(0,2.35,0);canopy.rotation.x=-0.16;stall.add_child(canopy)
	for i in range(7):
		var slat:=M.box(canopy,Vector3((i-3)*0.44,0.0,0),Vector3(0.46,0.05,2.3),"#c9564a" if i%2==0 else "#ede3c4","StallAwning")
		slat.rotation.z=0.06
	var palette:Array=[["#d98f3f","#c9743a"],["#9db85c","#6f9448"],["#c9564a","#ede3c4"]][kind%3]
	for i in range(9):
		var pile_x:=-0.95+(i%3)*0.95
		var pile_z:=-0.35+(i/3)*0.42
		M.ellipsoid(stall,Vector3(pile_x,0.72,pile_z),Vector3(0.30,0.11,0.20),palette[i%2],"StallGoods",12,6)
		if i%3==0:M.ellipsoid(stall,Vector3(pile_x,0.84,pile_z),Vector3(0.20,0.08,0.14),palette[(i+1)%2],"StallGoods",10,5)
	data["obstacles"].append({"shape":"box","position":Vector3(at.x,0.5,at.y),"size":Vector3(3.1,1.0,2.0)})


static func _build_harbor_props(root:Node3D,data:Dictionary)->void:
	# MAP-01：港口的木吊车、系缆桩与货堆；道具只落在码头矩形或岸上空地。
	var rng:=RandomNumberGenerator.new();rng.seed=8891
	var docks:Array=data["definition"]["docks"]
	var longest:Rect2=docks[0]["rect"]
	for dock:Dictionary in docks:
		if (dock["rect"] as Rect2).get_area()>longest.get_area():longest=dock["rect"]
	# 长栈桥两侧的系缆桩与少量货堆。
	var step:=42.0
	for t in range(int(step*0.5),int(longest.size.x),int(step)):
		var at:=Vector2(longest.position.x+t,longest.get_center().y)
		for side in [-1.0,1.0]:
			var bollard:=M.cylinder(root,Vector3(at.x,0.34,at.y+side*(longest.size.y*.5-.9)),0.16,0.13,0.62,"#5c4a36","HarborBollard",10)
			bollard.rotation.z=side*0.05
	for i in range(3):
		var at:=Vector2(longest.position.x+18.0+i*8.5,longest.get_center().y+2.0)
		if i%2==0:
			var crate:=L.crate(true)
			crate.position=Vector3(at.x,0.05,at.y);crate.rotation.y=rng.randf_range(-0.3,0.3);root.add_child(crate)
		else:
			var barrel:=L.barrel()
			barrel.position=Vector3(at.x,0.05,at.y);root.add_child(barrel)
		data["blocked"]["circles"].append({"position":at,"radius":0.5})
	# 深水栈桥尽头的木吊车。
	var pier:Rect2=docks[0]["rect"]
	for dock:Dictionary in docks:
		var r:Rect2=dock["rect"]
		if r.size.y>r.size.x and r.get_center().y>pier.get_center().y:pier=r
	var crane_at:=pier.position+Vector2(pier.size.x*.5,pier.size.y-3.0)
	_harbor_crane(root,data,crane_at,-PI*.5)
	# 码头岸侧的备用船桨与浮标；靠内陆摆放，不落进海面。
	for i in range(4):
		var at:=crane_at+Vector2(4.0+i*1.7,-6.5+sin(i)*0.6)
		M.beam(root,Vector3(at.x,0.35,at.y),Vector3(at.x+1.4,1.15,at.y+0.5),0.07,"#7c6142","Oar")
	for i in range(5):
		var at:=crane_at+Vector2(-3.0-i*1.1,-5.2)
		M.torus(root,Vector3(at.x,0.12,at.y),0.28,0.09,"#c9a03d" if i%2 else "#b8503f","Buoy")


static func _harbor_crane(root:Node3D,data:Dictionary,at:Vector2,yaw:float)->void:
	# 石基木桅的港口吊车：桅杆、斜臂、拉索与吊钩都能从码头读到。
	var crane:=Node3D.new();crane.name="HarborCrane"
	crane.position=Vector3(at.x,0,at.y);crane.rotation.y=yaw
	root.add_child(crane)
	M.cylinder(crane,Vector3(0,0.25,0),1.7,1.5,0.5,"#8f8b7d","CraneFooting",12)
	M.beam(crane,Vector3(0,0.5,0),Vector3(0,8.2,0),0.34,"#77563a","CraneMast",-1,true)
	var jib:=Node3D.new();jib.position=Vector3(0,7.8,0);jib.rotation.x=0.25;crane.add_child(jib)
	M.beam(jib,Vector3(0,0,0),Vector3(0,0,7.4),0.22,"#8a6543","CraneJib",-1,true)
	for i in range(4):
		M.beam(jib,Vector3(0.10,0,1.1+i*1.7),Vector3(-0.10,-0.55,1.55+i*1.7),0.06,"#6b4d33","JibBrace")
	M.beam(crane,Vector3(0,8.0,0),Vector3(-2.6,5.6,0),0.055,"#d9cba4","CraneStay")
	M.beam(crane,Vector3(0,8.0,0),Vector3(2.2,5.8,0),0.055,"#d9cba4","CraneStay")
	M.box(crane,Vector3(-2.7,0.5,0),Vector3(1.1,0.9,1.1),"#77836d","Counterweight")
	M.beam(crane,Vector3(0,5.95,7.15),Vector3(0,2.5,7.15),0.03,"#e8dcc0","CraneLine")
	M.torus(crane,Vector3(0,2.3,7.15),0.22,0.055,"#5c6256","CraneHook")
	data["obstacles"].append({"shape":"sphere","position":Vector3(at.x,1.0,at.y),"radius":1.3})
	data["blocked"]["circles"].append({"position":at,"radius":1.3})
	data["lights"].append(Vector3(at.x,3.0,at.y))


static func _build_npc_homestead(root:Node3D,data:Dictionary)->void:
	# MAP-01：NPC 农庄的院落——谷仓旁畜栏、干草、桶和庭院草花；经营保护规则不变。
	var definition:Dictionary=data["definition"]
	var barn:Vector2;var coop:Vector2;var house:Vector2
	for building:Dictionary in definition["buildings"]:
		match building["id"]:
			"npc_farmhouse":house=building["position"]
			"npc_barn":barn=building["position"]
			"npc_coop":coop=building["position"]
	var garden_art:=preload("res://scripts/art/cozy_landscape.gd")
	var rng:=RandomNumberGenerator.new();rng.seed=5533
	# 谷仓南侧的小型畜栏（参考图 NPC 农庄尺度），北侧留门。
	var pen:=Rect2(barn+Vector2(-19.0,10.0),Vector2(38.0,24.0))
	for side in [0,1]:
		_build_farm_fence_line(root,data,Vector2(pen.position.x,pen.position.y+side*pen.size.y),Vector2(pen.end.x,pen.position.y+side*pen.size.y),-99999.0)
	for side in [0,1]:
		_build_farm_fence_line(root,data,Vector2(pen.position.x+side*pen.size.x,pen.position.y),Vector2(pen.position.x+side*pen.size.x,pen.end.y),-99999.0)
	var homestead:=preload("res://scripts/art/landscape_models.gd")
	_place_prop(root,data,homestead.hay_bale(11),pen.position+Vector2(4.0,4.0),0.8,1.6,0.6)
	var stacked:=_place_prop(root,data,homestead.hay_bale(12),pen.position+Vector2(7.0,5.4),0.8,1.6,1.9)
	if stacked!=null:stacked.rotation.y=0.9
	_place_prop(root,data,homestead.barrel(),house+Vector2(7.2,6.0),0.42,1.2)
	_place_prop(root,data,homestead.watering_can(),coop+Vector2(-4.2,4.6),0.0,1.4)
	var lamp_at:=house+Vector2(-7.0,6.2)
	if _place_prop(root,data,homestead.lantern_post(),lamp_at,0.3,1.3)!=null:
		data["lights"].append(Vector3(lamp_at.x,2.4,lamp_at.y))
	# 农舍与谷仓周边的草花：避开三栋建筑、耕地、道路与畜栏内部。
	var yard:=Rect2(house,Vector2.ZERO).expand(barn).expand(coop).grow(14.0)
	var meadow:=SurfaceTool.new();meadow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var petals:=SurfaceTool.new();petals.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(2600):
		var spot:=yard.position+Vector2(rng.randf(),rng.randf())*yard.size
		if pen.grow(-1.0).has_point(spot):continue
		var skip:=false
		for field:Rect2 in definition["fields"]:
			if field.grow(-1.0).has_point(spot):skip=true;break
		if skip:continue
		if _near_road(data,spot,0.6):continue
		if spot.distance_to(house)>2.0 and spot.distance_to(barn)>3.0 and spot.distance_to(coop)>2.5:
			if rng.randf()<0.5:
				garden_art._grass(meadow,spot,rng,rng.randf_range(0.14,0.34))
				if i%5==0:garden_art._flower(meadow,petals,spot,rng,i%6)
	M.mesh_node(root,meadow.commit(),Vector3.ZERO,M.paint("#ffffff"),"NpcHomesteadGrass")
	M.mesh_node(root,petals.commit(),Vector3.ZERO,M.paint("#ffffff"),"NpcHomesteadFlowers")
