extends RefCounted
## 给农夫补充一段一次性的农活动作（挥臂），与 farmer_model 的 idle/walk 共存。

const ACTION_LENGTH := 0.7


static func add_act(farmer: Node3D) -> void:
	var player: AnimationPlayer = farmer.get_node("AnimationPlayer")
	if player.has_animation("act"):
		return
	var act := Animation.new()
	act.length = ACTION_LENGTH
	var times: Array = [0.0, 0.22, 0.45, 0.7]
	# 右臂：抬起 → 向下挥（锄地/浇水/采摘共用）；左臂与躯干轻微跟随。
	_rotation_track(act, "Body/Arm_R", times, [
		Vector3(0.0, 0, 0.11), Vector3(-2.05, 0, 0.16), Vector3(-0.72, 0, 0.12), Vector3(0.0, 0, 0.11),
	])
	_rotation_track(act, "Body/Arm_R/Elbow_R", times, [
		Vector3(-0.08, 0, 0), Vector3(-0.5, 0, 0), Vector3(-0.12, 0, 0), Vector3(-0.08, 0, 0),
	])
	_rotation_track(act, "Body/Arm_L", times, [
		Vector3(0, 0, -0.11), Vector3(0.16, 0, -0.13), Vector3(0.05, 0, -0.12), Vector3(0, 0, -0.11),
	])
	_rotation_track(act, "Body", times, [
		Vector3(0, 0, 0), Vector3(0.09, 0.06, 0), Vector3(0.14, -0.05, 0), Vector3(0, 0, 0),
	])
	_rotation_track(act, "Body/HeadPivot", times, [
		Vector3(0, 0, 0), Vector3(0.1, 0.08, 0), Vector3(0.16, -0.06, 0), Vector3(0, 0, 0),
	])
	var library := player.get_animation_library("")
	library.add_animation("act", act)
	_add_swing(library, "mine", 0.64, true)
	_add_swing(library, "slash", 0.48, false)


static func _add_swing(library: AnimationLibrary, name: String, duration: float, mining: bool) -> void:
	var action := Animation.new()
	action.length = duration
	var times: Array = [0.0, duration * 0.28, duration * 0.55, duration]
	_rotation_track(action, "Body/Arm_R", times, [
		Vector3(0, 0, 0.11),
		Vector3(-1.9, 0.1, 0.15) if mining else Vector3(-0.55, -0.85, -0.7),
		Vector3(0.24, 0, 0.18) if mining else Vector3(-0.8, 1.05, 0.7),
		Vector3(0, 0, 0.11),
	])
	_rotation_track(action, "Body/Arm_R/Elbow_R", times, [Vector3(-0.08, 0, 0), Vector3(-0.7, 0, 0), Vector3(-0.12, 0, 0), Vector3(-0.08, 0, 0)])
	_rotation_track(action, "Body/Arm_L", times, [Vector3(0, 0, -0.11), Vector3(-0.4, -0.1, -0.18), Vector3(0.25, 0, -0.18), Vector3(0, 0, -0.11)])
	_rotation_track(action, "Body", times, [Vector3.ZERO, Vector3(-0.10, -0.18, 0), Vector3(0.13, 0.16, 0), Vector3.ZERO])
	_rotation_track(action, "Body/HeadPivot", times, [Vector3.ZERO, Vector3(-0.08, 0, 0), Vector3(0.12, 0, 0), Vector3.ZERO])
	library.add_animation(name, action)


static func _rotation_track(animation: Animation, path: String, times: Array, values: Array) -> void:
	var track: int = animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, NodePath(path))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	for i in range(times.size()):
		animation.rotation_track_insert_key(track, times[i], Quaternion.from_euler(values[i]))
