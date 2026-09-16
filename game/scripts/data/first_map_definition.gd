extends RefCounted
## Canonical source-image coordinates, calibrated by the user-confirmed 400 m scale.
const BLUEPRINT := "res://resources/maps/first_map_blueprint.json"
const METERS_PER_PIXEL := 400.0 / 202.0
const ORIGIN := Vector2(656.0, 599.5)
static func point(value:Array) -> Vector2:
	return (Vector2(value[0],value[1])-ORIGIN)*METERS_PER_PIXEL
static func rect(value:Array) -> Rect2:
	return Rect2(point(value),Vector2(value[2],value[3])*METERS_PER_PIXEL)
static func polygon(values:Array) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for value:Array in values:result.append(point(value))
	return result
static func create() -> Dictionary:
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(BLUEPRINT))
	var definition:Dictionary={"id":source["id"],"revision":1,"meters_per_pixel":METERS_PER_PIXEL,"bounds":{"half":Vector2(1312,1199)*METERS_PER_PIXEL*.5,"pow":32},"buildings":[],"roads":[],"waters":[],"bridges":[],"docks":[],"regions":[],"forests":[],"reserved":[],"resource_zones":[],"ramps":[],"fields":[],"landmarks":{}}
	for entry:Dictionary in source["regions"]:
		var region:=entry.duplicate(true)
		region["rect"]=rect(entry["rect"])
		region["position"]=region["rect"].get_center()
		definition["regions"].append(region)
		if entry["id"]=="player_farm":definition["farm"]=region["rect"]
		elif entry["id"]=="npc_farm":definition["ranch"]=region["rect"]
		elif entry["id"]=="lake":
			definition["lake_center"]=region["position"]
			definition["lake_radius"]=region["rect"].size*.5
		if entry["id"] not in ["forest","lake"]:definition["reserved"].append(region["rect"])
	for i in range(7):
		var box:Array=[[8,300,150,345],[505,8,227,271],[22,18,360,81],[1130,8,170,187],[744,782,176,132],[808,938,395,139],[45,917,426,47]][i]
		definition["forests"].append({"id":"woodland_%d"%i,"rect":rect(box),"color":"#547b46"})
	for entry:Dictionary in source["roads"]:
		var lane:=entry.duplicate(true)
		lane["points"]=Array(polygon(entry["points"]))
		lane["width"]=entry["width"]*METERS_PER_PIXEL
		definition["roads"].append(lane)
	for entry:Dictionary in source["buildings"]:
		var building:=entry.duplicate(true)
		building["position"]=point(entry["at"])
		var sizes:Dictionary={"cottage":Vector2(4,3.6),"shop":Vector2(4.4,3.6),"barn":Vector2(6.6,5.2),"coop":Vector2(2.6,2.2),"hall":Vector2(9,6),"clinic":Vector2(6,4.8),"school":Vector2(8,5.8),"inn":Vector2(7.8,5.8),"library":Vector2(7.2,5.4),"smith":Vector2(6.4,4.8),"carpenter":Vector2(6.8,5.2),"bakery":Vector2(5.8,4.6),"home_a":Vector2(4.8,4.2),"home_b":Vector2(5.2,4.4),"home_c":Vector2(4.6,4)}
		building["size"]=sizes[entry["kind"]]*entry["factor"]+Vector2(.25,.25)
		building["door"]=building["position"]+Vector2(0,building["size"].y*.5+2)
		if entry["kind"]=="cottage":building["door"]=building["position"]+Vector2(.73,3.88)*entry["factor"]
		if entry["kind"]=="shop":building["door"]=building["position"]+Vector2(-1.45,3.2)*entry["factor"]
		definition["buildings"].append(building)
		if entry["id"] in ["cottage","shop"]:
			var at:Vector2=building["door"]
			definition["landmarks"][entry["id"]+"_door"]=Vector3(at.x,0,at.y)
		# A driveway connects each physical building to its depicted public street.
		var near:=Vector2.ZERO
		var best:=INF
		for road:Dictionary in definition["roads"]:
			if road["id"].begins_with("entry_"):continue
			for i in range(road["points"].size()-1):
				var candidate:=Geometry2D.get_closest_point_to_segment(building["door"],road["points"][i],road["points"][i+1])
				var distance:=candidate.distance_to(building["door"])
				if distance<best:best=distance;near=candidate
		definition["roads"].append({"id":"entry_"+entry["id"],"points":[building["door"],near],"width":2.5,"paved":entry["kind"] in ["clinic","library","hall"]})
	for entry:Dictionary in source["waters"]:
		var water:=entry.duplicate(true)
		water["kind"]="river"
		water["points"]=polygon(entry["points"])
		water["width"]=entry["width"]*METERS_PER_PIXEL
		water["polygon"]=Geometry2D.offset_polyline(water["points"],water["width"]*.5,Geometry2D.JOIN_ROUND,Geometry2D.END_SQUARE)[0]
		definition["waters"].append(water)
	for entry:Dictionary in source["lakes"]:
		definition["waters"].append({"id":entry["id"],"kind":"lake","polygon":polygon(entry["polygon"])})
	var coast:=polygon(source["coast"])
	definition["coast"]=coast
	coast.append(point([1312,1199]));coast.append(point([0,1199]))
	definition["waters"].append({"id":"southern_sea","kind":"sea","polygon":coast})
	for entry:Dictionary in source["bridges"]:
		var bridge:=entry.duplicate(true)
		bridge["rect"]=rect(entry["rect"])
		bridge["rise"]=1.8 if entry.get("stone",false) else .14
		definition["bridges"].append(bridge)
	for i in range(source["docks"].size()):definition["docks"].append({"id":"harbor_dock_%d"%i,"rect":rect(source["docks"][i])})
	for building:Dictionary in definition["buildings"]:
		if building["id"]!="harbor_house":continue
		var at:Vector2=building["position"]
		var footprint:Vector2=building["size"]+Vector2(7,8)
		definition["docks"].append({"id":"harbor_house_platform","rect":Rect2(at-footprint*.5,footprint)})
		var top:=point([0,987]).y
		definition["docks"].append({"id":"harbor_house_walkway","rect":Rect2(at.x+footprint.x*.5-3,top,3,at.y+footprint.y*.5-top)})
	for field:Array in source["fields"]:definition["fields"].append(rect(field))
	for key:String in source["landmarks"]:
		var at:=point(source["landmarks"][key])
		definition["landmarks"][key]=Vector3(at.x,0,at.y)
	definition["landmarks"]["spawn"]=definition["landmarks"]["cottage_door"]+Vector3(0,0,4)
	definition["square"]=rect([637,454,119,92])
	var farm_home:Vector2=definition["buildings"][0]["position"]
	definition["pasture"]=Rect2(farm_home+Vector2(21,14),Vector2(25,20))
	definition["landmarks"]["trough"]=Vector3(definition["pasture"].get_center().x,0,definition["pasture"].end.y-1)
	definition["starter_garden"]=Rect2(farm_home+Vector2(-20,16),Vector2(18,18))
	return definition
