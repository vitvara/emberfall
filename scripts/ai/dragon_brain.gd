class_name DragonBrain
extends RefCounted
## Vyrathax, the Cinder Tyrant. Three phases — see DESIGN.md §5.

var unit: Unit
var world  # RaidWorld
var phase := 0  # 0 = arriving (fly-in before the fight), 1 = ground, 2 = air, 3 = final
var timers := {}
var melee_timer := 0.0
var air_time := 0.0
var waves_spawned := 0
var meteor_timer := 0.0
var enraged := false
var fly_height := 0.0
var B: Dictionary = GameData.BOSS

## Entrance: Vyrathax circles far off in the ash clouds during the countdown, then sweeps in along
## this curve (quadratic Bézier, start -> control -> above the arena centre), lands and roars.
## Low over the lava sea so the party's camera (which looks down at them) sees him coming.
const ENTRY := [Vector3(-60, 6, -150), Vector3(32, 3, -60), Vector3(0, 6, 0)]
const FLY_IN_TIME := 6.0
const LAND_TIME := 1.8      # from touchdown to the roar that starts the fight
var _arrive_t := 0.0
var _landed_t := -1.0
var _hover_t := 0.0


static func entry_point(f: float) -> Vector3:
	var a: Vector3 = ENTRY[0].lerp(ENTRY[1], f)
	var b: Vector3 = ENTRY[1].lerp(ENTRY[2], f)
	return a.lerp(b, f)


func _init(u: Unit, w) -> void:
	unit = u
	world = w


func tick(delta: float) -> void:
	if not unit.alive:
		return
	if phase == 0:
		_arrive(delta)
		return
	unit.position.y = lerpf(unit.position.y, fly_height, clampf(delta * 1.5, 0.0, 1.0))
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

## Before the fight: hover far away until the countdown ends, fly in, land, roar.
func _arrive(delta: float) -> void:
	unit.untargetable = true
	if not world.started:
		_hover_t += delta
		unit.position = ENTRY[0] + Vector3(0, sin(_hover_t * 1.3) * 1.5, 0)
		unit.rotation.y = _yaw_along(entry_point(0.02) - ENTRY[0])
		return
	if _landed_t < 0.0:
		_arrive_t += delta
		var f := smoothstep(0.0, 1.0, minf(_arrive_t / FLY_IN_TIME, 1.0))
		var p := entry_point(f)
		var ahead := entry_point(minf(f + 0.03, 1.0))
		var yaw := _yaw_along(ahead - p) if f < 0.97 else PI
		unit.position = p
		unit.rotation.y = lerp_angle(unit.rotation.y, lerp_angle(yaw, PI, clampf((f - 0.7) / 0.3, 0.0, 1.0)),
			clampf(delta * 4.0, 0.0, 1.0))
		if _arrive_t >= FLY_IN_TIME:
			_landed_t = 0.0
			fly_height = 0.0
			world.boss_emote("Vyrathax descends upon the arena!")
			world.boss_fx("land")
		return
	_landed_t += delta
	unit.position.y = lerpf(unit.position.y, 0.0, clampf(delta * 2.5, 0.0, 1.0))
	unit.rotation.y = lerp_angle(unit.rotation.y, PI, clampf(delta * 3.0, 0.0, 1.0))
	if _landed_t >= LAND_TIME:
		unit.position.y = 0.0
		unit.untargetable = false
		unit.in_combat = true
		world.start_combat()
		_start_phase1()


## Yaw that faces along a flight direction (models face -Z at yaw 0).
static func _yaw_along(dir: Vector3) -> float:
	if Vector2(dir.x, dir.z).length() < 0.001:
		return PI
	return atan2(-dir.x, -dir.z)


func _start_phase1() -> void:
	phase = 1
	timers = {"claw": 6.0, "breath": 14.0, "tail": 9.0, "pools": 11.0}
	world.boss_emote("Vyrathax: \"Insects! You dare enter my domain?\"")
	world.boss_fx("wake")


func _take_off() -> void:
	phase = 2
	air_time = 0.0
	waves_spawned = 0
	meteor_timer = 4.0
	unit.untargetable = true
	unit.casting = {}
	fly_height = 20.0   # high enough that the huge dragon's wings clear the arena
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
		tgt = _nearest_hero()  # nobody has taunted or hit him yet
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


func _nearest_hero() -> Unit:
	var best: Unit = null
	for p in world.party_alive():
		if best == null or unit.distance_to_unit(p) < unit.distance_to_unit(best):
			best = p
	return best
