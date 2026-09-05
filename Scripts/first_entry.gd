extends Control
## 首次进入场景：剧情运镜（分镜表驱动）→ 基本操作教学 → 写库标记并进入主界面。
## 剧情分镜：设计师只需修改 STORY_BOARD 数组，每段 = 相机位置（pos）、可选缩放（zoom）、台词（text）；
## 玩家推进（点击 / 触控 / 空格）时相机运镜到下一段并显示该段台词。
## 交互系统：靠近过某个标记即视为「已发现」，之后离开仍可交互；
## 多个已发现标记时，用鼠标滚轮或 ↑↓ 键切换选中目标，按 F 与选中目标交互。

## 剧情分镜表：pos = 相机位置（必填）；zoom = 缩放倍数（可选，不写则保持当前视野不缩放）；text = 台词
const STORY_BOARD := [
	{"pos": Vector2(0, -60), "zoom": 2.6,
		"text": "很久以前，这片大陆由「控制核心」守护。"},
	{"pos": Vector2(-560, 150), "zoom": 1.7,
		"text": "它维系着万物的秩序，直到某一天，核心失去了光芒。"},
	{"pos": Vector2(480, 110), "zoom": 1.35,
		"text": "秩序崩塌，黑暗开始侵蚀大地的每个角落。"},
	{"pos": Vector2(0, 190), "zoom": 2.2,
		"text": "而你，是最后的控制者。夺回核心的力量，唤醒这个世界。"},
]
## 分镜间相机运镜时长（秒）
const STORY_MOVE_TIME := 1.6
## 教学移动速度（像素/秒）
const PLAYER_SPEED := 280.0
## 交互距离：进入该范围发现标记，按 F 交互也必须在该范围内（滚轮/↑↓ 切换不受限）
const INTERACT_RADIUS := 120.0
## 阶段切换的淡入淡出时长
const FADE_TIME := 0.4

enum Phase { STORY, TUTORIAL, DONE }

@onready var _intro_layer: Node2D = $IntroLayer
@onready var _camera: Camera2D = $IntroLayer/Camera
@onready var _fade_overlay: ColorRect = $FadeLayer/FadeOverlay
@onready var _story_layer: CanvasLayer = $StoryUILayer
@onready var _story_dialog: Control = $StoryUILayer/StoryDialog
@onready var _tutorial_layer: Control = $TutorialLayer
@onready var _tutorial_dialog: Control = $TutorialLayer/TutorialDialog
@onready var _player: Polygon2D = $TutorialLayer/World/Player
@onready var _interact_hint: PanelContainer = $FadeLayer/InteractHint
@onready var _continue_hint: Label = $FadeLayer/ContinueHint

var _phase: Phase = Phase.STORY
var _camera_tween: Tween
var _tutorial_step := 0
var _guide_text := ""
## 可交互物：{node, name, pos, radius, known, primary}
var _interactables: Array = []
var _selected_index := -1


func _ready() -> void:
	if not PlayerAuth.is_logged_in:
		get_tree().change_scene_to_file.call_deferred("res://Scenes/Main.tscn")
		return
	if not PlayerAuth.is_first_entry():
		# 非首次进入（如直接运行本场景），直接进主界面
		get_tree().change_scene_to_file.call_deferred("res://Scenes/Game.tscn")
		return

	_story_dialog.lines_finished.connect(_on_story_finished)
	_story_dialog.line_changed.connect(_on_story_line_changed)
	_setup_tutorial_world()
	_start_story()


# ---------- 剧情阶段（分镜表驱动运镜） ----------

func _start_story() -> void:
	# 开场淡入，相机直接就位于第 1 段分镜
	_fade_overlay.modulate.a = 1.0
	var fade := create_tween()
	fade.tween_property(_fade_overlay, "modulate:a", 0.0, FADE_TIME)
	var beat: Dictionary = STORY_BOARD[0]
	_camera.position = beat.pos
	_camera.zoom = Vector2(beat.zoom, beat.zoom)
	_story_layer.visible = true
	var lines: Array = []
	for item in STORY_BOARD:
		lines.append(item.text)
	_story_dialog.play(lines)
	# 第 1 段相机已就位：短暂停顿后才允许继续，避免开场误触
	_story_dialog.set_advance_locked(true)
	_grant_advance_after(0.3)


