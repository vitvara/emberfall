class_name DragonSkin
extends RefCounted
## The sculpted wyvern model ("DRAGO" by Oscar Creativo, CC-BY 4.0, assets/models/dragon/drago.glb) worn by
## the boss DragonRig. The rig keeps doing all the animation work on its (now hidden) procedural skeleton, and
## every frame this copies that pose onto the model's bones:
##  - pelvis, chest, head and jaw copy the rotation they made away from their rest pose;
##  - the neck, tail, legs, wing arms and wing fingers aim along the matching procedural chain, so the
##    model takes the rig's shapes even though its own bones have other lengths and another rest pose;
##  - a wyvern has no front legs: with the wings folded on the ground its wing arms follow the rig's front
##    legs instead (it walks and claws on its wing wrists), and blend back to the wing chain as they spread.
## The model is then lowered so its toes stand on the ground. The model's own clip (a hover loop) is unused.

const PATH := "res://assets/models/dragon/drago.glb"
const SCALE := 1.8
const CHEST_RISE := 0.35   # wyvern stance: the chest carried higher than the rig's
const FLOOR := 0.35        # lowest a tail joint may sink (root units)
static var _scene: PackedScene

var rig: DragonRig
var model: Node3D
var sk: Skeleton3D
var n_bones := 0
var parent: PackedInt32Array
var rest_local: Array[Transform3D] = []
var rest_global: Array[Transform3D] = []
var aim_local: Array[Vector3] = []    # rest direction to the bone's child joint, in the bone's own frame
var rules: Dictionary = {}            # bone -> {"orient": Node3D} | {"aim": Callable}
var skel_in_root: Transform3D         # skeleton space -> rig root space (fixed)
var root_to_skel: Transform3D
var rot_skel_root: Basis              # rotation part of skel_in_root
var proc_rest: Dictionary = {}        # procedural node -> its rest basis in rig root space
var hip := -1
var head := -1
var hands: Array = []                 # wing hand bones [left, right]
var feet: Array = []                  # toe tip bones
var body: Array = []                  # [bone, radius in root units] for lying on the ground
var mouth_local: Transform3D
var ground := 0.0
var _g := 0.0                         # wing arm: 0 = wing chain, 1 = front leg chain
var _to_skel: Transform3D
var _dead := false
var G: Array[Transform3D] = []
var floored: Array = []               # bones whose chain must not dig into the ground (the tail)
var spread_only: Array = []           # wing fingers: aimed only as the wing opens; folded, they keep the
                                      # model's own folded shape (its rest pose) relative to the hand


static func available() -> bool:
	return ResourceLoader.exists(PATH)


## Load (and cache) the model scene; the menu preview calls this first, so the raid reuses it.
static func scene() -> PackedScene:
	if _scene == null and available():
		_scene = load(PATH)
	return _scene


