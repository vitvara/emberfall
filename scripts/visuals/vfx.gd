class_name Vfx
extends RefCounted
## Reusable visual effects built from particles and simple meshes.
## Everything here is cosmetic — gameplay never depends on it.

static var _soft_tex: Texture2D
static var _ring_tex: Texture2D
static var _star_tex: Texture2D
static var _rune_tex: Texture2D
static var _crack_tex: Texture2D
static var _shield_shader: Shader
static var _swoosh_shader: Shader
static var _circle_shader: Shader
static var _disc_shader: Shader
static var _crystal_mesh: ArrayMesh
static var _sigil_shader: Shader
static var _ice_mat: StandardMaterial3D
static var _holy_mat: StandardMaterial3D
static var _shaft_tex: Texture2D
static var _swoosh_meshes := {}
static var _noise_tex: Texture2D
static var _cell_tex: Texture2D
static var _flame_mat: ShaderMaterial
static var _smoke_mat: ShaderMaterial
static var _flame_solid_mat: ShaderMaterial
static var _mats := {}


# ------------------------------------------------------------------ textures & materials

static func soft_tex() -> Texture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.3, Color(1, 1, 1, 0.75))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft_tex = t
	return _soft_tex


## Radial texture: faint fill with a bright rim — used for ground telegraphs.
static func ring_tex() -> Texture2D:
	if _ring_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.25))
		g.set_color(1, Color(1, 1, 1, 0.0))
		g.add_point(0.86, Color(1, 1, 1, 0.4))
		g.add_point(0.95, Color(1, 1, 1, 1.0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_ring_tex = t
	return _ring_tex


## Four-point sparkle star.
static func star_tex() -> Texture2D:
	if _star_tex == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var dx := absf((x + 0.5) / n * 2.0 - 1.0)
				var dy := absf((y + 0.5) / n * 2.0 - 1.0)
				var r := sqrt(dx * dx + dy * dy)
				var a := exp(-r * 7.0) + exp(-dx * 38.0) * exp(-dy * 3.5) + exp(-dy * 38.0) * exp(-dx * 3.5)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
		img.generate_mipmaps()
		_star_tex = ImageTexture.create_from_image(img)
	return _star_tex


## Magic circle: double ring, tick marks, rune blocks and a hexagram.
static func rune_tex() -> Texture2D:
	if _rune_tex == null:
		var n := 384
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var tri := []
		for k in 6:
			var a0 := TAU * k / 6.0 + PI / 2.0
			var a1 := TAU * (k + 2) / 6.0 + PI / 2.0
			tri.append([Vector2(cos(a0), sin(a0)) * 0.62, Vector2(cos(a1), sin(a1)) * 0.62])
		for y in n:
			for x in n:
				var p := Vector2((x + 0.5) / n * 2.0 - 1.0, (y + 0.5) / n * 2.0 - 1.0)
				var r := p.length()
				var ang := fposmod(atan2(p.y, p.x), TAU)
				var v := 0.0
				v = maxf(v, 1.0 - absf(r - 0.95) / 0.018)
				v = maxf(v, 1.0 - absf(r - 0.80) / 0.012)
				v = maxf(v, 1.0 - absf(r - 0.62) / 0.01)
				if r > 0.82 and r < 0.93:
					var seg := fposmod(ang / TAU * 36.0, 1.0)
					var glyph := fposmod(floor(ang / TAU * 36.0) * 7.31, 1.0)
					if (r < 0.875 and glyph > 0.4) or (r >= 0.875 and glyph < 0.7):
						var gy := 1.0 - absf(fposmod(r, 0.055) / 0.055 - 0.5) * 2.0
						v = maxf(v, 0.7 * smoothstep(0.15, 0.35, seg) * (1.0 - smoothstep(0.65, 0.85, seg)) * clampf(gy * 2.0, 0.0, 1.0))
				if r > 0.62 and r < 0.8 and fposmod(ang / TAU * 72.0, 1.0) < 0.12:
					v = maxf(v, 0.6)
				for seg2 in tri:
					var a: Vector2 = seg2[0]
					var b: Vector2 = seg2[1]
					var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
					var d := p.distance_to(a + (b - a) * t)
					v = maxf(v, 1.0 - d / 0.012)
				if r > 1.0:
					v = 0.0
				img.set_pixel(x, y, Color(1, 1, 1, clampf(v, 0.0, 1.0)))
		img.generate_mipmaps()
		_rune_tex = ImageTexture.create_from_image(img)
	return _rune_tex


## Radial ground cracks for heavy landings.
static func crack_tex() -> Texture2D:
	if _crack_tex == null:
		var n := 128
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 9
		var segs := []
		for k in 9:
			var a := TAU * k / 9.0 + rng.randf_range(-0.2, 0.2)
			var p := Vector2.ZERO
			for j in 5:
				a += rng.randf_range(-0.5, 0.5)
				var q := p + Vector2(cos(a), sin(a)) * rng.randf_range(0.12, 0.22)
				segs.append([p, q, 1.0 - j * 0.15])
				p = q
		for y in n:
			for x in n:
				var pt := Vector2((x + 0.5) / n * 2.0 - 1.0, (y + 0.5) / n * 2.0 - 1.0)
				var v := 0.0
				for sg in segs:
					var a2: Vector2 = sg[0]
					var b2: Vector2 = sg[1]
					var t := clampf((pt - a2).dot(b2 - a2) / maxf(0.0001, (b2 - a2).length_squared()), 0.0, 1.0)
					var d := pt.distance_to(a2 + (b2 - a2) * t)
					v = maxf(v, (1.0 - d / (0.03 * float(sg[2]))) * float(sg[2]))
				v = maxf(v, 1.0 - pt.length() / 0.18)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(v, 0.0, 1.0)))
		_crack_tex = ImageTexture.create_from_image(img)
	return _crack_tex


static func tex(key: String) -> Texture2D:
	match key:
		"star":
			return star_tex()
		"rune":
			return rune_tex()
		"ring":
			return ring_tex()
	return soft_tex()


