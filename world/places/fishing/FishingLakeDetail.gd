extends RefCounted
## Static bed and shoreline detail. Three batched draws, no per-frame work.
const GROUND := preload("res://assets/regions/source/world/harbor/UrbanGround.gd")

static func build(site: Node3D) -> void:
	var bed := SurfaceTool.new()
	bed.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in 8:
		var inner := float(ring) / 8.0
		var outer := float(ring + 1) / 8.0
		for index in 72:
			var angle := TAU * float(index) / 72.0
			var next := TAU * float(index + 1) / 72.0
			var a := _bed_point(site, angle, inner)
			var b := _bed_point(site, next, inner)
			var c := _bed_point(site, angle, outer)
			var d := _bed_point(site, next, outer)
			_triangle(bed, a, b, c)
			_triangle(bed, b, d, c)
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color("333d2c")
	soil.albedo_texture = GROUND.texture("gravel")
	soil.roughness = .97
	soil.uv1_scale = Vector3(.15, .15, .15)
	_finish(site, bed, soil, "SerenoLakeBed")
	var stones := SurfaceTool.new()
	stones.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pebble := SphereMesh.new()
	pebble.radial_segments = 7
	pebble.rings = 3
	pebble.radius = 1
	pebble.height = 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 16102026
	for index in 110:
		var angle := rng.randf() * TAU
		var reach := rng.randf_range(.52, .98)
		var point := _bed_point(site, angle, reach)
		var radius := rng.randf_range(.10, .36)
		point.y += radius * .22
		var form := Vector3(radius, radius * .38, radius * rng.randf_range(.7, 1.6))
		stones.append_from(pebble, 0, Transform3D(Basis(Vector3.UP, angle).scaled(form), point))
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color("485548")
	rock.roughness = .91
	_finish(site, stones, rock, "SerenoSubmergedStones")
	# Sparse reeds stay inside the guard, away from each cast corridor.
	var reeds := SurfaceTool.new()
	reeds.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in 22:
		var angle := TAU * float(index) / 22.0
		var clear := true
		for station in site.PLAYER_ANGLES + site.NPC_ANGLES:
			if absf(angle_difference(angle, float(station))) < .15: clear = false
		if not clear: continue
		var base: Vector3 = site._shore(angle) * Vector3(.979, 1, 1)
		base.y = -.04
		for stem in 5:
			var offset := Vector3(rng.randf_range(-.24,.24), 0, rng.randf_range(-.24,.24))
			var tip := base + offset + Vector3(rng.randf_range(-.14,.14),rng.randf_range(.30,.75),.07)
			var side := Vector3(.026,0,.015)
			_triangle(reeds, base + offset - side, tip, base + offset + side)
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color("657344")
	leaf.roughness = .94
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	_finish(site, reeds, leaf, "SerenoWaterReeds")

static func _bed_point(site: Node3D, angle: float, radius: float) -> Vector3:
	var center := Vector3(0, 0, -4)
	var point: Vector3 = center.lerp(site._shore(angle), radius)
	point.y = -.08 - pow(1.0 - radius, .65) * 1.65
	return point

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var points := [a,b,c] if (b-a).cross(c-a).y <= 0 else [a,c,b]
	for point in points:
		surface.set_normal(Vector3.UP)
		surface.set_uv(Vector2(point.x,point.z))
		surface.add_vertex(point)

static func _finish(parent: Node3D, surface: SurfaceTool, material: Material, title: String) -> void:
	var display := MeshInstance3D.new()
	display.name = title
	display.mesh = surface.commit()
	display.material_override = material
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(display)
