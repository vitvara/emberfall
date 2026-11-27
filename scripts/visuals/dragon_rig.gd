class_name DragonRig
extends Node3D
## Fire dragon with procedural animation, used for the boss (scale 1) and the whelps (small, always flying).
##
## Skeleton: the pelvis is the pivot, so the dragon can rear up on its hind legs (roar, inhale, claw).
## A five-segment S-neck carries a horned head with a hinged jaw; the wings have an arm, a wrist and four
## fingers, and their membranes are rebuilt every frame from the bone positions so they really fold and
## stretch; digitigrade hind legs, clawed front legs and a ten-segment tail.
## Motion: breathing and a sinuous idle, a four-legged walk with weight shift and dust at each step,
## smoothed turning that the neck leads, powerful down-stroke flaps in the air, and one-shot actions:
## roar (rear-up), breath (inhale then a sweeping fire stream), claw, bite, spit, tail whip, take-off,
## landing and a collapse on death.

var unit: Unit
var is_whelp := false

var root: Node3D
var pelvis: Node3D
var chest: Node3D
var _torso: MeshInstance3D
var _torso_rings: Array = []   # [node, centre (node-local), half width, half height]
var _swell := 1.0
var neck: Array = []
var head: Node3D
var jaw: Node3D
var mouth: Node3D
var mouth_glow: MeshInstance3D
var mouth_mat: StandardMaterial3D
var throat_mat: StandardMaterial3D
var glow_mat: StandardMaterial3D
var eye_mat: StandardMaterial3D
var wings: Array = []      # {side, shoulder, elbow, wrist, fingers, tips, anchors, mesh}
var arms: Array = []       # front legs {side, shoulder, elbow, wrist}
var legs: Array = []       # hind legs {side, hip, knee, ankle, foot}
var tail: Array = []
var nostrils: Array = []
var blob: MeshInstance3D
var membrane_mat: StandardMaterial3D
var skin_mats: Array = []      # dragon_skin ShaderMaterials; their "heat" follows the body glow
static var _skin_shader: Shader

var _t := 0.0
var _phase := 0.0
var _speed := 0.0
var _last_flat := Vector3.ZERO
var _vis_yaw := 0.0
var _turn := 0.0
var _action := ""
var _action_t := 0.0
var _action_dur := 0.0
var _flap_ph := 0.0
var _flap_boost := 0.0
var _dead_t := 0.0
var _snort_t := 5.0
var _ruffle_t := 9.0
var _preview_roar_t := 4.0
var _cast_name := ""
var _cast_fx: Node3D
var _spawn_t := -1.0
var _step_sign := [0.0, 0.0, 0.0, 0.0]
var _roared := false
var _hits_done := 0            # strikes of the current action that already landed
var _hit_target: Unit          # who the current melee action is aimed at
var last_melee := ""
var skin: DragonSkin           # sculpted model worn over the procedural skeleton (boss only, when present)
var wing_spread := 0.0         # smoothed 0 folded .. 1 open, for the skin's wing/front-leg blend
var _grounded := true
var _skin_tried := false
static var debug_freeze := -1.0  # dev (--animfreeze=0..1): hold every action at this point for screenshots

const BODY_Y := 4.3                  # pelvis height: long legs, the belly clears the ground
const CHEST_SCALE := Vector3(2.6, 2.45, 2.95)
const NECK_REST := [0.42, 0.28, 0.1, -0.12, -0.3]
const NECK_ROAR := [0.55, 0.22, -0.06, -0.16, -0.2]
const NECK_REACH := [0.16, 0.02, -0.06, -0.1, -0.12]
const NECK_INHALE := [0.62, 0.42, 0.2, 0.0, -0.08]
const FINGER_SPREAD := [0.32, -0.22, -0.78, -1.32]
const FINGER_FOLD := [0.05, -0.02, -0.09, -0.16]
const FINGER_LEN := [5.0, 6.1, 5.3, 4.1]


# ------------------------------------------------------------------ build

