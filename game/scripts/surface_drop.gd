extends "res://scripts/mine_drop.gd"

const Forestry = preload("res://scripts/art/forestry_models.gd")


func build_model() -> Node3D:
	if kind == "wood":
		return Forestry.wood()
	if kind == "sapling":
		return Forestry.sapling()
	return super.build_model()
