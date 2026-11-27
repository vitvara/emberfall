class_name MenuUI
extends CanvasLayer
## Player journey: Realm (type the server address) -> Login / Register -> War Party lobby.
## Offline practice (solo vs. bots) is reachable from the realm screen.
## If the game crashed or the link dropped mid-raid, logging back in shows the Rejoin screen.

signal connect_requested(address: String, port: int)
signal login_requested(user: String, password: String)
signal register_requested(user: String, password: String)
signal solo_start(class_id: String, autoplay: bool)
signal logout_requested
signal quit_requested
signal rejoin_requested

const CONFIG_PATH := "user://client.cfg"
const CLASS_ICONS := {
	"warden": "res://assets/icons/raise_shield.svg",
	"oracle": "res://assets/icons/sanctuary.svg",
	"blademaster": "res://assets/icons/executioners_cut.svg",
	"arcanist": "res://assets/icons/frost_shard.svg",
}
const ROLE_NAMES := {"tank": "Tank", "healer": "Healer", "melee": "Melee DPS", "ranged": "Ranged DPS"}

var root: Control
var screens := {}
var realm_edit: LineEdit
var port_edit: LineEdit
var realm_status: Label
var user_edit: LineEdit
var pass_edit: LineEdit
var pass2_edit: LineEdit
var pass2_row: Control
var auth_title: Label
var auth_btn: Button
var auth_switch: Button
var auth_status: Label
var auth_realm: Label
var registering := false
var auto_check: CheckBox
var lobby_info: Label
var comp_label: Label
var slot_box: VBoxContainer
var chat_log: RichTextLabel
var chat_edit: LineEdit
var start_btn: Button
var who_label: Label
var lobby_latency: Label
var rejoin_btn: Button
var rejoin_title: Label
var rejoin_body: Label
var rejoin_stats: Label
var rejoin_icon: TextureRect
var _lat_t := 0.0
var _cfg := ConfigFile.new()


func _ready() -> void:
	_cfg.load(CONFIG_PATH)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.theme()
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	_build_realm()
	_build_auth()
	_build_solo()
	_build_lobby()
	_build_rejoin()
	Net.lobby_changed.connect(_refresh_lobby)
	Net.chat_received.connect(_on_chat)
	Net.status_changed.connect(func(t: String): realm_status.text = t)
	show_screen("realm")


func show_screen(n: String, status := "") -> void:
	visible = true
	for k in screens:
		screens[k].visible = k == n
	match n:
		"realm":
			realm_status.text = status
		"auth":
			auth_status.text = status
			auth_realm.text = "Realm: " + Net.realm_address
			pass_edit.text = ""
			pass2_edit.text = ""
			_set_registering(registering)
			if user_edit.text == "":
				user_edit.grab_focus()
			else:
				pass_edit.grab_focus()
		"lobby":
			_refresh_lobby()


func hide_all() -> void:
	visible = false
	for k in screens:
		screens[k].visible = false


func remember(key: String, value) -> void:
	_cfg.set_value("client", key, value)
	_cfg.save(CONFIG_PATH)


# ------------------------------------------------------------------ helpers

