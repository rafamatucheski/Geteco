extends Node3D
## Small repeated details share immutable meshes/materials and MultiMesh draws.
const SURFACES := preload("res://world/places/ShopInteriorMaterials.gd")
var batches: Dictionary = {}
var materials: Dictionary = {}
var bottle_count := 0
var detail_count := 0

func surface(color: String, kind := "wood") -> StandardMaterial3D:
	var key := color + kind
	if materials.has(key): return materials[key]
	var material: StandardMaterial3D
	if kind in ["wood", "stone", "cloth"]:
		material = SURFACES.material(kind, Color(color))
	else:
		material = StandardMaterial3D.new()
		material.albedo_color = Color(color)
		material.roughness = .32 if kind in ["metal", "bottle"] else .7
		material.metallic = .62 if kind == "metal" else 0.0
		if kind == "glow":
			material.emission_enabled = true
			material.emission = Color(color)
			material.emission_energy_multiplier = .42
	materials[key] = material
	return material

func box(label: String, at: Vector3, size: Vector3, color: String, solid := "", kind := "wood") -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = at
	instance.material_override = surface(color, kind)
	if not solid.is_empty(): instance.set_meta("interior_solid_id", solid)
	add_child(instance)
	return instance

func piece(shape: String, at: Vector3, size: Vector3, color: String, kind := "wood", piece_rotation := Vector3.ZERO) -> void:
	var key := shape + color + kind
	if not batches.has(key): batches[key] = {"shape":shape,"color":color,"kind":kind,"transforms":[]}
	batches[key].transforms.append(Transform3D(Basis.from_euler(piece_rotation).scaled(size), at))
	detail_count += 1

func bottle(at: Vector3, label_color := "eee4c8", glass_color := "253d27", foil_color := "702b3d", bottle_rotation := Vector3.ZERO) -> void:
	bottle_count += 1
	var bottle_basis := Basis.from_euler(bottle_rotation)
	# Uma garrafa de 750 ml tem ~31 cm de altura, com ombro, gargalo e cápsula separados.
	piece("round",at+bottle_basis*Vector3(0,.106,0),Vector3(.078,.212,.078),glass_color,"bottle",bottle_rotation)
	piece("shoulder",at+bottle_basis*Vector3(0,.228,0),Vector3(.078,.043,.078),glass_color,"bottle",bottle_rotation)
	piece("round",at+bottle_basis*Vector3(0,.278,0),Vector3(.030,.072,.030),glass_color,"bottle",bottle_rotation)
	piece("round",at+bottle_basis*Vector3(0,.309,0),Vector3(.033,.031,.033),foil_color,"metal",bottle_rotation)
	piece("round",at+bottle_basis*Vector3(0,.112,0),Vector3(.079,.092,.079),label_color,"paper",bottle_rotation)
	piece("box",at+bottle_basis*Vector3(0,.119,.0405),Vector3(.042,.018,.0025),foil_color,"paper",bottle_rotation)
	piece("box",at+bottle_basis*Vector3(0,.092,.0405),Vector3(.045,.006,.0025),"a19780","paper",bottle_rotation)

func glass(at: Vector3, filled := false) -> void:
	# Taças finas claras e opacas ficam estáveis no renderer de compatibilidade.
	piece("round",at+Vector3(0,.008,0),Vector3(.09,.016,.09),"c2c7bd","metal")
	piece("round",at+Vector3(0,.08,0),Vector3(.014,.145,.014),"cbd2c7","metal")
	piece("cup",at+Vector3(0,.181,0),Vector3(.09,.10,.09),"b9c9bd","bottle")
	if filled: piece("round",at+Vector3(0,.196,0),Vector3(.073,.032,.073),"722d45","bottle")

func flush_batches() -> void:
	for key in batches:
		var row: Dictionary = batches[key]
		var primitive: PrimitiveMesh
		if row.shape in ["round", "shoulder", "cup"]:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = .2 if row.shape == "shoulder" else .5
			cylinder.bottom_radius = .22 if row.shape == "cup" else .5
			cylinder.height = 1.0
			cylinder.radial_segments = 10
			cylinder.rings = 1
			primitive = cylinder
		elif row.shape == "leaf":
			var sphere := SphereMesh.new()
			sphere.radius = .5
			sphere.height = 1
			sphere.radial_segments = 8
			sphere.rings = 4
			primitive = sphere
		else:
			var cube := BoxMesh.new()
			cube.size = Vector3.ONE
			primitive = cube
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = primitive
		multi.instance_count = row.transforms.size()
		for index in row.transforms.size(): multi.set_instance_transform(index, row.transforms[index])
		var node := MultiMeshInstance3D.new()
		node.name = "CellarDetail_" + key
		node.multimesh = multi
		node.material_override = surface(row.color, row.kind)
		add_child(node)
	batches.clear()

func anchor(label: String, at: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = label
	marker.position = at
	add_child(marker)
	return marker
