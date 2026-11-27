shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Ornate spell circle drawn on the ground: rings, four sweeping crescent arms,
// diamond panels, hooked caps, and a swirling mist core. Fully procedural.
uniform vec4 color : source_color = vec4(0.45, 0.75, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float spin = 0.35;

float ln(float d, float w) { return 1.0 - smoothstep(0.0, w, abs(d)); }

void fragment() {
	vec2 p0 = UV * 2.0 - 1.0;
	float t = TIME * spin;
	vec2 p = vec2(p0.x * cos(t) - p0.y * sin(t), p0.x * sin(t) + p0.y * cos(t));
	float r = length(p);
	float a = atan(p.y, p.x);
	float v = 0.0;
	v = max(v, ln(r - 0.95, 0.014));
	v = max(v, ln(r - 0.89, 0.006) * 0.7);
	v = max(v, ln(r - 0.28, 0.01));
	v = max(v, ln(r - 0.22, 0.005) * 0.6);
	// Sweeping crescent arms
	for (int k = 0; k < 4; k++) {
		float arm = float(k) * 1.5708 + (r - 0.28) * 1.9;
		float d = mod(a - arm + 3.14159, 6.28318) - 3.14159;
		if (r > 0.28 && r < 0.89) {
			v = max(v, ln(d * r, 0.006 + 0.022 * (0.89 - r)));
		}
	}
	// Diamond panels between the arms
	for (int k = 0; k < 4; k++) {
		float ang = float(k) * 1.5708 + 0.7854;
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 per = vec2(-dir.y, dir.x);
		float u = dot(p, dir) - 0.62;
		float w = dot(p, per);
		float dd = abs(u) / 0.17 + abs(w) / 0.12;
		v = max(v, ln(dd - 1.0, 0.07) * 0.9);
		v = max(v, ln(dd - 0.55, 0.06) * 0.5);
		// Hooked caps on the outer rim
		float cap = length(p - dir * 1.0) - 0.11;
		if (r > 0.95) { v = max(v, ln(cap, 0.012)); }
	}
	// Inner swirling mist
	float swirl = 0.5 + 0.5 * sin(a * 5.0 + r * 14.0 - TIME * 3.0);
	float mist = swirl * (1.0 - smoothstep(0.0, 0.55, r)) * 0.45 + (1.0 - smoothstep(0.0, 0.12, r)) * 0.6;
	float fade = 1.0 - smoothstep(1.0, 1.08, r);
	ALBEDO = mix(color.rgb * 1.3, vec3(1.0), v * 0.12) * (v * 2.6 + mist * 1.4) * intensity;
	ALPHA = clamp((v + mist * 0.7) * intensity * fade, 0.0, 1.0);
}
