extends RefCounted
## A self-contained, exportable, unskinned 3D farmer. Metres; Y up; +Z forward.
## All decoration is geometry. No external textures, plugins or imported assets.

const BODY_HEIGHT := 0.655
const JOINT_PATHS := [
	"Body/HeadPivot", "Body/Arm_L", "Body/Arm_R",
	"Body/Arm_L/Elbow_L", "Body/Arm_R/Elbow_R",
	"Body/Leg_L", "Body/Leg_R",
	"Body/Leg_L/Knee_L", "Body/Leg_R/Knee_R",
]
const HEAD_PROFILE := [
	Vector4(0.044, -0.213, 0.060, 0.020), Vector4(0.117, -0.192, 0.137, 0.017),
	Vector4(0.187, -0.148, 0.180, 0.005), Vector4(0.230, -0.076, 0.199, 0),
	Vector4(0.245, 0.010, 0.204, 0), Vector4(0.231, 0.094, 0.195, -0.005),
	Vector4(0.173, 0.170, 0.151, -0.010), Vector4(0.062, 0.215, 0.058, -0.008),
]
const CALF_PROFILE := [
	Vector4(0.087, -0.169, 0.098, 0), Vector4(0.101, -0.145, 0.110, 0),
	Vector4(0.106, -0.068, 0.117, 0), Vector4(0.107, 0.015, 0.118, 0),
	Vector4(0.091, 0.041, 0.104, 0),
]


static func build(variant: int = 0) -> Node3D:
	var alternate: bool = posmod(variant, 2) == 1
	var root := Node3D.new()
	root.name = "Farmer_Moss" if alternate else "Farmer_Indigo"
	root.set_meta("asset_type", "original_procedural_character")
	root.set_meta("variant", posmod(variant, 2))
	root.set_meta("forward_axis", "+Z")
	root.set_meta("units", "metres")
	root.set_meta("joint_paths", PackedStringArray(JOINT_PATHS))
	root.set_meta("animations", PackedStringArray(["idle", "walk"]))
	var palette: Dictionary = {
		"skin": _material("Warm skin", "e6ad80", 0.9),
		"skin_shade": _material("Warm ear and fingers", "d69570", 0.93),
		"blush": _material("Soft peach cheeks", "d88b72", 1.0),
		"shirt": _material("Unbleached linen", "e7ddba", 0.98),
		"collar": _material("Linen folded edge", "f1e7ca", 0.98),
		"shirt_seam": _material("Linen seams", "c4b897", 1.0),
		"cloth": _material("Moss twill" if alternate else "Indigo twill", "687b58" if alternate else "526f88", 0.98),
		"cloth_light": _material("Worn cloth folds", "829269" if alternate else "718aa0", 1.0),
		"cloth_dark": _material("Cloth recesses", "45563e" if alternate else "364f66", 1.0),
		"thread": _material("Ochre topstitch", "c1ac78", 1.0),
		"brass": _material("Aged brass", "b88948", 0.62, 0.25),
		"leather": _material("Oiled honey leather", "966944", 0.91),
		"leather_light": _material("Leather worn edges", "b38758", 0.96),
		"boot": _material("Soft brown boot leather", "684938", 0.93),
		"sole": _material("Dark stacked soles", "3e342b", 1.0),
		"hair": _material("Copper hair" if alternate else "Chestnut hair", "8a4e35" if alternate else "5b382c", 0.96),
		"hair_light": _material("Hair sunlit strands", "b27246" if alternate else "845336", 1.0),
		"straw": _material("Golden straw", "d1aa62", 1.0),
		"straw_light": _material("Straw woven highlights", "e7c987", 1.0),
		"straw_dark": _material("Straw woven shadows", "b88f4e", 1.0),
		"hat_band": _material("Woven hat ribbon", "a65f42" if alternate else "637660", 1.0),
		"eye_white": _material("Warm eye whites", "fff0d9", 0.65),
		"eye": _material("Chocolate eyes", "342a24", 0.4),
		"glint": _material("Eye catchlights", "fff7df", 0.35),
		"mouth": _material("Smile", "875444", 0.94),
		"steel": _material("Well used tool steel", "83908a", 0.72, 0.32),
		"leaf": _material("Fresh sprig", "82995b", 0.96),
	}
	var body := _pivot(root, "Body", Vector3(0, BODY_HEIGHT, 0))
	_make_torso(body, palette)
	for side: int in [-1, 1]:
		_make_leg(body, side, palette)
		_make_arm(body, side, palette)
	_make_head(body, alternate, palette)
	_make_satchel(body, palette)
	_add_animations(root)
	_set_owners(root, root)
	return root


