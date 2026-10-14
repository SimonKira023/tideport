# 旧探针的兼容入口. 正式外观由 slave_npc 的身份资料与原生动作工厂统一提供。
extends RefCounted

const APPEARANCE := preload("res://scene/character_appearance.gd")
const SHEETS := APPEARANCE.SHEETS
const NPC_FILES := APPEARANCE.NPC_FILES

static func texture(key: String, file: String) -> Texture2D:
	# 动态取得外观入口, 避免两个脚本互相 preload。
	var npc: Script = load("res://scene/slave_npc.gd")
	if key == "player":
		return npc.player_texture(file)
	if not npc.profile_for(key).is_empty():
		return npc.named_texture(key, file)
	return null

# 仅供已停用的旧素材生成探针读取, 正式动作不再使用程序化手腕。
static func work_wrist(direction: int, pose: int) -> Vector2i:
	var front: Array[Vector2i] = [Vector2i(17, 18), Vector2i(22, 9), Vector2i(18, 22), Vector2i(17, 18)]
	var side: Array[Vector2i] = [Vector2i(20, 18), Vector2i(22, 9), Vector2i(23, 22), Vector2i(20, 18)]
	return side[pose] if direction == 2 else front[pose]