func _center_panel(w: float, h: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = -w / 2
	p.offset_right = w / 2
	p.offset_top = -h / 2
	p.offset_bottom = h / 2
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(p)
	return p


func _button(text: String, cb: Callable, w := 280.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 42)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _text(t: String, size := 17, c := UITheme.TEXT, wrap := true) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	return l


func _vbox(parent: Control, sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	parent.add_child(v)
	return v


func _centered(c: Control) -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(c)
	return h


func _field(grid: GridContainer, label: String, edit: LineEdit) -> void:
	grid.add_child(_text(label, 18, UITheme.GOLD, false))
	edit.custom_minimum_size = Vector2(300, 38)
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(edit)


func _header(v: VBoxContainer, title: String, sub := "") -> void:
	var t := UITheme.title(title, 44 if sub != "" else 32)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if sub != "":
		var s := UITheme.title(sub, 18, UITheme.GOLD_DIM)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(s)
	v.add_child(UITheme.divider())


# ------------------------------------------------------------------ realm

func _build_realm() -> void:
	var p := _center_panel(600, 520)
	screens["realm"] = p
	var v := _vbox(p, 14)
	var t := UITheme.title("EMBERFALL", 60)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UITheme.title("Choose your realm", 20, UITheme.GOLD_DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	v.add_child(UITheme.divider())
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 10)
	v.add_child(_centered(g))
	realm_edit = LineEdit.new()
	realm_edit.text = str(_cfg.get_value("client", "realm", "10.10.10.30"))
	realm_edit.placeholder_text = "e.g. 10.10.10.30"
	realm_edit.text_submitted.connect(func(_t): _connect())
	_field(g, "Realm address", realm_edit)
	port_edit = LineEdit.new()
	port_edit.text = str(_cfg.get_value("client", "port", Net.DEFAULT_PORT))
	_field(g, "Port", port_edit)
	v.add_child(_centered(_button("Connect", _connect)))
	realm_status = _text("", 16, Color(1, 0.6, 0.5))
	realm_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(realm_status)
	v.add_child(UITheme.divider())
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 12)
	h.add_child(_button("Offline Practice", func(): show_screen("solo"), 220))
	h.add_child(_button("Quit", func(): quit_requested.emit(), 140))
	v.add_child(h)


func _connect() -> void:
	var addr := realm_edit.text.strip_edges()
	if addr == "":
		realm_status.text = "Type the realm address first."
		return
	remember("realm", addr)
	remember("port", int(port_edit.text))
	realm_status.text = "Connecting to %s ..." % addr
	connect_requested.emit(addr, int(port_edit.text))


# ------------------------------------------------------------------ login / register

func _build_auth() -> void:
	var p := _center_panel(600, 520)
	screens["auth"] = p
	var v := _vbox(p, 14)
	auth_title = UITheme.title("Enter the Realm", 34)
	auth_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(auth_title)
	auth_realm = _text("", 15, UITheme.GOLD_DIM)
	auth_realm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(auth_realm)
	v.add_child(UITheme.divider())
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 10)
	v.add_child(_centered(g))
	user_edit = LineEdit.new()
	user_edit.max_length = 16
	user_edit.text = str(_cfg.get_value("client", "user", ""))
	_field(g, "Name", user_edit)
	pass_edit = LineEdit.new()
	pass_edit.secret = true
	pass_edit.text_submitted.connect(func(_t): _submit_auth())
	_field(g, "Password", pass_edit)
	pass2_edit = LineEdit.new()
	pass2_edit.secret = true
	pass2_edit.text_submitted.connect(func(_t): _submit_auth())
	var l2 := _text("Confirm", 18, UITheme.GOLD, false)
	g.add_child(l2)
	pass2_edit.custom_minimum_size = Vector2(300, 38)
	g.add_child(pass2_edit)
	pass2_row = l2
	auth_btn = _button("Log In", _submit_auth)
	v.add_child(_centered(auth_btn))
	auth_status = _text("", 16, Color(1, 0.6, 0.5))
	auth_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(auth_status)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 12)
	auth_switch = _button("Create an account", func(): _set_registering(not registering), 240)
	h.add_child(auth_switch)
	h.add_child(_button("Change realm", func(): logout_requested.emit(), 200))
	v.add_child(h)
	var hint := _text("Names: 3-16 letters, numbers or _.  Passwords: at least 6 characters.", 14, UITheme.GOLD_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)


func _set_registering(on: bool) -> void:
	registering = on
	auth_title.text = "Create an Account" if on else "Enter the Realm"
	auth_btn.text = "Register" if on else "Log In"
	auth_switch.text = "I have an account" if on else "Create an account"
	pass2_edit.visible = on
	pass2_row.visible = on
	auth_status.text = ""


func _submit_auth() -> void:
	var u := user_edit.text.strip_edges()
	var pw := pass_edit.text
	if u == "" or pw == "":
		auth_status.text = "Enter your name and password."
		return
	if registering:
		var err := Accounts.valid_name(u)
		if err == "":
			err = Accounts.valid_password(pw)
		if err == "" and pw != pass2_edit.text:
			err = "Passwords do not match."
		if err != "":
			auth_status.text = err
			return
	remember("user", u)
	auth_status.text = "Please wait..."
	if registering:
		register_requested.emit(u, pw)
	else:
		login_requested.emit(u, pw)


func auth_failed(message: String) -> void:
	auth_status.text = message
	pass_edit.text = ""
	pass2_edit.text = ""


