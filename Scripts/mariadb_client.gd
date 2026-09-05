extends Node
## MariaDB 客户端（Autoload 单例，GDScript 版）。
## 通过内网 PHP REST 接口（players_api.php）访问 MariaDB；Godot 标准版无法直连 MySQL 协议，
## 故由部署在 MariaDB 同站点（phpMyAdmin 所在 web 根目录）的 PHP 脚本充当 HTTP→SQL 网关。
## 配置读取优先级：环境变量 MARIADB_API_BASE > res://Config/mariadb.json 的 "apiBase"。
##
## 返回结构与 SupabaseClient.request 保持一致：
## { "status": int, "ok": bool, "data": Variant, "raw": String }
## 其中 data 对读操作是行数组（Array），与 PostgREST 一致，便于上层无差别处理。

const CONFIG_PATH := "res://Config/mariadb.json"
const HTTP_TIMEOUT := 8.0

signal initialized
signal initialize_failed(message: String)

var api_base: String = ""
var is_ready: bool = false
var failure_reason: String = ""


func _ready() -> void:
	_initialize()


func _initialize() -> void:
	api_base = OS.get_environment("MARIADB_API_BASE")
	if api_base.is_empty() and FileAccess.file_exists(CONFIG_PATH):
		var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if file != null:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				api_base = str((json.data as Dictionary).get("apiBase", ""))
	api_base = api_base.strip_edges().rstrip("/")

	if api_base.is_empty():
		failure_reason = "缺少配置：请设置环境变量 MARIADB_API_BASE，或创建 Config/mariadb.json（参考 mariadb.json.example）"
		push_warning("[MariaDB] " + failure_reason)
		initialize_failed.emit(failure_reason)
		return

	is_ready = true
	print("[MariaDB] 客户端初始化完成：%s" % api_base)
	initialized.emit()


## 按用户名查询，返回行数组（未找到为 []）。
func get_by_username(username: String) -> Dictionary:
	return await _call("get_by_username", {"username": username})


## 按主键 id 查询，返回行数组（未找到为 []）。
func get_by_id(id: int) -> Dictionary:
	return await _call("get_by_id", {"id": id})


## 创建玩家。[param row] 可含 "id"（与 Supabase 对齐时传入，接口按 upsert 处理）。
## 成功返回 data = [新行]；用户名冲突返回 status 409。
func create(row: Dictionary) -> Dictionary:
	return await _call("create", row, true)


## 按 id 更新 [param patch] 中的字段。
func update(id: int, patch: Dictionary) -> Dictionary:
	var body := patch.duplicate()
	body["id"] = id
	return await _call("update", body, true)


## 统一的接口调用：读用 GET，写用 POST（body 为 JSON）。
func _call(action: String, params: Dictionary, use_post: bool = false) -> Dictionary:
	if not is_ready:
		return {"status": 0, "ok": false, "data": null, "raw": failure_reason}

	var http := HTTPRequest.new()
	http.timeout = HTTP_TIMEOUT
	add_child(http)

	var url := "%s/players_api.php?action=%s" % [api_base, action.uri_encode()]
	var err: int
	if use_post:
		err = http.request(url, PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST, JSON.stringify(params))
	else:
		var query := PackedStringArray()
		for key in params:
			query.append("%s=%s" % [key, str(params[key]).uri_encode()])
		if not query.is_empty():
			url += "&" + "&".join(query)
		err = http.request(url, PackedStringArray(), HTTPClient.METHOD_GET)

	if err != OK:
		http.queue_free()
		return {"status": 0, "ok": false, "data": null, "raw": "HTTP 请求发送失败：%s" % error_string(err)}

	var result: Array = await http.request_completed
	http.queue_free()

	var status: int = result[1]
	var raw := (result[3] as PackedByteArray).get_string_from_utf8()
	var data: Variant = null
	if not raw.is_empty():
		var json := JSON.new()
		if json.parse(raw) == OK:
			data = json.data
	# PHP 接口返回 {"ok":bool,"rows":Array,...}，这里把 rows 提升为 data，向 PostgREST 形态看齐
	var rows: Variant = null
	if data is Dictionary:
		rows = (data as Dictionary).get("rows", null)
	return {"status": status, "ok": status >= 200 and status < 300, "data": rows, "raw": raw}
