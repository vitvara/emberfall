class_name Unit
extends Node3D
## Any combatant: player, bot, boss or add.
## Holds stats, resources, auras, cooldowns, casting and (for enemies) a threat table.
## All logic is driven by RaidWorld.tick() so the fight can also run headless.

var world  # RaidWorld
var brain = null  # object with tick(delta)
var model: Node3D
var nameplate: Label3D

# Identity
var unit_name := ""
var class_id := ""
var role := ""
var team := "party"
var is_player := false
var is_boss := false
var resource_type := "none"
var color := Color.WHITE
var radius := 0.5
var chest_height := 1.25
var ability_ids: Array = []

# Stats (see DESIGN.md §2)
var base_stats := {}
var max_hp_base := 1.0
var max_hp := 1.0
var hp := 1.0
var resource := 0.0
var max_resource := 0.0
var combo := 0
var armor := 0.0
var attack_power := 0.0
var spell_power := 0.0
var crit_phys := 0.0
var crit_spell := 0.0
var dodge := 0.0
var mana_regen := 0.0
var base_haste := 0.0
var threat_mult := 1.0
var auto_attack := {}

# State
var alive := true
var untargetable := false
var in_combat := false
var auras: Array = []
var cooldowns := {}
var gcd_remaining := 0.0
var gcd_total := 1.5
var casting := {}
var target: Unit = null
var threat := {}
var forced_target: Unit = null
var forced_target_time := 0.0
var auto_timer := 0.0
var moved_this_tick := false
var crit_streak := 0
var vy := 0.0
var grounded := true
# Networking
var net_id := -1
var owner_peer := 0        # 0 = bot / AI
var net_pos := Vector3.ZERO
var net_rot := 0.0
var net_dashing := false
var dash := {}  # {from, to, t, dur, height, on_land}

const GRAVITY := 22.0
const JUMP_SPEED := 7.5


# ------------------------------------------------------------------ setup

func setup_class(cid: String, display_name: String) -> void:
	var c: Dictionary = GameData.CLASSES[cid]
	class_id = cid
	unit_name = display_name
	role = c["role"]
	resource_type = c["resource"]
	color = c["color"]
	base_stats = c["stats"]
	threat_mult = c["threat_mult"]
	auto_attack = c["auto_attack"]
	ability_ids = c["abilities"]
	radius = 0.45
	_compute_stats()
	max_hp = max_hp_base
	hp = max_hp
	match resource_type:
		"mana":
			resource = max_resource
		"energy":
			max_resource = 100.0
			resource = 100.0
		"rage":
			max_resource = 100.0
			resource = 0.0
	model = Models.make_hero(cid, color)
	add_child(model)
	_make_nameplate(1.25 + 1.0)


func setup_mob(display_name: String, hp_value: float, armor_value: float, body_radius: float,
		mob_model: Node3D, plate_height: float, chest := 1.2) -> void:
	chest_height = chest
	unit_name = display_name
	team = "enemy"
	role = "enemy"
	max_hp_base = hp_value
	max_hp = hp_value
	hp = hp_value
	armor = armor_value
	radius = body_radius
	color = Color(1.0, 0.35, 0.25)
	model = mob_model
	add_child(model)
	_make_nameplate(plate_height)


func _compute_stats() -> void:
	var s := base_stats
	max_hp_base = 200.0 + float(s["sta"]) * 10.0
	attack_power = float(s["str"]) * 2.0 + float(s["agi"])
	spell_power = float(s["int"])
	crit_phys = float(s["crit"]) + float(s["agi"]) * 0.05
	crit_spell = float(s["crit"]) + float(s["int"]) * 0.03
	dodge = float(s["agi"]) * 0.04
	mana_regen = float(s["spi"]) * 0.2
	armor = float(s["armor"])
	base_haste = float(s["haste"])
	if resource_type == "mana":
		max_resource = float(s["int"]) * 15.0


