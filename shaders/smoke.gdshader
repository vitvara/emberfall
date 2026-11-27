shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Particle smoke / dust: a billowing puff with a noise-eroded edge that thins out with age.
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float density = 1.0;

varying float v_age;
varying float v_seed;

void vertex() {
	mat4 w = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	w = w * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * w;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_age = INSTANCE_CUSTOM.y;
	v_seed = fract(float(INSTANCE_ID) * 0.7548776);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	vec2 nuv = UV * 0.9 + vec2(v_seed * 5.0, v_seed * 2.0 + TIME * 0.08);
	float n = texture(noise_tex, nuv).r * 0.6 + texture(noise_tex, nuv * 2.4 - vec2(TIME * 0.05)).r * 0.4;
	float puff = 1.0 - smoothstep(0.35, 1.0, r + (n - 0.5) * 0.7);
	puff *= 1.0 - smoothstep(0.72, 0.97, r);   // never reach the quad's edge (no square corners)
	float a = smoothstep(0.05, 0.6, puff - v_age * 0.35) * (0.55 + 0.45 * n);
	// a little self-shading: darker bottom-right, lighter top-left
	float shade = 0.8 + 0.35 * (n - 0.5) - p.y * 0.12;
	ALBEDO = COLOR.rgb * shade;
	ALPHA = clamp(a * COLOR.a * density, 0.0, 1.0);
}
