extends SceneTree

const PLAYER_SCRIPT := preload("res://characters/Player.gd")
const SEWER_SCRIPT := preload("res://world/harbor/sewer/HarborManholeSewer.gd")

var failures: Array[String] = []
var world: Node2D
var player: CharacterBody2D
var sewer: Node2D
var street_audio: AudioStreamPlayer
var street_probe: Node

class StreetProbe:
	extends Node
	var ticks := 0
	func _physics_process(_delta: float) -> void: ticks += 1

class CombatTarget:
	extends CharacterBody2D
	var health := 1000
	var heard := 0
	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		add_to_group("damageable")
		add_to_group("pedestrian")
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 6.0
		shape.shape = circle
		add_child(shape)
	func take_damage(amount: int, _from_player := false) -> void: health -= amount
	func hear_gunfire(_start: Vector2, _end: Vector2) -> void: heard += 1

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures.append(message)

func frames(count: int) -> void:
	for _index in count:
		await process_frame

func wait_for_state(expected: int, timeout_seconds := 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while sewer.state != expected and Time.get_ticks_msec() < deadline:
		await process_frame
	return sewer.state == expected

func _run() -> void:
	root.get_node("SaveManager").clear_pending_save()
	world = Node2D.new()
	world.name = "ManholeTestWorld"
	root.add_child(world)
	current_scene = world
	player = CharacterBody2D.new()
	player.name = "Player"
	player.set_script(PLAYER_SCRIPT)
	player.collision_layer = 4
	player.collision_mask = 7
	player.speed = 100.0
	player.position = Vector2(-52.0, 0.0)
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.zoom = Vector2.ONE * 2.072
	player.add_child(camera)
	var collision := CollisionShape2D.new()
	collision.name = "Collision"
	var capsule := CapsuleShape2D.new()
	capsule.radius = 5.0
	capsule.height = 16.0
	collision.shape = capsule
	player.add_child(collision)
	world.add_child(player)
	sewer = SEWER_SCRIPT.new()
	sewer.name = "PoliceManholeSewer"
	world.add_child(sewer)
	street_audio = AudioStreamPlayer.new()
	street_audio.stream = root.get_node("CityAudioManager").ambience_player.stream
	world.add_child(street_audio)
	street_audio.play()
	street_probe = StreetProbe.new()
	world.add_child(street_probe)
	await frames(6)

	var starting_scene := current_scene
	var original_layer := player.collision_layer
	var original_mask := player.collision_mask
	var original_z := player.z_index
	var head_anchor: Vector3 = player.torso_node.transform.affine_inverse() * player.head_node.position
	player.global_position = Vector2(-52.0, 0.0)
	check(not sewer.request_interaction(player), "secret cover cannot be opened from the old long distance")
	player.global_position = Vector2(-22.0, 0.0)
	await physics_frame
	var initial: Dictionary = sewer.get_runtime_stats()
	check(not initial.interior_loaded and not initial.inside, "closed cover keeps the underground scene unbuilt")
	check(sewer._surface_art.get_node_or_null("Prompt") == null, "surface has no orange marker or E prompt")
	player.global_position = Vector2(-6.0, 0.0)
	check(await wait_for_state(SEWER_SCRIPT.State.OPENING,1.0), "walking onto the cover starts descent without E")
	check(sewer.get_runtime_stats().interior_loaded, "opening the cover builds the sewer on demand")
	var original_scale: Vector2 = player.sprite_3d_display.scale
	var original_material: Material = player.sprite_3d_display.material
	await create_timer(0.85).timeout
	var lid: Node2D = sewer._surface_art.lid
	check(lid.model.get_child_count() >= 2, "cover is built from actual 3D geometry")
	check(lid.position.x < -1.0 and is_zero_approx(lid.rotation), "loose cover slides without hinging upright")
	var grip_offset: Vector2 = player.global_position - lid.global_position
	await create_timer(0.15).timeout
	check((player.global_position - lid.global_position).distance_to(grip_offset) < 0.01, "Dante follows the moving cover while dragging")
	await create_timer(2.0).timeout
	check(sewer.state == SEWER_SCRIPT.State.OPENING, "entry gives the ladder movement time to read")
	check(player.sprite_3d_display.scale == original_scale, "Dante keeps his full size during descent")
	check(player.sprite_3d_display.material is ShaderMaterial, "shaft lip occludes the descending body")
	check(player.head_node.position.distance_to(player.torso_node.transform * head_anchor) < 0.001, "head remains anchored during climbing")
	check(await wait_for_state(SEWER_SCRIPT.State.INSIDE), "entry animation reaches the playable sewer")
	check(player.sprite_3d_display.material == original_material, "normal sprite material returns underground")

	var entered: Dictionary = sewer.get_runtime_stats()
	check(current_scene == starting_scene and player.get_parent() != world, "street stays resident while Dante moves to a separate scene instance")
	check(entered.inside and entered.interior_visible, "sewer presentation is visible after descent")
	check(sewer._interior_overlay.get_node_or_null("ExitPrompt") == null, "ladder has no orange exit marker or E prompt")
	check(entered.collision_bodies == 13, "sewer blocks walls, channel, shelving, crates, cabinet, barrels and raised pipes")
	check(player.global_position.distance_to(sewer.global_position) < 1.0, "Dante stays on the same world coordinate through the descent")
	check(player.visible and player.is_physics_processing() and not player.is_control_disabled, "Dante regains normal control underground")
	check(entered.isolated_world and player.get_world_2d() != world.get_world_2d(), "underground collision has its own World2D, not a street collision layer")
	var stopped_at: int = street_probe.ticks
	await create_timer(0.10).timeout
	check(street_probe.ticks == stopped_at and sewer._isolation.layer.visible, "street simulation is suspended behind the separate opaque scene")
	check(street_audio.volume_db <= -70.0, "street audio sources are inaudible underground")
	check(not sewer._ambient_water.stream_paused and sewer._ambient_water.playing, "sewer water stays audible in its own instance")
	check(sewer.contains_point(player.global_position), "production room scan recognizes the sewer interior")
	check(player.has_meta("interior_actor_presentation"), "Dante shares the underground furniture depth buffer")
	if DisplayServer.get_name() != "headless":
		await verify_depth(player.get_meta("interior_actor_presentation"), "Dante")
	var room_model: Node2D = sewer._interior_overlay.get_node("RoomModel")
	var visitor := preload("res://characters/AnimatedPedestrian3D.gd").new() as CharacterBody2D
	sewer._interior_overlay.add_child(visitor)
	visitor.set_physics_process(false)
	visitor.collision_mask = 1
	visitor.global_position = player.global_position + Vector2(30, 0)
	var visitor_depth := preload("res://systems/interiors/InteriorActorPresentation.gd").new()
	sewer._interior_overlay.add_child(visitor_depth)
	visitor_depth.configure(visitor, room_model.camera_3d, room_model.sprite_3d)
	check(visitor.move_and_collide(Vector2(-250, 0)) != null, "underground wall blocks a visiting NPC")
	if DisplayServer.get_name() != "headless":
		await verify_depth(visitor_depth, "visiting NPC")
	visitor_depth.restore()
	visitor_depth.queue_free()
	visitor.queue_free()
	await verify_combat_isolation()

	var before_walk := player.global_position
	Input.action_press("move_right")
	await create_timer(2.8).timeout
	Input.action_release("move_right")
	await physics_frame
	check(player.global_position.x > before_walk.x + 230.0, "native movement crosses the service bridge")
	check(player.global_position.x < sewer.global_position.x + SEWER_SCRIPT.INTERIOR_BOUNDS.end.x, "outer sewer wall contains Dante")

	player.global_position = sewer.to_global(SEWER_SCRIPT.SECRET_POSITION + Vector2(-20.0, 0.0))
	for frame in 4: await physics_frame
	check(player.world_pickups_collected.has(SEWER_SCRIPT.SECRET_PICKUP_ID), "walking over the secret records its unique pickup in Player save data")
	check(player.weapon_inventory.get("sawed_off", false) == true, "secret stash grants the sawed-off shotgun")
	check(player.weapon_ammo.get("sawed_off", {}).get("reserve", 0) >= 24, "secret weapon includes usable ammunition")
	var serialized: Dictionary = player.serialize()
	check(serialized.world_pickups_collected.has(SEWER_SCRIPT.SECRET_PICKUP_ID), "secret collection survives Player serialization")
	check(Vector2(serialized.position[0], serialized.position[1]) == sewer.global_position + Vector2(0,20), "saving underground records a safe point beside the automatic cover")

	player.global_position = sewer.global_position
	await frames(2)
	check(await wait_for_state(SEWER_SCRIPT.State.SURFACE), "returning to the ladder exits without E and replaces the cover")
	await frames(2)
	var exited: Dictionary = sewer.get_runtime_stats()
	check(current_scene == starting_scene, "exit also keeps the same active scene")
	check(not exited.inside and not exited.interior_loaded, "sewer rendering and collision are freed after the cover closes")
	check(is_zero_approx(sewer._surface_art.open_amount), "surface cover is visibly closed at the end")
	check(sewer._surface_art.lid.position.is_zero_approx(), "3D lid returns to the shaft center")
	check(player.collision_layer == original_layer and player.collision_mask == original_mask and player.z_index == original_z, "surface collision and draw order are restored")
	check(player.visible and player.is_physics_processing() and not player.is_control_disabled, "Dante returns to ordinary street control")
	check(player.sprite_3d_display.material == original_material and player.sprite_3d_display.scale == original_scale, "exit restores the normal material and proportions")
	check(not bool(player.get_meta("harbor_interior", false)), "exit clears indoor metadata for street systems")
	check(not sewer.is_processing(), "surface idle state returns to event-only work")
	check(player.get_parent() == world and player.get_world_2d() == world.get_world_2d() and world.visible and world.process_mode == Node.PROCESS_MODE_INHERIT, "return restores player ownership, physics world and street activity")
	check(not street_audio.stream_paused and is_zero_approx(street_audio.volume_db), "return restores the street audio playback state and original volume")
	check(street_probe.is_physics_processing(), "street scripts resume their original processing flags")

	for action in ["move_left", "move_right", "move_up", "move_down", "sprint", "interact"]:
		Input.action_release(action)
	print("MANHOLE_SEWER_TEST failures=", failures)
	world.queue_free()
	await process_frame
	await process_frame
	# Let the audio mixer release the last playback block before engine shutdown.
	await create_timer(0.05).timeout
	quit(1 if not failures.is_empty() else 0)

func verify_depth(adapter: Node, label: String) -> void:
	adapter._update_scale()
	adapter.set_process(false)
	var room_model: Node2D = sewer._interior_overlay.get_node("RoomModel")
	var camera: Camera3D = room_model.camera_3d
	var view: SubViewport = room_model.view
	var anchor: Node3D = adapter.anchor
	var panel := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(4, 4, .2)
	panel.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("427766")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel.material_override = material
	view.add_child(panel)
	panel.position = anchor.position + Vector3.UP + (camera.position - anchor.position).normalized() * 1.5
	panel.look_at(camera.global_position)
	await process_frame
	await RenderingServer.frame_post_draw
	var hidden_actor: Image = view.get_texture().get_image()
	anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var hidden_empty: Image = view.get_texture().get_image()
	var pixel: Vector2 = camera.unproject_position(anchor.position + Vector3.UP * .9)
	check(changed_pixels(hidden_actor, hidden_empty, pixel) == 0, label + " is hidden by an opaque wall")
	panel.hide()
	anchor.show()
	await process_frame
	await RenderingServer.frame_post_draw
	var visible_actor: Image = view.get_texture().get_image()
	anchor.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var visible_empty: Image = view.get_texture().get_image()
	check(changed_pixels(visible_actor, visible_empty, pixel) > 100, label + " is visible on open floor")
	panel.queue_free()
	anchor.show()
	adapter.set_process(true)

func changed_pixels(a: Image, b: Image, center: Vector2) -> int:
	var changed := 0
	for y in range(maxi(0, int(center.y) - 25), mini(a.get_height(), int(center.y) + 25)):
		for x in range(maxi(0, int(center.x) - 20), mini(a.get_width(), int(center.x) + 20)):
			if a.get_pixel(x, y) != b.get_pixel(x, y): changed += 1
	return changed

func verify_combat_isolation() -> void:
	var room: Node2D = sewer._interior_overlay
	var above := CombatTarget.new()
	world.add_child(above)
	var below := CombatTarget.new()
	room.add_child(below)
	above.global_position = player.global_position + Vector2(65, 0)
	below.global_position = above.global_position
	await physics_frame
	await physics_frame
	var wanted := root.get_node("WantedManager")
	var points: int = wanted.crime_points
	player.weapon_inventory["pistol"] = true
	player.weapon_ammo["pistol"] = {"clip": 10, "reserve": 30}
	player.equip_weapon("pistol")
	check(player.active_weapon_id == "pistol", "firearm fixture equips an owned pistol")
	player._shoot_towards(below.global_position)
	var shots := room.find_children("*", "Area2D", true, false).filter(func(node): return node.has_signal("impact_resolved"))
	check(not shots.is_empty() and shots[-1].get_world_2d() == below.get_world_2d(), "native firearm creates its projectile in the sewer World2D")
	await create_timer(0.15).timeout
	check(below.health < 1000 and above.health == 1000, "bullet hits underground target, not the street target at identical coordinates")
	check(above.heard == 0, "street pedestrian cannot hear underground gunfire")
	check(room.has_node("CombatImpactAudio") and not world.has_node("CombatImpactAudio"), "bullet impact audio belongs to the isolated room")
	var before_blast := below.health
	var rocket := preload("res://guns/Bullet.tscn").instantiate()
	room.add_child(rocket)
	rocket.owner_body = player
	rocket.damage = 80
	rocket._trigger_explosion(below.global_position)
	rocket.queue_free()
	check(below.health < before_blast and above.health == 1000, "explosion group damage cannot cross physics worlds")
	player.global_position += Vector2(30, 0)
	player.equip_weapon("fists")
	var before_melee := below.health
	player._shoot_towards(below.global_position)
	check(below.health < before_melee and above.health == 1000, "native melee cone cannot hit a street target")
	# Let the real blast/melee impulse finish before placing the grenade target;
	# otherwise it can be pushed behind the canal's protective wall mid-throw.
	await create_timer(.8).timeout
	player.global_position = sewer.global_position + Vector2(-40, 40)
	below.global_position = sewer.global_position + Vector2(70, 40)
	above.global_position = below.global_position
	player.weapon_inventory["grenade"] = true
	player.weapon_ammo["grenade"] = {"clip": 2, "reserve": 2}
	player.equip_weapon("grenade")
	var before_grenade := below.health
	player._shoot_towards(below.global_position)
	await create_timer(preload("res://scripts/player/MeshyMeleePose.gd").GRENADE_RELEASE + .05).timeout
	var grenades := room.find_children("*", "CharacterBody2D", true, false).filter(func(body): return body is GrenadeProjectile)
	check(grenades.size() == 1 and grenades[0].get_world_2d() == below.get_world_2d(), "native grenade is created in the isolated physics space")
	await create_timer(1.65).timeout
	await create_timer(.7).timeout
	check(below.health < before_grenade and above.health == 1000, "grenade blast is local to the sewer")
	wanted.report_crime(30)
	check(wanted.crime_points == points, "underground activity does not increase surface wanted level")
	# The combat fixture teleports through the ladder radius. Resume its walk
	# probe from a fresh interior visit rather than triggering a false exit.
	sewer._exit_armed = false
	player.global_position = sewer.global_position
	above.queue_free()
	below.queue_free()
	await process_frame
