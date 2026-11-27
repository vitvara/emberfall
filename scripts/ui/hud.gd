class_name RaidHUD
extends CanvasLayer
## All UI, built in code: unit frames, action bar, meters, end screen, the Esc game menu and the
## surrender vote banner.

signal retry_requested
signal menu_requested
signal lobby_requested
signal leave_requested
signal surrender_requested
signal quit_requested

const RES_COLORS := {
	"mana": Color(0.25, 0.45, 1.0),
	"rage": Color(0.85, 0.15, 0.15),
	"energy": Color(1.0, 0.85, 0.2),
}

var world  # RaidWorld
var controller  # PlayerController
var root: Control
var fight_ui: Control
var end_buttons: HBoxContainer
var chat_log: RichTextLabel
var chat_input: LineEdit
var chat_panel: PanelContainer

var boss_bar: ProgressBar
var boss_text: Label
var boss_cast: ProgressBar
var boss_cast_text: Label
var boss_auras: HBoxContainer
var phase_label: Label
var player_ui := {}
var target_ui := {}
var party_rows: Array = []
var action_slots: Array = []
var cast_bar: ProgressBar
var cast_text: Label
var emote_label: Label
var error_label: Label
var msg_label: Label
var countdown_label: Label
var taunt_label: Label
var ground_label: Label
var timer_label: Label
var latency_label: Label
var _lat_t := 0.0
var meter_label: Label
var sheet: PanelContainer
var sheet_label: Label
var end_panel: PanelContainer
var end_title: Label
var end_body: Label
var _emote_t := 0.0
var _error_t := 0.0
var _msg_t := 0.0
var game_menu: Control
var menu_main: VBoxContainer
var menu_confirm: VBoxContainer
var confirm_text: Label
var confirm_yes: Button
var surrender_btn: Button
var _confirm_action := Callable()
var vote_panel: PanelContainer
var vote_label: Label
var vote_buttons: HBoxContainer
var _vote_result_t := 0.0
var menu_open: bool:
	get:
		return game_menu != null and is_instance_valid(game_menu) and game_menu.visible


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.theme()
	add_child(root)
	Net.chat_received.connect(_on_chat)
	Net.ability_failed.connect(func(t: String): _on_error(t))
	Net.vote_changed.connect(_on_vote)


# ------------------------------------------------------------------ helpers

func _style(bg: Color, radius := 6, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	return sb


func _panel(_bg := Color.BLACK) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.iron_panel_hud())
	return p


