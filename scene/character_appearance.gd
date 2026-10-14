# 成熟素材图层外观工厂. 按作者的逐帧姿态搭配衣服与发型, 不合成肢体动作。
# 第三方素材只经 SoftRes 读取, 只缓存内存纹理, 不复制原图或派生图进仓库。
extends RefCounted

const ROOT := "res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Character/Character/PNG/"
const INK := Color("34262f")
const SHEETS := {
	"Idle.png": [4, "idle"], "Walk.png": [6, "walk"], "Run.png": [8, "run"],
	"Hoe.png": [6, "hoe"], "Axe.png": [6, "axe"], "Pickaxe.png": [6, "pickaxe"],
	"Shovel.png": [5, "shovel"], "Sickle.png": [6, "sickle"], "Watering.png": [8, "water"],
	"Sword.png": [10, "sword"], "Bow and Arrow.png": [7, "bow"],
	"Damage.png": [4, "hurt"], "Dead.png": [4, "dead"], "Sleep.png": [2, "sleep"],
	"Fishing/Wait Idle.png": [4, "fish"], "Fishing/Hooked.png": [8, "hooked"],
	"Fishing/Casting.png": [15, "cast"], "Fishing/Captured Fish.png": [4, "capture"],
	"Fishing/Captured No Fish.png": [4, "capture_empty"],
	"Swim/Swim.png": [4, "swim"], "Swim/submerged.png": [4, "submerged"],
	"Swim/Coming out of the water.png": [3, "emerge"],
}
const NPC_FILES := ["Idle.png", "Walk.png", "Hoe.png", "Axe.png", "Pickaxe.png", "Shovel.png", "Sickle.png", "Watering.png", "Sword.png", "Bow and Arrow.png", "Damage.png", "Dead.png"]
# 文件夹、原生帧数、工具层. 钓竿本身是 64px, 人物仍是 32px。
const SOURCES := {
	"Idle.png": ["1. Idle", 4, ""], "Walk.png": ["2. Walk", 6, ""], "Run.png": ["3. Run", 8, ""],
	"Hoe.png": ["4. Pickaxe, Hoe and Catching insects", 6, "Weapons/Hoe/1.png"],
	"Pickaxe.png": ["4. Pickaxe, Hoe and Catching insects", 6, "Weapons/Pickaxe/1.png"],
	"Axe.png": ["5. Axe and Sickle", 6, "Weapons/Axe/1.png"],
	"Sickle.png": ["5. Axe and Sickle", 6, "Weapons/Sickle/1.png"],
	"Shovel.png": ["6. Shovel", 5, "Weapons/Shovel/1.png"],
	"Watering.png": ["7. Watering", 8, "Weapons/Watering/1.png"],
	"Sword.png": ["8. SwordAttack", 10, "Weapons/Sword/1.png"],
	"Bow and Arrow.png": ["9. Archer", 7, "Weapons/Bow and Arrow/1.png"],
	"Damage.png": ["10. Damage", 4, ""], "Dead.png": ["11. Death", 4, ""],
	"Sleep.png": ["19. Sleep", 2, ""],
	"Fishing/Casting.png": ["12. Fishing - Cast", 15, "Weapons/1.png"],
	"Fishing/Wait Idle.png": ["12.1. Fishing - Wait", 4, "Weapons/1.png"],
	"Fishing/Hooked.png": ["12.2. Fishing - Bite", 8, "Weapons/1.png"],
	"Fishing/Captured No Fish.png": ["12.3. Fishing - Reel", 4, "Weapons/1.png"],
	"Fishing/Captured Fish.png": ["12.4. Fishing - Catch", 4, "Weapons/1.png"],
	"Swim/Swim.png": ["24.3 Swim - Swim", 4, ""],
	"Swim/submerged.png": ["24.2 Swim - Submerged", 3, ""],
	"Swim/Coming out of the water.png": ["24.1 Swim - Outwater", 3, ""],
	"Horse/Run.png": ["14.2 Horse - Run", 6, ""],
}
static var _textures: Dictionary = {}
static var _layers: Dictionary = {}

