class_name BotBrain
extends RefCounted
## Party bot: Avoid -> Position -> Act, every tick. See DESIGN.md §6.

var unit: Unit
var world  # RaidWorld
var side := 1.0
var _danger_time := 0.0
var _reaction := 0.35
var _dodge_spot = null
var _repositioning := false
var _interrupt_wait := -1.0
var _delta := 0.0


func _init(u: Unit, w, side_sign: float) -> void:
	unit = u
	world = w
	side = side_sign if side_sign != 0.0 else 1.0
	_reaction = randf_range(0.2, 0.5)


func tick(delta: float) -> void:
	_delta = delta
	if not unit.alive or not world.started or unit.is_dashing():
		return
	# Non-tanks wait for the tank to pull and build a little threat.
	# Non-tanks wait for a tank to pull; with no tank in the party they open the fight themselves.
	var has_tank: bool = world.tank() != null
	if unit.role != GameData.ROLE_TANK and has_tank and (not world.combat_active or world.fight_time < 1.5):
		return
	_choose_target()
	if _avoid(delta):
		_act(true)
		return
	var moving := _position(delta)
	_act(moving)


# ------------------------------------------------------------------ targeting

func _choose_target() -> void:
	var boss: Unit = world.boss
	var whelps: Array = world.whelps_alive()
	var boss_ok: bool = boss.alive and not boss.untargetable
	match unit.role:
		GameData.ROLE_TANK:
			# Grab any whelp not attacking us first.
			var loose: Unit = null
			for w in whelps:
				if w.target != unit:
					if loose == null or w.distance_to_unit(unit) < loose.distance_to_unit(unit):
						loose = w
			if loose != null:
				unit.target = loose
			elif not whelps.is_empty() and not boss_ok:
				unit.target = whelps[0]
			elif boss_ok:
				unit.target = boss
			elif not whelps.is_empty():
				unit.target = whelps[0]
			else:
				unit.target = null
		GameData.ROLE_HEALER:
			unit.target = null
		_:
			if not whelps.is_empty():
				var low: Unit = whelps[0]
				for w in whelps:
					if w.hp < low.hp:
						low = w
				unit.target = low
			elif boss_ok:
				unit.target = boss
			else:
				unit.target = null


# ------------------------------------------------------------------ avoidance

func _danger_at(p: Vector3) -> bool:
	for h in world.hazards:
		if h.tank_soak and unit.role == GameData.ROLE_TANK:
			continue
		if h.contains(p):
			return true
	return false


func _boss_cone_unsafe(p: Vector3) -> bool:
	if unit.role == GameData.ROLE_TANK:
		return false
	var boss: Unit = world.boss
	if not boss.alive or boss.untargetable:
		return false
	var to := Vector3(p.x - boss.position.x, 0, p.z - boss.position.z)
	var d := to.length()
	if d < 0.5:
		return true
	var ang := rad_to_deg(boss.forward().angle_to(to / d))
	if ang < 55.0 and d < 32.0:
		return true  # breath side
	if ang > 125.0 and d < 16.0:
		return true  # tail side
	return false


func _avoid(delta: float) -> bool:
	if not _danger_at(unit.position):
		_danger_time = 0.0
		_dodge_spot = null
		return false
	_danger_time += delta
	if _danger_time < _reaction:
		return false
	if _dodge_spot == null or _danger_at(_dodge_spot):
		_dodge_spot = _find_safe_spot()
		if _dodge_spot != null:
			var far: float = unit.flat_pos().distance_to(_dodge_spot)
			if far > 4.0 and "sprint" in unit.ability_ids:
				_try("sprint")
			if far > 6.0 and "flicker" in unit.ability_ids and unit.cooldown_left("flicker") <= 0.0:
				unit.face_point(_dodge_spot)
				if _try("flicker"):
					_dodge_spot = null
					return true
	if _dodge_spot == null:
		return false
	unit.move_toward_point(_dodge_spot, delta, GameData.MOVE_SPEED)
	return true


