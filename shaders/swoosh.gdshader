shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Melee swoosh: a bright head sweeps along the arc (UV.x 0 -> 1) leaving a fading,
// streaky tail. UV.y runs from the inner edge (0) to the outer, white-hot edge (1).
uniform vec4 color : source_color = vec4(0.4, 0.6, 1.0, 1.0);
uniform float progress = 0.0;
uniform float tail = 0.6;
uniform float intensity = 1.0;

void fragment() {
	float d = progress - UV.x;
	float a = d < 0.0 ? 0.0 : 1.0 - smoothstep(0.0, tail, d);
	a *= smoothstep(-0.03, 0.03, d);
	float edge = pow(UV.y, 1.8);
	float streaks = 0.6 + 0.4 * sin(UV.y * 42.0 + UV.x * 9.0 - progress * 6.0);
	float core = smoothstep(0.78, 1.0, UV.y);
	vec3 col = mix(color.rgb, vec3(1.0, 0.98, 0.9), core * 0.85);
	float body = smoothstep(0.0, 0.25, UV.y);
	ALBEDO = col * intensity * (1.3 + edge * 2.2) * streaks;
	ALPHA = clamp(a * body * (0.5 + edge * 0.9) * intensity, 0.0, 1.0);
}
