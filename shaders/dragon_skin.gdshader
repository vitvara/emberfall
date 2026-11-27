shader_type spatial;
render_mode diffuse_toon, specular_toon;

// Vyrathax's hide: smooth, glossy near-black skin with a deep crimson undertone. The back fades to black,
// a faint ember rim outlines the silhouette so the dark body still reads against the arena, and the rim
// warms up with the dragon's heat (casting, enrage). No scale pattern: the surface stays smooth.
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 base_color : source_color = vec3(0.12, 0.025, 0.028);
uniform vec3 back_color : source_color = vec3(0.06, 0.018, 0.02);   // dorsal side
uniform vec3 rim_color : source_color = vec3(1.0, 0.2, 0.04);
uniform float heat = 1.0;            // driven by the rig every frame
uniform float rim = 0.5;
uniform float darkness = 0.0;        // extra darkening of the dorsal side
uniform float gloss = 0.35;          // lower = shinier
uniform vec3 belly_color : source_color = vec3(0.3, 0.12, 0.08);
uniform float belly = 0.0;           // 1 = lighter underside (torso)

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Very soft, large colour drift (no visible pattern), sampled in object-independent world space.
	float n = texture(noise_tex, wp.xz * 0.025 + wp.y * 0.01).r;
	float up = clamp(wn.y, 0.0, 1.0);
	vec3 col = mix(base_color, back_color, clamp(up * (0.8 + darkness), 0.0, 1.0));
	col = mix(col, belly_color, belly * (1.0 - smoothstep(-0.8, -0.25, wn.y)));
	ALBEDO = col * (0.85 + 0.3 * n);
	ROUGHNESS = gloss;
	SPECULAR = 0.6;

	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = rim_color * fr * rim * (0.6 + 0.3 * heat);
}
