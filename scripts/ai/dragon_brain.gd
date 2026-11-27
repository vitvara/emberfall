class_name DragonBrain
extends RefCounted
## Vyrathax, the Cinder Tyrant. Three phases — see DESIGN.md §5.

var unit: Unit
var world  # RaidWorld
var phase := 0  # 0 = asleep, 1 = ground, 2 = air, 3 = final
var timers := {}
var melee_timer := 0.0
var air_time := 0.0
var waves_spawned := 0
var meteor_timer := 0.0
var enraged := false
var fly_height := 0.0
var B: Dictionary = GameData.BOSS


func _init(u: Unit, w) -> void:
	unit = u
	world = w


func tick(delta: float) -> void:
	if not unit.alive:
		return
	unit.position.y = lerpf(unit.position.y, fly_height, clampf(delta * 1.5, 0.0, 1.0))
	if phase == 0:
		if unit.in_combat:
			_start_phase1()
		return
	if not enraged and world.fight_time >= float(B["enrage_time"]):
		enraged = true
		unit.add_aura("enraged", unit)
		world.boss_emote("Vyrathax becomes ENRAGED!")
		world.boss_fx("enrage")
		timers["pulse"] = 0.0
	match phase:
		1:
			_ground(delta, false)
			if unit.hp_pct() <= float(B["phase2_at"]) and not unit.is_casting():
				_take_off()
		2:
			_air(delta)
		3:
			_ground(delta, true)


func dmg(base) -> float:
	return float(base) * unit.get_mod("damage_done")


# ------------------------------------------------------------------ phases

func _start_phase1() -> void:
	phase = 1
	timers = {"claw": 6.0, "breath": 14.0, "tail": 9.0, "pools": 11.0}
	world.boss_emote("Vyrathax: \"Insects! You dare wake me?\"")
	world.boss_fx("wake")


func _take_off() -> void:
	phase = 2
	air_time = 0.0
	waves_spawned = 0
	meteor_timer = 4.0
	unit.untargetable = true
	unit.casting = {}
	fly_height = 9.0
	world.boss_emote("Vyrathax takes to the sky! Ember Whelps swarm in!")
	world.boss_fx("takeoff")


func _land() -> void:
	phase = 3
	unit.untargetable = false
	fly_height = 0.0
	var cat: Dictionary = B["cataclysm"]
	timers = {"claw": 5.0, "breath": 12.0, "tail": 8.0, "pools": 10.0,
		"pulse": 6.0, "cataclysm": float(cat["first"])}
	world.boss_emote("Vyrathax lands in a fury: \"BURN, ALL OF YOU!\"")
	world.boss_fx("land")


func _air(delta: float) -> void:
	air_time += delta
	unit.move_toward_point(Vector3.ZERO, delta, 4.0, false)
	var waves: Array = B["whelp"]["waves"]
	if waves_spawned < waves.size() and air_time >= float(waves[waves_spawned]):
		waves_spawned += 1
		for i in int(B["whelp"]["count"]):
			var a := TAU * (i / float(B["whelp"]["count"])) + randf() * 0.5
			world.spawn_whelp(Vector3(cos(a), 0, sin(a)) * 26.0)
	meteor_timer -= delta
	if meteor_timer <= 0.0:
		var m: Dictionary = B["meteor"]
		meteor_timer = float(m["interval"])
		var party: Array = world.party_alive()
		party.shuffle()
		for i in mini(int(m["count"]), party.size()):
			var h := Hazard.circle(party[i].position, m["radius"], m["delay"], dmg(m["damage"]), "Meteor", unit)
			world.add_hazard(h)
	if air_time >= float(B["air_duration"]):
		_land()


