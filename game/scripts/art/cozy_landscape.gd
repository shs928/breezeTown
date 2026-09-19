extends RefCounted
## 参考图近景：成簇草叶、白色雏菊、薰衣草、灌木与不规则踏石。
const M := preload("res://scripts/art/art_mesh.gd")
const L := preload("res://scripts/art/landscape_models.gd")
const Trees := preload("res://scripts/art/tree_models.gd")


static func ground_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec4 shade : source_color = vec4(0.21,0.37,0.13,1.0);
uniform vec4 grass : source_color = vec4(0.33,0.55,0.19,1.0);
uniform vec4 sunlit : source_color = vec4(0.50,0.66,0.27,1.0);
uniform float snow_amount : hint_range(0.0,1.0) = 0.0;
uniform vec3 season_tint : source_color = vec3(1.0,1.0,1.0);
varying vec3 world;
float hash21(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p){ vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y); }
void vertex(){ world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
 vec2 p=world.xz;
 float broad=noise(p*0.23)*0.65+noise(p*0.57+5.0)*0.35;
 float brush=noise(p*vec2(3.7,5.9));
 vec3 base=mix(shade.rgb,grass.rgb,smoothstep(0.05,0.66,broad));
 base=mix(base,sunlit.rgb,smoothstep(0.56,0.90,broad)*0.70);
 // 参考图的修剪条纹与细密双色斑点：大尺度斜向条带 + 小尺度明暗点。
 float stripe=sin((p.x+p.y)*0.33+noise(p*0.11)*2.2)*0.5+0.5;
 base*=mix(0.93,1.04,stripe);
 float fleck=smoothstep(0.76,0.96,noise(p*19.0));
 base*=season_tint;
 vec3 snowc=mix(vec3(0.88,0.91,0.96),vec3(0.97,0.98,1.0),noise(p*7.0));
 base=mix(base,snowc,snow_amount*(0.82+0.18*noise(p*1.7)));
 ALBEDO=mix(base*(0.93+0.12*brush)+sunlit.rgb*fleck*0.16, snowc*(0.9+0.1*noise(p*3.1)), snow_amount);
 ROUGHNESS=1.0; SPECULAR=0.05;
}
"""
	material.shader = shader
	return material


static func build(definition: Dictionary, data:Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "HandPaintedFarmGarden"
	var rng := RandomNumberGenerator.new()
	rng.seed = 73125
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var petals := SurfaceTool.new()
	petals.begin(Mesh.PRIMITIVE_TRIANGLES)
	var farm: Rect2 = definition["farm"]
	# 房屋四周和栅栏脚下成片布置，不用均匀撒点替代花园。
	var beds := [Rect2(-41, -12, 4, 16), Rect2(-23, -10, 4, 10), Rect2(-43, 4, 3, 25), Rect2(-41, 27, 27, 2), Rect2(-13, 4, 3, 23), Rect2(-20, -10, 11, 3)]
	for bed: Rect2 in beds:
		for i in range(int(bed.get_area() * 3.2)):
			var at := bed.position + Vector2(rng.randf(), rng.randf()) * bed.size
			if _water_or_road(at, definition, 0.9):
				continue
			_grass(leaves, at, rng, rng.randf_range(0.18, 0.40))
			if i % 3 == 0:
				_flower(leaves, petals, at, rng, i % 4)
	for i in range(6800):
		var at := Vector2(rng.randf_range(-69, 45), rng.randf_range(-25, 46))
		if farm.grow(-1.8).has_point(at) or _water_or_road(at, definition, 0.55) or _building(at, definition):
			continue
		if sin(at.x * 0.39) + cos(at.y * 0.33) < -0.2:
			continue
		_grass(leaves, at, rng, rng.randf_range(0.11, 0.27))
		if i % 18 == 0:
			_flower(leaves, petals, at, rng, i % 4)
	M.mesh_node(root, leaves.commit(), Vector3.ZERO, M.paint("#ffffff"), "BroadGrassAndStems")
	M.mesh_node(root, petals.commit(), Vector3.ZERO, M.paint("#ffffff"), "WildflowerPetals")
	# Intentional grove silhouettes: tallest foliage behind the cottage; gaps at gates.
	var tree_positions := [Vector2(-45,-9),Vector2(-42,-14),Vector2(-37,-16),Vector2(-32,-17),Vector2(-26,-16),Vector2(-20,-13),Vector2(-19,-6),Vector2(-45,-2),Vector2(-49,2),Vector2(-49,10),Vector2(-50,17),Vector2(-49,24),Vector2(-45,33),Vector2(-39,35),Vector2(-31,36),Vector2(-19,33),Vector2(-13,32),Vector2(-4,2),Vector2(-3,16),Vector2(-5,22),Vector2(-14,-18),Vector2(-8,-5)]
	for z in [-23.,-18.]:
		for x in [-49.,-44.,-39.,-34.,-29.,-24.,-19.]:
			tree_positions.append(Vector2(x+rng.randf_range(-1.2,1.2),z+rng.randf_range(-1.2,1.2)))
	for i in range(tree_positions.size()):
		var at:Vector2=tree_positions[i]
		if _water_or_road(at,definition,1.1): continue
		var tree:=Trees.build("pine" if i%3!=1 else "oak",i%6)
		tree.position=Vector3(at.x,0,at.y)
		tree.scale*=rng.randf_range(.82,1.18)
		tree.rotation.y=rng.randf()*TAU
		root.add_child(tree)
		if not data.is_empty():
			data["obstacles"].append({"shape":"sphere","position":tree.position+Vector3(0,.65,0),"radius":.38})
			data["blocked"]["circles"].append({"position":at,"radius":.55})
	for at:Vector2 in [Vector2(-40,-3),Vector2(-37,-12),Vector2(-24,-10),Vector2(-21,-5),Vector2(-44,9),Vector2(-44,24),Vector2(-16,25),Vector2(-15,5),Vector2(-40,30),Vector2(-34,30),Vector2(-23,29),Vector2(-11,18),Vector2(-5,5),Vector2(-5,15),Vector2(-42,1),Vector2(-24,1)]:
		_bush(root,at,rng)
	_build_precinct(root,definition,data,rng)
	# 门口踏石和花盆形成可读的生活区域。
	for i in range(13):
		var at := Vector3(-28.8 + sin(i * 1.7) * 0.45, 0.05, 1.2 + i * 0.47)
		var stone := L.stone(i + 21, Vector3(rng.randf_range(0.32,0.49),0.05,rng.randf_range(0.24,0.37)))
		stone.position = at
		root.add_child(stone)
	return root


static func _water_or_road(at: Vector2, definition: Dictionary, margin: float) -> bool:
	for water: Dictionary in definition["waters"]:
		if Geometry2D.is_point_in_polygon(at, water["polygon"]):
			return true
	for road: Dictionary in definition["roads"]:
		for i in range(road["points"].size()-1):
			if at.distance_to(Geometry2D.get_closest_point_to_segment(at, road["points"][i],road["points"][i+1])) < float(road["width"]) * 0.5 + margin:
				return true
	return false


static func _building(at: Vector2, definition: Dictionary) -> bool:
	for building: Dictionary in definition["buildings"]:
		if Rect2(building["position"]-building["size"]*0.5,building["size"]).grow(0.7).has_point(at):
			return true
	return false


static func _grass(surface: SurfaceTool, at: Vector2, rng: RandomNumberGenerator, height: float) -> void:
	for i in range(4):
		var angle := rng.randf()*TAU
		var bottom := Vector3(at.x+rng.randf_range(-0.16,0.16),0.015,at.y+rng.randf_range(-0.16,0.16))
		var side := Vector3(cos(angle),0,sin(angle))*rng.randf_range(0.035,0.07)
		var tip := bottom+Vector3(sin(angle)*height*0.6,height,cos(angle)*height*0.6)
		var green := Color(["#618b2f","#81a536","#527d32","#94ac43"][i])
		M.polygon(surface,[bottom-side,bottom+side,tip],Vector3.UP,green)


static func _flower(stems: SurfaceTool, petals: SurfaceTool, at: Vector2, rng: RandomNumberGenerator, kind: int) -> void:
	var height := rng.randf_range(0.25,0.52)
	var center := Vector3(at.x,height,at.y)
	M.polygon(stems,[Vector3(at.x-0.012,0,at.y),Vector3(at.x+0.012,0,at.y),center+Vector3(0.01,0,0)],Vector3.FORWARD,Color("#4e7d33"))
	var palette := ["#fff1d0","#d0b4e5","#f6ce4b","#fff6e1","#ef9fb2","#e0796f"]
	var color := Color(palette[absi(kind) % palette.size()])
	for i in range(5):
		var angle := i*TAU/5.0
		var direction := Vector3(cos(angle),0,sin(angle))
		var side := Vector3(-sin(angle),0,cos(angle))*0.055
		M.polygon(petals,[center,center+direction*0.1-side,center+direction*0.16,center+direction*0.1+side],Vector3.UP,color)
	M.polygon(petals,[center+Vector3(-0.044,0.012,-0.038),center+Vector3(0.044,0.012,-0.038),center+Vector3(0,0.013,0.05)],Vector3.UP,Color("#dfa730"))


static func _bush(root: Node3D, at: Vector2, rng: RandomNumberGenerator) -> void:
	# 不规则团簇：随机角度/半径/尺寸代替螺旋排布，顶部偶有浆果或小花。
	var blobs := 15 + rng.randi_range(0, 7)
	var squash := rng.randf_range(0.72, 1.05)
	for i in range(blobs):
		var angle := rng.randf() * TAU
		var spread := sqrt(rng.randf()) * 0.92
		var pos := Vector3(at.x + cos(angle) * spread, 0.28 + (0.88 - spread) * rng.randf_range(0.30, 0.58), at.y + sin(angle) * spread * squash)
		var part := M.ellipsoid(root, pos, Vector3(0.30, 0.26, 0.30) * rng.randf_range(0.72, 1.28), ["#47703a", "#5d8437", "#74993f", "#89a94a"][i % 4], "RoundLeafCluster", 10, 6)
		part.rotation.y = rng.randf() * TAU
		part.rotation.z = rng.randf_range(-0.28, 0.28)
	if rng.randf() < 0.4:
		for i in range(6):
			var berry_angle := rng.randf() * TAU
			M.ellipsoid(root, Vector3(at.x + cos(berry_angle) * 0.5, 0.68 + rng.randf() * 0.3, at.y + sin(berry_angle) * 0.5), Vector3(0.05, 0.05, 0.05), "#d4553f" if i % 2 == 0 else "#e46f4f", "BushBerry", 8, 5)


static func _build_precinct(root:Node3D,definition:Dictionary,data:Dictionary,rng:RandomNumberGenerator) -> void:

	# A small working courtyard connects house, beds and brook; ornamental herbs hug its edges.
	root.add_child(preload("res://scripts/art/painted_paths.gd").build([Vector2(-28.8,4.2),Vector2(-28.3,10.5),Vector2(-30,17),Vector2(-30,26)],1.05,false,638))
	root.add_child(preload("res://scripts/art/painted_paths.gd").build([Vector2(-30,12),Vector2(-23,10.5),Vector2(-15,10)],1.25,false,928))
	var well:=L.well()
	well.position=Vector3(-25.5,0,6.2)
	well.scale*=.86
	root.add_child(well)
	if not data.is_empty():
		data["obstacles"].append({"shape":"sphere","position":well.position+Vector3(0,.7,0),"radius":.78})
		data["blocked"]["circles"].append({"position":Vector2(-25.5,6.2),"radius":.90})
	# Lower stone retaining courses and mossy shelves establish real vertical edges.
	for i in range(23):
		var at:=Vector3(-44.8+sin(i*.7)*.38,.17+i%3*.10,-10+i*1.8)
		if _water_or_road(Vector2(at.x,at.z),definition,.2):continue
		var rock:=L.stone(i,Vector3(rng.randf_range(.60,.95),rng.randf_range(.38,.7),rng.randf_range(.6,.85)))
		rock.position=at
		root.add_child(rock)
		if i%2==0:_bush(root,Vector2(at.x-.6,at.z),rng)
	# Willow brook's grouped banks; stones are composed in clusters, never a uniform border.
	for i in range(17):
		var z:float=-3+i*1.95
		if z>6.7 and z<12.7:continue
		var x:float=-9.6+sin(z*.19)*.7
		for side in [-1.,1.]:
			var at:=Vector3(x+side*(2.0+rng.randf_range(0,.55)),-.20,z)
			var stone:=L.stone(i,Vector3(rng.randf_range(.3,.7),rng.randf_range(.2,.55),rng.randf_range(.4,.75)))
			stone.position=at;root.add_child(stone)
	# Potting bench, stacked produce crates, terracotta pots and a little herb bed.
	M.box(root,Vector3(-24.6,.72,.3),Vector3(2.6,.15,.9),"#987043","PottingBench",.05)
	for x in [-25.65,-23.55]:
		for z in [-.03,.60]:M.box(root,Vector3(x,.36,z),Vector3(.12,.72,.12),"#775a39","BenchLeg")
	for i in range(4):
		M.cylinder(root,Vector3(-25.3+i*.53,.93,.31),.15,.22,.32,"#b16b43","TerracottaPot",12)
		M.cylinder(root,Vector3(-25.3+i*.53,1.10,.31),.19,.19,.02,"#62492c","PottingEarth",12)
		for j in range(4):M.leaf(root,Vector3(-25.3+i*.53,1.1,.31),Vector3(-25.3+i*.53+sin(j*1.57)*.19,1.42,.31+cos(j*1.57)*.19),.13,"#7e9c43")
	for i in range(3):
		var crate:=L.crate(true)
		crate.position=Vector3(-25.8+(i%2)*1.05,(i/2)*.62,2.0)
		crate.rotation.y=.12-i*.14
		root.add_child(crate)
	# Low flowering borders divide cultivated beds without obstructing the walking aisles.
	var flower_mesh:=SurfaceTool.new();flower_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var green_mesh:=SurfaceTool.new();green_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(130):
		var at:=Vector2(-42+rng.randf()*25,27+rng.randf()*.9)
		if not _water_or_road(at,definition,.7):_flower(green_mesh,flower_mesh,at,rng,i%4)
	M.mesh_node(root,flower_mesh.commit(),Vector3.ZERO,M.paint("#ffffff"),"PerennialFlowerBorder")
	M.mesh_node(root,green_mesh.commit(),Vector3.ZERO,M.paint("#ffffff"),"FlowerBorderStems")
