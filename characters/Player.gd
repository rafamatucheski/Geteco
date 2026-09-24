extends CharacterBody2D

const BULLET_SCENE: PackedScene = preload("res://guns/Bullet.tscn")
const WEAPON_CATALOG = preload("res://guns/WeaponCatalog.gd")
const WEAPON_WHEEL_SCRIPT = preload("res://guns/WeaponWheel.gd")

@export var speed: float = 27.6
const SPRINT_MULTIPLIER := 90.0 / 27.6
@export var max_health: int = 100
@export var max_armor: int = 100
@export var fire_interval: float = 0.18
@export var starting_money: int = 3000

@onready var camera = $Camera

var health: int
var armor: int = 0
var fire_cooldown: float = 0.0
var _axe_attack_epoch := 0
signal reload_finished
var _reload_audio: AudioStreamPlayer2D
var _reload_weapon := ""
var _reload_duration := 0.0
var _reload_elapsed := 0.0

signal weapon_fired
var weapon_aim_active := false
var walk_clock: float = 0.0
var _move_weight: float = 0.0
var _sprint_weight: float = 0.0
var is_recovering: bool = false
var _death_fall_tween: Tween
var _respawn_grace_active: bool = false # Janela de protecao apos respawn: impede
# que o jogador reapareca e seja morto de novo instantaneamente por gangsters
# que ainda tinham "combat_target" travado nele (bug relatado: "morri, renasci,
# e os caras continuam me atacando").
var is_dead: bool = false
var is_arrested: bool = false
var is_in_dialogue: bool = false
var is_control_disabled: bool = false
var money: int = 0
var world_pickups_collected: Array = []
var mountain_thermal_coat := false
var collectibles_found: Array[String] = []
var secret_car_leads: int = 0
signal collectible_progress_changed(total_found: int, milestone: String)
var races_finished: int = 0
var races_best_time_count: int = 0
var best_drift_score: int = 0
var drift_challenges_completed: int = 0
var chop_shop_deliveries: int = 0
var chop_shop_total_scrap: int = 0
var unlocked_achievements: Array[String] = []
var _achievement_ready := false
const DISCOVERY_CATALOG := preload("res://economy/CollectibleCatalog.gd")
signal achievement_unlocked(id: String, title: String)
const ACHIEVEMENT_CATALOG := preload("res://economy/AchievementCatalog.gd")
var ski_rental_active: bool = false
var ski_equipment_ready: bool = false
var is_skiing: bool = false
var _previous_outfit_before_ski: String = "dante_classic"
var ski_controller: PlayerSkiController = null
var active_weapon_id: String = "fists"
var weapon_inventory: Dictionary = {"fists": true, "knuckles": false, "knife": false, "bat": false, "axe": false, "pistol": false, "smg": false, "shotgun": false}
var personal_car_state: Dictionary = {}
var personal_loadout_enabled := false
var _cheat_all_weapons := false
var _cheat_sequence := ""
var _cheat_last_key_msec := 0
const ARSENAL_CHEAT_CODE := "dukenuke"
const MONEY_CHEAT_CODE := "dirtybagmoney"
const MONEY_CHEAT_REWARD := 100000
const MAX_CHEAT_CODE_LENGTH := 13
var personal_loadout: Dictionary = {}
const PERSONAL_LOADOUT := preload("res://world/harbor/monaliza/PersonalLoadout.gd")

func can_carry_weapon(id: String) -> bool:
	return weapon_inventory.get(id,false) == true and (_cheat_all_weapons or not personal_loadout_enabled or id == "fists" or id in personal_loadout.values())

func carried_weapon_inventory() -> Dictionary:
	var carried := weapon_inventory.duplicate()
	for id in carried: carried[id] = can_carry_weapon(id)
	return carried
var weapon_ammo: Dictionary = {
	"pistol": {"clip": 0, "reserve": 0},
	"smg": {"clip": 0, "reserve": 0},
	"shotgun": {"clip": 0, "reserve": 0}
}
var weapon_wheel: WeaponWheel
var weapon_customization: Dictionary = {}
var weapon_flashlight: Node2D
var weapon_laser: Node2D
const WEAPON_CUSTOMIZATION = preload("res://guns/WeaponCustomization.gd")
var primary_fire_was_pressed: bool = false
const MELEE_SWING_DURATION := 0.22
var _melee_swing_timer: float = 0.0
var combat_pose := preload("res://characters/PlayerCombatPose.gd").new()
const DanteVisualAdapter := preload("res://scripts/player/DanteVisualAdapter.gd")
## Estado do capacete de moto. Sumiu do Player entre 12 e 14/09 e o MotorcycleModel
## só liga o capacete se este método existir (has_method), então o recurso inteiro
## ficou desligado. Restaurado do backup do Codex de 12/09.
var motorcycle_helmet: Node

func ensure_motorcycle_helmet() -> Node:
	if not is_instance_valid(motorcycle_helmet):
		motorcycle_helmet = preload("res://scripts/player/DanteMotorcycleHelmet.gd").new()
		motorcycle_helmet.name = "MotorcycleHelmetState"
		motorcycle_helmet.actor = self
		add_child(motorcycle_helmet)
	return motorcycle_helmet

var _muzzle_flash_epoch := 0
@export var use_meshy_dante := true
var meshy_rig: Node3D

func set_dialogue_active(active: bool) -> void:
	is_in_dialogue = active
	is_control_disabled = active
	if active:
		velocity = Vector2.ZERO


# --- 3D DANTE RIG & VIEWPORT ---
var viewport_3d: SubViewport
var sprite_3d_display: Sprite2D

var model_root: Node3D
var torso_node: Node3D
var head_node: Node3D
var left_upper_arm: Node3D
var left_lower_arm: Node3D
var right_upper_arm: Node3D
var right_lower_arm: Node3D
var left_upper_leg: Node3D
var left_lower_leg: Node3D
var right_upper_leg: Node3D
var right_lower_leg: Node3D

var weapon_mount_node: Node3D
var current_gun_mesh: Node3D
var muzzle_flash_3d: MeshInstance3D
var muzzle_light_3d: OmniLight3D
var mat_black_jacket: StandardMaterial3D
var _flamethrower_audio: AudioStreamPlayer2D = null

# --- SISTEMA DE TRAJES & GUARDA-ROUPA ---
var current_outfit_id: String = "dante_classic"
var owned_outfits: Dictionary = {"dante_classic": true}
var clothing_store_ui: ClothingStore = null

func _ready() -> void:
	if "--meshy-dante" in OS.get_cmdline_user_args(): use_meshy_dante = true
	add_to_group("player")
	z_index = 10
	health = max_health
	if collision_mask == 1:
		collision_mask = 7
	if collision_layer == 1:
		collision_layer = 4
	
	for child in get_children():
		if child is ColorRect:
			child.hide()

	_build_dante_3d_viewport()
	visibility_changed.connect(_sync_3d_render_visibility)
	_sync_3d_render_visibility()
	_setup_weapons()
	weapon_flashlight = preload("res://guns/WeaponFlashlight.gd").new()
	weapon_flashlight.name = "WeaponFlashlight"
	add_child(weapon_flashlight)
	weapon_laser = preload("res://guns/WeaponLaser.gd").new()
	weapon_laser.name = "WeaponLaser"
	add_child(weapon_laser)
	ski_controller = preload("res://scripts/player/PlayerSkiController.gd").new()
	ski_controller.name = "PlayerSkiController"
	add_child(ski_controller)
	ski_controller.configure(self)

	var dyn_cam = load("res://systems/DynamicCamera.gd")
	if dyn_cam and camera:
		camera.set_script(dyn_cam)
		camera.set_process(true)
	if camera:
		camera.make_current()

	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr and save_mgr.has_method("has_pending_save") and save_mgr.has_pending_save():
		call_deferred("_apply_pending_save_deferred")
	call_deferred("_finish_achievement_startup")

func _finish_achievement_startup() -> void:
	_reconcile_achievements()
	_achievement_ready = true

func _reconcile_achievements() -> void:
	var stats := _achievement_stats()
	for id in ACHIEVEMENT_CATALOG.ACHIEVEMENTS:
		if id not in unlocked_achievements and ACHIEVEMENT_CATALOG.evaluate(stats, id):
			unlocked_achievements.append(id)

func _sync_3d_render_visibility() -> void:
	if not is_visible_in_tree(): _axe_attack_epoch += 1
	if not is_visible_in_tree(): _cancel_reload()
	# Boarding hides the 2D player but does not automatically stop its separate
	# 3D viewport. Keep this signal-driven so death/arrest tweens still render
	# after show(), even while physics processing is disabled.
	if is_instance_valid(viewport_3d):
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED

func _apply_pending_save_deferred() -> void:
	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr and save_mgr.has_method("apply_pending_save"):
		save_mgr.apply_pending_save(get_tree())

func _build_dante_3d_viewport() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.size = Vector2i(128, 128)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport_3d)

	var cam = Camera3D.new()
	cam.position = Vector3(0.0, 3.2, 1.4)
	cam.fov = 30.0
	viewport_3d.add_child(cam)
	cam.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)

	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	light.light_energy = 1.65
	light.light_color = Color(1.0, 0.98, 0.94)
	viewport_3d.add_child(light)

	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, -145.0, 0.0)
	fill.light_energy = 0.85
	fill.light_color = Color(0.82, 0.88, 1.0)
	viewport_3d.add_child(fill)

	var env = WorldEnvironment.new()
	var env_res = Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color(0, 0, 0, 0)
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color(0.76, 0.79, 0.86)
	env.environment = env_res
	viewport_3d.add_child(env)

	model_root = Node3D.new()
	viewport_3d.add_child(model_root)

	# Sombra 3D no chÃƒÂ£o sob os pÃƒÂ©s do Dante
	# The silhouette shadow already grounds Dante; no extra circular blob.

	_rebuild_dante_costume()

	# Exibição 2D do Sprite na Escala Exata dos Pedestres e Proporção Real com os Carros
	sprite_3d_display = Sprite2D.new()
	sprite_3d_display.texture = viewport_3d.get_texture()
	sprite_3d_display.scale = Vector2(0.24, 0.24)
	sprite_3d_display.position = Vector2(0.0, 0.0)
	add_child(sprite_3d_display)

func apply_outfit(outfit_id: String) -> void:
	current_outfit_id = outfit_id
	mountain_thermal_coat = OutfitCatalog.cold_protection(outfit_id)>=0.8
	owned_outfits[outfit_id] = true
	_rebuild_dante_costume()

func open_clothing_store() -> void:
	if not clothing_store_ui or not is_instance_valid(clothing_store_ui):
		clothing_store_ui = ClothingStore.new()
		get_tree().root.add_child(clothing_store_ui)
	clothing_store_ui.open_store(self)

