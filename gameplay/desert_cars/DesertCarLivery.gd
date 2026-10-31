extends RefCounted
## Authored, opaque race vinyl. One vertex-coloured mesh/material per car, shared
## by the catalog cache. The door cutter carries its triangles onto the door.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const OFFSET := .006
const LAYER_GAP := .002
static var _vinyl: StandardMaterial3D
static var _mesh_cache: Dictionary = {}


static func apply(root: Node3D, spec: Dictionary) -> void:
	var style := str(spec.get("livery", "none"))
	if style == "none" or style.is_empty():
		return
	var size: Array = spec["size"]
	var width := float(size[0])
	var height := float(size[1])
	var length := float(size[2])
	var radius := float(spec.wheel_radius)
	var shoulder := float(spec.get("shoulder", .98 if str(spec.body) == "pickup" else .78))
	var accent := Color(str(spec.get("livery_color", "efeee2")))
	var secondary := Color(str(spec.get("livery_secondary", "18282e")))
	var number := clampi(int(spec.get("race_number", 0)), 0, 99)
	var key := str(
		[
			size,
			radius,
			shoulder,
			str(spec.body),
			style,
			accent,
			secondary,
			number,
			spec.get("cabin_front", 0),
			spec.get("roof_front", 0),
			spec.get("roof_back", 0),
			spec.get("hood_flat_front", 0)
		]
	)
	if not _mesh_cache.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for side: float in [-1.0, 1.0]:
			_side_graphics(
				st, side, width, length, radius, shoulder, style, accent, secondary, number
			)
		_top_graphics(st, width, height, length, shoulder, spec, style, accent, secondary)
		var mesh: ArrayMesh = st.commit()
		if str(spec.body) == "coupe":
			mesh = _curved_mesh(mesh, spec, preload("res://gameplay/desert_cars/DesertZShape.gd"))
		else:
			mesh = _curved_mesh(
				mesh, spec, preload("res://gameplay/desert_cars/DesertCarCabin.gd"), true
			)
		_mesh_cache[key] = mesh
	var part := MeshInstance3D.new()
	part.name = "DesertRaceLivery"
	part.mesh = _mesh_cache[key]
	part.material_override = _material()
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.set_meta("desert_livery", style)
	part.set_meta("race_number", number)
	# Deliberately not door_cut_exempt: a vinyl-covered door must take its vinyl
	# with it. The material role is not paint, so respraying preserves the design.
	root.add_child(part)


static func _material() -> StandardMaterial3D:
	if _vinyl == null:
		_vinyl = StandardMaterial3D.new()
		_vinyl.resource_name = "race_livery"
		_vinyl.vertex_color_use_as_albedo = true
		_vinyl.roughness = .40
		_vinyl.metallic = .08
		# The thin decal has no inner door card and must never become the
		# dominant door paint. VehicleDoorBuilder explicitly handles this flag.
		_vinyl.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _vinyl


