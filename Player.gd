extends CharacterBody2D

const BULLET_SCENE: PackedScene = preload("res://Bullet.tscn")
const WEAPON_CATALOG = preload("res://WeaponCatalog.gd")
const WEAPON_WHEEL_SCRIPT = preload("res://WeaponWheel.gd")

@export var speed: float = 125.0
@export var max_health: int = 100
@export var max_armor: int = 100
@export var fire_interval: float = 0.18
@export var starting_money: int = 3000

@onready var camera = $Camera

var health: int
var armor: int = 0
var fire_cooldown: float = 0.0
signal weapon_fired
var weapon_aim_active := false
var walk_clock: float = 0.0
var _move_weight: float = 0.0
var _sprint_weight: float = 0.0
var is_recovering: bool = false
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
signal achievement_unlocked(id: String, title: String)
const ACHIEVEMENT_CATALOG := preload("res://AchievementCatalog.gd")
var active_weapon_id: String = "pistol"
var weapon_inventory: Dictionary = {"fists": true, "knife": false, "pistol": true, "smg": false, "shotgun": false}
var personal_car_state: Dictionary = {}
var personal_loadout_enabled := false
var personal_loadout: Dictionary = {}
const PERSONAL_LOADOUT := preload("res://district/harbor_preview/monaliza/PersonalLoadout.gd")

func can_carry_weapon(id: String) -> bool:
	return weapon_inventory.get(id,false) == true and (not personal_loadout_enabled or id == "fists" or id in personal_loadout.values())

func carried_weapon_inventory() -> Dictionary:
	var carried := weapon_inventory.duplicate()
	for id in carried: carried[id] = can_carry_weapon(id)
	return carried
var weapon_ammo: Dictionary = {
	"pistol": {"clip": 12, "reserve": 60},
	"smg": {"clip": 0, "reserve": 0},
	"shotgun": {"clip": 0, "reserve": 0}
}
var weapon_wheel: WeaponWheel
var primary_fire_was_pressed: bool = false
const MELEE_SWING_DURATION := 0.22
var _melee_swing_timer: float = 0.0
var combat_pose := preload("res://PlayerCombatPose.gd").new()
const DanteVisualAdapter := preload("res://scripts/player/DanteVisualAdapter.gd")
var _muzzle_flash_epoch := 0

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
	add_to_group("player")
	z_index = 10
	health = max_health
	
	for child in get_children():
		if child is ColorRect:
			child.hide()

	_build_dante_3d_viewport()
	visibility_changed.connect(_sync_3d_render_visibility)
	_sync_3d_render_visibility()
	_setup_weapons()

	var dyn_cam = load("res://DynamicCamera.gd")
	if dyn_cam and camera:
		camera.set_script(dyn_cam)
		camera.set_process(true)
	if camera:
		camera.make_current()

	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr and save_mgr.has_method("has_pending_save") and save_mgr.has_pending_save():
		call_deferred("_apply_pending_save_deferred")

func _sync_3d_render_visibility() -> void:
	# Boarding hides the 2D player but does not automatically stop its separate
	# 3D viewport. Keep this signal-driven so death/arrest tweens still render
	# after show(), even while physics processing is disabled.
	if is_instance_valid(viewport_3d):
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED

func _apply_pending_save_deferred() -> void:
	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr and save_mgr.has_method("apply_pending_save"):
		save_mgr.apply_pending_save(get_tree())

func _build_dante_3d_viewport() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.size = Vector2i(128, 128)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
	var shadow_mat = StandardMaterial3D.new()
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.albedo_color = Color(0.02, 0.02, 0.05, 0.50)
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var shadow_mesh = MeshInstance3D.new()
	var cyl_shadow = CylinderMesh.new()
	cyl_shadow.top_radius = 0.28
	cyl_shadow.bottom_radius = 0.28
	cyl_shadow.height = 0.01
	shadow_mesh.mesh = cyl_shadow
	shadow_mesh.material_override = shadow_mat
	shadow_mesh.position = Vector3(0.0, 0.01, 0.0)
	model_root.add_child(shadow_mesh)

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

func _rebuild_dante_costume() -> void:
	if not model_root:
		return
	DanteVisualAdapter.build_dante_rig(self, current_outfit_id)

