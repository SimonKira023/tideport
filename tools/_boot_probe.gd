# tools/_boot_probe.gd —— --script 探针引导器
#
# ❗为什么需要这个文件：`godot --script x.gd` 的主脚本在 autoload 注册**之前**编译，
#   探针里 `SaveManager.enabled` 这种 autoload 标识符会直接编译失败
#   （「Identifier not found: SaveManager」）。所以由这个不引用任何 autoload 的
#   SceneTree 引导器先进场，等树起来了再把真正的探针挂上去——那时 autoload
#   已经全部就位，运行期加载编译就通了。
#
# 用法：godot --headless --path <项目> --script res://tools/_boot_probe.gd -- probe=tools/_probe_battle_loop.gd
#   （不带 probe= 参数时默认跑 _probe_battle_loop.gd）
extends SceneTree

func _initialize() -> void:
	var target := "res://tools/_probe_battle_loop.gd"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("probe="):
			target = "res://" + String(a).trim_prefix("probe=").trim_prefix("/")
	var scr: GDScript = load(target)
	if scr == null:
		push_error("引导失败：找不到探针脚本 %s" % target)
		quit(1)
		return
	var probe: Node = scr.new()
	probe.name = "Probe"
	root.add_child(probe)
