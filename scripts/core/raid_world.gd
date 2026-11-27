class_name RaidWorld
extends Node3D
## Owns every unit and hazard and advances the fight one tick at a time.
##
## net_role:
##   "offline" – solo game, everything local.
##   "server"  – authoritative simulation (host or dedicated). Sends snapshots + visual events.
##   "client"  – replica: no gameplay, applies snapshots and replays visual events.
## Every gameplay event has a visual half (_vis_*) that runs locally when visuals are on
## and is mirrored to clients through net_out().

signal message(text: String, color: Color)
signal emote(text: String)
signal fight_ended(victory: bool)
signal shake(strength: float)

var units: Array = []
var hazards: Array = []
var zones: Array = []
var pending: Array = []
var boss: Unit
var player: Unit
var visuals := true
var arena_radius := 30.0
var net_role := "offline"
var instant_spells := false  # headless balance sim: no projectile travel time
var by_id := {}
var _next_id := 101

var countdown := 5.0
var started := false
var combat_active := false
var fight_time := 0.0
var finished := false
var victory := false

var damage_done := {}
var damage_taken := {}  # Unit -> {label: amount}  (for balancing)
var move_time := {}
var healing_done := {}
var death_log: Array = []
var phase_log: Array = []

# Replicated boss state (client side)
var _snap_phase := 0
var _snap_air := 0.0
var _snap_count := 0
var synced := false  # client: first snapshot applied (positions are trustworthy)


## roster: Array of {"class": id, "peer": int (0 = bot), "name": String}
## local_peer: the peer id controlling `player` on this machine (0 = nobody, e.g. dedicated server).
func setup_roster(roster: Array, local_peer: int, autoplay: bool) -> void:
	var sides := [-1.0, 1.0, 1.0, -1.0]
	var side_i := 0
	for i in roster.size():
		var r: Dictionary = roster[i]
		var u := Unit.new()
		u.world = self
		u.setup_class(r["class"], r["name"])
		u.net_id = i
		u.owner_peer = int(r["peer"])
		u.position = Vector3(-6.0 + i * 3.0, 0.0, 20.0)
		u.net_pos = u.position
		var side: float = sides[side_i % sides.size()]
		side_i += 1
		u.set_meta("side", side)
		var is_local: bool = u.owner_peer != 0 and u.owner_peer == local_peer
		if is_local:
			u.is_player = true
			player = u
		if net_role != "client":
			if u.owner_peer == 0 or (is_local and autoplay):
				u.brain = BotBrain.new(u, self, side)
		_register(u)

	boss = Unit.new()
	boss.world = self
	var b: Dictionary = GameData.BOSS
	boss.setup_mob(b["name"], b["hp"], b["armor"], b["radius"], Models.make_dragon(), 11.5, 4.5)
	boss.is_boss = true
	boss.net_id = 100
	boss.position = Vector3.ZERO
	boss.net_pos = Vector3.ZERO
	boss.rotation.y = PI  # face the party (+Z)
	if net_role != "client":
		boss.brain = DragonBrain.new(boss, self)
	_register(boss)


## Solo convenience: the player takes the first slot of their class, bots fill the rest.
func setup(player_class: String, autoplay: bool) -> void:
	setup_roster(solo_roster(player_class), 1, autoplay)


static func solo_roster(player_class: String) -> Array:
	var roster: Array = []
	var used := false
	var name_idx := {}
	for cid in GameData.PARTY_LAYOUT:
		var mine: bool = not used and cid == player_class
		if mine:
			used = true
			roster.append({"class": cid, "peer": 1, "name": "You"})
		else:
			roster.append({"class": cid, "peer": 0, "name": bot_name(cid, name_idx)})
	return roster


static func bot_name(cid: String, name_idx: Dictionary) -> String:
	var k: int = name_idx.get(cid, 0)
	name_idx[cid] = k + 1
	var names: Array = GameData.BOT_NAMES[cid]
	return names[k % names.size()] + ("" if k < names.size() else " II")


func _register(u: Unit) -> void:
	add_child(u)
	units.append(u)
	by_id[u.net_id] = u


func unit_by_id(id) -> Unit:
	if id == null or int(id) < 0:
		return null
	return by_id.get(int(id), null)


func unit_of_peer(peer: int) -> Unit:
	for u in units:
		if u.owner_peer == peer and u.team == "party":
			return u
	return null