func begin_ski_rental(price: int) -> bool:
	if price < 0 or ski_rental_active or is_dead or is_recovering or money < price:
		return false
	money -= price
	_previous_outfit_before_ski = current_outfit_id
	ski_rental_active = true
	apply_outfit("dante_ski")
	return true

func return_ski_rental() -> void:
	if not ski_rental_active: return
	stop_skiing()
	ski_rental_active = false
	ski_equipment_ready = false
	is_skiing = false
	apply_outfit(_previous_outfit_before_ski)

func take_ski_equipment() -> void:
	if ski_rental_active: ski_equipment_ready = true

func start_skiing(direction: Vector2 = Vector2.UP) -> void:
	if is_instance_valid(ski_controller):
		ski_controller.enter_skiing(direction)

func stop_skiing() -> void:
	if is_instance_valid(ski_controller):
		ski_controller.leave_skiing()
	is_skiing = false

func report_ski_race_finished(record: bool) -> void:
	races_finished += 1
	if record:
		races_best_time_count += 1

func _rebuild_dante_costume() -> void:
	if not model_root:
		return
	meshy_rig = null
	DanteVisualAdapter.build_dante_rig(self, current_outfit_id)
	# Todos os trajes usam o modelo importado; MeshyDanteAppearance recolore a
	# textura e prende os acessórios de cada um.
	if use_meshy_dante:
		var candidate := preload("res://scripts/player/MeshyDanteRig.gd").new()
		candidate.name = "MeshyDanteRig"
		model_root.add_child(candidate)
		if candidate.configure(self):
			meshy_rig = candidate
			meshy_rig.prepare_pose(0.0, false, false)
			combat_pose.update(self, 1.0 / 60.0, false, false, 0.0)
			meshy_rig.update_pose(0.0, false, false)
		else:
			candidate.restore()
			candidate.queue_free()

	# Depois do Meshy: a configuração dele esconde as malhas antigas já existentes.
	if is_instance_valid(motorcycle_helmet): motorcycle_helmet.sync_visual()
	if is_instance_valid(ski_controller): ski_controller.sync_visuals()
func set_meshy_dante_enabled(enabled: bool) -> void:
	use_meshy_dante = enabled
	_rebuild_dante_costume()

func _update_equipped_weapon_3d_mesh() -> void:
	if is_instance_valid(weapon_flashlight): weapon_flashlight.switch_off()
	if is_instance_valid(weapon_laser): weapon_laser.configure()
	if weapons_forbidden(): active_weapon_id = "fists"
	_axe_attack_epoch += 1
	if _reload_weapon != active_weapon_id: _cancel_reload()
	_muzzle_flash_epoch += 1
	if not weapon_mount_node:
		return
	for child in weapon_mount_node.get_children():
		child.visible = false
		child.queue_free()

	current_gun_mesh = Node3D.new()
	current_gun_mesh.position = -combat_pose.GRIPS.get(active_weapon_id, Vector3.ZERO)
	weapon_mount_node.add_child(current_gun_mesh)

	var flash_pos: Vector3 = preload("res://scripts/player/ArsenalWeapon3D.gd").build(current_gun_mesh, active_weapon_id)
	WEAPON_CUSTOMIZATION.fit(current_gun_mesh, active_weapon_id, weapon_customization, flash_pos)
	if WEAPON_CUSTOMIZATION.selected(weapon_customization,active_weapon_id,"muzzle") == "suppressor": flash_pos.z -= .145

	muzzle_flash_3d = MeshInstance3D.new()
	var sph_f = SphereMesh.new()
	sph_f.radius = 0.08
	sph_f.height = 0.16
	muzzle_flash_3d.mesh = sph_f
	var mat_flash = StandardMaterial3D.new()
	mat_flash.albedo_color = Color(1.0, 0.85, 0.2)
	mat_flash.emission_enabled = true
	mat_flash.emission = Color(1.0, 0.6, 0.1)
	mat_flash.emission_energy_multiplier = 4.5
	mat_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle_flash_3d.material_override = mat_flash
	muzzle_flash_3d.position = flash_pos
	muzzle_flash_3d.visible = false
	current_gun_mesh.add_child(muzzle_flash_3d)

	muzzle_light_3d = OmniLight3D.new()
	muzzle_light_3d.light_color = Color(1.0, 0.7, 0.2)
	muzzle_light_3d.light_energy = 2.8
	muzzle_light_3d.omni_range = 2.5
	muzzle_light_3d.visible = false
	muzzle_light_3d.position = flash_pos
	current_gun_mesh.add_child(muzzle_light_3d)
	if is_instance_valid(meshy_rig): meshy_rig.sync_knuckles()

func _make_mat(col: Color, roughness: float) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = roughness
	return mat

func _create_limb_mesh(radius: float, height: float, mat: Material, offset: Vector3) -> MeshInstance3D:
	var mesh_inst = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius * 0.85
	cyl.height = height
	mesh_inst.mesh = cyl
	mesh_inst.material_override = mat
	mesh_inst.position = offset
	return mesh_inst

func _create_shoe_mesh(mat: Material, offset: Vector3) -> MeshInstance3D:
	var shoe = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.09, 0.065, 0.16)
	shoe.mesh = box
	shoe.material_override = mat
	shoe.position = offset
	return shoe

func _physics_process(delta: float) -> void:
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	_melee_swing_timer = maxf(0.0, _melee_swing_timer - delta)
	var input_vector: Vector2 = Vector2.ZERO if (is_control_disabled or is_in_dialogue) else get_node("/root/GameInput").movement()
	var is_sprinting: bool = false if (is_control_disabled or is_in_dialogue) else get_node("/root/GameInput").sprinting()
	var current_speed: float = speed * SPRINT_MULTIPLIER if is_sprinting else speed
	current_speed *= _movement_projection_scale(input_vector)

	var is_moving: bool = input_vector != Vector2.ZERO
	if is_skiing:
		if is_instance_valid(ski_controller):
			ski_controller.physics_step(delta)
		rotation = 0.0
		return
	elif is_moving:
		velocity = input_vector * current_speed
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * _movement_projection_scale(velocity) * delta)

	rotation = 0.0
	move_and_slide()
	var travelled := get_position_delta().length()
	is_moving = travelled > 0.001 and velocity.length_squared() > 0.01
	_advance_gait(travelled, delta, is_moving, is_sprinting)
	_handle_footsteps(is_moving, is_sprinting)

	# --- ROTAÇÃO 3D E ANIMAÇÃO ARTICULADA DO DANTE ---
	var mouse_pos: Vector2 = get_node("/root/GameInput").aim_target(self)
	var is_aiming: bool = Input.is_action_pressed("fire") or Input.is_action_pressed("aim") or (is_instance_valid(weapon_flashlight) and weapon_flashlight.enabled)
	weapon_aim_active = Input.is_action_pressed("aim") and active_weapon_id not in ["fists","knife","axe","knuckles","bat","grenade"] and not is_control_disabled and not is_in_dialogue
	var aim_dir: Vector2 = (mouse_pos - global_position).normalized() if is_aiming else (input_vector.normalized() if is_moving else Vector2.ZERO)

	if model_root and aim_dir.length_squared() > 0.01:
		var target_angle_3d: float = -atan2(aim_dir.y, aim_dir.x) - PI * 0.5
		model_root.rotation.y = lerp_angle(model_root.rotation.y, target_angle_3d, 15.0 * delta)

	_update_locomotion(delta, is_moving, is_sprinting)
	if is_instance_valid(meshy_rig):
		meshy_rig.prepare_pose(delta, is_moving, is_sprinting)
	# Left hand follows right foot, using the same contact phase as the legs.
	var arm_swing := _gait_arm_swing()
	combat_pose.update(self, delta, is_aiming, is_sprinting and is_moving, arm_swing)
	if is_instance_valid(meshy_rig):
		meshy_rig.update_pose(delta, is_moving, is_sprinting)
	if is_instance_valid(motorcycle_helmet): motorcycle_helmet.apply_on_foot_pose()

	if not is_control_disabled and not is_in_dialogue:
		_handle_weapon_fire()
		if Input.is_action_just_pressed("vehicle_interact"):
			if get_tree().get_nodes_in_group("weapon_store_open").is_empty():
				get_node("/root/GameInput").reset_sprint_toggle()
				try_enter_vehicle()

func _movement_projection_scale(direction: Vector2) -> float:
	var presentation: Node = get_meta("interior_actor_presentation") if has_meta("interior_actor_presentation") else null
	if not is_instance_valid(presentation) and has_meta("interior_movement_presentation"):
		presentation = get_meta("interior_movement_presentation")
	if not is_instance_valid(presentation) or direction.is_zero_approx(): return 1.0
	# Match room travel to the original outdoor projection, before portrait resize.
	var cam := viewport_3d.get_camera_3d()
	var axis := Vector3(direction.normalized().x, 0, direction.normalized().y) * .01
	var native_pixels := (cam.unproject_position(axis) - cam.unproject_position(-axis)).length() / .02
	native_pixels *= float(presentation.old_viewport_size.y) / viewport_3d.size.y * presentation.old_scale.x
	return presentation.pixels_per_rig_unit(direction) / maxf(native_pixels, .001)

func _gait_arm_swing() -> float:
	# Human gait keeps the hands opposite the feet, but the arms do not need
	# to follow the full leg excursion. Keep walking subtle and let running
	# add only a moderate extra swing with a small lead into the next step.
	var phase_lead := PI * 0.175 * _sprint_weight
	var amplitude := lerpf(0.32, 0.55, _sprint_weight)
	return cos(walk_clock + phase_lead) * amplitude * _move_weight

func _advance_gait(travelled: float, delta: float, moving: bool, sprinting: bool) -> void:
	# Project one model unit onto the same ground plane as the sprite. Camera
	# zoom then scales feet and travel together, so cadence survives zoom changes.
	if not moving or not viewport_3d or not sprite_3d_display:
		return
	var cam := viewport_3d.get_camera_3d()
	var direction := get_position_delta().normalized()
	var axis := Vector3(direction.x, 0, direction.y) * 0.01
	var pixels_per_unit := (cam.unproject_position(axis) - cam.unproject_position(-axis)).length() * sprite_3d_display.scale.x / 0.02
	var interior_presentation: Node = get_meta("interior_actor_presentation") if has_meta("interior_actor_presentation") else null
	if is_instance_valid(interior_presentation):
		pixels_per_unit = interior_presentation.pixels_per_rig_unit(direction)
	var run := move_toward(_sprint_weight, 1.0 if sprinting else 0.0, delta * 4.5)
	# Stride length must grow with speed, not just cadence. At the old 0.29 the
	# sprint's ~3.3x speed increase over walking was almost entirely absorbed
	# by faster leg-cycling instead of longer strides (legs looked sped-up).
	var stride := lerpf(0.22, 0.34, run)
	var support_fraction := lerpf(0.5, 0.34, run)
	walk_clock = fposmod(walk_clock + travelled * TAU / maxf(2.0 * stride * pixels_per_unit / support_fraction, 0.001), TAU)