# ------------------------------------------------------------------ offline practice

func _build_solo() -> void:
	var p := _center_panel(860, 600)
	screens["solo"] = p
	var v := _vbox(p, 12)
	_header(v, "Offline Practice")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	for cid in GameData.CLASS_ORDER:
		grid.add_child(_class_card(cid))
	auto_check = CheckBox.new()
	auto_check.text = "Autopilot — let a bot play your class too"
	auto_check.focus_mode = Control.FOCUS_NONE
	v.add_child(_centered(auto_check))
	var help := _text("WASD move · Space jump · 1-7 skills (7 = ground: click to place) · Right-drag camera · V view · " +
		"Tab / click target · F1-F5 party · C stats · Enter chat", 14, UITheme.GOLD_DIM)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(help)
	v.add_child(_centered(_button("Back", func(): show_screen("realm"), 200)))


func _class_card(cid: String) -> Button:
	var c: Dictionary = GameData.CLASSES[cid]
	var b := Button.new()
	b.custom_minimum_size = Vector2(400, 110)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UITheme.slot())
	b.add_theme_stylebox_override("hover", UITheme.slot(Color(0.85, 0.7, 0.35)))
	b.add_theme_stylebox_override("pressed", UITheme.slot(Color(1, 0.9, 0.6)))
	b.pressed.connect(func(): solo_start.emit(cid, auto_check.button_pressed))
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -12
	h.offset_top = 10
	h.offset_bottom = -10
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	h.add_child(_icon(cid, 80))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(UITheme.title(c["name"], 22, c["color"]))
	for line in [[ROLE_NAMES.get(c["role"], ""), UITheme.GOLD_DIM], [c["desc"], UITheme.TEXT]]:
		var l := _text(line[0], 15, line[1])
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	return b


func _icon(cid: String, size: float) -> TextureRect:
	var icon := TextureRect.new()
	if CLASS_ICONS.has(cid):
		icon.texture = load(CLASS_ICONS[cid])
	icon.custom_minimum_size = Vector2(size, size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


# ------------------------------------------------------------------ lobby

func _build_lobby() -> void:
	var p := _center_panel(1180, 680)
	screens["lobby"] = p
	var v := _vbox(p, 8)
	var t := UITheme.title("War Party", 34)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	lobby_info = _text("", 15, UITheme.GOLD_DIM)
	lobby_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lobby_info)
	v.add_child(UITheme.divider())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(700, 0)
	h.add_child(left)
	slot_box = VBoxContainer.new()
	slot_box.add_theme_constant_override("separation", 8)
	left.add_child(slot_box)
	comp_label = _text("", 16, UITheme.GOLD)
	left.add_child(comp_label)
	var chat := PanelContainer.new()
	chat.add_theme_stylebox_override("panel", UITheme.slot())
	chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(chat)
	var cv := VBoxContainer.new()
	chat.add_child(cv)
	cv.add_child(UITheme.title("Realm Chat", 16, UITheme.GOLD_DIM))
	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.add_theme_font_size_override("normal_font_size", 16)
	cv.add_child(chat_log)
	chat_edit = LineEdit.new()
	chat_edit.placeholder_text = "Say something..."
	chat_edit.text_submitted.connect(func(txt: String):
		if txt.strip_edges() != "":
			Net.request("chat", [txt])
		chat_edit.text = "")
	cv.add_child(chat_edit)
	var bh := HBoxContainer.new()
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_theme_constant_override("separation", 16)
	v.add_child(bh)
	who_label = _text("", 15, UITheme.GOLD_DIM, false)
	bh.add_child(who_label)
	lobby_latency = _text("", 15, UITheme.TEXT, false)
	lobby_latency.add_theme_font_override("font", UITheme.title_font())
	lobby_latency.tooltip_text = "Latency to the realm (round trip)"
	lobby_latency.mouse_filter = Control.MOUSE_FILTER_PASS
	bh.add_child(lobby_latency)
	start_btn = _button("Start Raid", func(): Net.request("start"), 240)
	bh.add_child(start_btn)
	rejoin_btn = _button("Rejoin Raid", func(): rejoin_requested.emit(), 220)
	rejoin_btn.visible = false
	bh.add_child(rejoin_btn)
	bh.add_child(_button("Log Out", func(): logout_requested.emit(), 180))


