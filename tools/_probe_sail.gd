extends Node
# tools/_probe_sail.gd —— 出海动画实拍探针: _depart 全链路跑一遍, 动画中途连拍。
# 跑法（要出图别加 --headless）:
#   & $exe --path . --log-file probe_sail.log res://tools/_probe_sail.tscn
# 出 outputs/probe_sail_0.png(上船) / 1(驶离) / 2(远去), 并打印 crew 精灵清单。

func _ready() -> void:
	await get_tree().process_frame
	SaveManager.enabled = false
	var game_scene: PackedScene = load("res://scene/game.tscn")
	var g: Node = game_scene.instantiate()
	add_child(g)
	await get_tree().create_timer(1.0).timeout
	# 码头建成 + 两条船 + 白天, 直接触发 _depart
	Voyage.dock_state = Voyage.DOCK_BUILT
	Voyage.boat_count = 2
	Voyage.dock_changed.emit()
	TimeManager.hour = 10
	Slaves.expedition = [0, 1]        # 带两个伙伴, 船上三个人物该都看得见
	print("[probe] depart_block = '", Voyage.depart_block_reason(g), "'")
	g.call("_depart")
	# 动画约 3 秒, 分三拍连拍
	await get_tree().create_timer(0.8).timeout
	await _report(g, 0)
	await get_tree().create_timer(0.9).timeout
	await _report(g, 1)
	await get_tree().create_timer(1.2).timeout
	await _report(g, 2)
	print("[probe] traveling = ", Voyage.traveling)
	get_tree().quit()

func _report(g: Node, tag: int) -> void:
	var fleet: Node2D = g.get_node_or_null("SailFleet")
	var dock: Node2D = g.get("dock")
	var cam: Camera2D = g.get_node_or_null("Player/Camera2D")
	if dock != null:
		print("[probe] dock global=", dock.global_position, " boats_node=", dock.get("_boats"))
	if cam != null:
		print("[probe] cam global=", cam.global_position, " zoom=", cam.zoom)
	if fleet == null:
		print("[probe] ", tag, ": SailFleet 不在了")
		return
	var boats := 0
	var crews := 0
	var info := []
	for b in fleet.get_children():
		if b is Sprite2D:
			boats += 1
			info.append("boat global=%s tex=%s size=%s vis=%s" % [
				(b as Sprite2D).global_position,
				(b as Sprite2D).texture.resource_path.get_file(),
				(b as Sprite2D).texture.get_size(), (b as Sprite2D).visible])
			for c in (b as Sprite2D).get_children():
				if c is Sprite2D:
					crews += 1
					var at: AtlasTexture = (c as Sprite2D).texture
					info.append("  crew global=%s vis=%s" % [
						(c as Sprite2D).global_position, (c as Sprite2D).visible])
	print("[probe] shot ", tag, ": boats=", boats, " crews=", crews)
	for s in info:
		print("[probe]   ", s)
	RenderingServer.force_draw(false)
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex != null:
		var shot := tex.get_image()
		shot.save_png(ProjectSettings.globalize_path("res://outputs/probe_sail_%d.png" % tag))
		print("[probe] saved probe_sail_%d.png" % tag)
