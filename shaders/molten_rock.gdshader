shader_type spatial;
render_mode diffuse_toon, specular_toon;

// Meteor boulder: dark basalt split by glowing lava cracks (cell borders sampled on three planes).
uniform sampler2D cell_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float heat = 1.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 p = lp * 0.35;
	vec3 w = abs(normalize(lp));
	w /= (w.x + w.y + w.z);
	float c = texture(cell_tex, p.yz).r * w.x + texture(cell_tex, p.zx + 0.31).r * w.y + texture(cell_tex, p.xy + 0.67).r * w.z;
	float crack = 1.0 - smoothstep(0.02, 0.1, c);
	float n = texture(noise_tex, p.xz * 0.7 + p.y * 0.3).r;
	ALBEDO = mix(vec3(0.09, 0.06, 0.05), vec3(0.2, 0.13, 0.1), n);
	ROUGHNESS = 0.95;
	EMISSION = vec3(1.0, 0.38, 0.06) * crack * 4.0 * heat + vec3(0.25, 0.05, 0.01) * heat * (1.0 - n) * 0.5;
}