static func merchant_texture() -> Texture2D:
	if _textures.has("goblin|stall"):
		return _textures["goblin|stall"]
	var original: Texture2D = SoftRes.tex("res://resources/Farm RPG - Tiny Asset Pack - (All in One)/Enemy/Goblins/Goblin merchant/1.png")
	if original == null:
		return null
	var image: Image = original.get_image().duplicate()
	image.convert(Image.FORMAT_RGBA8)
	_recolor(image, {"32131e": "44313a", "1c0a18": "34262f", "8a3625": "80503c", "ae4924": "a8744d", "c46120": "b78a58", "388129": "617e49", "5d9d29": "8fa861", "4ca32b": "779652", "7ec433": "b6c97e", "2c8d20": "6f8e45", "286ed0": "75678f", "1a3473": "4b4867"})
	var result := ImageTexture.create_from_image(image)
	_textures["goblin|stall"] = result
	return result

static func texture(profile: Dictionary, file: String, npc: bool = false) -> Texture2D:
	if not SHEETS.has(file) or (npc and file not in NPC_FILES):
		return null
	var tag: String = String(profile.get("key", "player")) + "|" + file
	if _textures.has(tag):
		return _textures[tag]
	var frames: int = SHEETS[file][0]
	var cell: int = 64 if file.begins_with("Fishing/") else 32
	var rows: int = 1 if file == "Sleep.png" else 3
	var sheet := Image.create(frames * cell, rows * cell, false, Image.FORMAT_RGBA8)
	for direction in rows:
		for frame in frames:
			var image: Image = frame_image(profile, file, direction, frame)
			if image == null:
				return null
			sheet.blit_rect(image, Rect2i(0, 0, cell, cell), Vector2i(frame * cell, direction * cell))
	var result := ImageTexture.create_from_image(sheet)
	_textures[tag] = result
	return result

static func _layer(folder: String, path: String, frames: int, direction: int, frame: int, cell: int = 32, directions: int = 4, height: int = 0) -> Image:
	var cell_height: int = cell if height == 0 else height
	var resource: String = ROOT + folder + "/" + path
	if not _layers.has(resource):
		var texture: Texture2D = SoftRes.tex(resource)
		if texture == null or texture.get_size() != Vector2(frames * directions * cell, cell_height):
			return null
		var decoded: Image = texture.get_image()
		decoded.convert(Image.FORMAT_RGBA8)
		_layers[resource] = decoded
	var strip: Image = _layers[resource]
	return strip.get_region(Rect2i((direction * frames + frame) * cell, 0, cell, cell_height))

static func mounted_texture(profile: Dictionary) -> Texture2D:
	var key: String = String(profile["key"]) + "|Horse/Run.png"
	if _textures.has(key):
		return _textures[key]
	var sheet := Image.create(192, 144, false, Image.FORMAT_RGBA8)
	for direction in 3:
		for frame in 6:
			var image: Image = frame_image(profile, "Horse/Run.png", direction, frame)
			if image == null:
				return null
			sheet.blit_rect(image, Rect2i(0, 0, 32, 48), Vector2i(frame * 32, direction * 48))
	var result := ImageTexture.create_from_image(sheet)
	_textures[key] = result
	return result

static func _recolor(image: Image, palette: Dictionary) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var color: Color = image.get_pixel(x, y)
			if color.a > 0.5 and palette.has(color.to_html(false)):
				image.set_pixel(x, y, Color(String(palette[color.to_html(false)])))

# 同一原生发型可按身份配出五档色阶, 保留作者的像素团与明暗层次。
static func _hair_palette(profile: Dictionary) -> Dictionary:
	if profile.has("hair_palette"):
		return profile["hair_palette"]
	var base := Color(String(profile.get("hair", "805039")))
	return {"32131e": base.lerp(INK, 0.65).to_html(false), "8a3625": base.darkened(0.20).to_html(false), "ae4924": base.to_html(false), "c46120": base.lerp(Color("d6bfa0"), 0.24).to_html(false), "d9884c": base.lerp(Color("eee2c9"), 0.42).to_html(false)}

