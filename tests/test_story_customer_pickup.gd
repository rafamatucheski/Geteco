extends SceneTree
## Bounded delivery lifecycle regression. Travel and prior recovery are fixtures;
## the existing first-favors integration proves that transportation separately.
var failures: Array[String] = []
var checks := 0
var bridge: Node
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("CUSTOMER_PICKUP ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func frames(count := 4) -> void:
	for i in count: await physics_frame
func dismiss() -> void:
	for i in 20:
		if bridge._dialog.visible: bridge._next_message()
		else: break
func run() -> void:
	create_timer(100,true,false,true).timeout.connect(func(): printerr("CUSTOMER_PICKUP_TIMEOUT"); quit(2))
	var state := root.get_node("CampaignState")
	state.reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	for flag in ["harbor_arrival_seen","harbor_arrival_call_complete","harbor_maciota_met","harbor_delivery_complete"]: state.set_campaign_flag(StringName(flag),true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null: await process_frame
	var world: Node2D = current_scene
	while not world.gameplay_ready: await process_frame
	await frames(10)
	var player: Node2D = world.get_node("Player")
	bridge = world.get_node("CobraCampaign")
	player.global_position = bridge.runtime.WORKSHOP+Vector2(0,40)
	check(bridge.runtime.start_mission("cobra_contact"), "real contact starts")
	dismiss()
	check(bridge.runtime.interact(), "real Ferrugem authorizes customer car")
	dismiss()
	var recovery: RefCounted = bridge.runtime._story_tow
	var service: Node = recovery.service
	var yard: Node2D = recovery.yard
	var target: Node2D = recovery.vehicle
	var truck: Node2D = service.truck
	if not is_instance_valid(target): quit(1); return
	# Explicit stage-three fixture: only receipt and subsequent bay reuse are tested.
	target.global_position = yard.to_global(yard.dock)
	target.velocity = Vector2.ZERO
	recovery._loaded_once = true
	bridge.runtime._set_stage(3)
	player.global_position = yard.npc.global_position+Vector2(0,40)
	var money: int = player.money
	check(bridge.runtime.interact(), "Neco receives and schedules customer collection")
	dismiss()
	service.set_process(false) # Isolate each guard before testing automatic pickup.
	check(service._customer_pickups.has(target) and not service.can_tow(target) and not yard.eligible(target), "received customer car stays protected from towing and press")
	service._collect_customer_repairs()
	check(not target.is_queued_for_deletion(), "customer car stays while player is near")
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = target.global_position
	camera.reset_physics_interpolation()
	camera.reset_smoothing()
	camera.make_current()
	camera.force_update_scroll()
	player.global_position = bridge.runtime.WORKSHOP+Vector2(0,40)
	await frames()
	check(root.get_camera_2d() == camera and camera.get_screen_center_position().distance_to(target.global_position) < 5, "camera fixture really witnesses customer car")
	service._collect_customer_repairs()
	check(not target.is_queued_for_deletion(), "customer car stays while visible even with distant player")
	check(bridge.runtime.interact(), "Ferrugem completes contact before asynchronous customer collection")
	dismiss()
	check(service._customer_pickups.has(target) and bridge.runtime.active_id.is_empty(), "customer handover survives mission cleanup")
	check(player.money == money+120, "completion grants only existing contact reward")
	camera.global_position = player.global_position
	camera.reset_physics_interpolation()
	camera.reset_smoothing()
	camera.force_update_scroll()
	await frames()
	target.is_driven_by_player = true
	service._collect_customer_repairs()
	check(not target.is_queued_for_deletion(), "occupied customer car is never removed")
	target.is_driven_by_player = false
	target.set_meta("vehicle_boarding", true)
	service._collect_customer_repairs()
	check(not target.is_queued_for_deletion(), "boarding blocks customer collection")
	target.remove_meta("vehicle_boarding")
	target.set_meta("tow_carried", true)
	service._collect_customer_repairs()
	check(not target.is_queued_for_deletion(), "loaded customer car is never removed")
	target.remove_meta("tow_carried")
	service.set_process(true)
	await create_timer(.7).timeout
	check(not is_instance_valid(target) and service._customer_pickups.is_empty(), "normal service processing collects unwitnessed empty car after mission completion")
	check(player.money == money+120, "customer pickup grants no sale or salvage reward")
	service._offer = service.choose_target(preload("res://world/shared/salvage/TowJobs.gd").next_job(yard.ledger().data))
	service.accept_job()
	var next_car: Node2D = yard._target
	check(is_instance_valid(next_car) and not yard.ledger().data.contract.is_empty(), "next normal tow service accepts another car")
	if is_instance_valid(next_car):
		truck.global_position = yard.to_global(Vector2(170,440))
		truck.global_rotation = 0
		truck.velocity = Vector2.ZERO
		next_car.global_position = truck.to_global(Vector2(-115,0))
		next_car.global_rotation = 0
		next_car.velocity = Vector2.ZERO
		await frames()
		check(service.attach(next_car), "next service uses real collision-checked winch")
		truck.global_position = yard.to_global(yard.dock)+Vector2(112,0)
		await frames()
		check(service._clear_at(yard.to_global(yard.dock)), "previous customer car no longer blocks delivery bay")
		check(service.unload() and next_car.global_position.distance_to(yard.to_global(yard.dock)) < 1, "next service unloads physically into freed bay")
	print("CUSTOMER_PICKUP_RESULT checks=",checks," failures=",failures)
	world.queue_free()
	await frames()
	quit(0 if failures.is_empty() else 1)
