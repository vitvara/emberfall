class_name HubWorld
extends RaidWorld
## The Outpost: a fortified war camp on a volcanic plateau where heroes gather before a raid.
## The raid portal (a carved stone gate around a fire-and-void vortex) stands in the middle of the
## camp; walking through it starts the fight against Vyrathax.
##
## The player is an ordinary Unit driven by a HubController, so movement, jumping, the camera and
## the hero animation are exactly the ones used in the raid. The Outpost is a RaidWorld without a
## dragon: skills, projectiles, ground zones, auras and damage numbers all work, which the training
## dummies in the yard east of the portal use. Combat here is local to each player's game.
##
## Online, everyone logged in to the realm and not fighting walks the same Outpost: positions go to
## the realm 20/s and come back as a hub snapshot. Walking through the portal opens the War Party
## window (create or join a party; the leader starts the raid) and the vortex sets the hero back down
## in front of the gate.

signal portal_entered
signal leave_requested
signal player_changed  # the hero was swapped for another class (the HUD rebuilds its action bar)

const ORIGIN := Vector3(0, 0, -900)  # far from the raid arena so the two maps never overlap
const WALK_RADIUS := 40.0
const WALL_RADIUS := 41.8
const SPAWN := Vector3(0, 0, 28)
const GATE_R := 4.2          # inner radius of the portal arch
const GATE_CY := 5.0         # height of the arch's centre
const GATE_HALF := 3.3       # half-width of the walk-through opening
const PROMPT_DIST := 14.0
const YARD := Vector3(30, 0, 6)       # training dummies
const YARD_DIST := 24.0               # the training HUD shows this close to the yard
const DUMMY_RESET := 6.0              # seconds without a hit before a dummy's DPS count resets
const BUBBLE_TIME := 6.0

var controller: HubController
var dummies: Array = []      # [{unit, dmg, t0, last}]
var _combat_t := 0.0
var _hint: Label

var _blockers: Array = []    # [Vector2 a, Vector2 b, radius]: capsules on the ground plane
var _entering := false
var _armed_t := 0.6
var _prev_z := SPAWN.z
var _t := 0.0
var _portal_lights: Array = []
var _vortex_mats: Array = []
var _prompt: Label
var _fade: ColorRect

# Online
var online := false
var ui_blocked := false      # main: a menu is open over the Outpost
var remotes := {}            # peer -> {unit, pos, rot}
var _side := 1.0             # which side of the gate the hero came from
var _send_t := 0.0
var _hub_ms := 0
var _hub_dt := Net.HUB_RATE   # measured (smoothed) time between hub snapshots
var _sent_pos := Vector3.INF
var _sent_rot := 0.0
var _idle_send := 0.0
var _sub: Label
var _party_box: VBoxContainer
var _toast: Label
var _toast_t := 0.0
var chat_log: RichTextLabel
var chat_input: LineEdit

var _rng := RandomNumberGenerator.new()
var _wood: StandardMaterial3D
var _wood_dark: StandardMaterial3D
var _iron: StandardMaterial3D
var _gold: StandardMaterial3D
var _rune: StandardMaterial3D
var _carved: StandardMaterial3D


func setup(class_id: String, is_online := false, display_name := "You") -> void:
	online = is_online
	position = ORIGIN
	started = true      # no countdown in the Outpost
	countdown = 0.0
	_rng.seed = 1337
	_wood = Models.mat(Color(0.33, 0.21, 0.13), 0.0, 0.95)
	_wood_dark = Models.mat(Color(0.19, 0.12, 0.08), 0.0, 1.0)
	_iron = Models.mat(Color(0.2, 0.2, 0.22), 0.0, 0.5)
	_gold = Models.mat(Color(0.72, 0.53, 0.22), 0.0, 0.4)
	_rune = Models.mat(Color(1.0, 0.38, 0.08), 2.2)
	_carved = Models.mat(Color(0.36, 0.31, 0.29), 0.0, 0.85)
	_build_ground()
	_build_portal()
	_build_plaza()
	_build_palisade()
	_build_camp()
	_build_npcs()
	_build_ui()
	player = Unit.new()
	player.world = self
	player.is_player = true
	add_child(player)
	player.setup_class(class_id, display_name)
	player.position = SPAWN
	player.rotation.y = 0.0
	player.net_id = 1
	units.append(player)
	by_id[1] = player
	controller = HubController.new()
	add_child(controller)
	controller.setup(self, player, false)
	controller.dist = 11.0
	controller.pitch = 0.32
	controller.leave_requested.connect(func():
		if not _entering:
			leave_requested.emit())
	if online:
		Net.hub_snapshot_received.connect(apply_remote)
		Net.notice_received.connect(show_notice)
		Net.lobby_changed.connect(_on_lobby)
		Net.chat_received.connect(_on_chat)
		_on_lobby()


## Swap the hero model (the realm says our class changed), keeping where we stand.
func set_player_class(cid: String) -> void:
	if player == null or player.class_id == cid:
		return
	var old := player
	var np := Unit.new()
	np.world = self
	np.is_player = true
	add_child(np)
	np.setup_class(cid, old.unit_name)
	np.position = old.position
	np.rotation = old.rotation
	np.net_id = 1
	units.erase(old)
	units.append(np)
	by_id[1] = np
	for d in dummies:
		(d["unit"] as Unit).damage_by.erase(old)
		(d["unit"] as Unit).threat.erase(old)
	old.queue_free()
	player = np
	controller.unit = np
	np.brain = controller
	player_changed.emit()
	Vfx.burst(self, np.position + Vector3(0, 1.2, 0), {"amount": 26, "lifetime": 0.6, "vmin": 1.0, "vmax": 3.0,
		"size": 0.3, "colors": [Color(1, 0.85, 0.5, 1), Color(np.color, 0.8), Color(np.color, 0)]})


# ------------------------------------------------------------------ RaidWorld stand-ins

## The walkable extent of the map, shared with the realm (which has no Outpost scene and only checks
## this). Growing the world into open country = widen this and build the new ground; nothing else
## in the netcode assumes the camp's size.
static func walk_bounds(p: Vector3) -> Vector3:
	var flat := Vector2(p.x, p.z).limit_length(WALK_RADIUS)
	return Vector3(flat.x, clampf(p.y, 0.0, 6.0), flat.y)