## Seamless fractal noise (flames, smoke, ground scorch).
static func noise_tex() -> Texture2D:
	if _noise_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.02
		n.fractal_octaves = 4
		var t := NoiseTexture2D.new()
		t.noise = n
		t.seamless = true
		t.width = 256
		t.height = 256
		t.generate_mipmaps = true
		_noise_tex = t
	return _noise_tex


## Cellular noise whose dark lines are the cell borders: cracks and fissures.
static func cell_tex() -> Texture2D:
	if _cell_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.frequency = 0.03
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
		var t := NoiseTexture2D.new()
		t.noise = n
		t.seamless = true
		t.width = 256
		t.height = 256
		t.generate_mipmaps = true
		_cell_tex = t
	return _cell_tex


## Licking-flame particle material (see shaders/flame.gdshader). Colour comes from the particle ramp.
static func flame_mat() -> ShaderMaterial:
	if _flame_mat == null:
		_flame_mat = ShaderMaterial.new()
		_flame_mat.shader = load("res://shaders/flame.gdshader")
		_flame_mat.set_shader_parameter("noise_tex", noise_tex())
	return _flame_mat


## Solid-blended flames for big dense fires (keeps their colour on a bright background).
static func flame_solid_mat() -> ShaderMaterial:
	if _flame_solid_mat == null:
		_flame_solid_mat = ShaderMaterial.new()
		_flame_solid_mat.shader = load("res://shaders/flame_solid.gdshader")
		_flame_solid_mat.set_shader_parameter("noise_tex", noise_tex())
	return _flame_solid_mat


## Billowing smoke / dust particle material.
static func smoke_mat() -> ShaderMaterial:
	if _smoke_mat == null:
		_smoke_mat = ShaderMaterial.new()
		_smoke_mat.shader = load("res://shaders/smoke.gdshader")
		_smoke_mat.set_shader_parameter("noise_tex", noise_tex())
	return _smoke_mat


static func particle_mat(additive := true, tex_key := "soft", billboard := true) -> StandardMaterial3D:
	var key := "p_%s_%s_%s" % [additive, tex_key, billboard]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex(tex_key)
	_mats[key] = m
	return m


