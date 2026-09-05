extends Node
## 临时冒烟测试（场景版）：验证 MariaDB 网关（db_api.php）players 表连通性（跑完即删）


func _ready() -> void:
	var api_base := OS.get_environment("MARIADB_API_BASE")
	if api_base.is_empty() and FileAccess.file_exists("res://Config/mariadb.json"):
		var file := FileAccess.open("res://Config/mariadb.json", FileAccess.READ)
		if file != null:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				api_base = str((json.data as Dictionary).get("apiBase", ""))
	api_base = api_base.strip_edges().rstrip("/")
	if api_base.is_empty():
		_finish("no_config", "缺少 MARIADB_API_BASE / Config/mariadb.json")
		return
	print("[SmokeTest] apiBase = %s" % api_base)

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_done)
	var body := JSON.stringify({"table": "players", "op": "select", "limit": 1})
	var err := http.request(
		"%s/db_api.php" % api_base,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		body,
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
