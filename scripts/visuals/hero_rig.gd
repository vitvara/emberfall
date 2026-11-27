class_name HeroRig
extends Node3D
## Jointed low-poly hero with procedural animation:
## idle breathing, walk/run cycle, jump, casting pose, attack swings, flinch, death.
## Reads its parent Unit's state every frame; gameplay never reads from here.

var unit: Unit
var class_id := ""
var col := Color.WHITE

# Skeleton
var body: Node3D
var hips: Node3D
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var cape: Node3D
var robe: Node3D

# FX attachments
var cast_fx: GPUParticles3D
var cast_circle: MeshInstance3D
var cast_fx_l: GPUParticles3D
var hand_light: OmniLight3D
var bubble: MeshInstance3D
var bubble_mat: ShaderMaterial
var blob: MeshInstance3D
var trails: Array = []
var _bubble_a := 0.0
var _circle_i := 0.0
var shield_node: Node3D
var cast_orb: MeshInstance3D
var cast_orb_fx: GPUParticles3D
var cast_rays: GPUParticles3D
var circle_mat: ShaderMaterial
var sprint_fx: GPUParticles3D
var _spiral_timer := 0.0
var spiral: Node3D
var spiral_arms: Array = []   # [low_node, high_node, trail]
var hand_fx: Array = []
var focus_orb: MeshInstance3D
var aura_fx := {}

# Animation state
var _t := 0.0
var _phase := 0.0
var _speed := 0.0
var _last_flat := Vector3.ZERO
var _action := ""
var _action_t := 0.0
var _action_dur := 0.0
var _flinch := 0.0
var _dead_t := 0.0

const AURA_COLORS := {
	"blade_rhythm": Color(1, 0.9, 0.3),
	"healing_draught": Color(1, 0.35, 0.4),
	"quickening": Color(0.6, 0.65, 1),
	"final_prayer": Color(1, 0.9, 0.5),
	"fade": Color(0.35, 0.35, 0.45),
}


