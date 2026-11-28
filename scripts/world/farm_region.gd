class_name FarmRegion
extends Node3D
## Brannoc's farm: the open world's southern end, down the Ashen Causeway from the Outpost's south
## gate. New heroes start here. Cinderbound zealots with torches and Ember Whelps are burning the
## house, barn and fields; the farmer begs for help, the hero drives off the raiders and then their
## leader, Firebrand Kael. The fires die down and the road leads north to the Emberfall Outpost.
##
## A region of the HubWorld (one continuous map): its node sits at HubWorld.FARM_C and builds its
## scenery in local coordinates; its units live in the hub world (world coordinates). Combat and the
## quest are local to each player's game, like the Outpost's training dummies.

signal completed   # the hero saved the farm and reached the Outpost

const FARM_RADIUS := 47.0
const FARM_SPAWN := Vector3(0, 0, 42)
const FARMER_POS := Vector3(3.2, 0, 33.5)
const RESPAWN := Vector3(-3, 0, 30)
const EXIT_Z := -43.0
const NAT := "res://assets/models/quaternius/nature/"   # Stylized Nature MegaKit (git-ignored, CC0)
const BLD := "res://assets/models/quaternius/buildings/"   # village buildings (git-ignored)

static var _nat_meshes := {}          # nature model -> [mesh, transform inside its scene]

enum Stage { ARRIVE, CLEAR, LEADER, SAVED, LEAVING, DONE }

## Monster kinds: model, stats, brain settings
const ZEALOT_LOOKS := [
	{"race": "Orc_Male", "outfit": "Ranger", "opts": {"hood": true, "pauldron": false, "tint": Color(0.55, 0.12, 0.1),
		"skin_tint": Color(0.62, 0.85, 0.42)}},
	{"race": "Orc_Female", "outfit": "Peasant", "opts": {"tint": Color(0.6, 0.2, 0.14),
		"skin_tint": Color(0.62, 0.85, 0.42)}},
	{"race": "Orc_Male", "outfit": "Peasant", "opts": {"tint": Color(0.45, 0.16, 0.12),
		"skin_tint": Color(0.62, 0.85, 0.42)}},
]
const LEADER_LOOK := {"race": "Orc_Male", "outfit": "Ranger", "opts": {"pauldron": true, "tint": Color(0.3, 0.08, 0.07),
	"skin_tint": Color(0.62, 0.85, 0.42)}}
const ZEALOT := {"hp": 2400.0, "armor": 500.0, "damage": 75.0, "interval": 2.0, "speed": 5.2}
const WHELP := {"hp": 1700.0, "armor": 300.0, "damage": 60.0, "interval": 1.4, "speed": 6.0}
const LEADER := {"hp": 8000.0, "armor": 800.0, "damage": 125.0, "interval": 2.2, "speed": 5.0, "nova": 9.0, "nova_dmg": 320.0}

var world: HubWorld
var stage := Stage.ARRIVE
var farmer: Unit
var farmer_rig: MobRig
var leader: Unit
var mobs: Array = []          # every hostile Unit spawned here
var _wave: Array = []         # the raiders (before the leader)
var _fires: Array = []        # [{fx: [emitters], light, base}]
var _glow_mats: Array = []    # burning windows: dimmed when the fires go out
var _corpses: Array = []      # [unit, seconds until removed]
var _dead_t := 0.0
var _talked := false
var _exit_fx: Array = []
var _t := 0.0
var _day := false             # the nature kit is installed: sunny daylight scenery
var _mill_blades: MeshInstance3D
var _rng := RandomNumberGenerator.new()

# UI
var _tracker: PanelContainer
var _tracker_title: Label
var _tracker_lines: Label
var _dialog: PanelContainer
var _dialog_name: Label
var _dialog_text: Label
var _dialog_btn: Button
var _dialog_cb: Callable
var _qbanner: Label
var _qbanner_t := 0.0
var _hide_tracker_t := 0.0

var _wood: StandardMaterial3D
var _wood_dark: StandardMaterial3D
var _soil: StandardMaterial3D
var _grass: StandardMaterial3D
var _straw: StandardMaterial3D
var _char: StandardMaterial3D
var _stone: StandardMaterial3D
var _red: StandardMaterial3D


## Build the farm into the hub world (call after adding this node to it). done: the hero saved it before.
func build(hub: HubWorld, done: bool) -> FarmRegion:
	world = hub
	position = HubWorld.FARM_C
	_rng.seed = 4242
	_day = ResourceLoader.exists(NAT + "CommonTree_1.gltf")
	_wood = Models.mat(Color(0.36, 0.23, 0.13), 0.0, 0.95)
	_wood_dark = Models.mat(Color(0.2, 0.13, 0.08), 0.0, 1.0)
	_char = Models.mat(Color(0.07, 0.06, 0.055), 0.0, 1.0)
	_stone = Models.mat(Color(0.38, 0.36, 0.34), 0.0, 0.9)
	_red = Models.mat(Color(0.48, 0.13, 0.09), 0.0, 0.95)
	if _day:
		_grass = Models.mat(Color(0.3, 0.45, 0.14), 0.0, 1.0)
		_straw = Models.mat(Color(0.8, 0.64, 0.32), 0.0, 1.0)
		_soil = Models.mat(Color(0.3, 0.21, 0.13), 0.0, 1.0)
	else:
		_grass = Models.mat(Color(0.17, 0.19, 0.09), 0.0, 1.0)
		_straw = Models.mat(Color(0.56, 0.45, 0.24), 0.0, 1.0)
		_soil = Models.mat(Color(0.2, 0.13, 0.08), 0.0, 1.0)
	_build_land()
	_build_farmstead()
	_build_fields()
	_build_exit()
	_build_farm_ui()
	_spawn_farmer()
	if done:
		_settle()
	else:
		_spawn_raiders()
		_update_tracker()
	return self


## The hero is anywhere on the farm's land.
func in_area(p: Vector3) -> bool:
	return Vector2(p.x - position.x, p.z - position.z).length() < FARM_RADIUS + 6.0


## Raiders are fighting someone (keeps the combat HUD and stances up).
func engaged() -> bool:
	return mobs.any(func(m): return m.alive and m.in_combat)


## Already saved: no raiders, fires out, the farmer at peace.
func _settle() -> void:
	stage = Stage.DONE
	for f in _fires:
		for e in f["fx"]:
			(e as GPUParticles3D).emitting = false
		(f["light"] as OmniLight3D).light_energy = 0.0
	for m in _glow_mats:
		m.emission_energy_multiplier = 0.0
		m.albedo_color = Color(0.05, 0.03, 0.02)
	farmer_rig.idle_clip = "Farm_Harvest"
	farmer.position = position + FARMER_POS + Vector3(-2.5, 0, -2.0)
	if _tracker != null:
		_tracker.visible = false   # no quest left here


# ------------------------------------------------------------------ hub-world helpers (local coordinates)

func _block(x: float, z: float, r: float) -> void:
	world._block(x + position.x, z + position.z, r)


func _block_line(a: Vector3, b: Vector3, r: float) -> void:
	world._block_line(a + position, b + position, r)


