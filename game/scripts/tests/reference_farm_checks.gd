extends SceneTree
## Exercise the actual new-game farm, including physical input across the raised bridge.
var game:Node3D
var failures:Array[String]=[]
func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("REFERENCE_FARM timeout"); quit(1))
	_run.call_deferred()
func _run() -> void:
	root.size=Vector2i(1600,1000)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _frames(4)
	_check("authored-cottage-loaded",game.world_data["root"].find_child("cottage",true,false)!=null)
	var crops:=0
	for tile in game.tiles.get_children():
		if tile.get("crop_kind")!=null and tile.crop_kind!="":crops+=1
	_check("new-game-has-real-crop-beds",crops>=35)
	var player:CharacterBody3D=game.player
	player.teleport(Vector3(-14.4,0,9.0))
	await _frames(2)
	_key(KEY_S,true);_key(KEY_D,true)
	var highest:=0.0
	for i in range(183):
		await physics_frame
		highest=maxf(highest,player.position.y)
	_key(KEY_S,false);_key(KEY_D,false)
	await _frames(2)
	_check("walk-across-stone-bridge",player.position.x>-4.0)
	_check("feet-follow-bridge-arch",highest>.56 and player.position.y<.2)
	# Step toward the river away from the bridge; movement must stop at the bank.
	player.teleport(Vector3(-13.3,0,16))
	await _frames(2)
	_key(KEY_S,true);_key(KEY_D,true)
	await _frames(65)
	_key(KEY_S,false);_key(KEY_D,false)
	await _frames(2)
	_check("brook-stops-walking",player.position.x<-10.8 and not game.tiles.map.is_water(Vector2(player.position.x,player.position.z),.24))
	_check("brook-cannot-be-tilled",not game.tiles.till(game.tiles.key_of(Vector3(-10,0,16))))
	player.teleport(game.landmarks["cottage_door"]+Vector3(0,0,.4))
	await _frames(3)
	game._update_targeting()
	_check("cottage-entry-remains-interactive",game.focus.get("kind")=="cottage")
	var day:int=game.state.day
	game._interact()
	await _frames(90)
	_check("cottage-sleep-advances-day",game.state.day==day+1)
	print("REFERENCE_FARM_RESULT "+("PASS" if failures.is_empty() else "FAIL "+",".join(failures)))
	quit(0 if failures.is_empty() else 1)
func _key(code:Key,pressed:bool)->void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event)
func _frames(count:int)->void:
	for i in range(count):await physics_frame
func _check(label:String,value:bool)->void:
	print("REFERENCE_FARM ",label," ","OK" if value else "FAIL")
	if not value:failures.append(label)