static func _side_graphics(
	st: SurfaceTool,
	side: float,
	width: float,
	length: float,
	radius: float,
	shoulder: float,
	style: String,
	accent: Color,
	secondary: Color,
	number: int
) -> void:
	var x := side * (width * .48 + OFFSET)
	var low := maxf(radius * 1.10, .33)
	var high := shoulder - .075
	var span := maxf(.24, high - low)
	var cream := Color("eee8cf")
	var charcoal := Color("131e27")
	# All broad shapes live between the wheel wells. Fender pinstripes sit
	# above their crowns, leaving tyres and the authored arch openings clear.
	match style:
		"rally":
			_side_poly(
				st,
				x,
				side,
				length,
				low,
				span,
				[
					Vector2(-.205, .02),
					Vector2(.180, .02),
					Vector2(.205, .43),
					Vector2(.015, .97),
					Vector2(-.155, .97)
				],
				charcoal,
				0
			)
			_side_poly(
				st,
				x,
				side,
				length,
				low,
				span,
				[Vector2(-.19, .03), Vector2(-.12, .03), Vector2(.010, .97), Vector2(-.06, .97)],
				accent,
				1
			)
			_side_poly(
				st,
				x,
				side,
				length,
				low,
				span,
				[Vector2(-.10, .03), Vector2(-.072, .03), Vector2(.058, .97), Vector2(.030, .97)],
				secondary,
				1
			)
			_side_poly(
				st,
				x,
				side,
				length,
				low,
				span,
				[Vector2(.106, .08), Vector2(.178, .08), Vector2(.19, .31), Vector2(.122, .48)],
				accent,
				1
			)
			# Three staggered rally checks, broad enough to read from the drag camera.
			for check in 3:
				var z := length * (-.193 + float(check) * .028)
				_side_rect(st, x, side, z, shoulder - .045, length * .021, .030, cream, 1)
			_number_badge(
				st, x, side, length * .061, low + span * .61, number, cream, charcoal, .21, 2
			)
		"drag":
			# A long arrow spear and a short counter-colour break make the muscle
			# silhouette read horizontally; the number occupies its own quiet area.
			_side_poly(
				st,
				x,
				side,
				length,
				low,
				span,
				[
					Vector2(-.205, .13),
					Vector2(.19, .13),
					Vector2(.205, .49),
					Vector2(.07, .92),
					Vector2(-.19, .92),
					Vector2(-.08, .58)
				],
				charcoal,
				0
			)
			_side_poly(
				st,
				x,
				side,
				length,
				low,
				span,
				[Vector2(-.20, .07), Vector2(.173, .07), Vector2(.196, .19), Vector2(-.185, .19)],
				accent,
				1
			)
			_side_poly(
				st,
				x,
				side,
				length,
				low,
				span,
				[
					Vector2(-.12, .79),
					Vector2(.069, .79),
					Vector2(.116, .63),
					Vector2(.18, .63),
					Vector2(.072, .97),
					Vector2(-.18, .97)
				],
				accent,
				1
			)
			_side_poly(
				st,
				x,
				side,
				length,
				low,
				span,
				[Vector2(.152, .18), Vector2(.184, .18), Vector2(.196, .43), Vector2(.182, .48)],
				secondary,
				2
			)
			_number_badge(
				st, x, side, length * .015, low + span * .47, number, charcoal, cream, .20, 2
			)
			_fender_line(st, x, side, length, radius, shoulder, accent)
		"gt":
			# Broken forward chevrons with a second, narrow pinline: an original
			# tuner graphic that remains legible as the car passes side-on.
			_side_poly(
				st,
				x,
				side,
				length,
				low,
				span,
				[
					Vector2(-.20, .02),
					Vector2(.19, .02),
					Vector2(.19, .31),
					Vector2(.048, .95),
					Vector2(-.045, .95),
					Vector2(.046, .51),
					Vector2(-.17, .51)
				],
				charcoal,
				0
			)
			_side_poly(
				st,
				x,
				side,
				length,
				low,
				span,
				[Vector2(-.19, .02), Vector2(-.12, .02), Vector2(.12, .97), Vector2(.05, .97)],
				accent,
				1
			)
			_side_poly(
				st,
				x,
				side,
				length,
				low,
				span,
				[Vector2(.09, .06), Vector2(.138, .06), Vector2(.012, .69), Vector2(-.021, .69)],
				accent,
				1
			)
			_side_poly(
				st,
				x,
				side,
				length,
				low,
				span,
				[
					Vector2(-.20, .62),
					Vector2(-.062, .62),
					Vector2(.004, .97),
					Vector2(-.019, .97),
					Vector2(-.077, .71),
					Vector2(-.194, .71)
				],
				secondary,
				2
			)
			_number_badge(
				st, x, side, -length * .090, low + span * .31, number, charcoal, cream, .18, 2
			)
			_fender_line(st, x, side, length, radius, shoulder, secondary)
		_:
			_side_poly(
				st,
				x,
				side,
				length,
				low,
				span,
				[Vector2(-.19, .10), Vector2(.19, .10), Vector2(.16, .27), Vector2(-.19, .27)],
				secondary,
				0
			)
			_side_poly(
				st,
				x,
				side,
				length,
				low,
				span,
				[Vector2(-.18, .33), Vector2(.11, .33), Vector2(.16, .40), Vector2(-.17, .40)],
				accent,
				1
			)


