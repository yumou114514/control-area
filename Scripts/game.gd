extends Control
## 登录成功后的游戏主场景（占位）。
## 首次进入（players.first_entered = false）时强制跳转到首次进入场景。


@onready var _welcome_label: Label = $Center/VBox/WelcomeLabel
@onready var _logout_button: Button = $Center/VBox/LogoutButton


func _ready() -> void:
	if not PlayerAuth.is_logged_in:
		# 未登录直接进来（如直接运行本场景），退回第一屏（_ready 中切场景需延迟）
		get_tree().change_scene_to_file.call_deferred("res://Scenes/Main.tscn")
		return
	if PlayerAuth.is_first_entry():
		# 首次进入：强制进入首次进入场景，不展示主界面
		get_tree().change_scene_to_file.call_deferred("res://Scenes/FirstEntry.tscn")
		return

	_welcome_label.text = "欢迎，%s！" % PlayerAuth.current_player.get("username", "玩家")
	_logout_button.pressed.connect(_on_logout_pressed)


func _on_logout_pressed() -> void:
	PlayerAuth.logout()
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")