func _light(p: Vector3, c: Color, rng: float, energy: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = c
	l.omni_range = rng
	l.light_energy = energy
	add_child(l)
	return l


func _multi(mesh: Mesh, m: Material, xforms: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	add_child(mmi)
	return mmi


func _supplies(c: Vector3) -> void:
	world._supplies(c + position)


## A monster noticed the hero: its whole group joins in.
func pull_group(group: int, target: Unit) -> void:
	for m in mobs:
		if m.alive and m.brain is MobBrain and (m.brain as MobBrain).group == group:
			m.add_threat(target, 1.0)
			m.in_combat = true


## Firebrand Kael's fire nova: a ring of flame erupts around him after a short warning.
func mob_nova(u: Unit, dmg: float) -> void:
	world.add_hazard(Hazard.circle(u.position, 6.5, 1.8, dmg, "Fire Nova", u))
	if u.model != null and u.model.has_method("play"):
		u.model.play("heavy")   # leaps and slams the ground
	world._say("Firebrand Kael gathers flame — get away from him!", Color(1, 0.55, 0.2))


func on_unit_died(u: Unit) -> void:
	if u == world.player:
		print("[farm] hero died at %.0fs" % _t)
		world._say("You have fallen. You'll wake by the farmhouse…", Color(1, 0.5, 0.4))
		return
	if u.team == "enemy":
		_corpses.append([u, 9.0])
		if stage == Stage.CLEAR and u in _wave:
			_update_tracker()
			if _wave.all(func(m): return not m.alive):
				_spawn_leader()
		elif stage == Stage.LEADER and u == leader:
			_farm_saved()


# ------------------------------------------------------------------ loop

func _process(delta: float) -> void:
	if world == null or world.player == null:
		return
	_t += delta
	var d := minf(delta, 0.1)
	var pl: Unit = world.player
	world.dialog_open = _dialog.visible
	_tick_fires()
	if _mill_blades != null:
		_mill_blades.rotate_object_local(Vector3.UP, d * 0.6)   # the windmill turns in the breeze
	_tick_corpses(d)
	_tick_player_death(d)
	if _qbanner_t > 0.0:
		_qbanner_t -= d
		_qbanner.modulate.a = clampf(_qbanner_t, 0.0, 1.0)
	if _hide_tracker_t > 0.0:
		_hide_tracker_t -= d
		if _hide_tracker_t <= 0.0:
			_tracker.visible = false
	var near_farmer := pl.position.distance_to(farmer.position) < 7.0
	if farmer_rig != null and stage != Stage.CLEAR and stage != Stage.LEADER and near_farmer:
		farmer.rotation.y = lerp_angle(farmer.rotation.y, atan2(-(pl.position.x - farmer.position.x),
			-(pl.position.z - farmer.position.z)), clampf(d * 3.0, 0.0, 1.0))
	if stage == Stage.ARRIVE and near_farmer and not _talked and not _dialog.visible:
		_talked = true
		_open_dialog("Farmer Brannoc", "Gods be thanked, a fighter! The Cinderbound came at dusk with torches, and they've " +
			"brought dragon-spawn with them. They're burning everything — my house, the barn, the harvest!\n\n" +
			"Please, drive them off before there's nothing left.", "I'll stop them", _accept_quest)
	elif stage == Stage.SAVED and near_farmer and not _dialog.visible:
		_open_dialog("Farmer Brannoc", "You did it… the fires are dying down. I'd have lost everything.\n\n" +
			"Kael was boasting that the Cinderbound serve the dragon, Vyrathax. The Emberfall Outpost up the north road, " +
			"across the Ashen Causeway, is gathering fighters against it. Commander Thessa will want to hear about this.",
			"Take the north road", func():
				stage = Stage.LEAVING
				_update_tracker())
	if stage == Stage.LEAVING and pl.position.z < HubWorld.WALL_RADIUS:
		_complete()


## The hero walked through the Outpost's south gate after saving the farm.
func _complete() -> void:
	print("[farm] reached the Outpost at %.0fs" % _t)
	stage = Stage.DONE
	_tracker_title.text = "The Road to Emberfall  —  Complete"
	_tracker_lines.text = "• You reached the Emberfall Outpost"
	_hide_tracker_t = 6.0
	completed.emit()


func _accept_quest() -> void:
	print("[farm] quest accepted")
	stage = Stage.CLEAR
	_update_tracker()
	_show_banner("Quest accepted: Smoke over the Fields")
	if farmer_rig != null and farmer_rig.cm != null:
		farmer_rig.idle_clip = "Crouch_Idle"   # hides behind his cart


func _spawn_leader() -> void:
	print("[farm] raiders cleared at %.0fs, Firebrand Kael appears" % _t)
	stage = Stage.LEADER
	var p := Vector3(14, 0, -6)   # in the barn door (local)
	leader = _mob("Firebrand Kael", LEADER, LEADER_LOOK, p, PI * 0.8, 99, false, 1.22, "Claymore.fbx")
	var br := leader.brain as MobBrain
	br.nova_every = float(LEADER["nova"])
	br.nova_damage = float(LEADER["nova_dmg"])
	br.aggro_radius = 60.0      # he comes straight for the hero
	br.leash = 80.0
	if world.visuals:
		Vfx.fire_explosion(self, p + Vector3(0, 1.0, 0), 1.4)
		var aura := Vfx.emitter({"amount": 26, "lifetime": 0.7, "one_shot": false, "vmin": 0.5, "vmax": 1.4,
			"direction": Vector3.UP, "spread": 20.0, "ring": [0.55, 0.3], "size": 0.55, "shader": "flame_solid",
			"local": false, "colors": [Color(1, 0.85, 0.5, 0.9), Color(1, 0.4, 0.1, 0.8), Color(0.3, 0.05, 0.02, 0)]})
		aura.position.y = 0.2
		leader.add_child(aura)
	world._say("Firebrand Kael: \"You dare? Then burn with the rest of it!\"", Color(1, 0.45, 0.2))
	_show_banner("Firebrand Kael emerges from the burning barn")
	_update_tracker()


func _farm_saved() -> void:
	print("[farm] farm saved at %.0fs" % _t)
	stage = Stage.SAVED
	_update_tracker()
	_show_banner("The raiders are broken. The fires die down.")
	for f in _fires:
		for e in f["fx"]:
			(e as GPUParticles3D).emitting = false
		var l: OmniLight3D = f["light"]
		create_tween().tween_property(l, "light_energy", 0.0, 4.0)
	for m in _glow_mats:
		create_tween().tween_property(m, "emission_energy_multiplier", 0.0, 4.0)
		create_tween().tween_property(m, "albedo_color", Color(0.05, 0.03, 0.02), 4.0)
	for e in _exit_fx:
		e.visible = true
	if farmer_rig != null:
		farmer_rig.idle_clip = "Idle_FoldArms"
	# Farmer comes out from behind the cart
	create_tween().tween_property(farmer, "position", position + FARMER_POS + Vector3(-2.5, 0, -2.0), 1.6)


func _tick_player_death(d: float) -> void:
	if world.player.alive:
		_dead_t = 0.0
		return
	_dead_t += d
	if _dead_t < 4.0:
		return
	# Wake by the farmhouse at full health; the raiders lose interest and go back to their fires
	world.player.alive = true
	world.player.auras.clear()
	world.player.hp = world.player.max_hp
	world.player.casting = {}
	world.player.position = position + RESPAWN
	world.player.target = null
	if world.player.nameplate:
		world.player.nameplate.modulate = world.player.color
	if world.player.model != null and world.player.model.has_method("play"):
		world.player.model.play("wake")   # gets up off the ground
	for m in mobs:
		m.threat.erase(world.player)
		m.damage_by.erase(world.player)
	Vfx.burst(world, world.player.position + Vector3(0, 1.2, 0), {"amount": 30, "lifetime": 0.8, "vmin": 1.0, "vmax": 3.0,
		"size": 0.3, "tex": "star", "colors": [Color(1, 0.9, 0.6, 1), Color(1, 0.7, 0.3, 0.8), Color(1, 0.5, 0.2, 0)]})


func _tick_corpses(d: float) -> void:
	for c in _corpses.duplicate():
		c[1] = float(c[1]) - d
		var u: Unit = c[0]
		if float(c[1]) < 1.5:
			u.position.y = lerpf(0.0, -1.2, 1.0 - float(c[1]) / 1.5)   # sink into the ash
		if float(c[1]) <= 0.0:
			_corpses.erase(c)
			# Gone: hidden and out of the world's lists (kept as an object, since the quest counts it)
			world.units.erase(u)
			if world.player.target == u:
				world.player.target = null
			u.visible = false
			u.set_process(false)


func _tick_fires() -> void:
	if stage >= Stage.SAVED:
		return
	for i in _fires.size():
		var l: OmniLight3D = _fires[i]["light"]
		l.light_energy = float(_fires[i]["base"]) * (1.0 + 0.22 * sin(_t * (5.0 + i * 1.3)) + 0.1 * sin(_t * 11.0 + i))


# ------------------------------------------------------------------ world.units

func _spawn_farmer() -> void:
	farmer = Unit.new()
	farmer.world = world
	farmer.team = "npc"
	farmer_rig = MobRig.new().build({"race": "Elf_Male", "outfit": "Peasant",
		"opts": {"tint": Color(0.75, 0.62, 0.45)}})
	farmer_rig.idle_clip = "Idle_Rail_Call"   # waving for help (Idle without library 2)
	world.add_child(farmer)
	farmer.setup_mob("Farmer Brannoc", 500.0, 0.0, 0.5, farmer_rig, 2.25, 1.2)
	farmer.team = "npc"
	farmer.role = "npc"
	farmer.untargetable = true
	farmer.nameplate.modulate = UITheme.GOLD
	farmer.position = position + FARMER_POS
	farmer.rotation.y = atan2(-(FARM_SPAWN.x - FARMER_POS.x), -(FARM_SPAWN.z - FARMER_POS.z))
	_block(FARMER_POS.x, FARMER_POS.z, 0.5)


func _spawn_raiders() -> void:
	# [kind, name, position, facing, group]
	var defs := [
		["z", Vector3(-6.5, 0, 11.0), -PI / 2.0, 1], ["z", Vector3(-7.5, 0, 3.5), -PI / 2.0 + 0.4, 1],
		["z", Vector3(17.0, 0, 18.0), 0.6, 2], ["w", Vector3(12.0, 0, 22.0), 2.0, 2], ["w", Vector3(21.0, 0, 13.0), -1.0, 2],
		["z", Vector3(8.0, 0, -9.0), PI / 2.0 + 0.5, 3], ["z", Vector3(10.5, 0, -2.0), 0.3, 3], ["w", Vector3(19.5, 0, -1.0), 2.5, 3],
		["z", Vector3(-22.0, 0, -14.0), 0.8, 4], ["z", Vector3(-17.0, 0, -19.0), -2.2, 4],
	]
	var zi := 0
	for d in defs:
		var u: Unit
		if d[0] == "z":
			u = _mob("Cinderbound Zealot", ZEALOT, ZEALOT_LOOKS[zi % ZEALOT_LOOKS.size()], d[1], d[2], d[3], true)
			zi += 1
		else:
			u = _whelp(d[1], d[2], d[3])
		_wave.append(u)


func _mob(nm: String, stats: Dictionary, look: Dictionary, p: Vector3, yaw: float, group: int, torch: bool,
		k := 1.0, weapon := "") -> Unit:
	var u := Unit.new()
	u.world = world
	var rig := MobRig.new().build(look, torch, k, weapon, 1.3)
	u.setup_mob(nm, float(stats["hp"]), float(stats["armor"]), 0.5 * k, rig, 2.2 * k, 1.2 * k)
	return _add_mob(u, stats, p, yaw, group)


func _whelp(p: Vector3, yaw: float, group: int) -> Unit:
	var u := Unit.new()
	u.world = world
	u.setup_mob("Ember Whelp", float(WHELP["hp"]), float(WHELP["armor"]), 0.9, Models.make_dragon(0.26), 2.6, 1.7)
	return _add_mob(u, WHELP, p, yaw, group)


func _add_mob(u: Unit, stats: Dictionary, p: Vector3, yaw: float, group: int) -> Unit:
	u.net_id = world._next_id
	world._next_id += 1
	u.position = position + p
	u.rotation.y = yaw
	world.add_child(u)
	world.units.append(u)
	world.by_id[u.net_id] = u
	mobs.append(u)
	var br := MobBrain.new(u, world)
	br.group = group
	br.damage = float(stats["damage"])
	br.interval = float(stats["interval"])
	br.speed = float(stats["speed"])
	u.brain = br
	return u


# ------------------------------------------------------------------ quest UI

func _update_tracker() -> void:
	if _tracker_lines == null:
		return
	var killed := _wave.filter(func(m): return not m.alive).size()
	match stage:
		Stage.ARRIVE:
			_tracker_title.text = "Smoke on the Horizon"
			_tracker_lines.text = "• Speak with the farmer by the south road"
		Stage.CLEAR:
			_tracker_title.text = "Smoke over the Fields"
			_tracker_lines.text = "• Drive off the Cinderbound raiders: %d / %d" % [killed, _wave.size()]
		Stage.LEADER:
			_tracker_title.text = "Smoke over the Fields"
			_tracker_lines.text = "• Raiders driven off: %d / %d  ✓\n• Defeat Firebrand Kael" % [killed, _wave.size()]
		Stage.SAVED:
			_tracker_title.text = "Smoke over the Fields  —  Complete"
			_tracker_lines.text = "• Return to Farmer Brannoc"
		Stage.LEAVING:
			_tracker_title.text = "The Road to Emberfall"
			_tracker_lines.text = "• Follow the north road to the Emberfall Outpost"


func _show_banner(text: String) -> void:
	_qbanner.text = text
	_qbanner_t = 4.0
	_qbanner.modulate.a = 1.0


func _open_dialog(speaker: String, text: String, button: String, cb: Callable) -> void:
	_dialog_name.text = speaker
	_dialog_text.text = text
	_dialog_btn.text = button + "   [F]"
	_dialog_cb = cb
	_dialog.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_dialog() -> void:
	if not _dialog.visible:
		return
	_dialog.visible = false
	if _dialog_cb.is_valid():
		_dialog_cb.call()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F and _dialog != null and _dialog.visible:
		_close_dialog()
		get_viewport().set_input_as_handled()


func _build_farm_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.theme()
	layer.add_child(root)
	# Quest banner under the hub's zone title
	_qbanner = UITheme.title("", 24, Color(1, 0.8, 0.45))
	_qbanner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_qbanner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_qbanner.offset_top = 112
	_qbanner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qbanner.modulate.a = 0.0
	root.add_child(_qbanner)
	# Quest tracker, top right
	var tracker := PanelContainer.new()
	_tracker = tracker
	tracker.add_theme_stylebox_override("panel", UITheme.iron_panel_hud())
	tracker.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tracker.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tracker.offset_top = 16
	tracker.offset_right = -16
	tracker.custom_minimum_size = Vector2(330, 0)
	tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tracker)
	var tv := VBoxContainer.new()
	tracker.add_child(tv)
	_tracker_title = UITheme.title("", 18)
	tv.add_child(_tracker_title)
	_tracker_lines = Label.new()
	_tracker_lines.add_theme_color_override("font_color", UITheme.TEXT)
	_tracker_lines.add_theme_font_size_override("font_size", 15)
	tv.add_child(_tracker_lines)
	# Dialog, bottom centre (above the action bar)
	_dialog = PanelContainer.new()
	_dialog.add_theme_stylebox_override("panel", UITheme.parchment())
	_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dialog.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dialog.offset_bottom = -130
	_dialog.custom_minimum_size = Vector2(640, 0)
	_dialog.visible = false
	root.add_child(_dialog)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 10)
	_dialog.add_child(dv)
	_dialog_name = UITheme.title("", 22, UITheme.INK)
	dv.add_child(_dialog_name)
	_dialog_text = Label.new()
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.custom_minimum_size = Vector2(600, 0)
	_dialog_text.add_theme_color_override("font_color", UITheme.INK)
	_dialog_text.add_theme_font_size_override("font_size", 17)
	dv.add_child(_dialog_text)
	_dialog_btn = Button.new()
	_dialog_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_dialog_btn.custom_minimum_size = Vector2(240, 40)
	_dialog_btn.pressed.connect(_close_dialog)
	dv.add_child(_dialog_btn)