static func frame_image(profile: Dictionary, file: String, direction: int, frame: int) -> Image:
	if not SOURCES.has(file):
		return null
	var source: Array = SOURCES[file]
	var folder: String = source[0]
	var source_frames: int = source[1]
	var source_frame: int = mini(frame, source_frames - 1)
	var asleep: bool = file == "Sleep.png"
	var mounted: bool = file == "Horse/Run.png"
	var fx: bool = file in ["Swim/submerged.png", "Swim/Coming out of the water.png"]
	var swimming: bool = file == "Swim/Swim.png"
	var dirs: int = 3 if asleep else 4
	var body: Image = _layer(folder, "Skins/1.png", source_frames, direction, source_frame, 32, dirs)
	if body == null:
		return null
	var raw_body: Image = body.duplicate()
	var eyes: Image = null if fx else _layer(folder, "Eyes/%s/Green.png" % profile.get("eye_style", "Male"), source_frames, direction, source_frame, 32, dirs)
	var hair: Image = null if file == "Swim/submerged.png" else _layer(folder, ("Hair/%s/Brown.png" if mounted else "Hair's/%s/Brown.png") % profile.get("hair_style", "Sebastian"), source_frames, direction, source_frame, 32, dirs)
	var clothes: Image = null if asleep or swimming or fx else _layer(folder, "Clothers/Farm/Blue.png", source_frames, direction, source_frame)
	if (not fx and (eyes == null or hair == null)) or (not asleep and not swimming and not fx and clothes == null):
		return null
	var eye_rect := Rect2i() if eyes == null else eyes.get_used_rect()
	var hair_top: int = 6 if hair == null else hair.get_used_rect().position.y
	var bob: int = clampi(eye_rect.position.y - 12 if eye_rect.has_area() else hair_top - 6, -2, 5)
	var skin_palette := {"1c0a18": "34262f", "f9e6cf": "f1d5b0", "fcba92": "dca684"}
	_recolor(body, skin_palette)
	if hair != null:
		_recolor(hair, _hair_palette(profile))
	if eyes != null:
		var face_style: Dictionary = profile.get("face_style", {})
		_recolor(eyes, {"000000": face_style.get("eye_ink", "34262f"), "115536": profile.get("eye_dark", "315f59"), "7ec433": profile.get("eye_light", "549184"), "8a9db8": face_style.get("nose", "bbc7c1"), "ffffff": "f6efdf"})
	if String(profile.get("key", "player")) == "player" and direction == 0 and not asleep and not fx:
		for y in [12 + bob, 13 + bob]:
			if y >= 0 and y < 32:
				hair.set_pixel(16, y, Color.TRANSPARENT)
	var fallen: bool = file == "Dead.png" and frame == source_frames - 1
	if not fx and not asleep:
		_paint_costume(body, clothes, profile, direction, bob, fallen, swimming, eye_rect, mounted)
		if profile.has("outfit") and not fallen and not swimming:
			_tailor(body, clothes, profile, direction, bob)
	# 肤色只影响仍然裸露的皮肤, 不把衣服、眼白或头发整体染色。
	_recolor(body, {"f1d5b0": profile.get("skin_light", "f1d5b0"), "dca684": profile.get("skin_shadow", "dca684")})
	if profile.has("face_style") and eye_rect.has_area() and not fallen and not fx:
		_soft_face(body, eyes, eye_rect, profile)
	# 长度只加在脸部以下, 头发和眼睛始终逐像素平移, 不拉伸发尾或五官。
	var grow: bool = not asleep and not fx and not swimming and not fallen and not mounted
	var row_map: PackedInt32Array = _row_map(eye_rect, grow)
	var result_body: Image = _grow(body, row_map) if grow else body
	var head_offset := Vector2i(0, -4) if grow else Vector2i.ZERO
	if eyes != null:
		result_body.blend_rect(eyes, Rect2i(0, 0, 32, 32), head_offset)
	if hair != null:
		result_body.blend_rect(hair, Rect2i(0, 0, 32, 32), head_offset)
	if profile.get("glasses", false) and eye_rect.has_area() and not fallen:
		# 眼镜只补外侧镜架和鼻梁, 不涂掉眼白与虹膜。
		var bridge := Vector2i(eye_rect.get_center().x, eye_rect.position.y) + head_offset
		for point: Vector2i in [bridge, Vector2i(eye_rect.position.x - 1, eye_rect.position.y + 1) + head_offset, Vector2i(eye_rect.end.x, eye_rect.position.y + 1) + head_offset]:
			if point.x >= 0 and point.x < 32 and point.y >= 0 and point.y < 32 and result_body.get_pixelv(point).a > 0.5:
				result_body.set_pixelv(point, Color("a38d71"))
	if profile.get("beard", false):
		var beard: Image = _layer(folder, "Acc/Beard/Brown.png", source_frames, direction, source_frame)
		if beard != null:
			_recolor(beard, _hair_palette(profile))
			result_body.blend_rect(beard, Rect2i(0, 0, 32, 32), head_offset)
	if profile.has("headwear"):
		var hat_path: String = "Acc/%s.png" % String(profile["headwear"])
		var hat: Image
		if ResourceLoader.exists(ROOT + folder + "/" + hat_path):
			hat = _layer(folder, hat_path, source_frames, direction, source_frame)
		else:
			# 包内浇水/骑马缺贝雷帽层, 复用原作者待机帽, 按头部轮廓平移, 不缩放。
			var idle_hat: Image = _layer("1. Idle", hat_path, 4, direction, 0)
			var idle_hair: Image = _layer("1. Idle", "Hair's/%s/Brown.png" % String(profile["hair_style"]), 4, direction, 0)
			if idle_hat != null and idle_hair != null:
				hat = Image.create(32, 32, false, Image.FORMAT_RGBA8)
				var shift := Vector2i(hair.get_used_rect().get_center().x - idle_hair.get_used_rect().get_center().x, hair_top - idle_hair.get_used_rect().position.y)
				hat.blit_rect(idle_hat, Rect2i(0, 0, 32, 32), shift)
		if hat == null:
			return null
		var hat_color := Color(String(profile.get("headwear_color", "eee2c9")))
		for y in 32:
			for x in 32:
				var pixel: Color = hat.get_pixel(x, y)
				if pixel.a > 0.5:
					hat.set_pixel(x, y, hat_color.darkened(0.28) if pixel.v < 0.30 else (hat_color.darkened(0.12) if pixel.v < 0.55 else hat_color))
		result_body.blend_rect(hat, Rect2i(0, 0, 32, 32), head_offset)
	if profile.has("crown") and not fallen:
		var crown_y: int = maxi(1, hair_top + head_offset.y + 2)
		var gold := Color(String(profile["crown"]))
		for x in range(13, 20):
			if result_body.get_pixel(x, crown_y).a > 0.5:
				result_body.set_pixel(x, crown_y, gold)
		for x in [13, 16, 19]:
			if result_body.get_pixel(x, crown_y - 1).a > 0.5:
				result_body.set_pixel(x, crown_y - 1, gold.lightened(0.15))
	if profile.has("ribbon") and not fallen:
		var ribbon_point := Vector2i(20 if direction == 0 else 12, hair_top + 5) + head_offset
		if result_body.get_pixelv(ribbon_point).a > 0.5:
			result_body.set_pixelv(ribbon_point, Color(String(profile["ribbon"])))
	if profile.has("clip") and not fx:
		var clip: Vector2i = Vector2i(19 if direction == 0 else 13, hair_top + 4) + head_offset
		if clip.y >= 0 and clip.y + 1 < 32:
			result_body.set_pixelv(clip, Color(String(profile["clip"])))
			result_body.set_pixelv(clip + Vector2i.DOWN, Color(String(profile["clip"])))
	var cell: int = 64 if file.begins_with("Fishing/") else 32
	var result := Image.create(cell, 48 if mounted else cell, false, Image.FORMAT_RGBA8)
	if mounted:
		var horse: Image = _layer(folder, "Horse/1.png", source_frames, direction, source_frame, 32, 4, 48)
		var saddle: Image = _layer(folder, "Horse/Saddle/Brown.png", source_frames, direction, source_frame, 32, 4, 48)
		if horse == null or saddle == null:
			return null
		result.blend_rect(horse, Rect2i(0, 0, 32, 48), Vector2i(0, 7))
		result.blend_rect(saddle, Rect2i(0, 0, 32, 48), Vector2i(0, 7))
	var offset := Vector2i(0, 7) if mounted else Vector2i((cell - 32) / 2, (cell - 32) / 2)
	result.blend_rect(result_body, Rect2i(0, 0, 32, 32), offset)
	var weapon_path: String = source[2]
	if weapon_path != "":
		var tool: Image = _layer(folder, weapon_path, source_frames, direction, source_frame, cell)
		if tool == null:
			return null
		var dy: int = _grip_shift(raw_body, clothes, hair, eye_rect, tool, offset, row_map) if grow else 0
		result.blend_rect(tool, Rect2i(0, 0, cell, cell), Vector2i(0, dy))
		if file == "Fishing/Captured Fish.png":
			var fish: Image = _layer(folder, "Weapons/Fish FX.png", source_frames, direction, source_frame, cell)
			if fish != null:
				result.blend_rect(fish, Rect2i(0, 0, cell, cell), Vector2i(0, dy))
	return result

