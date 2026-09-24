extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"

## Courier Van Express: Furgão de entrega urbana de carga e logística.
## Identidade: Carroceria de teto alto, baú traseiro fechado, rack de teto com travas de escada e portas traseiras 50/50.

const WHEEL_WELL_RESOURCE_PATH := "res://prototypes/living_cast/models/CourierVanWheelWells.res"
const WHEEL_WELL_CONTRACT_VERSION := 1
const PREPARED_GEOMETRY: PackedScene = preload("res://prototypes/living_cast/models/CourierVanPreparedGeometry.scn")
const MATERIAL_KEY_META := &"courier_van_material_key"
const SURFACE_KEYS_META := &"courier_van_surface_material_keys"
const EXPECTED_PREPARED_CONTRACT_VERSION := 1
const EXPECTED_PREPARED_SIGNATURE := 4069370056
const EXPECTED_PREPARED_MESHES := 19
const EXPECTED_PREPARED_SURFACES := 31
const EXPECTED_PREPARED_TRIANGLES := 24488


## Direct regional-prewarm contract. The threaded Script load brings the packed
## scene dependency in before scheduler-owned work starts, so runtime stages only
## prepare materials, validate, instantiate and atomically publish 19 meshes.
func vehicle_prepared_template_resource() -> PackedScene:
	return PREPARED_GEOMETRY


func prepare_vehicle_prewarm_materials() -> void:
	_prepare_runtime_materials()


func validate_vehicle_prepared_template(template: Node3D) -> bool:
	return _prepared_template_is_acceptable(template)


func vehicle_prepared_template_runtime_metadata(_template: Node3D) -> Dictionary:
	return {
		&"vehicle_mesh_batched": true,
		&"courier_van_geometry_source": &"prepared",
		&"vehicle_prepared_wheel_wells": true,
	}


func bind_vehicle_prepared_template_materials(template: Node) -> void:
	_bind_prepared_materials(template)


func _ready() -> void:
	# Direct cache restore reconstructs independent materials before _ready. Bind
	# every compact surface to this instance before damage/lamp capture runs.
	if get_meta("courier_van_geometry_source", &"") == &"prepared":
		_bind_prepared_materials(self)
	super._ready()


func build(use_prepared_geometry: bool = true) -> void:
	if get_child_count() != 0:
		push_error("CourierVanModel.build refused duplicate geometry")
		return
	_prepare_runtime_materials()
	if use_prepared_geometry:
		var template := PREPARED_GEOMETRY.instantiate() as Node3D
		if template != null and _prepared_template_is_acceptable(template):
			for metadata in template.get_meta_list():
				set_meta(metadata, template.get_meta(metadata))
			set_meta("courier_van_geometry_source", &"prepared")
			set_meta("vehicle_mesh_batched", true)
			set_meta("vehicle_prepared_wheel_wells", true)
			for child in template.get_children():
				_clear_owner(child)
				template.remove_child(child)
				add_child(child)
				_bind_prepared_materials(child)
			template.free()
			return
		if template != null:
			template.free()
		set_meta("courier_van_geometry_source", &"procedural_fallback")
	_build_procedural_geometry(use_prepared_geometry)


## Reproducible authored source used only by the resource builder and fallback
## diagnostics. false in build(false) deliberately bypasses every prepared form.
func build_procedural_source() -> void:
	if get_child_count() != 0:
		push_error("CourierVanModel.build_procedural_source refused duplicate geometry")
		return
	_prepare_runtime_materials()
	_build_procedural_geometry(false)


