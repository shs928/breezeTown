extends RefCounted
## Original, exportable farm architecture. Units: metres; up: +Y; front door: +Z.
## The root origin is ground level at the centre of the main wall footprint.
## All surfaces use ordinary meshes and StandardMaterial3D; no runtime shader is needed.

const MarketProps = preload("../buildings/market_props.gd")


static func cottage() -> Node3D:
	var root := Node3D.new()
	root.name = "Willow_Cottage"
	root.set_meta("main_footprint_m", Vector2(4.0, 3.6))
	root.set_meta("front", "+Z")
	var p := _palette()
	_house_shell(root, 4.0, 3.6, 2.62, 4.02, p)
	_tiled_roof(root, 2.28, 2.08, 2.66, 4.07, [Color("#BC7860"), Color("#C68767"), Color("#AE6855"), Color("#CD9070"), Color("#B97A64")], p)
	_front_window(root, "Front_Window", Vector3(-1.04, 1.49, 1.83), 0.94, 1.02, p, true)
	var side := Node3D.new()
	side.name = "East_Window_Assembly"
	side.position = Vector3(2.015, 1.46, -0.45)
	side.rotation.y = PI / 2.0
	root.add_child(side)
	_front_window(side, "Side_Window", Vector3.ZERO, 1.02, 1.06, p, true)
	var west := Node3D.new()
	west.name = "West_Window_Assembly"
	west.position = Vector3(-2.015, 1.47, -0.50)
	west.rotation.y = -PI / 2.0
	root.add_child(west)
	_front_window(west, "West_Window", Vector3.ZERO, 0.94, 1.03, p, false)
	_door(root, Vector3(0.66, 0.29, 1.85), 0.89, 1.88, p)
	_round_attic_window(root, Vector3(0.0, 3.15, 1.84), 0.28, p)
	_portrait_porch(root, Vector3(0.66, 0.0, 1.80), p)
	_chimney(root, Vector3(1.04, 2.92, -0.77), p)
	_lantern(root, Vector3(1.45, 1.93, 2.00), p)
	_box(root, "Door_Threshold", Vector3(1.14, 0.13, 0.44), Vector3(0.66, 0.275, 1.95), p["stone_light"], 0.045)
	_box(root, "Porch_Upper_Step", Vector3(1.44, 0.20, 0.58), Vector3(0.66, 0.17, 2.32), p["stone"], 0.055)
	_box(root, "Porch_Lower_Step", Vector3(1.70, 0.12, 0.60), Vector3(0.66, 0.06, 2.70), p["stone_light"], 0.045)
	_flower_pot(root, Vector3(-1.77, 0.02, 2.08), 0.86, p)
	return root


static func shop() -> Node3D:
	var root := Node3D.new()
	root.name = "Little_Seed_Market"
	root.set_meta("main_footprint_m", Vector2(4.4, 3.6))
	root.set_meta("front", "+Z")
	var p := _palette()
	_house_shell(root, 4.4, 3.6, 2.60, 3.94, p)
	_tiled_roof(root, 2.47, 2.09, 2.64, 3.99, [Color("#427D78"), Color("#508B82"), Color("#39746F"), Color("#60998C"), Color("#477D78")], p)
	_door(root, Vector3(-1.45, 0.27, 1.86), 0.82, 1.89, p)
	_front_window(root, "Shop_Display_Window", Vector3(0.71, 1.47, 1.84), 2.09, 1.20, p, false)
	_round_attic_window(root, Vector3(0.0, 3.12, 1.85), 0.26, p)
	var side := Node3D.new()
	side.name = "Market_East_Window"
	side.position = Vector3(2.215, 1.45, -0.40)
	side.rotation.y = PI / 2.0
	root.add_child(side)
	_front_window(side, "Side_Window", Vector3.ZERO, 1.10, 1.03, p, true)
	_striped_awning(root, Vector3(0.62, 0.0, 1.86), 2.84, p)
	var stall := MarketProps.seed_display()
	stall.name = "Wooden_Seed_Counter"
	stall.position = Vector3(0.63, 0.03, 2.54)
	stall.scale = Vector3(1.40, 1.0, 1.0)
	root.add_child(stall)
	_shop_sign(root, Vector3(-2.15, 2.05, 2.04), p)
	_lantern(root, Vector3(-0.69, 2.04, 2.03), p)
	_box(root, "Shop_Door_Upper_Step", Vector3(1.10, 0.18, 0.48), Vector3(-1.45, 0.16, 2.04), p["stone"], 0.045)
	_box(root, "Shop_Door_Lower_Step", Vector3(1.34, 0.11, 0.52), Vector3(-1.45, 0.055, 2.36), p["stone_light"], 0.045)
	_flower_pot(root, Vector3(2.20, 0.02, 2.37), 1.08, p)
	return root


