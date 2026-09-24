extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"

## Medic Box: Ambulância de suporte avançado tipo baú médico (SAMU / Resgate).
## Identidade: Módulo cúbico traseiro alargado, cruzes médicas em relevo, giroflex azul/vermelho e degrau de maca.

const WHEEL_WELL_RESOURCE_PATH := "res://prototypes/living_cast/models/MedicBoxWheelWells.res"
const WHEEL_WELL_CONTRACT_VERSION := 1
const PREPARED_GEOMETRY_PATH := "res://prototypes/living_cast/models/MedicBoxPreparedGeometry.scn"
const PREPARED_GEOMETRY := preload("res://prototypes/living_cast/models/MedicBoxPreparedGeometry.scn")
const PREPARED_CONTRACT_VERSION := 1
const PREPARED_MATERIAL_KEY_META := &"medic_box_material_key"
# Filled from the reproducible generator and deliberately fixed here so a stale
# or partially replaced scene always falls back to the authored source.
const EXPECTED_PREPARED_SIGNATURE := 3101446470
const EXPECTED_PREPARED_MESHES := 43
const EXPECTED_PREPARED_TRIANGLES := 23503
const REAR_DOOR_PATHS: Array[NodePath] = [^"RearDoorLeft", ^"RearDoorRight"]
var rear_door_motion: Tween

func set_rear_doors(open: bool, immediate := false) -> void:
	if rear_door_motion:
		rear_door_motion.kill()
	rear_door_motion = null
	var doors := _rear_door_nodes()
	if not immediate and not doors.is_empty():
		rear_door_motion = create_tween().set_parallel(true)
	for i in doors.size():
		var angle := (1.0 if i == 0 else -1.0) * deg_to_rad(110) if open else 0.0
		if immediate:
			doors[i].rotation.y = angle
		else:
			rear_door_motion.tween_property(doors[i], "rotation:y", angle, 0.65)

func _rear_door_nodes() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for path in REAR_DOOR_PATHS:
		var door := get_node_or_null(path) as Node3D
		if door != null:
			result.append(door)
	return result


func vehicle_prepared_template_resource() -> PackedScene:
	return PREPARED_GEOMETRY


func prepare_vehicle_prewarm_materials() -> void:
	_prepare_runtime_materials()


func validate_vehicle_prepared_template(template: Node3D) -> bool:
	return _prepared_template_is_acceptable(template)


func vehicle_prepared_template_runtime_metadata(template: Node3D) -> Dictionary:
	return {
		&"vehicle_mesh_batched": true,
		&"vehicle_wheel_clearance_signature": int(template.get_meta("vehicle_wheel_clearance_signature", 0)),
		&"vehicle_prepared_wheel_wells": true,
		&"medic_box_geometry_source": &"prepared",
		&"medic_box_prepared_geometry_signature": int(template.get_meta("medic_box_prepared_geometry_signature", 0)),
	}


func bind_vehicle_prepared_template_materials(template: Node) -> void:
	_bind_prepared_materials(template)


func _ready() -> void:
	if get_meta("medic_box_geometry_source", &"") == &"prepared":
		_bind_prepared_materials(self)
	super._ready()


func build() -> void:
	if get_child_count() != 0:
		push_error("MedicBoxModel.build refused duplicate geometry")
		return
	_prepare_runtime_materials()
	var prepared := vehicle_prepared_template_resource()
	var template := prepared.instantiate() as Node3D if prepared != null else null
	if template == null or not _prepared_template_is_acceptable(template):
		if template != null:
			template.free()
		set_meta("medic_box_geometry_source", &"procedural_fallback")
		build_procedural_source()
		return
	for metadata in template.get_meta_list():
		set_meta(metadata, template.get_meta(metadata))
	set_meta("vehicle_mesh_batched", true)
	set_meta("vehicle_prepared_wheel_wells", true)
	set_meta("medic_box_geometry_source", &"prepared")
	for child in template.get_children():
		_clear_owner(child)
		template.remove_child(child)
		add_child(child)
		_bind_prepared_materials(child)
	template.free()