func _find_safe_spot():
	var slot = _desired_slot()
	var best = null
	var best_score := INF
	for dist in [3.0, 5.0, 7.5, 10.0, 13.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var p: Vector3 = world.clamp_to_arena(unit.flat_pos() + Vector3(cos(a), 0, sin(a)) * dist)
			if _danger_at(p) or _boss_cone_unsafe(p):
				continue
			var score: float = dist
			if slot != null:
				score += 0.35 * p.distance_to(slot)
			if score < best_score:
				best_score = score
				best = p
		if best != null:
			return best
	return best


# ------------------------------------------------------------------ positioning

func _desired_slot():
	var boss: Unit = world.boss
	var t: Unit = unit.target
	match unit.role:
		GameData.ROLE_TANK:
			if t == null:
				return null
			if t == boss and boss.target != null and boss.target != unit and boss.target.role == GameData.ROLE_TANK:
				# Another tank holds the dragon: fight from the flank like melee
				return world.clamp_to_arena(boss.flat_pos() + boss.right() * side * (boss.radius + 2.2)
					+ boss.forward() * -0.5)
			if t == boss:
				# Hold the dragon facing south, away from the flanks.
				var spot := boss.flat_pos() + Vector3(0, 0, 1) * (boss.radius + unit.radius + 2.0)
				if unit.flat_pos().distance_to(boss.flat_pos()) > boss.radius + 6.0:
					return spot
				return spot
			return _melee_spot_on(t)
		GameData.ROLE_MELEE:
			if t == null:
				return null
			if t == boss:
				return world.clamp_to_arena(boss.flat_pos() + boss.right() * side * (boss.radius + 2.2)
					+ boss.forward() * -0.5)
			return _melee_spot_on(t)
		_:
			# Ranged 16 m out, healer 10 m: everyone stays inside the healer's 30 m range.
			var ranged_dist := 16.0 if unit.role == GameData.ROLE_RANGED else 10.0
			if boss.alive and not boss.untargetable:
				var fwd_shift := 2.0
				return world.clamp_to_arena(boss.flat_pos() + boss.right() * side * ranged_dist
					+ boss.forward() * fwd_shift)
			# Boss in the air: spread out near the middle, stay in range of whelps.
			var base := Vector3(side * 11.0, 0, 6.0 if unit.role == GameData.ROLE_HEALER else -4.0)
			if t != null and unit.flat_pos().distance_to(t.flat_pos()) > 26.0:
				return t.flat_pos() + (unit.flat_pos() - t.flat_pos()).normalized() * 20.0
			return base


func _melee_spot_on(t: Unit) -> Vector3:
	var away := unit.flat_pos() - t.flat_pos()
	if away.length() < 0.1:
		away = Vector3(0, 0, 1)
	return t.flat_pos() + away.normalized() * (t.radius + unit.radius + 1.0)


## If the ideal slot is standing in fire, pick the nearest safe point around it.
func _safe_slot(slot):
	if slot == null:
		return null
	if not _danger_at(slot):
		return slot
	for dist in [2.0, 4.0, 6.0, 8.5, 11.0]:
		var best = null
		var best_d := INF
		for k in 12:
			var a := TAU * k / 12.0
			var p: Vector3 = world.clamp_to_arena(slot + Vector3(cos(a), 0, sin(a)) * dist)
			if _danger_at(p) or _boss_cone_unsafe(p):
				continue
			var d: float = p.distance_to(unit.flat_pos())
			if d < best_d:
				best_d = d
				best = p
		if best != null:
			return best
	return slot


func _position(delta: float) -> bool:
	var slot = _safe_slot(_desired_slot())
	if slot == null:
		return false
	var tol := 1.2
	if unit.role == GameData.ROLE_RANGED or unit.role == GameData.ROLE_HEALER:
		tol = 4.0
		if unit.is_casting():
			tol = 7.0
	var d: float = unit.flat_pos().distance_to(slot)
	if d > tol:
		_repositioning = true
	if _repositioning:
		if d < 0.4 or unit.move_toward_point(slot, delta, GameData.MOVE_SPEED):
			_repositioning = false
		return true
	return false


# ------------------------------------------------------------------ actions

func _try(aid: String, tgt: Unit = null) -> bool:
	return unit.use_ability(aid, tgt) == ""


func _try_ground(aid: String, point: Vector3) -> bool:
	return unit.use_ability(aid, null, point) == ""


func _act(moving: bool) -> void:
	if unit.is_casting() or unit.is_dashing():
		return
	match unit.role:
		GameData.ROLE_TANK:
			_act_tank()
		GameData.ROLE_HEALER:
			_act_healer(moving)
		GameData.ROLE_MELEE:
			if unit.class_id == "arms":
				_act_arms()
			else:
				_act_melee()
		GameData.ROLE_RANGED:
			_act_ranged(moving)


func _try_interrupt() -> bool:
	var boss: Unit = world.boss
	if not boss.alive or not boss.is_casting() or not boss.casting.get("interruptible", false):
		_interrupt_wait = -1.0
		return false
	if _interrupt_wait < 0.0:
		_interrupt_wait = randf_range(0.4, 1.8)
	_interrupt_wait -= _delta
	if _interrupt_wait > 0.0:
		return false
	for aid in ["throat_jab", "shield_bash", "counterspell"]:
		if aid in unit.ability_ids and _try(aid, boss):
			return true
	return false


## Centre of the enemies standing near `around` (for ground-targeted skills).
func _enemy_cluster(around: Unit, r: float) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for e in world.enemies_alive():
		if e.flat_pos().distance_to(around.flat_pos()) <= r:
			sum += e.flat_pos()
			n += 1
	return sum / n if n > 0 else around.flat_pos()


func _in_reach(p: Vector3, aid: String) -> bool:
	var ab: Dictionary = GameData.ABILITIES[aid]
	return unit.flat_pos().distance_to(p) <= float(ab["range"])


func _act_tank() -> void:
	var t: Unit = unit.target
	var boss: Unit = world.boss
	if t == null:
		return
	var dist := unit.distance_to_unit(t)
	if dist > 8.0 and dist <= 25.0 and _try("charge", t):
		return
	# Leap onto whelps that are loose on the party
	var loose: Array = world.whelps_alive().filter(func(w): return w.target != unit)
	if loose.size() >= 2:
		var c := _enemy_cluster(loose[0], 10.0)
		if _in_reach(c, "thunder_leap") and _try_ground("thunder_leap", c):
			return
	# Keep the taunt lock going: re-taunt when it is about to run out or the enemy is loose
	# (but don't steal it from another tank who holds it). The dragon comes first, whatever we target.
	if boss.alive and not boss.untargetable and world.combat_active and _needs_taunt(boss) \
			and _try("challenging_shout", boss):
		pass
	elif t != boss and _needs_taunt(t) and not _boss_lands_soon(boss):
		_try("challenging_shout", t)  # saved for the dragon when it is about to land
	var breath_on_me: bool = boss.is_casting() and boss.casting["name"] == "Flame Breath" and boss.target == unit
	if breath_on_me or (world.combat_active and unit.hp_pct() < 0.8 and unit.resource >= 40.0):
		_try("raise_shield")
	_try_interrupt()
	if t.hp_pct() < 0.2 and _try("execution_strike", t):
		return
	if _try("bulwark_strike", t):
		return
	# Thunder Leap on the boss for extra threat when everything else is on cooldown
	if t == boss and unit.resource >= 0.0 and unit.distance_to_unit(boss) <= GameData.MELEE_RANGE:
		_try_ground("thunder_leap", unit.flat_pos())


## The dragon is in the air and lands before Challenging Shout would come off cooldown.
func _boss_lands_soon(boss: Unit) -> bool:
	if not boss.untargetable or not boss.alive:
		return false
	var left: float = float(GameData.BOSS["air_duration"]) - float(world.boss_air_time())
	return left <= float(GameData.ABILITIES["challenging_shout"]["cd"]) + 1.0


## A tank should taunt this enemy: nobody's taunt holds it for long enough (another tank's is fine).
func _needs_taunt(e: Unit) -> bool:
	if not e.is_taunted():
		return true
	if e.forced_target == unit:
		return e.forced_target_time <= 4.0
	return e.forced_target.role != GameData.ROLE_TANK


func _act_healer(moving: bool) -> void:
	var party: Array = world.party_alive().filter(
		func(p): return p == unit or unit.in_range(p, GameData.SPELL_RANGE))
	if party.is_empty():
		return
	var lowest: Unit = party[0]
	for p in party:
		if p.hp_pct() < lowest.hp_pct():
			lowest = p
	var tank: Unit = world.tank()
	# Shake off anything chewing on the healer
	for e in world.enemies_alive():
		if e.target == unit and not e.is_boss:
			_try("fade")
			break
	if unit.hp_pct() < 0.35:
		_try("final_prayer")
	if tank != null and world.combat_active and not tank.has_aura("ward_of_dawn") and _try("ward_of_dawn", tank):
		return
	if lowest.hp_pct() < 0.5 and lowest != tank and not lowest.has_aura("ward_of_dawn") \
			and _try("ward_of_dawn", lowest):
		return
	# Sanctuary where the most hurt allies stand together
	var best_spot = null
	var best_n := 0
	for p in party:
		if p.hp_pct() >= 0.9:
			continue
		var n := 0
		for q in party:
			if q.hp_pct() < 0.9 and q.flat_pos().distance_to(p.flat_pos()) <= 7.0:
				n += 1
		if n > best_n:
			best_n = n
			best_spot = p.flat_pos()
	if best_spot != null and (best_n >= 2 or (tank != null and tank.hp_pct() < 0.7)):
		if _try_ground("sanctuary", best_spot):
			return
	if moving:
		return
	# Raise the dead when things are calm
	if lowest.hp_pct() > 0.5:
		for p in world.party_all():
			if not p.alive and unit.in_range(p, GameData.SPELL_RANGE) and _try("resurrection", p):
				return
	if lowest.hp_pct() < 0.8 and _try("flash_mend", lowest):
		return
	if lowest.hp_pct() > 0.95 and unit.resource_pct() > 0.6:
		var boss: Unit = world.boss
		if boss.alive and not boss.untargetable and world.combat_active:
			_try("smite", boss)


func _act_melee() -> void:
	if _try_interrupt():
		return
	if unit.hp_pct() < 0.5:
		_try("healing_draught")
	var t: Unit = unit.target
	if t == null:
		return
	if t.alive and not t.untargetable and _in_reach(t.flat_pos(), "poison_bomb"):
		if _try_ground("poison_bomb", _enemy_cluster(t, 6.0)):
			return
	if not unit.in_range(t, GameData.MELEE_RANGE):
		return
	if not unit.has_aura("blade_rhythm") and unit.combo >= 2 and _try("blade_rhythm"):
		return
	if unit.combo >= 5 and _try("executioners_cut", t):
		return
	_try("wicked_strike", t)


## Arms Warden: charge in, keep the target sundered and bleeding, spin on packs, execute on procs.
func _act_arms() -> void:
	var t: Unit = unit.target
	if t == null or not t.alive or t.untargetable:
		return
	var d := unit.distance_to_unit(t)
	if d > 8.0 and d <= 25.0 and _try("charge", t):
		return
	var near: Array = world.enemies_alive().filter(
		func(e): return unit.flat_pos().distance_to(e.flat_pos()) - e.radius <= 8.0)
	if not unit.has_aura("steel_cyclone") and (near.size() >= 2 or (t.is_boss and t.has_aura("sundered"))) \
			and _try("steel_cyclone"):
		return
	if not unit.in_range(t, GameData.MELEE_RANGE):
		return
	if _try("execution_strike", t):  # below 20%, or Sudden Death is up
		return
	if not t.has_aura("sundered") and _try("sundering_blow", t):
		return
	var gash := t.find_aura("gashed", unit)
	if (gash.is_empty() or float(gash["remaining"]) < 4.0) and _try("deep_gash", t):
		return
	if _try("overwhelm", t):
		return
	_try("mortal_blow", t)


func _act_ranged(moving: bool) -> void:
	if _try_interrupt():
		return
	var t: Unit = unit.target
	if t == null or not unit.in_range(t, GameData.SPELL_RANGE):
		return
	if t.is_boss and world.fight_time > 4.0:
		var someone_hasted := false
		for p in world.party_alive():
			if p.has_aura("quickening"):
				someone_hasted = true
		if not someone_hasted:
			_try("quickening")
	if _try_ground("frost_storm", _enemy_cluster(t, 8.0)):
		return
	if not t.is_boss and unit.distance_to_unit(t) <= 10.0:
		unit.face_toward(t)
		if _try("frost_cone"):
			return
	if _try("flame_jolt", t):
		return
	if moving:
		return
	_try("frost_shard", t)


func _party_avg_hp() -> float:
	var party: Array = world.party_alive()
	if party.is_empty():
		return 1.0
	var s := 0.0
	for p in party:
		s += p.hp_pct()
	return s / party.size()