func _update_locomotion(delta: float, moving: bool, sprinting: bool) -> void:
	_move_weight = move_toward(_move_weight, 1.0 if moving else 0.0, delta * 7.0)
	_sprint_weight = move_toward(_sprint_weight, 1.0 if moving and sprinting else 0.0, delta * 4.5)
	var stride: float = lerpf(0.22, 0.34, _sprint_weight) * _move_weight
	var lift: float = lerpf(0.065, 0.32, _sprint_weight) * _move_weight
	# Rise over the supporting leg at mid-stance; sink at the wider contact
	# pose. Constant low hips made the walk read as a permanent crouch.
	var support_fraction := lerpf(0.5, 0.34, _sprint_weight)
	var half_cycle := fposmod(walk_clock, PI) / TAU
	var support_progress := minf(half_cycle / support_fraction, 1.0)
	var support_z := lerpf(-stride, stride, support_progress)
	var hip_height := 0.045 + sqrt(0.638 * 0.638 - support_z * support_z)
	var compression := sin(support_progress * PI) * 0.025 * _sprint_weight
	var bob := (hip_height - 0.684 - compression) * _move_weight
	# Running pushes the pelvis upward after toe-off, unlike walking's
	# mid-stance rise. The flight arc is shared by both legs and the torso.
	if half_cycle > support_fraction:
		var flight := (half_cycle - support_fraction) / (0.5 - support_fraction)
		bob += sin(flight * PI) * 0.065 * _sprint_weight * _move_weight
	# Negative X tips the chest toward the rig's forward axis (-Z).
	var lean: float = -lerpf(0.025, 0.24, _sprint_weight) * _move_weight
	if torso_node:
		torso_node.position = Vector3(0, 0.85 + bob, 0)
		torso_node.rotation = Vector3(lean, sin(walk_clock) * 0.035 * _move_weight, cos(walk_clock) * 0.012 * _move_weight)
	_sync_upper_body_anchors(lean)
	_pose_stride_leg(left_upper_leg, left_lower_leg, walk_clock, stride, lift, bob, lerpf(0.5, 0.34, _sprint_weight))
	_pose_stride_leg(right_upper_leg, right_lower_leg, walk_clock + PI, stride, lift, bob, lerpf(0.5, 0.34, _sprint_weight))

func _pose_stride_leg(upper: Node3D, lower: Node3D, phase: float, stride: float, lift: float, bob: float, support_fraction: float = 0.5) -> void:
	if not upper or not lower:
		return
	# Stance follows a level floor; swing clears it. The anatomical knee
	# bends backward, and the ankle compensates to keep the sole horizontal.
	var cycle := fposmod(phase, TAU) / TAU
	# Shorter support in sprint gives a brief flight interval between contacts.
	# The swing curve matches the stance velocity at lift-off and touchdown.
	var foot_z := lerpf(-stride, stride, minf(cycle / support_fraction, 1.0))
	var foot_lift := 0.0
	if cycle > support_fraction:
		var t := (cycle - support_fraction) / (1.0 - support_fraction)
		var ratio := (1.0 - support_fraction) / support_fraction
		foot_z = stride * (1.0 + 2.0 * ratio * t - (6.0 + 6.0 * ratio) * t * t + (4.0 + 4.0 * ratio) * t * t * t)
		# Fold the heel early, then drive the bent knee forward before landing.
		var recovery := pow(t, lerpf(1.0, 0.70, _sprint_weight))
		foot_lift = sin(recovery * PI) * sin(recovery * PI) * lift
	upper.position.y = 0.684 + bob
	var down := upper.position.y - 0.045 - foot_lift
	var thigh := 0.34
	var shin := 0.30
	var reach := clampf(Vector2(down, foot_z).length(), 0.05, thigh + shin - 0.001)
	var knee := -acos(clampf((reach * reach - thigh * thigh - shin * shin) / (2.0 * thigh * shin), -1.0, 1.0))
	upper.rotation.x = atan2(-foot_z, down) - atan2(shin * sin(knee), thigh + shin * cos(knee))
	lower.rotation.x = knee
	var foot := lower.get_node_or_null("Foot") as Node3D
	if foot:
		foot.rotation.x = -(upper.rotation.x + lower.rotation.x)

func _sync_upper_body_anchors(forward_lean: float) -> void:
	# Use the actual torso transform, including yaw and roll. Reconstructing only
	# pitch with the opposite sine detached both the neck and shoulders in sprint.
	if not torso_node:
		return
	if head_node:
		head_node.position = torso_node.transform * Vector3(0, 0.36, 0)
		head_node.rotation = Vector3(forward_lean * 0.35, torso_node.rotation.y * 0.35, torso_node.rotation.z * 0.35)
	if left_upper_arm and right_upper_arm:
		left_upper_arm.position = torso_node.transform * Vector3(-0.185, 0.20, 0)
		right_upper_arm.position = torso_node.transform * Vector3(0.185, 0.20, 0)

func _trigger_muzzle_flash_3d() -> void:
	weapon_fired.emit()
	# A thrown grenade has no muzzle; keep firearm effects on firearms only.
	if active_weapon_id == "grenade":
		return
	if muzzle_flash_3d and muzzle_light_3d:
		_muzzle_flash_epoch += 1
		var epoch := _muzzle_flash_epoch
		var heavy := active_weapon_id in ["magnum", "shotgun", "sawed_off", "rpg"]
		muzzle_flash_3d.scale = Vector3.ONE * (1.35 if heavy else 0.8)
		var suppressed: bool = WEAPON_CUSTOMIZATION.selected(weapon_customization,active_weapon_id,"muzzle") == "suppressor"
		if suppressed: muzzle_flash_3d.scale *= .22
		if active_weapon_id == "flamethrower":
			muzzle_flash_3d.scale = Vector3(0.30, 0.30, 1.65)
		elif active_weapon_id == "rpg":
			muzzle_flash_3d.scale = Vector3(0.70, 0.70, 2.2)
		muzzle_flash_3d.visible = true
		muzzle_light_3d.visible = not suppressed
		var t = create_tween()
		t.tween_interval(0.075 if active_weapon_id == "flamethrower" else (0.09 if active_weapon_id == "rpg" else (0.065 if heavy else 0.035)))
		t.tween_callback(_finish_muzzle_flash.bind(epoch))

func _finish_muzzle_flash(epoch: int) -> void:
	if epoch != _muzzle_flash_epoch:
		return
	if is_instance_valid(muzzle_flash_3d): muzzle_flash_3d.hide()
	if is_instance_valid(muzzle_light_3d): muzzle_light_3d.hide()

var _last_step_side: int = 0
var _step_variation_index: int = 0

func _handle_footsteps(moving: bool, is_sprinting: bool) -> void:
	if not moving:
		return
	var current_side: int = 1 if sin(walk_clock) > 0.0 else -1
	if current_side != _last_step_side:
		_last_step_side = current_side
		_play_footstep(is_sprinting)

func _is_raining_outside() -> bool:
	var dnm = get_tree().get_first_node_in_group("day_night_manager")
	if dnm != null and dnm.has_method("is_raining"):
		return dnm.is_raining()
	return false

var _footstep_voices: Array[AudioStreamPlayer2D] = []

func _play_footstep(is_sprinting: bool) -> void:
	if _footstep_voices.is_empty():
		for i in 2:
			var voice := AudioStreamPlayer2D.new()
			voice.name = "Footstep%d" % i
			voice.bus = &"SFX"
			voice.volume_db = -80.0
			voice.max_distance = 350.0
			add_child(voice)
			_footstep_voices.append(voice)
	var surface: String = preload("res://audio/footsteps/FootstepSurfaceResolver.gd").resolve(self, _is_raining_outside())
	for water in get_tree().get_nodes_in_group("water_surface"):
		water.actor_step(self, is_sprinting)
	var footstep_player := _footstep_voices[_step_variation_index % 2]
	footstep_player.stream = ProceduralAudio.get_footstep_stream(surface, _step_variation_index)
	_step_variation_index = (_step_variation_index + 1) % 4
	footstep_player.volume_db = -25.0 if is_sprinting else -29.0
	if surface == "water": footstep_player.volume_db += 5.0
	footstep_player.pitch_scale = randf_range(0.95, 1.05)
	footstep_player.play()

func take_damage(amount: int, _is_player_attacker: bool = false) -> void:
	if amount <= 0 or is_dead or is_arrested or _respawn_grace_active:
		return
	var absorbed := mini(armor, amount)
	armor -= absorbed
	health = maxi(0, health - (amount - absorbed))
	_refresh_weapon_ui()
	
	if mat_black_jacket:
		mat_black_jacket.albedo_color = Color(1.0, 0.2, 0.2)
		var tween = create_tween()
		tween.tween_property(mat_black_jacket, "albedo_color", mat_black_jacket.get_meta("rest_albedo", Color.WHITE), 0.25)
	# A jaqueta antiga fica oculta sob o Dante Meshy; o flash vai no material dele.
	if is_instance_valid(meshy_rig): meshy_rig.flash_damage()

	_play_audio(ProceduralAudio.get_squish_stream(), -4.0)
	preload("res://audio/reactions/PainReaction.gd").react(self, amount - absorbed)
	
	if health <= 0:
		_wasted()

func get_run_over(impact_velocity: Vector2, _is_player_driver: bool = false) -> void:
	if is_dead or is_arrested or _respawn_grace_active or is_recovering or not impact_velocity.is_finite():
		return
	if impact_velocity.length() < preload("res://guns/combat/VehiclePersonImpact.gd").MIN_SPEED:
		return
	is_recovering = true
	var damage = clampi(int(impact_velocity.length() * 0.25), 35, 100)
	_spawn_blood_burst(impact_velocity.normalized())
	# This actor supplies its own compact splash and impact audio. The vehicle
	# must not add a second, broad splash for the same contact.
	set_meta("vehicle_feedback_ms", Time.get_ticks_msec())
	velocity = impact_velocity.normalized() * maxf(320.0, impact_velocity.length() * 1.0)
	take_damage(damage)
	
	if health > 0:
		preload("res://guns/combat/GroundBlood.gd").spawn(self, false)
		await get_tree().create_timer(0.8).timeout
		is_recovering = false

func add_armor(amount: int) -> void:
	armor = clampi(armor + amount, 0, max_armor)
	_refresh_weapon_ui()
	_show_weapon_notice("COLETE %d%%" % armor)

