extends Node3D
## Entry point: menus, the Outpost, solo raids, online raids and the dedicated server.
##
## Dedicated server (no window):  godot --headless --path . -- --server [--port=24565]
## Headless balance test:         godot --headless --path . -- --sim --class=arcanist --runs=5

var world: RaidWorld  # the raid this client plays (or offline practice)
var raids: Array = []  # dedicated server: one RaidWorld per war party in battle
var hub: HubWorld  # the Outpost: walked before a raid (online: shared with everyone on the realm)
var controller: PlayerController
var hud: RaidHUD
var menu: MenuUI
var menu_camera: Camera3D
var preview: Node3D
var last_class := "warden"
var last_auto := false
var dedicated := false
var _args := {}


func _ready() -> void:
	_args = _parse_args()
	if _args.has("sim"):
		_run_sim(_args)
		return
	Net.main = self
	Net.raid_started.connect(_client_raid_started)
	Net.back_in_lobby.connect(return_to_lobby)
	Net.disconnected.connect(_on_disconnected)
	if _args.has("server"):
		_start_dedicated()
		return
	_build_arena()
	hud = RaidHUD.new()
	add_child(hud)
	hud.retry_requested.connect(_on_retry)
	hud.menu_requested.connect(_back_to_menu)
	hud.lobby_requested.connect(func(): Net.request("to_lobby"))
	hud.leave_requested.connect(func(): Net.request("leave_party"))
	hud.surrender_requested.connect(_on_surrender)
	hud.quit_requested.connect(_quit_game)
	menu = MenuUI.new()
	add_child(menu)
	menu.solo_start.connect(_enter_hub)
	menu.connect_requested.connect(_connect_realm)
	menu.login_requested.connect(func(u: String, p: String): Net.login(u, p))
	menu.register_requested.connect(func(u: String, p: String): Net.register_account(u, p))
	menu.logout_requested.connect(_logout)
	menu.quit_requested.connect(_quit_game)
	menu.rejoin_requested.connect(func(): Net.request("rejoin"))
	menu.hub_requested.connect(_close_overlay)
	menu.hero_chosen.connect(_choose_hero)
	Net.connected.connect(func(): menu.show_screen("auth"))
	Net.auth_result.connect(_on_auth)
	Net.rejoin_offered.connect(func(info: Dictionary):
		if world == null:
			menu.show_rejoin(info))
	Net.lobby_changed.connect(_on_lobby_changed)
	_dev_flags()


# ------------------------------------------------------------------ modes

## Offline: picking a hero drops you in the Outpost; walking through its portal starts the raid.
func _enter_hub(class_id: String, autoplay: bool) -> void:
	if Net.is_net():
		Net.leave()
	last_class = class_id
	last_auto = autoplay
	_clear_fight()
	if preview:
		preview.visible = false
	hub = HubWorld.new()
	add_child(hub)
	hub.setup(class_id)
	hub.portal_entered.connect(func(): _start_solo(last_class, last_auto))
	hub.leave_requested.connect(_back_to_menu)
	hub.player_changed.connect(func(): hud.bind_training(hub, hub.controller))
	hud.bind_training(hub, hub.controller)
	menu.hide_all()


## Online: logged-in players (and parties back from a raid) walk the realm's shared Outpost.
func _enter_online_hub() -> void:
	_clear_fight()
	if preview:
		preview.visible = false
	var cid := Net.avatar_class(Net.my_id())
	if cid == "":
		cid = String(menu.cfg_value("hero", "warden"))
	hub = HubWorld.new()
	add_child(hub)
	hub.setup(cid, true, Net.my_name)
	hub.portal_entered.connect(func(): menu.show_screen("party"))
	hub.leave_requested.connect(func(): menu.show_screen("party"))
	hub.player_changed.connect(func(): hud.bind_training(hub, hub.controller))
	hud.bind_training(hub, hub.controller)
	menu.hide_all()
	_hub_dev()