func build(scale_factor: float, whelp: bool) -> DragonRig:
	is_whelp = whelp
	root = Node3D.new()
	root.scale = Vector3.ONE * scale_factor
	add_child(root)

	# Dark, scary hide (shaders/dragon_skin.gdshader): smooth glossy black-crimson skin with an ember rim.
	var scale_m := _skin(Color(0.22, 0.05, 0.048) if not whelp else Color(0.4, 0.09, 0.045), 0.0)
	var back_m := _skin(Color(0.08, 0.025, 0.025), 0.4)
	var belly_m := _skin(Color(0.34, 0.15, 0.095), -0.6)
	belly_m.set_shader_parameter("back_color", Color(0.1, 0.04, 0.03))
	belly_m.set_shader_parameter("gloss", 0.5)
	var horn_m := Models.mat(Color(0.36, 0.31, 0.27), 0.0, 0.4)
	horn_m.rim = 0.6
	horn_m.rim_tint = 0.9
	var dark_m := Models.mat(Color(0.05, 0.03, 0.03), 0.0, 0.3)
	var gum_m := Models.mat(Color(0.3, 0.04, 0.04), 0.0, 0.8)
	var tooth_m := Models.mat(Color(0.86, 0.8, 0.68), 0.12)  # faint emission: no ink outline on tiny teeth
	glow_mat = Models.mat(Color(1.0, 0.4, 0.08), 2.5)
	eye_mat = Models.mat(Color(1.0, 0.5, 0.08), 10.0)
	throat_mat = Models.mat(Color(0.26, 0.05, 0.04), 0.0)
	throat_mat.emission_enabled = true
	throat_mat.emission = Color(1.0, 0.45, 0.1)
	throat_mat.emission_energy_multiplier = 0.0
	membrane_mat = StandardMaterial3D.new()
	membrane_mat.vertex_color_use_as_albedo = true
	membrane_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	membrane_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	membrane_mat.roughness = 0.85
	membrane_mat.backlight_enabled = true
	membrane_mat.backlight = Color(0.9, 0.16, 0.05)
	membrane_mat.rim_enabled = true
	membrane_mat.rim = 0.4
	membrane_mat.emission_enabled = true
	membrane_mat.emission = Color(0.3, 0.03, 0.01)
	membrane_mat.emission_energy_multiplier = 0.35

	# --- pelvis, waist, chest (heavy, barrel-chested: a dragon, not a dog)
	pelvis = _node(root, Vector3(0, BODY_Y, 2.0))
	chest = _node(pelvis, Vector3(0, 0.45, -3.4))
	# One smooth lofted torso from the tail root to the neck base (rebuilt each frame so it bends with the
	# pelvis/chest), instead of overlapping spheres that read as lumpy muscles.
	var torso_m := _skin(Color(0.22, 0.05, 0.048) if not whelp else Color(0.4, 0.09, 0.045), 0.0)
	torso_m.set_shader_parameter("belly", 1.0)
	torso_m.set_shader_parameter("belly_color", Color(0.3, 0.12, 0.08))
	_torso_rings = [
		[pelvis, Vector3(0, 0.25, 2.6), 1.25, 1.25], [pelvis, Vector3(0, 0.18, 2.0), 1.7, 1.65],
		[pelvis, Vector3(0, 0.1, 1.0), 2.05, 1.9], [pelvis, Vector3(0, 0.1, 0.0), 2.05, 1.95],
		[pelvis, Vector3(0, 0.15, -1.1), 1.9, 1.9], [chest, Vector3(0, -0.25, 1.5), 2.1, 2.1],
		[chest, Vector3(0, -0.35, 0.5), 2.45, 2.4], [chest, Vector3(0, -0.3, -0.6), 2.55, 2.45],
		[chest, Vector3(0, 0.0, -1.7), 2.15, 2.05], [chest, Vector3(0, 0.6, -2.1), 1.6, 1.6],
		[chest, Vector3(0, 1.15, -2.3), 1.2, 1.2]]
	_torso = MeshInstance3D.new()
	_torso.mesh = ImmediateMesh.new()
	_torso.material_override = torso_m
	root.add_child(_torso)
	# dorsal spikes along the back
	for i in 9:
		var on_chest := i < 4
		var par2: Node3D = chest if on_chest else pelvis
		var z2 := -1.7 + i * 0.95 if on_chest else -2.6 + (i - 4) * 1.0
		var y2 := 2.4 if on_chest else 1.9 - (i - 4) * 0.05
		var hgt := 1.6 - absf(i - 3.5) * 0.13
		Models.part(par2, _cyl(0.0, 0.44, hgt), back_m, Vector3(0, y2, z2), Vector3(0.55, 0, 0))

	# --- neck: five segments curving up and forward
	var parent := _node(chest, Vector3(0, 1.15, -2.3))
	for i in 5:
		var seg := parent if i == 0 else _node(parent, Vector3(0, 0, -1.2))
		var r := lerpf(1.3, 0.68, i / 4.0)
		var r_next := lerpf(1.3, 0.68, (i + 1) / 4.0) if i < 4 else 0.62
		# smooth tube: a tapered cylinder to the next joint plus a joint sphere (no capsule bulges)
		Models.part(seg, _cyl(r_next, r, 1.2), scale_m, Vector3(0, 0, -0.6), Vector3(-PI / 2, 0, 0))
		Models.part(seg, _sph(r), scale_m, Vector3.ZERO)
		# smooth throat stripe (glows while inhaling for Flame Breath)
		Models.part(seg, _cyl(r_next * 0.42, r * 0.42, 1.25), throat_mat, Vector3(0, -r * 0.8, -0.6), Vector3(-PI / 2, 0, 0),
			Vector3(1, 1, 0.35))
		Models.part(seg, _cyl(0.0, 0.2 + r * 0.12, 0.85 + r * 0.3), back_m, Vector3(0, r * 0.95, -0.55), Vector3(0.6, 0, 0))
		neck.append(seg)
		parent = seg

	# --- head
	head = _node(parent, Vector3(0, 0, -1.2))
	head.scale = Vector3.ONE * 1.15
	_frustum(head, Vector3(0, 0.25, -0.95), 0.6, 0.86, 2.0, 0.8, scale_m)          # skull
	_frustum(head, Vector3(0, 0.1, -2.75), 0.34, 0.62, 1.9, 0.68, scale_m)        # snout
	_frustum(head, Vector3(0, -0.12, -2.4), 0.3, 0.5, 2.4, 0.4, gum_m)            # upper mouth
	Models.part(head, _cyl(0.0, 0.14, 0.55), horn_m, Vector3(0, 0.5, -3.3), Vector3(-0.4, 0, 0))  # nose horn
	for side in [-1.0, 1.0]:
		var s: float = side
		Models.part(head, _cyl(0.04, 0.2, 1.4), back_m, Vector3(0.45 * s, 0.68, -1.35), Vector3(PI / 2 - 0.25, 0, 0.12 * s))  # brow
		Models.part(head, _sph(0.15), eye_mat, Vector3(0.52 * s, 0.5, -1.85))
		var nos := _node(head, Vector3(0.2 * s, 0.32, -3.6))
		Models.part(nos, _sph(0.07), dark_m, Vector3.ZERO)
		nostrils.append(nos)
		_horn(head, Vector3(0.5 * s, 0.75, -0.55), Vector3(PI / 2 - 0.55, 0.0, -0.32 * s), [1.5, 1.3, 1.0], [0.3, 0.2, 0.11],
			Vector3(0.32, 0, 0.0), horn_m, dark_m)
		_horn(head, Vector3(0.75 * s, 0.35, -0.35), Vector3(PI / 2 - 0.1, 0.0, -0.85 * s), [0.8, 0.6], [0.16, 0.09],
			Vector3(0.25, 0, 0), horn_m, dark_m)
		for k in 3:  # cheek frill
			Models.part(head, _cyl(0.0, 0.1, 0.75 - k * 0.12), back_m, Vector3(0.62 * s, -0.05 - k * 0.2, -0.45 + k * 0.1),
				Vector3(PI / 2 - 0.2, 0, -1.1 * s))
		for k in 7:  # upper teeth
			Models.part(head, _cyl(0.0, 0.055, 0.32 - (0.08 if k % 2 else 0.0)), tooth_m,
				Vector3(0.32 * s - k * 0.025 * s, -0.3, -1.75 - k * 0.27), Vector3(PI, 0, 0))
	jaw = _node(head, Vector3(0, -0.32, -0.55))
	_frustum(jaw, Vector3(0, -0.15, -1.65), 0.28, 0.52, 2.9, 0.42, scale_m)
	Models.part(jaw, Models.box(0.55, 0.1, 2.2), gum_m, Vector3(0, 0.02, -1.6))   # tongue bed
	Models.part(jaw, Models.box(0.3, 0.08, 1.6), Models.mat(Color(0.6, 0.15, 0.15)), Vector3(0, 0.08, -1.4))  # tongue
	for side in [-1.0, 1.0]:
		var s2: float = side
		for k in 6:
			Models.part(jaw, _cyl(0.0, 0.05, 0.28 - (0.07 if k % 2 else 0.0)), tooth_m,
				Vector3(0.27 * s2 - k * 0.022 * s2, 0.12, -1.05 - k * 0.3))
		Models.part(jaw, _cyl(0.0, 0.09, 0.6), back_m, Vector3(0.3 * s2, -0.35, -0.3), Vector3(PI / 2 + 0.5, 0, -0.5 * s2))
	mouth = _node(head, Vector3(0, -0.2, -3.55))
	mouth_glow = MeshInstance3D.new()
	mouth_glow.mesh = _sph(0.4)
	mouth_mat = Vfx.glow_mat(Color(1, 0.6, 0.15), 0.0)
	mouth_glow.material_override = mouth_mat
	mouth_glow.position = Vector3(0, 0.05, 1.3)
	mouth.add_child(mouth_glow)

	# --- front legs: thick, clawed, planted wide
	for side in [-1.0, 1.0]:
		var s3: float = side
		var sh := _node(chest, Vector3(1.85 * s3, -0.7, -0.55))
		Models.part(sh, _sph(1.0), scale_m, Vector3(-0.15 * s3, -0.35, 0), Vector3.ZERO, Vector3(0.8, 1.15, 1.0))
		var el := _node(sh, Vector3(0.18 * s3, -1.95, 0.45))
		_bone(sh, Vector3.ZERO, el.position, 0.78, 0.58, scale_m)
		var wr := _node(el, Vector3(0, -1.65, -0.4))
		_bone(el, Vector3.ZERO, wr.position, 0.56, 0.42, scale_m)
		_paw(wr, Vector3(0, -0.32, -0.6), 0.62, scale_m, dark_m)
		arms.append({"side": s3, "shoulder": sh, "elbow": el, "wrist": wr})

	# --- hind legs (digitigrade, big haunches)
	for side in [-1.0, 1.0]:
		var s4: float = side
		var hip := _node(pelvis, Vector3(1.65 * s4, -0.4, 0.45))
		Models.part(hip, _sph(1.0), scale_m, Vector3(-0.15 * s4, -0.55, -0.15), Vector3.ZERO, Vector3(0.85, 1.35, 1.25))
		var knee := _node(hip, Vector3(0.15 * s4, -1.8, -1.05))
		_bone(hip, Vector3.ZERO, knee.position, 1.0, 0.7, scale_m)
		var ankle := _node(knee, Vector3(0, -1.4, 1.2))
		_bone(knee, Vector3.ZERO, ankle.position, 0.66, 0.44, scale_m)
		var foot := _node(ankle, Vector3.ZERO)
		_paw(foot, Vector3(0, -0.4, -0.75), 0.7, scale_m, dark_m)
		legs.append({"side": s4, "hip": hip, "knee": knee, "ankle": ankle, "foot": foot})

	# --- tail
	var tp := _node(pelvis, Vector3(0, 0.25, 2.6))
	var tr := 1.35
	for i in 10:
		var seg2 := tp if i == 0 else _node(tp, Vector3(0, 0, 1.3))
		Models.part(seg2, _cyl(tr * 0.84, tr, 1.3), scale_m, Vector3(0, 0, 0.65), Vector3(PI / 2, 0, 0))
		Models.part(seg2, _sph(tr), scale_m, Vector3.ZERO)
		Models.part(seg2, Models.box(tr * 0.9, 0.1, 1.0), belly_m, Vector3(0, -tr * 0.86, 0.6))
		if i < 9:
			Models.part(seg2, _cyl(0.0, 0.1 + tr * 0.22, 0.35 + tr * 0.6), back_m, Vector3(0, tr * 0.88, 0.55), Vector3(-0.6, 0, 0))
		tail.append(seg2)
		tp = seg2
		tr *= 0.84
	for side in [-1.0, 1.0]:  # spade-shaped tail tip
		Models.part(tp, _cyl(0.0, 0.32, 1.4), back_m, Vector3(0.3 * side, 0, 1.4), Vector3(PI / 2 + 0.1, 0, 0.5 * side),
			Vector3(1, 1, 0.35))
	Models.part(tp, _cyl(0.0, 0.2, 1.6), dark_m, Vector3(0, 0, 1.7), Vector3(PI / 2 + 0.05, 0, 0))

	# --- wings
	for side in [-1.0, 1.0]:
		wings.append(_wing(side, back_m, horn_m, dark_m))

	Models.apply_outline(root, 0.06)
	blob = Models.blob_shadow(9.0 * scale_factor if not whelp else 1.6)
	add_child(blob)
	if not whelp:
		_build_aura()
	_pose_rest()
	return self


