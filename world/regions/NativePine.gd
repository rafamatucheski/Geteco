extends RefCounted
## Original Pine3D geometry, shared native meshes per variant; no atlas or viewport.
static var _mesh_cache := {}
static var _material_cache := {}
static var _models := {}
static func create(variant: int, snowy: bool) -> Node3D:
	var key := str(variant)+str(snowy)
	if not _models.has(key): _models[key] = _build(variant,snowy)
	var root := Node3D.new()
	for entry in _models[key]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = entry.mesh
		mesh.material_override = entry.material
		root.add_child(mesh)
	return root
static func _build(variant: int,snowy: bool) -> Array:
	var build_batches: Dictionary = {}
	var trunk_color := Color("acb5aa") if variant == 3 else Color("554333")
	var trunk := _shared_material(trunk_color)
	var needles := _shared_material([Color("294337"),Color("345140"),Color("3e5544"),Color("2c4a40")][variant%4])
	var snow := _shared_material(Color("dde9ec"))
	var ice := _shared_material(Color("aacdd9"), .22, .10)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3913+variant*89
	_cylinder(build_batches,Vector3(0,1.65,0),.10,.24,3.3,trunk,9)
	for root_side in 5:
		var angle := root_side*TAU/5
		_branch(build_batches,Vector3(0,.22,0),Vector3(cos(angle)*.48,.035,sin(angle)*.48),.06,trunk)
	for mark in 9:
		var scar_basis := Basis.from_euler(Vector3(0, 0, .08*sin(mark*2.1)))
		_cylinder(build_batches,Vector3(.01,.22+mark*.23,.0),.245-mark*.007,.24-mark*.007,.025,trunk if variant!=3 else needles,7,scar_basis)
	if variant in [3,4,5]:
		for limb in 9:
			var angle := limb*2.4
			var start := Vector3(0,1.4+limb*.20,0)
			var end := start+Vector3(cos(angle)*rng.randf_range(.7,1.2),.65,sin(angle)*rng.randf_range(.7,1.2))
			_branch(build_batches,start,end,.07,trunk)
			_branch(build_batches,end,start.lerp(end,1.35)+Vector3(0,.25,0),.035,trunk)
			if variant!=5:
				_crown(build_batches,end+Vector3(0,.18,0),Vector3(.78,.80,.70) if variant==4 else Vector3(.65,1.05,.62),needles)
			if snowy:
				var cap_height := .96 if variant==4 else (1.20 if variant==3 else .10)
				var cap_size := Vector3(.63,.18,.54) if variant!=5 else Vector3(.24,.07,.19)
				_crown(build_batches,end+Vector3(0,cap_height,0),cap_size,snow)
				_icicle(build_batches,end,ice,.20+limb%3*.06)
	else:
		var tall := 1.13 if variant in [1,6,7] else (.77 if variant==2 else 1.0)
		for tier in 5:
			if variant==6 and tier==0: continue
			var radius := (1.25-tier*.22)*(.73 if variant in [1,2,7] else 1.0)
			var center := (1.35+tier*.72)*tall
			var drift := Vector3(.055*tier if variant==7 else 0,0,0)
			_cylinder(build_batches,Vector3(0,center+.20,0)+drift,.015,radius*.75,1.4*tall,needles,9)
			for bough in 5:
				var angle := bough*TAU/5+tier*.61+variant*.4
				var tip := Vector3(cos(angle)*radius,center-.18,sin(angle)*radius)+drift
				_branch(build_batches,Vector3(0,center,0),tip,.035,trunk)
				var tuft_basis := Basis.from_euler(Vector3(sin(angle)*.18, 0, cos(angle)*.18))
				var tuft_position := tip*.72+Vector3(0,center*.28+.15,0)
				_cylinder(build_batches,tuft_position,.02,radius*.53,.70*tall,needles,7,tuft_basis)
				if snowy and (bough+tier)%3!=0:
					_crown(build_batches,tuft_position+Vector3(0,.20,0),Vector3(radius*.52,.20,radius*.45),snow)
					if tier<3: _icicle(build_batches,tip,ice,.18+(bough%3)*.08)
	var surfaces := {}
	for batch in build_batches.values():
		if not surfaces.has(batch.material):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surfaces[batch.material] = surface
		for transform in batch.transforms: surfaces[batch.material].append_from(batch.mesh,0,transform)
	var result: Array = []
	for material in surfaces: result.append({"mesh":surfaces[material].commit(),"material":material})
	return result

static func _branch(build_batches: Dictionary, start: Vector3, end: Vector3, radius: float, mat: Material) -> void:
	var axis := (end-start).normalized()
	var across := axis.cross(Vector3.FORWARD).normalized()
	var orientation := Basis(across,axis,across.cross(axis))
	_cylinder(build_batches,(start+end)*.5,radius*.55,radius,start.distance_to(end),mat,6,orientation)

static func _crown(build_batches: Dictionary, point: Vector3, size: Vector3, mat: Material) -> void:
	var sphere := _shared_sphere_mesh()
	_queue_primitive(build_batches, sphere, mat, Transform3D(Basis.from_scale(size), point))

static func _icicle(build_batches: Dictionary, point: Vector3, mat: Material, length: float) -> void:
	_cylinder(build_batches,point-Vector3(0,length*.5,0),.045,0,length,mat,5)

static func _cylinder(build_batches: Dictionary, point: Vector3, top: float, bottom: float, height: float, material: Material, sides: int, orientation := Basis.IDENTITY) -> void:
	var radius := maxf(top, bottom)
	if radius <= 0.0 or height <= 0.0:
		return
	var cylinder := _shared_cylinder_mesh(top / radius, bottom / radius, sides)
	var scaled_basis: Basis = orientation * Basis.from_scale(Vector3(radius, height, radius))
	_queue_primitive(build_batches, cylinder, material, Transform3D(scaled_basis, point))

static func _queue_primitive(build_batches: Dictionary, mesh: Mesh, material: Material, transform: Transform3D) -> void:
	var key := "%d_%d" % [mesh.get_instance_id(), material.get_instance_id()]
	var batch: Dictionary = build_batches.get(key, {})
	if batch.is_empty():
		batch = {"mesh": mesh, "material": material, "transforms": []}
		build_batches[key] = batch
	var transforms: Array = batch["transforms"]
	transforms.append(transform)

static func _shared_material(color: Color, roughness := 1.0, metallic := 0.0) -> StandardMaterial3D:
	var key := "%s_%.4f_%.4f" % [color.to_html(true), roughness, metallic]
	var cached := _material_cache.get(key) as StandardMaterial3D
	if cached != null:
		return cached
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_material_cache[key] = material
	return material

static func _shared_sphere_mesh() -> SphereMesh:
	var cached := _mesh_cache.get("sphere_7_3") as SphereMesh
	if cached != null:
		return cached
	var sphere := SphereMesh.new()
	sphere.radial_segments = 7
	sphere.rings = 3
	sphere.radius = 1.0
	sphere.height = 2.0
	_mesh_cache["sphere_7_3"] = sphere
	return sphere

static func _shared_cylinder_mesh(top_ratio: float, bottom_ratio: float, sides: int) -> CylinderMesh:
	var key := "cylinder_%d_%.6f_%.6f" % [sides, top_ratio, bottom_ratio]
	var cached := _mesh_cache.get(key) as CylinderMesh
	if cached != null:
		return cached
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top_ratio
	cylinder.bottom_radius = bottom_ratio
	cylinder.height = 1.0
	cylinder.radial_segments = sides
	_mesh_cache[key] = cylinder
	return cylinder