## Picked on the Choose Your Hero screen: after logging in, or "Change Hero" in the Outpost.
func _choose_hero(cid: String) -> void:
	menu.remember("hero", cid)
	Net.request("set_hero", [cid])
	if hub == null:
		_enter_online_hub()
	hub.set_player_class(cid)
	menu.hide_all()


## Closing the War Party window (or the rejoin / hero screens) goes back to walking the Outpost.
func _close_overlay() -> void:
	if hub != null:
		menu.hide_all()
	elif Net.logged_in:
		menu.show_screen("hero")


func _on_lobby_changed() -> void:
	if hub == null or not hub.online:
		return
	var cid := Net.avatar_class(Net.my_id())
	if cid != "" and cid != String(menu.cfg_value("hero", "")):
		menu.remember("hero", cid)


func _start_solo(class_id: String, autoplay: bool) -> void:
	if Net.is_net():
		Net.leave()
	last_class = class_id
	last_auto = autoplay
	_make_world("offline", RaidWorld.solo_roster(class_id), 1, autoplay)


func _make_world(role: String, roster: Array, local_peer: int, autoplay: bool) -> void:
	_clear_fight()
	if preview:
		preview.visible = false
	world = RaidWorld.new()
	world.net_role = role
	world.visuals = not dedicated
	add_child(world)
	world.setup_roster(roster, local_peer, autoplay)
	if dedicated or world.player == null:
		return
	controller = PlayerController.new()
	add_child(controller)
	controller.setup(world, world.player, autoplay)
	hud.bind(world, controller)
	menu.hide_all()


## Dedicated server: a war party's leader starts (or retries) its raid. Each party gets its own world.
func server_start_raid(party_id: int, roster: Array) -> RaidWorld:
	var w := RaidWorld.new()
	w.net_role = "server"
	w.visuals = false
	w.party_id = party_id
	add_child(w)
	w.setup_roster(roster, 0, false)
	raids.append(w)
	print("[realm] raid for party %d: %d players, %d raids running" % [party_id,
		roster.filter(func(r): return int(r["peer"]) != 0).size(), raids.size()])
	return w


func server_end_raid(w: RaidWorld) -> void:
	raids.erase(w)
	w.queue_free()


var _last_realm_log := ""


## Dedicated server: one line whenever the realm's parties change.
func log_realm(players: Dictionary, parties: Dictionary) -> void:
	var line: Array = []
	for pid in parties:
		var party: Dictionary = parties[pid]
		var seats: Array = []
		for sl in party["slots"]:
			var p := int(sl["peer"])
			seats.append("%s=%s" % [sl["class"], players[p]["name"] if players.has(p) else ("bot" if sl["bot"] else "-")])
		line.append("#%d%s[%s]" % [pid, " (raid)" if party["in_raid"] else "", ", ".join(seats)])
	var text := "%d online · %s" % [players.size(), "  ".join(line) if not line.is_empty() else "no parties"]
	if text != _last_realm_log:
		_last_realm_log = text
		print("[realm] ", text)


func _client_raid_started(roster: Array) -> void:
	var mine := roster.filter(func(r): return int(r["peer"]) == Net.my_id())
	if mine.is_empty():
		return  # not in this raid
	_make_world("client", roster, Net.my_id(), false)


func return_to_lobby() -> void:
	_clear_fight()
	if dedicated:
		return
	if Net.is_net() and Net.logged_in:
		_enter_online_hub()
		return
	_show_menu_scene()
	menu.show_screen("realm")


func world_peer_left(w: RaidWorld, peer: int) -> void:
	var u := w.unit_of_peer(peer)
	if u != null:
		u.owner_peer = 0
		u.set_meta("player_name", u.unit_name)
		u.unit_name += " (bot)"
		if u.nameplate:
			u.nameplate.text = u.unit_name
		u.brain = BotBrain.new(u, w, float(u.get_meta("side", 1.0)))


