class_name PlayerController
extends Node3D
## Keyboard + mouse control of the player's Unit, plus the orbit camera.

signal error_message(text: String)
signal toggle_character_sheet
signal ground_mode(text: String)

var world  # RaidWorld
var unit: Unit
var autoplay := false
var camera: Camera3D
var ring: MeshInstance3D

var yaw := 0.0
var pitch := 0.6
var dist := 14.0
var top_down := false
var _rmb := false
var _trauma := 0.0
var ground_aid := ""
var blocked := false  # the Esc menu is open
var reticle: MeshInstance3D
var reticle_mat: StandardMaterial3D
var _cine := 0.0  # 0..1: how much the camera looks toward the dragon while it flies in


func setup(w, u: Unit, auto: bool) -> void:
	world = w
	unit = u
	autoplay = auto
	if not autoplay:
		unit.brain = self
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 400.0
	add_child(camera)
	camera.make_current()
	world.shake.connect(func(v: float): _trauma = minf(1.0, _trauma + v))
	ring = Models.make_target_ring()
	ring.visible = false
	add_child(ring)
	reticle = Vfx.rune_decal(Color(0.45, 1.0, 0.55), 1.0, 0.95)
	reticle_mat = reticle.material_override as StandardMaterial3D
	reticle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	reticle.visible = false
	add_child(reticle)
	_update_camera()


## Called by RaidWorld every tick (as the player's brain).
func tick(delta: float) -> void:
	if autoplay or blocked or not unit.alive or unit.is_dashing():
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return  # typing in chat
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		input.x += 1.0
	if input != Vector2.ZERO:
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var rgt := Vector3(cos(yaw), 0, -sin(yaw))
		var dir := (fwd * -input.y + rgt * input.x).normalized()
		unit.move_toward_point(unit.flat_pos() + dir * 5.0, delta, GameData.MOVE_SPEED)
	elif unit.target != null and unit.target != unit:
		unit.face_toward(unit.target)


func _process(delta: float) -> void:
	if unit == null:
		return
	var tg := unit.target
	if tg != null and ((not tg.alive and tg.team != unit.team) or tg.untargetable):
		unit.target = null
	if ground_aid != "":
		if not unit.alive:
			_cancel_ground()
		else:
			var p := _mouse_ground()
			var ab: Dictionary = GameData.ABILITIES[ground_aid]
			var r: float = ab.get("radius", 6.0)
			reticle.visible = true
			reticle.position = Vector3(p.x, 0.07, p.z)
			reticle.scale = Vector3(r, 1, r)
			reticle.rotation.y += delta * 1.2
	_trauma = maxf(0.0, _trauma - _delta_guard(delta) * 1.6)
	var arriving: bool = world is RaidWorld and world.boss != null and world.boss_phase() == 0
	_cine = move_toward(_cine, 1.0 if arriving else 0.0, _delta_guard(delta) * 0.8)
	_update_camera()
	_update_ring()


func _delta_guard(d: float) -> float:
	return clampf(d, 0.0, 0.1)


func _update_camera() -> void:
	var focus := unit.position + Vector3(0, 1.6, 0)
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	camera.position = focus + off
	var look := global_transform * focus  # focus is local (the Outpost sits off-origin)
	if _cine > 0.0:
		# Vyrathax flying in: lean the view up toward him (eased), then hand it back for the fight
		var e := _cine * _cine * (3.0 - 2.0 * _cine)
		look = look.lerp(world.boss.global_position + Vector3(0, 3.0, 0), e * 0.6)
	camera.look_at(look, Vector3.UP)
	if _trauma > 0.0:
		var s := _trauma * _trauma
		camera.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.35 * s
		camera.rotation.z += randf_range(-1, 1) * 0.03 * s


func _update_ring() -> void:
	var t := unit.target
	if t == null:
		ring.visible = false
		return
	ring.visible = true
	var r := t.radius + 0.4
	ring.scale = Vector3(r, 0.05, r)
	ring.position = Vector3(t.position.x, 0.08, t.position.z)
	var m := ring.material_override as StandardMaterial3D
	m.albedo_color = Color(1, 0.3, 0.25) if t.team == "enemy" else Color(0.3, 1, 0.4)


