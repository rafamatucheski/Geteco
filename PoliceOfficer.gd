extends CharacterBody2D

const BULLET_SCENE: PackedScene = preload("res://guns/Bullet.tscn")
const POLICE_LOOT_SCRIPT = preload("res://world/shared/pickups/PoliceLoot.gd")

enum UnitTier {
	PATROL,       # 1-2 Estrelas: Polícia Regular (Pistola 9mm)
	DETECTIVE,    # 3 Estrelas: Investigador / Terno (Magnum .44)
	SWAT,         # 4 Estrelas: Tropa de Choque Tática SWAT (MP5 SMG / Escopeta)
	FBI,          # 5 Estrelas: Agente Federal FBI (Carabina M4A1)
	ARMY          # 6 Estrelas: Exército Militar (Fuzil M4A1 / RPG)
}

@export var tier: UnitTier = UnitTier.PATROL
@export var speed: float = 120.0
@export_range(-1, 9) var appearance_model: int = -1
@export var max_health: int = 50
@export var dropped_weapon: StringName = &"pistol"

var target: Node2D = null
var local_security := false
var security_alert := 0
var health: int = 50
var is_dead: bool = false
var fall_presentation := preload("res://CharacterFallPresentation.gd").new()
var is_flying: bool = false
var fly_velocity: Vector2 = Vector2.ZERO
var fire_cooldown: float = 0.0
var arrest_timer: float = 0.0
var arrest_warning_elapsed := 0.0
var arrest_warning_given := false
var response_aggression := 0.0
var visible_aim_time := 0.0
var fleeing_after_warning := 0.0
var burst_shots := 0
var burst_pause := 0.0
var weapon_reload := preload("res://guns/combat/WeaponReload.gd").new()
var walk_clock: float = 0.0
var service_vehicle: Node2D = null
var crew_side := 1.0
var crew_longitudinal := -8.0
var service_disembark_active := false
var returning_to_service_vehicle := false
var boarding_service_vehicle := false
var vehicle_stop := preload("res://PoliceVehicleStop.gd").new()
var crew_partner: CharacterBody2D
var car_cover_elapsed := 0.0
var car_cover_released := false
var walk_weight := 0.0

func _exit_tree() -> void:
	if is_instance_valid(crew_partner): crew_partner.remove_collision_exception_with(self)
	vehicle_stop.cancel()

var collision_shape: CollisionShape2D
var police_loot: PoliceLoot

# 3D SubViewport Rig
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
var muzzle_flash_3d: MeshInstance3D
var mat_uniform: StandardMaterial3D
var _uniform_base_color: Color
var _uniform_hit_tween: Tween

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	platform_floor_layers = 0
	platform_wall_layers = 0
	add_to_group("police_officer")
	if is_instance_valid(service_vehicle):
		add_collision_exception_with(service_vehicle)
	add_to_group("damageable")
	
	_configure_tier()
	preload("res://world/shared/emergency/PoliceAppearance.gd").prepare(self)
	
	health = max_health
	z_index = 6
	# A prepared, never-activated reserve keeps its rig and equipment. Re-entry
	# still binds the real service vehicle and restores the normal ready state.
	if is_instance_valid(model_root):
		if not get_meta("quiet_patrol", false) and not get_meta("crew_preparing", false):
			_play_audio(ProceduralAudio.get_scream_stream(), -4.0)
		return
	
	_build_3d_viewport()
	preload("res://world/shared/pedestrians/ServiceUniformDetails.gd").apply(self,"police")
	preload("res://world/shared/emergency/PoliceAppearance.gd").apply(self)
	preload("res://world/shared/pedestrians/NPCCombatRig.gd").attach(self, String(dropped_weapon))
	
	var col := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 5.0
	cap.height = 16.0
	col.shape = cap
	collision_shape = col
	add_child(col)

	police_loot = POLICE_LOOT_SCRIPT.new()
	police_loot.name = "PoliceLoot"
	police_loot.dropped_weapon = dropped_weapon
	police_loot.weapon_drop_chance = 0.45 if tier >= UnitTier.SWAT else 0.35
	police_loot.armor_drop_chance = 0.35 if tier >= UnitTier.SWAT else 0.12
	add_child(police_loot)
	
	if not get_meta("quiet_patrol",false) and not get_meta("crew_preparing", false):
		_play_audio(ProceduralAudio.get_scream_stream(), -4.0)

func _configure_tier() -> void:
	var wm = get_node_or_null("/root/WantedManager")
	var stars: int = int(get_meta("response_tier_level", wm.current_stars if wm else 1))
	
	if stars >= 6:
		tier = UnitTier.ARMY
	elif stars == 5:
		tier = UnitTier.FBI
	elif stars == 4:
		tier = UnitTier.SWAT
	elif stars == 3:
		tier = UnitTier.DETECTIVE
	else:
		tier = UnitTier.PATROL

	match tier:
		UnitTier.ARMY:
			max_health = 130
			speed = 132.0
			dropped_weapon = &"m4a1"
		UnitTier.FBI:
			max_health = 110
			speed = 128.0
			dropped_weapon = &"m4a1"
		UnitTier.SWAT:
			max_health = 95
			speed = 124.0
			dropped_weapon = &"m4a1"
		UnitTier.DETECTIVE:
			max_health = 75
			speed = 118.0
			dropped_weapon = &"smg"
		_:
			max_health = 50
			speed = 112.0
			dropped_weapon = &"pistol"