# ------------------------------------------------------------------ the land

func _build_land() -> void:
	if world.terrain != null:
		# Terrain3D carries the ground: register the tracks, yards and fields to paint into it
		var o := Vector2(position.x, position.z)
		var t := world.terrain
		t.paint_paths.append([o + Vector2(0, -75), o + Vector2(0, 62), 1.6])          # the north-south road
		t.paint_paths.append([o + Vector2(0, 4), o + Vector2(9, -4), 1.2])            # to the yard
		t.paint_paths.append([o + Vector2(17, 11), o + Vector2(17, 28), 9.5])         # east wheat field
		t.paint_paths.append([o + Vector2(-23, -26), o + Vector2(-23, -6), 7.5])      # west wheat field
		for y in [[Vector2(-11, 7), 9.0], [Vector2(14, -9), 9.0], [Vector2(4, -1), 7.0]]:
			t.paint_yards.append([o + y[0], y[1], WorldTerrain.Tex.DIRT])
		for y in [[Vector2(-12, 7), 5.0], [Vector2(14, -12), 6.0], [Vector2(5, -3), 2.5], [Vector2(-24, 20), 2.5]]:
			t.paint_yards.append([o + y[0], y[1], WorldTerrain.Tex.ASH])            # scorched by the raid
		if _day:
			_build_nature()
		return
	# Farmland disc, tiled so each patch only takes the lights near it (mobile renderer light cap)
	var tile := 10.0
	var pm := PlaneMesh.new()
	pm.size = Vector2(tile, tile)
	for ix in range(-7, 7):
		for iz in range(-7, 7):
			var c := Vector3((ix + 0.5) * tile, 0.0, (iz + 0.5) * tile)
			if Vector2(absf(c.x) - tile * 0.5, absf(c.z) - tile * 0.5).length() > FARM_RADIUS + 14.0:
				continue
			Models.part(self, pm, _grass, c)
	# The open country rolls on south, east and west (the causeway comes in from the north)
	var far := PlaneMesh.new()
	far.size = Vector2(700, 520)
	Models.part(self, far, _grass, Vector3(0, -0.06, 215))
	var flank := PlaneMesh.new()
	flank.size = Vector2(260, 150)
	for sx in [-1.0, 1.0]:
		Models.part(self, flank, _grass, Vector3(sx * 140.0, -0.06, -30))
	# Scorched patches around the fires and a dirt yard round the buildings
	for p in [Vector3(-11, 0, 7), Vector3(14, 0, -9), Vector3(4, 0, -1)]:
		var yard := Models.cyl(9.0, 9.0, 0.02)
		yard.radial_segments = 20
		Models.part(self, yard, _soil, p + Vector3(0, 0.01, 0))
	# The road: south gate to north exit, with a branch to the yard
	_dirt_road(Vector3(0, 0, 60), Vector3(0, 0, -60), 1.6)
	_dirt_road(Vector3(0, 0, 4), Vector3(9, 0, -4), 1.2)
	if ResourceLoader.exists(NAT + "CommonTree_1.gltf"):
		_build_nature()
		return
	# Without the nature kit: simple tufts, stones, cone trees and dark hills
	# Grass tufts and field stones break up the open ground
	var tufts: Array = []
	var stones: Array = []
	for i in 900:
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * (FARM_RADIUS + 10.0)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		if absf(p.x) < 2.2:
			continue
		var b := Basis.from_euler(Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3)))
		if i % 12 == 0:
			stones.append(Transform3D(b.scaled(Vector3(1.0, 0.6, 0.8) * _rng.randf_range(0.2, 0.55)), p))
		else:
			tufts.append(Transform3D(b.scaled(Vector3.ONE * _rng.randf_range(0.5, 1.1)), p + Vector3(0, 0.15, 0)))
	var tuft := Models.cyl(0.0, 0.16, 0.4)
	tuft.radial_segments = 4
	_multi(tuft, Models.mat(Color(0.2, 0.24, 0.1), 0.0, 1.0), tufts)
	var stone := Models.box(1.0, 1.0, 1.0)
	_multi(stone, _stone, stones)
	# Low hills and dark woods close the farm in; volcanoes smoulder far off
	var hill_m := Models.mat(Color(0.13, 0.11, 0.07), 0.0, 1.0)
	for i in 26:
		var a := TAU * i / 26.0 + _rng.randf_range(-0.1, 0.1)
		if absf(sin(a)) > 0.97:
			continue   # leave the road gaps north and south
		var d := _rng.randf_range(62.0, 75.0)
		var hill := SphereMesh.new()
		hill.radial_segments = 10
		hill.rings = 5
		hill.radius = _rng.randf_range(10.0, 16.0)
		hill.height = hill.radius * 2.0
		Models.part(self, hill, hill_m, Vector3(cos(a) * d, -hill.radius * 0.55, sin(a) * d), Vector3(0, _rng.randf() * TAU, 0),
			Vector3(1.6, _rng.randf_range(0.5, 0.9), 1.2))
	for i in 70:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(FARM_RADIUS + 2.0, 62.0)
		if absf(cos(a) * d) < 6.0:
			continue   # keep the road clear
		_tree(Vector3(cos(a) * d, 0, sin(a) * d), _rng.randf() < 0.3)


