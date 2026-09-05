extends Control
## 启动闪屏：黑屏等待 → 背景渐变为白 → studio logo → 渐变 → game logo → 进入对应界面。
## 自动登录与闪屏并行进行：播完且自动登录有结果后才切换，
## 登录成功进 Game，否则进登录第一屏。

## 开场黑屏等待时长
const BLACK_WAIT := 0.5
## 背景由黑变白的渐变时长
const BG_FADE := 0.5
const FADE_IN := 0.5
const HOLD := 1.5
const FADE_OUT := 0.5
## 闪屏播完后等待自动登录结果的超时时间，超时按失败处理进登录屏
const AUTO_LOGIN_TIMEOUT := 8.0

@onready var _background: ColorRect = $Background
@onready var _studio_logo: TextureRect = $StudioLogo
@onready var _game_logo: TextureRect = $GameLogo

var _splash_done := false
var _auto_login_settled := false
var _auto_login_ok := false


func _ready() -> void:
	_background.color = Color.BLACK
	_studio_logo.modulate.a = 0.0
	_game_logo.modulate.a = 0.0

	PlayerAuth.auto_login_finished.connect(_on_auto_login_finished)
	PlayerAuth.auto_login()

	_play_sequence()


func _play_sequence() -> void:
	# 黑屏等待，然后背景渐变为白色，再展示 logo
	await get_tree().create_timer(BLACK_WAIT).timeout
	var bg_fade := create_tween()
	bg_fade.tween_property(_background, "color", Color.WHITE, BG_FADE)
	await bg_fade.finished

	await _show_logo(_studio_logo)
	await _show_logo(_game_logo)
	_splash_done = true
	_try_finish()
	# 兜底：网络异常时自动登录可能长时间无响应，超时后进登录屏
	if not _auto_login_settled:
		await get_tree().create_timer(AUTO_LOGIN_TIMEOUT).timeout
		if not _auto_login_settled:
			_auto_login_settled = true
			_auto_login_ok = false
			_try_finish()


func _show_logo(logo: TextureRect) -> void:
	var fade_in := create_tween()
	fade_in.tween_property(logo, "modulate:a", 1.0, FADE_IN)
	await fade_in.finished

	await get_tree().create_timer(HOLD).timeout

	var fade_out := create_tween()
	fade_out.tween_property(logo, "modulate:a", 0.0, FADE_OUT)
	await fade_out.finished


func _on_auto_login_finished(success: bool) -> void:
	_auto_login_settled = true
	_auto_login_ok = success
	_try_finish()


func _try_finish() -> void:
	if not (_splash_done and _auto_login_settled):
		return
	var target := "res://Scenes/Loading.tscn" if _auto_login_ok else "res://Scenes/Main.tscn"
	get_tree().change_scene_to_file(target)