func _build_3d_viewport() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.size = Vector2i(96, 96)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport_3d)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 3.2, 1.4)
	cam.fov = 30.0
	viewport_3d.add_child(cam)
	cam.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60.0, 35.0, 0.0)
	light.light_energy = 1.35
	viewport_3d.add_child(light)

	var env := WorldEnvironment.new()
	var env_res := Environment.new()
	env_res.background_mode = Environment.BG_COLOR
	env_res.background_color = Color(0, 0, 0, 0)
	env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_res.ambient_light_color = Color(0.70, 0.72, 0.82)
	env.environment = env_res
	viewport_3d.add_child(env)

	model_root = Node3D.new()
	viewport_3d.add_child(model_root)

	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.albedo_color = Color(0.02, 0.02, 0.05, 0.50)
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var shadow_mesh := MeshInstance3D.new()
	var cyl_shadow := CylinderMesh.new()
	cyl_shadow.top_radius = 0.28
	cyl_shadow.bottom_radius = 0.28
	cyl_shadow.height = 0.01
	shadow_mesh.mesh = cyl_shadow
	shadow_mesh.material_override = shadow_mat
	shadow_mesh.position = Vector3(0.0, 0.01, 0.0)
	shadow_mesh.name = "GroundShadow"
	shadow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport_3d.add_child(shadow_mesh)
	preload("res://systems/ContactShadow.gd").soften(shadow_mesh)

	# Cores e Fardas de Acordo com o Escalão Tático (Tier)
	var uniform_col := Color(0.11, 0.15, 0.24) # Azul Polícia Regular
	if tier == UnitTier.ARMY:
		uniform_col = Color(0.24, 0.32, 0.20) # Camuflado Militar Verde-Oliva
	elif tier == UnitTier.FBI:
		uniform_col = Color(0.08, 0.08, 0.10) # Terno Preto FBI
	elif tier == UnitTier.SWAT:
		uniform_col = Color(0.12, 0.13, 0.16) # Preto Tático SWAT
	elif tier == UnitTier.DETECTIVE:
		uniform_col = Color(0.35, 0.26, 0.18) # Sobretudo Castanho / Couro
		
	mat_uniform = _make_mat(uniform_col, 0.82)
	_uniform_base_color = uniform_col
	var mat_skin := _make_mat(Color(get_meta("police_appearance").skin), 0.65)
	var mat_gold := _make_mat(Color(0.92, 0.78, 0.20), 0.3)
	var mat_black := _make_mat(Color(0.08, 0.08, 0.10), 0.4)
	var mat_gun := _make_mat(Color(0.20, 0.22, 0.25), 0.2)
	var mat_vest := _make_mat(Color(0.05, 0.05, 0.07), 0.3)
	var mat_fbi_yellow := _make_mat(Color(0.95, 0.85, 0.15), 0.3)

	# Torso 3D
	torso_node = Node3D.new()
	torso_node.position = Vector3(0.0, 0.85, 0.0)
	model_root.add_child(torso_node)

	var torso_mesh := preload("res://world/shared/emergency/PoliceAppearance.gd").uniform_body(mat_uniform, get_meta("police_appearance").get("woman", false))
	torso_node.add_child(torso_mesh)

	# Colete Tático Blindado Kevlar (SWAT, FBI e Exército)
	if tier >= UnitTier.SWAT:
		var vest := MeshInstance3D.new()
		var box_v := BoxMesh.new()
		box_v.size = Vector3(0.38, 0.34, 0.36)
		vest.mesh = box_v
		vest.material_override = mat_vest
		vest.position = Vector3(0.0, 0.05, 0.0)
		torso_node.add_child(vest)
		
		if tier == UnitTier.FBI:
			var fbi_logo := MeshInstance3D.new()
			var box_fl := BoxMesh.new()
			box_fl.size = Vector3(0.18, 0.08, 0.02)
			fbi_logo.mesh = box_fl
			fbi_logo.material_override = mat_fbi_yellow
			fbi_logo.position = Vector3(0.0, 0.08, -0.19)
			torso_node.add_child(fbi_logo)
	else:
		# Distintivo Dourado de Polícia Regular
		var badge := MeshInstance3D.new()
		var box_bg := BoxMesh.new()
		box_bg.size = Vector3(0.06, 0.07, 0.02)
		badge.mesh = box_bg
		badge.material_override = mat_gold
		badge.position = Vector3(-0.07, 0.12, -0.165)
		torso_node.add_child(badge)

	# Cinto Tático de Serviço
	var belt := MeshInstance3D.new()
	var box_bl := BoxMesh.new()
	box_bl.size = Vector3(0.36, 0.05, 0.34)
	belt.mesh = box_bl
	belt.material_override = mat_black
	belt.position = Vector3(0.0, -0.18, 0.0)
	torso_node.add_child(belt)

	# Cabeça 3D (Capacete Tático, Quepe ou Óculos Escuros)
	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.21, 0.0)
	# Scale the complete head so the cap, helmet and facial details stay fitted.
	head_node.scale = Vector3(0.62, 0.70, 0.62)
	model_root.add_child(head_node)
	torso_node.add_child(_create_limb(0.05, 0.14, mat_skin, Vector3(0.0, 0.24, 0.0)))

	var head_mesh := MeshInstance3D.new()
	var sph_h := SphereMesh.new()
	sph_h.radius = 0.17
	sph_h.height = 0.34
	head_mesh.mesh = sph_h
	head_mesh.material_override = mat_skin
	head_node.add_child(head_mesh)

	if tier == UnitTier.SWAT or tier == UnitTier.ARMY:
		# Capacete Tático Balístico Militar / SWAT
		var helmet := MeshInstance3D.new()
		var sph_hl := SphereMesh.new()
		sph_hl.radius = 0.195
		sph_hl.height = 0.32
		helmet.mesh = sph_hl
		helmet.material_override = mat_vest if tier == UnitTier.SWAT else _make_mat(Color(0.20, 0.28, 0.18), 0.4)
		helmet.position = Vector3(0.0, 0.08, 0.0)
		helmet.name = "CoveredCrown"
		head_node.add_child(helmet)
		
		if tier == UnitTier.SWAT:
			var visor_g := MeshInstance3D.new()
			var box_vg := BoxMesh.new()
			box_vg.size = Vector3(0.24, 0.08, 0.08)
			visor_g.mesh = box_vg
			visor_g.material_override = _make_mat(Color(0.1, 0.4, 0.8), 0.1)
			visor_g.position = Vector3(0.0, 0.04, -0.16)
			head_node.add_child(visor_g)
	else:
		# Quepe Policial Clássico com Aba
		var cap_hat := MeshInstance3D.new()
		var box_cp := CylinderMesh.new()
		box_cp.top_radius = 0.185
		box_cp.bottom_radius = 0.17
		box_cp.height = 0.11
		box_cp.radial_segments = 12
		cap_hat.mesh = box_cp
		cap_hat.material_override = mat_uniform
		cap_hat.position = Vector3(0.0, 0.15, 0.0)
		cap_hat.name = "CoveredCrown"
		head_node.add_child(cap_hat)

		var visor := MeshInstance3D.new()
		var box_vs := BoxMesh.new()
		box_vs.size = Vector3(0.24, 0.02, 0.12)
		visor.mesh = box_vs
		visor.material_override = mat_black
		visor.position = Vector3(0.0, 0.08, -0.18)
		head_node.add_child(visor)

	# Braços 3D
	left_upper_arm = Node3D.new()
	left_upper_arm.position = Vector3(-0.185, 1.05, 0.0)
	model_root.add_child(left_upper_arm)
	left_upper_arm.add_child(_create_limb(0.050, 0.22, mat_uniform, Vector3(0, -0.11, 0)))

	left_lower_arm = Node3D.new()
	left_lower_arm.position = Vector3(0, -0.22, 0)
	left_upper_arm.add_child(left_lower_arm)
	left_lower_arm.add_child(_create_limb(0.042, 0.18, mat_skin if tier < UnitTier.SWAT else mat_black, Vector3(0, -0.09, 0)))

	right_upper_arm = Node3D.new()
	right_upper_arm.position = Vector3(0.185, 1.05, 0.0)
	model_root.add_child(right_upper_arm)
	right_upper_arm.add_child(_create_limb(0.050, 0.22, mat_uniform, Vector3(0, -0.11, 0)))

	right_lower_arm = Node3D.new()
	right_lower_arm.position = Vector3(0, -0.22, 0)
	right_upper_arm.add_child(right_lower_arm)
	right_lower_arm.add_child(_create_limb(0.042, 0.18, mat_skin if tier < UnitTier.SWAT else mat_black, Vector3(0, -0.09, 0)))

	# Weapon geometry is supplied by NPCCombatRig after the articulated rig.
	muzzle_flash_3d = MeshInstance3D.new()
	var sph_f := SphereMesh.new()
	sph_f.radius = 0.07
	sph_f.height = 0.14
	muzzle_flash_3d.mesh = sph_f
	var mat_fl := StandardMaterial3D.new()
	mat_fl.albedo_color = Color(1.0, 0.85, 0.2)
	mat_fl.emission_enabled = true
	mat_fl.emission = Color(1.0, 0.6, 0.1)
	mat_fl.emission_energy_multiplier = 4.0
	mat_fl.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle_flash_3d.material_override = mat_fl
	muzzle_flash_3d.position = Vector3(0.0, -0.18, -0.22 if tier < UnitTier.SWAT else -0.32)
	muzzle_flash_3d.visible = false
	right_lower_arm.add_child(muzzle_flash_3d)

	# Pernas 3D
	left_upper_leg = Node3D.new()
	left_upper_leg.position = Vector3(-0.11, 0.65, 0.0)
	model_root.add_child(left_upper_leg)
	left_upper_leg.add_child(_create_limb(0.068, 0.30, mat_uniform, Vector3(0, -0.15, 0)))

	left_lower_leg = Node3D.new()
	left_lower_leg.position = Vector3(0, -0.30, 0)
	left_upper_leg.add_child(left_lower_leg)
	left_lower_leg.add_child(_create_limb(0.058, 0.30, mat_uniform, Vector3(0, -0.15, 0)))
	left_lower_leg.add_child(_create_shoe(mat_black, Vector3(0, -0.3075, -0.035)))

	right_upper_leg = Node3D.new()
	right_upper_leg.position = Vector3(0.11, 0.65, 0.0)
	model_root.add_child(right_upper_leg)
	right_upper_leg.add_child(_create_limb(0.068, 0.30, mat_uniform, Vector3(0, -0.15, 0)))

	right_lower_leg = Node3D.new()
	right_lower_leg.position = Vector3(0, -0.30, 0)
	right_upper_leg.add_child(right_lower_leg)
	right_lower_leg.add_child(_create_limb(0.058, 0.30, mat_uniform, Vector3(0, -0.15, 0)))
	right_lower_leg.add_child(_create_shoe(mat_black, Vector3(0, -0.3075, -0.035)))

	# Exibição 2D
	sprite_3d_display = Sprite2D.new()
	sprite_3d_display.texture = viewport_3d.get_texture()
	# Match Dante's 128px viewport at 0.24 scale with this 96px viewport.
	sprite_3d_display.scale = Vector2(0.32, 0.32)
	add_child(sprite_3d_display)

