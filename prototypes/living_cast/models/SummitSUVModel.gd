extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"

## Summit SUV 4x4 Heavy (Veículo Assinatura dos Lobos de Gelo - Viktor Frost):
## SUV pesado blindado de tração integral permanente, suspensão elevada,
## quebra-mato frontal com guincho, bagageiro de teto com estepe e barra de LED auxiliar.

const WHEEL_WELL_RESOURCE_PATH := "res://prototypes/living_cast/models/SummitSUVWheelWells.res"
const WHEEL_WELL_CONTRACT_VERSION := 1
const PREPARED_GEOMETRY := preload("res://prototypes/living_cast/models/SummitSUVPreparedGeometry.scn")
const MATERIAL_ROLE_META := &"summit_suv_material_role"
const SURFACE_ROLES_META := &"summit_suv_surface_material_roles"
const EXPECTED_CONTRACT_VERSION := 1
const EXPECTED_SIGNATURE := 1011982617
const EXPECTED_MESHES := 14
const EXPECTED_TRIANGLES := 12388
const EXPECTED_CLEARANCE_SIGNATURE := 2025983418
const EXPECTED_MATERIAL_ROLE_COUNTS := {
	&"black_trim": 1,
	&"caliper": 4,
	&"chrome": 1,
	&"headlight": 2,
	&"heavy_steel": 1,
	&"led_white": 1,
	&"paint": 1,
	&"rim_b5bdc3": 4,
	&"rotor": 4,
	&"rubber": 5,
	&"taillight": 2,
	&"tinted_glass": 1,
	&"trim": 4,
}


## Direct prepared-resource contract used by resumable regional prewarm.
func vehicle_prepared_template_resource() -> PackedScene:
	return PREPARED_GEOMETRY


func prepare_vehicle_prewarm_materials() -> void:
	_prepare_runtime_materials()


func validate_vehicle_prepared_template(template: Node3D) -> bool:
	return _prepared_template_is_acceptable(template)


func vehicle_prepared_template_runtime_metadata(_template: Node3D) -> Dictionary:
	return {
		&"vehicle_mesh_batched": true,
		&"vehicle_prepared_wheel_wells": true,
		&"summit_suv_geometry_source": &"prepared",
	}


func bind_vehicle_prepared_template_materials(template: Node) -> void:
	_bind_prepared_materials(template)


func build(install_prepared_wheel_wells: bool = true) -> void:
	if get_child_count() != 0:
		push_error("SummitSUVModel.build refused duplicate geometry")
		return
	# The wheel-well baker deliberately asks for the untouched procedural source.
	if not install_prepared_wheel_wells:
		build_procedural_source(false)
		return
	_prepare_runtime_materials()
	var template := PREPARED_GEOMETRY.instantiate() as Node3D
	if template == null or not _prepared_template_is_acceptable(template):
		if template != null:
			template.free()
		set_meta("summit_suv_geometry_source", &"procedural_fallback")
		build_procedural_source(true)
		return
	for metadata in template.get_meta_list():
		set_meta(metadata, template.get_meta(metadata))
	set_meta("summit_suv_geometry_source", &"prepared")
	for child in template.get_children():
		_clear_owner(child)
		template.remove_child(child)
		add_child(child)
		_bind_prepared_materials(child)
	template.free()


func _prepare_runtime_materials() -> void:
	materials.clear()
	paint = null
	paint = mat("paint", "2980b9", 0.35, 0.30)
	mat("heavy_steel", "2c3e50", 0.75, 0.35)
	mat("black_trim", "1e272e", 0.1, 0.75)
	mat("rubber", "15191d", 0.0, 0.95)
	var glass := mat("tinted_glass", "1c2833", 0.35, 0.10)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat("headlight", "f5f6fa", 0.1, 0.1, 0.8)
	mat("taillight", "c0392b", 0.1, 0.2, 0.6)
	mat("led_white", "ffffff", 0.1, 0.1, 1.0)
	mat("chrome", "bdc3c7", 0.9, 0.15)
	mat("trim", "282f36", 0.2, 0.45)
	mat("rim_b5bdc3", "b5bdc3", 0.75, 0.25)
	mat("caliper", "cd382b", 0.3, 0.4)
	mat("rotor", "555d64", 0.6, 0.5)