## Only distinct, catalogued finds pay rewards; legacy IDs remain preserved.
func add_collectible(collectible_id: String, _label: String = "", _at: Vector2 = Vector2.ZERO) -> bool:
	if collectible_id.is_empty() or collectibles_found.has(collectible_id): return false
	collectibles_found.append(collectible_id)
	var total := DISCOVERY_CATALOG.known_count(collectibles_found)
	var known := DISCOVERY_CATALOG.has_entry(collectible_id)
	var bonus := int(DISCOVERY_CATALOG.MILESTONE_CASH.get(total, 0)) if known else 0
	var reward := DISCOVERY_CATALOG.FIND_CASH + bonus if known else 0
	money += reward
	var hud := get_tree().get_first_node_in_group("hud")
	var english := TranslationServer.get_locale().begins_with("en")
	if hud and hud.has_method("show_notice"):
		var title := _label if not _label.is_empty() else ("DISCOVERY" if english else "DESCOBERTA")
		var message := "%s · %d/%d" % [title, total, DISCOVERY_CATALOG.ENTRIES.size()]
		if reward > 0: message += " · +$%d" % reward
		if bonus > 0: message += (" · COLLECTION BONUS" if english else " · BÔNUS DE COLEÇÃO")
		hud.show_notice(message, Color("#d5a43a"))
	preload("res://audio/rewards/RewardAudioBank.gd").play(self, "collectible")
	_refresh_weapon_ui()
	collectible_progress_changed.emit(total, "cash" if bonus > 0 else "")
	return true

## Chamado por NightRaceController ao cruzar a chegada de qualquer corrida.
func report_race_finished(is_new_best: bool) -> void:
	races_finished += 1
	if is_new_best:
		races_best_time_count += 1
	_check_achievements()

## Chamado por DriftChallengeZone ao terminar (saiu da zona ou tempo esgotou).
func report_drift_score(score: int, is_new_best: bool) -> void:
	if score > 0:
		drift_challenges_completed += 1
	if is_new_best:
		best_drift_score = maxi(best_drift_score, score)
	_check_achievements()

## Chamado por ChopShopZone ao terminar de esmagar um carro entregue.
func report_chop_shop_delivery(reward: int) -> void:
	chop_shop_deliveries += 1
	chop_shop_total_scrap += maxi(0, reward)
	_check_achievements()

func _achievement_stats() -> Dictionary:
	var ski_races := 0
	var campaign := get_node_or_null("/root/CampaignState")
	if campaign:
		for course in preload("res://world/mountain_pass/MountainSkiLayout.gd").COURSES:
			if campaign.get_race_best_time(course.id) >= 0.0: ski_races += 1
	var mountain_clues := 0
	for id in ["mountain_expedition_pack","mountain_expedition_journal","mountain_expedition_camera"]:
		if id in collectibles_found: mountain_clues += 1
	var weapon_count := 0
	for owned in weapon_inventory.values():
		if owned == true:
			weapon_count += 1
	var wanted := get_node_or_null("/root/WantedManager")
	var wanted_stars := int(wanted.current_stars) if wanted else 0
	return {
		"collectibles": DISCOVERY_CATALOG.known_count(collectibles_found),
		"ski_races": ski_races,
		"mountain_clues": mountain_clues,
		"leads": secret_car_leads,
		"races": races_finished,
		"bests": races_best_time_count,
		"drift_zones": drift_challenges_completed,
		"best_drift_score": best_drift_score,
		"chop_shop_deliveries": chop_shop_deliveries,
		"money": money,
		"weapons": weapon_count,
		"armor": armor,
		"wanted_stars": wanted_stars,
	}

## Confere o catálogo inteiro contra as stats atuais e desbloqueia o que
## bateu critério. Chamado a cada _refresh_weapon_ui() (cobre grana, armas,
## colete, achados) e a cada corrida terminada.
func _check_achievements() -> void:
	if not _achievement_ready: return
	var stats := _achievement_stats()
	for achievement_id in ACHIEVEMENT_CATALOG.ACHIEVEMENTS.keys():
		if unlocked_achievements.has(achievement_id):
			continue
		if ACHIEVEMENT_CATALOG.evaluate(stats, achievement_id):
			_unlock_achievement(achievement_id)

func _unlock_achievement(achievement_id: String) -> void:
	if not _achievement_ready or achievement_id in unlocked_achievements or not ACHIEVEMENT_CATALOG.ACHIEVEMENTS.has(achievement_id): return
	unlocked_achievements.append(achievement_id)
	var reward := ACHIEVEMENT_CATALOG.cash_reward(achievement_id)
	money += reward
	var entry: Dictionary = ACHIEVEMENT_CATALOG.ACHIEVEMENTS.get(achievement_id, {})
	var title := String(entry.get("name", achievement_id))
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_achievement"):
		hud.show_achievement(title, String(entry.get("desc", "")) + " · +$%d" % reward)
	if hud and hud.has_method("set_money"): hud.set_money(money)
	achievement_unlocked.emit(achievement_id, title)

func add_weapon_loot(id: StringName, ammo_amount: int, show_notice: bool = true) -> bool:
	var weapon_id := String(id)
	var data := WEAPON_CATALOG.get_weapon(weapon_id)
	if data.is_empty():
		return false
	if not (weapon_inventory.get(weapon_id, false) == true):
		weapon_inventory[weapon_id] = true
		weapon_ammo[weapon_id] = {"clip": 0, "reserve": 0}
	var ammo: Dictionary = weapon_ammo.get(weapon_id, {"clip": 0, "reserve": 0})
	ammo["reserve"] = int(ammo.get("reserve", 0)) + maxi(0, ammo_amount)
	weapon_ammo[weapon_id] = ammo
	if personal_loadout_enabled:
		var slot := PERSONAL_LOADOUT.slot_for(weapon_id)
		if slot != "" and String(personal_loadout.get(slot,"")) == "": personal_loadout[slot] = weapon_id
	if can_carry_weapon(weapon_id): active_weapon_id = weapon_id
	_update_equipped_weapon_3d_mesh()
	_refresh_weapon_ui()
	var suffix := ""
	if personal_loadout_enabled and not can_carry_weapon(weapon_id):
		suffix = " / GUARDADA NO ARSENAL" if not TranslationServer.get_locale().begins_with("en") else " / STORED IN ARSENAL"
	if show_notice: _show_weapon_notice("PEGOU " + String(data.get("label", weapon_id)) + suffix)
	return true

static var _cached_soft_particle_texture: GradientTexture2D = null

static func _make_soft_particle_texture() -> GradientTexture2D:
	if _cached_soft_particle_texture != null:
		return _cached_soft_particle_texture
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_cached_soft_particle_texture = tex
	return tex

func _spawn_blood_burst(dir: Vector2) -> void:
	var blood_particles := CPUParticles2D.new()
	blood_particles.emitting = true
	blood_particles.one_shot = true
	blood_particles.explosiveness = 0.9
	blood_particles.amount = 14
	blood_particles.lifetime = 0.45
	blood_particles.spread = 45.0
	blood_particles.direction = dir
	blood_particles.initial_velocity_min = 25.0
	blood_particles.initial_velocity_max = 65.0
	blood_particles.gravity = Vector2(0, 90)
	# Scale is a texture multiplier, not a diameter in world pixels.
	blood_particles.scale_amount_min = 2.0 / 64.0
	blood_particles.scale_amount_max = 5.0 / 64.0
	blood_particles.color = Color(0.75, 0.05, 0.05, 0.95)
	blood_particles.texture = _make_soft_particle_texture()
	blood_particles.local_coords = false
	blood_particles.z_as_relative = false
	blood_particles.z_index = 20
	get_parent().add_child(blood_particles)
	blood_particles.global_position = global_position
	blood_particles.finished.connect(blood_particles.queue_free)
	_play_audio(ProceduralAudio.get_scream_stream(), -4.0)

func _create_3d_blood_puddle() -> void:
	preload("res://guns/combat/GroundBlood.gd").spawn(self, true)

func _wasted() -> void:
	if is_dead or is_arrested:
		return
	if is_skiing: stop_skiing()
	is_dead = true
	collision_layer = 0
	for col in find_children("", "CollisionShape2D", true, false):
		col.set_deferred("disabled", true)
	for col in find_children("", "CollisionPolygon2D", true, false):
		col.set_deferred("disabled", true)
	_release_controlled_vehicle()
	
	visible = true
	is_recovering = true
	_create_3d_blood_puddle()
	set_physics_process(false)
	_play_audio(ProceduralAudio.get_wasted_stream(), 0.0)
	
	# Animacao de queda: antes o personagem ficava perfeitamente em pe mesmo
	# morto (model_root.rotation nunca era tocado aqui). Agora ele desaba
	# suavemente, mesmo angulo de "corpo caido" ja usado pelos NPCs em
	# AnimatedPedestrian3D._die(), so que animado em vez de instantaneo.
	if model_root:
		_death_fall_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_death_fall_tween.tween_property(model_root, "rotation:x", PI * 0.42, 0.45)
		_death_fall_tween.parallel().tween_property(model_root, "rotation:z", randf_range(-0.35, 0.35), 0.45)
	
	var wm = get_node_or_null("/root/WantedManager")
	if wm:
		wm.stand_down_police()
	
	var flash := CanvasLayer.new()
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(0.8, 0.1, 0.1, 0.0)
	flash.add_child(rect)
	
	var wasted_label := Label.new()
	wasted_label.text = "SE FODEU"
	wasted_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wasted_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wasted_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	wasted_label.add_theme_font_size_override("font_size", 42)
	wasted_label.add_theme_color_override("font_color", Color(1, 0.1, 0.1))
	wasted_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	wasted_label.add_theme_constant_override("shadow_offset_x", 3)
	wasted_label.add_theme_constant_override("shadow_offset_y", 3)
	wasted_label.modulate.a = 0.0
	wasted_label.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	wasted_label.scale = Vector2(1.35, 1.35)
	flash.add_child(wasted_label)
	
	get_tree().get_root().add_child(flash)
	
	# Entrada suave em vez do vermelho/texto aparecerem de golpe no frame
	# seguinte: o tint sobe de 0 pra 0.45 de alpha, e o texto "cai" de um
	# zoom levemente maior pro tamanho normal, com fade junto.
	var intro_tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	intro_tween.tween_property(rect, "color:a", 0.45, 0.35)
	intro_tween.tween_property(wasted_label, "modulate:a", 1.0, 0.35)
	intro_tween.tween_property(wasted_label, "scale", Vector2.ONE, 0.35)
	
	await get_tree().create_timer(2.2).timeout
	flash.queue_free()
	
	_respawn_at_hospital()