static func _palette() -> Dictionary:
	return {
		"plaster": _material("Warm_lime_plaster", Color("#F1D9AD")),
		"plaster_light": _material("Gable_limewash", Color("#F5E2BB")),
		"wood": _material("Honey_oak", Color("#8E6040")),
		"wood_light": _material("Cut_oak_edges", Color("#B48658")),
		"wood_dark": _material("Timber_recesses", Color("#654737")),
		"wood_warm": _material("Door_honey_wood", Color("#BA8754")),
		"stone": _material("Warm_foundation_stone", Color("#8C8977")),
		"stone_light": _material("Sunlit_stone_edges", Color("#ADA28A")),
		"mortar": _material("Mortar_recess", Color("#6E756B")),
		"teal": _material("Sage_painted_shutters", Color("#68998A")),
		"teal_light": _material("Sage_worn_edges", Color("#8DB49D")),
		"teal_dark": _material("Deep_teal_joinery", Color("#3E716B")),
		"glass": _material("Opaque_stylised_window_glass", Color("#739E9F"), 0.38),
		"glass_light": _material("Hand_painted_glass_reflection", Color("#B9CFBB"), 0.48),
		"iron": _material("Warm_charcoal_iron", Color("#454A40"), 0.55),
		"brass": _material("Old_brass", Color("#BA9B56"), 0.43, 0.55),
		"terra": _material("Terracotta_details", Color("#B86850")),
		"terra_light": _material("Terracotta_light", Color("#CC8860")),
		"canvas_cream": _material("Cream_linen", Color("#F1DEB3")),
		"canvas_gold": _material("Ochre_linen", Color("#D3AD61")),
		"leaf": _material("Garden_green", Color("#688B54")),
		"leaf_light": _material("Leaf_lighter_face", Color("#94AF68")),
		"soil": _material("Potting_soil", Color("#625141")),
		"flower": _material("Coral_flowers", Color("#D9917D")),
		"warm_glass": _material("Lantern_amber_glass", Color("#EAC782"), 0.55),
	}


