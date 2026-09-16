extends RefCounted
const M := preload("res://scripts/art/art_mesh.gd")
static func build(rect:Rect2,rise:float,axis:String="", openings:Array=[]) -> Node3D:
	var root:=Node3D.new()
	root.name="WillowBrookStoneBridge"
	var center:=rect.get_center()
	root.position=Vector3(center.x,0,center.y)
	var along_x := axis == "x" if not axis.is_empty() else rect.size.x >= rect.size.y
	var span := rect.size.x if along_x else rect.size.y
	var width := rect.size.y if along_x else rect.size.x
	if not along_x: root.rotation.y = PI * .5
	var rng:=RandomNumberGenerator.new()
	rng.seed=286
	# Barrel-vault stones, with a real open underside over the recessed stream.
	for i in range(19):
		var t:float=(i+.5)/19.0
		var x:float=(t-.5)*span
		var deck_y:float=.09+sin(t*PI)*rise
		var angle:float=atan(cos(t*PI)*PI*rise/span)
		for row in range(6):
			var block:=M.box(root,Vector3(x,deck_y-.09,(row-2.5)*width/6.),Vector3(span/19.-.024,.20,width/6.-.018),["#a9a18c","#b3ab94","#bbb198","#c4baa0"][rng.randi_range(0,3)],"VaultPaver",.065)
			block.rotation.z=angle
		for side in [-1.,1.]:
			var along_position: float = x if along_x else -x
			if rail_is_open(side, along_position - span / 38.0, along_position + span / 38.0, openings): continue
			for course in range(3):
				var block:=M.box(root,Vector3(x,deck_y+.14+course*.24,side*(width*.5-.16)),Vector3(span/19.-.028,.24,.43),["#a8a18b","#b4ae98","#c0b79e"][rng.randi_range(0,2)],"HandLaidParapet",.045)
				block.rotation.z=angle
			var cap:=M.box(root,Vector3(x,deck_y+.77,side*(width*.5-.16)),Vector3(span/19.-.018,.13,.53),"#d2c7ac","WornCoping",.055)
			cap.rotation.z=angle
	for end in [-1.,1.]:
		for side in [-1.,1.]:
			M.box(root,Vector3(end*(span*.5-.6),-.28,side*(width*.5-.14)),Vector3(1.5,1.05,.70),"#908b77","StoneAbutment",.1)
	return root


static func rail_is_open(side: float, from: float, to: float, openings: Array) -> bool:
	for opening: Dictionary in openings:
		if is_equal_approx(side, opening["side"]) and to > float(opening["from"]) and from < float(opening["to"]):
			return true
	return false
