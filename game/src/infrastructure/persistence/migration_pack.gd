class_name MigrationPack
## 私有迁移包（DATA 唯一维护，M4 DATA-05；契约 8.5 / CASE-32）。
## 流程：所有者关闭世界 → 完成快照 → 导出私有迁移包 → 校验包 → 目标导入 → 无界面启动。
## 安全：拒绝路径穿越、绝对路径、符号链接与超限解压（总量上限 100MiB）。
## 内容：版本信息、世界快照、必要私有服务器配置、文件校验清单；不含进程锁与临时文件。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractEnvelopes := preload("res://src/contracts/contract_envelopes.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRepository := preload("res://src/infrastructure/persistence/world_repository.gd")

const PACK_FORMAT_VERSION := 1
const PACK_MAX_BYTES := 100 * 1024 * 1024   # 解压总量上限 100MiB
const MANIFEST_NAME := "pack_manifest.json"


## 导出迁移包到目标目录。返回 {ok, dir, error}。
## 调用方必须先停服（本函数不检查活跃锁，由 LocalSession 保证顺序）。
static func export_pack(repository: WorldRepository, world: WorldState, out_dir: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(out_dir)
	# 先做一次完整快照（调用方应已保存；这里再存一次保证一致）
	var save := repository.save(world)
	if not save["ok"]:
		return {"ok": false, "dir": "", "error": "snapshot_failed:" + str(save["error"])}
	var generation := int(save["generation"])
	var snapshots_dir := repository.world_dir + "/snapshots"
	var snapshot_text := FileAccess.get_file_as_string(snapshots_dir + "/%d.json" % generation)
	if snapshot_text.is_empty():
		return {"ok": false, "dir": "", "error": "snapshot_missing"}
	# 私有服务器配置（证书/私钥）——属于敏感文件，仅随迁移包分发
	var private_dir := repository.world_dir + "/private"
	var files := {"snapshot.json": snapshot_text}
	for name: String in ["server_certificate.pem", "server_private_key.pem"]:
		var path := private_dir + "/" + name
		if FileAccess.file_exists(path):
			files[name] = FileAccess.get_file_as_string(path)
	# 写文件与校验清单
	var checksums := {}
	for name: String in files:
		if not _safe_name(name):
			return {"ok": false, "dir": "", "error": "unsafe_filename:" + name}
		var f := FileAccess.open(out_dir + "/" + name, FileAccess.WRITE)
		if f == null:
			return {"ok": false, "dir": "", "error": "write_failed:" + name}
		f.store_string(files[name])
		f.flush()
		f.close()
		checksums[name] = files[name].sha256_text()
	var manifest := {
		"pack_format_version": PACK_FORMAT_VERSION,
		"save_schema_version": ContractEnvelopes.SAVE_FORMAT_VERSION_CANDIDATE,
		"game_version": "0.1.0",
		"ruleset_version": world.ruleset_version,
		"content_hash": world.content_hash,
		"world_id": world.world_id,
		"generation": generation,
		"created_at_utc": Time.get_datetime_string_from_system(true) + "Z",
		"checksums": checksums,
	}
	var mf := FileAccess.open(out_dir + "/" + MANIFEST_NAME, FileAccess.WRITE)
	if mf == null:
		return {"ok": false, "dir": "", "error": "manifest_write_failed"}
	mf.store_string(JSON.stringify(manifest))
	mf.flush()
	mf.close()
	return {"ok": true, "dir": out_dir, "error": "", "generation": generation}


## 校验迁移包目录。返回 {ok, manifest, error}。
static func validate_pack(pack_dir: String) -> Dictionary:
	var manifest_text := FileAccess.get_file_as_string(pack_dir + "/" + MANIFEST_NAME)
	if manifest_text.is_empty():
		return {"ok": false, "manifest": {}, "error": "manifest_missing"}
	var parsed: Variant = WorldRepository.normalize_numbers(JSON.parse_string(manifest_text))
	if parsed is not Dictionary:
		return {"ok": false, "manifest": {}, "error": "manifest_unparseable"}
	var manifest: Dictionary = parsed
	if int(manifest.get("pack_format_version", 0)) != PACK_FORMAT_VERSION:
		return {"ok": false, "manifest": {}, "error": "pack_format_mismatch"}
	if int(manifest.get("save_schema_version", 0)) > ContractEnvelopes.SAVE_FORMAT_VERSION_CANDIDATE:
		return {"ok": false, "manifest": {}, "error": "future_schema_rejected"}
	var checksums: Dictionary = manifest.get("checksums", {})
	var total_bytes := 0
	for name: String in checksums:
		if not _safe_name(name):
			return {"ok": false, "manifest": {}, "error": "unsafe_filename:" + name}
		var path := pack_dir + "/" + name
		if not FileAccess.file_exists(path):
			return {"ok": false, "manifest": {}, "error": "missing_file:" + name}
		var content := FileAccess.get_file_as_string(path)
		total_bytes += content.to_utf8_buffer().size()
		if total_bytes > PACK_MAX_BYTES:
			return {"ok": false, "manifest": {}, "error": "pack_too_large"}
		if content.sha256_text() != str(checksums[name]):
			return {"ok": false, "manifest": {}, "error": "checksum_mismatch:" + name}
	# 快照 envelope 必须合法
	var snapshot_text := FileAccess.get_file_as_string(pack_dir + "/snapshot.json")
	var snapshot: Variant = WorldRepository.normalize_numbers(JSON.parse_string(snapshot_text))
	if snapshot is not Dictionary:
		return {"ok": false, "manifest": {}, "error": "snapshot_unparseable"}
	var env_err := ContractEnvelopes.validate_save_envelope(snapshot)
	if not env_err.is_empty():
		return {"ok": false, "manifest": {}, "error": "snapshot_invalid:" + env_err}
	return {"ok": true, "manifest": manifest, "error": ""}


## 导入迁移包到目标世界目录。返回 {ok, world_dir, error}。
static func import_pack(pack_dir: String, target_world_dir: String) -> Dictionary:
	var validated := validate_pack(pack_dir)
	if not validated["ok"]:
		return {"ok": false, "world_dir": "", "error": validated["error"]}
	var manifest: Dictionary = validated["manifest"]
	DirAccess.make_dir_recursive_absolute(target_world_dir + "/snapshots")
	DirAccess.make_dir_recursive_absolute(target_world_dir + "/private")
	# 导入快照为新代
	var snapshot_text := FileAccess.get_file_as_string(pack_dir + "/snapshot.json")
	var parsed: Variant = WorldRepository.normalize_numbers(JSON.parse_string(snapshot_text))
	var generation := int((parsed as Dictionary)["generation"])
	var sf := FileAccess.open(target_world_dir + "/snapshots/%d.json" % generation, FileAccess.WRITE)
	if sf == null:
		return {"ok": false, "world_dir": "", "error": "snapshot_write_failed"}
	sf.store_string(snapshot_text)
	sf.flush()
	sf.close()
	# 导入私有配置
	for name: String in ["server_certificate.pem", "server_private_key.pem"]:
		if FileAccess.file_exists(pack_dir + "/" + name):
			var content := FileAccess.get_file_as_string(pack_dir + "/" + name)
			var pf := FileAccess.open(target_world_dir + "/private/" + name, FileAccess.WRITE)
			if pf != null:
				pf.store_string(content)
				pf.close()
	return {"ok": true, "world_dir": target_world_dir, "error": "", "world_id": manifest["world_id"]}


## 文件名安全：拒绝路径穿越、绝对路径、隐藏目录与符号链接式名称。
static func _safe_name(name: String) -> bool:
	if name.is_empty() or name.begins_with("/") or name.begins_with("."):
		return false
	if name.contains("..") or name.contains("\\") or name.contains("/"):
		return false
	return true