func spawn_whelp(pos: Vector3) -> Unit:
	var u := _make_whelp(_next_id, pos)
	_next_id += 1
	u.brain = WhelpBrain.new(u, self)
	pending.append(u)
	# Whelps start on a random non-tank so the tank has to pick them up.
	var pool := party_alive().filter(func(p): return p.role != GameData.ROLE_TANK)
	if pool.is_empty():
		pool = party_alive()
	if not pool.is_empty():
		u.add_threat(pool[randi() % pool.size()], 60.0)
	net_out("whelp", [u.net_id, u.position])
	if visuals:
		SkillFx.boss_event(self, boss, "whelp", u)
	return u


func _make_whelp(id: int, pos: Vector3) -> Unit:
	var w: Dictionary = GameData.BOSS["whelp"]
	var u := Unit.new()
	u.world = self
	u.setup_mob("Ember Whelp", w["hp"], 1500.0, 0.9, Models.make_dragon(0.26), 2.6, 1.7)
	u.net_id = id
	u.position = clamp_to_arena(pos)
	u.net_pos = u.position
	u.in_combat = true
	add_child(u)
	by_id[id] = u
	return u


func add_hazard(h: Hazard) -> void:
	h.world = self
	add_child(h)
	h.build_visual(visuals)
	hazards.append(h)
	net_out("hazard", [h.shape, h.position, h.radius, h.dir, h.half_angle, h.length, h.delay, h.duration,
		h.label, h.tank_soak, h.color, h.knockback])
	if visuals:
		SkillFx.hazard_created(self, h)


func add_zone(z: GroundZone) -> void:
	add_child(z)
	z.build_visual(visuals)
	zones.append(z)
	net_out("zone", [z.kind, z.duration, z.radius, z.position, z.label])


# ------------------------------------------------------------------ queries

func party_all() -> Array:
	return units.filter(func(u): return u.team == "party")


func party_alive() -> Array:
	return units.filter(func(u): return u.team == "party" and u.alive)


func enemies_alive() -> Array:
	return units.filter(func(u): return u.team == "enemy" and u.alive and not u.untargetable)


func whelps_alive() -> Array:
	return units.filter(func(u): return u.team == "enemy" and u.alive and not u.is_boss)


func tank() -> Unit:
	for u in units:
		if u.team == "party" and u.alive and u.role == GameData.ROLE_TANK:
			return u
	return null


func clamp_to_arena(p: Vector3) -> Vector3:
	var flat := Vector2(p.x, p.z)
	if flat.length() > arena_radius:
		flat = flat.normalized() * arena_radius
	return Vector3(flat.x, p.y, flat.y)


func boss_phase() -> int:
	if net_role == "client":
		return _snap_phase
	return boss.brain.phase if boss and boss.brain else 0


func boss_air_time() -> float:
	if net_role == "client":
		return _snap_air
	return boss.brain.air_time if boss and boss.brain else 0.0


# ------------------------------------------------------------------ loop (offline / server)

func tick(delta: float) -> void:
	if net_role == "client":
		client_tick(delta)
		return
	if finished:
		return
	if not started:
		countdown -= delta
		if countdown <= 0.0:
			started = true
			_say("Pull! Vyrathax awakens.", Color(1, 0.6, 0.2))
	if combat_active:
		fight_time += delta
	for u in units:
		if u.alive and u.brain != null:
			u.brain.tick(delta)
	for u in units:
		if u.moved_this_tick and u.team == "party":
			move_time[u] = float(move_time.get(u, 0.0)) + delta
		u.tick(delta)
	for h in hazards.duplicate():
		h.tick(delta)
		if h.done:
			hazards.erase(h)
			h.queue_free()
	for z in zones.duplicate():
		z.tick(delta)
		if z.done:
			zones.erase(z)
			z.queue_free()
	if not pending.is_empty():
		units.append_array(pending)
		pending.clear()
	_check_end()


func start_combat() -> void:
	if net_role == "client":
		return
	if not combat_active and started:
		combat_active = true
	elif not started:
		started = true
		combat_active = true


func _check_end() -> void:
	if not combat_active:
		return
	if not boss.alive:
		_end(true)
	elif party_alive().is_empty():
		_end(false)


func _end(won: bool) -> void:
	finished = true
	victory = won
	if won:
		_say("Vyrathax, the Cinder Tyrant has been defeated!", Color(1, 0.85, 0.3))
	else:
		_say("Your party has fallen...", Color(1, 0.3, 0.3))
	net_out("end", [won, fight_time, death_log])
	fight_ended.emit(won)


