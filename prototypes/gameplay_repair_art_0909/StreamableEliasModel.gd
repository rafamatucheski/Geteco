class_name StreamableEliasModel
extends StreamableActorPresentation

## Modelo 3D de Elias com suporte nativo a Streaming e Compartilhamento de Recursos.
##
## Preserva 100% da silhueta marcante: sobretudo de tweed, cachecol ocre longo,
## boina de marinheiro, barba grisalha e oculos dourados.
##
## Performance sob demanda:
## - defer_presentation = true exibe silhueta com as cores de sobretudo/cachecol.
## - Constroi rig 3D detalhado somente sob demanda via ensure_presentation().
## - Compartilha geometrias unitarias e materiais exclusivos com zero vazamento.

enum Pose {
	WAIT,
	TALK,
	WALK,
	INSPECT
}

var current_pose: Pose = Pose.WAIT
var walking: bool = false
var clock: float = 0.0
var talk_gesture_clock: float = 0.0

var torso_node: Node3D
var head_node: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_forearm: Node3D
var right_forearm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var satchel_node: Node3D
var spectacles_node: Node3D

# Referencias para malhas que suportam dano / isolamento
var overcoat_mesh: MeshInstance3D
var scarf_mesh: MeshInstance3D
var head_mesh: MeshInstance3D

func _init(p_defer: bool = false) -> void:
	defer_presentation = p_defer

func _setup_fallback_silhouette() -> void:
	if _presentation_fallback != null or is_presentation_ready:
		return
	_presentation_fallback = Node3D.new()
	_presentation_fallback.name = "EliasSilhouette"
	add_child(_presentation_fallback)

	# Sobretudo tweed proxy
	var coat_proxy := MeshInstance3D.new()
	coat_proxy.mesh = ArtPresentationCache.get_unit_box()
	coat_proxy.scale = Vector3(0.42, 1.35, 0.28)
	coat_proxy.position = Vector3(0.0, 0.72, 0.0)
	var mat_coat := StandardMaterial3D.new()
	mat_coat.albedo_color = Color("#4b4034")
	coat_proxy.material_override = mat_coat
	_presentation_fallback.add_child(coat_proxy)

	# Cachecol ocre proxy
	var scarf_proxy := MeshInstance3D.new()
	scarf_proxy.mesh = ArtPresentationCache.get_unit_box()
	scarf_proxy.scale = Vector3(0.18, 0.38, 0.12)
	scarf_proxy.position = Vector3(0.06, 1.08, -0.15)
	var mat_scarf := StandardMaterial3D.new()
	mat_scarf.albedo_color = Color("#ad6834")
	scarf_proxy.material_override = mat_scarf
	_presentation_fallback.add_child(scarf_proxy)

	# Cabeca + boina proxy
	var head_proxy := MeshInstance3D.new()
	head_proxy.mesh = ArtPresentationCache.get_unit_sphere()
	head_proxy.scale = Vector3(0.30, 0.32, 0.30)
	head_proxy.position = Vector3(0.0, 1.42, 0.0)
	var mat_cap := StandardMaterial3D.new()
	mat_cap.albedo_color = Color("#292624")
	head_proxy.material_override = mat_cap
	_presentation_fallback.add_child(head_proxy)

