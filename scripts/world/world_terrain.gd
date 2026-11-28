class_name WorldTerrain
extends Node3D
## The open world's ground (Terrain3D): flat where heroes walk (the farm, the road), rolling hills
## and ridges everywhere else, sinking under the lava sea north towards the Outpost's plateau.
## Paths, yards and fields are painted into the terrain's control map; slopes turn to rock and the
## shore to dark volcanic soil.
##
## Gameplay stays on flat ground (y = 0): height() is 0 on every walkable spot, so units, hazards and
## the netcode need no ground heights. Props off the walkable area use height() to sit on the hills.
## All coordinates here are hub-local (the HubWorld node's space).

const SPACING := 2.0                       # metres between terrain vertices
const AREA := Rect2(-320, -120, 640, 680)  # hub-local x/z extent that gets heights and paint
const SHORE_Z0 := 112.0                    # under the lava north of here...
const SHORE_Z1 := 158.0                    # ...rising to farmland by here

enum Tex { GRASS, DIRT, ROCK, ASH }

static var _n1: FastNoiseLite
static var _n2: FastNoiseLite

var terrain: Terrain3D
var hub: HubWorld
var paint_paths: Array = []     # [Vector2 a, Vector2 b, half width]: dirt tracks (hub-local)
var paint_yards: Array = []     # [Vector2 centre, radius, texture]: dirt yards, scorched ground


static func _noise() -> void:
	if _n1 != null:
		return
	_n1 = FastNoiseLite.new()
	_n1.seed = 77
	_n1.frequency = 0.012
	_n1.fractal_octaves = 3
	_n2 = FastNoiseLite.new()
	_n2.seed = 1234
	_n2.frequency = 0.004
	_n2.fractal_octaves = 2


## Distance from a hub-local point to the nearest walkable ground (0 inside it).
static func _walk_dist(x: float, z: float) -> float:
	var farm := Vector2(x - HubWorld.FARM_C.x, z - HubWorld.FARM_C.z).length() - (FarmRegion.FARM_RADIUS + 7.0)
	var road := 1e9
	if z > HubWorld.WALL_RADIUS - 5.0 and z < HubWorld.FARM_C.z:
		road = absf(x) - (HubWorld.ROAD_HALF + 5.0)
	return maxf(minf(farm, road), 0.0)


## Ground height (hub-local) at x, z: 0 wherever heroes walk.
static func height(x: float, z: float) -> float:
	_noise()
	var d := _walk_dist(x, z)
	var n1 := _n1.get_noise_2d(x, z) * 0.5 + 0.5
	var n2 := _n2.get_noise_2d(x, z) * 0.5 + 0.5
	var h := smoothstep(0.0, 26.0, d) * (3.0 + 9.0 * n1) + smoothstep(30.0, 120.0, d) * (10.0 + 26.0 * n2)
	# North: the land dips under the lava sea that surrounds the Outpost
	var shore := smoothstep(SHORE_Z0, SHORE_Z1, z)
	if Vector2(x, z).length() < HubWorld.WALL_RADIUS + 30.0:
		shore = 0.0
	return lerpf(-7.0, h, shore)


## Build the terrain (call once the hub is in the tree). Paths and yards should be registered first.
func build(world: HubWorld) -> void:
	hub = world
	_noise()
	terrain = Terrain3D.new()
	terrain.name = "Terrain3D"
	terrain.vertex_spacing = SPACING
	terrain.free_editor_textures = false   # assets are built in code, not saved to disk
	terrain.top_level = true            # Terrain3D works in global space; we convert from hub-local
	add_child(terrain)
	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.collision.mode = Terrain3DCollision.DISABLED
	var greens := _texture(Color(0.24, 0.4, 0.11), Color(0.36, 0.54, 0.17), 0.03, 0.06)
	var dirt := _texture(Color(0.42, 0.31, 0.18), Color(0.6, 0.47, 0.3), 0.07, 0.09)
	var rock := _texture(Color(0.3, 0.29, 0.28), Color(0.5, 0.48, 0.45), 0.05, 0.05)
	var ash := _texture(Color(0.1, 0.08, 0.07), Color(0.24, 0.19, 0.16), 0.06, 0.07)
	for i in 4:
		terrain.assets.set_texture_asset(i, [greens, dirt, rock, ash][i])
	var w := int(AREA.size.x / SPACING)
	var hgt := int(AREA.size.y / SPACING)
	var himg := Image.create_empty(w, hgt, false, Image.FORMAT_RF)
	var cimg := Image.create_empty(w, hgt, false, Image.FORMAT_RF)
	for py in hgt:
		var z := AREA.position.y + py * SPACING
		for px in w:
			var x := AREA.position.x + px * SPACING
			var h := height(x, z)
			himg.set_pixel(px, py, Color(h, 0, 0, 1))
			cimg.set_pixel(px, py, Color(_control(x, z, h), 0, 0, 1))
	var origin := hub.global_position + Vector3(AREA.position.x, 0, AREA.position.y)
	terrain.data.import_images([himg, cimg, null], origin, 0.0, 1.0)