# ------------------------------------------------------------------ client replica

func client_tick(delta: float) -> void:
	# Smooth everything toward the last snapshot; the local player moves itself.
	if player != null and player.alive and not player.is_dashing() and player.brain != null:
		player.brain.tick(delta)
	if player != null:
		player.tick_jump(delta)
		player.moved_this_tick = false
	for u in units:
		var local_free: bool = u == player and u.alive and not u.net_dashing
		if not local_free:
			var k := clampf(delta * 14.0, 0.0, 1.0)
			u.position = u.position.lerp(u.net_pos, k)
			u.rotation.y = lerp_angle(u.rotation.y, u.net_rot, k)
		if not u.casting.is_empty():
			u.casting["remaining"] = maxf(0.0, float(u.casting["remaining"]) - delta)
	if player != null:
		player.gcd_remaining = maxf(0.0, player.gcd_remaining - delta)
		for k in player.cooldowns.keys():
			player.cooldowns[k] = maxf(0.0, float(player.cooldowns[k]) - delta)
	if not started:
		countdown = maxf(0.0, countdown - delta)
	elif combat_active and not finished:
		fight_time += delta
	for h in hazards.duplicate():
		h.tick(delta)
		if h.done:
			hazards.erase(h)
			h.queue_free()
	for z in zones.duplicate():
		z.tick(delta)
		if z.done:
			zones.erase(z)
			z.queue_free()


## Compact state of the whole fight, sent ~20x per second. Numbers ride in packed float arrays (no
## per-value type tags) so a deflated snapshot stays far below one network packet; players on Cloudflare
## WARP (inner MTU ~1280) lose any datagram that has to be fragmented.
## Layout: [fight_time, started, countdown, combat_active, phase, air, units, meters|null, threat, mine|null]
##   units:  [[nums, cast, aura_ids, aura_vals], ...]   nums = SNAP_FIELDS order
##   threat: PackedFloat32Array [id, value, id, value, ...]
##   mine:   per recipient (see own_state): [net_id, cooldowns, gcd_remaining, gcd_total]
func make_snapshot() -> Array:
	_snap_count += 1
	var us: Array = []
	for u in units:
		var cast = null
		if not u.casting.is_empty():
			cast = [u.casting["name"], u.casting["remaining"], u.casting["total"], u.casting.get("interruptible", false)]
		var ids := PackedStringArray()
		var vals := PackedFloat32Array()
		for a in u.auras:
			ids.append(a["id"])
			vals.append_array([a["remaining"], a["stacks"], a.get("absorb", 0.0)])
		var flags := (1 if u.alive else 0) | (2 if u.untargetable else 0) | (4 if u.is_dashing() else 0)
		var nums := PackedFloat32Array([u.net_id, u.position.x, u.position.y, u.position.z, u.rotation.y,
			u.hp, u.max_hp, u.resource, u.max_resource, u.combo, flags, u.target.net_id if u.target != null else -1])
		us.append([nums, cast, ids, vals])
	var meters = null
	if _snap_count % 10 == 0:
		meters = {}
		for u in party_all():
			meters[u.net_id] = [float(damage_done.get(u, 0.0)), float(healing_done.get(u, 0.0))]
	var threat := PackedFloat32Array()
	for u in boss.threat:
		if u.alive:
			threat.append_array([u.net_id, float(boss.threat[u])])
	return [fight_time, started, countdown, combat_active, boss_phase(), boss_air_time(), us, meters, threat, null]


## The part of a snapshot only the hero's own player needs (cooldowns, global cooldown).
func own_state(u: Unit) -> Array:
	return [u.net_id, u.cooldowns, u.gcd_remaining, u.gcd_total]


