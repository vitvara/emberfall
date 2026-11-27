class_name EnvKit
extends RefCounted
## Shared pieces for building maps: cracked volcanic stone, the lava sea, rocks and distant volcanoes.
## Used by the raid arena (main.gd) and the Outpost hub (hub_world.gd).

static var _stone: StandardMaterial3D
static var _lava: ShaderMaterial


## Cracked stone with glowing seams (world-space triplanar, so any mesh can use it).
static func stone_material() -> StandardMaterial3D:
	if _stone != null:
		return _stone
	var stone_noise := FastNoiseLite.new()
	stone_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	stone_noise.frequency = 0.035
	stone_noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	var stone_tex := NoiseTexture2D.new()
	stone_tex.noise = stone_noise
	stone_tex.seamless = true
	stone_tex.width = 512
	stone_tex.height = 512
	var stone_ramp := Gradient.new()
	stone_ramp.offsets = PackedFloat32Array([0.0, 0.55, 0.85, 1.0])
	stone_ramp.colors = PackedColorArray([Color(0.33, 0.29, 0.27), Color(0.27, 0.23, 0.22),
		Color(0.16, 0.13, 0.13), Color(0.05, 0.03, 0.03)])
	stone_tex.color_ramp = stone_ramp
	var normal_tex := NoiseTexture2D.new()
	normal_tex.noise = stone_noise
	normal_tex.seamless = true
	normal_tex.as_normal_map = true
	normal_tex.bump_strength = 6.0
	normal_tex.width = 512
	normal_tex.height = 512
	var crack_tex := NoiseTexture2D.new()
	crack_tex.noise = stone_noise
	crack_tex.seamless = true
	crack_tex.width = 512
	crack_tex.height = 512
	var crack_ramp := Gradient.new()
	crack_ramp.offsets = PackedFloat32Array([0.0, 0.9, 0.97, 1.0])
	crack_ramp.colors = PackedColorArray([Color(0, 0, 0), Color(0, 0, 0), Color(1.0, 0.35, 0.05), Color(1.0, 0.6, 0.2)])
	crack_tex.color_ramp = crack_ramp
	var m := StandardMaterial3D.new()
	m.albedo_texture = stone_tex
	m.normal_enabled = true
	m.normal_texture = normal_tex
	m.emission_enabled = true
	m.emission_texture = crack_tex
	m.emission_energy_multiplier = 1.4
	m.roughness = 0.9
	m.uv1_scale = Vector3(0.07, 0.07, 0.07)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	_stone = m
	return m


static func lava_material() -> ShaderMaterial:
	if _lava != null:
		return _lava
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/lava.gdshader")
	for k in 2:
		var n := FastNoiseLite.new()
		n.frequency = 0.012 if k == 0 else 0.02
		n.fractal_octaves = 4
		n.seed = 7 + k * 31
		var t := NoiseTexture2D.new()
		t.noise = n
		t.seamless = true
		t.width = 256
		t.height = 256
		t.generate_mipmaps = true
		m.set_shader_parameter("noise_a" if k == 0 else "noise_b", t)
	_lava = m
	return m


## A wide plane of animated lava just below ground level.
static func lava_sea(parent: Node3D, size := 400.0) -> void:
	var lava := PlaneMesh.new()
	lava.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = lava
	mi.material_override = lava_material()
	mi.position = Vector3(0, -1.6, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Low-poly boulders scattered in a ring between two distances.
static func rocks(parent: Node3D, rng: RandomNumberGenerator, count: int, d_min: float, d_max: float,
		s_min := 1.0, s_max := 4.0) -> void:
	var rock_m := Models.mat(Color(0.12, 0.1, 0.1), 0.0, 1.0)
	for i in count:
		var a := rng.randf() * TAU
		var d := rng.randf_range(d_min, d_max)
		var rs := rng.randf_range(s_min, s_max)
		var rock := SphereMesh.new()
		rock.radial_segments = 6
		rock.rings = 4
		rock.radius = rs
		rock.height = rs * 1.4
		Models.part(parent, rock, rock_m, Vector3(cos(a) * d, -1.2, sin(a) * d),
			Vector3(rng.randf(), rng.randf() * TAU, rng.randf()), Vector3(1.0, rng.randf_range(0.6, 1.6), 1.2))


## Smouldering volcanoes on the horizon.
static func volcanoes(parent: Node3D, rng: RandomNumberGenerator, count := 6, d_min := 140.0, d_max := 190.0) -> void:
	for i in count:
		var a := TAU * i / float(count) + 0.3
		var d := rng.randf_range(d_min, d_max)
		var hgt := rng.randf_range(45.0, 85.0)
		var cone := Models.cyl(hgt * 0.08, hgt * 0.75, hgt)
		cone.radial_segments = 12
		var vp := Vector3(cos(a) * d, hgt / 2.0 - 4.0, sin(a) * d)
		Models.part(parent, cone, Models.mat(Color(0.09, 0.05, 0.05), 0.0, 1.0), vp)
		Models.part(parent, Models.cyl(hgt * 0.07, hgt * 0.08, 0.5), Models.mat(Color(1.0, 0.4, 0.1), 4.0),
			vp + Vector3(0, hgt / 2.0, 0))


## A brazier on a pillar top (fire particles + warm light). `p` is the bowl position.
static func brazier(parent: Node3D, p: Vector3, scale := 1.0, light_range := 14.0) -> void:
	var gold := Models.mat(Color(0.6, 0.45, 0.2), 0.0, 0.5)
	Models.part(parent, Models.cyl(1.1 * scale, 0.6 * scale, 0.8 * scale), gold, p)
	var fire := Vfx.emitter({"amount": int(40 * scale), "lifetime": 0.9, "one_shot": false, "vmin": 1.5 * scale,
		"vmax": 3.0 * scale, "direction": Vector3.UP, "spread": 12.0, "sphere": 0.45 * scale, "size": 1.1 * scale,
		"grow": true, "colors": [Color(1, 0.9, 0.5, 1), Color(1, 0.45, 0.1, 0.9), Color(0.5, 0.1, 0.02, 0.4),
		Color(0.1, 0.05, 0.05, 0)]})
	fire.position = p + Vector3(0, 0.5 * scale, 0)
	parent.add_child(fire)
	var fl := OmniLight3D.new()
	fl.position = p + Vector3(0, 1.5 * scale, 0)
	fl.light_color = Color(1, 0.55, 0.2)
	fl.omni_range = light_range
	fl.light_energy = 1.2
	parent.add_child(fl)
