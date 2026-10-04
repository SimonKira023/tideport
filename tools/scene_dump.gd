# tools/scene_dump.gd —— 把 game.tscn 真实跑起来后，把「绘制指令」导成 JSON + 贴图，
# 交给 tools/render_preview.py 按节点顺序合成 PNG。
#
# 为什么需要它：Godot 的 headless 模式截不了图，想看画面只能这样「反向出图」。
# 跑法（在项目根目录）：
#   "D:\平台\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" ^
#       --headless --path "<项目根>" res://tools/scene_dump.tscn
#   python tools/render_preview.py outputs/俯视图.png [--crop x y w h] [--scale 0.8]
#
# 注意：Sprite2D 只按整张贴图导出，**不认 hframes / frame**。
# 所以带帧动画的角色（玩家、哥布林商人）在图里会横着摊开成一条，那是导出工具的局限，不是游戏的问题。
extends Node

const OUT_JSON := "res://_preview_dump.json"
const TEX_DIR := "res://_preview_tex"

var _tex_ids := {}
var _tex_seq := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEX_DIR))
	var g: Node = load("res://scene/game.tscn").instantiate()
	add_child(g)
	for i in 5:
		await get_tree().process_frame

	var items: Array = []
	_walk(g, items)
	var f := FileAccess.open(OUT_JSON, FileAccess.WRITE)
	f.store_string(JSON.stringify({"items": items}, "  "))
	f.close()
	print("[dump] 导出 %d 条绘制指令" % items.size())
	get_tree().quit()

func _walk(n: Node, items: Array) -> void:
	# HUD 在屏幕空间（CanvasLayer），坐标跟世界不同一套，跳过
	if n is CanvasLayer:
		return
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is TileMapLayer:
		_dump_tilemap(n, items)
	elif n is Sprite2D:
		_dump_sprite(n, items)
	for c in n.get_children():
		_walk(c, items)

func _dump_tilemap(l: TileMapLayer, items: Array) -> void:
	var ts := l.tile_set
	if ts == null:
		return
	var size := ts.tile_size
	for c in l.get_used_cells():
		var sid := l.get_cell_source_id(c)
		if sid == -1:
			continue
		var src := ts.get_source(sid)
		if not (src is TileSetAtlasSource):
			continue
		var atlas := src as TileSetAtlasSource
		var ac := l.get_cell_atlas_coords(c)
		var region: Vector2i = atlas.texture_region_size
		items.append({
			"kind": "tilemap",
			"tex": _tex_path(atlas.texture),
			"src_rect": [ac.x * region.x, ac.y * region.y, region.x, region.y],
			"pos": [l.global_position.x + c.x * size.x, l.global_position.y + c.y * size.y],
			"scale": [1.0, 1.0],
			"flip_h": false,
			"modulate": [1, 1, 1, 1],
			"node": str(l.get_path()),
		})

func _dump_sprite(s: Sprite2D, items: Array) -> void:
	var tex := s.texture
	if tex == null:
		return
	var sz := tex.get_size()
	var origin := s.global_position
	if s.centered:
		origin -= sz * 0.5
	var sr := [0, 0, sz.x, sz.y]
	if s.region_enabled:
		sr = [s.region_rect.position.x, s.region_rect.position.y,
			s.region_rect.size.x, s.region_rect.size.y]
	items.append({
		"kind": "sprite",
		"tex": _tex_path(tex),
		"src_rect": sr,
		"pos": [origin.x, origin.y],
		"scale": [s.scale.x, s.scale.y],
		"flip_h": s.flip_h,
		"modulate": [s.modulate.r, s.modulate.g, s.modulate.b, s.modulate.a],
		"node": str(s.get_path()),
	})

# 有资源路径的（项目里的 png）直接给路径；运行时生成的贴图（程序化图集）存成 png 再给路径
func _tex_path(tex: Texture2D) -> String:
	if tex.resource_path != "":
		return tex.resource_path
	var id := tex.get_instance_id()
	if _tex_ids.has(id):
		return _tex_ids[id]
	var p := "%s/gen_%02d.png" % [TEX_DIR, _tex_seq]
	_tex_seq += 1
	tex.get_image().save_png(p)
	_tex_ids[id] = p
	return p