static func _make_torso(body: Node3D, p: Dictionary) -> void:
	_loft(body, "LinenShirt", [
		Vector4(0.184, 0.090, 0.120, 0), Vector4(0.218, 0.126, 0.137, 0),
		Vector4(0.214, 0.230, 0.144, 0), Vector4(0.241, 0.342, 0.146, 0),
		Vector4(0.246, 0.385, 0.133, -0.004), Vector4(0.199, 0.433, 0.112, 0),
		Vector4(0.083, 0.464, 0.071, 0),
	], p.shirt)
	_ellipsoid(body, "Neck", Vector3(0, 0.481, 0), Vector3(0.075, 0.074, 0.073), p.skin)
	_loft(body, "OverallsWaist", [
		Vector4(0.166, -0.023, 0.112, 0), Vector4(0.220, 0.002, 0.143, 0),
		Vector4(0.227, 0.092, 0.148, 0), Vector4(0.218, 0.146, 0.137, 0),
		Vector4(0.204, 0.160, 0.132, 0),
	], p.cloth)
	_panel(body, "CurvedBib", Vector3(0, 0.277, 0.153), Vector2(0.324, 0.292), 0.025, 0.038, p.cloth, 0.050)
	_panel(body, "BibPocket", Vector3(0, 0.265, 0.178), Vector2(0.166, 0.100), 0.013, 0.023, p.cloth_light, 0.010)
	var seams: Array = [
		_path([Vector3(-0.073, 0.306, 0.187), Vector3(-0.073, 0.238, 0.190), Vector3(-0.054, 0.222, 0.191), Vector3(0.055, 0.222, 0.191), Vector3(0.073, 0.238, 0.190), Vector3(0.073, 0.306, 0.187)]),
		_path([Vector3(-0.148, 0.391, 0.124), Vector3(-0.144, 0.245, 0.130), Vector3(-0.137, 0.155, 0.130)]),
		_path([Vector3(0.148, 0.391, 0.124), Vector3(0.144, 0.245, 0.130), Vector3(0.137, 0.155, 0.130)]),
	]
	_tubes(body, "BibTopstitch", seams, 0.0017, p.thread, 5)
	_tubes(body, "PocketOpening", [_path([Vector3(-0.069, 0.308, 0.188), Vector3(0, 0.308, 0.192), Vector3(0.069, 0.308, 0.188)])], 0.0024, p.cloth_dark, 6)
	for side: int in [-1, 1]:
		var x: float = 0.146 * side
		var strap_points := _path([
			Vector3(x, 0.346, 0.131), Vector3(x, 0.423, 0.125),
			Vector3(x, 0.472, 0.082), Vector3(x, 0.481, 0.013),
			Vector3(x, 0.458, -0.080), Vector3(x, 0.372, -0.123),
			Vector3(x * 0.64, 0.161, -0.137),
		])
		_ribbon(body, "ShoulderStrap" + str(side), strap_points, 0.043, 0.013, p.cloth)
		_tubes(body, "StrapStitch" + str(side), [_path([
			Vector3(x - side * 0.014, 0.360, 0.140), Vector3(x - side * 0.014, 0.423, 0.136),
			Vector3(x - side * 0.014, 0.472, 0.091), Vector3(x - side * 0.014, 0.485, 0.015),
			Vector3(x - side * 0.014, 0.463, -0.084), Vector3(x - side * 0.014, 0.374, -0.132),
		])], 0.0015, p.thread, 5)
		_button(body, "BibButton" + str(side), Vector3(x, 0.354, 0.145), 0.012, p.brass)
		var collar := _panel(body, "Collar" + str(side), Vector3(side * 0.061, 0.444, 0.104), Vector2(0.091, 0.074), 0.020, 0.016, p.collar)
		collar.rotation.z = side * 0.43
		_tubes(body, "WaistPocket" + str(side), [_path([
			Vector3(side * 0.180, 0.120, 0.102), Vector3(side * 0.162, 0.074, 0.122),
			Vector3(side * 0.184, 0.035, 0.106),
		])], 0.0025, p.cloth_light, 6)
		var back_pocket := _panel(body, "BackPocket" + str(side), Vector3(side * 0.117, 0.063, -0.137), Vector2(0.120, 0.118), 0.010, 0.020, p.cloth_light, 0.008)
		back_pocket.rotation.y = PI + side * 0.17
	_button(body, "ShirtButton", Vector3(0, 0.430, 0.124), 0.006, p.shirt_seam)
	# A small folded kerchief adds a readable asymmetry without obscuring the bib.
	var kerchief := _panel(body, "PocketKerchief", Vector3(-0.041, 0.325, 0.182), Vector2(0.036, 0.048), 0.005, 0.004, p.hat_band)
	kerchief.rotation.z = 0.16


static func _make_leg(body: Node3D, side: int, p: Dictionary) -> void:
	var suffix: String = "L" if side < 0 else "R"
	var leg := _pivot(body, "Leg_" + suffix, Vector3(side * 0.126, 0, 0))
	_loft(leg, "TrouserThigh", [
		Vector4(0.093, -0.237, 0.111, 0), Vector4(0.109, -0.198, 0.119, 0),
		Vector4(0.119, -0.098, 0.130, 0), Vector4(0.118, 0.023, 0.125, 0),
		Vector4(0.090, 0.066, 0.092, 0),
	], p.cloth)
	var knee := _pivot(leg, "Knee_" + suffix, Vector3(0, -0.215, 0))
	_loft(knee, "TrouserCalf", CALF_PROFILE, p.cloth)
	_loft(knee, "RolledTrouserHem", [
		Vector4(0.090, -0.165, 0.100, 0), Vector4(0.104, -0.155, 0.113, 0),
		Vector4(0.105, -0.117, 0.113, 0), Vector4(0.094, -0.105, 0.105, 0),
	], p.cloth_light)
	_loft(knee, "BootSole", [
		Vector4(0.090, -0.440, 0.145, 0.043), Vector4(0.108, -0.432, 0.172, 0.043),
		Vector4(0.111, -0.407, 0.176, 0.043), Vector4(0.107, -0.390, 0.168, 0.043),
	], p.sole)
	_loft(knee, "LeatherBoot", [
		Vector4(0.097, -0.398, 0.154, 0.044), Vector4(0.106, -0.370, 0.160, 0.043),
		Vector4(0.104, -0.337, 0.151, 0.037), Vector4(0.099, -0.287, 0.127, 0.014),
		Vector4(0.093, -0.223, 0.108, -0.009), Vector4(0.095, -0.146, 0.107, -0.009),
		Vector4(0.087, -0.123, 0.096, -0.009),
	], p.boot)
	var boot_welt := PackedVector3Array()
	for i: int in range(49):
		var a: float = TAU * i / 48.0
		boot_welt.append(Vector3(sin(a) * 0.106, -0.390, cos(a) * 0.165 + 0.043))
	_tubes(knee, "BootWelt", [boot_welt], 0.0025, p.leather_light, 5)
	_tubes(knee, "BootToeSeam", [_path([
		Vector3(-0.080, -0.332, 0.112), Vector3(-0.045, -0.325, 0.151),
		Vector3(0, -0.322, 0.162), Vector3(0.045, -0.325, 0.151), Vector3(0.080, -0.332, 0.112),
	])], 0.0018, p.leather_light, 5)
	var boot_tab := _panel(knee, "BootPullTab", Vector3(0, -0.156, -0.116), Vector2(0.028, 0.057), 0.016, 0.011, p.leather)
	boot_tab.rotation.x = -0.10
	_tubes(leg, "OutsideTrouserSeam", [_path([
		Vector3(side * 0.112, 0.005, 0.033), Vector3(side * 0.118, -0.092, 0.034),
		Vector3(side * 0.109, -0.202, 0.030),
	])], 0.0018, p.thread, 5)
	_tubes(knee, "SoftKneeFolds", [
		_surface_path(CALF_PROFILE, [Vector3(-0.070, -0.023, 0.087), Vector3(-0.021, -0.035, 0.116), Vector3(0.046, -0.025, 0.105)]),
		_surface_path(CALF_PROFILE, [Vector3(-0.052, -0.083, 0.096), Vector3(0.001, -0.074, 0.116), Vector3(0.062, -0.083, 0.096)]),
	], 0.0021, p.cloth_light, 5)


