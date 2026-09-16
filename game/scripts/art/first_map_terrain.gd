extends RefCounted
const M:=preload("res://scripts/art/art_mesh.gd")
const Valley:=preload("res://scripts/art/valley_terrain.gd")
const D:=preload("res://scripts/data/first_map_definition.gd")
static func build(definition:Dictionary)->Node3D:
	var root:=Node3D.new();root.name="CalibratedValleyTerrain";root.set_meta("keep_meshes",true)
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half:Vector2=definition["bounds"]["half"]
	var step:=8.0
	var regions:Array=[]
	for water:Dictionary in definition["waters"]:
		var polygon:PackedVector2Array=water["polygon"]
		var box:=Rect2(polygon[0],Vector2.ZERO)
		for at:Vector2 in polygon:box=box.expand(at)
		regions.append({"bounds":box,"polygon":polygon})
	var nx:=ceili(half.x*2/step);var nz:=ceili(half.y*2/step)
	var heights:=PackedFloat32Array();heights.resize((nx+1)*(nz+1))
	for z in range(nz+1):
		for x in range(nx+1):
			var at:=Vector2(-half.x+x*step,-half.y+z*step)
			for region:Dictionary in regions:
				if region["bounds"].has_point(at) and Geometry2D.is_point_in_polygon(at,region["polygon"]):
					heights[z*(nx+1)+x]=-2.5
					break
	for z in range(nz):
		for x in range(nx):
			var corners:Array=[]
			for d:Vector2i in [Vector2i(0,0),Vector2i(0,1),Vector2i(1,1),Vector2i(1,0)]:
				corners.append(Vector3(-half.x+(x+d.x)*step,heights[(z+d.y)*(nx+1)+x+d.x],-half.y+(z+d.y)*step))
			M.polygon(surface,corners,Vector3.UP)
	M.mesh_node(root,surface.commit(),Vector3.ZERO,preload("res://scripts/art/cozy_landscape.gd").ground_material(),"MetricTerrain")
	# Grey ridges stay in the northwest, exactly where the blueprint places the mine.
	for i in range(24):
		var px:=Vector2(24+(i%8)*49,70+(i/8)*62)
		var at:=D.point([px.x,px.y])
		if at.distance_to(Vector2(definition["landmarks"]["mine_door"].x,definition["landmarks"]["mine_door"].z))<52:continue
		var rock:=Valley.crag(502+i,Vector2(48+i%3*10,43+i%4*8),28+i%5*11)
		rock.position=Vector3(at.x,-1,at.y);root.add_child(rock)
	return root
