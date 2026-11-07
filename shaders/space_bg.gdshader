shader_type canvas_item;
render_mode unshaded;

// 日系动画深空：三段渐变 + 两团星云 + 极光带 + 暗角，全部程序化。
// 540x960 到 720x1200 都能铺满，不依赖预渲染贴图。

uniform vec4 top_color : source_color = vec4(0.11, 0.16, 0.36, 1.0);
uniform vec4 mid_color : source_color = vec4(0.36, 0.49, 0.86, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.97, 0.78, 0.85, 1.0);
uniform vec4 nebula_a : source_color = vec4(0.62, 0.91, 0.86, 1.0);
uniform vec4 nebula_b : source_color = vec4(0.76, 0.65, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.95, 0.78, 1.0);
uniform float time_scale : hint_range(0.0, 3.0) = 1.0;
uniform float scroll : hint_range(0.0, 4.0) = 0.0;
uniform float nebula_amount : hint_range(0.0, 1.0) = 0.62;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.34;
uniform float game_dim : hint_range(0.0, 1.0) = 0.0;

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
	for (int i = 0; i < 4; i++) {
		v += vnoise(p) * a;
		p = p * 2.03 + vec2(17.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 drift = vec2(0.0, scroll * 0.5);

	vec3 col = mix(top_color.rgb, mid_color.rgb, smoothstep(0.0, 0.58, uv.y));
	col = mix(col, bottom_color.rgb, smoothstep(0.5, 1.05, uv.y));

	// 星云：两团低频噪声，边缘用 smoothstep 出绘画感
	vec2 q = uv * vec2(2.6, 3.4) + drift + vec2(TIME * 0.012 * time_scale, 0.0);
	float n1 = fbm(q + fbm(q * 0.7 + 3.1) * 0.7);
	float n2 = fbm(q * 1.7 - drift + vec2(9.4, TIME * 0.02 * time_scale));
	float cloud = smoothstep(0.40, 0.86, n1);
	col = mix(col, nebula_a.rgb, cloud * nebula_amount);
	col = mix(col, nebula_b.rgb, smoothstep(0.50, 0.92, n2) * nebula_amount * 0.58);

	// 极光带：斜向流动的亮带
	float band = sin((uv.y * 3.4 - uv.x * 1.2) + n1 * 2.6 + TIME * 0.08 * time_scale);
	col += glow_color.rgb * pow(max(0.0, band), 7.0) * 0.16;
	// 顶部柔光
	col += glow_color.rgb * smoothstep(0.55, 0.0, distance(uv, vec2(0.5, 0.08))) * 0.10;

	// 暗角 + 底部压暗，保证弹幕可读
	float v = length((uv - vec2(0.5, 0.46)) * vec2(1.0, 0.78));
	col *= 1.0 - v * vignette_strength;
	col *= mix(1.0, 0.82, smoothstep(0.72, 1.0, uv.y));
	// 战斗模式：底部平滑压暗，托住玩家与 HUD（不在 GDScript 里叠色带，避免横向条带）
	col *= 1.0 - smoothstep(0.30, 1.0, uv.y) * 0.34 * game_dim;

	// 轻微抖动防色带
	float grain = (hash21(FRAGCOORD.xy) - 0.5) / 255.0;
	col += grain;
	COLOR = vec4(col, 1.0);
}