static func _material(label: String, color: Color, roughness: float = 0.88, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = label
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func _house_shell(root: Node3D, width: float, depth: float, eave: float, peak: float, p: Dictionary) -> void:
	_box(root, "Limestone_Foundation", Vector3(width + 0.05, 0.32, depth + 0.05), Vector3(0, 0.16, 0), p["mortar"], 0.07)
	_box(root, "Soft_Edged_Plaster_Walls", Vector3(width, eave - 0.28, depth), Vector3(0, (eave + 0.28) * 0.5, 0), p["plaster"], 0.065)
	var gable := PackedVector2Array([Vector2(-width * 0.5, eave - 0.025), Vector2(width * 0.5, eave - 0.025), Vector2(0, peak - 0.08)])
	_extruded_outline(root, "Limewashed_Gable", gable, depth - 0.025, Vector3.ZERO, p["plaster_light"])
	for side in [-1.0, 1.0]:
		for i in 7:
			var stone_width := width / 7.0
			var stone := _box(root, "Foundation_Front_Stone", Vector3(stone_width - 0.018, 0.245 + 0.018 * sin(float(i) * 1.7), 0.17), Vector3(-width * 0.5 + stone_width * (float(i) + 0.5), 0.165, side * (depth * 0.5 + 0.018)), p["stone_light"] if i % 3 == 0 else p["stone"], 0.042)
			stone.rotation.z = 0.014 * sin(float(i) * 2.4 + side)
		for i in 6:
			var stone_depth := depth / 6.0
			_box(root, "Foundation_Side_Stone", Vector3(0.17, 0.25, stone_depth - 0.020), Vector3(side * (width * 0.5 + 0.018), 0.16, -depth * 0.5 + stone_depth * (float(i) + 0.5)), p["stone_light"] if i % 2 == 0 else p["stone"], 0.045)
		_box(root, "Front_Back_Lower_Timber", Vector3(width + 0.08, 0.15, 0.17), Vector3(0, 0.39, side * (depth * 0.5 + 0.025)), p["wood"], 0.027)
		_box(root, "Front_Back_Upper_Timber", Vector3(width + 0.08, 0.17, 0.17), Vector3(0, eave - 0.03, side * (depth * 0.5 + 0.025)), p["wood"], 0.029)
		_box(root, "Side_Lower_Timber", Vector3(0.17, 0.15, depth), Vector3(side * (width * 0.5 + 0.025), 0.39, 0), p["wood"], 0.026)
		_box(root, "Side_Upper_Timber", Vector3(0.17, 0.17, depth + 0.09), Vector3(side * (width * 0.5 + 0.025), eave - 0.03, 0), p["wood"], 0.028)
		for front_back in [-1.0, 1.0]:
			_box(root, "Corner_Timber", Vector3(0.18, eave - 0.35, 0.18), Vector3(side * (width * 0.5 - 0.018), (eave + 0.35) * 0.5, front_back * (depth * 0.5 - 0.012)), p["wood"], 0.024)
			_beam(root, "Gable_Rafter", Vector3(side * (width * 0.5 - 0.025), eave + 0.015, front_back * (depth * 0.5 + 0.035)), Vector3(0, peak - 0.095, front_back * (depth * 0.5 + 0.035)), 0.12, 0.14, p["wood"])
	_box(root, "Rear_Centre_Timber", Vector3(0.13, eave - 0.41, 0.14), Vector3(0, (eave + 0.41) * 0.5, -depth * 0.5 - 0.025), p["wood"], 0.021)
	_box(root, "Gable_Short_Kingpost", Vector3(0.115, 0.39, 0.13), Vector3(0, peak - 0.29, depth * 0.5 + 0.035), p["wood"], 0.02)


static func _tiled_roof(root: Node3D, half_width: float, half_depth: float, eave: float, peak: float, colors: Array, p: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rise := peak - eave
	var length := sqrt(half_width * half_width + rise * rise)
	var rows := ceili(length / 0.34)
	var columns := ceili(half_depth * 2.0 / 0.35)
	var pitch := half_depth * 2.0 / float(columns)
	for side in [-1.0, 1.0]:
		var downhill := Vector3(side * half_width, -rise, 0).normalized()
		var normal := Vector3(side * rise, half_width, 0).normalized()
		var ridge := Vector3(0, peak, 0)
		var roof_outline := PackedVector3Array([
			ridge + Vector3(0, 0, -half_depth), ridge + Vector3(0, 0, half_depth),
			ridge + downhill * length + Vector3(0, 0, half_depth), ridge + downhill * length + Vector3(0, 0, -half_depth),
		])
		var slab := SurfaceTool.new()
		slab.begin(Mesh.PRIMITIVE_TRIANGLES)
		_quad_facing(slab, roof_outline[0], roof_outline[1], roof_outline[2], roof_outline[3], Color.WHITE, normal)
		_quad_facing(slab, roof_outline[0] - normal * 0.085, roof_outline[1] - normal * 0.085, roof_outline[2] - normal * 0.085, roof_outline[3] - normal * 0.085, Color.WHITE, -normal)
		for edge in 4:
			var next := (edge + 1) % 4
			_quad(slab, roof_outline[edge], roof_outline[edge] - normal * 0.085, roof_outline[next] - normal * 0.085, roof_outline[next], Color.WHITE)
		_add_mesh(root, "Timber_Roof_Soffit", slab.commit(), p["wood_dark"], Vector3.ZERO)
		for row in rows:
			var d0 := float(row) * length / float(rows)
			var d1 := minf(d0 + length / float(rows) + 0.125, length + 0.045)
			for column in columns:
				var z_center := -half_depth + pitch * (float(column) + 0.5)
				var tile_color: Color = colors[posmod(row * 7 + column * 3 + (2 if side < 0.0 else 0), colors.size())]
				_roof_tile(st, ridge, downhill, normal, d0, d1, z_center, pitch + 0.025, 0.024 + float(rows - row) * 0.009, tile_color)
		for z_end in [-half_depth - 0.02, half_depth + 0.02]:
			_beam(root, "Carved_Bargeboard", Vector3(0, peak - 0.05, z_end), Vector3(side * (half_width + 0.07), eave - 0.095, z_end), 0.145, 0.16, p["wood"])
		_box(root, "Eave_Fascia", Vector3(0.14, 0.17, half_depth * 2.0 + 0.16), Vector3(side * half_width, eave - 0.06, 0), p["wood"], 0.028)
		for i in 7:
			_box(root, "Exposed_Rafter_End", Vector3(0.31, 0.10, 0.105), Vector3(side * (half_width - 0.03), eave - 0.11, -half_depth + 0.19 + float(i) * (half_depth * 2.0 - 0.38) / 6.0), p["wood_light"], 0.018)
	for column in columns:
		var z0 := -half_depth - 0.045 + pitch * float(column)
		_ridge_tile(st, peak + 0.072, z0, z0 + pitch + 0.065, colors[posmod(column + 1, colors.size())])
	var tile_material := _material("Hand_painted_ceramic_tiles", Color.WHITE)
	tile_material.vertex_color_use_as_albedo = true
	_add_mesh(root, "Individual_Curved_Roof_Tiles", st.commit(), tile_material, Vector3.ZERO)


static func _roof_tile(st: SurfaceTool, ridge: Vector3, downhill: Vector3, normal: Vector3, d0: float, d1: float, z: float, width: float, lift: float, tint: Color) -> void:
	var segments := 6
	for segment in segments:
		var u0 := float(segment) / float(segments)
		var u1 := float(segment + 1) / float(segments)
		var a := ridge + downhill * d0 + Vector3(0, 0, z + (u0 - 0.5) * width) + normal * (lift + sin(u0 * PI) * 0.048)
		var b := ridge + downhill * d1 + Vector3(0, 0, z + (u0 - 0.5) * width) + normal * (lift + sin(u0 * PI) * 0.048)
		var c := ridge + downhill * d1 + Vector3(0, 0, z + (u1 - 0.5) * width) + normal * (lift + sin(u1 * PI) * 0.048)
		var d := ridge + downhill * d0 + Vector3(0, 0, z + (u1 - 0.5) * width) + normal * (lift + sin(u1 * PI) * 0.048)
		_quad_facing(st, a, b, c, d, tint, normal)
		_quad_facing(st, b, b - normal * 0.047, c - normal * 0.047, c, tint.darkened(0.13), downhill)
		_quad_facing(st, a, a - normal * 0.047, d - normal * 0.047, d, tint.darkened(0.11), -downhill)
		if segment == 0:
			_quad_facing(st, a, b, b - normal * 0.047, a - normal * 0.047, tint.darkened(0.12), Vector3(0, 0, -1))
		if segment == segments - 1:
			_quad_facing(st, d, c, c - normal * 0.047, d - normal * 0.047, tint.darkened(0.12), Vector3(0, 0, 1))


static func _ridge_tile(st: SurfaceTool, y: float, z0: float, z1: float, tint: Color) -> void:
	for segment in 10:
		var a0 := PI * float(segment) / 10.0
		var a1 := PI * float(segment + 1) / 10.0
		var a := Vector3(cos(a0) * 0.17, y + sin(a0) * 0.17, z0)
		var b := Vector3(cos(a0) * 0.17, y + sin(a0) * 0.17, z1)
		var c := Vector3(cos(a1) * 0.17, y + sin(a1) * 0.17, z1)
		var d := Vector3(cos(a1) * 0.17, y + sin(a1) * 0.17, z0)
		_quad_facing(st, a, b, c, d, tint.lightened(0.06), Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), 0))
		var ai := Vector3(cos(a0) * 0.128, y + sin(a0) * 0.128, z1)
		var ci := Vector3(cos(a1) * 0.128, y + sin(a1) * 0.128, z1)
		_quad_facing(st, b, ai, ci, c, tint.darkened(0.16), Vector3(0, 0, 1))


