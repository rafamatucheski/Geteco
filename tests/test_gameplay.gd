extends SceneTree

const GAMEPLAY = preload("res://gameplay/Gameplay.gd")
const ACTOR = preload("res://scripts/Actor.gd")
const CATALOG = preload("res://gameplay/WeaponCatalog.gd")
var failures: Array[String] = []
var checks := 0

class CombatState extends RefCounted:
	var equipped_weapon := "pistol"
	var safe := false
	var ammunition: Dictionary = {}
	func _init() -> void:
		for id in CATALOG.ORDER:
			var data: Dictionary = CATALOG.get_weapon(id)
			ammunition[id] = {"magazine": data.magazine_size, "reserve": data.starting_reserve}
	func owns_weapon(id: String) -> bool: return CATALOG.ORDER.has(id)
	func get_ammo(id: String) -> Dictionary: return ammunition.get(id, {})
	func consume_ammo(id: String, amount: int) -> bool:
		if safe or ammunition[id].magazine < amount: return false
		ammunition[id].magazine -= amount
		return true
	func add_ammo(id: String, amount: int) -> void: ammunition[id].reserve += amount
	func reload_weapon(id: String, capacity: int = -1) -> bool:
		if safe: return false
		if capacity < 0: capacity = CATALOG.get_weapon(id).magazine_size
		var take := mini(capacity - ammunition[id].magazine, ammunition[id].reserve)
		ammunition[id].magazine += take
		ammunition[id].reserve -= take
		return take > 0
	func equip_weapon(id: String) -> bool:
		if safe: return false
		equipped_weapon = id
		return true
	func can_attack() -> bool: return not safe
	func weapons_allowed() -> bool: return not safe

class Target extends StaticBody3D:
	var health := 500.0
	func _ready() -> void:
		collision_layer = 2
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1, 2, 1)
		shape.shape = box
		shape.position.y = 1
		add_child(shape)
	func receive_damage(amount: float, _source: Node = null) -> void: health -= amount

class EconomyState extends RefCounted:
	var economy = preload("res://systems/economy/Economy.gd").new()
	var equipped_weapon: String:
		get: return economy.equipped_weapon
	func owns_weapon(id: String) -> bool: return economy.owns_weapon(id)
	func get_ammo(id: String) -> Dictionary: return economy.get_ammo(id)
	func consume_ammo(id: String, amount: int) -> bool: return economy.consume_ammo(id, amount)
	func add_ammo(id: String, amount: int) -> bool: return economy.add_ammo(id, amount)
	func reload_weapon(id: String, capacity: int = -1) -> bool: return economy.reload_weapon(id, capacity)
	func equip_weapon(id: String) -> bool: return economy.equip_weapon(id)
	func spend(amount: int, receipt: String) -> bool: return economy.spend(amount, receipt)
	func can_attack() -> bool: return true
	func weapons_allowed() -> bool: return true

