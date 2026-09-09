extends SceneTree
## DATA-04 测试（headless）：双重授权、白名单导出、重排名、HTML 无脚本、撤回取消、成对发布。
## 运行：godot --headless --path game --script res://tests/unit/data/data04_test_runner.gd

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractPublicSnapshot := preload("res://src/contracts/contract_public_snapshot.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const PublicExporter := preload("res://src/infrastructure/public_export/public_exporter.gd")

var _checks := 0
var _failures: PackedStringArray = []
var _root := ""


func _initialize() -> void:
	_root = ProjectSettings.globalize_path("res://../work/game-data/data04/%d" % Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute(_root)

	_test_double_authorization()
	_test_consenting_only_and_rerank()
	_test_html_safe_and_no_network()
	_test_consent_revoked_cancels()
	_test_alias_and_escaping()

	if _failures.is_empty():
		print("DATA04_OK checks=%d run_dir=%s" % [_checks, _root])
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		printerr("DATA04_FAILED checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _make_world(members: int) -> Array:
	var world := WorldState.create("w" + "0123456789abcdef0123456789abcdef", "m" + "11111111111111111111111111111111", "房主")
	var ids: Array[String] = [world.owner_player_id]
	for i in range(1, members):
		ids.append(world.add_member("成员%d" % i)["player_id"])
	return [world, ids]


# ---------- 1. 双重授权 ----------

func _test_double_authorization() -> void:
	var parts := _make_world(2)
	var world: WorldState = parts[0]
	# 世界开关关闭 → 拒绝导出
	var off := PublicExporter.build_snapshot(world, "2026-09-09T00:00:00Z")
	_check(not off["ok"] and off["error"] == "publication_disabled", "export blocked when world switch off")
	# 打开世界开关但无人同意 → 空列表
	world.publication_enabled = true
	var none := PublicExporter.build_snapshot(world, "2026-09-09T00:00:00Z")
	_check(none["ok"] and (none["snapshot"]["entries"] as Array).is_empty(), "no consenting members → empty list")
	# 成员同意后才出现
	world.find_member(parts[1][0])["publication_consent"] = true
	var one := PublicExporter.build_snapshot(world, "2026-09-09T00:00:00Z")
	_check(one["ok"] and (one["snapshot"]["entries"] as Array).size() == 1, "consenting member appears")


# ---------- 2. 只含同意成员并重排名 ----------

func _test_consenting_only_and_rerank() -> void:
	var parts := _make_world(3)
	var world: WorldState = parts[0]
	var ids: Array = parts[1]
	world.publication_enabled = true
	# 三人收益：A=300, B=200, C=100
	world.stats["members"][ids[0]]["total_gross_sales"] = 300
	world.stats["members"][ids[1]]["total_gross_sales"] = 200
	world.stats["members"][ids[2]]["total_gross_sales"] = 100
	world.stats["world_total_sales"] = 600
	# 只有 B 和 C 同意
	world.find_member(ids[1])["publication_consent"] = true
	world.find_member(ids[2])["publication_consent"] = true
	var built := PublicExporter.build_snapshot(world, "2026-09-09T00:00:00Z")
	_check(built["ok"], "snapshot built")
	var entries: Array = built["snapshot"]["entries"]
	_check(entries.size() == 2, "only consenting members exported")
	# 重新排名：B=1, C=2（不泄露隐藏成员 A 的名次）
	_check(int(entries[0]["total_gross_sales"]) == 200 and int(entries[0]["ranks"]["total_gross_sales"]) == 1, "B reranked to 1")
	_check(int(entries[1]["total_gross_sales"]) == 100 and int(entries[1]["ranks"]["total_gross_sales"]) == 2, "C reranked to 2")
	# 不出现隐藏成员的公开 ID
	var text := JSON.stringify(built["snapshot"])
	_check(not text.contains(str(world.find_member(ids[0])["public_player_id"])), "hidden member not leaked")


# ---------- 3. HTML 安全、无网络请求 ----------

func _test_html_safe_and_no_network() -> void:
	var parts := _make_world(1)
	var world: WorldState = parts[0]
	world.publication_enabled = true
	world.find_member(parts[1][0])["publication_consent"] = true
	var built := PublicExporter.build_snapshot(world, "2026-09-09T00:00:00Z")
	var html := PublicExporter.render_html(built["snapshot"])
	_check(html.contains("<!DOCTYPE html>"), "valid HTML doctype")
	_check(not html.contains("<script"), "no script tag")
	_check(not html.contains("http://") and not html.contains("https://"), "no external network references")
	_check(not html.contains("onload=") and not html.contains("onerror="), "no inline event handlers")
	_check(html.contains("社区自托管数据，非官方认证"), "self-hosted disclaimer present")
	_check(html.contains("仅含同意公开的成员"), "consenting-only note present")


# ---------- 4. 撤回/关闭取消导出 ----------

func _test_consent_revoked_cancels() -> void:
	var parts := _make_world(2)
	var world: WorldState = parts[0]
	world.publication_enabled = true
	world.find_member(parts[1][0])["publication_consent"] = true
	world.consent_revision = 7
	var export_root := _root + "/exports"
	DirAccess.make_dir_recursive_absolute(export_root)
	# 捕获时 revision=7，导出前变成 8 → 取消
	world.consent_revision = 8
	var cancelled := PublicExporter.export(world, export_root, 7)
	_check(not cancelled["ok"] and cancelled["error"] == "consent_changed", "consent change cancels export")
	# 正常导出
	world.consent_revision = 8
	var ok := PublicExporter.export(world, export_root, 8)
	_check(ok["ok"], "export succeeds with matching revision")
	_check(FileAccess.file_exists(ok["html_path"]) and FileAccess.file_exists(ok["json_path"]), "HTML and JSON paired")
	# 关总开关后拒绝
	world.publication_enabled = false
	var off := PublicExporter.export(world, export_root, world.consent_revision)
	_check(not off["ok"] and off["error"] == "publication_disabled", "switch off blocks export")
	# 失败不覆盖上一有效文件
	_check(FileAccess.file_exists(ok["html_path"]), "previous export retained")


# ---------- 5. 别名与转义 ----------

func _test_alias_and_escaping() -> void:
	var parts := _make_world(1)
	var world: WorldState = parts[0]
	world.publication_enabled = true
	var member: Dictionary = world.find_member(parts[1][0])
	member["publication_consent"] = true
	# 恶意别名
	member["public_alias"] = "<script>alert(1)</script>"
	var built := PublicExporter.build_snapshot(world, "2026-09-09T00:00:00Z")
	var entry: Dictionary = built["snapshot"]["entries"][0]
	_check(str(entry["alias"]) == "<script>alert(1)</script>", "alias stored as plain text")
	var html := PublicExporter.render_html(built["snapshot"])
	_check(not html.contains("<script>alert"), "malicious alias escaped in HTML")
	_check(html.contains("&lt;script&gt;"), "escaped form present")
	# 未设别名 → 使用昵称
	member["public_alias"] = ""
	member["display_name"] = "正常昵称"
	var built2 := PublicExporter.build_snapshot(world, "2026-09-09T00:00:00Z")
	_check(str((built2["snapshot"]["entries"] as Array)[0]["alias"]) == "正常昵称", "falls back to display name")