func arrest_and_respawn() -> void:
	if is_dead or is_arrested:
		return
	is_arrested = true
	is_recovering = true
	_release_controlled_vehicle()
	show()
	velocity = Vector2.ZERO
	set_physics_process(false)

	var flash := CanvasLayer.new()
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(0.1, 0.2, 0.8, 0.45)
	flash.add_child(rect)
	var label := Label.new()
	label.text = "PRESO"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 46)
	label.add_theme_color_override("font_color", Color(0.2, 0.6, 1.0))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 3)
	flash.add_child(label)
	get_tree().get_root().add_child(flash)

	var wm = get_node_or_null("/root/WantedManager")
	if wm:
		wm.stand_down_police()

	await get_tree().create_timer(2.2).timeout
	if is_instance_valid(flash):
		flash.queue_free()
	_respawn_at_hospital()


func _release_controlled_vehicle() -> void:
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if not is_instance_valid(vehicle) or vehicle.get("is_driven_by_player") != true:
			continue
		if vehicle.has_method("force_exit_vehicle"):
			vehicle.force_exit_vehicle()
		elif vehicle.has_method("exit_vehicle"):
			vehicle.exit_vehicle()
		else:
			vehicle.set("is_driven_by_player", false)


func _get_recovery_position() -> Vector2:
	var hospital := _get_arrest_spawn() if is_arrested else _get_active_checkpoint()
	if hospital == null and not is_arrested:
		hospital = _get_nearest_hospital_spawn()
	return hospital.global_position if hospital else Vector2(1125, 375)

func _respawn_at_hospital(recovery_position: Variant = null) -> void:
	# The recovery timer runs while paused, but the fall tween does not.
	# Cancel it before restoring the pose so unpausing cannot topple Dante again.
	if _death_fall_tween != null:
		_death_fall_tween.kill()
		_death_fall_tween = null
	health = max_health
	velocity = Vector2.ZERO
	global_position = recovery_position if recovery_position is Vector2 else _get_recovery_position()
	is_control_disabled = false
	# Restore the living pose before showing the actor at the destination.
	# Spawn selection above still needs is_arrested to choose the police station.
	is_dead = false
	is_arrested = false
	is_recovering = false
	if model_root:
		model_root.rotation = Vector3.ZERO
	# Respawn e teleporte: sem isso o jogador seria desenhado deslizando do lugar
	# onde morreu/foi preso ate o hospital.
	reset_physics_interpolation()
	collision_layer = 4
	for col in find_children("", "CollisionShape2D", true, false):
		col.set_deferred("disabled", false)
	for col in find_children("", "CollisionPolygon2D", true, false):
		col.set_deferred("disabled", false)
	show()
	set_physics_process(true)
	if camera:
		camera.remove_meta("compact_interior")
		camera.make_current()
		camera.reset_smoothing()
	_refresh_weapon_ui()
	var wm = get_node_or_null("/root/WantedManager")
	if wm:
		wm.dismiss_all_police()

	# Limpa a mira de qualquer gangster que ainda estivesse com "combat_target"
	# travado no jogador antes de morrer. Sem isso, ao reaparecer no hospital
	# o(s) mesmo(s) gangster(s) que acabaram de matar o jogador continuavam
	# atirando nele imediatamente (o alvo nunca era resetado por morte).
	for ped in get_tree().get_nodes_in_group("pedestrian"):
		if is_instance_valid(ped) and ped.get("is_gangster") == true and ped.get("combat_target") == self:
			ped.set("combat_target", null)

	# Janela curta de invulnerabilidade pos-respawn (padrao GTA: reaparecer no
	# hospital te da alguns segundos livre de dano), garantindo que mesmo um
	# inimigo proximo que ainda nao tenha perdido a mira não mate o jogador de
	# novo instantaneamente.
	_respawn_grace_active = true
	var grace_timer := get_tree().create_timer(3.0)
	grace_timer.timeout.connect(func():
		_respawn_grace_active = false
	)


func _get_active_checkpoint() -> Node2D:
	for provider in get_tree().get_nodes_in_group("player_checkpoint_provider"):
		if is_instance_valid(provider) and provider.has_method("get_checkpoint_spawn"):
			var checkpoint := provider.get_checkpoint_spawn() as Node2D
			if is_instance_valid(checkpoint):
				return checkpoint
	return null


func _get_arrest_spawn() -> Node2D:
	# Arrest always returns to the city's station, never the nearest clinic.
	var scene := get_tree().current_scene
	if scene:
		var entrance := scene.get_node_or_null("District/Police/Entrance") as Node2D
		if entrance:
			var outside := entrance.get_node_or_null("OutsideReturn") as Node2D
			return outside if outside else entrance
	return get_tree().get_first_node_in_group("police_spawn") as Node2D


func _get_nearest_hospital_spawn() -> Node2D:
	var nearest: Node2D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("hospital_spawn"):
		var hospital := node as Node2D
		if not is_instance_valid(hospital):
			continue
		var distance := global_position.distance_squared_to(hospital.global_position)
		if nearest == null or distance < best_distance:
			nearest = hospital
			best_distance = distance
	return nearest

func _play_audio(stream: AudioStream, volume_db: float = -6.0, maximum_distance: float = 600.0) -> void:
	var player = AudioStreamPlayer2D.new()
	player.bus = &"SFX"
	player.stream = stream
	player.volume_db = volume_db
	player.max_distance = maximum_distance
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

func _setup_weapons() -> void:
	active_weapon_id = "fists"
	if money == 0:
		money = starting_money
	weapon_inventory = {
		"fists": true,
		"knife": false,
		"pistol": false,
		"magnum": false,
		"smg": false,
		"shotgun": false,
		"sawed_off": false,
		"ak47": false,
		"m4a1": false,
		"rpg": false,
		"flamethrower": false,
		"grenade": false
	}
	weapon_ammo = {
		"fists": {"clip": -1, "reserve": -1},
		"knife": {"clip": -1, "reserve": -1},
		"pistol": {"clip": 0, "reserve": 0},
		"magnum": {"clip": 0, "reserve": 0},
		"smg": {"clip": 0, "reserve": 0},
		"shotgun": {"clip": 0, "reserve": 0},
		"sawed_off": {"clip": 0, "reserve": 0},
		"ak47": {"clip": 0, "reserve": 0},
		"m4a1": {"clip": 0, "reserve": 0},
		"rpg": {"clip": 0, "reserve": 0},
		"flamethrower": {"clip": 0, "reserve": 0},
		"grenade": {"clip": 0, "reserve": 0}
	}
	weapon_wheel = WEAPON_WHEEL_SCRIPT.new()
	var weapon_notice_layer := CanvasLayer.new()
	weapon_notice_layer.name = "WeaponNotices"
	weapon_notice_layer.layer = 40
	weapon_notice_layer.add_child(weapon_wheel)
	var ui_parent: Node = get_tree().current_scene
	if ui_parent == null:
		ui_parent = get_tree().root
	ui_parent.call_deferred("add_child", weapon_notice_layer)
	_update_equipped_weapon_3d_mesh()
	call_deferred("_refresh_weapon_ui")

