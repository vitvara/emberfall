class_name SkillFx
extends RefCounted
## Maps every skill and boss event to an animation + visual effect.
## Only called when RaidWorld.visuals is true.

const PROJECTILES := {
	"frost_shard": {"speed": 30.0, "color": Color(0.55, 0.85, 1.0), "size": 0.3, "impact": "frost"},
}

const GOLD := Color(1, 0.85, 0.4)
const HEAL := Color(0.55, 1, 0.5)
const STEEL := Color(0.75, 0.85, 1)
const BLOOD := Color(1, 0.15, 0.1)


static func has_projectile(aid: String) -> bool:
	return PROJECTILES.has(aid)


static func flight_time(caster: Unit, target: Unit, aid: String) -> float:
	var d: Dictionary = PROJECTILES[aid]
	return maxf(0.08, (caster.position + Vector3(0, 1.4, 0)).distance_to(Vfx.chest(target)) / float(d["speed"]))


static func ground_flight_time(caster: Unit, point: Vector3) -> float:
	return clampf(caster.flat_pos().distance_to(point) / 22.0, 0.25, 0.9)


static func has_ground_projectile(aid: String) -> bool:
	return aid == "poison_bomb"


static func launch_ground(world, caster: Unit, point: Vector3, aid: String, on_land: Callable) -> void:
	var p := Projectile.new()
	p.dest = Vector3(point.x, 0.2, point.z)
	p.color = Color(0.4, 1.0, 0.3)
	p.impact = "poison"
	p.arc = 3.5
	p.duration = ground_flight_time(caster, point)
	p.on_hit = on_land
	p.position = caster.position + Vector3(0, 1.5, 0) + caster.forward() * 0.4
	world.add_child(p)


static func launch(world, caster: Unit, target: Unit, aid: String, on_hit: Callable) -> void:
	var d: Dictionary = PROJECTILES[aid]
	var p := Projectile.new()
	p.target = target
	p.speed = d["speed"]
	p.color = d["color"]
	p.size = d["size"]
	p.impact = d["impact"]
	p.arc = d.get("arc", 0.0)
	p.on_hit = on_hit
	p.position = caster.position + Vector3(0, 1.4, 0) + caster.forward() * 0.6
	world.add_child(p)


## Run an effect a moment later (multi-hit combos). Safe if the fight was torn down.
static func _later(world, t: float, f: Callable) -> void:
	world.get_tree().create_timer(t).timeout.connect(func():
		if is_instance_valid(world):
			f.call())


static func _rig(u: Unit) -> Node:
	return u.model


static func _anim(u: Unit, a: String) -> void:
	if u.model != null and u.model.has_method("play"):
		u.model.play(a)


# ------------------------------------------------------------------ player skills

