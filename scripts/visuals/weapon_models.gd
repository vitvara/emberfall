class_name WeaponModels
extends RefCounted
## Weapon and shield models (Quaternius Medieval Weapons, CC0, in assets/models/weapons/), mounted in
## the rigs' weapon frame: grip at the origin, blade along -Z. The packs model blades along +Y in
## arbitrary units, so each model is measured once: its length, and where the crossguard is (the
## widest slice of the lower part), so the hand lands on the handle whatever the model.

const DIR := "res://assets/models/weapons/"

static var _info := {}   # path -> {len, min_y, guard, cx, cz}


static func exists(file: String) -> bool:
	return ResourceLoader.exists(DIR + file)


## A blade `length` metres long (pommel to tip), blade along -Z, crossguard at z = guard_z.
static func blade(file: String, length: float, guard_z: float) -> Node3D:
	var path := DIR + file
	var info := _measure(path)
	var n: Node3D = (load(path) as PackedScene).instantiate()
	var k := length / float(info["len"])
	n.scale = Vector3.ONE * k
	n.rotation.x = -PI / 2.0   # model +Y -> -Z (and model +Z -> +Y)
	n.position = Vector3(-float(info["cx"]) * k, -float(info["cz"]) * k, guard_z + float(info["guard"]) * k)
	_stylize(n)
	var root := Node3D.new()
	root.add_child(n)
	return root


## A shield `height` metres tall, centred on the origin, its face toward -Z (the arm straps on +Z).
static func shield(file: String, height: float) -> Node3D:
	var path := DIR + file
	var info := _measure(path)
	var n: Node3D = (load(path) as PackedScene).instantiate()
	var k := height / float(info["len"])
	n.scale = Vector3.ONE * k
	n.rotation.y = PI   # the models face +Z
	var mid_y := float(info["min_y"]) + float(info["len"]) * 0.5
	n.position = Vector3(float(info["cx"]) * k, -mid_y * k, float(info["cz"]) * k)
	_stylize(n)
	var root := Node3D.new()
	root.add_child(n)
	return root


static func _stylize(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m != null:
				m = m.duplicate() as BaseMaterial3D
				m.roughness = maxf(m.roughness, 0.45)
				CharModel.stylize(m, 0.08)
				mi.set_surface_override_material(s, m)
	for c in n.get_children():
		_stylize(c)


static func _measure(path: String) -> Dictionary:
	if _info.has(path):
		return _info[path]
	var n: Node = (load(path) as PackedScene).instantiate()
	var pts := PackedVector3Array()
	_collect(n, Transform3D(), pts)
	n.free()
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var length := hi.y - lo.y
	# Crossguard: the widest slice in the lower 45% (for shields this is just some height; unused)
	var slices := 40
	var widths := []
	widths.resize(slices)
	widths.fill(0.0)
	var cx := (lo.x + hi.x) * 0.5
	for p in pts:
		var f := (p.y - lo.y) / maxf(length * 0.45, 0.0001)
		if f < 0.0 or f >= 1.0:
			continue
		var i := int(f * slices)
		widths[i] = maxf(float(widths[i]), absf(p.x - cx))
	var best := 0
	for i in slices:
		if float(widths[i]) > float(widths[best]):
			best = i
	var guard := lo.y + (best + 0.5) / slices * length * 0.45
	var info := {"len": length, "min_y": lo.y, "guard": guard, "cx": cx, "cz": (lo.z + hi.z) * 0.5}
	_info[path] = info
	return info


static func _collect(n: Node, xf: Transform3D, out: PackedVector3Array) -> void:
	var t := xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D:
		var mesh := (n as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				out.append(t * v)
	for c in n.get_children():
		_collect(c, t, out)
