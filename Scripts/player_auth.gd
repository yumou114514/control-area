extends Node
## 基于 players 表的玩家注册/登录（Autoload 单例）。
## 密码哈希格式：「随机盐 + SHA-256」，存储为 salt$hash（盐为 16 字节 hex）。
## 兼容旧版（Unity）无盐裸 SHA-256 格式：登录验证通过后自动升级为加盐格式。
## 登录失败按 last_attempt_date（自然日）限流：当日失败达到上限后拒绝登录。

const MAX_FAILED_ATTEMPTS := 10
const CREDENTIALS_PATH := "user://credentials.cfg"

signal register_succeeded(player: Dictionary)
signal register_failed(message: String)
signal login_succeeded(player: Dictionary)
signal login_failed(message: String)
## 自动登录结束（无论成败都会发出）
signal auto_login_finished(success: bool)

## 当前登录的玩家记录；未登录为 {}
var current_player: Dictionary = {}

var is_logged_in: bool:
	get:
		return not current_player.is_empty()


func _ready() -> void:
	pass


## 注册新玩家。密码在本地哈希后入库（明文不落库）。
func register(username: String, password: String) -> void:
	if not DatabaseClient.is_any_ready():
		register_failed.emit("数据库未就绪")
		return
	if username.strip_edges().is_empty() or password.length() < 6:
		register_failed.emit("用户名不能为空，密码至少 6 位")
		return

	var password_hash := _hash_password(password)
	var body := {"username": username, "password_hash": password_hash}
	var result := await DatabaseClient.create_player(body)

	if result.ok and result.data is Array and (result.data as Array).size() > 0:
		var player: Dictionary = (result.data as Array)[0]
		player.erase("password_hash")
		current_player = player
		_save_credentials(username, password_hash)
		register_succeeded.emit(player)
		return

	if result.status == 409:
		register_failed.emit("用户名已存在")
		return
	register_failed.emit("注册失败（HTTP %d）：%s" % [result.status, result.raw])


## 登录：校验密码哈希，并维护 failed_attempts / last_attempt_date / last_login。
func login(username: String, password: String) -> void:
	if not DatabaseClient.is_any_ready():
		login_failed.emit("数据库未就绪")
		return

	var result := await DatabaseClient.get_player_by_username(username)
	if not result.ok:
		login_failed.emit("查询玩家失败（HTTP %d）：%s" % [result.status, result.raw])
		return

	var rows: Array = result.data if result.data is Array else []
	if rows.is_empty():
		login_failed.emit("用户名或密码错误")
		return

	var player: Dictionary = rows[0]
	var stored_hash := str(player.get("password_hash", ""))

	# 当日失败次数限流
	var today := _today()
	if str(player.get("last_attempt_date", "")) == today and int(player.get("failed_attempts", 0)) >= MAX_FAILED_ATTEMPTS:
		login_failed.emit("今日失败次数过多，请明天再试")
		return

	if not _verify_password(password, stored_hash):
		# 失败：新的一天则重置计数，否则累加
		var attempts := int(player.get("failed_attempts", 0))
		attempts = 1 if str(player.get("last_attempt_date", "")) != today else attempts + 1
		await _update_player(int(player.id), {"failed_attempts": attempts, "last_attempt_date": today})
		login_failed.emit("用户名或密码错误")
		return

	# 成功：清零失败计数，记录登录时间；旧版裸 SHA-256 哈希顺便升级为加盐格式
	var patch := {"failed_attempts": 0, "last_login": _now_utc()}
	if not stored_hash.contains("$"):
		patch["password_hash"] = _hash_password(password)
	await _update_player(int(player.id), patch)
	player.erase("password_hash")
	current_player = player
	# 保存凭证用于下次自动登录（哈希若已升级则存新哈希）
	_save_credentials(username, str(patch.get("password_hash", stored_hash)))
	login_succeeded.emit(player)


## 自动登录：用本地保存的凭证校验（对应 Unity 的 AutoLoginAsync）。
## 结束后发出 auto_login_finished；失败时自动清除本地凭证。
func auto_login() -> void:
	var creds := _load_credentials()
	if creds.is_empty():
		auto_login_finished.emit(false)
		return

	if not DatabaseClient.is_any_ready():
		_clear_credentials()
		auto_login_finished.emit(false)
		return

	var username: String = creds["username"]
	var saved_hash: String = creds["hash"]

	var result := await DatabaseClient.get_player_by_username(username)
	var rows: Array = result.data if result.ok and result.data is Array else []
	if rows.is_empty():
		_clear_credentials()
		auto_login_finished.emit(false)
		return

	var player: Dictionary = rows[0]
	var stored_hash := str(player.get("password_hash", ""))
	if saved_hash != stored_hash:
		# 凭证与服务器不一致（如改过密码）→ 清除本地凭证
		_clear_credentials()
		auto_login_finished.emit(false)
		return

	# 成功：记录登录时间（自动登录拿不到明文密码，裸哈希的升级留给下次手动登录）
	var patch := {"last_login": _now_utc()}
	await _update_player(int(player.id), patch)
	player.erase("password_hash")
	current_player = player
	print("[PlayerAuth] 自动登录成功：%s" % username)
	login_succeeded.emit(player)
	auto_login_finished.emit(true)


## 登出（清本地状态与自动登录凭证）
func logout() -> void:
	current_player = {}
	_clear_credentials()


## 当前玩家是否首次进入游戏（依据 players.first_entered 字段）
func is_first_entry() -> bool:
	if not is_logged_in:
		return false
	return not bool(current_player.get("first_entered", false))


## 标记首次进入已完成并写回数据库（本地同步置位）
func complete_first_entry() -> Dictionary:
	if not is_logged_in:
		return {}
	current_player["first_entered"] = true
	var result := await _update_player(int(current_player.id), {"first_entered": true})
	if not result.ok:
		print("[PlayerAuth] 标记首次进入失败：%s" % result.raw)
	return result


# ---------- 凭证存取 ----------

func _save_credentials(username: String, password_hash: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "username", username)
	cfg.set_value("auth", "hash", password_hash)
	cfg.save(CREDENTIALS_PATH)


func _load_credentials() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(CREDENTIALS_PATH) != OK:
		return {}
	var username := str(cfg.get_value("auth", "username", ""))
	var password_hash := str(cfg.get_value("auth", "hash", ""))
	if username.is_empty() or password_hash.is_empty():
		return {}
	return {"username": username, "hash": password_hash}


func _clear_credentials() -> void:
	if FileAccess.file_exists(CREDENTIALS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CREDENTIALS_PATH))


# ---------- 内部工具 ----------

func _update_player(id: int, patch: Dictionary) -> Dictionary:
	return await DatabaseClient.update_player(id, patch)


func _today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


func _now_utc() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


func _hash_password(password: String, salt_hex: String = "") -> String:
	if salt_hex.is_empty():
		var crypto := Crypto.new()
		salt_hex = crypto.generate_random_bytes(16).hex_encode()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((salt_hex + password).to_utf8_buffer())
	return "%s$%s" % [salt_hex, ctx.finish().hex_encode()]


func _verify_password(password: String, stored: String) -> bool:
	if stored.contains("$"):
		var parts := stored.split("$")
		if parts.size() != 2:
			return false
		return _hash_password(password, parts[0]) == stored
	# 旧版（Unity）格式：无盐裸 SHA-256
	return _hash_bare_sha256(password) == stored


func _hash_bare_sha256(password: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(password.to_utf8_buffer())
	return ctx.finish().hex_encode()
