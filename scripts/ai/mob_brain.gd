class_name MobBrain
extends RefCounted
## An ordinary monster out in the world: stands at its post until a hero comes close (or hits it),
## pulls its whole group, chases and strikes, and walks home to reset if dragged too far or if its
## target dies. Optional special: a fire nova (a ground hazard the hero can step out of).

var unit: Unit
var world   # FarmWorld (any RaidWorld with player + pull_group)
var home := Vector3.ZERO
var home_yaw := 0.0
var group := 0
var aggro_radius := 10.0
var leash := 30.0
var damage := 100.0
var interval := 2.0
var speed := 5.2
var reach := GameData.MELEE_RANGE
var label := "Strike"
var nova_every := 0.0           # > 0: cast a fire nova around itself this often
var nova_damage := 0.0
var _swing := 0.8
var _nova := 6.0
var _returning := false
var _stuck_t := 0.0
var _detour_t := 0.0
var _detour_side := 1.0


func _init(u: Unit, w) -> void:
	unit = u
	world = w
	home = u.position
	home_yaw = u.rotation.y


func tick(delta: float) -> void:
	if not unit.alive:
		return
	if _returning:
		unit.target = null
		if _steer(home, delta, 1.3):
			_returning = false
			unit.rotation.y = home_yaw
			unit.hp = unit.max_hp
			unit.in_combat = false
		return
	var tgt := unit.get_threat_target()
	if tgt == null or not tgt.alive:
		var p: Unit = world.player
		if p != null and p.alive and unit.flat_pos().distance_to(p.flat_pos()) < aggro_radius:
			world.pull_group(group, p)
			tgt = p
		elif unit.in_combat:
			_go_home()
			return
		else:
			return
	if unit.flat_pos().distance_to(home) > leash:
		_go_home()
		return
	unit.target = tgt
	unit.in_combat = true
	if not unit.in_range(tgt, reach - 1.6):
		_steer(tgt.flat_pos(), delta)
	else:
		unit.turn_toward(tgt, delta, 8.0)
	_swing -= delta
	if _swing <= 0.0 and unit.in_range(tgt, reach):
		_swing = interval
		world.on_auto_attack(unit, tgt)
		tgt.take_damage(damage * unit.get_mod("damage_done"), "physical", unit, label, false, 1.0, true)
	if nova_every > 0.0:
		_nova -= delta
		if _nova <= 0.0:
			_nova = nova_every
			world.mob_nova(unit, nova_damage)


## Walk toward a point; if a building or cart blocks the way (barely moving), sidestep around it for a moment.
func _steer(goal: Vector3, delta: float, k := 1.0) -> bool:
	var before := unit.flat_pos()
	var aim := goal
	if _detour_t > 0.0:
		_detour_t -= delta
		var to := goal - before
		to.y = 0.0
		aim = before + to.normalized().rotated(Vector3.UP, 1.2 * _detour_side) * 4.0
	var arrived := unit.move_toward_point(aim, delta, speed * k)
	var moved := unit.flat_pos().distance_to(before)
	if moved < speed * k * delta * 0.3 and not arrived:
		_stuck_t += delta
		if _stuck_t > 0.25:
			_stuck_t = 0.0
			_detour_t = 0.8
			_detour_side = -_detour_side if randf() < 0.3 else _detour_side
	else:
		_stuck_t = 0.0
	return arrived and _detour_t <= 0.0


func _go_home() -> void:
	_returning = true
	unit.threat.clear()
	unit.damage_by.clear()
	unit.target = null
