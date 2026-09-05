extends Node
## 临时冒烟测试（场景版）：验证 Supabase players 表连通性（跑完即删）


func _ready() -> void:
	var file := FileAccess.open("res://Config/supabase.json", FileAccess.READ)
	if file == null:
		_finish("no_config", "缺少 Config/supabase.json")
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		_finish("bad_config", "配置文件解析失败")
		return
	var cfg: Dictionary = json.data
	var url: String = str(cfg.get("url", "")).path_join("rest/v1")
	var key: String = str(cfg.get("anonKey", ""))
	print("[SmokeTest] URL = %s" % url)

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_done)
	var err := http.request(
		url.path_join("players?select=id,username&limit=1"),
		PackedStringArray(["apikey: %s" % key, "Authorization: Bearer %s" % key]),
		HTTPClient.METHOD_GET,
	)
	if err != OK:
		_finish("request_error", error_string(err))


func _on_done(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_finish("result=%d status=%d" % [result, status], body.get_string_from_utf8())


func _finish(tag: String, detail: String) -> void:
	var out := FileAccess.open("user://smoke_test.log", FileAccess.WRITE)
	out.store_string("%s\n%s" % [tag, detail])
	print("[SmokeTest] %s: %s" % [tag, detail])
	get_tree().quit()
