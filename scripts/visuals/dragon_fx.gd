class_name DragonFx
extends RefCounted
## Visuals for Vyrathax's attacks. Each attack looks like what it is: a burning rock falls out of the
## sky for Meteor, a real fire stream rolls over the ground for Flame Breath, the dragon spits molten
## globs that splash into lava for Cinder Pools, and Inferno Pulse / Cataclysm are walls and pillars of
## fire. Ground warnings use shaders/scorch.gdshader: shadows, fissures and heat with torn edges.
## Purely cosmetic: gameplay areas live in Hazard.

static var _scorch_shader: Shader
static var _rock_mesh: ArrayMesh
static var _chunk_mesh: ArrayMesh
static var _rock_mat: ShaderMaterial

const FIRE := [Color(1, 0.62, 0.22, 1), Color(1, 0.36, 0.05, 0.95), Color(0.75, 0.12, 0.02, 0.75), Color(0.25, 0.04, 0.02, 0)]


# ------------------------------------------------------------------ ground marks

## A ground decal using the scorch shader. size = radius (circle) or length (cone).
static func decal(parent: Node3D, size: float, mode: int, shape := 0, half_angle_deg := 45.0) -> ShaderMaterial:
	if _scorch_shader == null:
		_scorch_shader = load("res://shaders/scorch.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _scorch_shader
	m.set_shader_parameter("noise_tex", Vfx.noise_tex())
	m.set_shader_parameter("cell_tex", Vfx.cell_tex())
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("shape", shape)
	m.set_shader_parameter("half_angle", deg_to_rad(half_angle_deg))
	m.set_shader_parameter("seed", randf() * 10.0)
	m.set_shader_parameter("uv_scale", size / 5.0)
	m.render_priority = -1
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size * 2.0, size * 2.0)
	mi.mesh = pm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.05 + randf() * 0.02
	parent.add_child(mi)
	return m


## Warning decal for a hazard (called by Hazard.build_visual). Returns the material to animate.
static func telegraph(h: Hazard) -> ShaderMaterial:
	match h.label:
		"Meteor":
			var m := decal(h, h.radius * 1.12, 0)
			# Heat rising from where it will land
			var e := Vfx.emitter({"amount": int(h.radius * 5), "lifetime": 1.2, "one_shot": false, "vmin": 1.0,
				"vmax": 3.0, "direction": Vector3.UP, "spread": 15.0, "box": Vector3(h.radius * 0.7, 0.1, h.radius * 0.7),
				"size": 0.12, "local": true, "colors": [Color(1, 0.7, 0.3, 0), Color(1, 0.55, 0.15, 1), Color(1, 0.3, 0.05, 0)]})
			h.add_child(e)
			return m
		"Flame Breath":
			return decal(h, h.length, 1, 1, h.half_angle)
		"Tail Lash":
			return decal(h, h.length, 2, 1, h.half_angle)
		"Cinder Pool":
			return decal(h, h.radius * 1.1, 3)
	return decal(h, h.radius if h.shape == "circle" else h.length, 1, 0 if h.shape == "circle" else 1, h.half_angle)


## Charred patch with dying embers that fades away.
static func crater(world: Node3D, pos: Vector3, radius: float, dur := 5.0, shape := 0, dir := Vector3.FORWARD,
		half_angle_deg := 45.0) -> void:
	var holder := Node3D.new()
	world.add_child(holder)
	holder.global_position = Vector3(pos.x, 0.0, pos.z)
	if shape == 1:
		holder.rotation.y = atan2(-dir.x, -dir.z)
	var m := decal(holder, radius, 4, shape, half_angle_deg)
	m.set_shader_parameter("fade", 1.0)
	var tw := holder.create_tween()
	tw.tween_interval(dur * 0.4)
	tw.tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, dur * 0.6)
	tw.tween_callback(holder.queue_free)


# ------------------------------------------------------------------ rocks

## Jagged boulder: a low-poly sphere pushed around by noise, flat shaded.
static func rock_mesh() -> ArrayMesh:
	if _rock_mesh == null:
		_rock_mesh = _make_rock(1.0, 0.38, 11)
	return _rock_mesh


