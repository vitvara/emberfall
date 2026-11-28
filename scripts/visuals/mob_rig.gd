class_name MobRig
extends Node3D
## A humanoid monster or NPC built from the Quaternius parts (CharModel), animated from its Unit:
## idle, jog/sprint from how fast it moves, a weapon swing for attacks, a flinch when hit, death.
## Optionally carries a burning torch in the right hand. Reads the Unit; gameplay never reads here.
##
## Without the packs installed (the headless realm) it is a plain stand-in shape.

const PALM := Vector3(-0.03, 0.085, 0.0)   # grip point in the right hand bone's frame

var unit: Unit
var cm: CharModel
var idle_clip := "Idle"
var combat_idle := "Sword_Idle"
var attack_clip := "Sword_Attack"
var torch_fx: Array = []          # flame emitter + light, put out on death
var _last := Vector3.ZERO
var _speed := 0.0
var _attack_t := 0.0
var _t := 0.0


## look: {"race", "outfit", "opts"} as for CharModel.create; torch: carry a burning torch;
## weapon: a blade model file (assets/models/weapons) held in the right hand instead.
func build(look: Dictionary, torch := false, scale_k := 1.0, weapon := "", weapon_len := 1.0) -> MobRig:
	if CharModel.available():
		cm = CharModel.create(look["race"], look["outfit"], look.get("opts", {}))
		add_child(cm)
		cm.scale = Vector3.ONE * scale_k
		if weapon != "":
			var w := Node3D.new()
			w.position = PALM
			w.rotation.y = PI   # blade out of the index side of the fist
			w.add_child(WeaponModels.blade(weapon, weapon_len, -0.1))
			cm.attach("hand_r").add_child(w)
		elif torch:
			_torch(cm.attach("hand_r"))
			idle_clip = "Idle_Torch"
	else:
		Models.part(self, Models.capsule(0.32, 1.75 * scale_k), Models.mat(Color(0.45, 0.12, 0.08)),
			Vector3(0, 0.88 * scale_k, 0))
	add_child(Models.blob_shadow(0.6 * scale_k))
	return self


func _torch(hand: Node3D) -> void:
	var t := Node3D.new()
	t.position = PALM
	hand.add_child(t)
	# Stick along the fist's grip axis (+Z), burning rag wrapped round the top
	Models.part(t, Models.cyl(0.025, 0.032, 0.62), Models.mat(Color(0.3, 0.19, 0.1)), Vector3(0, 0, 0.18),
		Vector3(PI / 2.0, 0, 0))
	Models.part(t, Models.cyl(0.05, 0.04, 0.12), Models.mat(Color(0.16, 0.1, 0.07)), Vector3(0, 0, 0.47),
		Vector3(PI / 2.0, 0, 0))
	var fire := Vfx.emitter({"amount": 16, "lifetime": 0.45, "one_shot": false, "vmin": 0.4, "vmax": 1.0,
		"direction": Vector3.UP, "spread": 12.0, "sphere": 0.05, "size": 0.32, "shader": "flame_solid",
		"local": false, "colors": [Color(1, 0.9, 0.55, 1), Color(1, 0.5, 0.12, 0.9), Color(0.5, 0.1, 0.03, 0.3),
			Color(0.1, 0.05, 0.05, 0)]})
	fire.position = Vector3(0, 0, 0.53)
	t.add_child(fire)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.omni_range = 5.0
	l.light_energy = 1.3
	l.position = Vector3(0, 0, 0.6)
	t.add_child(l)
	torch_fx = [fire, l]


var _combo := 0


## One-shot action: weapon swings alternate through the sword combo (library 2) when it's installed;
## "heavy" is a leaping slam.
func play(action: String, _flip := false) -> void:
	if cm == null or unit == null or not unit.alive:
		return
	_attack_t = 0.55
	if action == "heavy" and cm.has_clip("Sword_Heavy_Combo"):
		_attack_t = 1.2
		cm.play_once("Sword_Heavy_Combo", 1.6, false)
		return
	var clip := attack_clip
	if cm.has_clip("Sword_Regular_A"):
		_combo = (_combo + 1) % 2
		clip = ["Sword_Regular_A", "Sword_Regular_B"][_combo]
	cm.play_once(clip, 1.1, _speed > 0.5)


func hit(fraction: float) -> void:
	if cm == null or _attack_t > 0.0 or unit == null or not unit.alive:
		return
	if fraction > 0.03:
		cm.play_once("Hit_Chest" if randf() < 0.6 else "Hit_Head", 1.3, _speed > 0.5)


func _process(delta: float) -> void:
	if unit == null:
		unit = get_parent() as Unit
		if unit == null:
			return
		_last = unit.flat_pos()
	_t += delta
	var flat := unit.flat_pos()
	var v := flat.distance_to(_last) / maxf(delta, 0.001)
	_last = flat
	_speed = lerpf(_speed, v, clampf(delta * 10.0, 0.0, 1.0))
	_attack_t -= delta
	if torch_fx.size() == 2:
		(torch_fx[1] as OmniLight3D).light_energy = 0.0 if not unit.alive else 1.2 + 0.25 * sin(_t * 13.0) + 0.15 * sin(_t * 7.3)
		(torch_fx[0] as GPUParticles3D).emitting = unit.alive
	if cm == null:
		return
	if not unit.alive:
		cm.stop_once()
		cm.play_loop("Death01")
		return
	if _speed > 4.5:
		cm.play_loop("Sprint", clampf(_speed / 6.0, 0.7, 1.5))
	elif _speed > 0.4:
		cm.play_loop("Jog_Fwd", clampf(_speed / 3.4, 0.7, 1.6))
	elif unit.in_combat and unit.team == "enemy":
		cm.play_loop(combat_idle)
	else:
		cm.play_loop(idle_clip)