static func shield_mat(c: Color, strength := 1.0) -> ShaderMaterial:
	if _shield_shader == null:
		_shield_shader = load("res://shaders/shield.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shield_shader
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("strength", strength)
	return m


static func glow_mat(c: Color, alpha := 0.8, additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	return m


static func ramp(colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offs.append(float(i) / maxf(1.0, colors.size() - 1.0))
		cols.append(colors[i])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	c.max_value = 3.0
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t


# ------------------------------------------------------------------ particle emitter

## Options: amount, lifetime, one_shot, explosiveness, local, direction, spread, vmin, vmax,
## gravity, damping, size, scale_min, scale_max, grow (bool), colors (Array), additive,
## sphere (radius), ring ([radius, inner]), box (Vector3 extents), tangential, orbit,
## shader ("flame" = licking fire tongues, "smoke" = billowing puffs), tall (flame height ratio), flat (XZ only)
static func emitter(o: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = o.get("amount", 32)
	p.lifetime = o.get("lifetime", 0.8)
	p.one_shot = o.get("one_shot", true)
	p.explosiveness = o.get("explosiveness", 0.92 if p.one_shot else 0.0)
	p.local_coords = o.get("local", false)
	p.randomness = 0.3
	p.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 50, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = o.get("direction", Vector3.UP)
	pm.spread = o.get("spread", 180.0)
	pm.initial_velocity_min = o.get("vmin", 1.0)
	pm.initial_velocity_max = o.get("vmax", 3.0)
	pm.gravity = o.get("gravity", Vector3.ZERO)
	pm.damping_min = o.get("damping", 0.0)
	pm.damping_max = o.get("damping", 0.0)
	pm.scale_min = o.get("scale_min", 0.6)
	pm.scale_max = o.get("scale_max", 1.2)
	if o.get("grow", false):
		pm.scale_curve = curve([Vector2(0, 0.4), Vector2(0.4, 1.0), Vector2(1, 1.3)])
	elif not o.get("const_scale", false):
		pm.scale_curve = curve([Vector2(0, 1.0), Vector2(1, 0.0)])
	pm.color_ramp = ramp(o.get("colors", [Color(1, 1, 1, 1), Color(1, 1, 1, 0)]))
	if o.has("tangential"):
		pm.tangential_accel_min = o["tangential"]
		pm.tangential_accel_max = o["tangential"]
	if o.has("radial"):
		pm.radial_accel_min = o["radial"]
		pm.radial_accel_max = o["radial"]
	if o.has("spin"):
		pm.angle_min = 0.0
		pm.angle_max = 360.0
		pm.angular_velocity_min = -float(o["spin"])
		pm.angular_velocity_max = float(o["spin"])
	if o.has("orbit"):
		pm.orbit_velocity_min = o["orbit"]
		pm.orbit_velocity_max = o["orbit"]
	if o.has("sphere"):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = o["sphere"]
	elif o.has("ring"):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = o["ring"][0]
		pm.emission_ring_inner_radius = o["ring"][1]
		pm.emission_ring_height = 0.1
	elif o.has("box"):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = o["box"]
	if o.get("flat", false):
		pm.flatness = 1.0
	p.process_material = pm
	var q := QuadMesh.new()
	var s: float = o.get("size", 0.5)
	var streak: bool = o.get("streak", false)
	if streak:
		# Long thin quads aligned to velocity (sparks, rain, speed lines)
		q.size = Vector2(s * 0.18, s * float(o.get("stretch", 3.0)))
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		q.material = particle_mat(o.get("additive", true), o.get("tex", "soft"), false)
	elif o.get("shader", "") in ["flame", "flame_solid"]:
		q.size = Vector2(s, s * float(o.get("tall", 1.4)))
		q.center_offset = Vector3(0, s * 0.25, 0)
		q.material = flame_mat() if o["shader"] == "flame" else flame_solid_mat()
	elif o.get("shader", "") == "smoke":
		q.size = Vector2(s, s)
		q.material = smoke_mat()
	else:
		q.size = Vector2(s, s)
		q.material = particle_mat(o.get("additive", true), o.get("tex", "soft"), true)
	p.draw_pass_1 = q
	p.emitting = true
	return p


## Spawns a one-shot burst into the world and frees it afterwards.
static func burst(parent: Node, pos: Vector3, o: Dictionary) -> GPUParticles3D:
	var p := emitter(o)
	parent.add_child(p)
	p.global_position = pos
	p.restart()
	_free_after(p, p.lifetime + 0.5)
	return p


static func _free_after(n: Node, t: float) -> void:
	n.get_tree().create_timer(t).timeout.connect(n.queue_free)


# ------------------------------------------------------------------ presets

static func chest(u: Unit) -> Vector3:
	return u.position + Vector3(0, u.chest_height, 0)


## Flare of licking flames (and a few sparks) at a point.
static func fire_burst(parent: Node, pos: Vector3, scale := 1.0) -> void:
	burst(parent, pos, {"amount": int(16 * scale) + 6, "lifetime": 0.75, "vmin": 1.5 * scale, "vmax": 4.5 * scale,
		"gravity": Vector3(0, 5, 0), "damping": 4.0, "size": 1.2 * scale, "grow": true, "shader": "flame",
		"sphere": 0.3 * scale, "scale_min": 0.7, "scale_max": 1.3,
		"colors": [Color(1, 0.85, 0.45, 1), Color(1, 0.5, 0.1, 1), Color(0.85, 0.2, 0.03, 0.8), Color(0.3, 0.05, 0.02, 0)]})
	burst(parent, pos, {"amount": int(14 * scale) + 4, "lifetime": 0.5, "vmin": 6.0 * scale, "vmax": 12.0 * scale,
		"gravity": Vector3(0, -12, 0), "size": 0.12, "colors": [Color(1, 0.9, 0.4), Color(1, 0.4, 0.1, 0)]})


static func smoke(parent: Node, pos: Vector3, scale := 1.0) -> void:
	burst(parent, pos, {"amount": int(10 * scale) + 4, "lifetime": 1.8, "vmin": 0.5, "vmax": 2.0 * scale,
		"gravity": Vector3(0, 1.5, 0), "damping": 1.0, "size": 2.0 * scale, "grow": true, "shader": "smoke",
		"spin": 40.0, "sphere": 0.6 * scale,
		"colors": [Color(0.22, 0.17, 0.15, 0.75), Color(0.14, 0.11, 0.1, 0.5), Color(0.1, 0.08, 0.08, 0.0)]})


static func sparks(parent: Node, pos: Vector3, c: Color, count := 14) -> void:
	burst(parent, pos, {"amount": count, "lifetime": 0.4, "vmin": 5.0, "vmax": 11.0, "damping": 5.0,
		"gravity": Vector3(0, -9, 0), "size": 0.35, "streak": true, "stretch": 3.5,
		"colors": [Color(1, 1, 1, 1), c, Color(c.r, c.g, c.b, 0)]})
	star_flash(parent, pos, c, 1.3)


## Bright 4-point star that pops at an impact point.
static func star_flash(parent: Node, pos: Vector3, c: Color, size := 1.5) -> void:
	burst(parent, pos, {"amount": 2, "lifetime": 0.25, "vmin": 0.0, "vmax": 0.0, "size": size, "tex": "star",
		"spin": 90.0, "scale_min": 0.8, "scale_max": 1.2,
		"colors": [Color(1, 1, 1, 1), Color(c.r, c.g, c.b, 0.9), Color(c.r, c.g, c.b, 0)]})


static func sparkles(parent: Node, pos: Vector3, c: Color, radius := 0.6, count := 18) -> void:
	burst(parent, pos, {"amount": count, "lifetime": 1.1, "explosiveness": 0.4, "vmin": 0.6, "vmax": 1.6,
		"direction": Vector3.UP, "spread": 25.0, "sphere": radius, "size": 0.4, "tex": "star", "spin": 180.0,
		"colors": [Color(1, 1, 1, 1), c, Color(c.r, c.g, c.b, 0)]})


## A vertical beam of light that fades out (heals, holy effects).
static func light_column(parent: Node, pos: Vector3, c: Color, height := 4.0, radius := 0.6, dur := 0.7) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.6
	cm.bottom_radius = radius
	cm.height = height
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	var m := glow_mat(c, 0.55)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, height / 2.0, 0)
	mi.scale = Vector3(0.2, 1, 0.2)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(1, 1, 1), dur * 0.25)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, dur).set_delay(dur * 0.2)
	tw.tween_callback(mi.queue_free)


## Expanding flat ring on the ground.
static func shockwave(parent: Node, pos: Vector3, c: Color, radius := 6.0, dur := 0.5, height := 0.15) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	mi.mesh = pm
	var m := glow_mat(c, 1.0)
	m.albedo_texture = ring_tex()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = Vector3(pos.x, height, pos.z)
	mi.scale = Vector3(0.3, 1, 0.3)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(radius, 1, radius), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


## Translucent sphere that pops and fades (shields, impacts).
static func bubble_flash(parent: Node, pos: Vector3, c: Color, radius := 1.2, dur := 0.5) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	mi.mesh = sm
	var m := shield_mat(c, 1.5)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * radius * 0.5
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * radius, dur * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_method(func(v: float): m.set_shader_parameter("strength", v), 1.5, 0.0, dur)
	tw.tween_callback(mi.queue_free)


## Weapon swoosh in front of a unit. angle_z tilts the arc (0 = horizontal, ~1 = diagonal, PI/2 = vertical).
static func slash(parent: Node, u: Unit, c: Color, angle_z := 0.0, size := 1.3, flip := false, intensity := 1.0) -> void:
	swoosh(parent, chest(u) + u.forward() * 0.2, u.rotation.y, angle_z, c, size * 1.35, size * 0.6, 210.0, 0.3, flip,
		intensity)


## WoW-style crescent swoosh. The head sweeps across `span_deg` in `dur` seconds and leaves a fading tail.
static func swoosh(parent: Node, center: Vector3, yaw: float, tilt: float, c: Color, radius := 1.8,
		width := 0.8, span_deg := 210.0, dur := 0.3, flip := false, intensity := 1.0) -> void:
	if _swoosh_shader == null:
		_swoosh_shader = load("res://shaders/swoosh.gdshader")
	var pivot := Node3D.new()
	parent.add_child(pivot)
	pivot.global_position = center
	pivot.rotation = Vector3(0, yaw, 0)
	var tilt_node := Node3D.new()
	tilt_node.rotation.z = tilt
	if flip:
		tilt_node.scale.x = -1.0
	pivot.add_child(tilt_node)
	var mi := MeshInstance3D.new()
	radius *= 1.25
	width *= 1.3
	intensity *= 1.35
	mi.mesh = _swoosh_mesh(span_deg, clampf(width / radius, 0.15, 0.6))
	mi.scale = Vector3(radius, 1, radius)
	var m := ShaderMaterial.new()
	m.shader = _swoosh_shader
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("progress", 0.0)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("tail", 0.7)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tilt_node.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("progress", v), 0.0, 1.7, dur * 1.9)
	tw.parallel().tween_method(func(v: float): m.set_shader_parameter("intensity", v), intensity, 0.0, dur * 0.9) \
		.set_delay(dur * 1.0)
	tw.tween_callback(pivot.queue_free)