## A dark haze always rolling off the body, with embers drifting up out of the molten veins.
func _build_aura() -> void:
	var sm := Vfx.emitter({"amount": 18, "lifetime": 3.0, "one_shot": false, "vmin": 0.3, "vmax": 0.9,
		"direction": Vector3.UP, "spread": 35.0, "gravity": Vector3(0, 0.5, 0), "damping": 0.2, "size": 3.2,
		"grow": true, "shader": "smoke", "spin": 20.0, "box": Vector3(2.0, 1.2, 3.0),
		"colors": [Color(0.05, 0.02, 0.02, 0.0), Color(0.06, 0.025, 0.025, 0.4), Color(0.04, 0.02, 0.02, 0.0)]})
	sm.position = Vector3(0, 0.4, 1.0)
	chest.add_child(sm)
	var em := Vfx.emitter({"amount": 26, "lifetime": 2.2, "one_shot": false, "vmin": 0.6, "vmax": 1.8,
		"direction": Vector3.UP, "spread": 30.0, "gravity": Vector3(0, 0.8, 0), "size": 0.13,
		"box": Vector3(2.2, 1.6, 3.2), "colors": [Color(1, 0.6, 0.2, 0), Color(1, 0.45, 0.1, 1), Color(0.9, 0.15, 0.02, 0)]})
	em.position = Vector3(0, 0, 1.0)
	chest.add_child(em)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.3, 0.06)
	l.light_energy = 1.6
	l.omni_range = 11.0
	l.position = Vector3(0, -2.0, 0.5)
	chest.add_child(l)