## Server: a player who dropped out takes their hero back from the bot. Returns the roster the
## client needs to rebuild the raid (snapshots then fill in positions, health and auras).
func world_peer_rejoined(w: RaidWorld, peer: int, slot: int, player_name: String) -> Array:
	var u := w.unit_by_id(slot)
	if u != null:
		u.owner_peer = peer
		u.brain = null
		u.unit_name = player_name
		if u.nameplate:
			u.nameplate.text = u.unit_name
	var roster: Array = []
	for p in w.party_all():
		roster.append({"class": p.class_id, "peer": p.owner_peer, "name": p.unit_name})
	return roster


func _connect_realm(address: String, port: int) -> void:
	var err := Net.connect_realm(address, port)
	if err != "":
		menu.show_screen("realm", err)


func _on_auth(ok: bool, message: String) -> void:
	if dedicated:
		return
	if ok:
		# Choose a hero, then walk into the Outpost. If our party's raid is still running the realm
		# follows up with a rejoin offer, which replaces this screen.
		menu.show_screen("hero")
	else:
		menu.auth_failed(message)


func _logout() -> void:
	Net.leave()
	_clear_fight()
	_show_menu_scene()
	menu.show_screen("realm")


func _on_disconnected(reason: String) -> void:
	var was_raiding := world != null and world.net_role == "client" and not world.finished
	_clear_fight()
	if dedicated:
		return
	_show_menu_scene()
	if was_raiding:
		reason += "\nA bot is holding your spot — reconnect and log in to rejoin the raid."
	menu.show_screen("realm", reason)


## Esc menu > Surrender: offline it ends the attempt; in a party it calls (or answers) a vote.
func _on_surrender() -> void:
	if Net.is_net():
		Net.request("surrender")
	else:
		_back_to_menu()


func _quit_game() -> void:
	Net.leave()  # tell the realm right away so a bot takes over our hero
	get_tree().quit()


func _on_retry() -> void:
	if Net.is_net():
		Net.request("retry")
	else:
		_start_solo(last_class, last_auto)


func _back_to_menu() -> void:
	_clear_fight()
	_show_menu_scene()
	menu.show_screen("solo")


func _show_menu_scene() -> void:
	if menu_camera:
		menu_camera.make_current()
	if preview:
		preview.visible = true


func _clear_fight() -> void:
	if hub:
		hub.queue_free()
		hub = null
	if controller:
		controller.queue_free()
		controller = null
	if world:
		world.queue_free()
		world = null
	if hud:
		hud.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _start_dedicated() -> void:
	dedicated = true
	Engine.max_fps = 60
	var port := int(_args.get("port", str(Net.DEFAULT_PORT)))
	var err := Net.host(port)
	if err != "":
		printerr(err)
		get_tree().quit(1)
		return
	print("Emberfall dedicated server listening on port %d" % port)
	print("LAN addresses: ", ", ".join(Net.local_addresses()))
	Net.chat_received.connect(func(f: String, t: String, _c: Color): print("[chat] %s: %s" % [f, t]))


# ------------------------------------------------------------------ loop

var _shot_path := ""
var _shot_at := 0.0
var _clock := 0.0
var _debug_t := 0.0


func _process(delta: float) -> void:
	if hub != null:
		hub.ui_blocked = menu.visible
		hud.set_training_visible(hub.training_near and not menu.visible)
	if world != null and not (hud != null and hud.menu_open and not Net.is_net()):
		world.tick(minf(delta, 0.1))  # the Esc menu pauses offline practice
	for w in raids:
		w.tick(minf(delta, 0.1))
	_clock += delta
	if _args.has("netdebug") and world != null:
		_debug_t -= delta
		if _debug_t <= 0.0:
			_debug_t = 2.0
			print("[%s] t=%.1f boss=%.1f%% units=%d hazards=%d started=%s ping=%d menu=%s" % [world.net_role, world.fight_time,
				world.boss.hp_pct() * 100.0, world.units.size(), world.hazards.size(), world.started, Net.latency_ms(),
				menu.visible if menu else false])
	if _args.has("quit-at") and _clock >= float(_args["quit-at"]):
		get_tree().quit()
	if _shot_path != "" and _clock >= _shot_at:
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("Saved screenshot ", _shot_path)
		get_tree().quit()