func _label(text: String, size := 14, c := UITheme.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size + 2)
	l.add_theme_color_override("font_color", c)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(fill: Color, h := 18.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.0
	b.custom_minimum_size = Vector2(0, h + 2)
	b.add_theme_stylebox_override("fill", UITheme.bar_fill(fill))
	b.add_theme_stylebox_override("background", UITheme.bar_bg())
	b.set_meta("fill", fill)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _bar_label(b: ProgressBar, size := 12) -> Label:
	var l := _label("", size - 2)
	l.add_theme_font_override("font", UITheme.title_font())  # clear lining numerals on bars
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(l)
	return l


func _set_fill(b: ProgressBar, c: Color) -> void:
	if b.get_meta("fill", Color.BLACK) != c:
		b.set_meta("fill", c)
		b.add_theme_stylebox_override("fill", UITheme.bar_fill(c))


func _place(c: Control, al: float, at: float, ar: float, ab: float,
		ol: float, ot: float, or_: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = or_
	c.offset_bottom = ob


func _center_label(size: int, c: Color, y_anchor: float) -> Label:
	var l := _label("", size, c)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(l, 0.0, y_anchor, 1.0, y_anchor, 0, 0, 0, 40)
	fight_ui.add_child(l)
	return l


func clear() -> void:
	if fight_ui:
		fight_ui.queue_free()
		fight_ui = null
	world = null
	training = false


var training := false  # Outpost training yard: just our frames, target frame and action bar


## The Outpost's training dummies: a slim HUD (no dragon, party, meters, chat or game menu).
func bind_training(w, ctrl) -> void:
	world = w
	controller = ctrl
	training = true
	if fight_ui:
		fight_ui.queue_free()
	party_rows.clear()
	action_slots.clear()
	fight_ui = Control.new()
	fight_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	fight_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fight_ui.visible = false
	root.add_child(fight_ui)
	player_ui = _build_unit_frame(Vector2(16, 16))
	target_ui = _build_unit_frame(Vector2(16, 138))
	_build_action_bar()
	_build_sheet()
	msg_label = _center_label(18, Color.WHITE, 0.62)
	error_label = _center_label(18, Color(1, 0.3, 0.3), 0.67)
	ground_label = _center_label(17, Color(0.5, 1, 0.6), 0.72)
	# Rebinding (hero changed) reuses the same controller and world: connect each handler once
	for pair in [[controller.ground_mode, _on_ground_mode], [world.message, _on_message],
			[controller.error_message, _on_error], [controller.toggle_character_sheet, _toggle_sheet]]:
		if not (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).connect(pair[1])


func _on_ground_mode(t: String) -> void:
	if ground_label and is_instance_valid(ground_label):
		ground_label.text = t


func _toggle_sheet() -> void:
	if sheet and is_instance_valid(sheet):
		sheet.visible = not sheet.visible


func set_training_visible(on: bool) -> void:
	if training and fight_ui:
		fight_ui.visible = on


# ------------------------------------------------------------------ fight UI

func bind(w, ctrl) -> void:
	world = w
	controller = ctrl
	training = false
	if fight_ui:
		fight_ui.queue_free()
	party_rows.clear()
	action_slots.clear()
	fight_ui = Control.new()
	fight_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	fight_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fight_ui)
	_build_boss_frame()
	player_ui = _build_unit_frame(Vector2(16, 16))
	target_ui = _build_unit_frame(Vector2(16, 138))
	_build_party_frames()
	_build_action_bar()
	_build_meters()
	_build_sheet()
	_build_end_panel()
	emote_label = _center_label(24, Color(1, 0.55, 0.2), 0.125)
	msg_label = _center_label(18, Color.WHITE, 0.62)
	error_label = _center_label(18, Color(1, 0.3, 0.3), 0.67)
	countdown_label = _center_label(48, Color(1, 0.85, 0.4), 0.4)
	taunt_label = _center_label(22, Color(1, 0.6, 0.25), 0.2)
	ground_label = _center_label(17, Color(0.5, 1, 0.6), 0.72)
	controller.ground_mode.connect(func(t: String): ground_label.text = t)
	world.emote.connect(_on_emote)
	world.message.connect(_on_message)
	world.fight_ended.connect(_on_fight_ended)
	controller.error_message.connect(_on_error)
	controller.toggle_character_sheet.connect(func(): sheet.visible = not sheet.visible)
	_build_chat()
	_build_vote_panel()
	_build_game_menu()
	configure_end_buttons()


func _build_boss_frame() -> void:
	var p := _panel()
	_place(p, 0.5, 0, 0.5, 0, -290, 12, 290, 12)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	fight_ui.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	var name_l := UITheme.title(GameData.BOSS["name"], 20, Color(1, 0.62, 0.4))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	boss_bar = _bar(Color(0.75, 0.12, 0.08), 22)
	boss_text = _bar_label(boss_bar, 13)
	v.add_child(boss_bar)
	phase_label = _label("", 13, Color(1, 0.85, 0.6))
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(phase_label)
	boss_cast = _bar(Color(1, 0.55, 0.1), 16)
	boss_cast_text = _bar_label(boss_cast, 12)
	v.add_child(boss_cast)
	boss_auras = _make_aura_bar(30)
	boss_auras.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(boss_auras)


func _build_unit_frame(pos: Vector2) -> Dictionary:
	var p := _panel()
	p.position = pos
	p.custom_minimum_size = Vector2(266, 0)
	fight_ui.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	var name_l := _label("", 15)
	v.add_child(name_l)
	var hp := _bar(Color(0.2, 0.8, 0.3), 20)
	var hp_t := _bar_label(hp)
	v.add_child(hp)
	var res := _bar(Color(0.25, 0.45, 1.0), 12)
	var res_t := _bar_label(res, 10)
	v.add_child(res)
	var cast := _bar(Color(1, 0.75, 0.2), 12)
	var cast_t := _bar_label(cast, 10)
	v.add_child(cast)
	var auras := _make_aura_bar(28)
	v.add_child(auras)
	return {"panel": p, "name": name_l, "hp": hp, "hp_t": hp_t, "res": res, "res_t": res_t,
		"cast": cast, "cast_t": cast_t, "auras": auras}


func _build_party_frames() -> void:
	var p := _panel()
	p.position = Vector2(16, 270)
	fight_ui.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	v.add_child(_label("Party  (F1-F5)", 13, Color(1, 0.85, 0.6)))
	for u in world.party_all():
		var b := Button.new()
		b.custom_minimum_size = Vector2(250, 52)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UITheme.slot())
		b.add_theme_stylebox_override("hover", UITheme.slot(Color(0.75, 0.6, 0.3)))
		b.add_theme_stylebox_override("pressed", UITheme.slot(Color(1, 0.85, 0.5)))
		b.pressed.connect(func(): controller.select(u))
		v.add_child(b)
		var inner := VBoxContainer.new()
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 4
		inner.offset_right = -4
		inner.offset_top = 3
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_theme_constant_override("separation", 1)
		b.add_child(inner)
		var hp := _bar(u.color.darkened(0.15), 22)
		var hp_t := _bar_label(hp, 12)
		inner.add_child(hp)
		var res := _bar(RES_COLORS.get(u.resource_type, Color.GRAY), 6)
		inner.add_child(res)
		var auras := _make_aura_bar(16)
		inner.add_child(auras)
		party_rows.append({"unit": u, "hp": hp, "hp_t": hp_t, "res": res, "auras": auras, "button": b})