func _make_nameplate(height: float) -> void:
	nameplate = Label3D.new()
	nameplate.text = unit_name
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.no_depth_test = true
	nameplate.fixed_size = true
	nameplate.pixel_size = 0.0009
	nameplate.font_size = 22
	nameplate.outline_size = 6
	nameplate.modulate = color if team == "party" else Color(1, 0.4, 0.3)
	nameplate.position = Vector3(0, height, 0)
	add_child(nameplate)


# ------------------------------------------------------------------ queries

func hp_pct() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0


func resource_pct() -> float:
	return resource / max_resource if max_resource > 0.0 else 0.0


func flat_pos() -> Vector3:
	return Vector3(position.x, 0.0, position.z)


func forward() -> Vector3:
	return Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))


func right() -> Vector3:
	return Vector3(cos(rotation.y), 0.0, -sin(rotation.y))


func distance_to_unit(o: Unit) -> float:
	return maxf(0.0, flat_pos().distance_to(o.flat_pos()) - radius - o.radius)


func in_range(o: Unit, r: float) -> bool:
	if r <= 0.0:
		return true
	return distance_to_unit(o) <= r


func is_casting() -> bool:
	return not casting.is_empty()


func cooldown_left(aid: String) -> float:
	return cooldowns.get(aid, 0.0)


func find_aura(aura_id: String, caster: Unit = null) -> Dictionary:
	for a in auras:
		if a["id"] == aura_id and (caster == null or a["caster"] == caster):
			return a
	return {}


func has_aura(aura_id: String, caster: Unit = null) -> bool:
	return not find_aura(aura_id, caster).is_empty()


func get_mod(key: String) -> float:
	var m := 1.0
	for a in auras:
		var mods: Dictionary = a["def"].get("mods", {})
		if mods.has(key):
			m *= float(mods[key])
	return m


func get_haste() -> float:
	var h := base_haste
	for a in auras:
		var mods: Dictionary = a["def"].get("mods", {})
		h += float(mods.get("haste", 0.0))
	return h


func haste_div() -> float:
	return 1.0 + get_haste() / 100.0


func fire_taken_bonus() -> float:
	var b := 0.0
	for a in auras:
		var sm: Dictionary = a["def"].get("stack_mods", {})
		b += float(sm.get("fire_taken", 0.0)) * float(a["stacks"])
	return b


func total_absorb() -> float:
	var t := 0.0
	for a in auras:
		t += float(a.get("absorb", 0.0))
	return t


# ------------------------------------------------------------------ tick

func tick(delta: float) -> void:
	if not alive:
		return
	for k in cooldowns.keys():
		cooldowns[k] = maxf(0.0, float(cooldowns[k]) - delta)
	gcd_remaining = maxf(0.0, gcd_remaining - delta)
	forced_target_time -= delta
	_tick_auras(delta)
	if not alive:
		return
	if not dash.is_empty():
		_tick_dash(delta)
	else:
		tick_jump(delta)
	_tick_resource(delta)
	_tick_cast(delta)
	_tick_auto_attack(delta)
	moved_this_tick = false


func _tick_auras(delta: float) -> void:
	var i := auras.size() - 1
	while i >= 0:
		if i >= auras.size():
			i -= 1
			continue
		var a: Dictionary = auras[i]
		var def: Dictionary = a["def"]
		a["remaining"] = float(a["remaining"]) - delta
		if def.has("tick"):
			a["tick_timer"] = float(a["tick_timer"]) - delta
			if float(a["tick_timer"]) <= 0.0:
				a["tick_timer"] = float(a["tick_timer"]) + float(def["tick"])
				_aura_tick(a)
				if not alive:
					return
		var expired: bool = float(a["remaining"]) <= 0.0
		if def.has("absorb") and float(a["absorb"]) <= 0.0:
			expired = true
		if expired and i < auras.size() and is_same(auras[i], a):
			auras.remove_at(i)
			_refresh_max_hp()
		i -= 1


