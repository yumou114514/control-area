extends Node
## 临时：哈希兼容性离线验证（跑完即删）


func _ready() -> void:
	# Unity（C# SHA256.Create）对 "TestPass123" 的结果，用作基准
	var expect := "c1b8b58c3e7ac442b525e87709d5c1aef49a5d5acb70551be645887a978e238a"

	var bare: String = PlayerAuth._hash_bare_sha256("TestPass123")
	print("[HashTest] bare=%s" % bare)
	print("[HashTest] bare_match_unity=%s" % str(bare == expect))

	var salted: String = PlayerAuth._hash_password("TestPass123")
	print("[HashTest] salted=%s" % salted)
	print("[HashTest] verify_salted=%s" % str(PlayerAuth._verify_password("TestPass123", salted)))
	print("[HashTest] verify_bare_legacy=%s" % str(PlayerAuth._verify_password("TestPass123", expect)))
	print("[HashTest] verify_wrong_pass=%s" % str(PlayerAuth._verify_password("WrongPass", expect)))
	get_tree().quit()