func apply_snapshot(s: Array) -> void:
	fight_time = s[0]
	started = s[1]
	countdown = s[2]
	combat_active = s[3]
	_snap_phase = s[4]
	_snap_air = s[5]
	var first := not synced
	synced = true
	for row in s[6]:
		var n: PackedFloat32Array = row[0]
		var u := unit_by_id(int(n[0]))
		if u == null:
			continue
		var flags := int(n[10])
		u.net_pos = Vector3(n[1], n[2], n[3])
		u.net_rot = n[4]
		u.net_dashing = flags & 4 != 0
		if first or (u == player and u.net_dashing):
			u.position = u.net_pos  # joining (or rejoining) mid-fight: start where the realm says
			u.rotation.y = u.net_rot
		u.hp = n[5]
		u.max_hp = n[6]
		u.resource = n[7]
		u.max_resource = n[8]
		u.combo = int(n[9])
		var was_alive := u.alive
		u.alive = flags & 1 != 0
		if was_alive != u.alive and u.nameplate:
			u.nameplate.modulate = Color(0.5, 0.5, 0.5) if not u.alive else (u.color if u.team == "party" else Color(1, 0.4, 0.3))
		u.untargetable = flags & 2 != 0
		if u != player:
			u.target = unit_by_id(int(n[11]))
		var c = row[1]
		if c == null:
			u.casting = {}
		else:
			u.casting = {"name": c[0], "remaining": c[1], "total": c[2], "interruptible": c[3], "moving": true}
		var ids: PackedStringArray = row[2]
		var vals: PackedFloat32Array = row[3]
		var auras: Array = []
		for i in ids.size():
			if GameData.AURAS.has(ids[i]):
				auras.append({"id": ids[i], "def": GameData.AURAS[ids[i]], "remaining": vals[i * 3],
					"stacks": int(vals[i * 3 + 1]), "absorb": vals[i * 3 + 2], "caster": null, "tick_timer": 0.0})
		u.auras = auras
	var mine = s[9] if s.size() > 9 else null
	if mine != null and player != null and int(mine[0]) == player.net_id:
		player.cooldowns = mine[1]
		player.gcd_remaining = mine[2]
		player.gcd_total = mine[3]
	if s[7] != null:
		for id in s[7]:
			var u := unit_by_id(id)
			if u != null:
				damage_done[u] = s[7][id][0]
				healing_done[u] = s[7][id][1]
	boss.threat.clear()
	var th: PackedFloat32Array = s[8]
	for i in range(0, th.size() - 1, 2):
		var u := unit_by_id(int(th[i]))
		if u != null:
			boss.threat[u] = th[i + 1]


# ------------------------------------------------------------------ network events

## Server: visual events that rebuild the current fight on a client that (re)joins mid-raid:
## live whelps, telegraphs and ground zones (with their remaining time), and the result if it is over.
func catchup_events() -> Array:
	var out: Array = []
	for u in units:
		if u.net_id > 100 and u.alive:
			out.append(["whelp", [u.net_id, u.position]])
	for h in hazards:
		if h.done:
			continue
		var warn: float = maxf(0.0, h.delay - h._t)
		var dur: float = h.duration - maxf(0.0, h._t - h.delay)
		if dur <= 0.0 and warn <= 0.0:
			continue
		out.append(["hazard", [h.shape, h.position, h.radius, h.dir, h.half_angle, h.length, warn, maxf(dur, 0.0),
			h.label, h.tank_soak, h.color, h.knockback]])
	for z in zones:
		if not z.done and z.duration - z._t > 0.3:
			out.append(["zone", [z.kind, z.duration - z._t, z.radius, z.position, z.label]])
	if finished:
		out.append(["end", [victory, fight_time, death_log]])
	return out


func net_out(ev: String, args: Array) -> void:
	if net_role == "server":
		Net.send_fx(ev, args)


