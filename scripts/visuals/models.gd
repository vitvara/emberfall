class_name Models
extends RefCounted
## Low-poly models built from primitive meshes — no asset files needed.
## Every model faces -Z (Godot's forward).

static var _outlines := {}


## Stylized material: toon (banded) lighting with a soft rim light.
static func mat(c: Color, emission := 0.0, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.6
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	return m


static func part(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3,
		rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


static func capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	return c


static func sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


static func cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 10
	return c


static func outline_mat(width: float) -> StandardMaterial3D:
	var key := int(width * 1000)
	if _outlines.has(key):
		return _outlines[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.06, 0.03, 0.03)
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.grow = true
	m.grow_amount = width
	_outlines[key] = m
	return m


## Adds a dark ink outline (inverted hull) to every solid, non-glowing mesh under `root`.
static func apply_outline(root: Node, width: float) -> void:
	for child in root.get_children():
		apply_outline(child, width)
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var sm := mi.material_override as ShaderMaterial
		if sm != null:
			# custom shaded surfaces opt in (e.g. the dragon's skin)
			if sm.get_meta("outline", false) and sm.next_pass == null and not (mi.mesh is BoxMesh or mi.mesh is ArrayMesh):
				sm.next_pass = outline_mat(width)
			return
		var m := mi.material_override as StandardMaterial3D
		if m == null or m.emission_enabled or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
				or m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or m.next_pass != null:
			return
		if mi.mesh is BoxMesh or mi.mesh is ArrayMesh:
			return  # split normals leave gaps; boxes read fine without
		m.next_pass = outline_mat(width)


## Soft dark circle under a character so it reads clearly from above.
static func blob_shadow(radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0, 0, 0, 0.45)
	m.albedo_texture = Vfx.soft_tex()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.03
	return mi


static func make_hero(class_id: String, c: Color) -> Node3D:
	return HeroRig.new().build(class_id, c)


## Fire dragon. scale_factor 1.0 = raid boss, ~0.26 = whelp.
static func make_dragon(scale_factor := 1.0) -> Node3D:
	return DragonRig.new().build(scale_factor, scale_factor < 0.5)


static func make_target_ring() -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = 0.9
	t.outer_radius = 1.0
	t.rings = 32
	t.ring_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = t
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 0.9, 0.3)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(1, 0.05, 1)
	return mi