# 面部修饰按原作眼睛的当帧落点定位, 不抹轮廓、不改虹膜、不放大头部。
# 后续仍由原作头发遮挡脸颊; 背面、倒地与水面特效不补假脸。
static func _soft_face(body: Image, eyes: Image, bounds: Rect2i, profile: Dictionary) -> void:
	var style: Dictionary = profile["face_style"]
	var skin := Color(String(profile.get("skin_light", "f1d5b0")))
	var shade := Color(String(profile.get("skin_shadow", "dca684")))
	var soft := Color(String(style["shadow"]))
	var face: Rect2i = Rect2i(bounds.position.x - 2, bounds.position.y - 1, bounds.size.x + 4, bounds.size.y + 3).intersection(Rect2i(0, 0, 32, 32))
	for y in range(face.position.y, face.end.y):
		for x in range(face.position.x, face.end.x):
			if body.get_pixel(x, y) == shade:
				body.set_pixel(x, y, soft)
	# 只在眼睛下方裸露的皮肤放两粒腮红, 不涂到瞳孔或轮廓线上。
	var left: int = 32
	var right: int = -1
	var bottom: int = -1
	var iris: Array[String] = [String(profile.get("eye_dark", "")), String(profile.get("eye_light", ""))]
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			if eyes.get_pixel(x, y).a > 0.5 and eyes.get_pixel(x, y).to_html(false) in iris:
				left = mini(left, x)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	if right < 0:
		return
	for point: Vector2i in [Vector2i(left - 1, bottom + 1), Vector2i(right + 1, bottom + 1)]:
		if point.x < 0 or point.x >= 32 or point.y < 0 or point.y >= 32:
			continue
		if body.get_pixelv(point) in [skin, shade, soft]:
			body.set_pixelv(point, Color(String(style["blush"])))
	var mouth := Vector2i((left + right) / 2, bottom + 2)
	if mouth.y < 32 and body.get_pixelv(mouth) == INK:
		body.set_pixelv(mouth, Color(String(style["lip"])))