## Unit-radius arc band in the XZ plane, centred on -Z. UV.x runs along the sweep, UV.y inner->outer.
static func _swoosh_mesh(span_deg: float, thickness: float) -> ArrayMesh:
	var key := "%d_%d" % [int(span_deg), int(thickness * 100)]
	if _swoosh_meshes.has(key):
		return _swoosh_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 40
	var span := deg_to_rad(span_deg)
	for i in segs:
		var f0 := float(i) / segs
		var f1 := float(i + 1) / segs
		var a0 := span / 2.0 - span * f0
		var a1 := span / 2.0 - span * f1
		# Crescent: thick in the middle, pointed at both ends
		var w0 := 1.0 - thickness * pow(sin(f0 * PI), 0.7)
		var w1 := 1.0 - thickness * pow(sin(f1 * PI), 0.7)
		var o0 := Vector3(-sin(a0), 0, -cos(a0))
		var o1 := Vector3(-sin(a1), 0, -cos(a1))
		var verts := [[o0 * w0, Vector2(f0, 0)], [o0, Vector2(f0, 1)], [o1, Vector2(f1, 1)],
			[o0 * w0, Vector2(f0, 0)], [o1, Vector2(f1, 1)], [o1 * w1, Vector2(f1, 0)]]
		for v in verts:
			st.set_uv(v[1])
			st.add_vertex(v[0])
	var mesh := st.commit()
	_swoosh_meshes[key] = mesh
	return mesh


static func lightning(parent: Node, a: Vector3, b: Vector3, c: Color, dur := 0.4, w := 0.18) -> void:
	if parent is Node3D and (parent as Node3D).is_inside_tree():
		a = (parent as Node3D).to_global(a)  # the bolt is drawn in world space (the Outpost sits off-origin)
		b = (parent as Node3D).to_global(b)
	var l := LightningBolt.new().setup(a, b, c, dur, w)
	parent.add_child(l)
	sparks(parent, b, c, 14)


## Electric crackle around a point (stuns, interrupts).
static func crackle(parent: Node, pos: Vector3, c: Color, radius := 0.9, bolts := 4) -> void:
	for i in bolts:
		var d := Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized()
		var d2 := Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized()
		lightning(parent, pos + d * radius * 0.3, pos + d2 * radius, c, 0.3, 0.08)


## Big layered fire explosion (flash, billowing flames, flame tongues, dark embers, smoke).
static func fire_explosion(parent: Node, pos: Vector3, scale := 1.0) -> void:
	star_flash(parent, pos, Color(1, 0.6, 0.2), 3.0 * scale)
	burst(parent, pos, {"amount": int(26 * scale) + 10, "lifetime": 0.7, "vmin": 1.5 * scale, "vmax": 5.5 * scale,
		"gravity": Vector3(0, 5, 0), "damping": 3.0, "size": 1.6 * scale, "grow": true, "sphere": 0.4 * scale,
		"shader": "flame", "colors": [Color(1, 0.9, 0.6, 1), Color(1, 0.6, 0.15, 1), Color(0.9, 0.22, 0.03, 0.85),
			Color(0.25, 0.05, 0.02, 0)]})
	burst(parent, pos, {"amount": int(18 * scale) + 6, "lifetime": 0.45, "vmin": 5.0 * scale, "vmax": 10.0 * scale,
		"direction": Vector3.UP, "spread": 70.0, "size": 0.9 * scale, "streak": true, "stretch": 2.5,
		"colors": [Color(1, 0.9, 0.5, 1), Color(1, 0.45, 0.08, 0.9), Color(0.6, 0.1, 0, 0)]})
	burst(parent, pos, {"amount": int(22 * scale) + 6, "lifetime": 1.0, "vmin": 3.0 * scale, "vmax": 7.0 * scale,
		"direction": Vector3.UP, "spread": 80.0, "gravity": Vector3(0, -9, 0), "size": 0.22 * scale,
		"additive": false, "colors": [Color(0.95, 0.25, 0.05, 1), Color(0.45, 0.06, 0.03, 1), Color(0.1, 0.02, 0.02, 0)]})
	smoke(parent, pos + Vector3(0, 0.4, 0), 1.2 * scale)
	flash_light(parent, pos, Color(1, 0.5, 0.2), 5.0 * scale, 8.0 * scale, 0.45)


static func _arc_mesh(r: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 14
	var span := 1.6
	for i in segs:
		var a0 := -span / 2.0 + span * i / segs
		var a1 := -span / 2.0 + span * (i + 1) / segs
		var f0 := float(i) / segs
		var f1 := float(i + 1) / segs
		var w0 := width * sin(f0 * PI)
		var w1 := width * sin(f1 * PI)
		var o0 := Vector3(-sin(a0) * r, 0, -cos(a0) * r)
		var o1 := Vector3(-sin(a1) * r, 0, -cos(a1) * r)
		var i0 := Vector3(-sin(a0) * (r - w0), 0, -cos(a0) * (r - w0))
		var i1 := Vector3(-sin(a1) * (r - w1), 0, -cos(a1) * (r - w1))
		st.set_color(Color(1, 1, 1, f0))
		st.add_vertex(o0)
		st.set_color(Color(1, 1, 1, f1))
		st.add_vertex(o1)
		st.set_color(Color(1, 1, 1, f0 * 0.3))
		st.add_vertex(i0)
		st.set_color(Color(1, 1, 1, f1))
		st.add_vertex(o1)
		st.set_color(Color(1, 1, 1, f1 * 0.3))
		st.add_vertex(i1)
		st.set_color(Color(1, 1, 1, f0 * 0.3))
		st.add_vertex(i0)
	return st.commit()


static func flash_light(parent: Node, pos: Vector3, c: Color, energy := 4.0, rng := 10.0, dur := 0.4) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	parent.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur)
	tw.tween_callback(l.queue_free)


