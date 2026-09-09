class_name PublicExporter
## 公开导出器（DATA 唯一维护，M4 DATA-04；契约 9.2 / PRD 第 10 章）。
## 规则：
## - 默认关闭；需世界总开关 + 每名成员明确同意（双重授权）。
## - 只导出同意成员，并基于公开成员重新排名；不泄露隐藏成员的名次或总人数。
## - 白名单构造（不复制存档再删字段）；别名纯文本转义。
## - HTML + JSON 成对使用同一已确认快照；两文件写入同一临时目录、验证完整后一次发布。
## - 发布前再检查世界总开关与 consent_revision，授权变化则取消。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractPublicSnapshot := preload("res://src/contracts/contract_public_snapshot.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const Leaderboard := preload("res://src/domain/statistics/leaderboard.gd")

const EXPORT_SUBDIR := "public_exports"


## 构建公开快照（仅含同意成员）。返回 {ok, snapshot, error}。
static func build_snapshot(world: WorldState, generated_at_utc: String) -> Dictionary:
	if not world.publication_enabled:
		return {"ok": false, "snapshot": {}, "error": "publication_disabled"}
	var boards := Leaderboard.build(world, [])
	var rows: Array = []
	for row: Dictionary in boards["total_gross_sales"]:
		var member: Dictionary = world.find_member(row["player_id"])
		if member.is_empty() or not bool(member.get("publication_consent", false)):
			continue
		var alias: String = str(member.get("public_alias", ""))
		if alias.is_empty():
			alias = str(member["display_name"])
		var today := 0
		for today_row: Dictionary in boards["today_gross_sales"]:
			if today_row["player_id"] == row["player_id"]:
				today = int(today_row["value"])
				break
		rows.append({
			"public_player_id": member["public_player_id"],
			"alias": alias,
			"total_gross_sales": int(row["value"]),
			"today_gross_sales": today,
			"contribution_breakdown": (member.get("public_contribution", null) if member.has("public_contribution") else world.stats["members"].get(member["player_id"], {}).get("contribution", {})),
		})
	var world_info := {
		"public_world_id": "pw" + str(world.world_id).substr(1, 32),
		"world_display_name": _world_display_name(world),
		"generated_at_utc": generated_at_utc,
		"game_day": world.game_day,
		"ruleset_version": world.ruleset_version,
	}
	var snapshot := ContractPublicSnapshot.build(world_info, rows)
	var err := ContractPublicSnapshot.validate(snapshot)
	if not err.is_empty():
		return {"ok": false, "snapshot": {}, "error": err}
	return {"ok": true, "snapshot": snapshot, "error": ""}