func _build_action_bar() -> void:
	var u: Unit = world.player
	var n := u.ability_ids.size()
	var w := n * 74
	var v := VBoxContainer.new()
	_place(v, 0.5, 1, 0.5, 1, -w / 2.0, -150, w / 2.0, -14)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BEGIN
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fight_ui.add_child(v)
	cast_bar = _bar(Color(1, 0.75, 0.2), 18)
	cast_text = _bar_label(cast_bar, 12)
	v.add_child(cast_bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	for i in n:
		var aid: String = u.ability_ids[i]
		var ab: Dictionary = GameData.ABILITIES[aid]
		var b := Button.new()
		b.custom_minimum_size = Vector2(68, 68)
		b.focus_mode = Control.FOCUS_NONE
		b.clip_contents = true
		var col := u.color.darkened(0.55)
		b.add_theme_stylebox_override("normal", UITheme.slot())
		b.add_theme_stylebox_override("hover", UITheme.slot(Color(0.85, 0.7, 0.35)))
		b.add_theme_stylebox_override("pressed", UITheme.slot(Color(1, 0.9, 0.6)))
		b.tooltip_text = _ability_tooltip(u, aid)
		b.pressed.connect(func(): controller.use_slot(i))
		h.add_child(b)
		var icon_path := "res://assets/icons/%s.svg" % aid
		if ResourceLoader.exists(icon_path):
			var icon := TextureRect.new()
			icon.texture = load(icon_path)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon.offset_left = 3
			icon.offset_top = 3
			icon.offset_right = -3
			icon.offset_bottom = -3
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(icon)
		else:
			b.text = ab["name"]
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.add_theme_font_size_override("font_size", 11)
		# Cooldown sweep: a dark curtain that shrinks as the cooldown runs out
		var sweep := ColorRect.new()
		sweep.color = Color(0, 0, 0, 0.62)
		sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sweep.anchor_left = 0.0
		sweep.anchor_right = 1.0
		sweep.anchor_bottom = 1.0
		sweep.anchor_top = 1.0
		b.add_child(sweep)
		var key := _label(str(i + 1), 13, Color(1, 0.95, 0.6))
		key.position = Vector2(5, 2)
		b.add_child(key)
		var cd := _label("", 22, Color(1, 1, 1))
		cd.set_anchors_preset(Control.PRESET_FULL_RECT)
		cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(cd)
		var short := _label(String(ab["name"]).split(" ")[0], 9, Color(1, 1, 1, 0.85))
		short.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		short.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		short.offset_top = -14
		b.add_child(short)
		action_slots.append({"aid": aid, "button": b, "cd": cd, "sweep": sweep})


func _ability_tooltip(u: Unit, aid: String) -> String:
	var ab: Dictionary = GameData.ABILITIES[aid]
	var parts: Array = []
	if float(ab["cost"]) > 0.0:
		parts.append("%d %s" % [int(ab["cost"]), u.resource_type])
	parts.append("Instant" if float(ab["cast"]) <= 0.0 else "%.1fs cast" % float(ab["cast"]))
	if float(ab["cd"]) > 0.0:
		parts.append("%ds cooldown" % int(ab["cd"]))
	if not ab["gcd"]:
		parts.append("off-GCD")
	if float(ab["range"]) > 0.0:
		parts.append("%dm range" % int(ab["range"]))
	if ab["target"] == "ground":
		parts.append("%dm radius · click to place" % int(ab.get("radius", 0.0)))
	return "%s\n%s\n%s" % [ab["name"], " · ".join(parts), ab["desc"]]


func _build_meters() -> void:
	var p := _panel()
	_place(p, 1, 0, 1, 0, -270, 16, -16, 16)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	fight_ui.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	v.add_child(top)
	timer_label = _label("", 15, Color(1, 0.9, 0.7))
	top.add_child(timer_label)
	latency_label = _label("", 15)
	latency_label.add_theme_font_override("font", UITheme.title_font())
	latency_label.tooltip_text = "Latency to the realm (round trip)"
	latency_label.mouse_filter = Control.MOUSE_FILTER_PASS
	latency_label.visible = Net.is_client()
	top.add_child(latency_label)
	meter_label = _label("", 13)
	meter_label.custom_minimum_size = Vector2(236, 0)
	v.add_child(meter_label)


func _build_sheet() -> void:
	sheet = PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", UITheme.parchment())
	_place(sheet, 1, 0.5, 1, 0.5, -320, -200, -16, 200)
	sheet.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sheet.visible = false
	fight_ui.add_child(sheet)
	sheet_label = _label("", 15, UITheme.INK)
	sheet_label.add_theme_constant_override("outline_size", 0)
	sheet.add_child(sheet_label)


func _build_end_panel() -> void:
	end_panel = PanelContainer.new()
	_place(end_panel, 0.5, 0.5, 0.5, 0.5, -300, -220, 300, 220)
	end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	end_panel.visible = false
	fight_ui.add_child(end_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	end_panel.add_child(v)
	end_title = UITheme.title("", 40)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(end_title)
	v.add_child(UITheme.divider())
	end_body = _label("", 14)
	v.add_child(end_body)
	end_buttons = HBoxContainer.new()
	end_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	end_buttons.add_theme_constant_override("separation", 12)
	v.add_child(end_buttons)


func _end_button(text: String, sig: Signal) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): sig.emit())
	end_buttons.add_child(b)


## Solo: Retry / Change class. Party leader: Retry / Back to Outpost. Members wait for the leader.
func configure_end_buttons() -> void:
	for c in end_buttons.get_children():
		c.queue_free()
	if not Net.is_net():
		_end_button("Retry", retry_requested)
		_end_button("Change class", menu_requested)
	elif Net.is_leader():
		_end_button("Retry", retry_requested)
		_end_button("Back to Outpost", lobby_requested)
		_end_button("Leave party", leave_requested)
	else:
		var l := _label("Waiting for the party leader...", 14, UITheme.GOLD_DIM)
		end_buttons.add_child(l)
		_end_button("Leave party", leave_requested)


