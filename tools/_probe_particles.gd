# tools/_probe_particles.gd —— 粒子溯源探针（只印事实 + 截图，不下结论）
#
# 用户反馈「删掉萤火虫层之后还有粒子在掉」。这个探针：
#   1) 列出全场所有 CPUParticles2D 的 emitting/amount/可见性/颜色 —— 谁在喷粒子一目了然
#   2) 中午晴天连拍三张（间隔 0.5 秒），截图里找「在动的小点」
extends Node

var game: Node = null

func _ready() -> void:
	SaveManager.enabled = false          # 别碰真档
	TimeManager.hour = 12
	TimeManager.time_running = true
	game = load("res://scene/game.tscn").instantiate()
	add_child(game)
	for i in 12:
		await get_tree().process_frame

	print("========== 粒子发射器清单 ==========")
	_list_emitters(game, "")

	print("\n========== 连拍三张（间隔 0.5s） ==========")
	for i in 3:
		await _snap("particles_t%d" % i)
		var t := 0.0
		while t < 0.5:
			await get_tree().process_frame
			t += get_process_delta_time()

	print("\n========== 拍完后再次列出（看状态变化） ==========")
	_list_emitters(game, "")
	get_tree().quit()

func _list_emitters(root: Node, indent: String) -> void:
	for n in root.get_children():
		if n is CPUParticles2D:
			var p: CPUParticles2D = n
			print("%s%s [emitting=%s amount=%d visible=%s color=%s local=%s z=%d]"
				% [indent, p.name, str(p.emitting), p.amount, str(p.visible),
					str(p.color), str(p.local_coords), p.z_index])
		_list_emitters(n, indent + "  ")

func _snap(tag: String) -> void:
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var shot := tex.get_image()
	var out := "res://outputs/probe_%s.png" % tag
	shot.save_png(ProjectSettings.globalize_path(out))
	print("[probe] saved ", out)
