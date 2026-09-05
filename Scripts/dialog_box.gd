extends Control
## 通用对话框组件（实例化到需要对话的界面）。
## transparent_mode = false：面板样式（带背景和继续提示，其他关卡的默认样式）
## transparent_mode = true ：无背景、文字居中（教学关样式）
## advance_on_input = true ：点击屏幕 / 触控 / 空格推进台词；每推进一句发出 line_changed，
##                           播完发出 lines_finished；
## advance_on_input = false：静态展示，只用 play() / set_text() 设置内容。

signal lines_finished
## 推进到第 index 句（从 0 起），供外部同步运镜等表现
signal line_changed(index: int)

@export var transparent_mode := false
@export var advance_on_input := true
@export var hint_text := "点击 / 按空格继续..."

@onready var _panel: PanelContainer = $Panel
@onready var _text: Label = $Panel/Box/Text
@onready var _hint: Label = $Panel/Box/Hint

var _lines: Array = []
var _index := 0
var _playing := false
## 为 true 时忽略一切推进输入（由外部把关节奏，如运镜未完成）
var advance_locked := false


func set_advance_locked(locked: bool) -> void:
	advance_locked = locked


func _ready() -> void:
	_apply_style()
	_hint.text = hint_text


func _apply_style() -> void:
	if transparent_mode:
		_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint.visible = false
	else:
		_panel.remove_theme_stylebox_override("panel")
		_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_hint.visible = true


## 按顺序播放多句台词
func play(lines: Array) -> void:
	_lines = lines
	_index = 0
	_playing = not lines.is_empty()
	visible = true
	_show_current()


## 直接展示单句文本（不推进）
func set_text(text: String) -> void:
	_playing = false
	visible = true
	_fade_in_text(text)


func _show_current() -> void:
	_fade_in_text(str(_lines[_index]))


func _fade_in_text(text: String) -> void:
	_text.text = text
	_text.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_text, "modulate:a", 1.0, 0.35)


func _advance() -> void:
	_index += 1
	if _index >= _lines.size():
		_playing = false
		lines_finished.emit()
		return
	_show_current()
	line_changed.emit(_index)


## 鼠标点击 / 触控推进（根节点铺满全屏，点击任意位置有效）
func _gui_input(event: InputEvent) -> void:
	if advance_locked or not (_playing and advance_on_input and visible):
		return
	if (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed):
		_advance()
		accept_event()


## 键盘推进（空格 / 回车）
func _unhandled_input(event: InputEvent) -> void:
	if advance_locked or not (_playing and advance_on_input and visible):
		return
	if event.is_action_pressed("ui_accept"):
		_advance()
		get_viewport().set_input_as_handled()