func _dirt_road(a: Vector3, b: Vector3, half_w: float) -> void:
	var dir := (b - a).normalized()
	var yaw := atan2(dir.x, dir.z)
	var length := a.distance_to(b)
	Models.part(self, Models.box(half_w * 2.0, 0.04, length), _road_mat(),
		(a + b) * 0.5 + Vector3(0, 0.02, 0), Vector3(0, yaw, 0))
	# Cart ruts
	var rut := _soil if not _day else Models.mat(Color(0.55, 0.43, 0.28), 0.0, 1.0)
	for sx in [-0.45, 0.45]:
		var side: Vector3 = Vector3(-dir.z, 0, dir.x) * half_w * float(sx)
		Models.part(self, Models.box(0.25, 0.045, length), rut, (a + b) * 0.5 + side + Vector3(0, 0.025, 0), Vector3(0, yaw, 0))


## Flame colours: in sunlight the near-white core washes out, so daytime fire burns deeper orange.
func _flame_colors() -> Array:
	if _day:
		return [Color(1, 0.72, 0.22, 1), Color(1, 0.38, 0.06, 0.95), Color(0.6, 0.1, 0.02, 0.5), Color(0.15, 0.05, 0.03, 0)]
	return [Color(1, 0.92, 0.6, 1), Color(1, 0.52, 0.12, 0.95), Color(0.55, 0.12, 0.03, 0.45), Color(0.1, 0.05, 0.05, 0)]


func _road_mat() -> StandardMaterial3D:
	if _day:
		return Models.mat(Color(0.64, 0.52, 0.34), 0.0, 1.0)   # sunlit sandy track
	return Models.mat(Color(0.2, 0.15, 0.1), 0.0, 1.0)


# ------------------------------------------------------------------ daylight and nature

## A nature kit model's mesh (with its in-scene transform), for MultiMesh scattering.
## A lower-resolution copy of a nature model, built from the LOD levels Godot generated on import:
## each surface uses the level closest to `ratio` of its full triangle count.
static var _lite_meshes := {}


