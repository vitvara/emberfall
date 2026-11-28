class_name CharModel
extends Node3D
## A rigged, animated character built from Quaternius parts that share one 65-bone humanoid skeleton:
## an outfit (body, arms, legs, boots; "Ranger" or "Peasant"), the head, eyes and hair of a race body
## ("Orc_Male", "Elf_Female", ...) and the Universal Animation Library.
##
## The packs live in assets/models/quaternius/ (git-ignored: the race kit's licence forbids
## redistributing the raw files). available() says whether they are installed; HeroRig falls back to
## its old procedural body when they are not.
##
## The model faces -Z like every other unit, stands on y = 0 and is about 1.85 m tall.

const DIR := "res://assets/models/quaternius/"
const ANIM_PATH := DIR + "anim/UAL1_Standard.glb"
const HEAD_BONES := ["Head", "neck_01"]
## Clips the base (locomotion) layer can crossfade between.
const LOCO := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Jump", "Sword_Idle", "Spell_Simple_Idle", "Death01",
	"Idle_Talking", "Crouch_Idle", "Fixing_Kneeling", "Idle_Torch",
	# Universal Animation Library 2
	"Idle_Shield", "Idle_FoldArms", "Idle_Rail_Call", "Hit_Knockback", "Farm_Harvest", "Sword_Regular_Combo"]
const ANIM2_PATH := DIR + "anim/UAL2_Standard.glb"
const LOOPED := ["Sword_Idle", "Fixing_Kneeling", "Idle_Rail_Call", "Farm_Harvest", "Farm_Watering", "Sword_Regular_Combo"]

static var _head_cache := {}      # race -> {mesh_name: Mesh}
static var _anim_lib: AnimationLibrary

var skeleton: Skeleton3D
var tree: AnimationTree
var _bt: AnimationNodeBlendTree
var meshes: Array = []            # every MeshInstance3D of the character
var _current := ""


static func available() -> bool:
	return ResourceLoader.exists(ANIM_PATH) and ResourceLoader.exists(DIR + "outfits/Male_Ranger.gltf")


## race: "Orc_Male" | "Orc_Female" | "Elf_Male" | "Elf_Female"; outfit: "Ranger" | "Peasant".
## opts: hood (bool), pauldron (bool), tint (Color: multiplies the outfit cloth),
##       cloth_tex (outfit base-colour variant file name), skin_tint (Color for the bare arms/legs).
static func create(race: String, outfit: String, opts := {}) -> CharModel:
	var cm := CharModel.new()
	cm._build(race, outfit, opts)
	return cm


func _build(race: String, outfit: String, opts: Dictionary) -> void:
	var sex := "Female" if race.ends_with("Female") else "Male"
	var body: Node3D = (load(DIR + "outfits/%s_%s.gltf" % [sex, outfit]) as PackedScene).instantiate()
	body.rotation.y = PI   # the packs face +Z
	add_child(body)
	skeleton = body.get_node("Armature/Skeleton3D") as Skeleton3D
	var cloth_tex: Texture2D = null
	if opts.has("cloth_tex"):
		cloth_tex = load(DIR + "outfits/" + String(opts["cloth_tex"])) as Texture2D
	for c in skeleton.get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		var nm := String(mi.name)
		if nm.contains("Hood") and not opts.get("hood", false):
			mi.queue_free()
			continue
		if nm.contains("Pauldron") and not opts.get("pauldron", true):
			mi.queue_free()
			continue
		_tint_mesh(mi, opts, cloth_tex)
		meshes.append(mi)
	# Head, eyes and hair from the race body, bound to the outfit's skeleton (same bone names and order)
	var parts := _race_parts(race, opts.get("hood", false) or opts.get("no_hair", false))
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.name = p["name"]
		mi.mesh = p["mesh"]
		mi.skin = p["skin"]
		for s in mi.mesh.get_surface_count():
			var m = p["mats"][s] if s < p["mats"].size() else null
			if m != null:
				mi.set_surface_override_material(s, m)
		skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
		meshes.append(mi)
	_build_tree(body)