## Replays a server event on a client replica.
func net_in(ev: String, a: Array) -> void:
	match ev:
		"msg":
			message.emit(a[0], a[1])
		"emote":
			emote.emit(a[0])
		"dmg":
			_vis_damage(unit_by_id(a[0]), unit_by_id(a[1]), a[2], a[3], a[4], a[5])
		"heal":
			_vis_heal(unit_by_id(a[0]), unit_by_id(a[1]), a[2], a[3], a[4])
		"dodge":
			var t := unit_by_id(a[0])
			if t and t.is_player:
				float_text(t, "Dodge", Color(0.8, 0.8, 1), false)
		"intr":
			var t2 := unit_by_id(a[0])
			if t2:
				float_text(t2, "Interrupted", Color(0.5, 0.9, 1), true)
		"ability":
			var c := unit_by_id(a[0])
			if c:
				SkillFx.ability(self, c, a[1], unit_by_id(a[2]), a[3])
		"auto":
			var c2 := unit_by_id(a[0])
			var t3 := unit_by_id(a[1])
			if c2 and t3:
				SkillFx.auto_attack(self, c2, t3)
		"blink":
			var c3 := unit_by_id(a[0])
			if c3:
				SkillFx.blink(self, c3, a[1], a[2])
		"landed":
			var c4 := unit_by_id(a[0])
			if c4:
				SkillFx.dash_landed(self, c4, a[1], a[2])
		"revived":
			var c5 := unit_by_id(a[0])
			if c5:
				SkillFx.revived(self, c5)
		"bossfx":
			SkillFx.boss_event(self, boss, a[0], unit_by_id(a[1]))
		"proj":
			var c6 := unit_by_id(a[0])
			var t4 := unit_by_id(a[1])
			if c6 and t4:
				SkillFx.launch(self, c6, t4, a[2], Callable())
		"projg":
			var c7 := unit_by_id(a[0])
			if c7:
				SkillFx.launch_ground(self, c7, a[1], a[2], Callable())
		"whelp":
			var w := _make_whelp(a[0], a[1])
			units.append(w)
			SkillFx.boss_event(self, boss, "whelp", w)
		"hazard":
			var h := Hazard.new()
			h.shape = a[0]
			h.position = a[1]
			h.radius = a[2]
			h.dir = a[3]
			h.half_angle = a[4]
			h.length = a[5]
			h.delay = a[6]
			h.duration = a[7]
			h.label = a[8]
			h.tank_soak = a[9]
			h.color = a[10]
			h.knockback = a[11]
			h.source = boss
			h.world = self
			add_child(h)
			h.build_visual(true)
			hazards.append(h)
			SkillFx.hazard_created(self, h)
		"zone":
			var z := GroundZone.new()
			z.world = self
			z.kind = a[0]
			z.duration = a[1]
			z.radius = a[2]
			z.position = a[3]
			z.label = a[4]
			add_child(z)
			z.build_visual(true)
			zones.append(z)
		"end":
			finished = true
			victory = a[0]
			fight_time = a[1]
			death_log = a[2]
			fight_ended.emit(victory)


# ------------------------------------------------------------------ events (gameplay + visuals)

const SCHOOL_COLORS := {
	"physical": Color(1, 1, 1), "bleed": Color(1, 0.35, 0.3), "fire": Color(1, 0.55, 0.15),
	"frost": Color(0.55, 0.85, 1), "nature": Color(0.5, 1, 0.35), "holy": Color(1, 0.9, 0.45),
}


func _say(text: String, c: Color) -> void:
	message.emit(text, c)
	net_out("msg", [text, c])


func on_damage(target: Unit, source: Unit, amount: float, absorbed: float, crit: bool, _label: String,
		school := "physical") -> void:
	if source != null and target.team == "enemy" and source.team == "party":
		damage_done[source] = float(damage_done.get(source, 0.0)) + amount + absorbed
	if target.team == "party":
		var d: Dictionary = damage_taken.get(target, {})
		d[_label] = float(d.get(_label, 0.0)) + amount
		damage_taken[target] = d
	net_out("dmg", [target.net_id, source.net_id if source else -1, amount, absorbed, crit, school])
	if visuals:
		_vis_damage(target, source, amount, absorbed, crit, school)


func _vis_damage(target: Unit, source: Unit, amount: float, absorbed: float, crit: bool, school: String) -> void:
	if target == null:
		return
	if target.model != null and target.model.has_method("hit") and amount > 0.0:
		target.model.hit(amount / maxf(1.0, target.max_hp))
	if source != null and source.is_player and target.team == "enemy":
		float_text(target, str(int(amount)) + ("!" if crit else ""), SCHOOL_COLORS.get(school, Color.WHITE), crit)
	elif target.is_player:
		var t := "-" + str(int(amount))
		if absorbed > 0.0:
			t = ("Absorbed %d" % int(absorbed)) if amount < 1.0 else t + " (%d absorbed)" % int(absorbed)
		float_text(target, t, Color(1, 0.3, 0.3), false)


func on_heal(target: Unit, source: Unit, effective: float, _overheal: float, crit: bool, _label: String) -> void:
	if source != null:
		healing_done[source] = float(healing_done.get(source, 0.0)) + effective
	net_out("heal", [target.net_id, source.net_id if source else -1, effective, crit, _label])
	if visuals:
		_vis_heal(target, source, effective, crit, _label)


func _vis_heal(target: Unit, source: Unit, effective: float, crit: bool, label: String) -> void:
	if target == null:
		return
	if label == "Sanctuary" or label == "Healing Draught":
		SkillFx.heal_tick(self, target)
	if source != null and source.is_player and effective >= 1.0:
		float_text(target, "+" + str(int(effective)) + ("!" if crit else ""), Color(0.3, 1, 0.4), crit)