static func ability(world, u: Unit, aid: String, t: Unit, point = null) -> void:
	var tp := Vfx.chest(t) if t != null else Vfx.chest(u)
	match aid:
		# ---- Warden
		"bulwark_strike":
			_anim(u, "bash")
			Vfx.swoosh(world, Vfx.chest(u), u.rotation.y, 0.25, Color(0.35, 0.55, 1.0), 2.0, 0.9, 170.0, 0.22, false)
			Vfx.star_flash(world, tp, Color(0.6, 0.8, 1), 2.6)
			Vfx.sparks(world, tp, STEEL, 20)
			Vfx.shockwave(world, t.position if t else u.position, Color(0.5, 0.7, 1), 2.5, 0.3)
		"charge":
			_anim(u, "bash")
			Vfx.shockwave(world, u.position, Color(0.85, 0.7, 0.5), 3.0, 0.35)
			Vfx.smoke(world, u.position, 0.8)
			if t != null:
				Vfx.speed_trail(world, u.position, (t.flat_pos() - u.flat_pos()).normalized(), Color(1, 0.85, 0.6))
		"raise_shield":
			_anim(u, "block")
			Vfx.bubble_flash(world, Vfx.chest(u), Color(0.5, 0.7, 1), 1.6, 0.5)
			Vfx.shockwave(world, u.position, Color(0.5, 0.7, 1), 3.0, 0.4)
		"challenging_shout":
			_anim(u, "shout")
			Vfx.shockwave(world, u.position, Color(1, 0.3, 0.2), 7.0, 0.5)
			Vfx.sparks(world, tp, Color(1, 0.3, 0.2), 20)
		"shield_bash":
			_anim(u, "bash")
			Vfx.swoosh(world, Vfx.chest(u), u.rotation.y, -0.3, Color(0.6, 0.8, 1), 1.8, 0.8, 150.0, 0.2, true)
			Vfx.crackle(world, tp, Color(0.55, 0.7, 1), 1.2, 4)
			Vfx.star_flash(world, tp, Color(0.8, 0.9, 1), 2.5)
		"execution_strike":
			_anim(u, "slash")
			Vfx.star_flash(world, tp, Color(1, 0.3, 0.2), 3.5)
			Vfx.swoosh(world, Vfx.chest(u) + Vector3(0, 0.4, 0), u.rotation.y, 1.4, Color(1, 0.25, 0.1), 2.6, 1.2, 200.0, 0.26)
			Vfx.ground_crack(world, (t.position if t else u.position), Color(1, 0.35, 0.15), 2.5, 1.5)
			Vfx.sparks(world, tp, BLOOD, 34)
			Vfx.flash_light(world, tp, Color(1, 0.3, 0.2), 5.0, 8.0, 0.4)
			world.shake.emit(0.35 if u.is_player else 0.1)
		"thunder_leap":
			_anim(u, "shout")
			Vfx.smoke(world, u.position, 1.0)
		# ---- Oracle
		"flash_mend":
			_anim(u, "heal")
			Vfx.light_column(world, t.position, GOLD, 4.0, 0.7, 0.7)
			Vfx.sparkles(world, t.position + Vector3(0, 1, 0), HEAL, 0.5, 22)
		"ward_of_dawn":
			_anim(u, "heal")
			Vfx.bubble_flash(world, Vfx.chest(t), GOLD, 1.5, 0.6)
			Vfx.sparkles(world, Vfx.chest(t), GOLD, 0.8, 16)
		"smite":
			_anim(u, "release")
			if t != null:
				Vfx.light_column(world, t.position + Vector3(0, max(0.0, t.chest_height - 1.0), 0), Color(1, 0.92, 0.55),
					10.0, 0.5 if not t.is_boss else 1.4, 0.45)
				Vfx.star_flash(world, tp, GOLD, 2.5)
				Vfx.sparks(world, tp, GOLD, 16)
		"final_prayer":
			_anim(u, "heal")
			Vfx.buff_burst(world, u, GOLD, 1.3)
			Vfx.light_column(world, u.position, Color(1, 0.95, 0.7), 7.0, 1.1, 0.9)
			Vfx.sparkles(world, u.position + Vector3(0, 1, 0), GOLD, 0.7, 30)
		"fade":
			_anim(u, "block")
			Vfx.burst(world, Vfx.chest(u), {"amount": 26, "lifetime": 1.2, "vmin": 0.5, "vmax": 1.6, "sphere": 0.6,
				"size": 1.0, "grow": true, "additive": false,
				"colors": [Color(0.3, 0.3, 0.4, 0.5), Color(0.15, 0.15, 0.2, 0)]})
		"resurrection":
			_anim(u, "heal")
			if t != null:
				Vfx.buff_burst(world, t, GOLD, 1.0)
		"sanctuary":
			_anim(u, "heal")
			if point != null:
				Vfx.light_shaft(world, point, GOLD, 10.0, 1.2, 1.0)
		# ---- Blademaster: fast, thin, bright dagger work
		"wicked_strike":
			_anim(u, "dual")
			var cw := Color(1, 0.85, 0.45)
			Vfx.swoosh(world, Vfx.chest(u), u.rotation.y, 0.9, cw, 1.5, 0.3, 120.0, 0.13)
			_later(world, 0.09, func(): Vfx.swoosh(world, Vfx.chest(u), u.rotation.y, -0.9, cw, 1.5, 0.3, 120.0, 0.13, true))
			Vfx.x_slash(world, tp, cw, 1.4 if t and t.is_boss else 1.0)
			Vfx.sparks(world, tp, cw, 14)
		"executioners_cut":
			_anim(u, "flurry")
			var cr := Color(1, 0.3, 0.15)
			for i in 3:
				var tilt := 0.9 if i % 2 == 0 else -0.9
				_later(world, i * 0.15, func():
					Vfx.swoosh(world, Vfx.chest(u), u.rotation.y, tilt, cr, 1.6, 0.32, 120.0, 0.12, i % 2 == 1)
					Vfx.sparks(world, tp, Color(1, 0.6, 0.3), 8))
			_later(world, 0.42, func():
				Vfx.x_slash(world, tp, Color(1, 0.15, 0.1), 2.4 if t and t.is_boss else 1.6)
				Vfx.star_flash(world, tp, Color(1, 0.3, 0.2), 3.2)
				Vfx.blood_spray(world, tp, -u.forward() * -1.0 + Vector3(0, 0.5, 0), 1.4)
				world.shake.emit(0.25 if u.is_player else 0.0))
			# combo points released
			Vfx.burst(world, Vfx.chest(u) + Vector3(0, 0.4, 0), {"amount": 5, "lifetime": 0.5, "vmin": 2.0, "vmax": 3.0,
				"direction": Vector3.UP, "spread": 60.0, "size": 0.6, "tex": "star", "spin": 200.0,
				"colors": [Color(1, 1, 0.6, 1), Color(1, 0.8, 0.2, 0.9), Color(1, 0.6, 0.1, 0)]})
		"blade_rhythm":
			_anim(u, "spin")
			Vfx.swoosh(world, u.position + Vector3(0, 0.9, 0), u.rotation.y, 0.0, Color(1, 0.8, 0.25), 1.7, 0.4, 360.0, 0.3)
			if u.model is HeroRig:
				u.model.flash_spiral(Color(1, 0.85, 0.3), 1.2)
			Vfx.buff_burst(world, u, Color(1, 0.8, 0.25), 1.0)
		"throat_jab":
			_anim(u, "stab")
			Vfx.x_slash(world, tp, Color(0.6, 0.85, 1), 1.0)
			Vfx.crackle(world, tp, Color(0.6, 0.75, 1), 1.2, 4)
		"sprint":
			Vfx.smoke(world, u.position, 0.6)
			Vfx.speed_trail(world, u.position, u.forward(), Color(1, 1, 0.9))
		"healing_draught":
			_anim(u, "drink")
			if u.model is HeroRig:
				u.model.flash_spiral(Color(1, 0.35, 0.4), 1.2)
			Vfx.sparkles(world, Vfx.chest(u), Color(1, 0.4, 0.45), 0.5, 20)
		"poison_bomb":
			_anim(u, "throw")
		# ---- Arcanist: frost magic
		"frost_shard":
			_anim(u, "release")
			Vfx.star_flash(world, Vfx.chest(u) + u.forward() * 0.6, Color(0.7, 0.9, 1), 1.8)
		"flame_jolt":
			_anim(u, "release")
			Vfx.fire_burst(world, Vfx.chest(u) + u.forward() * 0.7, 0.5)
			Vfx.fire_explosion(world, tp, 1.3 if t and t.is_boss else 0.9)
		"counterspell":
			_anim(u, "release")
			Vfx.lightning(world, Vfx.chest(u) + u.forward() * 0.6 + Vector3(0, 0.1, 0), tp, Color(0.65, 0.45, 1), 0.45, 0.12)
			Vfx.crackle(world, tp, Color(0.7, 0.5, 1), 1.6 if t and t.is_boss else 1.0, 5)
			Vfx.star_flash(world, tp, Color(0.7, 0.45, 1), 3.0)
		"quickening":
			_anim(u, "shout")
			Vfx.burst(world, Vfx.chest(u), {"amount": 40, "lifetime": 0.8, "vmin": 6.0, "vmax": 12.0, "damping": 6.0,
				"size": 0.5, "streak": true, "stretch": 3.0,
				"colors": [Color(1, 1, 1, 1), Color(0.6, 0.65, 1, 0.9), Color(0.5, 0.5, 1, 0)]})
			for p in world.party_alive():
				Vfx.buff_burst(world, p, Color(0.6, 0.65, 1), 0.8)
				Vfx.sparkles(world, p.position + Vector3(0, 1, 0), Color(0.6, 0.7, 1), 0.5, 14)
		"frost_cone":
			_anim(u, "release")
			var cone := Vfx.shard_emitter({"amount": 26, "lifetime": 0.45, "vmin": 16.0, "vmax": 26.0,
				"direction": Vector3(0, 0, -1), "spread": 38.0, "damping": 22.0, "size": 0.5,
				"scale_min": 0.6, "scale_max": 1.0})
			world.add_child(cone)
			cone.global_position = Vfx.chest(u) + u.forward() * 0.5
			cone.rotation.y = u.rotation.y
			cone.restart()
			Vfx._free_after(cone, 1.2)
			var mist := Vfx.emitter({"amount": 40, "lifetime": 0.6, "vmin": 10.0, "vmax": 18.0,
				"direction": Vector3(0, 0, -1), "spread": 40.0, "damping": 18.0, "size": 1.3, "grow": true,
				"colors": [Color(0.9, 0.97, 1, 0.9), Color(0.6, 0.85, 1, 0.5), Color(0.5, 0.75, 1, 0)]})
			world.add_child(mist)
			mist.global_position = Vfx.chest(u) + u.forward() * 0.5
			mist.rotation.y = u.rotation.y
			mist.restart()
			Vfx._free_after(mist, 1.2)
			# Ice spikes erupt across the cone
			for row in 3:
				for col in 3 + row:
					var ang := u.rotation.y + (col - (2 + row) / 2.0) * (0.55 / (1.0 + row * 0.4))
					var fwd := Vector3(-sin(ang), 0, -cos(ang))
					var at := u.position + fwd * (3.0 + row * 3.2)
					_later(world, 0.05 + row * 0.07, func(): Vfx.ice_spikes(world, at, 0.8 + row * 0.15, 0.6))
		"frost_storm":
			_anim(u, "heal")
			if point != null:
				Vfx.ice_fall(world, point, 1.3)