func _aura_tick(a: Dictionary) -> void:
	var e: Dictionary = a["def"]["tick_effect"]
	var caster: Unit = a["caster"]
	if caster == null:
		return
	if e["type"] == "heal":
		var r: Array = caster.roll(e["base"], e["coef"], "holy", true)
		receive_heal(r[0], caster, a["def"]["name"], r[1])
	elif e["type"] == "heal_pct":
		receive_heal(max_hp * float(e["pct"]), caster, a["def"]["name"])
	else:
		var r2: Array = caster.roll(e["base"], e["coef"], e["school"], false)
		take_damage(r2[0], e["school"], caster, a["def"]["name"], r2[1])


func _tick_resource(delta: float) -> void:
	match resource_type:
		"mana":
			resource = minf(max_resource, resource + mana_regen * delta)
		"energy":
			resource = minf(max_resource, resource + 10.0 * delta)
		"rage":
			if not world.combat_active:
				resource = maxf(0.0, resource - 3.0 * delta)


func _tick_cast(delta: float) -> void:
	if casting.is_empty():
		return
	if moved_this_tick and not casting.get("moving", false):
		world.on_cast_cancelled(self, casting["name"])
		casting = {}
		return
	casting["remaining"] = float(casting["remaining"]) - delta
	if float(casting["remaining"]) > 0.0:
		return
	var c := casting
	casting = {}
	var aid: String = c.get("ability_id", "")
	if aid != "":
		var ab: Dictionary = GameData.ABILITIES[aid]
		if resource >= float(ab["cost"]):
			_execute(aid, c["target"], c.get("point"))
	else:
		var cb: Callable = c.get("on_complete", Callable())
		if cb.is_valid():
			cb.call()


func _tick_auto_attack(delta: float) -> void:
	if auto_attack.is_empty() or not world.combat_active:
		return
	auto_timer -= delta
	if auto_timer > 0.0:
		return
	if target != null and target.alive and target.team != team and not target.untargetable \
			and in_range(target, GameData.MELEE_RANGE):
		auto_timer = float(auto_attack["interval"]) / haste_div()
		var r: Array = roll(auto_attack["base"], auto_attack["coef"], "physical", false)
		world.on_auto_attack(self, target)
		target.take_damage(r[0], "physical", self, "Attack", r[1])
	else:
		auto_timer = 0.2


# ------------------------------------------------------------------ abilities

func resolve_target(aid: String, tgt: Unit) -> Unit:
	var ab: Dictionary = GameData.ABILITIES[aid]
	match ab["target"]:
		"enemy":
			if tgt != null and tgt.team != team:
				return tgt
			return null
		"ally":
			if tgt != null and tgt.team == team and tgt.alive:
				return tgt
			return self
		"dead_ally":
			if tgt != null and tgt.team == team and not tgt.alive:
				return tgt
			return null
	return self


func is_dashing() -> bool:
	return not dash.is_empty()


## Returns "" if the ability can be used, otherwise a reason string.
## `point` is the ground target for "ground" abilities.
func can_use(aid: String, tgt: Unit, point = null) -> String:
	if not alive:
		return "You are dead"
	var ab: Dictionary = GameData.ABILITIES[aid]
	if is_dashing():
		return "Busy"
	if is_casting():
		return "Already casting"
	if cooldown_left(aid) > 0.0:
		return "Not ready yet"
	if ab["gcd"] and gcd_remaining > 0.0:
		return "GCD"
	if resource < float(ab["cost"]):
		return "Not enough " + resource_type
	if ab.get("needs_combo", false) and combo <= 0:
		return "No combo points"
	if float(ab["cast"]) > 0.0 and moved_this_tick and not ab.get("moving", false):
		return "Can't do that while moving"
	var t := resolve_target(aid, tgt)
	match ab["target"]:
		"enemy":
			if t == null or not t.alive:
				return "No enemy target"
			if t.untargetable:
				return "Target is immune"
			if ab.has("below_pct") and t.hp_pct() >= float(ab["below_pct"]):
				return "Target must be below %d%% health" % int(float(ab["below_pct"]) * 100)
			if ab.has("min_range") and distance_to_unit(t) < float(ab["min_range"]):
				return "Too close"
		"dead_ally":
			if t == null:
				return "Target a dead party member"
		"ground":
			if point == null:
				return "Choose a spot"
			var pt: Vector3 = point
			if flat_pos().distance_to(Vector3(pt.x, 0, pt.z)) > float(ab["range"]) + 0.5:
				return "Out of range"
	if ab["target"] in ["enemy", "ally", "dead_ally"]:
		if t != self and not in_range(t, ab["range"]):
			return "Out of range"
	return ""


