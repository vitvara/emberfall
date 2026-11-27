class_name Projectile
extends Node3D
## Visual missile (fireball, holy bolt, meteor). Calls on_hit when it arrives.
## Either homes on `target` at `speed`, or flies to `dest` over a fixed `duration`.

var target: Unit
var dest := Vector3.ZERO
var speed := 30.0
var duration := -1.0
var on_hit: Callable
var color := Color(1, 0.5, 0.1)
var size := 0.35
var impact := "fire"  # fire | holy | arcane | meteor
var arc := 0.0        # sideways/upward curve height

var _start := Vector3.ZERO
var _t := 0.0
var _total := 1.0
var _orb: MeshInstance3D
var _trail: GPUParticles3D
var _done := false
var _ribbons: Array = []


func _ready() -> void:
	_start = position  # map space, the same as the target's position (the Outpost sits off-origin)
	if impact == "frost":
		_build_frost()
		_finish_ready()
		return
	if impact == "poison":
		_build_vial()
		_finish_ready()
		return
	_orb = MeshInstance3D.new()
	_orb.mesh = Models.sphere(size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color.lightened(0.5)
	_orb.material_override = m
	add_child(_orb)
	var halo := MeshInstance3D.new()
	halo.mesh = Models.sphere(size * 2.2)
	halo.material_override = Vfx.glow_mat(color, 0.35)
	_orb.add_child(halo)
	_trail = Vfx.emitter({"amount": 40, "lifetime": 0.45, "one_shot": false, "vmin": 0.2, "vmax": 0.8,
		"size": size * 2.4, "colors": [color.lightened(0.4), color, Color(color.r * 0.4, color.g * 0.2, 0.05, 0)]})
	add_child(_trail)
	_finish_ready()


func _finish_ready() -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.0
	light.omni_range = 5.0
	add_child(light)
	if duration > 0.0:
		_total = duration
	else:
		_total = maxf(0.08, _start.distance_to(_goal()) / speed)


## Ice comet: crystal head, two crossed ribbon tails, streaky glow and shed snowflakes.
func _build_frost() -> void:
	_orb = MeshInstance3D.new()
	_orb.mesh = Vfx.crystal_mesh()
	_orb.scale = Vector3.ONE * 1.6
	_orb.rotation.x = -PI / 2.0
	add_child(_orb)
	# Solid ice core inside the glowing head (no round glow ball)
	var ice := MeshInstance3D.new()
	ice.mesh = Vfx.crystal_solid_mesh(0.9, 0.16)
	ice.material_override = Vfx.ice_mat()
	ice.rotation.x = -PI / 2.0
	ice.position.z = 0.3
	add_child(ice)
	for k in 2:
		var a := Node3D.new()
		var b := Node3D.new()
		var off := Vector3(0, 0.16, 0) if k == 0 else Vector3(0.16, 0, 0)
		a.position = -off
		b.position = off
		add_child(a)
		add_child(b)
		var tr := WeaponTrail.new().setup(a, b, Color(0.55, 0.8, 1))
		tr.life = 0.32
		tr.emitting = true
		add_child(tr)
		_ribbons.append(tr)
	_trail = Vfx.emitter({"amount": 60, "lifetime": 0.4, "one_shot": false, "vmin": 0.1, "vmax": 0.6,
		"size": 0.28, "tex": "star", "spin": 300.0, "sphere": 0.2,
		"colors": [Color(1, 1, 1, 1), Color(0.6, 0.85, 1, 0.8), Color(0.4, 0.6, 1, 0)]})
	add_child(_trail)


## Thrown glass vial with a green glow and drips.
func _build_vial() -> void:
	_orb = MeshInstance3D.new()
	_orb.mesh = Models.sphere(0.16)
	_orb.material_override = Models.mat(Color(0.4, 0.95, 0.3), 1.5)
	add_child(_orb)
	var neck := MeshInstance3D.new()
	neck.mesh = Models.cyl(0.05, 0.06, 0.14)
	neck.material_override = Models.mat(Color(0.5, 0.35, 0.2))
	neck.position.y = 0.17
	_orb.add_child(neck)
	_trail = Vfx.emitter({"amount": 30, "lifetime": 0.5, "one_shot": false, "vmin": 0.2, "vmax": 0.6,
		"gravity": Vector3(0, -6, 0), "size": 0.18,
		"colors": [Color(0.6, 1, 0.4, 1), Color(0.3, 0.8, 0.2, 0.7), Color(0.2, 0.5, 0.1, 0)]})
	add_child(_trail)


func _goal() -> Vector3:
	if target != null and is_instance_valid(target):
		return Vfx.chest(target)
	return dest


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var f := clampf(_t / _total, 0.0, 1.0)
	var p := _start.lerp(_goal(), f)
	p.y += sin(f * PI) * arc
	var prev := position
	position = p
	if impact != "poison" and p.distance_to(prev) > 0.001:
		look_at(global_position + (p - prev), Vector3.UP if absf((p - prev).normalized().y) < 0.95 else Vector3.RIGHT)
	elif impact == "poison":
		_orb.rotation += Vector3(8.0, 5.0, 0) * get_process_delta_time()
	if f >= 1.0:
		_hit()


func _hit() -> void:
	_done = true
	if on_hit.is_valid():
		on_hit.call()
	var parent := get_parent()
	match impact:
		"meteor":
			Vfx.explosion(parent, position, 6.0)
		"holy":
			Vfx.sparks(parent, position, color, 16)
			Vfx.bubble_flash(parent, position, color, 0.9, 0.35)
		"frost":
			Vfx.ice_burst(parent, position, 1.0 if target == null or not target.is_boss else 1.4)
		"poison":
			Vfx.burst(parent, position, {"amount": 40, "lifetime": 0.7, "vmin": 2.0, "vmax": 6.0,
				"direction": Vector3.UP, "spread": 70.0, "gravity": Vector3(0, -10, 0), "size": 0.3,
				"colors": [Color(0.7, 1, 0.5, 1), Color(0.35, 0.85, 0.25, 0.9), Color(0.2, 0.5, 0.1, 0)]})
			Vfx.sparks(parent, position, Color(0.5, 1, 0.3), 12)
			Vfx.burst(parent, position, {"amount": 10, "lifetime": 1.2, "vmin": 1.0, "vmax": 3.0, "size": 2.0,
				"grow": true, "additive": false, "colors": [Color(0.35, 0.8, 0.25, 0.5), Color(0.2, 0.5, 0.1, 0)]})
		"arcane":
			Vfx.sparks(parent, position, color, 16)
			Vfx.bubble_flash(parent, position, color, 1.0, 0.4)
		_:
			Vfx.fire_burst(parent, position, size * 3.0)
			Vfx.flash_light(parent, position, color, 3.0, 6.0, 0.3)
	_orb.visible = false
	_trail.emitting = false
	for r in _ribbons:
		r.emitting = false
	get_tree().create_timer(0.6).timeout.connect(queue_free)
