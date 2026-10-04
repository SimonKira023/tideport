shader_type canvas_item;
// 唯美后处理 v2（j2）：泛光 + 色温分离 + 柔光 + 饱和提升 + 晕影 + 顶部天光
//   · 泛光 bloom：4 方向双圈采样，亮部提取后晕开（灯光/水光/星星的反光柔化）
//     （v3 性能：8 方向砍成 4 方向斜十字，每像素 17 次采样降到 9 次——大地图帧率救星）
//   · 色温分离 split-toning：高光镀暖金、阴影浸冷青，中间调平滑过渡
//   · 柔光 soft-light：深暖玫瑰底色轻罩整幅，提气色不脏色
//   · strength 统一控制总浓度（0=原画，1=全开）
// e31 光影：加 night（0=白天, 1=深夜，game.gd 每帧喂）——
//   夜里把泛光推强（灯火更抓眼）、顶部天光从暖金换成冷月光、晕影压深一点。
//   昼夜本身由 CanvasModulate 上色，这里只调"光感"，不重复上色。
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;
// e52 情绪滤镜: 战局危急(+)边缘浸暗红, 大优(-)整幅镀暖金, 0 = 无感
uniform float mood : hint_range(-1.0, 1.0) = 0.0;
// 雨夜湿地反光：把上半屏的亮源（灯/窗/天光）往下"淌"出湿润光晕
// 2D 没有真 SSR，这是屏幕空间的假反射——上半采样、下半着色
uniform float wet : hint_range(0.0, 1.0) = 0.0;
// 胶片颗粒：暗部更显的细腻噪点，压住色带(banding)并给雨夜铺一层胶片感
uniform float grain : hint_range(0.0, 0.2) = 0.0;
// 色差：径向 RGB 微散，越靠画面边缘越散（夜/雨由 game.gd 调大，镜头质感）
uniform float ca : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

void fragment() {
	// ---- 色差：R 向外散、B 向内收，中心不动——夜雨里灯牌才有"镜头"味
	vec2 cd = (SCREEN_UV - vec2(0.5)) * ca * 0.0035;
	vec3 src = vec3(
			texture(screen_tex, SCREEN_UV + cd).r,
			texture(screen_tex, SCREEN_UV).g,
			texture(screen_tex, SCREEN_UV - cd).b);
	vec3 col = src;

	// ---- 泛光：只晕亮部，暗处保持干净（夜里更浓：光源在黑底上最抢眼）
	// 4 方向斜十字双圈（8 采样 + 中心 1 采样），比 8 方向省一半，观感几乎无差
	vec2 px = SCREEN_PIXEL_SIZE * 1.9;
	vec3 blur = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		float a = TAU * float(i) / 4.0 + 0.7853982;  // 45° 起，斜十字避免横竖纹理伪影
		vec2 off = vec2(cos(a), sin(a));
		blur += texture(screen_tex, SCREEN_UV + off * px).rgb;
		blur += texture(screen_tex, SCREEN_UV + off * px * 2.3).rgb;
	}
	blur /= 8.0;
	float bl = dot(blur, vec3(0.299, 0.587, 0.114));
	col += blur * smoothstep(0.52, 0.95, bl) * (0.5 + night * 0.2);

	// ---- 雨夜湿地反光 v2：向上采 10 点找亮源，把"源的颜色"往下淌出更长的湿润光带
	// （v1 是固定蓝白；v2 带源色——暖灯淌暖光、青窗淌青光，更像真积水映灯）
	if (wet > 0.003) {
		vec3 acc = vec3(0.0);
		for (float f = 1.0; f <= 10.0; f += 1.0) {
			vec2 ruv = SCREEN_UV - vec2(0.0, SCREEN_PIXEL_SIZE.y * (2.0 + f * f * 3.2));
			vec3 rc = texture(screen_tex, ruv).rgb;
			float b = dot(rc, vec3(0.299, 0.587, 0.114));
			acc += rc * smoothstep(0.55, 1.0, b) / f;   // 越远的亮源贡献越淡
		}
		float flow = 0.72 + 0.28 * sin(TIME * 1.9 + SCREEN_UV.y * 22.0 + SCREEN_UV.x * 7.0);
		float gnd = smoothstep(0.18, 0.72, SCREEN_UV.y);  // 只落下半屏（地面才积水）
		col += acc * gnd * flow * wet * 0.22;
	}

	// ---- 夜对比：夜里轻拉 S 曲线，黑更沉、灯更挺（高对比雨夜的胶片感）
	// 超亮部分（泛光加出来的）不参与回压，保住 bloom 的光晕
	if (night > 0.003) {
		vec3 sc = clamp(col, 0.0, 1.0);
		col = mix(col, sc * sc * (3.0 - 2.0 * sc), night * 0.28);
	}

	// ---- 色温分离：高光镀金、阴影浸青 + 晨雾感
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	float tone = smoothstep(0.16, 0.85, l);
	col *= mix(vec3(0.87, 0.94, 1.17), vec3(1.07, 1.0, 0.85), tone);
	col += vec3(0.02, 0.045, 0.085) * (1.0 - tone);

	// ---- 柔光：deep warm rose 底色 soft-light 轻罩
	vec3 soft = vec3(0.34, 0.26, 0.21);
	vec3 blended = mix(2.0 * col * soft,
			1.0 - 2.0 * (1.0 - col) * (1.0 - soft), smoothstep(0.35, 0.65, l));
	col = mix(col, blended, 0.2);

	// ---- 饱和与活力
	col = mix(vec3(l), col, 1.14);

	// ---- 晕影 + 顶部天光（白天暖金斜阳 -> 夜里冷月光，晕影夜里更收）
	vec2 d = (SCREEN_UV - vec2(0.5)) * vec2(1.18, 1.4);
	float vig = smoothstep(0.55, 1.2, length(d));
	col *= 1.0 - vig * (0.5 + night * 0.14);
	vec3 sky = mix(vec3(1.0, 0.92, 0.72), vec3(0.58, 0.70, 1.0), night);
	col += sky * (0.09 + night * 0.015) * smoothstep(0.85, 0.0, SCREEN_UV.y);

	// ---- 情绪滤镜（战斗用）: 危急时边缘浸暗红越压越紧, 大优时暖金上扬
	float m = clamp(mood, -1.0, 1.0);
	if (abs(m) > 0.003) {
		float edge = smoothstep(0.30, 0.98, length(d));
		if (m > 0.0) {
			vec3 danger = vec3(0.40, 0.045, 0.075);
			col = mix(col, col * 0.72 + danger * edge, m * (0.30 + 0.70 * edge));
		} else {
			float am = -m;
			col = mix(col, col * vec3(1.16, 1.03, 0.76) + vec3(0.055, 0.032, 0.0),
					am * (0.42 + 0.30 * (1.0 - edge)));
		}
	}

	// ---- 胶片颗粒：暗部更显、亮部抹平（压色带 + 雨夜胶片感）
	if (grain > 0.001) {
		float gn = fract(sin(dot(SCREEN_UV * vec2(TIME * 61.7 + 13.0, TIME * 83.3 + 7.0),
				vec2(12.9898, 78.233))) * 43758.5453);
		col += vec3((gn - 0.5) * grain * (1.15 - l * 0.6));
	}

	COLOR = vec4(mix(src, col, strength), 1.0);
}