static func _make_arm(body: Node3D, side: int, p: Dictionary) -> void:
	var suffix: String = "L" if side < 0 else "R"
	var arm := _pivot(body, "Arm_" + suffix, Vector3(side * 0.253, 0.441, 0))
	arm.rotation.z = side * 0.11
	_loft(arm, "ShortLinenSleeve", [
		Vector4(0.060, -0.170, 0.063, 0.007), Vector4(0.078, -0.149, 0.080, 0),
		Vector4(0.084, -0.051, 0.091, 0), Vector4(0.063, 0.011, 0.072, 0),
		Vector4(0.024, 0.027, 0.035, 0),
	], p.shirt)
	_loft(arm, "RolledSleeve", [
		Vector4(0.061, -0.167, 0.064, 0.007), Vector4(0.080, -0.157, 0.080, 0.007),
		Vector4(0.081, -0.124, 0.081, 0.007), Vector4(0.074, -0.115, 0.076, 0.007),
	], p.collar)
	_ellipsoid(arm, "UpperArm", Vector3(0, -0.167, 0.010), Vector3(0.057, 0.082, 0.059), p.skin)
	var elbow := _pivot(arm, "Elbow_" + suffix, Vector3(side * 0.009, -0.203, 0.014))
	_ellipsoid(elbow, "Forearm", Vector3(side * 0.004, -0.073, 0.007), Vector3(0.056, 0.107, 0.057), p.skin)
	_ellipsoid(elbow, "Palm", Vector3(side * 0.010, -0.180, 0.010), Vector3(0.060, 0.069, 0.047), p.skin)
	var thumb := _ellipsoid(elbow, "Thumb", Vector3(-side * 0.032, -0.169, 0.044), Vector3(0.025, 0.043, 0.026), p.skin)
	thumb.rotation.z = -side * 0.32
	var finger_marks: Array = []
	for i: int in range(3):
		var x: float = -0.019 + i * 0.018
		finger_marks.append(_path([Vector3(x, -0.211, 0.046), Vector3(x + side * 0.002, -0.219, 0.036)]))
	_tubes(elbow, "FingerCreases", finger_marks, 0.0015, p.skin_shade, 5)
	_tubes(arm, "SleeveFold", [_path([
		Vector3(side * 0.062, -0.045, 0.050), Vector3(side * 0.069, -0.081, 0.047),
		Vector3(side * 0.055, -0.107, 0.054),
	])], 0.0016, p.shirt_seam, 5)


static func _make_head(body: Node3D, alternate: bool, p: Dictionary) -> void:
	var head := _pivot(body, "HeadPivot", Vector3(0, 0.522, 0))
	var face := _pivot(head, "Face", Vector3(0, 0.167, 0))
	_loft(face, "SculptedHead", HEAD_PROFILE, p.skin, 48, 4)
	for side: int in [-1, 1]:
		_ellipsoid(face, "Ear" + str(side), Vector3(side * 0.239, 0.005, -0.006), Vector3(0.053, 0.067, 0.043), p.skin)
		var inner := _ellipsoid(face, "EarInner" + str(side), Vector3(side * 0.263, 0.004, 0.022), Vector3(0.023, 0.040, 0.010), p.skin_shade)
		inner.rotation.y = side * 0.54
		var cheek := _ellipsoid(face, "Cheek" + str(side), Vector3(side * 0.143, -0.040, 0.168), Vector3(0.043, 0.021, 0.006), p.blush)
		cheek.rotation.y = side * 0.60
		_ellipsoid(face, "EyeWhite" + str(side), Vector3(side * 0.078, 0.021, 0.194), Vector3(0.033, 0.040, 0.010), p.eye_white)
		_ellipsoid(face, "EyeIris" + str(side), Vector3(side * 0.076, 0.020, 0.203), Vector3(0.0215, 0.027, 0.009), p.eye)
		_ellipsoid(face, "EyeCatchlight" + str(side), Vector3(side * 0.076 - 0.005, 0.030, 0.211), Vector3(0.005, 0.0065, 0.0025), p.glint, 16, 10)
		_ellipsoid(face, "EyeSmallGlint" + str(side), Vector3(side * 0.076 + 0.006, 0.012, 0.211), Vector3(0.0024, 0.003, 0.0015), p.glint, 12, 8)
		_tubes(face, "UpperLid" + str(side), [_path([
			Vector3(side * 0.078 - 0.031, 0.034, 0.192), Vector3(side * 0.078 - 0.020, 0.054, 0.195),
			Vector3(side * 0.078, 0.060, 0.198), Vector3(side * 0.078 + 0.023, 0.049, 0.191),
		])], 0.0027, p.hair, 6)
		_tubes(face, "Brow" + str(side), [_path([
			Vector3(side * 0.080 - 0.028, 0.086, 0.181), Vector3(side * 0.080, 0.093, 0.185),
			Vector3(side * 0.080 + 0.026, 0.087, 0.174),
		])], 0.006, p.hair, 8)
	_ellipsoid(face, "Nose", Vector3(0, -0.022, 0.204), Vector3(0.034, 0.025, 0.039), p.skin)
	_ellipsoid(face, "NoseWarmTip", Vector3(0, -0.025, 0.236), Vector3(0.020, 0.012, 0.006), p.skin_shade)
	_tubes(face, "GentleSmile", [_path([
		Vector3(-0.035, -0.076, 0.195), Vector3(-0.018, -0.084, 0.202),
		Vector3(0, -0.086, 0.204), Vector3(0.018, -0.082, 0.202), Vector3(0.036, -0.072, 0.194),
	])], 0.0032, p.mouth, 8)
	_ellipsoid(face, "LowerLip", Vector3(0, -0.099, 0.195), Vector3(0.021, 0.005, 0.005), p.blush, 20, 12)
	_make_hair(face, alternate, p)
	var hat := _pivot(head, "StrawHat", Vector3(0, 0.358, -0.006))
	hat.rotation = Vector3(-0.028, 0, -0.035 if alternate else 0.028)
	_make_hat(hat, p)