func use_ability(aid: String, tgt: Unit, point = null) -> String:
	var err := can_use(aid, tgt, point)
	if err != "":
		return err
	var ab: Dictionary = GameData.ABILITIES[aid]
	var t := resolve_target(aid, tgt)
	var cast_time: float = ab["cast"]
	if ab["gcd"]:
		var g: float = GameData.ENERGY_GCD if resource_type == "energy" else GameData.BASE_GCD
		gcd_total = maxf(0.75, g / haste_div())
		gcd_remaining = gcd_total
	if cast_time > 0.0:
		var total := cast_time / haste_div()
		casting = {"name": ab["name"], "ability_id": aid, "target": t, "point": point, "remaining": total,
			"total": total, "interruptible": true, "moving": ab.get("moving", false)}
		face_toward(t)
	else:
		_execute(aid, t, point)
	return ""


func _execute(aid: String, t: Unit, point = null) -> void:
	var ab: Dictionary = GameData.ABILITIES[aid]
	match ab["target"]:
		"enemy", "ally":
			if t == null or not t.alive:
				return
		"dead_ally":
			if t == null or t.alive:
				return
	resource -= float(ab["cost"])
	if float(ab["cd"]) > 0.0:
		cooldowns[aid] = float(ab["cd"])
	if point != null:
		face_point(point)
	else:
		face_toward(t)
	var land := func(): _apply_effects(ab, t, point)
	if point != null and SkillFx.has_ground_projectile(aid) and not world.instant_spells:
		# Thrown at a spot (Poison Bomb): the effect starts where it lands.
		world.on_ground_projectile(self, point, aid)
		if world.visuals:
			SkillFx.launch_ground(world, self, point, aid, land)
		else:
			world.get_tree().create_timer(SkillFx.ground_flight_time(self, point)).timeout.connect(land)
	elif SkillFx.has_projectile(aid) and t != null and t != self and not world.instant_spells:
		# Spell damage lands when the missile arrives.
		world.on_projectile(self, t, aid)
		if world.visuals:
			SkillFx.launch(world, self, t, aid, land)
		else:
			world.get_tree().create_timer(SkillFx.flight_time(self, t, aid)).timeout.connect(land)
	else:
		land.call()
	world.on_ability_used(self, aid, t, point)


func _apply_effects(ab: Dictionary, t: Unit, point = null) -> void:
	if (ab["target"] == "enemy" or ab["target"] == "ally") and (t == null or not t.alive):
		return
	for e in ab["effects"]:
		_apply_effect(e, t, ab, point)


