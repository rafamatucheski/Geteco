extends Node3D
## Street setup: 8.5 x 32 inch popsicle deck, seven plies and 54 mm wheels.
const WIDTH := .2159
const LENGTH := .8128
const DECK_HEIGHT := .10
const WHEEL_RADIUS := .027
const AXLE_Z := .205
var color := Color("d36c3e")
var wheels: Array[Node3D] = []
static var _grip_material: StandardMaterial3D
var _wood: SurfaceTool
var _steel: SurfaceTool
var _grip: SurfaceTool

func _ready() -> void:
	_wood = _surface()
	_steel = _surface()
	_grip = _surface()
	_build_deck()
	for z in [-AXLE_Z, AXLE_Z]: _build_truck(z)
	_commit(_wood, "DeckTrucksAndHubs", false)
	_commit(_steel, "MetalHardware", true)
	_grip.index()
	_grip.generate_normals()
	var tape := MeshInstance3D.new()
	tape.name = "GripTape"
	tape.mesh = _grip.commit()
	tape.material_override = _grip_mat()
	add_child(tape)

static func _surface() -> SurfaceTool:
	var result := SurfaceTool.new()
	result.begin(Mesh.PRIMITIVE_TRIANGLES)
	return result

static func half_width(z: float) -> float:
	# Long parallel rails with round nose/tail, rather than an ellipse.
	var cap := maxf(0, (absf(z) - .275) / (LENGTH * .5 - .275))
	return WIDTH * .5 * sqrt(maxf(.00001, 1 - cap * cap)) * (1 - .025 * (1 - cap))

static func deck_y(x: float, z: float) -> float:
	var kick := smoothstep(.255, LENGTH * .5, absf(z)) * (.041 if z < 0 else .036)
	return DECK_HEIGHT + kick + .0045 * pow(x / (WIDTH * .5), 2)

func _build_deck() -> void:
	const ROWS := 32
	const COLS := 8
	for row in ROWS:
		var za := lerpf(-LENGTH * .5, LENGTH * .5, float(row) / ROWS)
		var zb := lerpf(-LENGTH * .5, LENGTH * .5, float(row + 1) / ROWS)
		for col in COLS:
			var xa := lerpf(-1, 1, float(col) / COLS)
			var xb := lerpf(-1, 1, float(col + 1) / COLS)
			var points: Array[Vector3] = []
			for pair in [Vector2(xa, za), Vector2(xb, za), Vector2(xa, zb), Vector2(xb, zb)]:
				var x: float = pair.x * half_width(pair.y)
				points.append(Vector3(x, deck_y(x, pair.y), pair.y))
			_quad(_grip, points, Color.WHITE)
			var underside: Array[Vector3] = []
			for point in points: underside.append(point - Vector3.UP * .010)
			# Original color-block underside; no copied brand logos.
			var paint := color
			if absf(za + .06) < .065: paint = Color("22354a")
			elif absf(za - .10) < .025: paint = Color("e4c570")
			_quad(_wood, [underside[2], underside[3], underside[0], underside[1]], paint)
		for side in [-1, 1]:
			var x0: float = side * half_width(za)
			var x1: float = side * half_width(zb)
			for ply in 7:
				var upper := ply * .010 / 7
				var lower := (ply + 1) * .010 / 7
				_quad(_wood, [Vector3(x0, deck_y(x0, za) - upper, za), Vector3(x1, deck_y(x1, zb) - upper, zb), Vector3(x0, deck_y(x0, za) - lower, za), Vector3(x1, deck_y(x1, zb) - lower, zb)], Color("bca17d") if ply % 2 == 0 else Color("896447"))
	# Eight flush truck screws visible through the grip tape.
	for z in [-AXLE_Z, AXLE_Z]:
		for dz in [-.021, .021]:
			for x in [-.0205, .0205]:
				_cylinder(_steel, Vector3(x, DECK_HEIGHT + .001, z + dz), .0031, .0015, Color("444a4e"))

func _build_truck(z: float) -> void:
	var silver := Color("a8b1b7")
	_box(_steel, Vector3(0, .086, z), Vector3(.056, .008, .068), silver)
	# Cast tapered hanger, angled kingpin, polyurethane bushings and steel axle.
	var pin_basis := Basis(Vector3.RIGHT, signf(z) * .27)
	_cylinder(_steel, Vector3(0, .057, z + signf(z) * .013), .004, .043, Color("6b7276"), pin_basis)
	_cylinder(_wood, Vector3(0, .060, z + signf(z) * .013), .010, .018, Color("97562b"), pin_basis)
	_cylinder(_steel, Vector3(0, .037, z + signf(z) * .019), .006, .006, silver, pin_basis, 6)
	_build_hanger(z, silver)
	_cylinder(_steel, Vector3(0, WHEEL_RADIUS, z), .0035, .221, Color("79858d"), Basis(Vector3.FORWARD, PI * .5))
	for side in [-1, 1]:
		var wheel := Node3D.new()
		wheel.name = "Wheel%s%s" % [side, z]
		wheel.position = Vector3(side * .099, WHEEL_RADIUS, z)
		add_child(wheel)
		wheels.append(wheel)
		_build_wheel(wheel, side)