static func _make_hair(face: Node3D, alternate: bool, p: Dictionary) -> void:
	var d := _data()
	var n_a: int = 48
	var n_t: int = 16
	for j: int in range(n_t + 1):
		for i: int in range(n_a + 1):
			var a: float = TAU * i / n_a
			var cutoff: float = lerpf(2.19 if alternate else 2.02, 1.18, (cos(a) + 1.0) * 0.5)
			var t: float = maxf(0.002, float(j) / n_t) * cutoff
			var v: Vector3 = _hair_surface_point(a, t)
			var normal := Vector3(v.x / 0.0625, (v.y - 0.005) / 0.054289, (v.z + 0.006) / 0.0441).normalized()
			_vertex(d, v, normal, 1.0 + 0.026 * sin(a * 7.0))
	# Use the sculpted surface's derivatives, including its changing hairline.
	# Ellipsoid normals would not match the corrected nape and temple profile.
	for j: int in range(n_t + 1):
		for i: int in range(n_a + 1):
			var left: int = n_a - 1 if i == 0 or i == n_a else i - 1
			var right: int = 1 if i == 0 or i == n_a else i + 1
			var du: Vector3 = d.vertices[j * (n_a + 1) + right] - d.vertices[j * (n_a + 1) + left]
			var dv: Vector3 = d.vertices[mini(n_t, j + 1) * (n_a + 1) + i] - d.vertices[maxi(0, j - 1) * (n_a + 1) + i]
			d.normals[j * (n_a + 1) + i] = dv.cross(du).normalized()
	for j: int in range(n_t):
		for i: int in range(n_a):
			var k: int = j * (n_a + 1) + i
			# Latitude runs from crown to nape, reversing the usual loft winding.
			_quad(d, k, k + 1, k + n_a + 2, k + n_a + 1)
	_mesh(face, "SculptedHairCap", _finish(d), p.hair)
	var direction: float = -1.0 if alternate else 1.0
	for i: int in range(4):
		var start_x: float = (-0.160 + i * 0.086) * direction
		var tip_y: float = 0.097 + absf(i - 1.5) * 0.009
		_smooth_sweep(face, "SweptFringe" + str(i), _path([
			Vector3(start_x, 0.172, 0.130), Vector3(start_x + direction * 0.022, 0.149, 0.175),
			Vector3(start_x + direction * 0.040, 0.125, 0.191), Vector3(start_x + direction * 0.059, tip_y, 0.188),
		]), [Vector2(0.044, 0.021), Vector2(0.045, 0.029), Vector2(0.031, 0.022), Vector2(0.003, 0.002)], p.hair, 12)
		_tubes(face, "FringeStrand" + str(i), [_path([
			Vector3(start_x - 0.010, 0.170, 0.150), Vector3(start_x + direction * 0.012, 0.152, 0.200),
			Vector3(start_x + direction * 0.037, 0.130, 0.211),
		])], 0.0018, p.hair_light, 5)
	for side: int in [-1, 1]:
		_smooth_sweep(face, "Sideburn" + str(side), _path([
			Vector3(side * 0.206, 0.142, 0.064), Vector3(side * 0.227, 0.080, 0.074),
			Vector3(side * 0.225, 0.011, 0.081), Vector3(side * 0.212, -0.024, 0.071),
		]), [Vector2(0.030, 0.019), Vector2(0.031, 0.022), Vector2(0.020, 0.017), Vector2(0.002, 0.002)], p.hair, 12)
		if alternate:
			for i: int in range(4):
				var braid := _ellipsoid(face, "Braid" + str(side) + "_" + str(i), Vector3(side * (0.195 + 0.009 * sin(i * 2.0)), -0.081 - i * 0.044, -0.084), Vector3(0.039 - i * 0.005, 0.039, 0.039 - i * 0.005), p.hair)
				braid.rotation.z = side * (0.25 if i % 2 == 0 else -0.25)
			_ellipsoid(face, "BraidTie" + str(side), Vector3(side * 0.197, -0.214, -0.082), Vector3(0.030, 0.013, 0.031), p.hat_band)


