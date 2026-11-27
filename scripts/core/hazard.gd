class_name Hazard
extends Node3D
## A telegraphed area on the ground: a circle or a cone.
## delay    = warning time before it does anything
## duration = 0 for a one-shot blast, > 0 for a lingering pool that ticks

var world  # RaidWorld
var shape := "circle"
var radius := 4.0
var dir := Vector3(0, 0, -1)
var half_angle := 45.0
var length := 30.0
var delay := 0.0
var duration := 0.0
var tick_interval := 1.0
var damage := 0.0
var school := "fire"
var label := ""
var source: Unit
var tank_soak := false
var knockback := 0.0
var color := Color(1.0, 0.25, 0.1)

var done := false
var _active := false
var _t := 0.0
var _tick_t := 0.0


static func circle(at: Vector3, r: float, warn: float, dmg: float, nm: String, src: Unit) -> Hazard:
	var h := Hazard.new()
	h.shape = "circle"
	h.position = Vector3(at.x, 0.0, at.z)
	h.radius = r
	h.delay = warn
	h.damage = dmg
	h.label = nm
	h.source = src
	return h


static func cone(at: Vector3, direction: Vector3, ln: float, half_deg: float, warn: float,
		dmg: float, nm: String, src: Unit) -> Hazard:
	var h := Hazard.new()
	h.shape = "cone"
	h.position = Vector3(at.x, 0.0, at.z)
	h.dir = Vector3(direction.x, 0.0, direction.z).normalized()
	h.length = ln
	h.half_angle = half_deg
	h.delay = warn
	h.damage = dmg
	h.label = nm
	h.source = src
	return h


func contains(p: Vector3) -> bool:
	var to := Vector3(p.x - position.x, 0.0, p.z - position.z)
	var d := to.length()
	if shape == "circle":
		return d <= radius
	if d > length:
		return false
	if d < 0.5:
		return true
	return rad_to_deg(dir.angle_to(to / d)) <= half_angle


func is_lingering() -> bool:
	return duration > 0.0


func tick(delta: float) -> void:
	if done:
		return
	_t += delta
	if _t < delay:
		_update_warning(_t / maxf(delay, 0.01))
		return
	var replica: bool = world.net_role == "client"
	if duration <= 0.0:
		if replica:
			world.on_hazard_fired(self)
		else:
			_fire_once()
		done = true
		return
	if not _active:
		_active = true
		world.on_hazard_active(self)
	_set_active_look()
	_tick_t -= delta
	if _tick_t <= 0.0 and not replica:
		_tick_t = tick_interval
		for u in world.party_alive():
			if contains(u.position):
				u.take_damage(damage * tick_interval, school, source, label)
				if u.alive and label == "Cinder Pool":
					u.add_aura("burning", source)
	if _t >= delay + duration:
		done = true


func _fire_once() -> void:
	world.on_hazard_fired(self)
	for u in world.party_alive():
		if contains(u.position):
			u.take_damage(damage, school, source, label)
			if knockback > 0.0 and u.alive:
				var away: Vector3 = u.flat_pos() - position
				if away.length() < 0.1:
					away = dir
				var y: float = u.position.y
				u.position = world.clamp_to_arena(u.position + away.normalized() * knockback)
				u.position.y = y
				world.force_position(u)
				if u.is_casting() and not u.casting.get("moving", false):
					u.casting = {}


# ------------------------------------------------------------------ visuals

## Ground warning: a scorch decal per attack (meteor shadow, heat, dust, lava) — see DragonFx.
var _decal: ShaderMaterial


func build_visual(enabled: bool) -> void:
	if not enabled:
		return
	if shape == "cone":
		rotation.y = atan2(-dir.x, -dir.z)
	_decal = DragonFx.telegraph(self)


func _update_warning(f: float) -> void:
	if _decal != null:
		_decal.set_shader_parameter("progress", f)


func _set_active_look() -> void:
	if _decal == null:
		return
	# Lingering pools: the lava spreads in quickly, then cools away in the last second.
	_decal.set_shader_parameter("progress", clampf((_t - delay) / 0.5, 0.0, 1.0))
	_decal.set_shader_parameter("fade", clampf(delay + duration - _t, 0.0, 1.0))
