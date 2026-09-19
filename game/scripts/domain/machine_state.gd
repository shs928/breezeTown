extends RefCounted
## PROCESS-01：加工机器领域状态（V2 PRD 第 14 节 Machine/MachineState）。
## 生命周期：EMPTY → PROCESSING → FINISHED → 收取回 EMPTY。
## PRD 的 INPUT_READY 并入 EMPTY（放入原料即自动开始），COLLECTED 由收取动作瞬时完成。

const RecipeDB := preload("res://scripts/data/recipe_db.gd")

var recipe_id := ""  # 空串 = 空闲；否则为 PROCESSING/FINISHED 中的配方
var hours_remaining := 0.0


func state() -> String:
	if recipe_id == "":
		return "EMPTY"
	return "FINISHED" if hours_remaining <= 0.0 else "PROCESSING"


func start(recipe: Dictionary) -> void:
	recipe_id = String(recipe["id"])
	hours_remaining = maxf(0.0, float(recipe["time"]))


func reset() -> void:
	recipe_id = ""
	hours_remaining = 0.0


func tick(hours: float) -> void:
	## 随世界时间推进；跨天/睡觉的大时间步同样适用。
	if recipe_id != "" and hours_remaining > 0.0:
		hours_remaining = maxf(0.0, hours_remaining - hours)


func just_finished(previous: String) -> bool:
	return previous == "PROCESSING" and state() == "FINISHED"


func collect() -> Dictionary:
	## FINISHED 时取出全部产出并回到 EMPTY；其余状态返回空字典。
	if state() != "FINISHED":
		return {}
	var outputs: Dictionary = RecipeDB.get_recipe(recipe_id)["outputs"]
	reset()
	return outputs


func can_start(recipes: Array, inventory_count: Callable) -> Dictionary:
	## 返回原料齐全的第一个配方（多配方的机器按目录顺序取优先级）；都不足则空字典。
	for recipe: Dictionary in recipes:
		var enough := true
		for item: String in recipe["inputs"]:
			if int(inventory_count.call(item)) < int(recipe["inputs"][item]):
				enough = false
				break
		if enough:
			return recipe
	return {}


func recipe() -> Dictionary:
	return RecipeDB.get_recipe(recipe_id)


func to_dict() -> Dictionary:
	return {"recipe": recipe_id, "hours": hours_remaining}


func from_dict(data: Dictionary) -> void:
	## 旧档缺键回到空闲；未知配方 id 视为脏数据丢弃。
	recipe_id = str(data.get("recipe", ""))
	hours_remaining = maxf(0.0, float(data.get("hours", 0.0)))
	if recipe_id != "" and RecipeDB.get_recipe(recipe_id).is_empty():
		reset()