static func _make_hat(hat: Node3D, p: Dictionary) -> void:
	var d := _data()
	var segments: int = 80
	var radial_steps: int = 8
	for layer: int in range(2):
		for ring: int in range(radial_steps + 1):
			var f: float = float(ring) / radial_steps
			for i: int in range(segments + 1):
				var a: float = TAU * i / segments
				var v: Vector3 = _brim_point(a, f)
				v.y -= 0.017 * layer
				_vertex(d, v, Vector3(0, 1.0 if layer == 0 else -1.0, 0), 0.98 + 0.035 * f)
	var layer_stride: int = (radial_steps + 1) * (segments + 1)
	for layer: int in range(2):
		for ring: int in range(radial_steps):
			for i: int in range(segments):
				var k: int = layer * layer_stride + ring * (segments + 1) + i
				if layer == 0:
					_quad(d, k, k + 1, k + segments + 2, k + segments + 1)
				else:
					_quad(d, k + 1, k, k + segments + 1, k + segments + 2)
	for i: int in range(segments):
		var k: int = radial_steps * (segments + 1) + i
		_quad(d, k, k + layer_stride, k + layer_stride + 1, k + 1)
		_quad(d, i + layer_stride, i, i + 1, i + layer_stride + 1)
	_mesh(hat, "WavyStrawBrim", _finish(d), p.straw)
	_loft(hat, "RoundedStrawCrown", [
		Vector4(0.204, -0.004, 0.180, -0.002), Vector4(0.204, 0.028, 0.179, -0.002),
		Vector4(0.190, 0.105, 0.166, -0.005), Vector4(0.173, 0.153, 0.149, -0.008),
		Vector4(0.133, 0.171, 0.118, -0.009), Vector4(0.050, 0.177, 0.045, -0.009),
	], p.straw, 56, 3)
	_loft(hat, "HatRibbon", [
		Vector4(0.207, 0.007, 0.183, -0.002), Vector4(0.205, 0.020, 0.181, -0.002),
		Vector4(0.199, 0.050, 0.176, -0.003), Vector4(0.195, 0.057, 0.173, -0.003),
	], p.hat_band, 56, 2)
	var light_weave: Array = []
	var dark_weave: Array = []
	for ring: int in range(12):
		var points := PackedVector3Array()
		var f: float = 0.06 + ring * 0.079
		for i: int in range(segments + 1):
			points.append(_brim_point(TAU * i / segments, f) + Vector3(0, 0.0016, 0))
		if ring % 3 == 1:
			dark_weave.append(points)
		else:
			light_weave.append(points)
	for i: int in range(32):
		var points := PackedVector3Array()
		for j: int in range(9):
			var f: float = float(j) / 8.0
			var a: float = TAU * i / 32.0 + 0.040 * f
			points.append(_brim_point(a, f) + Vector3(0, 0.002, 0))
		dark_weave.append(points)
	for ring: int in range(7):
		var points := PackedVector3Array()
		var y: float = 0.067 + ring * 0.014
		var rx: float = lerpf(0.196, 0.158, float(ring) / 6.0)
		var rz: float = rx * 0.874
		for i: int in range(65):
			var a: float = TAU * i / 64.0
			points.append(Vector3(sin(a) * rx, y + sin(a * 14.0) * 0.0007, cos(a) * rz - 0.005))
		light_weave.append(points)
	_tubes(hat, "WovenStrawHighlights", light_weave, 0.0014, p.straw_light, 5)
	_tubes(hat, "WovenStrawCrossgrain", dark_weave, 0.0010, p.straw_dark, 5)
	var rim := PackedVector3Array()
	for i: int in range(81):
		rim.append(_brim_point(TAU * i / 80.0, 1.0) + Vector3(0, -0.006, 0))
	_tubes(hat, "RolledBrimEdge", [rim], 0.0080, p.straw_light, 8)
	var knot := _ellipsoid(hat, "HatRibbonKnot", Vector3(-0.198, 0.032, 0.020), Vector3(0.013, 0.023, 0.031), p.hat_band)
	knot.rotation.x = -0.12
	var ribbon_end := _panel(hat, "HatRibbonTail", Vector3(-0.215, 0.001, 0.027), Vector2(0.028, 0.061), 0.006, 0.004, p.hat_band)
	ribbon_end.rotation = Vector3(-0.15, -0.8, -0.22)
	_tubes(hat, "HatSprigStem", [_path([Vector3(-0.200, 0.040, 0.046), Vector3(-0.231, 0.081, 0.039), Vector3(-0.239, 0.126, 0.031)])], 0.0022, p.leaf, 6)
	for i: int in range(3):
		var leaf := _ellipsoid(hat, "HatSprigLeaf" + str(i), Vector3(-0.221 - i * 0.008, 0.078 + i * 0.020, 0.040), Vector3(0.011, 0.024, 0.005), p.leaf)
		leaf.rotation.z = -0.65 if i % 2 == 0 else 0.70


static func _brim_point(a: float, f: float) -> Vector3:
	var rx: float = lerpf(0.180, 0.382, f)
	var rz: float = lerpf(0.158, 0.325, f)
	var wave: float = (0.012 * sin(2.0 * a + 0.40) + 0.005 * cos(3.0 * a)) * f * f
	return Vector3(sin(a) * rx, 0.006 + 0.017 * f * f + wave + 0.006 * cos(a) * f, cos(a) * rz)


static func _make_satchel(body: Node3D, p: Dictionary) -> void:
	var bag := _pivot(body, "SeedSatchel", Vector3(0.238, 0.050, -0.060))
	bag.rotation = Vector3(0.04, 0.43, -0.11)
	_panel(bag, "LeatherPouch", Vector3(0, 0, 0), Vector2(0.163, 0.193), 0.076, 0.033, p.leather)
	_panel(bag, "SatchelFlap", Vector3(0, 0.039, 0.050), Vector2(0.169, 0.116), 0.019, 0.033, p.leather_light)
	_panel(bag, "ClosureStrap", Vector3(0, -0.008, 0.067), Vector2(0.032, 0.098), 0.009, 0.010, p.leather)
	_tubes(bag, "SatchelStitches", [_path([
		Vector3(-0.073, 0.076, 0.061), Vector3(-0.072, 0.017, 0.064), Vector3(-0.053, -0.009, 0.065),
		Vector3(0.053, -0.009, 0.065), Vector3(0.072, 0.017, 0.064), Vector3(0.073, 0.076, 0.061),
	])], 0.0016, p.thread, 5)
	_tubes(bag, "SatchelBuckle", [_path([
		Vector3(-0.017, 0.002, 0.077), Vector3(-0.017, -0.025, 0.077), Vector3(0.017, -0.025, 0.077),
		Vector3(0.017, 0.002, 0.077), Vector3(-0.017, 0.002, 0.077),
	])], 0.0028, p.brass, 7)
	_rod(bag, "BuckleTongue", Vector3(0, 0.001, 0.080), Vector3(0, -0.026, 0.080), 0.0018, p.brass)
	# Short belt hangers keep the broad bib visible from the front.
	for x: float in [-0.056, 0.056]:
		_ribbon(bag, "BeltHanger" + str(x), _path([
			Vector3(x, 0.052, -0.025), Vector3(x, 0.147, -0.025),
			Vector3(x, 0.164, -0.054), Vector3(x, 0.091, -0.066),
		]), 0.022, 0.008, p.leather)
	# A real small trowel, tucked into the pouch, readable from the back quarter.
	var tool := _pivot(bag, "GardenTrowel", Vector3(0.032, 0.097, -0.021))
	tool.rotation.z = -0.23
	_ellipsoid(tool, "WoodHandle", Vector3(0, 0.066, 0), Vector3(0.019, 0.056, 0.018), p.leather_light)
	_rod(tool, "ToolFerrule", Vector3(0, 0.001, 0), Vector3(0, 0.028, 0), 0.012, p.brass)
	_rod(tool, "ToolShank", Vector3(0, -0.031, 0), Vector3(0, 0.005, 0), 0.006, p.steel)
	_sweep(tool, "TrowelBlade", _path([Vector3(0, -0.020, 0), Vector3(0, -0.059, 0.004), Vector3(0, -0.105, 0.010), Vector3(0, -0.128, 0.013)]), [Vector2(0.014, 0.004), Vector2(0.032, 0.006), Vector2(0.024, 0.005), Vector2(0.001, 0.001)], p.steel, 12)