## Animation graph: a crossfading locomotion state, then two one-shot action layers on top of it,
## one for the whole body (standing still) and one for the upper body only (attacking on the move).
func _build_tree(body: Node3D) -> void:
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	body.add_child(tree)
	tree.root_node = NodePath("..")   # the library's tracks address "Armature/Skeleton3D:<bone>"
	tree.add_animation_library("", _library())
	_bt = AnimationNodeBlendTree.new()
	var tr := AnimationNodeTransition.new()
	tr.xfade_time = 0.2
	_bt.add_node("loco", tr)
	for i in LOCO.size():
		tr.add_input(LOCO[i])
		var a := AnimationNodeAnimation.new()
		a.animation = LOCO[i]
		_bt.add_node("a_" + LOCO[i], a)
		_bt.connect_node("loco", i, "a_" + LOCO[i])
	_bt.add_node("loco_speed", AnimationNodeTimeScale.new())
	_bt.connect_node("loco_speed", 0, "loco")
	var prev := "loco_speed"
	for k in ["full", "up"]:
		var act := AnimationNodeAnimation.new()
		act.animation = "Sword_Attack"
		_bt.add_node("act_" + k, act)
		_bt.add_node("act_speed_" + k, AnimationNodeTimeScale.new())
		_bt.connect_node("act_speed_" + k, 0, "act_" + k)
		var os := AnimationNodeOneShot.new()
		os.fadein_time = 0.08
		os.fadeout_time = 0.2
		if k == "up":
			os.filter_enabled = true
			var spine := skeleton.find_bone("spine_01")
			for b in skeleton.get_bone_count():
				if b == spine or _descends(b, spine):
					os.set_filter_path(NodePath("Armature/Skeleton3D:" + skeleton.get_bone_name(b)), true)
		_bt.add_node("os_" + k, os)
		_bt.connect_node("os_" + k, 0, prev)
		_bt.connect_node("os_" + k, 1, "act_speed_" + k)
		prev = "os_" + k
	_bt.connect_node("output", 0, prev)
	tree.tree_root = _bt
	tree.active = true


func _descends(b: int, ancestor: int) -> bool:
	var p := skeleton.get_bone_parent(b)
	while p >= 0:
		if p == ancestor:
			return true
		p = skeleton.get_bone_parent(p)
	return false


func _tint_mesh(mi: MeshInstance3D, opts: Dictionary, cloth_tex: Texture2D) -> void:
	for s in mi.mesh.get_surface_count():
		var src := mi.get_active_material(s) as BaseMaterial3D
		if src == null:
			continue
		var m := src.duplicate() as BaseMaterial3D
		var tex_path := m.albedo_texture.resource_path if m.albedo_texture else ""
		var is_skin := tex_path.contains("Regular_") or String(m.resource_name).to_lower().contains("skin")
		if is_skin:
			if opts.has("skin_tint"):
				m.albedo_color = opts["skin_tint"]
		else:
			if cloth_tex != null:
				m.albedo_texture = cloth_tex
			if opts.has("tint"):
				m.albedo_color = Color.WHITE.lerp(opts["tint"], 0.7)   # dye the cloth, keep leather and metal readable
		stylize(m)
		mi.set_surface_override_material(s, m)


## Readable in the game's dim, fire-lit scenes: a rim light and a soft glow of the material's own
## colours, so the character never turns into a black silhouette against the lava.
static func stylize(m: BaseMaterial3D, glow := 0.12) -> void:
	m.rim_enabled = true
	m.rim = 0.3
	m.rim_tint = 0.5
	m.emission_enabled = true
	m.emission = m.albedo_color
	m.emission_texture = m.albedo_texture
	m.emission_energy_multiplier = glow