## 导出 HTML + JSON 成对文件。返回 {ok, dir, html_path, json_path, error}。
## export_root 为世界目录下的导出根；每次导出发布到新的时间戳子目录。
static func export(world: WorldState, export_root: String, consent_revision_at_capture: int) -> Dictionary:
	var built := build_snapshot(world, Time.get_datetime_string_from_system(true) + "Z")
	if not built["ok"]:
		return {"ok": false, "dir": "", "html_path": "", "json_path": "", "error": built["error"]}
	# 发布前复核授权版本：期间撤回/关闭则取消
	if not world.publication_enabled or world.consent_revision != consent_revision_at_capture:
		return {"ok": false, "dir": "", "html_path": "", "json_path": "", "error": "consent_changed"}
	var snapshot: Dictionary = built["snapshot"]
	# 时间戳含毫秒，避免同一秒内连续导出互相覆盖（固定安全文件名，不含用户输入）。
	var timestamp := "%d-%03d" % [Time.get_unix_time_from_system(), Time.get_ticks_msec() % 1000]
	var final_dir := export_root + "/" + timestamp
	var tmp_dir := export_root + "/.tmp-" + timestamp
	# 极端情况下（同毫秒）追加序号，绝不覆盖既有导出
	var suffix := 0
	while DirAccess.dir_exists_absolute(final_dir) or DirAccess.dir_exists_absolute(tmp_dir):
		suffix += 1
		timestamp = "%d-%03d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_msec() % 1000, suffix]
		final_dir = export_root + "/" + timestamp
		tmp_dir = export_root + "/.tmp-" + timestamp
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	# 写 JSON
	var json_text := JSON.stringify(snapshot)
	var jf := FileAccess.open(tmp_dir + "/snapshot.json", FileAccess.WRITE)
	if jf == null:
		return {"ok": false, "dir": "", "html_path": "", "json_path": "", "error": "json_write_failed"}
	jf.store_string(json_text)
	jf.flush()
	jf.close()
	# 写 HTML（无外部脚本/字体/网络请求）
	var html_text := render_html(snapshot)
	var hf := FileAccess.open(tmp_dir + "/snapshot.html", FileAccess.WRITE)
	if hf == null:
		return {"ok": false, "dir": "", "html_path": "", "json_path": "", "error": "html_write_failed"}
	hf.store_string(html_text)
	hf.flush()
	hf.close()
	# 验证两个文件完整后一次发布（任一失败不留下半对）
	if JSON.parse_string(FileAccess.get_file_as_string(tmp_dir + "/snapshot.json")) == null:
		return {"ok": false, "dir": "", "html_path": "", "json_path": "", "error": "json_verify_failed"}
	if FileAccess.get_file_as_string(tmp_dir + "/snapshot.html").length() < 100:
		return {"ok": false, "dir": "", "html_path": "", "json_path": "", "error": "html_verify_failed"}
	var da := DirAccess.open(export_root)
	if da == null or da.rename(".tmp-" + timestamp, timestamp) != OK:
		return {"ok": false, "dir": "", "html_path": "", "json_path": "", "error": "publish_failed"}
	return {
		"ok": true, "dir": final_dir,
		"html_path": final_dir + "/snapshot.html",
		"json_path": final_dir + "/snapshot.json",
		"error": "",
	}


## 渲染无脚本、无外部资源的 HTML。
static func render_html(snapshot: Dictionary) -> String:
	var esc := func(s: String) -> String: return _escape_html(s)
	var lines: PackedStringArray = []
	lines.append("<!DOCTYPE html>")
	lines.append("<html lang=\"zh-CN\"><head><meta charset=\"utf-8\">")
	lines.append("<title>%s</title>" % esc.call(str(snapshot["world_display_name"])))
	lines.append("<style>body{font-family:sans-serif;background:#f5efe3;color:#2b2b33;margin:2em}table{border-collapse:collapse}td,th{border:1px solid #c9b79a;padding:4px 8px}</style>")
	lines.append("</head><body>")
	lines.append("<h1>%s</h1>" % esc.call(str(snapshot["world_display_name"])))
	lines.append("<p>游戏第 %d 日 ｜ 生成时间 %s ｜ 规则版本 %s</p>" % [int(snapshot["game_day"]), esc.call(str(snapshot["generated_at_utc"])), esc.call(str(snapshot["ruleset_version"]))])
	lines.append("<p>社区自托管数据，非官方认证。仅含同意公开的成员。</p>")
	lines.append("<table><tr><th>名次</th><th>玩家</th><th>累计收益</th><th>当日收益</th><th>累计贡献</th></tr>")
	for entry: Dictionary in snapshot["entries"]:
		lines.append("<tr><td>%d</td><td>%s</td><td>%d</td><td>%d</td><td>%d</td></tr>" % [
			int(entry["ranks"]["total_gross_sales"]), esc.call(str(entry["alias"])),
			int(entry["total_gross_sales"]), int(entry["today_gross_sales"]), int(entry["contribution_total"]),
		])
	lines.append("</table>")
	if snapshot["entries"].is_empty():
		lines.append("<p>暂无同意公开的成员。</p>")
	lines.append("</body></html>")
	return "\n".join(lines)


static func _escape_html(text: String) -> String:
	return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;")


static func _world_display_name(world: WorldState) -> String:
	for member: Dictionary in world.members:
		if member.has("world_display_name"):
			return str(member["world_display_name"])
	return "微风小镇"