## Skin material (shaders/dragon_skin.gdshader). darkness = extra shade on the dorsal side.
func _skin(c: Color, darkness: float) -> ShaderMaterial:
	if _skin_shader == null:
		_skin_shader = load("res://shaders/dragon_skin.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _skin_shader
	m.set_shader_parameter("noise_tex", Vfx.noise_tex())
	m.set_shader_parameter("base_color", c)
	m.set_shader_parameter("darkness", darkness)
	if is_whelp:
		m.set_shader_parameter("rim", 0.35)
	m.set_meta("outline", true)
	skin_mats.append(m)
	return m


## Smooth (high-poly) primitives for the dragon, so the big body parts don't look faceted or lumpy.
static func _sph(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 28
	m.rings = 14
	return m


static func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 24 if maxf(top, bottom) > 0.3 else 10
	m.rings = 1
	return m


static func _cap(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 24
	m.rings = 8
	return m


func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


## Tapered limb between two points of `parent` (cylinder + rounded joint).
func _bone(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, m: Material) -> void:
	var d := b - a
	var ln := d.length()
	var mi := Models.part(parent, _cyl(r1, r0, ln), m, (a + b) * 0.5)
	var dn := d / ln
	mi.basis = Basis(Vector3.RIGHT, PI) if dn.dot(Vector3.UP) < -0.999 else Basis(Quaternion(Vector3.UP, dn))
	Models.part(parent, _sph(r0 * 1.04), m, a)


## Eight-sided tapered block along -Z (skull, snout, jaw). flatten < 1 squashes it vertically.
func _frustum(parent: Node3D, center: Vector3, front_r: float, back_r: float, ln: float, flatten: float, m: Material) -> void:
	var c := Models.cyl(front_r, back_r, ln)
	c.radial_segments = 8
	Models.part(parent, c, m, center, Vector3(-PI / 2, 0, 0), Vector3(1, 1, flatten))


## Curved horn: a chain of cones, each bent a little further than the last, with a dark tip.
func _horn(parent: Node3D, pos: Vector3, rot: Vector3, lengths: Array, radii: Array, bend: Vector3, m: Material,
		tip_m: Material) -> void:
	var n := _node(parent, pos)
	n.rotation = rot
	for i in lengths.size():
		var ln: float = lengths[i]
		var r0: float = radii[i]
		var r1: float = radii[i + 1] if i + 1 < radii.size() else 0.0
		Models.part(n, _cyl(r1, r0, ln), tip_m if i == lengths.size() - 1 else m, Vector3(0, ln * 0.5, 0))
		var nx := _node(n, Vector3(0, ln * 0.95, 0))
		nx.rotation = bend
		n = nx


## Foot / hand with three forward claws and a dew claw.
func _paw(parent: Node3D, center: Vector3, w: float, m: Material, claw_m: Material) -> void:
	Models.part(parent, _sph(1.0), m, center, Vector3.ZERO, Vector3(w * 1.1, w * 0.55, w * 1.5))
	for c in 3:
		var x := (c - 1) * w * 0.55
		Models.part(parent, _cyl(0.0, w * 0.2, w * 1.0), claw_m, center + Vector3(x, -w * 0.25, -w * 1.55),
			Vector3(-PI / 2 - 0.35, 0, -0.15 * (c - 1)))
	Models.part(parent, _cyl(0.0, w * 0.15, w * 0.6), claw_m, center + Vector3(0, -w * 0.2, w * 1.0), Vector3(PI / 2 + 0.4, 0, 0))


func _wing(side: float, bone_m: Material, horn_m: Material, claw_m: Material) -> Dictionary:
	var sh := _node(chest, Vector3(1.55 * side, 1.75, -0.6))
	var el := _node(sh, Vector3(3.0 * side, 0, 0))
	var wr := _node(el, Vector3(3.6 * side, 0, 0))
	_bone(sh, Vector3.ZERO, el.position, 0.36, 0.26, bone_m)
	_bone(el, Vector3.ZERO, wr.position, 0.26, 0.17, bone_m)
	Models.part(wr, _sph(0.2), bone_m, Vector3.ZERO)
	# thumb claw on the wrist
	Models.part(wr, _cyl(0.0, 0.12, 0.7), claw_m, Vector3(0.1 * side, 0.3, -0.2), Vector3(-0.5, 0, -0.4 * side))
	var fingers: Array = []
	var tips: Array = []
	for i in 4:
		var f := _node(wr, Vector3.ZERO)
		var ln: float = FINGER_LEN[i]
		_bone(f, Vector3.ZERO, Vector3(ln * side, 0, 0), 0.13, 0.04, bone_m)
		tips.append(_node(f, Vector3(ln * side, 0, 0)))
		fingers.append(f)
	var anchors := [_node(chest, Vector3(1.45 * side, 1.4, 1.1)), _node(pelvis, Vector3(1.4 * side, 1.2, 0.8))]
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	return {"side": side, "shoulder": sh, "elbow": el, "wrist": wr, "fingers": fingers, "tips": tips,
		"anchors": anchors, "mesh": mi}


## Rebuilds a wing membrane from where the bones are this frame.
func _update_membrane(w: Dictionary) -> void:
	var mi: MeshInstance3D = w["mesh"]
	var im := mi.mesh as ImmediateMesh
	var W := mi.to_local((w["wrist"] as Node3D).global_position)
	var E := mi.to_local((w["elbow"] as Node3D).global_position)
	var S := mi.to_local((w["shoulder"] as Node3D).global_position)
	var bc := mi.to_local((w["anchors"][0] as Node3D).global_position)
	var bp := mi.to_local((w["anchors"][1] as Node3D).global_position)
	var tips: Array = []
	for t in w["tips"]:
		tips.append(mi.to_local((t as Node3D).global_position))
	var ring: Array = []  # [position, colour] around the wrist
	var dark := Color(0.08, 0.02, 0.02)
	var mid := Color(0.2, 0.035, 0.03)
	var light := Color(0.38, 0.07, 0.04)
	for i in 4:
		ring.append([tips[i], mid])
		var nxt: Vector3 = tips[i + 1] if i < 3 else bp
		var scallop: Vector3 = (tips[i] + nxt) * 0.5
		scallop = scallop.lerp(W, 0.3 if i < 3 else 0.18)
		ring.append([scallop, light])
	ring.append([bp, dark])
	ring.append([bc, dark])
	ring.append([S, dark])
	ring.append([E, dark])
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, membrane_mat)
	for i in ring.size() - 1:
		_tri(im, [W, dark], ring[i], ring[i + 1])
	im.surface_end()


## Rebuild the lofted torso: elliptical rings placed on the pelvis/chest, smooth normals from the grid.
func _update_torso() -> void:
	if _torso == null:
		return
	const SEG := 28
	var inv := _torso.global_transform.affine_inverse()
	var grid: Array = []
	var centres: Array = []
	for rg in _torso_rings:
		var nd: Node3D = rg[0]
		var xf: Transform3D = inv * nd.global_transform
		var c: Vector3 = rg[1]
		var sw := _swell if nd == chest else 1.0
		var rx: float = float(rg[2]) * sw
		var ry: float = float(rg[3]) * sw
		var ring := PackedVector3Array()
		for j in SEG:
			var a := TAU * j / SEG
			var y := sin(a) * ry
			if y < 0.0:
				y *= 1.06  # a slightly deeper, heavier belly
			ring.append(xf * (c + Vector3(cos(a) * rx, y, 0)))
		grid.append(ring)
		centres.append(xf * c)
	var nr := grid.size()
	var normals: Array = []
	for i in nr:
		var nrow := PackedVector3Array()
		for j in SEG:
			var pa: Vector3 = grid[i][(j + 1) % SEG] - grid[i][(j - 1 + SEG) % SEG]
			var pb: Vector3 = grid[mini(i + 1, nr - 1)][j] - grid[maxi(i - 1, 0)][j]
			var n := pa.cross(pb).normalized()
			if n.dot(grid[i][j] - centres[i]) < 0.0:
				n = -n
			nrow.append(n)
		normals.append(nrow)
	var im := _torso.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in nr - 1:
		for j in SEG:
			var j2 := (j + 1) % SEG
			for v in [[i, j], [i, j2], [i + 1, j], [i + 1, j], [i, j2], [i + 1, j2]]:
				im.surface_set_normal(normals[v[0]][v[1]])
				im.surface_add_vertex(grid[v[0]][v[1]])
	im.surface_end()


func _tri(im: ImmediateMesh, a: Array, b: Array, c: Array) -> void:
	var pa: Vector3 = a[0]
	var pb: Vector3 = b[0]
	var pc: Vector3 = c[0]
	var n := (pb - pa).cross(pc - pa)
	if n.length_squared() < 0.000001:
		return
	n = n.normalized()
	for v in [a, b, c]:
		im.surface_set_normal(n)
		im.surface_set_color(v[1])
		im.surface_add_vertex(v[0])


# ------------------------------------------------------------------ events

## roar, breath, spit, bite, claw_l, claw_r, rake (Rending Claw), stomp, tail_windup, tail, takeoff, land, nova.
## Melee actions take the target so the hit effects land on it when the claw, jaw or paw connects.
func play(action: String, target: Unit = null) -> void:
	if action == "claw":
		action = "rake"
	_action = action
	_action_t = 0.0
	_roared = false
	_hits_done = 0
	_hit_target = target
	_action_dur = {"claw_l": 1.0, "claw_r": 1.0, "rake": 1.6, "stomp": 1.45, "bite": 0.6, "tail_windup": 1.2,
		"tail": 1.0, "roar": 2.4, "breath": 1.7, "takeoff": 2.4, "land": 1.6, "nova": 1.2, "spit": 0.7}.get(action, 0.8)
	if is_whelp:
		_action_dur *= 0.7
	if action == "breath" and is_inside_tree():
		# lunge forward first, then the stream (so it does not start while the head still points up)
		get_tree().create_timer(0.28).timeout.connect(func():
			if is_instance_valid(mouth):
				Vfx.breath_stream(mouth, 1.2))
	if action in ["takeoff", "land", "nova"]:
		_flap_boost = 1.0


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	_t += delta
	if unit == null:
		unit = get_parent() as Unit
		if unit != null:
			_last_flat = unit.flat_pos()
			_vis_yaw = unit.rotation.y
			if is_whelp:
				_spawn_t = 0.0
	if unit != null and unit.world != null and not unit.world.visuals:
		return  # dedicated server / headless sim: nobody sees it
	if not _skin_tried:
		_skin_tried = true
		if not is_whelp and DragonSkin.available():
			_wear_skin()
	var dead := unit != null and not unit.alive
	if dead:
		_animate_death(delta)
	else:
		_animate(delta)
	if skin != null:
		skin.update(delta, _grounded, dead)
		return
	for w in wings:
		_update_membrane(w)
	_update_torso()


## Swap the primitive body for the sculpted model: the procedural skeleton stays (hidden) and drives it.
func _wear_skin() -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visible = false  # incl. the mouth glow: it would float outside the slimmer jaws
	# the mouth (breath/roar effects) and nostrils now follow the model's head, not the hidden one
	mouth.reparent(root, false)
	for nos in nostrils:
		(nos as Node3D).reparent(mouth, false)
	nostrils[0].position = Vector3(-0.25, 0.45, 0.35)
	nostrils[1].position = Vector3(0.25, 0.45, 0.35)
	skin = DragonSkin.new(self)


func _animate(delta: float) -> void:
	var k := clampf(delta * 7.0, 0.0, 1.0)
	var preview := unit == null
	var breathe := sin(_t * 1.3)

	# Locomotion speed and smoothed turning (the visible body lags the unit's facing a little).
	if not preview:
		var flat := unit.flat_pos()
		var v := flat.distance_to(_last_flat) / maxf(delta, 0.001)
		_last_flat = flat
		_speed = lerpf(_speed, clampf(v / 5.0, 0.0, 1.3), clampf(delta * 5.0, 0.0, 1.0))
		var prev := _vis_yaw
		_vis_yaw = lerp_angle(_vis_yaw, unit.rotation.y, clampf(delta * 5.0, 0.0, 1.0))
		_turn = lerpf(_turn, wrapf(_vis_yaw - prev, -PI, PI) / maxf(delta, 0.001), clampf(delta * 6.0, 0.0, 1.0))
		rotation.y = wrapf(_vis_yaw - unit.rotation.y, -PI, PI)
	if _speed > 0.05:
		_phase += delta * (2.2 + 2.6 * _speed)
	var flying := is_whelp or (not preview and (unit.position.y > 1.0 or unit.untargetable))

	# ---- pose defaults (ground idle)
	var rear := 0.04 + breathe * 0.012
	var lift := 0.0           # pelvis height offset
	var roll := clampf(-_turn * 0.12, -0.18, 0.18)
	var twist := 0.0          # chest yaw against the pelvis
	var neck_p: Array = NECK_REST.duplicate()
	var neck_yaw := sin(_t * 0.37) * 0.25 + sin(_t * 0.11) * 0.2 + clampf(_turn * 0.35, -0.5, 0.5)
	var head_p := -0.3 + breathe * 0.04
	var head_roll := sin(_t * 0.5) * 0.05
	var jaw_open := 0.04 + maxf(0.0, breathe) * 0.03
	var mouth_a := 0.0
	var throat := 0.0
	var spread := 0.0
	var flap_amp := 0.0
	var flap_freq := 3.0
	var arm_lift := [0.0, 0.0]       # per front leg (side -1, +1)
	var arm_swipe := [0.0, 0.0]      # + out to the side, - across the chest
	var arm_reach := [0.0, 0.0]      # 1 = arm straightened out towards the target
	var arm_curl := [0.0, 0.0]       # + claws cocked back/open, - claws curled in (raking)
	var crouch := 0.0                # hind legs fold, loading the haunches
	var tail_extra := 0.0
	var tail_lift := 0.0
	var chest_swell := 1.0 + breathe * 0.02
	var heat := 2.0 + sin(_t * 2.2) * 0.6

	# Look at the current target
	if not preview and unit.target != null and unit.target.alive and unit.target != unit:
		var to := unit.target.flat_pos() - unit.flat_pos()
		var local_yaw := wrapf(atan2(-to.x, -to.z) - unit.rotation.y - rotation.y, -PI, PI)
		neck_yaw = clampf(local_yaw, -1.1, 1.1) + sin(_t * 0.4) * 0.06

	# Walking: weight shift and a counter-swaying neck
	if _speed > 0.05 and not flying:
		lift -= absf(sin(_phase)) * 0.14 * _speed
		roll += sin(_phase) * 0.05 * _speed
		neck_yaw -= sin(_phase) * 0.06 * _speed
		head_p -= 0.05 * _speed

	# Occasional wing ruffle and snort while idle
	if not flying and _action == "" and (preview or not unit.is_casting()):
		_ruffle_t -= delta
		if _ruffle_t < 0.0:
			var rf := clampf(-_ruffle_t, 0.0, 1.4)
			spread = 0.22 * sin(rf / 1.4 * PI)
			if _ruffle_t < -1.4:
				_ruffle_t = randf_range(8.0, 14.0)
		_snort_t -= delta
		if _snort_t <= 0.0:
			_snort_t = randf_range(5.0, 9.0)
			if not is_whelp and is_inside_tree():
				_snort()

	# Flying: wings out, slow powerful strokes, legs tucked
	if flying:
		spread = 1.0
		flap_amp = 0.8
		flap_freq = 7.0 if is_whelp else 2.6
		rear = 0.16
		neck_p = [0.3, 0.12, 0.0, -0.08, -0.2]
		tail_lift = 0.12

	# Casting poses (read straight from the replicated cast)
	if not preview and unit.is_casting():
		var cname: String = unit.casting["name"]
		var prog := 1.0 - float(unit.casting["remaining"]) / maxf(0.01, float(unit.casting["total"]))
		match cname:
			"Flame Breath":  # inhale: rear back, chest swells, throat fills with fire
				var e := _ease(prog * 1.6)
				rear = lerpf(rear, 0.42, e)
				neck_p = _lerp_arr(neck_p, NECK_INHALE, e)
				head_p = lerpf(head_p, 0.05, e)
				neck_yaw *= 1.0 - e
				jaw_open = 0.18 * e
				throat = prog
				mouth_a = 0.55 * prog
				chest_swell = 1.0 + 0.1 * prog
				spread = maxf(spread, 0.3 * e)
				arm_lift = [0.45 * e, 0.45 * e]
			"Cataclysm":  # rear up, wings wide, fire swirling
				var e2 := _ease(prog * 3.0)
				rear = lerpf(rear, 0.48, e2)
				neck_p = _lerp_arr(neck_p, NECK_ROAR, e2)
				head_p = lerpf(head_p, 0.45, e2)
				neck_yaw *= 1.0 - e2
				jaw_open = 0.45 + 0.15 * sin(_t * 9.0)
				mouth_a = 0.9
				throat = 1.0
				spread = 1.0
				flap_amp = 0.35
				flap_freq = 1.6
				arm_lift = [1.1 * e2, 1.1 * e2]
				heat += 4.0 * prog
		_update_cast_fx(cname)
	else:
		_update_cast_fx("")

	# One-shot actions
	if preview:
		_preview_roar_t -= delta
		if _preview_roar_t <= 0.0 and _action == "":
			_preview_roar_t = randf_range(7.0, 10.0)
			play("roar")
	if _action != "":
		_action_t += delta
		if debug_freeze >= 0.0:
			_action_t = minf(_action_t, debug_freeze * _action_dur)
		var p := clampf(_action_t / _action_dur, 0.0, 1.0)
		var bell := sin(p * PI)
		var hold := _ease(p * 4.0) * (1.0 - _ease((p - 0.75) * 4.0))  # in, hold, out
		k = clampf(delta * 11.0, 0.0, 1.0)
		match _action:
			"roar":
				rear = lerpf(rear, 0.46, hold)
				neck_p = _lerp_arr(neck_p, NECK_ROAR, hold)
				head_p = lerpf(head_p, 0.8, hold)
				head_roll += sin(_t * 18.0) * 0.04 * hold
				neck_yaw *= 1.0 - hold
				jaw_open = lerpf(jaw_open, 0.85, hold)
				mouth_a = 0.6 * hold
				spread = maxf(spread, 0.75 * hold)
				flap_amp = maxf(flap_amp, 0.25 * hold)
				arm_lift = [1.15 * hold, 1.0 * hold]
				arm_swipe = [0.25 * hold, -0.2 * hold]
				tail_lift = 0.2 * hold
				if p > 0.3 and not _roared:
					_roared = true
					_roar_breath()
			"nova":
				rear = lerpf(rear, 0.3, bell)
				spread = 1.0
				head_p = lerpf(head_p, 0.4, bell)
				neck_p = _lerp_arr(neck_p, NECK_ROAR, bell * 0.7)
				jaw_open = 0.6 * bell
				heat += 6.0 * bell
			"breath":
				var sweep := _ease(p * 1.15)
				rear = lerpf(0.42, 0.08, _ease(p * 9.0))
				k = clampf(delta * 16.0, 0.0, 1.0)
				neck_p = NECK_REACH.duplicate()
				head_p = -0.16
				neck_yaw = lerpf(-0.75, 0.75, sweep)
				jaw_open = 0.85
				mouth_a = 0.95 * (1.0 - p)
				throat = 1.0 - p
				spread = maxf(spread, 0.35)
				arm_lift = [0.15, 0.15]
			"spit":
				neck_p = _lerp_arr(neck_p, NECK_REACH, bell)
				head_p = lerpf(head_p, -0.05, bell)
				jaw_open = 0.6 * bell
				mouth_a = 0.7 * bell
			"bite":  # snake the neck back, then lunge and snap
				var bw := _ease(p / 0.3)
				var bs := _ease((p - 0.3) / 0.14)
				var br := _ease((p - 0.5) / 0.5)
				var bon := 1.0 - br
				neck_p = _lerp_arr(_lerp_arr(neck_p, NECK_INHALE, bw * 0.6 * bon), [0.05, -0.1, -0.16, -0.22, -0.26], bs * bon)
				head_p = lerpf(head_p, lerpf(0.15, -0.1, bs), maxf(bw, bs) * bon)
				jaw_open = maxf(jaw_open, (lerpf(0.6 * bw, 0.05, bs) + 0.15 * bs) * bon)
				rear = lerpf(rear, lerpf(0.12, -0.05, bs), maxf(bw, bs) * bon)
				lift -= 0.25 * bs * bon
				arm_lift = [0.12 * bs * bon, 0.12 * bs * bon]
				if bs > 0.0 and bs < 1.0:
					k = clampf(delta * 18.0, 0.0, 1.0)
				_hit_at(p, 0.42, 1)
			"claw_l", "claw_r":  # wind the paw up high and out, then rake it down across the target
				var i := 0 if _action == "claw_l" else 1
				var sw := _swipe_pose(p, i, 0.0, 0.38, 0.52, 0.95)
				rear = maxf(rear, sw["rear"])
				twist += sw["twist"]
				lift += sw["lift"]
				neck_yaw += sw["neck"]
				arm_lift[i] = sw["arm_lift"]
				arm_swipe[i] = sw["arm_swipe"]
				arm_reach[i] = sw["reach"]
				arm_curl[i] = sw["curl"]
				arm_lift[1 - i] = 0.12 * sw["w"] * (1.0 - sw["r"])
				crouch = 0.1 * sw["w"] * (1.0 - sw["s"])
				neck_p = _lerp_arr(neck_p, NECK_REACH, maxf(sw["w"] * 0.5, sw["s"]) * (1.0 - sw["r"]))
				head_p = lerpf(head_p, -0.2, sw["w"] * (1.0 - sw["r"]))
				jaw_open = maxf(jaw_open, 0.35 * sw["w"] * (1.0 - sw["r"]))
				roll += 0.06 * (1.0 if i == 1 else -1.0) * sw["s"] * (1.0 - sw["r"])
				if sw["fast"]:
					k = clampf(delta * 18.0, 0.0, 1.0)
				_hit_at(p, 0.46, 1)
			"rake":  # Rending Claw: rear up, right claw then left claw, then drop back down
				var ra := _swipe_pose(p, 1, 0.0, 0.3, 0.42, 0.62)
				var rb := _swipe_pose(p, 0, 0.34, 0.54, 0.66, 1.0)
				rear = maxf(rear, maxf(ra["rear"], rb["rear"]) + 0.12 * sin(clampf(p / 0.7, 0.0, 1.0) * PI))
				twist += ra["twist"] + rb["twist"]
				neck_yaw += ra["neck"] + rb["neck"]
				lift += ra["lift"] + rb["lift"]
				arm_lift = [rb["arm_lift"], ra["arm_lift"]]
				arm_swipe = [rb["arm_swipe"], ra["arm_swipe"]]
				arm_reach = [rb["reach"], ra["reach"]]
				arm_curl = [rb["curl"], ra["curl"]]
				crouch = 0.12 * sin(clampf(p / 0.75, 0.0, 1.0) * PI)
				var up := _ease(p * 4.0) * (1.0 - _ease((p - 0.7) * 3.3))
				neck_p = _lerp_arr(neck_p, NECK_REACH, up * 0.6)
				head_p = lerpf(head_p, -0.1, up)
				jaw_open = maxf(jaw_open, 0.55 * up)
				spread = maxf(spread, 0.45 * up)
				tail_lift = 0.15 * up
				if ra["fast"] or rb["fast"]:
					k = clampf(delta * 18.0, 0.0, 1.0)
				_hit_at(p, 0.36, 1)
				_hit_at(p, 0.6, 2)
			"stomp":  # rear up on the hind legs, then slam both forepaws into the ground
				var w := _ease(p / 0.42)
				var s2 := _ease((p - 0.42) / 0.09)
				var r := _ease((p - 0.6) / 0.4)
				var on := 1.0 - r
				rear = lerpf(rear, lerpf(0.5 * w, -0.06, s2), on)
				crouch = lerpf(0.15 * w, 0.0, s2) * on
				lift -= 0.28 * s2 * on
				arm_lift = [lerpf(1.6 * w, 0.25, s2) * on, lerpf(1.5 * w, 0.25, s2) * on]
				arm_swipe = [lerpf(0.35 * w, 0.05, s2) * on, lerpf(0.35 * w, 0.05, s2) * on]
				arm_reach = [lerpf(0.6 * w, 1.0, s2) * on, lerpf(0.6 * w, 1.0, s2) * on]
				arm_curl = [lerpf(0.6 * w, -0.3, s2) * on, lerpf(0.6 * w, -0.3, s2) * on]
				neck_p = _lerp_arr(neck_p, NECK_REACH, on * maxf(w * 0.7, s2))
				head_p = lerpf(head_p, lerpf(-0.05, -0.3, s2), on * w)
				neck_yaw *= 1.0 - 0.7 * w * on
				jaw_open = maxf(jaw_open, lerpf(0.7 * w, 0.3, s2) * on)
				spread = maxf(spread, 0.6 * w * on)
				flap_amp = maxf(flap_amp, 0.3 * w * (1.0 - s2))
				tail_lift = 0.2 * w * on
				if s2 > 0.0 and s2 < 1.0:
					k = clampf(delta * 22.0, 0.0, 1.0)
				_hit_at(p, 0.5, 1)
			"tail_windup":
				var e3 := _ease(p * 2.0)
				twist = 0.25 * e3
				tail_extra = -0.9 * e3
				neck_yaw = lerpf(neck_yaw, -1.0, e3)
				head_p = lerpf(head_p, -0.1, e3)
				lift -= 0.25 * e3
			"tail":
				twist = lerpf(0.25, -0.3, _ease(p * 2.5))
				tail_extra = lerpf(-0.9, 1.2, _ease(p * 2.2)) * (1.0 - _ease((p - 0.6) * 2.5))
				neck_yaw = lerpf(-1.0, 0.4, _ease(p * 2.0))
				roll -= 0.1 * bell
			"takeoff":
				if p < 0.3:
					lift -= 0.7 * _ease(p / 0.3)
					spread = maxf(spread, p / 0.3)
				else:
					lift += 1.2 * _ease((p - 0.3) * 3.0)
					spread = 1.0
					flap_amp = 1.0
					flap_freq = 3.6
				rear = lerpf(rear, 0.3, bell)
			"land":
				spread = 1.0
				flap_amp = 0.7 * (1.0 - p)
				rear = lerpf(0.35, 0.04, _ease(p * 1.6))
				if p > 0.45:
					lift -= 0.55 * sin(clampf((p - 0.45) / 0.55, 0.0, 1.0) * PI)
		if _action_t >= _action_dur:
			_action = ""

	# ---- wings
	_grounded = not flying
	_flap_boost = maxf(0.0, _flap_boost - delta * 0.5)
	if _flap_boost > 0.0:
		spread = maxf(spread, _flap_boost)
		flap_amp = maxf(flap_amp, 0.8 * _flap_boost)
		flap_freq = maxf(flap_freq, 3.4)
	_flap_ph += delta * flap_freq
	var stroke := sin(_flap_ph) + 0.25 * sin(_flap_ph * 2.0)
	var lagged := sin(_flap_ph - 0.7)
	if flying or flap_amp > 0.3:
		lift += -sin(_flap_ph) * 0.28 * flap_amp
	for w in wings:
		_pose_wing(w, spread, stroke * flap_amp, lagged * flap_amp, k)
	wing_spread = lerpf(wing_spread, spread, k)

	# ---- body
	var base_y := BODY_Y + lift - crouch * 0.9
	if is_whelp:
		base_y += 0.6
	pelvis.position.y = lerpf(pelvis.position.y, base_y, k)
	pelvis.rotation.x = lerp_angle(pelvis.rotation.x, rear, k)
	pelvis.rotation.z = lerp_angle(pelvis.rotation.z, roll, k)
	pelvis.rotation.y = lerp_angle(pelvis.rotation.y, -twist * 0.4, k)
	chest.rotation.y = lerp_angle(chest.rotation.y, twist, k)
	chest.rotation.x = lerp_angle(chest.rotation.x, rear * 0.25, k)
	_swell = lerpf(_swell, chest_swell, k)

	# ---- neck and head (S-curve; yaw spread along the segments)
	for i in neck.size():
		var seg: Node3D = neck[i]
		var sway := sin(_t * 0.9 - i * 0.5) * 0.03
		var tgt := Vector3(float(neck_p[i]) + sway, neck_yaw * (0.12 + i * 0.03), 0)
		seg.rotation = Vector3(lerp_angle(seg.rotation.x, tgt.x, k), lerp_angle(seg.rotation.y, tgt.y, k), 0)
	head.rotation = Vector3(lerp_angle(head.rotation.x, head_p, k), lerp_angle(head.rotation.y, neck_yaw * 0.2, k),
		lerp_angle(head.rotation.z, head_roll, k))
	jaw.rotation.x = lerpf(jaw.rotation.x, -jaw_open, clampf(delta * 14.0, 0.0, 1.0))
	mouth_mat.albedo_color.a = lerpf(mouth_mat.albedo_color.a, mouth_a, clampf(delta * 8.0, 0.0, 1.0))
	mouth_glow.scale = Vector3(0.7, 0.5, 1.4) * (0.4 + mouth_mat.albedo_color.a * 0.6)
	throat_mat.emission_energy_multiplier = lerpf(throat_mat.emission_energy_multiplier, throat * 5.0, k)

	# ---- legs
	for i in legs.size():
		var lg: Dictionary = legs[i]
		var off := 0.0 if i == 0 else PI
		var swing := sin(_phase + off) * 0.42 * _speed
		var raise := maxf(0.0, cos(_phase + off)) * 0.7 * _speed
		var hip_x := -rear + swing + crouch * 0.45
		var knee_x := raise - crouch * 0.9
		var ankle_x := -raise * 0.6 + crouch * 0.45
		if flying:
			hip_x = -0.9
			knee_x = 1.1
			ankle_x = 0.5
		elif _action == "takeoff" and _action_t < _action_dur * 0.3:
			knee_x = 0.5
		_rot_x(lg["hip"], hip_x, k)
		_rot_x(lg["knee"], knee_x, k)
		_rot_x(lg["ankle"], ankle_x, k)
		_footstep(i, sin(_phase + off), lg["foot"], flying)
	for i in arms.size():
		var am: Dictionary = arms[i]
		var off2 := PI if i == 0 else 0.0
		var a_swing := sin(_phase + off2) * 0.4 * _speed
		var a_raise := maxf(0.0, cos(_phase + off2)) * 0.6 * _speed
		var al: float = arm_lift[i]
		var sh_x := -rear * 1.1 + a_swing + al
		var rc: float = arm_reach[i]
		var el_x := -a_raise - al * 1.1 * (1.0 - rc) + 0.35 * rc
		var wr_x := a_raise * 0.5 + al * 0.6 * (1.0 - rc) + float(arm_curl[i])
		if flying:
			sh_x = -0.5
			el_x = -0.9
			wr_x = 0.6
		var sh: Node3D = am["shoulder"]
		sh.rotation = Vector3(lerp_angle(sh.rotation.x, sh_x, k), 0, lerp_angle(sh.rotation.z, float(arm_swipe[i]) * float(am["side"]), k))
		_rot_x(am["elbow"], el_x, k)
		_rot_x(am["wrist"], wr_x, k)
		if not flying:
			_footstep(2 + i, sin(_phase + off2), am["wrist"], flying)

	# ---- tail: a wave travelling down the chain
	for i in tail.size():
		var seg2: Node3D = tail[i]
		var yaw := sin(_t * 1.2 - i * 0.55) * (0.05 + i * 0.012) + tail_extra * (0.1 + i * 0.025)
		yaw -= _turn * 0.04 * i
		var pitch := (0.24 if i == 0 else (0.12 if i < 3 else -0.03)) - tail_lift * (0.6 if i < 3 else 0.0)
		pitch += rear * (0.35 if i == 0 else 0.0)
		seg2.rotation = Vector3(lerp_angle(seg2.rotation.x, pitch, k), lerp_angle(seg2.rotation.y, yaw, k), 0)

	# ---- glow, shadow, whelp entrance, air sway
	if not preview and unit.has_aura("enraged"):
		heat += 3.0
	glow_mat.emission_energy_multiplier = heat
	for sk in skin_mats:
		(sk as ShaderMaterial).set_shader_parameter("heat", heat / 2.2)
	if blob:
		var h := 0.0 if preview else unit.position.y
		blob.position.y = 0.04 - h
		blob.scale = Vector3.ONE * clampf(1.0 - h * 0.05, 0.35, 1.0)
	if is_whelp and _spawn_t >= 0.0:
		_spawn_t += delta
		var f := _ease(_spawn_t / 1.5)
		root.position = Vector3(0, 16.0, 12.0).lerp(Vector3.ZERO, f)
		if _spawn_t >= 1.5:
			_spawn_t = -1.0
			root.position = Vector3.ZERO
	elif not is_whelp and not preview:
		var air := unit.untargetable and unit.position.y > 1.0
		var target_off := Vector3(sin(_t * 0.35) * 2.5, sin(_t * 0.7) * 0.6, sin(_t * 0.7) * 1.2) if air else Vector3.ZERO
		root.position = root.position.lerp(target_off, clampf(delta * 1.5, 0.0, 1.0))


## One forepaw swipe: windup from t0 to t1 (paw high and out, chest turned away), strike t1..t2 (paw rakes
## down and across, chest whips round), recover t2..t3.
func _swipe_pose(p: float, i: int, t0: float, t1: float, t2: float, t3: float) -> Dictionary:
	var sd := -1.0 if i == 0 else 1.0
	var w := _ease((p - t0) / (t1 - t0))
	var s := _ease((p - t1) / (t2 - t1))
	var r := _ease((p - t2) / (t3 - t2))
	var on := 1.0 - r
	return {"w": w, "s": s, "r": r, "fast": s > 0.0 and s < 1.0,
		"arm_lift": lerpf(2.3 * w, 0.85, s) * on,
		"arm_swipe": lerpf(0.95 * w, -0.6, s) * on,
		"neck": 0.4 * sd * w * (1.0 - s) * on,
		"reach": lerpf(0.75 * w, 1.0, s) * on,
		"curl": lerpf(0.7 * w, -0.6, s) * on,
		"twist": lerpf(-0.32 * sd * w, 0.38 * sd, s) * on,
		"rear": lerpf(0.2 * w, 0.0, s) * on,
		"lift": -0.25 * s * on}


## Fire the melee hit effects once the animation reaches the moment of contact.
func _hit_at(p: float, at: float, n: int) -> void:
	if p < at or _hits_done >= n or unit == null or not is_inside_tree():
		return
	_hits_done = n
	var t := _hit_target if is_instance_valid(_hit_target) else null
	match _action:
		"bite":
			if t != null:
				DragonFx.bite_hit(unit.world, t)
		"claw_l", "claw_r", "rake":
			var i := 0 if _action == "claw_l" or (_action == "rake" and n == 2) else 1
			DragonFx.claw_hit(unit.world, unit, t, _paw_pos(i), -1.0 if i == 0 else 1.0,
				_action == "rake", is_whelp)
		"stomp":
			var c := Vector3.ZERO
			for i in arms.size():
				c += _paw_pos(i)
			c /= float(arms.size())
			DragonFx.stomp_hit(unit.world, unit, Vector3(c.x, 0.0, c.z), t)


## Where front paw i (0 = left) is now: the model's wing hand when it wears the skin.
func _paw_pos(i: int) -> Vector3:
	return skin.hand_pos(i) if skin != null else (arms[i]["wrist"] as Node3D).global_position


func _pose_wing(w: Dictionary, spread: float, flap: float, lag: float, k: float) -> void:
	var s: float = w["side"]
	var sh: Node3D = w["shoulder"]
	var el: Node3D = w["elbow"]
	var wr: Node3D = w["wrist"]
	# folded: swept back and raised along the flank; open: straight out and flapping
	var sh_t := Vector3(lerpf(0.25, -0.12, spread), lerpf(-1.4, -0.12, spread) * s, lerpf(0.28, flap, spread) * s)
	var upstroke := maxf(0.0, -lag) * 0.35 * spread  # fold a little on the way up
	var el_t := Vector3(0, (lerpf(2.75, 0.28, spread) + upstroke) * s, lerpf(-0.2, -lag * 0.35, spread) * s)
	var wr_t := Vector3(0, (lerpf(-2.65, 0.0, spread) - upstroke * 0.6) * s, lerpf(-0.15, -lag * 0.25, spread) * s)
	sh.rotation = _lerp_rot(sh.rotation, sh_t, k)
	el.rotation = _lerp_rot(el.rotation, el_t, k)
	wr.rotation = _lerp_rot(wr.rotation, wr_t, k)
	for i in 4:
		var f: Node3D = w["fingers"][i]
		var a := lerpf(FINGER_FOLD[i], FINGER_SPREAD[i], spread)
		f.rotation = _lerp_rot(f.rotation, Vector3(0, a * s, -lag * 0.12 * i * spread * s), k)


func _lerp_rot(a: Vector3, b: Vector3, k: float) -> Vector3:
	return Vector3(lerp_angle(a.x, b.x, k), lerp_angle(a.y, b.y, k), lerp_angle(a.z, b.z, k))


func _rot_x(n: Node3D, x: float, k: float) -> void:
	n.rotation.x = lerp_angle(n.rotation.x, x, k)


func _lerp_arr(a: Array, b: Array, f: float) -> Array:
	var out: Array = []
	for i in a.size():
		out.append(lerpf(float(a[i]), float(b[i]), f))
	return out


static func _ease(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


func _pose_rest() -> void:
	pelvis.rotation.x = 0.04
	for i in neck.size():
		neck[i].rotation.x = NECK_REST[i]
	head.rotation.x = -0.3
	for w in wings:
		_pose_wing(w, 0.0, 0.0, 0.0, 1.0)


# ------------------------------------------------------------------ little effects

## Dust where a foot comes down while walking.
func _footstep(i: int, s: float, n: Node3D, flying: bool) -> void:
	var prev: float = _step_sign[i]
	_step_sign[i] = s
	if flying or is_whelp or _speed < 0.35 or unit == null or not is_inside_tree():
		return
	if prev > 0.0 and s <= 0.0:
		var p := n.global_position
		Vfx.burst(unit.world, Vector3(p.x, 0.3, p.z), {"amount": 6, "lifetime": 1.0, "vmin": 0.8, "vmax": 2.0,
			"direction": Vector3.UP, "spread": 80.0, "size": 1.6, "grow": true, "shader": "smoke", "spin": 40.0,
			"damping": 2.0, "colors": [Color(0.36, 0.28, 0.22, 0.55), Color(0.3, 0.24, 0.2, 0)]})


## Smoke and a few embers puffing out of the nostrils.
func _snort() -> void:
	for nos in nostrils:
		var p := Vfx.emitter({"amount": 8, "lifetime": 1.3, "vmin": 1.0, "vmax": 2.0, "direction": Vector3(0, -0.2, -1),
			"spread": 25.0, "damping": 1.5, "gravity": Vector3(0, 1.2, 0), "size": 0.8, "grow": true, "shader": "smoke",
			"spin": 50.0, "colors": [Color(0.25, 0.2, 0.18, 0.6), Color(0.2, 0.16, 0.15, 0)]})
		(nos as Node3D).add_child(p)
		p.restart()
		Vfx._free_after(p, 2.0)
	var e := Vfx.emitter({"amount": 10, "lifetime": 0.8, "vmin": 0.5, "vmax": 1.5, "direction": Vector3.DOWN,
		"spread": 40.0, "gravity": Vector3(0, -4, 0), "size": 0.12, "colors": [Color(1, 0.7, 0.3), Color(1, 0.3, 0.05, 0)]})
	mouth.add_child(e)
	e.restart()
	Vfx._free_after(e, 1.5)


## Roar: a gust of heat, embers and smoke out of the open jaws.
func _roar_breath() -> void:
	if not is_inside_tree():
		return
	var e := Vfx.emitter({"amount": 40, "lifetime": 1.0, "vmin": 4.0, "vmax": 9.0, "direction": Vector3(0, 0.4, -1),
		"spread": 30.0, "damping": 3.0, "size": 0.18, "colors": [Color(1, 0.8, 0.4), Color(1, 0.35, 0.05, 0)]})
	mouth.add_child(e)
	e.restart()
	Vfx._free_after(e, 1.6)
	var sm := Vfx.emitter({"amount": 14, "lifetime": 1.6, "vmin": 2.0, "vmax": 4.0, "direction": Vector3(0, 0.4, -1),
		"spread": 25.0, "damping": 2.0, "size": 2.2, "grow": true, "shader": "smoke", "spin": 40.0,
		"colors": [Color(0.25, 0.18, 0.15, 0.5), Color(0.2, 0.15, 0.13, 0)]})
	mouth.add_child(sm)
	sm.restart()
	Vfx._free_after(sm, 2.2)


## Effects that live exactly as long as a cast (so an interrupt removes them too).
func _update_cast_fx(cname: String) -> void:
	if cname == _cast_name:
		return
	_cast_name = cname
	if _cast_fx != null and is_instance_valid(_cast_fx):
		for c in _cast_fx.get_children():
			if c is GPUParticles3D:
				(c as GPUParticles3D).emitting = false
		var old := _cast_fx
		get_tree().create_timer(1.5).timeout.connect(func():
			if is_instance_valid(old):
				old.queue_free())
	_cast_fx = null
	if cname == "" or is_whelp:
		return
	_cast_fx = Node3D.new()
	match cname:
		"Flame Breath":  # embers drawn into the jaws
			mouth.add_child(_cast_fx)
			_cast_fx.add_child(Vfx.emitter({"amount": 50, "lifetime": 0.6, "one_shot": false, "vmin": 0.0, "vmax": 0.2,
				"sphere": 3.0, "radial": -14.0, "size": 0.2, "local": true,
				"colors": [Color(1, 0.6, 0.2, 0), Color(1, 0.7, 0.3, 1), Color(1, 0.95, 0.7, 1)]}))
			_cast_fx.add_child(Vfx.emitter({"amount": 16, "lifetime": 0.5, "one_shot": false, "vmin": 0.2, "vmax": 0.6,
				"sphere": 0.3, "size": 0.9, "grow": true, "shader": "flame", "local": true, "colors": DragonFx.FIRE}))
		"Cataclysm":  # flames spiralling up around the dragon
			add_child(_cast_fx)
			_cast_fx.add_child(Vfx.emitter({"amount": 120, "lifetime": 1.2, "one_shot": false, "vmin": 2.0, "vmax": 5.0,
				"direction": Vector3.UP, "spread": 10.0, "ring": [7.0, 4.0], "tangential": 9.0, "radial": -2.0,
				"size": 2.4, "grow": true, "shader": "flame", "local": true, "colors": DragonFx.FIRE}))
			_cast_fx.add_child(Vfx.emitter({"amount": 40, "lifetime": 1.0, "one_shot": false, "vmin": 0.0, "vmax": 0.4,
				"sphere": 9.0, "radial": -12.0, "size": 0.3, "local": true,
				"colors": [Color(1, 0.6, 0.2, 0), Color(1, 0.6, 0.2, 1), Color(1, 0.95, 0.7, 1)]}))
		_:
			_cast_fx.free()
			_cast_fx = null


# ------------------------------------------------------------------ death

func _animate_death(delta: float) -> void:
	_dead_t += delta
	_update_cast_fx("")
	var f := _ease(_dead_t / 2.4)
	var k := clampf(delta * 3.0, 0.0, 1.0)
	# rears up in agony, then crashes onto its side
	var agony := sin(clampf(_dead_t / 0.9, 0.0, 1.0) * PI) * (1.0 - f)
	pelvis.rotation.x = lerp_angle(pelvis.rotation.x, 0.45 * agony - 0.1 * f, k)
	pelvis.rotation.z = lerp_angle(pelvis.rotation.z, 1.05 * f, k)
	pelvis.position.y = lerpf(pelvis.position.y, lerpf(BODY_Y, 2.3, f), k)
	if is_whelp:
		root.position.y = lerpf(root.position.y, -0.4, k)
	for i in neck.size():
		var seg: Node3D = neck[i]
		seg.rotation = _lerp_rot(seg.rotation, Vector3(0.55 * agony - 0.12 * f, 0.15 * f, 0.1 * f), k)
	head.rotation = _lerp_rot(head.rotation, Vector3(0.5 * agony - 0.2 * f, 0.2 * f, 0.3 * f), k)
	jaw.rotation.x = lerpf(jaw.rotation.x, -0.8 * agony - 0.35 * f, k)
	for w in wings:
		_pose_wing(w, 0.75, -0.35 * f * float(w["side"]), 0.0, k * 0.5)
	wing_spread = lerpf(wing_spread, 0.15, k * 0.5)  # the skinned model folds its wings as it falls
	for i in tail.size():
		var seg2: Node3D = tail[i]
		seg2.rotation = _lerp_rot(seg2.rotation, Vector3(0.05, 0.12 * f, 0), k)
	for lg in legs:
		_rot_x(lg["hip"], -0.3 * f, k)
		_rot_x(lg["knee"], 0.6 * f, k)
	for am in arms:
		_rot_x(am["shoulder"], 0.4 * f, k)
		_rot_x(am["elbow"], -0.8 * f, k)
	eye_mat.emission_energy_multiplier = lerpf(eye_mat.emission_energy_multiplier, 0.0, clampf(delta, 0.0, 1.0))
	glow_mat.emission_energy_multiplier = lerpf(glow_mat.emission_energy_multiplier, 0.0, clampf(delta, 0.0, 1.0))
	for sk in skin_mats:
		var hv: float = (sk as ShaderMaterial).get_shader_parameter("heat")
		(sk as ShaderMaterial).set_shader_parameter("heat", lerpf(hv, 0.0, clampf(delta, 0.0, 1.0)))
	throat_mat.emission_energy_multiplier = 0.0
	mouth_mat.albedo_color.a = 0.0