func _apply_effect(e: Dictionary, t: Unit, ab: Dictionary, point = null) -> void:
	match e["type"]:
		"damage":
			var r: Array = roll(e["base"], e["coef"], e["school"], false)
			t.take_damage(r[0], e["school"], self, ab["name"], r[1], e.get("threat", 1.0))
		"heal":
			var r: Array = roll(e["base"], e["coef"], "holy", true)
			t.receive_heal(r[0], self, ab["name"], r[1])
		"aura":
			match e["on"]:
				"self":
					add_aura(e["aura"], self)
				"target":
					if t.alive:
						t.add_aura(e["aura"], self)
				"party":
					for u in world.party_alive():
						u.add_aura(e["aura"], self)
		"cone_damage":
			for en in world.enemies_alive():
				var to: Vector3 = en.flat_pos() - flat_pos()
				var d := to.length()
				if d - en.radius > float(e["length"]):
					continue
				if d > en.radius + 0.5 and rad_to_deg(forward().angle_to(to / d)) > float(e["half_angle"]):
					continue
				var r: Array = roll(e["base"], e["coef"], e["school"], false)
				en.take_damage(r[0], e["school"], self, ab["name"], r[1], e.get("threat", 1.0))
				if e.has("aura") and en.alive:
					en.add_aura(e["aura"], self)
		"taunt":
			t.taunted_by(self)
		"resource":
			add_resource(float(e["amount"]))
		"combo":
			var gain := int(e["amount"])
			if randf() < float(e.get("bonus_chance", 0.0)):
				gain += 1
			combo = mini(5, combo + gain)
		"finisher":
			var pts := combo
			combo = 0
			var r: Array = roll(float(e["base"]) * pts, float(e["coef"]) * pts, e["school"], false)
			t.take_damage(r[0], e["school"], self, ab["name"], r[1])
		"finisher_aura":
			var pts2 := combo
			combo = 0
			add_aura(e["aura"], self, float(e["base_dur"]) + float(e["per_point"]) * pts2)
		"interrupt":
			t.interrupt(self)
		"blink":
			var from := position
			position = world.clamp_to_arena(position + forward() * float(e["distance"]))
			world.on_blink(self, from, position)
		"threat_drop":
			for en in world.units:
				if en.team != team and en.threat.has(self):
					en.threat[self] = float(en.threat[self]) * float(e["keep"])
		"revive":
			t.revive(float(e["pct"]), self)
		"charge":
			var away := flat_pos() - t.flat_pos()
			if away.length() < 0.1:
				away = Vector3(0, 0, 1)
			var dest := t.flat_pos() + away.normalized() * (t.radius + radius + 1.0)
			start_dash(dest, 0.0, 30.0, func(): world.on_dash_landed(self, "charge", 2.0))
		"leap":
			var pt: Vector3 = point
			var land := func():
				for en in world.enemies_alive():
					if flat_pos().distance_to(en.flat_pos()) - en.radius <= float(ab.get("radius", 8.0)):
						var r: Array = roll(e["base"], e["coef"], e["school"], false)
						en.take_damage(r[0], e["school"], self, ab["name"], r[1], e.get("threat", 1.0))
				world.on_dash_landed(self, "leap", float(ab.get("radius", 8.0)))
			start_dash(world.clamp_to_arena(Vector3(pt.x, 0, pt.z)), 5.0, 22.0, land)
		"zone":
			var z := GroundZone.new().setup(world, self, e, ab["name"], float(ab.get("radius", 8.0)), point)
			world.add_zone(z)


## Rolls base + coef × power with variance, crit and damage mods. Returns [amount, crit].
func roll(base, coef, school: String, is_heal: bool) -> Array:
	var power: float = attack_power if (school == "physical" or school == "bleed") else spell_power
	var amt: float = (float(base) + float(coef) * power) * randf_range(0.95, 1.05)
	var chance: float = crit_phys if (school == "physical" or school == "bleed") else crit_spell
	var crit := randf() * 100.0 < chance
	if crit:
		amt *= 1.5 if is_heal else 2.0
	if not is_heal:
		amt *= get_mod("damage_done")
	return [amt, crit]


# ------------------------------------------------------------------ receiving

