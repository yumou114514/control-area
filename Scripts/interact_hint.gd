extends PanelContainer
## 通用交互提示：悬浮在可交互物上方，显示名称与交互按键。
## 由使用方每帧设置 position（建议水平居中于目标）。

@onready var _label: Label = $Label


func set_text(text: String) -> void:
	_label.text = text
