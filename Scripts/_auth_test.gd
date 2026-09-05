extends Node
## 临时：PlayerAuth 注册/登录全流程自动化测试（跑完即删）


var _test_user := "autotest_%d" % (randi() % 1000000)
var _test_pass := "TestPass123"


func _ready() -> void:
	PlayerAuth.register_succeeded.connect(_on_register_ok)
	PlayerAuth.register_failed.connect(func(m): _fail("register", m))
	PlayerAuth.login_succeeded.connect(_on_login_ok)
	PlayerAuth.login_failed.connect(func(m): _fail("login", m))

	print("[AuthTest] user=%s" % _test_user)
	if not MariaDBClient.is_ready:
		_fail("init", MariaDBClient.failure_reason)
		return
	PlayerAuth.register(_test_user, _test_pass)


func _on_register_ok(player: Dictionary) -> void:
	print("[AuthTest] register OK id=%s" % player.get("id"))
	PlayerAuth.logout()
	PlayerAuth.login(_test_user, _test_pass)


func _on_login_ok(player: Dictionary) -> void:
	print("[AuthTest] login OK id=%s" % player.get("id"))
	_cleanup(int(player.id))


func _cleanup(id: int) -> void:
	var res := await DatabaseClient.delete_player(id)
	print("[AuthTest] cleanup DELETE status=%d" % res.status)
	_done("PASS")


func _fail(step: String, msg: String) -> void:
	_done("FAIL@%s: %s" % [step, msg])


func _done(summary: String) -> void:
	var out := FileAccess.open("user://auth_test.log", FileAccess.WRITE)
	out.store_string(summary)
	print("[AuthTest] %s" % summary)
	get_tree().quit()