static func _fender_line(
	st: SurfaceTool,
	x: float,
	side: float,
	length: float,
	radius: float,
	shoulder: float,
	color: Color
) -> void:
	var y := maxf(shoulder - .035, radius * 2.0 + .014)
	if y + .012 >= shoulder:
		return
	for axle: float in [-1.0, 1.0]:
		_side_rect(st, x, side, axle * length * .315, y, length * .16, .014, color, 0)


static func _number_badge(
	st: SurfaceTool,
	x: float,
	side: float,
	z: float,
	y: float,
	number: int,
	background: Color,
	ink: Color,
	height: float,
	layer: int
) -> void:
	if number <= 0:
		return
	var width := height * 1.49
	_side_rect(st, x, side, z, y, width, height * 1.16, background, layer)
	# Seven-segment numerals are geometric race identifiers, not a font/label
	# viewport. Reverse the local horizontal axis on the far side for legibility.
	_digit(st, x, side, z + side * height * .34, y, floori(float(number) / 10.0), height, ink, layer + 1)
	_digit(st, x, side, z - side * height * .34, y, number % 10, height, ink, layer + 1)


static func _digit(
	st: SurfaceTool,
	x: float,
	side: float,
	z: float,
	y: float,
	digit: int,
	height: float,
	color: Color,
	layer: int
) -> void:
	const SEGMENTS := [63, 6, 91, 79, 102, 109, 125, 7, 127, 111]
	var mask: int = SEGMENTS[clampi(digit, 0, 9)]
	var half_width := height * .235
	var half_height := height * .43
	var thickness := height * .13
	var centers := [
		Vector2(0, half_height),
		Vector2(half_width, half_height * .5),
		Vector2(half_width, -half_height * .5),
		Vector2(0, -half_height),
		Vector2(-half_width, -half_height * .5),
		Vector2(-half_width, half_height * .5),
		Vector2(0, 0)
	]
	for segment in 7:
		if (mask & (1 << segment)) == 0:
			continue
		var horizontal := segment in [0, 3, 6]
		var center: Vector2 = centers[segment]
		_side_rect(
			st,
			x,
			side,
			z - side * center.x,
			y + center.y,
			half_width * 1.76 if horizontal else thickness,
			thickness if horizontal else half_height * .77,
			color,
			layer
		)


static func _top_graphics(
	st: SurfaceTool,
	width: float,
	height: float,
	length: float,
	shoulder: float,
	spec: Dictionary,
	style: String,
	accent: Color,
	secondary: Color
) -> void:
	var body := str(spec.body)
	var hood_back := -length * .17
	var roof_front := -length * .065
	var roof_back := length * .14
	if body == "hatch":
		roof_back = length * .30
	elif body == "pickup":
		hood_back = -length * .24
		roof_front = -length * .12
		roof_back = length * .02
	elif body == "muscle":
		hood_back = -length * .12
	elif body == "coupe":
		hood_back = -length * .24
		roof_back = length * .09
	roof_front = float(spec.get("roof_front", roof_front / length)) * length
	roof_back = float(spec.get("roof_back", roof_back / length)) * length
	hood_back = float(spec.get("cabin_front", (hood_back + .05) / length)) * length - .05
	var hood_front := float(spec.get("hood_flat_front", -.445)) * length + .025
	var hood_y := shoulder + OFFSET
	var roof_y := height - .0075 + OFFSET
	var charcoal := Color("131e27")
	if style == "drag":
		# Two longitudinal stripes continue over the roof; leave the central
		# bonnet scoop visible and separate from the vinyl.
		for sign_x: float in [-1.0, 1.0]:
			var x: float = sign_x * width * .205
			_top_rect(st, x, hood_y, hood_front, hood_back, width * .13, charcoal)
			_top_rect(st, x, roof_y, roof_front + .025, roof_back - .025, width * .13, charcoal)
			_top_rect(
				st,
				x + sign_x * width * .09,
				hood_y + LAYER_GAP,
				hood_front,
				hood_back,
				width * .024,
				accent
			)
			_top_rect(
				st,
				x + sign_x * width * .09,
				roof_y + LAYER_GAP,
				roof_front + .025,
				roof_back - .025,
				width * .024,
				accent
			)
	elif style == "rally":
		_top_rect(st, -width * .15, hood_y, hood_front, hood_back, width * .22, charcoal)
		_top_rect(
			st, -width * .15, roof_y, roof_front + .025, roof_back - .025, width * .22, charcoal
		)
		_top_rect(st, width * .027, hood_y, hood_front, hood_back, width * .075, accent)
		_top_rect(
			st, width * .027, roof_y, roof_front + .025, roof_back - .025, width * .075, accent
		)
		_top_rect(st, width * .095, hood_y, hood_front, hood_back, width * .025, secondary)
	elif style == "gt":
		_top_polygon(
			st,
			hood_y,
			[
				Vector2(-width * .30, hood_front),
				Vector2(-width * .06, hood_front),
				Vector2(width * .25, hood_back),
				Vector2(width * .04, hood_back)
			],
			accent
		)
		_top_polygon(
			st,
			hood_y + LAYER_GAP,
			[
				Vector2(-width * .35, hood_front),
				Vector2(-width * .32, hood_front),
				Vector2(width * .02, hood_back),
				Vector2(-width * .012, hood_back)
			],
			secondary
		)
		_top_rect(st, width * .23, roof_y, roof_front + .025, roof_back - .025, width * .07, accent)