func _update_equipped_weapon_3d_mesh() -> void:
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
	var input_vector: Vector2 = Vector2.ZERO if (is_control_disabled or is_in_dialogue) else Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var is_sprinting: bool = false if (is_control_disabled or is_in_dialogue) else (Input.is_action_pressed("sprint") or Input.is_key_pressed(KEY_SHIFT))
	var current_speed: float = speed * 1.50 if is_sprinting else speed

	var is_moving: bool = input_vector != Vector2.ZERO
	if is_moving:
		velocity = input_vector * current_speed
		walk_clock += delta * (8.5 if is_sprinting else 4.8) * speed / 125.0
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		walk_clock += delta * 1.8

	rotation = 0.0
	move_and_slide()
	_handle_footsteps(is_moving and get_position_delta().length_squared() > 0.01, is_sprinting)

	# --- ROTAÇÃO 3D E ANIMAÇÃO ARTICULADA DO DANTE ---
	var mouse_pos: Vector2 = get_global_mouse_position()
	var is_aiming: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	weapon_aim_active = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and active_weapon_id not in ["fists","knife","grenade"] and not is_control_disabled and not is_in_dialogue
	var aim_dir: Vector2 = (mouse_pos - global_position).normalized() if is_aiming else (input_vector.normalized() if is_moving else (mouse_pos - global_position).normalized())

	if model_root and aim_dir.length_squared() > 0.01:
		var target_angle_3d: float = -atan2(aim_dir.y, aim_dir.x) - PI * 0.5
		model_root.rotation.y = lerp_angle(model_root.rotation.y, target_angle_3d, 15.0 * delta)

	# Pesos de interpolação contínua (elimina estalos ao parar, iniciar ou alternar sprint)
	_move_weight = move_toward(_move_weight, 1.0 if is_moving else 0.0, delta * 8.0)
	_sprint_weight = move_toward(_sprint_weight, 1.0 if (is_moving and is_sprinting) else 0.0, delta * 6.0)

	# Ângulos de passada: caminhada suave vs corrida atlética de grande amplitude
	var step_angle_walk: float = sin(walk_clock) * 0.36
	var step_angle_run: float = sin(walk_clock) * 0.62
	var step_angle: float = lerpf(step_angle_walk, step_angle_run, _sprint_weight) * _move_weight

	# Articulação anatômica dos joelhos:
	# - Caminhada: flexão suave apenas na perna traseira
	var knee_walk_l: float = maxf(0.0, -step_angle_walk * 0.70)
	var knee_walk_r: float = maxf(0.0, step_angle_walk * 0.70)

	# - Corrida:
	#   1. Perna traseira (impulso): flexão profunda do joelho elevando o calcanhar (~1.15 rad / ~66°)
	#   2. Perna dianteira (avanço atlético): elevação do joelho antes da aterrissagem
	var knee_run_l: float = maxf(0.0, -step_angle_run * 1.85) + maxf(0.0, cos(walk_clock)) * 0.45 * maxf(0.0, sin(walk_clock))
	var knee_run_r: float = maxf(0.0, step_angle_run * 1.85) + maxf(0.0, -cos(walk_clock)) * 0.45 * maxf(0.0, -sin(walk_clock))

	var lower_leg_l: float = lerpf(knee_walk_l, knee_run_l, _sprint_weight) * _move_weight
	var lower_leg_r: float = lerpf(knee_walk_r, knee_run_r, _sprint_weight) * _move_weight

	if left_upper_leg and right_upper_leg:
		left_upper_leg.rotation.x = step_angle
		right_upper_leg.rotation.x = -step_angle
		if left_lower_leg and right_lower_leg:
			left_lower_leg.rotation.x = lower_leg_l
			right_lower_leg.rotation.x = lower_leg_r

	# Postura dinâmica:
	# - Inclinação atlética para a frente na corrida (Pitch): projeta o corpo no movimento
	var forward_lean: float = -(0.02 + 0.18 * _sprint_weight) * _move_weight
	# - Torção da cintura/ombros (Yaw) e inclinação lateral (Roll)
	var torso_twist_yaw: float = sin(walk_clock) * (0.08 * _sprint_weight + 0.02 * (1.0 - _sprint_weight)) * _move_weight
	var torso_twist_roll: float = cos(walk_clock) * (0.035 * _sprint_weight + 0.012 * (1.0 - _sprint_weight)) * _move_weight

	# Bobbing vertical com impacto e impulso elástico de corrida
	var bobbing: float = (absf(cos(walk_clock)) * (0.024 if _sprint_weight > 0.5 else 0.012)) if is_moving else (sin(walk_clock) * 0.005)

	# Atualização do tronco mantendo ancoragem física perfeita:
	if torso_node:
		torso_node.position.y = 0.85 + bobbing
		torso_node.position.z = 0.0
		torso_node.rotation.x = forward_lean
		torso_node.rotation.y = torso_twist_yaw
		torso_node.rotation.z = torso_twist_roll

	_sync_upper_body_anchors(forward_lean)

	# Balanço de braços amplificado e sincronizado com a cadência
	var arm_swing: float = -step_angle * (1.10 if _sprint_weight > 0.5 else 0.65)
	combat_pose.update(self, delta, is_aiming, is_sprinting, arm_swing)

	if not is_control_disabled and not is_in_dialogue:
		_handle_weapon_fire()
		if Input.is_action_just_pressed("interact"):
			if get_tree().get_nodes_in_group("weapon_store_open").is_empty():
				try_enter_vehicle()