func _init(r: DragonRig) -> void:
	rig = r
	model = scene().instantiate()
	model.name = "DragoModel"
	model.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * SCALE), Vector3.ZERO)
	rig.root.add_child(model)
	for n in model.find_children("Aset_nature_rock*", "", true, false):
		n.queue_free()  # the display rock it was posed on
	for ap in model.find_children("*", "AnimationPlayer", true, false):
		ap.queue_free()
	sk = model.find_children("*", "Skeleton3D", true, false)[0]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	skel_in_root = rig.root.global_transform.affine_inverse() * sk.global_transform
	root_to_skel = skel_in_root.affine_inverse()
	rot_skel_root = skel_in_root.basis.orthonormalized()

	n_bones = sk.get_bone_count()
	parent.resize(n_bones)
	for i in n_bones:
		parent[i] = sk.get_bone_parent(i)
		rest_local.append(sk.get_bone_rest(i))
		rest_global.append(rest_local[i] if parent[i] < 0 else rest_global[parent[i]] * rest_local[i])
	G.resize(n_bones)
	for i in n_bones:
		aim_local.append(Vector3.ZERO)
	for i in n_bones:  # aim along the first child, or (leaf bones) carry on from the parent
		var kids := sk.get_bone_children(i)
		if kids.size() > 0:
			aim_local[i] = rest_local[kids[0]].origin.normalized()
		elif parent[i] >= 0:
			var d := rest_global[i].origin - rest_global[parent[i]].origin
			aim_local[i] = (rest_global[i].basis.inverse() * d).normalized()

	hip = _b(_find("Hip"))
	head = _b(_find("Head"))
	for n in [rig.pelvis, rig.chest, rig.head, rig.jaw]:
		proc_rest[n] = _root_basis(n)

	_orient(_find("Hip"), rig.pelvis)
	# the model's rest pose has a sideways bend in the spine: aim the torso straight along the rig's back
	_aim(_find("Torso_01"), func() -> Vector3: return _dir(rig.pelvis, rig.chest))
	_aim(_find("Torso_02"), func() -> Vector3:
		return _skel_dir(_root_dir(rig.pelvis, rig.chest) + _root_basis(rig.chest).y * CHEST_RISE))
	_orient(_find("Head"), rig.head)
	_orient(_find("Lower_Jaw"), rig.jaw)
	_chain([_find("Neck_01"), _find("Neck_02"), _find("Neck_03")], func() -> Array:
		var pts: Array = []
		for s in rig.neck:
			pts.append(s)
		pts.append(rig.head)
		return pts)
	var tail_names: Array = []
	for i in 13:
		tail_names.append(_find("Tail_%02d" % (i + 1)))
		floored.append(_b(tail_names[i]))
	_chain(tail_names, func() -> Array:
		var pts: Array = rig.tail.duplicate()
		pts.append((rig.tail[9] as Node3D).to_global(Vector3(0, 0, 1.3)))
		return pts)

	for side in 2:
		var p := "l" if side == 0 else "r"
		var lg: Dictionary = rig.legs[side]
		_aim(_find(p + "Leg_01"), func() -> Vector3: return _dir(lg["hip"], lg["knee"]))
		_aim(_find(p + "Leg_02"), func() -> Vector3: return _dir(lg["knee"], lg["ankle"]))
		_aim(_find(p + "Leg_03"), func() -> Vector3:
			# digitigrade: the long foot stands almost upright, a little forward of the shin's line
			var fwd := -_root_basis(rig.pelvis).z
			fwd.y = 0.0
			return _skel_dir(Vector3.DOWN * 1.0 + fwd.normalized() * 0.18 + _root_dir(lg["knee"], lg["ankle"]) * 0.35))
		_aim(_find(p + "Leg_04"), func() -> Vector3:  # toes flat on the ground, pointing ahead
			var fwd := -_root_basis(rig.pelvis).z
			fwd.y = 0.0
			return _skel_dir(fwd.normalized() + Vector3.DOWN * 0.25))
		feet.append(_b(_find(p + "Middle_Toe_02")))
		feet.append(_b(_find(p + "Leg_04")))

		var w: Dictionary = rig.wings[side]
		var am: Dictionary = rig.arms[side]
		_aim(_find(p + "Arm_01"), func() -> Vector3: return _dir(w["shoulder"], w["elbow"]).slerp(_dir(am["shoulder"], am["elbow"]), _g))
		_aim(_find(p + "Arm_02"), func() -> Vector3: return _dir(w["elbow"], w["wrist"]).slerp(_dir(am["elbow"], am["wrist"]), _g))
		hands.append(_b(_find(p + "Hand")))
		var fingers := ["Index", "Middle", "Ring", "Pinky"]
		for f in 4:
			var tip: Node3D = w["tips"][f]
			for seg in 3:
				var nm := _find(p + fingers[f] + "_Finger_0%d" % (seg + 1))
				if nm != "":
					_aim(nm, func() -> Vector3: return _dir(w["wrist"], tip))
					spread_only.append(_b(nm))

	for nm in ["Hip", "Torso_01", "Torso_02", "Neck_02", "Head", "Tail_03", "Tail_06"]:
		body.append([_b(_find(nm)), 0.9 * SCALE])

	# mouth: just ahead of the tongue tip, facing forward (-Z of the mouth node = out of the jaws)
	var tongue := rest_global[_b(_find("Tongue_07"))].origin
	var fwd_skel := Vector3(0, 0, 1)
	var mouth_rest := Transform3D(Basis(Vector3.UP, PI), tongue + fwd_skel * 25.0)
	mouth_local = rest_global[head].affine_inverse() * mouth_rest


func _b(nm: String) -> int:
	var i := sk.find_bone(nm)
	assert(i >= 0, "DragonSkin: no bone " + nm)
	return i


## Bone name by prefix (the export appended running numbers to every bone).
func _find(prefix: String) -> String:
	for i in n_bones:
		if sk.get_bone_name(i).begins_with(prefix + "_"):
			return sk.get_bone_name(i)
	return ""


func _orient(nm: String, n: Node3D) -> void:
	rules[_b(nm)] = {"orient": n}


func _aim(nm: String, f: Callable) -> void:
	rules[_b(nm)] = {"aim": f}


## Fit a chain of model bones along a procedural chain of nodes/points (any counts on either side).
func _chain(names: Array, pts_fn: Callable) -> void:
	var n := names.size()
	for j in n:
		var a := float(j) / n
		var b := float(j + 1) / n
		_aim(names[j], func() -> Vector3:
			var pts: Array = pts_fn.call()
			return (_along(pts, b) - _along(pts, a)).normalized())


func _along(pts: Array, f: float) -> Vector3:
	var x := f * (pts.size() - 1)
	var i := clampi(int(floor(x)), 0, pts.size() - 2)
	return _skel_pt(pts[i]).lerp(_skel_pt(pts[i + 1]), x - i)


