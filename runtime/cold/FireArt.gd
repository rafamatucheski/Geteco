extends RefCounted
## Shared static fire geometry. Materials/meshes are cached across streamed
## sources; only the existing five flame tongues and seven wisps animate.
const SURFACES := preload("res://world/places/ShopInteriorMaterials.gd")
static var _fuel: ArrayMesh
static var _ring: ArrayMesh
static var _bowl: ArrayMesh
static var _flame: ArrayMesh
static var _flame_material: StandardMaterial3D

static func fuel() -> MeshInstance3D:
	if _fuel == null:
		_fuel = ArrayMesh.new()
		var bark := SurfaceTool.new()
		bark.begin(Mesh.PRIMITIVE_TRIANGLES)
		var ends := SurfaceTool.new()
		ends.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 3:
			var log := CylinderMesh.new()
			log.top_radius = .078
			log.bottom_radius = .105
			log.height = .94
			log.radial_segments = 9
			log.cap_top = false
			log.cap_bottom = false
			var pose := Transform3D(Basis.from_euler(Vector3(PI / 2, i * 1.05 + .2, .08 * (i - 1))), Vector3(0, .105 + i * .045, 0))
			bark.append_from(log, 0, pose)
			for side in [-1.0, 1.0]:
				var cap := CylinderMesh.new()
				cap.top_radius = .078 if side > 0 else .105
				cap.bottom_radius = cap.top_radius
				cap.height = .008
				cap.radial_segments = 9
				ends.append_from(cap, 0, pose * Transform3D(Basis.IDENTITY, Vector3(0, side * .471, 0)))
		bark.set_material(SURFACES.material("wood", Color("34251e")))
		bark.commit(_fuel)
		ends.set_material(SURFACES.material("wood", Color("967557")))
		ends.commit(_fuel)
		var coal := SurfaceTool.new()
		coal.begin(Mesh.PRIMITIVE_TRIANGLES)
		var ember := StandardMaterial3D.new()
		ember.albedo_color = Color("763522")
		ember.roughness = 1.0
		ember.emission_enabled = true
		ember.emission = Color("c84c16")
		ember.emission_energy_multiplier = .5
		var nugget := SphereMesh.new()
		nugget.radius = 1
		nugget.height = 2
		nugget.radial_segments = 7
		nugget.rings = 3
		for i in 15:
			var angle := float(i) * 2.4
			var radius := .12 + .22 * float(i % 4) / 3.0
			var size := Vector3(.07 + (i % 3) * .017, .035, .07)
			coal.append_from(nugget, 0, Transform3D(Basis.from_euler(Vector3(.15, angle, .1)).scaled(size), Vector3(cos(angle) * radius, .035, sin(angle) * radius)))
		coal.set_material(ember)
		coal.commit(_fuel)
	return _instance("CharredFirewoodAndCoals", _fuel)

static func stone_ring() -> MeshInstance3D:
	if _ring == null:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var stone := SphereMesh.new()
		stone.radius = 1
		stone.height = 2
		stone.radial_segments = 7
		stone.rings = 3
		for i in 11:
			var angle := TAU * i / 11.0
			var size := Vector3(.105, .09 + (i % 3) * .012, .14)
			surface.append_from(stone, 0, Transform3D(Basis.from_euler(Vector3(.12, -angle, .08)).scaled(size), Vector3(cos(angle) * .53, .09, sin(angle) * .53)))
		surface.set_material(SURFACES.material("stone", Color("676961")))
		_ring = surface.commit()
	return _instance("FirepitStoneRing", _ring)

static func bowl() -> MeshInstance3D:
	if _bowl == null:
		var profile := [Vector2(.29, 0), Vector2(.61, .38), Vector2(.61, .43), Vector2(.54, .43), Vector2(.25, .09)]
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for row in range(profile.size() - 1):
			for i in 24:
				var a: Vector3 = _revolve(profile[row], TAU * i / 24.0)
				var b: Vector3 = _revolve(profile[row], TAU * (i + 1) / 24.0)
				var c: Vector3 = _revolve(profile[row + 1], TAU * i / 24.0)
				var d: Vector3 = _revolve(profile[row + 1], TAU * (i + 1) / 24.0)
				for vertex in [a, b, c, b, d, c]: surface.add_vertex(vertex)
		surface.generate_normals()
		var iron := StandardMaterial3D.new()
		iron.albedo_color = Color("343638")
		iron.metallic = .65
		iron.roughness = .78
		iron.cull_mode = BaseMaterial3D.CULL_DISABLED
		surface.set_material(iron)
		_bowl = surface.commit()
	return _instance("OpenIronFireBowl", _bowl)

static func flame_mesh() -> ArrayMesh:
	if _flame != null: return _flame
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var widths := [.025, .071, .059, .035, .012, .001]
	for row in 5:
		for side in 8:
			for corner in [Vector2i(row, side), Vector2i(row, side + 1), Vector2i(row + 1, side), Vector2i(row, side + 1), Vector2i(row + 1, side + 1), Vector2i(row + 1, side)]:
				var t := float(corner.x) / 5.0
				var angle: float = TAU * corner.y / 8.0
				var radius: float = widths[corner.x]
				surface.set_color(Color(1.0, lerpf(.86, .24, t), lerpf(.34, .025, t), lerpf(.94, .35, t)))
				surface.add_vertex(Vector3(cos(angle) * radius + .065 * t * t, -.16 + .35 * t, sin(angle) * radius * .72))
	surface.generate_normals()
	_flame = surface.commit()
	return _flame

static func flame_material() -> StandardMaterial3D:
	if _flame_material != null: return _flame_material
	_flame_material = StandardMaterial3D.new()
	_flame_material.vertex_color_use_as_albedo = true
	_flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flame_material.emission_enabled = true
	_flame_material.emission = Color(1, .38, .06)
	_flame_material.emission_energy_multiplier = .7
	return _flame_material

static func _revolve(point: Vector2, angle: float) -> Vector3:
	return Vector3(cos(angle) * point.x, point.y, sin(angle) * point.x)

static func _instance(label: String, mesh: ArrayMesh) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = label
	result.mesh = mesh
	return result