static func _side_poly(
	st: SurfaceTool,
	x: float,
	side: float,
	length: float,
	low: float,
	span: float,
	points: Array,
	color: Color,
	layer: int
) -> void:
	var polygon := PackedVector2Array()
	for point: Vector2 in points:
		polygon.append(Vector2(point.x * length, low + point.y * span))
	_side_polygon(st, x + side * float(layer) * LAYER_GAP, side, polygon, color)


static func _side_rect(
	st: SurfaceTool,
	x: float,
	side: float,
	z: float,
	y: float,
	width: float,
	height: float,
	color: Color,
	layer: int
) -> void:
	_side_polygon(
		st,
		x + side * float(layer) * LAYER_GAP,
		side,
		PackedVector2Array(
			[
				Vector2(z - width * .5, y - height * .5),
				Vector2(z + width * .5, y - height * .5),
				Vector2(z + width * .5, y + height * .5),
				Vector2(z - width * .5, y + height * .5)
			]
		),
		color
	)


static func _side_polygon(
	st: SurfaceTool, x: float, side: float, polygon: PackedVector2Array, color: Color
) -> void:
	var triangles := Geometry2D.triangulate_polygon(polygon)
	for triangle in range(0, triangles.size(), 3):
		var order := [0, 2, 1] if side > 0.0 else [0, 1, 2]
		for corner: int in order:
			var point: Vector2 = polygon[triangles[triangle + corner]]
			st.set_normal(Vector3(side, 0, 0))
			st.set_color(color)
			st.add_vertex(Vector3(x, point.y, point.x))


static func _top_rect(
	st: SurfaceTool, x: float, y: float, z_front: float, z_rear: float, width: float, color: Color
) -> void:
	_top_polygon(
		st,
		y,
		[
			Vector2(x - width * .5, z_front),
			Vector2(x + width * .5, z_front),
			Vector2(x + width * .5, z_rear),
			Vector2(x - width * .5, z_rear)
		],
		color
	)


static func _top_polygon(st: SurfaceTool, y: float, points: Array, color: Color) -> void:
	var polygon := PackedVector2Array(points)
	var triangles := Geometry2D.triangulate_polygon(polygon)
	for triangle in range(0, triangles.size(), 3):
		for corner: int in [0, 2, 1]:
			var point: Vector2 = polygon[triangles[triangle + corner]]
			st.set_normal(Vector3.UP)
			st.set_color(color)
			st.add_vertex(Vector3(point.x, y, point.y))


