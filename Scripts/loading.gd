extends Control
## 登录成功后的加载界面：进度条 + 当前状态，期间下载版本信息并比对。
## 当前版本 < minversion：弹窗强制更新，不能进入游戏；
## minversion <= 当前版本 < latestversion：弹窗提醒有新版，不强制，可跳过继续进入；
## 加载完成后进入主界面。

## 版本信息下载超时（秒）
const VERSION_TIMEOUT := 8.0

@onready var _progress: ProgressBar = $Center/VBox/Progress
@onready var _status_label: Label = $Center/VBox/StatusLabel


func _ready() -> void:
	_progress.value = 0.0
	_run()


func _run() -> void:
	_set_status("正在初始化…", 5.0)
	await get_tree().create_timer(0.3).timeout

	_set_status("正在检查版本更新…", 25.0)
	var info := await _fetch_version_info()
	if info.is_empty():
		_set_status("无法获取版本信息，跳过检查", 55.0)
		await get_tree().create_timer(0.5).timeout
	else:
		var latest := str(info.get("latestversion", ""))
		var minv := str(info.get("minversion", ""))
		# 低于最低版本：强制更新，不能进入
		if not minv.is_empty() and GameVersion.compare(GameVersion.CURRENT_VERSION, minv) < 0:
			_set_status("当前版本过低，无法进入游戏", 55.0)
			await _show_force_update_dialog(minv, latest)
			return
		# 有新版本但不强制：提醒一次，可跳过
		if not latest.is_empty() and GameVersion.compare(GameVersion.CURRENT_VERSION, latest) < 0:
			_set_status("发现新版本 %s" % latest, 55.0)
			await _show_new_version_dialog(latest)
		else:
			_set_status("版本检查完成", 55.0)
			await get_tree().create_timer(0.3).timeout

	_set_status("正在加载游戏资源…", 75.0)
	await get_tree().create_timer(0.8).timeout

	_set_status("加载完成，正在进入…", 100.0)
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://Scenes/Game.tscn")


## 更新状态文字并平滑推进进度条
func _set_status(text: String, value: float) -> void:
	_status_label.text = text
	var tween := create_tween()
	tween.tween_property(_progress, "value", value, 0.3)


## 下载版本信息。成功返回解析后的 Dictionary，失败返回 {}
func _fetch_version_info() -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = VERSION_TIMEOUT
	var err := http.request(GameVersion.VERSION_URL)
	if err != OK:
		http.queue_free()
		print("[Loading] 版本信息请求失败：%s" % error_string(err))
		return {}

	var result: Array = await http.request_completed
	http.queue_free()
	var status: int = result[1]
	var body: PackedByteArray = result[3]
	if status != 200:
		print("[Loading] 版本信息 HTTP %d" % status)
		return {}
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		print("[Loading] 版本信息 JSON 解析失败")
		return {}
	return parsed


## 版本过低：弹窗强制更新，关闭后退出游戏
func _show_force_update_dialog(minv: String, latest: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "需要更新版本"
	dialog.dialog_text = "当前版本 %s 低于最低支持版本 %s，必须更新后才能进入游戏。\n最新版本：%s" % [
		GameVersion.CURRENT_VERSION, minv, latest if not latest.is_empty() else minv
	]
	dialog.ok_button_text = "退出游戏"
	dialog.add_button("前往更新", true)
	add_child(dialog)

	var go_update := false
	dialog.custom_action.connect(func(_button): go_update = true)
	dialog.popup_centered()
	await dialog.hidden

	if go_update:
		OS.shell_open(GameVersion.UPDATE_URL)
	get_tree().quit()


## 有新版本但不强制：提醒弹窗，跳过则继续加载
func _show_new_version_dialog(latest: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "发现新版本"
	dialog.dialog_text = "发现新版本 %s（当前 %s），建议更新。" % [
		latest, GameVersion.CURRENT_VERSION
	]
	dialog.ok_button_text = "跳过"
	dialog.add_button("立即更新", true)
	add_child(dialog)

	var go_update := false
	dialog.custom_action.connect(func(_button): go_update = true)
	dialog.popup_centered()
	await dialog.hidden

	if go_update:
		OS.shell_open(GameVersion.UPDATE_URL)