func _input(event: InputEvent) -> void:
	if _handle_cheat_key(event):
		get_viewport().set_input_as_handled()
		return
	if not visible or is_control_disabled or is_in_dialogue or get_tree().get_nodes_in_group("weapon_store_open").size() > 0:
		return
	if event.is_action_pressed("weapon_next"):
		_cycle_weapon(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("weapon_previous"):
		_cycle_weapon(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reload"):
		if not is_dead and not is_arrested and not is_recovering:
			_reload_active_weapon()
			# Square also interacts: leave it available when no reload can start.
			if is_reloading():
				# Physics-polled interactions must not also see this shared press.
				if event.is_action_pressed("interact"): Input.action_release("interact")
				get_viewport().set_input_as_handled()
	elif event.is_action_pressed("unarmed"):
		if weapon_inventory.get("fists",false): equip_weapon("fists")
		get_viewport().set_input_as_handled()
	elif event.is_pressed() and not event.is_echo():
		var weapons := ["pistol","magnum","smg","shotgun","sawed_off","ak47","m4a1","rpg","flamethrower","grenade"]
		for i in weapons.size():
			if event.is_action_pressed("weapon_slot_%d" % (i+1)) and can_carry_weapon(weapons[i]):
				equip_weapon(weapons[i])
				get_viewport().set_input_as_handled()
				break


func _handle_cheat_key(event: InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo:
		return false
	var focus := get_viewport().gui_get_focus_owner()
	var game_input := get_node_or_null("/root/GameInput")
	if get_tree().paused or not _reload_allowed() or focus is LineEdit or focus is TextEdit or (game_input != null and game_input.remapping):
		_cheat_sequence = ""
		return false
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		_cheat_sequence = ""
		return false
	var now := Time.get_ticks_msec()
	if now - _cheat_last_key_msec > 3000:
		_cheat_sequence = ""
	_cheat_last_key_msec = now
	var code: int = event.unicode if event.unicode != 0 else event.keycode
	if code == 0: code = event.physical_keycode
	# Special key codes (e.g. Shift) are not Unicode characters.
	# Cheats only accept ASCII letters; validate before converting.
	if not ((code >= 65 and code <= 90) or (code >= 97 and code <= 122)):
		_cheat_sequence = ""
		return false
	var letter := String.chr(code).to_lower()
	_cheat_sequence = (_cheat_sequence + letter).right(MAX_CHEAT_CODE_LENGTH)
	if _cheat_sequence.ends_with(ARSENAL_CHEAT_CODE):
		_cheat_sequence = ""
		_activate_arsenal_cheat()
		return true
	if _cheat_sequence.ends_with(MONEY_CHEAT_CODE):
		_cheat_sequence = ""
		_activate_money_cheat()
		return true
	return false

func _activate_arsenal_cheat() -> void:
	_cancel_reload()
	_cheat_all_weapons = true
	for id in WEAPON_CATALOG.ORDER:
		var capacity := int(WEAPON_CATALOG.get_weapon(id).get("magazine_size", -1))
		weapon_inventory[id] = true
		weapon_ammo[id] = {"clip": capacity, "reserve": maxi(9999, int(weapon_ammo.get(id, {}).get("reserve", 0))) if capacity >= 0 else -1}
	_refresh_weapon_ui()
	_show_weapon_notice("Cheat ativado")

func _activate_money_cheat() -> void:
	money += MONEY_CHEAT_REWARD
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_money"):
		hud.set_money(money)
	_show_weapon_notice("Cheat ativado: +$100.000")

## Spatial membership also covers save restoration and clears after respawn.
func weapons_forbidden() -> bool:
	if not is_inside_tree(): return false
	for room in get_tree().get_nodes_in_group("weapon_free_zone"):
		if room is Node2D and room.get_world_2d() == get_world_2d() and room.contains_point(global_position):
			return true
	return false

func enforce_weapon_restrictions() -> void:
	if not weapons_forbidden(): return
	_cancel_reload()
	if active_weapon_id == "fists": return
	active_weapon_id = "fists"
	_update_equipped_weapon_3d_mesh()
	_refresh_weapon_ui()

func _block_garage_combat() -> bool:
	if not weapons_forbidden(): return false
	enforce_weapon_restrictions()
	fire_cooldown = 0.3
	_show_weapon_notice("Armas proibidas na garagem." if not TranslationServer.get_locale().begins_with("en") else "Weapons are prohibited in the garage.")
	return true

func _handle_weapon_fire() -> void:
	var data := WEAPON_CATALOG.get_weapon(active_weapon_id)
	if data.is_empty():
		return
	var primary_pressed: bool = Input.is_action_pressed("fire")
	if _flamethrower_audio and _flamethrower_audio.playing and (not primary_pressed or active_weapon_id != "flamethrower"):
		_flamethrower_audio.stop()
	var wants_to_fire: bool = primary_pressed if (data.get("automatic", false) == true) else primary_pressed and not primary_fire_was_pressed
	if wants_to_fire and fire_cooldown <= 0.0:
		_shoot_towards(get_node("/root/GameInput").aim_target(self))
	primary_fire_was_pressed = primary_pressed

func _shoot_towards(target: Vector2) -> void:
	if _block_garage_combat(): return
	if is_reloading(): return
	var direction = global_position.direction_to(target)
	if direction.length_squared() < 0.01:
		return
	var data := get_weapon_data(active_weapon_id)
	if data.get("is_melee", false) == true:
		fire_cooldown = float(data.get("fire_interval", fire_interval))
		_perform_melee_attack(direction, data)
		return
	var ammo: Dictionary = weapon_ammo.get(active_weapon_id, {})
	if int(ammo.get("clip", 0)) <= 0:
		_reload_active_weapon()
		if int(ammo.get("clip", 0)) <= 0:
			if is_reloading(): return
			return
	ammo["clip"] = int(ammo.get("clip", 0)) - 1
	weapon_ammo[active_weapon_id] = ammo
	fire_cooldown = float(data.get("fire_interval", fire_interval))
	combat_pose.on_attack(active_weapon_id, float(data.get("recoil_multiplier",1.0)))

	# Disparo Especial: Granada de FragmentaÃƒÂ§ÃƒÂ£o FÃƒÂ­sica com Quique e FusÃƒÂ­vel
	if (data.get("is_grenade", false) == true) or active_weapon_id == "grenade":
		var throw_dist: float = clampf(global_position.distance_to(target), 60.0, float(data.get("throw_range", 320.0)))
		_release_grenade(direction, throw_dist, data, is_instance_valid(meshy_rig))
		_trigger_muzzle_flash_3d()
		_refresh_weapon_ui()
		return

	# Disparo Especial: Jato ContÃƒÂ­nuo de Fogo de Curto Alcance do LanÃƒÂ§a-Chamas
	if active_weapon_id == "flamethrower" or (data.get("is_flame", false) == true):
		var flame_scene = preload("res://guns/FlameJet.tscn")
		var flame = flame_scene.instantiate() as FlameJet
		var flame_origin := get_weapon_muzzle_position()
		var flame_world: Node2D = preload("res://guns/combat/CombatWorld.gd").scene_for(self)
		# World-space particles must enter the tree at the nozzle; moving
		# their parent after _ready leaves the first burst at the old origin.
		flame.position = flame_world.to_local(flame_origin)
		flame.direction = flame_origin.direction_to(target)
		flame.configure_range(data)
		flame_world.add_child(flame)
		flame.setup(flame_origin, flame_origin.direction_to(target), self)
		if _flamethrower_audio == null:
			_flamethrower_audio = AudioStreamPlayer2D.new()
			_flamethrower_audio.stream = ProceduralAudio.get_flamethrower_stream()
			_flamethrower_audio.volume_db = -15.0
			_flamethrower_audio.max_distance = 600.0
			add_child(_flamethrower_audio)
		if not _flamethrower_audio.playing:
			_flamethrower_audio.play()
		_trigger_muzzle_flash_3d()
		_refresh_weapon_ui()
		return

	var muzzle_position := get_weapon_muzzle_position()
	direction = muzzle_position.direction_to(target)
	var pellets := int(data.get("pellets", 1))
	var spread := float(data.get("spread", 0.0))
	var is_explosive: bool = (data.get("is_explosive", false) == true)
	var is_flame: bool = (data.get("is_flame", false) == true)
	if is_explosive: preload("res://guns/combat/RocketBackblast.gd").spawn(self,muzzle_position,direction)
	
	for pellet_index in range(pellets):
		var ratio := 0.0 if pellets == 1 else float(pellet_index) / float(pellets - 1) - 0.5
		var shot_direction := direction.rotated(ratio * spread)
		var bullet = BULLET_SCENE.instantiate()
		preload("res://guns/combat/CombatWorld.gd").scene_for(self).add_child(bullet)
		bullet.owner_body = self
		bullet.direction = shot_direction
		bullet.configure_range(data)
		bullet.set_meta("gunfire_hearing_radius", float(data.get("hearing_radius",240.0)))
		bullet.damage = int(data.get("damage", 15))
		bullet.speed = float(data.get("projectile_speed", 2000.0))
		bullet.tracer_color = data.get("tracer_color", Color.WHITE)
		bullet.is_explosive = is_explosive
		bullet.is_flame = is_flame
		bullet.global_position = muzzle_position
		bullet.rotation = shot_direction.angle()
	
	_trigger_muzzle_flash_3d()
	
	# Som de tiro realista e encorpado com punch e sub-grave
	var vol: float = float(data.get("audio_volume_db", -2.0))
	var suppressed: bool = data.get("suppressed",false)
	_play_audio(ProceduralAudio.get_gunshot_stream(active_weapon_id, suppressed), vol - (9.0 if suppressed else 0.0), 220.0 if suppressed else 600.0)
	
	var effects := preload("res://guns/combat/CombatWorld.gd").effects_for(self)
	if effects:
		# The 3D flash already sits on the barrel; do not add a ground-level flash.
		if not is_explosive and not is_flame:
			effects.spawn_shell(muzzle_position, direction, data)
	_refresh_weapon_ui()

func _release_grenade(direction: Vector2, throw_dist: float, data: Dictionary, animated: bool) -> void:
	if animated:
		await get_tree().create_timer(preload("res://scripts/player/MeshyMeleePose.gd").GRENADE_RELEASE).timeout
		# A queued animation must not create an explosive after entering the garage.
		if is_dead or weapons_forbidden() or active_weapon_id != "grenade":
			var ammo: Dictionary = weapon_ammo.get("grenade", {"clip": 0, "reserve": 0})
			ammo["clip"] = int(ammo.get("clip",0)) + 1
			weapon_ammo["grenade"] = ammo
			_refresh_weapon_ui()
			return
	var grenade := preload("res://guns/GrenadeProjectile.tscn").instantiate() as GrenadeProjectile
	preload("res://guns/combat/CombatWorld.gd").scene_for(self).add_child(grenade)
	grenade.damage = int(data.damage)
	grenade.blast_radius = float(data.blast_radius)
	grenade.max_throw_range = float(data.throw_range)
	grenade.setup(global_position + direction * 22.0, direction, throw_dist * 1.85, self)
	_play_audio(ProceduralAudio.get_grenade_throw_stream(), 0.0)

func get_weapon_muzzle_position() -> Vector2:
	if not is_instance_valid(muzzle_flash_3d) or not is_instance_valid(sprite_3d_display):
		return global_position
	var interior_presentation: Node = get_meta("interior_actor_presentation") if has_meta("interior_actor_presentation") else null
	if is_instance_valid(interior_presentation):
		return interior_presentation.project_node(muzzle_flash_3d)
	var camera := viewport_3d.get_camera_3d()
	var pixel := camera.unproject_position(muzzle_flash_3d.global_position)
	# SubViewport pixels -> centered Sprite2D -> the gameplay canvas.
	return sprite_3d_display.to_global(pixel - Vector2(viewport_3d.size) * 0.5 + sprite_3d_display.offset)

func _alert_nearby_pedestrians() -> void:
	for ped in get_tree().get_nodes_in_group("pedestrian"):
		if preload("res://guns/combat/CombatWorld.gd").shares_world(self, ped) and ped != self:
			if global_position.distance_to(ped.global_position) < 450.0:
				if ped.has_method("panic"):
					ped.panic()

func _cycle_weapon(step: int) -> void:
	if _block_garage_combat(): return
	var order := WEAPON_CATALOG.get_order()
	var current := order.find(active_weapon_id)
	for offset in range(1, order.size() + 1):
		var candidate := WEAPON_CATALOG.get_weapon_id_at(current + step * offset)
		if can_carry_weapon(candidate):
			active_weapon_id = candidate
			_update_equipped_weapon_3d_mesh()
			_refresh_weapon_ui()
			return

func _perform_melee_attack(direction: Vector2, data: Dictionary) -> void:
	if _block_garage_combat(): return
	combat_pose.on_attack(active_weapon_id)
	var is_stab := String(data.get("stance", "")) == "knife"
	var is_axe := String(data.get("stance", "")) == "axe"
	var is_bat := String(data.get("stance", "")) == "bat"
	var is_punch := String(data.get("stance", "")) in ["unarmed", "knuckles"]
	var attack_weapon := active_weapon_id
	direction = direction.normalized()
	var melee_range: float = float(data.get("melee_range", 46.0))
	var melee_damage: int = int(data.get("damage", 9))
	_play_audio(preload("res://audio/combat/KnifeAudio.gd").swing() if is_stab else ProceduralAudio.get_melee_swing_stream("bat" if is_axe else String(data.get("sound_type", "fists"))), float(data.get("audio_volume_db", -4.0)))
	_melee_swing_timer = MELEE_SWING_DURATION
	if is_axe or is_bat:
		_axe_attack_epoch += 1
		var epoch := _axe_attack_epoch
		await get_tree().create_timer(combat_pose.BAT_HIT_TIME if is_bat else combat_pose.AXE_HIT_TIME, false).timeout
		if epoch != _axe_attack_epoch or active_weapon_id != attack_weapon or not _reload_allowed(): return
	var hit_anyone := false
	var candidates := get_tree().get_nodes_in_group("damageable")
	if is_punch:
		var first_body := preload("res://guns/combat/MeleeContact.gd").first_body(self, direction, melee_range, 0.35, candidates)
		candidates.clear()
		if first_body != null: candidates.append(first_body)
	elif is_stab:
		candidates = candidates.filter(func(n): return n is Node2D)
		candidates.sort_custom(func(a, b): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	for body in candidates:
		if not preload("res://guns/combat/CombatWorld.gd").shares_world(self, body) or body == self:
			continue
		var to_body: Vector2 = body.global_position - global_position
		var dist: float = to_body.length()
		if dist > melee_range or dist <= 0.01:
			continue
		# Cone de ~80 graus na frente do jogador: um soco/facada nao acerta
		# quem esta atras, so quem esta a frente na direcao do golpe.
		if direction.dot(to_body / dist) < (0.82 if is_stab else 0.35):
			continue
		if is_stab or is_punch or is_axe or is_bat:
			if "health" in body and float(body.health) <= 0.0: continue
			var ray := PhysicsRayQueryParameters2D.create(global_position, body.global_position, 1 | 2 | 4, [get_rid()])
			var obstruction := get_world_2d().direct_space_state.intersect_ray(ray)
			if not obstruction.is_empty() and obstruction.collider != body: continue
		if body.has_method("take_damage"):
			body.set_meta("combat_attacker", self)
			var contact_damage := WeaponCatalog.distance_damage(melee_damage, dist, float(data.falloff_start), melee_range, float(data.min_damage_ratio))
			body.take_damage(contact_damage, true)
			if data.get("is_knife", false) and preload("res://audio/combat/ImpactMaterial.gd").resolve(body) == &"flesh":
				preload("res://guns/combat/BodyWound.gd").apply(body, direction)
			hit_anyone = true
			if is_axe or is_bat: _axe_impact(body.global_position, direction, body, contact_damage)
			if is_stab:
				if preload("res://audio/combat/ImpactMaterial.gd").resolve(body) == &"flesh":
					_play_audio(preload("res://audio/combat/KnifeAudio.gd").impact(combat_pose.knife_variant), -3.0)
			if is_stab or is_punch:
				break
	if (is_axe or is_bat) and not hit_anyone:
		var ray := PhysicsRayQueryParameters2D.create(global_position, global_position + direction * melee_range, 1 | 2, [get_rid()])
		var contact := get_world_2d().direct_space_state.intersect_ray(ray)
		if not contact.is_empty(): _axe_impact(contact.position, direction, contact.collider, melee_damage)
	if hit_anyone:
		if active_weapon_id == "knife":
			_show_weapon_notice("CORTE CERTEIRO")
		elif active_weapon_id == "axe":
			_show_weapon_notice("GOLPE DE MACHADO")
		elif active_weapon_id == "knuckles":
			_show_weapon_notice("GOLPE COM SOQUEIRA")
		elif active_weapon_id == "bat":
			_show_weapon_notice("IMPACTO COM TACO")
		elif data.get("is_knife", false):
			_show_weapon_notice("ACERTOU")

func _axe_impact(point: Vector2, direction: Vector2, body: Node, damage: float) -> void:
	var material := preload("res://audio/combat/ImpactMaterial.gd").resolve(body)
	var effects := preload("res://guns/combat/CombatWorld.gd").effects_for(self)
	if effects: effects.spawn_impact(point, -direction, material, damage)
	preload("res://audio/combat/CombatImpactAudio.gd").play_hit(self, point, material, damage, body.get_instance_id())

func _reload_allowed() -> bool:
	if weapons_forbidden(): return false
	return is_visible_in_tree() and not is_control_disabled and not is_in_dialogue and not is_dead and not is_arrested and not is_recovering and get_tree().get_nodes_in_group("weapon_store_open").is_empty()

func _reload_active_weapon() -> void:
	if is_reloading() or not _reload_allowed(): return
	var data := get_weapon_data(active_weapon_id)
	var ammo: Dictionary = weapon_ammo.get(active_weapon_id, {})
	if int(data.get("magazine_size", -1)) <= 0 or int(ammo.get("reserve", 0)) <= 0 or int(ammo.get("clip", 0)) >= int(data.magazine_size): return
	_reload_weapon = active_weapon_id
	_reload_duration = preload("res://guns/combat/WeaponReload.gd").duration(active_weapon_id) * float(data.get("reload_multiplier",1.0))
	_reload_elapsed = 0.0
	if not is_instance_valid(_reload_audio):
		_reload_audio = AudioStreamPlayer2D.new()
		_reload_audio.name = "ReloadAudio"
		_reload_audio.bus = &"SFX"
		_reload_audio.max_distance = 600.0
		_reload_audio.volume_db = -5.0
		add_child(_reload_audio)
	var sample := preload("res://audio/reload/ReloadAudioBank.gd").next_sample(active_weapon_id)
	_reload_audio.stream = sample
	if sample:
		_reload_audio.pitch_scale = 1.0 / float(data.get("reload_multiplier",1.0))
		_reload_audio.play()
	if is_instance_valid(_flamethrower_audio): _flamethrower_audio.stop()

func _process(delta: float) -> void:
	if not is_reloading(): return
	if not _reload_allowed() or active_weapon_id != _reload_weapon:
		_cancel_reload()
		return
	_reload_elapsed += delta
	if _reload_elapsed < _reload_duration: return
	var data := get_weapon_data(_reload_weapon)
	var ammo: Dictionary = weapon_ammo.get(_reload_weapon, {})
	var moved := mini(maxi(0, int(data.get("magazine_size", 0)) - int(ammo.get("clip", 0))), maxi(0, int(ammo.get("reserve", 0))))
	ammo["clip"] = int(ammo.get("clip", 0)) + moved
	ammo["reserve"] = int(ammo.get("reserve", 0)) - moved
	weapon_ammo[_reload_weapon] = ammo
	_cancel_reload()
	_refresh_weapon_ui()
	reload_finished.emit()

func _cancel_reload() -> void:
	_reload_weapon = ""
	_reload_elapsed = 0.0
	if is_instance_valid(_reload_audio): _reload_audio.stop()

func is_reloading() -> bool:
	return not _reload_weapon.is_empty()

func get_reload_progress() -> float:
	return clampf(_reload_elapsed / maxf(_reload_duration, 0.001), 0.0, 1.0) if is_reloading() else 0.0

func equip_weapon(id: String) -> void:
	if id != "fists" and _block_garage_combat(): return
	# Mesmo caminho usado pelas teclas numericas/roda de armas: so troca se o
	# jogador realmente possui a arma.
	if not can_carry_weapon(id):
		return
	active_weapon_id = id
	_update_equipped_weapon_3d_mesh()
	_refresh_weapon_ui()

func buy_weapon(id: String) -> String:
	if not is_weapon_shop_unlocked(id):
		return String(WEAPON_CATALOG.get_weapon(id).get("discovery_hint", "ARMA BLOQUEADA"))
	var data := WEAPON_CATALOG.get_weapon(id)
	if data.is_empty():
		return "ARMA INDISPONÃƒÂVEL"
	if weapon_inventory.get(id, false) == true:
		return "VOCÃƒÅ  JÃƒÂ POSSUI ESTA ARMA"
	var price := int(data.get("price", 0))
	if money < price:
		return "DINHEIRO INSUFICIENTE"
	money -= price
	weapon_inventory[id] = true
	weapon_ammo[id] = {"clip": int(data.get("magazine_size", 0)), "reserve": int(data.get("starting_reserve", 0))}
	if not personal_loadout_enabled or String(personal_loadout.get(PERSONAL_LOADOUT.slot_for(id),"")) == "":
		if personal_loadout_enabled: personal_loadout[PERSONAL_LOADOUT.slot_for(id)] = id
		active_weapon_id = id
	_update_equipped_weapon_3d_mesh()
	_refresh_weapon_ui()
	_show_weapon_notice("COMPROU " + String(data.get("label", id)))
	return "COMPRA REALIZADA"

func is_weapon_shop_unlocked(id: String) -> bool:
	return WEAPON_CATALOG.is_shop_unlocked(id, world_pickups_collected)

func buy_ammo(price: int) -> String:
	return buy_ammo_for_weapon(active_weapon_id, price)

func buy_ammo_for_weapon(id: String, price: int) -> String:
	var data := WEAPON_CATALOG.get_weapon(id)
	if data.is_empty():
		return "ARMA NÃƒÆ’O ENCONTRADA"
	var rounds := int(data.get("magazine_size", 0)) * 5
	return buy_ammo_amount(id, rounds, price)

func buy_ammo_amount(id: String, rounds: int, price: int) -> String:
	if money < price:
		return "DINHEIRO INSUFICIENTE"
	var data := WEAPON_CATALOG.get_weapon(id)
	if data.is_empty():
		return "ARMA NÃƒÆ’O ENCONTRADA"
	if not (weapon_inventory.get(id, false) == true):
		return "COMPRE A ARMA PRIMEIRO"
	var ammo: Dictionary = weapon_ammo.get(id, {"clip": 0, "reserve": 0})
	money -= price
	ammo["reserve"] = int(ammo.get("reserve", 0)) + rounds
	weapon_ammo[id] = ammo
	_refresh_weapon_ui()
	_show_weapon_notice("+%d BALAS (%s)" % [rounds, String(data.get("short_label", id))])
	return "MUNIÇÃO COMPRADA"

func car_loadout_ammo_quote() -> Dictionary:
	var rounds := {}
	var total := 0
	if personal_loadout_enabled:
		for id in personal_loadout.values():
			if not weapon_inventory.get(id, false) or rounds.has(id): continue
			var capacity := int(get_weapon_data(id).get("magazine_size", 0))
			if capacity <= 0: continue
			var ammo: Dictionary = weapon_ammo.get(id, {})
			var missing := maxi(0, capacity * 5 - int(ammo.get("reserve", 0)))
			if missing == 0: continue
			rounds[id] = missing
			# Match the store's pistol rate: $40 per 24 rounds, rounded up.
			total += ceili(missing * 40.0 / 24.0)
	return {"rounds": rounds, "price": total}

func buy_car_loadout_ammo() -> String:
	var quote := car_loadout_ammo_quote()
	if quote.rounds.is_empty(): return "LOADOUT COMPLETO OU SEM ARMAS DE FOGO"
	if money < int(quote.price): return "DINHEIRO INSUFICIENTE"
	# Validate the complete basket before charging or changing any ammunition.
	money -= int(quote.price)
	for id in quote.rounds:
		var ammo: Dictionary = weapon_ammo.get(id, {"clip": 0, "reserve": 0})
		ammo["reserve"] = int(ammo.get("reserve", 0)) + int(quote.rounds[id])
		weapon_ammo[id] = ammo
	_refresh_weapon_ui()
	return "LOADOUT DO CARRO RECARREGADO"

func buy_armor_amount(amount: int, price: int) -> String:
	if money < price:
		return "DINHEIRO INSUFICIENTE"
	if armor >= max_armor:
		return "COLETE JÃƒÂ ESTÃƒÂ NO MÃƒÂXIMO"
	money -= price
	armor = clampi(armor + amount, 0, max_armor)
	_refresh_weapon_ui()
	_show_weapon_notice("COLETE +%d%% (TOTAL: %d%%)" % [amount, armor])
	return "COLETE EQUIPADO"

func _refresh_weapon_ui() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set_money(money)
		hud.update_health(health)
		hud.set_weapon_info(active_weapon_id, weapon_ammo.get(active_weapon_id, {}))
		hud.set_armor(armor, max_armor)
	if weapon_wheel:
		weapon_wheel.show_state(active_weapon_id, carried_weapon_inventory(), weapon_ammo)
	_check_achievements()

func _show_weapon_notice(message: String) -> void:
	if weapon_wheel:
		weapon_wheel.show_notice(message)

func try_enter_vehicle() -> void:
	if get_meta("isolated_interior", false): return
	var urban_ride := get_tree().get_first_node_in_group("urban_player_ride")
	if urban_ride != null and urban_ride.board_nearby(self): return
	for entrance in get_tree().get_nodes_in_group("harbor_entrance"):
		if is_instance_valid(entrance) and entrance.has_method("is_actor_in_range") and entrance.is_actor_in_range(self):
			return
	for exit_door in get_tree().get_nodes_in_group("harbor_interior_exit"):
		if is_instance_valid(exit_door) and exit_door.has_method("is_actor_in_range") and exit_door.is_actor_in_range(self):
			return

	var cars = get_tree().get_nodes_in_group("vehicle")
	var closest_car = null
	var min_dist = 80.0
	for car in cars:
		if not car.has_method("enter_vehicle"):
			continue
		# Cargo remains in the vehicle group at the truck's position.
		if not car.is_visible_in_tree() or car.has_meta("tow_carried") or car.has_meta("forklift_carried"):
			continue
		if car.get("is_driven_by_player") == true or car.get("is_broken") == true or (car.get("health") != null and car.health <= 0):
			continue
		var dist = global_position.distance_to(car.global_position)
		if dist < min_dist:
			min_dist = dist
			closest_car = car
	if closest_car:
		closest_car.enter_vehicle(self)

func get_weapon_data(id: String) -> Dictionary:
	return WEAPON_CUSTOMIZATION.effective_data(id,weapon_customization)

func weapon_scope_active() -> bool:
	return WEAPON_CUSTOMIZATION.selected(weapon_customization,active_weapon_id,"scope") != "none" and Input.is_action_pressed("aim") and _reload_allowed() and not get_meta("isolated_interior",false)

func customize_weapon_part(id: String, slot: String, part: String) -> String:
	if id not in WEAPON_CUSTOMIZATION.CUSTOMIZABLE: return "ARMA INCOMPATÍVEL"
	if weapon_inventory.get(id,false) != true: return "COMPRE A ARMA PRIMEIRO"
	if not WEAPON_CUSTOMIZATION.SLOTS.has(slot): return "MODIFICAÇÃO INVÁLIDA"
	if slot == "flashlight":
		if part not in ["none","flashlight"]: return "MODIFICAÇÃO INVÁLIDA"
		return customize_weapon(id,"remove" if part == "none" else "install")
	if part != "none" and (not WEAPON_CUSTOMIZATION.supports(id,part) or WEAPON_CUSTOMIZATION.PARTS[part].slot != slot): return "ARMA INCOMPATÍVEL"
	var entry: Dictionary = weapon_customization.get(id,{}).duplicate(true)
	var owned: Array = entry.get("owned_parts",[])
	if part != "none" and part not in owned:
		var price: int = WEAPON_CUSTOMIZATION.PARTS[part].price
		if money < price: return "SALDO INSUFICIENTE"
		money -= price
		owned.append(part)
	entry["owned_parts"] = owned
	var parts: Dictionary = entry.get("parts",{})
	if part == "none": parts.erase(slot)
	else: parts[slot] = part
	entry["parts"] = parts
	weapon_customization[id] = entry
	# Removing a larger magazine returns excess cartridges to reserve.
	if slot == "magazine" and weapon_ammo.has(id):
		var capacity := int(get_weapon_data(id).get("magazine_size",0))
		var excess := maxi(0,int(weapon_ammo[id].get("clip",0))-capacity)
		weapon_ammo[id]["clip"] = int(weapon_ammo[id].get("clip",0))-excess
		weapon_ammo[id]["reserve"] = int(weapon_ammo[id].get("reserve",0))+excess
	if active_weapon_id == id:
		_cancel_reload()
		_update_equipped_weapon_3d_mesh()
	_refresh_weapon_ui()
	return "PERSONALIZAÇÃO APLICADA"

func customize_weapon(id: String, operation: String) -> String:
	if id not in WEAPON_CUSTOMIZATION.COMPATIBLE: return "ARMA INCOMPATÍVEL"
	if weapon_inventory.get(id, false) != true: return "COMPRE A ARMA PRIMEIRO"
	var kit: Dictionary = weapon_customization.get(id, {}).duplicate(true)
	if operation == "install":
		if not kit.get("owned", false):
			if money < WEAPON_CUSTOMIZATION.PRICE: return "SALDO INSUFICIENTE"
			money -= WEAPON_CUSTOMIZATION.PRICE
		kit["owned"] = true
		kit["installed"] = true
	elif operation == "remove":
		if not kit.get("owned", false): return "KIT NÃO ADQUIRIDO"
		kit["installed"] = false
	else:
		return "MODIFICAÇÃO INVÁLIDA"
	weapon_customization[id] = kit
	if active_weapon_id == id: _update_equipped_weapon_3d_mesh()
	_refresh_weapon_ui()
	return "PERSONALIZAÇÃO APLICADA"

func serialize() -> Dictionary:
	var personal := get_tree().get_first_node_in_group("personal_car_manager")
	if personal != null: personal.capture_state()
	var save_pos: Vector2 = get_meta("interior_return_position", global_position)
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if is_instance_valid(vehicle) and vehicle.get("is_driven_by_player") == true:
			save_pos = vehicle.global_position
			break
	
	return {
		"position": [save_pos.x, save_pos.y],
		"rotation": rotation,
		"health": health,
		"armor": armor,
		"money": money,
		"active_weapon_id": active_weapon_id,
		"weapon_inventory": weapon_inventory.duplicate(true),
		"weapon_customization": weapon_customization.duplicate(true),
		"personal_car_state": personal_car_state.duplicate(true),
		"personal_loadout_enabled": personal_loadout_enabled,
		"personal_loadout": personal_loadout.duplicate(true),
		"mountain_thermal_coat": mountain_thermal_coat,
		"world_pickups_collected": world_pickups_collected.duplicate(),
		"weapon_ammo": weapon_ammo.duplicate(true),
		"current_outfit_id": current_outfit_id,
		"owned_outfits": owned_outfits.duplicate(true),
		"collectibles_found": collectibles_found.duplicate(),
		"secret_car_leads": secret_car_leads,
		"races_finished": races_finished,
		"races_best_time_count": races_best_time_count,
		"best_drift_score": best_drift_score,
		"drift_challenges_completed": drift_challenges_completed,
		"chop_shop_deliveries": chop_shop_deliveries,
		"chop_shop_total_scrap": chop_shop_total_scrap,
		"unlocked_achievements": unlocked_achievements.duplicate(),
	}

func restore(data: Dictionary) -> void:
	if not (data is Dictionary) or data.is_empty():
		return
	_achievement_ready = false
	
	_release_controlled_vehicle()
	weapon_customization = WEAPON_CUSTOMIZATION.normalize(data.get("weapon_customization", {}))
	if is_instance_valid(weapon_flashlight): weapon_flashlight.switch_off()
	
	if data.has("position") and data["position"] is Array and data["position"].size() >= 2:
		global_position = Vector2(float(data["position"][0]), float(data["position"][1]))
	if data.has("rotation"):
		rotation = float(data["rotation"])
	if data.has("health"):
		health = clampi(int(data["health"]), 1, max_health)
	if data.has("armor"):
		armor = clampi(int(data["armor"]), 0, max_armor)
	world_pickups_collected = data.get("world_pickups_collected", []).duplicate()
	mountain_thermal_coat = bool(data.get("mountain_thermal_coat", false))
	if data.has("money"):
		money = maxi(0, int(data["money"]))
	if data.has("active_weapon_id"):
		active_weapon_id = String(data["active_weapon_id"])
	if data.has("weapon_inventory") and data["weapon_inventory"] is Dictionary:
		weapon_inventory = (data["weapon_inventory"] as Dictionary).duplicate(true)
	personal_car_state = data.get("personal_car_state",{}).duplicate(true)
	personal_loadout_enabled = bool(data.get("personal_loadout_enabled",false))
	personal_loadout = PERSONAL_LOADOUT.normalize(data.get("personal_loadout",{}),weapon_inventory)
	if not can_carry_weapon(active_weapon_id): active_weapon_id = "fists"
	if data.has("weapon_ammo") and data["weapon_ammo"] is Dictionary:
		weapon_ammo = (data["weapon_ammo"] as Dictionary).duplicate(true)
	if data.has("current_outfit_id"):
		current_outfit_id = String(data["current_outfit_id"])
	if data.has("owned_outfits") and data["owned_outfits"] is Dictionary:
		owned_outfits = (data["owned_outfits"] as Dictionary).duplicate(true)
	if data.has("collectibles_found") and data["collectibles_found"] is Array:
		collectibles_found.clear()
		for collectible_id in data["collectibles_found"]:
			collectibles_found.append(String(collectible_id))
	if data.has("secret_car_leads"):
		secret_car_leads = maxi(0, int(data["secret_car_leads"]))
	if data.has("races_finished"):
		races_finished = maxi(0, int(data["races_finished"]))
	if data.has("races_best_time_count"):
		races_best_time_count = maxi(0, int(data["races_best_time_count"]))
	if data.has("best_drift_score"):
		best_drift_score = maxi(0, int(data["best_drift_score"]))
	if data.has("drift_challenges_completed"):
		drift_challenges_completed = maxi(0, int(data["drift_challenges_completed"]))
	if data.has("chop_shop_deliveries"):
		chop_shop_deliveries = maxi(0, int(data["chop_shop_deliveries"]))
	if data.has("chop_shop_total_scrap"):
		chop_shop_total_scrap = maxi(0, int(data["chop_shop_total_scrap"]))
	if data.has("unlocked_achievements") and data["unlocked_achievements"] is Array:
		unlocked_achievements.clear()
		for achievement_id in data["unlocked_achievements"]:
			unlocked_achievements.append(String(achievement_id))

	velocity = Vector2.ZERO
	is_dead = false
	is_arrested = false
	is_recovering = false
	show()
	for col in find_children("", "CollisionShape2D", true, false):
		col.set_deferred("disabled", false)
	
	_rebuild_dante_costume()
	_update_equipped_weapon_3d_mesh()
	call_deferred("_refresh_weapon_ui")
	_reconcile_achievements()
	_achievement_ready = true
	var personal := get_tree().get_first_node_in_group("personal_car_manager")
	if personal != null:
		personal.restore_from_player()

func take_environment_damage(amount: int) -> void:
	if is_dead or is_arrested or _respawn_grace_active:
		return
	health = maxi(0, health - maxi(0, amount))
	_refresh_weapon_ui()
	if health <= 0:
		_wasted()
