extends AnimatedPedestrian3D
## Authored locals: shared articulated rig, physical walking, no global random route.
var territory: Node
var profile: int = 0
var guard: bool = true
var combat_role := "lookout"
var weapon_id := "pistol"
var shots_fired := 0
var _burst_remaining := 0
const COBRA_BULLET := preload("res://Bullet.tscn")
var patrol := PackedVector2Array()
var _patrol_index := 0
var _patrol_direction := 1

func _setup_district_and_archetype() -> void:
	district_theme = DistrictTheme.CITY_DOWNTOWN
	archetype = Archetype.CITY_GANGSTER if guard else Archetype.CITY_CASUAL
	is_gangster = guard
	has_handgun = false # Role-specific meshes are attached after the shared rig.
	weapon_id = {"lookout":"pistol","enforcer":"shotgun","leader":"smg"}.get(combat_role,"pistol")
	ambient_running_enabled = false
	base_walk_speed = 38.0 + profile * 3.0
	body_height_scale = [1.08, 0.94, 1.02][profile % 3]
	body_width_scale = [0.94, 1.22, 1.08][profile % 3]
	skin_color = [Color("b88766"), Color("704d3b"), Color("d5aa83")][profile % 3]
	shirt_color = [Color("302c30"), Color("633b40"), Color("4a3035")][profile % 3]
	pants_color = Color("29333c")
	shoe_color = Color("242224")
	hair_color = Color("251e1b")
	hat_color = Color("682e38")
	accessory_color = Color("987247")
	if not guard:
		shirt_color = [Color("a59b80"),Color("627985"),Color("979b85")][profile%3]
		pants_color = Color("535b60")
		hat_color = Color("9b967f")
		accessory_color = Color("716557")
	has_bandana = guard and profile == 0
	has_vest = guard and profile == 1
	has_beanie = profile == 2
	has_beard = guard and profile == 1
	max_health = (110 if combat_role == "leader" else 80) if guard else 40
	health = max_health

func _ready() -> void:
	defer_presentation = true
	super._ready()
	add_to_group("cobra_local")
	if guard:
		add_to_group("iron_cobras")
		add_to_group("gang_member")
		presentation_ready.connect(_build_role_weapon, CONNECT_ONE_SHOT)

func _build_role_weapon() -> void:
	if not is_instance_valid(right_lower_arm):
		return
	muzzle_flash_3d = MeshInstance3D.new()
	var flash := SphereMesh.new()
	flash.radius = 0.055
	flash.height = 0.08
	muzzle_flash_3d.mesh = flash
	muzzle_flash_3d.material_override = _make_mat(Color("ffca75"),0.0)
	muzzle_flash_3d.visible = false
	right_lower_arm.add_child(muzzle_flash_3d)
	preload("res://world/shared/pedestrians/NPCCombatRig.gd").attach(self, weapon_id)

func _pick_new_sidewalk_target() -> void:
	if patrol.is_empty():
		walk_target = global_position
		return
	walk_target = patrol[_patrol_index % patrol.size()]
	# Authored sidewalks are open polylines: reverse at each end, never draw
	# an implicit diagonal shortcut from the final point back to the first.
	if patrol.size() > 1:
		_patrol_index += _patrol_direction
		if _patrol_index >= patrol.size():
			_patrol_direction = -1
			_patrol_index = patrol.size() - 2
		elif _patrol_index < 0:
			_patrol_direction = 1
			_patrol_index = 1

func _physics_process(delta: float) -> void:
	if not is_scared and is_instance_valid(territory) and territory.interaction_suspended():
		velocity = Vector2.ZERO
		_update_viewport_render_state(delta)
		return
	if guard and is_instance_valid(territory):
		combat_target = territory.combat_target_for(self)
	super._physics_process(delta)

func _navigate_towards(dest: Vector2, speed: float, delta: float) -> Vector2:
	if guard and is_instance_valid(territory) and territory.has_method("get_tactical_destination"):
		dest = territory.get_tactical_destination(self,dest)
	return super._navigate_towards(dest,speed,delta)

func _gangster_shoot_target(target_pos: Vector2) -> void:
	if is_instance_valid(territory) and territory.can_see(self, combat_target):
		var data := WeaponCatalog.get_weapon(weapon_id)
		var direction := global_position.direction_to(target_pos)
		for pellet in int(data.get("pellets",1)):
			var bullet := COBRA_BULLET.instantiate()
			bullet.owner_body = self
			bullet.damage = int(data.damage)
			bullet.speed = float(data.projectile_speed)
			bullet.direction = direction.rotated(randf_range(-float(data.spread),float(data.spread)))
			bullet.position = global_position + direction*16
			bullet.tracer_color = data.tracer_color
			get_tree().current_scene.add_child(bullet)
		var rig := get_node_or_null("NPCCombatRig")
		if rig: rig.attack()
		shots_fired += 1
		if weapon_id == "smg":
			_burst_remaining = (_burst_remaining+1)%3
			gun_cooldown = float(data.fire_interval) if _burst_remaining != 0 else 1.35
		else:
			gun_cooldown = maxf(0.95,float(data.fire_interval)*1.5)
		_play_audio(WeaponCatalog.get_audio_stream(weapon_id),-8.0)
		if muzzle_flash_3d:
			muzzle_flash_3d.visible = true
			var tween := create_tween()
			tween.tween_interval(0.05)
			tween.tween_callback(func():
				if is_instance_valid(muzzle_flash_3d): muzzle_flash_3d.visible = false)

func take_damage(amount: int, is_player_attacker: bool = false) -> void:
	if is_dead or amount <= 0:
		return
	if is_player_attacker and guard and is_instance_valid(territory):
		territory.report_aggression()
	# Base retaliation targets the player even for non-player damage; suppress it.
	var old_gangster := is_gangster
	is_gangster = false
	super.take_damage(amount, is_player_attacker)
	is_gangster = old_gangster
	if guard:
		is_scared = false
		combat_target = null

func get_run_over(impact_velocity: Vector2, is_player_driver: bool = false) -> void:
	if guard and is_player_driver and not is_dead and is_instance_valid(territory):
		territory.report_aggression()
	super.get_run_over(impact_velocity, is_player_driver)

func panic() -> void:
	if guard or is_dead:
		return
	super.panic()

func say(message: String) -> void:
	_show_custom_bubble(message, Color("a86660"))