func build(cid: String, c: Color) -> HeroRig:
	class_id = cid
	col = c
	var skin := Models.mat(Color(0.96, 0.78, 0.64))
	var skin_dark := Models.mat(Color(0.85, 0.6, 0.48))
	var dark := Models.mat(Color(0.12, 0.1, 0.12))
	var white := Models.mat(Color(1, 1, 1))
	var leather := Models.mat(Color(0.42, 0.27, 0.16))
	var leather_dark := Models.mat(Color(0.25, 0.16, 0.1))
	var metal := Models.mat(Color(0.74, 0.78, 0.86), 0.0, 0.35)
	var gold := Models.mat(Color(1.0, 0.78, 0.3), 0.0, 0.35)
	var main := Models.mat(c)

	# --- skeleton (stylized: big head and hands, short sturdy legs)
	body = _node(self, Vector3.ZERO)
	hips = _node(body, Vector3(0, 0.8, 0))
	torso = _node(hips, Vector3.ZERO)
	head = _node(torso, Vector3(0, 0.64, 0))
	arm_l = _node(torso, Vector3(-0.36, 0.52, 0))
	arm_r = _node(torso, Vector3(0.36, 0.52, 0))
	elbow_l = _node(arm_l, Vector3(0, -0.3, 0))
	elbow_r = _node(arm_r, Vector3(0, -0.3, 0))
	hand_l = _node(elbow_l, Vector3(0, -0.3, 0))
	hand_r = _node(elbow_r, Vector3(0, -0.3, 0))
	leg_l = _node(hips, Vector3(-0.14, 0, 0))
	leg_r = _node(hips, Vector3(0.14, 0, 0))
	knee_l = _node(leg_l, Vector3(0, -0.38, 0))
	knee_r = _node(leg_r, Vector3(0, -0.38, 0))

	var chest_m := main
	var arm_m := main
	var leg_m := Models.mat(c.darkened(0.45))
	var hand_m := skin
	var boot_m := leather_dark
	match cid:
		"warden":
			chest_m = metal
			arm_m = metal
			hand_m = metal
			boot_m = metal
			leg_m = Models.mat(Color(0.3, 0.28, 0.33))
		"blademaster":
			chest_m = Models.mat(Color(0.3, 0.22, 0.15))
			arm_m = Models.mat(Color(0.26, 0.19, 0.13))
			leg_m = Models.mat(Color(0.2, 0.16, 0.12))
			hand_m = leather_dark

	# --- body
	Models.part(torso, Models.capsule(0.3, 0.72), chest_m, Vector3(0, 0.32, 0), Vector3.ZERO, Vector3(1.15, 1, 0.82))
	Models.part(hips, Models.sphere(0.27), leg_m, Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1, 0.7, 0.8))
	Models.part(hips, Models.cyl(0.29, 0.29, 0.12), leather, Vector3(0, 0.1, 0))              # belt
	Models.part(hips, Models.box(0.13, 0.11, 0.05), gold, Vector3(0, 0.1, -0.27))              # buckle
	# --- head & face
	Models.part(head, Models.sphere(0.27), skin, Vector3(0, 0.24, 0))
	for sx in [-1.0, 1.0]:
		Models.part(head, Models.sphere(0.055), white, Vector3(0.095 * sx, 0.26, -0.215), Vector3.ZERO, Vector3(1, 1.25, 0.6))
		Models.part(head, Models.sphere(0.032), dark, Vector3(0.095 * sx, 0.255, -0.25))
		Models.part(head, Models.box(0.11, 0.025, 0.03), dark, Vector3(0.1 * sx, 0.34, -0.235), Vector3(0, 0, -0.18 * sx))
		Models.part(head, Models.sphere(0.06), skin, Vector3(0.27 * sx, 0.24, 0.0), Vector3.ZERO, Vector3(0.5, 1, 0.8))  # ears
	Models.part(head, Models.sphere(0.048), skin_dark, Vector3(0, 0.2, -0.27))                # nose
	# --- arms (big mitts)
	for arm in [[arm_l, elbow_l, hand_l], [arm_r, elbow_r, hand_r]]:
		Models.part(arm[0], Models.capsule(0.095, 0.36), arm_m, Vector3(0, -0.15, 0))
		Models.part(arm[1], Models.capsule(0.09, 0.34), arm_m, Vector3(0, -0.15, 0))
		Models.part(arm[1], Models.cyl(0.11, 0.1, 0.12), leather if cid != "warden" else metal, Vector3(0, -0.24, 0))  # cuff
		Models.part(arm[2], Models.sphere(0.115), hand_m, Vector3(0, -0.02, 0))
	# --- legs (chunky boots)
	for leg in [[leg_l, knee_l], [leg_r, knee_r]]:
		Models.part(leg[0], Models.capsule(0.12, 0.44), leg_m, Vector3(0, -0.18, 0))
		Models.part(leg[1], Models.capsule(0.11, 0.4), boot_m, Vector3(0, -0.18, 0))
		Models.part(leg[1], Models.sphere(0.15), boot_m, Vector3(0, -0.36, -0.07), Vector3.ZERO, Vector3(1, 0.6, 1.5))
		Models.part(leg[1], Models.cyl(0.13, 0.12, 0.1), leather if cid != "warden" else gold, Vector3(0, -0.06, 0))  # boot cuff

	# --- class outfits
	match cid:
		"warden":
			var purple := Models.mat(Color(0.38, 0.27, 0.62))
			Models.part(torso, Models.box(0.36, 0.5, 0.03), purple, Vector3(0, 0.22, -0.26))          # tabard
			Models.part(torso, Models.box(0.14, 0.14, 0.035), gold, Vector3(0, 0.32, -0.28))
			Models.part(hips, Models.box(0.3, 0.36, 0.03), purple, Vector3(0, -0.14, -0.24))         # front flap
			for sx in [-1.0, 1.0]:
				var arm_node: Node3D = arm_l if sx < 0 else arm_r
				Models.part(arm_node, Models.sphere(0.22), metal, Vector3(0.05 * sx, 0.04, 0), Vector3.ZERO, Vector3(1.3, 0.85, 1.2))
				Models.part(arm_node, Models.sphere(0.2), gold, Vector3(0.05 * sx, -0.02, 0), Vector3.ZERO, Vector3(1.35, 0.3, 1.25))
				Models.part(arm_node, Models.cyl(0.0, 0.06, 0.22), gold, Vector3(0.08 * sx, 0.24, 0))
			# Great helm with crest; beard pokes out below
			Models.part(head, Models.sphere(0.3), metal, Vector3(0, 0.27, 0.01), Vector3.ZERO, Vector3(1, 0.98, 1.05))
			Models.part(head, Models.box(0.38, 0.05, 0.05), dark, Vector3(0, 0.27, -0.3))
			Models.part(head, Models.box(0.05, 0.2, 0.04), metal, Vector3(0, 0.2, -0.31))
			Models.part(head, Models.capsule(0.06, 0.62), Models.mat(Color(0.85, 0.15, 0.12)), Vector3(0, 0.6, 0.02), Vector3(PI / 2, 0, 0))
			Models.part(head, Models.sphere(0.17), Models.mat(Color(0.5, 0.28, 0.14)), Vector3(0, 0.02, -0.17), Vector3.ZERO, Vector3(1.1, 0.9, 0.7))
			# Kite shield on the left forearm
			var shield := _node(self, Vector3.ZERO)
			shield_node = shield
			Models.part(shield, Models.box(0.6, 0.72, 0.06), Models.mat(Color(0.34, 0.28, 0.62)), Vector3.ZERO)
			Models.part(shield, Models.box(0.66, 0.07, 0.07), gold, Vector3(0, 0.33, 0))
			Models.part(shield, Models.box(0.07, 0.7, 0.07), gold, Vector3(0, 0, -0.005))
			Models.part(shield, Models.box(0.66, 0.07, 0.07), gold, Vector3(0, -0.33, 0))
			Models.part(shield, Models.sphere(0.1), gold, Vector3(0, 0.05, -0.05))
			_sword(hand_r, metal, gold, 1.1, Color(0.75, 0.85, 1))
			cape = _cape(torso, purple, 0.58, 1.05)
		"oracle":
			robe = _robe(Models.mat(Color(0.98, 0.96, 0.88)), gold)
			Models.part(torso, Models.box(0.16, 0.55, 0.03), gold, Vector3(0, 0.22, -0.26))          # stole
			var mantle := TorusMesh.new()
			mantle.inner_radius = 0.18
			mantle.outer_radius = 0.34
			Models.part(torso, mantle, Models.mat(Color(0.95, 0.85, 0.55)), Vector3(0, 0.6, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
			Models.part(head, Models.capsule(0.2, 0.6), Models.mat(Color(0.86, 0.66, 0.35)), Vector3(0, 0.08, 0.14),
				Vector3(0.2, 0, 0), Vector3(1.3, 1, 0.7))                                              # long hair
			Models.part(head, Models.sphere(0.28), Models.mat(Color(0.86, 0.66, 0.35)), Vector3(0, 0.32, 0.03),
				Vector3.ZERO, Vector3(1.02, 0.75, 1.02))                                               # hair top
			var circlet := TorusMesh.new()
			circlet.inner_radius = 0.26
			circlet.outer_radius = 0.29
			Models.part(head, circlet, gold, Vector3(0, 0.36, 0), Vector3(0.12, 0, 0))
			Models.part(head, Models.sphere(0.04), Models.mat(Color(0.5, 0.85, 1), 3.0), Vector3(0, 0.38, -0.29))
			var halo := TorusMesh.new()
			halo.inner_radius = 0.2
			halo.outer_radius = 0.24
			Models.part(head, halo, Models.mat(Color(1, 0.9, 0.5), 3.0), Vector3(0, 0.72, 0.08), Vector3(0.25, 0, 0))
			var staff := _node(hand_r, Vector3.ZERO)
			Models.part(staff, Models.cyl(0.04, 0.045, 2.1), Models.mat(Color(0.55, 0.36, 0.18)), Vector3(0, 0.3, 0))
			var crescent := TorusMesh.new()
			crescent.inner_radius = 0.16
			crescent.outer_radius = 0.22
			Models.part(staff, crescent, gold, Vector3(0, 1.42, 0), Vector3(PI / 2, 0, 0))
			focus_orb = Models.part(staff, Models.sphere(0.12), Models.mat(Color(1, 0.95, 0.6), 4.0), Vector3(0, 1.42, 0))
		"blademaster":
			var hood_m := Models.mat(Color(0.2, 0.17, 0.15))
			Models.part(head, Models.sphere(0.31), hood_m, Vector3(0, 0.29, 0.05), Vector3.ZERO, Vector3(1.02, 1.0, 1.08))
			Models.part(head, Models.cyl(0.0, 0.14, 0.3), hood_m, Vector3(0, 0.5, 0.2), Vector3(-0.9, 0, 0))  # hood tip
			Models.part(head, Models.box(0.4, 0.13, 0.07), Models.mat(c.darkened(0.25)), Vector3(0, 0.13, -0.24))  # mask
			Models.part(torso, Models.box(0.12, 0.85, 0.36), Models.mat(c), Vector3(0, 0.3, 0), Vector3(0, 0, 0.55))  # sash
			Models.part(arm_r, Models.sphere(0.2), leather, Vector3(0.05, 0.04, 0), Vector3.ZERO, Vector3(1.3, 0.75, 1.15))
			for i in 3:
				Models.part(hips, Models.box(0.1, 0.12, 0.08), leather, Vector3(-0.2 + i * 0.2, 0.06, 0.26))  # pouches
			cape = _cape(torso, Models.mat(c.darkened(0.1)), 0.2, 0.7)
			_dagger(hand_l, metal, gold, Color(1, 0.95, 0.6))
			_dagger(hand_r, metal, gold, Color(1, 0.95, 0.6))
		"arcanist":
			var robe_m := Models.mat(c.darkened(0.3))
			var trim := Models.mat(Color(0.86, 0.9, 1.0))
			robe = _robe(robe_m, trim)
			Models.part(torso, Models.box(0.1, 0.6, 0.03), trim, Vector3(0, 0.22, -0.26))
			var collar := TorusMesh.new()
			collar.inner_radius = 0.2
			collar.outer_radius = 0.33
			Models.part(torso, collar, trim, Vector3(0, 0.62, 0.02), Vector3(-0.2, 0, 0), Vector3(1, 0.7, 1))
			var beard_m := Models.mat(Color(0.95, 0.95, 0.97))
			Models.part(head, Models.cyl(0.2, 0.02, 0.5), beard_m, Vector3(0, -0.02, -0.17), Vector3(0.2, 0, 0))   # long beard
			Models.part(head, Models.sphere(0.12), beard_m, Vector3(0, 0.15, -0.22), Vector3.ZERO, Vector3(1.6, 0.6, 0.8))  # moustache
			for sx in [-1.0, 1.0]:
				Models.part(head, Models.box(0.13, 0.045, 0.05), beard_m, Vector3(0.1 * sx, 0.35, -0.24), Vector3(0, 0, -0.25 * sx))
			var hat := _node(head, Vector3(0, 0.42, 0.02))
			var brim := Models.cyl(0.46, 0.46, 0.04)
			brim.radial_segments = 18
			Models.part(hat, brim, Models.mat(c.darkened(0.55)), Vector3.ZERO)
			Models.part(hat, Models.cyl(0.08, 0.26, 0.5), Models.mat(c.darkened(0.45)), Vector3(0, 0.26, 0.02))
			Models.part(hat, Models.cyl(0.0, 0.08, 0.35), Models.mat(c.darkened(0.45)), Vector3(0, 0.6, 0.12), Vector3(0.6, 0, 0))
			Models.part(hat, Models.cyl(0.265, 0.27, 0.07), trim, Vector3(0, 0.06, 0))
			Models.part(hips, Models.box(0.2, 0.26, 0.08), leather, Vector3(0.28, -0.05, 0.05))      # spellbook
			focus_orb = Models.part(hand_l, Models.sphere(0.13), Models.mat(Color(0.6, 0.85, 1.0), 5.0), Vector3(0, 0.08, -0.14))
			var frost := Vfx.emitter({"amount": 14, "lifetime": 0.8, "one_shot": false, "vmin": 0.1, "vmax": 0.4,
				"spread": 180.0, "sphere": 0.12, "size": 0.2, "local": false, "tex": "star",
				"colors": [Color(1, 1, 1, 1), Color(0.6, 0.85, 1, 0.8), Color(0.4, 0.6, 1, 0)]})
			focus_orb.add_child(frost)
			cape = _cape(torso, robe_m, 0.5, 0.95)
	Models.apply_outline(self, 0.022)
	_build_fx()
	return self


func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _sword(hand: Node3D, metal: Material, gold: Material, length: float, trail_col: Color) -> void:
	var s := _node(hand, Vector3.ZERO)
	s.rotation.x = -0.25
	Models.part(s, Models.box(0.1, 0.035, length), metal, Vector3(0, 0, -length / 2.0 - 0.12))
	Models.part(s, Models.box(0.03, 0.04, length * 0.8), Models.mat(Color(0.55, 0.6, 0.7)), Vector3(0, 0.005, -length / 2.0 - 0.1))
	Models.part(s, Models.box(0.36, 0.07, 0.07), gold, Vector3(0, 0, -0.1))
	Models.part(s, Models.cyl(0.035, 0.035, 0.22), leather_mat(), Vector3(0, 0, 0.02), Vector3(PI / 2, 0, 0))
	Models.part(s, Models.sphere(0.06), gold, Vector3(0, 0, 0.15))
	var base := _node(s, Vector3(0, 0, -0.25))
	var tip := _node(s, Vector3(0, 0, -length - 0.1))
	_add_trail(base, tip, trail_col)


func _dagger(hand: Node3D, metal: Material, gold: Material, trail_col: Color) -> void:
	var s := _node(hand, Vector3.ZERO)
	s.rotation.x = -0.4
	Models.part(s, Models.box(0.07, 0.02, 0.6), metal, Vector3(0, 0, -0.38))
	Models.part(s, Models.box(0.2, 0.04, 0.04), gold, Vector3(0, 0, -0.07))
	var base := _node(s, Vector3(0, 0, -0.12))
	var tip := _node(s, Vector3(0, 0, -0.68))
	_add_trail(base, tip, trail_col)


func leather_mat() -> Material:
	return Models.mat(Color(0.35, 0.22, 0.12))


func _add_trail(base: Node3D, tip: Node3D, c: Color) -> void:
	var t := WeaponTrail.new().setup(base, tip, c)
	t.life = 0.3
	add_child(t)
	trails.append(t)


func _robe(m: Material, hem_m: Material) -> Node3D:
	var r := _node(hips, Vector3(0, 0.08, 0))
	var mesh := Models.cyl(0.27, 0.5, 0.82)
	mesh.radial_segments = 16
	Models.part(r, mesh, m, Vector3(0, -0.41, 0))
	var hem := Models.cyl(0.51, 0.51, 0.07)
	hem.radial_segments = 16
	Models.part(r, hem, hem_m, Vector3(0, -0.8, 0))
	return r


func _cape(parent: Node3D, m: Material, width: float, length: float) -> Node3D:
	var c := _node(parent, Vector3(0, 0.6, 0.22))
	Models.part(c, Models.box(width, length, 0.035), m, Vector3(0, -length / 2.0, 0))
	return c


func _build_fx() -> void:
	var fx_col := _fx_color()
	cast_fx = Vfx.gather_emitter(fx_col)
	cast_fx.emitting = false
	hand_r.add_child(cast_fx)
	cast_fx_l = Vfx.gather_emitter(fx_col)
	cast_fx_l.emitting = false
	hand_l.add_child(cast_fx_l)
	hand_light = OmniLight3D.new()
	hand_light.light_color = fx_col
	hand_light.light_energy = 0.0
	hand_light.omni_range = 3.5
	hand_r.add_child(hand_light)
	cast_circle = Vfx.magic_circle(fx_col, 1.6, 0.0, 0.5)
	circle_mat = cast_circle.material_override as ShaderMaterial
	cast_circle.position.y = 0.06
	cast_circle.visible = false
	add_child(cast_circle)
	# Light streaks rising around the caster
	cast_rays = Vfx.emitter({"amount": 18, "lifetime": 0.7, "one_shot": false, "vmin": 3.0, "vmax": 5.0,
		"direction": Vector3.UP, "spread": 2.0, "ring": [1.35, 1.2], "size": 0.6, "streak": true, "stretch": 4.0,
		"local": true, "colors": [Color(fx_col.r, fx_col.g, fx_col.b, 0), Color(1, 1, 1, 0.9),
			Color(fx_col.r, fx_col.g, fx_col.b, 0)]})
	cast_rays.emitting = false
	add_child(cast_rays)
	# Spell forming between the hands (Arcanist): a spinning ice crystal with sparkles, no glow ball
	cast_orb = MeshInstance3D.new()
	cast_orb.mesh = Vfx.crystal_solid_mesh(2.2, 0.45)
	cast_orb.material_override = Vfx.ice_mat()
	cast_orb_fx = Vfx.emitter({"amount": 24, "lifetime": 0.5, "one_shot": false, "vmin": 0.0, "vmax": 0.2,
		"sphere": 1.6, "radial": -6.0, "tangential": 5.0, "size": 0.5, "tex": "star", "spin": 300.0, "local": true,
		"colors": [Color(fx_col.r, fx_col.g, fx_col.b, 0), Color(1, 1, 1, 1), Color(fx_col.r, fx_col.g, fx_col.b, 0)]})
	cast_orb_fx.position.y = 0.9
	cast_orb.add_child(cast_orb_fx)
	cast_orb.visible = false
	add_child(cast_orb)
	sprint_fx = Vfx.emitter({"amount": 30, "lifetime": 0.3, "one_shot": false, "vmin": 8.0, "vmax": 12.0,
		"direction": Vector3(0, 0, 1), "spread": 6.0, "box": Vector3(0.35, 0.6, 0.1), "size": 0.45, "streak": true,
		"stretch": 5.0, "colors": [Color(1, 1, 1, 0), Color(1, 1, 0.9, 0.7), Color(1, 1, 1, 0)]})
	sprint_fx.position = Vector3(0, 1.0, 0.3)
	sprint_fx.emitting = false
	add_child(sprint_fx)
	bubble = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.15
	sm.height = 2.3
	bubble.mesh = sm
	bubble_mat = Vfx.shield_mat(Color(1, 0.88, 0.45), 0.0)
	bubble.material_override = bubble_mat
	bubble.position.y = 1.0
	bubble.visible = false
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bubble)
	blob = Models.blob_shadow(0.75)
	add_child(blob)
	# Spiral ribbons that coil up around the caster while casting
	spiral = _node(self, Vector3.ZERO)
	for i in 3:
		var low := _node(spiral, Vector3.ZERO)
		var high := _node(spiral, Vector3.ZERO)
		var tr := WeaponTrail.new().setup(low, high, fx_col)
		tr.life = 0.5
		add_child(tr)
		spiral_arms.append([low, high, tr])
	# Hands wreathed in the class's element while casting
	for hnd in [hand_l, hand_r]:
		var e := Vfx.emitter({"amount": 22, "lifetime": 0.45, "one_shot": false, "vmin": 0.8, "vmax": 1.8,
			"direction": Vector3.UP, "spread": 25.0, "sphere": 0.12, "size": 0.45, "streak": true, "stretch": 1.8,
			"local": false, "colors": [Color(1, 1, 1, 0.9), Color(fx_col.r, fx_col.g, fx_col.b, 0.9),
				Color(fx_col.r * 0.6, fx_col.g * 0.6, fx_col.b * 0.6, 0)]})
		e.emitting = false
		hnd.add_child(e)
		hand_fx.append(e)
		var motes := Vfx.emitter({"amount": 10, "lifetime": 0.7, "one_shot": false, "vmin": 0.2, "vmax": 0.6,
			"sphere": 0.25, "size": 0.3, "tex": "star", "spin": 200.0, "local": false,
			"colors": [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(fx_col.r, fx_col.g, fx_col.b, 0)]})
		motes.emitting = false
		hnd.add_child(motes)
		hand_fx.append(motes)


func _fx_color() -> Color:
	match class_id:
		"oracle":
			return Color(1, 0.9, 0.5)
		"arcanist":
			return Color(0.55, 0.8, 1.0)
		"warden":
			return Color(0.6, 0.75, 1)
	return Color(1, 0.9, 0.3)


# ------------------------------------------------------------------ events

## One-shot animation: slash, dual, stab, bash, spin, shout, release, block, heal, light
func play(action: String) -> void:
	_action = action
	_action_t = 0.0
	_action_dur = {"slash": 0.45, "light": 0.32, "dual": 0.5, "stab": 0.3, "bash": 0.45, "spin": 0.5,
		"shout": 0.8, "release": 0.4, "block": 0.7, "heal": 0.6, "flurry": 0.5, "drink": 0.8,
		"throw": 0.45}.get(action, 0.4)
	if class_id == "blademaster":
		# Rogues strike fast
		_action_dur *= {"slash": 0.6, "light": 0.65, "dual": 0.7, "stab": 0.7, "spin": 0.8}.get(action, 1.0)


## Briefly coil glowing ribbons around the hero (buffs like Blade Rhythm).
func flash_spiral(c: Color, dur := 1.0) -> void:
	_spiral_timer = dur
	for arm in spiral_arms:
		(arm[2] as WeaponTrail).color = c


func hit(fraction: float) -> void:
	_flinch = clampf(_flinch + fraction * 6.0, 0.0, 1.0)


# ------------------------------------------------------------------ per-frame animation

func _process(delta: float) -> void:
	if unit == null:
		unit = get_parent() as Unit
		if unit == null:
			return
		_last_flat = unit.flat_pos()
	_t += delta
	var flat := unit.flat_pos()
	var v := flat.distance_to(_last_flat) / maxf(delta, 0.001)
	_last_flat = flat
	_speed = lerpf(_speed, clampf(v / GameData.MOVE_SPEED, 0.0, 1.3), clampf(delta * 10.0, 0.0, 1.0))
	if not unit.alive:
		_animate_death(delta)
		return
	if _dead_t > 0.0:
		# Resurrected: stand back up
		_dead_t = 0.0
		body.rotation.x = 0.0
		body.position.y = 0.0
	_animate_body(delta)
	_animate_fx(delta)


func _animate_body(delta: float) -> void:
	var s := _speed
	if s > 0.05:
		_phase += delta * (5.0 + 6.0 * s)
	var sw := sin(_phase)
	var airborne := unit.position.y > 0.05
	var casting := unit.is_casting()

	# Targets (Euler) for every joint
	var t_leg_l := Vector3(sw * 0.8 * s, 0, 0)
	var t_leg_r := Vector3(-sw * 0.8 * s, 0, 0)
	var t_knee_l := Vector3(-maxf(0.0, -cos(_phase)) * 1.1 * s - 0.05, 0, 0)
	var t_knee_r := Vector3(-maxf(0.0, cos(_phase)) * 1.1 * s - 0.05, 0, 0)
	var idle := sin(_t * 1.6)
	var t_arm_l := Vector3(-sw * 0.65 * s + idle * 0.03, 0, -0.1)
	var t_arm_r := Vector3(sw * 0.65 * s - idle * 0.03, 0, 0.1)
	var t_elb_l := Vector3(0.25 + 0.35 * s, 0, 0)
	var t_elb_r := Vector3(0.25 + 0.35 * s, 0, 0)
	var t_torso := Vector3(-0.14 * s + idle * 0.02, sw * 0.08 * s, 0)
	var t_head := Vector3(0.08 * s, 0, 0)
	var body_y := absf(sw) * 0.07 * s
	var body_rot_y := 0.0
	var lunge := 0.0
	var crouch := 0.0
	var crouch_base := 0.0

	# Class idle stance
	match class_id:
		"warden":
			t_arm_l.x += 0.35
			t_elb_l.x = 1.1
		"oracle":
			t_arm_r.x = 0.15 + sw * 0.15 * s
			t_elb_r.x = 0.55
		"arcanist":
			t_elb_l.x = 1.3
			t_arm_l.x = 0.2 + sw * 0.15 * s
		"blademaster":
			t_elb_l.x = 0.8
			t_elb_r.x = 0.8
			t_torso.x -= 0.08

	if airborne:
		t_leg_l = Vector3(0.9, 0, 0)
		t_leg_r = Vector3(0.3, 0, 0)
		t_knee_l = Vector3(-1.3, 0, 0)
		t_knee_r = Vector3(-0.7, 0, 0)
		t_arm_l = Vector3(0.4, 0, -0.7)
		t_arm_r = Vector3(0.4, 0, 0.7)

	# Rogue combat stance: low crouch, daggers forward, light bounce
	if class_id == "blademaster" and world_combat() and s < 0.25 and not airborne and _action == "":
		crouch_base = 0.12
		t_leg_l = Vector3(0.4, 0, -0.08)
		t_leg_r = Vector3(-0.3, 0, 0.08)
		t_knee_l = Vector3(-0.7, 0, 0)
		t_knee_r = Vector3(-0.55, 0, 0)
		t_torso.x = -0.3
		t_arm_l = Vector3(0.75, 0, -0.25)
		t_arm_r = Vector3(0.6, 0, 0.3)
		t_elb_l = Vector3(1.25, 0, 0)
		t_elb_r = Vector3(1.35, 0, 0)
		body_y = absf(sin(_t * 5.0)) * 0.03
	if casting:
		var w := sin(_t * 7.0) * 0.06
		if class_id == "arcanist":
			# Hands drawn together in front, shaping the spell
			t_arm_l = Vector3(1.05 + w, 0, 0.5)
			t_arm_r = Vector3(1.05 - w, 0, -0.5)
			t_elb_l = Vector3(0.75, 0, 0)
			t_elb_r = Vector3(0.75, 0, 0)
			t_torso.x += 0.08
			t_leg_l = Vector3(0.25, 0, -0.1)
			t_leg_r = Vector3(-0.2, 0, 0.1)
		elif class_id == "oracle":
			t_arm_r = Vector3(2.4 + w, 0, 0.1)
			t_elb_r = Vector3(0.2, 0, 0)
			t_arm_l = Vector3(1.0 - w, 0, 0.3)
			t_elb_l = Vector3(0.6, 0, 0)
		else:
			t_arm_l = Vector3(1.15 + w, 0, 0.25)
			t_arm_r = Vector3(1.15 - w, 0, -0.25)
			t_elb_l = Vector3(0.35, 0, 0)
			t_elb_r = Vector3(0.35, 0, 0)
		t_torso.x -= 0.06

	# One-shot actions override the base pose
	var k := clampf(delta * 16.0, 0.0, 1.0)
	if _action != "":
		_action_t += delta
		var p := _action_t / _action_dur
		k = clampf(delta * 30.0, 0.0, 1.0)
		match _action:
			"slash", "light":
				var up := 2.7 if _action == "slash" else 1.9
				var big := 1.0 if _action == "slash" else 0.5
				if p < 0.35:
					t_arm_r = Vector3(up, 0, 0.3)
					t_torso.y = 0.55 * big
					t_torso.x = 0.1
					crouch = 0.06 * big
				elif p < 0.7:
					# Lunge into the strike: step forward, drop the hips, twist through
					t_arm_r = Vector3(-0.3, 0, -0.4)
					t_elb_r = Vector3(0.1, 0, 0)
					t_torso.y = -0.6 * big
					t_torso.x = -0.35 * big
					lunge = 0.45 * big
					crouch = 0.2 * big
					t_leg_l = Vector3(0.75 * big, 0, 0)
					t_leg_r = Vector3(-0.6 * big, 0, 0)
					t_knee_l = Vector3(-0.7 * big, 0, 0)
					t_knee_r = Vector3(-0.3 * big, 0, 0)
			"dual":
				if p > 0.2 and p < 0.8:
					lunge = 0.35
					crouch = 0.18
					t_leg_l = Vector3(0.7, 0, 0)
					t_leg_r = Vector3(-0.55, 0, 0)
					t_knee_l = Vector3(-0.7, 0, 0)
					t_knee_r = Vector3(-0.3, 0, 0)
					t_torso.x = -0.3
				if p < 0.25:
					t_arm_r = Vector3(2.2, 0, 0.3)
				elif p < 0.5:
					t_arm_r = Vector3(-0.2, 0, -0.5)
					t_arm_l = Vector3(2.2, 0, -0.3)
					t_torso.y = -0.4
				elif p < 0.75:
					t_arm_l = Vector3(-0.2, 0, 0.5)
					t_torso.y = 0.4
			"stab":
				if p < 0.6:
					lunge = 0.5
					crouch = 0.15
					t_leg_l = Vector3(0.8, 0, 0)
					t_leg_r = Vector3(-0.6, 0, 0)
					t_knee_l = Vector3(-0.6, 0, 0)
					t_arm_r = Vector3(1.5, 0, -0.1)
					t_elb_r = Vector3(0.0, 0, 0)
					t_torso.y = -0.35
					t_torso.x = -0.2
			"bash":
				if p < 0.3:
					t_arm_l = Vector3(0.6, 0, -0.4)
					t_torso.y = 0.4
				elif p < 0.7:
					t_arm_l = Vector3(1.5, 0, 0.1)
					t_elb_l = Vector3(0.2, 0, 0)
					t_torso.y = -0.3
					t_torso.x = -0.3
					lunge = 0.5
					crouch = 0.15
					t_leg_l = Vector3(0.7, 0, 0)
					t_leg_r = Vector3(-0.6, 0, 0)
					t_knee_l = Vector3(-0.6, 0, 0)
			"spin":
				body_rot_y = p * TAU
				crouch = 0.2
				t_leg_l = Vector3(0.4, 0, -0.3)
				t_leg_r = Vector3(-0.3, 0, 0.3)
				t_knee_l = Vector3(-0.6, 0, 0)
				t_knee_r = Vector3(-0.6, 0, 0)
				t_arm_l = Vector3(0.2, 0, -1.4)
				t_arm_r = Vector3(0.2, 0, 1.4)
				t_elb_r = Vector3(0.1, 0, 0)
			"shout":
				if p < 0.8:
					t_arm_l = Vector3(0.5, 0, -1.1)
					t_arm_r = Vector3(0.5, 0, 1.1)
					t_head = Vector3(0.45, 0, 0)
					t_torso.x = 0.2
			"release":
				if p < 0.5:
					lunge = 0.15
					t_leg_l = Vector3(0.4, 0, 0)
					t_leg_r = Vector3(-0.3, 0, 0)
					t_arm_l = Vector3(1.55, 0, 0.15)
					t_arm_r = Vector3(1.55, 0, -0.15)
					t_elb_l = Vector3(0.0, 0, 0)
					t_elb_r = Vector3(0.0, 0, 0)
					t_torso.x = -0.2
			"block":
				t_arm_l = Vector3(1.4, 0, 0.3)
				t_elb_l = Vector3(1.3, 0, 0)
				t_torso.x = -0.1
			"heal":
				t_arm_r = Vector3(2.6, 0, 0.1)
				t_elb_r = Vector3(0.1, 0, 0)
				t_arm_l = Vector3(1.2, 0, -0.5)
			"flurry":
				# Three alternating dagger thrusts with a driving lunge
				var seg := int(p * 3.0)
				var sp := fposmod(p * 3.0, 1.0)
				var thrust := sin(sp * PI)
				lunge = 0.35 + 0.1 * thrust
				crouch = 0.18
				t_leg_l = Vector3(0.75, 0, 0)
				t_leg_r = Vector3(-0.6, 0, 0)
				t_knee_l = Vector3(-0.75, 0, 0)
				t_knee_r = Vector3(-0.35, 0, 0)
				t_torso.x = -0.35
				if seg % 2 == 0:
					t_arm_r = Vector3(0.6 + 1.0 * thrust, 0, -0.2)
					t_elb_r = Vector3(1.2 - 1.1 * thrust, 0, 0)
					t_torso.y = -0.4 * thrust
				else:
					t_arm_l = Vector3(0.6 + 1.0 * thrust, 0, 0.2)
					t_elb_l = Vector3(1.2 - 1.1 * thrust, 0, 0)
					t_torso.y = 0.4 * thrust
			"drink":
				t_arm_r = Vector3(1.9, 0, -0.35)
				t_elb_r = Vector3(2.3, 0, 0)
				t_head = Vector3(0.35, 0, 0)
			"throw":
				if p < 0.4:
					t_arm_r = Vector3(-0.9, 0, 0.3)
					t_torso.y = 0.5
					t_torso.x = 0.1
				else:
					t_arm_r = Vector3(2.4, 0, 0.1)
					t_elb_r = Vector3(0.2, 0, 0)
					t_torso.y = -0.4
					t_torso.x = -0.25
					lunge = 0.2
		if _action_t >= _action_dur:
			_action = ""

	# Hit flinch
	_flinch = maxf(0.0, _flinch - delta * 3.0)
	t_torso.x += _flinch * 0.45
	t_head.x += _flinch * 0.3

	_lerp_rot(leg_l, t_leg_l, k)
	_lerp_rot(leg_r, t_leg_r, k)
	_lerp_rot(knee_l, t_knee_l, k)
	_lerp_rot(knee_r, t_knee_r, k)
	_lerp_rot(arm_l, t_arm_l, k)
	_lerp_rot(arm_r, t_arm_r, k)
	_lerp_rot(elbow_l, t_elb_l, k)
	_lerp_rot(elbow_r, t_elb_r, k)
	_lerp_rot(torso, t_torso, k)
	_lerp_rot(head, t_head, k)
	body.position.y = lerpf(body.position.y, body_y, k)
	body.position.z = lerpf(body.position.z, -lunge, k)
	hips.position.y = lerpf(hips.position.y, 0.8 - maxf(crouch, crouch_base), k)
	_place_shield(t_arm_l.x > 1.2)
	body.rotation.y = body_rot_y
	body.rotation.x = 0.0
	if cape:
		cape.rotation.x = lerpf(cape.rotation.x, -(0.1 + 0.55 * s + sin(_t * 3.0) * 0.05) - (0.5 if airborne else 0.0), k * 0.5)
	if robe:
		robe.rotation.x = lerpf(robe.rotation.x, -0.12 * s + sin(_phase) * 0.04 * s, k)
	var swinging := _action in ["slash", "light", "dual", "stab", "bash", "spin", "flurry"] and _action_t < _action_dur * 0.8
	for tr in trails:
		tr.emitting = swinging
	if focus_orb:
		var pulse := 1.0 + sin(_t * 4.0) * 0.1 + (0.5 if casting else 0.0)
		focus_orb.scale = Vector3.ONE * lerpf(focus_orb.scale.x, pulse, k)


## The kite shield follows the left hand but stays upright, angled forward (square-on when blocking).
func _place_shield(blocking: bool) -> void:
	if shield_node == null:
		return
	var hp := to_local(hand_l.global_position)
	var face := 0.0 if blocking else 0.55
	var yaw := body.rotation.y + face
	shield_node.position = hp + Vector3(-0.08, 0.12, -0.1).rotated(Vector3.UP, yaw)
	shield_node.rotation = Vector3(body.rotation.x, yaw, 0)


func world_combat() -> bool:
	return unit != null and unit.world != null and unit.world.combat_active


func _lerp_rot(n: Node3D, target: Vector3, k: float) -> void:
	n.rotation = n.rotation.lerp(target, k)


func _animate_fx(delta: float) -> void:
	var casting := unit.is_casting()
	cast_fx.emitting = casting
	cast_fx_l.emitting = casting
	for e in hand_fx:
		e.emitting = casting
	spiral.position.y = -unit.position.y
	spiral.rotation.y += delta * 6.5
	for i in spiral_arms.size():
		var arm: Array = spiral_arms[i]
		var f := fposmod(_t * 0.9 + i / 3.0, 1.0)
		var ang := i * TAU / 3.0
		var r := lerpf(1.0, 0.45, f)
		var y := f * 2.3
		var dirv := Vector3(cos(ang), 0, sin(ang))
		(arm[0] as Node3D).position = dirv * r + Vector3(0, y, 0)
		(arm[1] as Node3D).position = dirv * (r + 0.05) + Vector3(0, y + 0.16, 0)
		var spiral_on := (casting and class_id == "oracle") or _spiral_timer > 0.0
		(arm[2] as WeaponTrail).emitting = spiral_on and f > 0.05 and f < 0.95
	hand_light.light_energy = lerpf(hand_light.light_energy, 2.0 if casting else 0.0, clampf(delta * 8.0, 0, 1))
	var prog := 0.0
	if casting:
		prog = 1.0 - float(unit.casting["remaining"]) / maxf(0.01, float(unit.casting["total"]))
	_circle_i = lerpf(_circle_i, 1.0 if casting else 0.0, clampf(delta * 8.0, 0, 1))
	circle_mat.set_shader_parameter("intensity", _circle_i)
	cast_circle.visible = false  # casting is shown with hand effects and rising light, not a ground circle
	cast_circle.scale = Vector3.ONE * (0.75 + 0.25 * minf(1.0, prog * 2.0))
	cast_circle.position.y = 0.06 - unit.position.y
	cast_rays.emitting = casting
	cast_rays.position.y = -unit.position.y
	# Arcanist: a frost orb grows between the hands while casting
	if class_id == "arcanist" and casting:
		cast_orb.visible = true
		var mid := to_local((hand_l.global_position + hand_r.global_position) * 0.5)
		cast_orb.position = mid + Vector3(0, -0.05, -0.15)
		cast_orb.scale = Vector3.ONE * (0.05 + 0.14 * prog)
		cast_orb.rotation.y += get_process_delta_time() * 6.0
	else:
		cast_orb.visible = false
	sprint_fx.emitting = unit.has_aura("sprint") and _speed > 0.3
	_spiral_timer = maxf(0.0, _spiral_timer - delta)
	blob.position.y = 0.03 - unit.position.y
	blob.scale = Vector3.ONE * clampf(1.0 - unit.position.y * 0.15, 0.5, 1.0)
	# Shield bubble while absorbs or defensive cooldowns are up
	var shield_col := Color(0, 0, 0, 0)
	if unit.total_absorb() > 0.0:
		shield_col = Color(1, 0.85, 0.4, 0.9)
	elif unit.has_aura("raise_shield"):
		shield_col = Color(0.45, 0.7, 1.0, 0.9)
	var want := shield_col.a
	_bubble_a = lerpf(_bubble_a, want, clampf(delta * 6.0, 0, 1))
	bubble.visible = _bubble_a > 0.02
	if bubble.visible:
		if want > 0.0:
			bubble_mat.set_shader_parameter("color", Color(shield_col.r, shield_col.g, shield_col.b))
		bubble_mat.set_shader_parameter("strength", _bubble_a * (0.85 + sin(_t * 3.0) * 0.1))
	# Buff auras
	for aid in AURA_COLORS:
		var on := unit.has_aura(aid)
		if on and not aura_fx.has(aid):
			var e := Vfx.aura_emitter(AURA_COLORS[aid], 0.6, 1.8)
			e.position.y = 0.2
			add_child(e)
			aura_fx[aid] = e
		if aura_fx.has(aid):
			aura_fx[aid].emitting = on


func _animate_death(delta: float) -> void:
	_dead_t += delta
	var f := clampf(_dead_t / 0.6, 0.0, 1.0)
	var ease_f := f * f * (3.0 - 2.0 * f)
	body.rotation.x = lerpf(0.0, PI / 2.0, ease_f)
	body.position.y = lerpf(0.0, 0.2, ease_f)
	_lerp_rot(arm_l, Vector3(0.3, 0, -1.2), 0.1)
	_lerp_rot(arm_r, Vector3(0.3, 0, 1.2), 0.1)
	_lerp_rot(leg_l, Vector3(0.2, 0, -0.15), 0.1)
	_lerp_rot(leg_r, Vector3(-0.1, 0, 0.15), 0.1)
	cast_fx.emitting = false
	cast_fx_l.emitting = false
	cast_rays.emitting = false
	cast_orb.visible = false
	sprint_fx.emitting = false
	_place_shield(false)
	hand_light.light_energy = 0.0
	cast_circle.visible = false
	bubble.visible = false
	for tr in trails:
		tr.emitting = false
	for e in aura_fx.values():
		e.emitting = false