## The race body's head (cut out of the full body: only triangles skinned to the head and neck),
## plus its eyes and hair (not hair under a hood). Cached per race.
static func _race_parts(race: String, hooded: bool) -> Array:
	var key := race + (":hood" if hooded else "")
	if _head_cache.has(key):
		return _head_cache[key]
	var src: Node = (load(DIR + race + ".glb") as PackedScene).instantiate()
	var sk := src.get_node("Armature/Skeleton3D") as Skeleton3D
	var out := []
	for c in sk.get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		var nm := String(mi.name)
		if nm.ends_with("_Horns") or (hooded and nm.ends_with("_Hair")):
			continue
		var mesh: Mesh = mi.mesh
		if nm.ends_with("_Body"):
			mesh = _head_only(mi.mesh, mi.skin)
		var mats := []
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m != null:
				m = m.duplicate() as BaseMaterial3D
				stylize(m, 0.06 if nm.ends_with("_Eyes") else 0.1)
			mats.append(m)
		out.append({"name": nm.replace("_Body", "_Head"), "mesh": mesh, "skin": mi.skin, "mats": mats})
	src.free()
	_head_cache[key] = out
	return out


static func _head_only(mesh: Mesh, skin: Skin) -> ArrayMesh:
	var keep_bind := {}
	for i in skin.get_bind_count():
		if String(skin.get_bind_name(i)) in HEAD_BONES:
			keep_bind[i] = true
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var vcount: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var per := bones.size() / maxi(vcount, 1)
		var is_head := PackedByteArray()
		is_head.resize(vcount)
		for v in vcount:
			var best := 0
			var bw := -1.0
			for k in per:
				if weights[v * per + k] > bw:
					bw = weights[v * per + k]
					best = bones[v * per + k]
			is_head[v] = 1 if keep_bind.has(best) else 0
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var kept := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			if is_head[idx[t]] and is_head[idx[t + 1]] and is_head[idx[t + 2]]:
				kept.append_array([idx[t], idx[t + 1], idx[t + 2]])
		arrays[Mesh.ARRAY_INDEX] = kept
		var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return out


## Both Universal Animation Libraries (same skeleton) merged into one; library 2 is optional.
static func _library() -> AnimationLibrary:
	if _anim_lib == null:
		_anim_lib = AnimationLibrary.new()
		for path in [ANIM_PATH, ANIM2_PATH]:
			if not ResourceLoader.exists(path):
				continue
			var src: Node = (load(path) as PackedScene).instantiate()
			var ap := src.get_node("AnimationPlayer") as AnimationPlayer
			for n in ap.get_animation_list():
				if _anim_lib.has_animation(n):
					continue
				var a: Animation = ap.get_animation(n).duplicate()
				if n in LOOPED:  # (Godot already loops the "_Loop" clips and drops the suffix)
					a.loop_mode = Animation.LOOP_LINEAR
				_anim_lib.add_animation(n, a)
			src.free()
		# Locomotion inputs whose clip is missing (library 2 not installed) fall back to Idle
		for n in LOCO:
			if not _anim_lib.has_animation(n):
				_anim_lib.add_animation(n, _anim_lib.get_animation("Idle"))
	return _anim_lib


func has_clip(nm: String) -> bool:
	return tree.has_animation(nm)


## Crossfade the base layer to a locomotion clip (one of LOCO); a non-looping one (Death01) holds
## its last frame.
func play_loop(nm: String, speed := 1.0) -> void:
	tree.set("parameters/loco_speed/scale", speed)
	if _current == nm:
		return
	_current = nm
	tree.set("parameters/loco/transition_request", nm)


## Play a one-shot clip over the base layer, then blend back. upper: arms and torso only, so the
## legs keep walking.
func play_once(nm: String, speed := 1.0, upper := false) -> void:
	var k := "up" if upper else "full"
	var other := "full" if upper else "up"
	tree.set("parameters/os_%s/request" % other, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	(_bt.get_node("act_" + k) as AnimationNodeAnimation).animation = nm
	tree.set("parameters/act_speed_%s/scale" % k, speed)
	tree.set("parameters/os_%s/request" % k, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func stop_once() -> void:
	for k in ["full", "up"]:
		tree.set("parameters/os_%s/request" % k, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func clip_length(nm: String) -> float:
	var a := tree.get_animation(nm)
	return a.length if a != null else 1.0


func current() -> String:
	return _current


func bone(nm: String) -> int:
	return skeleton.find_bone(nm)


## Attach a node to a bone (it follows the animated bone every frame).
func attach(bone_name: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone_name
	skeleton.add_child(ba)
	return ba