func _prepare_runtime_materials() -> void:
	paint = mat("paint", "f5f6fa", 0.20, 0.35)
	mat("medic_orange", "e67e22", 0.1, 0.4)
	mat("medic_red", "d63031", 0.1, 0.4)
	mat("medic_blue", "0984e3", 0.1, 0.4)
	mat("chrome", "ecf0f1", 0.85, 0.20)
	mat("black_trim", "1e272e", 0.1, 0.7)
	mat("rubber", "15191d", 0.0, 0.95)
	var glass := mat("glass", "2c3e50", 0.35, 0.15)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat("headlight", "f5f6fa", 0.1, 0.1, 0.7)
	mat("taillight", "c0392b", 0.1, 0.2, 0.6)
	mat("amber_turn", "f39c12", 0.1, 0.2, 0.5)
	mat("lightbar_mount", "1a1d20", 0.5, 0.4)
	mat("bar_left", "e74c3c", 0.1, 0.1, 0.95)
	mat("bar_right", "0984e3", 0.1, 0.1, 0.95)
	mat("siren_speaker", "2f3640", 0.6, 0.3)
	mat("trim", "282f36", 0.2, 0.45)
	mat("rim_dcdde1", "dcdde1", 0.75, 0.25)
	mat("caliper", "cd382b", 0.3, 0.4)
	mat("rotor", "555d64", 0.6, 0.5)


func _prepared_template_is_acceptable(template: Node3D) -> bool:
	if int(template.get_meta("medic_box_prepared_contract_version", 0)) != PREPARED_CONTRACT_VERSION:
		return false
	if int(template.get_meta("medic_box_prepared_geometry_signature", 0)) != EXPECTED_PREPARED_SIGNATURE:
		return false
	if int(template.get_meta("medic_box_prepared_meshes", 0)) != EXPECTED_PREPARED_MESHES:
		return false
	if int(template.get_meta("medic_box_prepared_triangles", 0)) != EXPECTED_PREPARED_TRIANGLES:
		return false
	if int(template.get_meta("vehicle_wheel_clearance_signature", 0)) == 0:
		return false
	var wheel_centres: Array[Vector3] = []
	var valid := _validate_prepared_branch(template, wheel_centres)
	var meshes := _mesh_count(template)
	var triangles := _triangle_count(template)
	var left := template.get_node_or_null("RearDoorLeft") as Node3D
	var right := template.get_node_or_null("RearDoorRight") as Node3D
	return valid \
			and meshes == EXPECTED_PREPARED_MESHES \
			and triangles == EXPECTED_PREPARED_TRIANGLES \
			and wheel_centres.size() == 4 \
			and left != null and right != null \
			and left.find_children("*", "MeshInstance3D", true, false).size() >= 3 \
			and right.find_children("*", "MeshInstance3D", true, false).size() >= 3


func _validate_prepared_branch(node: Node, wheel_centres: Array[Vector3]) -> bool:
	for child in node.get_children():
		if child.get_script() != null:
			return false
		if child is MeshInstance3D:
			var part := child as MeshInstance3D
			if part.mesh == null:
				return false
			var material_key := StringName(part.get_meta(PREPARED_MATERIAL_KEY_META, &""))
			if material_key.is_empty() or not materials.has(material_key):
				return false
			if part.has_meta("wheel_center"):
				var centre: Vector3 = part.get_meta("wheel_center")
				if not wheel_centres.has(centre):
					wheel_centres.append(centre)
		if not _validate_prepared_branch(child, wheel_centres):
			return false
	return true


func _mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else 0
	for child in node.get_children():
		count += _mesh_count(child)
	return count


func _triangle_count(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface_index in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface_index)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
				count += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
	for child in node.get_children():
		count += _triangle_count(child)
	return count


func _bind_prepared_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var material_key := StringName(part.get_meta(PREPARED_MATERIAL_KEY_META, &""))
		if materials.has(material_key):
			part.material_override = materials[material_key]
	for child in node.get_children():
		_bind_prepared_materials(child)


func _clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner(child)


