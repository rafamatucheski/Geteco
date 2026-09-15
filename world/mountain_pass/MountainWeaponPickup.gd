extends Area2D
var weapon_id := "knife"
var pickup_id := ""
var ammo := 0
var model: Node3D
var clock := 0.0
var collected := false
var render_host: Node2D
var load_on_pickup := false
var animate_on_floor := true
var hover_height := 0.0
var _floor_height := 0.08

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 26
	add_child(shape)
	body_entered.connect(_collect)

func install_model(parent: Node3D, point: Vector3) -> void:
	model = Node3D.new()
	model.name = name + "Model"
	model.position = point
	_floor_height = point.y
	parent.add_child(model)
	# Lying on its side, just above the boards; yaw is rotation on the floor plane.
	var weapon := Node3D.new()
	weapon.name = "FloorWeapon"
	weapon.rotation.z = PI * 0.5
	weapon.position.y = hover_height
	if weapon_id == "knife":
		weapon.scale = Vector3.ONE * 1.3
	model.add_child(weapon)
	preload("res://scripts/player/WeaponPresentation3D.gd").build(weapon, weapon_id)
	var halo := MeshInstance3D.new()
	halo.name = "FloorHalo"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.30 if weapon_id == "hunting_rifle" else 0.15
	ring.outer_radius = ring.inner_radius + 0.012
	ring.rings = 24
	ring.ring_segments = 6
	halo.mesh = ring
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("ad9459") if weapon_id == "hunting_rifle" else Color("65939a")
	halo.material_override = material
	halo.position.y = -0.055
	model.add_child(halo)

func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not collected and player != null and ("world_pickups_collected" in player) and player.world_pickups_collected.has(pickup_id):
		_hide_collected()
	if not is_instance_valid(model) or collected:
		return
	if player == null or not (player.get_meta("mountain_interior", false) or (is_instance_valid(render_host) and render_host.contains_actor(player))):
		return
	clock += delta
	if hover_height > 0.0:
		model.get_node("FloorWeapon").position.y = hover_height + sin(clock * 1.8) * 0.035
	if animate_on_floor:
		model.rotation.y = clock * 0.8
		model.position.y = _floor_height + sin(clock * 1.5) * 0.012
	if animate_on_floor or hover_height > 0.0:
		_refresh_host()

func _collect(body: Node2D) -> void:
	if collected or not body.is_in_group("player") or not body.visible or body.is_dead:
		return
	if is_instance_valid(render_host) and not render_host.contains_actor(body):
		return
	if body.world_pickups_collected.has(pickup_id):
		_hide_collected()
		return
	body.world_pickups_collected.append(pickup_id)
	body.add_weapon_loot(weapon_id, ammo, false)
	if load_on_pickup:
		var rounds: Dictionary = body.weapon_ammo[weapon_id]
		var capacity := int(WeaponCatalog.get_weapon(weapon_id).get("magazine_size", 0))
		var loaded := mini(maxi(0, capacity - int(rounds.clip)), int(rounds.reserve))
		rounds.clip += loaded
		rounds.reserve -= loaded
		body._refresh_weapon_ui()
	var tutorials := get_tree().get_first_node_in_group("gameplay_tutorials")
	if tutorials != null: tutorials.request_context("rare_item")
	_hide_collected()
	preload("res://audio/rewards/RewardAudioBank.gd").play(self, "weapon")
	var data := WeaponCatalog.get_weapon(weapon_id)
	var notice := "ARMA RECOLHIDA — " + String(data.get("short_label", weapon_id))
	if data.has("discovery_pickup"):
		notice = String(data.get("short_label", weapon_id)) + " LIBERADA PARA COMPRAR NA LOJA"
		if ammo > 0: notice += " · +%d BALAS" % ammo
	body._show_weapon_notice(notice)

func _hide_collected() -> void:
	collected = true
	set_deferred("monitoring", false)
	if is_instance_valid(model): model.hide()
	_refresh_host()
	set_process(false)

func _refresh_host() -> void:
	if is_instance_valid(render_host):
		var viewport: SubViewport = render_host.viewport_3d
		# The room also renders its occupants; a pickup must not freeze their rig.
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if int(viewport.get_meta("interior_actor_count", 0)) > 0 else SubViewport.UPDATE_ONCE
