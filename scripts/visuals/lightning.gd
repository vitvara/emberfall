class_name LightningBolt
extends MeshInstance3D
## Crackling electric arc between two points. Re-jitters every few frames,
## draws a wide soft glow plus a thin white-hot core, with a couple of branches.

var from := Vector3.ZERO
var to := Vector3.ZERO
var color := Color(0.6, 0.7, 1.0)
var life := 0.4
var width := 0.18

var _t := 0.0
var _rejit := 0.0
var _paths: Array = []
var _im: ImmediateMesh


func setup(a: Vector3, b: Vector3, c: Color, duration := 0.4, w := 0.18) -> LightningBolt:
	from = a
	to = b
	color = c
	life = duration
	width = w
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
	m.no_depth_test = true
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_jitter()


func _jitter() -> void:
	_paths.clear()
	_paths.append(_make_path(from, to, 22, 0.07))
	for i in 2:
		var main: Array = _paths[0]
		var k := randi_range(3, main.size() - 4)
		var start: Vector3 = main[k]
		var dir := (to - from).normalized()
		var off := Vector3(randf_range(-1, 1), randf_range(-0.3, 1), randf_range(-1, 1)).normalized()
		var end := start + (dir * 0.6 + off * 0.8).normalized() * from.distance_to(to) * randf_range(0.15, 0.3)
		_paths.append(_make_path(start, end, 6, 0.18))


func _make_path(a: Vector3, b: Vector3, segs: int, rough: float) -> Array:
	var pts: Array = [a]
	var len := a.distance_to(b)
	for i in range(1, segs):
		var f := float(i) / segs
		var p := a.lerp(b, f)
		p += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * len * rough * sin(f * PI)
		pts.append(p)
	pts.append(b)
	return pts


func _process(delta: float) -> void:
	_t += delta
	_rejit -= delta
	if _rejit <= 0.0:
		_rejit = 0.045
		_jitter()
	var fade := 1.0 - clampf(_t / life, 0.0, 1.0)
	var cam := get_viewport().get_camera_3d()
	_im.clear_surfaces()
	if cam == null or fade <= 0.0:
		if _t >= life:
			queue_free()
		return
	for pi in _paths.size():
		var w := width * (1.0 if pi == 0 else 0.55)
		_strip(_paths[pi], cam.global_position, w * 3.0, Color(color.r, color.g, color.b, 0.35 * fade))
		_strip(_paths[pi], cam.global_position, w, Color(1, 1, 1, 0.95 * fade))


func _strip(pts: Array, cam_pos: Vector3, w: float, c: Color) -> void:
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var p: Vector3 = pts[i]
		var nxt: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var prv: Vector3 = pts[maxi(i - 1, 0)]
		var dir := (nxt - prv).normalized()
		var side := dir.cross(cam_pos - p).normalized() * w * 0.5
		var taper := 1.0 - absf(float(i) / (pts.size() - 1) - 0.5) * 0.8
		_im.surface_set_color(c)
		_im.surface_add_vertex(p - side * taper)
		_im.surface_add_vertex(p + side * taper)
	_im.surface_end()
