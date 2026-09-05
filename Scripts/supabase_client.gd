extends Node
## Supabase 全局客户端（Autoload 单例，GDScript 版）。
## 配置读取优先级：环境变量 SUPABASE_URL / SUPABASE_ANON_KEY > res://Config/supabase.json

const CONFIG_PATH := "res://Config/supabase.json"

## 初始化完成
signal initialized
## 初始化失败，携带错误信息
signal initialize_failed(message: String)

var url: String = ""
var anon_key: String = ""
var is_ready: bool = false
var failure_reason: String = ""

## PostgREST 基础地址，如 https://xxx.supabase.co/rest/v1
var rest_base: String:
	get:
		return url.path_join("rest/v1")


func _ready() -> void:
	_initialize()


func _initialize() -> void:
	# 1. 环境变量优先
	url = OS.get_environment("SUPABASE_URL")
	anon_key = OS.get_environment("SUPABASE_ANON_KEY")

	# 2. 本地配置文件
	if url.is_empty() or anon_key.is_empty():
		if FileAccess.file_exists(CONFIG_PATH):
			var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
			if file != null:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
					var dict: Dictionary = json.data
					if url.is_empty():
						url = str(dict.get("url", ""))
					if anon_key.is_empty():
						anon_key = str(dict.get("anonKey", ""))

	if url.is_empty() or anon_key.is_empty():
		failure_reason = "缺少配置：请设置环境变量 SUPABASE_URL/SUPABASE_ANON_KEY，或创建 Config/supabase.json（参考 supabase.json.example）"
		push_error("[Supabase] " + failure_reason)
		initialize_failed.emit(failure_reason)
		return

	is_ready = true
	print("[Supabase] 客户端初始化完成%s")
	initialized.emit()


## 基础请求头（PostgREST 要求 apikey + Bearer）
func _base_headers() -> PackedStringArray:
	return PackedStringArray([
		"apikey: %s" % anon_key,
		"Authorization: Bearer %s" % anon_key,
		"Content-Type: application/json",
	])


## 向 Supabase 发起 HTTP 请求。
## [param path] 相对 rest/v1 的路径（可带查询参数），如 "players?username=eq.foo"
## [param method] HTTPClient.Method.*
## [param body] 请求体（Dictionary/Array 会被序列化为 JSON）
## [param extra_headers] 附加请求头，如 "Prefer: return=representation"
## 返回 { "status": int, "ok": bool, "data": Variant, "raw": String }
func request(path: String, method: int = HTTPClient.METHOD_GET, body: Variant = null, extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)

	var headers := _base_headers()
	headers.append_array(extra_headers)

	var body_str := ""
	if body != null:
		body_str = JSON.stringify(body)

	var err := http.request(rest_base.path_join(path), headers, method, body_str)
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

	return {"status": status, "ok": status >= 200 and status < 300, "data": data, "raw": raw}