func _build_presentation_rig() -> void:
	var mat_overcoat := ArtPresentationCache.get_elias_overcoat_material()
	var mat_scarf := ArtPresentationCache.get_elias_scarf_material()
	var mat_cap := ArtPresentationCache.get_elias_cap_material()
	var mat_skin := ArtPresentationCache.get_elias_skin_material()
	var mat_beard := ArtPresentationCache.get_elias_beard_material()
	var mat_satchel := ArtPresentationCache.get_elias_satchel_material()
	var mat_specs := ArtPresentationCache.get_elias_spectacles_material()
	var mat_boots := ArtPresentationCache.get_worker_boots_material()
	var mat_trousers := ArtPresentationCache.get_worker_trousers_material()

	# 1. Torso
	torso_node = Node3D.new()
	torso_node.name = "Torso"
	torso_node.position = Vector3(0.0, 0.86, 0.0)
	add_child(torso_node)

	overcoat_mesh = _create_box_part(Vector3(0.42, 0.62, 0.28), mat_overcoat)
	torso_node.add_child(overcoat_mesh)

	var coat_flare := _create_box_part(Vector3(0.44, 0.40, 0.30), mat_overcoat)
	coat_flare.position = Vector3(0.0, -0.32, 0.0)
	torso_node.add_child(coat_flare)

	# Cachecol de la enrolado no pescoco
	scarf_mesh = _create_box_part(Vector3(0.38, 0.16, 0.32), mat_scarf)
	scarf_mesh.position = Vector3(0.0, 0.32, 0.0)
	torso_node.add_child(scarf_mesh)

	var scarf_tail := _create_box_part(Vector3(0.12, 0.44, 0.06), mat_scarf)
	scarf_tail.position = Vector3(0.10, 0.08, -0.16)
	scarf_tail.rotation_degrees = Vector3(6.0, 0.0, -8.0)
	torso_node.add_child(scarf_tail)

	# 2. Cabeca
	head_node = Node3D.new()
	head_node.name = "Head"
	head_node.position = Vector3(0.0, 1.32, 0.0)
	add_child(head_node)

	head_mesh = _create_sphere_part(Vector3(0.25, 0.28, 0.25), mat_skin)
	head_node.add_child(head_mesh)

	var beard := _create_sphere_part(Vector3(0.24, 0.30, 0.20), mat_beard)
	beard.position = Vector3(0.0, -0.10, -0.09)
	head_node.add_child(beard)

	var cap := _create_sphere_part(Vector3(0.32, 0.14, 0.32), mat_cap)
	cap.position = Vector3(0.0, 0.12, -0.02)
	head_node.add_child(cap)

	spectacles_node = Node3D.new()
	spectacles_node.name = "Spectacles"
	spectacles_node.position = Vector3(0.0, 0.03, -0.14)
	head_node.add_child(spectacles_node)

	var spec_bridge := _create_box_part(Vector3(0.16, 0.03, 0.015), mat_specs)
	spectacles_node.add_child(spec_bridge)

	# 3. Bolsa tiracolo
	satchel_node = Node3D.new()
	satchel_node.name = "Satchel"
	satchel_node.position = Vector3(-0.25, 0.70, 0.02)
	add_child(satchel_node)

	var satchel_bag := _create_box_part(Vector3(0.12, 0.26, 0.22), mat_satchel)
	satchel_node.add_child(satchel_bag)

	# 4. Bracos
	left_arm = Node3D.new()
	left_arm.name = "LeftArm"
	left_arm.position = Vector3(-0.26, 1.08, 0.0)
	add_child(left_arm)

	var l_uarm := _create_box_part(Vector3(0.11, 0.28, 0.12), mat_overcoat)
	l_uarm.position = Vector3(0.0, -0.14, 0.0)
	left_arm.add_child(l_uarm)

	left_forearm = Node3D.new()
	left_forearm.name = "LeftForearm"
	left_forearm.position = Vector3(0.0, -0.28, 0.0)
	left_arm.add_child(left_forearm)

	var l_farm := _create_box_part(Vector3(0.09, 0.24, 0.10), mat_overcoat)
	l_farm.position = Vector3(0.0, -0.12, 0.0)
	left_forearm.add_child(l_farm)

	var l_hand := _create_box_part(Vector3(0.07, 0.09, 0.07), mat_skin)
	l_hand.position = Vector3(0.0, -0.25, 0.0)
	left_forearm.add_child(l_hand)

	right_arm = Node3D.new()
	right_arm.name = "RightArm"
	right_arm.position = Vector3(0.26, 1.08, 0.0)
	add_child(right_arm)

	var r_uarm := _create_box_part(Vector3(0.11, 0.28, 0.12), mat_overcoat)
	r_uarm.position = Vector3(0.0, -0.14, 0.0)
	right_arm.add_child(r_uarm)

	right_forearm = Node3D.new()
	right_forearm.name = "RightForearm"
	right_forearm.position = Vector3(0.0, -0.28, 0.0)
	right_arm.add_child(right_forearm)

	var r_farm := _create_box_part(Vector3(0.09, 0.24, 0.10), mat_overcoat)
	r_farm.position = Vector3(0.0, -0.12, 0.0)
	right_forearm.add_child(r_farm)

	var r_hand := _create_box_part(Vector3(0.07, 0.09, 0.07), mat_skin)
	r_hand.position = Vector3(0.0, -0.25, 0.0)
	right_forearm.add_child(r_hand)

	# 5. Pernas
	left_leg = Node3D.new()
	left_leg.name = "LeftLeg"
	left_leg.position = Vector3(-0.13, 0.54, 0.0)
	add_child(left_leg)

	var l_leg_mesh := _create_box_part(Vector3(0.13, 0.52, 0.13), mat_trousers)
	l_leg_mesh.position = Vector3(0.0, -0.26, 0.0)
	left_leg.add_child(l_leg_mesh)

	var l_boot := _create_box_part(Vector3(0.14, 0.12, 0.22), mat_boots)
	l_boot.position = Vector3(0.0, -0.52, -0.03)
	left_leg.add_child(l_boot)

	right_leg = Node3D.new()
	right_leg.name = "RightLeg"
	right_leg.position = Vector3(0.13, 0.54, 0.0)
	add_child(right_leg)

	var r_leg_mesh := _create_box_part(Vector3(0.13, 0.52, 0.13), mat_trousers)
	r_leg_mesh.position = Vector3(0.0, -0.26, 0.0)
	right_leg.add_child(r_leg_mesh)

	var r_boot := _create_box_part(Vector3(0.14, 0.12, 0.22), mat_boots)
	r_boot.position = Vector3(0.0, -0.52, -0.03)
	right_leg.add_child(r_boot)