# ------------------------------------------------------------------ rejoin

func _build_rejoin() -> void:
	var p := _center_panel(640, 420)
	screens["rejoin"] = p
	var v := _vbox(p, 14)
	rejoin_title = UITheme.title("Raid in Progress", 38)
	rejoin_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rejoin_title)
	var sub := UITheme.title("Your party still fights Vyrathax", 18, UITheme.GOLD_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(UITheme.divider())
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 18)
	v.add_child(h)
	rejoin_icon = _icon("", 72)
	h.add_child(rejoin_icon)
	rejoin_body = _text("", 17)
	rejoin_body.custom_minimum_size = Vector2(440, 0)
	h.add_child(rejoin_body)
	rejoin_stats = _text("", 18, UITheme.GOLD)
	rejoin_stats.add_theme_font_override("font", UITheme.title_font())
	rejoin_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rejoin_stats)
	v.add_child(UITheme.divider())
	v.add_child(_centered(_button("Rejoin Raid", func(): rejoin_requested.emit(), 300)))
	var bh := HBoxContainer.new()
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_theme_constant_override("separation", 12)
	bh.add_child(_button("Go to Lobby", func(): show_screen("lobby"), 200))
	bh.add_child(_button("Log Out", func(): logout_requested.emit(), 160))
	v.add_child(bh)
	var hint := _text("You can also rejoin later from the lobby while the raid lasts.", 14, UITheme.GOLD_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)


## info from the realm: {slot, class, boss_pct, time, alive, party, hero_alive, finished, started}
func show_rejoin(info: Dictionary) -> void:
	show_screen("rejoin")
	var cid: String = info.get("class", "")
	var cls: Dictionary = GameData.CLASSES.get(cid, {})
	rejoin_icon.texture = load(CLASS_ICONS[cid]) if CLASS_ICONS.has(cid) else null
	var hero := "Your %s" % cls.get("name", "hero")
	if info.get("finished", false):
		rejoin_title.text = "Raid Over"
		rejoin_body.text = "%s's fight has ended. Rejoin to see the results with your party." % hero
	elif not info.get("hero_alive", true):
		rejoin_title.text = "Raid in Progress"
		rejoin_body.text = "%s has fallen, but the fight goes on — a healer may still revive you." % hero
	else:
		rejoin_title.text = "Raid in Progress"
		rejoin_body.text = "%s is still in the fight. A bot has been playing it while you were away." % hero
	rejoin_stats.text = "Vyrathax %d%%   ·   %s   ·   %d of %d standing" % [roundi(float(info.get("boss_pct", 1.0)) * 100.0),
		("Fight " + RaidWorld.fmt_time(float(info.get("time", 0.0)))) if info.get("started", false) else "Before the pull",
		int(info.get("alive", 0)), int(info.get("party", 5))]


func _class_picker(slot: int, current: String, enabled: bool) -> OptionButton:
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(190, 40)
	ob.add_theme_font_override("font", UITheme.title_font())
	ob.add_theme_font_size_override("font_size", 14)
	for i in GameData.CLASS_ORDER.size():
		var cid: String = GameData.CLASS_ORDER[i]
		ob.add_item("%s  (%s)" % [GameData.CLASSES[cid]["name"], ROLE_NAMES[GameData.CLASSES[cid]["role"]]], i)
		if cid == current:
			ob.select(i)
	ob.disabled = not enabled
	ob.item_selected.connect(func(idx: int): Net.request("set_class", [slot, GameData.CLASS_ORDER[idx]]))
	return ob