func _prepared_template_is_acceptable(template: Node3D) -> bool:
	if int(template.get_meta("summit_suv_prepared_contract_version", 0)) != EXPECTED_CONTRACT_VERSION:
		return false
	if int(template.get_meta("summit_suv_prepared_geometry_signature", 0)) != EXPECTED_SIGNATURE:
		return false
	if int(template.get_meta("summit_suv_prepared_meshes", 0)) != EXPECTED_MESHES:
		return false
	if int(template.get_meta("summit_suv_prepared_triangles", 0)) != EXPECTED_TRIANGLES:
		return false
	if int(template.get_meta("vehicle_wheel_clearance_signature", 0)) != EXPECTED_CLEARANCE_SIGNATURE:
		return false
	if not bool(template.get_meta("vehicle_mesh_batched", false)):
		return false
	if not bool(template.get_meta("summit_suv_authored_roof_rack", false)) or not bool(template.get_meta("summit_suv_authored_roof_spare", false)):
		return false
	var recorded_counts_value = template.get_meta("summit_suv_material_role_counts", {})
	if not recorded_counts_value is Dictionary:
		return false
	var recorded_counts := recorded_counts_value as Dictionary
	var actual_counts: Dictionary = {}
	var wheel_flags: Dictionary = {}
	var headlamps := 0
	var tail_lamps := 0
	var meshes := 0
	for child in template.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null:
			return false
		meshes += 1
		var surface_roles: PackedStringArray = part.get_meta(SURFACE_ROLES_META, PackedStringArray())
		if surface_roles.size() != part.mesh.get_surface_count():
			return false
		for role_value in surface_roles:
			var role := StringName(role_value)
			if role == &"" or not materials.has(role):
				return false
			actual_counts[role] = int(actual_counts.get(role, 0)) + 1
			if role == &"headlight":
				headlamps += 1
			elif role == &"taillight":
				tail_lamps += 1
		if part.has_meta("wheel_center"):
			var centre: Vector3 = part.get_meta("wheel_center")
			var flags := int(wheel_flags.get(centre, 0))
			if bool(part.get_meta("wheel_spins", false)):
				flags |= 1
			else:
				flags |= 2
			wheel_flags[centre] = flags
	if meshes != EXPECTED_MESHES or actual_counts.size() != EXPECTED_MATERIAL_ROLE_COUNTS.size():
		return false
	for role_value in EXPECTED_MATERIAL_ROLE_COUNTS:
		var role := StringName(role_value)
		var expected := int(EXPECTED_MATERIAL_ROLE_COUNTS[role_value])
		if int(actual_counts.get(role, 0)) != expected or _recorded_role_count(recorded_counts, role) != expected:
			return false
	if headlamps != 2 or tail_lamps != 2 or wheel_flags.size() != 4:
		return false
	for centre in wheel_flags:
		if int(wheel_flags[centre]) != 3:
			return false
	return true


func _recorded_role_count(recorded_counts: Dictionary, role: StringName) -> int:
	if recorded_counts.has(role):
		return int(recorded_counts[role])
	return int(recorded_counts.get(String(role), 0))


func _bind_prepared_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var surface_roles: PackedStringArray = part.get_meta(SURFACE_ROLES_META, PackedStringArray())
		if _all_same_surface_role(surface_roles):
			part.material_override = materials[StringName(surface_roles[0])]
		else:
			part.material_override = null
			for surface_index in surface_roles.size():
				part.set_surface_override_material(surface_index, materials[StringName(surface_roles[surface_index])])
	for child in node.get_children():
		_bind_prepared_materials(child)


func _all_same_surface_role(surface_roles: PackedStringArray) -> bool:
	if surface_roles.is_empty():
		return false
	for role in surface_roles:
		if role != surface_roles[0]:
			return false
	return true


func _clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner(child)