static func dash_landed(world, u: Unit, kind: String, r: float) -> void:
	if kind == "charge":
		Vfx.smoke(world, u.position, 0.8)
		Vfx.star_flash(world, Vfx.chest(u) + u.forward() * 0.8, Color(1, 0.85, 0.6), 2.0)
		world.shake.emit(0.2 if u.is_player else 0.0)
		return
	if kind == "leap":
		Vfx.ground_crack(world, u.position, Color(1, 0.55, 0.2), r * 0.9, 2.5)
		Vfx.debris(world, u.position, 1.3)
		Vfx.shockwave(world, u.position, Color(1, 0.7, 0.35), r, 0.45)
		Vfx.smoke(world, u.position, 2.5)
		Vfx.burst(world, u.position + Vector3(0, 0.3, 0), {"amount": 40, "lifetime": 0.7, "vmin": 4.0, "vmax": 10.0,
			"direction": Vector3.UP, "spread": 70.0, "gravity": Vector3(0, -14, 0), "size": 0.25,
			"colors": [Color(0.7, 0.55, 0.4), Color(0.4, 0.3, 0.2, 0)]})
		world.shake.emit(0.5 if u.is_player else 0.15)


static func revived(world, u: Unit) -> void:
	Vfx.buff_burst(world, u, GOLD, 1.6)
	Vfx.light_column(world, u.position, Color(1, 0.97, 0.75), 12.0, 1.5, 1.4)
	Vfx.shockwave(world, u.position, GOLD, 6.0, 0.7)
	Vfx.sparkles(world, u.position + Vector3(0, 1, 0), Color(1, 1, 0.8), 1.0, 50)