## Dev flags: --hub=<class> [--hubwalk] | --autostart=<class> [--autoplay] [--zoom=6] [--fxtest=<skill>] [--speed=4]
## [--screenshot=<file> --shot-at=<sec>] [--autojoin=<ip> ...] [--menu=<screen>] [--netdebug] [--quit-at=<sec>]
## Dev: --hubwalk[=<delay>] walks the hero up the road and through the portal; --hubcircle walks laps.
func _hub_dev() -> void:
	if hub == null:
		return
	if _args.has("hubwalk"):
		var delay := float(_args["hubwalk"]) if _args["hubwalk"] != "true" else 1.0
		hub.create_tween().tween_property(hub.player, "position", Vector3(0, 0, -0.8), 3.0).set_delay(delay)
	if _args.has("hubtrain"):
		# Dev: stand in the training yard, target the middle dummy and keep using skills
		var h := hub
		h.player.position = HubWorld.YARD + Vector3(-9, 0, 0)
		h.player.rotation.y = -PI / 2.0
		h.controller.yaw = -PI / 2.0
		h.controller.pitch = 0.35
		var t := Timer.new()
		t.wait_time = 0.7
		t.autostart = true
		h.add_child(t)
		var i := [0]
		t.timeout.connect(func():
			var dummy: Unit = h.dummies[1]["unit"]
			var cam := h.controller.camera
			var spot := cam.unproject_position(dummy.global_position + Vector3(0, 1.0, 0))
			if h.player.target == null:
				h.controller._pick(spot)  # the same path as a left-click on the dummy
				print("[train] click at %s -> target %s" % [spot, h.player.target.unit_name if h.player.target else "none"])
			h.controller.use_slot(i[0] % h.player.ability_ids.size())
			if h.controller.ground_aid != "":
				var g: Vector3 = h.controller._mouse_ground(cam.unproject_position(dummy.global_position))
				print("[train] ground aim %s, dummy at %s" % [g.snapped(Vector3.ONE * 0.1), dummy.position])
				h.controller._cast_ground(g)
			i[0] += 1)
	if _args.has("hubcircle"):
		var h := hub
		h.create_tween().tween_method(func(ang: float):
			var p := Vector3(cos(ang) * 16.0, 0, sin(ang) * 16.0 + 4.0)
			h.player.rotation.y = atan2(-(p.x - h.player.position.x), -(p.z - h.player.position.z))
			h.player.position = p, 0.0, 0.35 * 120.0, 120.0)


