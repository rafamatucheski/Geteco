extends SceneTree
const GRID := preload("res://systems/inventory/GridInventory.gd")
var world
var failures: Array[String]=[]
var checks:=0
var out:="res://evidence/inventory-grid-20260928/review"
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1; print("FIELD ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label); push_error(label)
func frames(n:=4) -> void:
	for i in n: await physics_frame
func shot(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out+"/"+name+".png")
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	world=load("res://Main.tscn").instantiate(); world.set_meta("skip_arrival",true); root.add_child(world); current_scene=world
	for i in 2400:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	check(world.session!=null and world.session.ready_for_play,"real session ready")
	if not failures.is_empty(): quit(1); return
	var session=world.session
	var field=session.field_inventory
	var economy=session.state.economy
	check(field!=null and economy.grid_enabled(),"spatial inventory installed in Main")
	check(economy.grid_snapshot().bag=="" and GRID.dimensions(economy.grid_snapshot(),"pockets")==Vector2i(2,1),"new game starts with two pockets only")
	check(field.sources.all(func(row): return row.item not in ["backpack","handbag"]),"no free bags scattered around shops")
	check(not session.personal_car.discover_backpack(),"backpack unavailable before earning Monaliza")
	var campaign_data: Dictionary = session.state.campaign.snapshot()
	var first_mission: Dictionary = preload("res://data/campaign/HarborMissions.gd").MISSIONS.primeiro_giro
	campaign_data.completed.append("primeiro_giro")
	campaign_data.pending_rewards.primeiro_giro = first_mission.reward
	for flag in first_mission.sets_flags: campaign_data.flags[flag] = true
	check(session.state.campaign.restore_snapshot(campaign_data),"earned-car fixture has valid completed first mission")
	var initial = world.driving.car
	initial.collision_layer=0; initial.collision_mask=0; initial.set_physics_process(false); initial.hide()
	var personal = world.production.spawn_vehicle("monaliza",initial.position,initial.rotation.y)
	check(personal!=null,"real Monaliza spawned for discovery")
	if personal==null: world.free(); quit(1); return
	personal.set_meta("garage_reward",true)
	personal.vehicle_id="personal_monaliza"; personal.controlled=false; personal.external_input=false; personal.speed=0
	session.garage_rewards.cars.personal_monaliza=personal
	session.garage_rewards.data.vehicles.personal_monaliza=session.garage_rewards._initial_record("monaliza",personal.position,personal.rotation.y,"")
	world.player.teleport(personal.global_position+Vector3(12,.05,0)); await frames()
	check(not session.personal_car.discover_backpack(),"remote backpack discovery rejected")
	world.player.teleport(session.personal_car._rear()+Vector3(0,.05,.8)); await frames()
	check(session.personal_car.perform("trunk"),"opening real Monaliza trunk discovers backpack")
	check(economy.grid_snapshot().bag=="backpack","Monaliza equips the first backpack")
	check(not session.personal_car.discover_backpack(),"Monaliza discovery is one-time")
	var discovery_save=preload("res://runtime/GameState.gd").new()
	check(discovery_save.restore_snapshot(JSON.parse_string(JSON.stringify(session.state.snapshot()))) and "monaliza_backpack" in discovery_save.economy.grid_snapshot().claimed,"discovery receipt survives save/load")
	field.close()
	var source: Dictionary=field.sources[0]
	world.player.teleport(source.point+Vector3(0,.1,.7)); world.production.region.set_focus(world.player.position)
	await frames(90)
	field._refresh_world()
	check(field.pickups.has(source.key),"authored food supply remains available")
	var supply: Node3D = field.pickups[source.key].node
	var original_angle: float = supply.art.rotation.y
	var anchor: Vector3 = supply.global_position
	await frames(12)
	check(not is_equal_approx(supply.art.rotation.y,original_angle) and supply.global_position==anchor,"pickup art rotates without moving the physical ground anchor")
	check(field.perform(source.key),"world interaction collects supply")
	check(supply.consumed and not field.pickups.has(source.key),"successful pickup starts absorption and removes interaction immediately")
	check(field.pickup_voice.stream!=null and field.pickup_voice.playing,"successful pickup plays the original V1 reward audio")
	check(not field.perform(source.key),"pickup cannot be collected twice during absorption")
	await create_timer(.35).timeout
	check(not is_instance_valid(supply),"absorption releases its visual after the V1 quarter-second tail")
	check(economy.grid_snapshot().bag=="backpack","food pickup preserves discovered backpack")
	check(not economy.grid_equip_bag("handbag"),"handbag cannot replace backpack silently")
	economy.grant_weapon("pistol"); economy.grant_weapon("hunting_rifle")
	economy.add_ammo("pistol",126); economy.grant_item("apple",3); economy.grant_item("water"); economy.grant_item("garage_part")
	check(economy.grid_store_weapon("hunting_rifle","storage"),"long gun stows in actual bag grid")
	session.show_inventory(); await frames(8)
	for i in economy.grid_snapshot().storage.size():
		if economy.grid_snapshot().storage[i].id=="weapon:hunting_rifle": field.ui._select("storage",i)
	await frames()
	check(field.ui.visible and session.modal and world.player.input_locked and not paused,"compact UI locks player and leaves world running")
	check(field.ui.card.size.x<root.size.x*.7,"inventory does not occupy full screen")
	check(field.ui.card.position.y>=0 and field.ui.card.get_rect().end.y<=root.size.y,"selected item actions remain inside viewport")
	await shot("backpack")
	field.ui.trunk_visible=true; field.ui.refresh(); await frames()
	check(not field.trunk_access(),"Monaliza inaccessible remotely")
	var before: Dictionary=economy.snapshot()
	check(not field.move("storage",0,"trunk") and economy.snapshot()==before,"remote transfer rejected without mutation")
	await shot("remote-trunk")
	world.gameplay.health=70
	var food_index:=-1
	var food_container:=""
	for container in ["pockets","storage"]:
		for i in economy.grid_snapshot()[container].size():
			if economy.grid_snapshot()[container][i].id=="apple": food_index=i; food_container=container
	check(food_index>=0 and field.consume(food_container,food_index),"food consumption applies real healing")
	check(world.gameplay.health==78,"apple restores eight life")
	field.close(); await frames()
	check(not field.ui.visible and not session.modal and not world.player.input_locked,"close restores gameplay")
	var content: Array=economy.grid_snapshot().storage
	check(field.drop_bag(),"drop finds collision-free ground")
	check(not session.personal_car.discover_backpack(),"dropping backpack cannot duplicate discovery")
	await frames()
	var drop: Dictionary=economy.grid_snapshot().ground.back()
	check(drop.entries==content and economy.grid_snapshot().storage.is_empty(),"drop preserves spatial contents")
	var restored=preload("res://runtime/GameState.gd").new()
	var restored_ok: bool = restored.restore_snapshot(JSON.parse_string(JSON.stringify(session.state.snapshot())))
	check(restored_ok,"whole GameState restores dropped bag")
	if not restored_ok: world.free(); quit(1); return
	var restored_drop: Dictionary=restored.economy.grid_snapshot().ground.back()
	var restored_point:=Vector3(restored_drop.position[0],restored_drop.position[1],restored_drop.position[2])
	var saved_point:=Vector3(drop.position[0],drop.position[1],drop.position[2])
	check(restored_drop.entries==drop.entries and restored_point.is_equal_approx(saved_point),"ground position/content survive GameState load")
	await shot("dropped")
	var key:="drop_"+str(drop.uid)
	var dropped_node: Node3D=field.pickups[key].node
	check(dropped_node.has_node("PickupBody/CollisionShape3D"),"dropped bag has a solid collision body")
	await physics_frame
	var collision_ray:=PhysicsRayQueryParameters3D.create(dropped_node.global_position+Vector3(-1,.3,0),dropped_node.global_position+Vector3(1,.3,0),1)
	var collision_hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(collision_ray)
	check(collision_hit.get("collider")==dropped_node.get_node("PickupBody"),"physical query hits dropped bag instead of passing through")
	world.player.teleport(dropped_node.global_position+Vector3(0,.01,.9)); await frames()
	check(field.perform(key),"recover dropped bag by physical interaction")
	check(economy.grid_snapshot().storage==content and economy.grid_snapshot().ground.is_empty(),"recover exactly once")
	# Physical trunk access uses the real vehicle rear and occlusion query.
	var car=session.personal_car._car()
	car.vehicle_id="personal_monaliza"; car.controlled=false; car.external_input=false; car.speed=0
	session.garage_rewards.cars.personal_monaliza=car
	session.garage_rewards.data.vehicles.personal_monaliza=session.garage_rewards._initial_record("monaliza",car.position,car.rotation.y,"")
	world.player.teleport(session.personal_car._rear()+Vector3(0,.05,.8)); await frames()
	check(field.trunk_access(),"real parked Monaliza rear admits transfer")
	field.open(true); await frames()
	var weapon_index:=-1
	var rejected_index:=-1
	for i in economy.grid_snapshot().storage.size():
		var id:=str(economy.grid_snapshot().storage[i].id)
		if id=="weapon:hunting_rifle": weapon_index=i
		elif not GRID.accepts("trunk",id): rejected_index=i
	before=economy.snapshot()
	check(rejected_index>=0 and not field.move("storage",rejected_index,"trunk") and economy.snapshot()==before,"physical trunk rejects non-weapon items without mutation")
	check(weapon_index>=0 and field.move("storage",weapon_index,"trunk"),"near trunk weapon transfer succeeds")
	check(not economy.grid_snapshot().trunk.is_empty(),"item stored in trunk")
	await shot("at-trunk")
	world.player.teleport(world.player.position+Vector3(12,0,0)); await frames()
	before=economy.snapshot()
	check(not field.move("trunk",0,"storage") and economy.snapshot()==before,"stale open trunk cannot transfer after moving away")
	field.close()
	# Exercise the actual visible button and keyboard route, not only the adapter.
	session.show_inventory(); await frames()
	check(field.ui.drop_button!=null and field.ui.drop_button.visible,"drop control discoverable in actual HUD")
	field.ui.drop_button.pressed.emit(); await frames()
	check(economy.grid_snapshot().bag=="" and not session.modal,"HUD drop button closes inventory and leaves bag in world")
	var last_drop: Dictionary=economy.grid_snapshot().ground.back()
	var drop_key:="drop_"+str(last_drop.uid)
	world.player.teleport(field.pickups[drop_key].node.global_position+Vector3(0,.01,.9)); await frames()
	check(field.perform(drop_key),"bag dropped through UI can be recovered")
	check(await session.enter_place("maciota",false,"maciota"),"garage available")
	check(not session.state.equip_weapon("pistol") and not world.gameplay.fire_at(world.player.position+Vector3.FORWARD*3),"inventory integration preserves garage weapon ban")
	var protected_actors: Array=[world.maciota_place.maciota,world.maciota_place.mechanic]
	var protected_ok:=protected_actors.size()==2
	for actor in protected_actors:
		protected_ok=protected_ok and is_instance_valid(actor) and not actor.has_method("damage") and not actor.has_method("take_damage")
	check(protected_ok,"garage residents remain without damage routines")
	world.free(); await process_frame
	print("FIELD_RESULT checks=",checks," failures=",failures.size())
	quit(1 if not failures.is_empty() else 0)
