extends Node
# F11 全屏/窗口切换: 任何场景都能按。
# 默认全屏在 project.godot 里设（display/window/size/mode=2 无边框全屏）。
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.physical_keycode == KEY_F11:
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode != Window.MODE_WINDOWED else Window.MODE_FULLSCREEN