func _unhandled_input(event: InputEvent) -> void:
	if blocked:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if ground_aid != "" and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_cast_ground(_mouse_ground())
			return
		if ground_aid != "" and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_ground()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_rmb = mb.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _rmb else Input.MOUSE_MODE_VISIBLE
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			dist = maxf(5.0, dist - 1.5)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			dist = minf(40.0, dist + 1.5)
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_pick(mb.position)
	elif event is InputEventMouseMotion and _rmb:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.006
		pitch = clampf(pitch + mm.relative.y * 0.005, 0.08, 1.35)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_7:
			use_slot(k - KEY_1)
		elif k == KEY_TAB:
			_cycle_enemy()
		elif k == KEY_SPACE:
			if not autoplay:
				unit.jump()
		elif k >= KEY_F1 and k <= KEY_F5:
			var party: Array = world.party_all()
			var idx := k - KEY_F1
			if idx < party.size():
				set_target(party[idx])
		elif k == KEY_ESCAPE:
			if ground_aid != "":
				_cancel_ground()
			else:
				set_target(null)
		elif k == KEY_C:
			toggle_character_sheet.emit()
		elif k == KEY_V:
			# Toggle top-down (overhead) and close behind-the-back camera
			top_down = not top_down
			pitch = 1.05 if top_down else 0.4
			dist = 24.0 if top_down else 12.0


func use_slot(i: int) -> void:
	if autoplay or not unit.alive or i >= unit.ability_ids.size():
		return
	var aid: String = unit.ability_ids[i]
	var ab: Dictionary = GameData.ABILITIES[aid]
	if ab["target"] == "ground":
		if ground_aid == aid:
			_cast_ground(_mouse_ground())  # press the key again to cast at the cursor
			return
		var check := unit.can_use(aid, null, unit.flat_pos())
		if check != "" and check != "GCD":
			error_message.emit(check)
			return
		ground_aid = aid
		ground_mode.emit("Click the ground to place %s  ·  right-click / Esc to cancel" % ab["name"])
		return
	_cancel_ground()
	var tgt := unit.target
	if ab["target"] == "enemy" and (tgt == null or tgt.team == unit.team):
		tgt = _nearest_enemy()
		set_target(tgt)
	var err := _use(aid, tgt, null)
	if err != "" and err != "GCD":
		error_message.emit(err)


## Changes our target and tells the server when we are a network client.
func set_target(u: Unit) -> void:
	unit.target = u
	if Net.is_client():
		Net.send_target(u)


## Uses an ability: locally (solo / host) or by asking the server (client).
func _use(aid: String, tgt: Unit, point) -> String:
	if not Net.is_client():
		return unit.use_ability(aid, tgt, point)
	var err := unit.can_use(aid, tgt, point)
	if err == "":
		Net.send_ability(aid, tgt if tgt != null else unit.target, point)
		var ab: Dictionary = GameData.ABILITIES[aid]
		if ab["gcd"]:
			unit.gcd_remaining = unit.gcd_total
	return err


func select(u: Unit) -> void:
	if u != null and (u.alive or u.team == unit.team):
		set_target(u)


## Mouse ray onto the ground, clamped to the pending skill's range.
func _mouse_ground() -> Vector3:
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var p := unit.flat_pos()
	if dir.y < -0.001:
		p = from + dir * (-from.y / dir.y)
	p.y = 0.0
	var ab: Dictionary = GameData.ABILITIES.get(ground_aid, {})
	var rng: float = ab.get("range", 30.0)
	var off := p - unit.flat_pos()
	if off.length() > rng:
		p = unit.flat_pos() + off.normalized() * rng
	return world.clamp_to_arena(p)


func _cast_ground(p: Vector3) -> void:
	if ground_aid == "":
		return
	var err := _use(ground_aid, null, p)
	if err == "GCD":
		return  # keep aiming, try again
	if err != "":
		error_message.emit(err)
	_cancel_ground()


func _cancel_ground() -> void:
	if ground_aid == "":
		return
	ground_aid = ""
	reticle.visible = false
	ground_mode.emit("")


func _nearest_enemy() -> Unit:
	var best: Unit = null
	for e in world.enemies_alive():
		if best == null or unit.distance_to_unit(e) < unit.distance_to_unit(best):
			best = e
	return best


func _cycle_enemy() -> void:
	var foes: Array = world.enemies_alive()
	if foes.is_empty():
		return
	foes.sort_custom(func(a, b): return unit.distance_to_unit(a) < unit.distance_to_unit(b))
	var idx := foes.find(unit.target)
	set_target(foes[(idx + 1) % foes.size()])


func _pick(screen_pos: Vector2) -> void:
	var best: Unit = null
	var best_d := INF
	for u in world.units:
		if not u.alive or u.untargetable:
			continue
		var p: Vector3 = u.position + Vector3(0, 3.0 if u.is_boss else 1.0, 0)
		if camera.is_position_behind(p):
			continue
		var d := camera.unproject_position(p).distance_to(screen_pos)
		var thresh := 160.0 if u.is_boss else 45.0
		if d < thresh and d < best_d:
			best = u
			best_d = d
	if best != null:
		set_target(best)
