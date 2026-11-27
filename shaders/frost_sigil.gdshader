shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Frost sigil: thin glowing lines with soft bloom, six triangle panels with zigzag runes,
// hooked blades on the rim, crackling energy rays and a flaring core, over faint streaky frost.
uniform vec4 color : source_color = vec4(0.35, 0.7, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float spin = 0.12;

float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float noise1(float x) { float i = floor(x); float f = fract(x); return mix(h1(i), h1(i + 1.0), smoothstep(0.0, 1.0, f)); }

float sd_tri(vec2 p, vec2 a, vec2 b, vec2 c) {
	vec2 e0 = b - a, e1 = c - b, e2 = a - c;
	vec2 v0 = p - a, v1 = p - b, v2 = p - c;
	vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
	vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
	vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
	float s = sign(e0.x * e2.y - e0.y * e2.x);
	vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
		vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
		vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
	return -sqrt(d.x) * sign(d.y);
}

// Thin bright core + wide soft glow for a distance d
vec2 glow_line(float d, float core_w, float glow_w) {
	float ad = abs(d);
	return vec2(1.0 - smoothstep(0.0, core_w, ad), exp(-ad / glow_w));
}

void fragment() {
	vec2 p0 = UV * 2.0 - 1.0;
	float t = TIME * spin;
	vec2 p = vec2(p0.x * cos(t) - p0.y * sin(t), p0.x * sin(t) + p0.y * cos(t));
	float r = length(p);
	float a = atan(p.y, p.x);
	float N = 6.0;
	float seg = 6.28318 / N;
	float sa = mod(a + seg * 0.5, seg) - seg * 0.5;
	vec2 q = vec2(cos(sa), sin(sa)) * r;            // sector-local: x = radial, y = tangential
	float sb = mod(a, seg) - seg * 0.5;
	vec2 qb = vec2(cos(sb), sin(sb)) * r;           // sector boundary frame

	float core = 0.0;
	float glow = 0.0;
	vec2 g;
	// Triangle panel pointing outward + inner inverted triangle
	g = glow_line(sd_tri(q, vec2(0.44, -0.2), vec2(0.44, 0.2), vec2(0.8, 0.0)), 0.007, 0.025);
	core = max(core, g.x); glow += g.y * 0.5;
	g = glow_line(sd_tri(q, vec2(0.66, -0.07), vec2(0.66, 0.07), vec2(0.52, 0.0)), 0.006, 0.02);
	core = max(core, g.x * 0.9); glow += g.y * 0.35;
	// Zigzag rune inside the panel
	if (q.x > 0.49 && q.x < 0.62) {
		float zig = (abs(fract(q.x * 22.0) - 0.5) - 0.25) * 0.05 + 0.1;
		g = glow_line(q.y - zig, 0.005, 0.015);
		core = max(core, g.x * 0.8); glow += g.y * 0.25;
		g = glow_line(q.y + zig, 0.005, 0.015);
		core = max(core, g.x * 0.8); glow += g.y * 0.25;
	}
	// Hooked blades on the rim, between panels
	float hook = length(qb - vec2(1.02, 0.0)) - 0.3;
	if (qb.x > 0.72 && r < 1.0) {
		g = glow_line(hook, 0.007, 0.03);
		core = max(core, g.x); glow += g.y * 0.6;
	}
	float hook2 = length(q - vec2(1.12, 0.0)) - 0.24;
	if (q.x > 0.86 && r < 1.0) {
		g = glow_line(hook2, 0.006, 0.025);
		core = max(core, g.x * 0.8); glow += g.y * 0.4;
	}
	// Crackling energy rays from the centre (between panels)
	vec2 dirv = vec2(cos(seg * 0.5), sin(seg * 0.5));
	float along = dot(qb, vec2(1.0, 0.0));
	float jag = (noise1(along * 18.0 + floor(TIME * 14.0) * 3.1) - 0.5) * 0.06 * along;
	if (along > 0.04 && along < 0.5) {
		g = glow_line(qb.y - jag, 0.006 * (1.2 - along * 1.6), 0.03);
		float flick = 0.7 + 0.3 * noise1(TIME * 20.0 + floor(a / seg) * 7.0);
		core = max(core, g.x * flick); glow += g.y * 0.8 * flick;
	}
	// Flaring core
	float flare = exp(-r * 14.0) * 2.5 + exp(-r * 5.0) * 0.5;
	// Faint streaky frost floor
	float s1 = a / 6.28318 * 50.0;
	float streak = mix(h1(floor(s1)), h1(floor(s1) + 1.0), smoothstep(0.0, 1.0, fract(s1)));
	float floor_frost = streak * smoothstep(0.1, 0.9, r) * (1.0 - smoothstep(0.9, 1.0, r)) * 0.12;
	float fade = 1.0 - smoothstep(0.98, 1.04, r);
	vec3 col = color.rgb * (glow * 1.4 + floor_frost * 2.0) + mix(color.rgb, vec3(1.0), 0.75) * (core * 2.4 + flare);
	ALBEDO = col * intensity * fade;
	ALPHA = clamp((core + glow * 0.5 + flare * 0.5 + floor_frost) * intensity * fade, 0.0, 1.0);
}