func build_procedural_source(install_prepared_wheel_wells: bool = true) -> void:
	paint = mat("paint", "f5f6fa", 0.20, 0.35)
	var orange_stripe := mat("medic_orange", "e67e22", 0.1, 0.4)
	var red_cross := mat("medic_red", "d63031", 0.1, 0.4)
	var blue_cross := mat("medic_blue", "0984e3", 0.1, 0.4)
	var chrome := mat("chrome", "ecf0f1", 0.85, 0.20)
	var black := mat("black_trim", "1e272e", 0.1, 0.7)
	var rubber := mat("rubber", "15191d", 0.0, 0.95)
	var glass := mat("glass", "2c3e50", 0.35, 0.15)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lens_head := mat("headlight", "f5f6fa", 0.1, 0.1, 0.7)
	var lens_tail := mat("taillight", "c0392b", 0.1, 0.2, 0.6)
	var lens_amber := mat("amber_turn", "f39c12", 0.1, 0.2, 0.5)

	# 1. Assoalho e Chassi da Ambulância
	box(Vector3(0.0, 0.30, 0.0), Vector3(2.00, 0.12, 5.30), rubber)

	# 2. Cabine Dianteira
	# Capô frontal
	box(Vector3(0.0, 0.78, -1.95), Vector3(1.92, 0.46, 1.40), paint)
	# Cabine do motorista/paramédico
	box(Vector3(0.0, 1.45, -1.05), Vector3(1.86, 0.90, 1.25), paint)
	# Para-brisa frontal inclinado
	var w_front := box(Vector3(0.0, 1.35, -1.48), Vector3(1.72, 0.72, 0.04), glass)
	w_front.rotation.x = deg_to_rad(24.0)
	# Vidros laterais da cabine
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.935, 1.38, -0.98), Vector3(0.02, 0.52, 0.92), glass)
		# Retrovisores com espelho de ponto cego
		box(Vector3(s * 1.08, 1.25, -1.35), Vector3(0.20, 0.34, 0.08), black)
		tube([Vector3(s * 0.95, 1.32, -1.35), Vector3(s * 1.06, 1.32, -1.35)], 0.018, black)
		tube([Vector3(s * 0.95, 1.18, -1.35), Vector3(s * 1.06, 1.18, -1.35)], 0.018, black)

	# 3. Módulo Traseiro Cúbico de Resgate (Box Module - mais largo e mais alto)
	# Hollow bay: the stretcher passes through the rear doorway.
	for side in [-1.0, 1.0]:
		box(Vector3(side*1.02,1.45,0.95),Vector3(.10,1.55,3.25),paint)
	box(Vector3(0,1.45,-.63),Vector3(1.96,1.55,.10),paint)
	box(Vector3(0,.72,.95),Vector3(1.96,.09,3.20),black)
	# Teto do módulo médico
	box(Vector3(0.0, 2.25, 0.95), Vector3(2.12, 0.08, 3.20), paint)

	# 4. Identidade Visual 1: Faixa Laranja / Vermelha Reflexiva de Resgate
	for s in [-1.0, 1.0]:
		# Faixa horizontal contínua
		box(Vector3(s * 1.075, 0.92, 0.95), Vector3(0.02, 0.22, 3.24), orange_stripe)
		# Faixa na cabine
		box(Vector3(s * 0.965, 0.92, -1.45), Vector3(0.02, 0.22, 2.10), orange_stripe)

	# 5. Identidade Visual 2: Cruzes Médicas / Estrela da Vida em Relevo nas Laterais e Teto
	for s in [-1.0, 1.0]:
		# Cruz Médica Lateral (haste vertical + horizontal)
		box(Vector3(s * 1.076, 1.52, 0.95), Vector3(0.025, 0.52, 0.16), red_cross)
		box(Vector3(s * 1.076, 1.52, 0.95), Vector3(0.025, 0.16, 0.52), red_cross)

	# Cruz Médica no Teto (visível por helicópteros e câmera top-down)
	box(Vector3(0.0, 2.30, 0.95), Vector3(0.65, 0.025, 0.20), red_cross)
	box(Vector3(0.0, 2.30, 0.95), Vector3(0.20, 0.025, 0.65), red_cross)

	# 6. Identidade Visual 3: Portas Traseiras de Maca com Janelas Quadradas Fumê e Degrau
	for side in [-1.0,1.0]:
		var hinge := Node3D.new()
		hinge.name = "RearDoorLeft" if side < 0 else "RearDoorRight"
		hinge.position = Vector3(side*1.02,.70,2.58)
		add_child(hinge)
		var panel := box(Vector3(side*.51,1.45,2.58),Vector3(1.0,1.5,.06),paint)
		var window := box(Vector3(side*.48,1.65,2.62),Vector3(.38,.42,.02),glass)
		var handle := box(Vector3(side*.10,1.14,2.64),Vector3(.04,.16,.03),black)
		for part in [panel,window,handle]:
			var at: Vector3 = part.position
			remove_child(part)
			hinge.add_child(part)
			part.position = at-hinge.position

	# Degrau traseiro antiderrapante de acesso à maca
	box(Vector3(0.0, 0.38, 2.65), Vector3(1.65, 0.08, 0.24), chrome)

	# 7. Identidade Visual 4: Barra de Giroflex Estroboscópico Azul/Vermelho e Estrobos de Quina
	add_lightbar(2.05, -1.25, Color("#e74c3c"), Color("#0984e3"), 1.65)
	# Estrobos de quina superiores do módulo traseiro
	for s in [-1.0, 1.0]:
		box(Vector3(s * 1.04, 2.22, -0.62), Vector3(0.08, 0.08, 0.08), red_cross if s < 0 else blue_cross)
		box(Vector3(s * 1.04, 2.22, 2.52), Vector3(0.08, 0.08, 0.08), red_cross if s < 0 else blue_cross)

	# 8. Frente, Faróis, Grade e Lanternas
	box(Vector3(0.0, 0.72, -2.66), Vector3(1.15, 0.28, 0.04), chrome)
	for s in [-1.0, 1.0]:
		# Faróis dianteiros duplos
		box(Vector3(s * 0.76, 0.76, -2.66), Vector3(0.28, 0.22, 0.04), lens_head)
		box(Vector3(s * 0.90, 0.76, -2.65), Vector3(0.06, 0.22, 0.04), lens_amber)
		# Lanternas traseiras verticais
		box(Vector3(s * 1.02, 1.05, 2.58), Vector3(0.08, 0.55, 0.03), lens_tail)

	# Para-choque dianteiro
	box(Vector3(0.0, 0.42, -2.68), Vector3(1.96, 0.16, 0.12), chrome)

	# 9. Quatro Rodas Reforçadas
	for s in [-0.94, 0.94]:
		add_wheel(s, 0.40, -1.65, 0.38, 0.24, 0.22, 5, "dcdde1")
		add_wheel(s, 0.40, 1.55, 0.38, 0.30, 0.22, 5, "dcdde1") # Rodagem traseira mais larga

	if install_prepared_wheel_wells:
		_install_prepared_wheel_wells()