static func explosion(parent: Node, pos: Vector3, radius := 4.0) -> void:
	var s := radius / 4.0
	fire_burst(parent, pos + Vector3(0, 0.5, 0), 1.6 * s)
	smoke(parent, pos + Vector3(0, 1.0, 0), 1.4 * s)
	shockwave(parent, pos, Color(1, 0.5, 0.15), radius * 1.2, 0.45)
	flash_light(parent, pos + Vector3(0, 2, 0), Color(1, 0.5, 0.2), 6.0, radius * 3.0, 0.5)


## Fiery stream from a node (dragon mouth). Lives `dur` seconds.
static func breath_stream(mouth: Node3D, dur := 1.3) -> void:
	var p := emitter({"amount": 260, "lifetime": 1.15, "one_shot": false, "vmin": 28.0, "vmax": 36.0,
		"direction": Vector3(0, -0.12, -1), "spread": 8.0, "damping": 4.0, "gravity": Vector3(0, 0.8, 0),
		"size": 2.4, "grow": true, "scale_min": 0.9, "scale_max": 2.2, "shader": "flame_solid", "tall": 1.1,
		"colors": [Color(1, 0.62, 0.25, 0.8), Color(1, 0.38, 0.06, 1), Color(0.85, 0.15, 0.02, 0.9),
			Color(0.4, 0.06, 0.02, 0.5), Color(0.1, 0.05, 0.05, 0)]})
	var sm := emitter({"amount": 60, "lifetime": 1.6, "one_shot": false, "vmin": 14.0, "vmax": 20.0,
		"direction": Vector3(0, 0, -1), "spread": 14.0, "damping": 2.5, "gravity": Vector3(0, 2.5, 0),
		"size": 3.0, "grow": true, "shader": "smoke", "spin": 30.0,
		"colors": [Color(0.15, 0.1, 0.09, 0.0), Color(0.15, 0.1, 0.09, 0.45), Color(0.1, 0.08, 0.08, 0.0)]})
	mouth.add_child(sm)
	var tws := sm.create_tween()
	tws.tween_interval(dur)
	tws.tween_callback(func(): sm.emitting = false)
	tws.tween_interval(2.0)
	tws.tween_callback(sm.queue_free)
	mouth.add_child(p)
	var tw := p.create_tween()
	tw.tween_interval(dur)
	tw.tween_callback(func(): p.emitting = false)
	tw.tween_interval(1.2)
	tw.tween_callback(p.queue_free)


## Persistent flames for a lingering fire pool.
static func pool_flames(h: Node3D, radius: float) -> GPUParticles3D:
	var p := emitter({"amount": int(radius * radius * 2.2) + 8, "lifetime": 0.9, "one_shot": false, "vmin": 0.6,
		"vmax": 1.6, "direction": Vector3.UP, "spread": 10.0, "ring": [radius * 0.85, 0.0], "size": 1.3,
		"scale_min": 0.6, "scale_max": 1.4, "gravity": Vector3(0, 1.5, 0), "grow": true, "shader": "flame_solid",
		"local": true, "colors": [Color(1, 0.8, 0.4, 0.0), Color(1, 0.5, 0.08, 1.0), Color(0.85, 0.18, 0.02, 0.7),
			Color(0.2, 0.05, 0.02, 0)]})
	h.add_child(p)
	return p


## Continuous aura emitter that follows a unit (buffs).
static func aura_emitter(c: Color, radius := 0.6, upward := 1.5) -> GPUParticles3D:
	return emitter({"amount": 22, "lifetime": 1.1, "one_shot": false, "vmin": upward * 0.6, "vmax": upward,
		"direction": Vector3.UP, "spread": 10.0, "ring": [radius, radius * 0.7], "tangential": 4.0, "size": 0.3,
		"tex": "star", "spin": 200.0,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(c.r, c.g, c.b, 0.8), Color(c.r, c.g, c.b, 0)]})


static func embers_ambient(parent: Node, radius: float) -> void:
	var p := emitter({"amount": 160, "lifetime": 7.0, "one_shot": false, "vmin": 0.3, "vmax": 1.2,
		"direction": Vector3.UP, "spread": 30.0, "box": Vector3(radius, 0.5, radius), "size": 0.14,
		"gravity": Vector3(0.2, 0.5, 0.1), "tangential": 0.2,
		"colors": [Color(1, 0.6, 0.2, 0), Color(1, 0.55, 0.15, 1), Color(1, 0.3, 0.05, 0.8), Color(1, 0.2, 0, 0)]})
	parent.add_child(p)
	p.position = Vector3(0, 0, 0)
	p.preprocess = 5.0


## Flat magic circle on the ground (casting, zones, reticle). Returns the node; spins via tween if dur > 0.
static func rune_decal(c: Color, radius: float, alpha := 0.9) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = pm
	var m := glow_mat(c, alpha)
	m.albedo_texture = rune_tex()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Rune circle that flares up under a point and fades (spell landing, buffs).
static func rune_flash(parent: Node, pos: Vector3, c: Color, radius := 2.0, dur := 0.8) -> void:
	var mi := rune_decal(c, radius, 1.0)
	parent.add_child(mi)
	mi.global_position = Vector3(pos.x, 0.08, pos.z)
	mi.scale = Vector3(0.6, 1, 0.6)
	var m := mi.material_override as StandardMaterial3D
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, dur * 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(mi, "rotation:y", 1.5, dur)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, dur * 0.6).set_delay(dur * 0.4)
	tw.tween_callback(mi.queue_free)