# ------------------------------------------------------------------ buff / debuff bars

const KIND_COLORS := {
	"buff": Color(0.85, 0.7, 0.3), "magic": Color(0.3, 0.6, 1.0), "poison": Color(0.3, 0.9, 0.2),
	"fire": Color(1.0, 0.5, 0.1), "physical": Color(0.9, 0.15, 0.1),
}
var _icon_cache := {}


func _make_aura_bar(icon_size: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	h.set_meta("size", icon_size)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _aura_icon(id: String) -> Texture2D:
	if not _icon_cache.has(id):
		var path := "res://assets/icons/%s.svg" % id
		_icon_cache[id] = load(path) if ResourceLoader.exists(path) else null
	return _icon_cache[id]


## Shows one icon per aura (debuffs first) with a coloured border, stacks and time left.
func _update_aura_bar(bar: HBoxContainer, u: Unit, debuffs_only := false, max_icons := 10) -> void:
	var list: Array = []
	for a in u.auras:
		var def: Dictionary = a["def"]
		if debuffs_only and not def.get("debuff", false):
			continue
		list.append(a)
	list.sort_custom(func(x, y): return int(x["def"].get("debuff", false)) > int(y["def"].get("debuff", false)))
	if list.size() > max_icons:
		list.resize(max_icons)
	var sz: float = bar.get_meta("size")
	while bar.get_child_count() < list.size():
		bar.add_child(_make_aura_tile(sz))
	for i in bar.get_child_count():
		var tile: Control = bar.get_child(i)
		if i >= list.size():
			tile.visible = false
			continue
		tile.visible = true
		var a: Dictionary = list[i]
		var def: Dictionary = a["def"]
		var kind: String = def.get("kind", "debuff" if def.get("debuff", false) else "buff")
		var border: Panel = tile.get_meta("border")
		var sb := border.get_theme_stylebox("panel") as StyleBoxFlat
		var kc: Color = KIND_COLORS.get(kind, Color(0.9, 0.15, 0.1))
		if sb.border_color != kc:
			var nsb := sb.duplicate() as StyleBoxFlat
			nsb.border_color = kc
			border.add_theme_stylebox_override("panel", nsb)
		(tile.get_meta("icon") as TextureRect).texture = _aura_icon(def.get("icon", ""))
		var stacks := int(a.get("stacks", 1))
		(tile.get_meta("stacks") as Label).text = str(stacks) if stacks > 1 else ""
		var rem := float(a.get("remaining", 0.0))
		var tl := tile.get_meta("time") as Label
		if rem > 999.0:
			tl.text = ""
		elif rem >= 60.0:
			tl.text = "%dm" % int(rem / 60.0)
		elif rem >= 10.0:
			tl.text = "%d" % int(rem)
		else:
			tl.text = "%.1f" % rem if rem < 3.0 else "%d" % ceili(rem)
		tl.add_theme_color_override("font_color", Color(1, 0.4, 0.3) if rem < 3.0 else Color(1, 1, 0.85))
		tile.tooltip_text = "%s\n%s" % [def["name"], def.get("desc", "")]
		# Gentle pulse on debuffs that are about to matter
		tile.modulate.a = 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() / 160.0)) if rem < 1.5 and rem < 999.0 else 1.0


func _make_aura_tile(sz: float) -> Control:
	var tile := Control.new()
	tile.custom_minimum_size = Vector2(sz, sz + (12 if sz >= 24 else 0))
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	var border := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.8)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.85, 0.7, 0.3)
	border.add_theme_stylebox_override("panel", sb)
	border.position = Vector2.ZERO
	border.size = Vector2(sz, sz)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(border)
	var icon := TextureRect.new()
	icon.position = Vector2(2, 2)
	icon.size = Vector2(sz - 4, sz - 4)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(icon)
	var stacks := _label("", int(sz * 0.42))
	stacks.position = Vector2(sz * 0.5, sz * 0.45)
	stacks.add_theme_font_override("font", UITheme.title_font())
	tile.add_child(stacks)
	var time := _label("", 10 if sz >= 24 else 8)
	time.add_theme_font_override("font", UITheme.title_font())
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time.position = Vector2(0, sz - 2 if sz >= 24 else sz * 0.45)
	time.size = Vector2(sz, 14)
	tile.add_child(time)
	tile.set_meta("border", border)
	tile.set_meta("icon", icon)
	tile.set_meta("stacks", stacks)
	time.visible = sz >= 24  # tiny party icons show only the icon and border
	tile.set_meta("time", time)
	return tile


# ------------------------------------------------------------------ chat