func _create_box_part(box_scale: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ArtPresentationCache.get_unit_box()
	mi.scale = box_scale
	mi.material_override = mat
	return mi

func _create_sphere_part(sphere_scale: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ArtPresentationCache.get_unit_sphere()
	mi.scale = sphere_scale
	mi.material_override = mat
	return mi

func set_pose(pose: Pose) -> void:
	current_pose = pose
	if not is_presentation_ready:
		_buffered_pose = pose as int
		return

	match current_pose:
		Pose.WAIT:
			left_arm.rotation_degrees = Vector3(15.0, -10.0, 15.0)
			left_forearm.rotation_degrees = Vector3(-45.0, 15.0, 0.0)
			right_arm.rotation_degrees = Vector3(12.0, 8.0, -12.0)
			right_forearm.rotation_degrees = Vector3(-40.0, -15.0, 0.0)
			head_node.rotation_degrees = Vector3(4.0, 0.0, 0.0)
		Pose.TALK:
			left_arm.rotation_degrees = Vector3(10.0, 0.0, 12.0)
			left_forearm.rotation_degrees = Vector3(-30.0, 0.0, 0.0)
			right_arm.rotation_degrees = Vector3(-35.0, 20.0, -15.0)
			right_forearm.rotation_degrees = Vector3(-60.0, 30.0, 0.0)
			head_node.rotation_degrees = Vector3(-4.0, 12.0, 0.0)
		Pose.WALK:
			pass
		Pose.INSPECT:
			left_arm.rotation_degrees = Vector3(20.0, -10.0, 12.0)
			left_forearm.rotation_degrees = Vector3(-50.0, 10.0, 0.0)
			right_arm.rotation_degrees = Vector3(20.0, 10.0, -12.0)
			right_forearm.rotation_degrees = Vector3(-50.0, -10.0, 0.0)
			head_node.rotation_degrees = Vector3(25.0, 0.0, 0.0)

func _apply_pose_to_rig(pose_idx: int) -> void:
	set_pose(pose_idx as Pose)

func update_animation(delta: float, moving: bool) -> void:
	walking = moving
	if not is_presentation_ready:
		_buffered_walking = moving
		return

	if walking:
		clock += delta * 3.6
		var swing := sin(clock) * 18.0
		left_leg.rotation_degrees.x = swing
		right_leg.rotation_degrees.x = -swing
		left_arm.rotation_degrees.x = -swing * 0.75
		right_arm.rotation_degrees.x = swing * 0.75
	else:
		left_leg.rotation_degrees.x = lerpf(left_leg.rotation_degrees.x, 0.0, 8.0 * delta)
		right_leg.rotation_degrees.x = lerpf(right_leg.rotation_degrees.x, 0.0, 8.0 * delta)

# --- ISOLAMENTO DE DANO E RESTAURACAO ---

func _apply_damage_to_rig(damage_type: String, intensity: float, _affected_part: String) -> void:
	var base_overcoat := ArtPresentationCache.get_elias_overcoat_material()
	var dmg_mat := ArtPresentationCache.create_damage_material(base_overcoat, damage_type, intensity)
	if overcoat_mesh != null:
		overcoat_mesh.material_override = dmg_mat

func _restore_shared_materials() -> void:
	if overcoat_mesh != null:
		overcoat_mesh.material_override = ArtPresentationCache.get_elias_overcoat_material()
	if scarf_mesh != null:
		scarf_mesh.material_override = ArtPresentationCache.get_elias_scarf_material()
	if head_mesh != null:
		head_mesh.material_override = ArtPresentationCache.get_elias_skin_material()

func _on_recycled_custom() -> void:
	current_pose = Pose.WAIT
	walking = false
	clock = 0.0
	talk_gesture_clock = 0.0