shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Ground marks for the dragon's attacks. Never a clean ring: the edge is torn by noise and each
// attack has its own material.
//   mode 0  meteor:   the falling rock's shadow darkens the ground, molten fissures spread out from
//                     the centre and the edge starts to smoulder as impact nears (progress 0..1)
//   mode 1  breath:   heat creeping along the ground, embers streaming outward, glow builds up
//   mode 2  dust:     scraped earth and gravel streaks (tail lash)
//   mode 3  lava:     molten pool with a cooling crust and bright flowing cracks
//   mode 4  crater:   charred ground with dying embers (after an impact), fades with `fade`
// shape 0 = circle (radius = plane half size), 1 = cone pointing -Z (length = plane half size).
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D cell_tex : repeat_enable, filter_linear_mipmap;
uniform int mode = 0;
uniform int shape = 0;
uniform float half_angle = 0.785;
uniform float progress = 0.0;
uniform float fade = 1.0;
uniform float seed = 0.0;
uniform float uv_scale = 1.0;   // world size / 10 m, keeps noise detail constant across sizes

void fragment() {
	vec2 p = UV * 2.0 - 1.0;          // x right, y = +Z (behind)
	float r = length(p);
	float ang = atan(p.x, -p.y);      // 0 straight ahead (-Z)
	float t = TIME;
	vec2 wuv = UV * uv_scale + vec2(seed, seed * 1.7);
	float n = texture(noise_tex, wuv * 0.9).r;
	float n2 = texture(noise_tex, wuv * 2.7 + 0.37).r;
	float edge = (shape == 0) ? r : max(r, abs(ang) / half_angle);
	if (shape == 1 && r < 0.04) { edge = 0.0; }
	edge += (n - 0.5) * 0.24 + (n2 - 0.5) * 0.08;
	float inside = 1.0 - smoothstep(0.9, 1.0, edge);
	float rim = smoothstep(0.62, 0.97, edge) * inside;
	float cell = texture(cell_tex, wuv * 1.6).r;
	float crack = 1.0 - smoothstep(0.0, 0.09 + 0.04 * n2, cell);
	vec3 col = vec3(0.0);
	float a = 0.0;

	if (mode == 0) {
		float grow = clamp(progress * 1.15, 0.0, 1.0);
		float shadow = inside * (0.25 + 0.5 * grow) * (1.0 - 0.45 * smoothstep(0.2, 1.0, edge));
		float fiss = crack * (1.0 - smoothstep(grow - 0.08, grow + 0.02, edge)) * inside;
		float pulse = 0.75 + 0.25 * sin(t * (8.0 + 14.0 * progress) + n * 6.0);
		float smoulder = rim * smoothstep(0.35, 1.0, progress) * (0.4 + 0.6 * n2) * pulse;
		col = mix(vec3(0.05, 0.02, 0.015), vec3(1.0, 0.32, 0.05) * 1.6, clamp(fiss * pulse + smoulder, 0.0, 1.0));
		a = clamp(shadow + fiss * 0.9 + smoulder * 0.8, 0.0, 0.95);
	} else if (mode == 1) {
		float flow = texture(noise_tex, vec2(r * 2.2 * uv_scale - t * 0.9, ang * 1.4 + seed)).r;
		float emb = smoothstep(0.62, 0.8, flow) * smoothstep(0.55, 0.85, n2);
		float heat = inside * (0.18 + 0.45 * progress) * (0.6 + 0.4 * n);
		float flick = rim * (0.5 + 0.5 * sin(t * 13.0 + n * 9.0)) * (0.3 + 0.7 * progress);
		col = mix(vec3(0.35, 0.06, 0.02), vec3(1.0, 0.55, 0.12) * 2.0, clamp(emb + flick * 0.7, 0.0, 1.0));
		a = clamp(heat + emb * inside * (0.4 + 0.6 * progress) + flick * 0.5, 0.0, 0.9);
	} else if (mode == 2) {
		float streak = texture(noise_tex, vec2(r * 0.6 * uv_scale + seed, ang * 7.0)).r;
		float scrape = smoothstep(0.55, 0.75, streak) * inside;
		float sweep = 1.0 - smoothstep(progress * 2.2 - 1.1, progress * 2.2 - 0.9, ang / max(half_angle, 0.01));
		col = mix(vec3(0.16, 0.11, 0.08), vec3(0.42, 0.32, 0.22), scrape);
		a = inside * (0.18 + 0.25 * progress + scrape * 0.3) * (0.5 + 0.5 * sweep);
	} else if (mode == 3) {
		float flow = texture(noise_tex, wuv * 1.2 + vec2(t * 0.03, -t * 0.05)).r;
		float crust = smoothstep(0.42, 0.62, flow + (n2 - 0.5) * 0.4);
		float glow = (1.0 - crust) * (0.75 + 0.25 * sin(t * 2.0 + n * 8.0));
		float hot = crack * crust;
		col = mix(vec3(0.1, 0.03, 0.02), vec3(1.0, 0.3, 0.04) * 1.7, clamp(glow + hot * 0.8, 0.0, 1.0));
		col = mix(col, vec3(1.0, 0.62, 0.22) * 1.9, (1.0 - smoothstep(0.0, 0.22, flow)) * 0.55);
		float grow = clamp(progress, 0.0, 1.0);
		float within = 1.0 - smoothstep(grow * 0.9, grow, edge);
		a = within * (0.92 - rim * 0.25);
	} else {
		float emb = crack * (0.5 + 0.5 * sin(t * 3.0 + n * 7.0)) * fade;
		col = mix(vec3(0.03, 0.02, 0.02), vec3(1.0, 0.38, 0.06) * 2.0, emb);
		a = inside * (0.75 - rim * 0.45) * (0.6 + 0.4 * n) + emb * inside * 0.5;
	}
	ALBEDO = col;
	ALPHA = clamp(a * fade, 0.0, 1.0);
}
