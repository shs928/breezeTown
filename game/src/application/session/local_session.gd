class_name LocalSession
## 本地会话（NET 唯一维护，M1 NET-00）。负责把身份、世界运行时、持久化组合起来：
## 创建世界 → 初始化所有者身份 → 首次保存成功后才激活；继续世界 → 复用同一身份。
## 远端连接生命周期是 M2 NET-02 的工作。

const ContractLimits := preload("res://src/contracts/contract_limits.gd")
const ContractError := preload("res://src/contracts/contract_error.gd")
const WorldState := preload("res://src/domain/world/world_state.gd")
const WorldRuntime := preload("res://src/application/world/world_runtime.gd")
const WorldRepository := preload("res://src/infrastructure/persistence/world_repository.gd")
const LocalIdentity := preload("res://src/infrastructure/identity/local_identity.gd")
const ItemCatalog := preload("res://src/domain/economy/item_catalog.gd")
const NetTransport := preload("res://src/infrastructure/network/net_transport.gd")
const ServerSession := preload("res://src/application/session/server_session.gd")
const ConnectionCard := preload("res://src/infrastructure/network/connection_card.gd")
const EconomyHandlers := preload("res://src/application/economy/economy_handlers.gd")
const FarmHandlers := preload("res://src/application/farming/farm_handlers.gd")
const ProjectHandler := preload("res://src/application/projects/project_handler.gd")
const ReliefHandler := preload("res://src/application/economy/relief_handler.gd")

enum State { INACTIVE, ACTIVE, FAILED }

var state: int = State.INACTIVE
var world: WorldState = null
var runtime: WorldRuntime = null
var repository: WorldRepository = null
var player_id := ""
var credential := ""          # 明文仅存活于本次会话，不写日志
var last_error := ""
var server_session: ServerSession = null   # listen_host 模式下的权威服务器会话
var connection_card: Dictionary = {}
var economy: EconomyHandlers = null
var farm: FarmHandlers = null
var projects: ProjectHandler = null
var relief: ReliefHandler = null


## 创建新世界。返回 {ok, error}。
func create_world(user_data_dir: String, worlds_dir: String, display_name: String, world_display_name: String) -> Dictionary:
	if world != null:
		return {"ok": false, "error": "session_already_active"}
	var cleaned_name := ContractLimits.sanitize_display_name(display_name)
	if cleaned_name.is_empty():
		return {"ok": false, "error": ContractError.INVALID_ARGUMENT}
	var cleaned_world_name := ContractLimits.sanitize_display_name(world_display_name)
	if cleaned_world_name.is_empty():
		return {"ok": false, "error": ContractError.INVALID_ARGUMENT}
	var world_id := "w" + Crypto.new().generate_random_bytes(16).hex_encode()
	var owner_id := "m" + Crypto.new().generate_random_bytes(16).hex_encode()
	var new_world := WorldState.create(world_id, owner_id, cleaned_name)
	new_world.content_hash = ItemCatalog.content_hash()
	new_world.members[0]["world_display_name"] = cleaned_world_name

	# 1) 建立本地身份
	var identity := LocalIdentity.create(user_data_dir, world_id)
	if not identity["ok"]:
		return {"ok": false, "error": identity["error"]}
	new_world.members[0]["credential_digest"] = identity["digest"]

	# 2) 组合运行时
	var new_runtime := WorldRuntime.new()
	new_runtime.setup(new_world, _load_map())
	var new_repo := WorldRepository.new()
	new_repo.world_dir = worlds_dir + "/" + world_id
	new_repo.world_id = world_id

	# 3) 首次保存成功后才激活身份
	var save := new_repo.save(new_world)
	if not save["ok"]:
		return {"ok": false, "error": "first_save_failed:" + str(save["error"])}

	world = new_world
	runtime = new_runtime
	repository = new_repo
	player_id = owner_id
	credential = identity["credential"]
	_install_handlers()
	state = State.ACTIVE
	return {"ok": true, "error": "", "world_id": world_id}


## 继续已有世界。返回 {ok, error}。
func continue_world(user_data_dir: String, worlds_dir: String, world_id: String) -> Dictionary:
	if not LocalIdentity.exists(user_data_dir, world_id):
		return {"ok": false, "error": ContractError.NOT_AUTHENTICATED}
	var repo := WorldRepository.new()
	repo.world_dir = worlds_dir + "/" + world_id
	repo.world_id = world_id
	var lock := repo.claim_lock()
	if not lock["ok"]:
		return {"ok": false, "error": "world_locked:" + str(lock["reason"])}
	var loaded := repo.load_latest()
	if not loaded["ok"]:
		repo.release_lock()
		return {"ok": false, "error": "load_failed"}
	var restored: WorldState = loaded["world"]
	# 身份校验：世界中的所有者摘要必须与本地凭据摘要一致
	var local_digest := LocalIdentity.load_digest(user_data_dir, world_id)
	if str(restored.find_member(restored.owner_player_id).get("credential_digest", "")) != local_digest:
		repo.release_lock()
		return {"ok": false, "error": ContractError.NOT_AUTHENTICATED}
	var new_runtime := WorldRuntime.new()
	new_runtime.setup(restored, _load_map())
	world = restored
	runtime = new_runtime
	repository = repo
	player_id = restored.owner_player_id
	_install_handlers()
	state = State.ACTIVE
	return {"ok": true, "error": "", "game_day": restored.game_day}


