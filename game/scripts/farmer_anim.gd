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


static func _rotation_track(animation: Animation, path: String, times: Array, values: Array) -> void:
	var track: int = animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, NodePath(path))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
	for i in range(times.size()):
		animation.rotation_track_insert_key(track, times[i], Quaternion.from_euler(values[i]))