func _prepare_runtime_materials() -> void:
	paint = mat("paint", "ffffff", 0.25, 0.30)
	mat("industrial_black", "1e272e", 0.1, 0.7)
	mat("van_stripe", "0984e3", 0.2, 0.4)
	mat("galvanized_steel", "b2bec3", 0.75, 0.35)
	mat("rubber", "15191d", 0.0, 0.92)
	var glass := mat("glass", "222f3e", 0.35, 0.15)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat("headlight", "f5f6fa", 0.1, 0.1, 0.65)
	mat("taillight", "c0392b", 0.1, 0.2, 0.6)
	mat("amber_turn", "f39c12", 0.1, 0.2, 0.5)
	# add_wheel uses these stable roles; preparing them up front makes direct
	# regional publication and procedural fallback material-equivalent.
	mat("trim", "282f36", 0.2, 0.45)
	mat("rim_7f8c8d", "7f8c8d", 0.75, 0.25)
	mat("caliper", "cd382b", 0.3, 0.4)
	mat("rotor", "555d64", 0.6, 0.5)


func _build_procedural_geometry(install_prepared_wheel_wells: bool) -> void:
	var black := materials["industrial_black"] as Material
	var stripe_blue := materials["van_stripe"] as Material
	var chrome_rack := materials["galvanized_steel"] as Material
	var rubber := materials["rubber"] as Material
	var glass := materials["glass"] as Material
	var lens_head := materials["headlight"] as Material
	var lens_tail := materials["taillight"] as Material
	var lens_amber := materials["amber_turn"] as Material

	# 1. Assoalho e Chassi Reforçado
	box(Vector3(0.0, 0.26, 0.0), Vector3(1.82, 0.10, 4.60), rubber)

	# 2. Carroceria Inferior
	# Capô inclinado curto frontal
	box(Vector3(0.0, 0.72, -1.75), Vector3(1.86, 0.44, 1.25), paint)
	# Área de carga inferior
	# Mantém a frente do compartimento e fecha a carroceria no plano das portas.
	box(Vector3(0.0, 0.72, 0.625), Vector3(1.92, 0.44, 3.50), paint)

	# 3. Baú Traseiro Alto Fechado (Sem janelas traseiras)
	box(Vector3(0.0, 1.5325, 0.70), Vector3(1.90, 1.185, 3.35), paint)

	# 4. Cabine Superior (Envidraçada apenas para motorista/passageiro)
	box(Vector3(0.0, 1.62, -1.05), Vector3(1.80, 0.95, 1.15), paint)
	# Para-brisa dianteiro amplo quase plano
	var w_front := box(Vector3(0.0, 1.25, -1.35), Vector3(1.68, 0.78, 0.04), glass)
	w_front.rotation.x = deg_to_rad(26.0)
	# Vidros das portas dianteiras
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.905, 1.30, -0.95), Vector3(0.02, 0.52, 0.95), glass)
		# Retrovisores grandes de haste dupla
		box(Vector3(s * 1.05, 1.20, -1.25), Vector3(0.22, 0.32, 0.10), black)
		tube([Vector3(s * 0.92, 1.28, -1.25), Vector3(s * 1.02, 1.28, -1.25)], 0.015, black)
		tube([Vector3(s * 0.92, 1.12, -1.25), Vector3(s * 1.02, 1.12, -1.25)], 0.015, black)

	# 5. Identidade Visual 1: Faixa Decorativa Lateral de Entrega Expressa
	for s in [-1.0, 1.0]:
		box(Vector3(s * 0.965, 0.92, 0.35), Vector3(0.015, 0.18, 3.10), stripe_blue)
		# Painéis de porta corrediça lateral marcada
		box(Vector3(s * 0.962, 1.05, 0.15), Vector3(0.01, 1.25, 0.02), black)
		box(Vector3(s * 0.962, 1.05, 1.35), Vector3(0.01, 1.25, 0.02), black)

	# 6. Identidade Visual 2: Rack de Teto Tubular com Travas
	for s in [-0.75, 0.75]:
		tube([Vector3(s, 2.18, -0.80), Vector3(s, 2.18, 1.85)], 0.022, chrome_rack)
		# Suportes verticais de teto
		for z_sup in [-0.60, 0.30, 1.20, 1.80]:
			tube([Vector3(s, 2.12, z_sup), Vector3(s, 2.18, z_sup)], 0.020, black)
	# Travessas transversais
	for z_bar in [-0.40, 0.50, 1.40]:
		tube([Vector3(-0.75, 2.20, z_bar), Vector3(0.75, 2.20, z_bar)], 0.020, chrome_rack)

	# 7. Identidade Visual 3: Portas Traseiras 50/50 com Trincos e Degrau Traseiro
	# Fresta central da divisão das portas
	box(Vector3(0.0, 1.25, 2.38), Vector3(0.02, 1.70, 0.02), black)
	# Maçanetas das portas traseiras
	box(Vector3(-0.06, 1.10, 2.39), Vector3(0.04, 0.14, 0.03), black)
	box(Vector3(0.06, 1.10, 2.39), Vector3(0.04, 0.14, 0.03), black)
	# Degrau traseiro antiderrapante de carga
	box(Vector3(0.0, 0.32, 2.45), Vector3(1.70, 0.08, 0.22), black)

	# 8. Lanternas Traseiras Verticais e Frente
	for s in [-1.0, 1.0]:
		# Lanternas traseiras altas
		box(Vector3(s * 0.88, 1.25, 2.38), Vector3(0.08, 0.65, 0.03), lens_tail)
		# Faróis dianteiros verticais utilitários
		box(Vector3(s * 0.75, 0.72, -2.38), Vector3(0.26, 0.22, 0.04), lens_head)
		box(Vector3(s * 0.89, 0.72, -2.37), Vector3(0.06, 0.22, 0.04), lens_amber)

	# Grade dianteira utilitária preta
	box(Vector3(0.0, 0.65, -2.38), Vector3(1.10, 0.24, 0.03), black)
	# Para-choque robusto
	box(Vector3(0.0, 0.38, -2.40), Vector3(1.88, 0.18, 0.12), black)

	# 9. Quatro Rodas Reforçadas de Carga
	for s in [-0.88, 0.88]:
		add_wheel(s, 0.38, -1.45, 0.37, 0.24, 0.21, 5, "7f8c8d")
		add_wheel(s, 0.38, 1.45, 0.37, 0.24, 0.21, 5, "7f8c8d")

	if install_prepared_wheel_wells:
		_install_prepared_wheel_wells()


