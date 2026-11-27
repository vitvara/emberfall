shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Radial streak disc with a crisp rim (frost nova / blizzard ground / poison pool).
uniform vec4 color : source_color = vec4(0.5, 0.75, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float flow_speed = 4.0;
uniform float spin = 0.15;

float h(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x) + TIME * spin;
	float s1 = a / 6.28318 * 46.0;
	float n1 = mix(h(floor(s1)), h(floor(s1) + 1.0), smoothstep(0.0, 1.0, fract(s1)));
	float s2 = a / 6.28318 * 17.0;
	float n2 = mix(h(floor(s2) + 7.0), h(floor(s2) + 8.0), smoothstep(0.0, 1.0, fract(s2)));
	float radial = smoothstep(0.1, 0.92, r) * (1.0 - smoothstep(0.96, 1.0, r));
	float rim = 1.0 - smoothstep(0.0, 0.035, abs(r - 0.965));
	float flow = 0.55 + 0.45 * sin(r * 22.0 - TIME * flow_speed + n1 * 5.0);
	float v = radial * (0.25 + 0.75 * n1 * n2) * flow + rim * 1.1;
	ALBEDO = mix(color.rgb, vec3(1.0), rim * 0.55 + radial * n1 * 0.15) * v * intensity * 1.6;
	ALPHA = clamp(v * intensity, 0.0, 1.0);
}