static func _material(label: String, hex_color: String, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = label
	mat.albedo_color = Color(hex_color)
	mat.roughness = roughness
	mat.metallic = metallic
	mat.vertex_color_use_as_albedo = true
	return mat


static func _pivot(parent: Node3D, label: String, position: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = label
	node.position = position
	parent.add_child(node)
	return node


static func _mesh(parent: Node3D, label: String, geometry: Mesh, material: Material, position: Vector3 = Vector3.ZERO, size: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = geometry
	instance.material_override = material
	instance.position = position
	instance.scale = size
	parent.add_child(instance)
	return instance


static func _ellipsoid(parent: Node3D, label: String, position: Vector3, radius: Vector3, material: Material, segments: int = 28, rings: int = 16) -> MeshInstance3D:
	var geometry := SphereMesh.new()
	geometry.radius = 1.0
	geometry.height = 2.0
	geometry.radial_segments = segments
	geometry.rings = rings
	return _mesh(parent, label, geometry, material, position, radius)


static func _rod(parent: Node3D, label: String, start: Vector3, end: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var geometry := CylinderMesh.new()
	geometry.top_radius = radius
	geometry.bottom_radius = radius
	geometry.height = start.distance_to(end)
	geometry.radial_segments = 12
	var instance := _mesh(parent, label, geometry, material, (start + end) * 0.5)
	instance.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	return instance


static func _button(parent: Node3D, label: String, position: Vector3, radius: float, material: Material) -> void:
	_ellipsoid(parent, label, position, Vector3(radius, radius, radius * 0.42), material, 20, 12)


static func _data() -> Dictionary:
	return {"vertices": [], "normals": [], "colors": [], "indices": []}


static func _vertex(d: Dictionary, vertex: Vector3, normal: Vector3, tint: float = 1.0) -> void:
	d.vertices.append(vertex)
	d.normals.append(normal)
	d.colors.append(Color(tint, tint, tint, 1.0))


static func _quad(d: Dictionary, a: int, b: int, c: int, e: int) -> void:
	d.indices.append_array([a, b, c, a, c, e])


static func _finish(d: Dictionary) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(d.vertices)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(d.normals)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(d.colors)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(d.indices)
	var geometry := ArrayMesh.new()
	geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return geometry


static func _profile(profiles: Array, sample: float) -> Vector4:
	var index: int = mini(int(sample), profiles.size() - 2)
	var t: float = sample - index
	var a: Vector4 = profiles[maxi(0, index - 1)]
	var b: Vector4 = profiles[index]
	var c: Vector4 = profiles[index + 1]
	var e: Vector4 = profiles[mini(profiles.size() - 1, index + 2)]
	return (b * 2.0 + (-a + c) * t + (a * 2.0 - b * 5.0 + c * 4.0 - e) * t * t + (-a + b * 3.0 - c * 3.0 + e) * t * t * t) * 0.5


static func _profile_at_height(profiles: Array, height: float) -> Vector4:
	var low: float = 0.0
	var high: float = profiles.size() - 1.0
	for iteration: int in range(18):
		var middle: float = (low + high) * 0.5
		if _profile(profiles, middle).y < height:
			low = middle
		else:
			high = middle
	return _profile(profiles, (low + high) * 0.5)


static func _hair_surface_point(angle: float, latitude: float) -> Vector3:
	var y: float = cos(latitude) * 0.233 + 0.005
	var rx: float = sin(latitude) * 0.250
	var rz: float = sin(latitude) * 0.210
	var center_z: float = -0.006
	if y <= HEAD_PROFILE[HEAD_PROFILE.size() - 1].y:
		# A simple ellipsoid intersects the fuller sculpted rear head by ~8 mm.
		# Match its actual cross-section with room for interpolation between rings.
		var head: Vector4 = _profile_at_height(HEAD_PROFILE, y)
		rx = maxf(rx, head.x + 0.008)
		rz = maxf(rz, head.z + 0.008)
		center_z = head.w
	return Vector3(sin(angle) * rx, y, cos(angle) * rz + center_z)


static func _surface_path(profiles: Array, control_points: Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	for segment: int in range(control_points.size() - 1):
		for step: int in range(5 if segment == control_points.size() - 2 else 4):
			var point: Vector3 = (control_points[segment] as Vector3).lerp(control_points[segment + 1], step / 4.0)
			var shape: Vector4 = _profile_at_height(profiles, point.y)
			var x_fraction: float = clampf(point.x / shape.x, -0.99, 0.99)
			point.z = shape.w + shape.z * sqrt(1.0 - x_fraction * x_fraction) + 0.0025
			points.append(point)
	return points


static func _loft(parent: Node3D, label: String, profiles: Array, material: Material, segments: int = 36, smoothing: int = 3) -> MeshInstance3D:
	var d := _data()
	var steps: int = (profiles.size() - 1) * smoothing
	for j: int in range(steps + 1):
		var sample: float = float(j) / smoothing
		var r: Vector4 = _profile(profiles, sample)
		var before: Vector4 = _profile(profiles, maxf(0, sample - 0.015))
		var after: Vector4 = _profile(profiles, minf(profiles.size() - 1.0, sample + 0.015))
		var derivative: Vector4 = after - before
		for i: int in range(segments + 1):
			var a: float = TAU * i / segments
			var vertex := Vector3(sin(a) * r.x, r.y, cos(a) * r.z + r.w)
			var tangent := Vector3(cos(a) * r.x, 0, -sin(a) * r.z)
			var vertical := Vector3(sin(a) * derivative.x, derivative.y, cos(a) * derivative.z + derivative.w)
			var normal: Vector3 = tangent.cross(vertical).normalized()
			_vertex(d, vertex, normal, 1.0 + 0.024 * normal.y + 0.008 * sin(a * 3.0 + r.y * 12.0))
	for j: int in range(steps):
		for i: int in range(segments):
			var k: int = j * (segments + 1) + i
			_quad(d, k, k + segments + 1, k + segments + 2, k + 1)
	for end: int in range(2):
		var r: Vector4 = profiles[0 if end == 0 else profiles.size() - 1]
		var center: int = d.vertices.size()
		_vertex(d, Vector3(0, r.y, r.w), Vector3.DOWN if end == 0 else Vector3.UP)
		var start: int = 0 if end == 0 else steps * (segments + 1)
		for i: int in range(segments):
			if end == 0:
				d.indices.append_array([center, start + i, start + i + 1])
			else:
				d.indices.append_array([center, start + i + 1, start + i])
	return _mesh(parent, label, _finish(d), material)


static func _panel(parent: Node3D, label: String, position: Vector3, size: Vector2, depth: float, radius: float, material: Material, curve: float = 0.0) -> MeshInstance3D:
	var d := _data()
	var outline: Array[Vector2] = []
	var centers: Array[Vector2] = [Vector2(size.x, size.y) * 0.5 - Vector2.ONE * radius, Vector2(-size.x * 0.5 + radius, size.y * 0.5 - radius), Vector2(-size.x, -size.y) * 0.5 + Vector2.ONE * radius, Vector2(size.x * 0.5 - radius, -size.y * 0.5 + radius)]
	for corner: int in range(4):
		for i: int in range(7):
			var a: float = corner * PI * 0.5 + float(i) / 6.0 * PI * 0.5
			outline.append(centers[corner] + Vector2(cos(a), sin(a)) * radius)
	var factors: Array[float] = [0.94, 1.0, 0.96, 0.74]
	var z_levels: Array[float] = [-0.50, 0.0, 0.50, 0.63]
	for layer: int in range(4):
		for point: Vector2 in outline:
			var q: Vector2 = point * factors[layer]
			var xy_weight: float = [0.7, 1.0, 0.6, 0.1][layer]
			var z_normal: float = [-0.7, 0.0, 0.8, 1.0][layer]
			var bend_gradient: float = 2.0 * curve * q.x / pow(size.x * 0.5, 2)
			var normal: Vector3 = Vector3(q.x / size.x * xy_weight + bend_gradient * z_normal, q.y / size.y * xy_weight, z_normal).normalized()
			var bend: float = curve * pow(q.x / (size.x * 0.5), 2)
			_vertex(d, Vector3(q.x, q.y, z_levels[layer] * depth - bend), normal, 1.0 + normal.y * 0.02)
	var count: int = outline.size()
	for layer: int in range(3):
		for i: int in range(count):
			var next: int = (i + 1) % count
			_quad(d, layer * count + i, (layer + 1) * count + i, (layer + 1) * count + next, layer * count + next)
	var front: int = d.vertices.size()
	_vertex(d, Vector3(0, 0, depth * 0.64), Vector3.FORWARD * -1)
	var back: int = d.vertices.size()
	_vertex(d, Vector3(0, 0, -depth * 0.5), Vector3.FORWARD)
	for i: int in range(count):
		var next: int = (i + 1) % count
		d.indices.append_array([front, 3 * count + next, 3 * count + i, back, i, next])
	return _mesh(parent, label, _finish(d), material, position)


static func _path(points: Array) -> PackedVector3Array:
	return PackedVector3Array(points)


static func _tubes(parent: Node3D, label: String, paths: Array, radius: float, material: Material, sides: int = 6) -> MeshInstance3D:
	var d := _data()
	for points: PackedVector3Array in paths:
		var sizes: Array = []
		for i: int in range(points.size()):
			sizes.append(Vector2(radius, radius))
		_append_sweep(d, points, sizes, sides, false)
	return _mesh(parent, label, _finish(d), material)


static func _sweep(parent: Node3D, label: String, points: PackedVector3Array, sizes: Array, material: Material, sides: int = 12) -> MeshInstance3D:
	var d := _data()
	_append_sweep(d, points, sizes, sides, true)
	return _mesh(parent, label, _finish(d), material)


static func _smooth_sweep(parent: Node3D, label: String, points: PackedVector3Array, sizes: Array, material: Material, sides: int = 12) -> MeshInstance3D:
	var smooth_points := PackedVector3Array()
	var smooth_sizes: Array = []
	for segment: int in range(points.size() - 1):
		for step: int in range(4 if segment == points.size() - 2 else 3):
			var t: float = step / 3.0
			var before: Vector3 = points[maxi(0, segment - 1)]
			var after: Vector3 = points[mini(points.size() - 1, segment + 2)]
			smooth_points.append(points[segment].cubic_interpolate(points[segment + 1], before, after, t))
			smooth_sizes.append((sizes[segment] as Vector2).lerp(sizes[segment + 1], t))
	return _sweep(parent, label, smooth_points, smooth_sizes, material, sides)


static func _ribbon(parent: Node3D, label: String, points: PackedVector3Array, width: float, depth: float, material: Material) -> MeshInstance3D:
	var sizes: Array = []
	for i: int in range(points.size()):
		sizes.append(Vector2(width * 0.5, depth * 0.5))
	return _sweep(parent, label, points, sizes, material, 12)


static func _append_sweep(d: Dictionary, points: PackedVector3Array, sizes: Array, sides: int, flattened: bool) -> void:
	var base: int = d.vertices.size()
	var closed: bool = points.size() > 2 and points[0].is_equal_approx(points[points.size() - 1])
	var previous_u := Vector3.ZERO
	for j: int in range(points.size()):
		var before: Vector3 = points[maxi(0, j - 1)]
		var after: Vector3 = points[mini(points.size() - 1, j + 1)]
		if closed and (j == 0 or j == points.size() - 1):
			before = points[points.size() - 2]
			after = points[1]
		var tangent: Vector3 = (after - before).normalized()
		# Carry the frame along the curve so a lock or strap never suddenly twists
		# when its tangent becomes nearly parallel to a world axis.
		var reference: Vector3 = previous_u if j > 0 else (Vector3.RIGHT if flattened else Vector3.UP)
		if absf(reference.dot(tangent)) > 0.94:
			reference = Vector3.FORWARD if absf(tangent.z) < 0.8 else Vector3.RIGHT
		var u: Vector3 = (reference - tangent * tangent.dot(reference)).normalized()
		if j > 0 and u.dot(previous_u) < 0:
			u = -u
		previous_u = u
		var v: Vector3 = tangent.cross(u).normalized()
		var size: Vector2 = sizes[j]
		for i: int in range(sides + 1):
			var a: float = TAU * i / sides
			var vertex: Vector3 = points[j] + u * cos(a) * size.x + v * sin(a) * size.y
			var normal: Vector3 = (u * cos(a) / maxf(size.x, 0.0001) + v * sin(a) / maxf(size.y, 0.0001)).normalized()
			_vertex(d, vertex, normal, 1.0 + 0.016 * sin(a))
	for j: int in range(points.size() - 1):
		for i: int in range(sides):
			var k: int = base + j * (sides + 1) + i
			_quad(d, k, k + sides + 1, k + sides + 2, k + 1)
	if not closed:
		var start_center: int = d.vertices.size()
		_vertex(d, points[0], (points[0] - points[1]).normalized())
		var end_center: int = d.vertices.size()
		_vertex(d, points[points.size() - 1], (points[points.size() - 1] - points[points.size() - 2]).normalized())
		var end_base: int = base + (points.size() - 1) * (sides + 1)
		for i: int in range(sides):
			d.indices.append_array([start_center, base + i, base + i + 1, end_center, end_base + i + 1, end_base + i])


static func _add_animations(root: Node3D) -> void:
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.root_node = NodePath("..")
	root.add_child(player)
	var library := AnimationLibrary.new()
	var idle := Animation.new()
	idle.length = 3.2
	idle.loop_mode = Animation.LOOP_LINEAR
	_position_track(idle, "Body", [0.0, 0.8, 1.6, 2.4, 3.2], [Vector3(0, BODY_HEIGHT, 0), Vector3(0, BODY_HEIGHT + 0.006, 0), Vector3(0, BODY_HEIGHT, 0), Vector3(0, BODY_HEIGHT - 0.004, 0), Vector3(0, BODY_HEIGHT, 0)])
	_rotation_track(idle, "Body/HeadPivot", [0.0, 1.6, 3.2], [Vector3(0.01, -0.015, 0), Vector3(-0.012, 0.015, 0.008), Vector3(0.01, -0.015, 0)])
	for side: int in [-1, 1]:
		var suffix: String = "L" if side < 0 else "R"
		_rotation_track(idle, "Body/Arm_" + suffix, [0.0, 1.6, 3.2], [Vector3(side * 0.015, 0, side * 0.11), Vector3(-side * 0.025, 0, side * 0.118), Vector3(side * 0.015, 0, side * 0.11)])
	library.add_animation("idle", idle)
	var walk := Animation.new()
	walk.length = 0.92
	walk.loop_mode = Animation.LOOP_LINEAR
	var times: Array = [0.0, 0.23, 0.46, 0.69, 0.92]
	_position_track(walk, "Body", times, [Vector3(0, BODY_HEIGHT + 0.015, 0), Vector3(0, BODY_HEIGHT + 0.035, 0), Vector3(0, BODY_HEIGHT + 0.015, 0), Vector3(0, BODY_HEIGHT + 0.035, 0), Vector3(0, BODY_HEIGHT + 0.015, 0)])
	_rotation_track(walk, "Body", times, [Vector3(0.018, 0.045, 0.025), Vector3(0.018, 0, 0), Vector3(0.018, -0.045, -0.025), Vector3(0.018, 0, 0), Vector3(0.018, 0.045, 0.025)])
	_rotation_track(walk, "Body/HeadPivot", times, [Vector3(-0.018, -0.025, -0.012), Vector3(-0.005, 0, 0), Vector3(-0.018, 0.025, 0.012), Vector3(-0.005, 0, 0), Vector3(-0.018, -0.025, -0.012)])
	for side: int in [-1, 1]:
		var suffix: String = "L" if side < 0 else "R"
		var leg_angles: Array = []
		var arm_angles: Array = []
		var knee_angles: Array = []
		var elbow_angles: Array = []
		for i: int in range(5):
			var phase: float = TAU * i / 4.0 + (PI if side > 0 else 0.0)
			leg_angles.append(Vector3(cos(phase) * 0.39, 0, 0))
			arm_angles.append(Vector3(-cos(phase) * 0.31, 0, side * 0.13))
			knee_angles.append(Vector3(0.04 + maxf(0, sin(phase)) * 0.36, 0, 0))
			elbow_angles.append(Vector3(-0.08 - maxf(0, -cos(phase)) * 0.12, 0, 0))
		_rotation_track(walk, "Body/Leg_" + suffix, times, leg_angles)
		_rotation_track(walk, "Body/Leg_" + suffix + "/Knee_" + suffix, times, knee_angles)
		_rotation_track(walk, "Body/Arm_" + suffix, times, arm_angles)
		_rotation_track(walk, "Body/Arm_" + suffix + "/Elbow_" + suffix, times, elbow_angles)
	library.add_animation("walk", walk)
	player.add_animation_library("", library)
	# Deliberately do not autoplay; callers choose a pose or animation explicitly.


static func _rotation_track(animation: Animation, path: String, times: Array, values: Array) -> void:
	var track: int = animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, NodePath(path))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	for i: int in range(times.size()):
		animation.rotation_track_insert_key(track, times[i], Quaternion.from_euler(values[i]))


static func _position_track(animation: Animation, path: String, times: Array, values: Array) -> void:
	var track: int = animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, NodePath(path))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	for i: int in range(times.size()):
		animation.position_track_insert_key(track, times[i], values[i])


static func _set_owners(node: Node, owner_root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_root
		_set_owners(child, owner_root)