## Cracked ground that glows then fades (leaps, slams, meteors).
static func ground_crack(parent: Node, pos: Vector3, c: Color, radius := 4.0, dur := 2.5) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = pm
	var m := glow_mat(c, 1.0)
	m.albedo_texture = crack_tex()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = Vector3(pos.x, 0.07, pos.z)
	mi.rotation.y = randf() * TAU
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


## Rocks and dust thrown up by a heavy impact.
static func debris(parent: Node, pos: Vector3, scale := 1.0) -> void:
	burst(parent, pos + Vector3(0, 0.2, 0), {"amount": int(16 * scale), "lifetime": 0.9, "vmin": 4.0 * scale,
		"vmax": 9.0 * scale, "direction": Vector3.UP, "spread": 55.0, "gravity": Vector3(0, -18, 0),
		"size": 0.28, "additive": false, "spin": 400.0,
		"colors": [Color(0.3, 0.24, 0.2, 1), Color(0.2, 0.15, 0.12, 1), Color(0.15, 0.1, 0.1, 0)]})


## Particles that spiral into a point (spell gathering in the hands).
static func gather_emitter(c: Color) -> GPUParticles3D:
	return emitter({"amount": 26, "lifetime": 0.55, "one_shot": false, "vmin": 0.0, "vmax": 0.3,
		"sphere": 0.7, "radial": -9.0, "tangential": 6.0, "size": 0.18, "local": true,
		"colors": [Color(c.r, c.g, c.b, 0), Color(c.r, c.g, c.b, 1), Color(1, 1, 1, 1)]})


## Speed lines / dust behind a charging unit.
static func speed_trail(parent: Node, pos: Vector3, dir: Vector3, c: Color) -> void:
	burst(parent, pos + Vector3(0, 1.0, 0), {"amount": 22, "lifetime": 0.35, "vmin": 6.0, "vmax": 12.0,
		"direction": -dir, "spread": 12.0, "box": Vector3(0.4, 0.6, 0.4), "size": 0.5, "streak": true,
		"stretch": 5.0, "colors": [Color(1, 1, 1, 0.8), Color(c.r, c.g, c.b, 0.5), Color(c.r, c.g, c.b, 0)]})


# ------------------------------------------------------------------ shader decals

## Ornate glowing spell circle on the ground (casting, ground skills).
static func magic_circle(c: Color, radius: float, intensity := 1.0, spin := 0.35) -> MeshInstance3D:
	if _circle_shader == null:
		_circle_shader = load("res://shaders/magic_circle.gdshader")
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = _circle_shader
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("spin", spin)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Radial streak disc with a crisp rim (frost nova, blizzard ground, poison pool).
static func radial_disc(c: Color, radius: float, intensity := 1.0, flow := 4.0) -> MeshInstance3D:
	if _disc_shader == null:
		_disc_shader = load("res://shaders/radial_disc.gdshader")
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = _disc_shader
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("flow_speed", flow)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A disc that blooms outward and fades (frost nova style).
static func nova(parent: Node, pos: Vector3, c: Color, radius := 3.0, dur := 0.6) -> void:
	var mi := radial_disc(c, 1.0, 1.4)
	parent.add_child(mi)
	mi.global_position = Vector3(pos.x, 0.08, pos.z)
	mi.scale = Vector3(radius * 0.3, 1, radius * 0.3)
	var m := mi.material_override as ShaderMaterial
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(radius, 1, radius), dur * 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_method(func(v: float): m.set_shader_parameter("intensity", v), 1.4, 0.0, dur).set_delay(dur * 0.2)
	tw.tween_callback(mi.queue_free)


# ------------------------------------------------------------------ ice

## Glowing ice crystal with a fading comet tail. +Y is the direction of travel.
static func crystal_mesh() -> ArrayMesh:
	if _crystal_mesh != null:
		return _crystal_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 6
	var tip := Vector3(0, 0.55, 0)
	var back := Vector3(0, -0.35, 0)
	var head_c := Color(0.95, 1.0, 1.0, 1.0)
	var body_c := Color(0.55, 0.8, 1.0, 0.9)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0) * 0.13, 0, sin(a0) * 0.13)
		var p1 := Vector3(cos(a1) * 0.13, 0, sin(a1) * 0.13)
		for tri in [[tip, p0, p1], [back, p1, p0]]:
			st.set_color(head_c)
			st.add_vertex(tri[0])
			st.set_color(body_c)
			st.add_vertex(tri[1])
			st.add_vertex(tri[2])
	# Crossed tail planes fading out behind the crystal
	for k in 2:
		var side := Vector3(0.11, 0, 0) if k == 0 else Vector3(0, 0, 0.11)
		var y0 := -0.15
		var y1 := -2.6
		var c0 := Color(0.7, 0.9, 1.0, 0.75)
		var c1 := Color(0.3, 0.55, 1.0, 0.0)
		var quad := [[Vector3(0, y0, 0) - side, c0], [Vector3(0, y0, 0) + side, c0], [Vector3(0, y1, 0) + side * 0.3, c1],
			[Vector3(0, y0, 0) - side, c0], [Vector3(0, y1, 0) + side * 0.3, c1], [Vector3(0, y1, 0) - side * 0.3, c1]]
		for q in quad:
			st.set_color(q[1])
			st.add_vertex(q[0])
	_crystal_mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.4, 1.5, 1.7, 1.0)
	_crystal_mesh.surface_set_material(0, m)
	return _crystal_mesh


## Mesh particles flying along their velocity (ice shards).
static func shard_emitter(o: Dictionary) -> GPUParticles3D:
	var p := emitter(o)
	p.draw_pass_1 = crystal_mesh()
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY
	return p


## Splash of ice sparkles and snow (shard impacts).
static func ice_splash_emitter(per_hit := 6) -> GPUParticles3D:
	var p := emitter({"amount": 160, "lifetime": 0.45, "one_shot": false, "vmin": 1.5, "vmax": 4.5,
		"direction": Vector3.UP, "spread": 75.0, "gravity": Vector3(0, -9, 0), "size": 0.32, "tex": "star",
		"spin": 300.0, "colors": [Color(1, 1, 1, 1), Color(0.6, 0.85, 1, 0.9), Color(0.4, 0.6, 1, 0)]})
	p.emitting = false
	p.set_meta("per_hit", per_hit)
	return p