func add_heal_threat(healer: Unit, amount: float) -> void:
	var foes := units.filter(func(u): return u.team == "enemy" and u.alive and u.in_combat)
	if foes.is_empty() or amount <= 0.0:
		return
	for e in foes:
		e.add_threat(healer, amount * 0.5 / foes.size())


func on_dodge(target: Unit, _source: Unit) -> void:
	net_out("dodge", [target.net_id])
	if visuals and target.is_player:
		float_text(target, "Dodge", Color(0.8, 0.8, 1), false)


func on_interrupted(target: Unit, source: Unit, spell: String) -> void:
	_say("%s interrupted %s!" % [source.unit_name, spell], Color(0.5, 0.9, 1))
	net_out("intr", [target.net_id])
	if visuals:
		float_text(target, "Interrupted", Color(0.5, 0.9, 1), true)


func on_cast_cancelled(_u: Unit, _spell: String) -> void:
	pass


func on_ability_used(u: Unit, aid: String, t: Unit, point = null) -> void:
	net_out("ability", [u.net_id, aid, t.net_id if t else -1, point])
	if visuals:
		SkillFx.ability(self, u, aid, t, point)


func on_projectile(u: Unit, t: Unit, aid: String) -> void:
	net_out("proj", [u.net_id, t.net_id, aid])


func on_ground_projectile(u: Unit, point: Vector3, aid: String) -> void:
	net_out("projg", [u.net_id, point, aid])


func on_auto_attack(u: Unit, t: Unit) -> void:
	net_out("auto", [u.net_id, t.net_id])
	if visuals:
		SkillFx.auto_attack(self, u, t)


func on_blink(u: Unit, from: Vector3, to: Vector3) -> void:
	net_out("blink", [u.net_id, from, to])
	force_position(u)
	if visuals:
		SkillFx.blink(self, u, from, to)


func on_dash_landed(u: Unit, kind: String, r: float) -> void:
	net_out("landed", [u.net_id, kind, r])
	if visuals:
		SkillFx.dash_landed(self, u, kind, r)


func on_revived(u: Unit, source: Unit) -> void:
	_say("%s has been resurrected by %s!" % [u.unit_name, source.unit_name], Color(1, 0.95, 0.6))
	net_out("revived", [u.net_id])
	if visuals:
		SkillFx.revived(self, u)


func on_hazard_fired(h: Hazard) -> void:
	if visuals:
		SkillFx.hazard_fired(self, h)


func on_hazard_active(h: Hazard) -> void:
	if visuals:
		SkillFx.hazard_active(self, h)


func boss_fx(ev: String, target: Unit = null) -> void:
	net_out("bossfx", [ev, target.net_id if target else -1])
	if visuals:
		SkillFx.boss_event(self, boss, ev, target)


## A remote player's character was moved by the server (knockback, blink): tell its owner.
func force_position(u: Unit) -> void:
	if net_role == "server" and u.owner_peer > 1:
		Net.send_force_position(u.owner_peer, u.position)


func on_unit_died(u: Unit) -> void:
	if u.team == "party":
		death_log.append("%s (%s) at %s" % [u.unit_name, u.class_id, fmt_time(fight_time)])
		_say("%s has died." % u.unit_name, Color(1, 0.4, 0.4))
	# Clear dead targets
	for o in units:
		if o.target == u:
			o.target = null


func boss_emote(text: String) -> void:
	emote.emit(text)
	net_out("emote", [text])
	phase_log.append("%s  %s" % [fmt_time(fight_time), text])


static func fmt_time(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


# ------------------------------------------------------------------ floating text

func float_text(u: Unit, text: String, c: Color, big: bool) -> void:
	if not visuals:
		return
	var l := Label3D.new()
	l.text = text
	l.modulate = c
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011 if big else 0.0008
	l.font_size = 40
	l.outline_size = 10
	add_child(l)
	var h := 6.0 if u.is_boss else 2.3
	l.position = u.position + Vector3(randf_range(-0.6, 0.6), h, randf_range(-0.6, 0.6))
	var tw := l.create_tween()
	tw.set_parallel(true)
	if big:
		# Crit "pop": start huge, snap down, then drift
		var final_px := l.pixel_size
		l.pixel_size = final_px * 2.2
		tw.tween_property(l, "pixel_size", final_px, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	l.position.x += randf_range(-0.8, 0.8)
	tw.tween_property(l, "position:y", l.position.y + 1.8, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.6)
	tw.chain().tween_callback(l.queue_free)
