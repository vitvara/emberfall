shader_type spatial;
render_mode unshaded, cull_disabled;

// Flowing lava: two scrolling noise layers mixed into crust / molten / white-hot.
uniform sampler2D noise_a : repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_b : repeat_enable, filter_linear_mipmap;
uniform float tiling = 10.0;
uniform float brightness = 1.35;

void fragment() {
	vec2 uv = UV * tiling;
	float a = texture(noise_a, uv + vec2(TIME * 0.012, TIME * 0.008)).r;
	float b = texture(noise_b, uv * 1.6 - vec2(TIME * 0.02, -TIME * 0.006)).r;
	float n = a * 0.6 + b * 0.4;
	float pulse = 0.5 + 0.5 * sin(TIME * 0.7 + n * 6.0);
	vec3 crust = vec3(0.12, 0.025, 0.015);
	vec3 molten = vec3(1.0, 0.28, 0.03);
	vec3 hot = vec3(1.0, 0.8, 0.35);
	vec3 col = mix(crust, molten, smoothstep(0.42, 0.62, n));
	col = mix(col, hot, smoothstep(0.7, 0.88, n) * (0.6 + 0.4 * pulse));
	ALBEDO = col * brightness;
}
