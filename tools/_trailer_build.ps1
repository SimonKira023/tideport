# k3: 预告片合成 —— tools/_trailer/*.png (9 镜头) + 2 张黑卡字幕卡 -> trailer.mp4
# 结构: 黑卡 -> 标题 -> 春夏秋冬 -> 夜 -> 战斗 -> 海图 -> 据点 -> 黑卡
# 每段 3.5s, xfade 1s 转场, 共 11*3.5-10*1 = 28.5s; BGM 用游戏主菜单曲 menu.ogg
# 用法: powershell -ExecutionPolicy Bypass -File tools\_trailer_build.ps1
$ErrorActionPreference = "Stop"
$ff = ".tmp_ff\ffmpeg.exe"
$out = "tools\_trailer"
$tmp = "$out\_segs"
$font = "'C\:/Windows/Fonts/msyh.ttc'"
$bgm = "resources\audio\bgm\menu.ogg"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# 段配置: name=镜头 png (空=黑卡), cap=字幕 txt (空=无字幕), zoom=push|pull 交替运镜
$segs = @(
	@{ name = "";            cap = "cap_01.txt"; zoom = ""     },
	@{ name = "01_title";    cap = "";           zoom = "push" },
	@{ name = "02_spring";   cap = "cap_02.txt"; zoom = "pull" },
	@{ name = "03_summer";   cap = "cap_03.txt"; zoom = "push" },
	@{ name = "04_autumn";   cap = "cap_04.txt"; zoom = "pull" },
	@{ name = "05_winter";   cap = "cap_05.txt"; zoom = "push" },
	@{ name = "06_night";    cap = "";           zoom = "pull" },
	@{ name = "07_battle";   cap = "cap_07.txt"; zoom = "push" },
	@{ name = "08_seamap";   cap = "cap_08.txt"; zoom = "pull" },
	@{ name = "09_mainland"; cap = "cap_09.txt"; zoom = "push" },
	@{ name = "";            cap = "cap_10.txt"; zoom = ""     }
)

# ---- 分段渲染: 静帧 -> 7680x4320 放大 -> zoompan 缓推/缓拉(防抖动) -> 字幕 ----
for ($i = 0; $i -lt $segs.Count; $i++) {
	$s = $segs[$i]
	$segFile = "$tmp\seg{0:d2}.mp4" -f $i
	$fargs = @("-y", "-hide_banner", "-loglevel", "error")
	if ($s.name -eq "") {
		$fargs += @("-f", "lavfi", "-i", "color=c=black:s=1920x1080:d=3.5:r=30")
	} else {
		$fargs += @("-i", "$out\$($s.name).png")
	}
	$vf = ""
	if ($s.name -ne "") {
		if ($s.zoom -eq "push") { $z = "1+0.12*on/104" } else { $z = "1.12-0.12*on/104" }
		$vf += "scale=7680:4320,zoompan=z='$z':d=105:x='(iw-iw/zoom)/2':y='(ih-ih/zoom)/2':s=1920x1080:fps=30"
	}
	if ($s.cap -ne "") {
		if ($vf -ne "") { $vf += "," }
		if ($s.name -eq "") {
			$vf += "drawtext=fontfile=${font}:textfile='tools/_trailer/$($s.cap)':fontsize=72:fontcolor=white:borderw=3:bordercolor=black:x=(w-text_w)/2:y=(h-text_h)/2"
		} else {
			$vf += "drawtext=fontfile=${font}:textfile='tools/_trailer/$($s.cap)':fontsize=60:fontcolor=white:borderw=3:bordercolor=black@0.85:x=(w-text_w)/2:y=h-170"
		}
	}
	$vf += ",format=yuv420p"
	$fargs += @("-vf", $vf, "-c:v", "libx264", "-crf", "18", "-preset", "medium", $segFile)
	& $ff @fargs
	if ($LASTEXITCODE -ne 0) { throw "segment $i failed" }
	Write-Host "seg $i ok"
}

# ---- xfade 拼接 11 段 + BGM 截取 28.5s 加淡入淡出 ----
$total = 11 * 3.5 - 10 * 1
$fcParts = @()
$prev = "[0:v]"
for ($i = 1; $i -lt $segs.Count; $i++) {
	$off = 2.5 * $i
	$fcParts += ("{0}[{1}:v]xfade=transition=fade:duration=1:offset={2}[v{1}]" -f $prev, $i, $off)
	$prev = "[v$i]"
}
$fcParts += ("[11:a]atrim=0:{0},afade=t=in:st=0:d=1,afade=t=out:st={1}:d=1[a]" -f $total, ($total - 1))
$jargs = @("-y", "-hide_banner", "-loglevel", "warning")
for ($i = 0; $i -lt $segs.Count; $i++) { $jargs += @("-i", ("$tmp\seg{0:d2}.mp4" -f $i)) }
$jargs += @("-i", $bgm)
$jargs += @("-filter_complex", ($fcParts -join ";"), "-map", "[v10]", "-map", "[a]", "-c:v", "libx264", "-crf", "18", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "$out\trailer.mp4")
& $ff @jargs
if ($LASTEXITCODE -ne 0) { throw "join failed" }
Write-Host "trailer done: $out\trailer.mp4"