## Curved coupe panels share the exact sampling functions used by the body.
## Tessellation happens once per catalog mesh; no projection runs per frame.
static func _curved_mesh(
	source: ArrayMesh, spec: Dictionary, shape: Script, roof_only := false
) -> ArrayMesh:
	var out := SurfaceTool.new()
	out.begin(Mesh.PRIMITIVE_TRIANGLES)
	var arrays := MESH_ARRAYS.arrays_of(source, 0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var length: float = float(spec["size"][2])
	var shoulder: float = float(spec.get("shoulder", .78))
	for triangle in range(0, vertices.size(), 3):
		var a: Vector3 = vertices[triangle]
		var b: Vector3 = vertices[triangle + 1]
		var c: Vector3 = vertices[triangle + 2]
		var normal: Vector3 = normals[triangle]
		var color: Color = colors[triangle]
		if roof_only and (normal.y < .5 or a.y <= shoulder + .12):
			for point: Vector3 in [a, b, c]:
				out.set_normal(normal)
				out.set_color(color)
				out.add_vertex(point)
			continue
		var flat_door: bool = (
			absf(normal.x) > .5 and maxf(absf(a.z), maxf(absf(b.z), absf(c.z))) <= length * .20
		)
		_curve_triangle(out, spec, shape, a, b, c, normal, color, 9 if flat_door else 0)
	return out.commit()


static func _curve_triangle(
	st: SurfaceTool,
	spec: Dictionary,
	shape: Script,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	normal: Vector3,
	color: Color,
	depth: int
) -> void:
	var ab := a.distance_squared_to(b)
	var bc := b.distance_squared_to(c)
	var ca := c.distance_squared_to(a)
	if depth < 9 and maxf(ab, maxf(bc, ca)) > .15 * .15:
		if ab >= bc and ab >= ca:
			var mid := (a + b) * .5
			_curve_triangle(st, spec, shape, a, mid, c, normal, color, depth + 1)
			_curve_triangle(st, spec, shape, mid, b, c, normal, color, depth + 1)
		elif bc >= ca:
			var mid := (b + c) * .5
			_curve_triangle(st, spec, shape, a, b, mid, normal, color, depth + 1)
			_curve_triangle(st, spec, shape, a, mid, c, normal, color, depth + 1)
		else:
			var mid := (c + a) * .5
			_curve_triangle(st, spec, shape, a, b, mid, normal, color, depth + 1)
			_curve_triangle(st, spec, shape, mid, b, c, normal, color, depth + 1)
		return
	var pa := _curve_point(spec, shape, a, normal)
	var pb := _curve_point(spec, shape, b, normal)
	var pc := _curve_point(spec, shape, c, normal)
	var curved_normal := (pb - pa).cross(pc - pa).normalized()
	if curved_normal.dot(normal) < 0.0:
		curved_normal = -curved_normal
	for point: Vector3 in [pa, pb, pc]:
		st.set_color(color)
		st.set_normal(curved_normal)
		st.add_vertex(point)


static func _curve_point(
	spec: Dictionary, shape: Script, point: Vector3, normal: Vector3
) -> Vector3:
	var shoulder: float = float(spec.get("shoulder", .76))
	if absf(normal.x) > .5:
		var side := signf(normal.x)
		var side_gap := absf(point.x) - float(spec["size"][0]) * .48 + .002
		var side_y := point.y
		# The upper fender stripe follows the descending haunch, keeping its
		# thickness instead of hovering above the rounded nose and rear deck.
		if point.y > shoulder - .055 and absf(point.z) > float(spec["size"][2]) * .22:
			var top: Vector3 = shape.call(
				"deck_point", spec, side * float(spec["size"][0]) * .48, point.z
			)
			var anchor := maxf(shoulder - .035, float(spec.wheel_radius) * 2.0 + .014)
			side_y = minf(anchor, top.y - .013) + (point.y - anchor)
		var side_surface: Vector3 = shape.call("side_point", spec, side, point.z, side_y)
		return side_surface + Vector3(side * side_gap, 0, 0)
	if point.y > shoulder + .12:
		var roof_gap := point.y - (float(spec["size"][1]) - .0075) + .002
		var roof_surface: Vector3 = shape.call("roof_point", spec, point.x, point.z)
		return roof_surface + Vector3(0, roof_gap, 0)
	var gap := point.y - shoulder + .002
	var surface: Vector3 = shape.call("deck_point", spec, point.x, point.z)
	return surface + Vector3(0, gap, 0)