static func chunk_mesh() -> ArrayMesh:
	if _chunk_mesh == null:
		_chunk_mesh = _make_rock(0.35, 0.5, 23)
	return _chunk_mesh


static func _make_rock(radius: float, rough: float, seed_v: int) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 10
	sm.rings = 7
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 1.3
	var moved := {}
	for i in verts.size():
		var v := verts[i]
		var key := Vector3i(roundi(v.x * 1000), roundi(v.y * 1000), roundi(v.z * 1000))  # keep seams closed
		if not moved.has(key):
			moved[key] = v * (1.0 + n.get_noise_3dv(v * 2.0) * rough) * Vector3(1.0, 0.82, 1.0)
		verts[i] = moved[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx.size():
		var v2 := verts[idx[i]]
		st.set_uv(Vector2(atan2(v2.z, v2.x) / TAU + 0.5, v2.y / radius * 0.5 + 0.5))
		st.add_vertex(v2)
	st.generate_normals()
	return st.commit()


## Dark basalt split by glowing lava cracks (shaders/molten_rock.gdshader).
static func rock_mat() -> ShaderMaterial:
	if _rock_mat == null:
		_rock_mat = ShaderMaterial.new()
		_rock_mat.shader = load("res://shaders/molten_rock.gdshader")
		_rock_mat.set_shader_parameter("cell_tex", Vfx.cell_tex())
		_rock_mat.set_shader_parameter("noise_tex", Vfx.noise_tex())
	return _rock_mat


## Rock chunks thrown out by an impact (real meshes, tumbling, falling back down).
static func rock_debris(world: Node3D, pos: Vector3, scale := 1.0, count := 14) -> void:
	var p := Vfx.emitter({"amount": count, "lifetime": 1.4, "vmin": 6.0 * scale, "vmax": 13.0 * scale,
		"direction": Vector3.UP, "spread": 50.0, "gravity": Vector3(0, -24, 0), "scale_min": 0.5 * scale,
		"scale_max": 1.4 * scale, "const_scale": true, "sphere": 0.8 * scale})
	var pm := p.process_material as ParticleProcessMaterial
	pm.particle_flag_rotate_y = true
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -540.0
	pm.angular_velocity_max = 540.0
	var mesh := chunk_mesh().duplicate() as ArrayMesh
	mesh.surface_set_material(0, rock_mat())
	p.draw_pass_1 = mesh
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
	world.add_child(p)
	p.global_position = pos + Vector3(0, 0.4, 0)
	p.restart()
	Vfx._free_after(p, 2.0)


# ------------------------------------------------------------------ meteor

## A burning boulder streaks down from the sky and lands exactly when the hazard fires.
static func meteor_fall(world: Node3D, h: Hazard) -> void:
	var land := Vector3(h.position.x, 0.6, h.position.z)
	var from := land + Vector3(-16, 42, -11).rotated(Vector3.UP, randf_range(-0.6, 0.6))
	var holder := Node3D.new()
	world.add_child(holder)
	holder.global_position = from
	var rock := MeshInstance3D.new()
	rock.mesh = rock_mesh()
	rock.material_override = rock_mat()
	rock.scale = Vector3.ONE * (0.9 + h.radius * 0.12)
	holder.add_child(rock)
	var shell := MeshInstance3D.new()  # heat glow around the rock
	var q := QuadMesh.new()
	q.size = Vector2(4.2, 4.2) * rock.scale.x
	shell.mesh = q
	var sm := Vfx.glow_mat(Color(1, 0.35, 0.06), 0.16)
	sm.albedo_texture = Vfx.soft_tex()
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	shell.material_override = sm
	holder.add_child(shell)
	var dir := (land - from).normalized()
	var trail := Vfx.emitter({"amount": 45, "lifetime": 0.45, "one_shot": false, "vmin": 1.0, "vmax": 3.0,
		"direction": -dir, "spread": 20.0, "size": 2.4, "grow": true, "sphere": 0.6, "shader": "flame",
		"tall": 1.1, "colors": [Color(1, 0.6, 0.2, 0.9), Color(0.95, 0.3, 0.05, 0.7), Color(0.5, 0.08, 0.02, 0.35),
			Color(0.2, 0.04, 0.02, 0)]})
	holder.add_child(trail)
	var smoke := Vfx.emitter({"amount": 40, "lifetime": 1.6, "one_shot": false, "vmin": 0.3, "vmax": 1.0,
		"direction": -dir, "spread": 30.0, "size": 3.2, "grow": true, "shader": "smoke", "spin": 40.0,
		"sphere": 0.6, "colors": [Color(0.2, 0.14, 0.12, 0.0), Color(0.16, 0.12, 0.11, 0.6), Color(0.1, 0.08, 0.08, 0)]})
	holder.add_child(smoke)
	var sparks := Vfx.emitter({"amount": 40, "lifetime": 0.5, "one_shot": false, "vmin": 2.0, "vmax": 6.0,
		"direction": -dir, "spread": 35.0, "size": 0.25, "streak": true, "stretch": 3.0,
		"colors": [Color(1, 0.9, 0.5), Color(1, 0.4, 0.05, 0)]})
	holder.add_child(sparks)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.5, 0.15)
	light.light_energy = 3.0
	light.omni_range = 14.0
	holder.add_child(light)
	var dur := maxf(h.delay - h._t, 0.15)
	var tw := holder.create_tween()
	tw.tween_property(holder, "global_position", land, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(rock, "rotation", Vector3(randf_range(4, 8), randf_range(4, 8), randf_range(2, 5)), dur)
	tw.tween_callback(func():
		rock.visible = false
		shell.visible = false
		light.visible = false
		for e in [trail, smoke, sparks]:
			e.emitting = false)
	tw.tween_interval(1.8)
	tw.tween_callback(holder.queue_free)


static func meteor_impact(world: Node3D, pos: Vector3, radius: float) -> void:
	var p := Vector3(pos.x, 0.0, pos.z)
	Vfx.burst(world, p + Vector3(0, 0.6, 0), {"amount": 46, "lifetime": 0.95, "vmin": 3.0, "vmax": 10.0,
		"direction": Vector3.UP, "spread": 75.0, "gravity": Vector3(0, 4, 0), "damping": 3.5, "size": 3.4,
		"grow": true, "sphere": 1.2, "shader": "flame_solid", "colors": FIRE})
	Vfx.burst(world, p + Vector3(0, 0.3, 0), {"amount": 40, "lifetime": 0.6, "vmin": 10.0, "vmax": 18.0,
		"direction": Vector3(1, 0, 0), "spread": 180.0, "flat": true, "damping": 7.0, "size": 2.0, "grow": true,
		"shader": "flame", "colors": FIRE})
	dust_ring(world, p, radius * 1.3)
	rock_debris(world, p, 1.0, 16)
	Vfx.sparks(world, p + Vector3(0, 1, 0), Color(1, 0.6, 0.2), 26)
	Vfx.smoke(world, p + Vector3(0, 1.5, 0), 2.0)
	crater(world, p, radius * 0.95, 6.0)
	Vfx.flash_light(world, p + Vector3(0, 3, 0), Color(1, 0.5, 0.2), 8.0, radius * 4.0, 0.6)


# ------------------------------------------------------------------ dust, waves, pillars

## Low ring of dust and grit rolling outward from an impact.
static func dust_ring(world: Node3D, pos: Vector3, radius: float, tint := Color(0.36, 0.28, 0.22)) -> void:
	Vfx.burst(world, pos + Vector3(0, 0.5, 0), {"amount": int(radius * 6) + 12, "lifetime": 1.3, "vmin": radius * 1.6,
		"vmax": radius * 2.4, "direction": Vector3(1, 0, 0), "spread": 180.0, "flat": true, "damping": radius * 1.8,
		"size": 2.6, "grow": true, "shader": "smoke", "spin": 60.0, "ring": [0.6, 0.0],
		"colors": [Color(tint.r, tint.g, tint.b, 0.75), Color(tint.r * 0.8, tint.g * 0.8, tint.b * 0.8, 0.4), Color(tint.r, tint.g, tint.b, 0.0)]})


## A wall of fire racing outward over the ground (Inferno Pulse, Cataclysm).
static func fire_wave(world: Node3D, pos: Vector3, radius: float, dur := 0.9) -> void:
	var speed := radius / dur
	Vfx.burst(world, Vector3(pos.x, 0.3, pos.z), {"amount": int(radius * 10), "lifetime": dur, "vmin": speed,
		"vmax": speed * 1.05, "direction": Vector3(1, 0, 0), "spread": 180.0, "flat": true, "ring": [2.5, 2.0],
		"size": 3.2, "grow": true, "scale_min": 0.8, "scale_max": 1.4, "shader": "flame_solid", "tall": 1.6,
		"colors": [Color(1, 0.85, 0.5, 1), Color(1, 0.5, 0.1, 1), Color(0.85, 0.18, 0.03, 0.7), Color(0.3, 0.05, 0.02, 0)]})
	Vfx.burst(world, Vector3(pos.x, 0.4, pos.z), {"amount": int(radius * 3), "lifetime": dur * 1.6, "vmin": speed * 0.8,
		"vmax": speed, "direction": Vector3(1, 0, 0), "spread": 180.0, "flat": true, "ring": [2.5, 2.0], "damping": 4.0,
		"size": 4.0, "grow": true, "shader": "smoke", "spin": 30.0,
		"colors": [Color(0.2, 0.13, 0.1, 0.0), Color(0.18, 0.12, 0.1, 0.5), Color(0.1, 0.08, 0.08, 0)]})


## Column of fire bursting out of the ground.
static func fire_pillar(world: Node3D, pos: Vector3, height := 10.0, delay := 0.0) -> void:
	var go := func():
		Vfx.burst(world, Vector3(pos.x, 0.2, pos.z), {"amount": 40, "lifetime": 0.9, "vmin": height * 0.9,
			"vmax": height * 1.4, "direction": Vector3.UP, "spread": 6.0, "damping": 2.0, "size": 2.6, "grow": true,
			"sphere": 0.6, "shader": "flame_solid", "tall": 1.8, "colors": FIRE})
		Vfx.burst(world, Vector3(pos.x, 0.2, pos.z), {"amount": 14, "lifetime": 0.5, "vmin": 3.0, "vmax": 6.0,
			"direction": Vector3(1, 0, 0), "spread": 180.0, "flat": true, "size": 1.8, "grow": true, "shader": "flame",
			"colors": FIRE})
		crater(world, pos, 2.2, 4.0)
		Vfx.flash_light(world, Vector3(pos.x, 3, pos.z), Color(1, 0.5, 0.2), 4.0, 10.0, 0.5)
	if delay <= 0.0:
		go.call()
	else:
		world.get_tree().create_timer(delay).timeout.connect(go)


static func eruptions(world: Node3D, count: int, radius: float) -> void:
	for i in count:
		var a := TAU * i / count + randf_range(-0.2, 0.2)
		var d := randf_range(radius * 0.35, radius)
		fire_pillar(world, Vector3(cos(a) * d, 0, sin(a) * d), randf_range(8.0, 13.0), randf_range(0.0, 0.5))


# ------------------------------------------------------------------ breath, tail, cinder pools

## After the breath stream: the ground along the cone keeps burning for a moment, then chars.
static func breath_ground(world: Node3D, h: Hazard) -> void:
	for i in 5:
		var d := 5.0 + i * 5.0
		var w := tan(deg_to_rad(h.half_angle)) * d
		var center := h.position + h.dir * d
		var e := Vfx.emitter({"amount": int(3 + w * 0.9), "lifetime": 1.0, "one_shot": false, "vmin": 0.6, "vmax": 2.0,
			"direction": Vector3.UP, "spread": 12.0, "box": Vector3(w * 0.8, 0.1, 2.0), "size": 3.0, "grow": true,
			"scale_min": 0.55, "scale_max": 1.6, "shader": "flame_solid", "tall": 1.6,
			"colors": [Color(1, 0.6, 0.2, 0.9), Color(0.95, 0.32, 0.05, 0.85), Color(0.6, 0.1, 0.02, 0.5), Color(0.2, 0.04, 0.02, 0)]})
		world.add_child(e)
		e.global_position = Vector3(center.x, 0.1, center.z)
		e.rotation.y = atan2(-h.dir.x, -h.dir.z)
		e.emitting = false
		var tw := e.create_tween()
		tw.tween_interval(0.12 * i + 0.15)
		tw.tween_callback(func(): e.emitting = true)
		tw.tween_interval(1.5)
		tw.tween_callback(func(): e.emitting = false)
		tw.tween_interval(1.2)
		tw.tween_callback(e.queue_free)
	crater(world, h.position, h.length, 4.5, 1, h.dir, h.half_angle)


## Tail Lash: a sweep of dust and gravel behind the dragon.
static func tail_sweep(world: Node3D, h: Hazard) -> void:
	for i in 5:
		var a := deg_to_rad(lerpf(-h.half_angle, h.half_angle, i / 4.0))
		var d := h.dir.rotated(Vector3.UP, a)
		var pos := h.position + d * (h.length * 0.6)
		world.get_tree().create_timer(0.05 * i).timeout.connect(func():
			Vfx.burst(world, pos + Vector3(0, 0.5, 0), {"amount": 14, "lifetime": 1.2, "vmin": 4.0, "vmax": 9.0,
				"direction": d, "spread": 25.0, "damping": 4.0, "size": 2.8, "grow": true, "shader": "smoke",
				"spin": 60.0, "colors": [Color(0.4, 0.32, 0.25, 0.7), Color(0.3, 0.24, 0.2, 0.35), Color(0.3, 0.24, 0.2, 0)]})
			Vfx.debris(world, pos, 0.8))
	rock_debris(world, h.position + h.dir * h.length * 0.5, 0.7, 8)


## A molten glob spat from the dragon's mouth that arcs onto the spot of a new cinder pool.
static func lava_glob(world: Node3D, boss: Unit, h: Hazard) -> void:
	var from: Vector3 = boss.position + Vector3(0, 7, 0)
	if boss.model is DragonRig and (boss.model as DragonRig).mouth != null:
		from = (boss.model as DragonRig).mouth.global_position
	var land := Vector3(h.position.x, 0.4, h.position.z)
	var glob := Node3D.new()
	world.add_child(glob)
	glob.global_position = from
	var core := MeshInstance3D.new()  # a lump of molten rock wrapped in flame
	core.mesh = rock_mesh()
	core.material_override = rock_mat()
	core.scale = Vector3.ONE * 0.55
	glob.add_child(core)
	var fl := Vfx.emitter({"amount": 40, "lifetime": 0.4, "one_shot": false, "vmin": 0.5, "vmax": 1.5,
		"spread": 180.0, "size": 1.5, "grow": true, "sphere": 0.5, "shader": "flame", "colors": FIRE})
	glob.add_child(fl)
	var drip := Vfx.emitter({"amount": 24, "lifetime": 0.6, "one_shot": false, "vmin": 0.0, "vmax": 0.5,
		"gravity": Vector3(0, -14, 0), "size": 0.3, "colors": [Color(1, 0.7, 0.3), Color(1, 0.3, 0.05, 0)]})
	glob.add_child(drip)
	var dur := maxf(h.delay - h._t, 0.2)
	var tw := glob.create_tween()
	tw.tween_method(func(f: float):
		var p := from.lerp(land, f)
		p.y += sin(f * PI) * 6.0
		glob.global_position = p
		core.rotation = Vector3(f * 9.0, f * 6.0, 0.0), 0.0, 1.0, dur)
	tw.tween_callback(func():
		core.visible = false
		fl.emitting = false
		drip.emitting = false)
	tw.tween_interval(0.8)
	tw.tween_callback(glob.queue_free)


## The glob lands: molten splash, then flames keep licking up out of the pool (children of the hazard).
static func lava_splash(world: Node3D, h: Hazard) -> void:
	var p := Vector3(h.position.x, 0.2, h.position.z)
	Vfx.burst(world, p, {"amount": 30, "lifetime": 0.9, "vmin": 4.0, "vmax": 9.0, "direction": Vector3.UP,
		"spread": 60.0, "gravity": Vector3(0, -16, 0), "size": 0.45, "colors": [Color(1, 0.8, 0.4), Color(1, 0.4, 0.05),
			Color(0.4, 0.05, 0.02, 0)]})
	Vfx.fire_burst(world, p + Vector3(0, 0.4, 0), 1.6)
	Vfx.smoke(world, p + Vector3(0, 1.0, 0), 1.2)
	Vfx.pool_flames(h, h.radius)
	var wisps := Vfx.emitter({"amount": int(h.radius * 3), "lifetime": 2.5, "one_shot": false, "vmin": 0.6, "vmax": 1.4,
		"direction": Vector3.UP, "spread": 15.0, "box": Vector3(h.radius * 0.6, 0.1, h.radius * 0.6), "size": 2.4,
		"grow": true, "local": true, "shader": "smoke", "spin": 30.0,
		"colors": [Color(0.2, 0.15, 0.13, 0.0), Color(0.18, 0.13, 0.12, 0.35), Color(0.1, 0.08, 0.08, 0)]})
	h.add_child(wisps)


# ------------------------------------------------------------------ melee (timed by DragonRig at contact)

const CLAW := Color(1, 0.22, 0.08)


## Jaws snapping shut on the target.
static func bite_hit(world: Node3D, t: Unit) -> void:
	var c := Vfx.chest(t)
	Vfx.sparks(world, c, Color(1, 0.45, 0.25), 12)
	Vfx.star_flash(world, c, CLAW, 1.6)
	if t.is_player:
		world.shake.emit(0.15)


## Three claw grooves torn diagonally through the target (the direction follows the swinging paw), grit
## kicked up where the paw lands. Rending Claw (heavy) is bigger and shakes the screen.
static func claw_hit(world: Node3D, boss: Unit, t: Unit, paw: Vector3, side: float, heavy: bool, whelp: bool) -> void:
	var sz := 0.5 if whelp else (1.25 if heavy else 1.0)
	var c := Vfx.chest(t) if t != null else paw
	for i in 3:
		var off := Vector3(0, (0.45 - i * 0.45) * sz, 0)
		Vfx.swoosh(world, c + off, boss.rotation.y, side * 0.85, CLAW, 2.3 * sz, 0.32 * sz, 150.0, 0.2 + i * 0.03,
			side < 0.0, 1.3 if heavy else 1.0)
	Vfx.sparks(world, c, Color(1, 0.3, 0.15), 24 if heavy else 12)
	if heavy:
		Vfx.star_flash(world, c, CLAW, 3.0)
	if not whelp:
		var g := Vector3(paw.x, 0.2, paw.z)
		Vfx.burst(world, g, {"amount": 8, "lifetime": 0.9, "vmin": 1.0, "vmax": 3.0, "direction": Vector3.UP,
			"spread": 70.0, "size": 1.4, "grow": true, "shader": "smoke", "spin": 50.0, "damping": 2.5,
			"colors": [Color(0.36, 0.28, 0.22, 0.6), Color(0.3, 0.24, 0.2, 0)]})
		rock_debris(world, g, 0.35, 5)
	if t != null and t.is_player:
		world.shake.emit(0.35 if heavy else 0.18)


## Both forepaws slam down: the ground cracks, dust rolls out, rocks fly. Shakes anyone close.
static func stomp_hit(world: Node3D, boss: Unit, pos: Vector3, t: Unit) -> void:
	dust_ring(world, pos, 8.0)
	rock_debris(world, pos, 0.75, 12)
	Vfx.burst(world, pos + Vector3(0, 0.3, 0), {"amount": 18, "lifetime": 1.6, "vmin": 2.0, "vmax": 5.0,
		"direction": Vector3.UP, "spread": 40.0, "size": 2.4, "grow": true, "shader": "smoke", "spin": 40.0,
		"damping": 2.0, "sphere": 1.5, "colors": [Color(0.4, 0.31, 0.24, 0.7), Color(0.32, 0.25, 0.2, 0)]})
	var holder := Node3D.new()
	world.add_child(holder)
	holder.global_position = pos
	var m := decal(holder, 5.0, 4)
	var tw := holder.create_tween()
	tw.tween_interval(1.5)
	tw.tween_method(func(v: float): m.set_shader_parameter("fade", v), 1.0, 0.0, 2.0)
	tw.tween_callback(holder.queue_free)
	if t != null:
		Vfx.sparks(world, Vfx.chest(t), Color(1, 0.45, 0.25), 10)
	var pl = world.get("player")
	if pl != null and (pl as Unit).position.distance_to(pos) < 16.0:
		world.shake.emit(0.45)