## Retained exact authoring source used by the wheel-well/prepared-resource
## builders and as a defensive fallback when the full scene fails validation.
func build_procedural_source(install_prepared_wheel_wells: bool = true) -> void:
	if get_child_count() != 0:
		push_error("SummitSUVModel procedural build refused duplicate geometry")
		return
	_prepare_runtime_materials()
	var steel_bumper := materials["heavy_steel"] as StandardMaterial3D
	var black := materials["black_trim"] as StandardMaterial3D
	var rubber := materials["rubber"] as StandardMaterial3D
	var glass := materials["tinted_glass"] as StandardMaterial3D
	var lens_head := materials["headlight"] as StandardMaterial3D
	var lens_tail := materials["taillight"] as StandardMaterial3D
	var led_bar := materials["led_white"] as StandardMaterial3D
	var chrome := materials["chrome"] as StandardMaterial3D

	# 1. Chassi 4x4 Elevado & Skidplates (Proteção Inferior)
	box(Vector3(0.0, 0.38, 0.0), Vector3(1.95, 0.16, 4.90), black)
	# Protetor de cárter de aço na frente
	box(Vector3(0.0, 0.32, -2.25), Vector3(1.30, 0.12, 0.50), steel_bumper)

	# 2. Carroceria Inferior / Linha de Cintura Muscular
	box(Vector3(0.0, 0.82, 0.0), Vector3(2.05, 0.55, 4.80), paint)
	# Para-lamas alargados (Fender Flares de plástico preto fosco)
	for s in [-1.0, 1.0]:
		box(Vector3(s * 1.04, 0.78, -1.45), Vector3(0.12, 0.42, 1.10), black)
		box(Vector3(s * 1.04, 0.78, 1.45), Vector3(0.12, 0.42, 1.10), black)
		# Estribos laterais tubulares (Rock Sliders)
		box(Vector3(s * 1.02, 0.42, 0.0), Vector3(0.14, 0.08, 2.20), steel_bumper)

	# 3. Capô Elevado com Entrada de Ar e Snorkel Lateral
	box(Vector3(0.0, 1.14, -1.55), Vector3(1.75, 0.16, 1.65), paint)
	box(Vector3(0.0, 1.23, -1.40), Vector3(0.70, 0.06, 0.90), black) # Scoop
	# Snorkel de ar na coluna A direita para travessia de rio
	tube([Vector3(0.96, 0.90, -1.80), Vector3(0.96, 1.70, -0.90)], 0.045, black)
	box(Vector3(0.96, 1.74, -0.85), Vector3(0.12, 0.10, 0.16), black)

	# 4. Cabine Fechada de 3 Fileiras (Estilo SUV Expedição)
	box(Vector3(0.0, 1.62, 0.6125), Vector3(1.72, 0.08, 3.575), paint) # Teto até o vidro traseiro
	# Para-brisa dianteiro inclinado
	var w_front := box(Vector3(0.0, 1.36, -0.75), Vector3(1.68, 0.58, 0.04), glass)
	w_front.rotation.x = deg_to_rad(26.0)
	# Vidro traseiro vertical do porta-malas
	box(Vector3(0.0, 1.38, 2.38), Vector3(1.62, 0.54, 0.04), glass)
	# Vidros laterais (três janelas de cada lado)
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.855, 1.38, 0.6375), Vector3(0.03, 0.52, 3.525), glass)
		# Retrovisores grandes de reboque
		box(Vector3(s * 1.12, 1.25, -0.70), Vector3(0.22, 0.26, 0.09), black)

	# 5. Bagageiro de Teto Tubular (Roof Rack) com Expedição & Barra de LED
	# Longarinas e travessas do bagageiro
	for s in [-0.78, 0.78]:
		tube([Vector3(s, 1.72, -0.90), Vector3(s, 1.72, 1.60)], 0.030, steel_bumper)
	for z_pos in [-0.80, -0.20, 0.40, 1.00, 1.55]:
		tube([Vector3(-0.76, 1.72, z_pos), Vector3(0.76, 1.72, z_pos)], 0.025, steel_bumper)
	# Estepe off-road amarrado no bagageiro de teto
	var roof_spare := cylinder(Vector3(0.0, 1.82, 0.35), 0.38, 0.22, rubber)
	roof_spare.rotation.x = PI / 2.0
	box(Vector3(0.0, 1.86, 0.35), Vector3(0.40, 0.04, 0.40), steel_bumper) # Cinta de fixação
	# Barra de LED auxiliar de alta potência no teto
	box(Vector3(0.0, 1.75, -0.92), Vector3(1.20, 0.07, 0.08), black)
	box(Vector3(0.0, 1.75, -0.96), Vector3(1.14, 0.05, 0.02), led_bar)

	# 6. Para-choque Dianteiro Tático de Aço com Quebra-Mato (Bullbar) e Guincho
	box(Vector3(0.0, 0.68, -2.48), Vector3(1.98, 0.32, 0.20), steel_bumper)
	# Quebra-mato tubular envolvente
	tube([Vector3(-0.55, 0.72, -2.52), Vector3(-0.55, 1.22, -2.50)], 0.035, steel_bumper)
	tube([Vector3(0.55, 0.72, -2.52), Vector3(0.55, 1.22, -2.50)], 0.035, steel_bumper)
	tube([Vector3(-0.55, 1.20, -2.50), Vector3(0.55, 1.20, -2.50)], 0.035, steel_bumper)
	# Guincho elétrico central com carretel de cabo de aço
	box(Vector3(0.0, 0.70, -2.58), Vector3(0.42, 0.18, 0.16), black)
	box(Vector3(0.0, 0.70, -2.66), Vector3(0.20, 0.08, 0.04), chrome)

	# 7. Faróis e Lanternas
	for s in [-1.0, 1.0]:
		# Faróis duplos de LED
		box(Vector3(s * 0.74, 0.88, -2.42), Vector3(0.38, 0.18, 0.04), lens_head)
		# Lanternas traseiras verticais
		box(Vector3(s * 0.92, 1.10, 2.41), Vector3(0.14, 0.44, 0.04), lens_tail)

	for side in [-1.0,1.0]:
		for axle in [-1.45,1.45]:
			add_wheel(side*0.98,0.36,axle,0.38,0.27,0.22,6)

	if install_prepared_wheel_wells:
		_install_prepared_wheel_wells()


