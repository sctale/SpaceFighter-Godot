shader_type canvas_item;
render_mode unshaded;

// 像素霓虹深空：低分辨率像素化的星云 + CRT 扫描线 + 拜尔抖动 + 霓虹地平线。
// 全部程序化，540x960 到 720x1200 都能铺满，不依赖预渲染贴图。
// 与 space_bg 旧版保持相同的 uniform 名称，backdrop.gd 无需改参数即可切换。

uniform vec4 top_color : source_color = vec4(0.02, 0.01, 0.05, 1.0);
uniform vec4 mid_color : source_color = vec4(0.06, 0.02, 0.14, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.12, 0.02, 0.16, 1.0);
uniform vec4 nebula_a : source_color = vec4(0.85, 0.10, 0.55, 1.0);
uniform vec4 nebula_b : source_color = vec4(0.10, 0.75, 0.90, 1.0);
uniform vec4 glow_color : source_color = vec4(0.95, 0.95, 1.0, 1.0);
uniform float time_scale : hint_range(0.0, 3.0) = 1.0;
uniform float scroll : hint_range(0.0, 4.0) = 0.0;
uniform float nebula_amount : hint_range(0.0, 1.0) = 0.52;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.46;
uniform float game_dim : hint_range(0.0, 1.0) = 0.0;
// 像素网格密度：越大像素越细。180 约等于 180 格横向。
uniform float pixel_grid : hint_range(64.0, 512.0) = 168.0;
uniform float scanline : hint_range(0.0, 1.0) = 0.16;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 3; i++) {
		v += vnoise(p) * a;
		p = p * 2.07 + vec2(13.7, 7.2);
		a *= 0.5;
	}
	return v;
}

// 4x4 拜尔抖动矩阵
float bayer(vec2 c) {
	int x = int(mod(c.x, 4.0));
	int y = int(mod(c.y, 4.0));
	const float m[16] = float[16](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0);
	return m[y * 4 + x] / 16.0;
}

void fragment() {
	// 1) 先把 UV 吸附到粗像素网格，星云按块状着色
	vec2 grid = vec2(pixel_grid, pixel_grid + 60.0);
	vec2 cell = floor(UV * grid);
	vec2 puv = (cell + 0.5) / grid;

	vec3 col = mix(top_color.rgb, mid_color.rgb, smoothstep(0.0, 0.62, puv.y));
	col = mix(col, bottom_color.rgb, smoothstep(0.55, 1.05, puv.y));

	// 2) 两块霓虹星云（洋红 / 青），像素化后仍保持成团形状
	vec2 drift = vec2(0.0, scroll * 0.42);
	vec2 q = puv * vec2(2.2, 3.0) + drift + vec2(TIME * 0.010 * time_scale, 0.0);
	float n1 = fbm(q + fbm(q * 0.7 + 3.1) * 0.6);
	float n2 = fbm(q * 1.6 - drift + vec2(9.4, TIME * 0.016 * time_scale));
	col = mix(col, nebula_a.rgb, smoothstep(0.44, 0.88, n1) * nebula_amount);
	col = mix(col, nebula_b.rgb, smoothstep(0.52, 0.94, n2) * nebula_amount * 0.62);

	// 3) 霓虹地平线：底部一排渐隐的像素横线，像街机机台的透视格
	float horizon = smoothstep(0.62, 1.0, puv.y);
	float line = step(0.86, fract(puv.y * 34.0 + TIME * 0.05 * time_scale));
	col += nebula_b.rgb * line * horizon * 0.055;

	// 4) 拜尔抖动量化：把连续渐变压成有限色阶，得到像素画质感
	float d = bayer(cell);
	col = floor(col * 11.0 + d) / 11.0;

	// 5) CRT 扫描线（按屏幕行，而不是色块行）
	float sl = step(0.5, fract(FRAGCOORD.y * 0.5));
	col *= 1.0 - sl * scanline;

	// 6) 暗角 + 战斗模式压暗，保证弹幕可读
	float v = length((UV - vec2(0.5, 0.46)) * vec2(1.0, 0.78));
	col *= 1.0 - v * vignette_strength;
	col *= 1.0 - smoothstep(0.30, 1.0, UV.y) * 0.30 * game_dim;

	COLOR = vec4(col, 1.0);
}