func _dev_flags() -> void:
	var args := _args
	if args.has("menu"):
		menu.show_screen(args["menu"])
	if args.has("autojoin"):
		# Dev: --autojoin=<ip> --user=<name> --pass=<pw> [--register] [--hero=<class>] [--nohero]
		#   [--party=create|join] [--autoraid --minplayers=N] [--startdelay=<sec>]
		_connect_realm(args["autojoin"], int(args.get("port", str(Net.DEFAULT_PORT))))
		Net.connected.connect(func():
			if args.has("register"):
				Net.register_account(args.get("user", "Tester"), args.get("pass", "secret123"))
			else:
				Net.login(args.get("user", "Tester"), args.get("pass", "secret123")))
		Net.auth_result.connect(func(ok: bool, msg: String):
			print("[auth] ", ok, " ", msg)
			if ok and not args.has("nohero"):
				_choose_hero(String(args.get("hero", "warden"))))
		Net.lobby_changed.connect(func():
			if not Net.logged_in or hub == null or not args.has("party"):
				return
			if not Net.in_party():
				if has_meta("asked"):
					return
				if args["party"] == "create":
					set_meta("asked", true)
					Net.request("create_party")
				elif args["party"] == "join" and not Net.lobby["parties"].is_empty():
					set_meta("asked", true)
					Net.request("join_party", [int(Net.lobby["parties"][0][0])])
			elif Net.is_leader() and args.has("autoraid") and not args.has("startdelay") and not Net.my_party()["in_raid"]:
				var n := 0
				for sl in Net.my_party()["slots"]:
					if int(sl["peer"]) != 0:
						n += 1
				if n >= int(args.get("minplayers", "1")) and not has_meta("started"):
					set_meta("started", true)  # once: don't re-pull after the party comes back
					Net.request("start"))
		if args.has("startdelay"):
			get_tree().create_timer(float(args["startdelay"])).timeout.connect(func(): Net.request("start"))
	if args.has("autorejoin"):
		Net.rejoin_offered.connect(func(info: Dictionary):
			print("[rejoin] offered: ", info)
			Net.request("rejoin"))
	if args.has("autovote"):
		Net.vote_changed.connect(func(st: Dictionary):
			print("[vote] ", st)
			if st.get("active", false) and not Net.i_voted():
				Net.request("vote", [args["autovote"] == "yes"]))
	if args.has("autosurrender"):
		get_tree().create_timer(float(args["autosurrender"])).timeout.connect(func():
			print("[vote] calling surrender")
			_on_surrender())
	if args.has("hub"):
		_enter_hub(args["hub"], false)
		_hub_dev()
	if args.has("autostart"):
		_start_solo(args["autostart"], args.has("autoplay"))
	if args.has("zoom") and controller:
		controller.dist = float(args["zoom"])
		controller.pitch = 0.3
	if args.has("fxtest") and world:
		# Dev: fire skill visuals on a loop for screenshots
		var aid: String = args["fxtest"]
		var t := Timer.new()
		t.wait_time = 0.9
		t.autostart = true
		add_child(t)
		t.timeout.connect(func():
			if world and world.player:
				var pl: Unit = world.player
				pl.cooldowns.clear()
				pl.gcd_remaining = 0.0
				pl.resource = pl.max_resource
				pl.combo = 5
				pl.target = world.boss
				pl.face_toward(world.boss)
				var pt := world.boss.flat_pos() + (pl.flat_pos() - world.boss.flat_pos()).normalized() * 6.0
				var err := pl.use_ability(aid, world.boss, pt)
				if err != "":
					SkillFx.ability(world, pl, aid, world.boss, pt))
	if args.has("animfreeze"):
		DragonRig.debug_freeze = float(args["animfreeze"])
	if args.has("bossfx") and world:
		# Dev: --bossfx=roar|breath|meteor|pools|tail|pulse|cataclysm|claw|bite|claw_l|claw_r|stomp|melee|takeoff [--bossfx-every=5]
		var t2 := Timer.new()
		t2.wait_time = float(args.get("bossfx-every", "5"))
		t2.autostart = true
		add_child(t2)
		var fire := func():
			if world == null:
				return
			var br: DragonBrain = world.boss.brain
			var who: Unit = world.player if world.player != null else world.party_all()[0]
			match String(args["bossfx"]):
				"roar":
					world.boss_fx("wake")
				"breath":
					br._flame_breath()
				"meteor":
					for i in 2:
						world.add_hazard(Hazard.circle(who.position + Vector3(i * 9.0 - 4.5, 0, -3), 6.0, 3.0, 0.0, "Meteor", world.boss))
				"pools":
					br._cinder_pools()
				"tail":
					br._tail_lash()
				"pulse":
					world.boss_fx("pulse")
				"cataclysm":
					br._cataclysm()
				"claw":
					world.boss_fx("claw", who)
				"bite", "claw_l", "claw_r", "stomp":
					world.boss.model.play(String(args["bossfx"]), who)
				"melee":
					SkillFx.auto_attack(world, world.boss, who)
				"takeoff":
					world.boss_fx("takeoff")
		t2.timeout.connect(fire)
		get_tree().create_timer(0.5).timeout.connect(fire)
	if args.has("nomenu"):
		menu.hide_all()
		if args.has("autostart"):
			hud.visible = false
	if args.has("cam"):
		var c: PackedStringArray = String(args["cam"]).split(",")
		var cam := Camera3D.new()
		cam.fov = 60
		add_child(cam)
		cam.position = Vector3(float(c[0]), float(c[1]), float(c[2]))
		var look := Vector3(float(c[3]), float(c[4]), float(c[5])) if c.size() >= 6 else Vector3(0, 4, 0)
		cam.look_at(look)
		cam.make_current()
	if args.has("escmenu") and hud:
		hud.set_menu_open(true)  # dev: screenshot the game menu
	if args.has("rejoinpreview"):
		menu.show_rejoin({"slot": 0, "class": "arcanist", "boss_pct": 0.63, "time": 134.0, "alive": 4, "party": 5,
			"hero_alive": true, "finished": false, "started": true})
	if args.has("speed"):
		Engine.time_scale = float(args["speed"])
	if args.has("screenshot"):
		_shot_path = args["screenshot"]
		_shot_at = float(args.get("shot-at", "3"))