func _prepared_template_is_acceptable(template: Node3D) -> bool:
	if int(template.get_meta("courier_van_prepared_contract_version", 0)) != EXPECTED_PREPARED_CONTRACT_VERSION:
		return false
	if int(template.get_meta("courier_van_prepared_geometry_signature", 0)) != EXPECTED_PREPARED_SIGNATURE:
		return false
	if int(template.get_meta("courier_van_prepared_meshes", 0)) != EXPECTED_PREPARED_MESHES:
		return false
	if int(template.get_meta("courier_van_prepared_surfaces", 0)) != EXPECTED_PREPARED_SURFACES:
		return false
	if int(template.get_meta("courier_van_prepared_triangles", 0)) != EXPECTED_PREPARED_TRIANGLES:
		return false
	if int(template.get_meta("vehicle_wheel_clearance_signature", 0)) == 0:
		return false
	var meshes := 0
	var surfaces := 0
	var wheel_centres: Array[Vector3] = []
	var spinning_wheels := 0
	var fixed_wheels := 0
	var headlamps := 0
	var taillamps := 0
	var damage_bodies := 0
	var static_groups := 0
	for child in template.get_children():
		var part := child as MeshInstance3D
		if part == null or part.mesh == null:
			return false
		meshes += 1
		surfaces += part.mesh.get_surface_count()
		var surface_keys: PackedStringArray = part.get_meta(SURFACE_KEYS_META, PackedStringArray())
		if surface_keys.is_empty() or surface_keys.size() != part.mesh.get_surface_count():
			return false
		for key in surface_keys:
			if not materials.has(StringName(key)):
				return false
		var material_key := StringName(surface_keys[0]) if _all_same_surface_key(surface_keys) else &""
		var child_name := String(part.name)
		if child_name.begins_with("CourierVan_lamp_"):
			if material_key == &"headlight":
				headlamps += 1
			elif material_key == &"taillight":
				taillamps += 1
			else:
				return false
		elif bool(part.get_meta("courier_van_damage_body", false)):
			if material_key != &"paint" or part.mesh.get_surface_count() != 1:
				return false
			damage_bodies += 1
		elif child_name.begins_with("CourierVan_static_"):
			static_groups += 1
		if part.has_meta("wheel_center"):
			var centre: Vector3 = part.get_meta("wheel_center")
			if not wheel_centres.has(centre):
				wheel_centres.append(centre)
			if bool(part.get_meta("wheel_spins", false)):
				spinning_wheels += 1
			else:
				fixed_wheels += 1
	return (
		meshes == EXPECTED_PREPARED_MESHES
		and surfaces == EXPECTED_PREPARED_SURFACES
		and wheel_centres.size() == 4
		and spinning_wheels == 4
		and fixed_wheels == 4
		and headlamps == 2
		and taillamps == 2
		and damage_bodies == 1
		and static_groups == 6
	)