static func _paint_costume(body: Image, clothes: Image, profile: Dictionary, direction: int, bob: int, fallen: bool, swimming: bool, eyes: Rect2i, protect_face: bool = false) -> void:
	var shirt: String = profile.get("shirt", "eee2c9")
	var shade: String = profile.get("shirt_shadow", "d7c3a4")
	if shade == shirt:
		shade = Color(shirt).darkened(0.18).to_html(false)
	var pants: String = profile.get("pants", "66504b")
	if fallen:
		# 倒地时按原服装层的位置换色, 不按站姿的高度给脸或手涂衣服。
		if clothes != null:
			var bounds: Rect2i = clothes.get_used_rect()
			for y in 32:
				for x in 32:
					if clothes.get_pixel(x, y).a > 0.5:
						body.set_pixel(x, y, Color(shirt if x >= bounds.get_center().x else pants))
		return
	var start_y: int = 17 + bob
	if swimming:
		start_y = maxi(start_y, eyes.end.y + 3)
	for y in range(clampi(start_y, 0, 32), 25 if not swimming else 32):
		for x in 32:
			var skin: Color = body.get_pixel(x, y)
			if skin.to_html(false) not in ["f1d5b0", "dca684"] or skin.a < 0.5:
				continue
			# 原生骑乘侧脸比站姿低, 衣服按真实五官区域避让, 不把下巴涂成裤子色。
			if protect_face and _face_area(eyes).has_point(Vector2i(x, y)):
				continue
			var on_clothes: bool = clothes != null and clothes.get_pixel(x, y).a > 0.5
			if y >= 22 and not swimming:
				body.set_pixel(x, y, Color(pants if y < 24 else "92705a"))
			elif on_clothes or y <= 19 + bob or swimming:
				body.set_pixel(x, y, Color(shade if skin == Color("dca684") else shirt))
	if swimming:
		return
	var torso_shift: int = 0 if clothes == null or not clothes.get_used_rect().has_area() else clothes.get_used_rect().get_center().x - 16
	if String(profile.get("key", "player")) == "player":
		var straps: Array[int] = [14 + torso_shift, 18 + torso_shift]
		if direction == 2:
			straps = [15]
		for y in range(maxi(0, 17 + bob), 22):
			for x in straps:
				if x >= 0 and x < 32 and not (protect_face and _face_area(eyes).has_point(Vector2i(x, y))) and body.get_pixel(x, y).a > 0.5 and body.get_pixel(x, y) != INK:
					body.set_pixel(x, y, Color("76543e"))
		for point: Vector2i in [Vector2i(15, 16), Vector2i(16, 16), Vector2i(17, 16), Vector2i(16, 17)]:
			var moved := point + Vector2i(0, bob)
			if not (protect_face and _face_area(eyes).has_point(moved)) and body.get_pixelv(moved).a > 0.5 and body.get_pixelv(moved) != INK:
				body.set_pixelv(moved, Color("3e7875" if point.x != 16 else "60938a"))
	elif profile.has("cloth") and not profile.has("outfit"):
		for y in range(maxi(0, 18 + bob), 22):
			for x in range(maxi(0, 14 + torso_shift), mini(32, 19 + torso_shift)):
				if clothes != null and clothes.get_pixel(x, y).a > 0.5 and body.get_pixel(x, y) != INK:
					body.set_pixel(x, y, Color(String(profile["cloth"])))