## Which ground texture shows at x, z (Terrain3D control value).
func _control(x: float, z: float, h: float) -> float:
	var base := Tex.GRASS
	var overlay := Tex.GRASS
	var blend := 0.0
	# Slopes turn to rock
	var dx := height(x + 1.0, z) - height(x - 1.0, z)
	var dz := height(x, z + 1.0) - height(x, z - 1.0)
	var slope := Vector2(dx, dz).length() * 0.5
	if slope > 0.35:
		overlay = Tex.ROCK
		blend = clampf((slope - 0.35) / 0.5, 0.0, 1.0)
	# Dark volcanic soil along the lava shore
	if z < SHORE_Z1 + 18.0:
		var s := 1.0 - smoothstep(SHORE_Z1 - 20.0, SHORE_Z1 + 18.0, z)
		if s > blend:
			overlay = Tex.ASH
			blend = s
	if h < -0.5:
		base = Tex.ASH
	# Painted tracks and yards
	var p := Vector2(x, z)
	for y in paint_yards:
		var dd: float = p.distance_to(y[0]) - float(y[1])
		if dd < 2.0:
			var b := clampf(1.0 - dd / 2.0, 0.0, 1.0)
			if b > blend or overlay == int(y[2]):
				overlay = int(y[2])
				blend = maxf(blend, b)
	for r in paint_paths:
		var a: Vector2 = r[0]
		var ab: Vector2 = r[1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var dd := p.distance_to(a + ab * t) - float(r[2])
		if dd < 1.5:
			var b := clampf(1.0 - dd / 1.5, 0.0, 1.0)
			if b > blend or overlay == Tex.DIRT:
				overlay = Tex.DIRT
				blend = maxf(blend, b)
	var bits := Terrain3DUtil.enc_base(base) | Terrain3DUtil.enc_overlay(overlay) | Terrain3DUtil.enc_blend(int(blend * 255.0))
	return Terrain3DUtil.as_float(bits)


## A stylised, tileable ground texture: two-tone noise (height in alpha) and a matching normal map.
func _texture(c0: Color, c1: Color, freq: float, uv_scale: float) -> Terrain3DTextureAsset:
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.fractal_octaves = 3
	var img := n.get_seamless_image(256, 256, false, false, 0.1, true)
	img.convert(Image.FORMAT_RGBA8)
	var nrm := img.duplicate() as Image
	for y in 256:
		for x in 256:
			var v := img.get_pixel(x, y).r
			var c: Color = c0.lerp(c1, v)
			c.a = v
			img.set_pixel(x, y, c)
	nrm.bump_map_to_normal_map(3.0)
	nrm.convert(Image.FORMAT_RGBA8)
	for y in 256:
		for x in 256:
			var c: Color = nrm.get_pixel(x, y)
			c.a = 0.85   # roughness
			nrm.set_pixel(x, y, c)
	img.generate_mipmaps()
	nrm.generate_mipmaps()
	var ta := Terrain3DTextureAsset.new()
	ta.albedo_texture = ImageTexture.create_from_image(img)
	ta.normal_texture = ImageTexture.create_from_image(nrm)
	ta.uv_scale = uv_scale
	return ta


## The causeway's stone road across the lava, from the camp's south gate to the farmland (Road Generator).
static func build_causeway_road(parent: Node3D, z0: float, z1: float) -> void:
	var stone := StandardMaterial3D.new()
	var n := FastNoiseLite.new()
	n.frequency = 0.08
	var nt := NoiseTexture2D.new()
	nt.noise = n
	nt.seamless = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.22, 0.2, 0.19))
	ramp.set_color(1, Color(0.42, 0.38, 0.34))
	nt.color_ramp = ramp
	stone.albedo_texture = nt
	stone.uv1_triplanar = true
	stone.uv1_world_triplanar = true
	stone.uv1_scale = Vector3.ONE * 0.35
	stone.roughness = 0.9
	var under := StandardMaterial3D.new()
	under.albedo_color = Color(0.13, 0.11, 0.1)
	under.roughness = 1.0
	var mgr := RoadManager.new()
	mgr.name = "Roads"
	parent.add_child(mgr)
	var cont := RoadContainer.new()
	cont.name = "Causeway"
	cont.flatten_terrain = false
	cont.material_resource = stone
	cont.material_underside = under
	cont.underside_thickness = 3.0
	mgr.add_child(cont)
	cont._auto_refresh = false
	var prev: RoadPoint = null
	var steps := 6
	for i in steps + 1:
		var rp := RoadPoint.new()
		rp.name = "RP_%d" % i
		cont.add_child(rp)
		rp.auto_lanes = false
		rp.traffic_dir = [RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD] as Array[RoadPoint.LaneDir]
		rp.lanes = [RoadPoint.LaneType.NO_MARKING, RoadPoint.LaneType.NO_MARKING] as Array[RoadPoint.LaneType]
		rp.lane_width = HubWorld.ROAD_HALF * 0.85
		rp.shoulder_width_l = 0.8
		rp.shoulder_width_r = 0.8
		rp.flatten_terrain = false
		rp.position = Vector3(0, 0.02, lerpf(z0, z1, float(i) / steps))
		if prev != null:
			prev.connect_roadpoint(RoadPoint.PointInit.NEXT, rp, RoadPoint.PointInit.PRIOR)
		prev = rp
	cont._auto_refresh = true
	cont.rebuild_segments(true)
