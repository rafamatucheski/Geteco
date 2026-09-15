extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok: failures.append(label)
class EntranceRegistry extends Node2D:
	var door: BuildingEntrance
	var return_position: Vector2
	func register_exterior_entrance(value: BuildingEntrance,_id: StringName,point: Vector2) -> void:
		door = value
		return_position = point
func _run() -> void:
	root.size = Vector2i(1280,720)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player := preload("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	var collision := CollisionShape2D.new()
	collision.name = "Collision"
	collision.shape = CircleShape2D.new()
	collision.shape.radius = 5
	player.add_child(collision)
	player.collision_layer = 4
	player.collision_mask = 1
	world.add_child(player)
	player.set_physics_process(false)
	var plane := preload("res://world/mountain_pass/MountainCargoPlane.gd").new()
	world.add_child(plane)
	player.position = plane.project_floor(Vector2(0,10.5))
	for frame in 120:
		await physics_frame
		player.velocity = Vector2(0,-80)
		player.move_and_slide()
	check(plane.contains_actor(player),"ramp permits continuous entry without relocation")
	check(plane.unproject_floor(player.global_position).y<1,"cargo aisle can be walked through")
	for frame in 70:
		await physics_frame
		player.velocity = Vector2(80,0)
		player.move_and_slide()
	check(plane.unproject_floor(player.global_position).x<1.5,"fuselage wall blocks lateral escape")
	var treasure_approach := plane.project_floor(Vector2(0.1,-6.4))
	for frame in 140:
		await physics_frame
		if player.position.distance_to(treasure_approach)<2.0: break
		player.velocity = player.position.direction_to(treasure_approach)*80
		player.move_and_slide()
	check(player.position.distance_to(treasure_approach)<4.0,"walk from ramp through both cargo rows to treasure")
	player.velocity = Vector2.ZERO
	plane._process(0.2)
	check(plane.inside and player.get_meta("mountain_shelter",false),"plane enables cutaway and shelter")
	check(not plane.model.cutaway_roof.visible,"roof hidden inside")
	var before: int = player.money
	check(plane.claim_treasure(player),"treasure reachable from cargo aisle")
	check(player.money==before+1800,"treasure awards actual cash")
	check(not plane.claim_treasure(player) and player.money==before+1800,"treasure cannot be claimed twice")
	var serialized: Dictionary = JSON.parse_string(JSON.stringify(player.serialize()))
	player.world_pickups_collected.clear()
	player.restore(serialized)
	check(player.world_pickups_collected.has(plane.PICKUP_ID),"treasure marker survives player save serialization and restore")
	var restored := preload("res://world/mountain_pass/MountainCargoPlane.gd").new()
	restored.position = Vector2(1000,0)
	world.add_child(restored)
	restored._process(0.2)
	check(restored.collected,"recreated plane reads saved pickup id")
	restored.queue_free()
	player.position = plane.project_floor(Vector2(0,11))
	plane._process(0.2)
	check(not plane.inside and not player.has_meta("mountain_shelter"),"exiting restores exterior shelter state")
	check(not camera.has_meta("mountain_zoom"),"exiting restores camera metadata")
	var facade := preload("res://world/mountain_pass/MountainGunShopFacade.gd").new()
	facade.position = Vector2(900,0)
	world.add_child(facade)
	var registry := EntranceRegistry.new()
	world.add_child(registry)
	facade.install_entrance(registry)
	check(registry.door!=null and registry.door.destination_id==&"ammunation","3D entrance preserves shop destination")
	var shop := preload("res://world/mountain_pass/MountainGunShopInterior.gd").new()
	shop.position = Vector2(1800,0)
	world.add_child(shop)
	shop.set_npc_rendering_active(true)
	player.position = shop.position+shop.project_floor(Vector2(-1.2,1.4))
	shop.is_near_counter = true
	player.money = 10000
	player.weapon_inventory.erase("shotgun")
	shop._buy_weapon("shotgun")
	check(player.weapon_inventory.get("shotgun",false),"shop purchases through existing player inventory")
	var reserve: int = player.weapon_ammo.shotgun.reserve
	shop._buy_ammo()
	check(player.weapon_ammo.shotgun.reserve>reserve,"shop purchases real ammunition")
	check(shop.gunsmith_npc.model_root.get_parent()==shop.room_view.model,"Vance renders in the same 3D room")
	if DisplayServer.get_name()!="headless":
		if player.weapon_wheel: player.weapon_wheel.hide()
		player.show()
		player.position = plane.project_floor(Vector2(0,10.5))
		plane.set_process(false)
		var review := Camera2D.new()
		world.add_child(review)
		review.zoom = Vector2.ONE*1.7
		review.position = Vector2(0,-50)
		review.make_current()
		for frame in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/mountain-plane-exterior-review.png")
		player.position = plane.project_floor(Vector2(0.15,-1.0))
		plane._set_inside(player,true)
		review.position = Vector2(0,-25)
		review.zoom = Vector2.ONE*2.5
		for frame in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/mountain-plane-cutaway-review.png")
		plane._set_inside(player,false)
		player.position = shop.position+shop.project_floor(Vector2(-1.2,1.8))
		var actor_scale := preload("res://world/mountain_pass/MountainInteriorActorScale.gd").new()
		world.add_child(actor_scale)
		actor_scale.configure(player,shop.camera_3d,shop.sprite_3d)
		review.position = shop.position+Vector2(0,-50)
		review.zoom = Vector2.ONE*1.5
		for frame in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/mountain-gunshop-interior-review.png")
		actor_scale.restore()
		actor_scale.queue_free()
		player.position = facade.position+facade.project_floor(Vector2(0,4.0))
		review.position = facade.position+Vector2(0,-45)
		review.zoom = Vector2.ONE*2.6
		for frame in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/mountain-gunshop-exterior-review.png")
	print("MOUNTAIN PLANE SHOP FAILURES: ",failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
