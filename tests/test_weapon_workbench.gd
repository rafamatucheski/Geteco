extends SceneTree
const CUSTOM = preload("res://guns/WeaponCustomization.gd")
var failures := 0
var checks := 0
var output := OS.get_temp_dir().path_join("geteco-workbench")
class Witness extends Node2D:
	var alerts := 0
	func hear_gunfire(_origin: Vector2,_end: Vector2) -> void: alerts += 1
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	print(("PASS " if value else "FAIL ")+message)
	if not value: failures += 1
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): output = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,720)
	root.get_node("SaveManager")._save_dir = output.path_join("saves")+"/"
	root.get_node("SaveManager").clear_pending_save()
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player = load("res://characters/Player.gd").new()
	var camera := preload("res://systems/DynamicCamera.gd").new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	player.personal_loadout_enabled = false
	player.money = 100000
	for id in CUSTOM.CUSTOMIZABLE:
		player.weapon_inventory[id] = true
		check(player.customize_weapon_part(id,"finish","olive") == "PERSONALIZAÇÃO APLICADA", "Finish available: "+id)
	for id in ["rpg","grenade","fists"]:
		player.weapon_inventory[id] = true
		check(player.customize_weapon_part(id,"finish","chrome") == "ARMA INCOMPATÍVEL" and not player.weapon_customization.has(id), "Excluded: "+id)
	check(player.customize_weapon_part("knife","laser","laser_red") == "ARMA INCOMPATÍVEL", "Melee only accepts appropriate parts")
	check(player.customize_weapon_part("magnum","muzzle","suppressor") == "ARMA INCOMPATÍVEL", "Revolver cannot mount a suppressor")
	check(player.customize_weapon_part("pistol","finish","scope_2x") == "ARMA INCOMPATÍVEL", "Wrong slot cannot install or charge")
	player.equip_weapon("pistol")
	player.weapon_ammo.pistol = {"clip":5,"reserve":40}
	player.customize_weapon_part("pistol","magazine","extended")
	check(player.get_weapon_data("pistol").magazine_size == 18 and player.weapon_ammo.pistol.clip == 5, "Larger magazine does not grant ammunition")
	var reload_base := preload("res://guns/combat/WeaponReload.gd").duration("pistol")
	player._reload_active_weapon()
	check(player._reload_duration > reload_base, "Extended magazine has slower reload")
	await player.reload_finished
	check(player.weapon_ammo.pistol == {"clip":18,"reserve":27}, "Reload fills the installed magazine using reserve")
	player.customize_weapon_part("pistol","magazine","none")
	check(player.weapon_ammo.pistol == {"clip":12,"reserve":33}, "Removing magazine conserves all rounds")
	var money: int = player.money
	player.customize_weapon_part("pistol","magazine","extended")
	check(player.money == money, "Previously purchased part reinstalls free")
	player.customize_weapon_part("pistol","muzzle","suppressor")
	player.customize_weapon_part("pistol","laser","laser_green")
	check(player.current_gun_mesh.has_node("Suppressor") and player.current_gun_mesh.has_node("LaserModule"), "Equipped model includes combined accessories")
	player.model_root.rotation.y = -PI*.5
	player._shoot_towards(Vector2(600,0))
	var projectile: Node2D
	for child in world.get_children():
		if child.get_script() == load("res://guns/Bullet.gd"): projectile = child
	check(projectile != null and projectile.get_meta("gunfire_hearing_radius") == 80.0, "Actual shot carries suppressed hearing radius")
	check(not player.muzzle_light_3d.visible, "Suppressor reduces muzzle flash lighting")
	var witness := Witness.new()
	witness.position = Vector2(0,160)
	witness.add_to_group("pedestrian")
	world.add_child(witness)
	player.set_meta("civilian_alert_after",0)
	preload("res://characters/PedestrianDanger.gd").report(projectile,Vector2.ZERO,Vector2.RIGHT,player)
	check(witness.alerts == 0, "Suppressed shot does not alert distant off-axis witness")
	projectile.set_meta("gunfire_hearing_radius",240.0)
	player.set_meta("civilian_alert_after",0)
	preload("res://characters/PedestrianDanger.gd").report(projectile,Vector2.ZERO,Vector2.RIGHT,player)
	check(witness.alerts == 1, "Same witness hears unsuppressed shot")
	projectile.queue_free()
	var wall := StaticBody2D.new()
	wall.position = Vector2(90,0)
	var collider := CollisionShape2D.new()
	collider.shape = RectangleShape2D.new()
	collider.shape.size = Vector2(8,200)
	wall.add_child(collider)
	world.add_child(wall)
	root.get_node("GameInput").touch_aim = Vector2.RIGHT
	Input.action_press("aim")
	await physics_frame
	await physics_frame
	player.weapon_laser._physics_process(0)
	check(player.weapon_laser.visible and player.weapon_laser.contact and player.weapon_laser.to_global(player.weapon_laser.endpoint).x < 91, "Laser stops at real collider")
	Input.action_release("aim")
	player.weapon_laser._physics_process(0)
	check(not player.weapon_laser.visible, "Laser hidden when not aiming")
	player.customize_weapon_part("hunting_rifle","scope","scope_2x")
	player.equip_weapon("hunting_rifle")
	Input.action_press("aim")
	check(player.weapon_scope_active(), "Rifle scope activates only while aiming")
	camera.make_current()
	camera._process(3.0)
	check(is_equal_approx(camera.zoom.x,camera.zoom_close*2.0) and camera.position.length()>100, "Scope doubles actual camera zoom and leads toward aim")
	player.set_meta("isolated_interior",true)
	check(not player.weapon_scope_active(), "Scope respects interior camera boundary")
	player.remove_meta("isolated_interior")
	Input.action_release("aim")
	camera._process(3.0)
	check(absf(camera.zoom.x-camera.zoom_close)<.001, "Releasing aim restores camera zoom")
	player.customize_weapon_part("smg","grip","vertical_grip")
	player.customize_weapon_part("smg","stock","stabilized_stock")
	check(player.get_weapon_data("smg").recoil_multiplier < .75, "Grip and stock combine recoil reduction")
	var room = load("res://world/harbor/interiors/HarborAmmunationInterior.gd").new()
	room.position = Vector2(3000,3000)
	world.add_child(room)
	player.global_position = room.spawn_point.global_position
	room.open_catalog()
	room.selection = room.stock.find("pistol")
	room.change_selection(0)
	room._open_workbench()
	var bench = room.workbench
	check(bench.visible and not room.panel.visible and room.preview.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Workbench suspends catalog preview")
	bench.select_slot("finish")
	var before: Dictionary = player.weapon_customization.duplicate(true)
	money = player.money
	bench.select_candidate("sand")
	check(player.weapon_customization == before and player.money == money, "Preview never charges or changes equipment")
	await capture("workbench-preview")
	bench.apply_selection()
	check(CUSTOM.selected(player.weapon_customization,"pistol","finish") == "sand" and player.money == money-200, "Apply purchases the previewed finish")
	if DisplayServer.get_name() != "headless":
		for id in ["magnum", "shotgun", "ak47", "hunting_rifle", "flamethrower", "knife"]:
			for part in ["flashlight", "laser_green", "suppressor", "extended", "vertical_grip", "stabilized_stock", "scope_2x"]:
				if CUSTOM.supports(id,part): player.customize_weapon_part(id,CUSTOM.PARTS[part].slot,part)
			bench.open(player,id)
			await capture("workbench-"+id)
	bench.close()
	check(room.panel.visible and not bench.visible and bench.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Back restores catalog and sleeps workbench viewport")
	room.close_catalog()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(player.serialize()))
	player.weapon_customization.clear()
	player.restore(saved)
	check(CUSTOM.selected(player.weapon_customization,"pistol","finish") == "sand" and CUSTOM.selected(player.weapon_customization,"hunting_rifle","scope") == "scope_2x", "Combined customizations survive JSON save round-trip")
	check(CUSTOM.owns(player.weapon_customization,"pistol","extended"), "Purchased removed parts survive save")
	print("WEAPON WORKBENCH: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
