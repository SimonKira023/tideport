# audio_manager.gd —— Autoload，名字：Audio
#
# 星露谷风格的背景音乐 + 音效。
# 音频不是从网上下的，而是 `tools/make_audio.py` 用纯 Python 的 wave 模块
# 现场合成的（方波/三角波/噪声 + 包络），所以没有版权问题、体积也小。
#
# 用法：
#   Audio.play_sfx("hoe")            # 播一个音效
#   Audio.play_sfx("coin", 3.0)      # 音量 +3dB
#   Audio.play_sfx("step", -10.0, 1.05)  # 音量 -10dB、音高 +5%（脚步随机化）
#
# BGM e52: 撤销 e49 的自制 41 首曲池，回到「原本的设置」——
#   岛上：Towball's Crossing Deluxe 的**十首** loopable 曲。每天起床随机选中一首，
#         那一天在岛上就一直是那一首的循环（loop=true，不换曲）。
#   出海 / 城镇 / 战场 / 战斗结算：中世纪包 Loops Medieval Vol. 2 的八首（loop=true），
#         进场景时从八首里随机挑一首，一直循环。
#   主菜单：固定 menu.ogg；开场动画：中世纪包第 2 首（e53: 跟主菜单区分开）。
#   场景指定曲目：Audio.set_scene_bgm("ocean"/"town"/"battle"/"settle"/"menu"/
#   "opening")，回岛上再 set_scene_bgm("island")。
# 所有资源缺失都不会报错崩游戏 —— 静默跳过（方便在没导入音频的机器上跑自检）。
extends Node

const BGM_DIR := "res://resources/audio/bgm/"   # 还剩主菜单那首 menu.ogg 在这
const SFX_DIR := "res://resources/audio/sfx/"
# 外部素材包（曲名带空格/感叹号，路径按实际目录写死）
const TOWBALL_DIR := "res://resources/Towball's Crossing Deluxe!/Towball's Crossing Deluxe!/Towballs Crossing Deluxe! Loopable Tracks/"
const MEDIEVAL_DIR := "res://resources/Loops Medieval Vol. 2/ogg/"

# 岛上的十首（Towball）。_on_new_day 挑一首当「今天的曲子」，一整天循环。
const ISLAND_TRACKS := [
	TOWBALL_DIR + "01 Welcome To Towballs Crossing Deluxe! (Loopable Version).mp3",
	TOWBALL_DIR + "02 Enjoying the Sunrise (Loopable Version).mp3",
	TOWBALL_DIR + "03 Spring is in the Air! (Loopable Version).mp3",
	TOWBALL_DIR + "04 Island Life (Loopable Version).mp3",
	TOWBALL_DIR + "05 At the Farmers Market (Loopable Version).mp3",
	TOWBALL_DIR + "06 Tax Office (Loopable Version).mp3",
	TOWBALL_DIR + "07 Afternoon Boredom (Loopable Version).mp3",
	TOWBALL_DIR + "08 Spooky Time! (Loopable Version).mp3",
	TOWBALL_DIR + "09 Snowed In (Loopable Version).mp3",
	TOWBALL_DIR + "10 Goodnight and Sweet Dreams (Loopable Version).mp3",
]

# 中世纪包八首（出海 / 城镇 / 战场 / 结算共用这一池）
const MEDIEVAL_TRACKS := [
	MEDIEVAL_DIR + "Medieval Vol. 2 1 (Loop).ogg",
	MEDIEVAL_DIR + "Medieval Vol. 2 2 (Loop).ogg",
	MEDIEVAL_DIR + "Medieval Vol. 2 3 (Loop).ogg",
	MEDIEVAL_DIR + "Medieval Vol. 2 4 (Loop).ogg",
	MEDIEVAL_DIR + "Medieval Vol. 2 5 (Loop).ogg",
	MEDIEVAL_DIR + "Medieval Vol. 2 6 (Loop).ogg",
	MEDIEVAL_DIR + "Medieval Vol. 2 7 (Loop).ogg",
	MEDIEVAL_DIR + "Medieval Vol. 2 8 (Loop).ogg",
]