func _build_chat() -> void:
	chat_panel = _panel()
	_place(chat_panel, 0, 1, 0, 1, 16, -250, 400, -16)
	chat_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chat_panel.visible = Net.is_net()
	fight_ui.add_child(chat_panel)
	var v := VBoxContainer.new()
	chat_panel.add_child(v)
	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	chat_log.custom_minimum_size = Vector2(360, 150)
	chat_log.add_theme_font_size_override("normal_font_size", 15)
	chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(chat_log)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Press Enter to chat"
	chat_input.text_submitted.connect(func(t: String):
		if t.strip_edges() != "":
			Net.request("chat", [t])
		chat_input.text = ""
		chat_input.release_focus())
	v.add_child(chat_input)


func _on_chat(from: String, text: String, c: Color) -> void:
	if chat_log == null or not is_instance_valid(chat_log):
		return
	if from == "":
		chat_log.append_text("[color=#%s][i]%s[/i][/color]\n" % [c.to_html(false), text])
	else:
		chat_log.append_text("[color=#e8c27a][%s][/color] [color=#%s]%s[/color]\n" % [from, c.to_html(false), text])


func _unhandled_key_input(event: InputEvent) -> void:
	if fight_ui == null or training:
		return  # in the Outpost, Esc and Enter belong to the Outpost
	var k := event as InputEventKey
	if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		# Esc: leave chat > back out of the menu > cancel ground targeting (controller) > open the menu
		if chat_input != null and chat_input.has_focus():
			chat_input.release_focus()
		elif menu_open:
			if menu_confirm.visible:
				_show_menu_page(false)
			else:
				set_menu_open(false)
		elif controller != null and controller.ground_aid != "":
			return
		else:
			set_menu_open(true)
		get_viewport().set_input_as_handled()
		return
	if chat_input == null or not chat_panel.visible or menu_open:
		return
	if k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and not chat_input.has_focus():
		chat_input.grab_focus()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ Esc game menu

func _build_game_menu() -> void:
	game_menu = ColorRect.new()
	(game_menu as ColorRect).color = Color(0, 0, 0, 0.45)
	game_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_menu.mouse_filter = Control.MOUSE_FILTER_STOP  # nothing behind the menu gets clicks
	game_menu.visible = false
	fight_ui.add_child(game_menu)
	var p := PanelContainer.new()
	_place(p, 0.5, 0.5, 0.5, 0.5, -200, -165, 200, 165)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	game_menu.add_child(p)
	var stack := VBoxContainer.new()
	p.add_child(stack)
	var t := UITheme.title("Game Menu", 30)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(t)
	stack.add_child(UITheme.divider())
	menu_main = VBoxContainer.new()
	menu_main.add_theme_constant_override("separation", 10)
	stack.add_child(menu_main)
	menu_main.add_child(_menu_button("Resume", func(): set_menu_open(false)))
	var settings := _menu_button("Settings", func(): pass)
	settings.disabled = true
	settings.tooltip_text = "Coming soon"
	menu_main.add_child(settings)
	var soon := _label("Settings — coming soon", 11, UITheme.GOLD_DIM)
	soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_main.add_child(soon)
	surrender_btn = _menu_button("Surrender", _ask_surrender)
	menu_main.add_child(surrender_btn)
	menu_main.add_child(_menu_button("Quit Game", _ask_quit))
	menu_confirm = VBoxContainer.new()
	menu_confirm.add_theme_constant_override("separation", 14)
	menu_confirm.visible = false
	stack.add_child(menu_confirm)
	confirm_text = _label("", 14)
	confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_text.custom_minimum_size = Vector2(340, 0)
	menu_confirm.add_child(confirm_text)
	confirm_yes = _menu_button("Yes", func():
		var cb := _confirm_action
		set_menu_open(false)
		if cb.is_valid():
			cb.call())
	menu_confirm.add_child(confirm_yes)
	menu_confirm.add_child(_menu_button("Cancel", func(): _show_menu_page(false)))


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func set_menu_open(on: bool) -> void:
	if game_menu == null:
		return
	game_menu.visible = on
	_show_menu_page(false)
	if controller != null:
		controller.blocked = on
		if on:
			controller._rmb = false
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh_menu()


func _show_menu_page(confirm: bool) -> void:
	menu_main.visible = not confirm
	menu_confirm.visible = confirm
	if not confirm:
		_refresh_menu()


func _refresh_menu() -> void:
	var over: bool = world == null or world.finished
	surrender_btn.disabled = over
	if not Net.is_net():
		surrender_btn.text = "Surrender"
		surrender_btn.tooltip_text = "Give up this attempt and pick a class again."
	elif Net.vote_state.get("active", false):
		surrender_btn.text = "Vote Yes to Surrender" if not Net.i_voted() else "Surrender Vote Running"
		surrender_btn.disabled = over or Net.i_voted()
		surrender_btn.tooltip_text = ""
	else:
		surrender_btn.text = "Vote to Surrender"
		surrender_btn.tooltip_text = "Ask the party to give up. Most connected players must agree."


func _confirm(text: String, yes_text: String, action: Callable) -> void:
	confirm_text.text = text
	confirm_yes.text = yes_text
	_confirm_action = action
	_show_menu_page(true)


func _ask_surrender() -> void:
	if not Net.is_net():
		_confirm("Give up on Vyrathax and return to class selection?", "Surrender", func(): surrender_requested.emit())
	elif Net.vote_state.get("active", false):
		set_menu_open(false)
		Net.request("vote", [true])
	else:
		_confirm("Start a vote to surrender?\nIf most of the party agrees within %d seconds, everyone returns to the Outpost." % int(Net.VOTE_TIME),
			"Start Vote", func(): surrender_requested.emit())