func _sync_upper_body_anchors(forward_lean: float) -> void:
	# Use the actual torso transform, including yaw and roll. Reconstructing only
	# pitch with the opposite sine detached both the neck and shoulders in sprint.
	if not torso_node:
		return
	if head_node:
		head_node.position = torso_node.transform * Vector3(0, 0.40, 0)
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
		muzzle_flash_3d.visible = true
		muzzle_light_3d.visible = true
		var t = create_tween()
		t.tween_interval(0.065 if heavy else 0.035)
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
	if is_dead or is_arrested or _respawn_grace_active:
		return
	var absorbed := mini(armor, amount)
	armor -= absorbed
	health = maxi(0, health - (amount - absorbed))
	_refresh_weapon_ui()
	
	if mat_black_jacket:
		mat_black_jacket.albedo_color = Color(1.0, 0.2, 0.2)
		var tween = create_tween()
		tween.tween_property(mat_black_jacket, "albedo_color", Color("121214"), 0.25)
	
	_play_audio(ProceduralAudio.get_squish_stream(), -4.0)
	
	if health <= 0:
		_wasted()

func get_run_over(impact_velocity: Vector2, _is_player_driver: bool = false) -> void:
	if is_recovering:
		return
	is_recovering = true
	var damage = clampi(int(impact_velocity.length() * 0.25), 35, 100)
	_spawn_blood_burst(impact_velocity.normalized())
	_create_3d_blood_puddle()
	velocity = impact_velocity.normalized() * maxf(320.0, impact_velocity.length() * 1.0)
	take_damage(damage)
	
	if health > 0:
		await get_tree().create_timer(0.8).timeout
		is_recovering = false

func add_armor(amount: int) -> void:
	armor = clampi(armor + amount, 0, max_armor)
	_refresh_weapon_ui()
	_show_weapon_notice("COLETE %d%%" % armor)