func take_damage(amount: float, school: String, source: Unit, label: String, crit := false,
		threat_factor := 1.0, can_dodge := false) -> float:
	if not alive or untargetable:
		return 0.0
	if can_dodge and randf() * 100.0 < dodge:
		world.on_dodge(self, source)
		return 0.0
	var amt := amount
	if school == "physical":
		amt *= 1.0 - armor / (armor + 4000.0)
	if school == "fire":
		amt *= 1.0 + fire_taken_bonus()
	amt *= get_mod("damage_taken")
	var absorbed := 0.0
	for a in auras:
		if a.has("absorb") and float(a["absorb"]) > 0.0 and amt > 0.0:
			var soak := minf(float(a["absorb"]), amt)
			a["absorb"] = float(a["absorb"]) - soak
			amt -= soak
			absorbed += soak
	hp -= amt
	in_combat = true
	world.start_combat()
	if resource_type == "rage":
		add_resource((amt + absorbed) / 20.0)
	if source != null and source != self:
		if source.resource_type == "rage":
			source.add_resource(amt / 30.0)
		if team == "enemy" and source.team == "party":
			add_threat(source, (amt + absorbed) * threat_factor * source.threat_mult)
	world.on_damage(self, source, amt, absorbed, crit, label, school)
	if hp <= 0.0:
		die()
	return amt


func receive_heal(amount: float, source: Unit, label: String, crit := false) -> void:
	if not alive:
		return
	var eff := minf(amount, max_hp - hp)
	hp += eff
	world.on_heal(self, source, eff, amount - eff, crit, label)
	if source != null:
		world.add_heal_threat(source, eff)


func add_resource(amount: float) -> void:
	if max_resource > 0.0:
		resource = clampf(resource + amount, 0.0, max_resource)


func add_aura(aura_id: String, caster: Unit, duration_override := -1.0) -> void:
	if not alive:
		return
	var def: Dictionary = GameData.AURAS[aura_id]
	var per_caster: bool = def.has("tick")
	var a := find_aura(aura_id, caster if per_caster else null)
	if a.is_empty():
		a = {"id": aura_id, "def": def, "remaining": def["duration"], "stacks": 1,
			"tick_timer": def.get("tick", 0.0), "caster": caster, "absorb": 0.0}
		auras.append(a)
	else:
		a["remaining"] = def["duration"]
		a["stacks"] = mini(int(a["stacks"]) + 1, int(def.get("max_stacks", 1)))
	if duration_override > 0.0:
		a["remaining"] = duration_override
	if def.has("absorb"):
		var ab: Dictionary = def["absorb"]
		a["absorb"] = float(ab["base"]) + float(ab["coef"]) * caster.spell_power
	_refresh_max_hp()
	if def.has("apply_heal_pct"):
		receive_heal(max_hp * float(def["apply_heal_pct"]), caster, def["name"])


func remove_aura(aura_id: String) -> void:
	for i in range(auras.size() - 1, -1, -1):
		if auras[i]["id"] == aura_id:
			auras.remove_at(i)
	_refresh_max_hp()


func _refresh_max_hp() -> void:
	var old := max_hp
	max_hp = max_hp_base * get_mod("max_hp")
	if max_hp > old:
		hp += max_hp - old
	hp = minf(hp, max_hp)


func interrupt(source: Unit) -> bool:
	if casting.is_empty() or not casting.get("interruptible", false):
		return false
	world.on_interrupted(self, source, casting["name"])
	casting = {}
	return true


func die() -> void:
	alive = false
	hp = 0.0
	casting = {}
	auras.clear()
	vy = 0.0
	if nameplate:
		nameplate.modulate = Color(0.5, 0.5, 0.5)
	world.on_unit_died(self)


# ------------------------------------------------------------------ threat

func add_threat(src: Unit, amount: float) -> void:
	threat[src] = float(threat.get(src, 0.0)) + amount


func top_threat_value() -> float:
	var best := 0.0
	for u in threat:
		if u.alive:
			best = maxf(best, float(threat[u]))
	return best