static func blink(world, u: Unit, from: Vector3, to: Vector3) -> void:
	var c := Color(0.7, 0.45, 1)
	Vfx.burst(world, from + Vector3(0, 1, 0), {"amount": 30, "lifetime": 0.5, "vmin": 1.0, "vmax": 4.0,
		"sphere": 0.5, "size": 0.25, "colors": [Color(1, 1, 1), c, Color(c.r, c.g, c.b, 0)]})
	Vfx.bubble_flash(world, to + Vector3(0, 1, 0), c, 1.2, 0.35)
	Vfx.sparkles(world, to + Vector3(0, 1, 0), c, 0.5, 20)


static func auto_attack(world, u: Unit, t: Unit) -> void:
	if u.model is DragonRig:
		# Mix up the dragon's swings: bites, left and right claw swipes and a two-paw stomp (not for whelps).
		# Hit effects fire from the rig at the moment of contact.
		var rig := u.model as DragonRig
		var moves := ["bite", "claw_l", "claw_r", "bite", "claw_l", "claw_r"] if rig.is_whelp \
			else ["bite", "claw_l", "claw_r", "claw_l", "claw_r", "stomp", "bite"]
		var mv: String = moves.pick_random()
		if mv == rig.last_melee and mv == "stomp":
			mv = "bite"
		rig.last_melee = mv
		rig.play(mv, t)
		return
	_anim(u, "light")
	if u.class_id == "blademaster":
		Vfx.swoosh(world, Vfx.chest(u), u.rotation.y, randf_range(-1.0, 1.0), Color(1, 0.9, 0.6), 1.3, 0.22, 100.0, 0.11,
			randf() < 0.5, 0.6)
		if randf() < 0.5:
			Vfx.x_slash(world, Vfx.chest(t), Color(1, 0.95, 0.8), 0.7)
		return
	Vfx.slash(world, u, Color(0.75, 0.85, 1), randf_range(-0.7, 0.7), 1.0, randf() < 0.5, 0.45)


