extends RefCounted
## Authored lanes: continuous irregular shoulders, worn dirt and inset fieldstones.
const M := preload("res://scripts/art/art_mesh.gd")
const L := preload("res://scripts/art/landscape_models.gd")
static var _materials := {}

static func material(paved: bool) -> ShaderMaterial:
	if _materials.has(paved): return _materials[paved]
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D paint : source_color, repeat_enable, filter_linear_mipmap;
uniform bool paved=false;
varying vec3 world;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.54);}
float noise(vec2 p){vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.-2.*f); return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;}
void fragment(){
 float variation=noise(world.xz*.48);
 vec3 earth=texture(paint,world.xz*.21).rgb;
 float edge=abs(UV.x*2.-1.);
 float ragged=noise(world.xz*5.5)*.15+noise(world.xz*1.7)*.18;
 ALPHA=1.-smoothstep(.73+ragged,.92+ragged,edge);
 ALPHA_SCISSOR_THRESHOLD=.45;
 ALBEDO=earth*(.90+variation*.19);
 ROUGHNESS=1.; SPECULAR=.07;
}
"""
	mat.shader=shader
	mat.set_shader_parameter("paint",load("res://resources/materials/terrain/stone.png" if paved else "res://resources/materials/terrain/earth.png"))
	mat.set_shader_parameter("paved",paved)
	_materials[paved]=mat
	return mat

static func build(points: Array, width: float, paved: bool, seed_value: int) -> Node3D:
	var root:=Node3D.new()
	root.name="PaintedVillageLane"
	root.set_meta("keep_meshes",true)
	var rng:=RandomNumberGenerator.new()
	rng.seed=absi(seed_value)
	var mesh:=SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stones:=SurfaceTool.new()
	stones.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Build a rounded spline, while the occupancy rule conservatively keeps the source corridor.
	var samples: Array[Vector2]=[]
	for part in range(points.size()-1):
		var a: Vector2=points[part]
		var b: Vector2=points[part+1]
		var steps:=maxi(1,ceili(a.distance_to(b)/.38))
		for i in range(steps): samples.append(a.lerp(b,float(i)/steps))
	samples.append(points[-1])
	var rims: Array=[]
	var distance:=0.0
	for i in range(samples.size()):
		var point:Vector2=samples[i]
		var tangent:Vector2=(samples[mini(i+1,samples.size()-1)]-samples[maxi(0,i-1)]).normalized()
		var side:=Vector2(-tangent.y,tangent.x)
		if i>0: distance+=point.distance_to(samples[i-1])
		var spread:=width*.58*(1.0+sin(distance*1.39+seed_value)*.055+sin(distance*.49)*.07)
		rims.append([point-side*spread,point+side*spread,distance])
	for i in range(rims.size()-1):
		var a:Array=rims[i];var b:Array=rims[i+1]
		_quad(mesh,[Vector3(a[0].x,.041,a[0].y),Vector3(a[1].x,.041,a[1].y),Vector3(b[1].x,.041,b[1].y),Vector3(b[0].x,.041,b[0].y)],[Vector2(0,a[2]),Vector2(1,a[2]),Vector2(1,b[2]),Vector2(0,b[2])])
	M.mesh_node(root,mesh.commit(),Vector3.ZERO,material(paved),"WornEarthShoulders").cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Irregular sunk stones, never a regular row of identical squares.
	for i in range(1,samples.size()-1,2 if paved else 8):
		var point:Vector2=samples[i]
		var tangent:Vector2=(samples[i+1]-samples[i-1]).normalized()
		var side:=Vector2(-tangent.y,tangent.x)
		for column in range(3 if paved else 1):
			var at:=point+side*((column-1)*width*.27+rng.randf_range(-.14,.14) if paved else rng.randf_range(-width*.36,width*.36))
			var outline:Array=[]
			var radius:=rng.randf_range(.26,.39) if paved else rng.randf_range(.055,.12)
			var tint:=Color(["#b6ad93","#c4b89a","#a69f87","#c5bda5"][rng.randi_range(0,3)])
			for corner in range(7):
				var angle:=float(corner)*TAU/7
				outline.append(Vector3(at.x+cos(angle)*radius*rng.randf_range(.8,1.2),.057,at.y+sin(angle)*radius*.78))
			M.polygon(stones,outline,Vector3.UP,tint)
	M.mesh_node(root,stones.commit(),Vector3.ZERO,M.paint("#ffffff"),"SunkFieldstones")
	return root

static func _quad(surface: SurfaceTool, vertices: Array, uvs: Array) -> void:
	for index in [0,2,1,0,3,2]:
		surface.set_normal(Vector3.UP)
		surface.set_uv(uvs[index])
		surface.add_vertex(vertices[index])