func _make_mat(col: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = roughness
	return mat

func _create_limb(radius: float, height: float, mat: Material, offset: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius * 0.85
	cyl.height = height
	m.mesh = cyl
	m.material_override = mat
	m.position = offset
	return m

func _create_shoe(mat: Material, offset: Vector3) -> MeshInstance3D:
	var shoe := MeshInstance3D.new()
	shoe.name = "ServiceShoe"
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.085
	mesh.radial_segments = 12
	mesh.rings = 6
	shoe.mesh = mesh
	shoe.scale.z = 1.75
	shoe.material_override = mat
	shoe.position = offset
	return shoe

func get_run_over(impact_velocity: Vector2, _is_player_driver: bool = false) -> void:
	if is_dead: return
	is_dead = true
	is_flying = true
	fly_velocity = impact_velocity.limit_length(600.0) * 0.85
	_start_fall(impact_velocity)
	health = 0
	_drop_loot()
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	
	_spawn_blood_burst(impact_velocity.normalized())
	_create_3d_blood_puddle()
	_play_audio(ProceduralAudio.get_squish_stream(), -3.0)
	_play_audio(ProceduralAudio.get_scream_stream(), -4.0)
	
	var wm = get_node_or_null("/root/WantedManager")
	if wm and _is_player_driver and not local_security: wm.report_officer_killed()
	_start_decay()

func take_damage(amount: int, _is_player_attacker: bool = false) -> void:
	if amount <= 0 or is_dead: return
	if boarding_service_vehicle:
		velocity = Vector2.ZERO
		return
	if _is_player_attacker:
		response_aggression = 12.0
		var wanted := get_node_or_null("/root/WantedManager")
		if wanted and not local_security: wanted.ensure_minimum_wanted_level(2)
	health = maxi(0, health - amount)
	if mat_uniform:
		# Repeated hits must return to the issued uniform, never a flash tint
		# or the patrol palette used by a different unit.
		if _uniform_hit_tween and _uniform_hit_tween.is_valid():
			_uniform_hit_tween.kill()
		mat_uniform.albedo_color = Color(1.0, 0.3, 0.3)
		_uniform_hit_tween = create_tween()
		_uniform_hit_tween.tween_property(mat_uniform, "albedo_color", _uniform_base_color, 0.2)
	preload("res://audio/combat/CombatImpactAudio.gd").play_hurt(self, amount)
	
	if health <= 0:
		_die(_is_player_attacker)

func _die(is_player_attacker: bool = false) -> void:
	if is_instance_valid(service_vehicle) and service_vehicle.has_method("close_crew_cover_door"):
		service_vehicle.close_crew_cover_door(crew_side)
	is_dead = true
	_drop_loot()
	velocity = Vector2.ZERO
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	_start_fall()
	_create_3d_blood_puddle()
	_play_audio(ProceduralAudio.get_death_reaction_stream(), -5.0)
	
	var wm = get_node_or_null("/root/WantedManager")
	if wm and is_player_attacker and not local_security: wm.report_officer_killed()
	_dispatch_emergency_coroner()
	_start_decay()

func _dispatch_emergency_coroner() -> void:
	var care := get_node_or_null("/root/NPCMedicalCare")
	if care:
		care.report_injury(self)
		return
	var director := get_tree().get_first_node_in_group("emergency_depot_director")
	if director and director.has_method("request_dispatch"):
		get_tree().create_timer(3.0).timeout.connect(func():
			if is_instance_valid(self) and is_dead:
				director.request_dispatch("coroner", self)
		)

func _drop_loot() -> void:
	if police_loot:
		police_loot.drop_now()

func _physics_process(delta: float) -> void:
	weapon_reload.equip(String(dropped_weapon))
	weapon_reload.tick(delta)
	if vehicle_stop.phase != "idle":
		vehicle_stop.tick(self, delta)
	if is_flying:
		position += fly_velocity * delta
		fly_velocity = fly_velocity.move_toward(Vector2.ZERO, 950.0 * delta)
		if fly_velocity.length() < 12.0: is_flying = false
		
	if is_dead:
		fall_presentation.update(delta)
		return
	if returning_to_service_vehicle:
		if not is_instance_valid(service_vehicle):
			returning_to_service_vehicle = false
		else:
			var door_point: Vector2 = service_vehicle.get_crew_door_point(crew_side, crew_longitudinal) if service_vehicle.has_method("get_crew_door_point") else service_vehicle.global_position
			var door_dir := global_position.direction_to(door_point)
			if global_position.distance_to(door_point) > 7.0:
				velocity = _navigate_towards(door_point, speed, delta)
				move_and_slide()
				_animate_walk(delta)
				if model_root and door_dir.length_squared() > 0.01:
					model_root.rotation.y = lerp_angle(model_root.rotation.y, -atan2(door_dir.y, door_dir.x) - PI * 0.5, minf(1.0, 14.0 * delta))
				return
			_board_service_vehicle()
		return

	# The officer starts just inside the cruiser and first walks out through the
	# selected side door.  This deliberately happens before pursuit logic, so a
	# target on the opposite side can never make the officer pop through the car.
	if service_disembark_active:
		if not is_instance_valid(service_vehicle):
			service_disembark_active = false
		else:
			# O painel protege contra tiros, mas não pode aprisionar quem está
			# atravessando a própria porta durante o desembarque.
			var door: Node2D = service_vehicle._tactical_doors.get(crew_side)
			if is_instance_valid(door):
				var cover := door.get_node_or_null("BallisticCover") as StaticBody2D
				if cover: add_collision_exception_with(cover)
			var exit_point: Vector2 = service_vehicle.get_crew_exit_point(crew_side, crew_longitudinal) if service_vehicle.has_method("get_crew_exit_point") else service_vehicle.global_position
			var exit_dir := global_position.direction_to(exit_point)
			if global_position.distance_to(exit_point) > 5.0:
				velocity = _navigate_towards(exit_point, speed * 0.72, delta)
				move_and_slide()
				if model_root and exit_dir.length_squared() > 0.01:
					model_root.rotation.y = lerp_angle(model_root.rotation.y, -atan2(exit_dir.y, exit_dir.x) - PI * 0.5, minf(1.0, 14.0 * delta))
				_animate_walk(delta)
				return
			velocity = Vector2.ZERO
			if not preload("res://EmergencyCrewTransition.gd").finish_exit(self, service_vehicle, crew_side, delta): return
			service_disembark_active = false
			remove_collision_exception_with(service_vehicle)
	
	var pursuit_manager := get_node_or_null("/root/WantedManager")
	var player_pursuit: bool = not local_security and pursuit_manager and ((is_instance_valid(service_vehicle) and service_vehicle.get_meta("police_player_pursuit", false)) or is_in_group("foot_patrol") or (is_instance_valid(target) and (target.is_in_group("player") or target.get("is_driven_by_player") == true or target.get_meta("police_search_position", false))))
	if player_pursuit and not (is_instance_valid(target) and target.get_meta("bank_blockade", false)):
		pursuit_manager.report_visual_contact(self)
		target = pursuit_manager.get_pursuit_target()
	if is_instance_valid(target) and target.get_meta("police_search_position", false):
		_reset_arrest_warning()
		visible_aim_time = 0.0
		if target.get_meta("bank_blockade",false) and is_instance_valid(service_vehicle):
			service_vehicle.open_crew_cover_door(crew_side,crew_longitudinal)
			var point: Vector2=service_vehicle.get_crew_cover_point(crew_side,crew_longitudinal,target.global_position-Vector2(0,160))
			velocity=_navigate_towards(point,speed,delta) if global_position.distance_to(point)>8 else Vector2.ZERO
		else:
			_release_car_cover()
			velocity = _navigate_towards(target.global_position, speed * 0.85, delta) if global_position.distance_to(target.global_position) > 12.0 else Vector2.ZERO
		move_and_slide()
		_animate_walk(delta)
		if model_root and velocity.length_squared() > 1.0:
			model_root.rotation.y = lerp_angle(model_root.rotation.y, -velocity.angle() - PI * 0.5, minf(1.0, 14.0 * delta))
		return
	if not is_instance_valid(target):
		if is_instance_valid(service_vehicle) and service_vehicle.get_meta("ambient_response",false):
			return_to_service_vehicle()
			return
		velocity = Vector2.ZERO
		return
		
	var dist: float = global_position.distance_to(target.global_position)
	var dir: Vector2 = global_position.direction_to(target.global_position)
	
	var wm = get_node_or_null("/root/WantedManager")
	var stars: int = 1 if is_instance_valid(target) and target.get_meta("ambient_crime",false) else (wm.current_stars if wm else 0)
	if local_security: stars = security_alert
	
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	var is_moving: bool = false
	
	response_aggression = maxf(0.0, response_aggression - delta)
	# Aiming peeks over the assigned door; the muzzle starts beyond its panel.
	# Arrest checks below still require a completely unobstructed body-to-body ray.
	var visible_target := dist <= 430.0 and _has_target_sight(true)
	visible_aim_time = visible_aim_time + delta if visible_target else 0.0
	burst_pause = maxf(0.0, burst_pause - delta)
	if stars == 1 and arrest_warning_given and visible_target and target.get("velocity") != null and (target.get("velocity") as Vector2).length() > 45.0:
		fleeing_after_warning += delta
		if fleeing_after_warning >= 6.0 and wm and not local_security:
			wm.ensure_minimum_wanted_level(2)
			stars = wm.current_stars
	elif not visible_target:
		fleeing_after_warning = 0.0
	if visible_target and target.is_in_group("player") and target.get("fire_cooldown") != null and float(target.get("fire_cooldown")) > 0.0:
		response_aggression = 12.0
	if stars == 0:
		_reset_arrest_warning()
		velocity = Vector2.ZERO
	elif stars < 2 and response_aggression <= 0.0 and (target.is_in_group("vehicle") or target.get("is_driven_by_player") == true):
		_reset_arrest_warning()
		vehicle_stop.approach(self, target, delta)
		is_moving = velocity.length_squared() > 1.0
	elif stars < 2 and response_aggression <= 0.0:
		if is_instance_valid(service_vehicle) and service_vehicle._tactical_doors.has(crew_side):
			service_vehicle.close_crew_cover_door(crew_side)
		var tactical_spd: float = speed * 0.75
		if visible_target and dist < 220.0:
			if not arrest_warning_given:
				arrest_warning_given = true
				_play_audio(ProceduralAudio.get_police_radio_chatter_stream(), -12.0)
				if target.has_method("_show_weapon_notice"):
					target._show_weapon_notice("POLÍCIA: Pare e fique imóvel para se render!" if TranslationServer.get_locale().begins_with("pt") else "POLICE: Stop and stand still to surrender!")
			arrest_warning_elapsed += delta
		else:
			_reset_arrest_warning()
		if dist > 34.0 or not _has_target_sight():
			velocity = _navigate_towards(target.global_position, tactical_spd, delta)
			is_moving = true
			arrest_timer = 0.0
		else:
			velocity = Vector2.ZERO
			arrest_timer = arrest_timer + delta if _can_arrest_target() else 0.0
			if arrest_timer >= 2.0:
				_arrest_player()
				return
	else:
		_reset_arrest_warning()
		vehicle_stop.cancel()
		if _use_car_cover(visible_target, dist, delta):
			service_vehicle.open_crew_cover_door(crew_side, crew_longitudinal)
			var cover_point := service_vehicle.get_crew_cover_point(crew_side, crew_longitudinal, target.global_position) as Vector2
			velocity = _navigate_towards(cover_point, speed * 0.72, delta) if global_position.distance_to(cover_point) > 8.0 else Vector2.ZERO
			is_moving = velocity.length_squared() > 1.0
		elif not visible_target or dist > 180.0:
			velocity = _navigate_towards(target.global_position, speed, delta)
			is_moving = true
		elif dist < 100.0:
			velocity = _navigate_towards(global_position - dir * 120.0, speed * 0.6, delta)
			is_moving = true
		else:
			velocity = Vector2.ZERO
			
		if visible_target and dist <= 360.0 and visible_aim_time >= 0.65 and fire_cooldown <= 0.0 and burst_pause <= 0.0:
			_shoot_at_target(target.global_position)
			
	move_and_slide()
	is_moving = velocity.length_squared() > 1.0

	# Animação e Rotação 3D
	if model_root and dir.length_squared() > 0.01:
		var target_angle_3d: float = -atan2(dir.y, dir.x) - PI * 0.5
		model_root.rotation.y = lerp_angle(model_root.rotation.y, target_angle_3d, minf(1.0, 14.0 * delta))

	_animate_walk(delta)

	# NPCCombatRig applies Dante's arm poses after locomotion.

func _animate_walk(delta: float) -> void:
	var actual_speed := get_real_velocity().length()
	var is_moving := actual_speed > 1.0
	var stride := .18
	var leg_yaw := left_upper_leg.rotation.y if left_upper_leg else 0.0
	if is_moving and model_root and viewport_3d and sprite_3d_display:
		var direction := get_position_delta().normalized()
		leg_yaw = wrapf(-direction.angle() - PI * .5 - model_root.rotation.y, -PI, PI)
		var gait_direction := 1.0
		# Retreat reverses the step cycle instead of twisting knees/boots 180°.
		if absf(leg_yaw) > PI * .5:
			leg_yaw = wrapf(leg_yaw + PI, -PI, PI)
			gait_direction = -1.0
		var camera := viewport_3d.get_camera_3d()
		var axis := Vector3(direction.x, 0, direction.y) * .01
		var pixels_per_unit := (camera.unproject_position(axis) - camera.unproject_position(-axis)).length() * sprite_3d_display.scale.x / .02
		var presentation: Node = get_meta("interior_actor_presentation") if has_meta("interior_actor_presentation") else null
		if is_instance_valid(presentation): pixels_per_unit = presentation.pixels_per_rig_unit(direction)
		var leg_axis := Vector3(sin(leg_yaw), 0, cos(leg_yaw))
		var body_scale := (leg_axis * model_root.scale).length()
		# A planted foot travels two strides during half a cycle. Match its
		# projected travel to the physical body, including each officer's build.
		walk_clock = fposmod(walk_clock + gait_direction * get_position_delta().length() * TAU / maxf(4.0 * stride * pixels_per_unit * body_scale, .001), TAU)
	walk_weight = move_toward(walk_weight, 1.0 if is_moving else 0.0, delta * 6.0)
	var sink := .03 * walk_weight
	if model_root: model_root.position.y = -sink * model_root.scale.y
	for side in 2:
		var upper: Node3D = left_upper_leg if side == 0 else right_upper_leg
		var lower: Node3D = left_lower_leg if side == 0 else right_lower_leg
		if not upper or not lower: continue
		var phase := fposmod(walk_clock + side * PI, TAU) / TAU
		var swing := phase < .5
		var progress := phase * 2.0 if swing else (phase - .5) * 2.0
		var foot_z := lerpf(stride, -stride, progress) if swing else lerpf(-stride, stride, progress)
		foot_z *= walk_weight
		var lift := sin(progress * PI) * .05 * walk_weight if swing else 0.0
		var down := .6075 - sink - lift
		var knee := -acos(clampf((down * down + foot_z * foot_z - .30 * .30 - .3075 * .3075) / (2.0 * .30 * .3075), -1.0, 1.0))
		var hip := atan2(-foot_z, down) - atan2(.3075 * sin(knee), .30 + .3075 * cos(knee))
		# Lower body follows actual avoidance/backward travel; arms keep aim.
		upper.rotation = Vector3(0, leg_yaw, 0)
		upper.rotate_object_local(Vector3.RIGHT, hip)
		lower.rotation.x = knee
		var shoe := lower.get_node_or_null("ServiceShoe") as Node3D
		if shoe:
			shoe.position = Vector3(0, -.3075, 0) + Basis(Vector3.RIGHT, -hip - knee) * Vector3(0, 0, -.035)
			shoe.rotation.x = -hip - knee

var last_pos: Vector2 = Vector2.ZERO
var stuck_timer: float = 0.0
var unstuck_dir_sign: float = 1.0

var movement_navigation := preload("res://world/shared/emergency/PoliceFootNavigation.gd").new()

func _release_car_cover() -> void:
	car_cover_released = true
	if is_instance_valid(service_vehicle) and service_vehicle._tactical_doors.has(crew_side):
		service_vehicle.close_crew_cover_door(crew_side)

func _use_car_cover(visible_target: bool, distance: float, delta: float) -> bool:
	if car_cover_released or not is_instance_valid(service_vehicle): return false
	if service_vehicle.get("police_variant") == "motorcycle": return false
	# Lost sight, a fleeing suspect or a threat beside the door means advance.
	# Each seat holds a different interval, so the pair does not leave together.
	car_cover_elapsed += delta
	var hold_time := 2.8 if crew_side < 0.0 else 4.4
	if not visible_target or distance > 390.0 or distance < 65.0 or car_cover_elapsed >= hold_time or service_vehicle.global_position.distance_to(global_position) >= 170.0:
		_release_car_cover()
		return false
	return true

func _navigate_towards(dest: Vector2, move_speed: float, delta: float) -> Vector2:
	var result: Vector2 = movement_navigation.movement(self, dest, move_speed, delta)
	stuck_timer = movement_navigation.stuck_time
	return result


func begin_service_disembark(vehicle: Node2D, side: float, longitudinal: float) -> void:
	# Called before add_child() by EmergencyVehicle; do not access the scene tree
	# here.  The first physics tick handles the actual visible exit walk.
	service_vehicle = vehicle
	crew_side = side
	crew_longitudinal = longitudinal
	service_disembark_active = true
	car_cover_elapsed = 0.0
	car_cover_released = false


func return_to_service_vehicle() -> void:
	if not is_dead and is_instance_valid(service_vehicle):
		vehicle_stop.cancel()
		service_vehicle.close_crew_cover_door(crew_side)
		add_collision_exception_with(service_vehicle)
		service_disembark_active = false
		returning_to_service_vehicle = true


func _board_service_vehicle() -> void:
	if boarding_service_vehicle:
		return
	boarding_service_vehicle = true
	velocity = Vector2.ZERO
	if is_instance_valid(service_vehicle) and service_vehicle.has_method("play_crew_door"):
		service_vehicle.play_crew_door(crew_side, crew_longitudinal)
	await get_tree().create_timer(0.42).timeout
	if not is_instance_valid(self):
		return
	hide()
	set_physics_process(false)
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if is_instance_valid(service_vehicle) and service_vehicle.has_method("on_officer_embarked"):
		service_vehicle.on_officer_embarked(self)
	queue_free()

func _shoot_at_target(target_pos: Vector2) -> void:
	weapon_reload.equip(String(dropped_weapon))
	if not weapon_reload.consume(): return
	# Tactical burst pauses are separate from the actual magazine reload.
	burst_shots += 1
	var damage := 6
	var interval := 0.85
	var spread := 0.13
	var bullet_speed := 880.0
	match tier:
		UnitTier.ARMY, UnitTier.FBI, UnitTier.SWAT:
			damage = 8
			interval = 0.32
			spread = 0.10
			bullet_speed = 1200.0
		UnitTier.DETECTIVE:
			damage = 6
			interval = 0.40
			spread = 0.13
	var burst_size := 3 if tier != UnitTier.PATROL else 2
	fire_cooldown = interval + randf_range(0.0, 0.2)
	if burst_shots >= burst_size:
		burst_shots = 0
		burst_pause = randf_range(1.7, 2.5)
	_fire_single_bullet(target_pos, damage, bullet_speed, spread)
	var sound := ProceduralAudio.get_gunshot_pistol_stream() if tier == UnitTier.PATROL else ProceduralAudio.get_gunshot_smg_stream()
	_play_audio(sound, -7.0, randf_range(0.95, 1.05))
	if is_reloading():
		burst_pause = 0.0
		fire_cooldown = 0.0
		burst_shots = 0
		var sample := preload("res://audio/reload/ReloadAudioBank.gd").next_sample(String(dropped_weapon))
		if sample: _play_audio(sample, -9.0, sample.get_length() / weapon_reload.duration(String(dropped_weapon)))

func is_reloading() -> bool:
	return weapon_reload.remaining > 0.0

func get_reload_progress() -> float:
	return 1.0 - weapon_reload.remaining / weapon_reload.duration(String(dropped_weapon)) if is_reloading() else 0.0

func _fire_single_bullet(target_pos: Vector2, damage_val: int, bullet_spd: float, spread: float) -> void:
	var rig := get_node_or_null("NPCCombatRig")
	if rig: rig.attack()
	var dir: Vector2 = global_position.direction_to(target_pos)
	var bullet = BULLET_SCENE.instantiate()
	var scene := get_tree().current_scene
	if not is_instance_valid(scene):
		bullet.free()
		return
	scene.add_child(bullet)
	bullet.owner_body = self
	bullet.configure_range(WeaponCatalog.get_weapon(String(dropped_weapon)))
	bullet.damage = damage_val
	bullet.speed = bullet_spd
	bullet.direction = dir.rotated(randf_range(-spread, spread))
	bullet.global_position = global_position + dir * 22.0
	if has_meta("interior_actor_presentation") and is_instance_valid(muzzle_flash_3d):
		bullet.global_position = get_meta("interior_actor_presentation").project_node(muzzle_flash_3d)
		if is_instance_valid(target) and target.has_meta("interior_actor_presentation"):
			var presentation: Node = target.get_meta("interior_actor_presentation")
			target_pos = presentation.project_world(presentation.floor_position(target.global_position) + Vector3.UP * 1.1)
		bullet.direction = bullet.global_position.direction_to(target_pos).rotated(randf_range(-spread,spread))
	
	if muzzle_flash_3d:
		muzzle_flash_3d.visible = true
		var t := create_tween()
		t.tween_interval(0.05)
		t.tween_callback(func(): if muzzle_flash_3d: muzzle_flash_3d.visible = false)

func _arrest_player() -> void:
	if not _can_arrest_target() or arrest_timer < 2.0: return
	arrest_timer = 0.0
	if is_instance_valid(target) and target.has_method("arrest_and_respawn"):
		target.arrest_and_respawn()

func _reset_arrest_warning() -> void:
	arrest_timer = 0.0
	arrest_warning_elapsed = 0.0
	arrest_warning_given = false
	fleeing_after_warning = 0.0

func _has_target_sight(peek_over_cover := false) -> bool:
	if not is_instance_valid(target) or target.get_meta("police_search_position", false): return false
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position, 1 | 2)
	query.exclude = [get_rid()]
	if peek_over_cover and is_instance_valid(service_vehicle):
		var door: Node2D = service_vehicle._tactical_doors.get(crew_side)
		if is_instance_valid(door):
			var cover := door.get_node_or_null("BallisticCover") as StaticBody2D
			if cover:
				var excluded := query.exclude
				excluded.append(cover.get_rid())
				query.exclude = excluded
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == target

func _can_arrest_target() -> bool:
	var wanted := get_node_or_null("/root/WantedManager")
	if not local_security and wanted and wanted.current_stars >= 2 and is_instance_valid(target) and not target.get_meta("ambient_crime", false): return false
	if not is_instance_valid(target) or not (target.is_in_group("player") or target.get_meta("ambient_crime",false)): return false
	if target.has_meta("police_exterior_position") or target.get("is_dead") == true or target.get("is_control_disabled") == true: return false
	if not arrest_warning_given or arrest_warning_elapsed < 3.0 or response_aggression > 0.0: return false
	if target.get("fire_cooldown") != null and float(target.get("fire_cooldown")) > 0.0: return false
	if global_position.distance_to(target.global_position) > 34.0: return false
	if target.get("velocity") != null and (target.get("velocity") as Vector2).length() > 10.0: return false
	for car in get_tree().get_nodes_in_group("vehicle"):
		if target.is_in_group("player") and is_instance_valid(car) and car.get("is_driven_by_player") == true: return false
	return _has_target_sight()

func is_police_aiming() -> bool:
	if is_dead or is_flying or returning_to_service_vehicle or service_disembark_active: return false
	if not is_instance_valid(target) or target.get("is_dead") == true or target.get("is_arrested") == true: return false
	var wanted := get_node_or_null("/root/WantedManager")
	var stars: int = security_alert if local_security else (wanted.current_stars if wanted else 0)
	if target.get_meta("ambient_crime", false): stars = maxi(stars, 1)
	return stars > 0 and global_position.distance_to(target.global_position) <= 320.0 and _has_target_sight(true)

func _spawn_blood_burst(dir: Vector2) -> void:
	var blood_particles := CPUParticles2D.new()
	blood_particles.emitting = true
	blood_particles.one_shot = true
	blood_particles.explosiveness = 0.9
	blood_particles.amount = 25
	blood_particles.lifetime = 0.6
	blood_particles.spread = 45.0
	blood_particles.direction = dir
	blood_particles.initial_velocity_min = 70.0
	blood_particles.initial_velocity_max = 190.0
	blood_particles.gravity = Vector2(0, 160)
	blood_particles.scale_amount_min = 2.0
	blood_particles.scale_amount_max = 4.0
	blood_particles.color = Color(0.75, 0.05, 0.05, 0.95)
	add_child(blood_particles)

func _create_3d_blood_puddle() -> void:
	var puddle_root := Node2D.new()
	puddle_root.name = "3DBloodPuddle"
	puddle_root.global_position = global_position
	puddle_root.z_as_relative = false
	puddle_root.z_index = 3
	
	var base_poly := Polygon2D.new()
	base_poly.polygon = PackedVector2Array([
		Vector2(-12, -3), Vector2(-8, -9), Vector2(0, -11),
		Vector2(8, -8), Vector2(13, -1), Vector2(11, 7),
		Vector2(4, 10), Vector2(-5, 9), Vector2(-11, 4)
	])
	base_poly.color = Color(0.24, 0.01, 0.015, 0.92)
	puddle_root.add_child(base_poly)
	
	var core_poly := Polygon2D.new()
	core_poly.polygon = PackedVector2Array([
		Vector2(-9, -2), Vector2(-6, -7), Vector2(0, -8),
		Vector2(6, -6), Vector2(10, -1), Vector2(8, 5),
		Vector2(3, 7), Vector2(-4, 6), Vector2(-8, 3)
	])
	core_poly.color = Color(0.68, 0.04, 0.04, 0.95)
	puddle_root.add_child(core_poly)
	
	if get_parent():
		get_parent().add_child(puddle_root)
	else:
		get_tree().current_scene.add_child(puddle_root)
	puddle_root.global_position = global_position
		
	puddle_root.scale = Vector2(0.1, 0.1)
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(puddle_root, "scale", Vector2(0.65, 0.65), 0.55)
	
	var fade_tween := puddle_root.create_tween()
	fade_tween.tween_interval(6.0)
	fade_tween.tween_property(puddle_root, "modulate:a", 0.0, 2.5)
	fade_tween.tween_callback(puddle_root.queue_free)

func _start_decay() -> void:
	if has_meta("medical_pending"): return
	var t := create_tween()
	t.tween_interval(8.0)
	t.tween_property(self, "modulate:a", 0.0, 3.0)
	t.tween_callback(queue_free)

func _play_audio(stream: AudioStream, volume_db: float = -6.0, pitch_scale: float = 1.0) -> void:
	if stream == null: return
	var player := AudioStreamPlayer2D.new()
	player.bus = &"SFX"
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.max_distance = 600.0
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

func _start_fall(impact := Vector2.ZERO) -> void:
	fall_presentation.start(self, model_root, viewport_3d, impact)