static func _front_window(root: Node3D, label: String, pos: Vector3, width: float, height: float, p: Dictionary, shutters: bool) -> void:
	var group := Node3D.new()
	group.name = label
	group.position = pos
	root.add_child(group)
	_box(group, "Deep_Recess", Vector3(width + 0.19, height + 0.19, 0.14), Vector3(0, 0, 0.005), p["wood_dark"], 0.035)
	_box(group, "Glazed_Opening", Vector3(width - 0.055, height - 0.055, 0.065), Vector3(0, 0, 0.10), p["glass"], 0.012)
	for edge in [-1.0, 1.0]:
		_box(group, "Window_Jamb", Vector3(0.083, height + 0.08, 0.14), Vector3(edge * width * 0.5, 0, 0.135), p["wood_light"], 0.016)
		_box(group, "Window_Rail", Vector3(width + 0.14, 0.088, 0.15), Vector3(0, edge * height * 0.5, 0.135), p["wood_light"], 0.018)
	_box(group, "Window_Mullion", Vector3(0.046, height, 0.078), Vector3(0, 0, 0.18), p["canvas_cream"], 0.009)
	_box(group, "Window_Crossbar", Vector3(width, 0.045, 0.078), Vector3(0, 0.015, 0.18), p["canvas_cream"], 0.009)
	if width > 1.6:
		for side in [-1.0, 1.0]:
			_box(group, "Bay_Extra_Mullion", Vector3(0.05, height, 0.08), Vector3(side * width * 0.29, 0, 0.18), p["canvas_cream"], 0.009)
	for side in [-1.0, 1.0]:
		var glint := _box(group, "Painted_Glass_Glint", Vector3(width * 0.07, height * 0.29, 0.008), Vector3(side * width * 0.22, height * 0.18, 0.139), p["glass_light"], 0.004)
		glint.rotation.z = -0.22
	_box(group, "Projecting_Window_Sill", Vector3(width + 0.30, 0.12, 0.37), Vector3(0, -height * 0.5 - 0.08, 0.14), p["wood_light"], 0.028)
	if shutters:
		for side in [-1.0, 1.0]:
			var shutter := Node3D.new()
			shutter.name = "Louvered_Shutter"
			shutter.position = Vector3(side * (width * 0.5 + 0.23), 0, 0.07)
			shutter.rotation.y = side * 0.14
			group.add_child(shutter)
			_box(shutter, "Shutter_Back", Vector3(0.34, height + 0.13, 0.065), Vector3.ZERO, p["teal_dark"], 0.019)
			for edge in [-1.0, 1.0]:
				_box(shutter, "Shutter_Stile", Vector3(0.044, height + 0.13, 0.08), Vector3(edge * 0.15, 0, 0.037), p["teal_light"], 0.011)
				_box(shutter, "Shutter_Rail", Vector3(0.34, 0.06, 0.08), Vector3(0, edge * (height * 0.5 + 0.03), 0.036), p["teal_light"], 0.011)
			for slat in 7:
				var louver := _box(shutter, "Angled_Shutter_Louver", Vector3(0.265, height / 8.0, 0.055), Vector3(0, -height * 0.42 + float(slat) * height * 0.14, 0.063), p["teal"], 0.009)
				louver.rotation.x = -0.20
			for hinge_y in [-0.30, 0.30]:
				_box(shutter, "Shutter_Hinge", Vector3(0.13, 0.025, 0.018), Vector3(-side * 0.10, hinge_y * height, 0.088), p["iron"], 0.004)
		var flowers := MarketProps.flower_box(width + 0.10)
		flowers.name = "Flower_Box"
		flowers.position = Vector3(0, -height * 0.5 - 0.30, 0.26)
		group.add_child(flowers)