static func _face_area(eyes: Rect2i) -> Rect2i:
	return Rect2i(eyes.position.x - 2, eyes.position.y - 1, eyes.size.x + 4, eyes.size.y + 3) if eyes.has_area() else Rect2i()

# 衣服沿作者姿态裁剪: 开领、外套、围裙、束腰和毛领都是几块清晰的原生色块。
# 不扩大胸臀, 不拉伸身体, 工作中的手臂保持原作轮廓。
static func _tailor(body: Image, clothes: Image, profile: Dictionary, direction: int, bob: int) -> void:
	if clothes == null or not clothes.get_used_rect().has_area():
		return
	var kind: String = profile.get("outfit", "blouse")
	var outer := Color(String(profile.get("cloth", "62538c")))
	var trim := Color(String(profile.get("trim", "d6c5a1")))
	var center: int = clampi(clothes.get_used_rect().get_center().x, 12, 20)
	var neck: int = clampi(17 + bob, 14, 21)
	for y in range(neck, 24):
		for x in range(maxi(0, center - 5), mini(32, center + 6)):
			var pixel: Color = body.get_pixel(x, y)
			if pixel.a < 0.5 or pixel == INK or clothes.get_pixel(x, y).a < 0.5:
				continue
			var distance: int = absi(x - center)
			if kind in ["jacket", "coat", "fur_coat"]:
				if direction == 1 or distance >= (1 if direction == 2 else 2):
					body.set_pixel(x, y, outer.darkened(0.12) if pixel.v < 0.5 else outer)
				if kind == "fur_coat" and y == neck and distance >= 1:
					body.set_pixel(x, y, trim)
			elif kind == "apron" and y >= neck + 1 and distance <= 2:
				body.set_pixel(x, y, trim.darkened(0.12) if x == center + 2 else trim)
			elif kind == "pinafore" and y >= neck + 2:
				body.set_pixel(x, y, outer.darkened(0.14) if x > center else outer)
			# 腰带只占一条原生像素行, 衣服边界与体型仍由原作定义。
			if y == 20 + bob and kind in ["blouse", "pinafore", "open_shirt", "coat"]:
				body.set_pixel(x, y, trim.darkened(0.20))
	# 正面适度开领, 只在领口留一到两像素肤色, 背面与侧面不补假领口。
	if direction == 0 and kind in ["blouse", "open_shirt", "jacket"]:
		for y in range(neck, mini(neck + 2, 22)):
			if body.get_pixel(center, y).a > 0.5 and body.get_pixel(center, y) != INK:
				body.set_pixel(center, y, Color("f1d5b0"))
	if direction != 1 and profile.has("trim") and kind in ["coat", "jacket"]:
		var point := Vector2i(center + (2 if direction == 0 else 0), neck + 1)
		if body.get_pixelv(point).a > 0.5 and body.get_pixelv(point) != INK:
			body.set_pixelv(point, trim)

