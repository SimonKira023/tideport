shader_type canvas_item;
// 雾团：噪声双八度错速流动，阈值切出软边雾块，intensity 控制整体浓度。
// 用的是 Sprite2D 自带的无缝噪声贴图（TEXTURE），repeat 铺 3x3 块。
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fog_color : source_color = vec4(0.78, 0.83, 0.92, 1.0);

void fragment() {
	vec2 uv = UV * 3.0;
	float t = TIME;
	float n1 = texture(TEXTURE, uv + vec2(t * 0.010, t * 0.004)).r;
	float n2 = texture(TEXTURE, uv * 1.9 - vec2(t * 0.017, -t * 0.006)).r;
	float n = n1 * 0.65 + n2 * 0.35;
	float a = smoothstep(0.42, 0.78, n) * intensity * 0.55;
	COLOR = vec4(fog_color.rgb, a);
}