func _skel_pt(p) -> Vector3:
	return _to_skel * ((p as Node3D).global_position if p is Node3D else (p as Vector3))


func _dir(a: Node3D, b: Node3D) -> Vector3:
	return (_to_skel * b.global_position - _to_skel * a.global_position).normalized()


func _root_dir(a: Node3D, b: Node3D) -> Vector3:
	var inv := rig.root.global_transform.affine_inverse()
	return (inv * b.global_position - inv * a.global_position).normalized()


func _skel_dir(v_root: Vector3) -> Vector3:
	return (root_to_skel.basis * v_root).normalized()


func _root_basis(n: Node3D) -> Basis:
	return (rig.root.global_transform.affine_inverse() * n.global_transform).basis.orthonormalized()


## Pose the model from the rig. Call after the rig animated its procedural skeleton this frame.
func update(delta: float, grounded: bool, dead: bool) -> void:
	_to_skel = root_to_skel * rig.root.global_transform.affine_inverse()
	var fold := clampf(1.0 - rig.wing_spread * 1.6, 0.0, 1.0)
	_dead = dead
	_g = lerpf(_g, fold if grounded or dead else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	for i in n_bones:
		var par := parent[i]
		var g: Transform3D = rest_local[i] if par < 0 else G[par] * rest_local[i]
		var r: Dictionary = rules.get(i, {})
		if r.has("orient"):
			var n: Node3D = r["orient"]
			var d_root: Basis = _root_basis(n) * (proc_rest[n] as Basis).inverse()
			var d: Basis = rot_skel_root.inverse() * d_root * rot_skel_root
			g.basis = d * rest_global[i].basis
		elif r.has("aim"):
			var want: Vector3 = (r["aim"] as Callable).call()
			if i in floored:
				want = _keep_above(g.origin, want, i)
			var cur := (g.basis * aim_local[i]).normalized()
			if i in spread_only:
				want = cur.slerp(want, clampf(rig.wing_spread * 1.4, 0.0, 1.0))
			if want.length_squared() > 0.5 and cur.dot(want) > -0.999:
				g.basis = Basis(Quaternion(cur, want)) * g.basis
		if i == hip:
			g.origin = _to_skel * rig.pelvis.global_position
		G[i] = g
		var loc: Transform3D = g if par < 0 else G[par].affine_inverse() * g
		sk.set_bone_pose_rotation(i, loc.basis.get_rotation_quaternion())
		if i == hip:
			sk.set_bone_pose_position(i, loc.origin)

	# Stand on the ground: lowest toe (or, lying dead, the lowest part of the body) at y = 0.
	var low := INF
	if dead:  # lying on its side: rest the body on the ground (the folded legs may sink a little)
		for b in body:
			low = minf(low, (skel_in_root * G[b[0]].origin).y - float(b[1]))
	else:
		for f in feet:
			low = minf(low, (skel_in_root * G[f].origin).y - 0.12)
	if grounded or dead:
		ground = lerpf(ground, -low, clampf(delta * 10.0, 0.0, 1.0))
	model.position.y = ground

	var m := _skel_to_world() * G[head] * mouth_local
	rig.mouth.global_transform = Transform3D(m.basis.orthonormalized(), m.origin)


## Bend a tail segment up just enough that its far end stays above the floor.
func _keep_above(origin: Vector3, want: Vector3, i: int) -> Vector3:
	var kids := sk.get_bone_children(i)
	var ln := rest_local[kids[0]].origin.length() if kids.size() > 0 else 0.0
	var o_root := skel_in_root * origin
	var w_root := (rot_skel_root * want).normalized()
	if _dead:  # dead: the tail slumps along the ground instead of curling up with the rolled body
		w_root.y = minf(w_root.y, -0.08)
		w_root = w_root.normalized()
		want = (rot_skel_root.inverse() * w_root).normalized()
	var reach := ln * skel_in_root.basis.get_scale().x
	var end_y := o_root.y + ground + w_root.y * reach
	if end_y >= FLOOR or reach <= 0.0:
		return want
	var flat := Vector2(w_root.x, w_root.z)
	var need := clampf((FLOOR - o_root.y - ground) / reach, -1.0, 1.0)
	var h := sqrt(maxf(0.0, 1.0 - need * need))
	if flat.length() < 0.001:
		return want
	flat = flat.normalized() * h
	return _skel_dir(Vector3(flat.x, need, flat.y))


## Skeleton space -> world, including the ground offset.
func _skel_to_world() -> Transform3D:
	return rig.root.global_transform * Transform3D(Basis(), Vector3(0, ground, 0)) * skel_in_root


## World position of a wing hand (the "paw" the wyvern claws with). 0 = left, 1 = right.
func hand_pos(i: int) -> Vector3:
	return _skel_to_world() * G[hands[i]].origin


## World position of a hind foot. 0 = left, 1 = right.
func foot_pos(i: int) -> Vector3:
	return _skel_to_world() * G[feet[i * 2 + 1]].origin