func _bind_prepared_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var surface_keys: PackedStringArray = part.get_meta(SURFACE_KEYS_META, PackedStringArray())
		if _all_same_surface_key(surface_keys):
			part.material_override = materials[StringName(surface_keys[0])]
		else:
			part.material_override = null
			for surface_index in surface_keys.size():
				part.set_surface_override_material(surface_index, materials[StringName(surface_keys[surface_index])])
	for child in node.get_children():
		_bind_prepared_materials(child)


func _all_same_surface_key(surface_keys: PackedStringArray) -> bool:
	if surface_keys.is_empty():
		return false
	for key in surface_keys:
		if key != surface_keys[0]:
			return false
	return true


func _clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner(child)


## Instala somente as superfícies da lataria que mudaram no recorte das caixas
## de roda. Rodas, materiais e nós de dano continuam sendo criados pelo build
## autoral acima e seguem o mesmo caminho do restante da frota.
func _install_prepared_wheel_wells() -> void:
	if not ResourceLoader.exists(WHEEL_WELL_RESOURCE_PATH, "Resource"):
		return
	var prepared := load(WHEEL_WELL_RESOURCE_PATH) as Resource
	if prepared == null:
		return
	if int(prepared.get_meta("format_version", 0)) != WHEEL_WELL_CONTRACT_VERSION:
		return
	if String(prepared.get_meta("model_id", "")) != "courier_van":
		return
	if int(prepared.get_meta("source_structure_signature", 0)) != wheel_well_source_structure_signature():
		push_warning("CourierVan wheel-well resource is stale; using safe runtime carving")
		return
	var baked: Dictionary = prepared.get_meta("meshes", {})
	if baked.is_empty():
		return
	# Validate the complete map before changing the first child. A stale or
	# partial resource must fall back atomically to normal runtime carving.
	for child_index_value in baked:
		var child_index := int(child_index_value)
		if child_index < 0 or child_index >= get_child_count():
			return
		if not get_child(child_index) is MeshInstance3D or not baked[child_index_value] is ArrayMesh:
			return
	for child_index_value in baked:
		var part := get_child(int(child_index_value)) as MeshInstance3D
		part.mesh = baked[child_index_value] as ArrayMesh
		part.set_meta("courier_van_precarved_mesh", true)
		if part.mesh.get_surface_count() == 0:
			part.hide()
	set_meta("vehicle_wheel_clearance_signature", int(prepared.get_meta("wheel_clearance_signature", 0)))
	set_meta("vehicle_prepared_wheel_wells", true)


## Assinatura barata do layout-fonte. Ela inclui ordem, transformação, limites
## de cada malha e metadados das rodas, evitando aplicar recortes antigos se o
## modelo autoral mudar sem que o recurso seja refeito.
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
