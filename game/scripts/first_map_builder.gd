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
static func build()->Dictionary:
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
	for field:Rect2 in definition["fields"]:
		var at:=field.get_center()
		var surface:=M.box(root,Vector3(at.x,.025,at.y),Vector3(field.size.x,.04,field.size.y),"#806641","AgriculturalParcel",0)
		var material:StandardMaterial3D=M.paint("#a08b56").duplicate()
		material.albedo_texture=preload("res://resources/materials/terrain/earth.png")
		material.uv1_triplanar=true;material.uv1_scale=Vector3.ONE*.25
		surface.material_override=material
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