## Achados de exploração espalhados pelo mapa (extremidades, território dos
## Cobras, docas). A cada 10 achados distintos: grana pra comprar arma em uma
## rodada, pista de carro secreto na próxima — alternando.
func add_collectible(collectible_id: String, _label: String = "") -> bool:
	if collectible_id.is_empty() or collectibles_found.has(collectible_id):
		return false
	collectibles_found.append(collectible_id)
	var total := collectibles_found.size()
	var hud := get_tree().get_first_node_in_group("hud")
	var milestone := ""
	if total % 10 == 0:
		var milestone_index := total / 10
		if milestone_index % 2 == 1:
			var bonus := 250
			money += bonus
			milestone = "cash"
			if hud and hud.has_method("show_notice"):
				hud.show_notice("%d ACHADOS! +$%d PRA COMPRAR ARMA" % [total, bonus], Color("#2ed573"))
		else:
			secret_car_leads += 1
			milestone = "lead"
			if hud and hud.has_method("show_notice"):
				hud.show_notice("%d ACHADOS! NOVA PISTA DE CARRO SECRETO (%d)" % [total, secret_car_leads], Color("#a29bfe"))
	elif hud and hud.has_method("show_notice"):
		hud.show_notice("ACHADO %d/10" % (total - ((total / 10) * 10)), Color("#74b9ff"))
	_refresh_weapon_ui()
	collectible_progress_changed.emit(total, milestone)
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
	var weapon_count := 0
	for owned in weapon_inventory.values():
		if owned == true:
			weapon_count += 1
	var wanted := get_node_or_null("/root/WantedManager")
	var wanted_stars := int(wanted.current_stars) if wanted else 0
	return {
		"collectibles": collectibles_found.size(),
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
	var stats := _achievement_stats()
	for achievement_id in ACHIEVEMENT_CATALOG.ACHIEVEMENTS.keys():
		if unlocked_achievements.has(achievement_id):
			continue
		if ACHIEVEMENT_CATALOG.evaluate(stats, achievement_id):
			_unlock_achievement(achievement_id)

func _unlock_achievement(achievement_id: String) -> void:
	unlocked_achievements.append(achievement_id)
	var entry: Dictionary = ACHIEVEMENT_CATALOG.ACHIEVEMENTS.get(achievement_id, {})
	var title := String(entry.get("name", achievement_id))
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_achievement"):
		hud.show_achievement(title, String(entry.get("desc", "")))
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
	blood_particles.amount = 30
	blood_particles.lifetime = 0.7
	blood_particles.spread = 45.0
	blood_particles.direction = dir
	blood_particles.initial_velocity_min = 80.0
	blood_particles.initial_velocity_max = 220.0
	blood_particles.gravity = Vector2(0, 180)
	blood_particles.scale_amount_min = 2.0
	blood_particles.scale_amount_max = 5.0
	blood_particles.color = Color(0.75, 0.05, 0.05, 0.95)
	blood_particles.texture = _make_soft_particle_texture()
	add_child(blood_particles)
	_play_audio(ProceduralAudio.get_scream_stream(), -4.0)

func _create_3d_blood_puddle() -> void:
	var puddle_root := Node2D.new()
	puddle_root.name = "3DBloodPuddle"
	puddle_root.global_position = global_position
	puddle_root.z_as_relative = false
	puddle_root.z_index = 3
	
	var base_poly := Polygon2D.new()
	base_poly.polygon = PackedVector2Array([
		Vector2(-14, -4), Vector2(-9, -11), Vector2(0, -13),
		Vector2(10, -9), Vector2(15, -1), Vector2(13, 8),
		Vector2(5, 12), Vector2(-6, 11), Vector2(-13, 5)
	])
	base_poly.color = Color(0.24, 0.01, 0.015, 0.92)
	puddle_root.add_child(base_poly)
	
	var core_poly := Polygon2D.new()
	core_poly.polygon = PackedVector2Array([
		Vector2(-11, -3), Vector2(-7, -8), Vector2(0, -10),
		Vector2(8, -7), Vector2(12, -1), Vector2(10, 6),
		Vector2(4, 9), Vector2(-5, 8), Vector2(-10, 4)
	])
	core_poly.color = Color(0.68, 0.04, 0.04, 0.95)
	puddle_root.add_child(core_poly)
	
	var gloss_poly := Polygon2D.new()
	gloss_poly.polygon = PackedVector2Array([
		Vector2(-5, -6), Vector2(-1, -8), Vector2(4, -5),
		Vector2(1, -4), Vector2(-4, -4)
	])
	gloss_poly.color = Color(1.0, 0.65, 0.65, 0.45)
	puddle_root.add_child(gloss_poly)
	
	var drops := [Vector2(16, -9), Vector2(-15, 8), Vector2(8, 14), Vector2(-12, -11)]
	for drop_pos in drops:
		var drop := Polygon2D.new()
		drop.polygon = PackedVector2Array([
			Vector2(-1.2, -1.2), Vector2(1.2, -1.2), Vector2(1.2, 1.2), Vector2(-1.2, 1.2)
		])
		drop.position = drop_pos
		drop.color = Color(0.45, 0.02, 0.02, 0.85)
		puddle_root.add_child(drop)
		
	if get_parent():
		get_parent().add_child(puddle_root)
	else:
		get_tree().current_scene.add_child(puddle_root)
		
	puddle_root.global_position = global_position
	puddle_root.scale = Vector2(0.1, 0.1)
	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(puddle_root, "scale", Vector2(0.7, 0.7), 0.55)
	
	var fade_tween = puddle_root.create_tween()
	fade_tween.tween_interval(7.0)
	fade_tween.tween_property(puddle_root, "modulate:a", 0.0, 2.5)
	fade_tween.tween_callback(puddle_root.queue_free)

func _wasted() -> void:
	if is_dead or is_arrested:
		return
	is_dead = true
	_release_controlled_vehicle()
	
	show()
	is_recovering = true
	_create_3d_blood_puddle()
	set_physics_process(false)
	_play_audio(ProceduralAudio.get_wasted_stream(), 0.0)
	
	# Animacao de queda: antes o personagem ficava perfeitamente em pe mesmo
	# morto (model_root.rotation nunca era tocado aqui). Agora ele desaba
	# suavemente, mesmo angulo de "corpo caido" ja usado pelos NPCs em
	# AnimatedPedestrian3D._die(), so que animado em vez de instantaneo.
	if model_root:
		var fall_tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fall_tween.tween_property(model_root, "rotation:x", PI * 0.42, 0.45)
		fall_tween.parallel().tween_property(model_root, "rotation:z", randf_range(-0.35, 0.35), 0.45)
	
	var wm = get_node_or_null("/root/WantedManager")
	if wm:
		wm.dismiss_all_police()
	
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
	await get_tree().create_timer(1.5).timeout
	is_dead = false
	is_recovering = false
	if model_root:
		model_root.rotation = Vector3.ZERO


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
		wm.dismiss_all_police()

	await get_tree().create_timer(2.2).timeout
	if is_instance_valid(flash):
		flash.queue_free()
	_respawn_at_hospital()
	await get_tree().create_timer(1.5).timeout
	is_arrested = false
	is_recovering = false


func _release_controlled_vehicle() -> void:
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if not is_instance_valid(vehicle) or vehicle.get("is_driven_by_player") != true:
			continue
		if vehicle.has_method("exit_vehicle"):
			vehicle.exit_vehicle()
		else:
			vehicle.set("is_driven_by_player", false)


func _respawn_at_hospital() -> void:
	health = max_health
	velocity = Vector2.ZERO
	var hospital := _get_arrest_spawn() if is_arrested else _get_nearest_hospital_spawn()
	if hospital:
		global_position = hospital.global_position
	else:
		global_position = Vector2(1125, 375)
	for col in find_children("", "CollisionShape2D", true, false):
		col.set_deferred("disabled", false)
	show()
	set_physics_process(true)
	if camera:
		camera.remove_meta("compact_interior")
		camera.make_current()
		camera.reset_smoothing()
	_refresh_weapon_ui()

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

func _play_audio(stream: AudioStream, volume_db: float = -6.0) -> void:
	var player = AudioStreamPlayer2D.new()
	player.bus = &"SFX"
	player.stream = stream
	player.volume_db = volume_db
	player.max_distance = 600.0
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

func _setup_weapons() -> void:
	if money == 0:
		money = starting_money
	weapon_inventory = {
		"fists": true,
		"knife": false,
		"pistol": true,
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
		"pistol": {"clip": 12, "reserve": 60},
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
	if not visible or is_control_disabled or is_in_dialogue or get_tree().get_nodes_in_group("weapon_store_open").size() > 0:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_weapon(1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_weapon(-1)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key_map := {
			KEY_1: "pistol",
			KEY_2: "magnum",
			KEY_3: "smg",
			KEY_4: "shotgun",
			KEY_5: "sawed_off",
			KEY_6: "ak47",
			KEY_7: "m4a1",
			KEY_8: "rpg",
			KEY_9: "flamethrower",
			KEY_0: "grenade"
		}
		if key_map.has(event.keycode):
			var target_weapon: String = key_map[event.keycode]
			if can_carry_weapon(target_weapon):
				active_weapon_id = target_weapon
				_update_equipped_weapon_3d_mesh()
				_show_weapon_notice(String(WEAPON_CATALOG.get_weapon(target_weapon).get("label", target_weapon)))
				_refresh_weapon_ui()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_X:
			# Maos livres na hora, sem precisar dar a volta na roda de armas.
			if weapon_inventory.get("fists", false) == true:
				active_weapon_id = "fists"
				_update_equipped_weapon_3d_mesh()
				_show_weapon_notice("PUNHOS")
				_refresh_weapon_ui()
				get_viewport().set_input_as_handled()

func _handle_weapon_fire() -> void:
	var data := WEAPON_CATALOG.get_weapon(active_weapon_id)
	if data.is_empty():
		return
	var primary_pressed: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _flamethrower_audio and _flamethrower_audio.playing and (not primary_pressed or active_weapon_id != "flamethrower"):
		_flamethrower_audio.stop()
	var wants_to_fire: bool = primary_pressed if (data.get("automatic", false) == true) else primary_pressed and not primary_fire_was_pressed
	if wants_to_fire and fire_cooldown <= 0.0:
		_shoot_towards(get_global_mouse_position())
	primary_fire_was_pressed = primary_pressed

func _shoot_towards(target: Vector2) -> void:
	var direction = global_position.direction_to(target)
	if direction.length_squared() < 0.01:
		return
	var data := WEAPON_CATALOG.get_weapon(active_weapon_id)
	if data.get("is_melee", false) == true:
		fire_cooldown = float(data.get("fire_interval", fire_interval))
		_perform_melee_attack(direction, data)
		return
	var ammo: Dictionary = weapon_ammo.get(active_weapon_id, {})
	if int(ammo.get("clip", 0)) <= 0:
		_reload_active_weapon()
		if int(ammo.get("clip", 0)) <= 0:
			_show_weapon_notice("SEM MUNIÃƒâ€¡ÃƒÆ’O")
			return
	ammo["clip"] = int(ammo.get("clip", 0)) - 1
	weapon_ammo[active_weapon_id] = ammo
	fire_cooldown = float(data.get("fire_interval", fire_interval))
	combat_pose.on_attack(active_weapon_id)

	# Disparo Especial: Granada de FragmentaÃƒÂ§ÃƒÂ£o FÃƒÂ­sica com Quique e FusÃƒÂ­vel
	if (data.get("is_grenade", false) == true) or active_weapon_id == "grenade":
		var grenade_scene = preload("res://GrenadeProjectile.tscn")
		var grenade = grenade_scene.instantiate() as GrenadeProjectile
		get_tree().current_scene.add_child(grenade)
		var throw_dist: float = clampf(global_position.distance_to(target), 120.0, 520.0)
		var throw_speed: float = throw_dist * 1.85
		grenade.setup(global_position + direction * 22.0, direction, throw_speed, self)
		_play_audio(ProceduralAudio.get_grenade_throw_stream(), 0.0)
		_trigger_muzzle_flash_3d()
		_refresh_weapon_ui()
		return

	# Disparo Especial: Jato ContÃƒÂ­nuo de Fogo de Curto Alcance do LanÃƒÂ§a-Chamas
	if active_weapon_id == "flamethrower" or (data.get("is_flame", false) == true):
		var flame_scene = preload("res://FlameJet.tscn")
		var flame = flame_scene.instantiate() as FlameJet
		get_tree().current_scene.add_child(flame)
		flame.setup(global_position + direction * 28.0, direction, self)
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

	var pellets := int(data.get("pellets", 1))
	var spread := float(data.get("spread", 0.0))
	var is_explosive: bool = (data.get("is_explosive", false) == true)
	var is_flame: bool = (data.get("is_flame", false) == true)
	
	for pellet_index in range(pellets):
		var ratio := 0.0 if pellets == 1 else float(pellet_index) / float(pellets - 1) - 0.5
		var shot_direction := direction.rotated(ratio * spread)
		var bullet = BULLET_SCENE.instantiate()
		get_tree().current_scene.add_child(bullet)
		bullet.owner_body = self
		bullet.direction = shot_direction
		bullet.damage = int(data.get("damage", 15))
		bullet.speed = float(data.get("projectile_speed", 2000.0))
		bullet.tracer_color = data.get("tracer_color", Color.WHITE)
		bullet.is_explosive = is_explosive
		bullet.is_flame = is_flame
		bullet.global_position = global_position + shot_direction * 26.0
	
	_trigger_muzzle_flash_3d()
	
	# Som de tiro realista e encorpado com punch e sub-grave
	var vol: float = float(data.get("audio_volume_db", -2.0))
	_play_audio(ProceduralAudio.get_gunshot_stream(active_weapon_id), vol)
	
	var effects := get_tree().get_first_node_in_group("weapon_effects")
	if effects:
		effects.spawn_muzzle_flash(global_position + direction * 24.0, direction, data)
		if not is_explosive and not is_flame:
			effects.spawn_shell(global_position + direction * 20.0, direction, data)
	_alert_nearby_pedestrians()
	_refresh_weapon_ui()

func _alert_nearby_pedestrians() -> void:
	for ped in get_tree().get_nodes_in_group("pedestrian"):
		if is_instance_valid(ped) and ped != self:
			if global_position.distance_to(ped.global_position) < 450.0:
				if ped.has_method("panic"):
					ped.panic()

func _cycle_weapon(step: int) -> void:
	var order := WEAPON_CATALOG.get_order()
	var current := order.find(active_weapon_id)
	for offset in range(1, order.size() + 1):
		var candidate := WEAPON_CATALOG.get_weapon_id_at(current + step * offset)
		if can_carry_weapon(candidate):
			active_weapon_id = candidate
			_update_equipped_weapon_3d_mesh()
			_show_weapon_notice(String(WEAPON_CATALOG.get_weapon(candidate).get("label", candidate)))
			_refresh_weapon_ui()
			return

func _perform_melee_attack(direction: Vector2, data: Dictionary) -> void:
	combat_pose.on_attack(active_weapon_id)
	# Corpo a corpo nao usa Bullet.tscn: e' um cone curto na frente do jogador,
	# igual ao raio de dano em area que Bullet.gd ja usa pra explosao (grupo
	# "damageable", que pedestres, policiais e veiculos ja compartilham) --
	# so que sem projetil nenhum, resolvido no mesmo frame do golpe.
	var melee_range: float = float(data.get("melee_range", 46.0))
	var melee_damage: int = int(data.get("damage", 9))
	_play_audio(ProceduralAudio.get_melee_swing_stream(String(data.get("sound_type", "fists"))), float(data.get("audio_volume_db", -4.0)))
	_melee_swing_timer = MELEE_SWING_DURATION
	var hit_anyone := false
	for body in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(body) or body == self:
			continue
		var to_body: Vector2 = body.global_position - global_position
		var dist: float = to_body.length()
		if dist > melee_range or dist <= 0.01:
			continue
		# Cone de ~80 graus na frente do jogador: um soco/facada nao acerta
		# quem esta atras, so quem esta a frente na direcao do golpe.
		if direction.dot(to_body / dist) < 0.35:
			continue
		if body.has_method("take_damage"):
			body.take_damage(melee_damage, true)
			hit_anyone = true
	if hit_anyone and data.get("is_knife", false) == true:
		_show_weapon_notice("ACERTOU")

func _reload_active_weapon() -> void:
	var data := WEAPON_CATALOG.get_weapon(active_weapon_id)
	var ammo: Dictionary = weapon_ammo.get(active_weapon_id, {})
	var needed := int(data.get("magazine_size", 0)) - int(ammo.get("clip", 0))
	var moved := mini(needed, int(ammo.get("reserve", 0)))
	if moved > 0:
		ammo["clip"] = int(ammo.get("clip", 0)) + moved
		ammo["reserve"] = int(ammo.get("reserve", 0)) - moved
		weapon_ammo[active_weapon_id] = ammo
		_show_weapon_notice("RECARREGOU")

func equip_weapon(id: String) -> void:
	# Mesmo caminho usado pelas teclas numericas/roda de armas: so troca se o
	# jogador realmente possui a arma.
	if not can_carry_weapon(id):
		return
	active_weapon_id = id
	_update_equipped_weapon_3d_mesh()
	_show_weapon_notice(String(WEAPON_CATALOG.get_weapon(id).get("label", id)))
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
			var capacity := int(WEAPON_CATALOG.get_weapon(id).get("magazine_size", 0))
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
		var dist = global_position.distance_to(car.global_position)
		if dist < min_dist:
			min_dist = dist
			closest_car = car
	if closest_car:
		closest_car.enter_vehicle(self)

func serialize() -> Dictionary:
	var personal := get_tree().get_first_node_in_group("personal_car_manager")
	if personal != null: personal.capture_state()
	var save_pos := global_position
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
	
	_release_controlled_vehicle()
	
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