static func _door(root: Node3D, pos: Vector3, width: float, height: float, p: Dictionary) -> void:
	var group := Node3D.new()
	group.name = "Arched_Oak_Door"
	group.position = pos
	root.add_child(group)
	_extruded_outline(group, "Deep_Arched_Portal", _arch_outline(width + 0.24, height + 0.13), 0.21, Vector3(0, 0, 0.025), p["wood_dark"])
	_extruded_outline(group, "Arched_Door_Leaf", _arch_outline(width, height), 0.14, Vector3(0, 0.055, 0.16), p["wood_warm"])
	var board_width := width / 7.0
	for i in 7:
		var x := -width * 0.5 + board_width * (float(i) + 0.5)
		var radius := width * 0.5
		var board_height := height - radius + sqrt(maxf(radius * radius - pow(absf(x) + board_width * 0.46, 2.0), 0.0)) - 0.075
		_box(group, "Individual_Door_Plank", Vector3(board_width - 0.012, board_height, 0.022), Vector3(x, board_height * 0.5 + 0.075, 0.238), p["wood_light"] if i % 3 == 0 else p["wood_warm"], 0.008)
	for y in [0.38, 1.18]:
		_box(group, "Forged_Door_Hinge", Vector3(width * 0.32, 0.058, 0.027), Vector3(-width * 0.30, y, 0.262), p["iron"], 0.012)
		for offset in [-0.055, 0.055]:
			_sphere(group, "Hinge_Rivet", 0.012, Vector3(-width * 0.30 + offset, y, 0.282), p["brass"])
	_box(group, "Handle_Backplate", Vector3(0.07, 0.16, 0.024), Vector3(width * 0.31, 0.92, 0.26), p["iron"], 0.022)
	_sphere(group, "Brass_Door_Handle", 0.038, Vector3(width * 0.31, 0.96, 0.31), p["brass"])
	var diamond := _box(group, "Door_Diamond_Frame", Vector3(0.265, 0.265, 0.045), Vector3(0, 1.40, 0.272), p["wood_dark"], 0.012)
	diamond.rotation.z = PI / 4.0
	var glass := _box(group, "Door_Diamond_Glass", Vector3(0.182, 0.182, 0.027), Vector3(0, 1.40, 0.304), p["glass_light"], 0.006)
	glass.rotation.z = PI / 4.0


static func _arch_outline(width: float, height: float) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2(-width * 0.5, 0), Vector2(width * 0.5, 0)])
	var radius := width * 0.5
	for i in 13:
		var angle := PI * float(i) / 12.0
		points.append(Vector2(cos(angle) * radius, height - radius + sin(angle) * radius))
	return points


static func _round_attic_window(root: Node3D, pos: Vector3, radius: float, p: Dictionary) -> void:
	var glass := _cylinder(root, "Round_Attic_Glass", radius * 0.85, radius * 0.85, 0.075, pos + Vector3(0, 0, 0.075), p["glass"])
	glass.rotation.x = PI / 2.0
	var rim := TorusMesh.new()
	rim.inner_radius = radius * 0.83
	rim.outer_radius = radius + 0.042
	rim.rings = 24
	rim.ring_segments = 6
	var node := _add_mesh(root, "Round_Attic_Timber_Frame", rim, p["wood_light"], pos + Vector3(0, 0, 0.105))
	node.rotation.x = PI / 2.0
	_box(root, "Round_Window_Vertical", Vector3(0.045, radius * 1.62, 0.04), pos + Vector3(0, 0, 0.137), p["canvas_cream"], 0.008)
	_box(root, "Round_Window_Horizontal", Vector3(radius * 1.62, 0.045, 0.04), pos + Vector3(0, 0, 0.137), p["canvas_cream"], 0.008)


