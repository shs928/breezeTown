extends Object
## NET-01 实验库：临时证书生成、DTLS 选项、消息收发辅助。
## 独立实验代码（spike），不进入正式工程；协议语义候选写入 docs/adr/NET-01.md。

## 生成自签证书对并保存 PEM。cn 必须与客户端 dtls_client_setup 的 hostname 一致。
## 注意 4.7 的日期格式是 YYYYMMDDHHMMSS，issuer 必须包含 CN=/O=/C=，否则生成空证书。
static func gen_certs(out_dir: String, cn: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var issuer := "CN=%s,O=BreezeTown Spike,C=CN" % cn
	var cert := crypto.generate_self_signed_certificate(key, issuer, "20260101000000", "20271231235959")
	var key_path := out_dir + "/server.key"
	var cert_path := out_dir + "/server.pem"
	var key_err := key.save(key_path)
	var cert_err := cert.save(cert_path)
	if key_err != OK or cert_err != OK:
		return {"ok": false, "reason": "save_failed key=%d cert=%d" % [key_err, cert_err]}
	if FileAccess.get_file_as_string(cert_path).length() < 200:
		return {"ok": false, "reason": "empty certificate generated"}
	return {"ok": true, "key_path": key_path, "cert_path": cert_path}


static func server_options(cert_path: String, key_path: String) -> TLSOptions:
	var key := CryptoKey.new()
	var key_err := key.load(key_path)
	var cert := X509Certificate.new()
	var cert_err := cert.load(cert_path)
	if key_err != OK or cert_err != OK:
		push_error("load key/cert failed: %d/%d" % [key_err, cert_err])
		return null
	return TLSOptions.server(key, cert)


static func client_options(trusted_cert_path: String) -> TLSOptions:
	var cert := X509Certificate.new()
	if cert.load(trusted_cert_path) != OK:
		push_error("load trusted cert failed")
		return null
	return TLSOptions.client(cert, "")


static func send_msg(peer: ENetPacketPeer, msg: Dictionary) -> void:
	peer.put_packet(JSON.stringify(msg).to_utf8_buffer())


static func recv_msg(peer: ENetPacketPeer) -> Variant:
	return JSON.parse_string((peer.get_packet() as PackedByteArray).get_string_from_utf8())


## 凭据：256 bit 随机 hex。日志只允许出现其 SHA-256 摘要前缀，绝不允许原文。
static func new_token() -> String:
	return Crypto.new().generate_random_bytes(32).hex_encode()


static func digest_of(token: String) -> String:
	return token.sha256_text()


static func digest_prefix(token: String, chars := 12) -> String:
	return digest_of(token).substr(0, chars)