func taunted_by(src: Unit) -> void:
	if team != "enemy":
		return
	threat[src] = top_threat_value() * 1.1 + 100.0
	forced_target = src
	forced_target_time = 3.0
	target = src
	in_combat = true
	world.start_combat()


func get_threat_target() -> Unit:
	if forced_target_time > 0.0 and forced_target != null and forced_target.alive:
		return forced_target
	var best: Unit = null
	var best_v := -1.0
	for u in threat:
		if u.alive and float(threat[u]) > best_v:
			best = u
			best_v = float(threat[u])
	if target != null and target.alive and threat.has(target):
		if best_v <= float(threat[target]) * 1.1:
			return target
	return best


# ------------------------------------------------------------------ movement

func face_toward(t: Unit) -> void:
	if t == null or t == self:
		return
	var d := t.flat_pos() - flat_pos()
	if d.length() > 0.01:
		rotation.y = atan2(-d.x, -d.z)


func turn_toward(t: Unit, delta: float, speed: float) -> void:
	if t == null:
		return
	var d := t.flat_pos() - flat_pos()
	if d.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), clampf(speed * delta, 0.0, 1.0))


func face_point(p) -> void:
	if p == null:
		return
	var pt: Vector3 = p
	var d := Vector3(pt.x, 0, pt.z) - flat_pos()
	if d.length() > 0.01:
		rotation.y = atan2(-d.x, -d.z)


## Fast movement to a point (charge, leap). height > 0 makes it an arc.
func start_dash(to: Vector3, height: float, speed: float, on_land: Callable) -> void:
	var from := flat_pos()
	var dist := from.distance_to(to)
	dash = {"from": from, "to": to, "t": 0.0, "dur": maxf(0.15, dist / speed), "height": height, "on_land": on_land}
	casting = {}
	face_point(to)
	grounded = true
	vy = 0.0


func _tick_dash(delta: float) -> void:
	dash["t"] = float(dash["t"]) + delta
	var f := clampf(float(dash["t"]) / float(dash["dur"]), 0.0, 1.0)
	var p: Vector3 = (dash["from"] as Vector3).lerp(dash["to"], f)
	p.y = sin(f * PI) * float(dash["height"])
	position = p
	moved_this_tick = true
	if f >= 1.0:
		position.y = 0.0
		var cb: Callable = dash["on_land"]
		dash = {}
		if cb.is_valid():
			cb.call()


func revive(pct: float, source: Unit) -> void:
	if alive:
		return
	alive = true
	auras.clear()
	_refresh_max_hp()
	hp = max_hp * pct
	resource = max_resource * 0.2 if resource_type == "mana" else 0.0
	combo = 0
	casting = {}
	if team == "enemy":
		return
	for e in world.units:
		if e.team != team and e.alive and e.in_combat:
			e.add_threat(self, 1.0)
	if nameplate:
		nameplate.modulate = color
	world.on_revived(self, source)


## Jump arc (also run on clients for the locally controlled character).
func tick_jump(delta: float) -> void:
	if grounded:
		return
	vy -= GRAVITY * delta
	position.y += vy * delta
	if position.y <= 0.0:
		position.y = 0.0
		vy = 0.0
		grounded = true


func jump() -> void:
	if not alive or not grounded or team != "party":
		return
	grounded = false
	vy = JUMP_SPEED
	position.y = maxf(position.y, 0.01)
	moved_this_tick = true


## Moves toward a ground point. Returns true when arrived.
func move_toward_point(p: Vector3, delta: float, speed: float, turn := true) -> bool:
	var to := Vector3(p.x, 0.0, p.z) - flat_pos()
	var d := to.length()
	if d < 0.05:
		return true
	var step := minf(d, speed * get_mod("speed") * delta)
	var dir := to / d
	var y := position.y
	position = world.clamp_to_arena(position + dir * step)
	position.y = y
	moved_this_tick = true
	if turn:
		rotation.y = atan2(-dir.x, -dir.z)
	return step >= d
