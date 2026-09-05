extends Control
## 游戏第一屏：玩家登录 / 注册。


@onready var _username_edit: LineEdit = $Center/Panel/VBox/UsernameEdit
@onready var _password_edit: LineEdit = $Center/Panel/VBox/PasswordEdit
@onready var _login_button: Button = $Center/Panel/VBox/Buttons/LoginButton
@onready var _register_button: Button = $Center/Panel/VBox/Buttons/RegisterButton
@onready var _status_label: Label = $Center/Panel/VBox/StatusLabel


func _ready() -> void:
	_login_button.pressed.connect(_on_login_pressed)
	_register_button.pressed.connect(_on_register_pressed)
	_password_edit.text_submitted.connect(func(_text): _on_login_pressed())

	PlayerAuth.login_succeeded.connect(_on_login_succeeded)
	PlayerAuth.login_failed.connect(_on_auth_failed)
	PlayerAuth.register_succeeded.connect(_on_register_succeeded)
	PlayerAuth.register_failed.connect(_on_auth_failed)

	# 数据库 未就绪时禁止操作
	if not MariaDBClient.is_ready:
		_set_busy(true)
		var reason := MariaDBClient.failure_reason
		_show_error(reason if not reason.is_empty() else "正在连接数据库…")


func _on_login_pressed() -> void:
	var username := _username_edit.text.strip_edges()
	var password := _password_edit.text
	if username.is_empty() or password.is_empty():
		_show_error("请输入用户名和密码")
		return
	_set_busy(true)
	_show_info("登录中…")
	PlayerAuth.login(username, password)


func _on_register_pressed() -> void:
	var username := _username_edit.text.strip_edges()
	var password := _password_edit.text
	if username.is_empty() or password.is_empty():
		_show_error("请输入用户名和密码")
		return
	_set_busy(true)
	_show_info("注册中…")
	PlayerAuth.register(username, password)


func _on_login_succeeded(player: Dictionary) -> void:
	_show_info("登录成功，欢迎 %s" % player.get("username"))
	_enter_game()


func _on_register_succeeded(player: Dictionary) -> void:
	_show_info("注册成功，欢迎 %s" % player.get("username"))
	_enter_game()


func _on_auth_failed(message: String) -> void:
	_set_busy(false)
	_show_error(message)


func _enter_game() -> void:
	await get_tree().create_timer(0.6).timeout
	get_tree().change_scene_to_file("res://Scenes/Loading.tscn")


func _set_busy(busy: bool) -> void:
	_login_button.disabled = busy
	_register_button.disabled = busy
	_username_edit.editable = not busy
	_password_edit.editable = not busy


func _show_info(text: String) -> void:
	_status_label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.98))
	_status_label.text = text


func _show_error(text: String) -> void:
	_status_label.add_theme_color_override("font_color", Color(0.95, 0.42, 0.42))
	_status_label.text = text