func _ground(delta: float, final_phase: bool) -> void:
	var tgt := unit.get_threat_target()
	if tgt == null:
		return
	if unit.is_casting():
		return  # facing locked while casting
	unit.target = tgt
	if not unit.in_range(tgt, GameData.MELEE_RANGE):
		unit.move_toward_point(tgt.flat_pos(), delta, 5.0)
	else:
		unit.turn_toward(tgt, delta, 4.0)

	for k in timers.keys():
		timers[k] = float(timers[k]) - delta

	melee_timer -= delta
	if melee_timer <= 0.0 and unit.in_range(tgt, GameData.MELEE_RANGE):
		melee_timer = float(B["melee"]["interval"])
		world.on_auto_attack(unit, tgt)
		tgt.take_damage(dmg(B["melee"]["damage"]), "physical", unit, "Melee", false, 1.0, true)

	var speed := 0.8 if final_phase else 1.0  # timers run faster in phase 3
	if timers["claw"] <= 0.0 and unit.in_range(tgt, GameData.MELEE_RANGE):
		timers["claw"] = float(B["rending_claw"]["interval"]) * speed
		world.boss_fx("claw", tgt)
		tgt.take_damage(dmg(B["rending_claw"]["damage"]), "physical", unit, "Rending Claw")
		tgt.add_aura("seared", unit)
	if timers["breath"] <= 0.0:
		timers["breath"] = float(B["flame_breath"]["interval"]) * speed
		_flame_breath()
		return
	if timers["tail"] <= 0.0:
		timers["tail"] = float(B["tail_lash"]["interval"]) * speed
		_tail_lash()
	if timers["pools"] <= 0.0:
		timers["pools"] = float(B["cinder_pools"]["interval"]) * speed
		_cinder_pools()
	if final_phase:
		if timers["pulse"] <= 0.0:
			var pulse: Dictionary = B["inferno_pulse"]
			timers["pulse"] = 3.0 if enraged else float(pulse["interval"])
			world.boss_fx("pulse")
			for p in world.party_alive():
				p.take_damage(dmg(pulse["damage"]), "fire", unit, "Inferno Pulse")
		if timers["cataclysm"] <= 0.0:
			timers["cataclysm"] = float(B["cataclysm"]["interval"])
			_cataclysm()


# ------------------------------------------------------------------ abilities

func _flame_breath() -> void:
	var fb: Dictionary = B["flame_breath"]
	var h := Hazard.cone(unit.position, unit.forward(), fb["length"], fb["half_angle"], fb["cast"],
		dmg(fb["damage"]), "Flame Breath", unit)
	h.tank_soak = true
	world.add_hazard(h)
	unit.casting = {"name": "Flame Breath", "remaining": fb["cast"], "total": fb["cast"],
		"interruptible": false, "moving": true}
	world.boss_emote("Vyrathax inhales deeply... (Flame Breath)")


func _tail_lash() -> void:
	var tl: Dictionary = B["tail_lash"]
	var h := Hazard.cone(unit.position, -unit.forward(), tl["length"], tl["half_angle"], 1.2,
		dmg(tl["damage"]), "Tail Lash", unit)
	h.knockback = tl["knockback"]
	h.color = Color(1.0, 0.6, 0.1)
	world.add_hazard(h)


func _cinder_pools() -> void:
	var cp: Dictionary = B["cinder_pools"]
	var pool: Array = world.party_alive().filter(func(p): return p.role != GameData.ROLE_TANK)
	if pool.is_empty():
		pool = world.party_alive()
	pool.shuffle()
	for i in mini(int(cp["count"]), pool.size()):
		var h := Hazard.circle(pool[i].position, cp["radius"], 1.0, dmg(cp["dps"]), "Cinder Pool", unit)
		h.duration = cp["duration"]
		world.add_hazard(h)


func _cataclysm() -> void:
	var c: Dictionary = B["cataclysm"]
	unit.casting = {"name": "Cataclysm", "remaining": c["cast"], "total": c["cast"],
		"interruptible": true, "moving": true, "on_complete": _cataclysm_hit}
	world.boss_emote("Vyrathax begins casting CATACLYSM! Interrupt it!")
	world.boss_fx("cataclysm_start")


func _cataclysm_hit() -> void:
	world.boss_emote("Cataclysm engulfs the party!")
	world.boss_fx("cataclysm_hit")
	for p in world.party_alive():
		p.take_damage(dmg(B["cataclysm"]["damage"]), "fire", unit, "Cataclysm")