## Burst of ice: star flash, shards flying outward, snow, a frost nova on the ground.
static func ice_burst(parent: Node, pos: Vector3, scale := 1.0) -> void:
	star_flash(parent, pos, Color(0.7, 0.9, 1), 2.8 * scale)
	var p := shard_emitter({"amount": int(10 * scale) + 4, "lifetime": 0.35, "vmin": 6.0 * scale, "vmax": 11.0 * scale,
		"spread": 180.0, "damping": 14.0, "size": 0.5, "scale_min": 0.35 * scale, "scale_max": 0.6 * scale})
	parent.add_child(p)
	p.global_position = pos
	p.restart()
	_free_after(p, 1.0)
	burst(parent, pos, {"amount": int(18 * scale), "lifetime": 0.9, "vmin": 1.0, "vmax": 4.0 * scale,
		"gravity": Vector3(0, -3, 0), "damping": 2.0, "size": 0.3, "tex": "star", "spin": 300.0,
		"colors": [Color(1, 1, 1, 1), Color(0.65, 0.88, 1, 0.8), Color(0.5, 0.7, 1, 0)]})
	burst(parent, pos, {"amount": 10, "lifetime": 1.0, "vmin": 0.5, "vmax": 1.5, "size": 1.4, "grow": true,
		"colors": [Color(0.75, 0.9, 1, 0.35), Color(0.6, 0.8, 1, 0)]})
	ice_spikes(parent, Vector3(pos.x, 0, pos.z), 0.7 * scale, 0.5)
	flash_light(parent, pos, Color(0.6, 0.85, 1), 3.0, 7.0, 0.35)


# ------------------------------------------------------------------ rogue

## Thin, bright X-shaped slash flash on a target (dagger strikes).
static func x_slash(parent: Node, pos: Vector3, c: Color, size := 1.4, yaw := 0.0) -> void:
	for k in 2:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.09, size * 1.6)
		mi.mesh = q
		var m := glow_mat(Color(lerpf(c.r, 1.0, 0.4), lerpf(c.g, 1.0, 0.4), lerpf(c.b, 1.0, 0.4)), 1.0)
		m.albedo_texture = soft_tex()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		mi.global_position = pos
		mi.rotation.z = (0.75 if k == 0 else -0.75) + yaw
		mi.scale = Vector3(1, 0.1, 1)
		var tw := mi.create_tween()
		tw.tween_interval(0.05 * k)
		tw.tween_property(mi, "scale", Vector3(1.6, 1.0, 1), 0.08).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3(0.2, 1.15, 1), 0.2)
		tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.2)
		tw.tween_callback(mi.queue_free)


## Dark red droplets (bleed, finishers).
static func blood_spray(parent: Node, pos: Vector3, dir: Vector3, scale := 1.0) -> void:
	burst(parent, pos, {"amount": int(18 * scale), "lifetime": 0.6, "vmin": 3.0, "vmax": 7.0 * scale,
		"direction": dir, "spread": 35.0, "gravity": Vector3(0, -14, 0), "size": 0.16, "additive": false,
		"colors": [Color(0.85, 0.05, 0.05, 1), Color(0.5, 0.02, 0.02, 1), Color(0.3, 0.0, 0.0, 0)]})


## Green poison bubbles popping up from a point or area.
static func poison_emitter(radius: float) -> GPUParticles3D:
	return emitter({"amount": int(radius * radius * 2.5) + 6, "lifetime": 1.2, "one_shot": false, "vmin": 0.4,
		"vmax": 1.2, "direction": Vector3.UP, "spread": 10.0, "ring": [radius * 0.9, 0.0], "size": 0.35,
		"grow": true, "colors": [Color(0.5, 1, 0.3, 0), Color(0.55, 1, 0.35, 0.9), Color(0.3, 0.8, 0.2, 0)]})


# ------------------------------------------------------------------ objects (ice, holy, poison)

static func frost_sigil(c: Color, radius: float) -> MeshInstance3D:
	if _sigil_shader == null:
		_sigil_shader = load("res://shaders/frost_sigil.gdshader")
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = _sigil_shader
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("intensity", 0.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Solid, glassy ice (for spikes and shards that stay on the ground).
static func ice_mat() -> StandardMaterial3D:
	if _ice_mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.7, 0.88, 1.0, 0.78)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.emission_enabled = true
		m.emission = Color(0.35, 0.65, 1.0)
		m.emission_energy_multiplier = 1.6
		m.roughness = 0.08
		m.metallic = 0.3
		m.rim_enabled = true
		m.rim = 1.0
		m.rim_tint = 0.2
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ice_mat = m
	return _ice_mat


## Faceted crystal (bipyramid). Tall along +Y, base at y = 0.
static func crystal_solid_mesh(height: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 5
	var top := Vector3(0, height, 0)
	var bot := Vector3(0, -height * 0.15, 0)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0) * width, height * 0.35, sin(a0) * width)
		var p1 := Vector3(cos(a1) * width, height * 0.35, sin(a1) * width)
		st.add_vertex(top)
		st.add_vertex(p1)
		st.add_vertex(p0)
		st.add_vertex(bot)
		st.add_vertex(p0)
		st.add_vertex(p1)
	st.generate_normals()
	return st.commit()


## A cluster of ice spikes that bursts out of the ground, holds, then sinks away.
static func ice_spikes(parent: Node, pos: Vector3, scale := 1.0, hold := 0.8) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = Vector3(pos.x, 0.0, pos.z)
	root.rotation.y = randf() * TAU
	var count := randi_range(3, 5)
	for i in count:
		var mi := MeshInstance3D.new()
		mi.mesh = crystal_solid_mesh(randf_range(0.9, 1.8) * scale, randf_range(0.14, 0.26) * scale)
		mi.material_override = ice_mat()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ang := TAU * i / count + randf_range(-0.4, 0.4)
		mi.position = Vector3(cos(ang), 0, sin(ang)) * randf_range(0.05, 0.35) * scale
		mi.rotation = Vector3(randf_range(-0.5, 0.5), randf() * TAU, randf_range(-0.5, 0.5))
		root.add_child(mi)
	root.scale = Vector3(1, 0.01, 1)
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3(1, 1.1, 1), 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(root, "scale", Vector3.ONE, 0.08)
	tw.tween_interval(hold)
	tw.tween_property(root, "scale", Vector3(0.8, 0.01, 0.8), 0.35).set_ease(Tween.EASE_IN)
	tw.tween_callback(root.queue_free)