# 战斗曲池：按 ffmpeg volumedetect 响度（mean）从 MEDIEVAL_TRACKS 挑最激烈的 5 首
# Track 5 (-19.7) > 4 (-20.0) > 6 (-21.8) > 3 (-22.0) > 2 (-22.1)
const BATTLE_TRACKS := [
	MEDIEVAL_DIR + "Medieval Vol. 2 5 (Loop).ogg",
	MEDIEVAL_DIR + "Medieval Vol. 2 4 (Loop).ogg",
	MEDIEVAL_DIR + "Medieval Vol. 2 6 (Loop).ogg",
	MEDIEVAL_DIR + "Medieval Vol. 2 3 (Loop).ogg",
	MEDIEVAL_DIR + "Medieval Vol. 2 2 (Loop).ogg",
]

# 场景曲池（场景组 -> 曲文件全路径）。进场景时从池里随机挑一首，避开当前这首。
const MUSIC_POOL := {
	"menu": [BGM_DIR + "menu.ogg"],
	# 开局动画不跟主菜单共用一首：用中世纪包第 2 首（e53）
	"opening": [MEDIEVAL_DIR + "Medieval Vol. 2 2 (Loop).ogg"],
	"ocean": MEDIEVAL_TRACKS,
	"town": MEDIEVAL_TRACKS,
	"battle": BATTLE_TRACKS,
	"settle": MEDIEVAL_TRACKS,
}
const DEFAULT_KEY := "island"

# 跟 tools/make_audio.py 生成的文件一一对应
const SFX_NAMES := [
	"hoe", "water", "fill", "plant", "harvest", "pickup", "coin", "buy",
	"error", "ui_click", "ui_open", "ui_close", "step", "sleep", "bin",
	"chop", "fell", "campfire", "thunder",
	"step_wood", "step_stone", "step_sand",
	"deploy", "move", "attack",
]

const SFX_POOL := 10          # 同时能响多少个音效（脚步/砍树一起响时不会互相打断）
const SFX_VOLUME_DB := -8.0    # e30j: 音效整体调小一点(-5 → -8)，玩家反馈声响偏大
const BGM_VOLUME_DB := -14.0     # e30n: BGM 再调小一点(-12 → -14), 与音效响度平衡; 曲间均衡已离线烘焙(loudnorm I=-16)
const BGM_SILENT_DB := -60.0
const BGM_FADE := 1.6         # 交叉淡入淡出时长（秒）e27c: 1.2→1.6, 曲中换曲更柔和

const NIGHT_FROM := 19        # 19 点之后算夜里
const DAY_FROM := 6           # 早上 6 点开始算白天

