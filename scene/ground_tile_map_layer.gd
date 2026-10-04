# ground_tile_map_layer.gd —— 挂在 TilledGroundTileMapLayer 上
#
# 这一层的作用只有一个：把你在编辑器里「手画」出来的农场原有耕地保存成数据。
# 它的内容在开场会被 game.gd 取走：
#   1) 每一格变成 Farm.tilled 里的真实耕地（能直接播种、浇水、收获）；
#   2) 显示交给 soil_layer.gd 用 16 格自动拼接重画一遍 ——
#      连成整片、边缘和拐角都有对应的瓦块变化；
#   3) 自己 clear() 并隐藏，避免"手画的平铺土块"和"自动拼接的土块"叠在一起。
extends TileMapLayer

# 取走手绘耕地的格子列表，并把自己清空隐藏
func take_authored_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for c in get_used_cells():
		cells.append(c)
	clear()
	visible = false
	return cells
