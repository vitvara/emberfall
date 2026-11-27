shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

// Raid portal vortex: a spiral of molten fire and void-violet light sucked toward a dark eye.
// Drawn on a flat disc (UV 0..1); everything is computed in polar coordinates around the centre.
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
uniform vec3 rim_color = vec3(1.0, 0.45, 0.08);
uniform vec3 core_color = vec3(0.55, 0.15, 1.0);
uniform float intensity = 1.3;
uniform float spin = 0.35;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	float a = atan(p.y, p.x) / 6.2831853;
	// Spiral arms: the angle twists with depth (log radius) and turns over time.
	float twist = a + log(r + 0.04) * 0.55 + TIME * spin;
	float n1 = texture(noise, vec2(twist * 3.0, r * 1.2 - TIME * 0.35)).r;
	float n2 = texture(noise, vec2(twist * 5.0 + 0.37, r * 2.3 - TIME * 0.6)).r;
	float arms = smoothstep(0.35, 0.85, n1 * 0.65 + n2 * 0.45);
	float streaks = pow(0.5 + 0.5 * sin((twist * 9.0 + n2 * 1.5) * 6.2831853), 6.0);
	vec3 col = mix(core_color, rim_color, smoothstep(0.15, 0.95, r));
	float rim = smoothstep(0.75, 0.97, r) * (1.0 - smoothstep(0.97, 1.0, r));
	float eye = 1.0 - smoothstep(0.0, 0.28, r);  // dark centre the light pours into
	float glow = arms * 0.9 + streaks * 0.5 + rim * 0.7;
	glow *= (1.0 - eye * 0.85);
	float edge = 1.0 - smoothstep(0.9, 1.0, r);
	ALBEDO = col * glow * intensity * edge + rim_color * rim * 0.45;
}