static func _portrait_porch(root: Node3D, pos: Vector3, p: Dictionary) -> void:
	var porch := Node3D.new()
	porch.name = "Small_Timber_Porch"
	porch.position = pos
	root.add_child(porch)
	var canopy := _box(porch, "Painted_Porch_Canopy", Vector3(1.70, 0.105, 0.99), Vector3(0, 2.40, 0.45), p["teal_dark"], 0.035)
	canopy.rotation.x = 0.20
	for i in 7:
		var seam := _box(porch, "Canopy_Raised_Seam", Vector3(0.018, 0.034, 0.985), Vector3(-0.72 + float(i) * 0.24, 2.462, 0.45), p["teal"], 0.007)
		seam.rotation.x = 0.20
	_box(porch, "Canopy_Front_Fascia", Vector3(1.79, 0.12, 0.12), Vector3(0, 2.30, 0.96), p["wood_light"], 0.025)
	for side in [-1.0, 1.0]:
		_beam(porch, "Porch_Carved_Bracket", Vector3(side * 0.66, 1.86, 0.10), Vector3(side * 0.66, 2.30, 0.77), 0.088, 0.088, p["wood"])
		_box(porch, "Bracket_Wall_Mount", Vector3(0.105, 0.54, 0.115), Vector3(side * 0.66, 2.08, 0.08), p["wood"], 0.02)


static func _chimney(root: Node3D, pos: Vector3, p: Dictionary) -> void:
	var chimney := Node3D.new()
	chimney.name = "Handlaid_Brick_Chimney"
	chimney.position = pos
	root.add_child(chimney)
	_box(chimney, "Chimney_Mortar_Core", Vector3(0.51, 1.43, 0.55), Vector3(0, 0.715, 0), p["mortar"], 0.025)
	for row in 9:
		var y := 0.10 + float(row) * 0.147
		for side in [-1.0, 1.0]:
			for brick in 2:
				var x := (float(brick) - 0.5) * 0.25
				_box(chimney, "Warm_Front_Brick", Vector3(0.233, 0.124, 0.067), Vector3(x + 0.008 * sin(float(row)), y, side * 0.267), p["terra_light"] if (row + brick) % 3 == 0 else p["terra"], 0.018)
				_box(chimney, "Warm_Side_Brick", Vector3(0.067, 0.124, 0.245), Vector3(side * 0.25, y, x), p["terra"] if (row + brick) % 3 == 0 else p["terra_light"], 0.016)
	_box(chimney, "Chimney_Dark_Opening", Vector3(0.41, 0.025, 0.43), Vector3(0, 1.42, 0), p["wood_dark"], 0.008)
	for side in [-1.0, 1.0]:
		_box(chimney, "Chimney_Stone_Coping", Vector3(0.69, 0.14, 0.115), Vector3(0, 1.44, side * 0.29), p["stone_light"], 0.025)
		_box(chimney, "Chimney_Side_Coping", Vector3(0.115, 0.14, 0.50), Vector3(side * 0.285, 1.44, 0), p["stone_light"], 0.023)


static func _striped_awning(root: Node3D, pos: Vector3, width: float, p: Dictionary) -> void:
	var awning := Node3D.new()
	awning.name = "Ochre_And_Cream_Canvas_Awning"
	awning.position = pos
	root.add_child(awning)
	var stripe_count := 11
	var stripe_width := width / float(stripe_count)
	for stripe in stripe_count:
		var x0 := -width * 0.5 + float(stripe) * stripe_width
		var x1 := x0 + stripe_width - 0.003
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for section in 8:
			var t0 := float(section) / 8.0
			var t1 := float(section + 1) / 8.0
			var y0 := 2.46 - 0.27 * t0 - 0.072 * sin(t0 * PI)
			var y1 := 2.46 - 0.27 * t1 - 0.072 * sin(t1 * PI)
			_quad_facing(st, Vector3(x0, y0, t0 * 1.13), Vector3(x1, y0, t0 * 1.13), Vector3(x1, y1, t1 * 1.13), Vector3(x0, y1, t1 * 1.13), Color.WHITE, Vector3.UP)
		var valance := PackedVector2Array([Vector2(x0, 2.19), Vector2(x1, 2.19)])
		for i in 9:
			var u := float(i) / 8.0
			valance.append(Vector2(lerpf(x1, x0, u), 2.045 - sin(u * PI) * 0.064))
		var mat: StandardMaterial3D = p["canvas_cream"] if stripe % 2 == 0 else p["canvas_gold"]
		_add_mesh(awning, "Curved_Linen_Stripe", st.commit(), mat, Vector3.ZERO)
		_extruded_outline(awning, "Scalloped_Valance", valance, 0.024, Vector3(0, 0, 1.14), mat)
	for side in [-1.0, 1.0]:
		_box(awning, "Awning_Timber_Post", Vector3(0.088, 2.20, 0.088), Vector3(side * (width * 0.5 - 0.07), 1.10, 1.10), p["wood"], 0.019)
		_sphere(awning, "Awning_Post_Finial", 0.068, Vector3(side * (width * 0.5 - 0.07), 2.225, 1.10), p["wood_light"])
		_beam(awning, "Awning_Side_Rail", Vector3(side * width * 0.5, 2.43, 0), Vector3(side * width * 0.5, 2.16, 1.14), 0.045, 0.045, p["wood_dark"])
	_box(awning, "Awning_Front_Rail", Vector3(width + 0.05, 0.047, 0.06), Vector3(0, 2.18, 1.11), p["wood"], 0.012)