static func _nat_lite(nm: String, ratio: float) -> Mesh:
	var key := "%s@%.2f" % [nm, ratio]
	if _lite_meshes.has(key):
		return _lite_meshes[key]
	var full: Mesh = _nat_mesh(nm)[0]
	var out := ArrayMesh.new()
	for si in full.get_surface_count():
		var arrays := full.surface_get_arrays(si)
		var d: Dictionary = RenderingServer.mesh_get_surface(full.get_rid(), si)
		var verts := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var base_tris := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var best: PackedByteArray = PackedByteArray()
		var best_err := absf(1.0 - ratio)   # the full mesh's error
		for ld in d.get("lods", []):
			var bytes: PackedByteArray = ld["index_data"]
			var tris := bytes.size() / (2 if verts <= 65535 else 4) / 3
			var err := absf(float(tris) / maxf(base_tris, 1) - ratio)
			if err < best_err:
				best_err = err
				best = bytes
		if not best.is_empty():
			var idx := PackedInt32Array()
			var n := best.size() / (2 if verts <= 65535 else 4)
			idx.resize(n)
			for i in n:
				idx[i] = best.decode_u16(i * 2) if verts <= 65535 else best.decode_u32(i * 4)
			arrays[Mesh.ARRAY_INDEX] = idx
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, full.surface_get_material(si))
	_lite_meshes[key] = out
	return out


static func _nat_mesh(nm: String) -> Array:
	if not _nat_meshes.has(nm):
		var scene: Node = (load(NAT + nm + ".gltf") as PackedScene).instantiate()
		var mi := scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var inner := mi.transform
		var n := mi.get_parent()
		while n != null and n != scene:
			if n is Node3D:
				inner = (n as Node3D).transform * inner
			n = n.get_parent()
		_nat_meshes[nm] = [mi.mesh, inner]
		scene.free()
	return _nat_meshes[nm]


## Scatter instances of nature models: entries are [model name, position, yaw, scale].
## Entries are grouped per model into 32 m patches, so the renderer can skip whole patches that are
## off screen or too far (vis_end > 0). far_lod: trees beyond vis_end show as cheap stand-ins.
const CELL := 32.0
const FAR_END := 420.0


## detail: fraction of the model's triangles to draw (its import LODs); shadows come from a much
## coarser copy that only casts shadows.
func _scatter(entries: Array, vis_end := 0.0, shadows := true, far_lod := false, detail := 1.0) -> void:
	var groups := {}
	for e in entries:
		var nm: String = e[0]
		var b := Basis(Vector3.UP, float(e[2])).scaled(Vector3.ONE * float(e[3]))
		var p: Vector3 = e[1]
		if world.terrain != null:
			p.y += WorldTerrain.height(p.x + position.x, p.z + position.z)   # on the hills
		var key := "%s|%d|%d" % [nm, floori(p.x / CELL), floori(p.z / CELL)]
		if not groups.has(key):
			groups[key] = [nm, Vector3((floori(p.x / CELL) + 0.5) * CELL, 0, (floori(p.z / CELL) + 0.5) * CELL), []]
		(groups[key][2] as Array).append(Transform3D(b, p))
	for key in groups:
		var nm: String = groups[key][0]
		var centre: Vector3 = groups[key][1]
		var xforms: Array = groups[key][2]
		var info := _nat_mesh(nm)
		var mesh: Mesh = info[0] if detail >= 0.99 else _nat_lite(nm, detail)
		var mmi := _patch(mesh, info[1], centre, xforms)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if shadows:
			# Shadows from a far coarser copy (shadow-only): the sun redraws casters for every cascade
			var caster := _patch(_nat_lite(nm, 0.06), info[1], centre, xforms)
			caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			if vis_end > 0.0:
				caster.visibility_range_end = vis_end
		if vis_end > 0.0:
			mmi.visibility_range_end = vis_end
			mmi.visibility_range_end_margin = 6.0
		if far_lod and vis_end > 0.0:
			var far := _far_tree(nm)
			if far != null:
				var lod := _patch(far, Transform3D(), centre, xforms)
				lod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				lod.visibility_range_begin = vis_end
				lod.visibility_range_begin_margin = 6.0
				lod.visibility_range_end = FAR_END


