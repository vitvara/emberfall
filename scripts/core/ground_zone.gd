class_name GroundZone
extends Node3D
## A player-placed area (Frost Storm, Poison Bomb, Sanctuary).
## Ticks its effect on enemies or allies standing inside.

var world  # RaidWorld
var caster: Unit
var kind := "frost"   # frost | poison | holy
var radius := 8.0
var duration := 8.0
var interval := 1.0
var hits := "enemies"  # enemies | allies
var effect := {}
var aura := ""
var label := ""
var done := false

var _t := 0.0
var _tick_t := 0.0
var _vis := false
var _decal: MeshInstance3D
var _glow_m: StandardMaterial3D
var _crystal: Node3D
var _spawn_every := 0.3
var _spawn_t := 0.0


func setup(w, src: Unit, spec: Dictionary, ability_name: String, r: float, at: Vector3) -> GroundZone:
	world = w
	caster = src
	kind = spec.get("kind", "frost")
	duration = spec.get("duration", 8.0)
	interval = spec.get("interval", 1.0)
	hits = spec.get("hits", "enemies")
	effect = spec.get("effect", {})
	aura = spec.get("aura", "")
	label = ability_name
	radius = r
	position = Vector3(at.x, 0.0, at.z)
	_tick_t = 0.3
	return self


func contains(p: Vector3) -> bool:
	return Vector2(p.x - position.x, p.z - position.z).length() <= radius


func tick(delta: float) -> void:
	if done:
		return
	_t += delta
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t += interval
		_pulse()
	if _t >= duration:
		done = true


func _pulse() -> void:
	if caster == null:
		return
	var targets: Array = world.enemies_alive() if hits == "enemies" else world.party_alive()
	for u in targets:
		if Vector2(u.position.x - position.x, u.position.z - position.z).length() - u.radius > radius:
			continue
		if effect.get("type", "") == "heal":
			var r: Array = caster.roll(effect["base"], effect["coef"], "holy", true)
			u.receive_heal(r[0], caster, label, r[1])
		else:
			var r2: Array = caster.roll(effect["base"], effect["coef"], effect.get("school", "physical"), false)
			u.take_damage(r2[0], effect.get("school", "physical"), caster, label, r2[1])
		if aura != "" and u.alive:
			u.add_aura(aura, caster)


func build_visual(enabled: bool) -> void:
	if not enabled:
		return
	_vis = true
	var c := color()
	match kind:
		"frost":
			# Glowing frost sigil + big ice shards crashing down + light shard rain + mist
			_decal = Vfx.frost_sigil(c, radius * 1.05)
			_decal.position.y = 0.06
			add_child(_decal)
			var splash := Vfx.ice_splash_emitter()
			add_child(splash)
			var fall_h := 14.0
			var speed := 32.0
			var dirv := Vector3(0.3, -1.0, 0.18).normalized()
			var rain := Vfx.shard_emitter({"amount": int(radius * radius * 0.35) + 4, "lifetime": fall_h / (speed * -dirv.y),
				"one_shot": false, "vmin": speed, "vmax": speed, "direction": dirv, "spread": 2.0,
				"box": Vector3(radius * 0.75, 0.1, radius * 0.75), "const_scale": true,
				"scale_min": 0.6, "scale_max": 0.95})
			rain.position = Vector3(-dirv.x / -dirv.y * fall_h, fall_h, -dirv.z / -dirv.y * fall_h)
			var ppm := rain.process_material as ParticleProcessMaterial
			ppm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_END
			ppm.sub_emitter_amount_at_end = 5
			add_child(rain)
			rain.sub_emitter = rain.get_path_to(splash)
			add_child(Vfx.emitter({"amount": 26, "lifetime": 1.8, "one_shot": false, "vmin": 0.2, "vmax": 0.6,
				"direction": Vector3.UP, "spread": 60.0, "box": Vector3(radius * 0.7, 0.1, radius * 0.7), "size": 2.0,
				"grow": true, "colors": [Color(0.7, 0.85, 1, 0), Color(0.7, 0.88, 1, 0.22), Color(0.7, 0.85, 1, 0)]}))
			_spawn_every = 0.22
		"poison":
			# Bubbling toxic puddle made of glossy blobs, popping bubbles and drifting fog
			var puddle_m := StandardMaterial3D.new()
			puddle_m.albedo_color = Color(0.16, 0.42, 0.08, 0.75)
			puddle_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			puddle_m.emission_enabled = true
			puddle_m.emission = Color(0.25, 0.75, 0.1)
			puddle_m.emission_energy_multiplier = 0.35
			puddle_m.roughness = 0.05
			puddle_m.metallic = 0.2
			for i in 9:
				var ang := TAU * i / 9.0 + randf_range(-0.3, 0.3)
				var d := 0.0 if i == 0 else randf_range(radius * 0.25, radius * 0.6)
				var blob := MeshInstance3D.new()
				blob.mesh = Models.sphere(1.0)
				blob.material_override = puddle_m
				blob.position = Vector3(cos(ang) * d, 0.0, sin(ang) * d)
				var bs := randf_range(radius * 0.3, radius * 0.45)
				blob.scale = Vector3(bs, 0.06, bs * randf_range(0.7, 1.2))
				blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(blob)
			add_child(Vfx.emitter({"amount": int(radius * radius * 2), "lifetime": 2.0, "one_shot": false,
				"vmin": 0.3, "vmax": 0.8, "direction": Vector3.UP, "spread": 40.0, "box": Vector3(radius * 0.6, 0.1, radius * 0.6),
				"size": 2.4, "grow": true, "additive": false,
				"colors": [Color(0.3, 0.7, 0.2, 0), Color(0.32, 0.75, 0.22, 0.35), Color(0.2, 0.45, 0.1, 0)]}))
			add_child(Vfx.emitter({"amount": 20, "lifetime": 1.0, "one_shot": false, "vmin": 0.6, "vmax": 1.4,
				"direction": Vector3.UP, "spread": 20.0, "box": Vector3(radius * 0.6, 0.1, radius * 0.6), "size": 0.2,
				"tex": "star", "colors": [Color(0.7, 1, 0.5, 0), Color(0.6, 1, 0.4, 1), Color(0.3, 0.8, 0.2, 0)]}))
			_spawn_every = 0.12
		_:
			# Sanctuary: soft golden glow, shafts of light, falling motes, a floating holy crystal
			var glow := MeshInstance3D.new()
			var gp := PlaneMesh.new()
			gp.size = Vector2(radius * 2.2, radius * 2.2)
			glow.mesh = gp
			_glow_m = Vfx.glow_mat(c, 0.0)
			_glow_m.albedo_texture = Vfx.soft_tex()
			glow.material_override = _glow_m
			glow.position.y = 0.05
			add_child(glow)
			add_child(Vfx.emitter({"amount": int(radius * radius * 2), "lifetime": 2.2, "one_shot": false,
				"vmin": 0.6, "vmax": 1.2, "direction": Vector3.DOWN, "spread": 15.0, "box": Vector3(radius * 0.8, 0.2, radius * 0.8),
				"size": 0.35, "tex": "star", "spin": 120.0, "gravity": Vector3(0, -0.3, 0),
				"colors": [Color(1, 1, 0.8, 0), Color(1, 0.92, 0.55, 1), Color(1, 0.85, 0.4, 0)]}))
			get_child(get_child_count() - 1).position.y = 5.0
			add_child(Vfx.emitter({"amount": int(radius * radius), "lifetime": 1.6, "one_shot": false,
				"vmin": 1.0, "vmax": 2.0, "direction": Vector3.UP, "spread": 6.0, "box": Vector3(radius * 0.8, 0.1, radius * 0.8),
				"size": 0.5, "streak": true, "stretch": 3.0,
				"colors": [Color(1, 1, 0.8, 0), Color(1, 0.9, 0.5, 0.8), Color(1, 0.85, 0.4, 0)]}))
			_crystal = Node3D.new()
			_crystal.position.y = 3.2
			add_child(_crystal)
			var gem := MeshInstance3D.new()
			gem.mesh = Vfx.crystal_solid_mesh(1.2, 0.38)
			gem.material_override = Vfx.holy_mat()
			gem.position.y = -0.4
			_crystal.add_child(gem)
			var halo := MeshInstance3D.new()
			halo.mesh = Models.sphere(0.9)
			halo.material_override = Vfx.glow_mat(c, 0.25)
			halo.position.y = 0.2
			_crystal.add_child(halo)
			_spawn_every = 0.4
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 1.4
	light.omni_range = radius * 1.6
	light.position.y = 2.0
	add_child(light)