func _initialize() -> void: call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func run() -> void:
	if "--outfit-sheet" in OS.get_cmdline_user_args():
		await capture_outfits()
		return
	var scene := Node3D.new()
	root.add_child(scene)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	scene.add_child(floor_body)
	var player := ACTOR.new()
	player.is_player = true
	player.controlled_automatically = true
	scene.add_child(player)
	var state := CombatState.new()
	var gameplay := GAMEPLAY.new()
	gameplay.configure(scene, player, null, state)
	scene.add_child(gameplay)
	var target := Target.new()
	scene.add_child(target)
	target.position = Vector3(0, 0, -6)
	await physics_frame
	await physics_frame
	check(gameplay.fire_at(Vector3(0, 1, -6)), "pistol fires")
	check(target.health < 500, "native ray hits target")
	check(state.ammunition.pistol.magazine == 11, "one cartridge consumed")
	check(not gameplay.fire_at(Vector3(0, 1, -6)), "cadence enforced")
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(4, 3, 0.5)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	scene.add_child(wall)
	wall.position = Vector3(0, 1.5, -3)
	await physics_frame
	await physics_frame
	gameplay.cooldown = 0
	var old_health: float = target.health
	gameplay.fire_at(Vector3(0, 1, -6))
	check(target.health == old_health, "wall blocks bullet")
	gameplay.explode(Vector3(0, 1, -1), 8, 90, player)
	check(target.health == old_health, "wall blocks explosion")
	wall.queue_free()
	await physics_frame
	await physics_frame
	state.safe = true
	for id in CATALOG.ORDER:
		state.equipped_weapon = id
		gameplay.cooldown = 0
		var old_ammo: Dictionary = state.get_ammo(id).duplicate()
		check(not gameplay.fire_at(Vector3(0, 1, -6)), "garage blocks " + id)
		check(state.get_ammo(id) == old_ammo, "garage preserves ammo " + id)
	check(not gameplay.reload_weapon(), "garage blocks reload")
	check(not gameplay.cycle_weapon(1), "garage blocks draw")
	var health_before: float = gameplay.health
	gameplay.damage_player(1000)
	check(gameplay.health == health_before, "safe zone blocks incoming damage")
	state.safe = false
	state.equipped_weapon = "pistol"
	state.ammunition.pistol.magazine = 0
	gameplay.cooldown = 0
	check(not gameplay.fire_at(Vector3(0, 1, -6)), "empty magazine cannot fire")
	# V1: pente vazio com reserva inicia a recarga sozinho; a duração vem do maior take do banco de recarga da arma.
	check(gameplay.reload_timer > 0.0, "empty magazine starts reload by itself (V1)")
	check(not gameplay.reload_weapon(), "reload already running")
	gameplay._physics_process(preload("res://gameplay/CombatAudio.gd").reload_seconds("pistol") + 0.1)
	check(state.ammunition.pistol.magazine == 12, "reload transfers reserve")
	state.equipped_weapon = "fists"
	target.position.z = -1.6
	await physics_frame
	await physics_frame
	gameplay.cooldown = 0
	old_health = target.health
	gameplay.fire_at(Vector3(0, 1, -2))
	check(target.health < old_health, "melee uses collision target")
	gameplay.clear_wanted()
	gameplay.register_crime(30, player.position)
	check(gameplay.stars == 2, "V1 wanted thresholds")
	gameplay.register_crime(210, player.position)
	check(gameplay.stars == 6, "six wanted levels")
	gameplay.clear_wanted()
	gameplay.register_crime(12, player.position)
	gameplay.hidden_time = 23.1
	gameplay._update_police(0.1)
	check(gameplay.stars == 0, "escaping contact clears wanted")
	gameplay.damage_player(1000)
	check(gameplay.health == 0 and not gameplay.fire_at(Vector3(0, 1, -2)), "death blocks firing")
	gameplay.respawn()
	check(gameplay.health == 100 and gameplay.stars == 0, "respawn resets health and pursuit")
	gameplay.damage_player(45)
	var saved: Dictionary = gameplay.snapshot()
	gameplay.respawn()
	check(gameplay.restore_state(saved) and gameplay.health == 55, "health restores")
	var bad: Dictionary = saved.duplicate()
	bad.health = -1
	check(not gameplay.restore_state(bad), "invalid snapshot rejected atomically")
	check(gameplay.health == 55, "rejected restore preserves health")
	gameplay.register_crime(12, Vector3.ZERO)
	var officer := gameplay.spawn_officer()
	check(officer != null, "native police spawns on free floor")
	if officer:
		check(officer.find_children("*", "SubViewport", true, false).is_empty(), "police has no private viewport")
		officer.receive_damage(1000, player)
		check(officer.dead and officer.collision_layer == 0, "police death disables blocking")
	gameplay.clear_wanted()
	gameplay.respawn()
	target.health = 5000
	target.position = Vector3(0, 0, -6)
	await physics_frame
	await physics_frame
	for id in CATALOG.ORDER:
		state.equipped_weapon = id
		gameplay.cooldown = 0
		gameplay.reload_timer = 0
		gameplay._update_visual()
		check(gameplay.fire_at(Vector3(0, 1, -6)), "arsenal fires: " + id)
		check(gameplay.visual_id == id, "original geometry equipped: " + id)
	var projectiles: Array[Node] = []
	for child in gameplay.get_children():
		if child.get_script() == preload("res://gameplay/Projectile.gd"): projectiles.append(child)
	check(projectiles.size() == 2, "RPG and grenade use native projectiles")
	for projectile in projectiles:
		if projectile.grenade:
			projectile.global_position = Vector3(3, 0.11, 0)
			projectile.velocity = Vector3(0, -5, 0)
			projectile._physics_process(0.1)
			check(projectile.velocity.y > 0, "grenade bounces off solid ground")
		else:
			var before_rocket: float = target.health
			for tick in 10:
				if projectile.detonated: break
				projectile._physics_process(0.05)
			check(projectile.detonated and target.health < before_rocket, "rocket swept collision detonates on target")
	var snapshot_before_safe_blast: float = target.health
	state.safe = true
	gameplay.explode(target.position + Vector3.UP, 4, 50, player)
	check(target.health == snapshot_before_safe_blast, "in-flight explosion cannot follow player into safe zone")
	# Shop economics and capacity use the production Economy, not CombatState.
	var economy_state := EconomyState.new()
	economy_state.economy.grant_reward("gameplay_fixture", 4000)
	economy_state.economy.grant_weapon("pistol")
	economy_state.economy.equip_weapon("pistol")
	gameplay.state = economy_state
	gameplay.cooldown = 0
	gameplay.reload_timer = 0
	check(gameplay.buy_attachment("pistol", "extended"), "original extended magazine purchased")
	check(economy_state.economy.balance == 3500, "attachment charges original price")
	check(gameplay.buy_attachment("pistol", "extended") and economy_state.economy.balance == 3500, "owned part reinstall cannot charge twice")
	check(int(gameplay.weapon_data("pistol").magazine_size) == 18, "attachment modifies actual capacity")
	check(gameplay.reload_weapon(), "extended magazine can reload above base")
	gameplay._physics_process(2.0)
	check(economy_state.get_ammo("pistol").magazine == 18, "production economy stores extended rounds")
	check(gameplay.buy_attachment("pistol", "laser_green"), "laser can be purchased")
	check(gameplay.buy_attachment("pistol", "flashlight"), "flashlight can be purchased")
	check(gameplay.toggle_flashlight(), "owned lamp switches")
	gameplay._update_visual()
	check(gameplay.flashlight.visible and gameplay.laser.visible, "native lamp and laser active")
	check(not gameplay.buy_attachment("pistol", "scope_2x"), "incompatible scope rejected")
	var custom_save: Dictionary = gameplay.snapshot()
	check(gameplay.restore_state(custom_save), "customization survives validated snapshot")
	check(gameplay.customization.pistol.parts.magazine == "extended", "installed part restored")
	var citizen := ACTOR.new()
	scene.add_child(citizen)
	citizen.position = Vector3(8, 0, 8)
	citizen.health = 20
	gameplay.emergency.report_injury(citizen, false)
	var incident: int = gameplay.emergency.serial
	check(gameplay.emergency.incidents[incident].role == "medic", "living casualty requests medic")
	gameplay.emergency.complete(incident)
	check(citizen.health >= 60 and not citizen.dead, "medic stabilizes living casualty to at least 60 health")
	citizen.dead = true
	citizen.health = 0
	gameplay.emergency.report_injury(citizen, true)
	incident = gameplay.emergency.serial
	check(gameplay.emergency.incidents[incident].role == "mortician", "fatal casualty requests mortician")
	gameplay.emergency.complete(incident)
	check(citizen.is_queued_for_deletion(), "mortician removes fatal body")
	var fire: Node3D = gameplay.emergency.ignite(Vector3(12, 0, 12), player)
	check(fire != null, "fire needs actual ground")
	gameplay.emergency.extinguish(fire, 2)
	check(fire.is_queued_for_deletion(), "firefighter extinguishes intensity")
	for role in ["medic", "fire", "mortician"]:
		var responder := preload("res://gameplay/emergency/Responder.gd").new()
		responder.manager = gameplay.emergency
		responder.role = role
		scene.add_child(responder)
		responder.set_physics_process(false)
		check(responder.visual.get_child_count() > 4, "original emergency rig built: " + role)
		check(responder.find_children("*", "SubViewport", true, false).is_empty(), "native emergency rig: " + role)
		responder.queue_free()
	# Finish the prior explosive/fire fixture before testing self-defense.
	for effect in gameplay.emergency.fires:
		if is_instance_valid(effect): effect.queue_free()
	for child in gameplay.get_children():
		if child.get_script() == preload("res://gameplay/Projectile.gd"): child.queue_free()
	await physics_frame
	await physics_frame
	gameplay.clear_wanted()
	for tier in 3:
		var cobra := preload("res://gameplay/CobraAgent.gd").new()
		cobra.configure(gameplay, tier)
		scene.add_child(cobra)
		cobra.position = Vector3(0, 0, -4)
		cobra.set_physics_process(false)
		await physics_frame
		await physics_frame
		check(cobra.visual.name == "CobraOriginal" and cobra.get_meta("gameplay_role") == "cobra", "original Cobra identity " + str(tier))
		check(cobra.health == (110 if tier == 2 else 80), "original Cobra health " + str(tier))
		gameplay.cooldown = 0
		var cobra_shot: bool = gameplay.fire_at(cobra.position + Vector3.UP)
		check(cobra_shot and cobra.health < cobra.max_health and gameplay.crime_points == 0, "defending against Cobra does not create wanted " + str(tier))
		cobra.receive_damage(1000, player)
		check(cobra.dead and cobra.collision_layer == 0, "Cobra defeat uses native collision " + str(tier))
		cobra.queue_free()
	gameplay.clear_wanted()
	gameplay._update_police(180.0)
	check(gameplay.hidden_time == 0 and gameplay.restore_state(gameplay.snapshot()), "idle session over two minutes keeps valid combat snapshot")
	var patient := ACTOR.new()
	scene.add_child(patient)
	patient.position = Vector3(20, 0, 20)
	patient.health = 15
	gameplay.emergency.report_injury(patient, false)
	var call_id: int = gameplay.emergency.serial
	await physics_frame
	await physics_frame
	check(gameplay.emergency._dispatch(call_id), "emergency dispatch admits native vehicle on free ground")
	if gameplay.emergency.incidents[call_id].assigned:
		var crew: CharacterBody3D = gameplay.emergency.incidents[call_id].crew
		crew.set_physics_process(false)
		await physics_frame
		await physics_frame
		for tick in 900:
			if not gameplay.emergency.incidents.has(call_id): break
			crew._physics_process(1.0 / 60.0)
		check(patient.health >= 60 and not gameplay.emergency.incidents.has(call_id), "responder physically approaches and stabilizes patient")
		if is_instance_valid(crew): gameplay.emergency.release(crew)
	var wardrobe: Dictionary = preload("res://assets/outfits/MeshyDanteAppearance.gd").OUTFITS
	var original_skeleton := player.skeleton
	var weapon_socket: Node3D = gameplay.socket
	for id in wardrobe:
		check(player.set_outfit(id), "outfit applies: " + id)
		check(player.outfit_id == id and player.outfit_material != null, "outfit shader bound: " + id)
		check(player.outfit_material.get_shader_parameter("region_tex") != null, "original outfit mask exists: " + id)
		check(player.outfit_material.get_shader_parameter("recolor") == (id != "dante_classic"), "original palette selected: " + id)
		check(player.skeleton == original_skeleton and is_instance_valid(weapon_socket), "changing outfit preserves skeleton and gun socket: " + id)
		var expected_accessories: Array = wardrobe[id].get("accessories", [])
		var attached: Array[Node] = player.skeleton.find_children("MeshyOutfit*", "BoneAttachment3D", false, false)
		check(attached.is_empty() == expected_accessories.is_empty(), "outfit accessories replaced without accumulation: " + id)
	check(not player.set_outfit("nonexistent_outfit") and player.outfit_id == "dante_badboy", "unknown outfit preserves previous appearance")
	player.set_outfit("dante_classic")
	var traffic_routes := preload("res://gameplay/NativeTrafficRoutes.gd").new()
	var road_fixture: Array = [
		{"id":"north","width":8.0,"points":PackedVector3Array([Vector3(-20,0,-20),Vector3(20,0,-20)])},
		{"id":"east","width":8.0,"points":PackedVector3Array([Vector3(20,0,-20),Vector3(20,0,20)])},
		{"id":"south","width":8.0,"points":PackedVector3Array([Vector3(20,0,20),Vector3(-20,0,20)])},
		{"id":"west","width":8.0,"points":PackedVector3Array([Vector3(-20,0,20),Vector3(-20,0,-20)])}]
	traffic_routes.configure(road_fixture)
	var traffic_curve: Curve3D = traffic_routes.route_near(Vector3(0,0,-18))
	check(traffic_curve != null and not traffic_curve.get_meta("traffic_open"), "authored road circuit forms closed traffic loop")
	check(traffic_curve.get_point_position(0).is_equal_approx(traffic_curve.get_point_position(traffic_curve.get_point_count()-1)), "traffic loop seam closes physically")
	var loop_nodes: Array = traffic_curve.get_meta("traffic_nodes")
	var has_uturn := false
	for index in range(2,loop_nodes.size()):
		if loop_nodes[index] == loop_nodes[index-2]: has_uturn = true
	check(not has_uturn and traffic_curve.get_meta("traffic_source_ids").size() == 4, "loop uses actual junctions without same-street U-turn")
	var outside_road := false
	for point in traffic_curve.get_baked_points():
		var nearest := INF
		for road in road_fixture:
			nearest = minf(nearest, point.distance_to(Geometry3D.get_closest_point_to_segment(point,road.points[0],road.points[1])))
		if nearest > 4.05: outside_road = true
	check(not outside_road, "rounded lane remains within original road corridor")
	traffic_routes.configure([
		{"id":"east_west","width":8.0,"points":PackedVector3Array([Vector3(-20,0,0),Vector3(20,0,0)])},
		{"id":"north_south","width":8.0,"points":PackedVector3Array([Vector3(0,0,-20),Vector3(0,0,20)])}])
	check(traffic_routes.vertices.size() == 5, "crossing centre-lines become one real junction")
	traffic_curve = traffic_routes.route_near(Vector3(-10,0,2))
	check(traffic_curve.get_meta("traffic_open"), "acyclic roads terminate instead of invented U-turn")
	traffic_routes.configure([{"id":"mountain_bridge_outbound","width":3.875,"points":PackedVector3Array([Vector3.ZERO,Vector3(0,0,20)])}])
	check(traffic_routes.edges[1].is_empty(), "authored one-way bridge has no reverse edge")
	traffic_curve = traffic_routes.route_near(Vector3(0,0,5))
	check(traffic_curve.get_point_position(0).x == 0 and traffic_curve.get_meta("traffic_endpoint").z == 20, "one-way bridge uses authored centre without double lane offset")
	print(JSON.stringify({"suite":"gameplay", "checks":checks, "failures":failures}))
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func capture_outfits() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("29353b")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d7e1e4")
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	scene.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 11.8
	scene.add_child(camera)
	camera.position = Vector3(0, 13, 18)
	camera.look_at(Vector3(0, 0.7, 0))
	camera.current = true
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(25, 20)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("607078")
	material.roughness = 1
	ground.material_override = material
	scene.add_child(ground)
	var index := 0
	for id in preload("res://assets/outfits/MeshyDanteAppearance.gd").OUTFITS:
		var actor := ACTOR.new()
		actor.is_player = true
		actor.outfit_id = id
		scene.add_child(actor)
		actor.position = Vector3((index % 4 - 1.5) * 3.6, 0.03, (index / 4 - 1) * 5.4)
		actor.visual.rotation.y = PI
		actor.animation.play("Walking")
		actor.animation.seek(0.067, true)
		actor.set_physics_process(false)
		var label := Label3D.new()
		label.text = id.trim_prefix("dante_").to_upper()
		label.font_size = 50
		label.pixel_size = 0.005
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color.WHITE
		label.outline_modulate = Color("20272b")
		label.outline_size = 8
		scene.add_child(label)
		label.position = actor.position + Vector3(0, 0.25, 0.9)
		index += 1
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var path := "res://evidence/outfits-v2.png"
	var result := root.get_texture().get_image().save_png(path)
	print("OUTFIT_CAPTURE ", result, " ", ProjectSettings.globalize_path(path))
	quit(0 if result == OK else 1)