func _patch(mesh: Mesh, inner: Transform3D, centre: Vector3, xforms: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		var xf: Transform3D = xforms[i]
		mm.set_instance_transform(i, Transform3D(xf.basis, xf.origin - centre) * inner)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = centre
	add_child(mmi)
	return mmi


static var _far_meshes := {}


## A few-dozen-triangle stand-in for a distant tree: trunk plus a cone (pines) or a rough crown.
static func _far_tree(nm: String) -> Mesh:
	var kind := "pine" if nm.begins_with("Pine") else ("round" if nm.begins_with("Common") or nm.begins_with("Twisted") else "")
	if kind == "":
		return null
	if _far_meshes.has(kind):
		return _far_meshes[kind]
	# Two surfaces with their own materials: a bark trunk and a leafy crown
	var m := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.3
	trunk.height = 3.2
	trunk.radial_segments = 5
	trunk.rings = 1
	var crown: PrimitiveMesh
	var crown_y := 4.9
	if kind == "pine":
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 2.2
		c.height = 5.6
		c.radial_segments = 7
		c.rings = 1
		crown = c
		crown_y = 4.4
	else:
		var sp := SphereMesh.new()
		sp.radius = 2.1
		sp.height = 3.6
		sp.radial_segments = 7
		sp.rings = 4
		crown = sp
	for part in [[trunk, 1.6, Color(0.42, 0.29, 0.18)], [crown, crown_y,
			Color(0.24, 0.42, 0.15) if kind == "pine" else Color(0.34, 0.52, 0.18)]]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(part[0], 0, Transform3D(Basis(), Vector3(0, float(part[1]), 0)))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = part[2]
		mat.roughness = 1.0
		st.commit(m)
		m.surface_set_material(m.get_surface_count() - 1, mat)
	_far_meshes[kind] = m
	return m


## Open ground away from the road, buildings, fields and the farmer's cart.
func _open(p: Vector3, margin := 0.0) -> bool:
	if absf(p.x) < 2.6 + margin:
		return false
	for r in [Rect2(6, 10, 22, 19), Rect2(-31, -27, 17, 22)]:   # wheat fields
		if (r as Rect2).grow(margin + 0.5).has_point(Vector2(p.x, p.z)):
			return false
	for c in [[Vector3(-12, 0, 7), 6.5], [Vector3(14, 0, -12), 8.0], [Vector3(-3.5, 0, -2), 2.0], [FARMER_POS, 3.5],
			[Vector3(5, 0, -3), 2.2], [Vector3(23, 0, 4), 2.2], [Vector3(-24, 0, 20), 2.2], [Vector3(-20, 0, 24), 2.2],
			[Vector3(4.5, 0, 0), 3.0], [Vector3(3.2, 0, EXIT_Z + 3.0), 1.5]]:
		if p.distance_to(c[0]) < float(c[1]) + margin:
			return false
	return true


func _build_nature() -> void:
	var trees := ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5"]
	var pines := ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"]
	var twisted := ["TwistedTree_1", "TwistedTree_4", "TwistedTree_5"]
	var big: Array = []
	# The wood around the clearing: dense and tall, leaving the road open north and south
	for i in 150:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(FARM_RADIUS + 1.0, 88.0)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		if absf(p.x) < 5.0 + (d - FARM_RADIUS) * 0.08 or p.z < -FARM_RADIUS + 4.0 and absf(p.x) < 22.0 + (d - FARM_RADIUS):
			continue   # the road north and south stays open; to the north the land opens onto the causeway
		var r := _rng.randf()
		var nm: String = (trees if r < 0.55 else pines if r < 0.93 else twisted).pick_random()
		var k := _rng.randf_range(1.2, 1.9) if not nm.begins_with("Twisted") else _rng.randf_range(0.55, 0.75)
		big.append([nm, p, _rng.randf() * TAU, k])
	# A few trees inside the clearing, and dead ones scorched by the raid
	for t in [[Vector3(-27, 0, 25), "CommonTree_2"], [Vector3(-37, 0, 4), "Pine_2"], [Vector3(-9, 0, -32), "CommonTree_4"],
			[Vector3(31, 0, -30), "Pine_4"], [Vector3(35, 0, 21), "CommonTree_1"], [Vector3(-40, 0, -18), "CommonTree_5"],
			[Vector3(22, 0, 39), "Pine_1"], [Vector3(-19, 0, 39), "CommonTree_3"], [Vector3(-34, 0, -30), "DeadTree_2"],
			[Vector3(25, 0, -24), "DeadTree_1"], [Vector3(-24, 0, 13), "DeadTree_4"]]:
		var pos: Vector3 = t[0]
		var nm2: String = t[1]
		big.append([nm2, pos, _rng.randf() * TAU, 1.0 if nm2.begins_with("Dead") else _rng.randf_range(1.3, 1.6)])
		_block(pos.x, pos.z, 0.8)
	_scatter(big, 85.0, true, true, 0.25)
	# Boulders
	var rocks: Array = []
	for i in 34:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(20.0, 70.0)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		if not _open(p, 2.0):
			continue
		var k := _rng.randf_range(0.5, 1.2)
		rocks.append(["Rock_Medium_%d" % _rng.randi_range(1, 3), p, _rng.randf() * TAU, k])
		if d < FARM_RADIUS:
			_block(p.x, p.z, 1.4 * k)
	_scatter(rocks, 170.0, true, false, 0.5)
	# Meadow: knee-high grass everywhere; flowers, ferns, bushes and mushrooms
	var meadow: Array = []   # (no scattered grass clumps: the ground's own grass texture is enough detail)
	var flora := ["Flower_3_Group", "Flower_4_Group", "Clover_1", "Clover_2", "Fern_1", "Plant_1", "Plant_7", "Bush_Common",
		"Bush_Common_Flowers", "Mushroom_Common", "Flower_3_Single", "Flower_4_Single", "Plant_1_Big"]
	for i in 520:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(12.0, 70.0) if i % 3 != 0 else _rng.randf_range(36.0, 60.0)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		if not _open(p, 0.5):
			continue
		var nm: String = flora.pick_random()
		var k := _rng.randf_range(0.45, 0.8)
		if nm.begins_with("Bush") or nm == "Plant_1_Big":
			k = _rng.randf_range(0.6, 0.9)
		meadow.append([nm, p, _rng.randf() * TAU, k])
	# The track: path stones along its edges and pebbles in the dust
	for z in range(-60, 61, 2):
		for side in [-1.0, 1.0]:
			if _rng.randf() < 0.55:
				var p := Vector3(float(side) * _rng.randf_range(1.7, 2.6), 0, z + _rng.randf_range(-0.8, 0.8))
				meadow.append(["RockPath_Round_Small_%d" % _rng.randi_range(1, 3), p, _rng.randf() * TAU, _rng.randf_range(0.35, 0.6)])
		if _rng.randf() < 0.6:
			var p2 := Vector3(_rng.randf_range(-1.4, 1.4), 0.02, z + _rng.randf_range(-1, 1))
			meadow.append(["Pebble_Round_%d" % _rng.randi_range(1, 5), p2, _rng.randf() * TAU, _rng.randf_range(0.4, 0.8)])
	_scatter(meadow, 55.0, false)
	if world.terrain != null:
		return   # the terrain has its own colours and real hills
	# Patches of richer and drier grass so the meadow isn't one flat colour
	for i in 46:
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * 60.0
		var p := Vector3(cos(a) * d, 0.012 + i * 0.0003, sin(a) * d)
		var patch := Models.cyl(1.0, 1.0, 0.01)
		patch.radial_segments = 12
		var c := Color(0.26, 0.4, 0.12) if i % 2 == 0 else Color(0.42, 0.48, 0.18)
		Models.part(self, patch, Models.mat(c, 0.0, 1.0), p, Vector3(0, _rng.randf() * TAU, 0),
			Vector3(_rng.randf_range(3.0, 7.0), 1, _rng.randf_range(2.0, 5.0)))
	# Green hills rolling away past the woods
	var hill_m := Models.mat(Color(0.3, 0.47, 0.18), 0.0, 1.0)
	for i in 22:
		var a := TAU * i / 22.0 + _rng.randf_range(-0.1, 0.1)
		var d := _rng.randf_range(105.0, 140.0)
		if sin(a) * d < -70.0:
			continue   # nothing between the farm and the causeway to the north
		var hill := SphereMesh.new()
		hill.radial_segments = 14
		hill.rings = 7
		hill.radius = _rng.randf_range(22.0, 34.0)
		hill.height = hill.radius * 2.0
		Models.part(self, hill, hill_m, Vector3(cos(a) * d, -hill.radius * 0.6, sin(a) * d), Vector3(0, _rng.randf() * TAU, 0),
			Vector3(1.7, _rng.randf_range(0.45, 0.75), 1.3))



func _tree(p: Vector3, burnt: bool) -> void:
	var s := _rng.randf_range(0.8, 1.4)
	var trunk_m := _char if burnt else _wood_dark
	Models.part(self, Models.cyl(0.18 * s, 0.3 * s, 3.0 * s), trunk_m, p + Vector3(0, 1.5 * s, 0))
	if burnt:
		for k in 3:   # bare, blackened branches
			Models.part(self, Models.cyl(0.03, 0.08, 1.4 * s), _char, p + Vector3(0, (2.3 + k * 0.4) * s, 0),
				Vector3(_rng.randf_range(-0.9, 0.9), _rng.randf() * TAU, _rng.randf_range(-0.9, 0.9)))
		return
	var leaf := Models.mat(Color(0.1, 0.17, 0.08).lerp(Color(0.2, 0.16, 0.06), _rng.randf()), 0.0, 1.0)
	for k in 3:
		var cone := Models.cyl(0.0, (1.7 - k * 0.35) * s, 2.0 * s)
		cone.radial_segments = 7
		Models.part(self, cone, leaf, p + Vector3(0, (2.6 + k * 1.1) * s, 0), Vector3(0, _rng.randf() * TAU, 0))


func _fire(p: Vector3, extent: Vector3, light_e := 2.2, light_r := 11.0) -> void:
	var area := extent.x * extent.z
	var flames := Vfx.emitter({"amount": int(clampf(14 + area * 10.0, 14, 60)), "lifetime": 0.85, "one_shot": false,
		"vmin": 0.8, "vmax": 2.2, "direction": Vector3.UP, "spread": 12.0, "box": extent, "size": 1.0 + extent.y * 0.6,
		"shader": "flame_solid", "colors": _flame_colors()})
	flames.position = p
	add_child(flames)
	var smoke := Vfx.emitter({"amount": 12, "lifetime": 5.0, "one_shot": false, "vmin": 1.4, "vmax": 2.4,
		"direction": Vector3.UP, "spread": 10.0, "sphere": maxf(extent.x, extent.z) * 0.6, "size": 3.0, "shader": "smoke",
		"grow": true, "gravity": Vector3(0.7, 0.3, 0.2), "colors": [Color(0.16, 0.13, 0.12, 0), Color(0.12, 0.1, 0.1, 0.6),
			Color(0.08, 0.07, 0.07, 0)]})
	smoke.position = p + Vector3(0, 2.5, 0)
	add_child(smoke)
	var l := _light(p + Vector3(0, 1.4, 0), Color(1.0, 0.48, 0.14), light_r, light_e)
	_fires.append({"fx": [flames], "light": l, "base": light_e})


# ------------------------------------------------------------------ buildings

func _build_farmstead() -> void:
	if ResourceLoader.exists(BLD + "House_1.fbx"):
		# Prebuilt timber-frame buildings (Quaternius village pack); the raiders' fires sit on their roofs
		var house := _building("House_1", Vector3(-12, 0, 7), PI / 2.0, 3.2)
		_fire(Vector3(-12, house.y * 0.78, 8.5), Vector3(2.6, 0.7, 1.6), 2.6, 14.0)
		_fire(Vector3(-8.0, 1.0, 5.0), Vector3(0.8, 0.4, 0.6), 1.2, 7.0)
		var barn := _building("Stable", Vector3(14, 0, -12), 0.0, 2.6)
		_fire(Vector3(11.0, barn.y * 0.8, -12.5), Vector3(3.2, 0.8, 1.8), 2.8, 15.0)
		_fire(Vector3(17.0, 0.6, -8.5), Vector3(1.4, 0.6, 0.5), 1.5, 9.0)
		_building("Mill", Vector3(27, 0, -31), -0.7, 3.0)
	else:
		_house(Vector3(-12, 0, 7), PI / 2.0)
		_barn(Vector3(14, 0, -12), 0.0)
	_well(Vector3(-3.5, 0, -2.0))
	_cart(FARMER_POS + Vector3(-1.3, 0, -1.6), 0.4)
	for hs in [[Vector3(5, 0, -3), true], [Vector3(23, 0, 4), false], [Vector3(-24, 0, 20), true], [Vector3(-20, 0, 24), false]]:
		_haystack(hs[0], hs[1])
	_supplies(Vector3(-5.5, 0, 14.5))
	_supplies(Vector3(7.0, 0, -15.5))
	# Fences along the fields
	_fence(Vector3(5, 0, 9), Vector3(28, 0, 9))
	_fence(Vector3(5, 0, 9), Vector3(5, 0, 29))
	_fence(Vector3(-31, 0, -4), Vector3(-14, 0, -4))
	_fence(Vector3(-31, 0, -4), Vector3(-31, 0, -27))


## Place a prebuilt building (its door faces +Z before `yaw`) and block its footprint. Returns its size.
func _building(nm: String, p: Vector3, yaw: float, k: float) -> Vector3:
	var b: Node3D = (load(BLD + nm + ".fbx") as PackedScene).instantiate()
	b.scale = Vector3.ONE * k
	b.rotation.y = yaw
	b.position = p
	add_child(b)
	var box := AABB()
	var first := true
	for mi in b.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var a := (b.global_transform.affine_inverse() * m.global_transform) * m.get_aabb()
		box = a if first else box.merge(a)
		first = false
		if m.name.ends_with("_Blades"):
			_mill_blades = m
	var size := box.size * k
	# Footprint (local x/z) as a capsule along its longer side, turned with the building
	var c := Vector3((box.position.x + box.size.x * 0.5) * k, 0, (box.position.z + box.size.z * 0.5) * k).rotated(Vector3.UP, yaw)
	var long_x := size.x >= size.z
	var half := (maxf(size.x, size.z) - minf(size.x, size.z)) * 0.5
	var axis := (Vector3.RIGHT if long_x else Vector3.BACK).rotated(Vector3.UP, yaw)
	_block_line(p + c - axis * half, p + c + axis * half, minf(size.x, size.z) * 0.5 * 0.9)
	return size


func _house(p: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = yaw
	add_child(root)
	var plaster := Models.mat(Color(0.62, 0.55, 0.44), 0.0, 1.0)
	Models.part(root, Models.box(8.0, 3.2, 6.0), plaster, Vector3(0, 1.6, 0))
	# Timber frame
	for x in [-3.9, -1.3, 1.3, 3.9]:
		for z in [-3.02, 3.02]:
			Models.part(root, Models.box(0.25, 3.2, 0.1), _wood_dark, Vector3(x, 1.6, z))
	Models.part(root, Models.box(8.1, 0.25, 6.1), _wood_dark, Vector3(0, 3.1, 0))
	# Pitched thatch roof, half of it burned through
	for sz in [-1.0, 1.0]:
		Models.part(root, Models.box(8.8, 0.3, 4.1), _straw if sz < 0 else _char, Vector3(0, 4.3, sz * 1.55),
			Vector3(sz * 0.72, 0, 0))
	for sx in [-1.0, 1.0]:   # gables
		var gable := Models.cyl(0.02, 3.4, 2.4)
		gable.radial_segments = 3
		Models.part(root, gable, plaster, Vector3(sx * 3.95, 4.2, 0), Vector3(0, 0, 0), Vector3(0.05, 1, 1))
	Models.part(root, Models.box(0.8, 2.2, 0.8), _stone, Vector3(2.5, 4.8, 1.2))   # chimney
	# Door, and windows glowing with the fire inside
	Models.part(root, Models.box(1.2, 2.1, 0.12), _wood_dark, Vector3(0, 1.05, -3.05))
	var glow := Models.mat(Color(1.0, 0.5, 0.15), 2.5)
	_glow_mats.append(glow)
	for x in [-2.5, 2.5]:
		Models.part(root, Models.box(1.0, 0.9, 0.1), glow, Vector3(x, 1.8, -3.04))
		Models.part(root, Models.box(1.0, 0.9, 0.1), glow, Vector3(x, 1.8, 3.04))
	_fire(root.to_global(Vector3(0, 4.6, 1.6)) - global_position, Vector3(3.5, 0.6, 1.5), 2.6, 14.0)
	_fire(root.to_global(Vector3(2.0, 1.0, -3.5)) - global_position, Vector3(0.8, 0.4, 0.4), 1.2, 7.0)
	var a := root.to_global(Vector3(-4.0, 0, 0)) - global_position
	var b := root.to_global(Vector3(4.0, 0, 0)) - global_position
	_block_line(a, b, 3.1)


func _barn(p: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = yaw
	add_child(root)
	Models.part(root, Models.box(11.0, 4.5, 8.0), _red, Vector3(0, 2.25, 0))
	for x in [-5.4, 5.4]:
		Models.part(root, Models.box(0.3, 4.5, 8.1), _wood_dark, Vector3(x, 2.25, 0))
	# Big doors facing the yard (south), one hanging open with fire behind it
	Models.part(root, Models.box(4.0, 3.6, 0.1), Models.mat(Color(0.05, 0.02, 0.01)), Vector3(0, 1.8, 4.02))
	var glow := Models.mat(Color(1.0, 0.45, 0.12), 1.6)
	_glow_mats.append(glow)
	Models.part(root, Models.box(3.0, 2.0, 0.05), glow, Vector3(0, 1.0, 4.05))
	Models.part(root, Models.box(2.0, 3.6, 0.15), _red, Vector3(-2.8, 1.8, 4.6), Vector3(0, -0.9, 0))
	for x in [-1.0, 1.0]:
		Models.part(root, Models.box(0.15, 3.6, 0.17), _wood_dark, Vector3(x * 2.05, 1.8, 4.06))
	# Gambrel roof
	for sz in [-1.0, 1.0]:
		Models.part(root, Models.box(11.6, 0.3, 3.0), _wood_dark, Vector3(0, 5.2, sz * 3.1), Vector3(sz * 0.95, 0, 0))
		Models.part(root, Models.box(11.6, 0.3, 2.6), _char if sz > 0 else _wood_dark, Vector3(0, 6.6, sz * 1.1),
			Vector3(sz * 0.4, 0, 0))
	_fire(Vector3(p.x - 2.0, 6.5, p.z + 1.0), Vector3(3.5, 0.8, 2.0), 2.8, 15.0)
	_fire(Vector3(p.x, 0.5, p.z + 4.5), Vector3(1.5, 0.6, 0.4), 1.5, 9.0)
	_block_line(Vector3(p.x - 5.5, 0, p.z), Vector3(p.x + 5.5, 0, p.z), 4.0)


func _well(p: Vector3) -> void:
	var ring := Models.cyl(1.0, 1.05, 0.9)
	ring.radial_segments = 10
	Models.part(self, ring, _stone, p + Vector3(0, 0.45, 0))
	Models.part(self, Models.cyl(0.8, 0.8, 0.05), Models.mat(Color(0.05, 0.07, 0.08), 0.0, 0.1), p + Vector3(0, 0.85, 0))
	for sx in [-1.0, 1.0]:
		Models.part(self, Models.box(0.15, 2.0, 0.15), _wood_dark, p + Vector3(sx * 0.9, 1.4, 0))
	Models.part(self, Models.box(2.2, 0.15, 1.4), _wood, p + Vector3(0, 2.45, 0), Vector3(0, 0, 0))
	Models.part(self, Models.cyl(0.08, 0.08, 1.8), _wood_dark, p + Vector3(0, 2.0, 0), Vector3(0, 0, PI / 2.0))
	_block(p.x, p.z, 1.1)


func _cart(p: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = yaw
	add_child(root)
	Models.part(root, Models.box(1.6, 0.15, 2.6), _wood, Vector3(0, 0.75, 0))
	for sx in [-1.0, 1.0]:
		Models.part(root, Models.box(0.1, 0.5, 2.6), _wood, Vector3(sx * 0.8, 1.05, 0))
		var wheel := Models.cyl(0.55, 0.55, 0.12)
		wheel.radial_segments = 10
		Models.part(root, wheel, _wood_dark, Vector3(sx * 0.9, 0.55, 0.3), Vector3(0, 0, PI / 2.0))
	Models.part(root, Models.box(0.1, 0.1, 2.0), _wood_dark, Vector3(0, 0.6, -2.1))
	var sack := Models.mat(Color(0.45, 0.38, 0.26))
	for i in 3:   # sacks of grain he managed to save
		Models.part(root, Models.box(0.5, 0.35, 0.75), sack, Vector3(-0.4 + i * 0.4, 1.0, -0.5 + i * 0.45),
			Vector3(0.1, 0.35 * i - 0.3, 0.08))
		Models.part(root, Models.box(0.2, 0.12, 0.2), sack, Vector3(-0.4 + i * 0.4, 1.2, -0.85 + i * 0.45))   # tied neck
	_block(p.x, p.z, 1.3)


func _haystack(p: Vector3, burning: bool) -> void:
	var body := Models.cyl(1.4, 1.6, 1.6)
	body.radial_segments = 9
	Models.part(self, body, _char if burning else _straw, p + Vector3(0, 0.8, 0))
	if not burning:   # binding ropes
		for y in [0.5, 1.2]:
			var band := Models.cyl(1.48 + (0.5 - y) * 0.15, 1.5 + (0.5 - y) * 0.15, 0.08)
			band.radial_segments = 9
			Models.part(self, band, _wood_dark, p + Vector3(0, y, 0))
	var top := Models.cyl(0.1, 1.45, 1.3)
	top.radial_segments = 9
	Models.part(self, top, _char if burning else _straw, p + Vector3(0, 2.25, 0))
	if burning:
		_fire(p + Vector3(0, 1.4, 0), Vector3(1.1, 0.6, 1.1), 2.0, 10.0)
	_block(p.x, p.z, 1.5)


func _fence(a: Vector3, b: Vector3) -> void:
	var dir := (b - a).normalized()
	var n := int(a.distance_to(b) / 2.5)
	var yaw := atan2(dir.x, dir.z)
	var posts: Array = []
	for i in n + 1:
		var p := a + dir * (i * 2.5)
		posts.append(Transform3D(Basis(), p + Vector3(0, 0.6, 0)))
	_multi(Models.box(0.15, 1.2, 0.15), _wood_dark, posts)
	for h in [0.5, 1.0]:
		Models.part(self, Models.box(0.08, 0.1, n * 2.5), _wood, (a + a + dir * (n * 2.5)) * 0.5 + Vector3(0, h, 0),
			Vector3(0, yaw, 0))


func _build_fields() -> void:
	# Wheat in rows: the east field half burned, the west field burning at the far edge
	var stalk := Models.cyl(0.0, 0.09, 1.0)
	stalk.radial_segments = 4
	for f in [[Vector3(7, 0, 11), Vector3(27, 0, 28), Vector3(10, 0, 18), 6.0], [Vector3(-30, 0, -26), Vector3(-15, 0, -6),
			Vector3(-24, 0, -24), 5.0]]:
		var lo: Vector3 = f[0]
		var hi: Vector3 = f[1]
		var burn_c: Vector3 = f[2]
		var burn_r: float = f[3]
		var gold: Array = []
		var black: Array = []
		var z := lo.z
		while z < hi.z:
			var x := lo.x
			while x < hi.x:
				var p := Vector3(x + _rng.randf_range(-0.2, 0.2), 0.45, z + _rng.randf_range(-0.15, 0.15))
				var xf := Transform3D(Basis.from_euler(Vector3(_rng.randf_range(-0.15, 0.15), 0, _rng.randf_range(-0.15, 0.15)))
					.scaled(Vector3.ONE * _rng.randf_range(0.8, 1.15)), p)
				if Vector2(p.x - burn_c.x, p.z - burn_c.z).length() < burn_r:
					xf = Transform3D(xf.basis.scaled(Vector3(1, 0.4, 1)), Vector3(p.x, 0.18, p.z))
					black.append(xf)
				else:
					gold.append(xf)
				x += 0.55 if not _day else 0.95
			z += 1.1 if not _day else 1.45
		if _day:
			# Daylight: wheat sheaves from the nature kit's wispy grass, ripe gold (or burnt black)
			var wheat: Mesh = _nat_mesh("Grass_Wispy_Tall")[0]
			var k := Basis().scaled(Vector3(0.75, 0.85, 0.75))
			for mm in [_multi(wheat, Models.mat(Color(0.86, 0.68, 0.3), 0.0, 1.0), gold.map(func(x): return Transform3D(x.basis * k, Vector3(x.origin.x, 0, x.origin.z)))),
					_multi(wheat, _char, black.map(func(x): return Transform3D(x.basis * k, Vector3(x.origin.x, 0, x.origin.z))))]:
				mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mm.visibility_range_end = 110.0
		else:
			_multi(stalk, _straw, gold)
			_multi(stalk, _char, black)
		_fire(burn_c + Vector3(burn_r * 0.4, 0.3, 0), Vector3(2.5, 0.3, 1.2), 1.8, 10.0)
		_fire(burn_c + Vector3(-burn_r * 0.3, 0.3, burn_r * 0.5), Vector3(1.8, 0.3, 1.0), 1.4, 8.0)


func _build_exit() -> void:
	# Signpost at the north road, and a stream of golden motes to guide the hero once the farm is safe
	var p := Vector3(3.2, 0, EXIT_Z + 3.0)
	Models.part(self, Models.cyl(0.1, 0.12, 2.6), _wood_dark, p + Vector3(0, 1.3, 0))
	Models.part(self, Models.box(1.8, 0.4, 0.08), _wood, p + Vector3(-0.7, 2.2, 0), Vector3(0, 0, 0.05))
	var sign := Label3D.new()
	sign.text = "Emberfall Outpost  ↑"
	sign.font_size = 40
	sign.pixel_size = 0.006
	sign.modulate = Color(0.95, 0.85, 0.6)
	sign.outline_size = 8
	sign.position = p + Vector3(-0.7, 2.75, 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	add_child(sign)
	var motes := Vfx.emitter({"amount": 40, "lifetime": 2.2, "one_shot": false, "vmin": 0.6, "vmax": 1.6,
		"direction": Vector3.UP, "spread": 25.0, "box": Vector3(3.0, 0.2, 2.0), "size": 0.25, "tex": "star",
		"colors": [Color(1, 0.9, 0.6, 0), Color(1, 0.85, 0.5, 0.9), Color(1, 0.7, 0.3, 0)]})
	motes.position = Vector3(0, 0.2, EXIT_Z - 1.0)
	motes.visible = false
	add_child(motes)
	var l := _light(Vector3(0, 2.0, EXIT_Z - 1.0), Color(1, 0.8, 0.45), 9.0, 1.6)
	l.visible = false
	_exit_fx = [motes, l]