func _build_hanger(z: float, silver: Color) -> void:
	var outline := [Vector2(-.076, .025), Vector2(-.074, .037), Vector2(-.025, .044), Vector2(0, .065), Vector2(.025, .044), Vector2(.074, .037), Vector2(.076, .025)]
	for i in outline.size():
		var p: Vector2 = outline[i]
		var q: Vector2 = outline[(i + 1) % outline.size()]
		_quad(_steel, [Vector3(p.x, p.y, z - .008), Vector3(q.x, q.y, z - .008), Vector3(p.x, p.y, z + .008), Vector3(q.x, q.y, z + .008)], silver)
		for side in [-1, 1]:
			for point in [Vector3(0, .038, z + side * .008), Vector3(p.x, p.y, z + side * .008), Vector3(q.x, q.y, z + side * .008)]:
				_steel.set_color(silver)
				_steel.set_uv(Vector2.ZERO)
				_steel.add_vertex(point)

func _build_wheel(owner_wheel: Node3D, side: int) -> void:
	# 31 mm width, rounded shoulders, recessed bearing and visible axle nut.
	var wheel := _surface()
	var profile := [Vector2(-.0155, .018), Vector2(-.012, .024), Vector2(-.00975, WHEEL_RADIUS), Vector2(.00975, WHEEL_RADIUS), Vector2(.012, .024), Vector2(.0155, .018)]
	for ring in profile.size() - 1:
		for sector in 20:
			var a := TAU * sector / 20.0
			var b := TAU * (sector + 1) / 20.0
			var p: Vector2 = profile[ring]
			var q: Vector2 = profile[ring + 1]
			_quad(wheel, [Vector3(p.x, cos(a) * p.y, sin(a) * p.y), Vector3(p.x, cos(b) * p.y, sin(b) * p.y), Vector3(q.x, cos(a) * q.y, sin(a) * q.y), Vector3(q.x, cos(b) * q.y, sin(b) * q.y)], Color("e6dfc9"))
	for end in [-1, 1]:
		for sector in 20:
			var a := TAU * sector / 20.0
			var b := TAU * (sector + 1) / 20.0
			var x: float = end * .0155
			_quad(wheel, [Vector3(x, cos(a) * .007, sin(a) * .007), Vector3(x, cos(b) * .007, sin(b) * .007), Vector3(x, cos(a) * .018, sin(a) * .018), Vector3(x, cos(b) * .018, sin(b) * .018)], Color("d1c8ac"))
	# Colored side mark makes actual wheel rotation readable.
	_box(wheel, Vector3(side * .0158, .012, 0), Vector3(.0008, .004, .010), color)
	_cylinder(wheel, Vector3(side * .013, 0, 0), .005, .004, Color("4d565d"), Basis(Vector3.FORWARD, PI * .5), 6)
	_commit(wheel, "UrethaneAndBearing", false, owner_wheel)

func _box(surface: SurfaceTool, at: Vector3, size: Vector3, tint: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_append_primitive(surface, mesh, at, tint)

func _cylinder(surface: SurfaceTool, at: Vector3, radius: float, height: float, tint: Color, orientation := Basis.IDENTITY, sectors := 8) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sectors
	_append_primitive(surface, mesh, at, tint, orientation)

func _append_primitive(surface: SurfaceTool, mesh: Mesh, at: Vector3, tint: Color, orientation := Basis.IDENTITY) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		surface.set_color(tint)
		surface.set_uv(Vector2.ZERO)
		surface.add_vertex(orientation * vertices[index] + at)

func _quad(surface: SurfaceTool, points: Array[Vector3], tint: Color) -> void:
	for index in [0, 1, 2, 1, 3, 2]:
		var point := points[index]
		surface.set_color(tint)
		surface.set_uv(Vector2(point.x / WIDTH + .5, point.z / LENGTH + .5))
		surface.add_vertex(point)

func _commit(surface: SurfaceTool, title: String, metallic: bool, target_parent: Node = null) -> void:
	surface.index()
	surface.generate_normals()
	var art := MeshInstance3D.new()
	art.name = title
	art.mesh = surface.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.metallic = .75 if metallic else 0
	mat.roughness = .32 if metallic else .85
	art.material_override = mat
	(target_parent if target_parent != null else self).add_child(art)

static func _grip_mat() -> StandardMaterial3D:
	if _grip_material != null: return _grip_material
	var image := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var random := RandomNumberGenerator.new()
	random.seed = 7281
	for y in 128:
		for x in 128:
			var grain := random.randf_range(.07, .14)
			image.set_pixel(x, y, Color(grain, grain * 1.03, grain * 1.06))
	_grip_material = StandardMaterial3D.new()
	_grip_material.albedo_texture = ImageTexture.create_from_image(image)
	_grip_material.roughness = 1
	_grip_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _grip_material
