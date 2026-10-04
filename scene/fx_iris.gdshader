shader_type canvas_item;
// C1 iris 转场: 圆形光洞从中心展开/收拢, 软边柔和
uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float feather = 0.09;
	// progress=0 时 hole<0 保证全黑, progress=1 时洞覆盖全屏
	float hole = progress * (1.25 + feather) - feather;
	// 16:9 宽屏补偿: 横向半径按比例放大, 洞才是正圆
	float r = length((UV - vec2(0.5)) * vec2(1.7778, 1.0));
	COLOR = vec4(0.015, 0.015, 0.025, smoothstep(hole - feather, hole, r));
}