func _process(delta: float) -> void:
	if not _vis or done:
		return
	var appear := clampf(_t * 4.0, 0.0, 1.0)
	var fade := clampf((duration - _t) / 0.6, 0.0, 1.0)
	if _decal:
		(_decal.material_override as ShaderMaterial).set_shader_parameter("intensity", appear * fade)
		_decal.scale = Vector3.ONE * (0.7 + 0.3 * appear)
	if _glow_m:
		_glow_m.albedo_color.a = 0.35 * appear * fade
	if _crystal:
		_crystal.rotation.y += delta * 1.5
		_crystal.position.y = 3.2 + sin(_t * 2.5) * 0.2
		_crystal.scale = Vector3.ONE * appear * fade
	_spawn_t -= delta
	if _spawn_t > 0.0 or _t > duration - 0.4:
		return
	_spawn_t = _spawn_every
	var ang := randf() * TAU
	var d := sqrt(randf()) * radius * 0.85
	var at := position + Vector3(cos(ang) * d, 0, sin(ang) * d)
	match kind:
		"frost":
			Vfx.ice_fall(get_parent(), at, randf_range(0.8, 1.15))
		"poison":
			_bubble(at)
		_:
			Vfx.light_shaft(get_parent(), at, color(), 10.0, randf_range(0.12, 0.28), 1.4)


## A glossy bubble that swells on the puddle and pops into droplets.
func _bubble(at: Vector3) -> void:
	var b := MeshInstance3D.new()
	b.mesh = Models.sphere(1.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.95, 0.3, 0.7)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.35, 0.9, 0.2)
	m.roughness = 0.05
	b.material_override = m
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(b)
	b.global_position = Vector3(at.x, 0.05, at.z)
	var size := randf_range(0.15, 0.4)
	b.scale = Vector3.ONE * 0.02
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector3.ONE * size, randf_range(0.3, 0.6)).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		Vfx.burst(b.get_parent(), b.global_position, {"amount": 8, "lifetime": 0.4, "vmin": 1.0, "vmax": 2.5,
			"direction": Vector3.UP, "spread": 60.0, "gravity": Vector3(0, -8, 0), "size": 0.12,
			"colors": [Color(0.7, 1, 0.5, 1), Color(0.3, 0.8, 0.2, 0)]})
		b.queue_free())


func color() -> Color:
	match kind:
		"frost":
			return Color(0.55, 0.8, 1.0)
		"poison":
			return Color(0.4, 0.95, 0.3)
	return Color(1.0, 0.88, 0.45)