## A big glowing ice shard that streaks down from the sky and shatters at `land`.
static func ice_fall(parent: Node, land: Vector3, scale := 1.0, on_land := Callable()) -> void:
	var shard := Node3D.new()
	parent.add_child(shard)
	var dirv := Vector3(0.3, -1.0, 0.18).normalized()
	var height := 15.0
	var start := land - dirv * (height / -dirv.y)
	shard.global_position = start
	var head := MeshInstance3D.new()
	head.mesh = crystal_mesh()
	head.scale = Vector3.ONE * 2.6 * scale
	shard.add_child(head)
	# Orient +Y of the crystal along the fall direction
	shard.look_at(start + dirv, Vector3.FORWARD if absf(dirv.y) > 0.99 else Vector3.UP)
	head.rotation.x = -PI / 2.0
	var sparkle := emitter({"amount": 30, "lifetime": 0.5, "one_shot": false, "vmin": 0.2, "vmax": 1.0,
		"sphere": 0.25, "size": 0.35, "tex": "star", "spin": 300.0,
		"colors": [Color(1, 1, 1, 1), Color(0.6, 0.85, 1, 0.8), Color(0.4, 0.6, 1, 0)]})
	shard.add_child(sparkle)
	var dur := 0.34
	var tw := shard.create_tween()
	tw.tween_property(shard, "global_position", Vector3(land.x, 0.1, land.z), dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		head.visible = false
		sparkle.emitting = false
		ice_impact(parent, Vector3(land.x, 0.1, land.z), scale)
		if on_land.is_valid():
			on_land.call())
	tw.tween_interval(0.6)
	tw.tween_callback(shard.queue_free)


## Shard impact: white flash, splinters, a fountain of sparkles, frost puff and ice spikes.
static func ice_impact(parent: Node, pos: Vector3, scale := 1.0) -> void:
	star_flash(parent, pos + Vector3(0, 0.3, 0), Color(0.75, 0.92, 1), 3.2 * scale)
	burst(parent, pos + Vector3(0, 0.2, 0), {"amount": int(26 * scale), "lifetime": 0.6, "vmin": 2.5, "vmax": 7.0 * scale,
		"direction": Vector3.UP, "spread": 55.0, "gravity": Vector3(0, -12, 0), "size": 0.32, "tex": "star",
		"spin": 400.0, "colors": [Color(1, 1, 1, 1), Color(0.65, 0.88, 1, 0.9), Color(0.4, 0.6, 1, 0)]})
	var splinters := shard_emitter({"amount": 8, "lifetime": 0.35, "vmin": 5.0, "vmax": 9.0, "direction": Vector3.UP,
		"spread": 70.0, "damping": 10.0, "gravity": Vector3(0, -14, 0), "scale_min": 0.25 * scale, "scale_max": 0.45 * scale})
	parent.add_child(splinters)
	splinters.global_position = pos
	splinters.restart()
	_free_after(splinters, 1.0)
	burst(parent, pos + Vector3(0, 0.3, 0), {"amount": 6, "lifetime": 1.1, "vmin": 0.6, "vmax": 1.6, "size": 1.6,
		"grow": true, "colors": [Color(0.8, 0.92, 1, 0.35), Color(0.6, 0.8, 1, 0)]})
	ice_spikes(parent, pos, 0.75 * scale, 0.7)
	flash_light(parent, pos + Vector3(0, 1, 0), Color(0.55, 0.8, 1), 3.5, 7.0, 0.3)


## Glowing golden crystal (Sanctuary focus).
static func holy_mat() -> StandardMaterial3D:
	if _holy_mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1, 0.92, 0.6)
		m.emission_enabled = true
		m.emission = Color(1, 0.8, 0.35)
		m.emission_energy_multiplier = 3.0
		m.roughness = 0.1
		m.metallic = 0.4
		_holy_mat = m
	return _holy_mat


## A shaft of light from above that fades in and out.
static func light_shaft(parent: Node, pos: Vector3, c: Color, height := 9.0, width := 0.5, dur := 1.2) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = width * 1.6
	cm.bottom_radius = width
	cm.height = height
	cm.cap_top = false
	cm.cap_bottom = false
	cm.radial_segments = 12
	mi.mesh = cm
	var m := glow_mat(c, 0.0)
	if _shaft_tex == null:
		# Bright near the ground, fading out toward the sky
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 0.92, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.35), Color(1, 1, 1, 1), Color(1, 1, 1, 0.2)])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		gt.width = 4
		gt.height = 64
		_shaft_tex = gt
	m.albedo_texture = _shaft_tex
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, height / 2.0, 0)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.55, dur * 0.3)
	tw.tween_property(m, "albedo_color:a", 0.0, dur * 0.7)
	tw.tween_callback(mi.queue_free)


## Buff burst: a helix of sparkles spiralling up the body, plus motes and a soft flash. No circles.
static func buff_burst(parent: Node, u: Unit, c: Color, strength := 1.0) -> void:
	var p := emitter({"amount": int(40 * strength), "lifetime": 0.9, "explosiveness": 0.15, "vmin": 2.2, "vmax": 3.2,
		"direction": Vector3.UP, "spread": 4.0, "ring": [0.7, 0.6], "tangential": 9.0, "radial": -1.5,
		"size": 0.38, "tex": "star", "spin": 300.0,
		"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(c.r, c.g, c.b, 0.9), Color(c.r, c.g, c.b, 0)]})
	parent.add_child(p)
	p.global_position = u.position
	p.restart()
	_free_after(p, 1.6)
	burst(parent, chest(u), {"amount": int(16 * strength), "lifetime": 0.7, "vmin": 1.5, "vmax": 3.5, "size": 0.3,
		"damping": 3.0, "tex": "star", "spin": 300.0, "colors": [Color(1, 1, 1, 1), c, Color(c.r, c.g, c.b, 0)]})
	flash_light(parent, chest(u), c, 2.5 * strength, 5.0, 0.4)