## Instala apenas as superfícies alteradas pelo recorte das caixas de roda.
## Portas, materiais, rodas e referências de dano continuam sendo construídos
## pelo modelo autoral. Um recurso incompleto ou obsoleto nunca é aplicado.
func _install_prepared_wheel_wells() -> void:
	if not ResourceLoader.exists(WHEEL_WELL_RESOURCE_PATH, "Resource"):
		return
	var prepared := load(WHEEL_WELL_RESOURCE_PATH) as Resource
	if prepared == null:
		return
	if int(prepared.get_meta("format_version", 0)) != WHEEL_WELL_CONTRACT_VERSION:
		return
	if String(prepared.get_meta("model_id", "")) != "medic_box":
		return
	if int(prepared.get_meta("source_structure_signature", 0)) != wheel_well_source_structure_signature():
		push_warning("MedicBox wheel-well resource is stale; using safe runtime carving")
		return
	var baked: Dictionary = prepared.get_meta("meshes", {})
	var clearance_signature := int(prepared.get_meta("wheel_clearance_signature", 0))
	if baked.is_empty() \
			or int(prepared.get_meta("mesh_count", 0)) != baked.size() \
			or int(prepared.get_meta("wheel_centres", 0)) != 4 \
			or clearance_signature == 0:
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
		part.set_meta("medic_box_precarved_mesh", true)
		if part.mesh.get_surface_count() == 0:
			part.hide()
	set_meta("vehicle_wheel_clearance_signature", clearance_signature)
	set_meta("vehicle_prepared_wheel_wells", true)


## Assinatura barata da estrutura usada pelo gerador. Alterações na ordem,
## transformação, bounds ou metadados das rodas invalidam o recurso preparado.
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
