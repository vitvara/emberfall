class_name WeaponTrail
extends MeshInstance3D
## Glowing ribbon swept by a weapon (swing trails). Records base/tip positions each
## frame while `emitting` and draws a fading triangle strip in world space.

var base_node: Node3D
var tip_node: Node3D
var color := Color(1, 1, 1)
var emitting := false
var life := 0.2
var fade_pow := 1.0  # > 1: bright leading edge that falls off fast (a streak, not a sheet)

var _pts: Array = []  # [base: Vector3, tip: Vector3, age: float]
var _im: ImmediateMesh


func setup(base: Node3D, tip: Node3D, c: Color) -> WeaponTrail:
	base_node = base
	tip_node = tip
	color = c
	return self


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_im = ImmediateMesh.new()
	mesh = _im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	for p in _pts:
		p[2] = float(p[2]) + delta
	while not _pts.is_empty() and float(_pts[0][2]) > life:
		_pts.pop_front()
	if emitting and is_instance_valid(tip_node) and is_instance_valid(base_node):
		_pts.append([base_node.global_position, tip_node.global_position, 0.0])
	_im.clear_surfaces()
	if _pts.size() < 2:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in _pts:
		var a := pow(1.0 - float(p[2]) / life, fade_pow)
		_im.surface_set_color(Color(color.r, color.g, color.b, 0.0))
		_im.surface_add_vertex(p[0])
		_im.surface_set_color(Color(lerpf(color.r, 1.0, a * 0.5), lerpf(color.g, 1.0, a * 0.5),
			lerpf(color.b, 1.0, a * 0.5), a * 0.9))
		_im.surface_add_vertex(p[1])
	_im.surface_end()