func _install_prepared_wheel_wells() -> void:
	if not ResourceLoader.exists(WHEEL_WELL_RESOURCE_PATH, "Resource"):
		return
	var prepared := load(WHEEL_WELL_RESOURCE_PATH) as Resource
	if prepared == null:
		return
	if int(prepared.get_meta("format_version", 0)) != WHEEL_WELL_CONTRACT_VERSION:
		return
	if String(prepared.get_meta("model_id", "")) != "summit_suv":
		return
	if int(prepared.get_meta("source_structure_signature", 0)) != wheel_well_source_structure_signature():
		push_warning("SummitSUV wheel-well resource is stale; using safe runtime carving")
		return
	var baked: Dictionary = prepared.get_meta("meshes", {})
	if baked.is_empty():
		return
	for child_index_value in baked:
		var child_index := int(child_index_value)
		if child_index < 0 or child_index >= get_child_count():
			return
		if not get_child(child_index) is MeshInstance3D or not baked[child_index_value] is ArrayMesh:
			return
	for child_index_value in baked:
		var part := get_child(int(child_index_value)) as MeshInstance3D
		part.mesh = baked[child_index_value] as ArrayMesh
		part.set_meta("summit_suv_precarved_mesh", true)
		if part.mesh.get_surface_count() == 0:
			part.hide()
	set_meta("vehicle_wheel_clearance_signature", int(prepared.get_meta("wheel_clearance_signature", 0)))
	set_meta("vehicle_prepared_wheel_wells", true)


func wheel_well_source_structure_signature() -> int:
	var structure: Array = []
	for child_index in get_child_count():
		var child := get_child(child_index)
		if not child is MeshInstance3D:
			continue
		var part := child as MeshInstance3D
		var mesh := part.mesh
		structure.append([
			child_index,
			part.transform,
			mesh.get_class() if mesh != null else "",
			mesh.get_aabb() if mesh != null else AABB(),
			part.get_meta("wheel_center", Vector3.INF),
			float(part.get_meta("wheel_radius", -1.0)),
		])
	return hash(structure)
