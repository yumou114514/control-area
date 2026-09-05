extends Node
## MariaDB 客户端（Autoload 单例，GDScript 版）。
## 通过内网 PHP REST 网关（db_api.php）访问 MariaDB；Godot 标准版无法直连 MySQL 协议，
## 故由部署在 MariaDB 同站点（phpMyAdmin 所在 web 根目录）的 PHP 脚本充当 HTTP→SQL 网关。
## 网关为多表通用接口：统一 POST {table, op, where, data, limit}，支持 select/insert/update/upsert/delete。
## 配置读取优先级：环境变量 MARIADB_API_BASE > res://Config/mariadb.json 的 "apiBase"。
##
## 返回结构统一为 { "status": int, "ok": bool, "data": Variant, "raw": String }，
## 其中 data 对读操作是行数组（Array），便于上层无差别处理。

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


## 通用查询：按等值条件 [param where] 过滤，[param limit] > 0 时限制行数。
## 返回 data = 行数组（未找到为 []）。
func select(table: String, where: Dictionary = {}, limit: int = -1) -> Dictionary:
	var body := {"table": table, "op": "select", "where": where}
	if limit > 0:
		body["limit"] = limit
	return await _call(body)


## 插入一行。[param data] 为列值字典（仅网关白名单列生效）。
## 成功返回 data = [新行]、status 201；唯一键冲突返回 status 409。
func insert(table: String, data: Dictionary) -> Dictionary:
	return await _call({"table": table, "op": "insert", "data": data})


## 按 [param where]（须命中主键）更新 [param data] 中的列。
func update(table: String, where: Dictionary, data: Dictionary) -> Dictionary:
	return await _call({"table": table, "op": "update", "where": where, "data": data})


## 存在则更新、不存在则插入（依赖主键/唯一键）。[param data] 需含主键列。
func upsert(table: String, data: Dictionary) -> Dictionary:
	return await _call({"table": table, "op": "upsert", "data": data})


## 按 [param where] 删除行。
func delete(table: String, where: Dictionary) -> Dictionary:
	return await _call({"table": table, "op": "delete", "where": where})


## 统一网关调用：所有操作走单一 POST（body 为 JSON）。
func _call(body: Dictionary) -> Dictionary:
	if not is_ready:
		return {"status": 0, "ok": false, "data": null, "raw": failure_reason}

	var http := HTTPRequest.new()
	http.timeout = HTTP_TIMEOUT
	add_child(http)

	var url := "%s/db_api.php" % api_base
	var err := http.request(url, PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return {"status": 0, "ok": false, "data": null, "raw": "HTTP 请求发送失败：%s" % error_string(err)}

	var result: Array = await http.request_completed
	http.queue_free()

	var status: int = result[1]
	var raw := (result[3] as PackedByteArray).get_string_from_utf8()
	# 空响应体时给出可读原因（连不上/超时等），避免上层只看到空字符串无法排查
	if status == 0 and raw.is_empty():
		match int(result[0]):
			HTTPRequest.RESULT_CANT_CONNECT:
				raw = "无法连接 MariaDB 接口 %s（服务未启动/端口不对/被防火墙拦截）" % url
			HTTPRequest.RESULT_TIMEOUT:
				raw = "连接 MariaDB 接口超时：%s" % url
			HTTPRequest.RESULT_CANT_RESOLVE:
				raw = "无法解析 MariaDB 接口地址：%s" % url
			_:
				raw = "请求 MariaDB 接口失败（result=%d）：%s" % [int(result[0]), url]
	var parsed: Variant = null
	if not raw.is_empty():
		var json := JSON.new()
		if json.parse(raw) == OK:
			parsed = json.data
	# 网关返回 {"ok":bool,"rows":Array,...}，这里把 rows 提升为 data
	var rows: Variant = null
	if parsed is Dictionary:
		rows = (parsed as Dictionary).get("rows", null)
	return {"status": status, "ok": status >= 200 and status < 300, "data": rows, "raw": raw}
