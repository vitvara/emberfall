shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Solid-blended variant of flame.gdshader for big, dense fires (breath, ground fire, pillars): additive
// flames stacked on a bright arena wash out to white, these keep a red-orange body with a hot core.
// Particle flame: an upright, camera-facing tongue of fire whose edge is eaten by scrolling noise,
// so each particle reads as a licking flame instead of a round dot. Colour comes from the particle
// colour ramp (COLOR); INSTANCE_CUSTOM.y is the particle's age (0..1) and burns it away over its life.
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float intensity = 1.0;
uniform float rise = 1.5;       // how fast the noise climbs the flame
uniform float wisp = 0.75;      // how ragged the edge is

varying float v_age;
varying float v_seed;

void vertex() {
	mat4 w = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * w;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_age = INSTANCE_CUSTOM.y;
	v_seed = fract(float(INSTANCE_ID) * 0.61803398);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;                 // x -1..1, y -1 (top) .. 1 (bottom)
	float up = clamp(0.5 - p.y * 0.5, 0.0, 1.0);   // 0 at the base, 1 at the tip
	float t = TIME;
	vec2 nuv = vec2(UV.x * 0.8 + v_seed * 7.3, UV.y * 0.7 + t * rise + v_seed * 3.1);
	float n = texture(noise_tex, nuv).r * 0.62 + texture(noise_tex, nuv * 2.3 + vec2(t * 0.35, t * 0.9)).r * 0.38;
	// Teardrop: round base, narrowing tip that sways with the noise.
	float width = mix(0.82, 0.1, pow(up, 1.25));
	float dx = (p.x + (n - 0.5) * 0.6 * up) / max(width, 0.03);
	float base = 1.0 - smoothstep(0.5, 1.0, length(vec2(dx, max(p.y - 0.2, 0.0) * 2.4)));
	float body = 1.0 - smoothstep(0.55, 1.0, abs(dx));
	float shape = body * base * (1.0 - smoothstep(0.82, 1.0, up));
	float f = shape - n * wisp - v_age * 0.6 + 0.3;
	float a = smoothstep(0.0, 0.22, f);
	float core = smoothstep(0.22, 0.75, f) * (1.0 - v_age);
	vec3 c = COLOR.rgb;
	vec3 body_col = mix(c * vec3(0.75, 0.35, 0.25), c, smoothstep(0.0, 0.35, f));
	ALBEDO = mix(body_col, vec3(1.0, 0.82, 0.45), core * 0.55) * intensity * 1.45;
	ALPHA = clamp(a * COLOR.a * 0.92, 0.0, 1.0);
}