## 剧情推进到第 index 段：先锁定推进，相机运镜完成（或无需运镜时等 0.3 秒）再解锁并显示继续提示
func _on_story_line_changed(index: int) -> void:
	_story_dialog.set_advance_locked(true)
	_continue_hint.visible = false
	var beat: Dictionary = STORY_BOARD[index]
	var target_zoom := _camera.zoom
	if beat.has("zoom"):
		target_zoom = Vector2(beat.zoom, beat.zoom)
	var need_move := _camera.position.distance_to(beat.pos) > 1.0 \
		or absf(_camera.zoom.x - target_zoom.x) > 0.01
	if not need_move:
		# 无需运镜：等 0.3 秒再允许玩家继续
		_grant_advance_after(0.3)
		return
	# 旧运镜未完成时推进已被锁定，这里只需重建运镜
	if _camera_tween != null:
		_camera_tween.kill()
	var tween := create_tween()
	_camera_tween = tween
	tween.tween_property(_camera, "position", beat.pos, STORY_MOVE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if beat.has("zoom"):
		tween.parallel().tween_property(_camera, "zoom", target_zoom, STORY_MOVE_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_on_camera_arrived)


## 相机到达分镜位置：解锁推进并显示继续提示
func _on_camera_arrived() -> void:
	if _phase != Phase.STORY:
		return
	_story_dialog.set_advance_locked(false)
	_continue_hint.visible = true


## delay 秒后解锁推进并显示继续提示（用于无需运镜的分镜）
func _grant_advance_after(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if _phase != Phase.STORY:
		return
	_story_dialog.set_advance_locked(false)
	_continue_hint.visible = true


func _on_story_finished() -> void:
	_continue_hint.visible = false
	var fade_in := create_tween()
	fade_in.tween_property(_fade_overlay, "modulate:a", 1.0, FADE_TIME)
	await fade_in.finished
	if _camera_tween != null:
		_camera_tween.kill()
	_intro_layer.visible = false
	_camera.enabled = false
	_story_layer.visible = false
	_tutorial_layer.visible = true
	_phase = Phase.TUTORIAL
	_set_guide("第 1 步：使用 WASD 移动，靠近场上的发光标记")
	var fade_out := create_tween()
	fade_out.tween_property(_fade_overlay, "modulate:a", 0.0, FADE_TIME)


# ---------- 教学阶段 ----------

func _set_guide(text: String) -> void:
	_guide_text = text
	_tutorial_dialog.set_text(text)


func _setup_tutorial_world() -> void:
	var center := get_viewport_rect().size / 2.0
	_player.position = center + Vector2(-260.0, 120.0)
	var target_a: Polygon2D = $TutorialLayer/World/TargetA
	var target_b: Polygon2D = $TutorialLayer/World/TargetB
	_interactables = [
		{"node": target_a, "name": "控制核心光点", "pos": center + Vector2(250.0, -70.0), "known": false, "was_in": false, "primary": true},
		{"node": target_b, "name": "微弱的紫色光点", "pos": center + Vector2(70.0, 175.0), "known": false, "was_in": false, "primary": false},
	]
	for item in _interactables:
		item.node.position = item.pos
		# 标记呼吸动效
		var tween := create_tween().set_loops()
		tween.tween_property(item.node, "scale", Vector2(1.12, 1.12), 0.6).set_trans(Tween.TRANS_SINE)
		tween.tween_property(item.node, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)


func _physics_process(delta: float) -> void:
	if _phase != Phase.TUTORIAL:
		return

	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if dir != Vector2.ZERO:
		_player.position += dir.normalized() * PLAYER_SPEED * delta
		var rect := get_viewport_rect()
		_player.position = _player.position.clamp(Vector2(28, 28), rect.size - Vector2(28, 28))

	# 发现标记：进入交互距离即永久可交互（离开后依然有效）；
	# 「进入范围」的瞬间自动选中该标记（包括重新走近已发现的标记），
	# 在范围内走动不覆盖手动切换，避免滚轮/↑↓ 切不动的问题
	var primary_known := false
	for i in range(_interactables.size()):
		var item: Dictionary = _interactables[i]
		var in_reach := _player.position.distance_to(item.pos) <= INTERACT_RADIUS
		if not item.known and in_reach:
			item.known = true
		if in_reach and not item.was_in:
			_selected_index = i
			_refresh_selection()
		item.was_in = in_reach
		primary_known = primary_known or item.known
	if _tutorial_step == 0 and primary_known:
		_tutorial_step = 1
		_set_guide("第 2 步：靠近后按 F 与选中的标记交互；有多个目标时用滚轮或 ↑↓ 切换")


## 玩家当前是否处在选中目标的交互距离内（超出则按 F 无效）
func _selected_in_reach() -> bool:
	if _selected_index < 0:
		return false
	var item: Dictionary = _interactables[_selected_index]
	return _player.position.distance_to(item.pos) <= INTERACT_RADIUS


## 每帧刷新交互提示：固定在屏幕底部居中的 UI 位置，不跟随物体移动；
## 只有选中目标在交互距离内才显示，文案随距离变化提示玩家靠近。
func _process(_delta: float) -> void:
	if _phase != Phase.TUTORIAL or _selected_index < 0 or not _selected_in_reach():
		_interact_hint.visible = false
		return
	var item: Dictionary = _interactables[_selected_index]
	_interact_hint.visible = true
	_interact_hint.set_text("%s · 按 F 交互" % item.name)
	var hint_size := _interact_hint.get_combined_minimum_size()
	var screen := get_viewport_rect().size
	_interact_hint.position = Vector2(
		(screen.x - hint_size.x) / 2.0, screen.y - hint_size.y - 48.0)


func _refresh_selection() -> void:
	for i in range(_interactables.size()):
		var item: Dictionary = _interactables[i]
		item.node.self_modulate = Color(1.45, 1.45, 1.45) if i == _selected_index else Color(1, 1, 1)


## 在已发现的标记间切换选中（滚轮 / 上下键）
func _cycle_selection(step: int) -> void:
	var known_index: Array = []
	for i in range(_interactables.size()):
		if _interactables[i].known:
			known_index.append(i)
	if known_index.size() < 2:
		return
	var cur := known_index.find(_selected_index)
	_selected_index = known_index[wrapi(cur + step, 0, known_index.size() - 1)]
	_refresh_selection()


func _interact_selected() -> void:
	if _phase != Phase.TUTORIAL or _selected_index < 0:
		return
	if not _selected_in_reach():
		# 超出交互距离：无法交互，提示玩家靠近（不消耗选中状态）
		var target: Dictionary = _interactables[_selected_index]
		_tutorial_dialog.set_text("离「%s」太远了，走近一点再按 F。" % target.name)
		await get_tree().create_timer(2.0).timeout
		if _phase == Phase.TUTORIAL:
			_tutorial_dialog.set_text(_guide_text)
		return
	var item: Dictionary = _interactables[_selected_index]
	if item.primary:
		_finish_tutorial()
		return
	# 非目标标记：给一句反馈，稍后恢复引导文本
	_tutorial_dialog.set_text("微弱的紫光轻轻晃动…但它不是我们要找的核心。")
	await get_tree().create_timer(2.5).timeout
	if _phase == Phase.TUTORIAL:
		_tutorial_dialog.set_text(_guide_text)


func _finish_tutorial() -> void:
	_phase = Phase.DONE
	_interact_hint.visible = false
	_tutorial_dialog.set_text("教学完成！正在进入游戏…")
	_complete_and_enter()


func _complete_and_enter() -> void:
	# 等待写库完成再切场景，确保标记不丢
	await PlayerAuth.complete_first_entry()
	get_tree().change_scene_to_file("res://Scenes/Game.tscn")


# ---------- 输入 ----------

func _unhandled_input(event: InputEvent) -> void:
	if _phase != Phase.TUTORIAL:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_selection(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_selection(1)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_UP:
			_cycle_selection(-1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DOWN:
			_cycle_selection(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F:
			_interact_selected()
			get_viewport().set_input_as_handled()