func clamp_to_arena(p: Vector3) -> Vector3:
	var y := p.y
	var b0 := walk_bounds(p)
	var flat := Vector2(b0.x, b0.z)
	for b in _blockers:
		var a: Vector2 = b[0]
		var ab: Vector2 = b[1] - a
		var t := 0.0
		if ab.length_squared() > 0.0001:
			t = clampf((flat - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var c := a + ab * t
		var r: float = b[2] + 0.45
		var d := flat - c
		if d.length() < r:
			flat = c + (d.normalized() if d.length() > 0.001 else Vector2.RIGHT) * r
	return Vector3(flat.x, y, flat.y)


func party_all() -> Array:
	return [player]


## No dragon here: fights never "end", and a hit only puts the hero in a fighting stance for a while.
func start_combat() -> void:
	_combat_t = DUMMY_RESET
	combat_active = true


func _check_end() -> void:
	pass


func _block(x: float, z: float, r: float) -> void:
	_blockers.append([Vector2(x, z), Vector2(x, z), r])


func _block_line(a: Vector3, b: Vector3, r: float) -> void:
	_blockers.append([Vector2(a.x, a.z), Vector2(b.x, b.z), r])


# ------------------------------------------------------------------ loop

func _process(delta: float) -> void:
	if player == null:
		return
	_t += delta
	var d := minf(delta, 0.1)
	controller.blocked = _entering or ui_blocked
	tick(d)  # RaidWorld loop: the hero (via its controller), dummies, auras, projectiles, ground zones
	_tick_dummies(d)
	if online:
		_online_tick(d)
	for i in _portal_lights.size():
		var l: OmniLight3D = _portal_lights[i]
		l.light_energy = l.get_meta("base") * (1.0 + 0.18 * sin(_t * (2.3 + i * 1.7)) + 0.08 * sin(_t * 7.1 + i))
	_armed_t -= d
	var p := player.position
	var dist := Vector2(p.x, p.z).length()
	if _prompt:
		var a := clampf((PROMPT_DIST - dist) / 4.0, 0.0, 1.0) if not _entering else 0.0
		_prompt.modulate.a = lerpf(_prompt.modulate.a, a, clampf(d * 6.0, 0.0, 1.0))
	# Crossing the gate plane inside the opening sends the hero through.
	var crossed := signf(p.z) != signf(_prev_z) or absf(p.z) < 0.5
	if not _entering and _armed_t <= 0.0 and crossed and absf(p.x) < GATE_HALF and p.y < 3.0:
		_enter_portal()
	_prev_z = p.z


func _enter_portal() -> void:
	if online:
		_touch_portal()
		return
	_entering = true
	controller.blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var core := Vector3(0, GATE_CY - 0.4, 0)
	Vfx.burst(self, core, {"amount": 60, "lifetime": 0.9, "vmin": 2.0, "vmax": 7.0, "size": 0.5, "streak": true,
		"colors": [Color(1, 0.8, 0.5, 1), Color(0.8, 0.3, 1.0, 0.9), Color(0.3, 0.05, 0.5, 0)]})
	for l in _portal_lights:
		var tl := create_tween()
		tl.tween_property(l, "light_energy", float(l.get_meta("base")) * 3.0, 0.5)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(player, "position", Vector3(0, 1.6, 0), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(player, "scale", Vector3.ONE * 0.15, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(player, "rotation:y", player.rotation.y + TAU, 0.7)
	tw.tween_property(_fade, "color:a", 1.0, 0.85)
	tw.chain().tween_callback(func(): portal_entered.emit())


# ------------------------------------------------------------------ training dummies

func _tick_dummies(d: float) -> void:
	_combat_t -= d
	if _combat_t <= 0.0:
		combat_active = false
	var now := Time.get_ticks_msec() / 1000.0
	for e in dummies:
		var u: Unit = e["unit"]
		if u.hp < u.max_hp * 0.5 or not u.alive:
			u.alive = true
			u.hp = u.max_hp  # straw is cheap: it never breaks
		var idle := now - float(e["last"]) > DUMMY_RESET
		if idle and float(e["dmg"]) > 0.0:
			e["dmg"] = 0.0
			u.hp = u.max_hp
			u.auras.clear()
			u.damage_by.clear()
		var txt := "Training Dummy"
		if float(e["dmg"]) > 0.0:
			var secs := maxf(now - float(e["t0"]), 1.0)
			txt += "\n%s DPS" % _num(float(e["dmg"]) / secs)
		u.nameplate.text = txt
	# The training HUD (action bar, frames) only shows near the yard
	var near := player.position.distance_to(YARD) < YARD_DIST
	if not near and player.target != null and player.target in units:
		player.target = null
	if _hint:
		_hint.visible = not near
	training_near = near


var training_near := false  # main shows the training HUD while this is true


## RaidWorld hook: a hit on a dummy feeds its DPS readout.
func on_damage(target: Unit, source: Unit, amount: float, absorbed: float, crit: bool, _label: String,
		school := "physical") -> void:
	super.on_damage(target, source, amount, absorbed, crit, _label, school)
	for e in dummies:
		if e["unit"] == target:
			var now := Time.get_ticks_msec() / 1000.0
			if float(e["dmg"]) <= 0.0:
				e["t0"] = now
			e["dmg"] = float(e["dmg"]) + amount + absorbed
			e["last"] = now
			start_combat()


static func _num(v: float) -> String:
	if v >= 10000.0:
		return "%.1fk" % (v / 1000.0)
	return str(int(v))


# ------------------------------------------------------------------ online

func _online_tick(d: float) -> void:
	# Our position to the realm: 10/s while moving, once a second standing still
	_send_t -= d
	_idle_send -= d
	if _send_t <= 0.0:
		_send_t = maxf(_send_t + Net.HUB_RATE, 0.0)
		var p := player.position
		if p.distance_to(_sent_pos) > 0.03 or absf(angle_difference(player.rotation.y, _sent_rot)) > 0.02 or _idle_send <= 0.0:
			_sent_pos = p
			_sent_rot = player.rotation.y
			_idle_send = 1.0
			Net.send_hub_pos(p, player.rotation.y)
	# Other heroes walk at a steady pace toward their last reported spot, arriving as the next
	# report is due (HeroRig sees the motion and plays the walk cycle)
	for peer in remotes:
		var r: Dictionary = remotes[peer]
		var u: Unit = r["unit"]
		var to: Vector3 = r["pos"]
		r["t"] = minf(1.0, float(r["t"]) + d / _hub_dt)
		var from: Vector3 = r["from"]
		if from.distance_to(to) > 8.0:
			u.position = to
		else:
			u.position = from.lerp(to, float(r["t"]))
		u.rotation.y = lerp_angle(float(r["rot_from"]), float(r["rot"]), float(r["t"]))
		u.grounded = u.position.y < 0.05
		var bubble: Label3D = r["bubble"]
		if bubble.visible:
			r["bubble_t"] = float(r["bubble_t"]) - d
			if float(r["bubble_t"]) <= 0.0:
				bubble.visible = false
	if _toast_t > 0.0:
		_toast_t -= d
		_toast.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0)


## The realm's hub snapshot: everyone walking the Outpost (we skip ourselves).
func apply_remote(ids: PackedInt32Array, data: PackedFloat32Array) -> void:
	var me := Net.my_id()
	var seen := {}
	var now := Time.get_ticks_msec()
	if _hub_ms > 0:
		_hub_dt = lerpf(_hub_dt, clampf((now - _hub_ms) / 1000.0, 0.02, 0.3), 0.1)
	_hub_ms = now
	for i in ids.size():
		var peer := ids[i]
		if peer == me or data.size() < i * 4 + 4:
			continue
		seen[peer] = true
		var cid := Net.avatar_class(peer)
		if cid == "":
			cid = "warden"
		var pos := Vector3(data[i * 4], data[i * 4 + 1], data[i * 4 + 2])
		var r: Dictionary = remotes.get(peer, {})
		if not r.is_empty() and (r["unit"] as Unit).class_id != cid:
			var old: Unit = r["unit"]
			pos = old.position
			old.queue_free()
			remotes.erase(peer)
			r = {}
		if r.is_empty():
			r = {"unit": _make_remote(peer, cid, pos), "bubble_t": 0.0}
			r["bubble"] = r["unit"].get_meta("bubble")
			remotes[peer] = r
		var u: Unit = r["unit"]
		r["from"] = u.position
		r["rot_from"] = u.rotation.y
		r["t"] = 0.0
		r["pos"] = Vector3(data[i * 4], data[i * 4 + 1], data[i * 4 + 2])
		r["rot"] = data[i * 4 + 3]
	for peer in remotes.keys():
		if not seen.has(peer):
			var u: Unit = remotes[peer]["unit"]
			if u.position.distance_to(player.position) < 40.0:
				Vfx.burst(self, u.position + Vector3(0, 1.0, 0), {"amount": 20, "lifetime": 0.5, "vmin": 1.0, "vmax": 2.5,
					"size": 0.3, "colors": [Color(0.8, 0.4, 1.0, 1), Color(0.3, 0.05, 0.5, 0)]})
			u.queue_free()
			remotes.erase(peer)
	_update_sub()


func _make_remote(peer: int, cid: String, pos: Vector3) -> Unit:
	var u := Unit.new()
	u.world = self
	add_child(u)
	u.setup_class(cid, Net.peer_name(peer))
	u.position = pos
	var bubble := Label3D.new()
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.fixed_size = true
	bubble.pixel_size = 0.0008
	bubble.font_size = 22
	bubble.outline_size = 8
	bubble.width = 360.0
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.modulate = Color(1, 0.95, 0.8)
	bubble.position = Vector3(0, 2.75, 0)
	bubble.visible = false
	u.add_child(bubble)
	u.set_meta("bubble", bubble)
	return u


func _touch_portal() -> void:
	_side = signf(_prev_z) if absf(_prev_z) > 0.01 else 1.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Vfx.burst(self, Vector3(player.position.x, 1.4, 0), {"amount": 40, "lifetime": 0.7, "vmin": 1.5, "vmax": 5.0,
		"size": 0.4, "streak": true, "colors": [Color(1, 0.8, 0.5, 1), Color(0.8, 0.3, 1.0, 0.9), Color(0.3, 0.05, 0.5, 0)]})
	for l in _portal_lights:
		var tl := create_tween()
		tl.tween_property(l, "light_energy", float(l.get_meta("base")) * 2.2, 0.25)
		tl.tween_property(l, "light_energy", float(l.get_meta("base")), 0.6)
	_bounce()
	portal_entered.emit()


## The vortex sets the hero back down in front of the gate, the way they came.
func _bounce() -> void:
	_armed_t = 1.2
	var to := Vector3(clampf(player.position.x, -GATE_HALF + 0.5, GATE_HALF - 0.5), 0.0, _side * 3.6)
	player.grounded = true
	player.vy = 0.0
	player.rotation.y = 0.0 if _side > 0.0 else PI
	var tw := create_tween()
	tw.tween_property(player, "position", to, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_prev_z = to.z


func show_notice(text: String) -> void:
	if _toast:
		_toast.text = text
		_toast.modulate.a = 1.0
		_toast_t = 5.0


func _on_lobby() -> void:
	if _party_box == null:
		return
	# Remote heroes pick up class changes on the next snapshot; refresh the party box now.
	for c in _party_box.get_children():
		c.queue_free()
	var party := Net.my_party()
	if party.is_empty():
		_party_box.add_child(UITheme.title("No War Party", 18))
		var l := Label.new()
		l.text = "Step through the portal to form one\nor join another hero's party."
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", UITheme.TEXT)
		_party_box.add_child(l)
	else:
		var leader := int(party["leader"])
		_party_box.add_child(UITheme.title("%s's Party%s" % [Net.peer_name(leader), "  ·  in battle" if party["in_raid"] else ""], 18))
		for sl in party["slots"]:
			var peer := int(sl["peer"])
			var cid: String = sl["class"]
			var filled := peer != 0 or bool(sl["bot"])
			var who := "open seat"
			var c := Color(0.6, 0.58, 0.52)
			if peer != 0:
				who = Net.peer_name(peer)
				if peer == leader:
					who += "  ♛"
				if peer == Net.my_id():
					who += "  (you)"
				c = Color(1, 0.95, 0.8)
			elif sl["bot"]:
				who = "Bot" if String(sl.get("away", "")) == "" else "%s (bot covering)" % sl["away"]
				c = Color(0.65, 0.8, 1)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var cl := Label.new()
			cl.text = GameData.CLASSES[cid]["name"] if filled and cid != "" else "—"
			cl.custom_minimum_size = Vector2(110, 0)
			cl.add_theme_font_size_override("font_size", 15)
			cl.add_theme_color_override("font_color", GameData.CLASSES[cid]["color"] if filled and cid != "" else c)
			row.add_child(cl)
			var wl := Label.new()
			wl.text = who
			wl.add_theme_font_size_override("font_size", 15)
			wl.add_theme_color_override("font_color", c)
			row.add_child(wl)
			_party_box.add_child(row)
	var hint := Label.new()
	hint.text = "Esc — war party window"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UITheme.GOLD_DIM)
	_party_box.add_child(hint)
	if _prompt:
		_prompt.text = _prompt_text()
	_update_sub()
	var my := Net.avatar_class(Net.my_id())
	if my != "":
		set_player_class(my)


func _prompt_text() -> String:
	if not online:
		return "The portal roars before you — step through to face Vyrathax, the Cinder Tyrant"
	if Net.can_rejoin():
		return "Your party still fights — step through the portal to rejoin the raid"
	if not Net.in_party():
		return "Step through the portal to form a war party or join one"
	if Net.my_party()["in_raid"]:
		return "Your party is battling Vyrathax"
	if Net.is_leader():
		return "Step through the portal to start the raid when your party is ready"
	return "Waiting for %s to start the raid" % Net.peer_name(int(Net.my_party()["leader"]))


func _update_sub() -> void:
	if _sub == null or not online:
		return
	var n := remotes.size() + 1
	_sub.text = "Realm %s  ·  %d %s nearby" % [Net.realm_address, n, "hero" if n == 1 else "heroes"]


func _on_chat(from: String, text: String, c: Color) -> void:
	_append_chat(from, text, c)
	if from == "":
		return
	for peer in remotes:
		var u: Unit = remotes[peer]["unit"]
		if u.unit_name == from:
			var b: Label3D = remotes[peer]["bubble"]
			b.text = text
			b.visible = true
			remotes[peer]["bubble_t"] = BUBBLE_TIME


func _append_chat(from: String, text: String, c: Color) -> void:
	if chat_log == null:
		return
	if from == "":
		chat_log.append_text("[color=#%s][i]%s[/i][/color]\n" % [c.to_html(false), text])
	else:
		chat_log.append_text("[color=#e8c27a][%s][/color] [color=#%s]%s[/color]\n" % [from, c.to_html(false), text])


func _unhandled_key_input(event: InputEvent) -> void:
	if not online or chat_input == null or ui_blocked:
		return
	var k := event as InputEventKey
	if k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and not chat_input.has_focus():
		chat_input.grab_focus()
		get_viewport().set_input_as_handled()


func _build_online_ui(root: Control) -> void:
	# Chat, bottom-left
	var chat := PanelContainer.new()
	chat.add_theme_stylebox_override("panel", UITheme.slot())
	chat.anchor_top = 1.0
	chat.anchor_bottom = 1.0
	chat.offset_left = 16
	chat.offset_right = 416
	chat.offset_top = -330
	chat.offset_bottom = -140
	chat.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(chat)
	var cv := VBoxContainer.new()
	chat.add_child(cv)
	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	chat_log.custom_minimum_size = Vector2(380, 130)
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.add_theme_font_size_override("normal_font_size", 15)
	chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(chat_log)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Press Enter to chat"
	chat_input.text_submitted.connect(func(t: String):
		if t.strip_edges() != "":
			Net.request("chat", [t])
		chat_input.text = ""
		chat_input.release_focus())
	chat_input.gui_input.connect(func(e: InputEvent):
		if e is InputEventKey and e.pressed and (e as InputEventKey).keycode == KEY_ESCAPE:
			chat_input.release_focus()
			chat_input.accept_event())
	cv.add_child(chat_input)
	for line in Net.chat_history:
		_append_chat(line[0], line[1], line[2])
	# War party, top-right
	var pp := PanelContainer.new()
	pp.add_theme_stylebox_override("panel", UITheme.slot())
	pp.anchor_left = 1.0
	pp.anchor_right = 1.0
	pp.offset_left = -330
	pp.offset_right = -16
	pp.offset_top = 16
	pp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pp)
	_party_box = VBoxContainer.new()
	_party_box.add_theme_constant_override("separation", 2)
	pp.add_child(_party_box)
	# Realm notices, centre
	_toast = UITheme.title("", 22, Color(1, 0.85, 0.55))
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 60
	_toast.offset_left = -420
	_toast.offset_right = 420
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.modulate.a = 0.0
	root.add_child(_toast)


# ------------------------------------------------------------------ ground & sky

func _build_ground() -> void:
	var stone := EnvKit.stone_material()
	# Plateau body; its top is tiled so every patch only receives the lights near it
	# (the mobile renderer caps lights per mesh).
	var body := Models.cyl(WALL_RADIUS + 3.0, WALL_RADIUS + 7.0, 4.0)
	body.radial_segments = 72
	Models.part(self, body, stone, Vector3(0, -2.02, 0))
	var tile := 10.0
	var pm := PlaneMesh.new()
	pm.size = Vector2(tile, tile)
	for ix in range(-5, 5):
		for iz in range(-5, 5):
			var c := Vector3((ix + 0.5) * tile, 0.0, (iz + 0.5) * tile)
			if Vector2(absf(c.x) + tile * 0.5, absf(c.z) + tile * 0.5).length() > WALL_RADIUS + 3.0:
				continue
			Models.part(self, pm, stone, c)
	# Cliff boulders around the plateau edge and out in the lava
	EnvKit.rocks(self, _rng, 46, WALL_RADIUS + 3.0, WALL_RADIUS + 18.0, 1.5, 5.5)
	EnvKit.rocks(self, _rng, 20, WALL_RADIUS + 20.0, 110.0, 2.0, 7.0)
	EnvKit.lava_sea(self, 900.0)
	EnvKit.volcanoes(self, _rng, 7, 150.0, 220.0)
	Vfx.embers_ambient(self, 48.0)
	# Warm under-light from the lava around the cliffs
	for i in 6:
		var a := TAU * i / 6.0 + 0.2
		_light(Vector3(cos(a), 0, sin(a)) * (WALL_RADIUS + 6.0) + Vector3(0, 0.5, 0), Color(1.0, 0.34, 0.08), 20.0, 2.0)


func _light(p: Vector3, c: Color, rng: float, energy: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = c
	l.omni_range = rng
	l.light_energy = energy
	add_child(l)
	return l


# ------------------------------------------------------------------ the raid portal

func _build_portal() -> void:
	var gate := Node3D.new()
	gate.name = "RaidPortal"
	add_child(gate)
	var outer := GATE_R + 1.1
	# Pillars: stacked carved blocks up to the arch springline, on heavy plinths
	for sx in [-1.0, 1.0]:
		var x: float = sx * (GATE_R + 0.55)
		Models.part(gate, Models.box(2.4, 0.9, 2.4), _carved, Vector3(x, 0.45, 0))
		Models.part(gate, Models.box(2.0, 0.35, 2.0), EnvKit.stone_material(), Vector3(x, 1.05, 0))
		for k in 3:
			var h := 1.22 + k * 1.26
			Models.part(gate, Models.box(1.1, 1.18, 1.4), _carved, Vector3(x, h + 0.59, 0))
			for sz in [-1.0, 1.0]:
				Models.part(gate, Models.box(0.36, 0.5, 0.05), _rune, Vector3(x, h + 0.6, sz * 0.71))
		_block(x, 0.0, 1.35)
	# Arch of wedge stones (voussoirs) over the top
	var n := 11
	for i in n:
		var a := PI * (i + 0.5) / n
		var c := Vector3(cos(a) * (GATE_R + 0.55), GATE_CY + sin(a) * (GATE_R + 0.55), 0)
		var arc := PI * (GATE_R + 0.55) / n
		var key := i == 5  # keystone (n = 11)
		var depth := 1.7 if key else 1.4
		var radial := 1.6 if key else 1.1
		Models.part(gate, Models.box(arc * 0.93, radial, depth), _carved, c, Vector3(0, 0, a - PI / 2.0))
		for sz in [-1.0, 1.0]:
			var glyph := Models.box(arc * 0.16, radial * 0.5, 0.05)
			Models.part(gate, glyph, _rune, c + Vector3(0, 0, sz * (depth * 0.5 + 0.01)), Vector3(0, 0, a - PI / 2.0))
		# Jagged obsidian spikes jutting out of every other stone
		if i % 2 == 0 and not key:
			var sp := Models.cyl(0.0, 0.32, 1.5)
			sp.radial_segments = 5
			var dir := Vector3(cos(a), sin(a), 0)
			Models.part(gate, sp, Models.mat(Color(0.07, 0.05, 0.06), 0.0, 0.3), c + dir * 1.2, Vector3(0, 0, a - PI / 2.0))
	# Keystone horns: the gate is crowned like a dragon's brow
	for sx in [-1.0, 1.0]:
		var horn := Models.cyl(0.0, 0.42, 2.8)
		horn.radial_segments = 6
		Models.part(gate, horn, Models.mat(Color(0.12, 0.08, 0.07), 0.0, 0.5),
			Vector3(sx * 1.0, GATE_CY + outer + 1.0, 0), Vector3(0, 0, -sx * 0.55))
	Models.part(gate, Models.box(0.6, 0.6, 0.06), Models.mat(Color(1.0, 0.55, 0.15), 5.0),
		Vector3(0, GATE_CY + GATE_R + 0.55, 0.86), Vector3(0, 0, PI / 4.0))

	# The vortex: a dark void with the spiral drawn on both faces
	var shape := Vector2(GATE_R * 2.0, GATE_CY + GATE_R)
	var void_q := QuadMesh.new()
	void_q.size = shape
	var void_m := StandardMaterial3D.new()
	void_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	void_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	void_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	void_m.albedo_texture = Vfx.soft_tex()
	void_m.albedo_color = Color(0.03, 0.0, 0.05, 0.97)
	var vmi := Models.part(gate, void_q, void_m, Vector3(0, shape.y * 0.5, 0))
	vmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var vq := QuadMesh.new()
	vq.size = shape
	for k in 2:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/portal.gdshader")
		m.set_shader_parameter("noise", Vfx.noise_tex())
		m.set_shader_parameter("spin", 0.35 if k == 0 else -0.35)
		_vortex_mats.append(m)
		var mi := Models.part(gate, vq, m, Vector3(0, shape.y * 0.5, 0.07 if k == 0 else -0.07),
			Vector3(0, PI * k, 0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Embers and violet motes drawn into the eye
	var suck := Vfx.emitter({"amount": 90, "lifetime": 1.6, "one_shot": false, "vmin": 0.2, "vmax": 0.8,
		"ring": [GATE_R + 0.6, GATE_R - 0.4], "radial": -4.5, "size": 0.22, "streak": true, "stretch": 4.0,
		"colors": [Color(1, 0.6, 0.2, 0), Color(1, 0.55, 0.2, 1), Color(0.7, 0.25, 1.0, 0.9), Color(0.3, 0.05, 0.6, 0)]})
	suck.position = Vector3(0, GATE_CY - 0.3, 0)
	suck.rotation.x = PI / 2.0
	gate.add_child(suck)
	# Flames licking up the inside of each pillar
	for sx in [-1.0, 1.0]:
		var lick := Vfx.emitter({"amount": 26, "lifetime": 0.8, "one_shot": false, "vmin": 1.2, "vmax": 2.6,
			"direction": Vector3.UP, "spread": 8.0, "box": Vector3(0.15, 2.0, 0.4), "size": 0.7, "shader": "flame_solid",
			"tall": 1.8, "colors": [Color(1, 0.85, 0.5, 1), Color(1, 0.45, 0.1, 0.9), Color(0.6, 0.12, 0.03, 0.5),
			Color(0.2, 0.05, 0.05, 0)]})
		lick.position = Vector3(sx * (GATE_R - 0.15), 2.4, 0)
		gate.add_child(lick)
	# Dark smoke rolling out across the plaza floor
	var spill := Vfx.emitter({"amount": 18, "lifetime": 3.0, "one_shot": false, "vmin": 0.6, "vmax": 1.4,
		"direction": Vector3(0, 0.1, 1), "spread": 180.0, "box": Vector3(GATE_R * 0.8, 0.1, 0.2), "size": 2.6,
		"shader": "smoke", "grow": true, "colors": [Color(0.25, 0.08, 0.3, 0), Color(0.22, 0.07, 0.25, 0.45),
		Color(0.12, 0.04, 0.1, 0)]})
	spill.position = Vector3(0, 0.3, 0)
	gate.add_child(spill)
	# Light spilling out of the vortex on both sides
	for sz in [-1.0, 1.0]:
		var l := _light(Vector3(0, GATE_CY - 1.0, sz * 1.6), Color(0.75, 0.35, 1.0), 16.0, 2.4)
		l.set_meta("base", 2.4)
		_portal_lights.append(l)
	var warm := _light(Vector3(0, 1.0, 0), Color(1.0, 0.45, 0.12), 12.0, 1.8)
	warm.set_meta("base", 1.8)
	_portal_lights.append(warm)


# ------------------------------------------------------------------ plaza around the portal

func _build_plaza() -> void:
	var floor_m := Models.mat(Color(0.16, 0.13, 0.13), 0.0, 0.6)
	var inlay := Models.mat(Color(0.62, 0.45, 0.2), 0.6, 0.4)
	var plaza := Models.cyl(12.0, 12.4, 0.12)
	plaza.radial_segments = 48
	Models.part(self, plaza, floor_m, Vector3(0, 0.0, 0))
	# Gold inlay border and eight spokes of flagstone
	for i in 32:
		var a := TAU * i / 32.0
		Models.part(self, Models.box(2.1, 0.03, 0.22), inlay, Vector3(cos(a) * 11.4, 0.07, sin(a) * 11.4),
			Vector3(0, -a + PI / 2.0, 0))
	var slab := Models.mat(Color(0.27, 0.24, 0.22), 0.0, 0.85)
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		for k in 4:
			var r := 6.2 + k * 1.3
			Models.part(self, Models.box(1.15, 0.05, 1.0 + k * 0.15), slab, Vector3(cos(a) * r, 0.07, sin(a) * r),
				Vector3(0, -a, 0))
	# Four obelisks with braziers frame the gate
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var p := Vector3(cos(a), 0, sin(a)) * 9.0
		Models.part(self, Models.box(2.0, 0.6, 2.0), _carved, p + Vector3(0, 0.3, 0), Vector3(0, a, 0))
		var ob := Models.cyl(0.45, 0.8, 5.0)
		ob.radial_segments = 4
		Models.part(self, ob, _carved, p + Vector3(0, 3.1, 0), Vector3(0, a + PI / 4.0, 0))
		for k in 3:
			Models.part(self, Models.box(0.28, 0.4, 0.05), _rune, p + Vector3(0, 1.7 + k * 1.1, 0) +
				Vector3(cos(a), 0, sin(a)) * -(0.66 - k * 0.07), Vector3(0, -a + PI / 2.0, 0))
		EnvKit.brazier(self, p + Vector3(0, 5.75, 0), 0.9, 15.0)
		_block(p.x, p.z, 1.3)
	# Flagstone road from the south gate to the plaza
	_road(Vector3(0, 0, 12.5), Vector3(0, 0, WALL_RADIUS), 2.6)
	_road(Vector3(-12.5, 0, 0), Vector3(-27.0, 0, 0), 2.2)
	_road(Vector3(12.5, 0, 0), Vector3(27.0, 0, 0), 2.2)
	_road(Vector3(0, 0, -12.5), Vector3(0, 0, -26.0), 2.2)


func _road(a: Vector3, b: Vector3, half_w: float) -> void:
	var slab_m := Models.mat(Color(0.3, 0.27, 0.25), 0.0, 0.85)
	var dir := (b - a).normalized()
	var side := Vector3(-dir.z, 0, dir.x)
	var yaw := atan2(dir.x, dir.z)
	var length := a.distance_to(b)
	var s := 0.0
	while s < length:
		var step := _rng.randf_range(0.9, 1.4)
		var across := -half_w
		while across < half_w:
			var w := _rng.randf_range(0.8, 1.5)
			w = minf(w, half_w - across)
			var p := a + dir * (s + step * 0.5) + side * (across + w * 0.5)
			var tint := _rng.randf_range(-0.04, 0.04)
			var m := slab_m if absf(tint) < 0.02 else Models.mat(Color(0.3 + tint, 0.27 + tint, 0.25 + tint), 0.0, 0.85)
			Models.part(self, Models.box(w - 0.1, 0.06, step - 0.1), m, p + Vector3(0, 0.03, 0),
				Vector3(0, yaw + _rng.randf_range(-0.04, 0.04), 0))
			across += w
		s += step


# ------------------------------------------------------------------ palisade wall

func _build_palisade() -> void:
	var stake := Models.cyl(0.24, 0.3, 3.2)
	stake.radial_segments = 6
	var tip := Models.cyl(0.0, 0.24, 0.7)
	tip.radial_segments = 6
	var stakes: Array = []
	var tips: Array = []
	var gate_a := PI / 2.0  # south, where the road comes in
	var gap := 0.11
	var count := int(TAU * WALL_RADIUS / 0.58)
	for i in count:
		var a := TAU * i / count
		if absf(wrapf(a - gate_a, -PI, PI)) < gap:
			continue
		var h := _rng.randf_range(2.6, 3.6)
		var p := Vector3(cos(a), 0, sin(a)) * (WALL_RADIUS + _rng.randf_range(-0.12, 0.12))
		var tilt := Basis(Vector3(-sin(a), 0, cos(a)), _rng.randf_range(-0.06, 0.12))
		var sc := Basis().scaled(Vector3(1, h / 3.2, 1))
		stakes.append(Transform3D(tilt * sc, p + tilt * Vector3(0, h * 0.5, 0)))
		tips.append(Transform3D(tilt, p + tilt * Vector3(0, h + 0.35, 0)))
	_multi(stake, _wood_dark, stakes)
	_multi(tip, _wood, tips)
	# Two cross-beams lashed along the inside of the wall
	var beam_m := _wood
	for k in 2:
		var segs := 72
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var mid := (a0 + a1) * 0.5
			if absf(wrapf(mid - gate_a, -PI, PI)) < gap + 0.03:
				continue
			var r := WALL_RADIUS - 0.35
			var p0 := Vector3(cos(a0), 0, sin(a0)) * r
			var p1 := Vector3(cos(a1), 0, sin(a1)) * r
			var seg_len := p0.distance_to(p1)
			Models.part(self, Models.box(seg_len + 0.1, 0.18, 0.18), beam_m, (p0 + p1) * 0.5 + Vector3(0, 0.9 + k * 1.2, 0),
				Vector3(0, -mid + PI / 2.0, 0))
	# Gatehouse towers either side of the road
	for sx in [-1.0, 1.0]:
		var a: float = gate_a + sx * (gap + 0.04)
		_tower(Vector3(cos(a), 0, sin(a)) * (WALL_RADIUS + 0.4))
	# Banners over the gate
	var lintel_y := 6.2
	Models.part(self, Models.box(9.5, 0.5, 0.5), _wood, Vector3(0, lintel_y, WALL_RADIUS + 0.4))
	for sx in [-1.0, 1.0]:
		_banner(Vector3(sx * 2.0, lintel_y - 0.25, WALL_RADIUS + 0.1), 0.0, 2.6)


func _tower(p: Vector3) -> void:
	var h := 7.5
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var off := Vector3(c.x * 1.3, 0, c.y * 1.3)
		Models.part(self, Models.cyl(0.22, 0.28, h), _wood_dark, p + off + Vector3(0, h * 0.5, 0))
	for y in [2.4, 4.6]:
		for k in 4:
			var yaw := PI / 2.0 * k
			var o := Vector3(sin(yaw), 0, cos(yaw)) * 1.3
			Models.part(self, Models.box(2.7, 0.14, 0.14), _wood, p + o + Vector3(0, y, 0), Vector3(0, yaw, 0.0))
	Models.part(self, Models.box(3.6, 0.3, 3.6), _wood, p + Vector3(0, h, 0))
	for k in 4:
		var yaw := PI / 2.0 * k
		var o := Vector3(sin(yaw), 0, cos(yaw)) * 1.7
		Models.part(self, Models.box(3.6, 0.9, 0.15), _wood_dark, p + o + Vector3(0, h + 0.6, 0), Vector3(0, yaw, 0))
	var roof := Models.cyl(0.05, 2.8, 2.0)
	roof.radial_segments = 4
	Models.part(self, roof, Models.mat(Color(0.35, 0.09, 0.07), 0.0, 0.9), p + Vector3(0, h + 2.6, 0), Vector3(0, PI / 4.0, 0))
	for c in [Vector2(-1, -1), Vector2(1, 1)]:
		Models.part(self, Models.cyl(0.1, 0.1, 1.6), _wood_dark, p + Vector3(c.x * 1.3, h + 1.1, c.y * 1.3))
	EnvKit.brazier(self, p + Vector3(0, h + 0.45, 0), 0.6, 12.0)
	_block(p.x, p.z, 2.0)


func _banner(top: Vector3, yaw: float, length: float) -> void:
	var cloth := Models.mat(Color(0.48, 0.07, 0.05), 0.0, 0.9)
	var root := Node3D.new()
	root.position = top
	root.rotation.y = yaw
	add_child(root)
	Models.part(root, Models.cyl(0.07, 0.07, 1.5), _gold, Vector3.ZERO, Vector3(0, 0, PI / 2.0))
	Models.part(root, Models.box(1.3, length, 0.04), cloth, Vector3(0, -length * 0.5, 0))
	# Notched tail and a gold flame sigil
	for sx in [-1.0, 1.0]:
		var tail := Models.box(0.65, 0.65, 0.04)
		Models.part(root, tail, cloth, Vector3(sx * 0.33, -length, 0), Vector3(0, 0, PI / 4.0))
	var sigil := Models.cyl(0.0, 0.26, 0.6)
	sigil.radial_segments = 3
	for sz in [-1.0, 1.0]:
		Models.part(root, sigil, Models.mat(Color(0.95, 0.7, 0.3), 0.8), Vector3(0, -length * 0.42, sz * 0.03),
			Vector3(PI / 2.0 * sz, 0, 0), Vector3(1, 1, 0.15))


func _multi(mesh: Mesh, m: Material, xforms: Array) -> void:
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


# ------------------------------------------------------------------ camp

func _build_camp() -> void:
	# Tents along the west and east halves, leaving the roads clear
	var tents := [[2.55, 29.0, 0], [2.95, 31.0, 1], [3.55, 30.0, 0], [3.85, 32.0, 1], [0.6, 31.0, 1],
		[0.95, 29.5, 0], [5.95, 31.0, 0], [2.2, 21.0, 1]]
	for t in tents:
		var a: float = t[0]
		var p := Vector3(cos(a), 0, sin(a)) * float(t[1])
		_tent(p, atan2(p.x, p.z), t[2] == 1)  # doorway faces the portal
	# Command tent behind the portal (north)
	_tent(Vector3(0, 0, -31), PI, false, 1.7)
	_table(Vector3(0, 0, -22.5))
	_forge(Vector3(-31, 0, -4))
	_dummies(Vector3(30, 0, 6))
	# Supply heaps
	for c in [Vector3(-22, 0, 14), Vector3(21, 0, -15), Vector3(-17, 0, -22), Vector3(9, 0, 26), Vector3(-8, 0, 27)]:
		_supplies(c)
	# Banners lining the south road
	for z in [16.0, 24.0, 32.0]:
		for sx in [-1.0, 1.0]:
			var bp := Vector3(sx * 3.6, 0, z)
			Models.part(self, Models.cyl(0.11, 0.14, 5.2), _wood_dark, bp + Vector3(0, 2.6, 0))
			_banner(bp + Vector3(0, 5.0, 0.08), 0.0, 2.2)
			_block(bp.x, bp.z, 0.35)
	# Iron braziers on tripods around the camp
	for p in [Vector3(-9, 0, 15), Vector3(14, 0, 16), Vector3(-25, 0, -12), Vector3(18, 0, -24),
			Vector3(22, 0, 8), Vector3(-6, 0, -20)]:
		for k in 3:
			var ka := TAU * k / 3.0
			Models.part(self, Models.cyl(0.06, 0.06, 1.6), _iron, p + Vector3(cos(ka) * 0.35, 0.75, sin(ka) * 0.35),
				Vector3(sin(ka) * 0.25, 0, -cos(ka) * 0.25))
		EnvKit.brazier(self, p + Vector3(0, 1.45, 0), 0.55, 11.0)
		_block(p.x, p.z, 0.6)


func _tent(p: Vector3, yaw: float, red: bool, s := 1.0) -> void:
	var cloth := Models.mat(Color(0.46, 0.1, 0.07) if red else Color(0.5, 0.4, 0.28), 0.0, 0.95)
	var root := Node3D.new()
	root.position = p
	root.rotation.y = yaw
	add_child(root)
	var w := 3.2 * s
	var walls := Models.cyl(w, w * 1.04, 1.1 * s)
	walls.radial_segments = 4
	Models.part(root, walls, cloth, Vector3(0, 0.55 * s, 0), Vector3(0, PI / 4.0, 0))
	var roof := Models.cyl(0.05, w * 1.12, 2.4 * s)
	roof.radial_segments = 4
	Models.part(root, roof, cloth, Vector3(0, 2.3 * s, 0), Vector3(0, PI / 4.0, 0))
	Models.part(root, Models.cyl(0.08, 0.08, 4.2 * s), _wood_dark, Vector3(0, 2.1 * s, 0))
	Models.part(root, Models.cyl(0.0, 0.14, 0.4), _gold, Vector3(0, 4.3 * s, 0))
	# Dark doorway facing the camp centre, with tied-back flaps
	var door_z := -w * 0.72
	Models.part(root, Models.box(1.2 * s, 1.5 * s, 0.05), Models.mat(Color(0.04, 0.02, 0.02)), Vector3(0, 0.75 * s, door_z - 0.02))
	for sx in [-1.0, 1.0]:
		Models.part(root, Models.box(0.35 * s, 1.6 * s, 0.06), cloth, Vector3(sx * 0.72 * s, 0.85 * s, door_z - 0.05),
			Vector3(0, 0, sx * 0.12))
	# Guy ropes and stakes
	for k in 4:
		var ka := PI / 2.0 * k + PI / 4.0
		var corner := Vector3(sin(ka), 0, cos(ka)) * w * 1.05
		var stake := corner * 1.45
		var mid := (corner + Vector3(0, 1.0 * s, 0) + stake) * 0.5
		var rope_len := (corner + Vector3(0, 1.0 * s, 0)).distance_to(stake)
		var dir := (stake - (corner + Vector3(0, 1.0 * s, 0))).normalized()
		var rope := Models.part(root, Models.cyl(0.02, 0.02, rope_len), Models.mat(Color(0.6, 0.5, 0.35)), mid)
		rope.basis = Basis(Quaternion(Vector3.UP, dir))
		Models.part(root, Models.cyl(0.05, 0.05, 0.4), _wood_dark, stake + Vector3(0, 0.15, 0))
	_block(p.x, p.z, w * 0.92)


func _table(p: Vector3) -> void:
	Models.part(self, Models.box(3.6, 0.15, 2.2), _wood, p + Vector3(0, 1.0, 0))
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		Models.part(self, Models.box(0.15, 1.0, 0.15), _wood_dark, p + Vector3(c.x * 1.6, 0.5, c.y * 0.9))
	# A war map pinned with markers, the dragon's lair circled in red
	Models.part(self, Models.box(3.0, 0.02, 1.8), Models.mat(Color(0.78, 0.68, 0.48)), p + Vector3(0, 1.09, 0), Vector3(0, 0.06, 0))
	for i in 6:
		var mp := p + Vector3(_rng.randf_range(-1.3, 1.3), 1.18, _rng.randf_range(-0.7, 0.7))
		Models.part(self, Models.cyl(0.0, 0.06, 0.18), Models.mat(Color(0.2, 0.3, 0.7) if i % 2 == 0 else Color(0.8, 0.15, 0.1)), mp)
	Models.part(self, Models.box(0.5, 0.03, 0.35), Models.mat(Color(0.9, 0.2, 0.1), 1.2), p + Vector3(1.0, 1.11, -0.4))
	_block_line(p + Vector3(-1.6, 0, 0), p + Vector3(1.6, 0, 0), 1.1)


func _forge(p: Vector3) -> void:
	var brick := Models.mat(Color(0.24, 0.19, 0.17), 0.0, 0.95)
	# Furnace with a roaring mouth facing the plaza (east)
	Models.part(self, Models.box(3.6, 3.2, 3.6), brick, p + Vector3(0, 1.6, 0))
	Models.part(self, Models.box(4.0, 0.4, 4.0), brick, p + Vector3(0, 3.3, 0))
	Models.part(self, Models.cyl(0.8, 1.1, 4.5), brick, p + Vector3(-0.4, 5.6, 0))
	Models.part(self, Models.box(0.06, 1.3, 1.6), Models.mat(Color(1.0, 0.45, 0.1), 5.0), p + Vector3(1.81, 1.0, 0))
	var fire := Vfx.emitter({"amount": 28, "lifetime": 0.7, "one_shot": false, "vmin": 0.6, "vmax": 1.6,
		"direction": Vector3(0.4, 1, 0), "spread": 15.0, "box": Vector3(0.1, 0.2, 0.6), "size": 0.75, "shader": "flame_solid",
		"colors": [Color(1, 0.9, 0.55, 1), Color(1, 0.5, 0.12, 0.9), Color(0.5, 0.1, 0.03, 0.4), Color(0.1, 0.05, 0.05, 0)]})
	fire.position = p + Vector3(1.75, 0.55, 0)
	add_child(fire)
	var smoke := Vfx.emitter({"amount": 14, "lifetime": 4.0, "one_shot": false, "vmin": 1.2, "vmax": 2.2,
		"direction": Vector3.UP, "spread": 10.0, "sphere": 0.4, "size": 2.2, "shader": "smoke", "grow": true,
		"gravity": Vector3(0.6, 0.3, 0.2), "colors": [Color(0.2, 0.17, 0.16, 0), Color(0.18, 0.15, 0.14, 0.55),
		Color(0.1, 0.09, 0.09, 0)]})
	smoke.position = p + Vector3(-0.4, 8.0, 0)
	add_child(smoke)
	_light(p + Vector3(3.0, 1.5, 0), Color(1.0, 0.5, 0.15), 13.0, 2.6)
	_block(p.x, p.z, 2.6)
	# Anvil, quench trough and a weapon rack
	var anvil := p + Vector3(4.2, 0, 1.2)
	Models.part(self, Models.cyl(0.35, 0.45, 0.7), _wood_dark, anvil + Vector3(0, 0.35, 0))
	Models.part(self, Models.box(0.9, 0.3, 0.42), _iron, anvil + Vector3(0, 0.85, 0))
	var horn := Models.cyl(0.0, 0.16, 0.5)
	horn.radial_segments = 6
	Models.part(self, horn, _iron, anvil + Vector3(0.68, 0.88, 0), Vector3(0, 0, -PI / 2.0))
	Models.part(self, Models.box(0.12, 0.08, 0.6), Models.mat(Color(1.0, 0.5, 0.2), 2.5), anvil + Vector3(-0.1, 1.04, 0), Vector3(0, 0.4, 0))
	_block(anvil.x, anvil.z, 0.6)
	var trough := p + Vector3(3.4, 0, -2.6)
	Models.part(self, Models.box(2.0, 0.7, 0.9), _wood, trough + Vector3(0, 0.35, 0))
	Models.part(self, Models.box(1.8, 0.04, 0.7), Models.mat(Color(0.12, 0.2, 0.25), 0.0, 0.1), trough + Vector3(0, 0.66, 0))
	_block_line(trough + Vector3(-0.8, 0, 0), trough + Vector3(0.8, 0, 0), 0.5)
	var rack := p + Vector3(0.5, 0, 3.4)
	for sx in [-1.0, 1.0]:
		Models.part(self, Models.box(0.15, 1.8, 0.15), _wood_dark, rack + Vector3(sx * 1.2, 0.9, 0))
	Models.part(self, Models.box(2.6, 0.12, 0.15), _wood, rack + Vector3(0, 1.6, 0))
	for i in 5:
		var x := -0.9 + i * 0.45
		Models.part(self, Models.box(0.07, 1.4, 0.03), Models.mat(Color(0.7, 0.72, 0.78), 0.0, 0.3), rack + Vector3(x, 0.9, 0.1),
			Vector3(0, 0, 0.12))
		Models.part(self, Models.box(0.28, 0.05, 0.06), _gold, rack + Vector3(x - 0.07, 1.5, 0.1))
	_block_line(rack + Vector3(-1.2, 0, 0), rack + Vector3(1.2, 0, 0), 0.35)


func _dummies(p: Vector3) -> void:
	var straw := Models.mat(Color(0.7, 0.56, 0.3), 0.0, 1.0)
	var sack := Models.mat(Color(0.55, 0.45, 0.3), 0.0, 1.0)
	for i in 3:
		var d := p + Vector3(0, 0, (i - 1) * 3.2)
		# A real, targetable enemy with the dragon's armour, so the numbers match the raid
		var model := Node3D.new()
		Models.part(model, Models.cyl(0.1, 0.12, 2.4), _wood_dark, Vector3(0, 1.2, 0))
		Models.part(model, Models.box(1.5, 0.12, 0.12), _wood, Vector3(0, 1.75, 0), Vector3(0, PI / 2.0, 0))
		Models.part(model, Models.capsule(0.38, 1.1), straw, Vector3(0, 1.35, 0))
		Models.part(model, Models.box(0.42, 0.42, 0.42), sack, Vector3(0, 2.15, 0), Vector3(0.1, 0.3, 0.05))
		for k in 2:  # arrows stuck in the straw
			var ar := Models.cyl(0.015, 0.015, 0.8)
			Models.part(model, ar, _wood, Vector3(-0.5, 1.3 + k * 0.25, 0.1 - k * 0.2), Vector3(0.2, 0, PI / 2.0 + 0.2))
		var u := Unit.new()
		u.world = self
		u.net_id = 200 + i
		add_child(u)
		u.setup_mob("Training Dummy", 60000.0, float(GameData.BOSS["armor"]), 0.5, model, 2.9, 1.35)
		u.position = d
		u.rotation.y = -PI / 2.0  # face the plaza
		u.nameplate.modulate = Color(1, 0.85, 0.5)
		units.append(u)
		by_id[u.net_id] = u
		dummies.append({"unit": u, "dmg": 0.0, "t0": 0.0, "last": 0.0})
		_block(d.x, d.z, 0.5)
	# Archery butt
	var butt := p + Vector3(4.0, 0, -6.0)
	var target := Models.cyl(1.0, 1.0, 0.3)
	target.radial_segments = 16
	Models.part(self, target, straw, butt + Vector3(0, 1.3, 0), Vector3(PI / 2.0, 0, 0))
	Models.part(self, Models.box(0.12, 1.6, 0.12), _wood_dark, butt + Vector3(0, 0.8, 0.3), Vector3(-0.25, 0, 0))
	_block(butt.x, butt.z, 1.0)


func _supplies(c: Vector3) -> void:
	for i in _rng.randi_range(3, 5):
		var o := Vector3(_rng.randf_range(-1.6, 1.6), 0, _rng.randf_range(-1.6, 1.6))
		var p := c + o
		if _rng.randf() < 0.55:
			var s := _rng.randf_range(0.8, 1.2)
			Models.part(self, Models.box(s, s, s), _wood, p + Vector3(0, s * 0.5, 0), Vector3(0, _rng.randf() * TAU, 0))
			if _rng.randf() < 0.4:
				var s2 := s * 0.7
				Models.part(self, Models.box(s2, s2, s2), _wood, p + Vector3(0, s + s2 * 0.5, 0), Vector3(0, _rng.randf() * TAU, 0))
		else:
			var barrel := Models.cyl(0.42, 0.42, 1.1)
			barrel.radial_segments = 12
			Models.part(self, barrel, _wood_dark, p + Vector3(0, 0.55, 0))
			for y in [0.2, 0.9]:
				Models.part(self, Models.cyl(0.44, 0.44, 0.06), _iron, p + Vector3(0, y, 0))
	_block(c.x, c.z, 2.1)


# ------------------------------------------------------------------ NPCs

func _build_npcs() -> void:
	var npcs := [
		["warden", "Commander Thessa", Vector3(2.8, 0, -20.5)],
		["arcanist", "Archmage Corvin", Vector3(-6.5, 0, 3.0)],
		["oracle", "Sister Maelis", Vector3(5.5, 0, 9.8)],
		["blademaster", "Quartermaster Hesk", Vector3(-18.5, 0, 12.0)],
	]
	for n in npcs:
		var u := Unit.new()
		u.world = self
		add_child(u)
		u.setup_class(n[0], n[1])
		u.position = n[2]
		u.nameplate.modulate = UITheme.GOLD
		var look := -u.position
		if u.unit_name.begins_with("Commander"):
			look = Vector3(0, 0, 1)
		u.rotation.y = atan2(-look.x, -look.z)
		_block(u.position.x, u.position.z, 0.5)


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.theme()
	layer.add_child(root)
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 22
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var title := UITheme.title("Emberfall Outpost", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)
	var sub := UITheme.title("The last camp before the Cinder Tyrant's lair", 17, UITheme.GOLD_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(sub)
	_sub = sub
	_prompt = UITheme.title(_prompt_text(), 22)
	_bottom(_prompt, 92)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.modulate.a = 0.0
	root.add_child(_prompt)
	var hint := UITheme.title("WASD move  ·  Space jump  ·  Right-drag camera  ·  V view  ·  Training dummies east of the portal  ·  " +
		("Enter chat  ·  Esc war party" if online else "Esc change hero"), 15, UITheme.GOLD_DIM)
	_hint = hint
	_bottom(hint, 36)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)
	if online:
		_build_online_ui(root)
	_fade = ColorRect.new()
	_fade.color = Color(0.07, 0.01, 0.05, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)


## Centres a label horizontally, `up` pixels above the bottom edge.
func _bottom(l: Label, up: float) -> void:
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.offset_top = -up - 30.0
	l.offset_bottom = -up