## 装配全部玩法处理器（本地房主与远端命令共用同一条权威路径）。
## 这样远端客户端能执行农务/经济/建设/救济，而不是只有管理命令。
func _install_handlers() -> void:
	var catalog := ItemCatalog.load_from_disk()
	economy = EconomyHandlers.new()
	economy.setup(runtime, catalog)
	farm = FarmHandlers.new()
	farm.setup(runtime, catalog)
	projects = ProjectHandler.new()
	projects.setup(runtime, catalog)
	relief = ReliefHandler.new()
	relief.setup(runtime, catalog)
	runtime.set_day_settle_hook(Callable(farm, "settle_growth"))
	economy.ensure_backpack(player_id)


## 开启联机监听（listen_host）。返回 {ok, error, card}。
## 证书与私钥写入世界私有目录；连接卡只含公开信息。
func start_hosting(bind_address: String, port: int, tls_hostname := "localhost") -> Dictionary:
	if not is_active():
		return {"ok": false, "error": "no_active_session", "card": {}}
	if server_session != null:
		return {"ok": false, "error": "already_hosting", "card": {}}
	var private_dir := repository.world_dir + "/private"
	DirAccess.make_dir_recursive_absolute(private_dir)
	var cert_path := private_dir + "/server_certificate.pem"
	var key_path := private_dir + "/server_private_key.pem"
	if not FileAccess.file_exists(cert_path) or not FileAccess.file_exists(key_path):
		if not _generate_server_certificate(tls_hostname, cert_path, key_path):
			return {"ok": false, "error": "certificate_generation_failed", "card": {}}
	var transport := NetTransport.new()
	var session := ServerSession.new()
	session.setup(runtime, transport)
	session.approval_mode = ServerSession.Approval.MANUAL
	session.local_host_online = true   # 房主本地角色占一席
	var started := session.start(bind_address, port, cert_path, key_path)
	if not started["ok"]:
		return {"ok": false, "error": started["error"], "card": {}}
	server_session = session
	var card := ConnectionCard.build(bind_address, int(started["port"]), tls_hostname, cert_path, _world_display_name())
	if card.is_empty() or not ConnectionCard.validate(card).is_empty():
		return {"ok": false, "error": "connection_card_failed", "card": {}}
	connection_card = card
	return {"ok": true, "error": "", "card": card}


## 轮询托管服务器（每帧调用）。
func poll_hosting(timeout_ms := 0) -> int:
	if server_session == null:
		return 0
	return server_session.poll(timeout_ms)


## 关闭托管（先通知客户端，再释放端口）。
func stop_hosting() -> void:
	if server_session != null:
		server_session.shutdown()
		server_session.transport.close()
		server_session = null


func pending_approvals() -> Array:
	if server_session == null:
		return []
	return server_session.pending_digests()


func approve_join(digest_or_connection: String) -> Dictionary:
	if server_session == null:
		return {"ok": false, "error": "not_hosting"}
	return server_session.approve(digest_or_connection)


func reject_join(digest_or_connection: String) -> Dictionary:
	if server_session == null:
		return {"ok": false, "error": "not_hosting"}
	return server_session.reject(digest_or_connection)


func kick_member(player_id_to_kick: String) -> Dictionary:
	if server_session == null:
		return {"ok": false, "error": "not_hosting"}
	return server_session.kick(player_id_to_kick)


func revoke_member(player_id_to_revoke: String) -> Dictionary:
	if server_session == null:
		return {"ok": false, "error": "not_hosting"}
	var result := server_session.revoke(player_id_to_revoke)
	if result["ok"]:
		repository.save(world)
	return result


func rebind_member(player_id_to_rebind: String, new_digest: String) -> Dictionary:
	if server_session == null:
		return {"ok": false, "error": "not_hosting"}
	var result := server_session.rebind(player_id_to_rebind, new_digest)
	if result["ok"]:
		repository.save(world)
	return result


## 生成服务器证书（自签，单服务器场景）。M0 实验已确认 4.7 的日期格式与 issuer 要求。
func _generate_server_certificate(common_name: String, cert_path: String, key_path: String) -> bool:
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var issuer := "CN=%s,O=BreezeTown,C=CN" % common_name
	var cert := crypto.generate_self_signed_certificate(key, issuer, "20260101000000", "20271231235959")
	if key.save(key_path) != OK or cert.save(cert_path) != OK:
		return false
	return FileAccess.get_file_as_string(cert_path).length() > 200


func _world_display_name() -> String:
	for member: Dictionary in world.members:
		if member.has("world_display_name"):
			return str(member["world_display_name"])
	return "微风小镇"


## 保存并关闭会话（正常退出）。
func close(reason := "quit") -> Dictionary:
	if world == null:
		return {"ok": false, "error": "no_active_session"}
	stop_hosting()
	var save := repository.save(world)
	repository.release_lock()
	world = null
	runtime = null
	repository = null
	player_id = ""
	credential = ""
	state = State.INACTIVE
	if not save["ok"]:
		return {"ok": false, "error": "save_failed_on_close:" + str(save["error"])}
	return {"ok": true, "error": "", "reason": reason}


func is_active() -> bool:
	return state == State.ACTIVE


func _load_map() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/schema/examples/map_town_minimal.json"))
	return parsed if parsed is Dictionary else {}
