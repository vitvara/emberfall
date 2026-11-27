shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;

// Energy bubble: bright fresnel rim + drifting bands.
uniform vec4 color : source_color = vec4(0.5, 0.75, 1.0, 1.0);
uniform float strength = 1.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	float shimmer = 0.5 + 0.5 * sin(UV.y * 18.0 - TIME * 2.5);
	ALBEDO = mix(color.rgb, vec3(1.0), fres * 0.35) * (fres * 1.9 + 0.05 + shimmer * fres * 0.25) * strength;
	ALPHA = clamp(fres * 0.95 + 0.03, 0.0, 1.0) * strength;
}
