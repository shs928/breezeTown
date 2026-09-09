class_name LocalIdentity
## 本地身份（NET 唯一维护，M1 NET-00）。契约 3.2 / 7.2 的单人部分：
## - 为每个世界生成高熵随机凭据，本地持久保存（不写入世界存档、不进日志）。
## - 凭据只以 SHA-256 摘要进入世界成员记录（世界文件不含明文）。
## - 继续世界复用同一身份；身份激活必须在世界首次保存成功之后。
## - 远端认证是 M2 NET-02 的工作，本类只提供本地候选所有者与本地会话。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractIds := preload("res://src/contracts/contract_ids.gd")

const IDENTITY_DIR := "identity"
const CREDENTIAL_BYTES := 32  # 256 bit


## 本地身份配置路径：与用户设置目录隔离，不随世界目录迁移。
static func identity_path(user_data_dir: String, world_id: String) -> String:
	return user_data_dir + "/" + IDENTITY_DIR + "/" + world_id + ".json"


## 为一个世界生成新凭据并持久化。返回 {ok, credential, digest, path}。
## credential 只返回一次给调用方，之后应丢弃明文。
static func create(user_data_dir: String, world_id: String) -> Dictionary:
	if not ContractIds.is_world_id(world_id):
		return {"ok": false, "credential": "", "digest": "", "path": "", "error": "bad_world_id"}
	var dir := user_data_dir + "/" + IDENTITY_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	var credential := Crypto.new().generate_random_bytes(CREDENTIAL_BYTES).hex_encode()
	var digest := credential.sha256_text()
	var path := identity_path(user_data_dir, world_id)
	var record := {"world_id": world_id, "credential_digest": digest, "created_at": Time.get_unix_time_from_system()}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "credential": "", "digest": "", "path": "", "error": "write_failed"}
	f.store_string(JSON.stringify(record))
	f.flush()
	f.close()
	# 明文凭据单独保存，权限最小化（世界目录之外）
	var cred_path := path + ".cred"
	var cf := FileAccess.open(cred_path, FileAccess.WRITE)
	if cf == null:
		return {"ok": false, "credential": "", "digest": "", "path": "", "error": "credential_write_failed"}
	cf.store_string(credential)
	cf.flush()
	cf.close()
	return {"ok": true, "credential": credential, "digest": digest, "path": cred_path, "error": ""}


## 读取已保存的凭据摘要（用于继续世界时校验身份）。
static func load_digest(user_data_dir: String, world_id: String) -> String:
	var text := FileAccess.get_file_as_string(identity_path(user_data_dir, world_id))
	if text.is_empty():
		return ""
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		return ""
	return str((parsed as Dictionary).get("credential_digest", ""))


## 校验一个凭据是否匹配已保存的摘要（常量时间比较由摘要特性保证）。
static func verify(user_data_dir: String, world_id: String, credential: String) -> bool:
	var stored := load_digest(user_data_dir, world_id)
	return not stored.is_empty() and stored == credential.sha256_text()


static func exists(user_data_dir: String, world_id: String) -> bool:
	return not load_digest(user_data_dir, world_id).is_empty()