static func _shop_sign(root: Node3D, pos: Vector3, p: Dictionary) -> void:
	var sign := Node3D.new()
	sign.name = "Hanging_Radish_Seed_Sign"
	sign.position = pos
	root.add_child(sign)
	_box(sign, "Sign_Wall_Bracket", Vector3(0.11, 0.60, 0.11), Vector3(0, 0.43, -0.07), p["wood_dark"], 0.022)
	_box(sign, "Sign_Outrigger", Vector3(0.11, 0.095, 0.48), Vector3(0, 0.64, 0.15), p["wood_dark"], 0.025)
	_beam(sign, "Sign_Bracket_Brace", Vector3(0, 0.30, -0.06), Vector3(0, 0.61, 0.30), 0.038, 0.045, p["iron"])
	for side in [-1.0, 1.0]:
		_cylinder(sign, "Sign_Hanger", 0.011, 0.011, 0.19, Vector3(side * 0.21, 0.48, 0.31), p["iron"])
	_box(sign, "Carved_Sign_Board", Vector3(0.72, 0.61, 0.095), Vector3(0, 0.10, 0.31), p["wood_light"], 0.065)
	_box(sign, "Cream_Painted_Sign_Face", Vector3(0.59, 0.49, 0.027), Vector3(0, 0.10, 0.369), p["canvas_cream"], 0.042)
	var bulb := _sphere(sign, "Raised_Radish_Emblem", 0.128, Vector3(0, 0.08, 0.410), p["terra"])
	bulb.scale = Vector3(0.97, 0.90, 0.39)
	var tip := _cylinder(sign, "Radish_White_Tip", 0.062, 0.009, 0.115, Vector3(0, -0.046, 0.411), p["canvas_cream"])
	tip.scale.z = 0.6
	for i in 3:
		var leaf := _sphere(sign, "Raised_Radish_Leaf", 0.082, Vector3((float(i) - 1.0) * 0.063, 0.247, 0.412), p["leaf_light"] if i == 1 else p["teal"])
		leaf.scale = Vector3(0.42, 1.0, 0.25)
		leaf.rotation.z = (1.0 - float(i)) * 0.51


static func _lantern(root: Node3D, pos: Vector3, p: Dictionary) -> void:
	var lantern := Node3D.new()
	lantern.name = "Forged_Hanging_Lantern"
	lantern.position = pos
	root.add_child(lantern)
	_box(lantern, "Lantern_Wall_Plate", Vector3(0.10, 0.29, 0.04), Vector3(0, 0.23, -0.07), p["iron"], 0.027)
	_beam(lantern, "Lantern_Bracket", Vector3(0, 0.35, -0.06), Vector3(0, 0.35, 0.21), 0.032, 0.034, p["iron"])
	_cylinder(lantern, "Lantern_Hanger", 0.016, 0.016, 0.12, Vector3(0, 0.27, 0.21), p["iron"])
	_cylinder(lantern, "Lantern_Roof", 0.025, 0.147, 0.105, Vector3(0, 0.162, 0.21), p["iron"])
	_cylinder(lantern, "Amber_Glass_Chamber", 0.102, 0.096, 0.235, Vector3(0, 0.0, 0.21), p["warm_glass"])
	_cylinder(lantern, "Lantern_Base", 0.123, 0.085, 0.06, Vector3(0, -0.145, 0.21), p["iron"])
	for i in 4:
		var angle := PI * 0.25 + PI * 0.5 * float(i)
		_cylinder(lantern, "Lantern_Glass_Stile", 0.010, 0.010, 0.245, Vector3(cos(angle) * 0.105, -0.003, 0.21 + sin(angle) * 0.105), p["iron"])


static func _flower_pot(root: Node3D, pos: Vector3, factor: float, p: Dictionary) -> void:
	var pot := Node3D.new()
	pot.name = "Terracotta_Herb_Pot"
	pot.position = pos
	pot.scale = Vector3.ONE * factor
	root.add_child(pot)
	_cylinder(pot, "Thrown_Clay_Pot", 0.17, 0.11, 0.27, Vector3(0, 0.145, 0), p["terra"])
	_cylinder(pot, "Rolled_Clay_Rim", 0.19, 0.19, 0.055, Vector3(0, 0.285, 0), p["terra_light"])
	_cylinder(pot, "Visible_Potting_Soil", 0.154, 0.154, 0.014, Vector3(0, 0.317, 0), p["soil"])
	for i in 7:
		var a := float(i) * TAU / 7.0
		var leaf := _sphere(pot, "Pot_Herb_Leaf", 0.105, Vector3(cos(a) * 0.10, 0.44 + 0.04 * sin(float(i) * 2.0), sin(a) * 0.10), p["leaf_light"] if i % 3 == 0 else p["leaf"])
		leaf.scale = Vector3(0.62, 1.25, 0.45)
		leaf.rotation.z = -cos(a) * 0.5
		leaf.rotation.x = sin(a) * 0.5