func _ask_quit() -> void:
	var text := "Quit Emberfall?"
	if Net.is_net():
		text += "\nA bot takes over your hero. Log back in to rejoin while the raid lasts."
	_confirm(text, "Quit Game", func(): quit_requested.emit())


# ------------------------------------------------------------------ surrender vote banner

func _build_vote_panel() -> void:
	vote_panel = _panel()
	_place(vote_panel, 0.5, 0, 0.5, 0, -260, 128, 260, 128)
	vote_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vote_panel.visible = false
	vote_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	fight_ui.add_child(vote_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	vote_panel.add_child(v)
	vote_label = _label("", 14, Color(1, 0.9, 0.7))
	vote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vote_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(vote_label)
	vote_buttons = HBoxContainer.new()
	vote_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vote_buttons.add_theme_constant_override("separation", 12)
	v.add_child(vote_buttons)
	for opt in [["Yes, surrender", true], ["No, fight on", false]]:
		var b := Button.new()
		b.text = opt[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(170, 36)
		var yes: bool = opt[1]
		b.pressed.connect(func(): Net.request("vote", [yes]))
		vote_buttons.add_child(b)
	if not Net.vote_state.is_empty():
		_on_vote(Net.vote_state)


func _on_vote(state: Dictionary) -> void:
	if vote_panel == null or not is_instance_valid(vote_panel):
		return
	if state.get("active", false):
		vote_panel.visible = true
		var voted := Net.i_voted()
		vote_buttons.visible = not voted
		vote_label.text = "%s wants to surrender  ·  Yes %d  ·  No %d  ·  need %d of %d  ·  %ds%s" % [
			state["by"], state["yes"], state["no"], state["needed"], state["total"], ceili(float(state["time"])),
			"\nYou voted. Waiting for the others..." if voted else ""]
		_vote_result_t = 0.0
	else:
		vote_buttons.visible = false
		var r: String = state.get("result", "")
		vote_panel.visible = r != ""
		vote_label.text = r
		_vote_result_t = 4.0
	if menu_open and menu_main.visible:
		_refresh_menu()


# ------------------------------------------------------------------ events

func _on_emote(text: String) -> void:
	emote_label.text = text
	_emote_t = 4.0


func _on_message(text: String, c: Color) -> void:
	msg_label.text = text
	msg_label.add_theme_color_override("font_color", c)
	_msg_t = 3.5


func _on_error(text: String) -> void:
	error_label.text = text
	_error_t = 1.4


func _on_fight_ended(won: bool) -> void:
	configure_end_buttons()
	end_panel.visible = true
	end_title.text = "VICTORY!" if won else "DEFEAT"
	end_title.add_theme_color_override("font_color", Color(1, 0.85, 0.3) if won else Color(1, 0.35, 0.3))
	var lines: Array = ["Fight time: %s   ·   Boss HP left: %.1f%%" % [RaidWorld.fmt_time(world.fight_time),
		world.boss.hp_pct() * 100.0], "", _meter_text(12)]
	if not world.death_log.is_empty():
		lines.append("Deaths: " + ", ".join(world.death_log))
	end_body.text = "\n".join(lines)


# ------------------------------------------------------------------ update

## Tanks: a warning as their taunt runs out (or when the dragon is loose on someone else).
func _update_taunt_warning() -> void:
	var me: Unit = world.player
	var boss: Unit = world.boss
	taunt_label.text = ""
	if me == null or me.role != GameData.ROLE_TANK or not me.alive or not world.combat_active or not boss.alive \
			or boss.untargetable:
		return
	if boss.is_taunted() and boss.forced_target == me:
		if boss.forced_target_time <= 5.0:
			taunt_label.text = "Taunt fading in %d — taunt again (3)!" % ceili(boss.forced_target_time)
	elif not boss.is_taunted() and boss.target != null and boss.target != me:
		taunt_label.text = "Vyrathax is on %s — taunt (3)!" % boss.target.unit_name
	taunt_label.modulate.a = 0.65 + 0.35 * sin(Time.get_ticks_msec() / 120.0) if taunt_label.text != "" else 1.0


func _process(delta: float) -> void:
	if world == null or fight_ui == null:
		return
	if training:
		_process_training(delta)
		return
	_emote_t -= delta
	_msg_t -= delta
	if _vote_result_t > 0.0:
		_vote_result_t -= delta
		if _vote_result_t <= 0.0 and not Net.vote_state.get("active", false):
			vote_panel.visible = false
	_error_t -= delta
	emote_label.modulate.a = clampf(_emote_t, 0.0, 1.0)
	msg_label.modulate.a = clampf(_msg_t, 0.0, 1.0)
	error_label.modulate.a = clampf(_error_t, 0.0, 1.0)
	countdown_label.visible = not world.combat_active
	if not world.started:
		countdown_label.text = "Vyrathax arrives in %d" % ceili(world.countdown)
	elif world.player.role == GameData.ROLE_TANK and not (world.player.brain is BotBrain):
		countdown_label.text = "You are the tank — taunt (3) the moment he lands!"
	else:
		countdown_label.text = ""
	_update_taunt_warning()
	_update_boss()
	_update_unit_frame(player_ui, world.player)
	var t: Unit = world.player.target
	target_ui["panel"].visible = t != null
	if t != null:
		_update_unit_frame(target_ui, t)
	_update_party()
	_update_action_bar()
	_update_cast_bar()
	timer_label.text = "Time %s   ·   Enrage %s" % [RaidWorld.fmt_time(world.fight_time),
		RaidWorld.fmt_time(float(GameData.BOSS["enrage_time"]))]
	meter_label.text = _meter_text(5)
	_lat_t -= delta
	if _lat_t <= 0.0 and latency_label.visible:
		_lat_t = 0.5
		var lt: Array = Net.latency_text()
		latency_label.text = lt[0]
		latency_label.add_theme_color_override("font_color", lt[1])
	if sheet.visible:
		sheet_label.text = _sheet_text(world.player)


func _process_training(delta: float) -> void:
	if not fight_ui.visible or not is_instance_valid(world.player):
		return
	_msg_t -= delta
	_error_t -= delta
	msg_label.modulate.a = clampf(_msg_t, 0.0, 1.0)
	error_label.modulate.a = clampf(_error_t, 0.0, 1.0)
	_update_unit_frame(player_ui, world.player)
	var t: Unit = world.player.target
	target_ui["panel"].visible = t != null
	if t != null:
		_update_unit_frame(target_ui, t)
	_update_action_bar()
	_update_cast_bar()
	if sheet.visible:
		sheet_label.text = _sheet_text(world.player)


func _update_boss() -> void:
	var b: Unit = world.boss
	_update_aura_bar(boss_auras, b)
	boss_bar.value = b.hp_pct()
	boss_text.text = "%s / %s  (%.1f%%)" % [_k(b.hp), _k(b.max_hp), b.hp_pct() * 100.0]
	var ph: int = world.boss_phase()
	var names := ["Approaching", "Phase 1 — The Tyrant Wakes", "Phase 2 — Sky of Ash (immune, kill the whelps!)",
		"Phase 3 — Final Inferno"]
	phase_label.text = names[ph]
	if b.has_aura("enraged"):
		phase_label.text += "   ·   ENRAGED"
	if ph == 2:
		phase_label.text += "   lands in %ds" % ceili(float(GameData.BOSS["air_duration"]) - world.boss_air_time())
	boss_cast.visible = b.is_casting()
	if b.is_casting():
		boss_cast.value = 1.0 - float(b.casting["remaining"]) / float(b.casting["total"])
		var tag := "  (INTERRUPT!)" if b.casting.get("interruptible", false) else ""
		boss_cast_text.text = b.casting["name"] + tag
		_set_fill(boss_cast, Color(0.3, 0.8, 1.0) if tag != "" else Color(1, 0.55, 0.1))


func _update_unit_frame(f: Dictionary, u: Unit) -> void:
	var title := u.unit_name
	if u.class_id != "":
		title += "  —  " + String(GameData.CLASSES[u.class_id]["name"])
	f["name"].text = title
	f["name"].add_theme_color_override("font_color", u.color)
	f["hp"].value = u.hp_pct()
	var absorb := u.total_absorb()
	var hp_txt := "%s / %s" % [_k(u.hp), _k(u.max_hp)]
	if absorb > 0.0:
		hp_txt += "  +%s shield" % _k(absorb)
	f["hp_t"].text = hp_txt if u.alive else "DEAD"
	_set_fill(f["hp"], Color(0.2, 0.8, 0.3) if u.team == "party" else Color(0.8, 0.2, 0.15))
	f["res"].visible = u.max_resource > 0.0
	if u.max_resource > 0.0:
		f["res"].value = u.resource_pct()
		_set_fill(f["res"], RES_COLORS.get(u.resource_type, Color.GRAY))
		var rt := "%d / %d %s" % [int(u.resource), int(u.max_resource), u.resource_type]
		if u.resource_type == "energy":
			rt += "   " + "●".repeat(u.combo) + "○".repeat(5 - u.combo)
		f["res_t"].text = rt
	f["cast"].visible = u.is_casting()
	if u.is_casting():
		f["cast"].value = 1.0 - float(u.casting["remaining"]) / float(u.casting["total"])
		f["cast_t"].text = u.casting["name"]
	_update_aura_bar(f["auras"], u)


func _aura_text(u: Unit) -> String:
	var parts: Array = []
	for a in u.auras:
		var s: String = a["def"]["name"]
		if int(a["stacks"]) > 1:
			s += " x%d" % int(a["stacks"])
		if float(a["remaining"]) < 100.0:
			s += " %ds" % ceili(float(a["remaining"]))
		parts.append(s)
	return " · ".join(parts)


func _update_party() -> void:
	var boss: Unit = world.boss
	for r in party_rows:
		var u: Unit = r["unit"]
		r["hp"].value = u.hp_pct()
		var tag := ""
		if boss.target == u and boss.alive:
			tag = " [AGGRO]"
		if u == world.player.target:
			tag += " <"
		var role_tag: String = {"tank": "T", "healer": "H", "melee": "D", "ranged": "D"}.get(u.role, "")
		r["hp_t"].text = "%s %s  %s%s" % [role_tag, u.unit_name, ("%d%%" % int(u.hp_pct() * 100)) if u.alive else "DEAD", tag]
		r["res"].value = u.resource_pct()
		_update_aura_bar(r["auras"], u, false, 8)
		r["button"].modulate = Color(1, 1, 1) if u.alive else Color(0.5, 0.5, 0.5)


func _update_action_bar() -> void:
	var u: Unit = world.player
	for s in action_slots:
		var aid: String = s["aid"]
		var ab: Dictionary = GameData.ABILITIES[aid]
		var cd := u.cooldown_left(aid)
		var b: Button = s["button"]
		if cd > 0.0:
			s["cd"].text = str(ceili(cd)) if cd >= 1.0 else "%.1f" % cd
		else:
			s["cd"].text = ""
		var frac := 0.0
		if cd > 0.0:
			frac = cd / maxf(0.01, float(ab["cd"]))
		elif ab["gcd"] and u.gcd_remaining > 0.0:
			frac = u.gcd_remaining / maxf(0.01, u.gcd_total)
		s["sweep"].anchor_top = 1.0 - clampf(frac, 0.0, 1.0)
		var m := Color(1, 1, 1)
		if not u.alive:
			m = Color(0.45, 0.45, 0.45)
		elif u.resource < float(ab["cost"]):
			m = Color(0.5, 0.6, 1.0)
		elif ab["target"] == "enemy":
			var t := u.target if (u.target != null and u.target.team != u.team) else null
			if t != null and not u.in_range(t, ab["range"]):
				m = Color(1, 0.45, 0.45)
		b.modulate = m


func _update_cast_bar() -> void:
	var u: Unit = world.player
	cast_bar.visible = u.is_casting()
	if u.is_casting():
		cast_bar.value = 1.0 - float(u.casting["remaining"]) / float(u.casting["total"])
		cast_text.text = "%s  %.1fs" % [u.casting["name"], float(u.casting["remaining"])]


func _meter_text(max_rows: int) -> String:
	var t := maxf(world.fight_time, 1.0)
	var dmg_rows: Array = []
	for u in world.party_all():
		dmg_rows.append([u, float(world.damage_done.get(u, 0.0))])
	dmg_rows.sort_custom(func(a, b): return a[1] > b[1])
	var lines: Array = ["Damage (DPS)"]
	for i in mini(max_rows, dmg_rows.size()):
		lines.append("  %-10s %7s  %5d" % [dmg_rows[i][0].unit_name, _k(dmg_rows[i][1]), int(dmg_rows[i][1] / t)])
	var heal_rows: Array = []
	for u in world.party_all():
		var hv := float(world.healing_done.get(u, 0.0))
		if hv > 0.0:
			heal_rows.append([u, hv])
	heal_rows.sort_custom(func(a, b): return a[1] > b[1])
	lines.append("Healing (HPS)")
	for i in mini(3, heal_rows.size()):
		lines.append("  %-10s %7s  %5d" % [heal_rows[i][0].unit_name, _k(heal_rows[i][1]), int(heal_rows[i][1] / t)])
	var boss: Unit = world.boss
	if world.combat_active and max_rows <= 5:
		if boss.is_taunted():
			lines.append("Taunt  %s  %ds" % [boss.forced_target.unit_name, ceili(boss.forced_target_time)])
		else:
			lines.append("No taunt — top damage has aggro")
		var top := boss.top_damage_value()
		if top > 0.0:
			lines.append("Aggro (damage to boss)")
			var th: Array = []
			for u in boss.damage_by:
				if u.alive:
					th.append([u, float(boss.damage_by[u])])
			th.sort_custom(func(a, b): return a[1] > b[1])
			for i in mini(3, th.size()):
				lines.append("  %-10s %3d%%" % [th[i][0].unit_name, int(th[i][1] / top * 100.0)])
	return "\n".join(lines)


func _sheet_text(u: Unit) -> String:
	var s := u.base_stats
	var c: Dictionary = GameData.CLASSES[u.class_id]
	var phys_red := u.armor / (u.armor + 4000.0) * 100.0
	return "\n".join([
		"%s — %s" % [c["name"], String(c["role"]).capitalize()],
		"",
		"PRIMARY",
		"  Strength     %d" % int(s["str"]),
		"  Agility      %d" % int(s["agi"]),
		"  Intellect    %d" % int(s["int"]),
		"  Stamina      %d" % int(s["sta"]),
		"  Spirit       %d" % int(s["spi"]),
		"",
		"DERIVED",
		"  Max HP         %d" % int(u.max_hp),
		"  Attack Power   %d" % int(u.attack_power),
		"  Spell Power    %d" % int(u.spell_power),
		"  Crit (phys)    %.1f%%" % u.crit_phys,
		"  Crit (spell)   %.1f%%" % u.crit_spell,
		"  Haste          %.1f%%" % u.get_haste(),
		"  Dodge          %.1f%%" % u.dodge,
		"  Armor          %d  (-%.0f%% phys)" % [int(u.armor), phys_red],
		"  Mana regen     %.1f / s" % u.mana_regen,
	])


static func _k(v: float) -> String:
	if v >= 10000.0:
		return "%.1fk" % (v / 1000.0)
	return str(int(v))
