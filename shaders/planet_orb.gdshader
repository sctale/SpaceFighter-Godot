shader_type canvas_item;
render_mode unshaded;

// 赛璐璐星球/月面：圆形遮罩 + 三色阶 + 纬向云带 + 硬边描边。
// 只画球体，行星环由 backdrop.gd 的 _draw 叠在上面。

uniform vec4 light_col : source_color = vec4(1.0, 0.96, 0.90, 1.0);
uniform vec4 mid_col : source_color = vec4(0.82, 0.76, 0.96, 1.0);
uniform vec4 dark_col : source_color = vec4(0.42, 0.40, 0.66, 1.0);
uniform vec4 band_col : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 rim_col : source_color = vec4(1.0, 0.96, 0.82, 1.0);
uniform vec4 ink_col : source_color = vec4(0.16, 0.13, 0.22, 1.0);
uniform float bands : hint_range(0.0, 16.0) = 7.0;
uniform float band_strength : hint_range(0.0, 1.0) = 0.20;
uniform float light_angle : hint_range(-3.14, 3.14) = -0.72;

void fragment() {
	// 像素化：UV 吸附到色块中心，输出前再走 8 级拜尔抖动
	vec2 cells = vec2(44.0);
	vec2 cell = floor(UV * cells);
	vec2 uvq = (cell + 0.5) / cells;
	vec2 p = uvq * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float z = sqrt(max(0.0, 1.0 - r * r));
	vec3 n = normalize(vec3(p.x, p.y, z));
	vec3 l = normalize(vec3(cos(light_angle), sin(light_angle), 0.72));
	float lam = dot(n, l);

	vec3 col = dark_col.rgb;
	if (lam > 0.16) {
		col = mid_col.rgb;
	}
	if (lam > 0.50) {
		col = light_col.rgb;
	}

	// 纬向云带：从球心坐标切出不同高度的色带
	float t = p.y * 0.5 + 0.5;
	float b = smoothstep(0.52, 0.94, abs(sin(t * bands * 3.14159 + 0.35)));
	col = mix(col, band_col.rgb, b * band_strength);

	// 斜向云纹，增加手绘感
	float swirl = sin((p.x * 3.1 + p.y * 2.2) * 3.14159 + 1.2);
	col = mix(col, band_col.rgb, smoothstep(0.55, 1.0, swirl) * band_strength * 0.38);

	// 亮侧边缘 + 深色线稿
	float rim = smoothstep(0.72, 1.0, r);
	col = mix(col, rim_col.rgb, rim * 0.48);
	float edge = smoothstep(0.935, 0.995, r);
	col = mix(col, ink_col.rgb, edge * 0.92);

	// 色阶量化 + 拜尔抖动，与背景的像素霓虹保持同一套视觉语言
	int bx = int(mod(cell.x, 4.0));
	int by = int(mod(cell.y, 4.0));
	const float bm[16] = float[16](
		0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	float dith = bm[by * 4 + bx] / 16.0;
	col = floor(col * 8.0 + dith) / 8.0;
	COLOR = vec4(col, 1.0);
}