static func _row_map(eyes: Rect2i, grow: bool) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(32)
	var first: int = maxi(18, eyes.end.y + 2) if eyes.has_area() else 18
	var second: int = maxi(21, first + 1)
	var third: int = maxi(23, second + 1)
	var target: int = -4 if grow else 0
	for y in 32:
		result[y] = target
		target += 1 + (int(y == first) + int(y == second) + 2 * int(y == third) if grow else 0)
	return result

static func _grow(source: Image, mapping: PackedInt32Array) -> Image:
	var result := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		var end: int = mapping[y + 1] if y < 31 else mapping[y] + 1
		for target_y in range(maxi(0, mapping[y]), mini(32, end)):
			result.blit_rect(source, Rect2i(0, y, 32, 1), Vector2i(0, target_y))
	return result

static func _grip_shift(skin: Image, clothes: Image, hair: Image, eyes: Rect2i, tool: Image, offset: Vector2i, mapping: PackedInt32Array) -> int:
	var total: int = 0
	var count: int = 0
	var face := eyes.grow(3) if eyes.has_area() else Rect2i(12, 7, 9, 10)
	for y in 26:
		for x in 32:
			var color: Color = skin.get_pixel(x, y)
			if color.a < 0.5 or color.to_html(false) not in ["f9e6cf", "fcba92"] or face.has_point(Vector2i(x, y)):
				continue
			if clothes != null and clothes.get_pixel(x, y).a > 0.5:
				continue
			if hair != null and hair.get_pixel(x, y).a > 0.5:
				continue
			if tool.get_pixelv(Vector2i(x, y) + offset).a > 0.5:
				total += mapping[y] - y
				count += 1
	# 完整工具只做平移, 不伸缩或旋转; 没有交叠时按下垂手腕的作者落点平移。
	return roundi(float(total) / count) if count > 0 else mapping[20] - 20