static func _box(root: Node3D, label: String, size: Vector3, pos: Vector3, material: StandardMaterial3D, bevel: float = 0.025) -> MeshInstance3D:
	var b := minf(bevel, minf(size.x, minf(size.y, size.z)) * 0.30)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var levels := PackedFloat32Array([-size.y * 0.5, -size.y * 0.5 + b, size.y * 0.5 - b, size.y * 0.5])
	var rings: Array[PackedVector3Array] = []
	for level in 4:
		var inset := b if level == 0 or level == 3 else 0.0
		var hx := size.x * 0.5 - inset
		var hz := size.z * 0.5 - inset
		var corner := minf(b * 0.65, minf(hx, hz) * 0.40)
		var points := PackedVector2Array([
			Vector2(-hx + corner, -hz), Vector2(hx - corner, -hz), Vector2(hx, -hz + corner), Vector2(hx, hz - corner),
			Vector2(hx - corner, hz), Vector2(-hx + corner, hz), Vector2(-hx, hz - corner), Vector2(-hx, -hz + corner),
		])
		var ring := PackedVector3Array()
		for point in points:
			ring.append(Vector3(point.x, levels[level], point.y))
		rings.append(ring)
	for level in 3:
		for edge in 8:
			var next := (edge + 1) % 8
			_quad(st, rings[level][edge], rings[level + 1][edge], rings[level + 1][next], rings[level][next], Color.WHITE)
	for edge in 8:
		var next := (edge + 1) % 8
		_tri(st, Vector3(0, levels[0], 0), rings[0][edge], rings[0][next], Color.WHITE)
		_tri(st, Vector3(0, levels[3], 0), rings[3][next], rings[3][edge], Color.WHITE)
	return _add_mesh(root, label, st.commit(), material, pos)


static func _beam(root: Node3D, label: String, a: Vector3, b: Vector3, width: float, depth: float, material: StandardMaterial3D) -> MeshInstance3D:
	var node := _box(root, label, Vector3(width, a.distance_to(b), depth), (a + b) * 0.5, material, minf(width, depth) * 0.16)
	node.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	return node


static func _sphere(root: Node3D, label: String, radius: float, pos: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return _add_mesh(root, label, mesh, material, pos)


static func _cylinder(root: Node3D, label: String, top_radius: float, bottom_radius: float, height: float, pos: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	return _add_mesh(root, label, mesh, material, pos)


static func _extruded_outline(root: Node3D, label: String, outline: PackedVector2Array, depth: float, pos: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var triangles := Geometry2D.triangulate_polygon(outline)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, triangles.size(), 3):
		var a := outline[triangles[i]]
		var b := outline[triangles[i + 1]]
		var c := outline[triangles[i + 2]]
		_tri_facing(st, Vector3(a.x, a.y, depth * 0.5), Vector3(b.x, b.y, depth * 0.5), Vector3(c.x, c.y, depth * 0.5), Color.WHITE, Vector3(0, 0, 1))
		_tri_facing(st, Vector3(a.x, a.y, -depth * 0.5), Vector3(b.x, b.y, -depth * 0.5), Vector3(c.x, c.y, -depth * 0.5), Color.WHITE, Vector3(0, 0, -1))
	for i in outline.size():
		var next := (i + 1) % outline.size()
		var a := outline[i]
		var b := outline[next]
		_quad(st, Vector3(a.x, a.y, -depth * 0.5), Vector3(b.x, b.y, -depth * 0.5), Vector3(b.x, b.y, depth * 0.5), Vector3(a.x, a.y, depth * 0.5), Color.WHITE)
	return _add_mesh(root, label, st.commit(), material, pos)


static func _add_mesh(root: Node3D, label: String, mesh: Mesh, material: StandardMaterial3D, pos: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	root.add_child(node)
	return node


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	st.set_color(tint.srgb_to_linear())  # glTF vertex colours are linear, unlike the palette swatches.
	st.set_normal(normal)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)  # Godot uses clockwise front faces; retain the outward normal.


static func _tri_facing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color, normal_hint: Vector3) -> void:
	if (b - a).cross(c - a).dot(normal_hint) < 0.0:
		_tri(st, a, c, b, tint)
	else:
		_tri(st, a, b, c, tint)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, tint: Color) -> void:
	_tri(st, a, b, c, tint)
	_tri(st, a, c, d, tint)


static func _quad_facing(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, tint: Color, normal_hint: Vector3) -> void:
	_tri_facing(st, a, b, c, tint, normal_hint)
	_tri_facing(st, a, c, d, tint, normal_hint)