static func heal_tick(world, t: Unit) -> void:
	Vfx.sparkles(world, t.position + Vector3(0, 1, 0), GOLD, 0.4, 6)


# ------------------------------------------------------------------ boss events

static func boss_event(world, boss: Unit, ev: String, target: Unit) -> void:
	match ev:
		"wake":
			_anim(boss, "roar")
			DragonFx.dust_ring(world, boss.position, 14.0)
			world.shake.emit(0.5)
		"claw":
			if boss.model is DragonRig:
				boss.model.play("rake", target)  # right claw, then left; the rig times the hits
			elif target != null:
				DragonFx.claw_hit(world, boss, target, Vfx.chest(target), 1.0, true, false)
		"takeoff":
			_anim(boss, "takeoff")
			DragonFx.dust_ring(world, boss.position, 18.0)
			Vfx.smoke(world, boss.position, 3.0)
			world.shake.emit(0.5)
		"land":
			_anim(boss, "land")
			DragonFx.dust_ring(world, Vector3.ZERO, 20.0)
			DragonFx.crater(world, Vector3.ZERO, 9.0, 6.0)
			DragonFx.rock_debris(world, Vector3.ZERO, 1.3, 18)
			Vfx.fire_burst(world, Vector3(0, 0.5, 0), 2.5)
			world.shake.emit(0.8)
		"pulse":
			_anim(boss, "nova")
			DragonFx.fire_wave(world, boss.position, 32.0, 0.9)
			for p in world.party_alive():
				Vfx.fire_burst(world, Vfx.chest(p), 0.7)
			world.shake.emit(0.35)
		"cataclysm_start":
			_anim(boss, "roar")
		"cataclysm_hit":
			_anim(boss, "nova")
			Vfx.fire_explosion(world, boss.position + Vector3(0, 3, 0), 3.0)
			DragonFx.fire_wave(world, boss.position, 34.0, 1.1)
			DragonFx.eruptions(world, 14, 28.0)
			for p in world.party_alive():
				Vfx.fire_burst(world, Vfx.chest(p), 1.2)
			world.shake.emit(1.0)
		"enrage":
			_anim(boss, "roar")
			var e := Vfx.emitter({"amount": 60, "lifetime": 0.9, "one_shot": false, "vmin": 1.0, "vmax": 2.5,
				"direction": Vector3.UP, "spread": 10.0, "ring": [4.0, 2.5], "size": 1.8, "grow": true, "local": true,
				"shader": "flame", "colors": DragonFx.FIRE})
			boss.add_child(e)
			world.shake.emit(0.6)
		"whelp":
			if target != null:
				Vfx.smoke(world, target.position + Vector3(0, 2, 0), 1.0)


static func hazard_created(world, h: Hazard) -> void:
	match h.label:
		"Meteor":
			DragonFx.meteor_fall(world, h)
		"Cinder Pool":
			if h.source != null:
				_anim(h.source, "spit")
				DragonFx.lava_glob(world, h.source, h)
		"Tail Lash":
			if h.source != null:
				_anim(h.source, "tail_windup")


static func hazard_fired(world, h: Hazard) -> void:
	match h.label:
		"Flame Breath":
			if h.source != null:
				_anim(h.source, "breath")
			DragonFx.breath_ground(world, h)
			world.shake.emit(0.6)
		"Tail Lash":
			if h.source != null:
				_anim(h.source, "tail")
			DragonFx.tail_sweep(world, h)
			world.shake.emit(0.3)
		"Meteor":
			DragonFx.meteor_impact(world, h.position, h.radius)
			world.shake.emit(0.45)


static func hazard_active(world, h: Hazard) -> void:
	if h.label == "Cinder Pool":
		DragonFx.lava_splash(world, h)