# ------------------------------------------------------------------ arena

func _build_arena() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	# Dark, ash-choked sky: black overhead, a smouldering red band at the horizon.
	sky_mat.sky_top_color = Color(0.035, 0.012, 0.018)
	sky_mat.sky_horizon_color = Color(0.46, 0.12, 0.045)
	sky_mat.ground_horizon_color = Color(0.38, 0.1, 0.035)
	sky_mat.ground_bottom_color = Color(0.08, 0.015, 0.008)
	sky_mat.sky_curve = 0.1
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.38, 0.35)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.95
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.8
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_light_color = Color(0.3, 0.09, 0.045)
	env.fog_density = 0.0075
	env.fog_sky_affect = 0.75
	env.fog_height = 1.0
	env.fog_height_density = 0.05   # low smoke hugging the ground
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.light_color = Color(1.0, 0.62, 0.48)   # dim, filtered through ash
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

	# Warm under-light from the lava
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		var l := OmniLight3D.new()
		l.position = Vector3(cos(a) * 30.0, 1.0, sin(a) * 30.0)
		l.light_color = Color(1.0, 0.34, 0.08)
		l.omni_range = 24.0
		l.light_energy = 2.2
		add_child(l)

	# Cracked stone platform with glowing seams
	var stone_noise := FastNoiseLite.new()
	stone_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	stone_noise.frequency = 0.035
	stone_noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	var stone_tex := NoiseTexture2D.new()
	stone_tex.noise = stone_noise
	stone_tex.seamless = true
	stone_tex.width = 512
	stone_tex.height = 512
	var stone_ramp := Gradient.new()
	stone_ramp.offsets = PackedFloat32Array([0.0, 0.55, 0.85, 1.0])
	stone_ramp.colors = PackedColorArray([Color(0.33, 0.29, 0.27), Color(0.27, 0.23, 0.22),
		Color(0.16, 0.13, 0.13), Color(0.05, 0.03, 0.03)])
	stone_tex.color_ramp = stone_ramp
	var normal_tex := NoiseTexture2D.new()
	normal_tex.noise = stone_noise
	normal_tex.seamless = true
	normal_tex.as_normal_map = true
	normal_tex.bump_strength = 6.0
	normal_tex.width = 512
	normal_tex.height = 512
	var crack_tex := NoiseTexture2D.new()
	crack_tex.noise = stone_noise
	crack_tex.seamless = true
	crack_tex.width = 512
	crack_tex.height = 512
	var crack_ramp := Gradient.new()
	crack_ramp.offsets = PackedFloat32Array([0.0, 0.9, 0.97, 1.0])
	crack_ramp.colors = PackedColorArray([Color(0, 0, 0), Color(0, 0, 0), Color(1.0, 0.35, 0.05), Color(1.0, 0.6, 0.2)])
	crack_tex.color_ramp = crack_ramp
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_texture = stone_tex
	floor_m.normal_enabled = true
	floor_m.normal_texture = normal_tex
	floor_m.emission_enabled = true
	floor_m.emission_texture = crack_tex
	floor_m.emission_energy_multiplier = 1.4
	floor_m.roughness = 0.9
	floor_m.uv1_scale = Vector3(0.07, 0.07, 0.07)
	floor_m.uv1_triplanar = true
	floor_m.uv1_world_triplanar = true
	var floor_mesh := Models.cyl(32.0, 34.5, 2.0)
	floor_mesh.radial_segments = 72
	Models.part(self, floor_mesh, floor_m, Vector3(0, -1.0, 0))
	# Rim stones
	var rim_m := Models.mat(Color(0.2, 0.17, 0.16), 0.0, 0.95)
	for i in 36:
		var a := TAU * i / 36.0
		Models.part(self, Models.box(5.2, 0.5, 1.4), rim_m, Vector3(cos(a) * 32.3, 0.05, sin(a) * 32.3),
			Vector3(0, -a + PI / 2.0, 0))

	# Lava sea (animated shader)
	var lava_mat := ShaderMaterial.new()
	lava_mat.shader = load("res://shaders/lava.gdshader")
	for k in 2:
		var n := FastNoiseLite.new()
		n.frequency = 0.012 if k == 0 else 0.02
		n.fractal_octaves = 4
		n.seed = 7 + k * 31
		var t := NoiseTexture2D.new()
		t.noise = n
		t.seamless = true
		t.width = 256
		t.height = 256
		t.generate_mipmaps = true
		lava_mat.set_shader_parameter("noise_a" if k == 0 else "noise_b", t)
	var lava := PlaneMesh.new()
	lava.size = Vector2(400, 400)
	var lava_mi := MeshInstance3D.new()
	lava_mi.mesh = lava
	lava_mi.material_override = lava_mat
	lava_mi.position = Vector3(0, -1.6, 0)
	lava_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lava_mi)

	# Pillars with burning braziers
	var pillar_m := Models.mat(Color(0.17, 0.14, 0.14), 0.0, 0.9)
	var gold := Models.mat(Color(0.6, 0.45, 0.2), 0.0, 0.5)
	for i in 10:
		var a := TAU * i / 10.0
		var p := Vector3(cos(a), 0, sin(a)) * 34.0
		var broken := i % 3 == 1
		var h := 6.0 if broken else 10.0
		Models.part(self, Models.cyl(1.0, 1.4, h), pillar_m, p + Vector3(0, h / 2.0 - 0.5, 0))
		Models.part(self, Models.box(3.0, 0.6, 3.0), pillar_m, p + Vector3(0, 0, 0))
		if broken:
			Models.part(self, Models.cyl(1.0, 1.0, 3.0), pillar_m, p + Vector3(2.5, 0.3, 1.0), Vector3(0.2, a, PI / 2))
			continue
		Models.part(self, Models.cyl(1.1, 0.6, 0.8), gold, p + Vector3(0, h, 0))
		var fire := Vfx.emitter({"amount": 40, "lifetime": 0.9, "one_shot": false, "vmin": 1.5, "vmax": 3.0,
			"direction": Vector3.UP, "spread": 12.0, "sphere": 0.45, "size": 1.1, "grow": true,
			"colors": [Color(1, 0.9, 0.5, 1), Color(1, 0.45, 0.1, 0.9), Color(0.5, 0.1, 0.02, 0.4), Color(0.1, 0.05, 0.05, 0)]})
		fire.position = p + Vector3(0, h + 0.5, 0)
		add_child(fire)
		var fl := OmniLight3D.new()
		fl.position = p + Vector3(0, h + 1.5, 0)
		fl.light_color = Color(1, 0.55, 0.2)
		fl.omni_range = 14.0
		fl.light_energy = 1.2
		add_child(fl)

	# Rocks scattered at the edge and distant volcanoes
	var rock_m := Models.mat(Color(0.12, 0.1, 0.1), 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 26:
		var a := rng.randf() * TAU
		var d := rng.randf_range(36.0, 60.0)
		var rs := rng.randf_range(1.0, 4.0)
		var rock := SphereMesh.new()
		rock.radial_segments = 6
		rock.rings = 4
		rock.radius = rs
		rock.height = rs * 1.4
		Models.part(self, rock, rock_m, Vector3(cos(a) * d, -1.2, sin(a) * d),
			Vector3(rng.randf(), rng.randf() * TAU, rng.randf()), Vector3(1.0, rng.randf_range(0.6, 1.6), 1.2))
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		var d := rng.randf_range(140.0, 190.0)
		var hgt := rng.randf_range(45.0, 85.0)
		var cone := Models.cyl(hgt * 0.08, hgt * 0.75, hgt)
		cone.radial_segments = 12
		var vp := Vector3(cos(a) * d, hgt / 2.0 - 4.0, sin(a) * d)
		Models.part(self, cone, Models.mat(Color(0.09, 0.05, 0.05), 0.0, 1.0), vp)
		Models.part(self, Models.cyl(hgt * 0.07, hgt * 0.08, 0.5), Models.mat(Color(1.0, 0.4, 0.1), 4.0),
			vp + Vector3(0, hgt / 2.0, 0))

	Vfx.embers_ambient(self, 40.0)

	menu_camera = Camera3D.new()
	menu_camera.position = Vector3(20, 11, 30)
	menu_camera.fov = 60
	add_child(menu_camera)
	menu_camera.look_at(Vector3(0, 4, 0))
	menu_camera.make_current()
	preview = Models.make_dragon()
	preview.name = "PreviewDragon"
	preview.rotation.y = PI * 0.85
	add_child(preview)


# ------------------------------------------------------------------ headless sim

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var kv := s.split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out


func _run_sim(args: Dictionary) -> void:
	var cid: String = args.get("class", "warden")
	var runs := int(args.get("runs", "3"))
	var wins := 0
	for r in runs:
		seed(1000 + r)
		var w := RaidWorld.new()
		w.visuals = false
		w.instant_spells = true
		add_child(w)
		if args.has("comp"):
			# e.g. --comp=arcanist,arcanist,blademaster,oracle,arcanist  (first slot is "You", all bots)
			var roster: Array = []
			var idx := {}
			var list: PackedStringArray = String(args["comp"]).split(",")
			for i in list.size():
				roster.append({"class": list[i], "peer": 1 if i == 0 else 0,
					"name": "You" if i == 0 else RaidWorld.bot_name(list[i], idx)})
			w.setup_roster(roster, 1, true)
		else:
			w.setup(cid, true)
		var steps := 0
		var min_res := {}
		while not w.finished and steps < 20 * 700:
			w.tick(0.05)
			steps += 1
			for u in w.party_all():
				if u.resource_type == "mana" and u.alive:
					min_res[u] = minf(float(min_res.get(u, 1.0)), u.resource_pct())
		if w.victory:
			wins += 1
		print("=== Run %d (%s): %s at %s, boss %.1f%% ===" % [r + 1, cid,
			"VICTORY" if w.victory else ("DEFEAT" if w.finished else "TIMEOUT"),
			RaidWorld.fmt_time(w.fight_time), w.boss.hp_pct() * 100.0])
		var t := maxf(w.fight_time, 1.0)
		for u in w.party_all():
			print("  %-8s %-11s dmg %7d (%4d dps)  heal %7d (%4d hps)  %s" % [u.unit_name, u.class_id,
				int(w.damage_done.get(u, 0.0)), int(float(w.damage_done.get(u, 0.0)) / t),
				int(w.healing_done.get(u, 0.0)), int(float(w.healing_done.get(u, 0.0)) / t),
				"alive" if u.alive else "DEAD"])
			if args.has("verbose"):
				var taken: Dictionary = w.damage_taken.get(u, {})
				var parts: Array = []
				for k in taken:
					parts.append("%s=%d" % [k, int(taken[k])])
				print("      moved %.0fs | min mana %d%% | taken: %s" % [float(w.move_time.get(u, 0.0)),
					int(float(min_res.get(u, 1.0)) * 100), ", ".join(parts)])
		for d in w.death_log:
			print("  death: ", d)
		for p in w.phase_log:
			print("  ", p)
		w.free()
	print("WINS %d / %d" % [wins, runs])
	get_tree().quit()