func _refresh_lobby() -> void:
	if slot_box == null:
		return
	for c in slot_box.get_children():
		c.queue_free()
	var slots: Array = Net.lobby.get("slots", [])
	var names: Dictionary = Net.lobby.get("names", {})
	var leader := int(Net.lobby.get("leader", 0))
	var me := Net.my_id()
	var i_lead := Net.is_leader()
	var my_slot := Net.my_slot()
	var in_raid: bool = Net.lobby.get("in_raid", false)
	var roles := {"tank": 0, "healer": 0, "melee": 0, "ranged": 0}
	for i in slots.size():
		var s: Dictionary = slots[i]
		var peer := int(s["peer"])
		var cid: String = s["class"]
		var filled: bool = peer != 0 or s["bot"]
		if filled and cid != "":
			roles[GameData.CLASSES[cid]["role"]] += 1
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UITheme.slot(Color(0.85, 0.7, 0.35) if peer == me else Color(0, 0, 0, 0)))
		slot_box.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		row.add_child(h)
		h.add_child(_icon(cid if filled else "", 52))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var title := "Slot %d — open" % (i + 1)
		var tc := UITheme.GOLD_DIM
		if filled and cid != "":
			title = "%s  ·  %s" % [GameData.CLASSES[cid]["name"], ROLE_NAMES[GameData.CLASSES[cid]["role"]]]
			tc = GameData.CLASSES[cid]["color"]
		info.add_child(UITheme.title(title, 18, tc))
		var who := ""
		var who_c := UITheme.TEXT
		if peer != 0:
			who = String(names.get(peer, "Adventurer"))
			if peer == leader:
				who += "  ♛ leader"
			if peer == me:
				who += "  — you"
			who_c = Color(1, 0.95, 0.8)
		elif s["bot"]:
			who = "Bot"
			who_c = Color(0.65, 0.8, 1)
		else:
			who = "Empty — a bot fills it when the raid starts"
			who_c = Color(0.6, 0.58, 0.52)
		info.add_child(_text(who, 16, who_c, false))
		if in_raid:
			continue
		if peer == me:
			h.add_child(_class_picker(i, cid, true))
			h.add_child(_button("Leave", func(): Net.request("leave_slot"), 100))
		elif peer == 0 and s["bot"]:
			h.add_child(_class_picker(i, cid, i_lead))
			if i_lead:
				h.add_child(_button("Remove", func(): Net.request("set_bot", [i, false]), 110))
		elif peer == 0:
			if my_slot != i:
				h.add_child(_button("Join", func(): Net.request("take_slot", [i]), 100))
			if i_lead:
				h.add_child(_button("Add Bot", func(): Net.request("set_bot", [i, true]), 120))
	var parts: Array = ["Tanks %d" % roles["tank"], "Healers %d" % roles["healer"],
		"Damage %d" % (roles["melee"] + roles["ranged"])]
	var warn := ""
	if roles["tank"] == 0:
		warn += "   No tank chosen — a bot tank will fill an empty slot."
	if roles["healer"] == 0:
		warn += "   No healer chosen — a bot healer will fill an empty slot."
	comp_label.text = "Party: " + "  ·  ".join(parts) + warn
	var can_rejoin := Net.can_rejoin()
	start_btn.visible = i_lead and not can_rejoin
	start_btn.disabled = in_raid or my_slot < 0
	rejoin_btn.visible = can_rejoin
	who_label.text = "Logged in as %s" % Net.my_name if Net.my_name != "" else ""
	# Still on the rejoin screen (menu showing, not in a fight) but the raid ended meanwhile: go to the lobby.
	# After Rejoin the menu is hidden; the lobby update that follows must not bring it back over the fight.
	if visible and screens.has("rejoin") and screens["rejoin"].visible and not can_rejoin \
			and (Net.main == null or Net.main.world == null):
		show_screen("lobby", "")
		return
	if can_rejoin:
		lobby_info.text = "Your raid is still going — a bot is playing your hero. Press Rejoin Raid to take it back."
	elif in_raid:
		lobby_info.text = "A raid is in progress on this realm — you will be able to join the next one."
	elif i_lead:
		lobby_info.text = "Realm %s  ·  You lead the party: take a slot, pick any class, add bots, then start." % Net.realm_address
	else:
		lobby_info.text = "Realm %s  ·  Take a slot and pick any class. The leader starts the raid." % Net.realm_address


func _process(delta: float) -> void:
	if not visible or not screens["lobby"].visible:
		return
	_lat_t -= delta
	if _lat_t <= 0.0:
		_lat_t = 0.5
		var lt: Array = Net.latency_text()
		lobby_latency.text = lt[0]
		lobby_latency.add_theme_color_override("font_color", lt[1])


func _on_chat(from: String, text: String, c: Color) -> void:
	if from == "":
		chat_log.append_text("[color=#%s][i]%s[/i][/color]\n" % [c.to_html(false), text])
	else:
		chat_log.append_text("[color=#e8c27a][%s][/color] [color=#%s]%s[/color]\n" % [from, c.to_html(false), text])