var _sfx_streams := {}
var _bgm_streams := {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _bgm_a: AudioStreamPlayer
var _bgm_b: AudioStreamPlayer
var _bgm_active: AudioStreamPlayer
var _current_track := ""
var _last_track := ""        # 上一首（换场景时清掉, 让新池可以重选旧曲）
var _group_last := {}        # 组名 -> 该组上一首：回到同一组/换日换曲时不跟上一首撞车
var _sync_group := ""        # 上次挑曲时的组：0.5s 轮询用它判断「同组还在播就别动」
var _scene_track := ""       # 场景音乐键（menu/island/ocean/town/battle）
var _bgm_check := 0.0
var _bgm_tween: Tween = null
var _rr := 0                  # 音效播放器轮转指针
var _island_day_track := ""    # e52: 今天岛上循环的那一首（_on_new_day 抽签, 一整天不变）
var _gap := false             # e29k: 曲间随机静默进行中（等下一首淡入）

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in SFX_POOL:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		p.volume_db = SFX_VOLUME_DB
		add_child(p)
		_sfx_players.append(p)
	_bgm_a = AudioStreamPlayer.new()
	_bgm_a.name = "BgmA"
	_bgm_a.volume_db = BGM_SILENT_DB
	add_child(_bgm_a)
	_bgm_b = AudioStreamPlayer.new()
	_bgm_b.name = "BgmB"
	_bgm_b.volume_db = BGM_SILENT_DB
	add_child(_bgm_b)
	_bgm_active = _bgm_a
	_bgm_a.finished.connect(_on_track_finished)
	_bgm_b.finished.connect(_on_track_finished)

	_load_all()
	call_deferred("_sync_bgm")
	# e23/e52: 每天起床在岛上重抽一首当天的曲子（那一天就循环它）
	TimeManager.new_day.connect(_on_new_day)

# ---------------- 载入 ----------------
func _load_all() -> void:
	for n in SFX_NAMES:
		var s := _load_stream(SFX_DIR + n + ".wav", false)
		if s != null:
			_sfx_streams[n] = s
	# 岛上十首（Towball）+ 场景池（中世纪八首 / menu）—— 全部 loop=true。
	# loop=true 的曲子不会发 finished, 所以岛上真就是「整天循环这一首」。
	var all_tracks: Array = ISLAND_TRACKS.duplicate()
	for key in MUSIC_POOL.keys():
		for f in MUSIC_POOL[key]:
			if not all_tracks.has(f):
				all_tracks.append(f)
	for f in all_tracks:
		var s2 := _load_music(f, true)
		if s2 != null:
			_bgm_streams[f] = s2
	var island_loaded := 0
	for f in ISLAND_TRACKS:
		if _bgm_streams.has(f):
			island_loaded += 1
	print("[音频] 音效 %d/%d 个, BGM %d/%d 首（岛上 Towball %d/%d, 中世纪包 %d/%d）" % [
		_sfx_streams.size(), SFX_NAMES.size(), _bgm_streams.size(), all_tracks.size(),
		island_loaded, ISLAND_TRACKS.size(),
		_loaded_count(MEDIEVAL_TRACKS), MEDIEVAL_TRACKS.size()])

# 池子里实际载入成功了几首（资源缺失时静默跳过, 打印/自检都要按「真的在的」算）
func _loaded_count(pool: Array) -> int:
	var n := 0
	for f in pool:
		if _bgm_streams.has(f):
			n += 1
	return n

# 按 loop 参数决定循环：e52 起一律 loop=true —— 岛上一天一首循环, 场景曲一首循环到底,
# 都不再靠「播完换曲」轮转（要换曲是进场景 / 起床这两个时机重新抽签）。
func _load_music(path: String, loop: bool) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("[音频] 找不到 %s -- 静默跳过(不影响游戏)" % path)
		return null
	var res: Resource = load(path)
	if res == null:
		return null
	var s := res.duplicate() as AudioStream
	if s == null:
		return res
	s.set("loop", loop)   # AudioStreamOggVorbis / AudioStreamMP3 都有 loop 属性
	return s

# 读一个 wav。loop=true 时把它设成从头到尾循环。
# ❗WAV 导入后的默认 loop_mode 是 Disabled，BGM 不设这个就会播一遍就停。
func _load_stream(path: String, loop: bool) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("[音频] 找不到 %s -- 静默跳过(不影响游戏)" % path)
		return null
	var res: Resource = load(path)
	var wav := res as AudioStreamWAV
	if wav == null:
		return res
	var s: AudioStreamWAV = wav.duplicate()
	if not loop:
		s.loop_mode = AudioStreamWAV.LOOP_DISABLED
		return s
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	# loop_end 单位是「帧」，而 data 是原始字节，得按位深和声道数换算
	var bytes_per_sample := 2
	if s.format == AudioStreamWAV.FORMAT_8_BITS:
		bytes_per_sample = 1
	var channels := 2 if s.stereo else 1
	var frames := int(s.data.size() / (bytes_per_sample * channels))
	s.loop_end = maxi(frames, 1)
	return s

# ---------------- 音效 ----------------
func play_sfx(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _sfx_streams.has(name):
		return
	var p := _pick_sfx_player()
	if p == null:
		return
	p.stream = _sfx_streams[name]
	p.volume_db = SFX_VOLUME_DB + volume_db
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
	p.play()

# 优先找闲置的播放器；都忙着就轮流复用（脚步声这种高频音效不会把池子撑爆）
func _pick_sfx_player() -> AudioStreamPlayer:
	if _sfx_players.is_empty():
		return null
	for i in _sfx_players.size():
		var idx := (_rr + i) % _sfx_players.size()
		if not _sfx_players[idx].playing:
			_rr = (idx + 1) % _sfx_players.size()
			return _sfx_players[idx]
	var fallback := _sfx_players[_rr]
	_rr = (_rr + 1) % _sfx_players.size()
	return fallback

# ---------------- BGM ----------------
func _process(delta: float) -> void:
	_bgm_check += delta
	if _bgm_check < 0.5:
		return
	_bgm_check = 0.0
	_sync_bgm()

func is_night_now() -> bool:
	var h: int = TimeManager.hour
	return h >= NIGHT_FROM or h < DAY_FROM

func current_track() -> String:
	return _current_track

# 场景音乐键（e21）："menu"/"ocean"/"town"/"battle"/"island"。
# 传同一个键不会重新起曲（免得每次进战场都从头开始放一遍）。
func set_scene_bgm(key: String) -> void:
	var k := key if key != "" else DEFAULT_KEY
	if k == _scene_track:
		return
	_scene_track = k
	_last_track = ""          # 换场景允许连播同曲（不同池互不排斥）
	_sync_bgm()

func scene_track() -> String:
	return _scene_track

# e52: 不再按「季节 + 昼夜」切组 —— 岛上就是一组十首, 当天抽中的那首循环一整天。
# 留这个函数是因为 _sync_bgm / 自检都按「组名」取池。
func _resolve_key() -> String:
	return _scene_track

# 组名 -> 曲目表（岛上单独一组, 其余查 MUSIC_POOL）
func _pool_of(group: String) -> Array:
	if group == "island":
		return ISLAND_TRACKS
	return MUSIC_POOL.get(group, [])

# 从组里随机挑一首：绝不与当前曲连播，也尽量避开该组上一首（组里挑得出别的就避开）
func _pick_from(group: String, exclude: String) -> String:
	var pool: Array = _pool_of(group)
	var usable: Array = []
	for f in pool:
		if _bgm_streams.has(f) and f != exclude:
			usable.append(f)
	if usable.is_empty():
		return ""
	if usable.size() > 1:
		var without_last := usable.duplicate()
		without_last.erase(String(_group_last.get(group, "")))
		if not without_last.is_empty():
			usable = without_last
	return String(usable[randi() % usable.size()])

# force=true 跳过「同组还在播」守卫（换场景/换日强制换曲用）。
# ❗0.5s 轮询也走这里：没有守卫的话每 0.5s 都会挑一首 != 当前的曲子换着放,
#   曲子永远停在交叉淡入的半路(-40dB) —— 这就是「进游戏几乎没声音」的根源。
func _sync_bgm(force := false) -> void:
	# 剧情演出接管期间: 0.5s 轮询不许把曲子抢回去 (pop_bgm 才恢复)
	if _sync_group == CUTSCENE_GROUP and not force:
		return
	var group := _resolve_key()
	# 岛上特殊：不是「从池里随机挑」, 而是「用今天抽中的那一首」（抽签在 _on_new_day）。
	# 所以从海图/城镇回岛、0.5s 轮询、起床这几种情况都只会把它拉回今天那一首。
	if group == "island":
		if _island_day_track == "":
			_island_day_track = _pick_from("island", _current_track)
		if _island_day_track == "":
			return
		if _current_track == _island_day_track and _bgm_active.playing:
			return
		_sync_group = group
		_last_track = _island_day_track
		_current_track = _island_day_track
		_crossfade_to(_island_day_track)
		return
	if not force and group == _sync_group \
			and _current_track != "" and _bgm_active.playing:
		return
	var want := _pick_from(group, _current_track)
	if want == "":
		want = _current_track          # 池里没得换（空组/单曲循环兜底）
	if want == "" or (want == _current_track and _bgm_active.playing):
		return
	_sync_group = group
	_last_track = want
	_group_last[group] = want
	_current_track = want
	_crossfade_to(want)

# e52: 每天起床在岛上重抽一首 —— 那一天岛上循环它。
# ❗这里要 force：曲子是 loop 的，没有这条钩子就永远是开局那首。
func _on_new_day(_day: int) -> void:
	if _bgm_in_cutscene:
		return                  # 演出接管中: 换日不许抢曲
	if _scene_track == "":
		return
	if _scene_track == "island":
		var old := _island_day_track
		_island_day_track = _pick_from("island", old)
		if _island_day_track == "":
			_island_day_track = old     # 池子读不出来就维持原样, 别把 BGM 弄哑
	_sync_bgm(true)

# 单曲播完 → 留一小段随机静默 → 从当前场景组里再随机挑一首淡入
func _on_track_finished() -> void:
	if _scene_track == "":
		return
	_current_track = ""
	if _gap:
		return
	# e29k: 曲与曲之间留 2~5 秒随机静默 —— 有出场有入场，别糊成一片。
	# e49: 41 首全部 loop=false，所以每组都靠这条路径轮着换曲。
	_gap = true
	var t := get_tree().create_timer(randf_range(2.0, 5.0))
	await t.timeout
	_gap = false
	_sync_bgm(false)   # 静默结束，1.6s 淡入下一首（出场/入场过渡）

func _crossfade_to(track: String) -> void:
	if not _bgm_streams.has(track):
		return
	# 上一次淡入淡出还没播完就又切曲的话，两个 tween 会同时改同一对播放器的音量，
	# 直接互相打架 → 先把旧的掐掉
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	var incoming: AudioStreamPlayer = _bgm_b if _bgm_active == _bgm_a else _bgm_a
	var outgoing := _bgm_active
	incoming.stream = _bgm_streams[track]
	# e27c: 曲中换曲 —— 原来 dB 线性 tween 在中点两边都掉到 -36dB,
	# 听感是「先变小再变大」。改成入曲快起(EASE_OUT)、出曲慢走快收(EASE_IN),
	# 近似平方增益的等功率交叉淡化, 中点不再凹陷。
	# （e29k: instant 接续分支已删 —— 唯一调用者改走「静默 → 正常淡入」路径）
	incoming.volume_db = BGM_SILENT_DB
	incoming.play()
	var tw := create_tween()
	tw.tween_property(incoming, "volume_db", BGM_VOLUME_DB, BGM_FADE) \
		.set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(outgoing, "volume_db", BGM_SILENT_DB, BGM_FADE) \
		.set_ease(Tween.EASE_IN)
	tw.tween_callback(outgoing.stop)
	_bgm_tween = tw
	_bgm_active = incoming

# 睡觉 / 结算画面时把 BGM 压下去（不是停掉，只是小声一点）
func duck(amount_db := -12.0, dur := 0.4) -> void:
	var tw := create_tween()
	tw.tween_property(_bgm_active, "volume_db", BGM_VOLUME_DB + amount_db, dur)

func unduck(dur := 0.6) -> void:
	var tw := create_tween()
	tw.tween_property(_bgm_active, "volume_db", BGM_VOLUME_DB, dur)

# ---------------- 剧情演出 BGM 接管 (cg_view / story_dialogue 用) ----------------
# push: 记下「演出接管中」, 切到情绪曲。_sync_group 离开场景组后,
#       0.5s 轮询和场景切换都不会再把曲子抢回去 (见 _sync_bgm 顶部的守卫)。
# pop:  解除接管, 按当前场景组强制重挑 (岛上就是今天抽中的那一首, 无缝回原曲)。
const CUTSCENE_GROUP := "cutscene"
var _bgm_in_cutscene := false

func push_bgm(track: String) -> void:
	if track == "" or not _bgm_streams.has(track):
		return
	if _sync_group == CUTSCENE_GROUP and _current_track == track and _bgm_active.playing:
		return
	_sync_group = CUTSCENE_GROUP
	_bgm_in_cutscene = true
	_last_track = track
	_current_track = track
	_crossfade_to(track)

func pop_bgm() -> void:
	if _sync_group != CUTSCENE_GROUP:
		return
	_sync_group = ""
	_bgm_in_cutscene = false
	_current_track = ""
	_sync_bgm(true)

func stop_bgm() -> void:
	_bgm_a.stop()
	_bgm_b.stop()
	_current_track = ""
	_scene_track = ""

# ---------------- D3 进屋低通 ----------------
var _indoor := false
var _lp_fx: AudioEffectLowPassFilter = null
var _lp_tween: Tween = null
const INDOOR_CUTOFF := 1250.0

# 进屋: Master 总线挂低通, BGM/音效/环境一起变闷; 出屋摘掉。
func set_indoor(on: bool) -> void:
	if _indoor == on:
		return
	_indoor = on
	var bus := AudioServer.get_bus_index("Master")
	if _lp_tween != null and _lp_tween.is_valid():
		_lp_tween.kill()
	if on:
		if _lp_fx == null:
			var fx := AudioEffectLowPassFilter.new()
			fx.resonance = 0.3
			_lp_fx = fx
			AudioServer.add_bus_effect(bus, fx)
		_lp_tween = create_tween()
		_lp_tween.tween_method(_set_cutoff, 20000.0, INDOOR_CUTOFF, 0.5)
	else:
		if _lp_fx != null:
			_lp_tween = create_tween()
			_lp_tween.tween_method(_set_cutoff, INDOOR_CUTOFF, 20000.0, 0.45)
			_lp_tween.tween_callback(_drop_lowpass)

func _set_cutoff(hz: float) -> void:
	if _lp_fx != null:
		_lp_fx.cutoff_hz = hz

func _drop_lowpass() -> void:
	if _lp_fx != null:
		AudioServer.remove_bus_effect(AudioServer.get_bus_index("Master"), 0)
		_lp_fx = null

# 环境音层读这个: 屋里把海浪/风/鸟压到四分之一
func indoor_gain() -> float:
	return 0.25 if _indoor else 1.0
